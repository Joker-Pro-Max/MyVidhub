import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvidhub/data/db/library_db.dart';
import 'package:myvidhub/data/db/models.dart';
import 'package:myvidhub/data/sources/local_source.dart';
import 'package:myvidhub/services/library_scanner.dart';
import 'package:myvidhub/services/translator.dart';
import 'package:path/path.dart' as p;

import 'support/sample_library.dart';

void main() {
  test('哪些文字需要翻译', () {
    expect(needsTranslation('The Matrix'), isTrue);
    expect(needsTranslation('Sam Worthington'), isTrue);
    expect(needsTranslation('君の名は。'), isTrue);
    expect(needsTranslation('기생충'), isTrue);
    expect(needsTranslation('阿凡达'), isFalse);
    expect(needsTranslation('黑客帝国 The Matrix'), isFalse);
    expect(needsTranslation('SSIS-001'), isFalse);
    expect(needsTranslation('2012'), isFalse);
    expect(needsTranslation('   '), isFalse);
  });

  group('译文入库', () {
    late Directory tmp;
    late LibraryDb db;
    late String root;

    Future<void> scan() async {
      final sid = db.sources().isEmpty ? db.addSource(type: 'local', name: 't', root: root) : db.sources().first.id;
      final stamp = db.beginScan();
      await for (final item in LibraryScanner(LocalSource(root)).scan()) {
        db.writeItem(sid, item, stamp);
      }
      db.finishScan(sid, stamp);
    }

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('reelnest_tr');
      root = p.join(tmp.path, 'lib');
      createSampleLibrary(root);
      db = LibraryDb.open(p.join(tmp.path, 'lib.db'));
      await scan();
    });
    tearDown(() {
      db.dispose();
      tmp.deleteSync(recursive: true);
    });

    test('翻译后改名，重新扫描仍保留，恢复原文后还原', () async {
      final t = db.translatableTexts();
      expect(t.titles, contains('The Matrix'));
      expect(t.actors, contains('Sam Worthington'));
      expect(db.allActors().map((a) => a.name), contains('Sam Worthington'));

      db.saveTranslations({'The Matrix': '黑客帝国', 'Sam Worthington': '萨姆·沃辛顿'});
      expect(db.translationCount(), 2);
      final m = db.listItems(kind: MediaKind.movie).firstWhere((m) => m.title == '黑客帝国');
      expect(db.detail(m.id)!.originalTitle, isNotNull);
      expect(db.allActors().map((a) => a.name), contains('萨姆·沃辛顿'));

      await scan();
      expect(db.listItems(kind: MediaKind.movie).map((m) => m.title), contains('黑客帝国'));
      expect(db.allActors().map((a) => a.name), contains('萨姆·沃辛顿'));

      db.clearTranslations();
      expect(db.translationCount(), 0);
      await scan();
      expect(db.listItems(kind: MediaKind.movie).map((m) => m.title), contains('The Matrix'));
    });
  });
}
