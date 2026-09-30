import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/utils/logger.dart';

/// 同声传译真左右耳声道路由（Windows/Linux · media_kit/mpv `af`）。
///
/// - 会话开启：主轨 pan 到 [EarSide]（mainEar）、翻译轨 pan 到对侧；
///   滤镜先 `aformat` 强制立体声再 `pan` downmix 到单耳（不丢内容）。
/// - 会话关闭 / `mainEar == null`：清 `af`，恢复全立体声。
/// - 非 media_kit 后端（Android/iOS 原生 just_audio 无 pan API）：no-op，
///   维持 `TranslationMixState` 音量 emphasis 混播降级。
///
/// 角色认领：`expectMainPlayer` / `expectTtsPlayer` 必须在对应
/// `AudioPlayer()` 构造前调用（见 fork 内 expect 队列注释）。
class EarChannelRouter {
  EarChannelRouter._();

  /// mpv `af`：单耳输出（内容 downmix 到 side，对侧静音）。
  static String filterFor(EarSide side) {
    // pan 表达式用 `FL<增益*cN` 经典语法：`c0=...` 赋值语法在所集成的
    // ffmpeg（zhongfly 完整版 mpv）上被实测拒绝（"Expected in channel
    // name"），而 `FL<0.5*c0+0.5*c1` 两端均验证通过（见 ao=pcm 输出
    // 波形分析）。先 aformat 保证 mono/多声道都能进 pan。
    final expr = side == EarSide.left
        ? 'stereo|FL<0.5*c0+0.5*c1|FR<0*c0'
        : 'stereo|FL<0*c0|FR<0.5*c0+0.5*c1';
    return 'lavfi=[aformat=channel_layouts=stereo,pan=$expr]';
  }

  static bool get _supported =>
      JustAudioPlatform.instance is JustAudioMediaKit;

  /// 主轨 AudioPlayer 构造前认领（仅 media_kit 平台）。
  static void expectMainPlayer() {
    if (_supported) JustAudioMediaKit.expectMainPlayer();
  }

  /// 翻译轨 AudioPlayer 构造前认领。
  static void expectTtsPlayer() {
    if (_supported) JustAudioMediaKit.expectTtsPlayer();
  }

  /// 应用（或清除）分耳路由。
  ///
  /// - `mainEar`：主轨 pan 目标；null = 主轨保持原始立体声（清 `af`）。
  /// - `ttsEar`：翻译轨 pan 目标；省略时取 `mainEar.flipped`（固定分耳
  ///   的老行为），两者都为 null = 双轨清 `af`。
  /// - 智能耳（实验）只推 `ttsEar`（`mainEar: null`）：主轨不动，翻译
  ///   逐句落在内容的对侧。
  static Future<void> apply({EarSide? mainEar, EarSide? ttsEar}) async {
    if (!_supported) return;
    final tts = ttsEar ?? mainEar?.flipped;
    try {
      await JustAudioMediaKit.setRoleAudioFilter(
        JustAudioMediaKit.roleMain,
        mainEar == null ? null : filterFor(mainEar),
      );
      await JustAudioMediaKit.setRoleAudioFilter(
        JustAudioMediaKit.roleTts,
        tts == null ? null : filterFor(tts),
      );
    } catch (e) {
      AppLogger.warning('声道隔离设置失败: $e');
    }
  }
}
