import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_settings.dart';
import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../organizer/organize.dart';
import '../../organizer/pipeline.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import 'organize_storage.dart';

export 'organize_storage.dart' show tmdbKeySetting, builtInTmdbKey, effectiveTmdbKey;

Future<UndoStore> _undoStore() => organizeUndoStore();

enum _Phase { scanning, ready, running, done }

/// 刮削并整理一个本地文件夹：预览 → 逐个刮削、移动、写 NFO 和图片 → 结果 / 撤销。
class OrganizePage extends ConsumerStatefulWidget {
  const OrganizePage({super.key, required this.source});
  final SourceRow source;

  static Future<void> open(BuildContext context, SourceRow source) =>
      Navigator.of(context).push(FadeRoute(builder: (_) => OrganizePage(source: source)));

  @override
  ConsumerState<OrganizePage> createState() => _OrganizePageState();
}

class _OrganizePageState extends ConsumerState<OrganizePage> {
  _Phase _phase = _Phase.scanning;
  ScraperChoice _choice = ScraperChoice.auto;
  List<VideoItem> _items = const [];
  final _selected = <String>{};
  final _results = <String, ItemResult>{};
  String? _current;
  bool _cancel = false;
  String? _error;
  (dynamic, UndoLog)? _lastUndo;
  bool _undoing = false;

  String get _root => widget.source.root;

