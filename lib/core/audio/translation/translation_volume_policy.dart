import 'package:aaplay/core/audio/translation/translation_mix_state.dart';

/// 一次混播音量决策的结果（纯数据）。
class VolumePlan {
  final double mainVolume;
  final double translationVolume;

  /// true = 走了「响度对齐」；false = 回退 [TranslationMixState] 的 emphasis。
  final bool aligned;

  const VolumePlan({
    required this.mainVolume,
    required this.translationVolume,
    required this.aligned,
  });

  @override
  bool operator ==(Object other) =>
      other is VolumePlan &&
      other.mainVolume == mainVolume &&
      other.translationVolume == translationVolume &&
      other.aligned == aligned;

  @override
  int get hashCode => Object.hash(mainVolume, translationVolume, aligned);

  @override
  String toString() =>
      'VolumePlan(main: $mainVolume, tts: $translationVolume, aligned: $aligned)';
}

/// 翻译音量策略（纯逻辑、无 IO，单测友好）。
///
/// 两种口径（见 TODO 20260928-translation-volume-auto-manual）：
/// - **自动对齐**：`autoVolume` 开、会话开、两轨响度都实测到 → 让响的一侧
///   压到与轻的一侧同响（`main × mainVol == tts × ttsVol == min(两轨)`）。
///   volume 上限 1.0（平台不放大），所以下限用 [minVolume] 兜底，避免把
///   任一轨压到听不清。
/// - **回退 emphasis**：自动关 / 任一轨不可测（在线流、flac…）/ 会话未开 →
///   用 `TranslationMixState` 现有的 primary(1.0) / secondary(手动值) 模型，
///   与本特性上线前行为完全一致。
class TranslationVolumePolicy {
  TranslationVolumePolicy._();

  /// 对齐结果的下限：压到更小就听不清了。
  static const double minVolume = 0.1;

  /// 低于此的测量值视为无效（全静音 / 测量失败）。
  static const double invalidRms = 1e-4;

  static VolumePlan compute({
    required TranslationMixState state,
    required bool autoVolume,
    double? mainRms,
    double? ttsRms,
  }) {
    final emphasis = VolumePlan(
      mainVolume: state.mainVolume,
      translationVolume: state.translationVolume,
      aligned: false,
    );
    if (!state.enabled || !autoVolume) return emphasis;
    if (!usable(mainRms) || !usable(ttsRms)) return emphasis;

    final main = mainRms!;
    final tts = ttsRms!;
    return VolumePlan(
      mainVolume: (tts / main).clamp(minVolume, 1.0),
      translationVolume: (main / tts).clamp(minVolume, 1.0),
      aligned: true,
    );
  }

  /// 一个测量值是否可用于对齐（非 null、有限、高于 [invalidRms]）。
  static bool usable(double? rms) =>
      rms != null && rms.isFinite && rms >= invalidRms;
}
