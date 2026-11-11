import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_shell.dart';
import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../data/sources/network_config.dart';
import '../../services/source_registry.dart';
import 'add_network_source.dart';
import 'add_source.dart';
import 'folder_browser.dart';
import 'update_ui.dart';

final storageRootsProvider = FutureProvider<List<StorageRoot>>((ref) => storageRoots());

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final scan = ref.watch(scanProvider);
    final db = ref.watch(dbProvider);
    ref.watch(libraryRevisionProvider);
    final roots = ref.watch(storageRootsProvider).value ?? const <StorageRoot>[];
    final insets = ShellInsets.of(context);
    final g = FormFactor.of(context).gutter;

    final movies = db.count(MediaKind.movie);
    final shows = db.count(MediaKind.show);
    final episodes = db.episodeTotal();
    final summary = sources.isEmpty
        ? '还没有添加任何文件夹'
        : [
            '$movies 部电影',
            '$shows 部剧集',
            if (episodes > 0) '共 $episodes 集',
            '来自 ${sources.length} 个文件夹',
          ].join(' · ');

    return ListView(
      padding: EdgeInsets.fromLTRB(g, insets.top + 8, g, insets.bottom),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('设置', style: TypeScale.largeTitle),
              const SizedBox(height: 6),
              Text(summary, style: TypeScale.callout.copyWith(color: Palette.text2)),
              const SizedBox(height: 32),

              GroupedList(
                header: '媒体文件夹',
                headerAction: sources.isEmpty
                    ? null
                    : _HeaderAction(
                        label: '全部重新扫描',
                        onTap: scan.running ? null : () => ref.read(scanProvider.notifier).scanAll(),
                      ),
                footer: [
                  if (!scan.running && scan.lastMessage != null) scan.lastMessage!,
                  '支持 Kodi、Jellyfin、Emby、tinyMediaManager 整理的目录：读取 NFO、海报、剧照、季海报和集缩略图。只读取，不会改动文件。',
                ].join('\n'),
                children: [
                  for (final s in sources.where((s) => !s.isNetwork))
                    _FolderRow(
                      source: s,
                      roots: roots,
                      scanning: scan.sourceId == s.id,
                      queued: scan.queue.contains(s.id),
                      found: scan.sourceId == s.id ? scan.found : null,
                    ),
                  SettingRow(
                    icon: Icons.add_rounded,
                    leading: const IconTile(icon: Icons.add_rounded, size: 44, filled: true),
                    title: '添加文件夹',
                    subtitle: '内部存储、SD 卡或 U 盘里的影视文件夹',
                    onTap: () => addLocalFolder(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              GroupedList(
                header: '网络存储',
                footer: '支持 SMB 和 WebDAV。海报和剧照在浏览时才下载，并缓存在本机。',
                children: [
                  for (final s in sources.where((s) => s.isNetwork))
                    _FolderRow(
                      source: s,
                      roots: roots,
                      scanning: scan.sourceId == s.id,
                      queued: scan.queue.contains(s.id),
                      found: scan.sourceId == s.id ? scan.found : null,
                    ),
                  SettingRow(
                    icon: Icons.lan_outlined,
                    leading: const IconTile(icon: Icons.add_rounded, size: 44, filled: true),
                    title: '添加 SMB / WebDAV',
                    subtitle: '群晖、威联通、Windows 共享文件夹等',
                    onTap: () => AddNetworkSourcePage.open(context),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              const UpdateSection(),
            ]),
          ),
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        radius: 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(label, style: TypeScale.caption.copyWith(color: Palette.text, fontWeight: FontWeight.w600)),
        ),
      );
}

enum _FolderAction { rescan, remove }

class _FolderRow extends ConsumerWidget {
  const _FolderRow({
    required this.source,
    required this.roots,
    required this.scanning,
    required this.queued,
    this.found,
  });

  final SourceRow source;
  final List<StorageRoot> roots;
  final bool scanning;
  final bool queued;
  final int? found;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = source.lastScanAt;
    final status = scanning
        ? '正在扫描 · 已发现 ${found ?? 0} 个'
        : queued
            ? '等待扫描'
            : [
                '${source.itemCount} 个条目',
                last != null ? '${relativeTime(last)}更新' : '尚未扫描',
              ].join(' · ');
    final root = source.isNetwork
        ? null
        : roots.where((r) => p.equals(r.path, source.root) || p.isWithin(r.path, source.root)).firstOrNull;
    final icon = source.isNetwork
        ? Icons.dns_rounded
        : root?.icon == Icons.sd_card_outlined
            ? Icons.sd_card_outlined
            : Icons.folder_rounded;
    final location = source.isNetwork && source.config != null
        ? '${source.type.toUpperCase()} · ${NetworkConfig.decode(source.config!).host}'
            '${source.root.split('/').where((x) => x.isNotEmpty).map((x) => ' › $x').join()}'
        : friendlyPath(source.root, roots);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(children: [
        IconTile(icon: icon, size: 44, color: Palette.text),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TypeScale.headline),
            const SizedBox(height: 3),
            Text(
              location,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.caption.copyWith(color: Palette.text3),
            ),
            const SizedBox(height: 6),
            Row(children: [
              if (scanning) ...[const Spinner(size: 12), const SizedBox(width: 8)],
              Flexible(
                child: Text(status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TypeScale.caption.copyWith(color: scanning ? Palette.text : Palette.text2)),
              ),
            ]),
          ]),
        ),
        PopupMenuButton<_FolderAction>(
          tooltip: '更多操作',
          offset: const Offset(0, 40),
          onSelected: (a) => switch (a) {
            _FolderAction.rescan => ref.read(scanProvider.notifier).scan(source.id),
            _FolderAction.remove => _confirmDelete(context, ref),
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: _FolderAction.rescan,
              enabled: !scanning && !queued,
              child: const _MenuRow(icon: Icons.refresh_rounded, label: '重新扫描'),
            ),
            PopupMenuItem(
              value: _FolderAction.remove,
              enabled: !scanning,
              child: const _MenuRow(icon: Icons.remove_circle_outline_rounded, label: '从片库移除', danger: true),
            ),
          ],
          child: const SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.more_horiz_rounded, color: Palette.text2),
          ),
        ),
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('移除「${source.name}」？'),
        content: const Text('这个文件夹里的影片会从片库中移除，磁盘上的文件不受影响。之后可以随时重新添加。'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          PillButton(label: '取消', primary: false, compact: true, onPressed: () => Navigator.pop(c, false)),
          PillButton(label: '移除', compact: true, onPressed: () => Navigator.pop(c, true)),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(dbProvider).deleteSource(source.id);
    SourceRegistry.instance.forget(source.id);
    ref.read(libraryRevisionProvider.notifier).bump();
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.danger = false});
  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: danger ? Palette.danger : Palette.text2),
        const SizedBox(width: 12),
        Text(label, style: TypeScale.callout.copyWith(fontSize: 15, color: danger ? Palette.danger : Palette.text)),
      ]);
}
