import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../app/providers.dart';
import '../../ui/components.dart';
import 'folder_browser.dart';

/// 选择本地文件夹作为媒体源，并立即开始扫描。
Future<void> addLocalFolder(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  if (Platform.isAndroid && !await _ensureAndroidStorage(context)) {
    messenger.showSnackBar(const SnackBar(content: Text('未获得存储权限，无法读取媒体文件夹')));
    return;
  }

  if (!context.mounted) return;
  final picked = await FolderBrowser.pick(context);
  if (picked == null) return;
  final path = picked;
  if (!Directory(path).existsSync()) {
    messenger.showSnackBar(SnackBar(content: Text('无法访问：$path')));
    return;
  }

  final db = ref.read(dbProvider);
  if (db.sources().any((s) => p.equals(s.root, path))) {
    messenger.showSnackBar(const SnackBar(content: Text('这个文件夹已经添加过了')));
    return;
  }
  final name = p.basename(path).isEmpty ? path : p.basename(path);
  final id = db.addSource(type: 'local', name: name, root: path);
  ref.read(libraryRevisionProvider.notifier).bump();
  ref.read(scanProvider.notifier).scan(id);
  messenger.showSnackBar(SnackBar(content: Text('已添加「$name」，正在扫描…')));
}

/// Android 11+ 读取任意目录需要"所有文件访问权限"；10 及以下用普通存储权限。
Future<bool> _ensureAndroidStorage(BuildContext context) async {
  if (await Permission.manageExternalStorage.isGranted) return true;
  if (await Permission.storage.isGranted) return true;

  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('允许读取文件'),
      content: const Text('MyVidhub 需要读取视频、NFO 和海报图片。接下来会打开系统设置，'
          '请打开「允许访问所有文件」后返回。只读取，不会修改任何文件。'),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        PillButton(label: '取消', primary: false, compact: true, onPressed: () => Navigator.pop(c, false)),
        PillButton(label: '去设置', compact: true, onPressed: () => Navigator.pop(c, true)),
      ],
    ),
  );
  if (ok != true) return false;

  final manage = await Permission.manageExternalStorage.request();
  if (manage.isGranted) return true;
  // Android 10 及以下没有 MANAGE_EXTERNAL_STORAGE
  final legacy = await Permission.storage.request();
  return legacy.isGranted;
}
