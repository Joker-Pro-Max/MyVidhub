import '../data/sources/media_source.dart';
import '../domain/filename_parser.dart';
import '../domain/media_extensions.dart';
import '../domain/nfo_parser.dart';

class ScannedFile {
  const ScannedFile(this.path, this.size, this.modified);
  final String path;
  final int size;
  final DateTime? modified;
}

class ScannedActor {
  const ScannedActor(this.name, this.role, this.thumb);
  final String name;
  final String? role;
  final String? thumb;
}

sealed class ScannedItem {
  ScannedItem({
    required this.key,
    required this.dir,
    required this.title,
    this.nfo,
    this.nfoPath,
    this.year,
    this.poster,
    this.fanart,
    this.logo,
    this.actors = const [],
  });

  /// 在一个媒体源内唯一的身份标识（重扫时用来保留"添加时间"等状态）。
  final String key;
  final String dir;
  final String title;
  final NfoData? nfo;
  final String? nfoPath;
  final int? year;
  final String? poster;
  final String? fanart;
  final String? logo;
  final List<ScannedActor> actors;
}

class ScannedMovie extends ScannedItem {
  ScannedMovie({
    required super.key,
    required super.dir,
    required super.title,
    required this.files,
    super.nfo,
    super.nfoPath,
    super.year,
    super.poster,
    super.fanart,
    super.logo,
    super.actors,
  });
  final List<ScannedFile> files;
}

class ScannedEpisode {
  ScannedEpisode({
    required this.file,
    required this.season,
    required this.episode,
    required this.title,
    this.plot,
    this.aired,
    this.rating,
    this.runtime,
    this.thumb,
    this.nfoPath,
  });
  final ScannedFile file;
  final int season;
  final int? episode;
  final String title;
  final String? plot;
  final String? aired;
  final double? rating;
  final int? runtime;
  final String? thumb;
  final String? nfoPath;
}

class ScannedShow extends ScannedItem {
  ScannedShow({
    required super.key,
    required super.dir,
    required super.title,
    required this.episodes,
    required this.seasonPosters,
    super.nfo,
    super.nfoPath,
    super.year,
    super.poster,
    super.fanart,
    super.logo,
    super.actors,
  });
  final List<ScannedEpisode> episodes;
  final Map<int, String> seasonPosters;
}

/// 递归遍历媒体源，识别电影 / 剧集，并读取 NFO 与本地图片。
///
/// 识别规则（兼容 Kodi / Jellyfin / Emby / tinyMediaManager 目录结构）：
/// - 目录内有 `tvshow.nfo`，或子目录是 `Season 1` / `第1季` → 剧集根目录
/// - 目录内视频大多带 `S01E02` 之类集号 → 剧集（无 tvshow.nfo 的散装剧集）
/// - 其余视频 → 电影；同名 `CD1/CD2/part1` 合并为同一部；
///   有 `movie.nfo` 时整个目录视为一部电影（多版本）
class LibraryScanner {
  LibraryScanner(this.source, {this.onProgress, this.isCancelled});

  final MediaSource source;
  final void Function(String dir, int itemsFound)? onProgress;
  final bool Function()? isCancelled;

  int _found = 0;

  Stream<ScannedItem> scan() async* {
    yield* _scanDir(source.rootPath, depth: 0);
  }

  Stream<ScannedItem> _scanDir(String dir, {required int depth}) async* {
    if (depth > 12 || (isCancelled?.call() ?? false)) return;
    onProgress?.call(dir, _found);

    final entries = await source.list(dir)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final files = entries.where((e) => !e.isDir).toList();
    final dirs = entries.where((e) => e.isDir && !isIgnoredDir(e.name)).toList();
    final fileIndex = {for (final f in files) f.name.toLowerCase(): f};

    final hasTvshowNfo = fileIndex.containsKey('tvshow.nfo');
    final seasonDirs = dirs.where((d) => seasonFromDirName(d.name) != null).toList();
    final videos = files.where((f) => isVideoFile(f.name)).toList();

    // 1. 剧集根目录
    if (hasTvshowNfo || (seasonDirs.isNotEmpty && videos.isEmpty)) {
      final show = await _scanShow(dir, entries);
      if (show != null) {
        _found++;
        yield show;
      }
      return;
    }

    if (videos.isNotEmpty) {
      // 2. 散装剧集（没有 tvshow.nfo，但文件名带集号）
      final epCount = videos
          .where((v) => FilenameParser.parse(baseNameOf(v.name)).isEpisode)
          .length;
      final isSeasonDir = seasonFromDirName(_name(dir)) != null;
      if (epCount >= 2 && epCount * 2 >= videos.length || isSeasonDir && epCount > 0) {
        final show = await _scanShow(dir, entries);
        if (show != null) {
          _found++;
          yield show;
        }
        return;
      }

      // 3. 电影
      for (final m in await _scanMovies(dir, entries, fileIndex, videos)) {
        _found++;
        yield m;
      }
    }

    for (final d in dirs) {
      yield* _scanDir(d.path, depth: depth + 1);
    }
  }

