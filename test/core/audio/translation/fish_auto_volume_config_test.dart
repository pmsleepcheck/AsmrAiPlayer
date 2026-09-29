import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('自动音量开关', () {
    test('默认开启', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      expect(store.translationAutoVolume, isTrue);
      expect(FishTtsConfigStore.defaultAutoVolume, isTrue);
    });

    test('关闭后持久化，重开仍为关', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      await store.setTranslationAutoVolume(false);
      expect(store.translationAutoVolume, isFalse);

      final prefs2 = await SharedPreferences.getInstance();
      final store2 = FishTtsConfigStore(prefs: prefs2);
      expect(store2.translationAutoVolume, isFalse);
    });

    test('仅在值变化时 notifyListeners', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      var notified = 0;
      store.addListener(() => notified++);

      await store.setTranslationAutoVolume(true); // 本来就是 true
      expect(notified, 0);
      await store.setTranslationAutoVolume(false);
      expect(notified, 1);
      await store.setTranslationAutoVolume(false);
      expect(notified, 1);
    });
  });

  group('手动音量（secondaryVolume）', () {
    test('默认 0.7、写入钳位到 0..1、变化即通知', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FishTtsConfigStore(prefs: prefs);
      expect(store.secondaryVolume, closeTo(0.7, 1e-9));

      var notified = 0;
      store.addListener(() => notified++);

      await store.setSecondaryVolume(2.5);
      expect(store.secondaryVolume, 1.0);
      expect(notified, 1);

      await store.setSecondaryVolume(2.5); // 同值 → 不再通知
      expect(notified, 1);

      await store.setSecondaryVolume(-1);
      expect(store.secondaryVolume, 0.0);
      expect(notified, 2);
    });
  });
}
