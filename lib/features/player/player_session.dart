import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/db/library_db.dart';
import '../../services/source_registry.dart';
import 'play_item.dart';
import 'subtitle_fonts.dart';

enum AspectMode {
  fit('适应屏幕', null),
  fill('裁剪填充', null),
  stretch('拉伸铺满', null),
  r16x9('16:9', '16:9'),
  r4x3('4:3', '4:3'),
  r235('2.35:1', '2.35:1');

  const AspectMode(this.label, this.mpvAspect);
  final String label;
  final String? mpvAspect;
}

/// 一次播放会话：持有 mpv 播放器、播放队列，负责进度记忆与自动连播。
class PlayerSession extends ChangeNotifier {
  PlayerSession({required this.db, required this.queue, required int startIndex})
      : index = startIndex;

  final LibraryDb db;
  final List<PlayItem> queue;
  int index;

  late final Player player;
  late final VideoController video;

  PlayItem get current => queue[index];
  bool get hasNext => index + 1 < queue.length;
  bool get hasPrev => index > 0;

  /// 本次是从哪里续播的（用于提示"已从 xx:xx 继续"）。
  Duration? resumedFrom;

  /// 播完后倒计时自动下一集；null 表示没有倒计时。
  int? upNextCountdown;
  Timer? _upNextTimer;

  AspectMode aspect = AspectMode.fit;
  double subDelay = 0;
  double subScale = 1;
  String? error;

  final _subs = <StreamSubscription<dynamic>>[];
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  NativePlayer? get _native => player.platform is NativePlayer ? player.platform as NativePlayer : null;

  Future<void> init() async {
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'ReelNest',
        libass: true, // ASS 特效字幕由 libass 原样渲染
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    video = VideoController(
      player,
      configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true),
    );

    final np = _native;
    if (np != null) {
      // 自动加载同目录 / Subs 子目录里的外挂字幕（文件名模糊匹配）
      await np.setProperty('sub-auto', 'fuzzy');
      await np.setProperty('sub-file-paths', 'Subs:subs:Subtitles:subtitles:Sub:sub:字幕');
      // 默认字幕语言优先级：简体 > 中文 > 繁体 > 英文
      await np.setProperty('slang', 'chs,sc,zh-hans,zh-cn,chi,zho,zh,cht,tc,zh-hant,zh-tw,eng,en');
      await np.setProperty('sub-codepage', 'auto');
      await np.setProperty('demuxer-mkv-subtitle-preroll', 'yes');
      await np.setProperty('keep-open', 'yes'); // 播完停在最后一帧，不清空画面
      await SubtitleFonts.configure(np);
    }

    _subs
      ..add(player.stream.position.listen(_onPosition))
      ..add(player.stream.completed.listen(_onCompleted))
      ..add(player.stream.error.listen((e) {
        error = e;
        notifyListeners();
      }));

    await _openCurrent();
  }

  Future<void> _openCurrent({bool fromStart = false}) async {
    _cancelUpNext();
    error = null;
    final pr = db.progress(current.path);
    Duration? start;
    if (!fromStart && pr != null && !pr.finished && pr.positionMs > 30000) {
      start = Duration(milliseconds: pr.positionMs);
    }
    resumedFrom = start;
    _lastSave = DateTime.now();

    // 本地文件直接播放；NAS 上的文件解析成 HTTP 地址（WebDAV 直连 / SMB 走本地代理）
    final PlayTarget target;
    try {
      target = await SourceRegistry.instance.playTarget(current.path);
    } catch (e) {
      error = '$e';
      notifyListeners();
      return;
    }
    final np = _native;
    await np?.setProperty('http-header-fields', target.httpHeader ?? '');
    await player.open(Media(target.url, start: start), play: true);
    notifyListeners();

    if (target.subtitles.isNotEmpty && np != null) {
      // 等文件真正加载（拿到时长）后再挂外挂字幕
      try {
        await player.stream.duration.firstWhere((d) => d > Duration.zero).timeout(const Duration(seconds: 20));
        for (final s in target.subtitles) {
          final name = Uri.decodeComponent(s.substring(s.lastIndexOf('/') + 1));
          await np.command(['sub-add', s, 'auto', name]);
        }
      } catch (_) {}
    }
  }

  Future<void> restartFromBeginning() async {
    resumedFrom = null;
    await player.seek(Duration.zero);
    notifyListeners();
  }

  Future<void> playAt(int i) async {
    if (i < 0 || i >= queue.length) return;
    saveProgress();
    index = i;
    await _openCurrent();
  }

  Future<void> next() => playAt(index + 1);
  Future<void> prev() => playAt(index - 1);

  void _onPosition(Duration pos) {
    if (DateTime.now().difference(_lastSave).inSeconds >= 5) saveProgress();
  }

  /// 保存进度。看到 92% 以上，或长片剩余不足 90 秒，视为看完。
  void saveProgress({bool forceFinished = false}) {
    if (_disposed) return;
    _lastSave = DateTime.now();
    final dur = player.state.duration;
    final pos = player.state.position;
    if (dur <= Duration.zero) return;
    final finished = forceFinished ||
        pos.inMilliseconds >= dur.inMilliseconds * 0.92 ||
        (dur > const Duration(minutes: 10) && dur - pos < const Duration(seconds: 90));
    db.saveProgress(
      current.path,
      positionMs: finished ? 0 : pos.inMilliseconds,
      durationMs: dur.inMilliseconds,
      finished: finished,
    );
  }

  void _onCompleted(bool completed) {
    if (!completed) return;
    saveProgress(forceFinished: true);
    if (!hasNext) return;
    upNextCountdown = 5;
    notifyListeners();
    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = (upNextCountdown ?? 0) - 1;
      if (left <= 0) {
        t.cancel();
        upNextCountdown = null;
        next();
      } else {
        upNextCountdown = left;
        notifyListeners();
      }
    });
  }

  void cancelUpNext() {
    _cancelUpNext();
    notifyListeners();
  }

  void _cancelUpNext() {
    _upNextTimer?.cancel();
    _upNextTimer = null;
    upNextCountdown = null;
  }

  // ------------------------------------------------------------ 画面 / 字幕

  Future<void> setAspect(AspectMode m) async {
    aspect = m;
    await _native?.setProperty('video-aspect-override', m.mpvAspect ?? '-1');
    notifyListeners();
  }

  Future<void> setSubDelay(double seconds) async {
    subDelay = double.parse(seconds.toStringAsFixed(1));
    await _native?.setProperty('sub-delay', subDelay.toString());
    notifyListeners();
  }

  Future<void> setSubScale(double scale) async {
    subScale = double.parse(scale.clamp(0.5, 2.5).toStringAsFixed(1));
    await _native?.setProperty('sub-scale', subScale.toString());
    notifyListeners();
  }

  Future<void> seekRelative(Duration d) async {
    final dur = player.state.duration;
    var t = player.state.position + d;
    if (t < Duration.zero) t = Duration.zero;
    if (dur > Duration.zero && t > dur) t = dur - const Duration(milliseconds: 500);
    await player.seek(t);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  Future<void> dispose() async {
    saveProgress();
    _disposed = true;
    _cancelUpNext();
    for (final s in _subs) {
      await s.cancel();
    }
    super.dispose();
    await player.dispose();
  }
}
