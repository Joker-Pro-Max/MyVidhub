import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/organize/organize_storage.dart';
import '../organizer/filename_title.dart';
import '../organizer/organize.dart';
import '../organizer/scrapers/tmdb.dart';
import 'app_settings.dart';
import 'providers.dart';

class AutoScrapeState {
  const AutoScrapeState({this.sourceId, this.done = 0, this.total = 0, this.current, this.message});
  final int? sourceId;
  final int done;
  final int total;
  final String? current;
  final String? message;

  bool get running => sourceId != null;
}

final autoScrapeProvider = NotifierProvider<AutoScrapeController, AutoScrapeState>(AutoScrapeController.new);

/// 自动刮削（「使用在线影视数据」）：扫描完成后，用 TMDB 为本地文件夹里没有 NFO 的电影补资料，
/// 写到视频旁边（NFO + 海报 + 背景图），视频不移动；每个文件只自动尝试一次，可在整理页撤销。
class AutoScrapeController extends Notifier<AutoScrapeState> {
  @override
  AutoScrapeState build() => const AutoScrapeState();

  Future<void> afterScan(int sourceId) async {
    if (state.running || !ref.read(appSettingsProvider).autoScrape) return;
    final db = ref.read(dbProvider);
    final source = db.source(sourceId);
    if (source == null || source.isNetwork) return;
    final key = effectiveTmdbKey(db);
    final candidates = db.autoScrapeCandidates(sourceId);
    if (candidates.isEmpty) return;
    if (key.trim().isEmpty) {
      state = AutoScrapeState(message: '自动刮削需要 TMDB API Key（设置 › 刮削）');
      return;
    }

    state = AutoScrapeState(sourceId: sourceId, total: candidates.length);
    final ops = <UndoOp>[];
    final backup = await metadataBackupDir();
    var found = 0;
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      state = AutoScrapeState(sourceId: sourceId, done: i, total: candidates.length, current: c.title);
      db.markAutoScrapeAttempt(c.path);
      if (!File(c.path).existsSync()) continue;
      // 番号片不走 TMDB（会匹配错），留给手动刮削
      final (title, year, code) = titleForSearch(c.path, c.title, c.year);
      if (code != null) continue;
      try {
        final meta = await tmdbSearchMovie(title, year, key);
        if (meta == null) continue;
        await refreshMetadata(c.path, meta, ops, backup);
        found++;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (ops.isNotEmpty) {
      await (await organizeUndoStore()).save(UndoLog(createdAt: DateTime.now(), root: source.root, ops: ops));
    }
    state = AutoScrapeState(
      message: found > 0 ? '自动刮削完成：${source.name} 补全了 $found 部的资料' : null,
    );
    if (found > 0) ref.read(scanProvider.notifier).scan(sourceId);
  }
}
