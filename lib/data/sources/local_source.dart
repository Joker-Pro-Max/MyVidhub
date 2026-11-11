import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'media_source.dart';

class LocalSource implements MediaSource {
  LocalSource(this.rootPath);

  @override
  final String rootPath;

  @override
  Future<List<SourceEntry>> list(String path) async {
    final dir = Directory(path);
    final out = <SourceEntry>[];
    try {
      await for (final e in dir.list(followLinks: true)) {
        final name = p.basename(e.path);
        try {
          final stat = await e.stat();
          final isDir = stat.type == FileSystemEntityType.directory;
          out.add(SourceEntry(
            name: name,
            path: e.path,
            isDir: isDir,
            size: isDir ? 0 : stat.size,
            modified: stat.modified,
          ));
        } on FileSystemException {
          // 无权限 / 断开的链接：跳过
        }
      }
    } on FileSystemException {
      return const [];
    }
    return out;
  }

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  @override
  String join(String dir, String name) => p.join(dir, name);

  @override
  String? localImagePath(String path) => path;

  @override
  Future<String> playableUri(String path) async => path;
}
