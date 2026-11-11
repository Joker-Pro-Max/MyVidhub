import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../ui/components.dart';
import '../../ui/tokens.dart';

import 'play_item.dart';
import 'player_page.dart';
import 'player_panels.dart';
import 'player_session.dart';

const _accent = Palette.light;

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.session,
    required this.visible,
    required this.locked,
    required this.fullscreen,
    required this.isMobile,
    required this.onBack,
    required this.onTogglePlay,
    required this.onSeekBy,
    required this.onOpenPanel,
    required this.onToggleLock,
    required this.onInteraction,
    this.onToggleFullscreen,
  });

  final PlayerSession session;
  final bool visible;
  final bool locked;
  final bool fullscreen;
  final bool isMobile;
  final VoidCallback onBack;
  final VoidCallback onTogglePlay;
  final void Function(int seconds) onSeekBy;
  final void Function(PlayerPanel) onOpenPanel;
  final VoidCallback onToggleLock;
  final VoidCallback onInteraction;
  final VoidCallback? onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final player = session.player;
    final item = session.current;

    final lockButton = isMobile
        ? Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _RoundButton(
                icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                tooltip: locked ? '解锁' : '锁定屏幕',
                onPressed: onToggleLock,
              ),
            ),
          )
        : const SizedBox.shrink();

    if (locked) {
      return IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(opacity: visible ? 1 : 0, duration: const Duration(milliseconds: 200), child: lockButton),
      );
    }

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        child: Listener(
          onPointerDown: (_) => onInteraction(),
          behavior: HitTestBehavior.translucent,
          child: Stack(fit: StackFit.expand, children: [
            // 顶部
            Align(
              alignment: Alignment.topCenter,
              child: _Gradient(
                top: true,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 12, 24),
                    child: Row(children: [
                      IconButton(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back_rounded),
                        tooltip: '返回',
                        iconSize: 28,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          if (item.subtitle != null)
                            Text(item.subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, color: Colors.white70)),
                        ]),
                      ),
                      _TopAction(icon: Icons.subtitles_outlined, label: '字幕', onTap: () => onOpenPanel(PlayerPanel.subtitle)),
                      _TopAction(icon: Icons.graphic_eq_rounded, label: '音轨', onTap: () => onOpenPanel(PlayerPanel.audio)),
                      StreamBuilder<double>(
                        stream: player.stream.rate,
                        initialData: player.state.rate,
                        builder: (_, s) => _TopAction(
                          icon: Icons.speed_rounded,
                          label: s.data == 1.0 ? '倍速' : '${_trim(s.data!)}x',
                          onTap: () => onOpenPanel(PlayerPanel.speed),
                        ),
                      ),
                      _TopAction(icon: Icons.aspect_ratio_rounded, label: '画面', onTap: () => onOpenPanel(PlayerPanel.display)),
                      if (session.queue.length > 1)
                        _TopAction(
                            icon: Icons.video_library_outlined, label: '选集', onTap: () => onOpenPanel(PlayerPanel.episodes)),
                    ]),
                  ),
                ),
              ),
            ),
            // 中间大按钮
            Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _RoundButton(icon: Icons.replay_10_rounded, tooltip: '后退 10 秒', onPressed: () => onSeekBy(-10), size: 52),
                const SizedBox(width: 36),
                StreamBuilder<bool>(
                  stream: player.stream.playing,
                  initialData: player.state.playing,
                  builder: (_, s) => _RoundButton(
                    icon: s.data! ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    tooltip: s.data! ? '暂停' : '播放',
                    onPressed: onTogglePlay,
                    size: 76,
                  ),
                ),
                const SizedBox(width: 36),
                _RoundButton(icon: Icons.forward_10_rounded, tooltip: '前进 10 秒', onPressed: () => onSeekBy(10), size: 52),
              ]),
            ),
            lockButton,
            // 底部
            Align(
              alignment: Alignment.bottomCenter,
              child: _Gradient(
                top: false,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 32, 20, 10),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      SeekBar(player: player, onInteraction: onInteraction),
                      Row(children: [
                        if (session.queue.length > 1)
                          IconButton(
                            onPressed: session.hasPrev ? session.prev : null,
                            icon: const Icon(Icons.skip_previous_rounded),
                            tooltip: '上一集',
                          ),
                        StreamBuilder<bool>(
                          stream: player.stream.playing,
                          initialData: player.state.playing,
                          builder: (_, s) => IconButton(
                            onPressed: onTogglePlay,
                            icon: Icon(s.data! ? Icons.pause_rounded : Icons.play_arrow_rounded),
                            iconSize: 30,
                            tooltip: s.data! ? '暂停' : '播放',
                          ),
                        ),
                        if (session.queue.length > 1)
                          IconButton(
                            onPressed: session.hasNext ? session.next : null,
                            icon: const Icon(Icons.skip_next_rounded),
                            tooltip: '下一集',
                          ),
                        const SizedBox(width: 8),
                        _TimeLabel(player: player),
                        const Spacer(),
                        if (!isMobile) _VolumeButton(player: player),
                        if (onToggleFullscreen != null)
                          IconButton(
                            onPressed: onToggleFullscreen,
                            icon: Icon(fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
                            iconSize: 28,
                            tooltip: fullscreen ? '退出全屏' : '全屏',
                          ),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  static String _trim(double v) => v == v.roundToDouble() ? v.toStringAsFixed(1) : v.toString();
}

class _Gradient extends StatelessWidget {
  const _Gradient({required this.top, required this.child});
  final bool top;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: top ? Alignment.topCenter : Alignment.bottomCenter,
            end: top ? Alignment.bottomCenter : Alignment.topCenter,
            colors: const [Color(0xCC000000), Color(0x00000000)],
          ),
        ),
        child: IconTheme(
          data: const IconThemeData(color: Colors.white),
          child: DefaultTextStyle(style: const TextStyle(color: Colors.white), child: child),
        ),
      );
}

