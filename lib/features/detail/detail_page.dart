import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../widgets/media_image.dart';
import '../player/play_item.dart';
import '../player/player_page.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key, required this.id});
  final int id;

  static Future<void> open(BuildContext context, int id) => Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, _, _) => DetailPage(id: id),
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
                  .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        ),
      );

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  int? _season;

  void _play(MediaDetail d, String path) {
    if (d.kind == MediaKind.movie) {
      PlayerPage.open(context, ref, movieQueue(d, path));
    } else {
      final queue = showQueue(ref.read(dbProvider), d.id, d.title);
      PlayerPage.open(context, ref, queue, queue.indexWhere((q) => q.path == path).clamp(0, queue.length));
    }
  }

  void _setWatched(List<String> paths, bool watched) {
    ref.read(dbProvider).setWatched(paths, watched);
    ref.read(libraryRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(detailProvider(widget.id));
    final theme = Theme.of(context);
    if (d == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('条目已不存在')));
    }
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;
    final backdropH = (size.height * (wide ? 0.62 : 0.42)).clamp(260.0, 620.0);
    final progress = ref.watch(itemProgressProvider(d.id));
    final allEps = d.kind == MediaKind.show ? ref.watch(allEpisodesProvider(d.id)) : const <EpisodeRow>[];
    final resumeIdx = resumeEpisodeIndex(allEps, progress);
    final season = _season ??
        (allEps.isNotEmpty
            ? allEps[resumeIdx].season
            : (d.seasons.where((s) => s.season > 0).firstOrNull ?? d.seasons.firstOrNull)?.season);

    // 播放按钮文案与目标
    String playLabel = '播放';
    String? playPath;
    late final List<String> allPaths;
    late final bool watched;
    if (d.kind == MediaKind.movie) {
      allPaths = [for (final f in d.files) f.path];
      watched = allPaths.any((p) => progress[p]?.finished == true);
      if (d.files.isNotEmpty) {
        playPath = d.files.first.path;
        final pr = progress[playPath];
        if (pr != null && !pr.finished && pr.positionMs > 30000) {
          playLabel = '继续播放 ${formatDuration(Duration(milliseconds: pr.positionMs))}';
        }
      }
    } else {
      allPaths = [for (final e in allEps) e.path];
      watched = allPaths.isNotEmpty && allPaths.every((p) => progress[p]?.finished == true);
      if (allEps.isNotEmpty) {
        final e = allEps[resumeIdx];
        playPath = e.path;
        final code = episodeLabel(e).split(' · ').first;
        playLabel = progress.isEmpty ? '播放 $code' : '继续 $code';
      }
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: const _CircleBack(),
      ),
      body: Stack(children: [
        // 背景大图
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: backdropH,
          child: Stack(fit: StackFit.expand, children: [
            MediaImage(
              path: d.fanart ?? d.poster,
              decodeWidth: size.width,
              alignment: Alignment.topCenter,
              placeholder: const SizedBox.shrink(),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.45, 1],
                  colors: [
                    theme.scaffoldBackgroundColor.withValues(alpha: 0.35),
                    theme.scaffoldBackgroundColor.withValues(alpha: 0.6),
                    theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
            ),
          ]),
        ),
        CustomScrollView(slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverPadding(
              padding: EdgeInsets.fromLTRB(wide ? 40 : 20, wide ? 96 : 64, wide ? 40 : 20, 0),
              sliver: SliverToBoxAdapter(
                child: _Header(
                  d: d,
                  wide: wide,
                  playLabel: playLabel,
                  onPlay: playPath == null ? null : () => _play(d, playPath!),
                  watched: watched,
                  onToggleWatched: allPaths.isEmpty ? null : () => _setWatched(allPaths, !watched),
                ),
              ),
            ),
          ),
          if (d.actors.isNotEmpty) ...[
            _sectionTitle(context, '演职人员', wide),
            SliverToBoxAdapter(child: _Cast(actors: d.actors, wide: wide)),
          ],
          if (d.kind == MediaKind.show && d.seasons.isNotEmpty) ...[
            _sectionTitle(context, '剧集', wide),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20, vertical: 4),
                  children: [
                    for (final s in d.seasons)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${s.label} · ${s.episodeCount}'),
                          selected: s.season == season,
                          showCheckmark: false,
                          onSelected: (_) => setState(() => _season = s.season),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (season != null)
              _EpisodeGrid(
                itemId: d.id,
                season: season,
                wide: wide,
                progress: progress,
                onPlay: (path) => _play(d, path),
                onToggleWatched: (path, w) => _setWatched([path], w),
              ),
          ],
          if (d.kind == MediaKind.movie && d.files.isNotEmpty) ...[
            _sectionTitle(context, d.files.length > 1 ? '版本 / 文件' : '文件', wide),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 8),
              sliver: SliverList.list(children: [
                for (final f in d.files)
                  ListTile(
                    leading: const Icon(Icons.movie_outlined),
                    title: Text(p.basename(f.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      formatSize(f.size),
                      if (progress[f.path]?.finished == true) '已看完',
                      if (progress[f.path] case final pr? when !pr.finished && pr.positionMs > 0)
                        '看到 ${formatDuration(Duration(milliseconds: pr.positionMs))}',
                    ].join(' · ')),
                    trailing: const Icon(Icons.play_circle_outline),
                    onTap: () => _play(d, f.path),
                  ),
              ]),
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(wide ? 40 : 20, 24, wide ? 40 : 20, 40),
              child: Text(d.dir,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, bool wide) => SliverPadding(
        padding: EdgeInsets.fromLTRB(wide ? 40 : 20, 28, 20, 10),
        sliver: SliverToBoxAdapter(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
      );
}

class _CircleBack extends StatelessWidget {
  const _CircleBack();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(6),
        child: IconButton.filledTonal(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: '返回',
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({
    required this.d,
    required this.wide,
    required this.playLabel,
    required this.onPlay,
    required this.watched,
    required this.onToggleWatched,
  });
  final MediaDetail d;
  final bool wide;
  final String playLabel;
  final VoidCallback? onPlay;
  final bool watched;
  final VoidCallback? onToggleWatched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posterW = wide ? 230.0 : 118.0;
    final poster = Container(
      width: posterW,
      height: posterW * 1.5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 24, offset: Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: MediaImage(
        path: d.poster,
        decodeWidth: posterW,
        placeholder: PosterPlaceholder(title: d.title),
      ),
    );

    final meta = [
      if (d.year != null) '${d.year}',
      if (d.runtime != null && d.runtime! > 0) formatRuntime(d.runtime!),
      if (d.mpaa != null) d.mpaa!,
      if (d.kind == MediaKind.show && d.seasons.isNotEmpty)
        '${d.seasons.where((s) => s.season > 0).length} 季',
      if (d.countries.isNotEmpty) d.countries.take(2).join(' / '),
    ];

    final titleBlock = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (d.logo != null && wide)
        SizedBox(
          height: 90,
          width: 360,
          child: MediaImage(
            path: d.logo,
            decodeWidth: 360,
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            placeholder: Text(d.title, style: theme.textTheme.headlineMedium),
          ),
        )
      else
        Text(d.title,
            style: (wide ? theme.textTheme.displaySmall : theme.textTheme.headlineSmall)
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.15)),
      if (d.originalTitle != null && d.originalTitle != d.title)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(d.originalTitle!,
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      const SizedBox(height: 10),
      Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (d.rating != null)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.star_rounded, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 3),
            Text(d.rating!.toStringAsFixed(1),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        for (final m in meta)
          Text(m, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ]),
    ]);

    final actions = Wrap(spacing: 12, runSpacing: 12, children: [
      FilledButton.icon(
        onPressed: onPlay,
        icon: const Icon(Icons.play_arrow_rounded),
        label: Text(playLabel),
        style: FilledButton.styleFrom(minimumSize: const Size(140, 48)),
      ),
      OutlinedButton.icon(
        onPressed: onToggleWatched,
        icon: Icon(watched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded),
        label: Text(watched ? '已看过' : '标记已看'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
      ),
    ]);

    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (d.genres.isNotEmpty) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final g in d.genres)
            Chip(label: Text(g), visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 16),
      ],
      actions,
      if (d.tagline != null) ...[
        const SizedBox(height: 20),
        Text('“${d.tagline}”', style: theme.textTheme.titleMedium?.copyWith(fontStyle: FontStyle.italic)),
      ],
      if (d.plot != null) ...[
        const SizedBox(height: 16),
        _ExpandableText(d.plot!),
      ],
      const SizedBox(height: 16),
      _credit(context, '导演', d.directors),
      _credit(context, '编剧', d.writers),
      _credit(context, '出品', d.studios),
      if (d.setName != null) _credit(context, '合集', [d.setName!]),
      if (d.premiered != null) _credit(context, d.kind == MediaKind.show ? '首播' : '上映', [d.premiered!]),
      if (d.status != null) _credit(context, '状态', [_status(d.status!)]),
    ]);

    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        poster,
        const SizedBox(width: 36),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 8),
              titleBlock,
              const SizedBox(height: 20),
              body,
            ]),
          ),
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        poster,
        const SizedBox(width: 16),
        Expanded(child: titleBlock),
      ]),
      const SizedBox(height: 20),
      body,
    ]);
  }

  static String _status(String s) => switch (s.toLowerCase()) {
        'ended' => '已完结',
        'continuing' || 'returning series' => '连载中',
        'canceled' || 'cancelled' => '已取消',
        _ => s,
      };

  Widget _credit(BuildContext context, String label, List<String> values) {
    if (values.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 48,
          child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
        ),
        Expanded(child: Text(values.join('、'), style: theme.textTheme.bodyMedium)),
      ]),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);
  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6);
    return GestureDetector(
      onTap: () => setState(() => _open = !_open),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: Text(widget.text,
            style: style, maxLines: _open ? null : 4, overflow: _open ? null : TextOverflow.ellipsis),
      ),
    );
  }
}

