import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/platform/dummy_lyric_overlay_controller.dart';
import 'package:aaplay/core/platform/i_lyric_overlay_controller.dart';

class _FakeController implements ILyricOverlayController {
  int showCount = 0;
  int hideCount = 0;
  bool showing = false;

  @override
  bool get isSupported => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> show() async {
    showCount++;
    showing = true;
  }

  @override
  Future<void> hide() async {
    hideCount++;
    showing = false;
  }

  @override
  Future<void> updateLyric(String? text) async {}

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> isShowing() async => showing;

  @override
  Future<void> setEditable(bool editable) async {}
}

void main() {
  group('ILyricOverlayController.isSupported（bug.txt 1）', () {
    test('Dummy（Windows 等）不支持系统悬浮', () {
      expect(DummyLyricOverlayController().isSupported, isFalse);
    });

    test('假实现 show 后 isShowing 为 true（对照 Dummy 恒 false）', () async {
      final c = _FakeController();
      expect(await c.isShowing(), isFalse);
      await c.show();
      expect(await c.isShowing(), isTrue);
      await c.hide();
      expect(await c.isShowing(), isFalse);
    });
  });

  group('朗读方位文案（bug.txt 4）', () {
    test('主耳右 →「主耳：右　同声传译：左」', () {
      expect(
        Strings.translationEarDesc(mainIsRight: true),
        '主耳：右　同声传译：左',
      );
    });

    test('主耳左 →「主耳：左　同声传译：右」', () {
      expect(
        Strings.translationEarDesc(mainIsRight: false),
        '主耳：左　同声传译：右',
      );
    });
  });

  group('同声传译延迟文案（bug.txt 5）', () {
    test('0/负值 → 不延迟；毫秒/秒分档', () {
      expect(Strings.translationDelayOption(0), '不延迟');
      expect(Strings.translationDelayOption(-1), '不延迟');
      expect(Strings.translationDelayOption(200), '200 毫秒');
      expect(Strings.translationDelayOption(1000), '1 秒');
      expect(Strings.translationDelayOption(1500), '1.5 秒');
    });
  });

  group('睡眠定时剩余时间文案（bug.txt 6）', () {
    test('mm:ss 与 h:mm:ss', () {
      expect(Strings.sleepTimerRemaining(const Duration(seconds: 59)), '00:59');
      expect(Strings.sleepTimerRemaining(const Duration(minutes: 30)), '30:00');
      expect(
        Strings.sleepTimerRemaining(const Duration(minutes: 90)),
        '1:30:00',
      );
      expect(
        Strings.playerSleepTimerActive(const Duration(seconds: 45)),
        '定时 · 剩余 00:45',
      );
    });
  });

  group('字幕三模式标签（bug.txt 2）', () {
    test('关闭 / 应用内 / 弹窗', () {
      expect(Strings.subtitleModeOff, '关闭');
      expect(Strings.subtitleModeInApp, '应用内');
      expect(Strings.subtitleModePopup, '弹窗');
    });
  });
}
