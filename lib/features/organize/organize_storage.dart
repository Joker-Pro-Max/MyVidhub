import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/db/library_db.dart';
import '../../organizer/organize.dart';

const tmdbKeySetting = 'tmdb_api_key';

/// 打包时内置的默认 TMDB Key（tool/release.sh 从本机 .secrets/tmdb_api_key 读取，
/// 用 --dart-define 编译进 App；源代码和 git 仓库里没有这个 Key）。
const builtInTmdbKey = String.fromEnvironment('TMDB_API_KEY');

/// 实际使用的 Key：用户在设置里填的优先，否则用内置的。
String effectiveTmdbKey(LibraryDb db) {
  final custom = (db.setting(tmdbKeySetting) ?? '').trim();
  return custom.isNotEmpty ? custom : builtInTmdbKey;
}

Future<Directory> _support() => getApplicationSupportDirectory();

/// 整理 / 重新刮削 / 编辑信息 的撤销记录。
Future<UndoStore> organizeUndoStore() async => UndoStore(Directory(p.join((await _support()).path, 'organize_undo')));

/// 被替换掉的旧 NFO / 图片的备份目录（撤销时移回）。
Future<Directory> metadataBackupDir() async =>
    Directory(p.join((await _support()).path, 'metadata_backup', '${DateTime.now().millisecondsSinceEpoch}'));
