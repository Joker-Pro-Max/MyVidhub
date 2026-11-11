import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class AppSettings {
  const AppSettings({required this.autoScrape, required this.blurAv});

  /// 自动刮削：刮削源固定为 TMDB，扫描后自动为没有 NFO 的电影获取在线资料。
  /// 关闭后不再自动刮削，刮削时由用户选择刮削源。
  final bool autoScrape;

  /// AV（资料来自 JavBus / R18.dev）的海报、剧照模糊显示。
  final bool blurAv;
}

final appSettingsProvider = NotifierProvider<AppSettingsController, AppSettings>(AppSettingsController.new);

class AppSettingsController extends Notifier<AppSettings> {
  static const _autoKey = 'auto_scrape';
  static const _blurKey = 'blur_av';

  @override
  AppSettings build() {
    final db = ref.watch(dbProvider);
    return AppSettings(
      autoScrape: (db.setting(_autoKey) ?? '1') == '1',
      blurAv: (db.setting(_blurKey) ?? '1') == '1',
    );
  }

  void setAutoScrape(bool v) {
    ref.read(dbProvider).setSetting(_autoKey, v ? '1' : '0');
    state = AppSettings(autoScrape: v, blurAv: state.blurAv);
  }

  void setBlurAv(bool v) {
    ref.read(dbProvider).setSetting(_blurKey, v ? '1' : '0');
    state = AppSettings(autoScrape: state.autoScrape, blurAv: v);
  }
}
