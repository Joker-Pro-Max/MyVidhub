// R18.dev 刮削（移植自花栗鼠 scrapers/r18dev.rs）。
import 'dart:convert';

import '../code.dart';
import '../http_util.dart';
import '../meta.dart';

const _base = 'https://r18.dev';
const _headers = {
  'Accept': 'application/json, text/html, */*',
  'Accept-Language': 'en-US,en;q=0.9,ja;q=0.8',
  'Referer': 'https://r18.dev/',
};

/// 查无此片、网络错误、HTML 兜底页一律返回 null。
Future<Map<String, dynamic>?> _getJson(String url) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    final r = await httpGet(Uri.parse(url), headers: _headers);
    if (r == null) return null;
    if ((r.status == 429 || r.status == 503) && attempt == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      continue;
    }
    if (r.status != 200 || r.contentType.contains('text/html')) return null;
    try {
      final v = jsonDecode(r.text);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }
  return null;
}

String _t(dynamic v, String key) => v is Map && v[key] is String ? (v[key] as String).trim() : '';
String? _nz(String s) => s.isEmpty ? null : s;

String _namedOrFlat(Map<String, dynamic> raw, String key) {
  final n = raw[key];
  if (n is Map && n['name'] is String && (n['name'] as String).trim().isNotEmpty) return (n['name'] as String).trim();
  for (final c in ['${key}_name_en', '${key}_name_ja']) {
    final t = _t(raw, c);
    if (t.isNotEmpty) return t;
  }
  return '';
}

List<dynamic> _list(dynamic v) => v is List ? v : const [];

ScrapedMeta mapR18(String code, Map<String, dynamic> raw) {
  final titleEn = _t(raw, 'title_en');
  final titleJa = _t(raw, 'title_ja');
  final plot = [_t(raw, 'comment_en'), _t(raw, 'description_en'), _t(raw, 'description')]
      .where((s) => s.isNotEmpty)
      .firstOrNull;

  final directors = <String>[];
  for (final d in _list(raw['directors'])) {
    final n = _nz(_t(d, 'name_romaji')) ?? _nz(_t(d, 'name_kanji'));
    if (n != null && !directors.contains(n)) directors.add(n);
  }

  final actors = <ScrapedActor>[];
  for (final a in _list(raw['actresses'])) {
    final name = _nz(_t(a, 'name_romaji')) ?? _nz(_t(a, 'name_kanji'));
    if (name == null || actors.any((x) => x.name == name)) continue;
    final thumb = _t(a, 'image_url');
    actors.add(ScrapedActor(name, thumb.startsWith('http') ? thumb : null));
  }

  final genres = <String>[];
  for (final c in _list(raw['categories'])) {
    final n = _nz(_t(c, 'name_en')) ?? _nz(_t(c, 'name')) ?? _nz(_t(c, 'name_ja'));
    if (n != null && !genres.contains(n)) genres.add(n);
  }

  var cover = _t(raw, 'jacket_full_url');
  if (cover.isEmpty && raw['images'] is Map) {
    final j = (raw['images'] as Map)['jacket_image'];
    cover = _nz(_t(j, 'large')) ?? _nz(_t(j, 'large2')) ?? '';
  }
  final poster = _nz(_t(raw, 'jacket_thumb_url')) ?? _nz(cover);

  final d = _t(raw, 'release_date');
  final date = d.length >= 10 ? d.substring(0, 10) : null;
  final runtime = raw['runtime_mins'];

  return ScrapedMeta(
    source: 'r18dev',
    code: code.toUpperCase(),
    title: _nz(titleEn) ?? _nz(titleJa) ?? code.toUpperCase(),
    originalTitle: _nz(titleJa),
    plot: plot,
    year: ScrapedMeta.yearFromDate(date),
    releaseDate: date,
    runtimeMins: runtime is int ? runtime : null,
    genres: genres,
    actors: actors,
    directors: directors,
    studio: _nz(_namedOrFlat(raw, 'maker')),
    label: _nz(_namedOrFlat(raw, 'label')),
    series: _nz(_namedOrFlat(raw, 'series')),
    coverUrl: _nz(cover),
    posterUrl: poster,
  );
}

Future<ScrapedMeta?> r18FindByCode(String code) async {
  var contentId = '';
  for (final cand in contentIdVariants(code)) {
    final v = await _getJson('$_base/videos/vod/movies/detail/-/dvd_id=$cand/json');
    final id = v?['content_id'];
    if (id is String && id.trim().isNotEmpty) {
      contentId = id.trim();
      break;
    }
  }
  if (contentId.isEmpty) return null;
  final raw = await _getJson('$_base/videos/vod/movies/detail/-/combined=$contentId/json');
  if (raw == null) return null;
  // 源站模糊匹配可能返回别的影片，番号对不上就当没查到
  final got = raw['dvd_id'] is String ? raw['dvd_id'] as String : '';
  if (got.isNotEmpty && normalizeCode(got) != normalizeCode(code)) return null;
  return mapR18(code, raw);
}
