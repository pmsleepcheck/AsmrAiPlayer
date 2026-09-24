import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettingsService.noImageMode 持久化', () {
    test('默认 false', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      expect(s.noImageMode, isFalse);
    });

    test('setNoImageMode 写入 prefs 且 reload 后保持', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      await s.setNoImageMode(true);
      expect(s.noImageMode, isTrue);

      final reloaded = AppSettingsService(prefs);
      expect(reloaded.noImageMode, isTrue);

      await s.setNoImageMode(false);
      final again = AppSettingsService(prefs);
      expect(again.noImageMode, isFalse);
    });

    test('同值 setter 不重复写/不重复通知', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      var notified = 0;
      s.addListener(() => notified++);
      await s.setNoImageMode(false); // 已是 false
      expect(notified, 0);
      await s.setNoImageMode(true);
      expect(notified, 1);
      await s.setNoImageMode(true);
      expect(notified, 1);
    });
  });
}
