import 'ear_side.dart';

/// 翻译混播的纯状态（无 IO / 无 player），单测友好。
///
/// 音量模型（emphasis + 真分耳路由的响度平衡）：
/// - 主轨 / 翻译轨各有一个 volume；「方向」决定谁是 primary（1.0），
///   谁是 secondary（[secondaryVolume]，默认 0.7）。
/// - 翻译关闭时主轨必须回到 1.0，翻译轨为 0（不发声）。
/// - 声道路由不在本类：`EarChannelRouter.apply(mainEar: ...)`（智能耳有
///   时间线时传 `mainEar: null, ttsEar: ...`，主轨不 pan）在
///   `TranslationSessionController._applyEarRouting` 里随本状态推送
///   （Windows/Linux media_kit mpv `af`；移动端 no-op 降级为本音量 mix）。
class TranslationMixState {
  final bool enabled;
  final bool translationPrimary;
  final EarSide? mainEar;
  final double secondaryVolume;

  const TranslationMixState({
    required this.enabled,
    required this.translationPrimary,
    required this.mainEar,
    required this.secondaryVolume,
  });

  static const double fullVolume = 1.0;
  static const double muted = 0.0;

  factory TranslationMixState.idle({double secondaryVolume = 0.7}) =>
      TranslationMixState(
        enabled: false,
        translationPrimary: false,
        mainEar: null,
        secondaryVolume: secondaryVolume,
      );

  double get mainVolume {
    if (!enabled) return fullVolume;
    return translationPrimary ? secondaryVolume : fullVolume;
  }

  double get translationVolume {
    if (!enabled) return muted;
    return translationPrimary ? fullVolume : secondaryVolume;
  }

  TranslationMixState get toggled => TranslationMixState(
        enabled: !enabled,
        translationPrimary: translationPrimary,
        mainEar: mainEar,
        secondaryVolume: secondaryVolume,
      );

  /// 切换方向：主次 emphasis 对调 + 主耳左右对调。
  TranslationMixState get swapped => TranslationMixState(
        enabled: enabled,
        translationPrimary: !translationPrimary,
        mainEar: mainEar?.flipped,
        secondaryVolume: secondaryVolume,
      );

  TranslationMixState withEnabled(bool value) => TranslationMixState(
        enabled: value,
        translationPrimary: translationPrimary,
        mainEar: mainEar,
        secondaryVolume: secondaryVolume,
      );

  TranslationMixState withEar(EarSide? ear) => TranslationMixState(
        enabled: enabled,
        translationPrimary: translationPrimary,
        mainEar: ear,
        secondaryVolume: secondaryVolume,
      );

  TranslationMixState withSecondaryVolume(double v) => TranslationMixState(
        enabled: enabled,
        translationPrimary: translationPrimary,
        mainEar: mainEar,
        secondaryVolume: v.clamp(0.0, 1.0),
      );

  TranslationMixState beginSession(EarSide ear) => TranslationMixState(
        enabled: true,
        translationPrimary: false,
        mainEar: ear,
        secondaryVolume: secondaryVolume,
      );

  TranslationMixState endSession() => TranslationMixState(
        enabled: false,
        translationPrimary: false,
        mainEar: null,
        secondaryVolume: secondaryVolume,
      );

  @override
  bool operator ==(Object other) =>
      other is TranslationMixState &&
      other.enabled == enabled &&
      other.translationPrimary == translationPrimary &&
      other.mainEar == mainEar &&
      other.secondaryVolume == secondaryVolume;

  @override
  int get hashCode =>
      Object.hash(enabled, translationPrimary, mainEar, secondaryVolume);
}
