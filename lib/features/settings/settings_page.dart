import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../home/home_page.dart';
import 'add_source.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final scan = ref.watch(scanProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Text('设置', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        Row(children: [
          Text('媒体库文件夹', style: theme.textTheme.titleMedium),
          const Spacer(),
          if (sources.isNotEmpty)
            TextButton.icon(
              onPressed: scan.running ? null : () => ref.read(scanProvider.notifier).scanAll(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('全部重新扫描'),
            ),
        ]),
        const SizedBox(height: 8),
        if (scan.running) const ScanBanner(padding: EdgeInsets.only(bottom: 8)),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final s in sources) _SourceTile(source: s, scanning: scan.sourceId == s.id),
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('添加文件夹'),
              subtitle: const Text('本地磁盘、U 盘、SD 卡'),
              onTap: () => addLocalFolder(context, ref),
            ),
            ListTile(
              enabled: false,
              leading: const Icon(Icons.lan_outlined),
              title: const Text('添加 SMB / WebDAV'),
              subtitle: const Text('即将支持（M4）'),
            ),
          ]),
        ),
        if (scan.lastMessage != null && !scan.running) ...[
          const SizedBox(height: 10),
          Text(scan.lastMessage!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        ],
        const SizedBox(height: 28),
        Text('关于', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('MyVidhub'),
              subtitle: Text('M1 · 电影 ${ref.watch(dbProvider).count(MediaKind.movie)} 部 · '
                  '剧集 ${ref.watch(dbProvider).count(MediaKind.show)} 部'),
            ),
            const ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text('支持的元数据'),
              subtitle: Text('Kodi / Jellyfin / Emby NFO，poster / fanart / clearlogo / 季海报 / 集缩略图'),
            ),
          ]),
        ),
      ],
    );
  }
}

class _SourceTile extends ConsumerWidget {
  const _SourceTile({required this.source, required this.scanning});
  final SourceRow source;
  final bool scanning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = source.lastScanAt;
    final subtitle = [
      source.root,
      '${source.itemCount} 个条目${last != null ? ' · 上次扫描 ${_fmt(last)}' : ''}',
    ].join('\n');
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(source.name),
      subtitle: Text(subtitle),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        scanning
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              )
            : IconButton(
                tooltip: '重新扫描',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.read(scanProvider.notifier).scan(source.id),
              ),
        IconButton(
          tooltip: '移除',
          icon: const Icon(Icons.delete_outline),
          onPressed: scanning ? null : () => _confirmDelete(context, ref),
        ),
      ]),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('移除「${source.name}」？'),
        content: const Text('只会从媒体库中移除索引，不会删除磁盘上的任何文件。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('移除')),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(dbProvider).deleteSource(source.id);
    ref.read(libraryRevisionProvider.notifier).bump();
  }

  static String _fmt(DateTime d) =>
      '${d.month}-${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