  // ---------------------------------------------------------------- 电影

  Future<List<ScannedMovie>> _scanMovies(
    String dir,
    List<SourceEntry> entries,
    Map<String, SourceEntry> fileIndex,
    List<SourceEntry> videos,
  ) async {
    final actorThumbs = await _actorThumbs(entries);

    // 有 movie.nfo：整个目录 = 一部电影
    final movieNfo = fileIndex['movie.nfo'];
    final groups = <String, List<SourceEntry>>{};
    if (movieNfo != null) {
      groups[baseNameOf(videos.first.name)] = videos;
    } else {
      for (final v in videos) {
        groups.putIfAbsent(_stackBase(baseNameOf(v.name)), () => []).add(v);
      }
    }
    final single = groups.length == 1;

    final out = <ScannedMovie>[];
    for (final entry in groups.entries) {
      final vids = entry.value..sort((a, b) => a.name.compareTo(b.name));
      final bases = {
        for (final v in vids) baseNameOf(v.name).toLowerCase(),
        entry.key.toLowerCase(),
      };

      SourceEntry? nfoEntry = movieNfo;
      if (nfoEntry == null) {
        for (final b in bases) {
          nfoEntry = fileIndex['$b.nfo'];
          if (nfoEntry != null) break;
        }
      }
      final nfo = nfoEntry == null ? null : await _readNfo(nfoEntry.path);
      if (nfo != null && nfo.kind == NfoKind.tvshow) continue;

      final parsed = FilenameParser.parse(
          single && movieNfo != null ? _name(dir) : entry.key);
      // 只有一部电影的目录：文件名解析不出年份时，用目录名（通常是 "片名 (年份)"）
      final dirParsed = single ? FilenameParser.parse(_name(dir)) : null;

      String? find(List<String> suffixes, List<String> generic) =>
          _findImage(fileIndex, [
            for (final b in bases)
              for (final s in suffixes) '$b$s',
            if (single) ...generic,
          ]);

      out.add(ScannedMovie(
        key: vids.first.path,
        dir: dir,
        title: nfo?.title ??
            (parsed.year == null && dirParsed?.year != null ? dirParsed!.title : parsed.title),
        year: nfo?.year ?? parsed.year ?? dirParsed?.year,
        nfo: nfo,
        nfoPath: nfoEntry?.path,
        files: [for (final v in vids) ScannedFile(v.path, v.size, v.modified)],
        poster: find(['-poster', '.poster', '-cover', ''], ['poster', 'folder', 'cover', 'movie']),
        fanart: find(['-fanart', '.fanart', '-backdrop', '-background'], ['fanart', 'backdrop', 'background']),
        logo: find(['-clearlogo', '-logo'], ['clearlogo', 'logo']),
        actors: _actors(nfo, actorThumbs),
      ));
    }
    return out;
  }

  /// "Movie CD1" / "Movie.part2" → "Movie"
  static String _stackBase(String base) => base
      .replaceFirst(
          RegExp(r'[ ._\-]*[\[(]?(cd|dvd|part|pt|disc|disk)[ ._\-]*\d+[\])]?$', caseSensitive: false),
          '')
      .trim();

  // ---------------------------------------------------------------- 剧集

