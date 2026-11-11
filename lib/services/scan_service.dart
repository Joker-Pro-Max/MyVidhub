import 'dart:async';
import 'dart:isolate';

import '../data/db/library_db.dart';
import '../data/sources/source_factory.dart';
import 'library_scanner.dart';

class ScanEvent {
  const ScanEvent({this.dir, this.found = 0, this.done = false, this.error});
  final String? dir;
  final int found;
  final bool done;
  final String? error;
}

/// 在后台 Isolate 里扫描媒体源并写入数据库，UI 线程不受影响。
class ScanJob {
  ScanJob._(this._isolate, this.events);

  final Isolate _isolate;
  final Stream<ScanEvent> events;

  void cancel() => _isolate.kill(priority: Isolate.immediate);

  static Future<ScanJob> start({
    required String dbPath,
    required int sourceId,
    required String root,
    String type = 'local',
    String? config,
  }) async {
    final port = ReceivePort();
    final controller = StreamController<ScanEvent>();
    final isolate = await Isolate.spawn(
      _entry,
      [port.sendPort, dbPath, sourceId, root, type, config],
      onExit: port.sendPort,
      onError: port.sendPort,
    );
    var finished = false;
    port.listen((msg) {
      if (msg is List && msg.length == 3) {
        controller.add(ScanEvent(dir: msg[0] as String?, found: msg[1] as int));
      } else if (msg is Map) {
        finished = true;
        controller.add(ScanEvent(
          found: msg['found'] as int,
          done: true,
          error: msg['error'] as String?,
        ));
      } else if (msg is List && msg.length == 2) {
        // onError: [error, stack]
        finished = true;
        controller.add(ScanEvent(done: true, error: '${msg[0]}'));
      } else if (msg == null) {
        // onExit
        if (!finished) controller.add(const ScanEvent(done: true, error: '扫描已取消'));
        port.close();
        controller.close();
      }
    });
    return ScanJob._(isolate, controller.stream);
  }

  static Future<void> _entry(List<Object?> args) async {
    final send = args[0] as SendPort;
    final dbPath = args[1] as String;
    final sourceId = args[2] as int;
    final root = args[3] as String;
    final type = args[4] as String;
    final config = args[5] as String?;

    final db = LibraryDb.open(dbPath);
    var found = 0;
    var lastSent = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final scanner = LibraryScanner(
        createSource(id: sourceId, type: type, root: root, config: config),
        onProgress: (dir, n) {
          final now = DateTime.now();
          if (now.difference(lastSent).inMilliseconds > 120) {
            lastSent = now;
            send.send([dir, n, 0]);
          }
        },
      );
      final stamp = db.beginScan();
      await for (final item in scanner.scan()) {
        db.writeItem(sourceId, item, stamp);
        found++;
      }
      db.finishScan(sourceId, stamp);
      send.send({'found': found, 'error': null});
    } catch (e) {
      send.send({'found': found, 'error': '$e'});
    } finally {
      db.dispose();
    }
  }
}
