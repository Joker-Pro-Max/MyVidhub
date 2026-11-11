import 'dart:convert';

/// 网络源的文件 / 图片在数据库里统一记为 `mvsrc://<源编号>/<远程路径>`。
/// 这样播放进度、收藏、扫描结果都和本地文件一样按"路径"稳定关联。
const remoteScheme = 'mvsrc://';

bool isRemotePath(String? path) => path != null && path.startsWith(remoteScheme);

String remoteUri(int sourceId, String remotePath) {
  final p = remotePath.startsWith('/') ? remotePath : '/$remotePath';
  return '$remoteScheme$sourceId$p';
}

/// mvsrc://3/share/电影/a.mkv → (3, /share/电影/a.mkv)
(int, String)? parseRemote(String uri) {
  if (!uri.startsWith(remoteScheme)) return null;
  final rest = uri.substring(remoteScheme.length);
  final slash = rest.indexOf('/');
  final id = int.tryParse(slash < 0 ? rest : rest.substring(0, slash));
  if (id == null) return null;
  return (id, slash < 0 ? '/' : rest.substring(slash));
}

enum NetworkKind {
  smb('SMB'),
  webdav('WebDAV');

  const NetworkKind(this.label);
  final String label;
}

/// 网络源连接配置。存在 sources.config（JSON）。
class NetworkConfig {
  const NetworkConfig({
    required this.kind,
    required this.host,
    this.username = '',
    this.password = '',
    this.domain = '',
    this.secure = false,
    this.port,
    this.basePath = '/',
  });

  final NetworkKind kind;

  /// SMB：主机名或 IP。WebDAV：主机名或 IP（不含协议）。
  final String host;
  final String username;
  final String password;
  final String domain;

  /// WebDAV 是否用 https。
  final bool secure;
  final int? port;

  /// WebDAV 服务的起始路径（如 /dav）。
  final String basePath;

  /// WebDAV 根地址：https://nas.local:5006
  Uri get origin => Uri(scheme: secure ? 'https' : 'http', host: host, port: port);

  String get display => switch (kind) {
        NetworkKind.smb => 'smb://$host',
        NetworkKind.webdav => '${origin.toString()}${basePath == '/' ? '' : basePath}',
      };

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'host': host,
        'username': username,
        'password': password,
        'domain': domain,
        'secure': secure,
        'port': port,
        'basePath': basePath,
      };

  String encode() => jsonEncode(toJson());

  static NetworkConfig decode(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return NetworkConfig(
      kind: NetworkKind.values.byName(m['kind'] as String),
      host: m['host'] as String,
      username: m['username'] as String? ?? '',
      password: m['password'] as String? ?? '',
      domain: m['domain'] as String? ?? '',
      secure: m['secure'] as bool? ?? false,
      port: m['port'] as int?,
      basePath: m['basePath'] as String? ?? '/',
    );
  }

  /// 从用户输入的 WebDAV 地址解析：nas.local:5005/dav、https://1.2.3.4:5006 等。
  static NetworkConfig? parseWebDav(String input, {String username = '', String password = ''}) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'http://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty || (u.scheme != 'http' && u.scheme != 'https')) return null;
    return NetworkConfig(
      kind: NetworkKind.webdav,
      host: u.host,
      secure: u.scheme == 'https',
      port: u.hasPort ? u.port : null,
      basePath: u.path.isEmpty ? '/' : u.path,
      username: username,
      password: password,
    );
  }

  /// SMB 地址：192.168.1.10、smb://nas.local、\\NAS
  static String? parseSmbHost(String input) {
    var s = input.trim().replaceAll('\\', '/');
    s = s.replaceFirst(RegExp(r'^smb://', caseSensitive: false), '').replaceFirst(RegExp(r'^/+'), '');
    final host = s.split('/').first;
    return host.isEmpty ? null : host;
  }

  String get basicAuth => 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
}
