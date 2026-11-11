import 'media_extensions.dart';

class ParsedName {
  const ParsedName({required this.title, this.year, this.season, this.episode});
  final String title;
  final int? year;
  final int? season;
  final int? episode;

  bool get isEpisode => episode != null;

  @override
  String toString() => 'ParsedName($title, $year, S$season E$episode)';
}

/// 没有 NFO 时，从文件名 / 目录名推断标题、年份、季集。
class FilenameParser {
  static final _seasonEpisode = [
    RegExp(r'(?<![a-z0-9])s(\d{1,3})[ ._\-]?e(\d{1,4})', caseSensitive: false),
    RegExp(r'(?<![a-z0-9])(\d{1,2})x(\d{2,3})(?![0-9p])', caseSensitive: false),
  ];
  static final _cnEpisode = RegExp(r'第\s*([0-9零一二三四五六七八九十百两]+)\s*[集话話期]');
  static final _cnSeason = RegExp(r'第\s*([0-9零一二三四五六七八九十百两]+)\s*季');
  static final _epOnly = RegExp(r'(?<![a-z0-9])(?:ep?|episode)[ ._\-]?(\d{1,4})(?![0-9p])',
      caseSensitive: false);
  static final _year = RegExp(r'(?<![0-9])(19\d{2}|20\d{2})(?![0-9])');
  static final _quality = RegExp(
    r'(?<![a-z])(2160p|1080p|1080i|720p|576p|480p|4k|uhd|bluray|blu-ray|bdrip|brrip|'
    r'web-?dl|webrip|web|hdtv|hdrip|dvdrip|remux|x264|x265|h\.?264|h\.?265|hevc|avc|'
    r'10bit|8bit|hdr10?|dolby|dv|atmos|dts(?:-hd)?|truehd|aac|ac3|ddp?5\.1|'
    r'proper|repack|extended|unrated|directors\.?cut|国语|中字|双语|简繁|内封)(?![a-z])',
    caseSensitive: false,
  );

  static ParsedName parse(String name) {
    var s = name;
    // 去掉开头的 [字幕组] 【xxx】
    s = s.replaceFirst(RegExp(r'^\s*(?:\[[^\]]*\]|【[^】]*】)\s*'), '');

    int? season;
    int? episode;
    var cut = s.length;

    for (final re in _seasonEpisode) {
      final m = re.firstMatch(s);
      if (m != null) {
        season = int.parse(m.group(1)!);
        episode = int.parse(m.group(2)!);
        cut = m.start;
        break;
      }
    }
    if (episode == null) {
      final m = _cnEpisode.firstMatch(s);
      if (m != null) {
        episode = parseChineseNumber(m.group(1)!);
        cut = m.start;
      }
    }
    final sm = _cnSeason.firstMatch(s);
    if (sm != null) {
      season ??= parseChineseNumber(sm.group(1)!);
      if (sm.start < cut) cut = sm.start;
    }
    if (episode == null) {
      final m = _epOnly.firstMatch(s);
      if (m != null) {
        episode = int.parse(m.group(1)!);
        if (m.start < cut) cut = m.start;
      }
    }

    // 年份：取标题之后的最后一个年份（避免 "2012 (2009)" 这种片名被误判）
    int? year;
    final head = s.substring(0, cut);
    final years = _year.allMatches(head).where((m) => m.start > 0).toList();
    if (years.isNotEmpty) {
      final m = years.last;
      year = int.parse(m.group(1)!);
      cut = m.start;
    }

    final q = _quality.firstMatch(s.substring(0, cut));
    if (q != null && q.start > 0) cut = q.start;

    var title = s.substring(0, cut);
    // "The.Dark.Knight" 这类点分隔名 → 空格；已含空格的（如 "Mr. Robot"）保持原样
    if (!title.trim().contains(' ')) {
      title = title.replaceAll(RegExp(r'[._]'), ' ');
    }
    title = title
        .replaceAll(RegExp(r'[\[\(（【]\s*$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s\-–_.]+|[\s\-–_.\[(（【]+$'), '')
        .trim();
    if (title.isEmpty) title = name.trim();

    return ParsedName(title: title, year: year, season: season, episode: episode);
  }
}
