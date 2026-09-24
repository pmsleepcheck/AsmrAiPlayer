import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettingsService.downloadExtraDirs 持久化', () {
    test('默认空列表（旧行为：仅默认下载根）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      expect(s.downloadExtraDirs, isEmpty);
    });

    test('setDownloadExtraDirs 写入 prefs 且 reload 后保持', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      await s.setDownloadExtraDirs(['D:\\asmr', '/sdcard/cache']);
      expect(s.downloadExtraDirs, ['D:\\asmr', '/sdcard/cache']);

      final reloaded = AppSettingsService(prefs);
      expect(reloaded.downloadExtraDirs, ['D:\\asmr', '/sdcard/cache']);
    });

    test('getter 返回 unmodifiable（外部修改不污染内部状态）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      await s.setDownloadExtraDirs(['D:\\a']);
      expect(
        () => s.downloadExtraDirs.add('D:\\b'),
        throwsUnsupportedError,
      );
      expect(s.downloadExtraDirs, ['D:\\a']);
    });

    test('清空列表后 reload 仍为空', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      await s.setDownloadExtraDirs(['D:\\a']);
      await s.setDownloadExtraDirs(const []);
      expect(s.downloadExtraDirs, isEmpty);
      expect(AppSettingsService(prefs).downloadExtraDirs, isEmpty);
    });

    test('setter 触发 notifyListeners', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      var notified = 0;
      s.addListener(() => notified++);
      await s.setDownloadExtraDirs(['D:\\a']);
      expect(notified, 1);
    });
  });
}
