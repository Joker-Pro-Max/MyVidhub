// 生成 Kodi 风格电影 NFO（移植自花栗鼠 nfo.rs）。Infuse、VidHub、Jellyfin、Emby、ReelNest 通用。
import 'meta.dart';

String _esc(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    switch (r) {
      case 0x26:
        b.write('&amp;');
      case 0x3C:
        b.write('&lt;');
      case 0x3E:
        b.write('&gt;');
      case 0x22:
        b.write('&quot;');
      case 0x27:
        b.write('&apos;');
      default:
        // XML 1.0 不允许的控制字符，直接丢掉，免得整份 NFO 解析失败
        if (r < 0x20 && r != 0x09 && r != 0x0A && r != 0x0D) continue;
        b.writeCharCode(r);
    }
  }
  return b.toString();
}

void _tag(StringBuffer o, String name, String? value) {
  if (value == null || value.trim().isEmpty) return;
  o.write('  <$name>${_esc(value.trim())}</$name>\n');
}

String renderMovieNfo(ScrapedMeta m) {
  final o = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<movie>\n');
  _tag(o, 'title', m.title);
  _tag(o, 'originaltitle', m.originalTitle);
  if (m.code != null) _tag(o, 'sorttitle', m.code);
  if (m.year != null) _tag(o, 'year', '${m.year}');
  _tag(o, 'premiered', m.releaseDate);
  _tag(o, 'releasedate', m.releaseDate);
  if (m.runtimeMins != null) _tag(o, 'runtime', '${m.runtimeMins}');
  if (m.rating != null) _tag(o, 'rating', m.rating!.toStringAsFixed(1));
  final plot = m.plotOrFallback();
  _tag(o, 'plot', plot);
  _tag(o, 'outline', plot);
  _tag(o, 'studio', m.studio);
  for (final d in m.directors) {
    _tag(o, 'director', d);
  }
  for (final g in m.genres) {
    _tag(o, 'genre', g);
  }
  if (m.label != null) _tag(o, 'tag', m.label);
  if (m.series != null && m.series!.trim().isNotEmpty) {
    o.write('  <set>\n    <name>${_esc(m.series!.trim())}</name>\n  </set>\n');
  }
  if (m.code != null) {
    o.write('  <uniqueid type="num" default="true">${_esc(m.code!)}</uniqueid>\n');
    _tag(o, 'num', m.code);
  }
  if (m.tmdbId != null) {
    o.write('  <uniqueid type="tmdb"${m.code == null ? ' default="true"' : ''}>${m.tmdbId}</uniqueid>\n');
    _tag(o, 'tmdbid', '${m.tmdbId}');
  }
  for (var i = 0; i < m.actors.length; i++) {
    final a = m.actors[i];
    if (a.name.trim().isEmpty) continue;
    o.write('  <actor>\n    <name>${_esc(a.name.trim())}</name>\n    <type>Actor</type>\n    <order>$i</order>\n');
    if (a.thumb != null && a.thumb!.isNotEmpty) o.write('    <thumb>${_esc(a.thumb!)}</thumb>\n');
    o.write('  </actor>\n');
  }
  o.write('</movie>\n');
  return o.toString();
}
