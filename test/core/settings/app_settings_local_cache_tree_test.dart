import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettingsService.localCacheTreeMode 持久化', () {
    test('默认树形（true）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(AppSettingsService(prefs).localCacheTreeMode, isTrue);
    });

    test('setLocalCacheTreeMode(false) 写入 prefs 且 reload 后保持', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      await s.setLocalCacheTreeMode(false);
      expect(s.localCacheTreeMode, isFalse);
      expect(AppSettingsService(prefs).localCacheTreeMode, isFalse);
    });

    test('显式写 true 的存档仍为 true', () async {
      SharedPreferences.setMockInitialValues(
        {'local_cache_tree_mode': true},
      );
      final prefs = await SharedPreferences.getInstance();
      expect(AppSettingsService(prefs).localCacheTreeMode, isTrue);
    });

    test('值未变化不 notify，变化时 notify 一次', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      var notified = 0;
      s.addListener(() => notified++);

      await s.setLocalCacheTreeMode(true);
      expect(notified, 0);

      await s.setLocalCacheTreeMode(false);
      expect(notified, 1);
    });
  });
}
