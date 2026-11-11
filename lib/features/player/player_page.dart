import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../app/providers.dart';
import 'play_item.dart';
import 'player_controls.dart';
import 'player_panels.dart';
import 'player_session.dart';

bool get isMobile => Platform.isAndroid || Platform.isIOS;

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({super.key, required this.queue, required this.startIndex});

  final List<PlayItem> queue;
  final int startIndex;

  static Future<void> open(BuildContext context, WidgetRef ref, List<PlayItem> queue, [int index = 0]) async {
    if (queue.isEmpty) return;
    await Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      pageBuilder: (_, _, _) => PlayerPage(queue: queue, startIndex: index),
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
    // 回来后刷新进度条 / 继续观看
    ref.read(libraryRevisionProvider.notifier).bump();
  }

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

/// 屏幕中央的临时提示（音量 / 亮度 / 拖动进度 / 倍速）。
class Hud {
  const Hud(this.icon, this.text, {this.value});
  final IconData icon;
  final String text;
  final double? value;
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final PlayerSession session;
  final _focus = FocusNode();
  bool _ready = false;

  bool _controlsVisible = true;
  bool _locked = false;
  PlayerPanel? _panel;
  Timer? _hideTimer;

  Hud? _hud;
  Timer? _hudTimer;

  bool _fullscreen = false;
  bool _showResume = false;
  Timer? _resumeTimer;

  // 手势状态
  Duration? _seekBase;
  Duration? _seekTarget;
  double _dragStartValue = 0;
  bool _dragIsBrightness = false;
  double _brightness = 0.5;
  double? _rateBeforeLongPress;

