import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/sources/local_source.dart';
import '../../data/sources/media_source.dart';
import '../../data/sources/network_config.dart';
import '../../data/sources/webdav_source.dart' show NetworkSourceException;
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
      if (Directory(drive).existsSync()) {
        out.add(StorageRoot(drive, '本地磁盘（${String.fromCharCode(c)}:）', Icons.storage_rounded));
      }
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

/// 文件夹浏览器的数据来源：本地磁盘或 NAS。
abstract class BrowseBackend {
  /// 第一屏的存储位置（本地：内部存储 / SD 卡；SMB：共享文件夹；WebDAV：服务根目录）。
  Future<List<StorageRoot>> roots();
  Future<List<SourceEntry>> list(String path);
  String get rootsHeader;

  /// 本地才逐个统计子文件夹 / 视频数（网络上太慢）。
  bool get countChildren;
  bool get allowSystemPicker;

  String basename(String path);
  String dirname(String path);
  bool equals(String a, String b);
  bool isWithin(String root, String path);
  List<String> relativeSegments(String root, String path);
}

class LocalBackend implements BrowseBackend {
  const LocalBackend();
  static final _src = LocalSource('/');

  @override
  Future<List<StorageRoot>> roots() => storageRoots();
  @override
  Future<List<SourceEntry>> list(String path) async {
    try {
      Directory(path).listSync(); // 先同步探测一次，拿到真实的权限错误
    } on FileSystemException catch (e) {
      throw NetworkSourceException('无法打开这个文件夹（${e.osError?.message ?? e.message}）');
    }
    return _src.list(path);
  }

  @override
  String get rootsHeader => '存储位置';
  @override
  bool get countChildren => true;
  @override
  bool get allowSystemPicker => true;
  @override
  String basename(String path) => p.basename(path);
  @override
  String dirname(String path) => p.dirname(path);
  @override
  bool equals(String a, String b) => p.equals(a, b);
  @override
  bool isWithin(String root, String path) => p.isWithin(root, path);
  @override
  List<String> relativeSegments(String root, String path) =>
      p.split(p.relative(path, from: root)).where((s) => s != '.').toList();
}

/// NAS：路径是 mvsrc://… 地址，用 "/" 拼接。
class RemoteBackend implements BrowseBackend {
  RemoteBackend(this.source, this.config);
  final MediaSource source;
  final NetworkConfig config;

  @override
  Future<List<StorageRoot>> roots() async {
    if (config.kind == NetworkKind.smb) {
      final shares = await source.list(source.rootPath);
      return [for (final s in shares) StorageRoot(s.path, s.name, Icons.folder_shared_outlined)];
    }
    return [StorageRoot(source.rootPath, config.display, Icons.cloud_outlined)];
  }

  @override
  Future<List<SourceEntry>> list(String path) => source.list(path);
  @override
  String get rootsHeader => config.kind == NetworkKind.smb ? '${config.host} 上的共享文件夹' : '服务器';
  @override
  bool get countChildren => false;
  @override
  bool get allowSystemPicker => false;

  static String _trim(String s) => s.length > 1 && s.endsWith('/') ? s.substring(0, s.length - 1) : s;
  @override
  String basename(String path) => Uri.decodeComponent(_trim(path).split('/').last);
  @override
  String dirname(String path) {
    final t = _trim(path);
    return t.substring(0, t.lastIndexOf('/'));
  }

  @override
  bool equals(String a, String b) => _trim(a) == _trim(b);
  @override
  bool isWithin(String root, String path) => _trim(path).startsWith('${_trim(root)}/');
  @override
  List<String> relativeSegments(String root, String path) =>
      _trim(path).substring(_trim(root).length).split('/').where((s) => s.isNotEmpty).toList();
}

/// 自建的文件夹浏览器，替代系统选择器。返回所选文件夹的路径。
class FolderBrowser extends StatefulWidget {
  const FolderBrowser({super.key, this.initialPath, this.backend = const LocalBackend(), this.title = '选择影视文件夹'});
  final String? initialPath;
  final BrowseBackend backend;
  final String title;

  static Future<String?> pick(
    BuildContext context, {
    String? initialPath,
    BrowseBackend backend = const LocalBackend(),
    String title = '选择影视文件夹',
  }) => Navigator.of(context).push<String>(
    FadeRoute(
      builder: (_) => FolderBrowser(initialPath: initialPath, backend: backend, title: title),
    ),
  );

  @override
  State<FolderBrowser> createState() => _FolderBrowserState();
}

class _DirInfo {
  const _DirInfo(this.folders, this.videos);
  final int folders;
  final int videos;
}

