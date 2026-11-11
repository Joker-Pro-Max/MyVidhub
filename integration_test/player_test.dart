// 播放器端到端测试：真实 mpv 解码 + 真实文件。
//
// flutter test integration_test/player_test.dart -d macos \
//   --dart-define=DEMO_DIR=/path/to/library --dart-define=SHOT_DIR=/path/to/out
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:myvidhub/app/app_shell.dart';
import 'package:myvidhub/app/providers.dart';
import 'package:myvidhub/data/db/library_db.dart';
import 'package:myvidhub/data/sources/local_source.dart';
import 'package:myvidhub/features/player/player_controls.dart';
import 'package:myvidhub/features/player/player_session.dart';
import 'package:myvidhub/main.dart';
import 'package:myvidhub/services/library_scanner.dart';
import 'package:path/path.dart' as p;

const demoDir = String.fromEnvironment('DEMO_DIR');
const shotDir = String.fromEnvironment('SHOT_DIR');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  late LibraryDb db;
  late String dbPath;
  final boundaryKey = GlobalKey();

  setUpAll(() async {
    final tmp = Directory.systemTemp.createTempSync('myvidhub_player');
    dbPath = p.join(tmp.path, 'library.db');
    db = LibraryDb.open(dbPath);
    final id = db.addSource(type: 'local', name: 'demo', root: demoDir);
    final stamp = db.beginScan();
    await for (final item in LibraryScanner(LocalSource(demoDir)).scan()) {
      db.writeItem(id, item, stamp);
    }
    db.finishScan(id, stamp);
    Directory(shotDir).createSync(recursive: true);
  });

  Future<void> wait(WidgetTester tester, int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump();
    await tester.runAsync(() async {
      final b = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File(p.join(shotDir, 'player_$name.png')).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  PlayerSession session(WidgetTester tester) =>
      tester.widget<PlayerControls>(find.byType(PlayerControls)).session;

  testWidgets('电影播放：解码、音轨、字幕、进度记忆', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [dbPathProvider.overrideWithValue(dbPath), dbProvider.overrideWithValue(db)],
      child: RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: const AppShell()),
      ),
    ));
    await wait(tester, 800);

    // 进入电影详情并播放
    await tester.tap(find.text('电影').last);
    await wait(tester, 400);
    await tester.ensureVisible(find.text('星际穿越').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('星际穿越').first);
    await wait(tester, 600);
    await tester.tap(find.text('播放'));
    await wait(tester, 3500);

    final s = session(tester);
    final player = s.player;
    // ignore: avoid_print
    print('PLAYER position=${player.state.position} duration=${player.state.duration} '
        'playing=${player.state.playing} video=${player.state.width}x${player.state.height}');
    expect(player.state.duration.inSeconds, inInclusiveRange(59, 61));
    expect(player.state.position, greaterThan(const Duration(milliseconds: 500)));
    expect(player.state.width, 1280);

    final audio = player.state.tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
    final subs = player.state.tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
    // ignore: avoid_print
    print('PLAYER audio=${audio.map((t) => '${t.id}:${t.title}:${t.language}:${t.codec}')} '
        'subs=${subs.map((t) => '${t.id}:${t.title}:${t.language}:${t.codec}')} '
        'selectedSub=${player.state.track.subtitle.id}');
    expect(audio, hasLength(2));
    expect(subs.length, greaterThanOrEqualTo(2), reason: '内封 ASS + 外挂 SRT（sub-auto）');

    await shot(tester, '1_controls');

    // 字幕面板
    await tester.tap(find.text('字幕').first);
    await wait(tester, 500);
    await shot(tester, '2_subtitle_panel');
    expect(find.text('字幕延迟'), findsOneWidget);
    await tester.tap(find.textContaining('简中特效'));
    await wait(tester, 800);
    expect(player.state.track.subtitle.title, '简中特效');
    await tester.tapAt(const Offset(200, 400));
    await wait(tester, 1200);
    await shot(tester, '2b_ass_rendered');
    await tester.tap(find.text('字幕').first);
    await wait(tester, 500);
    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await wait(tester, 200);
    expect(s.subDelay, 0.1);
    await tester.tapAt(const Offset(200, 400)); // 点空白处关闭面板
    await wait(tester, 400);

    // 音轨面板：切到国语
    await tester.tap(find.text('音轨').first);
    await wait(tester, 500);
    await shot(tester, '3_audio_panel');
    await tester.tap(find.textContaining('国语'));
    await wait(tester, 600);
    expect(player.state.track.audio.title, '国语');
    await tester.tapAt(const Offset(200, 400));
    await wait(tester, 400);

    // 拖到 30 秒后退出 → 进度被记住
    await player.seek(const Duration(seconds: 30));
    await wait(tester, 1500);
    await tester.tap(find.byTooltip('返回').first);
    await wait(tester, 1200);
    final pr = db.progress(s.current.path)!;
    // ignore: avoid_print
    print('PLAYER saved progress=${pr.positionMs}ms finished=${pr.finished}');
    expect(pr.positionMs, greaterThan(29000));
    expect(pr.finished, isFalse);
    expect(find.textContaining('继续播放'), findsOneWidget);
    await shot(tester, '4_detail_resume');

    // 再次播放：从 30 秒续播并提示
    await tester.tap(find.textContaining('继续播放'));
    await wait(tester, 2500);
    final s2 = session(tester);
    expect(s2.resumedFrom, isNotNull);
    expect(s2.player.state.position, greaterThan(const Duration(seconds: 29)));
    expect(find.textContaining('已从'), findsOneWidget);
    await tester.tap(find.byTooltip('返回').first);
    await wait(tester, 1000);
    await tester.tap(find.byTooltip('返回').first);
    await wait(tester, 800);

    // 剧集：播完自动下一集
    await tester.tap(find.text('剧集').last);
    await wait(tester, 400);
    await tester.tap(find.text('绝命毒师').first);
    await wait(tester, 600);
    await tester.tap(find.textContaining('播放 S01E01'));
    await wait(tester, 2500);
    final s3 = session(tester);
    expect(s3.index, 0);
    await s3.player.seek(const Duration(seconds: 18));
    await wait(tester, 4000);
    // ignore: avoid_print
    print('PLAYER upNext=${s3.upNextCountdown} index=${s3.index}');
    expect(s3.upNextCountdown, isNotNull);
    await shot(tester, '5_up_next');
    await wait(tester, 6000);
    expect(s3.index, 1, reason: '倒计时结束自动播放下一集');
    expect(db.progress(s3.queue[0].path)!.finished, isTrue);
    await tester.tap(find.text('选集').first);
    await wait(tester, 500);
    await shot(tester, '6_episodes_panel');
    await tester.tapAt(const Offset(200, 400));
    await wait(tester, 300);
    await s3.player.seek(const Duration(seconds: 8));
    await wait(tester, 1500);
    await tester.tap(find.byTooltip('返回').first);
    await wait(tester, 1000);
    await tester.tap(find.byTooltip('返回').first);
    await wait(tester, 800);

    // 首页：继续观看
    await tester.tap(find.text('首页').last);
    await wait(tester, 1000);
    expect(find.text('继续观看'), findsOneWidget);
    await shot(tester, '7_home_continue');
  });
}
