import 'dart:io';

import 'package:flutter/material.dart';

/// 本地 / 网络图片，按显示尺寸降采样解码（4K 海报也不卡），淡入，失败显示占位。
class MediaImage extends StatelessWidget {
  const MediaImage({
    super.key,
    required this.path,
    required this.decodeWidth,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.alignment = Alignment.center,
  });

  final String? path;

  /// 逻辑像素宽度，会乘以设备像素比后作为解码宽度。
  final double decodeWidth;
  final BoxFit fit;
  final Widget? placeholder;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final ph = placeholder ?? const SizedBox.shrink();
    final p = path;
    if (p == null || p.isEmpty) return ph;
    final cacheWidth = (decodeWidth * MediaQuery.devicePixelRatioOf(context)).round();
    final ImageProvider provider = p.startsWith('http://') || p.startsWith('https://')
        ? NetworkImage(p)
        : FileImage(File(p));
    return Image(
      image: ResizeImage(provider, width: cacheWidth, policy: ResizeImagePolicy.fit),
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => ph,
      frameBuilder: (context, child, frame, wasSync) {
        if (wasSync) return child;
        return Stack(fit: StackFit.passthrough, children: [
          ph,
          AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            child: child,
          ),
        ]);
      },
    );
  }
}

/// 没有海报时的占位：标题首字 + 柔和渐变（每个标题颜色固定）。
class PosterPlaceholder extends StatelessWidget {
  const PosterPlaceholder({super.key, required this.title, this.icon});
  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final hue = (title.hashCode % 360).abs().toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.28, 0.24).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.32, 0.14).toColor();
    final glyph = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
      ),
      child: Center(
        child: icon != null
            ? Icon(icon, color: Colors.white38, size: 32)
            : LayoutBuilder(
                builder: (context, c) => Text(
                  glyph,
                  style: TextStyle(
                    fontSize: c.maxWidth * 0.36,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
      ),
    );
  }
}
