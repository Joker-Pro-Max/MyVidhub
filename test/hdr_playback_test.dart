import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myvidhub/features/player/hdr_playback.dart';
import 'package:myvidhub/services/source_registry.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('检测到杜比视界才自动切换，检测失败时保留原播放器', () async {
    const target = PlayTarget('/video.mkv');
    expect(await AutoHdrDetector(probe: (_) async => true).detect(target), isTrue);
    expect(await AutoHdrDetector(probe: (_) async => false).detect(target), isFalse);
    expect(await AutoHdrDetector(probe: (_) async => throw StateError('probe')).detect(target), isFalse);
  });

  test('切换影片或退出后，不使用旧的检测结果', () async {
    final oldResult = Completer<bool>();
    final detector = AutoHdrDetector(probe: (_) => oldResult.future);
    final result = detector.detect(const PlayTarget('/old.mkv'));
    detector.cancel();
    oldResult.complete(true);
    expect(await result, isFalse);
  });

  test('只采用最新影片的检测结果', () async {
    final first = Completer<bool>();
    final second = Completer<bool>();
    final detector = AutoHdrDetector(
      probe: (target) => target.url == '/first.mkv' ? first.future : second.future,
    );
    final oldResult = detector.detect(const PlayTarget('/first.mkv'));
    final newResult = detector.detect(const PlayTarget('/second.mkv'));
    first.complete(true);
    second.complete(true);
    expect(await oldResult, isFalse);
    expect(await newResult, isTrue);
  });

  test('原生检测传递网络地址和认证信息', () async {
    const channel = MethodChannel('myvidhub/hdr_player');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'probe');
      expect(call.arguments['url'], 'https://example.com/video.mkv');
      expect(call.arguments['header'], 'Authorization: Basic test');
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    expect(
      await AutoHdrDetector().detect(
        const PlayTarget('https://example.com/video.mkv', httpHeader: 'Authorization: Basic test'),
      ),
      isTrue,
    );
  });
}
