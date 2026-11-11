import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import '../../ui/tokens.dart';

import 'player_session.dart';
import 'track_labels.dart';

enum PlayerPanel { subtitle, audio, speed, display, episodes }

const _accent = Palette.light;

/// 右侧滑出的设置面板（全屏播放时不离开播放页面）。
class PanelHost extends StatelessWidget {
  const PanelHost({super.key, required this.panel, required this.session, required this.onClose});

  final PlayerPanel? panel;
  final PlayerSession session;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 600 ? size.width * 0.82 : (size.width * 0.42).clamp(320.0, 420.0);
    final open = panel != null;
    return Stack(children: [
      if (open)
        Positioned.fill(
          child: GestureDetector(onTap: onClose, behavior: HitTestBehavior.opaque, child: const ColoredBox(color: Colors.black26)),
        ),
      AnimatedPositioned(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        top: 0,
        bottom: 0,
        right: open ? 0 : -width - 20,
        width: width,
        child: Material(
          color: Palette.surface1.withValues(alpha: 0.96),
          child: SafeArea(
            left: false,
            child: panel == null
                ? const SizedBox.shrink()
                : Theme(
                    data: Theme.of(context).copyWith(
                      listTileTheme: const ListTileThemeData(textColor: Colors.white, iconColor: Colors.white70),
                    ),
                    child: switch (panel!) {
                      PlayerPanel.subtitle => _SubtitlePanel(session: session),
                      PlayerPanel.audio => _AudioPanel(session: session),
                      PlayerPanel.speed => _SpeedPanel(session: session),
                      PlayerPanel.display => _DisplayPanel(session: session),
                      PlayerPanel.episodes => _EpisodesPanel(session: session, onPicked: onClose),
                    },
                  ),
          ),
        ),
      ),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
      );
}

class _Option extends StatelessWidget {
  const _Option({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(label, style: TextStyle(color: selected ? _accent : Colors.white)),
        trailing: selected ? const Icon(Icons.check_rounded, color: _accent) : null,
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      );
}

class _SubtitlePanel extends StatelessWidget {
  const _SubtitlePanel({required this.session});
  final PlayerSession session;

  @override
  Widget build(BuildContext context) {
    final player = session.player;
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, _) => StreamBuilder<Track>(
        stream: player.stream.track,
        initialData: player.state.track,
        builder: (context, _) {
          final tracks = player.state.tracks.subtitle.where((t) => isRealTrack(t.id)).toList();
          final current = player.state.track.subtitle.id;
          return ListenableBuilder(
            listenable: session,
            builder: (context, _) => ListView(children: [
              const _Header('字幕'),
              _Option(
                label: '关闭',
                selected: current == 'no',
                onTap: () => player.setSubtitleTrack(SubtitleTrack.no()),
              ),
              for (var i = 0; i < tracks.length; i++)
                _Option(
                  label: subtitleTrackLabel(tracks[i], i),
                  selected: tracks[i].id == current,
                  onTap: () => player.setSubtitleTrack(tracks[i]),
                ),
              if (tracks.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Text('没有找到字幕。外挂字幕请与视频同名放在同一目录（或 Subs 子目录）。',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              const Divider(color: Colors.white12, height: 32),
              _Stepper(
                label: '字幕延迟',
                value: '${session.subDelay >= 0 ? '+' : ''}${session.subDelay.toStringAsFixed(1)} 秒',
                onMinus: () => session.setSubDelay(session.subDelay - 0.1),
                onPlus: () => session.setSubDelay(session.subDelay + 0.1),
                onReset: session.subDelay == 0 ? null : () => session.setSubDelay(0),
              ),
              _Stepper(
                label: '字幕大小',
                value: '${(session.subScale * 100).round()}%',
                onMinus: () => session.setSubScale(session.subScale - 0.1),
                onPlus: () => session.setSubScale(session.subScale + 0.1),
                onReset: session.subScale == 1 ? null : () => session.setSubScale(1),
              ),
              const SizedBox(height: 16),
            ]),
          );
        },
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.onMinus, required this.onPlus, this.onReset});
  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white))),
          IconButton(onPressed: onMinus, icon: const Icon(Icons.remove_rounded, color: Colors.white)),
          SizedBox(
            width: 76,
            child: Text(value,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
          ),
          IconButton(onPressed: onPlus, icon: const Icon(Icons.add_rounded, color: Colors.white)),
          IconButton(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded),
            color: Colors.white70,
            tooltip: '重置',
          ),
        ]),
      );
}

