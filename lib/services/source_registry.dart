import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db/library_db.dart';
import '../data/sources/media_source.dart';
import '../data/sources/network_config.dart';
import '../data/sources/smb_source.dart';
import '../data/sources/source_factory.dart';
import '../data/sources/webdav_source.dart';
import '../domain/media_extensions.dart';

/// 播放器要打开的目标。
class PlayTarget {
  const PlayTarget(this.url, {this.httpHeader, this.subtitles = const []});
  final String url;

  /// 例如 "Authorization: Basic xxx"（WebDAV）。
  final String? httpHeader;

  /// 同目录的外挂字幕地址（网络源 mpv 不能自动发现）。
  final List<String> subtitles;
}

/// 主线程上的网络源管理：连接复用、远程图片磁盘缓存、播放地址解析、SMB 本地代理。
class SourceRegistry {
  SourceRegistry._();
  static final instance = SourceRegistry._();

  LibraryDb? _db;
  final _sources = <int, MediaSource>{};
  final _inflight = <String, Future<Uint8List?>>{};
  Directory? _cacheDir;
  HttpServer? _proxy;

  void attach(LibraryDb db) => _db = db;

  /// 源配置改了 / 被删了时调用。
  void forget(int id) {
    final s = _sources.remove(id);
    if (s is SmbSource) s.close();
  }

  MediaSource? source(int id) {
    final cached = _sources[id];
    if (cached != null) return cached;
    final row = _db?.source(id);
    if (row == null) return null;
    return _sources[id] = createSource(id: row.id, type: row.type, root: row.root, config: row.config);
  }

  // ------------------------------------------------------------ 图片

  Future<Directory> _cache() async {
    if (_cacheDir != null) return _cacheDir!;
    final d = Directory(p.join((await getApplicationCacheDirectory()).path, 'remote_images'));
    await d.create(recursive: true);
    return _cacheDir = d;
  }

  /// 读取远程小文件（海报、剧照），先查磁盘缓存。
  Future<Uint8List?> bytes(String uri) => _inflight.putIfAbsent(uri, () async {
        try {
          final dir = await _cache();
          final f = File(p.join(dir.path, sha1.convert(utf8.encode(uri)).toString()));
          if (f.existsSync()) return await f.readAsBytes();
          final ref = parseRemote(uri);
          final src = ref == null ? null : source(ref.$1);
          if (src == null) return null;
          final data = await src.readBytes(uri);
          await f.writeAsBytes(data, flush: false);
          return data;
        } catch (_) {
          return null;
        } finally {
          // 失败的请求允许稍后重试
          Future<void>.delayed(const Duration(seconds: 30), () => _inflight.remove(uri));
        }
      });

  // ------------------------------------------------------------ 播放

  Future<PlayTarget> playTarget(String uri) async {
    final ref = parseRemote(uri);
    if (ref == null) return PlayTarget(uri);
    final src = source(ref.$1);
    if (src == null) throw const NetworkSourceException('这个网络源已被移除');

    final subs = await _siblingSubtitles(src, uri);
    if (src is WebDavSource) {
      return PlayTarget(
        await src.playableUri(uri),
        httpHeader: src.config.username.isEmpty ? null : 'Authorization: ${src.config.basicAuth}',
        subtitles: [for (final s in subs) await src.playableUri(s)],
      );
    }
    if (src is SmbSource) {
      return PlayTarget(await _proxyUrl(uri), subtitles: [for (final s in subs) await _proxyUrl(s)]);
    }
    return PlayTarget(await src.playableUri(uri));
  }

  /// 与视频同名开头的字幕文件（同目录和 Subs 子目录）。
  Future<List<String>> _siblingSubtitles(MediaSource src, String uri) async {
    try {
      final slash = uri.lastIndexOf('/');
      final dir = uri.substring(0, slash);
      final base = baseNameOf(uri.substring(slash + 1)).toLowerCase();
      final entries = await src.list(dir);
      final out = [
        for (final e in entries)
          if (!e.isDir && subtitleExtensions.contains(extOf(e.name)) && e.name.toLowerCase().startsWith(base)) e.path,
      ];
      for (final sub in entries.where((e) => e.isDir && RegExp(r'^subs?$|^subtitles?$|^字幕$', caseSensitive: false).hasMatch(e.name))) {
        for (final e in await src.list(sub.path)) {
          if (!e.isDir && subtitleExtensions.contains(extOf(e.name))) out.add(e.path);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<String> _proxyUrl(String uri) async {
    final server = await _startProxy();
    final token = base64Url.encode(utf8.encode(uri));
    final name = Uri.encodeComponent(uri.substring(uri.lastIndexOf('/') + 1));
    return 'http://127.0.0.1:${server.port}/s/$token/$name';
  }

  /// 本地 HTTP 代理：把播放器的 Range 请求转成 SMB 随机读取。只监听本机回环地址。
  Future<HttpServer> _startProxy() async {
    if (_proxy != null) return _proxy!;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_serve);
    return _proxy = server;
  }

  Future<void> _serve(HttpRequest req) async {
    final res = req.response;
    RandomAccessFile? raf;
    try {
      final segs = req.uri.pathSegments;
      if (segs.length < 2 || segs[0] != 's') {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final uri = utf8.decode(base64Url.decode(segs[1]));
      final ref = parseRemote(uri);
      final src = ref == null ? null : source(ref.$1);
      if (src is! SmbSource) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final total = await src.size(uri);
      var start = 0;
      var end = total - 1;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final m = range == null ? null : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (m != null) {
        if (m.group(1)!.isNotEmpty) start = int.parse(m.group(1)!);
        if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
        if (m.group(1)!.isEmpty && m.group(2)!.isNotEmpty) {
          start = total - int.parse(m.group(2)!); // bytes=-N：最后 N 字节
          end = total - 1;
        }
        if (start >= total || start > end) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
          return;
        }
        end = end.clamp(start, total - 1);
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
      }
      res.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1
        ..contentType = _mime(uri);
      if (req.method == 'HEAD') return;

      raf = await src.openRandom(uri);
      await raf.setPosition(start);
      var left = end - start + 1;
      const chunk = 512 * 1024;
      while (left > 0) {
        final data = await raf.read(left < chunk ? left : chunk);
        if (data.isEmpty) break;
        res.add(data);
        left -= data.length;
        await res.flush(); // 播放器断开（拖动进度）时这里会抛异常，停止读取
      }
    } catch (_) {
      // 客户端断开或 SMB 读取失败
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
      try {
        await res.close();
      } catch (_) {}
    }
  }

  static ContentType _mime(String uri) => switch (extOf(uri)) {
        'mp4' || 'm4v' => ContentType('video', 'mp4'),
        'mkv' => ContentType('video', 'x-matroska'),
        'webm' => ContentType('video', 'webm'),
        'srt' => ContentType('text', 'plain', charset: 'utf-8'),
        'ass' || 'ssa' => ContentType('text', 'x-ssa', charset: 'utf-8'),
        _ => ContentType('application', 'octet-stream'),
      };

  /// 数据库里存的路径 → 给人看的路径。
  String displayPath(String path) {
    final ref = parseRemote(path);
    if (ref == null) return path;
    final row = _db?.source(ref.$1);
    if (row == null || row.config == null) return ref.$2;
    final c = NetworkConfig.decode(row.config!);
    return '${c.host}${ref.$2}';
  }
}
