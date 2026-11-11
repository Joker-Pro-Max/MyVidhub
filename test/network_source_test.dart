import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myvidhub/data/sources/network_config.dart';
import 'package:myvidhub/data/sources/webdav_source.dart';
import 'package:myvidhub/services/library_scanner.dart';
import 'package:path/path.dart' as p;

import 'support/sample_library.dart';

/// 极简 WebDAV 服务器：把 [root] 目录以 /dav 前缀提供出来，要求 Basic 认证。
Future<HttpServer> _miniDav(String root, {String user = 'u', String pass = 'p'}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final auth = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
  server.listen((req) async {
    final res = req.response;
    if (req.headers.value('authorization') != auth) {
      res.statusCode = 401;
      await res.close();
      return;
    }
    final rel = req.uri.pathSegments.skip(1).join('/'); // 去掉 /dav
    final local = p.join(root, rel);
    if (req.method == 'PROPFIND') {
      final dir = Directory(local);
      if (!dir.existsSync()) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      String href(String path) => '/dav/${p.split(p.relative(path, from: root)).where((s) => s != '.').map(Uri.encodeComponent).join('/')}';
      final b = StringBuffer('<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">');
      void entry(FileSystemEntity e) {
        final isDir = e is Directory;
        b.write('<D:response><D:href>${href(e.path)}${isDir ? '/' : ''}</D:href><D:propstat><D:prop>'
            '<D:resourcetype>${isDir ? '<D:collection/>' : ''}</D:resourcetype>'
            '${isDir ? '' : '<D:getcontentlength>${(e as File).lengthSync()}</D:getcontentlength>'}'
            '</D:prop></D:propstat></D:response>');
      }

      entry(dir);
      for (final e in dir.listSync()) {
        entry(e);
      }
      b.write('</D:multistatus>');
      res.statusCode = 207;
      res.headers.contentType = ContentType('application', 'xml', charset: 'utf-8');
      res.write(b.toString());
    } else if (req.method == 'GET') {
      final f = File(local);
      if (!f.existsSync()) {
        res.statusCode = 404;
      } else {
        res.add(f.readAsBytesSync());
      }
    }
    await res.close();
  });
  return server;
}

void main() {
  test('地址解析', () {
    final w = NetworkConfig.parseWebDav('192.168.1.10:5005/dav')!;
    expect(w.origin.toString(), 'http://192.168.1.10:5005');
    expect(w.basePath, '/dav');
    final s = NetworkConfig.parseWebDav('https://nas.local:5006')!;
    expect(s.secure, isTrue);
    expect(s.basePath, '/');
    expect(NetworkConfig.parseWebDav(''), isNull);
    expect(NetworkConfig.parseSmbHost(r'\\NAS\share'), 'NAS');
    expect(NetworkConfig.parseSmbHost('smb://192.168.1.2/movies'), '192.168.1.2');

    final round = NetworkConfig.decode(w.encode());
    expect(round.host, '192.168.1.10');
    expect(round.port, 5005);

    expect(remoteUri(3, '/share/电影/a.mkv'), 'mvsrc://3/share/电影/a.mkv');
    expect(parseRemote('mvsrc://3/share/电影/a.mkv'), (3, '/share/电影/a.mkv'));
    expect(parseRemote('/local/path'), isNull);
  });

  group('WebDAV', () {
    late Directory tmp;
    late HttpServer server;
    late String root;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('myvidhub_dav');
      root = p.join(tmp.path, 'lib');
      createSampleLibrary(root);
      server = await _miniDav(root);
    });
    tearDown(() async {
      await server.close(force: true);
      tmp.deleteSync(recursive: true);
    });

    WebDavSource source({String pass = 'p'}) => WebDavSource(
          sourceId: 7,
          config: NetworkConfig(
              kind: NetworkKind.webdav, host: '127.0.0.1', port: server.port, username: 'u', password: pass),
          root: '/dav',
        );

    test('列目录（中文路径）与读文件', () async {
      final s = source();
      final top = await s.list(s.rootPath);
      expect(top.map((e) => e.name).toSet(), containsAll(['电影', '剧集']));
      expect(top.every((e) => e.path.startsWith('mvsrc://7/dav/')), isTrue);

      final movieDir = (await s.list(top.firstWhere((e) => e.name == '电影').path))
          .firstWhere((e) => e.name == '阿凡达 (2009)');
      final files = await s.list(movieDir.path);
      final nfo = files.firstWhere((e) => e.name.endsWith('.nfo'));
      expect(nfo.isDir, isFalse);
      expect(nfo.size, greaterThan(0));
      final bytes = await s.readBytes(nfo.path);
      expect(utf8.decode(bytes), contains('<title>阿凡达</title>'));
      expect(s.url(nfo.path).toString(), contains('%E9%98%BF%E5%87%A1%E8%BE%BE')); // 逐段编码
    });

    test('密码错误给出明确提示', () async {
      final s = source(pass: 'wrong');
      expect(() => s.list(s.rootPath), throwsA(isA<NetworkSourceException>()));
    });

    test('通过 WebDAV 完整扫描片库', () async {
      final items = await LibraryScanner(source()).scan().toList();
      final movies = items.whereType<ScannedMovie>().map((m) => m.title).toSet();
      final shows = items.whereType<ScannedShow>().map((s) => s.title).toSet();
      expect(movies, containsAll(['阿凡达', '盗梦空间', 'The Matrix']));
      expect(shows, containsAll(['绝命毒师', '庆余年', 'Friends']));
      final avatar = items.whereType<ScannedMovie>().firstWhere((m) => m.title == '阿凡达');
      expect(avatar.poster, startsWith('mvsrc://7/'));
      expect(avatar.files.single.path, startsWith('mvsrc://7/'));
      expect(avatar.nfo!.genres, ['动作', '科幻']);
    });
  });
}