class _AudioPanel extends StatelessWidget {
  const _AudioPanel({required this.session});
  final PlayerSession session;

  @override
  Widget build(BuildContext context) {
    final player = session.player;
    return StreamBuilder<Track>(
      stream: player.stream.track,
      initialData: player.state.track,
      builder: (context, _) {
        final tracks = player.state.tracks.audio.where((t) => isRealTrack(t.id)).toList();
        final current = player.state.track.audio.id;
        return ListView(children: [
          const _Header('音轨'),
          for (var i = 0; i < tracks.length; i++)
            _Option(
              label: audioTrackLabel(tracks[i], i),
              // 当前为 auto 时，第一条视为选中
              selected: tracks[i].id == current || (current == 'auto' && i == 0),
              onTap: () => player.setAudioTrack(tracks[i]),
            ),
          if (tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('没有音轨', style: TextStyle(color: Colors.white54)),
            ),
        ]);
      },
    );
  }
}

class _SpeedPanel extends StatelessWidget {
  const _SpeedPanel({required this.session});
  final PlayerSession session;

  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  @override
  Widget build(BuildContext context) {
    final player = session.player;
    return StreamBuilder<double>(
      stream: player.stream.rate,
      initialData: player.state.rate,
      builder: (context, s) => ListView(children: [
        const _Header('播放速度'),
        for (final v in speeds)
          _Option(
            label: v == 1.0 ? '1.0x  正常' : '${v}x',
            selected: (s.data! - v).abs() < 0.01,
            onTap: () => player.setRate(v),
          ),
      ]),
    );
  }
}

class _DisplayPanel extends StatelessWidget {
  const _DisplayPanel({required this.session});
  final PlayerSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) => ListView(children: [
          const _Header('画面比例'),
          for (final m in AspectMode.values)
            _Option(label: m.label, selected: session.aspect == m, onTap: () => session.setAspect(m)),
          const Divider(color: Colors.white12, height: 32),
          StreamBuilder<VideoParams>(
            stream: session.player.stream.videoParams,
            initialData: session.player.state.videoParams,
            builder: (_, s) {
              final v = s.data!;
              final info = [
                if (v.w != null && v.h != null) '${v.w}×${v.h}',
                if (v.pixelformat != null) v.pixelformat!,
                if (v.gamma != null && v.gamma != 'auto') v.gamma!,
              ].join(' · ');
              return info.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('视频：$info', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    );
            },
          ),
        ]),
      );
}

class _EpisodesPanel extends StatefulWidget {
  const _EpisodesPanel({required this.session, required this.onPicked});
  final PlayerSession session;
  final VoidCallback onPicked;

  @override
  State<_EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends State<_EpisodesPanel> {
  static const _itemExtent = 64.0;
  late final _scroll = ScrollController(
    initialScrollOffset: (widget.session.index - 2).clamp(0, 1 << 20) * _itemExtent,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Header('选集 · 共 ${s.queue.length} 集'),
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          itemExtent: _itemExtent,
          itemCount: s.queue.length,
          itemBuilder: (context, i) {
            final item = s.queue[i];
            final progress = s.db.progress(item.path);
            final playing = i == s.index;
            return ListTile(
              leading: playing
                  ? const Icon(Icons.equalizer_rounded, color: _accent)
                  : progress?.finished == true
                      ? const Icon(Icons.check_circle_rounded, color: Colors.white38)
                      : const Icon(Icons.play_circle_outline_rounded, color: Colors.white54),
              title: Text(item.subtitle ?? item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: playing ? _accent : Colors.white)),
              subtitle: progress != null && !progress.finished && progress.positionMs > 0
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6, right: 24),
                      child: LinearProgressIndicator(
                        value: progress.fraction,
                        minHeight: 3,
                        color: _accent,
                        backgroundColor: Colors.white12,
                      ),
                    )
                  : null,
              onTap: () {
                widget.onPicked();
                if (!playing) s.playAt(i);
              },
            );
          },
        ),
      ),
    ]);
  }
}
