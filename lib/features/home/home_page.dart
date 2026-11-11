import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../widgets/poster_card.dart';
import '../../widgets/media_image.dart';
import '../detail/detail_page.dart';
import '../player/play_item.dart';
import '../player/player_page.dart';
import 'empty_library.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key, required this.onSeeAll});

  final void Function(MediaKind) onSeeAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final scan = ref.watch(scanProvider);
    if (sources.isEmpty) return const EmptyLibrary();

    final movies = ref.watch(itemsProvider(
        (kind: MediaKind.movie, sort: SortOrder.added, genre: null, limit: 24)));
    final shows = ref.watch(itemsProvider(
        (kind: MediaKind.show, sort: SortOrder.added, genre: null, limit: 24)));
    final cont = ref.watch(continueWatchingProvider);
    final topRated = ref.watch(itemsProvider(
        (kind: MediaKind.movie, sort: SortOrder.rating, genre: null, limit: 24)))
        .where((m) => m.rating != null)
        .toList();

    return CustomScrollView(
      key: const PageStorageKey('home'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text('首页',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
        if (scan.running) const SliverToBoxAdapter(child: ScanBanner()),
        if (movies.isEmpty && shows.isEmpty && !scan.running)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('媒体库为空：文件夹中没有识别到视频文件')),
          ),
        if (cont.isNotEmpty) _ContinueShelf(items: cont),
        if (movies.isNotEmpty)
          _Shelf(title: '最近添加的电影', items: movies, onMore: () => onSeeAll(MediaKind.movie)),
        if (shows.isNotEmpty)
          _Shelf(title: '最近添加的剧集', items: shows, onMore: () => onSeeAll(MediaKind.show)),
        if (topRated.length >= 3)
          _Shelf(title: '高分电影', items: topRated, onMore: () => onSeeAll(MediaKind.movie)),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.title, required this.items, required this.onMore});

  final String title;
  final List<MediaSummary> items;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final width = PosterGrid.targetWidth(MediaQuery.sizeOf(context).width);
    return SliverToBoxAdapter(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            TextButton(onPressed: onMore, child: const Text('全部')),
          ]),
        ),
        SizedBox(
          height: PosterCard.heightFor(width) + 8,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) => PosterCard(
              item: items[i],
              width: width,
              onTap: () => DetailPage.open(context, items[i].id),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ContinueShelf extends ConsumerWidget {
  const _ContinueShelf({required this.items});
  final List<ContinueItem> items;

  void _play(BuildContext context, WidgetRef ref, ContinueItem c) {
    final db = ref.read(dbProvider);
    if (c.kind == MediaKind.movie) {
      final d = db.detail(c.itemId);
      if (d != null) PlayerPage.open(context, ref, movieQueue(d, c.path));
    } else {
      final queue = showQueue(db, c.itemId, c.title);
      PlayerPage.open(context, ref, queue, queue.indexWhere((q) => q.path == c.path).clamp(0, queue.length));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenW = MediaQuery.sizeOf(context).width;
    final w = screenW < 600 ? 240.0 : 300.0;
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Text('继续观看', style: theme.textTheme.titleLarge),
        ),
        SizedBox(
          height: w * 9 / 16 + 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final c = items[i];
              final left = c.durationMs > 0 ? Duration(milliseconds: c.durationMs - c.positionMs) : null;
              return SizedBox(
                width: w,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _play(context, ref, c),
                  onLongPress: () => DetailPage.open(context, c.itemId),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: w,
                        height: w * 9 / 16,
                        child: Stack(fit: StackFit.expand, children: [
                          MediaImage(
                            path: c.fanart ?? c.poster,
                            decodeWidth: w,
                            placeholder: PosterPlaceholder(title: c.title),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black54],
                              ),
                            ),
                          ),
                          Center(
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                            ),
                          ),
                          if (left != null && c.positionMs > 0)
                            Positioned(
                              right: 8,
                              bottom: 10,
                              child: Text(left.inMinutes < 1 ? '即将看完' : '剩余 ${left.inMinutes} 分钟',
                                  style: const TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: c.fraction,
                              minHeight: 4,
                              color: theme.colorScheme.primary,
                              backgroundColor: Colors.white24,
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                    if (c.episodeLabel != null)
                      Text(c.episodeLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class ScanBanner extends ConsumerWidget {
  const ScanBanner({super.key, this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 8)});
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('正在扫描媒体库 · 已发现 ${scan.found} 个条目', style: theme.textTheme.bodyMedium),
                if (scan.dir != null)
                  Text(scan.dir!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ]),
            ),
            TextButton(onPressed: () => ref.read(scanProvider.notifier).cancel(), child: const Text('取消')),
          ]),
        ),
      ),
    );
  }
}
