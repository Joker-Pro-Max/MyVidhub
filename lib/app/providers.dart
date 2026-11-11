import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/library_db.dart';
import '../data/db/models.dart';
import '../services/scan_service.dart';

/// 在 main() 中初始化后通过 overrides 注入。
final dbPathProvider = Provider<String>((ref) => throw UnimplementedError());
final dbProvider = Provider<LibraryDb>((ref) => throw UnimplementedError());

/// 媒体库内容变化时 +1，所有查询 provider 依赖它自动刷新。
final libraryRevisionProvider =
    NotifierProvider<LibraryRevision, int>(LibraryRevision.new);

class LibraryRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final sourcesProvider = Provider<List<SourceRow>>((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).sources();
});

typedef LibraryQuery = ({MediaKind kind, SortOrder sort, String? genre, int? limit, WatchFilter filter});

final itemsProvider = Provider.family<List<MediaSummary>, LibraryQuery>((ref, q) {
  ref.watch(libraryRevisionProvider);
  return ref
      .watch(dbProvider)
      .listItems(kind: q.kind, sort: q.sort, genre: q.genre, limit: q.limit, filter: q.filter);
});

final favoritesProvider = Provider<List<MediaSummary>>((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).favorites(limit: 30);
});

final isFavoriteProvider = Provider.family<bool, int>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).isFavorite(id);
});

typedef SearchResults = ({
  List<MediaSummary> movies,
  List<MediaSummary> shows,
  List<PersonHit> people,
  List<EpisodeHit> episodes,
});

final searchProvider = Provider.family<SearchResults, String>((ref, q) {
  ref.watch(libraryRevisionProvider);
  final db = ref.watch(dbProvider);
  if (q.trim().isEmpty) return (movies: const [], shows: const [], people: const [], episodes: const []);
  final items = db.searchItems(q);
  return (
    movies: [for (final m in items) if (m.kind == MediaKind.movie) m],
    shows: [for (final m in items) if (m.kind == MediaKind.show) m],
    people: db.searchPeople(q),
    episodes: db.searchEpisodes(q),
  );
});

final actorItemsProvider = Provider.family<List<MediaSummary>, String>((ref, name) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).itemsWithActor(name);
});

final sameSetProvider = Provider.family<List<MediaSummary>, int>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).sameSet(id);
});

final similarProvider = Provider.family<List<MediaSummary>, int>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).similar(id);
});

/// 搜索页"按类型浏览"：每个类型取评分最高、有剧照的条目做封面。
typedef GenreTile = ({String genre, int count, String? image});

final genreTilesProvider = Provider<List<GenreTile>>((ref) {
  ref.watch(libraryRevisionProvider);
  final db = ref.watch(dbProvider);
  final all = [
    ...db.listItems(kind: MediaKind.movie, sort: SortOrder.rating),
    ...db.listItems(kind: MediaKind.show, sort: SortOrder.rating),
  ];
  final count = <String, int>{};
  final image = <String, String>{};
  for (final m in all) {
    for (final g in m.genres) {
      count[g] = (count[g] ?? 0) + 1;
      if (m.fanart != null) image.putIfAbsent(g, () => m.fanart!); // 优先剧照（列表已按评分排序）
    }
  }
  for (final m in all) {
    for (final g in m.genres) {
      if (m.poster != null) image.putIfAbsent(g, () => m.poster!); // 没有剧照时退回海报
    }
  }
  final genres = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
  return [for (final g in genres.take(12)) (genre: g, count: count[g]!, image: image[g])];
});

/// 某个类型下的电影 + 剧集（按评分）。
final genreItemsProvider = Provider.family<List<MediaSummary>, String>((ref, genre) {
  ref.watch(libraryRevisionProvider);
  final db = ref.watch(dbProvider);
  return [
    ...db.listItems(kind: MediaKind.movie, sort: SortOrder.rating, genre: genre),
    ...db.listItems(kind: MediaKind.show, sort: SortOrder.rating, genre: genre),
  ];
});

final genresProvider = Provider.family<List<String>, MediaKind>((ref, kind) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).genres(kind);
});

final detailProvider = Provider.family<MediaDetail?, int>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).detail(id);
});

final continueWatchingProvider = Provider<List<ContinueItem>>((ref) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).continueWatching();
});

final itemProgressProvider = Provider.family<Map<String, PlaybackProgress>, int>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).progressForItem(id);
});

final allEpisodesProvider = Provider.family<List<EpisodeRow>, int>((ref, id) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).allEpisodes(id);
});

final episodesProvider = Provider.family<List<EpisodeRow>, (int, int)>((ref, arg) {
  ref.watch(libraryRevisionProvider);
  return ref.watch(dbProvider).episodes(arg.$1, arg.$2);
});

// ------------------------------------------------------------------ 扫描

class ScanState {
  const ScanState({this.sourceId, this.dir, this.found = 0, this.queue = const [], this.lastMessage});
  final int? sourceId;
  final String? dir;
  final int found;
  final List<int> queue;
  final String? lastMessage;

  bool get running => sourceId != null;
}

final scanProvider = NotifierProvider<ScanController, ScanState>(ScanController.new);

class ScanController extends Notifier<ScanState> {
  ScanJob? _job;
  StreamSubscription<ScanEvent>? _sub;

  @override
  ScanState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _job?.cancel();
    });
    return const ScanState();
  }

  void scan(int sourceId) {
    if (state.sourceId == sourceId || state.queue.contains(sourceId)) return;
    if (state.running) {
      state = ScanState(
        sourceId: state.sourceId,
        dir: state.dir,
        found: state.found,
        queue: [...state.queue, sourceId],
      );
      return;
    }
    _start(sourceId, state.queue);
  }

  void scanAll() {
    for (final s in ref.read(sourcesProvider)) {
      scan(s.id);
    }
  }

  void cancel() {
    _job?.cancel();
  }

  Future<void> _start(int sourceId, List<int> queue) async {
    final source = ref.read(sourcesProvider).where((s) => s.id == sourceId).firstOrNull;
    if (source == null) {
      _next(queue, null);
      return;
    }
    state = ScanState(sourceId: sourceId, queue: queue);
    final job = await ScanJob.start(
      dbPath: ref.read(dbPathProvider),
      sourceId: sourceId,
      root: source.root,
      type: source.type,
      config: source.config,
    );
    _job = job;
    var lastBump = DateTime.now();
    _sub = job.events.listen((e) {
      if (e.done) {
        _job = null;
        _sub?.cancel();
        ref.read(libraryRevisionProvider.notifier).bump();
        _next(state.queue, e.error ?? '「${source.name}」扫描完成，共 ${e.found} 个条目');
        return;
      }
      state = ScanState(sourceId: sourceId, dir: e.dir, found: e.found, queue: state.queue);
      // 扫描过程中每 2 秒刷新一次界面，海报墙逐步出现
      if (DateTime.now().difference(lastBump).inSeconds >= 2) {
        lastBump = DateTime.now();
        ref.read(libraryRevisionProvider.notifier).bump();
      }
    });
  }

  void _next(List<int> queue, String? message) {
    if (queue.isEmpty) {
      state = ScanState(lastMessage: message);
    } else {
      _start(queue.first, queue.sublist(1));
    }
  }
}
