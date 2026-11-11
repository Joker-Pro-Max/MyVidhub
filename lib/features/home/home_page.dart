import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../services/source_registry.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../app/app_settings.dart';
import '../../widgets/av_blur.dart';
import '../../widgets/media_image.dart';
import '../../widgets/poster_shelf.dart';
import '../detail/detail_page.dart';
import '../player/play_actions.dart';
import 'empty_library.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key, required this.onSeeAll});

  final void Function(MediaKind) onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final scan = ref.watch(scanProvider);
    final insets = ShellInsets.of(context);
    if (sources.isEmpty) return const EmptyLibrary();

    final movies = ref.watch(itemsProvider((kind: MediaKind.movie, sort: SortOrder.added, genre: null, limit: 24, filter: WatchFilter.all)));
    final shows = ref.watch(itemsProvider((kind: MediaKind.show, sort: SortOrder.added, genre: null, limit: 24, filter: WatchFilter.all)));
    final cont = ref.watch(continueWatchingProvider);
    final favs = ref.watch(favoritesProvider);
    final topRated = ref
        .watch(itemsProvider((kind: MediaKind.movie, sort: SortOrder.rating, genre: null, limit: 24, filter: WatchFilter.all)))
        .where((m) => m.rating != null)
        .toList();

    // AV 模糊显示开启时，首页大图不放 AV（整屏模糊图不好看）
    final hideAv = ref.watch(appSettingsProvider).blurAv;
    final heroes = _heroEntries(
      cont.where((c) => !hideAv || !c.isAv).toList(),
      movies.where((m) => !hideAv || !m.isAv).toList(),
      shows.where((m) => !hideAv || !m.isAv).toList(),
    );
    final g = FormFactor.of(context).gutter;

    return CustomScrollView(
      key: const PageStorageKey('home'),
      slivers: [
        if (heroes.isNotEmpty)
          SliverToBoxAdapter(child: _Hero(entries: heroes))
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(g, insets.top + 8, g, 24),
              child: const Text('首页', style: TypeScale.largeTitle),
            ),
          ),
        if (scan.running) SliverToBoxAdapter(child: ScanBanner(padding: EdgeInsets.fromLTRB(g, 8, g, 24))),
        if (movies.isEmpty && shows.isEmpty && !scan.running)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text('文件夹里还没有识别到视频', style: TypeScale.body.copyWith(color: Palette.text2)),
            ),
          ),
        if (cont.isNotEmpty) _ContinueShelf(items: cont),
        if (favs.isNotEmpty) _shelf(context, '我的收藏', favs),
        if (movies.isNotEmpty) _shelf(context, '最近添加的电影', movies, onMore: () => onSeeAll(MediaKind.movie)),
        if (shows.isNotEmpty) _shelf(context, '最近添加的剧集', shows, onMore: () => onSeeAll(MediaKind.show)),
        if (topRated.length >= 3) _shelf(context, '高分电影', topRated, onMore: () => onSeeAll(MediaKind.movie)),
        SliverToBoxAdapter(child: SizedBox(height: insets.bottom)),
      ],
    );
  }

  static Widget _shelf(BuildContext context, String title, List<MediaSummary> items, {VoidCallback? onMore}) =>
      SliverToBoxAdapter(
        child: PosterShelf(title: title, items: items, onMore: onMore, onTap: (m) => DetailPage.open(context, m.id)),
      );

  /// 顶部大图：先放"继续观看"，再放最近添加里有剧照的，最多 5 个。
  static List<_HeroEntry> _heroEntries(List<ContinueItem> cont, List<MediaSummary> movies, List<MediaSummary> shows) {
    final out = <_HeroEntry>[];
    final seen = <int>{};
    for (final c in cont) {
      if (c.fanart == null || !seen.add(c.itemId)) continue;
      out.add(_HeroEntry(
        itemId: c.itemId,
        title: c.title,
        backdrop: c.fanart!,
        overline: '继续观看',
        meta: c.episodeLabel ?? '',
        progress: c.positionMs > 0 ? c.fraction : null,
        remaining: c.durationMs > 0 ? Duration(milliseconds: c.durationMs - c.positionMs) : null,
        path: c.path,
      ));
      if (out.length >= 2) break;
    }
    final recent = [...movies, ...shows].where((m) => m.fanart != null).toList();
    for (final m in recent) {
      if (out.length >= 5) break;
      if (!seen.add(m.id)) continue;
      out.add(_HeroEntry(
        itemId: m.id,
        title: m.title,
        backdrop: m.fanart!,
        logo: m.logo,
        overline: m.kind == MediaKind.movie ? '最近添加 · 电影' : '最近添加 · 剧集',
        meta: [
          if (m.year != null) '${m.year}',
          ...m.genres.take(2),
          if (m.rating != null) '★ ${m.rating!.toStringAsFixed(1)}',
        ].join('  ·  '),
      ));
    }
    return out;
  }
}

