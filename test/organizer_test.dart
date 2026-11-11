// 刮削整理（移植自花栗鼠）的单元测试：用例沿用花栗鼠 Rust 版本，确保行为一致。
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:myvidhub/domain/nfo_parser.dart';
import 'package:myvidhub/organizer/code.dart';
import 'package:myvidhub/organizer/images.dart';
import 'package:myvidhub/organizer/meta.dart';
import 'package:myvidhub/organizer/nfo_writer.dart';
import 'package:myvidhub/organizer/organize.dart';
import 'package:myvidhub/organizer/scrapers/javbus.dart';
import 'package:myvidhub/organizer/scrapers/r18dev.dart';
import 'package:path/path.dart' as p;

const _page = '''<html><head><title>IPX-535 完整標題 - JavBus</title>
<meta name="description" content="【發行日期】2021-02-03，(IPX-535)簡介文字"></head><body>
<a class="bigImage" href="/pics/cover/abc_b.jpg"><img src="/pics/thumb/abc.jpg"></a>
<div class="info">
  <p><span class="header">發行日期:</span> 2021-02-03</p>
  <p><span class="header">長度:</span> 120分鐘</p>
  <p><span class="header">導演:</span> <a href="/director/1">導演甲</a></p>
  <p><span class="header">製作商:</span> <a href="/studio/1">S1</a></p>
  <p><span class="header">系列:</span> <a href="/series/1">系列乙</a></p>
  <p><a href="/genre/1">高畫質</a> <a href="/genre/2">單體作品</a></p>
</div>
<div id="avatar-waterfall">
  <a href="/star/1"><img src="/pics/actress/1_a.jpg" title="女優甲"></a>
  <a href="/star/2"><img src="/pics/actress/2_a.jpg" title="演員"></a>
</div></body></html>''';

