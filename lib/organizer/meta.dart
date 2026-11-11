// 刮削结果的统一结构（移植自花栗鼠 meta.rs）。

class ScrapedActor {
  const ScrapedActor(this.name, [this.thumb]);
  final String name;
  final String? thumb;
}

/// 各刮削源统一抹平成这一份结构，NFO 和图片都从它生成。
class ScrapedMeta {
  ScrapedMeta({
    required this.source,
    required this.title,
    this.code,
    this.originalTitle,
    this.plot,
    this.year,
    this.releaseDate,
    this.runtimeMins,
    this.rating,
    this.genres = const [],
    this.actors = const [],
    this.directors = const [],
    this.studio,
    this.label,
    this.series,
    this.coverUrl,
    this.posterUrl,
    this.tmdbId,
  });

  /// "r18dev" | "javbus" | "tmdb"
  final String source;

  /// JAV 番号；普通电影为空
  final String? code;
  final String title;
  String? originalTitle;
  String? plot;
  final int? year;
  final String? releaseDate;
  final int? runtimeMins;
  final double? rating;
  final List<String> genres;
  final List<ScrapedActor> actors;
  final List<String> directors;
  final String? studio;
  final String? label;
  final String? series;

  /// 横版大图，用作 fanart / backdrop
  final String? coverUrl;

  /// 竖版海报；没有时退回 coverUrl
  final String? posterUrl;
  final int? tmdbId;

  /// 数据源没有剧情简介时，用已有信息拼一句话："厂牌：…　系列：…　演员：…　类型：…"。
  /// 只整理已有字段，不编造内容；一个字段都没有就返回 null。
  String? fallbackPlot() {
    final parts = <String>[];
    String? nz(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    if (nz(studio) case final s?) parts.add('厂牌：$s');
    if (nz(series) case final s?) parts.add('系列：$s');
    final a = actors.map((x) => x.name.trim()).where((n) => n.isNotEmpty).toList();
    if (a.isNotEmpty) parts.add('演员：${a.join('、')}');
    final g = genres.map((x) => x.trim()).where((n) => n.isNotEmpty).toList();
    if (g.isNotEmpty) parts.add('类型：${g.join('、')}');
    return parts.isEmpty ? null : parts.join('　');
  }

  /// 真简介优先，没有才用拼出来的。
  String? plotOrFallback() {
    final p = plot?.trim();
    return (p != null && p.isNotEmpty) ? p : fallbackPlot();
  }

  static int? yearFromDate(String? date) =>
      (date == null || date.length < 4) ? null : int.tryParse(date.substring(0, 4));
}
