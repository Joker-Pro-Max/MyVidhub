import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// 从海报 / 剧照取主色，压暗降饱和后作为详情页背景的氛围光。
class ArtworkTint {
  static final _cache = <String, Future<Color?>>{};

  static Future<Color?> of(String? path) {
    if (path == null || path.isEmpty || path.startsWith('http')) return Future.value();
    return _cache.putIfAbsent(path, () => _compute(path));
  }

  static Future<Color?> _compute(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (data == null) return null;

      double r = 0, g = 0, b = 0, wsum = 0;
      for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
        final c = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
        final hsl = HSLColor.fromColor(c);
        // 偏向饱和、亮度适中的像素，避开黑白底
        final w = hsl.saturation * (1 - (hsl.lightness - 0.5).abs() * 2) + 0.02;
        r += c.r * w;
        g += c.g * w;
        b += c.b * w;
        wsum += w;
      }
      if (wsum == 0) return null;
      final avg = Color.from(alpha: 1, red: r / wsum, green: g / wsum, blue: b / wsum);
      final hsl = HSLColor.fromColor(avg);
      return hsl
          .withSaturation((hsl.saturation * 0.7).clamp(0.0, 0.45))
          .withLightness(0.24)
          .toColor();
    } catch (_) {
      return null;
    }
  }
}

/// 详情页顶部的氛围光：主色从顶部向下淡入背景色。
class ArtworkGlow extends StatelessWidget {
  const ArtworkGlow({super.key, required this.path, required this.height});
  final String? path;
  final double height;

  @override
  Widget build(BuildContext context) => FutureBuilder<Color?>(
        future: ArtworkTint.of(path),
        builder: (context, snap) {
          final c = snap.data ?? Palette.surface1;
          return AnimatedContainer(
            duration: Motion.of(context, Motion.base),
            height: height,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.6, -1.0),
                radius: 1.4,
                colors: [c.withValues(alpha: 0.55), Palette.bg.withValues(alpha: 0)],
              ),
            ),
          );
        },
      );
}
