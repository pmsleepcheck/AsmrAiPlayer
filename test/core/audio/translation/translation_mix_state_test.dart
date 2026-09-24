import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/translation_mix_state.dart';

void main() {
  group('TranslationMixState volumes', () {
    test('idle：翻译关 → 主 1.0 / 翻译 0', () {
      const s = TranslationMixState(
        enabled: false,
        translationPrimary: false,
        mainEar: null,
        secondaryVolume: 0.7,
      );
      expect(s.mainVolume, 1.0);
      expect(s.translationVolume, 0.0);
    });

    test('enabled 默认：主 primary=1.0，翻译 secondary=0.7', () {
      const s = TranslationMixState(
        enabled: true,
        translationPrimary: false,
        mainEar: EarSide.left,
        secondaryVolume: 0.7,
      );
      expect(s.mainVolume, 1.0);
      expect(s.translationVolume, 0.7);
    });

    test('swapped：主变 secondary、翻译变 primary，且主耳对调', () {
      const s = TranslationMixState(
        enabled: true,
        translationPrimary: false,
        mainEar: EarSide.left,
        secondaryVolume: 0.5,
      );
      final w = s.swapped;
      expect(w.translationPrimary, isTrue);
      expect(w.mainEar, EarSide.right);
      expect(w.mainVolume, 0.5);
      expect(w.translationVolume, 1.0);
      expect(w.swapped.mainEar, EarSide.left);
      expect(w.swapped.translationPrimary, isFalse);
    });

    test('toggle 只翻 enabled，不动方向/耳', () {
      const s = TranslationMixState(
        enabled: true,
        translationPrimary: true,
        mainEar: EarSide.right,
        secondaryVolume: 0.6,
      );
      final off = s.toggled;
      expect(off.enabled, isFalse);
      expect(off.translationPrimary, isTrue);
      expect(off.mainEar, EarSide.right);
      expect(off.mainVolume, 1.0);
      expect(off.translationVolume, 0.0);
      expect(off.toggled.enabled, isTrue);
    });

    test('beginSession 开翻译、清方向、写主耳；endSession 复位', () {
      const base = TranslationMixState(
        enabled: false,
        translationPrimary: true,
        mainEar: EarSide.right,
        secondaryVolume: 0.4,
      );
      final begun = base.beginSession(EarSide.left);
      expect(begun.enabled, isTrue);
      expect(begun.translationPrimary, isFalse);
      expect(begun.mainEar, EarSide.left);
      expect(begun.secondaryVolume, 0.4);

      final ended = begun.endSession();
      expect(ended.enabled, isFalse);
      expect(ended.mainEar, isNull);
      expect(ended.translationPrimary, isFalse);
      expect(ended.secondaryVolume, 0.4);
    });

    test('withSecondaryVolume clamp 到 0..1', () {
      final s = TranslationMixState.idle(secondaryVolume: 0.7)
          .withSecondaryVolume(1.9)
          .withSecondaryVolume(-0.2);
      expect(s.secondaryVolume, 0.0);
      expect(TranslationMixState.idle().withSecondaryVolume(2).secondaryVolume,
          1.0);
    });
  });
}
