import 'dart:typed_data';

class SourceEntry {
  const SourceEntry({
    required this.name,
    required this.path,
    required this.isDir,
    this.size = 0,
    this.modified,
  });
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime? modified;
}

/// 统一的存储源接口：本地目录 / WebDAV / SMB 都实现它。
abstract class MediaSource {
  String get rootPath;

  /// 列出目录内容（不递归）。
  Future<List<SourceEntry>> list(String path);

  /// 读取小文件（NFO、图片）。
  Future<Uint8List> readBytes(String path);

  /// 拼接子路径。
  String join(String dir, String name);

  /// 本地可直接访问的图片路径（本地源直接返回；网络源在 M4 返回缓存路径）。
  String? localImagePath(String path);

  /// 交给播放器的地址。
  Future<String> playableUri(String path);
}
