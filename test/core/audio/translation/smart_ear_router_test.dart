import 'package:flutter_test/flutter_test.dart';

import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/smart_ear_analyzer.dart';
import 'package:aaplay/core/audio/translation/smart_ear_router.dart';

void main() {
  EarTimeline timelineOf(List<EarSide?> sides, {int windowMs = 1000}) =>
      EarTimeline(
        windowMs: windowMs,
        durationMs: windowMs * sides.length,
        sides: sides,
      );

  group('SmartEarRouter.resolve', () {
    test('智能关 → 固定耳的对侧（与旧行为一致）', () {
      expect(
        SmartEarRouter.resolve(
          smart: false,
          fallbackEar: EarSide.right,
          timeline: timelineOf([EarSide.left]),
          lineIndex: 3,
        ),
        EarSide.left,
      );
      expect(
        SmartEarRouter.resolve(
          smart: false,
          fallbackEar: EarSide.left,
          lineIndex: 0,
        ),
        EarSide.right,
      );
    });

    test('智能开 + 无时间线（分析中/不支持）→ 固定耳的对侧', () {
      expect(
        SmartEarRouter.resolve(
          smart: true,
          fallbackEar: EarSide.left,
          timeline: null,
          positionMs: 4000,
          lineIndex: 1,
        ),
        EarSide.right,
      );
    });

    test('智能开 + 内容在左 → 翻译走右（内容对侧）', () {
      final t = timelineOf([EarSide.left, EarSide.right]);
      expect(
        SmartEarRouter.resolve(
          smart: true,
          fallbackEar: EarSide.right,
          timeline: t,
          positionMs: 500, // 第 0 窗 = 左
          lineIndex: 0,
        ),
        EarSide.right,
      );
      expect(
        SmartEarRouter.resolve(
          smart: true,
          fallbackEar: EarSide.right,
          timeline: t,
          positionMs: 1500, // 第 1 窗 = 右
          lineIndex: 1,
        ),
        EarSide.left,
      );
    });

    test('等响窗 → 一句左一句右（偶数行左，行号稳定）', () {
      final t = timelineOf([null, null, null]);
      expect(
        SmartEarRouter.resolve(
          smart: true,
          fallbackEar: EarSide.right,
          timeline: t,
          positionMs: 0,
          lineIndex: 0,
        ),
        EarSide.left,
      );
      expect(
        SmartEarRouter.resolve(
          smart: true,
          fallbackEar: EarSide.right,
          timeline: t,
          positionMs: 2500,
          lineIndex: 1,
        ),
        EarSide.right,
      );
      expect(
        SmartEarRouter.resolve(
          smart: true,
          fallbackEar: EarSide.right,
          timeline: t,
          positionMs: 2500, // 同一行重复取 → 同一只耳
          lineIndex: 1,
        ),
        EarSide.right,
      );
      expect(
        SmartEarRouter.resolve(
          smart: true,
          fallbackEar: EarSide.right,
          timeline: t,
          positionMs: 2500,
          lineIndex: 2,
        ),
        EarSide.left,
      );
    });

    test('位置越界钳到首/尾窗', () {
      final t = timelineOf([EarSide.right, EarSide.right]);
      expect(
        SmartEarRouter.resolve(
          smart: true,
          fallbackEar: EarSide.left,
          timeline: t,
          positionMs: -5000,
          lineIndex: 0,
        ),
        EarSide.left, // 首窗内容在右 → 翻译走左
      );
      expect(
        SmartEarRouter.resolve(
          smart: true,
          fallbackEar: EarSide.left,
          timeline: t,
          positionMs: 999999,
          lineIndex: 0,
        ),
        EarSide.left, // 尾窗同样内容在右
      );
    });
  });
}