  @override
  void initState() {
    super.initState();
    if (ref.read(appSettingsProvider).autoScrape) _choice = ScraperChoice.tmdb;
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await scanForOrganize(_root);
      final last = await (await _undoStore()).latestFor(_root);
      if (!mounted) return;
      setState(() {
        _items = items;
        _selected
          ..clear()
          ..addAll(items.where((i) => !i.alreadyOrganized).map((i) => i.path));
        _lastUndo = last;
        _phase = _Phase.ready;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '无法读取文件夹：$e';
          _phase = _Phase.ready;
        });
      }
    }
  }

  Future<void> _start() async {
    final todo = _items.where((i) => _selected.contains(i.path)).toList();
    if (todo.isEmpty) return;
    final again = todo.where((i) => i.alreadyOrganized).length;
    final fresh = todo.length - again;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('处理 ${todo.length} 个视频？'),
        content: Text([
          if (fresh > 0)
            '$fresh 个新视频：查到资料后移到「番号 (年份)」或「片名 (年份)」文件夹，并写入 NFO、海报和背景图；查不到的原样不动。',
          if (again > 0) '$again 个已整理的视频：重新刮削，更新 NFO 和图片（旧的会先备份），视频不移动。',
          '刮削源：${_choice.label}。处理完可以一键撤销。',
        ].join('\n\n')),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          PillButton(label: '取消', primary: false, compact: true, onPressed: () => Navigator.pop(c, false)),
          PillButton(label: '开始整理', compact: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final db = ref.read(dbProvider);
    final tmdbKey = effectiveTmdbKey(db);
    final ops = <UndoOp>[];
    final backup = await metadataBackupDir();
    setState(() {
      _phase = _Phase.running;
      _cancel = false;
      _results.clear();
    });

    for (final item in todo) {
      if (_cancel || !mounted) break;
      setState(() => _current = item.path);
      final r = item.alreadyOrganized
          ? await rescrapeItem(item, _choice, tmdbKey, ops, backup)
          : await processItem(item, _root, tmdbKey, ops, onMoved: db.movePlaybackPath, choice: _choice);
      if (!mounted) break;
      setState(() => _results[item.path] = r);
      // 对数据源客气一点，避免被限流
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    final log = UndoLog(createdAt: DateTime.now(), root: _root, ops: ops);
    await (await _undoStore()).save(log);
    if (!mounted) return;
    setState(() {
      _current = null;
      _phase = _Phase.done;
      if (ops.isNotEmpty) _lastUndo = (null, log);
    });
    // 文件位置变了，重新扫描片库
    if (ops.isNotEmpty) ref.read(scanProvider.notifier).scan(widget.source.id);
  }

  Future<void> _undo() async {
    final last = _lastUndo;
    if (last == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('撤销上次整理？'),
        content: Text('会把 ${last.$2.movedVideos} 个视频移回原来的位置，并删除这次生成的 NFO 和图片。'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          PillButton(label: '取消', primary: false, compact: true, onPressed: () => Navigator.pop(c, false)),
          PillButton(label: '撤销', compact: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _undoing = true);
    final db = ref.read(dbProvider);
    final (_, errors) = await undoLog(last.$2, onRestored: db.movePlaybackPath);
    // 撤销记录用过就删掉，避免重复撤销
    final store = await _undoStore();
    final f = await store.latestFor(_root);
    if (f != null && f.$2.createdAt == last.$2.createdAt) {
      try {
        await f.$1.delete();
      } catch (_) {}
    }
    if (!mounted) return;
    ref.read(scanProvider.notifier).scan(widget.source.id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(errors.isEmpty ? '已撤销，文件已移回原位' : '已撤销，${errors.length} 项未能还原：${errors.first}'),
    ));
    setState(() {
      _undoing = false;
      _lastUndo = null;
      _results.clear();
      _phase = _Phase.scanning;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final g = FormFactor.of(context).gutter;
    final pad = MediaQuery.paddingOf(context);
    final organizedCount = _items.where((i) => i.alreadyOrganized).length;

    return PopScope(
      canPop: _phase != _Phase.running,
      child: Scaffold(
        body: Column(children: [
          Expanded(
            child: CustomScrollView(slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(g - 8, pad.top + 12, g, 0),
                sliver: SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: RoundIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: '返回',
                      onPressed: _phase == _Phase.running ? null : () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(g, 20, g, 20),
                sliver: SliverToBoxAdapter(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('刮削并整理', style: TypeScale.largeTitle),
                    const SizedBox(height: 6),
                    Text('${widget.source.name} · 番号用 JavBus / R18.dev，其他用 TMDB',
                        style: TypeScale.callout.copyWith(color: Palette.text2)),
                    if (_phase == _Phase.ready && _items.isNotEmpty && ref.watch(appSettingsProvider).autoScrape) ...[
                      const SizedBox(height: 22),
                      Text('刮削源'.toUpperCase(), style: TypeScale.overline),
                      const SizedBox(height: 8),
                      Text('自动刮削已开启，使用在线影视数据（TMDB）。番号片请到「设置 › 刮削」关闭自动刮削后选择 JavBus / R18.dev。',
                          style: TypeScale.caption),
                    ],
                    if (_phase == _Phase.ready && _items.isNotEmpty && !ref.watch(appSettingsProvider).autoScrape) ...[
                      const SizedBox(height: 22),
                      Text('刮削源'.toUpperCase(), style: TypeScale.overline),
                      const SizedBox(height: 8),
                      Transform.translate(
                        offset: const Offset(-4, 0),
                        child: FilterPills<ScraperChoice>(
                          items: ScraperChoice.values,
                          selected: _choice,
                          label: (c) => c.label,
                          onSelect: (c) => setState(() => _choice = c),
                        ),
                      ),
                    ],
                    if (_lastUndo != null && _phase != _Phase.running) ...[
                      const SizedBox(height: 18),
                      _UndoBanner(log: _lastUndo!.$2, busy: _undoing, onUndo: _undo),
                    ],
                    if (_phase != _Phase.scanning && _items.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      Row(children: [
                        Expanded(
                          child: Text(
                            '共 ${_items.length} 个视频${organizedCount > 0 ? ' · $organizedCount 个已整理' : ''} · 已选 ${_selected.length}',
                            style: TypeScale.caption,
                          ),
                        ),
                        if (_phase == _Phase.ready && organizedCount > 0)
                          Pressable(
                            onTap: () => setState(() {
                              final organized = _items.where((i) => i.alreadyOrganized).map((i) => i.path).toSet();
                              if (organized.every(_selected.contains)) {
                                _selected.removeAll(organized);
                              } else {
                                _selected.addAll(organized);
                              }
                            }),
                            radius: 8,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Text('选已整理的',
                                  style: TypeScale.caption.copyWith(color: Palette.text, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        if (_phase == _Phase.ready)
                          Pressable(
                            onTap: () => setState(() {
                              if (_selected.length == _items.length) {
                                _selected.clear();
                              } else {
                                _selected.addAll(_items.map((i) => i.path));
                              }
                            }),
                            radius: 8,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Text(_selected.length == _items.length ? '全不选' : '全选',
                                  style: TypeScale.caption.copyWith(color: Palette.text, fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ]),
                    ],
                  ]),
                ),
              ),
              if (_phase == _Phase.scanning)
                const SliverFillRemaining(hasScrollBody: false, child: Center(child: Spinner(size: 24)))
              else if (_error != null)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: g),
                  sliver: SliverToBoxAdapter(
                    child: Text(_error!, style: TypeScale.body.copyWith(color: Palette.danger)),
                  ),
                )
              else if (_items.isEmpty)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: g),
                  sliver: SliverToBoxAdapter(
                    child: Text('这个文件夹里没有视频。', style: TypeScale.body.copyWith(color: Palette.text2)),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(g, 0, g, 24),
                  sliver: SliverList.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      return _ItemRow(
                        item: item,
                        root: _root,
                        first: i == 0,
                        last: i == _items.length - 1,
                        selected: _selected.contains(item.path),
                        result: _results[item.path],
                        working: _current == item.path,
                        selectable: _phase == _Phase.ready,
                        onToggle: () => setState(() {
                          _selected.contains(item.path) ? _selected.remove(item.path) : _selected.add(item.path);
                        }),
                      );
                    },
                  ),
                ),
            ]),
          ),
          if (_phase != _Phase.scanning && _items.isNotEmpty) _bottomBar(g, pad.bottom),
        ]),
      ),
    );
  }

  Widget _bottomBar(double g, double bottom) {
    final done = _results.values;
    int count(ItemStatus s) => done.where((r) => r.status == s).length;
    final total = _selected.length;

    final (String title, String sub, Widget action) = switch (_phase) {
      _Phase.running => (
          '正在处理 ${done.length + 1} / $total',
          '完成 ${count(ItemStatus.ok)} · 未找到 ${count(ItemStatus.notFound)}',
          PillButton(label: '停止', primary: false, onPressed: () => setState(() => _cancel = true)),
        ),
      _Phase.done => (
          '整理完成',
          [
            '成功 ${count(ItemStatus.ok)}',
            if (count(ItemStatus.notFound) > 0) '未找到 ${count(ItemStatus.notFound)}',
            if (count(ItemStatus.skipped) > 0) '跳过 ${count(ItemStatus.skipped)}',
            if (count(ItemStatus.error) > 0) '失败 ${count(ItemStatus.error)}',
          ].join(' · '),
          PillButton(label: '完成', onPressed: () => Navigator.of(context).maybePop()),
        ),
      _ => (
          '处理 $total 个视频',
          () {
            final again = _items.where((i) => i.alreadyOrganized && _selected.contains(i.path)).length;
            return again > 0
                ? '其中 $again 个重新刮削 · 刮削源：${_choice.label}'
                : '刮削源：${_choice.label} · 查不到的原样不动，不覆盖已有文件';
          }(),
          PillButton(label: '开始', icon: Icons.auto_fix_high_rounded, onPressed: total == 0 ? null : _start),
        ),
    };

    return Container(
      padding: EdgeInsets.fromLTRB(g, 14, g, 14 + bottom),
      decoration: const BoxDecoration(
        color: Palette.surface1,
        border: Border(top: BorderSide(color: Palette.hairline)),
      ),
      child: Row(children: [
        if (_phase == _Phase.running) ...[const Spinner(), const SizedBox(width: 14)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: TypeScale.headline),
            const SizedBox(height: 2),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.caption),
          ]),
        ),
        const SizedBox(width: 16),
        action,
      ]),
    );
  }
}

