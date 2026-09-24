import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';
import 'package:aaplay/core/subtitle/i_subtitle_service.dart';
import 'package:aaplay/core/audio/models/subtitle.dart';

/// 播放页应用内字幕条：
/// - [SubtitleDisplayMode.inApp]：贴在内容区底部的常规字幕条。
/// - [SubtitleDisplayMode.popup]：Windows 等无系统悬浮平台的降级形态——
///   半透明底、白字描边（Win 常见字幕样式），仍在 app 窗口内。
/// - [SubtitleDisplayMode.off]：不渲染。
///
/// Android 真弹窗仍由 `LyricOverlayManager` 系统悬浮负责；本组件在
/// `popup` 模式下也会显示（保证任意平台都有可见反馈）。
class SubtitleCaptionBand extends StatelessWidget {
  const SubtitleCaptionBand({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = GetIt.I<AppSettingsService>();
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final mode = settings.subtitleDisplayMode;
        if (mode == SubtitleDisplayMode.off) {
          return const SizedBox.shrink();
        }
        return _BandBody(mode: mode);
      },
    );
  }
}

class _BandBody extends StatelessWidget {
  const _BandBody({required this.mode});

  final SubtitleDisplayMode mode;

  @override
  Widget build(BuildContext context) {
    final subtitleService = GetIt.I<ISubtitleService>();
    final isPopup = mode == SubtitleDisplayMode.popup;

    return StreamBuilder<Subtitle?>(
      stream: subtitleService.currentSubtitleStream,
      initialData: subtitleService.currentSubtitle,
      builder: (context, snapshot) {
        final text = snapshot.data?.text.trim();
        if (text == null || text.isEmpty) {
          return const SizedBox(height: 0);
        }
        final theme = Theme.of(context);
        final cs = theme.colorScheme;

        return SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            decoration: isPopup
                ? BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(4),
                  )
                : BoxDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(8),
                  ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: isPopup
                  ? theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      shadows: const [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 2,
                          offset: Offset(1, 1),
                        ),
                      ],
                    )
                  : theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface),
            ),
          ),
        );
      },
    );
  }
}
