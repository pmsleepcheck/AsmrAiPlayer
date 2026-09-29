import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/translation_mix_state.dart';
import 'package:aaplay/core/audio/translation/translation_volume_policy.dart';

TranslationMixState enabledState({
  bool primary = false,
  double secondary = 0.7,
}) =>
    TranslationMixState(
      enabled: true,
      translationPrimary: primary,
      mainEar: EarSide.right,
      secondaryVolume: secondary,
    );

void main() {
  group('回退 emphasis（自动关 / 不可测 / 会话关）', () {
    test('自动关 → 与上线前行为一致（翻译为 secondary）', () {
      final plan = TranslationVolumePolicy.compute(
        state: enabledState(secondary: 0.7),
        autoVolume: false,
        mainRms: 0.2,
        ttsRms: 0.5,
      );
      expect(plan.aligned, isFalse);
      expect(plan.mainVolume, 1.0);
      expect(plan.translationVolume, 0.7);
    });

    test('自动关且方向对调 → 主轨 secondary', () {
      final plan = TranslationVolumePolicy.compute(
        state: enabledState(primary: true, secondary: 0.4),
        autoVolume: false,
      );
      expect(plan.aligned, isFalse);
      expect(plan.mainVolume, 0.4);
      expect(plan.translationVolume, 1.0);
    });

    test('主轨不可测（在线流）→ 回退手动比例', () {
      final plan = TranslationVolumePolicy.compute(
        state: enabledState(secondary: 0.6),
        autoVolume: true,
        mainRms: null,
        ttsRms: 0.3,
      );
      expect(plan.aligned, isFalse);
      expect(plan.mainVolume, 1.0);
      expect(plan.translationVolume, 0.6);
    });

    test('TTS 不可测 / 全静音测量值 → 回退', () {
      for (final tts in <double?>[null, 0, 1e-9, double.nan]) {
        final plan = TranslationVolumePolicy.compute(
          state: enabledState(secondary: 0.7),
          autoVolume: true,
          mainRms: 0.2,
          ttsRms: tts,
        );
        expect(plan.aligned, isFalse, reason: 'tts=$tts');
      }
    });

    test('会话未开 → 翻译轨必须静音', () {
      final idle = TranslationMixState.idle(secondaryVolume: 0.7);
      final plan = TranslationVolumePolicy.compute(
        state: idle,
        autoVolume: true,
        mainRms: 0.2,
        ttsRms: 0.5,
      );
      expect(plan.aligned, isFalse);
      expect(plan.mainVolume, 1.0);
      expect(plan.translationVolume, 0.0);
    });
  });

  group('自动响度对齐', () {
    test('主轨更响 → 压主轨，翻译保持 1.0', () {
      final plan = TranslationVolumePolicy.compute(
        state: enabledState(),
        autoVolume: true,
        mainRms: 0.4,
        ttsRms: 0.1,
      );
      expect(plan.aligned, isTrue);
      expect(plan.mainVolume, closeTo(0.25, 1e-9));
      expect(plan.translationVolume, 1.0);
      // 感知响度相等
      expect(0.4 * plan.mainVolume, closeTo(0.1 * plan.translationVolume, 1e-9));
    });

    test('翻译更响 → 压翻译，主轨保持 1.0', () {
      final plan = TranslationVolumePolicy.compute(
        state: enabledState(),
        autoVolume: true,
        mainRms: 0.05,
        ttsRms: 0.5,
      );
      expect(plan.aligned, isTrue);
      expect(plan.mainVolume, 1.0);
      expect(plan.translationVolume, closeTo(0.1, 1e-9));
      expect(0.05 * plan.mainVolume, closeTo(0.5 * plan.translationVolume, 1e-9));
    });

    test('比例极端时被下限 0.1 兜住（不会静音）', () {
      final plan = TranslationVolumePolicy.compute(
        state: enabledState(),
        autoVolume: true,
        mainRms: 1e-3,
        ttsRms: 0.9,
      );
      expect(plan.aligned, isTrue);
      expect(plan.translationVolume,
          TranslationVolumePolicy.minVolume);
      expect(plan.mainVolume, 1.0);
    });

    test('两轨相等 → 都不压', () {
      final plan = TranslationVolumePolicy.compute(
        state: enabledState(),
        autoVolume: true,
        mainRms: 0.3,
        ttsRms: 0.3,
      );
      expect(plan.aligned, isTrue);
      expect(plan.mainVolume, 1.0);
      expect(plan.translationVolume, 1.0);
    });

    test('对齐结果永远在 [0.1, 1]', () {
      for (final main in <double>[1e-3, 0.01, 0.1, 0.5, 1.0]) {
        for (final tts in <double>[1e-3, 0.01, 0.1, 0.5, 1.0]) {
          final plan = TranslationVolumePolicy.compute(
            state: enabledState(),
            autoVolume: true,
            mainRms: main,
            ttsRms: tts,
          );
          expect(plan.mainVolume,
              inInclusiveRange(0.1, 1.0), reason: 'main=$main tts=$tts');
          expect(plan.translationVolume,
              inInclusiveRange(0.1, 1.0), reason: 'main=$main tts=$tts');
        }
      }
    });
  });
}
