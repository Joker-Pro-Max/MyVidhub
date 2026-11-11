/// 媒体相关的扩展名与目录规则。
library;

const videoExtensions = {
  'mkv', 'mp4', 'm4v', 'avi', 'mov', 'wmv', 'flv', 'webm', 'ts', 'm2ts',
  'mts', 'iso', 'rmvb', 'rm', 'mpg', 'mpeg', 'vob', '3gp', 'ogv', 'divx', 'f4v',
};

const imageExtensions = {'jpg', 'jpeg', 'png', 'webp', 'bmp'};

const subtitleExtensions = {'srt', 'ass', 'ssa', 'sub', 'idx', 'vtt', 'sup'};

/// 扫描时跳过的目录（小写比较）。
const ignoredDirNames = {
  'extras', 'extra', 'featurettes', 'behind the scenes', 'deleted scenes',
  'interviews', 'scenes', 'shorts', 'trailers', 'trailer', 'samples',
  'sample', 'extrafanart', 'extrathumbs', 'other', 'others', 'bdmv',
  'certificate', 'video_ts', 'audio_ts', 'lost+found', r'$recycle.bin',
  'system volume information', '@eadir', '#recycle', '.@__thumb',
};

String extOf(String name) {
  final i = name.lastIndexOf('.');
  return i < 0 ? '' : name.substring(i + 1).toLowerCase();
}

String baseNameOf(String name) {
  final i = name.lastIndexOf('.');
  return i <= 0 ? name : name.substring(0, i);
}

bool isVideoFile(String name) {
  if (name.startsWith('._')) return false; // macOS 资源分叉文件
  if (!videoExtensions.contains(extOf(name))) return false;
  final base = baseNameOf(name).toLowerCase();
  // 跳过 sample / trailer 片段
  if (RegExp(r'(^|[ ._\-\[(])(sample|trailer)([ ._\-\])]|$)').hasMatch(base)) {
    return false;
  }
  return true;
}

bool isImageFile(String name) => imageExtensions.contains(extOf(name));

bool isIgnoredDir(String name) {
  if (name.startsWith('.')) return true;
  return ignoredDirNames.contains(name.toLowerCase());
}

/// "Season 1" / "S01" / "第一季" / "Specials" → 季号；不是季目录返回 null。
int? seasonFromDirName(String name) {
  final n = name.trim();
  final lower = n.toLowerCase();
  if (lower == 'specials' || lower == 'special' || n == '特别篇') return 0;
  var m = RegExp(r'^(?:season|series|s)[ ._\-]*(\d{1,3})$', caseSensitive: false)
      .firstMatch(n);
  if (m != null) return int.parse(m.group(1)!);
  m = RegExp(r'^第\s*([0-9零一二三四五六七八九十百两]+)\s*季$').firstMatch(n);
  if (m != null) return parseChineseNumber(m.group(1)!);
  return null;
}

/// 解析中文/阿拉伯数字（支持到 999）。
int? parseChineseNumber(String s) {
  final direct = int.tryParse(s);
  if (direct != null) return direct;
  const digits = {
    '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  };
  var total = 0;
  var current = 0;
  for (final ch in s.split('')) {
    if (digits.containsKey(ch)) {
      current = digits[ch]!;
    } else if (ch == '十') {
      total += (current == 0 ? 1 : current) * 10;
      current = 0;
    } else if (ch == '百') {
      total += (current == 0 ? 1 : current) * 100;
      current = 0;
    } else {
      return null;
    }
  }
  return total + current;
}
