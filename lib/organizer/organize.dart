// 扫描待整理视频、生成整理计划、执行与撤销（移植自花栗鼠 scan.rs / organize.rs）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'code.dart';
import 'images.dart';
import 'meta.dart';
import 'nfo_writer.dart';

const organizeVideoExts = {'mp4', 'mkv', 'mov', 'avi', 'wmv', 'flv', 'ts', 'm4v', 'webm', 'rmvb', 'mpg', 'mpeg'};
const organizeSubtitleExts = {'srt', 'ass', 'ssa', 'vtt', 'sub', 'idx', 'sup'};

// ------------------------------------------------------------------ 扫描

class VideoItem {
  VideoItem({
    required this.path,
    required this.fileName,
    required this.sizeBytes,
    required this.code,
    required this.title,
    required this.year,
    required this.targetFolder,
    required this.alreadyOrganized,
  });

  final String path;
  final String fileName;
  final int sizeBytes;

  /// JAV 番号；摘不出来就是普通电影
  final String? code;

  /// 从文件名粗解析出的片名（普通电影刮削用）
  final String title;
  final int? year;

  /// 预览用：整理后会放进哪个文件夹
  final String targetFolder;

  /// 同目录已经有同名 NFO，视为已整理过
  final bool alreadyOrganized;
}

final _yearRe = RegExp(r'[.\s_(\[]((?:19|20)\d{2})[.\s_)\]]?');
final _noiseRe = RegExp(
    r'\b(1080p|720p|2160p|4k|x264|x265|h264|h265|hevc|webrip|web-dl|bluray|bdrip|hdtv|aac|dts|mkv|mp4)\b',
    caseSensitive: false);

/// 从文件名粗解析片名和年份（普通电影用）。
(String, int?) parseTitleYear(String stem) {
  final normalized = stem.replaceAll(RegExp(r'[._]'), ' ');
  final ym = _yearRe.firstMatch(stem);
  final year = ym == null ? null : int.tryParse(ym.group(1)!);
  var title = normalized;
  // _yearRe 在原始 stem 上匹配；normalized 只是把 . _ 换成空格，长度不变
  if (ym != null) title = normalized.substring(0, ym.start);
  title = title.replaceAll(_noiseRe, '');
  title = title.replaceAll(RegExp(r'^[ .\-_]+|[ .\-_]+$'), '');
  title = title.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).join(' ');
  return (title.isEmpty ? stem : title, year);
}

/// 文件夹/文件名里不能出现的字符替换掉，去掉首尾的点和空格。
String sanitizeName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1F]'), ' ');
  final collapsed = cleaned.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).join(' ');
  final trimmed = collapsed.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  final chars = trimmed.runes.take(120).toList();
  return String.fromCharCodes(chars).trim();
}

/// 整理后的文件夹名，一律是电影标准写法 "名字 (年份)"：JAV 用番号，普通电影用片名。
/// 带年份是为了让 VidHub / Infuse 判成电影——只有 "SNOS-008" 这种 "字母-数字"，
/// 播放器会把数字当集数，把 SNOS-008 和 SNOS-030 合并成同一部剧的第 8、30 集。
String folderNameFor(String? code, String title, int? year) {
  final base = code != null ? sanitizeName(code) : sanitizeName(title);
  return year != null ? '$base ($year)' : base;
}

/// 扫描文件夹里的视频（跳过隐藏文件和 macOS 的 ._ 资源叉文件）。
Future<List<VideoItem>> scanForOrganize(String root, {bool recursive = true}) async {
  final paths = <File>[];
  await for (final e in Directory(root).list(recursive: recursive, followLinks: false)) {
    if (e is! File) continue;
    final name = p.basename(e.path);
    if (name.startsWith('.')) continue;
    if (!organizeVideoExts.contains(p.extension(name).replaceFirst('.', '').toLowerCase())) continue;
    // 跳过隐藏目录里的文件
    if (p.split(p.relative(e.path, from: root)).any((s) => s.startsWith('.'))) continue;
    paths.add(e);
  }
  paths.sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in paths)
      () {
        final fileName = p.basename(f.path);
        final stem = p.basenameWithoutExtension(f.path);
        final code = extractCode(fileName);
        final (title, year) = parseTitleYear(stem);
        return VideoItem(
          path: f.path,
          fileName: fileName,
          sizeBytes: f.lengthSync(),
          code: code,
          title: title,
          year: year,
          // 番号的发行年份要刮削之后才知道
          targetFolder: code != null ? '${folderNameFor(code, title, null)} (发行年份)' : folderNameFor(null, title, year),
          alreadyOrganized: File(p.setExtension(f.path, '.nfo')).existsSync(),
        );
      }(),
  ];
}

