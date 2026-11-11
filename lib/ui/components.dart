import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// 所有可点元素的基础：无水波纹。
/// 悬停 = 轻微提亮，按下 = 降低不透明度，键盘 / 遥控器焦点 = 光圈。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.radius = 12,
    this.focusRing = true,
    this.hoverOverlay = true,
    this.semanticLabel,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final bool focusRing;
  final bool hoverOverlay;
  final String? semanticLabel;
  final bool autofocus;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final fast = Motion.of(context, Motion.fast);
    final radius = BorderRadius.circular(widget.radius);
    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _enabled,
        autofocus: widget.autofocus,
        mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: _enabled ? () => setState(() => _down = false) : null,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedOpacity(
            duration: fast,
            curve: Motion.curve,
            opacity: !_enabled ? 0.4 : (_down ? 0.7 : 1),
            child: Stack(children: [
              widget.child,
              if (widget.hoverOverlay)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: fast,
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        color: _hover ? Palette.glow(0.04) : Palette.glow(0),
                      ),
                    ),
                  ),
                ),
              if (widget.focusRing && _focus)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(color: Palette.light, width: 2),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 胶囊按钮。primary = 光色填充（每屏最多一个），secondary = 半透明。
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = true,
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Palette.onLight : Palette.text;
    final h = compact ? 40.0 : 48.0;
    return Pressable(
      onTap: onPressed,
      radius: h / 2,
      hoverOverlay: !primary,
      child: Container(
        height: h,
        padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22),
        decoration: BoxDecoration(
          color: primary ? Palette.light : Palette.glow(0.12),
          borderRadius: BorderRadius.circular(h / 2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 20 : 24, color: fg),
            const SizedBox(width: 6),
          ],
          Text(label, style: TypeScale.callout.copyWith(color: fg, fontWeight: FontWeight.w600, fontSize: 15)),
        ]),
      ),
    );
  }
}

/// 圆形图标按钮。[overArtwork] 为 true 时带模糊底，用在背景图上。
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 44,
    this.overArtwork = false,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final bool overArtwork;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    Widget circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? Palette.light
            : overArtwork
                ? Palette.shade(0.35)
                : Palette.glow(0.10),
      ),
      child: Icon(icon, size: size * 0.5, color: selected ? Palette.onLight : Palette.text),
    );
    if (overArtwork && !selected) {
      circle = ClipOval(
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: circle),
      );
    }
    return Tooltip(
      message: tooltip,
      child: Pressable(onTap: onPressed, radius: size / 2, semanticLabel: tooltip, child: circle),
    );
  }
}

/// 文字胶囊筛选 / 分段选择。
class FilterPills<T> extends StatelessWidget {
  const FilterPills({
    super.key,
    required this.items,
    required this.selected,
    required this.label,
    required this.onSelect,
    this.padding = EdgeInsets.zero,
  });

  final List<T> items;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final fast = Motion.of(context, Motion.fast);
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final item = items[i];
          final on = item == selected;
          return Pressable(
            onTap: () => onSelect(item),
            radius: 20,
            child: AnimatedContainer(
              duration: fast,
              curve: Motion.curve,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? Palette.light : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label(item),
                style: TypeScale.callout.copyWith(
                  color: on ? Palette.onLight : Palette.text2,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 区块标题 + 可选"全部"。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.onMore, this.padding, this.trailing});

  final String title;
  final VoidCallback? onMore;
  final EdgeInsets? padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final g = FormFactor.of(context).gutter;
    return Padding(
      padding: padding ?? EdgeInsets.fromLTRB(g, 0, g - 8, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Text(title, style: TypeScale.title)),
        ?trailing,
        if (onMore != null)
          Pressable(
            onTap: onMore,
            radius: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('全部', style: TypeScale.callout.copyWith(color: Palette.text2)),
                const Icon(Icons.chevron_right_rounded, size: 20, color: Palette.text2),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// 细进度条（叠在图片底部）。
class ProgressHairline extends StatelessWidget {
  const ProgressHairline({super.key, required this.value, this.height = 3});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: Palette.glow(0.22)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: const ColoredBox(color: Palette.light),
            ),
          ]),
        ),
      );
}

/// 已看完标记。
class WatchedMark extends StatelessWidget {
  const WatchedMark({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: Palette.light, shape: BoxShape.circle),
        child: Icon(Icons.check_rounded, size: size * 0.7, color: Palette.onLight),
      );
}

