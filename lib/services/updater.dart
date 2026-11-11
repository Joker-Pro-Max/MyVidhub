import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 自动更新：从 GitHub 私有仓库的 Release 检查、下载新版本。
///
/// 私有仓库需要访问令牌（只读）。令牌在打包时通过
/// `--dart-define=UPDATE_TOKEN=...` 注入（见 tool/release.sh），也可在设置里手动填写。
class UpdateConfig {
  static const repo = String.fromEnvironment('UPDATE_REPO', defaultValue: 'Joker-Pro-Max/MyVidhub');
  static const buildToken = String.fromEnvironment('UPDATE_TOKEN');
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.build,
    required this.tag,
    required this.notes,
    required this.assetName,
    required this.assetApiUrl,
    required this.assetSize,
    this.sha256,
    this.publishedAt,
  });

  final String version;
  final int build;
  final String tag;
  final String notes;
  final String assetName;
  final String assetApiUrl;
  final int assetSize;
  final String? sha256;
  final DateTime? publishedAt;
}

class CurrentVersion {
  const CurrentVersion(this.version, this.build);
  final String version;
  final int build;

  @override
  String toString() => '$version ($build)';
}

class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}

class Updater {
  Updater({required this.token});

  final String token;
  static const _channel = MethodChannel('myvidhub/installer');

  static bool get supported => Platform.isAndroid;

  static Future<CurrentVersion> current() async {
    final info = await PackageInfo.fromPlatform();
    // Android 分 ABI 打包时 versionCode = ABI 前缀 × 1000 + build
    final raw = int.tryParse(info.buildNumber) ?? 0;
    return CurrentVersion(info.version, raw % 1000);
  }

  /// "v1.2.0+7" → (1.2.0, 7)
  static (String, int)? parseTag(String tag) {
    final m = RegExp(r'^v?(\d+\.\d+\.\d+)\+(\d+)$').firstMatch(tag.trim());
    if (m == null) return null;
    return (m.group(1)!, int.parse(m.group(2)!));
  }

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'MyVidhub-Updater',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  /// 返回比当前新的版本；已是最新返回 null。
  Future<ReleaseInfo?> check() async {
    final r = await latest();
    final cur = await current();
    return r.build > cur.build ? r : null;
  }

  /// 仓库最新发布的版本信息（适合本设备的安装包）。
  Future<ReleaseInfo> latest() async {
    if (token.isEmpty) throw UpdateException('未设置访问令牌，无法访问私有仓库');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/${UpdateConfig.repo}/releases/latest'));
      _headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 401) throw UpdateException('访问令牌无效或已过期');
      if (res.statusCode == 404) throw UpdateException('没有找到发布版本（或令牌无权访问该仓库）');
      if (res.statusCode != 200) throw UpdateException('检查更新失败（HTTP ${res.statusCode}）');

      final json = jsonDecode(body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String;
      final parsed = parseTag(tag);
      if (parsed == null) throw UpdateException('无法识别的版本号：$tag');

      final abi = await _abi();
      final assets = (json['assets'] as List).cast<Map<String, dynamic>>();
      final asset = assets.where((a) => (a['name'] as String).contains(abi) && (a['name'] as String).endsWith('.apk')).firstOrNull;
      if (asset == null) throw UpdateException('新版本 $tag 没有适合本设备（$abi）的安装包');

      final digest = asset['digest'] as String?; // GitHub 提供 "sha256:..."
      return ReleaseInfo(
        version: parsed.$1,
        build: parsed.$2,
        tag: tag,
        notes: (json['body'] as String?)?.trim() ?? '',
        assetName: asset['name'] as String,
        assetApiUrl: asset['url'] as String,
        assetSize: asset['size'] as int,
        sha256: digest != null && digest.startsWith('sha256:') ? digest.substring(7) : null,
        publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      );
    } on SocketException {
      throw UpdateException('网络连接失败，无法访问 GitHub');
    } on TimeoutException {
      throw UpdateException('连接 GitHub 超时');
    } finally {
      client.close();
    }
  }

  /// 下载安装包，返回本地文件。[onProgress] 回调 0–1。
  Future<File> download(ReleaseInfo r, {void Function(double)? onProgress}) async {
    final dir = Directory(p.join((await getApplicationCacheDirectory()).path, 'updates'));
    if (dir.existsSync()) dir.deleteSync(recursive: true); // 清掉旧安装包
    dir.createSync(recursive: true);
    final file = File(p.join(dir.path, r.assetName));

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      // 1. 私有仓库的资源先请求 API（带令牌），GitHub 302 跳转到临时签名地址
      final req = await client.getUrl(Uri.parse(r.assetApiUrl));
      _headers.forEach(req.headers.set);
      req.headers.set('Accept', 'application/octet-stream');
      req.followRedirects = false;
      var res = await req.close();
      if (res.isRedirect || res.statusCode == 302 || res.statusCode == 307) {
        final location = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (location == null) throw UpdateException('下载地址无效');
        // 2. 签名地址不能再带 Authorization 头
        final req2 = await client.getUrl(Uri.parse(location));
        req2.headers.set('User-Agent', 'MyVidhub-Updater');
        res = await req2.close();
      }
      if (res.statusCode != 200) throw UpdateException('下载失败（HTTP ${res.statusCode}）');

      final total = res.contentLength > 0 ? res.contentLength : r.assetSize;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.close();
    } on SocketException {
      throw UpdateException('下载中断，请检查网络');
    } finally {
      client.close();
    }

    if (file.lengthSync() != r.assetSize) {
      throw UpdateException('安装包大小不符，可能下载不完整');
    }
    if (r.sha256 != null) {
      final hash = (await sha256.bind(file.openRead()).first).toString();
      if (hash != r.sha256) throw UpdateException('安装包校验失败（SHA-256 不一致）');
    }
    return file;
  }

  /// 调起系统安装器。返回 false 表示需要先允许"安装未知应用"。
  static Future<bool> install(File apk) async {
    final can = await _channel.invokeMethod<bool>('canInstall') ?? false;
    if (!can) {
      await _channel.invokeMethod('openInstallSettings');
      return false;
    }
    await _channel.invokeMethod('install', {'path': apk.path});
    return true;
  }

  static Future<String> _abi() async {
    if (!Platform.isAndroid) return 'arm64';
    final abi = await _channel.invokeMethod<String>('abi') ?? 'arm64-v8a';
    return switch (abi) {
      'arm64-v8a' => 'arm64',
      'armeabi-v7a' => 'armv7',
      'x86_64' => 'x86_64',
      _ => 'arm64',
    };
  }
}
