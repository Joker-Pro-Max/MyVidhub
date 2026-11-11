import 'dart:ui' as ui;

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
import 'batch_rescrape.dart';

/// 电影 / 剧集海报墙：类型筛选 + 排序；长按海报进入多选（重新刮削、标记 / 取消 AV）。
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

  /// 多选模式下已选中的条目；null = 不在多选模式。
  Set<int>? _sel;

  void _toggle(int id) => setState(() {
        final s = _sel ?? <int>{};
        s.contains(id) ? s.remove(id) : s.add(id);
        _sel = s;
      });

  void _exitSelect() => setState(() => _sel = null);

  void _setAv(bool av) {
    final ids = _sel?.toList() ?? const <int>[];
    if (ids.isEmpty) return;
    final db = ref.read(dbProvider);
    for (final id in ids) {
      db.setAv(id, av);
    }
    ref.read(libraryRevisionProvider.notifier).bump();
    _exitSelect();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(av ? '已将 ${ids.length} 部标记为 AV' : '已取消 ${ids.length} 部的 AV 标记'),
    ));
  }

  Future<void> _rescrape() async {
    final ids = _sel?.toList() ?? const <int>[];
    if (ids.isEmpty) return;
    await showBatchRescrape(context, ids);
    if (mounted) _exitSelect();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(itemsProvider((kind: widget.kind, sort: _sort, genre: _genre, limit: null, filter: _filter)));
    final genres = ref.watch(genresProvider(widget.kind));
    final hasSources = ref.watch(sourcesProvider).isNotEmpty;
    final insets = ShellInsets.of(context);
    final g = FormFactor.of(context).gutter;
    final label = widget.kind == MediaKind.movie ? '电影' : '剧集';

    if (!hasSources) return const EmptyLibrary();
    final sel = _sel;
    // 已删除 / 被筛掉的条目不算在已选里
    sel?.retainWhere((id) => items.any((m) => m.id == id));

    final header = sel != null
        ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('已选 ${sel.length}', style: TypeScale.largeTitle),
            const Spacer(),
            PillButton(
              label: sel.length == items.length ? '全不选' : '全选',
              primary: false,
              compact: true,
              onPressed: () => setState(() {
                _sel = sel.length == items.length ? <int>{} : items.map((m) => m.id).toSet();
              }),
            ),
            const SizedBox(width: 8),
            PillButton(label: '完成', compact: true, onPressed: _exitSelect),
          ])
        : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
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
          ]);

    final grid = CustomScrollView(
      key: PageStorageKey('library-${widget.kind.name}'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(padding: EdgeInsets.fromLTRB(g, insets.top + 8, g - 8, 16), child: header),
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
          PosterGrid(
            items: items,
            onTap: (m) => sel != null ? _toggle(m.id) : DetailPage.open(context, m.id),
            // 长按进入多选
            onLongPress: (m) => _toggle(m.id),
            selectedIds: sel,
            bottom: insets.bottom + (sel != null ? 96 : 0),
          ),
      ],
    );

    return PopScope(
      // 不在当前标签页（被 IndexedStack 隐藏）时不拦截返回
      canPop: sel == null || !TickerMode.valuesOf(context).enabled,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelect();
      },
      child: Stack(children: [
        grid,
        if (sel != null)
          Positioned(
            left: g,
            right: g,
            bottom: insets.bottom + 4,
            child: Center(
              child: _SelectionBar(
                count: sel.length,
                onRescrape: _rescrape,
                onAv: () => _setAv(true),
                onNotAv: () => _setAv(false),
              ),
            ),
          ),
      ]),
    );
  }
}

/// 多选时浮在底部的操作栏。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.count, required this.onRescrape, required this.onAv, required this.onNotAv});
  final int count;
  final VoidCallback onRescrape;
  final VoidCallback onAv;
  final VoidCallback onNotAv;

  @override
  Widget build(BuildContext context) {
    final on = count > 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Palette.surface2.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Palette.hairline),
          ),
          child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            PillButton(label: '重新刮削', icon: Icons.auto_fix_high_rounded, onPressed: on ? onRescrape : null),
            PillButton(label: '标记为 AV', primary: false, onPressed: on ? onAv : null),
            PillButton(label: '取消 AV', primary: false, onPressed: on ? onNotAv : null),
          ]),
        ),
      ),
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
            Text(
              label(value),
              style: TypeScale.callout.copyWith(
                color: highlighted ? Palette.onLight : Palette.text2,
                fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(icon, size: 18, color: highlighted ? Palette.onLight : Palette.text2),
          ]),
        ),
      );
}
