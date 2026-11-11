import 'package:path/path.dart' as p;

import '../../data/db/library_db.dart';
import '../../data/db/models.dart';

/// 播放队列中的一项。
class PlayItem {
  const PlayItem({required this.path, required this.title, this.subtitle, this.itemId});
  final String path;
  final String title;
  final String? subtitle;
  final int? itemId;
}

/// 电影：只放所选的那个文件（多版本不连播）。
List<PlayItem> movieQueue(MediaDetail d, String path) => [
      PlayItem(
        path: path,
        title: d.title,
        subtitle: d.files.length > 1 ? p.basename(path) : (d.year != null ? '${d.year}' : null),
        itemId: d.id,
      ),
    ];

/// 剧集：整部剧所有季按顺序连播。
List<PlayItem> showQueue(LibraryDb db, int itemId, String showTitle) => [
      for (final e in db.allEpisodes(itemId))
        PlayItem(path: e.path, title: showTitle, subtitle: episodeLabel(e), itemId: itemId),
    ];

String episodeLabel(EpisodeRow e) {
  final s = e.season == 0 ? '特别篇' : 'S${e.season.toString().padLeft(2, '0')}';
  final ep = e.episode != null ? 'E${e.episode.toString().padLeft(2, '0')}' : '';
  return '$s$ep · ${e.title}';
}

/// 剧集详情页"播放"按钮应该从哪一集开始：
/// 最后一个有进度的集未看完 → 它；看完了 → 下一集；都没看 → 第一集。
int resumeEpisodeIndex(List<EpisodeRow> eps, Map<String, PlaybackProgress> progress) {
  var last = -1;
  for (var i = 0; i < eps.length; i++) {
    if (progress.containsKey(eps[i].path)) last = i;
  }
  if (last < 0) return 0;
  final pr = progress[eps[last].path]!;
  if (!pr.finished) return last;
  return last + 1 < eps.length ? last + 1 : 0;
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
