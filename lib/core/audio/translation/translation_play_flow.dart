import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/ear_side_detector.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/translation_session_controller.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/widgets/translation/ear_side_prompt_dialog.dart';

/// 列表「翻译+播放」入口编排：查 Key → 耳侧检测（含弹窗）→ 开会话。
/// 返回 true 表示会话已就绪，调用方继续走原播放路径。
class TranslationPlayFlow {
  static Future<bool> prepareSession({
    required BuildContext context,
    required Child file,
    required List<String> keys,
    Future<String?> Function(Child file)? resolveLocalPath,
  }) async {
    if (!context.mounted) return false;
    final messenger = ScaffoldMessenger.of(context);

    final config = GetIt.I<FishTtsConfigStore>();
    final key = await config.loadApiKey();
    if (key == null || key.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(
        content: Text(Strings.translationRequiresApiKey),
      ));
      return false;
    }

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
          messenger.showSnackBar(const SnackBar(
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
