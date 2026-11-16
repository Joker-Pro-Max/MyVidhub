import 'dart:async';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../../services/source_registry.dart';

/// 保持现有控制栏使用的 Player 接口，在 mpv 与 Android 原生输出间切换。
class InlineHdrBackend extends PlatformPlayer {
  InlineHdrBackend(this.mpv, {required this.onModeChanged, this.onFallback})
      : super(configuration: const PlayerConfiguration()) {
    _forward(mpv.stream.playing, playingController);
    _forward(mpv.stream.position, positionController);
    _forward(mpv.stream.duration, durationController);
    _forward(mpv.stream.completed, completedController);
    _forward(mpv.stream.buffering, bufferingController);
    _forward(mpv.stream.buffer, bufferController);
    _forward(mpv.stream.volume, volumeController);
    _forward(mpv.stream.rate, rateController);
    _forward(mpv.stream.track, trackController);
    _forward(mpv.stream.tracks, tracksController);
    _forward(mpv.stream.videoParams, videoParamsController);
    _forward(mpv.stream.error, errorController);
  }

  final Player mpv;
  final void Function() onModeChanged;
  final void Function(String)? onFallback;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  static const _channel = MethodChannel('myvidhub/hdr_player');
  static const _events = EventChannel('myvidhub/inline_hdr_events');
  StreamSubscription<dynamic>? _hdrEvents;
  PlayerState _hdrState = const PlayerState();
  bool _active = false;
  bool _disposed = false;
  int _generation = 0;

  bool get active => _active;

  @override
  PlayerState get state => _active ? _hdrState : mpv.state;

  void _forward<T>(Stream<T> source, StreamController<T> target) {
    _subscriptions.add(source.listen((value) {
      if (!_active && !_disposed) target.add(value);
    }));
  }

  void _publishState() {
    final value = state;
    playingController.add(value.playing);
    positionController.add(value.position);
    durationController.add(value.duration);
    completedController.add(value.completed);
    bufferingController.add(value.buffering);
    bufferController.add(value.buffer);
    volumeController.add(value.volume);
    rateController.add(value.rate);
    trackController.add(value.track);
    tracksController.add(value.tracks);
    videoParamsController.add(value.videoParams);
  }

  Future<void> activate(PlayTarget target, List<String> subtitles, Duration position) async {
    final generation = ++_generation;
    final previous = mpv.state;
    await mpv.pause();
    if (_disposed || generation != _generation) return;
    _hdrState = PlayerState(
      position: position,
      duration: previous.duration,
      playing: previous.playing,
      volume: previous.volume,
      rate: previous.rate,
      buffering: true,
    );
    _active = true;
    _hdrEvents = _events.receiveBroadcastStream().listen(_onEvent, onError: (Object error) {
      if (_active && !_disposed) unawaited(_fallback('HDR 播放失败：$error'));
    });
    onModeChanged();
    _publishState();
    try {
      await _channel.invokeMethod<void>('inlineOpen', {
        'url': target.url,
        'header': target.httpHeader,
        'subtitles': subtitles,
        'position': position.inMilliseconds,
        'volume': previous.volume,
        'rate': previous.rate,
        'playing': previous.playing,
      });
    } catch (_) {
      if (generation == _generation) {
        await closeHdr();
        if (previous.playing && !_disposed) await mpv.play();
      }
      rethrow;
    }
  }

