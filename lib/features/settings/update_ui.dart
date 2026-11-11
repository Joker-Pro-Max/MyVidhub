import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/update_controller.dart';
import '../../services/updater.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';

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
    if (r == null) return const SizedBox.shrink();
    final busy = s.status == UpdateStatus.downloading;

    return AlertDialog(
      title: Text('MyVidhub ${r.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 380),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('当前 ${s.current?.version ?? '-'}  ·  ${_size(r.assetSize)}', style: TypeScale.caption),
          const SizedBox(height: 16),
          if (r.notes.isNotEmpty)
            Flexible(
              child: SingleChildScrollView(
                child: Text(r.notes, style: TypeScale.body.copyWith(color: Palette.text2, fontSize: 14)),
              ),
            ),
          if (busy || s.status == UpdateStatus.ready) ...[
            const SizedBox(height: 20),
            ProgressHairline(value: s.progress, height: 4),
            const SizedBox(height: 8),
            Text(s.status == UpdateStatus.ready ? '下载完成' : '正在下载 ${(s.progress * 100).round()}%',
                style: TypeScale.caption),
          ],
          if (s.message != null) ...[
            const SizedBox(height: 12),
            Text(s.message!,
                style: TypeScale.caption.copyWith(
                    color: s.status == UpdateStatus.error ? Palette.danger : Palette.text)),
          ],
        ]),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      actions: [
        PillButton(
          label: '稍后',
          primary: false,
          compact: true,
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        PillButton(
          label: switch (s.status) {
            UpdateStatus.downloading => '下载中…',
            UpdateStatus.ready => '安装',
            UpdateStatus.error => '重试',
            _ => Updater.supported ? '更新' : '仅安卓可自动更新',
          },
          compact: true,
          onPressed: busy || !Updater.supported ? null : ctrl.downloadAndInstall,
        ),
      ],
    );
  }
}

/// 设置页里的"版本与更新"分组。
class UpdateSection extends ConsumerWidget {
  const UpdateSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(updateProvider);
    final ctrl = ref.read(updateProvider.notifier);

    final (String statusText, Widget? trailing) = switch (s.status) {
      UpdateStatus.checking => ('正在检查…', const Spinner()),
      UpdateStatus.upToDate => ('已是最新版本', const Icon(Icons.check_rounded, color: Palette.text2)),
      UpdateStatus.available => (
          '有新版本 ${s.release!.version}',
          PillButton(label: '查看', compact: true, onPressed: () => UpdateDialog.show(context)),
        ),
      UpdateStatus.downloading => (
          '正在下载 ${(s.progress * 100).round()}%',
          SizedBox(width: 64, child: ProgressHairline(value: s.progress)),
        ),
      UpdateStatus.ready => ('新版本已下载', PillButton(label: '安装', compact: true, onPressed: ctrl.install)),
      UpdateStatus.error => (s.message ?? '检查失败', null),
      UpdateStatus.idle => ('轻点检查', null),
    };

    return GroupedList(
      header: '版本与更新',
      footer: 'PolyForm Noncommercial 1.0.0 · 仅限个人非商业使用 · github.com/${UpdateConfig.repo}',
      children: [
        SettingRow(
          icon: Icons.info_outline_rounded,
          title: '当前版本',
          trailing: Text(s.current?.toString() ?? '-', style: TypeScale.callout.copyWith(color: Palette.text2)),
        ),
        SettingRow(
          icon: Icons.system_update_alt_rounded,
          title: '检查更新',
          subtitle: statusText,
          trailing: trailing,
          onTap: s.status == UpdateStatus.available ? () => UpdateDialog.show(context) : () => ctrl.check(),
        ),
      ],
    );
  }
}
