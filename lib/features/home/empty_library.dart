import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/add_source.dart';

class EmptyLibrary extends ConsumerWidget {
  const EmptyLibrary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.video_library_outlined, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 20),
            Text('还没有媒体库', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              '添加存放电影、剧集的文件夹。MyVidhub 会读取其中的 NFO 元数据和海报图片，'
              '兼容 Kodi、Jellyfin、Emby、tinyMediaManager 整理的目录。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => addLocalFolder(context, ref),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('添加媒体文件夹'),
              style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
            ),
          ]),
        ),
      ),
    );
  }
}
