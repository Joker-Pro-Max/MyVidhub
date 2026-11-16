import 'dart:io';

import 'package:path/path.dart' as p;

/// Android 原生播放器支持的外挂字幕；ASS 仍由原播放器处理。
Future<List<String>> findLocalHdrSubtitles(String videoPath) async {
  if (!p.isAbsolute(videoPath)) return [];
  final video = File(videoPath);
  final base = p.basenameWithoutExtension(videoPath).toLowerCase();
  final result = <String>[];

  Future<void> scan(Directory dir, {required bool matchVideoName}) async {
    try {
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! File) continue;
        final name = p.basename(entry.path).toLowerCase();
        if (matchVideoName && !name.startsWith(base)) continue;
        if ({'.srt', '.vtt', '.ttml', '.xml'}.contains(p.extension(name))) {
          result.add(entry.path);
        }
      }
    } on FileSystemException {
      // 字幕目录不可读时仍允许播放视频。
    }
  }

  await scan(video.parent, matchVideoName: true);
  for (final name in ['Subs', 'subs', 'Subtitles', 'subtitles', 'Sub', 'sub', '字幕']) {
    await scan(Directory(p.join(video.parent.path, name)), matchVideoName: false);
  }
  return result;
}
