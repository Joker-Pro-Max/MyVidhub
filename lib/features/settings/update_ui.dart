import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/update_controller.dart';
import '../../services/updater.dart';

String _size(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

/// 新版本对话框：更新说明 + 下载进度 + 安装。
class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) =>
      showDialog(context: context, barrierDismissible: false, builder: (_) => const UpdateDialog());

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateProvider);
    final ctrl = ref.read(updateProvider.notifier);
    final r = s.release;
    final theme = Theme.of(context);
    if (r == null) return const SizedBox.shrink();
    final busy = s.status == UpdateStatus.downloading;

    return AlertDialog(
      title: Text('发现新版本 ${r.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 360),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('当前 ${s.current?.version ?? '-'} → ${r.version}（${r.build}） · ${_size(r.assetSize)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (r.notes.isNotEmpty)
            Flexible(child: SingleChildScrollView(child: Text(r.notes, style: theme.textTheme.bodyMedium))),
          if (busy || s.status == UpdateStatus.ready) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: s.progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
            const SizedBox(height: 6),
            Text(s.status == UpdateStatus.ready ? '下载完成' : '正在下载 ${(s.progress * 100).round()}%',
                style: theme.textTheme.bodySmall),
          ],
          if (s.message != null) ...[
            const SizedBox(height: 12),
            Text(s.message!,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: s.status == UpdateStatus.error ? theme.colorScheme.error : theme.colorScheme.primary)),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: busy || !Updater.supported ? null : ctrl.downloadAndInstall,
          child: Text(switch (s.status) {
            UpdateStatus.downloading => '下载中…',
            UpdateStatus.ready => '安装',
            UpdateStatus.error => '重试',
            _ => Updater.supported ? '立即更新' : '仅安卓可自动更新',
          }),
        ),
      ],
    );
  }
}

/// 设置页里的"版本与更新"卡片。
class UpdateSection extends ConsumerWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateProvider);
    final ctrl = ref.read(updateProvider.notifier);
    final theme = Theme.of(context);

    final (statusText, trailing) = switch (s.status) {
      UpdateStatus.checking => ('正在检查…', const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))),
      UpdateStatus.upToDate => ('已是最新版本', const Icon(Icons.check_circle_outline_rounded)),
      UpdateStatus.available => ('发现新版本 ${s.release!.version}', FilledButton(onPressed: () => UpdateDialog.show(context), child: const Text('查看'))),
      UpdateStatus.downloading => ('正在下载 ${(s.progress * 100).round()}%', SizedBox(width: 60, child: LinearProgressIndicator(value: s.progress))),
      UpdateStatus.ready => ('新版本已下载', FilledButton(onPressed: ctrl.install, child: const Text('安装'))),
      UpdateStatus.error => (s.message ?? '检查失败', const Icon(Icons.error_outline_rounded)),
      UpdateStatus.idle => ('点击检查', const Icon(Icons.chevron_right_rounded)),
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('当前版本'),
          subtitle: Text(s.current?.toString() ?? '-'),
        ),
        ListTile(
          leading: const Icon(Icons.system_update_rounded),
          title: const Text('检查更新'),
          subtitle: Text(statusText,
              style: s.status == UpdateStatus.error ? TextStyle(color: theme.colorScheme.error) : null),
          trailing: trailing,
          onTap: s.status == UpdateStatus.available
              ? () => UpdateDialog.show(context)
              : () => ctrl.check(),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_rounded),
          title: const Text('许可'),
          subtitle: Text('PolyForm Noncommercial 1.0.0 · 仅限个人非商业使用，禁止商业化\ngithub.com/${UpdateConfig.repo}'),
          isThreeLine: true,
        ),
      ]),
    );
  }
}
