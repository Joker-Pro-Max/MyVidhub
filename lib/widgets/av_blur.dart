import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_settings.dart';

/// AV 影片的图片在「AV 模糊显示」开启时模糊处理。
class AvBlur extends ConsumerWidget {
  const AvBlur({super.key, required this.isAv, required this.child, this.sigma = 22});
  final bool isAv;
  final Widget child;
  final double sigma;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isAv || !ref.watch(appSettingsProvider).blurAv) return child;
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.decal),
        child: child,
      ),
    );
  }
}

/// 海报左上角的 "AV" 标识：文字七彩流光，彩虹渐变在字里循环流动。
/// 系统开启「减少动画」时停在静态彩虹。
class AvBadge extends StatefulWidget {
  const AvBadge({super.key, this.fontSize = 12});
  final double fontSize;

  @override
  State<AvBadge> createState() => _AvBadgeState();
}

class _AvBadgeState extends State<AvBadge> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  static const _rainbow = [
    Color(0xFFFF3B6B),
    Color(0xFFFF9F1C),
    Color(0xFFFFE347),
    Color(0xFF3EE58A),
    Color(0xFF2ED3F5),
    Color(0xFF6C6BFF),
    Color(0xFFE04CFF),
    Color(0xFFFF3B6B),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: const Color(0xB30B0C0F),
            borderRadius: BorderRadius.circular(6),
          ),
          child: AnimatedBuilder(
            animation: _c,
            // 文字流光：彩虹渐变只填充在文字笔画里，沿水平方向循环流动
            builder: (context, child) => ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                colors: _rainbow,
                tileMode: TileMode.repeated,
                transform: _Slide(_c.value),
              // 一个彩虹周期 = 字宽的四分之一：细色带，字里同时能看到四轮流光
              ).createShader(Rect.fromLTWH(0, 0, bounds.width * 0.25, bounds.height)),
              child: child,
            ),
            child: Text(
              'AV',
              style: TextStyle(
                fontSize: widget.fontSize,
                height: 1.2,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
}

/// 让渐变沿水平方向平移一个周期（配合 TileMode.repeated 首尾衔接）。
class _Slide extends GradientTransform {
  const _Slide(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * t, 0, 0);
}
