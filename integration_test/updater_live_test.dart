// 联网验证自动更新链路（读取 GitHub 上真实的最新 Release）。
// flutter test integration_test/updater_live_test.dart -d macos
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:myvidhub/services/updater.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('获取最新版本并下载校验', (tester) async {
    await tester.runAsync(() async {
      final u = Updater();
      final r = await u.latest();
      final cur = await Updater.current();
      // ignore: avoid_print
      print('UPDATER latest=${r.tag} asset=${r.assetName} size=${r.assetSize} sha256=${r.sha256} current=$cur');
      expect(r.assetName, contains('arm64'));
      var last = 0.0;
      final f = await u.download(r, onProgress: (p) => last = p);
      // ignore: avoid_print
      print('UPDATER downloaded ${f.lengthSync()} bytes progress=$last');
      expect(f.lengthSync(), r.assetSize);
      expect(last, closeTo(1.0, 0.001));
      expect(await u.check(), isNull, reason: '本地版本与最新发布相同，应判断为已是最新');
    });
  });
}
