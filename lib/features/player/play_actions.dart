import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/models.dart';
import 'play_item.dart';
import 'player_page.dart';

/// 直接播放一个条目：电影播第一个文件（自动续播），剧集从该续看的那一集开始。
/// [path] 指定时播放这个文件 / 这一集。
Future<void> playItem(BuildContext context, WidgetRef ref, int itemId, {String? path}) async {
  final db = ref.read(dbProvider);
  final d = db.detail(itemId);
  if (d == null) return;
  if (d.kind == MediaKind.movie) {
    final target = path ?? (d.files.isEmpty ? null : d.files.first.path);
    if (target == null) return;
    return PlayerPage.open(context, ref, movieQueue(d, target));
  }
  final queue = showQueue(db, d.id, d.title);
  if (queue.isEmpty) return;
  int index;
  if (path != null) {
    index = queue.indexWhere((q) => q.path == path);
  } else {
    index = resumeEpisodeIndex(db.allEpisodes(d.id), db.progressForItem(d.id));
  }
  return PlayerPage.open(context, ref, queue, index.clamp(0, queue.length - 1));
}
