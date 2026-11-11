import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_shell.dart';
import '../../app/providers.dart';
import '../../data/db/models.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../home/home_page.dart';
import 'add_source.dart';
import 'update_ui.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final scan = ref.watch(scanProvider);
    final db = ref.watch(dbProvider);
    ref.watch(libraryRevisionProvider);
    final insets = ShellInsets.of(context);
    final g = FormFactor.of(context).gutter;

    return ListView(
      padding: EdgeInsets.fromLTRB(g, insets.top + 8, g, insets.bottom),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('设置', style: TypeScale.largeTitle),
              const SizedBox(height: 28),
              if (scan.running) ...[
                const ScanBanner(padding: EdgeInsets.symmetric(horizontal: 4)),
                const SizedBox(height: 20),
              ],
              GroupedList(
                header: '媒体库',
                footer: !scan.running ? scan.lastMessage : null,
                children: [
                  for (final s in sources) _SourceRow(source: s, scanning: scan.sourceId == s.id),
                  SettingRow(
                    icon: Icons.create_new_folder_outlined,
                    title: '添加文件夹',
                    subtitle: '本地磁盘、U 盘、SD 卡',
                    onTap: () => addLocalFolder(context, ref),
                  ),
                  if (sources.isNotEmpty)
                    SettingRow(
                      icon: Icons.refresh_rounded,
                      title: '全部重新扫描',
                      enabled: !scan.running,
                      onTap: () => ref.read(scanProvider.notifier).scanAll(),
                    ),
                  const SettingRow(
                    icon: Icons.lan_outlined,
                    title: '添加 SMB / WebDAV',
                    subtitle: '即将支持',
                    enabled: false,
                  ),
                ],
              ),
              const SizedBox(height: 32),
              const UpdateSection(),
              const SizedBox(height: 32),
              GroupedList(
                header: '关于',
                children: [
                  SettingRow(
                    icon: Icons.video_library_outlined,
                    title: '片库',
                    subtitle: '电影 ${db.count(MediaKind.movie)} 部 · 剧集 ${db.count(MediaKind.show)} 部',
                  ),
                  const SettingRow(
                    icon: Icons.description_outlined,
                    title: '支持的元数据',
                    subtitle: 'Kodi / Jellyfin / Emby NFO，poster、fanart、clearlogo、季海报、集缩略图',
                  ),
                ],
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends ConsumerWidget {
  const _SourceRow({required this.source, required this.scanning});
  final SourceRow source;
  final bool scanning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final last = source.lastScanAt;
    return SettingRow(
      icon: Icons.folder_outlined,
      title: source.name,
      subtitle: '${source.root}\n${source.itemCount} 个条目${last != null ? ' · 上次扫描 ${_fmt(last)}' : ''}',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (scanning)
          const Padding(padding: EdgeInsets.all(9), child: Spinner())
        else
          RoundIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '重新扫描',
            size: 36,
            onPressed: () => ref.read(scanProvider.notifier).scan(source.id),
          ),
        const SizedBox(width: 8),
        RoundIconButton(
          icon: Icons.remove_rounded,
          tooltip: '移除',
          size: 36,
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
        content: const Text('只会从片库里移除，不会删除磁盘上的任何文件。'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          PillButton(label: '取消', primary: false, compact: true, onPressed: () => Navigator.pop(c, false)),
          PillButton(label: '移除', compact: true, onPressed: () => Navigator.pop(c, true)),
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
