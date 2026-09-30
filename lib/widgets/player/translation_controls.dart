import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/smart_ear_analyzer.dart';
import 'package:aaplay/core/audio/translation/translation_session_controller.dart';
import 'package:aaplay/core/audio/translation/translation_play_flow.dart';
import 'package:aaplay/core/audio/translation/tts_synthesizer.dart';

/// 播放页「翻译朗读开关」+「耳侧文案」+「切换主次方向」+「音色预设一键切换」
/// + 「自动音量开关 + 翻译轨音量滑杆」+ 「智能(实验)开关 + 分析状态」。
class TranslationControls extends StatefulWidget {
  const TranslationControls({super.key});

  @override
  State<TranslationControls> createState() => _TranslationControlsState();
}

class _TranslationControlsState extends State<TranslationControls> {
  void _cycleVoice(BuildContext context, FishTtsConfigStore config) {
    final presets = config.voicePresets;
    if (presets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(Strings.voicePresetNoPresets)),
      );
      return;
    }
    final active = config.activeVoiceId;
    final i = presets.indexWhere((p) => p.id == active);
    final next = (i < 0 || i + 1 >= presets.length) ? presets.first : presets[i + 1];
    config.setActiveVoiceId(next.id);
  }

  /// 智能耳状态文案（idle = 不显示文字）。
  static String _smartStatusLabel(SmartEarStatus status) {
    switch (status) {
      case SmartEarStatus.idle:
        return '';
      case SmartEarStatus.analyzing:
        return Strings.smartEarStatusAnalyzing;
      case SmartEarStatus.ready:
        return Strings.smartEarStatusReady;
      case SmartEarStatus.unsupported:
        return Strings.smartEarStatusUnsupported;
      case SmartEarStatus.failed:
        return Strings.smartEarStatusFailed;
    }
  }

  /// 分析中=中性、就绪=accent、不支持/失败=error（全部取自 colorScheme）。
  static Color _smartStatusColor(SmartEarStatus status, ColorScheme cs) {
    switch (status) {
      case SmartEarStatus.ready:
        return cs.primary;
      case SmartEarStatus.unsupported:
      case SmartEarStatus.failed:
        return cs.error;
      case SmartEarStatus.idle:
      case SmartEarStatus.analyzing:
        return cs.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = GetIt.I<TranslationSessionController>();
    final voice = GetIt.I<FishTtsConfigStore>();
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: Listenable.merge([session, voice]),
      builder: (context, _) {
        final enabled = session.enabled;
        final ear = session.mainEar ?? EarSide.right;
        final earLabel = Strings.translationEarDesc(
          mainIsRight: ear == EarSide.right,
        );
        final activeVoice = voice.activeVoice;
        final voiceLabel = activeVoice?.name ?? Strings.voicePresetDefault;
        // 音色预设只属于 Fish；Supertonic 的音色在设置里填（这里仅展示）。
        final fishSource = voice.ttsSource == TtsSource.fish;
        final voiceCaption = fishSource ? voiceLabel : voice.supertonicVoice;
        final manualVolume = session.manualVolume.clamp(0.0, 1.0);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Tooltip(
                    message:
                        enabled ? Strings.translationToggleOff : Strings.translationToggleOn,
                    child: IconButton(
                      iconSize: 24,
                      icon: Icon(
                        enabled
                            ? Icons.record_voice_over
                            : Icons.record_voice_over_outlined,
                        color: enabled ? cs.primary : cs.onSurfaceVariant,
                      ),
                      onPressed: () async {
                        if (!enabled) {
                          // 开启前确认引擎就绪：fish 要 API Key，
                          // supertonic（默认）要本地服务在跑；不就绪时
                          // ensureTtsReady 已给出带「启动服务」的 SnackBar。
                          final ready = await TranslationPlayFlow.ensureTtsReady(
                            context,
                            onReady: () async {
                              if (context.mounted) {
                                await session.toggleTranslation();
                              }
                            },
                          );
                          if (!ready || !context.mounted) return;
                        }
                        await session.toggleTranslation();
                        if (!context.mounted) return;
                        final messenger = ScaffoldMessenger.of(context);
                        if (session.lastError == 'noApiKey') {
                          messenger.showSnackBar(const SnackBar(
                            content: Text(Strings.translationRequiresApiKey),
                          ));
                        } else if (session.lastError == 'unavailable') {
                          // Supertonic 本地服务没起来（默认引擎最常见失败）。
                          messenger.showSnackBar(const SnackBar(
                            content: Text(Strings.translationTtsServiceOffline),
                          ));
                        } else if (session.lastError == 'unauthorized') {
                          messenger.showSnackBar(const SnackBar(
                            content: Text(Strings.translationUnauthorized),
                          ));
                        } else if (session.lastError != null) {
                          messenger.showSnackBar(const SnackBar(
                            content: Text(Strings.translationTtsFailed),
                          ));
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          earLabel,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: enabled ? cs.primary : cs.onSurfaceVariant,
                              ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 28),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed:
                              fishSource ? () => _cycleVoice(context, voice) : null,
                          child: Text(
                            voiceCaption,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: fishSource
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                  decoration: fishSource
                                      ? TextDecoration.underline
                                      : null,
                                  decorationColor: fishSource
                                      ? cs.primary.withValues(alpha: 0.4)
                                      : null,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: Strings.translationSwapDirection,
                    child: IconButton(
                      iconSize: 24,
                      icon: Icon(
                        Icons.swap_horiz,
                        color: session.translationPrimary
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                      onPressed: () => session.swapDirection(),
                    ),
                  ),
                ],
              ),
              // 音量：自动对齐开关 + 手动滑杆（按作品记住）。
              Row(
                children: [
                  Tooltip(
                    message: Strings.translationAutoVolumeDesc,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Strings.translationAutoVolumeLabel,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: session.autoVolume
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                        ),
                        Switch.adaptive(
                          value: session.autoVolume,
                          onChanged: (v) => session.setAutoVolume(v),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    // 对齐生效时手动值不参与音量 → 明说「拖了不会变」。
                    message: session.manualVolumeEffective
                        ? Strings.translationManualVolumeDesc
                        : Strings.translationVolumeAlignedHint,
                    child: SizedBox(
                      height: 28,
                      child: Slider(
                        value: manualVolume,
                        onChanged: session.manualVolumeEffective
                            ? (v) =>
                                session.setManualVolume(v, commit: false)
                            : null,
                        onChangeEnd: session.manualVolumeEffective
                            ? (v) => session.setManualVolume(v)
                            : null,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      Strings.percentLabel((manualVolume * 100).round()),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: session.manualVolumeEffective
                                ? cs.onSurfaceVariant
                                : cs.onSurfaceVariant
                                    .withValues(alpha: 0.4),
                          ),
                    ),
                  ),
                ],
              ),
              // 智能耳（实验）：开关 + 分析状态（会话开着才显示）。
              if (enabled)
                Row(
                  children: [
                    Tooltip(
                      message: Strings.translationSmartEarDesc,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            Strings.translationSmartEarLabel,
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: session.smartEar
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                    ),
                          ),
                          Switch.adaptive(
                            value: session.smartEar,
                            onChanged: (v) => session.setSmartEar(v),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        session.smartEar
                            ? _smartStatusLabel(session.smartStatus)
                            : '',
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: _smartStatusColor(
                                session.smartStatus,
                                cs,
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

