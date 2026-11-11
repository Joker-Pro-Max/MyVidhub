import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../services/source_registry.dart';
import '../../ui/artwork_tint.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../widgets/media_image.dart';
import '../player/play_actions.dart';
import '../player/play_item.dart';
import '../search/actor_page.dart';
import '../../widgets/poster_shelf.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key, required this.id});
  final int id;

  static Future<void> open(BuildContext context, int id) =>
      Navigator.of(context).push(FadeRoute(builder: (_) => DetailPage(id: id)));

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  int? _season;

  void _play(MediaDetail d, String path) => playItem(context, ref, d.id, path: path);

  void _setWatched(List<String> paths, bool watched, {String? message}) {
    ref.read(dbProvider).setWatched(paths, watched);
    ref.read(libraryRevisionProvider.notifier).bump();
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
    }
  }

  void _toggleFavorite(int id, bool now) {
    ref.read(dbProvider).setFavorite(id, !now);
    ref.read(libraryRevisionProvider.notifier).bump();
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(detailProvider(widget.id));
    if (d == null) {
      return Scaffold(
        body: Center(
          child: Text('这个条目已不存在', style: TypeScale.body.copyWith(color: Palette.text2)),
        ),
      );
    }
    final ff = FormFactor.of(context);
    final g = ff.gutter;
    final progress = ref.watch(itemProgressProvider(d.id));
    final favorite = ref.watch(isFavoriteProvider(d.id));
    final sameSet = ref.watch(sameSetProvider(d.id));
    final similar = ref.watch(similarProvider(d.id));
    final allEps = d.kind == MediaKind.show ? ref.watch(allEpisodesProvider(d.id)) : const <EpisodeRow>[];
    final resumeIdx = resumeEpisodeIndex(allEps, progress);
    final season =
        _season ??
        (allEps.isNotEmpty
            ? allEps[resumeIdx].season
            : (d.seasons.where((s) => s.season > 0).firstOrNull ?? d.seasons.firstOrNull)?.season);

    // 播放按钮文案与目标
    var playLabel = '播放';
    String? playPath;
    double? playProgress;
    Duration? remaining;
    late final List<String> allPaths;
    late final bool watched;
    if (d.kind == MediaKind.movie) {
      allPaths = [for (final f in d.files) f.path];
      watched = allPaths.any((p) => progress[p]?.finished == true);
      if (d.files.isNotEmpty) {
        playPath = d.files.first.path;
        final pr = progress[playPath];
        if (pr != null && !pr.finished && pr.positionMs > 30000) {
          playLabel = '继续播放';
          playProgress = pr.fraction;
          remaining = Duration(milliseconds: pr.durationMs - pr.positionMs);
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
        final pr = progress[e.path];
        if (pr != null && !pr.finished && pr.positionMs > 0) {
          playProgress = pr.fraction;
          remaining = Duration(milliseconds: pr.durationMs - pr.positionMs);
        }
      }
    }

    return Scaffold(
      body: FutureBuilder<Color?>(
        future: ArtworkTint.of(d.fanart ?? d.poster),
        builder: (context, tintSnap) {
          final tint = Color.lerp(Palette.bg, tintSnap.data ?? Palette.bg, 0.55)!;
          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _Hero(
                      d: d,
                      tint: tint,
                      playLabel: playLabel,
                      playProgress: playProgress,
                      remaining: remaining,
                      onPlay: playPath == null ? null : () => _play(d, playPath!),
                      watched: watched,
                      onToggleWatched: allPaths.isEmpty
                          ? null
                          : () => _setWatched(allPaths, !watched, message: watched ? '已标为未看' : '已标为看过'),
                      favorite: favorite,
                      onToggleFavorite: () => _toggleFavorite(d.id, favorite),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.base),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [tint, Palette.bg],
                        ),
                      ),
                      padding: EdgeInsets.fromLTRB(g, 8, g, 40),
                      child: _Info(d: d),
                    ),
                  ),
                  if (d.kind == MediaKind.show && d.seasons.isNotEmpty && season != null) ...[
                    SliverToBoxAdapter(
                      child: SectionHeader(
                        title: '剧集',
                        trailing: _SeasonMenu(
                          label: d.seasons.where((s) => s.season == season).firstOrNull?.label ?? '本季',
                          paths: [
                            for (final e in allEps)
                              if (e.season == season) e.path,
                          ],
                          progress: progress,
                          onSet: (paths, w, msg) => _setWatched(paths, w, message: msg),
                        ),
                      ),
                    ),
                    if (d.seasons.length > 1)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: FilterPills<int>(
                            items: [for (final s in d.seasons) s.season],
                            selected: season,
                            label: (n) => d.seasons.firstWhere((s) => s.season == n).label,
                            onSelect: (n) => setState(() => _season = n),
                            padding: EdgeInsets.symmetric(horizontal: g - 4),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: _EpisodeRow(
                        key: ValueKey('season-$season'),
                        itemId: d.id,
                        season: season,
                        progress: progress,
                        focusPath: allEps.isEmpty ? null : allEps[resumeIdx].path,
                        onPlay: (path) => _play(d, path),
                        onToggleWatched: (path, w) => _setWatched([path], w, message: w ? '已标为看过' : '已标为未看'),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                  if (d.actors.isNotEmpty) ...[
                    const SliverToBoxAdapter(child: SectionHeader(title: '演职人员')),
                    SliverToBoxAdapter(child: _Cast(actors: d.actors)),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                  if (sameSet.isNotEmpty)
                    SliverToBoxAdapter(
                      child: PosterShelf(
                        title: d.setName ?? '同系列',
                        items: sameSet,
                        onTap: (m) => DetailPage.open(context, m.id),
                      ),
                    ),
                  if (similar.length >= 2)
                    SliverToBoxAdapter(
                      child: PosterShelf(title: '更多类似', items: similar, onTap: (m) => DetailPage.open(context, m.id)),
                    ),
                  if (d.kind == MediaKind.movie && d.files.isNotEmpty)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: g),
                      sliver: SliverToBoxAdapter(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: GroupedList(
                              header: d.files.length > 1 ? '版本' : '文件',
                              children: [
                                for (final f in d.files)
                                  SettingRow(
                                    icon: Icons.movie_outlined,
                                    title: p.basename(f.path),
                                    subtitle: [
                                      formatSize(f.size),
                                      if (progress[f.path]?.finished == true) '已看完',
                                      if (progress[f.path] case final pr? when !pr.finished && pr.positionMs > 0)
                                        '看到 ${formatDuration(Duration(milliseconds: pr.positionMs))}',
                                    ].join('  ·  '),
                                    trailing: const Icon(Icons.play_arrow_rounded, color: Palette.text2),
                                    onTap: () => _play(d, f.path),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(g, 32, g, 48 + MediaQuery.paddingOf(context).bottom),
                    sliver: SliverToBoxAdapter(
                      child: Text(SourceRegistry.instance.displayPath(d.dir), style: TypeScale.caption.copyWith(color: Palette.text3)),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 12,
                left: g - 8,
                child: RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '返回',
                  overArtwork: true,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.d,
    required this.tint,
    required this.playLabel,
    required this.onPlay,
    required this.watched,
    required this.onToggleWatched,
    required this.favorite,
    required this.onToggleFavorite,
    this.playProgress,
    this.remaining,
  });

  final bool favorite;
  final VoidCallback onToggleFavorite;
  final MediaDetail d;
  final Color tint;
  final String playLabel;
  final VoidCallback? onPlay;
  final bool watched;
  final VoidCallback? onToggleWatched;
  final double? playProgress;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ff = FormFactor.of(context);
    final g = ff.gutter;
    final height = ff.isPhone ? (size.width * 1.2).clamp(440.0, 600.0) : (size.height * 0.74).clamp(460.0, 780.0);
    final hasBackdrop = d.fanart != null;

    final meta = [
      if (d.year != null) '${d.year}',
      ...d.genres.take(3),
      if (d.runtime != null && d.runtime! > 0) formatRuntime(d.runtime!),
      if (d.kind == MediaKind.show && d.seasons.isNotEmpty) '${d.seasons.where((s) => s.season > 0).length} 季',
      if (d.mpaa != null) d.mpaa!,
    ].join('  ·  ');

    final title = d.logo != null
        ? SizedBox(
            height: ff.isPhone ? 80 : 120,
            width: ff.isPhone ? 280 : 460,
            child: MediaImage(
              path: d.logo,
              decodeWidth: 460,
              fit: BoxFit.contain,
              alignment: Alignment.bottomLeft,
              placeholder: _titleText(ff),
            ),
          )
        : _titleText(ff);

    final textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        if (d.originalTitle != null && d.originalTitle != d.title) ...[
          const SizedBox(height: 6),
          Text(
            d.originalTitle!,
            style: TypeScale.headline.copyWith(color: Palette.text2, fontWeight: FontWeight.w500),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 14,
          runSpacing: 6,
          children: [
            if (d.rating != null)
              Text('★ ${d.rating!.toStringAsFixed(1)}', style: TypeScale.callout.copyWith(fontSize: 15)),
            if (meta.isNotEmpty) Text(meta, style: TypeScale.callout.copyWith(color: Palette.text2, fontSize: 15)),
          ],
        ),
        if (playProgress != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(width: 180, child: ProgressHairline(value: playProgress!)),
              const SizedBox(width: 12),
              if (remaining != null)
                Text(remaining!.inMinutes < 1 ? '即将看完' : '剩余 ${remaining!.inMinutes} 分钟', style: TypeScale.caption),
            ],
          ),
        ],
        const SizedBox(height: 22),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PillButton(label: playLabel, icon: Icons.play_arrow_rounded, onPressed: onPlay),
            const SizedBox(width: 12),
            RoundIconButton(
              icon: Icons.check_rounded,
              tooltip: watched ? '标记为未看' : '标记为已看',
              selected: watched,
              size: 48,
              onPressed: onToggleWatched,
            ),
            const SizedBox(width: 12),
            RoundIconButton(
              icon: favorite ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              tooltip: favorite ? '取消收藏' : '收藏',
              selected: favorite,
              size: 48,
              onPressed: onToggleFavorite,
            ),
          ],
        ),
      ],
    );

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasBackdrop)
            MediaImage(path: d.fanart, decodeWidth: size.width, alignment: const Alignment(0, -0.4))
          else if (d.poster != null)
            // 没有剧照：用海报做大面积虚化背景
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 48, sigmaY: 48, tileMode: TileMode.decal),
              child: Opacity(opacity: 0.55, child: MediaImage(path: d.poster, decodeWidth: 200)),
            ),
          if (!ff.isPhone)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0, 0.62],
                  colors: [Palette.shade(0.72), Palette.shade(0)],
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.3, 0.8, 0.97],
                colors: [Palette.shade(0.35), Palette.shade(0), tint.withValues(alpha: 0.85), tint],
              ),
            ),
          ),
          Positioned(
            left: g,
            right: g,
            bottom: 24,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!hasBackdrop && d.poster != null) ...[
                  Container(
                    width: ff.isPhone ? 110 : 190,
                    height: (ff.isPhone ? 110 : 190) * 1.5,
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.poster),
                      border: Border.all(color: Palette.hairline),
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.poster),
                      boxShadow: [BoxShadow(color: Palette.shade(0.6), blurRadius: 30, offset: const Offset(0, 14))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.poster),
                      child: MediaImage(
                        path: d.poster,
                        decodeWidth: 190,
                        placeholder: PosterPlaceholder(title: d.title),
                      ),
                    ),
                  ),
                  SizedBox(width: ff.isPhone ? 16 : 32),
                ],
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: textBlock),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _titleText(FormFactor ff) => Text(
    d.title,
    maxLines: 3,
    overflow: TextOverflow.ellipsis,
    style: ff.isPhone ? TypeScale.largeTitle.copyWith(fontSize: 32) : TypeScale.display.copyWith(fontSize: 52),
  );
}

