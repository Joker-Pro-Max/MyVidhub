import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import '../data/sources/network_config.dart';
import '../services/source_registry.dart';
import '../ui/tokens.dart';

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
    final ImageProvider provider = isRemotePath(p)
        ? RemoteImage(p)
        : p.startsWith('http://') || p.startsWith('https://')
            ? NetworkImage(p, headers: _hotlinkHeaders(p))
            : FileImage(File(p));
    return Image(
      image: ResizeImage(provider, width: cacheWidth, policy: ResizeImagePolicy.fit),
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => ph,
      frameBuilder: (context, child, frame, wasSync) {
        // 缓存命中直接显示；加载中只显示占位；首帧到达后淡入（占位随之移除）
        if (wasSync) return child;
        if (frame == null) return ph;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.of(context, Motion.base),
          curve: Motion.curve,
          builder: (_, v, c) => Opacity(opacity: v, child: c),
          child: child,
        );
      },
    );
  }
}

/// 没有海报时的占位：安静的石墨色，轻微带一点按标题固定的色相，
/// 大尺寸排出片名，小尺寸（头像）只显示首字。
class PosterPlaceholder extends StatelessWidget {
  const PosterPlaceholder({super.key, required this.title, this.icon});
  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final hue = (title.hashCode % 360).abs().toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.10, 0.17).toColor();
    final c2 = HSLColor.fromAHSL(1, hue, 0.08, 0.11).toColor();
    final glyph = title.trim().isEmpty ? '?' : title.trim().characters.first.toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [c1, c2]),
      ),
      child: LayoutBuilder(builder: (context, c) {
        if (icon != null) {
          return Center(child: Icon(icon, color: Palette.text3, size: 28));
        }
        if (c.maxWidth < 96) {
          return Center(
            child: Text(glyph,
                style: TypeScale.title.copyWith(fontSize: c.maxWidth * 0.36, color: Palette.text3)),
          );
        }
        return Padding(
          padding: EdgeInsets.all(c.maxWidth * 0.1),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TypeScale.headline.copyWith(
                fontSize: (c.maxWidth * 0.11).clamp(12.0, 22.0),
                color: Palette.text2,
                height: 1.25,
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// NAS（SMB / WebDAV）上的图片：经 [SourceRegistry] 下载并缓存到磁盘，显示时才加载。
@immutable
class RemoteImage extends ImageProvider<RemoteImage> {
  const RemoteImage(this.uri);
  final String uri;

  @override
  Future<RemoteImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(RemoteImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await SourceRegistry.instance.bytes(uri);
    if (bytes == null || bytes.isEmpty) throw StateError('无法加载 $uri');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is RemoteImage && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}

/// 有些站点（JavBus）的图片没有 Referer 会返回 403。
Map<String, String>? _hotlinkHeaders(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.contains('tmdb.org')) return null;
  return {'Referer': '${u.scheme}://${u.host}/', 'User-Agent': 'Mozilla/5.0'};
}
