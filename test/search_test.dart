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
  late LibraryDb db;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('myvidhub_search');
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

  int idOf(MediaKind k, String t) => db.listItems(kind: k).firstWhere((m) => m.title == t).id;

  test('搜索片名、原名、导演、演员、单集', () {
    expect(db.searchItems('阿凡').map((m) => m.title), ['阿凡达']);
    expect(db.searchItems('avatar').map((m) => m.title), ['阿凡达']); // 原名，大小写不敏感
    expect(db.searchItems('卡梅隆').map((m) => m.title), ['阿凡达']); // 导演
    expect(db.searchItems('worthington').map((m) => m.title), ['阿凡达']); // 演员
    expect(db.searchItems('matrix').map((m) => m.title), contains('The Matrix'));
    expect(db.searchItems('%'), isEmpty); // 通配符被转义
    expect(db.searchPeople('sam').single.name, 'Sam Worthington');
    expect(db.itemsWithActor('Sam Worthington').single.title, '阿凡达');
    expect(db.searchEpisodes('试播').single.episode.title, '试播集');
    expect(db.searchEpisodes('第 2 集'), isEmpty); // 自动生成的标题不算
  });

  test('收藏与观看筛选', () {
    final avatar = idOf(MediaKind.movie, '阿凡达');
    db.setFavorite(avatar, true);
    expect(db.isFavorite(avatar), isTrue);
    expect(db.favorites().single.id, avatar);
    expect(db.listItems(kind: MediaKind.movie, filter: WatchFilter.favorite).single.id, avatar);
    expect(db.listItems(kind: MediaKind.movie).firstWhere((m) => m.id == avatar).favorite, isTrue);

    final path = db.detail(avatar)!.files.single.path;
    db.setWatched([path], true);
    expect(db.listItems(kind: MediaKind.movie, filter: WatchFilter.watched).map((m) => m.id), [avatar]);
    expect(db.listItems(kind: MediaKind.movie, filter: WatchFilter.unwatched).map((m) => m.id), isNot(contains(avatar)));

    final bb = idOf(MediaKind.show, '绝命毒师');
    final eps = db.allEpisodes(bb);
    db.setWatched([eps.first.path], true);
    final show = db.listItems(kind: MediaKind.show).firstWhere((m) => m.id == bb);
    expect(show.unwatchedEpisodes, 2);
    expect(db.listItems(kind: MediaKind.show, filter: WatchFilter.unwatched).map((m) => m.id), contains(bb));

    db.setFavorite(avatar, false);
    expect(db.favorites(), isEmpty);
  });

  test('同系列与更多类似', () {
    final avatar = idOf(MediaKind.movie, '阿凡达');
    expect(db.sameSet(avatar).map((m) => m.title), ['盗梦空间']);
    // 同为科幻，但已在同系列里，不重复出现在"更多类似"
    expect(db.similar(avatar).map((m) => m.title), isNot(contains('盗梦空间')));
  });
}