class _Cast extends StatelessWidget {
  const _Cast({required this.actors, required this.wide});
  final List<ActorRow> actors;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const w = 92.0;
    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 20),
        itemCount: actors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final a = actors[i];
          return SizedBox(
            width: w,
            child: Column(children: [
              ClipOval(
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: MediaImage(
                    path: a.thumb,
                    decodeWidth: 80,
                    placeholder: PosterPlaceholder(title: a.name),
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(a.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              if (a.role != null)
                Text(a.role!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ]),
          );
        },
      ),
    );
  }
}

class _EpisodeGrid extends ConsumerWidget {
  const _EpisodeGrid({
    required this.itemId,
    required this.season,
    required this.wide,
    required this.progress,
    required this.onPlay,
    required this.onToggleWatched,
  });
  final int itemId;
  final int season;
  final bool wide;
  final Map<String, PlaybackProgress> progress;
  final void Function(String path) onPlay;
  final void Function(String path, bool watched) onToggleWatched;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eps = ref.watch(episodesProvider((itemId, season)));
    final theme = Theme.of(context);
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(wide ? 40 : 20, 8, wide ? 40 : 20, 0),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 560,
          mainAxisExtent: 104,
          crossAxisSpacing: 16,
          mainAxisSpacing: 12,
        ),
        itemCount: eps.length,
        itemBuilder: (context, i) {
          final e = eps[i];
          return Material(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onPlay(e.path),
              onLongPress: () => onToggleWatched(e.path, progress[e.path]?.finished != true),
              child: Row(children: [
                SizedBox(
                  width: 104 * 16 / 9,
                  height: 104,
                  child: Stack(fit: StackFit.expand, children: [
                    MediaImage(
                      path: e.thumb,
                      decodeWidth: 185,
                      placeholder: PosterPlaceholder(title: e.title, icon: Icons.play_arrow_rounded),
                    ),
                    if (progress[e.path] case final pr?)
                      if (pr.finished)
                        const Positioned(
                          top: 6,
                          right: 6,
                          child: Icon(Icons.check_circle_rounded, size: 20, color: Colors.white),
                        )
                      else if (pr.positionMs > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: pr.fraction,
                            minHeight: 3,
                            color: theme.colorScheme.primary,
                            backgroundColor: Colors.black45,
                          ),
                        ),
                    if (e.episode != null)
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('E${e.episode}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ]),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Text(
                          e.plot ?? [if (e.aired != null) e.aired!, formatSize(e.size)].join(' · '),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

String formatRuntime(int minutes) =>
    minutes >= 60 ? '${minutes ~/ 60} 小时 ${minutes % 60} 分钟' : '$minutes 分钟';

String formatSize(int bytes) {
  if (bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i >= 3 ? 2 : 0)} ${units[i]}';
}