class _UndoBanner extends StatelessWidget {
  const _UndoBanner({required this.log, required this.busy, required this.onUndo});
  final UndoLog log;
  final bool busy;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final t = log.createdAt;
    final when = '${t.month}月${t.day}日 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(color: Palette.surface1, borderRadius: BorderRadius.circular(Radii.group)),
      child: Row(children: [
        const Icon(Icons.history_rounded, color: Palette.text2, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text('上次整理：$when · ${log.movedVideos} 个视频',
              style: TypeScale.callout.copyWith(color: Palette.text2)),
        ),
        busy
            ? const Padding(padding: EdgeInsets.all(10), child: Spinner())
            : PillButton(label: '撤销', primary: false, compact: true, onPressed: onUndo),
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.root,
    required this.first,
    required this.last,
    required this.selected,
    required this.result,
    required this.working,
    required this.selectable,
    required this.onToggle,
  });

  final VideoItem item;
  final String root;
  final bool first;
  final bool last;
  final bool selected;
  final ItemResult? result;
  final bool working;
  final bool selectable;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final rel = p.relative(item.path, from: root);
    final String detail;
    final Color detailColor;
    if (r == null) {
      detail = item.alreadyOrganized
          ? (selected ? '已整理 · 将重新刮削并更新资料（视频不移动）' : '已整理（有 NFO）· 选中可重新刮削')
          : '→ ${item.targetFolder}';
      detailColor = Palette.text3;
    } else {
      switch (r.status) {
        case ItemStatus.ok:
          detail = '✓ ${r.title ?? ''} · ${item.alreadyOrganized ? '资料已更新' : '→ ${p.basename(p.dirname(r.dest!))}'}'
              '${r.warnings.isNotEmpty ? '（${r.warnings.first}）' : ''}';
          detailColor = Palette.text;
        case ItemStatus.notFound:
          detail = r.message ?? '没查到';
          detailColor = Palette.text2;
        case ItemStatus.skipped:
          detail = r.message ?? '已跳过';
          detailColor = Palette.text2;
        case ItemStatus.error:
          detail = r.message ?? '失败';
          detailColor = Palette.danger;
      }
    }

