// 下载封面、从横版封面裁出竖版海报（移植自花栗鼠 images.rs）。
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'http_util.dart';

bool looksLikeImage(Uint8List b) =>
    (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) ||
    (b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47);

class ImageDownloadException implements Exception {
  const ImageDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<Uint8List> downloadImage(String url) async {
  final r = await httpGet(
    Uri.parse(url),
    headers: {if (url.contains('javbus')) 'Referer': 'https://www.javbus.com/'},
    timeout: const Duration(seconds: 30),
  );
  if (r == null) throw const ImageDownloadException('下载图片失败：网络错误');
  if (r.status < 200 || r.status >= 300) throw ImageDownloadException('下载图片失败：HTTP ${r.status}');
  if (!looksLikeImage(r.body)) throw const ImageDownloadException('下载到的内容不是图片（可能被站点拦截）');
  return r.body;
}

/// 横版封面（正面+背面拼在一起，宽明显大于高）。
bool isWideCover(Uint8List bytes) {
  final i = img.decodeImage(bytes);
  return i != null && i.width > i.height * 1.2;
}

/// 从横版封面里裁出右侧的正面封面当竖版海报（DMM 封面右侧约 47% 是正面）。
/// 在后台 Isolate 里解码 / 编码，不卡界面。
Future<Uint8List> cropPoster(Uint8List bytes) => Isolate.run(() {
      final i = img.decodeImage(bytes);
      if (i == null) throw const ImageDownloadException('图片解码失败');
      final x0 = (i.width * 0.5263).round();
      final c = img.copyCrop(i, x: x0, y: 0, width: i.width - x0, height: i.height);
      return img.encodeJpg(c, quality: 92);
    });

Future<bool> isWideCoverAsync(Uint8List bytes) => Isolate.run(() => isWideCover(bytes));