/// 简介 + 演职信息。宽屏左右两栏，窄屏上下。
class _Info extends StatelessWidget {
  const _Info({required this.d});
  final MediaDetail d;

  static String _status(String s) => switch (s.toLowerCase()) {
    'ended' => '已完结',
    'continuing' || 'returning series' => '连载中',
    'canceled' || 'cancelled' => '已取消',
    _ => s,
  };

  @override
  Widget build(BuildContext context) {
    final ff = FormFactor.of(context);
    final credits = <(String, String)>[
      if (d.directors.isNotEmpty) ('导演', d.directors.join('、')),
      if (d.writers.isNotEmpty) ('编剧', d.writers.join('、')),
      if (d.studios.isNotEmpty) ('出品', d.studios.join('、')),
      if (d.countries.isNotEmpty) ('地区', d.countries.join('、')),
      if (d.setName != null) ('合集', d.setName!),
      if (d.premiered != null) (d.kind == MediaKind.show ? '首播' : '上映', d.premiered!),
      if (d.status != null) ('状态', _status(d.status!)),
    ];

    final story = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (d.tagline != null) ...[
          Text(d.tagline!, style: TypeScale.headline.copyWith(fontSize: 18)),
          const SizedBox(height: 12),
        ],
        if (d.plot != null) _ExpandableText(d.plot!),
      ],
    );

    final creditList = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (k, v) in credits)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k, style: TypeScale.overline),
                const SizedBox(height: 3),
                Text(v, style: TypeScale.callout.copyWith(color: Palette.text2)),
              ],
            ),
          ),
      ],
    );

    if (d.plot == null && d.tagline == null && credits.isEmpty) return const SizedBox(height: 8);

    if (ff.isPhone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          story,
          if (credits.isNotEmpty) ...[const SizedBox(height: 24), creditList],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: story),
        ),
        const SizedBox(width: 56),
        Expanded(flex: 2, child: creditList),
      ],
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
    return LayoutBuilder(
      builder: (context, c) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: TypeScale.body),
          maxLines: 4,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: c.maxWidth);
        final overflow = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: TypeScale.body.copyWith(color: Palette.text.withValues(alpha: 0.88)),
              maxLines: _open ? null : 4,
              overflow: _open ? null : TextOverflow.ellipsis,
            ),
            if (overflow)
              Pressable(
                onTap: () => setState(() => _open = !_open),
                radius: 6,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(_open ? '收起' : '更多', style: TypeScale.callout.copyWith(fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Cast extends StatelessWidget {
  const _Cast({required this.actors});
  final List<ActorRow> actors;

  @override
  Widget build(BuildContext context) {
    final g = FormFactor.of(context).gutter;
    return SizedBox(
      height: 136,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: g),
        itemCount: actors.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, i) {
          final a = actors[i];
          return Pressable(
            onTap: () => ActorPage.open(context, a.name),
            radius: 12,
            hoverOverlay: false,
            semanticLabel: a.name,
            child: SizedBox(
              width: 84,
              child: Column(
                children: [
                  PersonAvatar(name: a.name, thumb: a.thumb, size: 76),
                  const SizedBox(height: 10),
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TypeScale.callout.copyWith(fontSize: 13),
                  ),
                  if (a.role != null)
                    Text(
                      a.role!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TypeScale.caption.copyWith(fontSize: 12),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 剧集区标题右侧的"…"：整季标为已看 / 未看。
class _SeasonMenu extends StatelessWidget {
  const _SeasonMenu({required this.label, required this.paths, required this.progress, required this.onSet});
  final String label;
  final List<String> paths;
  final Map<String, PlaybackProgress> progress;
  final void Function(List<String> paths, bool watched, String message) onSet;

  @override
  Widget build(BuildContext context) {
    final allWatched = paths.isNotEmpty && paths.every((p) => progress[p]?.finished == true);
    return PopupMenuButton<bool>(
      tooltip: '更多',
      offset: const Offset(0, 40),
      onSelected: (w) => onSet(paths, w, w ? '$label已全部标为看过' : '$label已标为未看'),
      itemBuilder: (_) => [
        PopupMenuItem(value: true, enabled: !allWatched, child: Text('将$label标为看过')),
        PopupMenuItem(value: false, enabled: paths.any((p) => progress.containsKey(p)), child: Text('将$label标为未看')),
      ],
      child: const SizedBox(width: 44, height: 36, child: Icon(Icons.more_horiz_rounded, color: Palette.text2)),
    );
  }
}

/// 一季的剧集：横向滚动的 16:9 卡片，自动滚到该续看的那一集。
class _EpisodeRow extends ConsumerStatefulWidget {
  const _EpisodeRow({
    super.key,
    required this.itemId,
    required this.season,
    required this.progress,
    required this.focusPath,
    required this.onPlay,
    required this.onToggleWatched,
  });
  final int itemId;
  final int season;
  final Map<String, PlaybackProgress> progress;
  final String? focusPath;
  final void Function(String path) onPlay;
  final void Function(String path, bool watched) onToggleWatched;

  @override
  ConsumerState<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends ConsumerState<_EpisodeRow> {
  ScrollController? _scroll;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eps = ref.watch(episodesProvider((widget.itemId, widget.season)));
    final ff = FormFactor.of(context);
    final w = ff.isPhone ? 250.0 : 300.0;
    const gap = 18.0;
    final focus = eps.indexWhere((e) => e.path == widget.focusPath);
    _scroll ??= ScrollController(initialScrollOffset: focus > 0 ? (focus * (w + gap)) - 0 : 0);

    return SizedBox(
      height: w * 9 / 16 + 104,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.symmetric(horizontal: ff.gutter),
        itemCount: eps.length,
        separatorBuilder: (_, _) => const SizedBox(width: gap),
        itemBuilder: (context, i) {
          final e = eps[i];
          final pr = widget.progress[e.path];
          return SizedBox(
            width: w,
            child: Pressable(
              onTap: () => widget.onPlay(e.path),
              onLongPress: () => widget.onToggleWatched(e.path, pr?.finished != true),
              radius: Radii.card,
              hoverOverlay: false,
              semanticLabel: '播放 ${e.title}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: w,
                    height: w * 9 / 16,
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.card),
                      border: Border.all(color: Palette.hairline),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.card),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          MediaImage(
                            path: e.thumb,
                            decodeWidth: w,
                            placeholder: PosterPlaceholder(title: e.title, icon: Icons.play_arrow_rounded),
                          ),
                          if (pr != null && pr.finished) const Positioned(top: 10, right: 10, child: WatchedMark()),
                          if (pr != null && !pr.finished && pr.positionMs > 0)
                            Positioned(left: 10, right: 10, bottom: 10, child: ProgressHairline(value: pr.fraction)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    e.episode == null ? (e.season == 0 ? '特别篇' : '其他') : '第 ${e.episode} 集',
                    style: TypeScale.overline,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.callout.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.plot ?? [if (e.aired != null) e.aired!, formatSize(e.size)].join('  ·  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.caption.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String formatRuntime(int minutes) => minutes >= 60 ? '${minutes ~/ 60} 小时 ${minutes % 60} 分钟' : '$minutes 分钟';

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
