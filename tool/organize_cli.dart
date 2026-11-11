// 开发用：在命令行里对一个文件夹跑「刮削 → 整理」，和 App 里用的是同一套代码。
//
//   dart run tool/organize_cli.dart [--source auto|javbus|r18dev|tmdb] <文件夹> [TMDB_API_KEY]
//   已整理过（有 NFO）的视频会重新刮削、原地更新资料。
//   dart run tool/organize_cli.dart --undo <文件夹>
//
// 撤销记录写在 <文件夹>/.myvidhub-undo.json。
import 'dart:io';

import 'package:myvidhub/organizer/organize.dart';
import 'package:myvidhub/organizer/pipeline.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('用法：dart run tool/organize_cli.dart [--undo] <文件夹> [TMDB_API_KEY]');
    exit(64);
  }
  final undo = args.first == '--undo';
  var rest = undo ? args.skip(1).toList() : args;
  var choice = ScraperChoice.auto;
  if (rest.isNotEmpty && rest.first == '--source') {
    choice = ScraperChoice.values.byName(rest[1]);
    rest = rest.skip(2).toList();
  }
  final root = p.normalize(p.absolute(rest.first));
  final undoFile = File(p.join(root, '.myvidhub-undo.json'));

  if (undo) {
    if (!undoFile.existsSync()) {
      stderr.writeln('没有撤销记录');
      exit(1);
    }
    final (ok, errors) = await undoLog(UndoLog.decode(undoFile.readAsStringSync()));
    stdout.writeln('撤销完成：$ok 步${errors.isEmpty ? '' : '，失败：$errors'}');
    undoFile.deleteSync();
    return;
  }

  // Key 优先从环境变量读，避免出现在命令行参数（进程列表）里
  final tmdbKey = rest.length > 1 ? rest[1] : (Platform.environment['TMDB_API_KEY'] ?? '');
  final items = await scanForOrganize(root);
  stdout.writeln('找到 ${items.length} 个视频');
  final ops = <UndoOp>[];
  for (final item in items) {
    stdout.writeln('\n▶ ${item.fileName}  番号=${item.code ?? '无'}  预计 → ${item.targetFolder}');
    final sw = Stopwatch()..start();
    final r = item.alreadyOrganized
        ? await rescrapeItem(item, choice, tmdbKey, ops, Directory(p.join(root, '.myvidhub-backup')))
        : await processItem(item, root, tmdbKey, ops, choice: choice);
    if (item.alreadyOrganized) stdout.writeln('  （已整理，按 ${choice.label} 重新刮削）');
    stdout.writeln('  结果：${r.status.name}  来源=${r.source ?? '-'}  标题=${r.title ?? '-'}  (${sw.elapsedMilliseconds} ms)');
    if (r.dest != null) stdout.writeln('  位置：${r.dest}');
    if (r.message != null) stdout.writeln('  说明：${r.message}');
    for (final w in r.warnings) {
      stdout.writeln('  警告：$w');
    }
  }
  if (ops.isNotEmpty) {
    undoFile.writeAsStringSync(UndoLog(createdAt: DateTime.now(), root: root, ops: ops).encode());
    stdout.writeln('\n已记录撤销信息：${undoFile.path}');
  }
}