class _TopAction extends StatelessWidget {
  const _TopAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: compact
          ? IconButton(onPressed: onTap, icon: Icon(icon), tooltip: label)
          : TextButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 22),
              label: Text(label),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(48, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onPressed, required this.tooltip, this.size = 48});
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: 0.38),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: Colors.white, size: size * 0.55),
            ),
          ),
        ),
      );
}

class _TimeLabel extends StatelessWidget {
  const _TimeLabel({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration>(
        stream: player.stream.position,
        initialData: player.state.position,
        builder: (_, s) => Text(
          '${formatDuration(s.data!)} / ${formatDuration(player.state.duration)}',
          style: const TextStyle(fontSize: 13, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]),
        ),
      );
}

class _VolumeButton extends StatelessWidget {
  const _VolumeButton({required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) => StreamBuilder<double>(
        stream: player.stream.volume,
        initialData: player.state.volume,
        builder: (_, s) {
          final v = s.data!;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              onPressed: () => player.setVolume(v > 0 ? 0 : 100),
              icon: Icon(v == 0 ? Icons.volume_off_rounded : v < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
              tooltip: v > 0 ? '静音' : '取消静音',
            ),
            SizedBox(
              width: 110,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                ),
                child: Slider(value: v.clamp(0, 100), max: 100, onChanged: player.setVolume),
              ),
            ),
          ]);
        },
      );
}

/// 带缓冲进度的进度条；拖动时只预览，松手才 seek。
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, required this.player, required this.onInteraction});
  final Player player;
  final VoidCallback onInteraction;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      initialData: player.state.position,
      builder: (context, snap) {
        final dur = player.state.duration.inMilliseconds.toDouble();
        final max = dur <= 0 ? 1.0 : dur;
        final pos = (_dragValue ?? snap.data!.inMilliseconds.toDouble()).clamp(0.0, max);
        final buf = player.state.buffer.inMilliseconds.toDouble().clamp(0.0, max);
        return Row(children: [
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                activeTrackColor: _accent,
                secondaryActiveTrackColor: Colors.white38,
                inactiveTrackColor: Colors.white24,
                thumbColor: _accent,
                overlayColor: _accent.withValues(alpha: 0.2),
                showValueIndicator: ShowValueIndicator.onDrag,
                valueIndicatorColor: Colors.black87,
                valueIndicatorTextStyle: const TextStyle(color: Colors.white),
              ),
              child: Slider(
                value: pos,
                max: max,
                secondaryTrackValue: buf,
                label: formatDuration(Duration(milliseconds: pos.round())),
                onChangeStart: (v) {
                  widget.onInteraction();
                  setState(() => _dragValue = v);
                },
                onChanged: (v) {
                  widget.onInteraction();
                  setState(() => _dragValue = v);
                },
                onChangeEnd: (v) {
                  player.seek(Duration(milliseconds: v.round()));
                  setState(() => _dragValue = null);
                },
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class BufferingIndicator extends StatelessWidget {
  const BufferingIndicator({super.key, required this.player});
  final Player player;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: StreamBuilder<bool>(
          stream: player.stream.buffering,
          initialData: player.state.buffering,
          builder: (_, s) => s.data!
              ? const Center(
                  child: SizedBox(width: 48, height: 48, child: CircularProgressIndicator(color: _accent, strokeWidth: 3)),
                )
              : const SizedBox.shrink(),
        ),
      );
}

class HudView extends StatelessWidget {
  const HudView({super.key, required this.hud});
  final Hud hud;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(minWidth: 180),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(hud.icon, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Text(hud.text,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 16, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
            if (hud.value != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: hud.value,
                    minHeight: 4,
                    color: _accent,
                    backgroundColor: Colors.white24,
                  ),
                ),
              ),
            ],
          ]),
        ),
      );
}

class ResumeToast extends StatelessWidget {
  const ResumeToast({super.key, required this.from, required this.onRestart});
  final Duration from;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) => Material(
        color: Palette.surface2.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('已从 ${formatDuration(from)} 继续播放', style: const TextStyle(color: Colors.white)),
            const SizedBox(width: 8),
            PillButton(label: '从头播放', primary: false, compact: true, onPressed: onRestart),
          ]),
        ),
      );
}

class UpNextCard extends StatelessWidget {
  const UpNextCard({super.key, required this.session});
  final PlayerSession session;

  @override
  Widget build(BuildContext context) {
    final next = session.queue[session.index + 1];
    return Material(
      color: Palette.surface2.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 300,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${session.upNextCountdown} 秒后播放下一集',
                style: const TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 6),
            Text(next.subtitle ?? next.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(children: [
              PillButton(label: '立即播放', icon: Icons.skip_next_rounded, compact: true, onPressed: session.next),
              const SizedBox(width: 8),
              PillButton(label: '取消', primary: false, compact: true, onPressed: session.cancelUpNext),
            ]),
          ]),
        ),
      ),
    );
  }
}
