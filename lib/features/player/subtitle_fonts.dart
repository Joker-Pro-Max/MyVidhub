import 'dart:io';

import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Android 上 libass 读不到系统字体，中文 ASS 字幕会变成方块。
/// 这里把系统自带的中文字体链接到 App 目录，作为 libass 的字体目录。
/// （MKV 内嵌的字幕组字体不受影响，照常使用。）
class SubtitleFonts {
  static const _candidates = [
    ('/system/fonts/NotoSansCJK-Regular.ttc', 'Noto Sans CJK SC'),
    ('/system/fonts/NotoSansSC-Regular.otf', 'Noto Sans SC'),
    ('/system/fonts/NotoSansHans-Regular.otf', 'Noto Sans Hans'),
    ('/system/fonts/DroidSansFallbackFull.ttf', 'Droid Sans Fallback'),
    ('/system/fonts/DroidSansFallback.ttf', 'Droid Sans Fallback'),
  ];

  static Future<void> configure(NativePlayer player) async {
    if (!Platform.isAndroid) return;
    try {
      final found = _candidates.where((c) => File(c.$1).existsSync()).firstOrNull;
      if (found == null) return;
      final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'subfonts'));
      await dir.create(recursive: true);
      final target = p.join(dir.path, p.basename(found.$1));
      if (!File(target).existsSync() && !Link(target).existsSync()) {
        try {
          await Link(target).create(found.$1);
        } catch (_) {
          await File(found.$1).copy(target);
        }
      }
      await player.setProperty('sub-fonts-dir', dir.path);
      await player.setProperty('sub-font', found.$2);
    } catch (_) {
      // 字体配置失败不影响播放
    }
  }
}