class _FolderBrowserState extends State<FolderBrowser> {
  BrowseBackend get _b => widget.backend;
  List<StorageRoot> _roots = const [];
  bool _loading = true;
  String? _path; // null = 存储位置列表
  List<SourceEntry> _dirs = const [];
  int _videosHere = 0;
  String? _error;
  final _info = <String, Future<_DirInfo>>{};
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _b.roots().then(
      (r) {
        if (!mounted) return;
        setState(() {
          _roots = r;
          _loading = false;
        });
        if (widget.initialPath != null) _open(widget.initialPath);
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = '$e';
          });
        }
      },
    );
  }

  Future<void> _open(String? path) async {
    final req = ++_req;
    if (path == null) {
      setState(() {
        _path = null;
        _dirs = const [];
        _error = null;
      });
      return;
    }
    setState(() {
      _path = path;
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _b.list(path);
      if (!mounted || req != _req) return;
      final dirs = entries.where((e) => e.isDir && !isIgnoredDir(e.name)).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      setState(() {
        _dirs = dirs;
        _videosHere = entries.where((e) => !e.isDir && isVideoFile(e.name)).length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || req != _req) return;
      setState(() {
        _dirs = const [];
        _loading = false;
        _error = '$e';
      });
    }
  }

  StorageRoot? get _root =>
      _path == null ? null : _roots.where((r) => _b.equals(r.path, _path!) || _b.isWithin(r.path, _path!)).firstOrNull;

  void _up() {
    final root = _root;
    if (_path == null) return Navigator.pop(context);
    if (root == null || _b.equals(root.path, _path!)) {
      _open(null);
      return;
    }
    _open(_b.dirname(_path!));
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
      for (final seg in _b.relativeSegments(root.path, _path!)) {
        acc = _b is LocalBackend ? p.join(acc, seg) : '$acc/$seg';
        crumbs.add((Uri.decodeComponent(seg), acc));
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题栏
                Padding(
                  padding: EdgeInsets.fromLTRB(g - 8, pad.top + 12, g - 8, 0),
                  child: Row(
                    children: [
                      RoundIconButton(
                        icon: _path == null ? Icons.close_rounded : Icons.arrow_back_rounded,
                        tooltip: _path == null ? '关闭' : '上一级',
                        onPressed: _up,
                      ),
                      const Spacer(),
                      if (_b.allowSystemPicker)
                        Pressable(
                          onTap: _systemPicker,
                          radius: 18,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Text('使用系统选择器', style: TypeScale.callout.copyWith(color: Palette.text2)),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(g, 20, g, 6),
                  child: Text(
                    _path == null
                        ? widget.title
                        : _b.equals(root?.path ?? '', _path!)
                        ? root!.label
                        : _b.basename(_path!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.largeTitle,
                  ),
                ),
                // 路径面包屑
                SizedBox(
                  height: 36,
                  child: _path == null
                      ? Padding(
                          padding: EdgeInsets.symmetric(horizontal: g),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '选一个存放电影或剧集的文件夹，子文件夹会一起扫描。',
                              style: TypeScale.callout.copyWith(color: Palette.text2),
                            ),
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
                                  child: Text(
                                    c.$1,
                                    style: TypeScale.callout.copyWith(
                                      color: last ? Palette.text : Palette.text2,
                                      fontWeight: last ? FontWeight.w600 : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _loading
                      ? const Center(child: Spinner(size: 24))
                      : _path == null
                      ? _rootList(g)
                      : _dirList(g),
                ),
                if (_path != null) _bottomBar(g, pad.bottom),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rootList(double g) => ListView(
    padding: EdgeInsets.fromLTRB(g, 8, g, 32),
    children: [
      if (_error != null)
        Text(_error!, style: TypeScale.body.copyWith(color: Palette.danger))
      else
        GroupedList(
          header: _b.rootsHeader,
          children: [
            for (final r in _roots)
              SettingRow(
                icon: r.icon,
                title: r.label,
                subtitle: _b is LocalBackend ? r.path : null,
                onTap: () => _open(r.path),
              ),
            if (_roots.isEmpty) const SettingRow(icon: Icons.info_outline_rounded, title: '没有找到可用的存储位置'),
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
        child: Text(
          _videosHere > 0 ? '没有子文件夹，这里有 $_videosHere 个视频。' : '这个文件夹是空的。',
          style: TypeScale.body.copyWith(color: Palette.text2),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(g, 4, g, 24),
      children: [
        GroupedList(
          children: [
            for (final d in _dirs)
              if (!_b.countChildren)
                SettingRow(icon: Icons.folder_outlined, title: d.name, onTap: () => _open(d.path))
              else
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
                      title: d.name,
                      subtitle: info == null ? ' ' : (parts.isEmpty ? '空' : parts.join(' · ')),
                      onTap: () => _open(d.path),
                    );
                  },
                ),
          ],
        ),
      ],
    );
  }

  Widget _bottomBar(double g, double bottomPad) {
    final name = _b.equals(_root?.path ?? '', _path!) ? _root?.label ?? _path! : _b.basename(_path!);
    return Container(
      padding: EdgeInsets.fromLTRB(g, 14, g, 14 + bottomPad),
      decoration: const BoxDecoration(
        color: Palette.surface1,
        border: Border(top: BorderSide(color: Palette.hairline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('添加「$name」', maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.headline),
                const SizedBox(height: 2),
                Text(_videosHere > 0 ? '包含子文件夹 · 这一层有 $_videosHere 个视频' : '会扫描所有子文件夹', style: TypeScale.caption),
              ],
            ),
          ),
          const SizedBox(width: 16),
          PillButton(label: '添加', icon: Icons.add_rounded, onPressed: () => Navigator.pop(context, _path)),
        ],
      ),
    );
  }
}
