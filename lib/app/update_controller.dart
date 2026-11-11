import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/updater.dart';
import 'providers.dart';

enum UpdateStatus { idle, checking, upToDate, available, downloading, ready, error }

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.current,
    this.release,
    this.progress = 0,
    this.message,
    this.file,
    this.shouldPrompt = false,
  });

  final UpdateStatus status;
  final CurrentVersion? current;
  final ReleaseInfo? release;
  final double progress;
  final String? message;
  final File? file;

  /// 自动检查发现新版本时为 true，界面据此弹出一次更新对话框。
  final bool shouldPrompt;

  UpdateState copyWith({
    UpdateStatus? status,
    CurrentVersion? current,
    ReleaseInfo? release,
    double? progress,
    String? message,
    File? file,
    bool? shouldPrompt,
  }) =>
      UpdateState(
        status: status ?? this.status,
        current: current ?? this.current,
        release: release ?? this.release,
        progress: progress ?? this.progress,
        message: message,
        file: file ?? this.file,
        shouldPrompt: shouldPrompt ?? false,
      );
}

final updateProvider = NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

class UpdateController extends Notifier<UpdateState> {
  static const _lastCheckKey = 'update_last_check';
  static const _autoInterval = Duration(hours: 6);

  @override
  UpdateState build() {
    Updater.current().then((v) => state = state.copyWith(current: v, status: state.status));
    return const UpdateState();
  }

  /// 启动时调用：安卓上每 6 小时最多静默检查一次。
  Future<void> autoCheck() async {
    if (!Updater.supported) return;
    final db = ref.read(dbProvider);
    final last = int.tryParse(db.setting(_lastCheckKey) ?? '');
    if (last != null &&
        DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) < _autoInterval) {
      return;
    }
    await check(silent: true);
  }

  Future<void> check({bool silent = false}) async {
    if (state.status == UpdateStatus.checking || state.status == UpdateStatus.downloading) return;
    state = state.copyWith(status: UpdateStatus.checking);
    try {
      final r = await Updater().check();
      ref.read(dbProvider).setSetting(_lastCheckKey, '${DateTime.now().millisecondsSinceEpoch}');
      if (r == null) {
        state = state.copyWith(status: UpdateStatus.upToDate, message: '已是最新版本');
      } else {
        state = state.copyWith(status: UpdateStatus.available, release: r, shouldPrompt: silent);
      }
    } catch (e) {
      // 静默检查失败不打扰用户
      state = state.copyWith(status: silent ? UpdateStatus.idle : UpdateStatus.error, message: '$e');
    }
  }

  void promptShown() => state = state.copyWith(status: state.status, shouldPrompt: false);

  Future<void> downloadAndInstall() async {
    final r = state.release;
    if (r == null) return;
    if (state.status == UpdateStatus.ready && state.file != null && state.file!.existsSync()) {
      return install();
    }
    state = state.copyWith(status: UpdateStatus.downloading, progress: 0);
    try {
      var lastEmit = 0.0;
      final file = await Updater().download(r, onProgress: (p) {
        if (p - lastEmit >= 0.01 || p >= 1) {
          lastEmit = p;
          state = state.copyWith(status: UpdateStatus.downloading, progress: p);
        }
      });
      state = state.copyWith(status: UpdateStatus.ready, file: file, progress: 1);
      await install();
    } catch (e) {
      state = state.copyWith(status: UpdateStatus.error, message: '$e');
    }
  }

  Future<void> install() async {
    final f = state.file;
    if (f == null) return;
    try {
      final ok = await Updater.install(f);
      state = state.copyWith(
        status: UpdateStatus.ready,
        message: ok ? null : '请在打开的系统设置中允许 MyVidhub「安装未知应用」，返回后点「安装」',
      );
    } catch (e) {
      state = state.copyWith(status: UpdateStatus.ready, message: '无法打开安装器：$e');
    }
  }
}
