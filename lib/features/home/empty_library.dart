import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../settings/add_source.dart';

class EmptyLibrary extends ConsumerWidget {
  const EmptyLibrary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = FormFactor.of(context).gutter;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: EdgeInsets.all(g),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('把你的片库放进来', style: TypeScale.largeTitle),
            const SizedBox(height: 14),
            Text(
              '选择存放电影和剧集的文件夹。ReelNest 会读取里面的 NFO 和海报，'
              '用 Kodi、Jellyfin、Emby 或 tinyMediaManager 整理过的目录可以直接识别。',
              style: TypeScale.body.copyWith(color: Palette.text2),
            ),
            const SizedBox(height: 28),
            PillButton(
              label: '添加媒体文件夹',
              icon: Icons.add_rounded,
              onPressed: () => addLocalFolder(context, ref),
            ),
            const SizedBox(height: 14),
            Text('只读取，不会修改或移动任何文件。', style: TypeScale.caption.copyWith(color: Palette.text3)),
          ]),
        ),
      ),
    );
  }
}
