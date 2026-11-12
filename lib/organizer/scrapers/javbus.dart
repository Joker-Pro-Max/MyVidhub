// JavBus 刮削（移植自花栗鼠 scrapers/javbus.rs）。
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../code.dart';
import '../http_util.dart';
import '../meta.dart';

const _base = 'https://www.javbus.com';
const _invalidActress = ['演員', '演员', '點擊放大', '点击放大'];
const _labelDate = ['發行日期', '发行日期', '発売日'];
const _labelRuntime = ['長度', '长度', '収録時間'];
const _labelDirector = ['導演', '导演', '監督'];
const _labelMaker = ['製作商', '制作商', 'メーカー'];
const _labelLabel = ['發行商', '发行商', 'レーベル'];
const _labelSeries = ['系列'];

final _titleRe = RegExp(r'^([a-z0-9_-]+)\s+(.*?)\s*-\s*javbus\s*$', caseSensitive: false);

const _headers = {
  'Accept-Language': 'zh-CN,zh;q=0.9,ja;q=0.8,en;q=0.6',
  // 不带这三个 cookie 会被重定向到 /doc/driver-verify 挑战页
  'Cookie': 'age=verified; dv=1; existmag=mag',
};

bool _isChallenge(String body) {
  final l = body.toLowerCase();
  return ['driver-verify', 'age verification javbus', '驗證您的瀏覽器', 'cloudflare'].any(l.contains);
}

Future<String?> _fetch(String url) async {
  final r = await httpGet(Uri.parse(url), headers: _headers);
  if (r == null || r.status != 200) return null;
  final body = r.text;
  return _isChallenge(body) ? null : body;
}

String _joined(Element e) => e.nodes.isEmpty ? e.text.trim() : _textOf(e);
String _textOf(Node n) {
  final b = StringBuffer();
  void walk(Node x) {
    if (x is Text) {
      b.write(x.text.trim());
    } else {
      x.nodes.forEach(walk);
    }
  }

  walk(n);
  return b.toString();
}

String _infoRow(Document doc, List<String> labels, {required bool wantLinkText}) {
  for (final p in doc.querySelectorAll('.info p')) {
    final header = p.querySelector('span.header');
    final headerText = header == null ? '' : _joined(header).replaceAll(RegExp(r'[:：]+$'), '');
    if (!labels.any(headerText.contains)) continue;
    if (wantLinkText) {
      final a = p.querySelector('a');
      if (a != null) {
        final t = _joined(a);
        if (t.isNotEmpty) return t;
      }
    }
    var text = _joined(p);
    if (header != null) {
      final ht = _joined(header);
      if (text.startsWith(ht)) text = text.substring(ht.length);
    }
    return text.replaceFirst(RegExp(r'^[:： ]+'), '').trim();
  }
  return '';
}

(String, String) _codeAndTitle(Document doc, String fallback) {
  final t = doc.querySelector('title');
  final m = t == null ? null : _titleRe.firstMatch(_joined(t));
  if (m != null) return (m.group(1)!.toUpperCase(), m.group(2)!.trim());
  final h3 = doc.querySelector('h3');
  if (h3 != null) return (fallback.toUpperCase(), _joined(h3));
  return (fallback.toUpperCase(), fallback.toUpperCase());
}

String? _abs(Uri base, String? href) => href == null ? null : base.resolve(href).toString();

