import 'package:media_kit/media_kit.dart';

const _languages = {
  'chi': '中文', 'zho': '中文', 'zh': '中文', 'chs': '简体中文', 'sc': '简体中文',
  'zh-hans': '简体中文', 'zh-cn': '简体中文', 'cht': '繁体中文', 'tc': '繁体中文',
  'zh-hant': '繁体中文', 'zh-tw': '繁体中文', 'zh-hk': '繁体中文',
  'yue': '粤语', 'can': '粤语', 'eng': '英语', 'en': '英语', 'jpn': '日语', 'ja': '日语',
  'kor': '韩语', 'ko': '韩语', 'fre': '法语', 'fra': '法语', 'fr': '法语',
  'ger': '德语', 'deu': '德语', 'de': '德语', 'spa': '西班牙语', 'es': '西班牙语',
  'rus': '俄语', 'ru': '俄语', 'ita': '意大利语', 'it': '意大利语', 'tha': '泰语', 'th': '泰语',
  'por': '葡萄牙语', 'pt': '葡萄牙语', 'und': '未知语言',
};

String? languageName(String? code) {
  if (code == null || code.isEmpty) return null;
  return _languages[code.toLowerCase()] ?? code;
}

String _codec(String? c) => switch (c?.toLowerCase()) {
      null => '',
      'subrip' => 'SRT',
      'ass' || 'ssa' => 'ASS',
      'hdmv_pgs_subtitle' => 'PGS',
      'dvd_subtitle' => 'VobSub',
      'webvtt' => 'VTT',
      'mov_text' => 'TX3G',
      'truehd' => 'TrueHD',
      'eac3' => 'E-AC3',
      'dts' => 'DTS',
      final other => other.toUpperCase(),
    };

String _channels(int? n) => switch (n) {
      null => '',
      1 => '单声道',
      2 => '立体声',
      6 => '5.1',
      8 => '7.1',
      _ => '$n 声道',
    };

String audioTrackLabel(AudioTrack t, int index) {
  final name = [t.title, languageName(t.language)]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toSet()
      .join(' · ');
  final tech = [_codec(t.codec), _channels(t.channelscount)].where((s) => s.isNotEmpty).join(' ');
  return [name.isEmpty ? '音轨 ${index + 1}' : name, if (tech.isNotEmpty) tech].join('  ');
}

String subtitleTrackLabel(SubtitleTrack t, int index) {
  // 外挂字幕 mpv 用文件名做标题，换成可读的 "外挂"
  final title = t.title != null && RegExp(r'\.(srt|ass|ssa|vtt|sub|sup|idx)$', caseSensitive: false).hasMatch(t.title!)
      ? '外挂'
      : t.title;
  final name = [title, languageName(t.language)]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .toSet()
      .join(' · ');
  final codec = _codec(t.codec);
  return [name.isEmpty ? '字幕 ${index + 1}' : name, if (codec.isNotEmpty) codec].join('  ');
}

bool isRealTrack(String id) => id != 'auto' && id != 'no';
