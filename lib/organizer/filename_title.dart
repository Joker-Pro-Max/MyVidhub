import 'package:path/path.dart' as p;

import 'code.dart';
import 'organize.dart';

/// 给在线搜索用的片名 / 年份 / 番号：番号优先；否则用文件名解析（比片库里显示的标题更接近原始片名）。
(String title, int? year, String? code) titleForSearch(String videoPath, String fallbackTitle, int? fallbackYear) {
  final name = p.basename(videoPath);
  final code = extractCode(name);
  final (t, y) = parseTitleYear(p.basenameWithoutExtension(videoPath));
  return (t.isEmpty ? fallbackTitle : t, y ?? fallbackYear, code);
}
