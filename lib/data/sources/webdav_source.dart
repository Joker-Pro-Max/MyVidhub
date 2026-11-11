import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'media_source.dart';
import 'network_config.dart';

/// WebDAV 媒体源：PROPFIND 列目录，GET 读文件，播放器直接用 HTTP 地址播放。
class WebDavSource implements MediaSource {
  WebDavSource({required this.sourceId, required this.config, required String root})
      : rootPath = remoteUri(sourceId, root);

  final int sourceId;
  final NetworkConfig config;

  @override
  final String rootPath;

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 15)
    // 局域网 NAS 常用自签名证书
    ..badCertificateCallback = (_, _, _) => true;

  Map<String, String> get headers => {
        'User-Agent': 'MyVidhub',
        if (config.username.isNotEmpty) 'Authorization': config.basicAuth,
      };

  String _remote(String path) => parseRemote(path)?.$2 ?? path;

  /// 远程路径 → 完整 URL（逐段编码）。
  Uri url(String path) {
    final remote = _remote(path);
    final segs = remote.split('/').where((s) => s.isNotEmpty).toList();
    final tail = remote.endsWith('/') && segs.isNotEmpty ? '/' : '';
    return Uri.parse('${config.origin}/${segs.map(Uri.encodeComponent).join('/')}$tail');
  }

  @override
  Future<List<SourceEntry>> list(String path) async {
    final remote = _remote(path);
    final dirPath = remote.endsWith('/') ? remote : '$remote/';
    final client = _client();
    try {
      final req = await client.openUrl('PROPFIND', url(dirPath));
      headers.forEach(req.headers.set);
      req.headers
        ..set('Depth', '1')
        ..contentType = ContentType('application', 'xml', charset: 'utf-8');
      req.write('<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop>'
          '<d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>');
      final res = await req.close().timeout(const Duration(seconds: 30));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401) throw const NetworkSourceException('用户名或密码不对');
      if (res.statusCode == 404) throw const NetworkSourceException('找不到这个路径');
      if (res.statusCode != 207 && res.statusCode != 200) {
        throw NetworkSourceException('服务器返回 ${res.statusCode}');
      }
      return _parse(body, dirPath);
    } on SocketException catch (e) {
      throw NetworkSourceException('无法连接 ${config.host}（${e.osError?.message ?? e.message}）');
    } on HandshakeException {
      throw const NetworkSourceException('HTTPS 握手失败，试试改用 http://');
    } on TimeoutException {
      throw const NetworkSourceException('连接超时');
    } finally {
      client.close();
    }
  }

  List<SourceEntry> _parse(String body, String dirPath) {
    final doc = XmlDocument.parse(body);
    final self = _norm(dirPath);
    final out = <SourceEntry>[];
    for (final resp in doc.descendants.whereType<XmlElement>().where((e) => e.localName == 'response')) {
      final hrefEl = resp.descendants.whereType<XmlElement>().where((e) => e.localName == 'href').firstOrNull;
      if (hrefEl == null) continue;
      final href = Uri.parse(hrefEl.innerText.trim());
      final segs = href.pathSegments.where((s) => s.isNotEmpty).toList();
      final p = '/${segs.join('/')}';
      if (_norm(p) == self || segs.isEmpty) continue;
      final isDir = resp.descendants.whereType<XmlElement>().any((e) => e.localName == 'collection') ||
          hrefEl.innerText.trim().endsWith('/');
      final sizeText = resp.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName == 'getcontentlength')
          .firstOrNull
          ?.innerText;
      final modText =
          resp.descendants.whereType<XmlElement>().where((e) => e.localName == 'getlastmodified').firstOrNull?.innerText;
      DateTime? modified;
      try {
        if (modText != null) modified = HttpDate.parse(modText.trim());
      } catch (_) {}
      out.add(SourceEntry(
        name: segs.last,
        path: remoteUri(sourceId, p),
        isDir: isDir,
        size: int.tryParse(sizeText?.trim() ?? '') ?? 0,
        modified: modified,
      ));
    }
    return out;
  }

  /// 两边都是已解码的路径，只去掉末尾的 /。
  static String _norm(String p) => p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;

  @override
  Future<Uint8List> readBytes(String path) async {
    final client = _client();
    try {
      final req = await client.getUrl(url(path));
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw NetworkSourceException('读取失败（${res.statusCode}）');
      final b = BytesBuilder(copy: false);
      await for (final c in res) {
        b.add(c);
      }
      return b.takeBytes();
    } on SocketException catch (e) {
      throw NetworkSourceException('无法连接 ${config.host}（${e.osError?.message ?? e.message}）');
    } finally {
      client.close();
    }
  }

  @override
  String join(String dir, String name) => dir.endsWith('/') ? '$dir$name' : '$dir/$name';

  @override
  String? localImagePath(String path) => path;

  @override
  Future<String> playableUri(String path) async => url(path).toString();
}

class NetworkSourceException implements Exception {
  const NetworkSourceException(this.message);
  final String message;
  @override
  String toString() => message;
}
