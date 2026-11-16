import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:myvidhub/features/player/inline_hdr_backend.dart';
import 'package:myvidhub/services/source_registry.dart';

class FakeMpv extends PlatformPlayer {
  FakeMpv() : super(configuration: const PlayerConfiguration()) {
    state = const PlayerState(
      playing: true,
      position: Duration(seconds: 42),
      duration: Duration(minutes: 10),
      volume: 70,
      rate: 1.25,
    );
  }

  Completer<void>? pauseGate;
  int pauses = 0;
  int plays = 0;
  Duration? seeked;

  @override
  Future<void> pause() async {
    pauses++;
    await pauseGate?.future;
    state = state.copyWith(playing: false);
  }

  @override
  Future<void> play() async {
    plays++;
    state = state.copyWith(playing: true);
  }

  @override
  Future<void> seek(Duration duration) async {
    seeked = duration;
    state = state.copyWith(position: duration);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('myvidhub/hdr_player');
  const events = EventChannel('myvidhub/inline_hdr_events');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('切换内核后仍通过同一播放器控制并读取原生进度和音轨', () async {
    final calls = <MethodCall>[];
    late MockStreamHandlerEventSink eventSink;
    messenger.setMockStreamHandler(events, MockStreamHandler.inline(onListen: (_, sink) => eventSink = sink));
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final fake = FakeMpv();
    var changes = 0;
    final backend = InlineHdrBackend(Player(platformPlayer: fake), onModeChanged: () => changes++);
    final player = Player(platformPlayer: backend);

    await backend.activate(const PlayTarget('/movie.mkv'), ['/movie.srt'], const Duration(seconds: 42));
    expect(backend.active, isTrue);
    expect(fake.pauses, 1);
    expect(calls.first.method, 'inlineOpen');
    expect(calls.first.arguments['position'], 42000);
    expect(calls.first.arguments['playing'], isTrue);
    expect(calls.first.arguments['rate'], 1.25);

    eventSink.success({
      'playing': true,
      'position': 48000,
      'duration': 600000,
      'buffer': 50000,
      'buffering': false,
      'completed': false,
      'volume': 70.0,
      'rate': 1.25,
      'tracks': [
        {'id': '0:0', 'type': 'audio', 'language': 'ja', 'selected': true},
        {'id': '1:0', 'type': 'subtitle', 'language': 'zh', 'selected': true},
      ],
    });
    await Future<void>.delayed(Duration.zero);
    expect(player.state.position, const Duration(seconds: 48));
    expect(player.state.track.audio.id, '0:0');
    expect(player.state.track.subtitle.id, '1:0');
    await player.seek(const Duration(seconds: 60));
    await player.setSubtitleTrack(SubtitleTrack.no());
    expect(calls.map((call) => call.method), containsAll(['inlineSeek', 'inlineTrack']));
    await backend.closeHdr();
    expect(backend.active, isFalse);
    expect(changes, 2);
    expect(calls.last.method, 'inlineClose');
    await player.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('切集时取消尚未完成的旧内核切换', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final fake = FakeMpv()..pauseGate = Completer<void>();
    final backend = InlineHdrBackend(Player(platformPlayer: fake), onModeChanged: () {});
    final activation = backend.activate(const PlayTarget('/old.mkv'), [], Duration.zero);
    await backend.closeHdr();
    fake.pauseGate!.complete();
    await activation;
    expect(backend.active, isFalse);
    expect(calls, isEmpty);
    await backend.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('原生解码失败后从当前进度回退到原播放器', () async {
    late MockStreamHandlerEventSink eventSink;
    messenger.setMockStreamHandler(events, MockStreamHandler.inline(onListen: (_, sink) => eventSink = sink));
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    final fake = FakeMpv();
    final notices = <String>[];
    final backend = InlineHdrBackend(
      Player(platformPlayer: fake),
      onModeChanged: () {},
      onFallback: notices.add,
    );
    await backend.activate(const PlayTarget('/movie.mkv'), [], const Duration(seconds: 42));
    eventSink.success({'error': '设备不支持'});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(backend.active, isFalse);
    expect(fake.seeked, const Duration(seconds: 42));
    expect(fake.plays, 1);
    expect(notices.single, contains('切回普通播放'));
    await backend.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
