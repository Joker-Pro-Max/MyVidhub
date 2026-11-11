import 'package:flutter/material.dart';

import '../data/db/models.dart';
import '../ui/components.dart';
import '../ui/tokens.dart';
import 'av_blur.dart';
import 'media_image.dart';

/// 海报卡片：2:3 海报 + 标题 + 年份。
/// 悬停 / 焦点时轻微放大并加光圈；已看完 = 小勾，看了一半 = 底部细进度条。
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.width,
    required this.onTap,
    this.onLongPress,
    this.selected,
  });

  /// 长按（进入多选）。
  final VoidCallback? onLongPress;

  /// 多选模式下是否选中；null 表示不在多选模式。
  final bool? selected;

  final MediaSummary item;
  final double width;
  final VoidCallback onTap;

  static const textHeight = 48.0;
  static double heightFor(double width) => width * 1.5 + textHeight;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _lift = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final fast = Motion.of(context, Motion.fast);
    final sub = [
      if (item.year != null) '${item.year}',
      if (item.unwatchedEpisodes > 0)
        '剩 ${item.unwatchedEpisodes} 集'
      else if (item.kind == MediaKind.show && item.episodeCount > 0)
        '${item.episodeCount} 集',
    ].join(' · ');

    return Semantics(
      button: true,
      label: item.title,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _lift = v),
        onShowFocusHighlight: (v) => setState(() => _lift = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap();
            return null;
          }),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: SizedBox(
            width: widget.width,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedScale(
                scale: _down ? 0.98 : (_lift ? 1.03 : 1),
                duration: fast,
                curve: Motion.curve,
                child: AnimatedContainer(
                  duration: fast,
                  curve: Motion.curve,
                  width: widget.width,
                  height: widget.width * 1.5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.poster),
                    boxShadow: [
                      BoxShadow(
                        color: Palette.shade(_lift ? 0.7 : 0.45),
                        blurRadius: _lift ? 28 : 14,
                        offset: Offset(0, _lift ? 12 : 6),
                      ),
                    ],
                  ),
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.poster),
                    border: Border.all(
                      color: _lift || widget.selected == true ? Palette.light : Palette.hairline,
                      width: _lift || widget.selected == true ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.poster),
                    child: Stack(fit: StackFit.expand, children: [
                      AvBlur(
                        isAv: item.isAv,
                        child: MediaImage(
                          path: item.poster,
                          decodeWidth: widget.width,
                          placeholder: PosterPlaceholder(title: item.title),
                        ),
                      ),
                      if (item.isAv) const Positioned(top: 8, left: 8, child: AvBadge()),
                      if (item.watched)
                        const Positioned(top: 8, right: 8, child: WatchedMark(size: 20)),
                      if (item.unwatchedEpisodes > 0)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 22),
                            height: 22,
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: Palette.light, borderRadius: BorderRadius.circular(11)),
                            child: Text('${item.unwatchedEpisodes}',
                                style: TypeScale.caption.copyWith(
                                    color: Palette.onLight, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ),
                      if (item.progress != null && !item.watched)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: ProgressHairline(value: item.progress!),
                        ),
                      // 多选：未选中的压暗，右下角圆形勾选框
                      if (widget.selected != null) ...[
                        AnimatedContainer(
                          duration: fast,
                          color: widget.selected! ? Palette.shade(0) : Palette.shade(0.45),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: AnimatedContainer(
                            duration: fast,
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.selected! ? Palette.light : Palette.shade(0.4),
                              border: Border.all(color: Palette.light, width: 1.5),
                            ),
                            child: widget.selected!
                                ? const Icon(Icons.check_rounded, size: 18, color: Palette.onLight)
                                : null,
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TypeScale.callout.copyWith(color: Palette.text),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(sub, maxLines: 1, style: TypeScale.caption),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// 自适应海报网格：根据可用宽度计算列数（手机 3 列、平板 5–7 列、桌面更多）。
class PosterGrid extends StatelessWidget {
  const PosterGrid({
    super.key,
    required this.items,
    required this.onTap,
    this.bottom = 32,
    this.onLongPress,
    this.selectedIds,
  });

  final void Function(MediaSummary)? onLongPress;

  /// 多选模式下已选中的 id；null 表示不在多选模式。
  final Set<int>? selectedIds;

  final List<MediaSummary> items;
  final void Function(MediaSummary) onTap;
  final double bottom;

  static double targetWidth(double screenWidth) =>
      screenWidth < 600 ? 104 : screenWidth < 1200 ? 150 : 172;

  @override
  Widget build(BuildContext context) {
    final ff = FormFactor.of(context);
    final g = ff.gutter;
    return SliverLayoutBuilder(builder: (context, constraints) {
      final avail = constraints.crossAxisExtent - g * 2;
      final target = targetWidth(MediaQuery.sizeOf(context).width);
      final spacing = ff.isPhone ? 14.0 : 22.0;
      final cols = ((avail + spacing) / (target + spacing)).floor().clamp(2, 12);
      final cellW = (avail - spacing * (cols - 1)) / cols;
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(g, 8, g, bottom),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing + 6,
            mainAxisExtent: PosterCard.heightFor(cellW),
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => PosterCard(
            item: items[i],
            width: cellW,
            onTap: () => onTap(items[i]),
            onLongPress: onLongPress == null ? null : () => onLongPress!(items[i]),
            selected: selectedIds?.contains(items[i].id),
          ),
        ),
      );
    });
  }
}
