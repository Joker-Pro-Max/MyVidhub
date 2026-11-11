import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../ui/components.dart';
import '../../ui/tokens.dart';
import '../../widgets/poster_card.dart';
import '../detail/detail_page.dart';

/// 某个类型下的全部电影和剧集。
class GenrePage extends ConsumerWidget {
  const GenrePage({super.key, required this.genre});
  final String genre;

  static Future<void> open(BuildContext context, String genre) =>
      Navigator.of(context).push(FadeRoute(builder: (_) => GenrePage(genre: genre)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(genreItemsProvider(genre));
    final g = FormFactor.of(context).gutter;
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
          padding: EdgeInsets.fromLTRB(g, 20, g, 20),
          sliver: SliverToBoxAdapter(
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text(genre, style: TypeScale.largeTitle),
              const SizedBox(width: 10),
              Text('${items.length}', style: TypeScale.title.copyWith(color: Palette.text3)),
            ]),
          ),
        ),
        PosterGrid(items: items, onTap: (m) => DetailPage.open(context, m.id), bottom: pad.bottom + 40),
      ]),
    );
  }
}
