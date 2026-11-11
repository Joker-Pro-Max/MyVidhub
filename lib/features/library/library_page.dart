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
  WatchFilter _filter = WatchFilter.all;
  String? _genre;

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider((kind: widget.kind, sort: _sort, genre: _genre, limit: null, filter: _filter)));
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
              _MenuPicker<WatchFilter>(
                tooltip: '筛选',
                value: _filter,
                values: WatchFilter.values,
                label: (f) => f == WatchFilter.all ? '全部' : f.label,
                icon: Icons.filter_list_rounded,
                highlighted: _filter != WatchFilter.all,
                onChanged: (f) => setState(() => _filter = f),
              ),
              const SizedBox(width: 4),
              _MenuPicker<SortOrder>(
                tooltip: '排序',
                value: _sort,
                values: SortOrder.values,
                label: (s) => s.label,
                icon: Icons.unfold_more_rounded,
                onChanged: (s) => setState(() => _sort = s),
              ),
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
                  : Text(
                      switch (_filter) {
                        WatchFilter.all => '没有找到$label',
                        WatchFilter.unwatched => '这里的$label都看过了',
                        WatchFilter.watched => '还没有看完的$label',
                        WatchFilter.favorite => '还没有收藏$label。在详情页点书签即可收藏。',
                      },
                      style: TypeScale.body.copyWith(color: Palette.text2),
                    ),
            ),
          )
        else
          PosterGrid(items: items, onTap: (m) => DetailPage.open(context, m.id), bottom: insets.bottom),
      ],
    );
  }
}

/// 标题栏右侧的下拉选择（排序 / 筛选）。
class _MenuPicker<T> extends StatelessWidget {
  const _MenuPicker({
    required this.tooltip,
    required this.value,
    required this.values,
    required this.label,
    required this.icon,
    required this.onChanged,
    this.highlighted = false,
  });

  final String tooltip;
  final T value;
  final List<T> values;
  final String Function(T) label;
  final IconData icon;
  final ValueChanged<T> onChanged;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        tooltip: tooltip,
        initialValue: value,
        onSelected: onChanged,
        offset: const Offset(0, 44),
        itemBuilder: (_) => [
          for (final v in values)
            PopupMenuItem(
              value: v,
              child: Row(children: [
                SizedBox(
                  width: 24,
                  child: v == value ? const Icon(Icons.check_rounded, size: 18, color: Palette.light) : null,
                ),
                Text(label(v)),
              ]),
            ),
        ],
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: highlighted ? Palette.light : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label(value),
                style: TypeScale.callout.copyWith(
                    color: highlighted ? Palette.onLight : Palette.text2,
                    fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500)),
            const SizedBox(width: 4),
            Icon(icon, size: 18, color: highlighted ? Palette.onLight : Palette.text2),
          ]),
        ),
      );
}
