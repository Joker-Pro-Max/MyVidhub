import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
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
    final items = ref.watch(itemsProvider((kind: widget.kind, sort: _sort, genre: _genre, limit: null)));
    final genres = ref.watch(genresProvider(widget.kind));
    final hasSources = ref.watch(sourcesProvider).isNotEmpty;
    final insets = ShellInsets.of(context);
    final g = FormFactor.of(context).gutter;
    final label = widget.kind == MediaKind.movie ? '电影' : '剧集';

    if (!hasSources) return const EmptyLibrary();

    return CustomScrollView(
      key: PageStorageKey('library-${widget.kind.name}'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(g, insets.top + 8, g - 8, 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(label, style: TypeScale.largeTitle),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${items.length}', style: TypeScale.title.copyWith(color: Palette.text3)),
              ),
              const Spacer(),
              _SortMenu(value: _sort, onChanged: (s) => setState(() => _sort = s)),
            ]),
          ),
        ),
        if (genres.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilterPills<String?>(
                items: [null, ...genres],
                selected: _genre,
                label: (g) => g ?? '全部',
                onSelect: (v) => setState(() => _genre = v),
                padding: EdgeInsets.symmetric(horizontal: g - 4),
              ),
            ),
          ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: ref.watch(scanProvider).running
                  ? const Spinner(size: 24)
                  : Text('没有找到$label', style: TypeScale.body.copyWith(color: Palette.text2)),
            ),
          )
        else
          PosterGrid(items: items, onTap: (m) => DetailPage.open(context, m.id), bottom: insets.bottom),
      ],
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.value, required this.onChanged});
  final SortOrder value;
  final ValueChanged<SortOrder> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<SortOrder>(
        tooltip: '排序',
        initialValue: value,
        onSelected: onChanged,
        offset: const Offset(0, 44),
        itemBuilder: (_) => [
          for (final s in SortOrder.values)
            PopupMenuItem(
              value: s,
              child: Row(children: [
                SizedBox(
                  width: 24,
                  child: s == value ? const Icon(Icons.check_rounded, size: 18, color: Palette.light) : null,
                ),
                Text(s.label),
              ]),
            ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(value.label, style: TypeScale.callout.copyWith(color: Palette.text2)),
            const SizedBox(width: 2),
            const Icon(Icons.unfold_more_rounded, size: 18, color: Palette.text2),
          ]),
        ),
      );
}