  void _onEvent(dynamic data) {
    if (!_active || _disposed || data is! Map) return;
    final message = Map<Object?, Object?>.from(data);
    final error = message['error'];
    if (error is String) {
      unawaited(_fallback(error));
      return;
    }
    final audio = <AudioTrack>[];
    final subtitle = <SubtitleTrack>[];
    AudioTrack selectedAudio = AudioTrack.auto();
    SubtitleTrack selectedSubtitle = SubtitleTrack.no();
    final rawTracks = message['tracks'];
    if (rawTracks is List) {
      for (final raw in rawTracks) {
        if (raw is! Map || raw['id'] is! String) continue;
        final id = raw['id'] as String;
        final title = raw['title'] as String?;
        final language = raw['language'] as String?;
        final codec = raw['codec'] as String?;
        if (raw['type'] == 'audio') {
          final track = AudioTrack(id, title, language, codec: codec, channelscount: (raw['channels'] as num?)?.toInt());
          audio.add(track);
          if (raw['selected'] == true) selectedAudio = track;
        } else if (raw['type'] == 'subtitle') {
          final track = SubtitleTrack(id, title, language, codec: codec);
          subtitle.add(track);
          if (raw['selected'] == true) selectedSubtitle = track;
        }
      }
    }
    int integer(String key) => (message[key] as num?)?.toInt() ?? 0;
    _hdrState = _hdrState.copyWith(
      playing: message['playing'] == true,
      position: Duration(milliseconds: integer('position')),
      duration: Duration(milliseconds: integer('duration')),
      buffer: Duration(milliseconds: integer('buffer')),
      buffering: message['buffering'] == true,
      completed: message['completed'] == true,
      volume: (message['volume'] as num?)?.toDouble() ?? 100,
      rate: (message['rate'] as num?)?.toDouble() ?? 1,
      track: Track(audio: selectedAudio, subtitle: selectedSubtitle),
      tracks: Tracks(audio: audio, subtitle: subtitle),
    );
    _publishState();
  }

  Future<void> _fallback(String message) async {
    if (!_active || _disposed) return;
    final position = _hdrState.position;
    final playing = _hdrState.playing;
    final generation = _generation + 1;
    await closeHdr();
    if (_disposed || generation != _generation) return;
    await mpv.seek(position);
    if (_disposed || generation != _generation) return;
    if (playing) await mpv.play();
    if (!_disposed && generation == _generation) onFallback?.call('$message，已切回普通播放');
  }

  Future<void> closeHdr() async {
    _generation++;
    if (!_active) return;
    _active = false;
    await _hdrEvents?.cancel();
    _hdrEvents = null;
    await _channel.invokeMethod<void>('inlineClose');
    if (!_disposed) {
      onModeChanged();
      _publishState();
    }
  }

  Future<void> setAspect(String mode) => _channel.invokeMethod<void>('inlineAspect', {'mode': mode});
  Future<void> setSubtitleScale(double scale) =>
      _channel.invokeMethod<void>('inlineSubtitleScale', {'scale': scale});

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    await closeHdr();
    await mpv.open(playable, play: play);
  }

  @override
  Future<void> play() => _active ? _channel.invokeMethod<void>('inlinePlay') : mpv.play();
  @override
  Future<void> pause() => _active ? _channel.invokeMethod<void>('inlinePause') : mpv.pause();
  @override
  Future<void> playOrPause() => state.playing ? pause() : play();
  @override
  Future<void> seek(Duration duration) => _active
      ? _channel.invokeMethod<void>('inlineSeek', {'position': duration.inMilliseconds})
      : mpv.seek(duration);
  @override
  Future<void> setVolume(double volume) =>
      _active ? _channel.invokeMethod<void>('inlineVolume', {'volume': volume}) : mpv.setVolume(volume);
  @override
  Future<void> setRate(double rate) =>
      _active ? _channel.invokeMethod<void>('inlineRate', {'rate': rate}) : mpv.setRate(rate);
  @override
  Future<void> setAudioTrack(AudioTrack track) => _active
      ? _channel.invokeMethod<void>('inlineTrack', {'type': 'audio', 'id': track.id})
      : mpv.setAudioTrack(track);
  @override
  Future<void> setSubtitleTrack(SubtitleTrack track) => _active
      ? _channel.invokeMethod<void>('inlineTrack', {'type': 'subtitle', 'id': track.id})
      : mpv.setSubtitleTrack(track);

  @override
  Future<void> dispose() async {
    _disposed = true;
    await closeHdr();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await super.dispose();
    await mpv.dispose();
  }
}
