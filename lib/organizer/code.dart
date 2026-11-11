// 番号识别（移植自花栗鼠 code.rs，规则保持一致）。

/// 前后边界不用 \b：下划线算 \w，"SONE_890_标题" 这种常见形状在 \b 下匹配不到。
/// 用显式的字母/数字环视，下划线、连字符、空格、中文、首尾都算干净边界。
/// 数字后允许跟 0-2 个字母后缀（PPPE-378C 的 C），但不计入返回的番号。
/// 分隔符必须真实存在，否则 "RandomMovie2023" 会被误判成番号。
/// 厂牌也可以是「1 个字母 + 2 位数字」，比如 T28-、T38-。
final _codeRe = RegExp(r'(?<![A-Za-z0-9])(\d{2,4})?([A-Za-z]{2,10}|[A-Za-z]\d{2})[-_ ](\d{2,6})(?:[A-Za-z]{0,2})?(?![A-Za-z0-9])');

/// 从文件名（可带扩展名）里摘出疑似番号，摘不出来返回 null。
String? extractCode(String filename) {
  final dot = filename.lastIndexOf('.');
  final stem = dot >= 0 ? filename.substring(0, dot) : filename;
  final m = _codeRe.firstMatch(stem.toUpperCase());
  if (m == null) return null;
  return '${m.group(1) ?? ''}${m.group(2)}-${m.group(3)}';
}

/// 去掉所有非字母数字并转大写，用来比较两个番号是否同一部。
String normalizeCode(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

/// r18.dev 的 content_id 候选变体（补零策略）。不做变体兜底直接拿短写法查，
/// 会被源站模糊匹配到错误影片。
List<String> contentIdVariants(String code) {
  final c = code.trim().toUpperCase();
  final dash = c.indexOf('-');
  if (dash < 0) return [c.replaceAll('-', '').toLowerCase()];
  final prefix = c.substring(0, dash).toLowerCase();
  var number = c.substring(dash + 1).replaceFirst(RegExp(r'^0+'), '');
  if (number.isEmpty) number = '0';

  var head3 = prefix.length >= 3 ? prefix.substring(0, 3) : prefix;
  while (head3.length < 3) {
    head3 += '0';
  }
  final head2 = prefix.length >= 2 ? prefix.substring(0, 2) : prefix;

  final out = <String>[];
  for (final cand in [
    '$head3${number.padLeft(5, '0')}',
    '$prefix$number',
    '$head3${number.padLeft(4, '0')}',
    '$head2${number.padLeft(5, '0')}',
  ]) {
    if (!out.contains(cand)) out.add(cand);
  }
  return out.take(4).toList();
}
