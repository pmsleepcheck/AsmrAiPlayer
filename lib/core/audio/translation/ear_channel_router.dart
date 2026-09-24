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
    // pan 表达式引用输入 c0/c1；先 aformat 保证 mono/多声道都能进 pan。
    final expr = side == EarSide.left
        ? 'stereo|c0=0.5*c0+0.5*c1|c1=0'
        : 'stereo|c0=0|c1=0.5*c0+0.5*c1';
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

  /// 应用（或清除）分耳路由。[mainEar] 为 null = 清 `af`。
  static Future<void> apply(EarSide? mainEar) async {
    if (!_supported) return;
    try {
      if (mainEar == null) {
        await JustAudioMediaKit.setRoleAudioFilter(
            JustAudioMediaKit.roleMain, null);
        await JustAudioMediaKit.setRoleAudioFilter(
            JustAudioMediaKit.roleTts, null);
        return;
      }
      await JustAudioMediaKit.setRoleAudioFilter(
        JustAudioMediaKit.roleMain,
        filterFor(mainEar),
      );
      await JustAudioMediaKit.setRoleAudioFilter(
        JustAudioMediaKit.roleTts,
        filterFor(mainEar.flipped),
      );
    } catch (e) {
      AppLogger.warning('声道隔离设置失败: $e');
    }
  }
}
