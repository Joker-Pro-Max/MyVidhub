import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../../services/library_scanner.dart';
import 'models.dart';

/// 媒体库数据库。主线程只读查询；扫描在后台 Isolate 中另开连接写入（WAL 模式）。
class LibraryDb {
  LibraryDb._(this._db);

  final Database _db;

  static const _schemaVersion = 7;

  static LibraryDb open(String path) {
    final db = sqlite3.open(path);
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA foreign_keys=ON;');
    db.execute('PRAGMA busy_timeout=5000;');
    final ldb = LibraryDb._(db);
    ldb._migrate();
    return ldb;
  }

  void dispose() => _db.close();

  void _migrate() {
    final v = _db.select('PRAGMA user_version').first.values.first as int;
    if (v >= _schemaVersion) return;
    if (v < 1) _createV1();
    if (v < 2) {
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_files_path ON files(path);
        CREATE INDEX IF NOT EXISTS idx_episodes_path ON episodes(path);
        CREATE INDEX IF NOT EXISTS idx_playback_updated ON playback_state(updated_at DESC);
      ''');
    }
    if (v < 3) {
      _db.execute('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)');
    }
    if (v < 4) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS favorites (
          item_id INTEGER PRIMARY KEY REFERENCES items(id) ON DELETE CASCADE,
          added_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_items_set ON items(set_name);
      ''');
    }
    if (v < 5) {
      // 网络源的连接配置（JSON：地址、用户名、密码等）
      _db.execute('ALTER TABLE sources ADD COLUMN config TEXT');
    }
    if (v < 6) {
      // 「从媒体库中移除」的条目：重新扫描时跳过
      _db.execute('''CREATE TABLE IF NOT EXISTS excluded_items (
        source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        key TEXT NOT NULL,
        title TEXT,
        PRIMARY KEY (source_id, key))''');
    }
    if (v < 7) {
      _db.execute('''
        ALTER TABLE items ADD COLUMN is_av INTEGER NOT NULL DEFAULT 0;
        CREATE TABLE IF NOT EXISTS av_overrides (
          source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
          key TEXT NOT NULL,
          is_av INTEGER NOT NULL,
          PRIMARY KEY (source_id, key));
        CREATE TABLE IF NOT EXISTS auto_scrape_attempts (path TEXT PRIMARY KEY, at INTEGER NOT NULL);
      ''');
    }
    _db.execute('PRAGMA user_version = $_schemaVersion;');
  }

  // ------------------------------------------------------------ 设置

  String? setting(String key) {
    final r = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  void setSetting(String key, String? value) {
    if (value == null) {
      _db.execute('DELETE FROM settings WHERE key = ?', [key]);
    } else {
      _db.execute('INSERT INTO settings(key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value', [key, value]);
    }
  }

  void _createV1() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        root TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        last_scan_at INTEGER
      );
      CREATE TABLE IF NOT EXISTS items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id INTEGER NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
        key TEXT NOT NULL,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        original_title TEXT,
        sort_title TEXT,
        year INTEGER,
        plot TEXT,
        tagline TEXT,
        rating REAL,
        runtime INTEGER,
        premiered TEXT,
        mpaa TEXT,
        set_name TEXT,
        status TEXT,
        genres TEXT,
        countries TEXT,
        studios TEXT,
        directors TEXT,
        writers TEXT,
        tags TEXT,
        unique_ids TEXT,
        poster TEXT,
        fanart TEXT,
        logo TEXT,
        dir TEXT NOT NULL,
        nfo_path TEXT,
        added_at INTEGER NOT NULL,
        scanned_at INTEGER NOT NULL,
        UNIQUE(source_id, key)
      );
      CREATE INDEX IF NOT EXISTS idx_items_kind ON items(kind, added_at DESC);
      CREATE TABLE IF NOT EXISTS files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
        path TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS idx_files_item ON files(item_id);
      CREATE TABLE IF NOT EXISTS episodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
        season INTEGER NOT NULL,
        episode INTEGER,
        title TEXT NOT NULL,
        plot TEXT,
        aired TEXT,
        rating REAL,
        runtime INTEGER,
        path TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0,
        thumb TEXT,
        nfo_path TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_episodes_item ON episodes(item_id, season, episode);
      CREATE TABLE IF NOT EXISTS seasons (
        item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
        season INTEGER NOT NULL,
        poster TEXT,
        PRIMARY KEY(item_id, season)
      );
      CREATE TABLE IF NOT EXISTS actors (
        item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
        ord INTEGER NOT NULL,
        name TEXT NOT NULL,
        role TEXT,
        thumb TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_actors_item ON actors(item_id);
      CREATE INDEX IF NOT EXISTS idx_actors_name ON actors(name);
      CREATE TABLE IF NOT EXISTS playback_state (
        path TEXT PRIMARY KEY,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        finished INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      );
    ''');
  }

  // ------------------------------------------------------------ 媒体源

  List<SourceRow> sources() => _db
      .select('SELECT s.*, (SELECT COUNT(*) FROM items i WHERE i.source_id = s.id) AS n '
          'FROM sources s ORDER BY s.id')
      .map((r) => SourceRow(
            id: r['id'] as int,
            type: r['type'] as String,
            name: r['name'] as String,
            root: r['root'] as String,
            config: r['config'] as String?,
            lastScanAt: _date(r['last_scan_at']),
            itemCount: r['n'] as int,
          ))
      .toList();

  int addSource({required String type, required String name, required String root, String? config}) {
    _db.execute('INSERT INTO sources(type, name, root, created_at, config) VALUES (?, ?, ?, ?, ?)',
        [type, name, root, _now(), config]);
    return _db.lastInsertRowId;
  }

  SourceRow? source(int id) => sources().where((s) => s.id == id).firstOrNull;

  void deleteSource(int id) => _db.execute('DELETE FROM sources WHERE id = ?', [id]);

  // ------------------------------------------------------------ 扫描写入

  /// 开始一次扫描：返回扫描批次时间戳，写入的条目都会打上这个时间。
  int beginScan() => _now();

  void writeItem(int sourceId, ScannedItem item, int scanStamp) {
    if (_db.select('SELECT 1 FROM excluded_items WHERE source_id = ? AND key = ?', [sourceId, item.key]).isNotEmpty) {
      return; // 用户从媒体库移除过
    }
    final nfo = item.nfo;
    final kind = item is ScannedShow ? 'show' : 'movie';
    _db.execute('BEGIN');
    try {
      _db.execute('''
        INSERT INTO items(source_id, key, kind, title, original_title, sort_title, year, plot,
          tagline, rating, runtime, premiered, mpaa, set_name, status, genres, countries, studios,
          directors, writers, tags, unique_ids, poster, fanart, logo, dir, nfo_path, added_at, scanned_at, is_av)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(source_id, key) DO UPDATE SET
          kind=excluded.kind, title=excluded.title, original_title=excluded.original_title,
          sort_title=excluded.sort_title, year=excluded.year, plot=excluded.plot,
          tagline=excluded.tagline, rating=excluded.rating, runtime=excluded.runtime,
          premiered=excluded.premiered, mpaa=excluded.mpaa, set_name=excluded.set_name,
          status=excluded.status, genres=excluded.genres, countries=excluded.countries,
          studios=excluded.studios, directors=excluded.directors, writers=excluded.writers,
          tags=excluded.tags, unique_ids=excluded.unique_ids, poster=excluded.poster,
          fanart=excluded.fanart, logo=excluded.logo, dir=excluded.dir,
          nfo_path=excluded.nfo_path, scanned_at=excluded.scanned_at, is_av=excluded.is_av
      ''', [
        sourceId, item.key, kind, item.title, nfo?.originalTitle, nfo?.sortTitle, item.year,
        nfo?.plot, nfo?.tagline, nfo?.rating, nfo?.runtime, nfo?.premiered, nfo?.mpaa,
        nfo?.setName, nfo?.status, _list(nfo?.genres), _list(nfo?.countries),
        _list(nfo?.studios), _list(nfo?.directors), _list(nfo?.writers), _list(nfo?.tags),
        nfo == null || nfo.uniqueIds.isEmpty ? null : jsonEncode(nfo.uniqueIds),
        item.poster, item.fanart, item.logo, item.dir, item.nfoPath, scanStamp, scanStamp,
        _isAv(sourceId, item) ? 1 : 0,
      ]);
      final id = _db
          .select('SELECT id FROM items WHERE source_id = ? AND key = ?', [sourceId, item.key])
          .first['id'] as int;

      for (final t in ['files', 'episodes', 'seasons', 'actors']) {
        _db.execute('DELETE FROM $t WHERE item_id = ?', [id]);
      }

      final actorStmt =
          _db.prepare('INSERT INTO actors(item_id, ord, name, role, thumb) VALUES (?,?,?,?,?)');
      for (var i = 0; i < item.actors.length; i++) {
        final a = item.actors[i];
        actorStmt.execute([id, i, a.name, a.role, a.thumb]);
      }
      actorStmt.close();

      switch (item) {
        case ScannedMovie(:final files):
          final st = _db.prepare('INSERT INTO files(item_id, path, size) VALUES (?,?,?)');
          for (final f in files) {
            st.execute([id, f.path, f.size]);
          }
          st.close();
        case ScannedShow(:final episodes, :final seasonPosters):
          final st = _db.prepare('''INSERT INTO episodes(item_id, season, episode, title, plot,
              aired, rating, runtime, path, size, thumb, nfo_path) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)''');
          final seasons = <int>{};
          for (final e in episodes) {
            seasons.add(e.season);
            st.execute([id, e.season, e.episode, e.title, e.plot, e.aired, e.rating, e.runtime,
              e.file.path, e.file.size, e.thumb, e.nfoPath]);
          }
          st.close();
          final ss = _db.prepare('INSERT INTO seasons(item_id, season, poster) VALUES (?,?,?)');
          for (final s in seasons) {
            ss.execute([id, s, seasonPosters[s]]);
          }
          ss.close();
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// 扫描完成：删除本次没扫到的条目（文件已被删除/移走）。
  void finishScan(int sourceId, int scanStamp) {
    _db.execute('DELETE FROM items WHERE source_id = ? AND scanned_at < ?', [sourceId, scanStamp]);
    _db.execute('UPDATE sources SET last_scan_at = ? WHERE id = ?', [_now(), sourceId]);
  }

  // ------------------------------------------------------------ 查询

  static const _summaryCols = '''i.id, i.kind, i.title, i.original_title, i.sort_title, i.year, i.rating,
      i.poster, i.fanart, i.logo, i.genres, i.added_at,
      EXISTS(SELECT 1 FROM favorites fv WHERE fv.item_id = i.id) AS favorite, i.is_av,
      (SELECT COUNT(*) FROM episodes e WHERE e.item_id = i.id) AS episode_count,
      (SELECT COUNT(*) FROM playback_state ps WHERE ps.finished = 1 AND ps.path IN
        (SELECT path FROM files WHERE item_id = i.id
         UNION ALL SELECT path FROM episodes WHERE item_id = i.id)) AS watched_count,
      (SELECT CAST(ps.position_ms AS REAL) / ps.duration_ms FROM files f
        JOIN playback_state ps ON ps.path = f.path
        WHERE f.item_id = i.id AND ps.finished = 0 AND ps.duration_ms > 0
        ORDER BY ps.updated_at DESC LIMIT 1) AS progress''';

  static const _watchedExpr = "((kind = 'movie' AND watched_count > 0) OR "
      "(kind = 'show' AND episode_count > 0 AND watched_count >= episode_count))";

  List<MediaSummary> listItems({
    required MediaKind kind,
    SortOrder sort = SortOrder.added,
    int? limit,
    String? genre,
    WatchFilter filter = WatchFilter.all,
  }) {
    final order = switch (sort) {
      SortOrder.added => 'added_at DESC, id DESC',
      SortOrder.title => 'COALESCE(sort_title, title) COLLATE NOCASE',
      SortOrder.year => 'year DESC NULLS LAST, title',
      SortOrder.rating => 'rating DESC NULLS LAST, title',
    };
    final where = StringBuffer('i.kind = ?');
    final args = <Object?>[kind.name];
    if (genre != null) {
      where.write(" AND ('|' || i.genres || '|') LIKE ?");
      args.add('%|$genre|%');
    }
    final outer = switch (filter) {
      WatchFilter.all => '1',
      WatchFilter.unwatched => 'NOT $_watchedExpr',
      WatchFilter.watched => _watchedExpr,
      WatchFilter.favorite => 'favorite = 1',
    };
    return _db
        .select('SELECT * FROM (SELECT $_summaryCols FROM items i WHERE $where) '
            'WHERE $outer ORDER BY $order${limit != null ? ' LIMIT $limit' : ''}', args)
        .map(_summary)
        .toList();
  }

  // ------------------------------------------------------------ 收藏

  List<MediaSummary> favorites({int? limit}) => _db
      .select('SELECT $_summaryCols FROM items i JOIN favorites f ON f.item_id = i.id '
          'ORDER BY f.added_at DESC${limit != null ? ' LIMIT $limit' : ''}')
      .map(_summary)
      .toList();

  bool isFavorite(int itemId) =>
      _db.select('SELECT 1 FROM favorites WHERE item_id = ?', [itemId]).isNotEmpty;

  void setFavorite(int itemId, bool favorite) {
    if (favorite) {
      _db.execute('INSERT OR IGNORE INTO favorites(item_id, added_at) VALUES (?, ?)', [itemId, _now()]);
    } else {
      _db.execute('DELETE FROM favorites WHERE item_id = ?', [itemId]);
    }
  }

  // ------------------------------------------------------------ 搜索

  static String _like(String q) => '%${q.replaceAll('\\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

  /// 片名 / 原名 / 导演 / 演员 匹配的条目；片名前缀匹配排最前。
  List<MediaSummary> searchItems(String q, {int limit = 60}) {
    final like = _like(q.trim());
    final prefix = '${q.trim()}%';
    return _db
        .select('''SELECT $_summaryCols FROM items i
            WHERE i.title LIKE ?1 ESCAPE '\\' OR i.original_title LIKE ?1 ESCAPE '\\'
               OR i.sort_title LIKE ?1 ESCAPE '\\' OR i.directors LIKE ?1 ESCAPE '\\'
               OR i.id IN (SELECT item_id FROM actors WHERE name LIKE ?1 ESCAPE '\\')
            ORDER BY CASE WHEN i.title LIKE ?2 THEN 0 WHEN i.title LIKE ?1 ESCAPE '\\' THEN 1 ELSE 2 END,
                     i.rating DESC NULLS LAST
            LIMIT $limit''', [like, prefix])
        .map(_summary)
        .toList();
  }

  List<PersonHit> searchPeople(String q, {int limit = 20}) => _db
      .select('''SELECT name, MAX(thumb) AS thumb, COUNT(DISTINCT item_id) AS n FROM actors
          WHERE name LIKE ? ESCAPE '\\' GROUP BY name ORDER BY n DESC, name LIMIT $limit''', [_like(q.trim())])
      .map((r) => PersonHit(r['name'] as String, r['thumb'] as String?, r['n'] as int))
      .toList();

  /// 单集标题匹配（排除"第 N 集"这种自动生成的标题）。
  List<EpisodeHit> searchEpisodes(String q, {int limit = 20}) => _db
      .select('''SELECT e.*, i.title AS show_title, i.id AS show_id FROM episodes e
          JOIN items i ON i.id = e.item_id
          WHERE e.title LIKE ? ESCAPE '\\' AND e.title NOT LIKE '第 % 集'
          ORDER BY i.title, e.season, e.episode LIMIT $limit''', [_like(q.trim())])
      .map((r) => EpisodeHit(r['show_id'] as int, r['show_title'] as String, _episode(r)))
      .toList();

  /// 某位演员参演的条目。
  List<MediaSummary> itemsWithActor(String name) => _db
      .select('SELECT $_summaryCols FROM items i WHERE i.id IN '
          '(SELECT item_id FROM actors WHERE name = ?) ORDER BY i.year DESC NULLS LAST, i.title', [name])
      .map(_summary)
      .toList();

  String? actorThumb(String name) => _db
      .select('SELECT MAX(thumb) AS t FROM actors WHERE name = ?', [name])
      .firstOrNull?['t'] as String?;

  // ------------------------------------------------------------ 相关推荐

  /// 同一合集（NFO 的 `<set>`）里的其他影片，按年份排列。
  List<MediaSummary> sameSet(int itemId) => _db
      .select('''SELECT $_summaryCols FROM items i WHERE i.set_name IS NOT NULL
          AND i.set_name = (SELECT set_name FROM items WHERE id = ?1) AND i.id != ?1
          ORDER BY i.year NULLS LAST, i.title''', [itemId])
      .map(_summary)
      .toList();

  /// 类型相近的同类条目：共享类型越多越靠前，其次按评分。
  List<MediaSummary> similar(int itemId, {int limit = 20}) {
    final row = _db.select('SELECT kind, genres, set_name FROM items WHERE id = ?', [itemId]).firstOrNull;
    if (row == null || row['genres'] == null) return const [];
    final genres = (row['genres'] as String).split('|').where((g) => g.isNotEmpty).take(3).toList();
    if (genres.isEmpty) return const [];
    final score = genres.map((_) => "(CASE WHEN ('|' || i.genres || '|') LIKE ? THEN 1 ELSE 0 END)").join(' + ');
    final args = [for (final g in genres) '%|$g|%', row['kind'], itemId, row['set_name']];
    return _db
        .select('''SELECT * FROM (SELECT $_summaryCols, ($score) AS score FROM items i
            WHERE i.kind = ? AND i.id != ? AND i.genres IS NOT NULL
              AND (i.set_name IS NULL OR i.set_name IS NOT ?))
            WHERE score > 0 ORDER BY score DESC, rating DESC NULLS LAST LIMIT $limit''', args)
        .map(_summary)
        .toList();
  }

  int episodeTotal() => _db.select('SELECT COUNT(*) AS n FROM episodes').first['n'] as int;

  int count(MediaKind kind) =>
      _db.select('SELECT COUNT(*) AS n FROM items WHERE kind = ?', [kind.name]).first['n'] as int;

  List<String> genres(MediaKind kind) {
    final counts = <String, int>{};
    for (final r in _db.select(
        'SELECT genres FROM items WHERE kind = ? AND genres IS NOT NULL', [kind.name])) {
      for (final g in (r['genres'] as String).split('|')) {
        if (g.isNotEmpty) counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final list = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return list;
  }

  /// AV 识别：资料来自 JavBus / R18.dev（NFO 里有番号 uniqueid "num"，花栗鼠整理的也一样），
  /// 或 NFO 带 AV 标签；用户手动设置过的以手动为准。
  bool _isAv(int sourceId, ScannedItem item) {
    final o = _db.select('SELECT is_av FROM av_overrides WHERE source_id = ? AND key = ?', [sourceId, item.key]);
    if (o.isNotEmpty) return o.first['is_av'] == 1;
    final nfo = item.nfo;
    if (nfo == null) return false;
    return nfo.uniqueIds.containsKey('num') || nfo.tags.any((t) => t.toUpperCase() == 'AV');
  }

  /// 手动设置 / 取消 AV 标记（重新扫描后保持）。
  void setAv(int itemId, bool isAv) {
    final r = _db.select('SELECT source_id, key FROM items WHERE id = ?', [itemId]).firstOrNull;
    if (r == null) return;
    _db.execute('INSERT OR REPLACE INTO av_overrides(source_id, key, is_av) VALUES (?, ?, ?)',
        [r['source_id'], r['key'], isAv ? 1 : 0]);
    _db.execute('UPDATE items SET is_av = ? WHERE id = ?', [isAv ? 1 : 0, itemId]);
  }

  // ------------------------------------------------------------ 自动刮削

  /// 某个本地源里还没有 NFO、也没自动刮削过的电影（每个文件只自动尝试一次）。
  List<({int id, String title, int? year, String path})> autoScrapeCandidates(int sourceId) => _db
      .select('''SELECT i.id, i.title, i.year, (SELECT path FROM files f WHERE f.item_id = i.id ORDER BY path LIMIT 1) AS path
          FROM items i WHERE i.source_id = ? AND i.kind = 'movie' AND i.nfo_path IS NULL''', [sourceId])
      .where((r) => r['path'] != null)
      .where((r) => _db.select('SELECT 1 FROM auto_scrape_attempts WHERE path = ?', [r['path']]).isEmpty)
      .map((r) => (id: r['id'] as int, title: r['title'] as String, year: r['year'] as int?, path: r['path'] as String))
      .toList();

  void markAutoScrapeAttempt(String path) => _db.execute(
      'INSERT OR REPLACE INTO auto_scrape_attempts(path, at) VALUES (?, ?)', [path, _now()]);

  /// 从媒体库移除（不删文件），以后重新扫描也不会再加回来。
  void excludeItem(int id) {
    final r = _db.select('SELECT source_id, key, title FROM items WHERE id = ?', [id]).firstOrNull;
    if (r == null) return;
    _db.execute('INSERT OR REPLACE INTO excluded_items(source_id, key, title) VALUES (?, ?, ?)',
        [r['source_id'], r['key'], r['title']]);
    _db.execute('DELETE FROM items WHERE id = ?', [id]);
  }

  int excludedCount(int sourceId) =>
      _db.select('SELECT COUNT(*) AS n FROM excluded_items WHERE source_id = ?', [sourceId]).first['n'] as int;

  /// 恢复某个媒体源下所有被移除的条目（下次扫描时重新加入）。
  void restoreExcluded(int sourceId) => _db.execute('DELETE FROM excluded_items WHERE source_id = ?', [sourceId]);

  MediaDetail? detail(int id) {
    final rows = _db.select('SELECT * FROM items WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return MediaDetail(
      id: id,
      sourceId: r['source_id'] as int,
      nfoPath: r['nfo_path'] as String?,
      isAv: r['is_av'] == 1,
      tags: _split(r['tags']),
      kind: r['kind'] == 'show' ? MediaKind.show : MediaKind.movie,
      title: r['title'] as String,
      originalTitle: r['original_title'] as String?,
      year: r['year'] as int?,
      plot: r['plot'] as String?,
      tagline: r['tagline'] as String?,
      rating: (r['rating'] as num?)?.toDouble(),
      runtime: r['runtime'] as int?,
      premiered: r['premiered'] as String?,
      mpaa: r['mpaa'] as String?,
      setName: r['set_name'] as String?,
      status: r['status'] as String?,
      genres: _split(r['genres']),
      countries: _split(r['countries']),
      studios: _split(r['studios']),
      directors: _split(r['directors']),
      writers: _split(r['writers']),
      poster: r['poster'] as String?,
      fanart: r['fanart'] as String?,
      logo: r['logo'] as String?,
      dir: r['dir'] as String,
      actors: _db
          .select('SELECT name, role, thumb FROM actors WHERE item_id = ? ORDER BY ord', [id])
          .map((a) => ActorRow(a['name'] as String, a['role'] as String?, a['thumb'] as String?))
          .toList(),
      files: _db
          .select('SELECT path, size FROM files WHERE item_id = ? ORDER BY path', [id])
          .map((f) => FileRow(f['path'] as String, f['size'] as int))
          .toList(),
      seasons: _db
          .select('SELECT s.season, s.poster, (SELECT COUNT(*) FROM episodes e '
              'WHERE e.item_id = s.item_id AND e.season = s.season) AS n '
              'FROM seasons s WHERE s.item_id = ? ORDER BY CASE WHEN s.season = 0 THEN 9999 '
              'ELSE s.season END', [id])
          .map((s) => SeasonRow(s['season'] as int, s['poster'] as String?, s['n'] as int))
          .toList(),
    );
  }

  List<EpisodeRow> episodes(int itemId, int season) => _db
      .select('SELECT * FROM episodes WHERE item_id = ? AND season = ? '
          'ORDER BY episode NULLS LAST, path', [itemId, season])
      .map(_episode)
      .toList();

  static EpisodeRow _episode(Row e) => EpisodeRow(
        id: e['id'] as int,
        season: e['season'] as int,
        episode: e['episode'] as int?,
        title: e['title'] as String,
        plot: e['plot'] as String?,
        aired: e['aired'] as String?,
        rating: (e['rating'] as num?)?.toDouble(),
        runtime: e['runtime'] as int?,
        path: e['path'] as String,
        size: e['size'] as int,
        thumb: e['thumb'] as String?,
      );

  // ------------------------------------------------------------ 播放进度

  PlaybackProgress? progress(String path) {
    final rows = _db.select('SELECT * FROM playback_state WHERE path = ?', [path]);
    return rows.isEmpty ? null : _progress(rows.first);
  }

  Map<String, PlaybackProgress> progressForItem(int itemId) => {
        for (final r in _db.select('''SELECT ps.* FROM playback_state ps WHERE ps.path IN
            (SELECT path FROM files WHERE item_id = ? UNION ALL
             SELECT path FROM episodes WHERE item_id = ?)''', [itemId, itemId]))
          r['path'] as String: _progress(r),
      };

  void saveProgress(String path, {required int positionMs, required int durationMs, required bool finished}) {
    _db.execute('''INSERT INTO playback_state(path, position_ms, duration_ms, finished, updated_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(path) DO UPDATE SET position_ms = excluded.position_ms,
          duration_ms = excluded.duration_ms, finished = excluded.finished,
          updated_at = excluded.updated_at''',
        [path, positionMs, durationMs, finished ? 1 : 0, _now()]);
  }

  /// 文件被整理（移动）后，把播放进度迁移到新路径。
  void movePlaybackPath(String from, String to) {
    _db.execute('UPDATE OR IGNORE playback_state SET path = ? WHERE path = ?', [to, from]);
  }

  void setWatched(List<String> paths, bool watched) {
    _db.execute('BEGIN');
    for (final path in paths) {
      if (watched) {
        _db.execute('''INSERT INTO playback_state(path, position_ms, duration_ms, finished, updated_at)
            VALUES (?, 0, 0, 1, ?) ON CONFLICT(path) DO UPDATE SET finished = 1,
            position_ms = 0, updated_at = excluded.updated_at''', [path, _now()]);
      } else {
        _db.execute('DELETE FROM playback_state WHERE path = ?', [path]);
      }
    }
    _db.execute('COMMIT');
  }

  /// 首页"继续观看"：电影取未看完的；剧集取未看完的那一集，若上次看完了则推荐下一集。
  List<ContinueItem> continueWatching({int limit = 20}) {
    final rows = _db.select('''
      SELECT ps.path, ps.position_ms, ps.duration_ms, ps.finished, ps.updated_at,
             f.item_id AS movie_item, e.item_id AS show_item, e.id AS ep_id
      FROM playback_state ps
      LEFT JOIN files f ON f.path = ps.path
      LEFT JOIN episodes e ON e.path = ps.path
      WHERE f.item_id IS NOT NULL OR e.item_id IS NOT NULL
      ORDER BY ps.updated_at DESC LIMIT 300''');
    final seen = <int>{};
    final out = <ContinueItem>[];
    for (final r in rows) {
      final movieItem = r['movie_item'] as int?;
      final itemId = movieItem ?? r['show_item'] as int;
      if (!seen.add(itemId)) continue;
      final finished = r['finished'] == 1;
      final pos = r['position_ms'] as int;
      final dur = r['duration_ms'] as int;
      final item = _db.select('SELECT title, poster, fanart, is_av FROM items WHERE id = ?', [itemId]);
      if (item.isEmpty) continue;
      final it = item.first;

      if (movieItem != null) {
        if (finished || pos < 30000) continue;
        out.add(ContinueItem(
          itemId: itemId, kind: MediaKind.movie, title: it['title'] as String, isAv: it['is_av'] == 1,
          poster: it['poster'] as String?, fanart: it['fanart'] as String?,
          path: r['path'] as String, positionMs: pos, durationMs: dur,
        ));
      } else {
        final eps = _db.select('SELECT id, season, episode, title, path, thumb FROM episodes '
            'WHERE item_id = ? ORDER BY CASE WHEN season = 0 THEN 9999 ELSE season END, '
            'episode NULLS LAST, path', [itemId]);
        final idx = eps.indexWhere((e) => e['id'] == r['ep_id']);
        if (idx < 0) continue;
        Row? target;
        var tPos = 0, tDur = 0;
        var isNext = false;
        if (!finished && pos >= 30000) {
          target = eps[idx];
          tPos = pos;
          tDur = dur;
        } else if (finished && idx + 1 < eps.length) {
          target = eps[idx + 1];
          final p = progress(target['path'] as String);
          if (p != null && p.finished) continue;
          tPos = p?.positionMs ?? 0;
          tDur = p?.durationMs ?? 0;
          isNext = true;
        }
        if (target == null) continue;
        final s = target['season'] as int;
        final e = target['episode'] as int?;
        out.add(ContinueItem(
          itemId: itemId, kind: MediaKind.show, title: it['title'] as String, isAv: it['is_av'] == 1,
          poster: it['poster'] as String?, fanart: target['thumb'] as String? ?? it['fanart'] as String?,
          path: target['path'] as String, positionMs: tPos, durationMs: tDur,
          episodeLabel: '${isNext ? '下一集 · ' : ''}S${s.toString().padLeft(2, '0')}'
              '${e != null ? 'E${e.toString().padLeft(2, '0')}' : ''} ${target['title']}',
        ));
      }
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 剧集的完整播放列表（跨季，特别篇排最后）。
  List<EpisodeRow> allEpisodes(int itemId) => _db
      .select('SELECT * FROM episodes WHERE item_id = ? ORDER BY CASE WHEN season = 0 '
          'THEN 9999 ELSE season END, episode NULLS LAST, path', [itemId])
      .map(_episode)
      .toList();

  static PlaybackProgress _progress(Row r) => PlaybackProgress(
        path: r['path'] as String,
        positionMs: r['position_ms'] as int,
        durationMs: r['duration_ms'] as int,
        finished: r['finished'] == 1,
      );

  // ------------------------------------------------------------ 工具

  static MediaSummary _summary(Row r) => MediaSummary(
        id: r['id'] as int,
        kind: r['kind'] == 'show' ? MediaKind.show : MediaKind.movie,
        title: r['title'] as String,
        originalTitle: r['original_title'] as String?,
        year: r['year'] as int?,
        rating: (r['rating'] as num?)?.toDouble(),
        poster: r['poster'] as String?,
        fanart: r['fanart'] as String?,
        logo: r['logo'] as String?,
        genres: _split(r['genres']),
        favorite: r['favorite'] == 1,
        isAv: r['is_av'] == 1,
        episodeCount: r['episode_count'] as int,
        watchedCount: r['watched_count'] as int,
        progress: (r['progress'] as num?)?.toDouble(),
      );

  static String? _list(List<String>? l) => l == null || l.isEmpty ? null : l.join('|');
  static List<String> _split(Object? s) =>
      s == null ? const [] : (s as String).split('|').where((e) => e.isNotEmpty).toList();
  static int _now() => DateTime.now().millisecondsSinceEpoch;
  static DateTime? _date(Object? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms as int);
}
