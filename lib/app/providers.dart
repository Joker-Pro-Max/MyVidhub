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

typedef LibraryQuery = ({MediaKind kind, SortOrder sort, String? genre, int? limit});

final itemsProvider = Provider.family<List<MediaSummary>, LibraryQuery>((ref, q) {
  ref.watch(libraryRevisionProvider);
  return ref
      .watch(dbProvider)
      .listItems(kind: q.kind, sort: q.sort, genre: q.genre, limit: q.limit);
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