// ------------------------------------------------------------------ 撤销日志

/// 撤销日志里的一步操作；撤销时按相反顺序执行。
class UndoOp {
  const UndoOp(this.op, {this.path, this.from, this.to});
  final String op; // mkdir | move | create | rmdir
  final String? path;
  final String? from;
  final String? to;

  Map<String, dynamic> toJson() => {'op': op, 'path': ?path, 'from': ?from, 'to': ?to};
  static UndoOp fromJson(Map<String, dynamic> m) =>
      UndoOp(m['op'] as String, path: m['path'] as String?, from: m['from'] as String?, to: m['to'] as String?);
}

class UndoLog {
  UndoLog({required this.createdAt, required this.root, required this.ops});
  final DateTime createdAt;
  final String root;
  final List<UndoOp> ops;

  int get movedVideos => ops.where((o) => o.op == 'move' && organizeVideoExts.contains(p.extension(o.to!).replaceFirst('.', '').toLowerCase())).length;

  String encode() => jsonEncode({
        'created_at': createdAt.toIso8601String(),
        'root': root,
        'ops': [for (final o in ops) o.toJson()],
      });

  static UndoLog decode(String s) {
    final m = jsonDecode(s) as Map<String, dynamic>;
    return UndoLog(
      createdAt: DateTime.parse(m['created_at'] as String),
      root: m['root'] as String,
      ops: [for (final o in m['ops'] as List) UndoOp.fromJson(Map<String, dynamic>.from(o as Map))],
    );
  }
}

class UndoStore {
  UndoStore(this.dir);
  final Directory dir;

  Future<File?> save(UndoLog log) async {
    if (log.ops.isEmpty) return null;
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, '${log.createdAt.millisecondsSinceEpoch}.json'));
    await f.writeAsString(log.encode());
    return f;
  }

  /// 某个根目录最近一次的整理记录。
  Future<(File, UndoLog)?> latestFor(String root) async {
    if (!dir.existsSync()) return null;
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in files) {
      try {
        final log = UndoLog.decode(await f.readAsString());
        if (p.equals(log.root, root)) return (f, log);
      } catch (_) {}
    }
    return null;
  }
}

// ------------------------------------------------------------------ 计划与执行

class OrganizePlan {
  OrganizePlan({required this.src, required this.dir, required this.stem, required this.ext, required this.sidecars});
  final String src;
  final String dir;
  final String stem;
  final String ext;
  final List<(String, String)> sidecars;

  String get destVideo => p.join(dir, '$stem.$ext');
}

class OrganizeException implements Exception {
  const OrganizeException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool _sameFile(String a, String b) {
  try {
    return File(a).resolveSymbolicLinksSync() == File(b).resolveSymbolicLinksSync();
  } catch (_) {
    return false;
  }
}

/// 生成整理计划。目标位置已被另一个文件占用时抛异常，绝不覆盖。
OrganizePlan buildPlan(String src, String root, String folderName) {
  final ext = p.extension(src).replaceFirst('.', '');
  if (ext.isEmpty) throw const OrganizeException('文件没有扩展名');
  final dir = p.join(root, folderName);
  final stem = folderName;
  final dest = p.join(dir, '$stem.$ext');
  if (File(dest).existsSync() && !_sameFile(src, dest)) {
    throw OrganizeException('目标已存在，已跳过：$dest');
  }

  final srcStem = p.basenameWithoutExtension(src);
  final sidecars = <(String, String)>[];
  try {
    for (final e in Directory(p.dirname(src)).listSync()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (!organizeSubtitleExts.contains(p.extension(name).replaceFirst('.', '').toLowerCase())) continue;
      // 字幕必须以视频的文件名开头（SSIS-001.zh.srt 跟 SSIS-001.mp4 配对）
      if (!name.startsWith(srcStem)) continue;
      final rest = name.substring(srcStem.length);
      if (!rest.startsWith('.')) continue;
      sidecars.add((e.path, p.join(dir, '$stem$rest')));
    }
  } catch (_) {}
  sidecars.sort((a, b) => a.$1.compareTo(b.$1));
  return OrganizePlan(src: src, dir: dir, stem: stem, ext: ext, sidecars: sidecars);
}

/// 同盘直接 rename；只有跨盘才退回"复制、校验大小、再删原文件"。
Future<void> moveFile(String from, String to) async {
  if (File(to).existsSync()) throw OrganizeException('目标已存在：$to');
  try {
    await File(from).rename(to);
  } on FileSystemException catch (e) {
    final code = e.osError?.errorCode;
    if (code == 18 /* EXDEV */) return _copyThenDelete(from, to);
    if (code == 1 || code == 13 /* EPERM / EACCES */) {
      throw OrganizeException('没有权限移动（文件可能被锁定，或缺少文件访问授权）：$from');
    }
    throw OrganizeException('移动失败：${e.osError?.message ?? e.message}');
  }
}

Future<void> _copyThenDelete(String from, String to) async {
  final want = File(from).lengthSync();
  await File(from).copy(to);
  if (File(to).lengthSync() != want) {
    try {
      File(to).deleteSync();
    } catch (_) {}
    throw const OrganizeException('复制后大小不一致，已放弃，原文件未动');
  }
  try {
    File(from).deleteSync();
  } catch (e) {
    // 原文件删不掉就把刚复制的副本删掉，不留重复文件
    try {
      File(to).deleteSync();
    } catch (_) {}
    throw OrganizeException('删除原文件失败，已撤回复制：$e');
  }
}

Future<void> _writeNew(String path, List<int> data, List<UndoOp> ops) async {
  if (File(path).existsSync()) return; // 不覆盖已有文件
  await File(path).writeAsBytes(data);
  ops.add(UndoOp('create', path: path));
}

class ExecReport {
  const ExecReport(this.destVideo, this.warnings);
  final String destVideo;

