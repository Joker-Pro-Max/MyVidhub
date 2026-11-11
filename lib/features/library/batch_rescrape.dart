import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_settings.dart';
import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../organizer/code.dart';
import '../../organizer/filename_title.dart';
import '../../organizer/organize.dart';
import '../../organizer/pipeline.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../organize/organize_storage.dart';

/// 多选后的「重新刮削」：逻辑与单部一致——自动刮削开启用 TMDB，关闭则让用户选刮削源；
/// 原地更新 NFO / 海报 / 背景图（旧文件备份，可在「刮削并整理」页撤销），视频不移动。
Future<void> showBatchRescrape(BuildContext context, List<int> ids) =>
    showDialog(context: context, barrierDismissible: false, builder: (_) => _BatchRescrapeDialog(ids: ids));

enum _Phase { ready, running, done }

class _Target {
  _Target(this.detail, this.root);
  final MediaDetail detail;
  final String root;
  String? skip;
}

class _BatchRescrapeDialog extends ConsumerStatefulWidget {
  const _BatchRescrapeDialog({required this.ids});
  final List<int> ids;

  @override
  ConsumerState<_BatchRescrapeDialog> createState() => _BatchRescrapeDialogState();
}

class _BatchRescrapeDialogState extends ConsumerState<_BatchRescrapeDialog> {
  _Phase _phase = _Phase.ready;
  late final bool _locked = ref.read(appSettingsProvider).autoScrape;
  late ScraperChoice _choice = _locked ? ScraperChoice.tmdb : ScraperChoice.auto;
  late final List<_Target> _targets = _collect();
  int _done = 0;
  String? _current;
  bool _cancel = false;
  final _ok = <String>[];
  final _failed = <String>[];

  /// 只有本地文件夹里、文件还在的电影能重新刮削。
  List<_Target> _collect() {
    final db = ref.read(dbProvider);
    final out = <_Target>[];
    for (final id in widget.ids) {
      final d = db.detail(id);
      if (d == null) continue;
      final src = db.source(d.sourceId);
      final t = _Target(d, src?.root ?? '');
      if (src == null || src.isNetwork) {
        t.skip = 'NAS 上的影片暂不支持';
      } else if (d.kind == MediaKind.show) {
        t.skip = '剧集暂不支持';
      } else if (d.files.isEmpty || !File(d.files.first.path).existsSync()) {
        t.skip = '视频文件不存在';
      }
      out.add(t);
    }
    return out;
  }

  List<_Target> get _eligible => _targets.where((t) => t.skip == null).toList();

  Future<void> _run() async {
    final db = ref.read(dbProvider);
    final key = effectiveTmdbKey(db);
    if (_choice == ScraperChoice.tmdb && key.trim().isEmpty) {
      setState(() => _failed.add('没有设置 TMDB API Key（设置 › 刮削）'));
      return;
    }
    setState(() => _phase = _Phase.running);
    final backup = await metadataBackupDir();
    final opsByRoot = <String, List<UndoOp>>{};
    final sources = <int>{};

    for (final t in _eligible) {
      if (_cancel || !mounted) break;
      final d = t.detail;
      setState(() => _current = d.title);
      final video = d.files.first.path;
      final (title, year, code) = titleForSearch(video, d.title, d.year);
      try {
        if (_choice.needsCode && code == null) {
          _failed.add('${d.title}：文件名里没有番号');
        } else {
          final meta = await scrapeWith(_choice, code: code ?? extractCode(p.basename(video)), title: title, year: year, tmdbKey: key);
          if (meta == null) {
            _failed.add('${d.title}：${_choice.label} 没有查到');
          } else {
            final ops = opsByRoot.putIfAbsent(t.root, () => []);
            await refreshMetadata(video, meta, ops, backup, nfoPath: d.nfoPath);
            _ok.add(meta.title);
            sources.add(d.sourceId);
          }
        }
      } catch (e) {
        _failed.add('${d.title}：$e');
      }
      if (!mounted) return;
      setState(() => _done++);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    final store = await organizeUndoStore();
    for (final e in opsByRoot.entries) {
      await store.save(UndoLog(createdAt: DateTime.now(), root: e.key, ops: e.value));
    }
    for (final s in sources) {
      ref.read(scanProvider.notifier).scan(s);
    }
    if (mounted) {
      setState(() {
        _phase = _Phase.done;
        _current = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final skipped = _targets.where((t) => t.skip != null).toList();
    final eligible = _eligible.length;

    final Widget body = switch (_phase) {
      _Phase.ready => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$eligible 部会重新刮削，更新 NFO、海报和背景图（旧的会备份，可撤销），视频不移动。',
              style: TypeScale.body.copyWith(color: Palette.text2, fontSize: 14)),
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('跳过 ${skipped.length} 部：${skipped.map((t) => t.skip).toSet().join('、')}',
                style: TypeScale.caption.copyWith(color: Palette.text3)),
          ],
          const SizedBox(height: 18),
          Text('刮削源'.toUpperCase(), style: TypeScale.overline),
          const SizedBox(height: 8),
          if (_locked)
            Text('自动刮削已开启：使用在线影视数据（TMDB）。到「设置 › 刮削」关闭后可选择 JavBus / R18.dev。',
                style: TypeScale.caption)
          else
            SizedBox(
              width: 420,
              child: FilterPills<ScraperChoice>(
                items: ScraperChoice.values,
                selected: _choice,
                label: (c) => c.label,
                onSelect: (c) => setState(() => _choice = c),
              ),
            ),
          if (_failed.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_failed.first, style: TypeScale.caption.copyWith(color: Palette.danger)),
          ],
        ]),
      _Phase.running => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProgressHairline(value: eligible == 0 ? 0 : _done / eligible, height: 4),
          const SizedBox(height: 10),
          Text('$_done / $eligible${_current != null ? ' · $_current' : ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.caption),
        ]),
      _Phase.done => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('成功 ${_ok.length} 部${_failed.isNotEmpty ? ' · 未完成 ${_failed.length} 部' : ''}${skipped.isNotEmpty ? ' · 跳过 ${skipped.length} 部' : ''}',
              style: TypeScale.headline),
          if (_failed.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: Text(_failed.join('\n'), style: TypeScale.caption.copyWith(height: 1.5)),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text('片库正在刷新。需要还原可以到「设置 › 文件夹 › … › 刮削并整理」里撤销。',
              style: TypeScale.caption.copyWith(color: Palette.text3)),
        ]),
    };

    return AlertDialog(
      title: Text(switch (_phase) {
        _Phase.ready => '重新刮削 ${widget.ids.length} 部',
        _Phase.running => '正在重新刮削…',
        _Phase.done => '重新刮削完成',
      }),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: body),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      actions: switch (_phase) {
        _Phase.ready => [
            PillButton(label: '取消', primary: false, compact: true, onPressed: () => Navigator.pop(context)),
            PillButton(label: '开始', compact: true, onPressed: eligible == 0 ? null : _run),
          ],
        _Phase.running => [
            PillButton(label: '停止', primary: false, compact: true, onPressed: () => setState(() => _cancel = true)),
          ],
        _Phase.done => [PillButton(label: '完成', compact: true, onPressed: () => Navigator.pop(context))],
      },
    );
  }
}
