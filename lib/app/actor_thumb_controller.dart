import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/organize/organize_storage.dart';
import '../organizer/scrapers/javbus.dart';
import '../organizer/scrapers/tmdb.dart';
import 'providers.dart';

class ActorThumbState {
  const ActorThumbState({this.running = false, this.done = 0, this.total = 0, this.message});
  final bool running;
  final int done;
  final int total;
  final String? message;
}

final actorThumbProvider = NotifierProvider<ActorThumbController, ActorThumbState>(ActorThumbController.new);

/// 给没有头像的演员联网补全头像：先试 JavBus 女优搜索，再退回 TMDB 人物。
/// 头像存远程地址，直接写数据库，不下载文件、不改 NFO。
class ActorThumbController extends Notifier<ActorThumbState> {
  bool _cancel = false;

  @override
  ActorThumbState build() => const ActorThumbState();

  /// 还缺头像的演员数量。
  int pending() => ref.read(dbProvider).actorsMissingThumb().length;

  void cancel() => _cancel = true;

  Future<void> run() async {
    if (state.running) return;
    final db = ref.read(dbProvider);
    final todo = db.actorsMissingThumb();
    if (todo.isEmpty) {
      state = const ActorThumbState(message: '所有演员都已有头像');
      return;
    }
    _cancel = false;
    state = ActorThumbState(running: true, total: todo.length);
    final key = effectiveTmdbKey(db);
    var found = 0;
    for (var i = 0; i < todo.length; i++) {
      if (_cancel) break;
      final name = todo[i];
      // 演员名可能已被翻成中文，JavBus / TMDB 都只认原名，用原名去查。
      final orig = db.originalActorName(name);
      String? thumb;
      try {
        thumb = await javbusActorThumb(orig);
        if (thumb == null && orig != name) thumb = await javbusActorThumb(name);
        if (thumb == null && key.trim().isNotEmpty) thumb = await tmdbPersonThumb(orig, key);
      } catch (_) {
        thumb = null;
      }
      if (thumb != null) {
        db.setActorThumb(name, thumb);
        found++;
      }
      state = ActorThumbState(running: true, done: i + 1, total: todo.length);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    ref.read(libraryRevisionProvider.notifier).bump();
    state = ActorThumbState(
      message: _cancel ? '已停止：新增 $found 个头像' : '补全完成：新增 $found / ${todo.length} 个头像',
    );
  }
}
