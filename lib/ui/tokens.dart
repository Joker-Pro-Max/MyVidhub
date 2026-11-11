import 'package:flutter/material.dart';

/// 设计令牌：颜色、字体、间距、圆角、动效。规范见 DESIGN.md。
/// 业务代码里不要直接写颜色 / 圆角 / 时长，统一从这里取。
abstract final class Palette {
  static const bg = Color(0xFF0B0C0F);
  static const surface1 = Color(0xFF141619);
  static const surface2 = Color(0xFF1B1E22);
  static const surface3 = Color(0xFF24282D);
  static const hairline = Color(0x14E9ECF2);
  static const text = Color(0xFFECEEF2);
  static const text2 = Color(0xFF9DA3AD);
  static const text3 = Color(0xFF767C86);
  static const light = Color(0xFFF1F3F6);
  static const onLight = Color(0xFF0B0C0F);
  static const danger = Color(0xFFE2685E);

  /// 叠在任意背景上的"光"层（悬停 / 次要按钮 / 轨道）。
  static Color glow(double opacity) => light.withValues(alpha: opacity);

  /// 叠在图片上的暗层。
  static Color shade(double opacity) => bg.withValues(alpha: opacity);
}

abstract final class TypeScale {
  static const display = TextStyle(
      fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.1, color: Palette.text);
  static const largeTitle = TextStyle(
      fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.15, color: Palette.text);
  static const title = TextStyle(
      fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: -0.2, height: 1.25, color: Palette.text);
  static const headline = TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3, color: Palette.text);
  static const body = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.6, color: Palette.text);
  static const callout = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.3, color: Palette.text);
  static const caption = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.3, color: Palette.text2);
  static const overline = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, height: 1.3, color: Palette.text3);
}

abstract final class Radii {
  static const poster = 10.0;
  static const card = 12.0;
  static const group = 14.0;
  static const dialog = 22.0;
}

/// 屏幕尺寸分级。
enum FormFactor {
  phone,
  tablet,
  desktop;

  static FormFactor of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 600) return FormFactor.phone;
    if (w < 1200) return FormFactor.tablet;
    return FormFactor.desktop;
  }

  double get gutter => switch (this) { phone => 20, tablet => 32, desktop => 48 };
  bool get isPhone => this == phone;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 220);

  /// ease-out-quart
  static const curve = Cubic(0.25, 1, 0.5, 1);

  /// 系统开启"减少动画"时返回 0。
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}
