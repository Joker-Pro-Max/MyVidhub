import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:smb_connect/smb_connect.dart';

import 'media_source.dart';
import 'network_config.dart';
import 'webdav_source.dart' show NetworkSourceException;

/// SMB 媒体源（SMB 2.1 / 2.0 / 1）。根路径 "/" 列出共享，"/共享/目录" 列出文件。
/// 播放时由 [SourceRegistry] 的本地 HTTP 代理把播放器的 Range 请求转成 SMB 读取。
class SmbSource implements MediaSource {
  SmbSource({required this.sourceId, required this.config, required String root})
      : rootPath = remoteUri(sourceId, root);

  final int sourceId;
  final NetworkConfig config;

  @override
  final String rootPath;

  SmbConnect? _conn;
  Future<SmbConnect>? _connecting;

  Future<SmbConnect> _connect() {
    if (_conn != null) return Future.value(_conn);
    return _connecting ??= SmbConnect.connectAuth(
      host: config.host,
      domain: config.domain,
      username: config.username.isEmpty ? 'guest' : config.username,
      password: config.password,
      onDisconnect: (_) => _conn = null,
    ).then((c) {
      _conn = c;
      _connecting = null;
      return c;
    }, onError: (Object e) {
      _connecting = null;
      throw _wrap(e);
    });
  }

  /// 出错时断开重连一次（NAS 休眠、Wi-Fi 切换后连接会失效）。
  Future<T> _withConn<T>(Future<T> Function(SmbConnect c) op) async {
    try {
      return await op(await _connect());
    } catch (e) {
      if (e is NetworkSourceException) rethrow;
      try {
        await _conn?.close();
      } catch (_) {}
      _conn = null;
      try {
        return await op(await _connect());
      } catch (e2) {
        throw _wrap(e2);
      }
    }
  }

  NetworkSourceException _wrap(Object e) {
    final s = e.toString();
    if (e is SocketException) {
      return NetworkSourceException('无法连接 ${config.host}（${e.osError?.message ?? e.message}）');
    }
    if (s.contains('LOGON_FAILURE') || s.contains('ACCESS_DENIED')) {
      return const NetworkSourceException('用户名或密码不对，或没有访问权限');
    }
    if (s.contains('BAD_NETWORK_NAME')) return const NetworkSourceException('找不到这个共享文件夹');
    if (s.contains('OBJECT_NAME_NOT_FOUND') || s.contains('OBJECT_PATH_NOT_FOUND')) {
      return const NetworkSourceException('找不到这个路径');
    }
    return NetworkSourceException('SMB 错误：$s');
  }

  String _remote(String path) => parseRemote(path)?.$2 ?? path;

  @override
  Future<List<SourceEntry>> list(String path) async {
    final remote = _remote(path);
    final clean = remote.replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty) {
      final shares = await _withConn((c) => c.listShares());
      return [
        for (final s in shares)
          if (!s.name.endsWith(r'$')) // 隐藏 IPC$、ADMIN$ 等系统共享
            SourceEntry(name: s.name.replaceAll('/', ''), path: remoteUri(sourceId, '/${s.name.replaceAll('/', '')}'), isDir: true),
      ];
    }
    final files = await _withConn((c) async => c.listFiles(await c.file('$clean/')));
    return [
      for (final f in files)
        SourceEntry(
          name: f.name,
          path: remoteUri(sourceId, '$clean/${f.name}'),
          isDir: f.isDirectory(),
          size: f.size,
          modified: f.lastModified > 0 ? DateTime.fromMillisecondsSinceEpoch(f.lastModified) : null,
        ),
    ];
  }

  @override
  Future<Uint8List> readBytes(String path) => _withConn((c) async {
        final file = await c.file(_remote(path));
        final stream = await c.openRead(file);
        final b = BytesBuilder(copy: false);
        await for (final chunk in stream) {
          b.add(chunk);
        }
        return b.takeBytes();
      });

  Future<int> size(String path) => _withConn((c) async => (await c.file(_remote(path))).size);

  /// 打开随机读取（播放代理用）。
  Future<RandomAccessFile> openRandom(String path) =>
      _withConn((c) async => c.open(await c.file(_remote(path))));

  Future<void> close() async {
    try {
      await _conn?.close();
    } catch (_) {}
    _conn = null;
  }

  @override
  String join(String dir, String name) => dir.endsWith('/') ? '$dir$name' : '$dir/$name';

  @override
  String? localImagePath(String path) => path;

  /// SMB 不能直接交给播放器；地址由 SourceRegistry 的本地代理生成。
  @override
  Future<String> playableUri(String path) async => path;
}
