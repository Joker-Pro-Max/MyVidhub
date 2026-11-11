import 'package:flutter/material.dart';

import '../data/db/models.dart';
import 'media_image.dart';

/// 海报卡片：2:3 海报 + 标题 + 年份。支持鼠标悬停、键盘/遥控器焦点高亮。
class PosterCard extends StatefulWidget {
  const PosterCard({super.key, required this.item, required this.width, required this.onTap});

  final MediaSummary item;
  final double width;
  final VoidCallback onTap;

  static const textHeight = 46.0;
  static double heightFor(double width) => width * 1.5 + textHeight;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _highlight = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final sub = [
      if (item.year != null) '${item.year}',
      if (item.kind == MediaKind.show && item.episodeCount > 0) '${item.episodeCount} 集',
    ].join(' · ');

    return FocusableActionDetector(
      onShowHoverHighlight: (v) => setState(() => _highlight = v),
      onShowFocusHighlight: (v) => setState(() => _highlight = v),
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                scale: _highlight ? 1.04 : 1,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: widget.width,
                  height: widget.width * 1.5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _highlight ? theme.colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(fit: StackFit.expand, children: [
                      MediaImage(
                        path: item.poster,
                        decodeWidth: widget.width,
                        placeholder: PosterPlaceholder(title: item.title),
                      ),
                      if (item.watched)
                        const Positioned(
                          top: 6,
                          left: 6,
                          child: _WatchedBadge(),
                        ),
                      if (item.progress != null && !item.watched)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 4,
                            color: theme.colorScheme.primary,
                            backgroundColor: Colors.black54,
                          ),
                        ),
                      if (item.rating != null)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: _RatingBadge(rating: item.rating!),
                        ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
              ),
              if (sub.isNotEmpty)
                Text(
                  sub,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatchedBadge extends StatelessWidget {
  const _WatchedBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
      );
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.rating});
  final double rating;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
}

/// 自适应海报网格：根据可用宽度计算列数（手机 3 列、平板 5–7 列、桌面更多）。
class PosterGrid extends StatelessWidget {
  const PosterGrid({super.key, required this.items, required this.onTap, this.padding});

  final List<MediaSummary> items;
  final void Function(MediaSummary) onTap;
  final EdgeInsets? padding;

  static double targetWidth(double screenWidth) =>
      screenWidth < 600 ? 100 : screenWidth < 1100 ? 150 : 170;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    final pad = padding ?? EdgeInsets.fromLTRB(phone ? 16 : 20, 8, phone ? 16 : 20, 32);
    return SliverLayoutBuilder(builder: (context, constraints) {
      final avail = constraints.crossAxisExtent - pad.horizontal;
      final target = targetWidth(MediaQuery.sizeOf(context).width);
      final spacing = MediaQuery.sizeOf(context).width < 600 ? 12.0 : 16.0;
      final cols = ((avail + spacing) / (target + spacing)).floor().clamp(2, 12);
      final cellW = (avail - spacing * (cols - 1)) / cols;
      return SliverPadding(
        padding: pad,
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing + 4,
            mainAxisExtent: PosterCard.heightFor(cellW),
          ),
          itemCount: items.length,
          itemBuilder: (context, i) =>
              PosterCard(item: items[i], width: cellW, onTap: () => onTap(items[i])),
        ),
      );
    });
  }
}
