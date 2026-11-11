import 'package:flutter/material.dart';

import '../data/db/models.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import 'poster_card.dart';

/// 横向滚动的一排海报（首页货架、详情页"同系列 / 更多类似"、搜索结果）。
class PosterShelf extends StatelessWidget {
  const PosterShelf({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onMore,
    this.bottom = 36,
  });

  final String title;
  final List<MediaSummary> items;
  final void Function(MediaSummary) onTap;
  final VoidCallback? onMore;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final width = PosterGrid.targetWidth(MediaQuery.sizeOf(context).width);
    final g = FormFactor.of(context).gutter;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionHeader(title: title, onMore: onMore),
        SizedBox(
          height: PosterCard.heightFor(width) + 16,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: EdgeInsets.fromLTRB(g, 6, g, 10),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 18),
            itemBuilder: (context, i) => PosterCard(item: items[i], width: width, onTap: () => onTap(items[i])),
          ),
        ),
      ]),
    );
  }
}
