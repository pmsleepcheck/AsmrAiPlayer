import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

/// 播放页「字幕开关 + 三模式切换」。无论封面/歌词视图均常显（bug.txt 3）。
class SubtitleModeControls extends StatelessWidget {
  const SubtitleModeControls({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = GetIt.I<AppSettingsService>();
    final cs = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final mode = settings.subtitleDisplayMode;
        final on = mode != SubtitleDisplayMode.off;

        String modeLabel(SubtitleDisplayMode m) => switch (m) {
              SubtitleDisplayMode.off => Strings.subtitleModeOff,
              SubtitleDisplayMode.inApp => Strings.subtitleModeInApp,
              SubtitleDisplayMode.popup => Strings.subtitleModePopup,
            };

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Row(
            children: [
              Tooltip(
                message: on
                    ? Strings.subtitleToggleOff
                    : Strings.subtitleToggleOn,
                child: IconButton(
                  iconSize: 24,
                  icon: Icon(
                    on ? Icons.subtitles : Icons.subtitles_outlined,
                    color: on ? cs.primary : cs.onSurfaceVariant,
                  ),
                  onPressed: () {
                    settings.setSubtitleDisplayMode(
                      on
                          ? SubtitleDisplayMode.off
                          : AppSettingsService.defaultSubtitleDisplayMode,
                    );
                  },
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: DropdownButtonFormField<SubtitleDisplayMode>(
                  value: mode,
                  isDense: true,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: cs.onSurface,
                      ),
                  items: [
                    for (final m in SubtitleDisplayMode.values)
                      DropdownMenuItem(
                        value: m,
                        child: Text(
                          modeLabel(m),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                  onChanged: (m) {
                    if (m != null) settings.setSubtitleDisplayMode(m);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