  /// 非致命问题（比如图片下载失败），整理本身仍然成功
  final List<String> warnings;
}

/// 执行整理：建文件夹 → 移动视频和字幕 → 写 NFO → 下载封面 / 海报。
/// [onMoved] 在视频移动后回调（ReelNest 用来迁移播放进度）。
Future<ExecReport> executePlan(
  OrganizePlan plan,
  ScrapedMeta meta,
  List<UndoOp> ops, {
  void Function(String from, String to)? onMoved,
}) async {
  final warnings = <String>[];
  if (!Directory(plan.dir).existsSync()) {
    await Directory(plan.dir).create(recursive: true);
    ops.add(UndoOp('mkdir', path: plan.dir));
  }

  final dest = plan.destVideo;
  if (!_sameFile(plan.src, dest)) {
    await moveFile(plan.src, dest);
    ops.add(UndoOp('move', from: plan.src, to: dest));
    onMoved?.call(plan.src, dest);
    for (final (from, to) in plan.sidecars) {
      try {
        await moveFile(from, to);
        ops.add(UndoOp('move', from: from, to: to));
      } catch (e) {
        warnings.add('字幕未移动：$e');
      }
    }
    // 源目录搬空了就顺手删掉（只删空目录；绝不删用户选的根文件夹本身）
    final parent = p.dirname(plan.src);
    final isRoot = p.equals(p.dirname(plan.dir), parent);
    if (!p.equals(parent, plan.dir) && !isRoot) {
      try {
        Directory(parent).deleteSync();
        ops.add(UndoOp('rmdir', path: parent));
      } catch (_) {}
    }
  }

  // 元数据文件。VidHub 认 <视频名>.nfo、<视频名>-poster.jpg、<视频名>-fanart.jpg；
  // Infuse / Kodi / Jellyfin 认 poster.jpg、fanart.jpg，两套都写。
  await _writeNew(p.join(plan.dir, '${plan.stem}.nfo'), utf8.encode(renderMovieNfo(meta)), ops);

  Uint8List? cover;
  if (meta.coverUrl != null) {
    try {
      cover = await downloadImage(meta.coverUrl!);
    } catch (e) {
      warnings.add('封面：$e');
    }
  }
  final poster = await _posterFor(meta, cover, warnings);

  if (poster != null) {
    await _writeNew(p.join(plan.dir, '${plan.stem}-poster.jpg'), poster, ops);
    await _writeNew(p.join(plan.dir, 'poster.jpg'), poster, ops);
  }
  if (cover != null) {
    await _writeNew(p.join(plan.dir, '${plan.stem}-fanart.jpg'), cover, ops);
    await _writeNew(p.join(plan.dir, 'fanart.jpg'), cover, ops);
  }
  return ExecReport(dest, warnings);
}

/// 选海报：番号片（JavBus / R18.dev）的封面是正面+背面拼成的横图，裁右侧正面当海报；
/// TMDB 有正规竖版海报，直接用（不能拿横版剧照去裁）。
Future<Uint8List?> _posterFor(ScrapedMeta meta, Uint8List? cover, List<String> warnings) async {
  Future<Uint8List?> download() async {
    try {
      return await downloadImage(meta.posterUrl!);
    } catch (e) {
      warnings.add('海报：$e');
      return null;
    }
  }

  final jav = meta.source == 'javbus' || meta.source == 'r18dev';
  if (!jav && meta.posterUrl != null) return await download() ?? cover;
  if (cover != null && await isWideCoverAsync(cover)) {
    try {
      return await cropPoster(cover);
    } catch (e) {
      warnings.add('海报裁剪失败：$e');
    }
  }
  if (meta.posterUrl != null) return download();
  return cover;
}

// ------------------------------------------------------------------ 原地更新资料（重新刮削 / 编辑信息）

/// 替换一个已有文件：旧文件先移进备份目录（记为 move，撤销时移回），再写新文件（记为 create）。
Future<void> replaceFile(String path, List<int> data, List<UndoOp> ops, Directory backupDir) async {
  if (File(path).existsSync()) {
    await backupDir.create(recursive: true);
    final backup = p.join(backupDir.path, '${DateTime.now().microsecondsSinceEpoch}_${p.basename(path)}');
    await moveFile(path, backup);
    ops.add(UndoOp('move', from: path, to: backup));
  }
  await File(path).writeAsBytes(data);
  ops.add(UndoOp('create', path: path));
}

/// 用新的资料更新一部已整理影片：写 NFO、海报、背景图（旧的备份后替换），视频不移动。
/// [nfoPath] 为原来的 NFO（可能是 movie.nfo）；为空时写 `<视频名>.nfo`。
/// 只有文件夹里只有这一部影片时，才同时写通用名 poster.jpg / fanart.jpg。
Future<ExecReport> refreshMetadata(
  String videoPath,
  ScrapedMeta meta,
  List<UndoOp> ops,
  Directory backupDir, {
  String? nfoPath,
  bool writeImages = true,
}) async {
  final warnings = <String>[];
  final dir = p.dirname(videoPath);
  final stem = p.basenameWithoutExtension(videoPath);
  final videosHere = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => organizeVideoExts.contains(p.extension(f.path).replaceFirst('.', '').toLowerCase()))
      .length;
  final single = videosHere <= 1;