ScrapedMeta parseJavbusDetail(String body, String sourceUrl, String fallbackCode) {
  final doc = html.parse(body);
  final base = Uri.tryParse(sourceUrl) ?? Uri.parse(_base);
  final (code, title) = _codeAndTitle(doc, fallbackCode);

  final runtimeText = _infoRow(doc, _labelRuntime, wantLinkText: false);
  final runtime = int.tryParse(RegExp(r'\d+').firstMatch(runtimeText)?.group(0) ?? '');

  final dateRaw = _infoRow(doc, _labelDate, wantLinkText: false);
  final date = dateRaw.length >= 10 ? dateRaw.substring(0, 10) : null;

  final actors = <ScrapedActor>[];
  for (final a in doc.querySelectorAll("#avatar-waterfall a[href*='/star/'], .star-name a[href*='/star/']")) {
    final img = a.querySelector('img');
    final name = (img?.attributes['title'] ?? a.attributes['title'] ?? _joined(a)).trim();
    if (name.isEmpty || _invalidActress.contains(name) || actors.any((x) => x.name == name)) continue;
    actors.add(ScrapedActor(name, _actorThumb(base, img?.attributes['src'])));
  }
  // 页面上「名字链接」在前、带头像的那份在后，按名字把头像补上
  for (final img in doc.querySelectorAll('#avatar-waterfall img[title], .star-box img[title]')) {
    final i = actors.indexWhere((x) => x.name == img.attributes['title']?.trim() && x.thumb == null);
    final t = _actorThumb(base, img.attributes['src']);
    if (i >= 0 && t != null) actors[i] = ScrapedActor(actors[i].name, t);
  }

  final genres = <String>[];
  for (final a in doc.querySelectorAll(".info a[href*='/genre/'], #genre-toggle a")) {
    final n = _joined(a);
    if (n.isNotEmpty && !genres.contains(n)) genres.add(n);
  }

  final cover = _abs(base, doc.querySelector('a.bigImage[href]')?.attributes['href']) ??
      _abs(base, doc.querySelector('#cover img[src]')?.attributes['src']);

  var plot = (doc.querySelector("meta[name='description']")?.attributes['content'] ??
          doc.querySelector("meta[property='og:description']")?.attributes['content'])
      ?.trim();
  // javbus 的 meta description 只是"【發行日期】…，(番号)标题"的拼接，不是剧情简介
  if (plot != null && (plot.isEmpty || plot.contains('發行日期') || plot.contains('发行日期'))) plot = null;

  final director = _infoRow(doc, _labelDirector, wantLinkText: true);
  String? nz(String s) => s.isEmpty ? null : s;

  return ScrapedMeta(
    source: 'javbus',
    code: code,
    title: title,
    plot: plot,
    year: ScrapedMeta.yearFromDate(date),
    releaseDate: date,
    runtimeMins: runtime,
    genres: genres,
    actors: actors,
    directors: director.isEmpty ? const [] : [director],
    studio: nz(_infoRow(doc, _labelMaker, wantLinkText: true)),
    label: nz(_infoRow(doc, _labelLabel, wantLinkText: true)),
    series: nz(_infoRow(doc, _labelSeries, wantLinkText: true)),
    coverUrl: cover,
  );
}

Future<String?> _findDetailUrl(String code) async {
  final target = normalizeCode(code);
  final base = Uri.parse(_base);
  final enc = Uri.encodeComponent(code);
  for (final path in ['/search/$enc&type=0&parent=uc', '/uncensored/search/$enc&type=0&parent=uc']) {
    final body = await _fetch('$_base$path');
    if (body == null) continue;
    final doc = html.parse(body);
    final candidates = <String>[];
    for (final b in doc.querySelectorAll('a.movie-box[href]')) {
      final href = b.attributes['href'] ?? '';
      final date = b.querySelector('date');
      final ids = [
        normalizeCode(date == null ? '' : _joined(date)),
        normalizeCode(b.attributes['title'] ?? ''),
        normalizeCode(href.split('/').last),
      ];
      if (target.isNotEmpty && ids.contains(target)) return _abs(base, href);
      candidates.add(href);
    }
    if (candidates.length == 1) return _abs(base, candidates.first);
  }
  return null;
}

Future<ScrapedMeta?> javbusFindByCode(String code) async {
  final url = await _findDetailUrl(code);
  if (url == null) return null;
  final body = await _fetch(url);
  if (body == null) return null;
  final meta = parseJavbusDetail(body, url, code);
  // 搜索页兜底"只有一个候选就采用"时可能是别的影片，番号对不上就不要
  if (normalizeCode(meta.code ?? '') != normalizeCode(code)) return null;
  return meta;
}

/// 演员头像地址；JavBus 没有头像时给的是 nowprinting 占位图，不要。
String? _actorThumb(Uri base, String? src) {
  final u = _abs(base, src);
  return u == null || u.contains('nowprinting') ? null : u;
}

/// 按演员名在 JavBus 搜女优，返回头像地址；精确同名优先，只有一个结果也直接采用，
/// 其余情况只在名字足够相似时才认（避免搜索结果里认错人）。找不到返回 null。
Future<String?> javbusActorThumb(String name) async {
  final q = name.trim();
  if (q.isEmpty) return null;
  final body = await _fetch('$_base/searchstar/${Uri.encodeComponent(q)}');
  if (body == null) return null;
  final doc = html.parse(body);
  final base = Uri.parse(_base);
  String? first;
  String? similar;
  var count = 0;
  for (final a in doc.querySelectorAll("a.avatar-box[href*='/star/']")) {
    final img = a.querySelector('img');
    final thumb = _actorThumb(base, img?.attributes['src']);
    if (thumb == null) continue;
    count++;
    first ??= thumb;
    final title = (img?.attributes['title'] ?? '').trim();
    if (title == q) return thumb;
    similar ??= _nameSimilar(title, q) ? thumb : null;
  }
  return count == 1 ? first : similar;
}

/// 两个名字是否至少有 2 个相同汉字/字符。
bool _nameSimilar(String a, String b) {
  final sa = a.runes.map(String.fromCharCode).where((c) => c.trim().isNotEmpty).toSet();
  final sb = b.runes.map(String.fromCharCode).where((c) => c.trim().isNotEmpty).toSet();
  return sa.intersection(sb).length >= 2;
}
