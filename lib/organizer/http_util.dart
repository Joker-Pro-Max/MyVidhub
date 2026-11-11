import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 刮削用的简单 HTTP GET。失败（网络错误、非 200、超时）返回 null，不抛异常。
class HttpResult {
  const HttpResult(this.status, this.body, this.contentType);
  final int status;
  final Uint8List body;
  final String contentType;

  String get text => utf8.decode(body, allowMalformed: true);
}

const browserUa = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/122.0 Safari/537.36';

Future<HttpResult?> httpGet(
  Uri url, {
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 15),
}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(url);
    req.headers.set(HttpHeaders.userAgentHeader, browserUa);
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(timeout);
    final b = BytesBuilder(copy: false);
    await for (final chunk in res.timeout(timeout)) {
      b.add(chunk);
    }
    return HttpResult(res.statusCode, b.takeBytes(), res.headers.contentType?.mimeType ?? '');
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