class _HeroEntry {
  const _HeroEntry({
    required this.itemId,
    required this.title,
    required this.backdrop,
    required this.overline,
    required this.meta,
    this.logo,
    this.progress,
    this.remaining,
    this.path,
  });
  final int itemId;
  final String title;
  final String backdrop;
  final String? logo;
  final String overline;
  final String meta;
  final double? progress;
  final Duration? remaining;
  final String? path;
}

class _Hero extends ConsumerStatefulWidget {
  const _Hero({required this.entries});
  final List<_HeroEntry> entries;

  @override
  ConsumerState<_Hero> createState() => _HeroState();
}

class _HeroState extends ConsumerState<_Hero> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ff = FormFactor.of(context);
    final height = ff.isPhone
        ? (size.width * 1.25).clamp(420.0, 560.0)
        : (size.height * 0.72).clamp(440.0, 760.0);
    final entries = widget.entries;

    return SizedBox(
      height: height,
      child: Stack(children: [
        PageView.builder(
          controller: _page,
          itemCount: entries.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => _HeroPage(entry: entries[i], width: size.width),
        ),
        if (entries.length > 1)
          Positioned(
            right: ff.gutter,
            bottom: 28,
            child: Row(children: [
              for (var i = 0; i < entries.length; i++)
                Pressable(
                  onTap: () => _page.animateToPage(i,
                      duration: Motion.of(context, Motion.base), curve: Motion.curve),
                  radius: 6,
                  hoverOverlay: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.fast),
                      width: i == _index ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index ? Palette.light : Palette.glow(0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
      ]),
    );
  }
}

class _HeroPage extends ConsumerWidget {
  const _HeroPage({required this.entry, required this.width});
  final _HeroEntry entry;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ff = FormFactor.of(context);
    final g = ff.gutter;
    final e = entry;

    return Stack(fit: StackFit.expand, children: [
      MediaImage(path: e.backdrop, decodeWidth: width, alignment: const Alignment(0, -0.3)),
      // 左侧压暗，保证文字可读
      if (!ff.isPhone)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: const [0, 0.6],
              colors: [Palette.shade(0.7), Palette.shade(0)],
            ),
          ),
        ),
      // 底部融入背景
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.35, 0.78, 0.97],
            colors: [Palette.shade(0), Palette.shade(0.72), Palette.bg],
          ),
        ),
      ),
      Positioned(
        left: g,
        right: g,
        bottom: 28,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(e.overline.toUpperCase(), style: TypeScale.overline.copyWith(color: Palette.text2)),
            const SizedBox(height: 10),
            if (e.logo != null)
              SizedBox(
                height: ff.isPhone ? 72 : 104,
                width: ff.isPhone ? 260 : 400,
                child: MediaImage(
                  path: e.logo,
                  decodeWidth: 400,
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomLeft,
                  placeholder: _title(ff),
                ),
              )
            else
              _title(ff),
            if (e.meta.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(e.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.callout.copyWith(color: Palette.text2, fontSize: 15)),
            ],
            if (e.progress != null) ...[
              const SizedBox(height: 14),
              Row(children: [
                SizedBox(width: 180, child: ProgressHairline(value: e.progress!)),
                const SizedBox(width: 12),
                if (e.remaining != null)
                  Text(
                    e.remaining!.inMinutes < 1 ? '即将看完' : '剩余 ${e.remaining!.inMinutes} 分钟',
                    style: TypeScale.caption,
                  ),
              ]),
            ],
            const SizedBox(height: 20),
            Wrap(spacing: 12, runSpacing: 12, children: [
              PillButton(
                label: e.progress != null ? '继续播放' : '播放',
                icon: Icons.play_arrow_rounded,
                onPressed: () => playItem(context, ref, e.itemId, path: e.path),
              ),
              PillButton(
                label: '详情',
                primary: false,
                onPressed: () => DetailPage.open(context, e.itemId),
              ),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Widget _title(FormFactor ff) => Text(
        entry.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: ff.isPhone ? TypeScale.largeTitle.copyWith(fontSize: 32) : TypeScale.display.copyWith(fontSize: 48),
      );
}

class _ContinueShelf extends ConsumerWidget {
  const _ContinueShelf({required this.items});
  final List<ContinueItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ff = FormFactor.of(context);
    final w = ff.isPhone ? 260.0 : 320.0;
    return SliverPadding(
      padding: const EdgeInsets.only(bottom: 36),
      sliver: SliverToBoxAdapter(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader(title: '继续观看'),
          SizedBox(
            height: w * 9 / 16 + 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.symmetric(horizontal: ff.gutter),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 18),
              itemBuilder: (context, i) => _ContinueCard(
                item: items[i],
                width: w,
                onTap: () => playItem(context, ref, items[i].itemId, path: items[i].path),
                onLongPress: () => DetailPage.open(context, items[i].itemId),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.item, required this.width, required this.onTap, required this.onLongPress});
  final ContinueItem item;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = item;
    final left = c.durationMs > 0 ? Duration(milliseconds: c.durationMs - c.positionMs) : null;
    return SizedBox(
      width: width,
      child: Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
        radius: Radii.card,
        hoverOverlay: false,
        semanticLabel: '继续播放 ${c.title}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: width,
            height: width * 9 / 16,
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: Palette.hairline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card),
              child: Stack(fit: StackFit.expand, children: [
                AvBlur(
                  isAv: c.isAv,
                  child: MediaImage(
                    path: c.fanart ?? c.poster,
                    decodeWidth: width,
                    placeholder: PosterPlaceholder(title: c.title),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.45, 1],
                      colors: [Palette.shade(0), Palette.shade(0.8)],
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (left != null && c.positionMs > 0)
                      Text(left.inMinutes < 1 ? '即将看完' : '剩余 ${left.inMinutes} 分钟',
                          style: TypeScale.caption.copyWith(color: Palette.text)),
                    if (c.positionMs > 0) ...[
                      const SizedBox(height: 8),
                      ProgressHairline(value: c.fraction),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.callout),
          if (c.episodeLabel != null) ...[
            const SizedBox(height: 2),
            Text(c.episodeLabel!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.caption),
          ],
        ]),
      ),
    );
  }
}

/// 扫描进度：一行安静的状态，不用卡片。
class ScanBanner extends ConsumerWidget {
  const ScanBanner({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanProvider);
    return Padding(
      padding: padding,
      child: Row(children: [
        const Spinner(),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('正在扫描媒体库 · 已发现 ${scan.found} 个', style: TypeScale.callout),
            if (scan.dir != null)
              Text(SourceRegistry.instance.displayPath(scan.dir!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.caption.copyWith(color: Palette.text3)),
          ]),
        ),
        PillButton(
          label: '取消',
          primary: false,
          compact: true,
          onPressed: () => ref.read(scanProvider.notifier).cancel(),
        ),
      ]),
    );
  }
}