  @override
  void initState() {
    super.initState();
    session = PlayerSession(db: ref.read(dbProvider), queue: widget.queue, startIndex: widget.startIndex);
    session.addListener(_onSession);
    _init();
    if (isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      // 手机强制横屏；平板保持可旋转
      final shortest = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.shortestSide /
          WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
      if (shortest < 600) {
        SystemChrome.setPreferredOrientations(
            [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      }
      ScreenBrightness.instance.application.then((v) => _brightness = v).catchError((_) => 0.5);
    }
  }

  Future<void> _init() async {
    await session.init();
    if (!mounted) return;
    setState(() => _ready = true);
    _scheduleHide();
  }

  String? _lastPath;
  void _onSession() {
    if (!mounted) return;
    if (session.current.path != _lastPath) {
      _lastPath = session.current.path;
      _showResume = session.resumedFrom != null;
      _resumeTimer?.cancel();
      if (_showResume) {
        _resumeTimer = Timer(const Duration(seconds: 7), () => setState(() => _showResume = false));
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _hudTimer?.cancel();
    _resumeTimer?.cancel();
    session.removeListener(_onSession);
    session.dispose();
    _focus.dispose();
    if (isMobile) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});
    } else if (_fullscreen) {
      defaultExitNativeFullscreen();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ 控制栏显隐

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted || _panel != null) return;
      if (!_ready || !session.player.state.playing) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _openPanel(PlayerPanel p) {
    setState(() => _panel = _panel == p ? null : p);
    _hideTimer?.cancel();
  }

  void _closePanel() {
    setState(() => _panel = null);
    _scheduleHide();
  }

  void _flashHud(Hud hud) {
    _hudTimer?.cancel();
    setState(() => _hud = hud);
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hud = null);
    });
  }

  // ------------------------------------------------------------ 动作

  void _togglePlay() {
    session.player.playOrPause();
    _flashHud(Hud(session.player.state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        session.player.state.playing ? '暂停' : '播放'));
    _showControls();
  }

  void _seekBy(int seconds) {
    session.seekRelative(Duration(seconds: seconds));
    _flashHud(Hud(seconds > 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
        '${seconds > 0 ? '+' : ''}$seconds 秒'));
  }

  void _changeVolume(double delta) {
    final v = (session.player.state.volume + delta).clamp(0.0, 100.0);
    session.player.setVolume(v);
    _flashHud(Hud(v == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, '音量 ${v.round()}',
        value: v / 100));
  }

  void _setBrightness(double v) {
    _brightness = v.clamp(0.0, 1.0);
    ScreenBrightness.instance.setApplicationScreenBrightness(_brightness).catchError((_) {});
    _flashHud(Hud(Icons.brightness_6_rounded, '亮度 ${(_brightness * 100).round()}%', value: _brightness));
  }

  Future<void> _toggleFullscreen() async {
    if (isMobile) return;
    _fullscreen = !_fullscreen;
    _fullscreen ? await defaultEnterNativeFullscreen() : await defaultExitNativeFullscreen();
    setState(() {});
  }

  void _exit() {
    if (_panel != null) {
      _closePanel();
      return;
    }
    if (_fullscreen) {
      _toggleFullscreen();
      return;
    }
    Navigator.of(context).maybePop();
  }

  // ------------------------------------------------------------ 键盘（桌面 / 遥控器）

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || !_ready) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK || k == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
    } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyJ) {
      _seekBy(shift ? -60 : -10);
      _showControls();
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyL) {
      _seekBy(shift ? 60 : 10);
      _showControls();
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _changeVolume(5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _changeVolume(-5);
    } else if (k == LogicalKeyboardKey.keyF || (k == LogicalKeyboardKey.enter && HardwareKeyboard.instance.isAltPressed)) {
      _toggleFullscreen();
    } else if (k == LogicalKeyboardKey.keyM) {
      final v = session.player.state.volume;
      session.player.setVolume(v > 0 ? 0 : 100);
      _flashHud(Hud(v > 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, v > 0 ? '静音' : '取消静音'));
    } else if (k == LogicalKeyboardKey.keyN || k == LogicalKeyboardKey.mediaTrackNext) {
      if (session.hasNext) session.next();
    } else if (k == LogicalKeyboardKey.keyP || k == LogicalKeyboardKey.mediaTrackPrevious) {
      if (session.hasPrev) session.prev();
    } else if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.goBack) {
      _exit();
    } else if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter) {
      _toggleControls();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------ 手势

  Widget _gestureLayer(BoxConstraints c) {
    final width = c.maxWidth;
    Offset? doubleTapPos;

    return Listener(
      onPointerSignal: (s) {
        if (s is PointerScrollEvent) _changeVolume(s.scrollDelta.dy > 0 ? -5 : 5);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_panel != null) return _closePanel();
          if (_locked) return setState(() => _controlsVisible = !_controlsVisible);
          isMobile ? _toggleControls() : _togglePlay();
        },
        onDoubleTapDown: (d) => doubleTapPos = d.localPosition,
        onDoubleTap: _locked
            ? null
            : () {
                if (!isMobile) {
                  _toggleFullscreen();
                  return;
                }
                final x = doubleTapPos?.dx ?? width / 2;
                if (x < width / 3) {
                  _seekBy(-10);
                } else if (x > width * 2 / 3) {
                  _seekBy(10);
                } else {
                  _togglePlay();
                }
              },
        onLongPressStart: _locked
            ? null
            : (_) {
                _rateBeforeLongPress = session.player.state.rate;
                session.player.setRate(2.0);
                _hudTimer?.cancel();
                setState(() => _hud = const Hud(Icons.fast_forward_rounded, '2 倍速播放中'));
              },
        onLongPressEnd: _locked
            ? null
            : (_) {
                session.player.setRate(_rateBeforeLongPress ?? 1.0);
                setState(() => _hud = null);
              },
        onHorizontalDragStart: _locked
            ? null
            : (_) {
                _seekBase = session.player.state.position;
                _seekTarget = _seekBase;
              },
        onHorizontalDragUpdate: _locked
            ? null
            : (d) {
                final dur = session.player.state.duration;
                if (_seekTarget == null || dur <= Duration.zero) return;
                // 横滑满屏 ≈ 90 秒
                final deltaMs = d.delta.dx / width * 90000;
                var t = _seekTarget! + Duration(milliseconds: deltaMs.round());
                if (t < Duration.zero) t = Duration.zero;
                if (t > dur) t = dur;
                _seekTarget = t;
                final diff = (t - _seekBase!).inSeconds;
                _hudTimer?.cancel();
                setState(() => _hud = Hud(
                      diff >= 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                      '${formatDuration(t)} / ${formatDuration(dur)}   ${diff >= 0 ? '+' : ''}$diff 秒',
                      value: t.inMilliseconds / dur.inMilliseconds,
                    ));
              },
        onHorizontalDragEnd: _locked
            ? null
            : (_) {
                if (_seekTarget != null) session.player.seek(_seekTarget!);
                _seekTarget = null;
                _flashHud(_hud ?? const Hud(Icons.fast_forward_rounded, ''));
              },
        onVerticalDragStart: _locked
            ? null
            : (d) {
                _dragIsBrightness = isMobile && d.localPosition.dx < width / 2;
                _dragStartValue = _dragIsBrightness ? _brightness : session.player.state.volume / 100;
              },
        onVerticalDragUpdate: _locked
            ? null
            : (d) {
                final delta = -d.delta.dy / (c.maxHeight * 0.8);
                _dragStartValue = (_dragStartValue + delta).clamp(0.0, 1.0);
                if (_dragIsBrightness) {
                  _setBrightness(_dragStartValue);
                } else {
                  session.player.setVolume(_dragStartValue * 100);
                  _flashHud(Hud(_dragStartValue == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      '音量 ${(_dragStartValue * 100).round()}', value: _dragStartValue));
                }
              },
      ),
    );
  }

  // ------------------------------------------------------------ 布局

  @override
  Widget build(BuildContext context) {
    final hideCursor = !_controlsVisible && _panel == null && !isMobile;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: PopScope(
        canPop: _panel == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _closePanel();
          } else {
            // 在返回动画开始前就保存进度，详情页 / 首页立即显示最新状态
            session.saveProgress();
            session.player.pause();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: MouseRegion(
            cursor: hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
            onHover: (_) => _showControls(),
            child: LayoutBuilder(builder: (context, c) {
              return Stack(fit: StackFit.expand, children: [
                if (_ready)
                  Video(
                    controller: session.video,
                    controls: NoVideoControls,
                    fill: Colors.black,
                    fit: switch (session.aspect) {
                      AspectMode.fill => BoxFit.cover,
                      AspectMode.stretch => BoxFit.fill,
                      _ => BoxFit.contain,
                    },
                    // libass 直接把字幕画进视频帧，关闭 Flutter 文字字幕
                    subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                  ),
                _gestureLayer(c),
                if (_ready) BufferingIndicator(player: session.player),
                if (session.error != null) _ErrorView(message: session.error!, onBack: _exit),
                if (_hud != null) Align(alignment: const Alignment(0, -0.45), child: HudView(hud: _hud!)),
                if (_ready)
                  PlayerControls(
                    session: session,
                    visible: _controlsVisible && _panel == null,
                    locked: _locked,
                    fullscreen: _fullscreen,
                    isMobile: isMobile,
                    onBack: _exit,
                    onTogglePlay: _togglePlay,
                    onSeekBy: _seekBy,
                    onOpenPanel: _openPanel,
                    onToggleFullscreen: isMobile ? null : _toggleFullscreen,
                    onToggleLock: () {
                      setState(() => _locked = !_locked);
                      _scheduleHide();
                    },
                    onInteraction: _showControls,
                  ),
                if (_ready && _showResume && session.resumedFrom != null && !_locked)
                  Positioned(
                    left: 24,
                    bottom: _controlsVisible ? 128 : 32,
                    child: ResumeToast(
                      from: session.resumedFrom!,
                      onRestart: () {
                        session.restartFromBeginning();
                        setState(() => _showResume = false);
                      },
                    ),
                  ),
                if (_ready && session.upNextCountdown != null)
                  Positioned(
                    right: 24,
                    bottom: 32,
                    child: UpNextCard(session: session),
                  ),
                if (_ready)
                  PanelHost(
                    panel: _panel,
                    session: session,
                    onClose: _closePanel,
                  ),
              ]);
            }),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.white70),
            const SizedBox(height: 12),
            const Text('无法播放这个文件', style: TextStyle(fontSize: 18, color: Colors.white)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 20),
            OutlinedButton(onPressed: onBack, child: const Text('返回')),
          ]),
        ),
      );
}
