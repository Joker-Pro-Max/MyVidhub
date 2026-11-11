import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/media_extensions.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';

/// 存储位置（内部存储 / SD 卡 / U 盘 / 个人文件夹 / 外接磁盘）。
class StorageRoot {
  const StorageRoot(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

Future<List<StorageRoot>> storageRoots() async {
  final out = <StorageRoot>[];
  // 存在且可以列出内容（无权限的挂载点会抛异常）
  bool ok(String path) {
    try {
      Directory(path).listSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  if (Platform.isAndroid) {
    if (ok('/storage/emulated/0')) {
      out.add(const StorageRoot('/storage/emulated/0', '内部存储', Icons.phone_android_rounded));
    }
    try {
      for (final e in Directory('/storage').listSync()) {
        final name = p.basename(e.path);
        if (e is! Directory || name == 'emulated' || name == 'self') continue;
        if (ok(e.path)) out.add(StorageRoot(e.path, 'SD 卡 / U 盘（$name）', Icons.sd_card_outlined));
      }
    } catch (_) {}
  } else if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null) out.add(StorageRoot(home, '个人文件夹', Icons.home_outlined));
    try {
      for (final e in Directory('/Volumes').listSync()) {
        if (e is Directory && !p.basename(e.path).startsWith('.')) {
          out.add(StorageRoot(e.path, p.basename(e.path), Icons.storage_rounded));
        }
      }
    } catch (_) {}
  } else if (Platform.isWindows) {
    for (var c = 'C'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
      final drive = '${String.fromCharCode(c)}:\\';
      if (Directory(drive).existsSync()) out.add(StorageRoot(drive, '本地磁盘（${String.fromCharCode(c)}:）', Icons.storage_rounded));
    }
  } else {
    final docs = await getApplicationDocumentsDirectory();
    out.add(StorageRoot(docs.path, '本 App 的文件', Icons.folder_special_outlined));
  }
  return out;
}

/// 把绝对路径换成好读的形式：/storage/emulated/0/Movies → 内部存储 › Movies
String friendlyPath(String path, List<StorageRoot> roots) {
  for (final r in roots) {
    if (p.equals(path, r.path)) return r.label;
    if (p.isWithin(r.path, path)) {
      return [r.label, ...p.split(p.relative(path, from: r.path))].join(' › ');
    }
  }
  return path;
}

/// 自建的文件夹浏览器，替代系统选择器。返回所选文件夹的绝对路径。
class FolderBrowser extends StatefulWidget {
  const FolderBrowser({super.key, this.initialPath});
  final String? initialPath;

  static Future<String?> pick(BuildContext context, {String? initialPath}) =>
      Navigator.of(context).push<String>(FadeRoute(builder: (_) => FolderBrowser(initialPath: initialPath)));

  @override
  State<FolderBrowser> createState() => _FolderBrowserState();
}

class _DirInfo {
  const _DirInfo(this.folders, this.videos);
  final int folders;
  final int videos;
}

class _FolderBrowserState extends State<FolderBrowser> {
  List<StorageRoot> _roots = const [];
  String? _path; // null = 存储位置列表
  List<Directory> _dirs = const [];
  int _videosHere = 0;
  String? _error;
  final _info = <String, Future<_DirInfo>>{};

  @override
  void initState() {
    super.initState();
    storageRoots().then((r) {
      if (!mounted) return;
      setState(() => _roots = r);
      if (widget.initialPath != null) _open(widget.initialPath);
    });
  }

  void _open(String? path) {
    if (path == null) {
      setState(() {
        _path = null;
        _dirs = const [];
        _error = null;
      });
      return;
    }
    try {
      final entries = Directory(path).listSync(followLinks: false);
      final dirs = entries.whereType<Directory>().where((d) => !isIgnoredDir(p.basename(d.path))).toList()
        ..sort((a, b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase()));
      setState(() {
        _path = path;
        _dirs = dirs;
        _videosHere = entries.whereType<File>().where((f) => isVideoFile(p.basename(f.path))).length;
        _error = null;
      });
    } on FileSystemException catch (e) {
      setState(() {
        _path = path;
        _dirs = const [];
        _error = '无法打开这个文件夹（${e.osError?.message ?? e.message}）';
      });
    }
  }

  StorageRoot? get _root =>
      _path == null ? null : _roots.where((r) => p.equals(r.path, _path!) || p.isWithin(r.path, _path!)).firstOrNull;

  void _up() {
    final root = _root;
    if (_path == null) return Navigator.pop(context);
    if (root == null || p.equals(root.path, _path!)) return _open(null);
    _open(p.dirname(_path!));
  }

  Future<_DirInfo> _infoOf(String path) => _info.putIfAbsent(path, () async {
        var folders = 0, videos = 0, seen = 0;
        try {
          await for (final e in Directory(path).list(followLinks: false)) {
            if (++seen > 2000) break;
            final name = p.basename(e.path);
            if (e is Directory) {
              if (!isIgnoredDir(name)) folders++;
            } else if (isVideoFile(name)) {
              videos++;
            }
          }
        } catch (_) {}
        return _DirInfo(folders, videos);
      });

  Future<void> _systemPicker() async {
    try {
      final picked = await FilePicker.getDirectoryPath(dialogTitle: '选择影视文件夹');
      if (picked != null && mounted) Navigator.pop(context, picked);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ff = FormFactor.of(context);
    final g = ff.gutter;
    final pad = MediaQuery.paddingOf(context);
    final root = _root;
    final crumbs = <(String, String)>[]; // (label, path)
    if (root != null && _path != null) {
      crumbs.add((root.label, root.path));
      var acc = root.path;
      for (final seg in p.split(p.relative(_path!, from: root.path))) {
        if (seg == '.') continue;
        acc = p.join(acc, seg);
        crumbs.add((seg, acc));
      }
    }

    return PopScope(
      canPop: _path == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 标题栏
              Padding(
                padding: EdgeInsets.fromLTRB(g - 8, pad.top + 12, g - 8, 0),
                child: Row(children: [
                  RoundIconButton(
                    icon: _path == null ? Icons.close_rounded : Icons.arrow_back_rounded,
                    tooltip: _path == null ? '关闭' : '上一级',
                    onPressed: _up,
                  ),
                  const Spacer(),
                  Pressable(
                    onTap: _systemPicker,
                    radius: 18,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text('使用系统选择器', style: TypeScale.callout.copyWith(color: Palette.text2)),
                    ),
                  ),
                ]),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(g, 20, g, 6),
                child: Text(_path == null ? '选择影视文件夹' : p.basename(_path!).isEmpty ? root!.label : p.basename(_path!),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.largeTitle),
              ),
              // 路径面包屑
              SizedBox(
                height: 36,
                child: _path == null
                    ? Padding(
                        padding: EdgeInsets.symmetric(horizontal: g),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('选一个存放电影或剧集的文件夹，子文件夹会一起扫描。',
                              style: TypeScale.callout.copyWith(color: Palette.text2)),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        padding: EdgeInsets.symmetric(horizontal: g - 8),
                        itemCount: crumbs.length,
                        separatorBuilder: (_, _) =>
                            const Icon(Icons.chevron_right_rounded, size: 18, color: Palette.text3),
                        itemBuilder: (_, i) {
                          final c = crumbs[crumbs.length - 1 - i];
                          final last = i == 0;
                          return Pressable(
                            onTap: last ? null : () => _open(c.$2),
                            radius: 8,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Center(
                                child: Text(c.$1,
                                    style: TypeScale.callout.copyWith(
                                        color: last ? Palette.text : Palette.text2,
                                        fontWeight: last ? FontWeight.w600 : FontWeight.w500)),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),
              Expanded(child: _path == null ? _rootList(g) : _dirList(g)),
              if (_path != null) _bottomBar(g, pad.bottom),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _rootList(double g) => ListView(
        padding: EdgeInsets.fromLTRB(g, 8, g, 32),
        children: [
          GroupedList(
            header: '存储位置',
            children: [
              for (final r in _roots)
                SettingRow(icon: r.icon, title: r.label, subtitle: r.path, onTap: () => _open(r.path)),
              if (_roots.isEmpty)
                const SettingRow(icon: Icons.info_outline_rounded, title: '没有找到可用的存储位置'),
            ],
          ),
        ],
      );

  Widget _dirList(double g) {
    if (_error != null) {
      return Padding(
        padding: EdgeInsets.all(g),
        child: Text(_error!, style: TypeScale.body.copyWith(color: Palette.text2)),
      );
    }
    if (_dirs.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(g),
        child: Text(_videosHere > 0 ? '没有子文件夹，这里有 $_videosHere 个视频。' : '这个文件夹是空的。',
            style: TypeScale.body.copyWith(color: Palette.text2)),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(g, 4, g, 24),
      children: [
        GroupedList(children: [
          for (final d in _dirs)
            FutureBuilder<_DirInfo>(
              future: _infoOf(d.path),
              builder: (context, snap) {
                final info = snap.data;
                final parts = [
                  if (info != null && info.folders > 0) '${info.folders} 个文件夹',
                  if (info != null && info.videos > 0) '${info.videos} 个视频',
                ];
                return SettingRow(
                  icon: info != null && info.videos > 0 ? Icons.movie_outlined : Icons.folder_outlined,
                  title: p.basename(d.path),
                  subtitle: info == null ? ' ' : (parts.isEmpty ? '空' : parts.join(' · ')),
                  onTap: () => _open(d.path),
                );
              },
            ),
        ]),
      ],
    );
  }

  Widget _bottomBar(double g, double bottomPad) {
    final name = p.basename(_path!).isEmpty ? _root?.label ?? _path! : p.basename(_path!);
    return Container(
      padding: EdgeInsets.fromLTRB(g, 14, g, 14 + bottomPad),
      decoration: const BoxDecoration(
        color: Palette.surface1,
        border: Border(top: BorderSide(color: Palette.hairline)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('添加「$name」', maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.headline),
            const SizedBox(height: 2),
            Text(
              _videosHere > 0 ? '包含子文件夹 · 这一层有 $_videosHere 个视频' : '会扫描所有子文件夹',
              style: TypeScale.caption,
            ),
          ]),
        ),
        const SizedBox(width: 16),
        PillButton(label: '添加', icon: Icons.add_rounded, onPressed: () => Navigator.pop(context, _path)),
      ]),
    );
  }
}