  await replaceFile(nfoPath ?? p.join(dir, '$stem.nfo'), utf8.encode(renderMovieNfo(meta)), ops, backupDir);
  if (!writeImages) return ExecReport(videoPath, warnings);

  Uint8List? cover;
  if (meta.coverUrl != null) {
    try {
      cover = await downloadImage(meta.coverUrl!);
    } catch (e) {
      warnings.add('封面：$e');
    }
  }
  final poster = await _posterFor(meta, cover, warnings);
  if (poster != null) {
    await replaceFile(p.join(dir, '$stem-poster.jpg'), poster, ops, backupDir);
    if (single) await replaceFile(p.join(dir, 'poster.jpg'), poster, ops, backupDir);
  }
  if (cover != null) {
    await replaceFile(p.join(dir, '$stem-fanart.jpg'), cover, ops, backupDir);
    if (single) await replaceFile(p.join(dir, 'fanart.jpg'), cover, ops, backupDir);
  }
  return ExecReport(videoPath, warnings);
}

/// 按相反顺序撤销一份日志。返回 (成功步数, 失败说明)。
/// [onRestored] 在视频移回原位后回调（迁移回播放进度）。
Future<(int, List<String>)> undoLog(UndoLog log, {void Function(String from, String to)? onRestored}) async {
  var ok = 0;
  final errors = <String>[];
  for (final op in log.ops.reversed) {
    try {
      switch (op.op) {
        case 'create':
          final f = File(op.path!);
          if (f.existsSync()) f.deleteSync();
        case 'move':
          await Directory(p.dirname(op.from!)).create(recursive: true);
          await moveFile(op.to!, op.from!);
          onRestored?.call(op.to!, op.from!);
        case 'mkdir':
          final d = Directory(op.path!);
          if (d.existsSync()) {
            try {
              d.deleteSync();
            } catch (_) {
              throw OrganizeException('目录 ${op.path} 不是空的，已保留');
            }
          }
        case 'rmdir':
          await Directory(op.path!).create(recursive: true);
      }
      ok++;
    } catch (e) {
      errors.add('$e');
    }
  }
  return (ok, errors);
}
