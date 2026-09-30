import 'dart:math' as math;

import 'package:aaplay/core/platform/lyric_overlay_manager.dart';
import 'package:aaplay/core/theme/app_animations.dart';
import 'package:aaplay/core/theme/app_radius.dart';
import 'package:aaplay/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/core/audio/models/playback_context.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/presentation/viewmodels/player_viewmodel.dart';
import 'package:aaplay/core/theme/app_spacing.dart';
import 'package:aaplay/widgets/player/player_controls.dart';
import 'package:aaplay/widgets/player/sleep_timer_footer.dart';
import 'package:aaplay/widgets/player/translation_controls.dart';
import 'package:aaplay/widgets/player/subtitle_mode_controls.dart';
import 'package:aaplay/widgets/player/subtitle_caption_band.dart';
import 'package:aaplay/widgets/player/waveform_progress.dart';
import 'package:aaplay/widgets/player/square_cover.dart';
import 'package:aaplay/screens/detail_screen.dart';
import 'package:aaplay/widgets/lyrics/components/player_lyric_view.dart';
import 'package:aaplay/widgets/player/player_work_info.dart';
import 'package:aaplay/core/platform/wakelock_controller.dart';
import 'package:aaplay/core/platform/sleep_timer_controller.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';
import 'package:aaplay/screens/settings/sleep_timer_dialog.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/subtitle/subtitle_import_service.dart';
import 'package:aaplay/widgets/detail/subtitle_pick_dialog.dart';