/// 分组列表（类似系统设置）。
class GroupedList extends StatelessWidget {
  const GroupedList({super.key, required this.children, this.header, this.footer, this.headerAction});

  final List<Widget> children;
  final String? header;
  final String? footer;

  /// 分组标题右侧的小操作（如"全部重新扫描"）。
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Padding(
          padding: EdgeInsets.only(left: 62),
          child: Divider(height: 1, thickness: 1, color: Palette.hairline),
        ));
      }
      rows.add(children[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (header != null)
        Padding(
          padding: EdgeInsets.fromLTRB(16, 0, headerAction != null ? 4 : 16, headerAction != null ? 2 : 8),
          child: Row(children: [
            Expanded(child: Text(header!.toUpperCase(), style: TypeScale.overline)),
            ?headerAction,
          ]),
        ),
      ClipRRect(
        borderRadius: BorderRadius.circular(Radii.group),
        child: ColoredBox(color: Palette.surface1, child: Column(children: rows)),
      ),
      if (footer != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(footer!, style: TypeScale.caption.copyWith(color: Palette.text3, height: 1.5)),
        ),
    ]);
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
    this.leading,
    this.subtitleMaxLines = 2,
  });

  final IconData icon;

  /// 替换默认图标方块。
  final Widget? leading;
  final int subtitleMaxLines;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Palette.danger : Palette.text;
    final content = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(children: [
            leading ?? IconTile(icon: icon, color: destructive ? Palette.danger : Palette.text2),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: TypeScale.callout.copyWith(color: color, fontSize: 15)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      maxLines: subtitleMaxLines, overflow: TextOverflow.ellipsis, style: TypeScale.caption),
                ],
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            if (trailing == null && onTap != null && enabled)
              const Icon(Icons.chevron_right_rounded, color: Palette.text3),
          ]),
        ),
      ),
    );
    if (onTap == null || !enabled) return content;
    return Pressable(onTap: onTap, radius: 0, focusRing: true, child: content);
  }
}

/// 开关（光色轨道 + 圆钮，不用 Material 默认样式）。
class LightSwitch extends StatelessWidget {
  const LightSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.fast);
    return Semantics(
      toggled: value,
      child: Pressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        radius: 16,
        hoverOverlay: false,
        child: AnimatedContainer(
          duration: d,
          curve: Motion.curve,
          width: 50,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? Palette.light : Palette.surface3,
            borderRadius: BorderRadius.circular(15),
          ),
          child: AnimatedAlign(
            duration: d,
            curve: Motion.curve,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? Palette.onLight : Palette.text2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 设置行左侧的图标方块。
class IconTile extends StatelessWidget {
  const IconTile({super.key, required this.icon, this.size = 32, this.filled = false, this.color = Palette.text2});
  final IconData icon;
  final double size;

  /// true = 光色填充（主操作），false = 石墨灰。
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? Palette.light : Palette.surface3,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Icon(icon, size: size * 0.58, color: filled ? Palette.onLight : color),
      );
}

/// 小标签（如"即将支持"）。
class TagLabel extends StatelessWidget {
  const TagLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Palette.glow(0.16)),
        ),
        child: Text(text, style: TypeScale.caption.copyWith(fontSize: 11.5, color: Palette.text3)),
      );
}

/// "刚刚 / 5 分钟前 / 3 小时前 / 昨天 / 11月2日"
String relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inDays < 1) return '${d.inHours} 小时前';
  if (d.inDays == 1) return '昨天';
  return '${t.month}月${t.day}日';
}

/// 小号加载指示（不用 Material 默认粗环）。
class Spinner extends StatelessWidget {
  const Spinner({super.key, this.size = 18});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: Palette.text2, backgroundColor: Palette.glow(0.08)),
      );
}

/// 淡入淡出的页面路由（减少动画时无过渡）。
class FadeRoute<T> extends PageRouteBuilder<T> {
  FadeRoute({required WidgetBuilder builder, super.opaque})
      : super(
          pageBuilder: (context, _, _) => builder(context),
          transitionDuration: Motion.base,
          reverseTransitionDuration: Motion.fast,
          transitionsBuilder: (context, a, _, child) {
            if (MediaQuery.maybeDisableAnimationsOf(context) == true) return child;
            return FadeTransition(opacity: CurvedAnimation(parent: a, curve: Motion.curve), child: child);
          },
        );
}
