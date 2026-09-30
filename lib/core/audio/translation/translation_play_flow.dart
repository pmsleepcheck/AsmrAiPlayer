import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/ear_side_detector.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/supertonic_tts_service.dart';
import 'package:aaplay/core/audio/translation/translation_session_controller.dart';
import 'package:aaplay/core/audio/translation/tts_synthesizer.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/widgets/translation/ear_side_prompt_dialog.dart';

/// 列表「翻译+播放」入口编排：TTS 引擎就绪检查 → 耳侧检测（含弹窗）→ 开会话。
/// 返回 true 表示会话已就绪，调用方继续走原播放路径。
class TranslationPlayFlow {
  /// 引擎就绪检查（列表入口与播放页开关共用）：
  ///
  /// - fish → 必须已配 API Key；
  /// - supertonic（默认）→ `GET /v1/health` 本地服务必须在跑。
  ///
  /// 不就绪时弹出可执行的 SnackBar（带「启动服务」动作，成功后回调 [onReady]
  /// 接着走原流程），返回 false。
  static Future<bool> ensureTtsReady(
    BuildContext context, {
    required Future<void> Function()? onReady,
  }) async {
    if (!context.mounted) return false;
    final config = GetIt.I<FishTtsConfigStore>();
    if (config.ttsSource == TtsSource.fish) {
      final key = await config.loadApiKey();
      if (key == null || key.trim().isEmpty) {
        if (!context.mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(Strings.translationRequiresApiKey),
        ));
        return false;
      }
      return true;
    }

    final supertonic = GetIt.I<SupertonicTtsService>();
    if (await supertonic.isHealthy()) return true;
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text(Strings.translationTtsServiceOffline),
      action: SnackBarAction(
        label: Strings.supertonicStart,
        onPressed: () async {
          final status = await supertonic.startServer();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_launchMessage(status)),
          ));
          if (status == SupertonicLaunchStatus.started ||
              status == SupertonicLaunchStatus.alreadyRunning) {
            await onReady?.call();
          }
        },
      ),
    ));
    return false;
  }

  static String _launchMessage(SupertonicLaunchStatus status) =>
      switch (status) {
        SupertonicLaunchStatus.alreadyRunning =>
          Strings.supertonicLaunchAlreadyRunning,
        SupertonicLaunchStatus.started => Strings.supertonicLaunchStarted,
        SupertonicLaunchStatus.starting => Strings.supertonicLaunchStarting,
        SupertonicLaunchStatus.unsupported =>
          Strings.supertonicLaunchUnsupported,
        SupertonicLaunchStatus.notFound => Strings.supertonicLaunchNotFound,
        SupertonicLaunchStatus.failed => Strings.supertonicLaunchFailed,
      };

  static Future<bool> prepareSession({
    required BuildContext context,
    required Child file,
    required List<String> keys,
    Future<String?> Function(Child file)? resolveLocalPath,
  }) async {
    if (!context.mounted) return false;

    final ready = await ensureTtsReady(
      context,
      // 服务被 SnackBar 动作拉起后，从头再走一遍（健康检查此时已通过）。
      onReady: () => prepareSession(
        context: context,
        file: file,
        keys: keys,
        resolveLocalPath: resolveLocalPath,
      ),
    );
    if (!ready) return false;
    if (!context.mounted) return false;

    final detector = GetIt.I<EarSideDetector>();
    final result = await detector.detect(
      file,
      keys: keys,
      resolveLocalPath: resolveLocalPath,
    );
    EarSide? side = result.side;
    if (side == null) {
      if (!context.mounted) return false;
      side = await showEarSidePromptDialog(context);
      if (side == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(Strings.earDetectCancelled),
            duration: Duration(seconds: 1),
          ));
        }
        return false;
      }
      await detector.persistChoice(file, side, keys: keys);
    }

    await GetIt.I<TranslationSessionController>().beginSession(side);
    return true;
  }

  /// 普通播放入口：关掉翻译会话，保持旧行为。
  static Future<void> prepareNormalPlay() async {
    try {
      await GetIt.I<TranslationSessionController>().endSession();
    } catch (_) {
      // DI 未就绪（单测）时忽略。
    }
  }
}