  Future<ScannedShow?> _scanShow(String dir, List<SourceEntry> rootEntries) async {
    final rootFiles = rootEntries.where((e) => !e.isDir).toList();
    final rootIndex = {for (final f in rootFiles) f.name.toLowerCase(): f};
    final nfoEntry = rootIndex['tvshow.nfo'];
    final nfo = nfoEntry == null ? null : await _readNfo(nfoEntry.path);

    // 如果当前目录本身是 "Season 1"（散装），剧名来自上级目录
    final dirName = _name(dir);
    final dirSeason = seasonFromDirName(dirName);
    final parsedDir = FilenameParser.parse(dirSeason != null ? _name(_parent(dir)) : dirName);

    final seasonPosters = <int, String>{};
    for (final f in rootFiles) {
      final m = RegExp(r'^season[ _\-]?(\d{1,3}|specials|all)-poster\.(jpe?g|png|webp)$',
              caseSensitive: false)
          .firstMatch(f.name);
      if (m != null) {
        final s = m.group(1)!.toLowerCase();
        final n = s == 'specials' ? 0 : s == 'all' ? -1 : int.parse(s);
        seasonPosters[n] = f.path;
      }
    }

    final episodes = <ScannedEpisode>[];
    final firstEpisodeTitle = <String>[];

    Future<void> walk(String d, List<SourceEntry> entries, int? folderSeason, int depth) async {
      if (depth > 4) return;
      final files = entries.where((e) => !e.isDir).toList();
      final index = {for (final f in files) f.name.toLowerCase(): f};

      if (folderSeason != null && depth > 0) {
        final sp = _findImage(index, ['poster', 'folder', 'cover']);
        if (sp != null) seasonPosters.putIfAbsent(folderSeason, () => sp);
      }

      for (final v in files.where((f) => isVideoFile(f.name))) {
        final base = baseNameOf(v.name);
        final epNfoEntry = index['${base.toLowerCase()}.nfo'];
        final epNfo = epNfoEntry == null ? null : await _readNfo(epNfoEntry.path);
        final parsed = FilenameParser.parse(base);
        if (firstEpisodeTitle.isEmpty) firstEpisodeTitle.add(parsed.title);
        final season = epNfo?.season ?? parsed.season ?? folderSeason ?? 1;
        final episode = epNfo?.episode ?? parsed.episode;
        episodes.add(ScannedEpisode(
          file: ScannedFile(v.path, v.size, v.modified),
          season: season,
          episode: episode,
          title: epNfo?.title ?? (episode != null ? '第 $episode 集' : base),
          plot: epNfo?.plot,
          aired: epNfo?.premiered,
          rating: epNfo?.rating,
          runtime: epNfo?.runtime,
          thumb: _findImage(index, [
            '${base.toLowerCase()}-thumb',
            '${base.toLowerCase()}.thumb',
            base.toLowerCase(),
          ]),
          nfoPath: epNfoEntry?.path,
        ));
      }

      for (final sub in entries.where((e) => e.isDir && !isIgnoredDir(e.name))) {
        final subEntries = await source.list(sub.path)
          ..sort((a, b) => a.name.compareTo(b.name));
        await walk(sub.path, subEntries, seasonFromDirName(sub.name) ?? folderSeason, depth + 1);
      }
    }

    await walk(dir, rootEntries, dirSeason, 0);
    if (episodes.isEmpty) return null;

    episodes.sort((a, b) {
      final s = a.season.compareTo(b.season);
      if (s != 0) return s;
      if (a.episode != null && b.episode != null) return a.episode!.compareTo(b.episode!);
      return a.file.path.compareTo(b.file.path);
    });

    // 无 tvshow.nfo 且目录名不像剧名（如 "Season 1"）时，用文件名里的剧名
    var title = nfo?.title ?? parsedDir.title;
    if (nfo == null && dirSeason != null && firstEpisodeTitle.isNotEmpty &&
        firstEpisodeTitle.first.isNotEmpty && _parent(dir) == source.rootPath) {
      title = firstEpisodeTitle.first;
    }

    final actorThumbs = await _actorThumbs(rootEntries);
    return ScannedShow(
      key: dir,
      dir: dir,
      title: title,
      year: nfo?.year ?? parsedDir.year,
      nfo: nfo,
      nfoPath: nfoEntry?.path,
      episodes: episodes,
      seasonPosters: seasonPosters,
      poster: _findImage(rootIndex, ['poster', 'folder', 'cover', 'show']) ?? seasonPosters[-1],
      fanart: _findImage(rootIndex, ['fanart', 'backdrop', 'background']),
      logo: _findImage(rootIndex, ['clearlogo', 'logo']),
      actors: _actors(nfo, actorThumbs),
    );
  }

  // ---------------------------------------------------------------- 工具

  Future<NfoData?> _readNfo(String path) async {
    try {
      return NfoParser.parseBytes(await source.readBytes(path));
    } catch (_) {
      return null;
    }
  }

  /// Kodi 风格本地演员头像：`.actors/Tom_Hanks.jpg`
  Future<Map<String, String>> _actorThumbs(List<SourceEntry> entries) async {
    final out = <String, String>{};
    final actorsDir = entries.where((e) => e.isDir && e.name == '.actors').firstOrNull;
    if (actorsDir == null) return out;
    for (final f in await source.list(actorsDir.path)) {
      if (!f.isDir && isImageFile(f.name)) {
        out[baseNameOf(f.name).replaceAll('_', ' ').toLowerCase()] = f.path;
      }
    }
    return out;
  }

  List<ScannedActor> _actors(NfoData? nfo, Map<String, String> localThumbs) => [
        for (final a in nfo?.actors ?? const <NfoActor>[])
          ScannedActor(a.name, a.role, localThumbs[a.name.toLowerCase()] ?? a.thumb),
      ];

  String? _findImage(Map<String, SourceEntry> index, List<String> bases) {
    for (final b in bases) {
      for (final ext in const ['jpg', 'jpeg', 'png', 'webp']) {
        final e = index['$b.$ext'];
        if (e != null) return source.localImagePath(e.path);
      }
    }
    return null;
  }

  static String _name(String path) {
    final parts = path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  static String _parent(String path) {
    final i = path.replaceAll(RegExp(r'[/\\]+$'), '').lastIndexOf(RegExp(r'[/\\]'));
    return i <= 0 ? path : path.substring(0, i);
  }
}
