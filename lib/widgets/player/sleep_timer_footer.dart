import 'package:flutter/material.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/platform/sleep_timer_controller.dart';
import 'package:aaplay/core/theme/app_spacing.dart';
import 'package:aaplay/core/theme/app_text_styles.dart';
import 'package:aaplay/screens/settings/sleep_timer_dialog.dart';

/// 播放页底部「睡眠倒计时」行（分隔线 + 图标 + 倒计时文案 + 修改入口）。
///
/// **整行可点**（bug.txt 2026-09-28 ③）：原实现只有右侧「修改」文案是热区，戳图标 /
/// 倒计时文本都没反应。整行包一个 `InkWell` 打开同一个 `SleepTimerDialog`，
/// 视觉（配色/字号/分隔线）保持原样。
class PlayerSleepTimerFooter extends StatelessWidget {
  const PlayerSleepTimerFooter({super.key, required this.sleepTimer});

  final SleepTimerController sleepTimer;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sleepTimer,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final minutes = sleepTimer.minutes;
        return Column(
          children: [
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.space24,
                AppSpacing.space16,
                AppSpacing.space24,
                0,
              ),
              child: InkWell(
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => SleepTimerDialog(controller: sleepTimer),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.space4),
                  child: Row(
                    children: [
                      Icon(Icons.bedtime_outlined,
                          size: 18, color: cs.primary),
                      const SizedBox(width: AppSpacing.space8),
                      Expanded(
                        child: Text(
                          minutes != null
                              ? Strings.playerSleepTimerActive(
                                  sleepTimer.remaining,
                                )
                              : Strings.playerSleepTimerInactive,
                          style: AppTextStyles.labelMedium
                              .copyWith(color: cs.onSurface),
                        ),
                      ),
                      Text(
                        Strings.playerSleepTimerChange,
                        style: AppTextStyles.labelMedium
                            .copyWith(color: cs.primary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
