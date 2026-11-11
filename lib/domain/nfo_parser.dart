import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

enum NfoKind { movie, tvshow, episode, unknown }

class NfoActor {
  const NfoActor({required this.name, this.role, this.thumb, this.order});
  final String name;
  final String? role;
  final String? thumb;
  final int? order;
}

/// 从 Kodi / Jellyfin / Emby / tinyMediaManager 风格 NFO 中解析出的元数据。
class NfoData {
  NfoData({required this.kind});

  final NfoKind kind;
  String? title;
  String? originalTitle;
  String? sortTitle;
  String? plot;
  String? tagline;
  String? premiered;
  String? mpaa;
  String? setName;
  String? status;
  int? year;
  int? runtime; // 分钟
  int? season;
  int? episode;
  double? rating;
  List<String> genres = [];
  List<String> tags = [];
  List<String> countries = [];
  List<String> studios = [];
  List<String> directors = [];
  List<String> writers = [];
  List<NfoActor> actors = [];
  Map<String, String> uniqueIds = {};
  String? posterUrl;
  String? fanartUrl;
}

/// 容错的 NFO 解析器。
///
/// 处理常见的不规范情况：BOM、非法控制字符、未转义的 `&`、
/// XML 后面附带 URL（旧版 Kodi 格式）、XML 截断等。
class NfoParser {
  static const _rootTags = ['movie', 'tvshow', 'episodedetails', 'musicvideo'];

  static NfoData? parseBytes(Uint8List bytes) =>
      parse(utf8.decode(bytes, allowMalformed: true));

  static NfoData? parse(String raw) {
    var text = raw.replaceAll('﻿', '');
    text = text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

    final rootMatch =
        RegExp('<(${_rootTags.join('|')})[\\s>/]').firstMatch(text);
    if (rootMatch == null) return null;
    final tag = rootMatch.group(1)!;
    final kind = switch (tag) {
      'movie' || 'musicvideo' => NfoKind.movie,
      'tvshow' => NfoKind.tvshow,
      'episodedetails' => NfoKind.episode,
      _ => NfoKind.unknown,
    };

    // 只取第一个根元素（多集合并文件里有多个 <episodedetails>）
    final start = rootMatch.start;
    final closeTag = '</$tag>';
    final end = text.indexOf(closeTag, start);
    final xmlText = end < 0
        ? text.substring(start)
        : text.substring(start, end + closeTag.length);

    final escaped = xmlText.replaceAll(
        RegExp(r'&(?!(?:[a-zA-Z][a-zA-Z0-9]*|#\d+|#x[0-9a-fA-F]+);)'), '&amp;');

    try {
      final doc = XmlDocument.parse(escaped);
      return _fromElement(doc.rootElement, kind);
    } catch (_) {
      return _regexFallback(xmlText, kind);
    }
  }

