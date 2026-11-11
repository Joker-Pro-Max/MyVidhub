import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../widgets/poster_card.dart';
import '../detail/detail_page.dart';
import '../home/empty_library.dart';

/// 电影 / 剧集海报墙：类型筛选 + 排序。
class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, required this.kind});
  final MediaKind kind;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  SortOrder _sort = SortOrder.added;
  String? _genre;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = ref.watch(
        itemsProvider((kind: widget.kind, sort: _sort, genre: _genre, limit: null)));
    final genres = ref.watch(genresProvider(widget.kind));
    final hasSources = ref.watch(sourcesProvider).isNotEmpty;
    final label = widget.kind == MediaKind.movie ? '电影' : '剧集';

    if (!hasSources) return const EmptyLibrary();

    return CustomScrollView(
      key: PageStorageKey('library-${widget.kind.name}'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
            child: Row(children: [
              Text(label, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Text('${items.length}', style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
              const Spacer(),
              PopupMenuButton<SortOrder>(
                tooltip: '排序',
                initialValue: _sort,
                onSelected: (s) => setState(() => _sort = s),
                itemBuilder: (_) => [
                  for (final s in SortOrder.values) PopupMenuItem(value: s, child: Text(s.label)),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.sort_rounded, size: 20),
                    const SizedBox(width: 6),
                    Text(_sort.label),
                  ]),
                ),
              ),
            ]),
          ),
        ),
        if (genres.isNotEmpty)
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                children: [
                  _chip('全部', _genre == null, () => setState(() => _genre = null)),
                  for (final g in genres)
                    _chip(g, _genre == g, () => setState(() => _genre = _genre == g ? null : g)),
                ],
              ),
            ),
          ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                ref.watch(scanProvider).running ? '正在扫描…' : '没有找到$label',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          )
        else
          PosterGrid(items: items, onTap: (m) => DetailPage.open(context, m.id)),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
        ),
      );
}
