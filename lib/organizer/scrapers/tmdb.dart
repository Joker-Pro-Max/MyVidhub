// TMDB 刮削（移植自花栗鼠 scrapers/tmdb.rs）。
import 'dart:convert';

import '../http_util.dart';
import '../meta.dart';

const _api = 'https://api.themoviedb.org/3';
const _posterBase = 'https://image.tmdb.org/t/p/w500';
const _backdropBase = 'https://image.tmdb.org/t/p/w1280';
const _profileBase = 'https://image.tmdb.org/t/p/w185';

Future<Map<String, dynamic>?> _get(String path, Map<String, String> params) async {
  final r = await httpGet(Uri.parse('$_api$path').replace(queryParameters: params),
      timeout: const Duration(seconds: 10));
  if (r == null || r.status != 200) return null;
  try {
    final v = jsonDecode(r.text);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}

/// 按标题（可选年份）搜 TMDB 电影，取第一条命中，再拉详情补上时长、类型、演员。
/// 没配 key / 没命中 / 网络错误一律 null。
Future<ScrapedMeta?> tmdbSearchMovie(String title, int? year, String apiKey) async {
  if (apiKey.trim().isEmpty) return null;
  final found = await _get('/search/movie', {
    'query': title,
    'language': 'zh-CN',
    'api_key': apiKey.trim(),
    if (year != null) 'year': '$year',
  });
  final results = found?['results'];
  if (results is! List || results.isEmpty || results.first is! Map) return null;
  final top = Map<String, dynamic>.from(results.first as Map);
  final id = top['id'];
  if (id is! int) return null;
  final detail = await _get('/movie/$id', {
        'language': 'zh-CN',
        'api_key': apiKey.trim(),
        'append_to_response': 'credits',
      }) ??
      top;
  return mapTmdb(detail, top, title, year);
}

/// 搜索候选（最多 [limit] 条），只含列表页信息；选定后用 [tmdbDetailById] 补全。
Future<List<ScrapedMeta>> tmdbSearchList(String query, int? year, String apiKey, {int limit = 10}) async {
  if (apiKey.trim().isEmpty || query.trim().isEmpty) return const [];
  final found = await _get('/search/movie', {
    'query': query.trim(),
    'language': 'zh-CN',
    'api_key': apiKey.trim(),
    if (year != null) 'year': '$year',
  });
  final results = found?['results'];
  if (results is! List) return const [];
  return [
    for (final r in results.take(limit))
      if (r is Map) mapTmdb(Map<String, dynamic>.from(r), Map<String, dynamic>.from(r), query, year),
  ];
}

/// 按 TMDB 编号拉完整详情（含演员、导演、时长）。
Future<ScrapedMeta?> tmdbDetailById(int id, String apiKey) async {
  if (apiKey.trim().isEmpty) return null;
  final d = await _get('/movie/$id', {
    'language': 'zh-CN',
    'api_key': apiKey.trim(),
    'append_to_response': 'credits',
  });
  return d == null ? null : mapTmdb(d, d, '', null);
}

/// 按演员名搜 TMDB 人物，取第一个有资料图的结果。没配 key / 没命中 / 网络错误返回 null。
Future<String?> tmdbPersonThumb(String name, String apiKey) async {
  final q = name.trim();
  if (q.isEmpty || apiKey.trim().isEmpty) return null;
  final found = await _get('/search/person', {
    'query': q,
    'language': 'zh-CN',
    'api_key': apiKey.trim(),
  });
  final results = found?['results'];
  if (results is! List) return null;
  for (final r in results) {
    if (r is! Map) continue;
    final p = r['profile_path'];
    if (p is String && p.trim().isNotEmpty) return '$_profileBase$p';
  }
  return null;
}

ScrapedMeta mapTmdb(Map<String, dynamic> detail, Map<String, dynamic> top, String queryTitle, int? queryYear) {
  String? s(Map v, String k) {
    final x = v[k];
    return x is String && x.trim().isNotEmpty ? x.trim() : null;
  }

  final date = s(detail, 'release_date') ?? s(top, 'release_date');
  final poster = s(detail, 'poster_path') ?? s(top, 'poster_path');
  final backdrop = s(detail, 'backdrop_path') ?? s(top, 'backdrop_path');
  final genres = [
    for (final g in (detail['genres'] is List ? detail['genres'] as List : const []))
      if (g is Map && s(g, 'name') != null) s(g, 'name')!,
  ];
  final credits = detail['credits'] is Map ? detail['credits'] as Map : const {};
  final cast = credits['cast'] is List ? credits['cast'] as List : const [];
  final crew = credits['crew'] is List ? credits['crew'] as List : const [];
  final actors = [
    for (final p in cast.take(15))
      if (p is Map && s(p, 'name') != null)
        ScrapedActor(s(p, 'name')!, s(p, 'profile_path') == null ? null : '$_profileBase${s(p, 'profile_path')}'),
  ];
  final directors = [
    for (final p in crew)
      if (p is Map && s(p, 'job') == 'Director' && s(p, 'name') != null) s(p, 'name')!,
  ];
  final companies = detail['production_companies'];
  final runtime = detail['runtime'];
  final vote = detail['vote_average'];

  return ScrapedMeta(
    source: 'tmdb',
    title: s(detail, 'title') ?? s(top, 'title') ?? queryTitle,
    originalTitle: s(detail, 'original_title'),
    plot: s(detail, 'overview') ?? s(top, 'overview'),
    year: ScrapedMeta.yearFromDate(date) ?? queryYear,
    releaseDate: date,
    runtimeMins: runtime is int && runtime > 0 ? runtime : null,
    rating: vote is num && vote > 0 ? vote.toDouble() : null,
    genres: genres,
    actors: actors,
    directors: directors,
    studio: companies is List && companies.isNotEmpty && companies.first is Map ? s(companies.first as Map, 'name') : null,
    posterUrl: poster == null ? null : '$_posterBase$poster',
    coverUrl: backdrop == null ? null : '$_backdropBase$backdrop',
    tmdbId: detail['id'] is int ? detail['id'] as int : null,
  );
}
