import 'package:flutter_test/flutter_test.dart';
import 'package:myvidhub/services/updater.dart';

void main() {
  test('解析发布 tag', () {
    expect(Updater.parseTag('v1.2.0+7'), ('1.2.0', 7));
    expect(Updater.parseTag('1.0.1+12'), ('1.0.1', 12));
    expect(Updater.parseTag('v1.2.0'), isNull);
    expect(Updater.parseTag('latest'), isNull);
  });
}
