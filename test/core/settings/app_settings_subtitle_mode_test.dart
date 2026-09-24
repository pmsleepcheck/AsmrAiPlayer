import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettingsService.subtitleDisplayMode 持久化', () {
    test('默认 inApp（旧存档无键也安全）', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      expect(s.subtitleDisplayMode, SubtitleDisplayMode.inApp);
      expect(
        AppSettingsService.defaultSubtitleDisplayMode,
        SubtitleDisplayMode.inApp,
      );
    });

    test('三模式写入 prefs 且 reload 后保持', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);

      await s.setSubtitleDisplayMode(SubtitleDisplayMode.off);
      expect(s.subtitleDisplayMode, SubtitleDisplayMode.off);
      expect(
        AppSettingsService(prefs).subtitleDisplayMode,
        SubtitleDisplayMode.off,
      );

      await s.setSubtitleDisplayMode(SubtitleDisplayMode.popup);
      expect(
        AppSettingsService(prefs).subtitleDisplayMode,
        SubtitleDisplayMode.popup,
      );
    });

    test('未知存档值回落 inApp', () async {
      SharedPreferences.setMockInitialValues({
        'subtitle_display_mode': 'bogus',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        AppSettingsService(prefs).subtitleDisplayMode,
        SubtitleDisplayMode.inApp,
      );
    });

    test('setter 触发 notifyListeners；同值不重复通知', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppSettingsService(prefs);
      var notified = 0;
      s.addListener(() => notified++);
      await s.setSubtitleDisplayMode(SubtitleDisplayMode.popup);
      expect(notified, 1);
      await s.setSubtitleDisplayMode(SubtitleDisplayMode.popup);
      expect(notified, 1);
    });
  });
}