    final Widget lead = working
        ? const SizedBox(width: 22, height: 22, child: Center(child: Spinner()))
        : r != null
            ? Icon(
                switch (r.status) {
                  ItemStatus.ok => Icons.check_circle_rounded,
                  ItemStatus.notFound => Icons.help_outline_rounded,
                  ItemStatus.skipped => Icons.skip_next_rounded,
                  ItemStatus.error => Icons.error_outline_rounded,
                },
                size: 22,
                color: switch (r.status) {
                  ItemStatus.ok => Palette.light,
                  ItemStatus.error => Palette.danger,
                  _ => Palette.text3,
                },
              )
            : AnimatedContainer(
                duration: Motion.of(context, Motion.fast),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Palette.light : Colors.transparent,
                  border: Border.all(color: selected ? Palette.light : Palette.text3, width: 1.5),
                ),
                child: selected ? const Icon(Icons.check_rounded, size: 15, color: Palette.onLight) : null,
              );

    final row = Container(
      decoration: BoxDecoration(
        color: Palette.surface1,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(first ? Radii.group : 0),
          bottom: Radius.circular(last ? Radii.group : 0),
        ),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            lead,
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (item.code != null) ...[TagLabel(item.code!), const SizedBox(width: 8)],
                  Expanded(
                    child: Text(rel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.callout.copyWith(fontSize: 15)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: TypeScale.caption.copyWith(color: detailColor)),
              ]),
            ),
          ]),
        ),
        if (!last) const Padding(padding: EdgeInsets.only(left: 52), child: Divider(height: 1, color: Palette.hairline)),
      ]),
    );
    return selectable ? Pressable(onTap: onToggle, radius: 0, child: row) : row;
  }
}
