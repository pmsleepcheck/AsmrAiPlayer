import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aaplay/core/audio/translation/fish_tts_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('智能耳（实验）默认关', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = FishTtsConfigStore(prefs: prefs);
    expect(store.translationSmartEar, isFalse);
    expect(FishTtsConfigStore.defaultSmartEar, isFalse);
  });

  test('写入持久化 + 仅变更时 notify', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = FishTtsConfigStore(prefs: prefs);
    var notified = 0;
    store.addListener(() => notified++);

    await store.setTranslationSmartEar(true);
    expect(store.translationSmartEar, isTrue);
    expect(notified, 1);

    await store.setTranslationSmartEar(true); // 同值 → 不重复通知
    expect(notified, 1);

    expect(prefs.getBool(FishTtsConfigStore.prefSmartEar), isTrue);

    final store2 = FishTtsConfigStore(prefs: prefs);
    expect(store2.translationSmartEar, isTrue);

    var notified2 = 0;
    store2.addListener(() => notified2++);
    await store2.setTranslationSmartEar(false);
    expect(store2.translationSmartEar, isFalse);
    expect(notified2, 1);
    expect(prefs.getBool(FishTtsConfigStore.prefSmartEar), isFalse);
  });
}
