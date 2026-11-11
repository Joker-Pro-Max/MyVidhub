// 在真机 / 桌面上跑完整 App，按不同屏幕尺寸截图，用于检查布局。
//
// flutter test integration_test/screenshots_test.dart -d macos \
//   --dart-define=DEMO_DIR=/path/to/library --dart-define=SHOT_DIR=/path/to/out
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myvidhub/app/app_shell.dart';
import 'package:myvidhub/app/providers.dart';
import 'package:myvidhub/data/db/library_db.dart';
import 'package:myvidhub/data/db/models.dart';
import 'package:myvidhub/features/library/library_page.dart';
import 'package:myvidhub/features/settings/folder_browser.dart';
import 'package:myvidhub/data/sources/local_source.dart';
import 'package:myvidhub/main.dart';
import 'package:myvidhub/services/library_scanner.dart';
import 'package:path/path.dart' as p;

const demoDir = String.fromEnvironment('DEMO_DIR');
const shotDir = String.fromEnvironment('SHOT_DIR');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LibraryDb db;
  late String dbPath;

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('myvidhub_it');
    dbPath = p.join(tmp.path, 'library.db');
    db = LibraryDb.open(dbPath);
    final id = db.addSource(type: 'local', name: p.basename(demoDir), root: demoDir);
    final stamp = db.beginScan();
    await for (final item in LibraryScanner(LocalSource(demoDir)).scan()) {
      db.writeItem(id, item, stamp);
    }
    db.finishScan(id, stamp);
    Directory(shotDir).createSync(recursive: true);
  });

  final boundaryKey = GlobalKey();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 15));
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester);
    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(p.join(shotDir, '$name.png')).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> pumpApp(WidgetTester tester, Size logical) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = logical;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        dbPathProvider.overrideWithValue(dbPath),
        dbProvider.overrideWithValue(db),
      ],
      child: RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const AppShell(),
        ),
      ),
    ));
  }

  final sizes = {
    'tablet_landscape': const Size(1280, 800),
    'tablet_portrait': const Size(800, 1280),
    'phone': const Size(390, 844),
    'desktop': const Size(1440, 900),
  };

  for (final entry in sizes.entries) {
    testWidgets('screens ${entry.key}', (tester) async {
      await pumpApp(tester, entry.value);
      await shot(tester, '${entry.key}_1_home');

      await tester.tap(find.text('电影').last);
      await shot(tester, '${entry.key}_2_movies');

      await tester.scrollUntilVisible(find.text('星际穿越').first, 300,
          scrollable: find.descendant(
              of: find.byWidgetPredicate((w) => w is LibraryPage && w.kind == MediaKind.movie),
              matching: find.byType(Scrollable)).first);
      await tester.ensureVisible(find.text('星际穿越').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('星际穿越').first);
      await shot(tester, '${entry.key}_3_movie_detail');
      await tester.tap(find.byTooltip('返回'));
      await settle(tester);

      await tester.tap(find.text('剧集').last);
      await settle(tester);
      await tester.ensureVisible(find.text('绝命毒师').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('绝命毒师').first);
      await shot(tester, '${entry.key}_4_show_detail');
      await tester.tap(find.byTooltip('返回'));
      await settle(tester);

      await tester.tap(find.text('设置').evaluate().isNotEmpty ? find.text('设置').last : find.byTooltip('设置'));
      await shot(tester, '${entry.key}_5_settings');
    });
  }

  for (final entry in {'tablet_landscape': const Size(1280, 800), 'phone': const Size(390, 844)}.entries) {
    testWidgets('folder browser ${entry.key}', (tester) async {
      await pumpApp(tester, entry.value);
      await settle(tester);
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => const FolderBrowser()));
      await shot(tester, '${entry.key}_6_folder_roots');
      nav.pop();
      await settle(tester);
      nav.push(MaterialPageRoute<void>(builder: (_) => FolderBrowser(initialPath: p.dirname(demoDir))));
      await shot(tester, '${entry.key}_7_folder_browse');
    });
  }
}
