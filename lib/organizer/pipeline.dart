// 单个文件的「刮削 → 整理」流程（移植自花栗鼠 pipeline.rs）。
import 'dart:io';

import 'package:path/path.dart' as p;

import 'meta.dart';
import 'organize.dart';
import 'scrapers/javbus.dart';
import 'scrapers/r18dev.dart';
import 'scrapers/tmdb.dart';

enum ItemStatus { ok, notFound, skipped, error }

class ItemResult {
  ItemResult(this.item);
  final VideoItem item;
  ItemStatus status = ItemStatus.error;
  String? source;
  String? title;
  String? dest;
  String? message;
  List<String> warnings = const [];
}

/// 刮削源选择。auto（智能）= 花栗鼠的顺序：番号走 JavBus / R18.dev，其他走 TMDB。
enum ScraperChoice {
  auto('智能'),
  javbus('JavBus'),
  r18dev('R18.dev'),
  tmdb('TMDB');

  const ScraperChoice(this.label);
  final String label;

  bool get needsCode => this == javbus || this == r18dev;
}

/// 用指定的刮削源查一部。[code] 为番号；[title]/[year] 给 TMDB 用。
Future<ScrapedMeta?> scrapeWith(
  ScraperChoice choice, {
  String? code,
  required String title,
  int? year,
  required String tmdbKey,
}) async {
  switch (choice) {
    case ScraperChoice.javbus:
      if (code == null) return null;
      final m = await javbusFindByCode(code);
      if (m != null && m.plot == null) {
        final r = await r18FindByCode(code);
        if (r != null) {
          m.plot = r.plot;
          m.originalTitle ??= r.originalTitle;
        }
      }
      return m;
    case ScraperChoice.r18dev:
      return code == null ? null : r18FindByCode(code);
    case ScraperChoice.tmdb:
      return tmdbSearchMovie(title, year, tmdbKey);
    case ScraperChoice.auto:
      return scrapeItem(
        VideoItem(
          path: '',
          fileName: '',
          sizeBytes: 0,
          code: code,
          title: title,
          year: year,
          targetFolder: '',
          alreadyOrganized: false,
        ),
        tmdbKey,
      );
  }
}

/// 列出候选结果供用户挑选：TMDB 返回多条；番号源最多一条。
/// TMDB 候选只有列表信息，选定后用 [resolveCandidate] 拉完整详情。
Future<List<ScrapedMeta>> searchCandidates(
  ScraperChoice choice, {
  String? code,
  required String title,
  int? year,
  required String tmdbKey,
}) async {
  if (choice == ScraperChoice.tmdb) return tmdbSearchList(title, year, tmdbKey);
  final m = await scrapeWith(choice, code: code, title: title, year: year, tmdbKey: tmdbKey);
  return m == null ? const [] : [m];
}

Future<ScrapedMeta?> resolveCandidate(ScrapedMeta m, String tmdbKey) async {
  if (m.source == 'tmdb' && m.tmdbId != null && m.actors.isEmpty) {
    return await tmdbDetailById(m.tmdbId!, tmdbKey) ?? m;
  }
  return m;
}

/// 番号 → javbus → r18dev；没有番号或都没查到 → TMDB（需要配置 key）。
Future<ScrapedMeta?> scrapeItem(VideoItem item, String tmdbKey) async {
  final code = item.code;
  if (code != null) {
    final m = await javbusFindByCode(code);
    if (m != null) {
      // javbus 没有真正的剧情简介，从 r18.dev 补；顺便补上日文原名
      if (m.plot == null) {
        final r = await r18FindByCode(code);
        if (r != null) {
          m.plot = r.plot;
          m.originalTitle ??= r.originalTitle;
        }
      }
      return m;
    }
    final r = await r18FindByCode(code);
    if (r != null) return r;
  }
  return tmdbSearchMovie(item.title, item.year, tmdbKey);
}

/// 处理一个文件：刮削 → 整理 → 写元数据。查不到时文件原样不动。
Future<ItemResult> processItem(
  VideoItem item,
  String root,
  String tmdbKey,
  List<UndoOp> ops, {
  void Function(String from, String to)? onMoved,
  ScraperChoice choice = ScraperChoice.auto,
}) async {
  final r = ItemResult(item);
  if (!File(item.path).existsSync()) {
    r.message = '文件不存在或已被移动';
    return r;
  }
  if (!p.isWithin(root, item.path)) {
    r.message = '文件不在所选文件夹内';
    return r;
  }

  if (choice.needsCode && item.code == null) {
    r.status = ItemStatus.notFound;
    r.message = '文件名里没有番号，${choice.label} 无法查询';
    return r;
  }
  final meta = choice == ScraperChoice.auto
      ? await scrapeItem(item, tmdbKey)
      : await scrapeWith(choice, code: item.code, title: item.title, year: item.year, tmdbKey: tmdbKey);
  if (meta == null) {
    r.status = ItemStatus.notFound;
    r.message = choice != ScraperChoice.auto
        ? '${choice.label} 没有查到'
        : item.code != null
        ? '各数据源都没查到这个番号'
        : tmdbKey.trim().isEmpty
            ? '不是番号，且没有设置 TMDB API Key，无法刮削'
            : 'TMDB 没有找到匹配的影片';
    return r;
  }
  r.source = meta.source;
  r.title = meta.title;

  // 番号的年份用刮削到的发行年份，文件名里的年份不可靠
  final folder = item.code != null
      ? folderNameFor(item.code, item.title, meta.year)
      : folderNameFor(null, meta.title, meta.year ?? item.year);
  if (folder.isEmpty) {
    r.message = '无法生成有效的文件夹名';
    return r;
  }

  final OrganizePlan plan;
  try {
    plan = buildPlan(item.path, root, folder);
  } on OrganizeException catch (e) {
    r.status = ItemStatus.skipped;
    r.message = e.message;
    return r;
  }
  try {
    final rep = await executePlan(plan, meta, ops, onMoved: onMoved);
    r.status = ItemStatus.ok;
    r.dest = rep.destVideo;
    r.warnings = rep.warnings;
  } catch (e) {
    r.message = '$e';
  }
  return r;
}

/// 重新刮削一部已整理的影片：按 [choice] 查资料后原地更新 NFO 和图片，视频不移动。
Future<ItemResult> rescrapeItem(
  VideoItem item,
  ScraperChoice choice,
  String tmdbKey,
  List<UndoOp> ops,
  Directory backupDir,
) async {
  final r = ItemResult(item);
  if (!File(item.path).existsSync()) {
    r.message = '文件不存在或已被移动';
    return r;
  }
  if (choice.needsCode && item.code == null) {
    r.status = ItemStatus.notFound;
    r.message = '文件名里没有番号，${choice.label} 无法查询';
    return r;
  }
  final meta = await scrapeWith(choice, code: item.code, title: item.title, year: item.year, tmdbKey: tmdbKey);
  if (meta == null) {
    r.status = ItemStatus.notFound;
    r.message = choice == ScraperChoice.tmdb && tmdbKey.trim().isEmpty ? '没有设置 TMDB API Key' : '${choice.label} 没有查到';
    return r;
  }
  r.source = meta.source;
  r.title = meta.title;
  try {
    final rep = await refreshMetadata(item.path, meta, ops, backupDir);
    r.status = ItemStatus.ok;
    r.dest = item.path;
    r.warnings = rep.warnings;
  } catch (e) {
    r.message = '$e';
  }
  return r;
}
