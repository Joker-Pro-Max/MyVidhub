import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/translator.dart';
import 'providers.dart';

class TranslateState {
  const TranslateState({this.running = false, this.done = 0, this.total = 0, this.message});
  final bool running;
  final int done;
  final int total;
  final String? message;
}

final translateProvider = NotifierProvider<TranslateController, TranslateState>(TranslateController.new);

/// 把片库里非中文的片名、演员名翻译成中文（译文存数据库，不改 NFO）。
class TranslateController extends Notifier<TranslateState> {
  bool _cancel = false;

  @override
  TranslateState build() => const TranslateState();

  /// 待翻译的条数（片名 + 演员名，去重）。
  int pending() {
    final t = ref.read(dbProvider).translatableTexts();
    return {...t.titles, ...t.actors}.where(needsTranslation).length;
  }

  void cancel() => _cancel = true;

  Future<void> run() async {
    if (state.running) return;
    final db = ref.read(dbProvider);
    final t = db.translatableTexts();
    final todo = {...t.titles, ...t.actors}.where(needsTranslation).toList();
    if (todo.isEmpty) {
      state = const TranslateState(message: '没有需要翻译的片名或演员名');
      return;
    }
    _cancel = false;
    state = TranslateState(running: true, total: todo.length);
    try {
      final map = await Translator.toChinese(
        todo,
        isCancelled: () => _cancel,
        onProgress: (d, n) => state = TranslateState(running: true, done: d, total: n),
      );
      db.saveTranslations(map);
      ref.read(libraryRevisionProvider.notifier).bump();
      state = TranslateState(
        message: _cancel ? '已停止：翻译了 ${map.length} 条' : '翻译完成：${map.length} / ${todo.length} 条已改为中文',
      );
    } catch (e) {
      state = TranslateState(message: '$e');
    }
  }

  /// 恢复原文：删除译文并重新扫描所有文件夹。
  void restore() {
    ref.read(dbProvider).clearTranslations();
    ref.read(scanProvider.notifier).scanAll();
    state = const TranslateState(message: '已恢复原文，正在重新扫描');
  }
}
