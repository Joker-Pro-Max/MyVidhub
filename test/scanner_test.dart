import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvidhub/data/db/library_db.dart';
import 'package:myvidhub/data/db/models.dart';
import 'package:myvidhub/data/sources/local_source.dart';
import 'package:myvidhub/services/library_scanner.dart';
import 'package:path/path.dart' as p;

import 'support/sample_library.dart';

void main() {
  late Directory tmp;
  late String root;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('myvidhub_test');
    root = p.join(tmp.path, 'lib');
    createSampleLibrary(root);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<List<ScannedItem>> scan() => LibraryScanner(LocalSource(root)).scan().toList();

  test('识别电影', () async {
    final items = await scan();
    final movies = items.whereType<ScannedMovie>().toList()
      ..sort((a, b) => a.title.compareTo(b.title));
    expect(movies.map((m) => '${m.title}|${m.year}').toList()..sort(), [
      'The Matrix|1999',
      '盗梦空间|2010',
      '老电影|1994', // 文件名无年份 → 用目录名 "老电影 (1994)"
      '阿凡达|2009',
      '黑客帝国2：重装上阵|2003',
    ]);

    final avatar = movies.firstWhere((m) => m.title == '阿凡达');
    expect(avatar.files, hasLength(1)); // sample 与 extras 被排除
    expect(p.basename(avatar.poster!), 'poster.jpg');
    expect(p.basename(avatar.fanart!), 'fanart.jpg');
    expect(avatar.nfo!.genres, ['动作', '科幻']);
    expect(p.basename(avatar.actors.single.thumb!), 'Sam_Worthington.jpg');

    final inception = movies.firstWhere((m) => m.title == '盗梦空间');
    expect(inception.files, hasLength(2));
    expect(p.basename(inception.poster!), 'folder.jpg');

    final matrix = movies.firstWhere((m) => m.title == 'The Matrix');
    expect(p.basename(matrix.poster!), 'The.Matrix.1999.1080p-poster.jpg');
    final reloaded = movies.firstWhere((m) => m.title.startsWith('黑客帝国2'));
    expect(reloaded.poster, isNull); // 多电影目录不使用通用 poster.jpg

    final old = movies.firstWhere((m) => m.title == '老电影');
    expect(old.files, hasLength(2));
  });

  test('识别剧集', () async {
    final shows = (await scan()).whereType<ScannedShow>().toList();
    expect(shows.map((s) => s.title).toSet(), {'绝命毒师', '庆余年', 'Friends'});

    final bb = shows.firstWhere((s) => s.title == '绝命毒师');
    expect(bb.year, 2008);
    expect(bb.episodes.map((e) => 'S${e.season}E${e.episode}'), ['S1E1', 'S1E2', 'S2E1']);
    expect(bb.episodes.first.title, '试播集');
    expect(bb.episodes.first.thumb, isNotNull);
    expect(bb.seasonPosters.keys.toSet(), {1, 2});

    final qyn = shows.firstWhere((s) => s.title == '庆余年');
    expect(qyn.episodes.map((e) => 'S${e.season}E${e.episode}'), ['S1E1', 'S1E2', 'S2E1']);

    final friends = shows.firstWhere((s) => s.title == 'Friends');
    expect(friends.episodes, hasLength(3));
  });

  test('写入数据库、重扫保留添加时间、删除文件后清理', () async {
    final db = LibraryDb.open(p.join(tmp.path, 'lib.db'));
    final sid = db.addSource(type: 'local', name: 'test', root: root);

    Future<void> runScan() async {
      final stamp = db.beginScan();
      await for (final item in LibraryScanner(LocalSource(root)).scan()) {
        db.writeItem(sid, item, stamp);
      }
      db.finishScan(sid, stamp);
    }

    await runScan();
    expect(db.count(MediaKind.movie), 5);
    expect(db.count(MediaKind.show), 3);

    final avatar = db.listItems(kind: MediaKind.movie).firstWhere((m) => m.title == '阿凡达');
    final detail = db.detail(avatar.id)!;
    expect(detail.genres, ['动作', '科幻']);
    expect(detail.directors, ['詹姆斯·卡梅隆']);
    expect(detail.actors.single.name, 'Sam Worthington');
    expect(db.genres(MediaKind.movie).first, '科幻'); // 两部电影都是科幻

    final bbId = db.listItems(kind: MediaKind.show).firstWhere((s) => s.title == '绝命毒师').id;
    final bb = db.detail(bbId)!;
    expect(bb.seasons.map((s) => s.season), [1, 2]);
    expect(db.episodes(bbId, 1).map((e) => e.title), ['试播集', '第 2 集']);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    Directory(p.join(root, '电影', '老电影 (1994)')).deleteSync(recursive: true);
    await runScan();
    expect(db.count(MediaKind.movie), 4);
    // 同一条目 id 不变（不会因重扫重新"添加"）
    expect(db.listItems(kind: MediaKind.movie).any((m) => m.id == avatar.id), isTrue);

    db.deleteSource(sid);
    expect(db.count(MediaKind.movie), 0);
    db.dispose();
  });
}