void main() {
  test('番号识别', () {
    expect(extractCode('SSIS-001.mp4'), 'SSIS-001');
    expect(extractCode('SONE_890_标题.mp4'), 'SONE-890');
    expect(extractCode('300MIUM-001.mkv'), '300MIUM-001');
    expect(extractCode('T38-002.mp4'), 'T38-002');
    expect(extractCode('t28_555.mp4'), 'T28-555');
    expect(extractCode('PPPE-378C.mp4'), 'PPPE-378');
    expect(extractCode('ipx-535.mp4'), 'IPX-535');
    expect(extractCode('RandomMovie2023.mp4'), isNull);
    expect(extractCode('Interstellar.2014.1080p.mkv'), isNull);
    expect(normalizeCode('ssis-001'), normalizeCode('SSIS_001'));
    final v = contentIdVariants('SSIS-001');
    expect(v.first, 'ssi00001');
    expect(v, contains('ssis1'));
    expect(v.length, lessThanOrEqualTo(4));
    expect(contentIdVariants('AB-12').first, 'ab000012');
  });

  test('片名年份解析与文件夹命名', () {
    expect(parseTitleYear('Interstellar.2014.1080p.BluRay'), ('Interstellar', 2014));
    expect(parseTitleYear('Some_Movie'), ('Some Movie', null));
    expect(sanitizeName('a/b:c*d?'), 'a b c d');
    expect(sanitizeName('  ..name.. '), 'name');
    expect(folderNameFor('SSIS-001', 'x', null), 'SSIS-001');
    expect(folderNameFor('SSIS-001', 'x', 2021), 'SSIS-001 (2021)');
    expect(folderNameFor(null, '流浪地球', 2019), '流浪地球 (2019)');
    expect(folderNameFor(null, 'No Year', null), 'No Year');
  });

  test('JavBus 详情页解析', () {
    final m = parseJavbusDetail(_page, 'https://www.javbus.com/IPX-535', 'IPX-535');
    expect(m.code, 'IPX-535');
    expect(m.title, '完整標題');
    expect(m.releaseDate, '2021-02-03');
    expect(m.year, 2021);
    expect(m.runtimeMins, 120);
    expect(m.directors, ['導演甲']);
    expect(m.studio, 'S1');
    expect(m.series, '系列乙');
    expect(m.genres, ['高畫質', '單體作品']);
    expect(m.actors.single.name, '女優甲');
    expect(m.coverUrl, 'https://www.javbus.com/pics/cover/abc_b.jpg');
    expect(m.plot, isNull, reason: 'javbus 的 meta description 是拼接文本，不是简介');

    final real = parseJavbusDetail(
        _page.replaceAll('【發行日期】2021-02-03，(IPX-535)簡介文字', '这是一段真正的剧情简介'), 'https://www.javbus.com/IPX-535', 'IPX-535');
    expect(real.plot, '这是一段真正的剧情简介');
  });

  test('R18.dev JSON 映射', () {
    final m = mapR18('ssis-001', {
      'title_en': 'English Title',
      'title_ja': '日本語タイトル',
      'comment_en': 'A plot.',
      'release_date': '2021-02-19 10:00:00',
      'runtime_mins': 150,
      'actresses': [
        {'name_romaji': 'Actress A', 'image_url': 'https://x/a.jpg'},
        {'name_romaji': 'Actress A'},
      ],
      'categories': [
        {'name_en': 'Drama'}
      ],
      'maker': {'name': 'S1'},
      'jacket_full_url': 'https://x/full.jpg',
      'jacket_thumb_url': 'https://x/thumb.jpg',
    });
    expect(m.code, 'SSIS-001');
    expect(m.title, 'English Title');
    expect(m.originalTitle, '日本語タイトル');
    expect(m.year, 2021);
    expect(m.releaseDate, '2021-02-19');
    expect(m.runtimeMins, 150);
    expect(m.actors.length, 1);
    expect(m.studio, 'S1');
    expect(m.coverUrl, 'https://x/full.jpg');
    expect(m.posterUrl, 'https://x/thumb.jpg');
  });

  test('生成的 NFO 能被 ReelNest 自己读回', () {
    final meta = ScrapedMeta(
      source: 'javbus',
      code: 'IPX-535',
      title: 'A & B <标题>',
      year: 2021,
      releaseDate: '2021-02-03',
      runtimeMins: 120,
      genres: ['剧情'],
      actors: [const ScrapedActor('女優甲', 'https://x/a.jpg')],
      studio: 'S1',
      series: '系列乙',
    );
    final nfo = NfoParser.parse(renderMovieNfo(meta))!;
    expect(nfo.title, 'A & B <标题>');
    expect(nfo.sortTitle, 'IPX-535');
    expect(nfo.year, 2021);
    expect(nfo.setName, '系列乙');
    expect(nfo.actors.single.name, '女優甲');
    expect(nfo.uniqueIds['num'], 'IPX-535');
    // 没有简介时用已有字段拼一句
    expect(nfo.plot, contains('厂牌：S1'));
  });

  test('横版封面裁出右侧竖版海报', () async {
    final wide = img.Image(width: 800, height: 538);
    final bytes = Uint8List.fromList(img.encodeJpg(wide));
    expect(looksLikeImage(bytes), isTrue);
    expect(isWideCover(bytes), isTrue);
    final poster = img.decodeImage(await cropPoster(bytes))!;
    expect(poster.width, 800 - (800 * 0.5263).round());
    expect(poster.height, 538);
  });

  group('整理与撤销', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('myvidhub_org'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('移动视频和字幕、写 NFO、不覆盖、撤销还原', () async {
      final root = tmp.path;
      final sub = Directory(p.join(root, '下载', 'x'))..createSync(recursive: true);
      File(p.join(sub.path, 'ssis-001.mp4')).writeAsStringSync('video');
      File(p.join(sub.path, 'ssis-001.zh.srt')).writeAsStringSync('sub');
      File(p.join(sub.path, 'other.srt')).writeAsStringSync('unrelated');
      File(p.join(root, 'Some.Movie.2020.mkv')).writeAsStringSync('m');
      File(p.join(root, 'Some.Movie.2020.nfo')).writeAsStringSync('<movie/>');

      final items = await scanForOrganize(root);
      expect(items.length, 2);
      final jav = items.firstWhere((i) => i.code != null);
      expect(jav.code, 'SSIS-001');
      expect(jav.targetFolder, 'SSIS-001 (发行年份)');
      expect(jav.alreadyOrganized, isFalse);
      expect(items.firstWhere((i) => i.code == null).alreadyOrganized, isTrue);

      final plan = buildPlan(jav.path, root, 'SSIS-001 (2021)');
      expect(plan.sidecars.single.$2, p.join(root, 'SSIS-001 (2021)', 'SSIS-001 (2021).zh.srt'));

      final ops = <UndoOp>[];
      final moved = <String>[];
      final meta = ScrapedMeta(source: 'test', code: 'SSIS-001', title: '标题', year: 2021);
      final rep = await executePlan(plan, meta, ops, onMoved: (f, t) => moved.add(t));
      final dir = p.join(root, 'SSIS-001 (2021)');
      expect(rep.destVideo, p.join(dir, 'SSIS-001 (2021).mp4'));
      expect(File(rep.destVideo).readAsStringSync(), 'video');
      expect(File(p.join(dir, 'SSIS-001 (2021).zh.srt')).existsSync(), isTrue);
      expect(File(p.join(dir, 'SSIS-001 (2021).nfo')).existsSync(), isTrue);
      expect(File(p.join(sub.path, 'other.srt')).existsSync(), isTrue, reason: '不相关的字幕不动');
      expect(moved, [rep.destVideo]);

      // 目标已被别的文件占用 → 跳过，绝不覆盖
      File(p.join(root, 'b.mp4')).writeAsStringSync('another');
      expect(() => buildPlan(p.join(root, 'b.mp4'), root, 'SSIS-001 (2021)'), throwsA(isA<OrganizeException>()));

      final log = UndoLog(createdAt: DateTime.now(), root: root, ops: ops);
      final store = UndoStore(Directory(p.join(tmp.path, '.undo')));
      await store.save(log);
      final latest = await store.latestFor(root);
      expect(latest, isNotNull);
      expect(latest!.$2.movedVideos, 1);

      final (ok, errors) = await undoLog(latest.$2);
      expect(errors, isEmpty);
      expect(ok, ops.length);
      expect(File(p.join(sub.path, 'ssis-001.mp4')).readAsStringSync(), 'video');
      expect(File(p.join(sub.path, 'ssis-001.zh.srt')).existsSync(), isTrue);
      expect(Directory(dir).existsSync(), isFalse);
    });

    test('重新刮削：替换旧 NFO（先备份），撤销后恢复原样', () async {
      final dir = Directory(p.join(tmp.path, 'SSIS-001 (2021)'))..createSync();
      final video = p.join(dir.path, 'SSIS-001 (2021).mp4');
      File(video).writeAsStringSync('v');
      final nfo = File(p.join(dir.path, 'SSIS-001 (2021).nfo'))..writeAsStringSync('<movie><title>旧标题</title></movie>');

      final ops = <UndoOp>[];
      final backup = Directory(p.join(tmp.path, '.backup'));
      await refreshMetadata(video, ScrapedMeta(source: 'test', code: 'SSIS-001', title: '新标题', year: 2021), ops, backup);
      expect(NfoParser.parse(nfo.readAsStringSync())!.title, '新标题');
      expect(File(video).readAsStringSync(), 'v', reason: '视频不动');
      expect(backup.listSync(), hasLength(1));

      final (_, errors) = await undoLog(UndoLog(createdAt: DateTime.now(), root: tmp.path, ops: ops));
      expect(errors, isEmpty);
      expect(NfoParser.parse(nfo.readAsStringSync())!.title, '旧标题');
    });
  });
}
