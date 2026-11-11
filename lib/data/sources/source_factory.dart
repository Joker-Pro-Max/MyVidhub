import 'local_source.dart';
import 'media_source.dart';
import 'network_config.dart';
import 'smb_source.dart';
import 'webdav_source.dart';

/// 按数据库里的类型 / 配置创建媒体源（主线程和扫描 Isolate 共用）。
MediaSource createSource({required int id, required String type, required String root, String? config}) {
  switch (type) {
    case 'webdav':
      return WebDavSource(sourceId: id, config: NetworkConfig.decode(config!), root: root);
    case 'smb':
      return SmbSource(sourceId: id, config: NetworkConfig.decode(config!), root: root);
    default:
      return LocalSource(root);
  }
}

/// 只连接、不落库：添加网络源时用来浏览目录。
MediaSource createProbeSource(NetworkConfig c, {int tempId = 0}) => switch (c.kind) {
      NetworkKind.webdav => WebDavSource(sourceId: tempId, config: c, root: c.basePath),
      NetworkKind.smb => SmbSource(sourceId: tempId, config: c, root: '/'),
    };
