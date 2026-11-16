import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../services/source_registry.dart';

/// 新片源开始播放或页面退出后，丢弃旧检测的结果。
class AutoHdrDetector {
  AutoHdrDetector({Future<bool> Function(PlayTarget)? probe}) : _probe = probe ?? _probeNative;

  final Future<bool> Function(PlayTarget) _probe;
  int _generation = 0;

  Future<bool> detect(PlayTarget target) async {
    final generation = ++_generation;
    try {
      final detected = await _probe(target);
      return detected && generation == _generation;
    } catch (_) {
      return false;
    }
  }

  void cancel() => _generation++;

  static Future<bool> _probeNative(PlayTarget target) async =>
      await const MethodChannel('myvidhub/hdr_player').invokeMethod<bool>('probe', {
        'url': target.url,
        'header': target.httpHeader,
      }) ??
      false;
}

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
