import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app_shell.dart';
import '../../app/app_settings.dart';
import '../../app/auto_scrape.dart';
import '../../app/providers.dart';
import '../../app/translate_controller.dart';
import '../../data/db/models.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../data/sources/network_config.dart';
import '../../services/source_registry.dart';
import '../organize/organize_page.dart';
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
    final settings = ref.watch(appSettingsProvider);
    final auto = ref.watch(autoScrapeProvider);
    final tr = ref.watch(translateProvider);
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
                  '支持 Kodi、Jellyfin、Emby、tinyMediaManager 整理的目录：读取 NFO、海报、剧照、季海报和集缩略图。扫描只读取；「…」里的「刮削并整理」会移动文件，可撤销。',
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

              GroupedList(
                header: '刮削',
                footer: [
                  if (auto.running) '正在自动刮削 ${auto.done + 1} / ${auto.total}${auto.current != null ? ' · ${auto.current}' : ''}',
                  if (!auto.running && auto.message != null) auto.message!,
                  settings.autoScrape
                      ? '自动刮削开启时，扫描后会用 TMDB 为没有资料的电影补全 NFO、海报和背景图（视频不移动，可在「刮削并整理」页撤销）。番号片请关闭自动刮削后手动选择 JavBus / R18.dev。'
                      : '自动刮削已关闭：在「编辑信息」「刮削并整理」里自己选择 JavBus、R18.dev 或 TMDB。',
                  'TMDB API Key（v3）可在 themoviedb.org › 设置 › API 免费申请。',
                ].join('\n'),
                children: [
                  SettingRow(
                    icon: Icons.auto_awesome_rounded,
                    title: '自动刮削',
                    subtitle: settings.autoScrape ? '使用在线影视数据（TMDB）' : '关闭 · 刮削时自己选择刮削源',
                    trailing: LightSwitch(
                      value: settings.autoScrape,
                      onChanged: (v) {
                        ref.read(appSettingsProvider.notifier).setAutoScrape(v);
                        if (v) {
                          for (final s in sources) {
                            ref.read(autoScrapeProvider.notifier).afterScan(s.id);
                          }
                        }
                      },
                    ),
                  ),
                  SettingRow(
                    icon: Icons.key_rounded,
                    title: 'TMDB API Key',
                    subtitle: (db.setting(tmdbKeySetting) ?? '').trim().isNotEmpty
                        ? '已设置（自己的 Key）'
                        : builtInTmdbKey.isNotEmpty
                            ? '使用内置 Key · 也可以填自己的'
                            : '未设置',
                    onTap: () => _editTmdbKey(context, ref),
                  ),
                  SettingRow(
                    icon: Icons.blur_on_rounded,
                    title: 'AV 模糊显示',
                    subtitle: '资料来自 JavBus / R18.dev 的影片自动标记为 AV，海报和剧照模糊显示',
                    trailing: LightSwitch(
                      value: settings.blurAv,
                      onChanged: (v) => ref.read(appSettingsProvider.notifier).setBlurAv(v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              GroupedList(
                header: '翻译',
                footer: [
                  if (tr.running) '正在翻译 ${tr.done} / ${tr.total}',
                  if (!tr.running && tr.message != null) tr.message!,
                  '把非中文（日文、英文、韩文等）的片名和演员名翻译成中文，番号不翻译。译文保存在本机片库里，不修改 NFO；'
                      '片名原文保留在「原名」，搜索原文照样能找到。使用 Google 翻译，片名和演员名会发送给 Google，需要能访问 Google。',
                ].join('\n'),
                children: [
                  SettingRow(
                    icon: Icons.translate_rounded,
                    title: '翻译为中文',
                    subtitle: tr.running ? '正在翻译…' : '${ref.read(translateProvider.notifier).pending()} 条待翻译',
                    trailing: tr.running
                        ? PillButton(
                            label: '停止',
                            primary: false,
                            compact: true,
                            onPressed: () => ref.read(translateProvider.notifier).cancel(),
                          )
                        : PillButton(
                            label: '翻译',
                            compact: true,
                            onPressed: () => ref.read(translateProvider.notifier).run(),
                          ),
                  ),
                  if (db.translationCount() > 0)
                    SettingRow(
                      icon: Icons.undo_rounded,
                      title: '恢复原文',
                      subtitle: '已翻译 ${db.translationCount()} 条 · 删除译文并重新扫描',
                      enabled: !tr.running,
                      onTap: () => ref.read(translateProvider.notifier).restore(),
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

Future<void> _editTmdbKey(BuildContext context, WidgetRef ref) async {
  final db = ref.read(dbProvider);
  final controller = TextEditingController(text: db.setting(tmdbKeySetting) ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('TMDB API Key'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(builtInTmdbKey.isNotEmpty
            ? 'App 已内置一个 Key，留空即可使用。也可以填自己的 v3 API Key（只保存在这台设备上）。'
            : '填写 v3 的 API Key（32 位字母数字）。只保存在这台设备上。'),
        const SizedBox(height: 14),
        TextField(
          controller: controller,
          autocorrect: false,
          enableSuggestions: false,
          style: TypeScale.callout.copyWith(fontSize: 15),
          decoration: const InputDecoration(hintText: '例如 1a2b3c…'),
        ),
      ]),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        PillButton(label: '取消', primary: false, compact: true, onPressed: () => Navigator.pop(c)),
        PillButton(label: '保存', compact: true, onPressed: () => Navigator.pop(c, controller.text.trim())),
      ],
    ),
  );
  if (result == null) return;
  db.setSetting(tmdbKeySetting, result.isEmpty ? null : result);
  ref.read(libraryRevisionProvider.notifier).bump();
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

enum _FolderAction { organize, rescan, restore, remove }

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
            _FolderAction.organize => OrganizePage.open(context, source),
            _FolderAction.rescan => ref.read(scanProvider.notifier).scan(source.id),
            _FolderAction.restore => () {
                ref.read(dbProvider).restoreExcluded(source.id);
                ref.read(scanProvider.notifier).scan(source.id);
              }(),
            _FolderAction.remove => _confirmDelete(context, ref),
          },
          itemBuilder: (_) => [
            if (!source.isNetwork)
              PopupMenuItem(
                value: _FolderAction.organize,
                enabled: !scanning,
                child: const _MenuRow(icon: Icons.auto_fix_high_rounded, label: '刮削并整理…'),
              ),
            PopupMenuItem(
              value: _FolderAction.rescan,
              enabled: !scanning && !queued,
              child: const _MenuRow(icon: Icons.refresh_rounded, label: '重新扫描'),
            ),
            if (ref.read(dbProvider).excludedCount(source.id) case final n when n > 0)
              PopupMenuItem(
                value: _FolderAction.restore,
                enabled: !scanning,
                child: _MenuRow(icon: Icons.restore_rounded, label: '恢复已移除的影片（$n）'),
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