  static NfoData _fromElement(XmlElement root, NfoKind kind) {
    final d = NfoData(kind: kind);
    String? text(String name) {
      for (final e in root.childElements) {
        if (e.name.local.toLowerCase() == name) {
          final t = e.innerText.trim();
          if (t.isNotEmpty) return t;
        }
      }
      return null;
    }

    List<String> all(String name, {bool split = false}) {
      final out = <String>[];
      for (final e in root.childElements) {
        if (e.name.local.toLowerCase() != name) continue;
        final t = e.innerText.trim();
        if (t.isEmpty) continue;
        if (split) {
          out.addAll(t.split(RegExp(r'\s*[/|,，、]\s*')).where((s) => s.isNotEmpty));
        } else {
          out.add(t);
        }
      }
      return _dedupe(out);
    }

    d.title = text('title');
    d.originalTitle = text('originaltitle');
    d.sortTitle = text('sorttitle');
    d.plot = text('plot') ?? text('outline') ?? text('review');
    d.tagline = text('tagline');
    d.mpaa = text('mpaa') ?? text('certification');
    d.status = text('status');
    d.premiered =
        text('premiered') ?? text('releasedate') ?? text('aired') ?? text('release');
    d.year = _parseYear(text('year')) ?? _parseYear(d.premiered);
    d.runtime = _parseInt(text('runtime'));
    d.season = _parseInt(text('season'));
    d.episode = _parseInt(text('episode'));
    d.genres = all('genre', split: true);
    d.tags = all('tag');
    d.countries = all('country', split: true);
    d.studios = all('studio', split: true);
    d.directors = all('director', split: true);
    d.writers = all('credits', split: true);

    // 评分：优先 <ratings><rating default="true">，否则第一个，再否则 <rating>
    final ratings = root.childElements
        .where((e) => e.name.local.toLowerCase() == 'ratings')
        .expand((e) => e.childElements)
        .toList();
    if (ratings.isNotEmpty) {
      final def = ratings.firstWhere(
        (r) => r.getAttribute('default') == 'true',
        orElse: () => ratings.first,
      );
      final v = def.childElements
          .where((e) => e.name.local == 'value')
          .map((e) => e.innerText)
          .firstOrNull;
      d.rating = _parseDouble(v);
    }
    d.rating ??= _parseDouble(text('rating')) ?? _parseDouble(text('userrating'));

    // 合集
    for (final e in root.childElements) {
      if (e.name.local.toLowerCase() != 'set') continue;
      final name = e.childElements
          .where((c) => c.name.local == 'name')
          .map((c) => c.innerText.trim())
          .firstOrNull;
      final s = name ?? (e.childElements.isEmpty ? e.innerText.trim() : null);
      if (s != null && s.isNotEmpty) d.setName = s;
    }

    // 唯一 ID
    for (final e in root.childElements) {
      final n = e.name.local.toLowerCase();
      final v = e.innerText.trim();
      if (v.isEmpty) continue;
      if (n == 'uniqueid') {
        d.uniqueIds[(e.getAttribute('type') ?? 'unknown').toLowerCase()] = v;
      } else if (n == 'tmdbid') {
        d.uniqueIds.putIfAbsent('tmdb', () => v);
      } else if (n == 'imdbid' || (n == 'id' && v.startsWith('tt'))) {
        d.uniqueIds.putIfAbsent('imdb', () => v);
      }
    }

    // 演员
    var autoOrder = 0;
    for (final e in root.childElements) {
      if (e.name.local.toLowerCase() != 'actor') continue;
      String? c(String n) => e.childElements
          .where((x) => x.name.local.toLowerCase() == n)
          .map((x) => x.innerText.trim())
          .where((s) => s.isNotEmpty)
          .firstOrNull;
      final name = c('name');
      if (name == null) continue;
      d.actors.add(NfoActor(
        name: name,
        role: c('role'),
        thumb: c('thumb'),
        order: _parseInt(c('order')) ?? autoOrder,
      ));
      autoOrder++;
    }
    d.actors.sort((a, b) => (a.order ?? 0).compareTo(b.order ?? 0));

    // 海报 / 背景 URL（通常是网络地址，本地图片优先由扫描器按文件名查找）
    for (final e in root.childElements) {
      final n = e.name.local.toLowerCase();
      if (n == 'thumb' && d.posterUrl == null) {
        final aspect = e.getAttribute('aspect');
        if (aspect == null || aspect == 'poster') {
          final t = e.innerText.trim();
          if (t.isNotEmpty) d.posterUrl = t;
        }
      } else if (n == 'fanart' && d.fanartUrl == null) {
        final t = e.childElements
            .where((x) => x.name.local == 'thumb')
            .map((x) => x.innerText.trim())
            .where((s) => s.isNotEmpty)
            .firstOrNull;
        if (t != null) d.fanartUrl = t;
      }
    }
    return d;
  }

  /// XML 完全无法解析时的兜底：用正则提取常用字段。
  static NfoData? _regexFallback(String text, NfoKind kind) {
    String? tag(String name) {
      final m = RegExp('<$name(?:\\s[^>]*)?>([\\s\\S]*?)</$name>',
              caseSensitive: false)
          .firstMatch(text);
      final v = m?.group(1)?.trim();
      return (v == null || v.isEmpty) ? null : _unescape(v);
    }

    List<String> tags(String name) => _dedupe(RegExp(
            '<$name(?:\\s[^>]*)?>([\\s\\S]*?)</$name>',
            caseSensitive: false)
        .allMatches(text)
        .map((m) => _unescape(m.group(1)!.trim()))
        .where((s) => s.isNotEmpty && !s.contains('<'))
        .toList());

    final d = NfoData(kind: kind)
      ..title = tag('title')
      ..originalTitle = tag('originaltitle')
      ..plot = tag('plot')
      ..premiered = tag('premiered') ?? tag('aired')
      ..runtime = _parseInt(tag('runtime'))
      ..season = _parseInt(tag('season'))
      ..episode = _parseInt(tag('episode'))
      ..genres = tags('genre')
      ..directors = tags('director');
    d.year = _parseYear(tag('year')) ?? _parseYear(d.premiered);
    final r = tag('rating');
    d.rating = r == null || r.contains('<') ? null : _parseDouble(r);
    if (d.title == null && d.plot == null) return null;
    return d;
  }

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  static List<String> _dedupe(List<String> list) {
    final seen = <String>{};
    return [for (final s in list) if (seen.add(s.toLowerCase())) s];
  }

  static int? _parseInt(String? s) {
    if (s == null) return null;
    final m = RegExp(r'-?\d+').firstMatch(s);
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  static double? _parseDouble(String? s) {
    if (s == null) return null;
    final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(s);
    if (m == null) return null;
    final v = double.tryParse(m.group(0)!.replaceAll(',', '.'));
    return (v == null || v <= 0) ? null : v;
  }

  static int? _parseYear(String? s) {
    if (s == null) return null;
    final m = RegExp(r'(?<!\d)(18|19|20|21)\d{2}(?!\d)').firstMatch(s);
    return m == null ? null : int.parse(m.group(0)!);
  }
}
