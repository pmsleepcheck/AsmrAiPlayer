import 'package:flutter/material.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';

/// 主耳无法自动判定时弹窗：用户选 左耳 / 右耳。
/// 返回 null = 取消（调用方中止翻译播放）。
Future<EarSide?> showEarSidePromptDialog(BuildContext context) {
  return showDialog<EarSide>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(Strings.earPromptTitle),
      content: const Text(Strings.earPromptBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(Strings.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, EarSide.left),
          child: const Text(Strings.earPromptLeft),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, EarSide.right),
          child: const Text(Strings.earPromptRight),
        ),
      ],
    ),
  );
}
