import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvidhub/data/db/library_db.dart';
import 'package:myvidhub/data/db/models.dart';
import 'package:myvidhub/data/sources/local_source.dart';
import 'package:myvidhub/features/player/play_item.dart';
import 'package:myvidhub/services/library_scanner.dart';
import 'package:path/path.dart' as p;

import 'support/sample_library.dart';

void main() {
  late Directory tmp;
  late LibraryDb db;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('myvidhub_pb');
    final root = p.join(tmp.path, 'lib');
    createSampleLibrary(root);
    db = LibraryDb.open(p.join(tmp.path, 'lib.db'));
    final sid = db.addSource(type: 'local', name: 't', root: root);
    final stamp = db.beginScan();
    await for (final item in LibraryScanner(LocalSource(root)).scan()) {
      db.writeItem(sid, item, stamp);
    }
    db.finishScan(sid, stamp);
  });
  tearDown(() {
    db.dispose();
    tmp.deleteSync(recursive: true);
  });

  int idOf(MediaKind k, String title) => db.listItems(kind: k).firstWhere((m) => m.title == title).id;

  test('电影进度：继续观看、海报进度、看完后移出', () async {
    final id = idOf(MediaKind.movie, '阿凡达');
    final path = db.detail(id)!.files.single.path;

    db.saveProgress(path, positionMs: 600000, durationMs: 9720000, finished: false);
    var cont = db.continueWatching();
    expect(cont.single.itemId, id);
    expect(cont.single.positionMs, 600000);
    final summary = db.listItems(kind: MediaKind.movie).firstWhere((m) => m.id == id);
    expect(summary.progress, closeTo(600000 / 9720000, 1e-6));
    expect(summary.watched, isFalse);

    db.saveProgress(path, positionMs: 0, durationMs: 9720000, finished: true);
    cont = db.continueWatching();
    expect(cont, isEmpty);
    expect(db.listItems(kind: MediaKind.movie).firstWhere((m) => m.id == id).watched, isTrue);
  });

  test('剧集：看完一集推荐下一集；中途退出推荐当前集', () async {
    final id = idOf(MediaKind.show, '绝命毒师');
    final eps = db.allEpisodes(id);
    expect(eps.map((e) => '${e.season}-${e.episode}'), ['1-1', '1-2', '2-1']);

    db.saveProgress(eps[0].path, positionMs: 0, durationMs: 2800000, finished: true);
    var cont = db.continueWatching();
    expect(cont.single.path, eps[1].path);
    expect(cont.single.episodeLabel, startsWith('下一集'));

    await Future<void>.delayed(const Duration(milliseconds: 3));
    db.saveProgress(eps[1].path, positionMs: 900000, durationMs: 2800000, finished: false);
    cont = db.continueWatching();
    expect(cont.single.path, eps[1].path);
    expect(cont.single.positionMs, 900000);

    final progress = db.progressForItem(id);
    expect(resumeEpisodeIndex(eps, progress), 1);

    db.setWatched([for (final e in eps) e.path], true);
    expect(db.listItems(kind: MediaKind.show).firstWhere((m) => m.id == id).watched, isTrue);
    expect(db.continueWatching(), isEmpty);
    expect(resumeEpisodeIndex(eps, db.progressForItem(id)), 0); // 全部看完 → 从头

    db.setWatched([eps[0].path], false);
    expect(db.progress(eps[0].path), isNull);
  });

  test('重扫后进度保留（按文件路径记录）', () async {
    final id = idOf(MediaKind.movie, '阿凡达');
    final path = db.detail(id)!.files.single.path;
    db.saveProgress(path, positionMs: 123000, durationMs: 9720000, finished: false);

    final src = db.sources().single;
    final stamp = db.beginScan();
    await for (final item in LibraryScanner(LocalSource(src.root)).scan()) {
      db.writeItem(src.id, item, stamp);
    }
    db.finishScan(src.id, stamp);
    expect(db.progress(path)!.positionMs, 123000);
    expect(db.continueWatching().single.title, '阿凡达');
  });
}
