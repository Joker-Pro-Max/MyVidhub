import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../organizer/code.dart';

final _kana = RegExp(r'[぀-ヿㇰ-ㇿ]'); // 平假名 / 片假名
final _hangul = RegExp(r'[가-힯ᄀ-ᇿ]');
final _han = RegExp(r'[一-鿿㐀-䶿]');
final _latin = RegExp(r'[A-Za-z]');

/// 是否需要翻译成中文：含日文假名 / 韩文，或者没有汉字但有字母（英文、罗马音）。
/// 纯番号（SSIS-001）、纯数字不翻译。
bool needsTranslation(String s) {
  final t = s.trim();
  if (t.isEmpty) return false;
  if (_kana.hasMatch(t) || _hangul.hasMatch(t)) return true;
  if (_han.hasMatch(t)) return false;
  if (!_latin.hasMatch(t)) return false;
  final code = extractCode(t);
  if (code != null && normalizeCode(code) == normalizeCode(t)) return false;
  return true;
}

class TranslateException implements Exception {
  const TranslateException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Google 翻译（免费接口，不需要 Key）：自动识别语言 → 简体中文。
class Translator {
  static const _endpoint = 'https://translate.googleapis.com/translate_a/single';

  /// 翻译一批文字，返回 原文 → 中文。失败的条目不在结果里。
  /// 多条用换行拼成一次请求，按行拆回；行数对不上时退回逐条翻译。
  static Future<Map<String, String>> toChinese(
    List<String> texts, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final out = <String, String>{};
    // batches 里是发给 Google 的清理后文本；originals 是与之一一对应的原文，用作返回的 key
    // （数据库按 items.title 精确匹配，key 必须是原文，不能是 trim / 换行替换后的文本）。
    final batches = <List<String>>[];
    final originals = <List<String>>[];
    var cur = <String>[];
    var curOrig = <String>[];
    var len = 0;
    for (final t in texts) {
      final clean = t.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
      if (clean.isEmpty) continue;
      if (cur.isNotEmpty && (len + clean.length > 1800 || cur.length >= 40)) {
        batches.add(cur);
        originals.add(curOrig);
        cur = [];
        curOrig = [];
        len = 0;
      }
      cur.add(clean);
      curOrig.add(t);
      len += clean.length + 1;
    }
    if (cur.isNotEmpty) {
      batches.add(cur);
      originals.add(curOrig);
    }

    var done = 0;
    for (var bi = 0; bi < batches.length; bi++) {
      if (isCancelled?.call() ?? false) break;
      final b = batches[bi];
      final orig = originals[bi];
      final res = await _request(b.join('\n'));
      final lines = res.split('\n');
      if (lines.length == b.length) {
        for (var i = 0; i < b.length; i++) {
          final zh = lines[i].trim();
          if (zh.isNotEmpty) out[orig[i]] = zh;
        }
      } else {
        for (var i = 0; i < b.length; i++) {
          if (isCancelled?.call() ?? false) break;
          final zh = (await _request(b[i])).trim();
          if (zh.isNotEmpty) out[orig[i]] = zh;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
      done += b.length;
      onProgress?.call(done, texts.length);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return out;
  }

  static Future<String> _request(String q) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse(_endpoint).replace(queryParameters: {
        'client': 'gtx',
        'sl': 'auto',
        'tl': 'zh-CN',
        'dt': 't',
      });
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 ReelNest');
      req.write('q=${Uri.encodeQueryComponent(q)}');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 429) throw const TranslateException('翻译请求太频繁，请稍后再试');
      if (res.statusCode != 200) throw TranslateException('翻译服务返回 ${res.statusCode}');
      final json = jsonDecode(body);
      // 结构：[[["译文","原文",...], ...], ...]
      final segs = json is List && json.isNotEmpty && json[0] is List ? json[0] as List : const [];
      return segs.map((s) => s is List && s.isNotEmpty && s[0] is String ? s[0] as String : '').join();
    } on SocketException {
      throw const TranslateException('无法连接 Google 翻译（需要能访问 Google）');
    } on TimeoutException {
      throw const TranslateException('连接 Google 翻译超时');
    } finally {
      client.close(force: true);
    }
  }
}
