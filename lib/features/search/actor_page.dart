import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../widgets/media_image.dart';
import '../../widgets/poster_card.dart';
import '../detail/detail_page.dart';

/// 圆形头像（演员）。没有头像时显示名字首字，图片加载失败也退回首字。
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, required this.thumb, this.size = 76});
  final String name;
  final String? thumb;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        foregroundDecoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Palette.hairline)),
        child: ClipOval(
          child: MediaImage(
            path: thumb,
            decodeWidth: size,
            alignment: Alignment.topCenter,
            placeholder: _AvatarFallback(name: name, size: size),
          ),
        ),
      );
}

/// 没有头像时的占位：按名字固定色相的底色 + 名字首字。
class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final n = name.trim();
    final glyph = n.isEmpty ? '?' : n.characters.first.toUpperCase();
    final hue = (name.hashCode % 360).abs().toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.10, 0.20).toColor();
    final c2 = HSLColor.fromAHSL(1, hue, 0.08, 0.12).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c1, c2]),
      ),
      child: Center(
        child: Text(glyph, style: TypeScale.title.copyWith(fontSize: size * 0.4, color: Palette.text3)),
      ),
    );
  }
}

/// 演员页：片库里这位演员参演的所有影片和剧集。
class ActorPage extends ConsumerWidget {
  const ActorPage({super.key, required this.name});
  final String name;

  static Future<void> open(BuildContext context, String name) =>
      Navigator.of(context).push(FadeRoute(builder: (_) => ActorPage(name: name)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(actorItemsProvider(name));
    final thumb = ref.watch(dbProvider).actorThumb(name);
    final ff = FormFactor.of(context);
    final g = ff.gutter;
    final pad = MediaQuery.paddingOf(context);

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(g - 8, pad.top + 12, g, 0),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.centerLeft,
              child: RoundIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(g, 20, g, 28),
          sliver: SliverToBoxAdapter(
            child: Row(children: [
              PersonAvatar(name: name, thumb: thumb, size: ff.isPhone ? 80 : 104),
              const SizedBox(width: 20),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TypeScale.largeTitle),
                  const SizedBox(height: 6),
                  Text('片库中参演 ${items.length} 部', style: TypeScale.callout.copyWith(color: Palette.text2)),
                ]),
              ),
            ]),
          ),
        ),
        PosterGrid(
          items: items,
          onTap: (m) => DetailPage.open(context, m.id),
          bottom: pad.bottom + 40,
        ),
      ]),
    );
  }
}
