import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvidhub/features/player/hdr_playback.dart';
import 'package:path/path.dart' as p;

void main() {
  test('查找同名字幕及字幕目录，跳过原生播放器不支持的格式', () async {
    final dir = await Directory.systemTemp.createTemp('reelnest_hdr_');
    addTearDown(() => dir.delete(recursive: true));
    final subs = await Directory(p.join(dir.path, 'Subs')).create();
    for (final path in [
      p.join(dir.path, '电影.zh.srt'),
      p.join(dir.path, '电影.en.vtt'),
      p.join(dir.path, '电影.ass'),
      p.join(dir.path, '其他.srt'),
      p.join(subs.path, '中文.srt'),
    ]) {
      await File(path).create();
    }

    final found = await findLocalHdrSubtitles(p.join(dir.path, '电影.mkv'));
    expect(found.map(p.basename).toSet(), {'电影.zh.srt', '电影.en.vtt', '中文.srt'});
  });

  test('网络地址不当作本地目录扫描', () async {
    expect(await findLocalHdrSubtitles('https://example.com/video.mkv'), isEmpty);
  });
}
