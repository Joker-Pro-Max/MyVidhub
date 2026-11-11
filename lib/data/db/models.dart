enum MediaKind { movie, show }

enum WatchFilter {
  all('全部'),
  unwatched('未看'),
  watched('已看'),
  favorite('收藏');

  const WatchFilter(this.label);
  final String label;
}

class PersonHit {
  const PersonHit(this.name, this.thumb, this.itemCount);
  final String name;
  final String? thumb;
  final int itemCount;
}

class EpisodeHit {
  const EpisodeHit(this.showId, this.showTitle, this.episode);
  final int showId;
  final String showTitle;
  final EpisodeRow episode;
}

enum SortOrder {
  added('最近添加'),
  title('标题'),
  year('年份'),
  rating('评分');

  const SortOrder(this.label);
  final String label;
}

class SourceRow {
  const SourceRow({
    required this.id,
    required this.type,
    required this.name,
    required this.root,
    required this.itemCount,
    this.lastScanAt,
    this.config,
  });
  final int id;

  /// local / webdav / smb
  final String type;
  final String name;
  final String root;
  final int itemCount;
  final DateTime? lastScanAt;

  /// 网络源连接配置（JSON）。
  final String? config;

  bool get isNetwork => type != 'local';
}

class MediaSummary {
  const MediaSummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.episodeCount,
    this.watchedCount = 0,
    this.progress,
    this.originalTitle,
    this.year,
    this.rating,
    this.poster,
    this.fanart,
    this.logo,
    this.genres = const [],
    this.favorite = false,
  });
  final int id;
  final MediaKind kind;
  final String title;
  final String? originalTitle;
  final int? year;
  final double? rating;
  final String? poster;
  final String? fanart;
  final String? logo;
  final List<String> genres;
  final bool favorite;
  final int episodeCount;
  final int watchedCount;

  /// 电影未看完时的进度 0–1。
  final double? progress;

  /// 剧集看了一部分时剩余的集数；没开始看或已看完返回 0。
  int get unwatchedEpisodes =>
      kind == MediaKind.show && watchedCount > 0 && watchedCount < episodeCount ? episodeCount - watchedCount : 0;

  bool get watched => kind == MediaKind.movie
      ? watchedCount > 0
      : episodeCount > 0 && watchedCount >= episodeCount;
}

class PlaybackProgress {
  const PlaybackProgress({
    required this.path,
    required this.positionMs,
    required this.durationMs,
    required this.finished,
  });
  final String path;
  final int positionMs;
  final int durationMs;
  final bool finished;

  double get fraction => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);
}

class ContinueItem {
  const ContinueItem({
    required this.itemId,
    required this.kind,
    required this.title,
    required this.path,
    required this.positionMs,
    required this.durationMs,
    this.poster,
    this.fanart,
    this.episodeLabel,
  });
  final int itemId;
  final MediaKind kind;
  final String title;
  final String? poster;
  final String? fanart;
  final String path;
  final int positionMs;
  final int durationMs;
  final String? episodeLabel;

  double get fraction => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);
}

class ActorRow {
  const ActorRow(this.name, this.role, this.thumb);
  final String name;
  final String? role;
  final String? thumb;
}

class FileRow {
  const FileRow(this.path, this.size);
  final String path;
  final int size;
}

class SeasonRow {
  const SeasonRow(this.season, this.poster, this.episodeCount);
  final int season;
  final String? poster;
  final int episodeCount;

  String get label => season == 0 ? '特别篇' : '第 $season 季';
}

class EpisodeRow {
  const EpisodeRow({
    required this.id,
    required this.season,
    required this.title,
    required this.path,
    required this.size,
    this.episode,
    this.plot,
    this.aired,
    this.rating,
    this.runtime,
    this.thumb,
  });
  final int id;
  final int season;
  final int? episode;
  final String title;
  final String? plot;
  final String? aired;
  final double? rating;
  final int? runtime;
  final String path;
  final int size;
  final String? thumb;
}

class MediaDetail {
  const MediaDetail({
    required this.id,
    required this.kind,
    required this.title,
    required this.dir,
    required this.genres,
    required this.countries,
    required this.studios,
    required this.directors,
    required this.writers,
    required this.actors,
    required this.files,
    required this.seasons,
    this.originalTitle,
    this.year,
    this.plot,
    this.tagline,
    this.rating,
    this.runtime,
    this.premiered,
    this.mpaa,
    this.setName,
    this.status,
    this.poster,
    this.fanart,
    this.logo,
  });
  final int id;
  final MediaKind kind;
  final String title;
  final String? originalTitle;
  final int? year;
  final String? plot;
  final String? tagline;
  final double? rating;
  final int? runtime;
  final String? premiered;
  final String? mpaa;
  final String? setName;
  final String? status;
  final List<String> genres;
  final List<String> countries;
  final List<String> studios;
  final List<String> directors;
  final List<String> writers;
  final String? poster;
  final String? fanart;
  final String? logo;
  final String dir;
  final List<ActorRow> actors;
  final List<FileRow> files;
  final List<SeasonRow> seasons;
}