/// 播放页封面边长（纯函数，供测试锁定）。
///
/// 封面按宽度取正方形，在小屏安卓上「封面 + 曲名 + 作品信息」的自然高度会
/// 超过封面区可用高度 → `RenderFlex` 溢出且不裁剪，子节点直接画到底部控件上
/// （bug.txt 2026-09-28 ①「糊到一起/各种叠在一起」）。这里按**可用高度减去固定信息预算**
/// 收缩封面，配合外层的滚动容器做到「任何屏高都不重叠」。
///
/// - 左右各 `AppSpacing.space32` 内边距 → 宽度上限减 64。
/// - 高度预算：上下间距 64 + 曲名两行 64 + 作品信息 44（+ kicker 行 24）。
/// - 估算偏小只会让封面多留白（仍然滚动兜底），偏大则曲名区进入滚动 —— 两者
///   都不会重叠。
@visibleForTesting
double playerCoverSideFor({
  required double availableWidth,
  required double availableHeight,
  bool hasKicker = true,
  double maxSide = 320,
}) {
  const double horizontalPadding = 64;
  const double minSide = 120;
  final double kickerHeight = hasKicker ? 24 : 0;
  // 上/下间距 + kicker + 曲名(2 行) + 作品信息（marquee 行 + 声优行 + 内边距）。
  const double chrome = 64 + 64 + 44;
  final double widthLimit = availableWidth - horizontalPadding;
  if (!widthLimit.isFinite || widthLimit <= 0) return 0;
  final double heightLimit = availableHeight - chrome - kickerHeight;
  // 高度不足时保底 120（宁可滚动也不把封面压没），但绝不超宽。
  final double desired = math.max(heightLimit, minSide);
  return math.min(math.min(widthLimit, desired), maxSide);
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _LyricOverlayAction extends StatefulWidget {
  const _LyricOverlayAction({required this.manager});

  final LyricOverlayManager manager;

  @override
  State<_LyricOverlayAction> createState() => _LyricOverlayActionState();
}

class _LyricOverlayActionState extends State<_LyricOverlayAction> {
  Future<void> _onTap() async {
    await widget.manager.toggle(context);
    if (mounted) setState(() {});
  }

  Future<void> _onLongPress() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!widget.manager.isShowing) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(Strings.lyricOverlayEnterFirstHint),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await widget.manager.toggleEditable();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(widget.manager.isEditable
            ? Strings.lyricOverlayEditEntered
            : Strings.lyricOverlayEditExited),
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;
    if (!manager.isSupported) {
      // Windows 等无系统悬浮能力：入口不显示（改由播放页字幕条负责）。
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final iconColor = manager.isEditable ? theme.colorScheme.primary : null;
    final tooltipMsg = manager.isShowing
        ? (manager.isEditable
            ? Strings.lyricOverlayTooltipExitEdit
            : Strings.lyricOverlayTooltipLongPressHint)
        : Strings.lyricOverlayTooltipEnable;
    return Tooltip(
      message: tooltipMsg,
      child: InkResponse(
        radius: 24,
        onTap: _onTap,
        onLongPress: _onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space12),
          child: Icon(
            manager.isShowing ? Icons.lyrics : Icons.lyrics_outlined,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}

/// 顶栏右侧「在线 / 本地」角标：按下载表判定当前曲目是否已离线可用。
/// 拿不到判定结果（未在播放 / 查询异常）时不渲染任何东西——不能写死成
/// 「在线」，那会在下载表查询失败时给用户一个错误的离线状态承诺。
class _DownloadStatusBadge extends StatefulWidget {
  const _DownloadStatusBadge({required this.context});

  final PlaybackContext? context;

  @override
  State<_DownloadStatusBadge> createState() => _DownloadStatusBadgeState();
}

class _DownloadStatusBadgeState extends State<_DownloadStatusBadge> {
  bool? _isLocal;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _DownloadStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.context?.currentFile != widget.context?.currentFile ||
        oldWidget.context?.work.id != widget.context?.work.id) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final ctx = widget.context;
    final workId = ctx?.work.id?.toString();
    if (ctx == null || workId == null) {
      if (mounted) setState(() => _isLocal = null);
      return;
    }
    try {
      final path = await GetIt.I<DownloadService>()
          .localPathIfDownloaded(workId, ctx.currentFile);
      if (!mounted) return;
      setState(() => _isLocal = path != null);
    } catch (_) {
      // 下载表查询失败：宁可不显示角标，也不能误导用户「在线」。
      if (mounted) setState(() => _isLocal = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocal == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space8,
        vertical: AppSpacing.space4,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant, width: 1),
        borderRadius: AppRadius.smAll,
      ),
      child: Text(
        _isLocal! ? Strings.playerLocal : Strings.playerOnline,
        style: AppTextStyles.labelMedium.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _PlayerScreenState extends State<PlayerScreen> {
  bool _showLyrics = false;
  bool _canSwitchView = true;
  late final PlayerViewModel _viewModel;
  late final AppSettingsService _settings;
  SubtitleDisplayMode? _lastSubtitleMode;

  @override
  void initState() {
    super.initState();
    _viewModel = GetIt.I<PlayerViewModel>();
    _settings = GetIt.I<AppSettingsService>();
    _lastSubtitleMode = _settings.subtitleDisplayMode;
    _settings.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncOverlay(initial: true);
    });
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    if (_settings.subtitleDisplayMode == _lastSubtitleMode) return;
    _lastSubtitleMode = _settings.subtitleDisplayMode;
    _syncOverlay(initial: false);
  }

  /// 字幕模式 → 系统悬浮字幕同步：
  /// - `popup` + 平台支持 → 已授权则 show；未授权仅在用户主动切换时请求。
  /// - 离开 `popup` → hide。
  /// Windows 等无能力平台直接返回（字幕条负责可见反馈）。
  void _syncOverlay({required bool initial}) {
    final manager = GetIt.I<LyricOverlayManager>();
    if (!manager.isSupported) return;
    final mode = _settings.subtitleDisplayMode;
    if (mode == SubtitleDisplayMode.popup) {
      manager.checkPermission().then((granted) {
        if (!mounted || _settings.subtitleDisplayMode != mode) return;
        if (granted) {
          manager.show().ignore();
        } else if (!initial) {
          manager.showWithPermissionCheck(context).ignore();
        }
      }).ignore();
    } else if (manager.isShowing) {
      manager.hide().ignore();
    }
  }

  Widget _buildContent() {
    return AnimatedSwitcher(
      duration: AppAnimations.long,
      switchInCurve: AppAnimations.smoothScroll,
      switchOutCurve: AppAnimations.exit,
      transitionBuilder: (Widget child, Animation<double> animation) {
        final isLyrics = (child as dynamic).key == const ValueKey('lyrics');

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, isLyrics ? 0.1 : -0.1),
              end: Offset.zero,
            ).animate(animation),
            child: ScaleTransition(
              scale: Tween<double>(
                begin: 0.95,
                end: 1.0,
              ).animate(animation),
              child: child,
            ),
          ),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: _showLyrics
          ? LayoutBuilder(
              key: const ValueKey('lyrics'),
              builder: (context, constraints) {
                return PlayerLyricView(
                  onScrollStateChanged: (canSwitch) {
                    setState(() {
                      _canSwitchView = canSwitch;
                    });
                  },
                );
              },
            )
          : LayoutBuilder(
              key: const ValueKey('cover'),
              builder: (context, constraints) {
                final double availableHeight = constraints.maxHeight;
                final double availableWidth = constraints.maxWidth;
                return ListenableBuilder(
                  listenable: _viewModel,
                  builder: (context, _) {
                    final cs = Theme.of(context).colorScheme;
                    final trackInfo = _viewModel.currentTrackInfo;
                    final kicker = trackInfo?.artist ?? '';
                    final double coverSide = playerCoverSideFor(
                      availableWidth: availableWidth,
                      availableHeight: availableHeight,
                      hasKicker: kicker.isNotEmpty,
                    );
                    // 滚动容器内高度无界 → Column 必须 mainAxisSize.min，
                    // 且不能再用 Spacer（flex 子项在无界高度下会抛错）。
                    // 内容放不下时整体滚动，绝不画到下方控件上（bug.txt 2026-09-28 ①）。
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: availableHeight),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: AppSpacing.space32),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.space32),
                              child: Hero(
                                tag: 'mini-player-cover',
                                child: SizedBox.square(
                                  dimension: coverSide,
                                  child: SquareCover(
                                    coverUrl: trackInfo?.coverUrl,
                                    maxSize: coverSide,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space32),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.space32),
                              child: Column(
                                children: [
                                  // kicker：社团名，Modernist 三段式曲目信息
                                  // （kicker/曲名/副标）的第一段，accent 色。
                                  if (kicker.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          bottom: AppSpacing.space8),
                                      child: Text(
                                        kicker,
                                        style: AppTextStyles.labelMedium
                                            .copyWith(color: cs.primary),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  Hero(
                                    tag: 'player-title',
                                    child: Material(
                                      color: Colors.transparent,
                                      child: Text(
                                        trackInfo?.title ?? Strings.notPlaying,
                                        style: AppTextStyles.headlineMedium
                                            .copyWith(color: cs.onSurface),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.space24),
                            PlayerWorkInfo(
                                context: _viewModel.currentContext),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lyricManager = GetIt.I<LyricOverlayManager>();
    final wakeLockController = GetIt.I<WakeLockController>();
    final sleepTimer = GetIt.I<SleepTimerController>();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.expand_more),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          Strings.nowPlaying.toUpperCase(),
          style: AppTextStyles.labelMedium
              .copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
        ),
        actions: [
          ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) =>
                _DownloadStatusBadge(context: _viewModel.currentContext),
          ),
          ListenableBuilder(
            listenable: sleepTimer,
            builder: (context, _) {
              return IconButton(
                icon: Icon(
                  sleepTimer.isActive ? Icons.bedtime : Icons.bedtime_outlined,
                  color: sleepTimer.isActive
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                tooltip: Strings.sleepTimer,
                onPressed: () => showDialog(
                  context: context,
                  builder: (_) => SleepTimerDialog(controller: sleepTimer),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              final currentWork = _viewModel.currentContext?.work;
              if (currentWork != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => DetailScreen(
                      work: currentWork,
                      fromPlayer: true,
                    ),
                  ),
                );
              }
            },
          ),
          // Subtitle import menu
          ListenableBuilder(
            listenable: _viewModel,
            builder: (context, _) {
              return PopupMenuButton<String>(
                icon: Icon(
                  Icons.subtitles,
                  color: _viewModel.isUserImportedSubtitle
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onSelected: (value) async {
                  if (value == 'import') {
                    final result = await _viewModel.importSubtitle();
                    if (!context.mounted) return;
                    final message = switch (result) {
                      ImportResult.success => Strings.importSuccess,
                      ImportResult.cancelled => null,
                      ImportResult.invalidFormat => Strings.importInvalidFormat,
                      ImportResult.fileTooLarge => Strings.importFileTooLarge,
                      ImportResult.parseFailed => Strings.importParseFailed,
                      ImportResult.ioError => Strings.importIoError,
                    };
                    if (message != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(message)),
                      );
                    }
                  } else if (value == 'remove') {
                    await _viewModel.removeImportedSubtitle();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text(Strings.subtitleRemoved)),
                    );
                  } else if (value == 'pick') {
                    final playbackContext = _viewModel.currentContext;
                    final audio = playbackContext?.currentFile;
                    final files = playbackContext?.files;
                    if (audio == null || files == null) return;
                    final sub = await showSubtitlePickDialog(
                      context,
                      audio: audio,
                      files: files,
                    );
                    if (sub == null || !context.mounted) return;
                    final ok =
                        await _viewModel.assignSubtitleFromAlbum(sub);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(ok
                          ? '${Strings.subtitleMatchedToast}${sub.title ?? ''}'
                          : Strings.subtitleMatchRecordFailed),
                    ));
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'pick',
                    child: Text(Strings.pickSubtitleFromAlbum),
                  ),
                  const PopupMenuItem(
                    value: 'import',
                    child: Text(Strings.importSubtitle),
                  ),
                  if (_viewModel.isUserImportedSubtitle)
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text(Strings.removeImportedSubtitle),
                    ),
                ],
              );
            },
          ),
          _LyricOverlayAction(manager: lyricManager),
          ListenableBuilder(
            listenable: wakeLockController,
            builder: (context, _) {
              return IconButton(
                icon: Icon(
                  wakeLockController.enabled
                      ? Icons.lightbulb
                      : Icons.lightbulb_outline,
                ),
                tooltip: wakeLockController.enabled
                    ? Strings.screenAwakeOff
                    : Strings.screenAwakeOn,
                onPressed: () => wakeLockController.toggle(),
              );
            },
          ),
        ],
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        // 布局不变量（bug.txt 2026-09-28 ①）：非 flex 子项拿到的是**无界**主轴约束，
        // 所以可用高度必须在 Column 外层取。底部控件封顶 55%，放不下时自身
        // 滚动；封面区（Expanded）拿剩余空间，内容高于可用高度时滚动 ——
        // 两块各自裁剪，任何屏高都不会再溢出互相压叠。
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double bodyHeight = constraints.maxHeight;
            return Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      if (_canSwitchView) {
                        setState(() {
                          _showLyrics = !_showLyrics;
                        });
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Stack(
                      children: [
                        _buildContent(),
                        // 应用内字幕条：封面/歌词视图下均贴底显示（模式由设置驱动）。
                        const Positioned(
                          left: 16,
                          right: 16,
                          bottom: 8,
                          child: SubtitleCaptionBand(),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.space32),
                  // `SingleChildScrollView` 在 0..maxHeight 约束下是收缩布局
                  // （放得下 = 自然高度，不占多余空间），所以上限只在真的
                  // 放不下时才生效。
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: bodyHeight * 0.55,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const WaveformProgress(),
                          const SizedBox(height: AppSpacing.space8),
                          // 字幕开关 + 模式切换：任何播放方式下常显（bug.txt 3）。
                          const SubtitleModeControls(),
                          const TranslationControls(),
                          const SizedBox(height: AppSpacing.space8),
                          const PlayerControls(),
                          const SizedBox(height: AppSpacing.space20),
                          PlayerSleepTimerFooter(sleepTimer: sleepTimer),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
