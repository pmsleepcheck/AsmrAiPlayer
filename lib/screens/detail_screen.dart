import 'package:aaplay/core/theme/app_animations.dart';
import 'package:aaplay/widgets/mini_player/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/widgets/detail/work_cover.dart';
import 'package:aaplay/widgets/detail/work_info.dart';
import 'package:aaplay/widgets/detail/work_files_list.dart';
import 'package:aaplay/widgets/detail/work_files_skeleton.dart';
import 'package:aaplay/presentation/viewmodels/detail_viewmodel.dart';
import 'package:aaplay/widgets/detail/work_action_buttons.dart';
import 'package:aaplay/widgets/detail/media_download_dialog.dart';
import 'package:aaplay/widgets/detail/batch_download_dialog.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/screens/similar_works_screen.dart';
import 'package:aaplay/screens/subtitle_preview_screen.dart';
import 'package:aaplay/screens/download_management_screen.dart';
import 'package:aaplay/utils/logger.dart';
import 'package:open_filex/open_filex.dart';

class DetailScreen extends StatelessWidget {
  final Work work;
  final bool fromPlayer;

  const DetailScreen({
    super.key,
    required this.work,
    this.fromPlayer = false,
  });

  /// 入队 Snackbar：提示 +「查看」跳转下载管理。
  static void _showQueuedSnackBar(BuildContext context, int count) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(
      content: Text(
        count <= 1
            ? Strings.downloadQueued
            : Strings.downloadQueuedCount(count),
      ),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: Strings.downloadViewQueue,
        onPressed: () {
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => const DownloadManagementScreen(),
            ),
          );
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DetailViewModel(
        work: work,
      )..loadInitialData(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(work.sourceId ?? ''),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: MiniPlayer.height),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WorkCover(
                imageUrl: work.mainCoverUrl ?? '',
                workId: work.id ?? 0,
                sourceId: work.sourceId ?? '',
                releaseDate: work.release,
                heroTag: 'work-cover-${work.id}',
              ),
              Consumer<DetailViewModel>(
                builder: (context, viewModel, _) => WorkInfo(
                  work: work,
                  workInfo: viewModel.workInfo,
                ),
              ),
              Consumer<DetailViewModel>(
                builder: (context, viewModel, _) => WorkActionButtons(
                  hasRecommendations: viewModel.hasRecommendations,
                  checkingRecommendations: viewModel.checkingRecommendations,
                  onRecommendationsTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            SimilarWorksScreen(work: work),
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                          const begin = Offset(1.0, 0.0);
                          const end = Offset.zero;
                          const curve = AppAnimations.standard;
                          var tween = Tween(begin: begin, end: end).chain(
                            CurveTween(curve: curve),
                          );
                          return SlideTransition(
                            position: animation.drive(tween),
                            child: child,
                          );
                        },
                      ),
                    );
                  },
                  onFavoriteTap: () => viewModel.showPlaylistsDialog(context),
                  loadingFavorite: viewModel.loadingFavorite,
                  onMarkTap: () => viewModel.showMarkDialog(context),
                  currentMarkStatus: viewModel.currentMarkStatus,
                  loadingMark: viewModel.loadingMark,
                ),
              ),
              Consumer<DetailViewModel>(
                builder: (context, viewModel, _) {
                  if (viewModel.isLoading) {
                    return const WorkFilesSkeleton();
                  }

                  if (viewModel.error != null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              viewModel.error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () => viewModel.loadFiles(),
                              child: const Text(Strings.retry),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (viewModel.files != null) {
                    // 确认弹窗 → 后台队列（入队即返回）→ Snackbar 引导下载管理。
                    // 视频 [openOnDone]=true 仍阻塞下载（完成立刻打开），
                    // 不走队列；音频离线/批量入队后台执行。
                    Future<void> runDownload(
                      Child file, {
                      required bool openOnDone,
                      required String title,
                      required String prompt,
                    }) async {
                      if (openOnDone) {
                        // 视频：保持阻塞弹窗，下载完成即用外部查看器打开。
                        final result = await showDialog<DownloadResult>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => MediaDownloadDialog(
                            fileName: file.title ?? '',
                            titleText: title,
                            promptText: prompt,
                            download: (ct, onP) => viewModel.downloadFile(
                              file,
                              cancelToken: ct,
                              onProgress: onP,
                            ),
                          ),
                        );
                        if (result == null || !context.mounted) return;
                        final messenger = ScaffoldMessenger.of(context);
                        if (result.isPlayable && result.localPath != null) {
                          final open =
                              await OpenFilex.open(result.localPath!);
                          AppLogger.info(
                              'OpenFilex 视频: type=${open.type} path=${result.localPath}');
                          if (open.type != ResultType.done) {
                            final path = result.localPath!;
                            final dir = path.replaceAll(RegExp(r'[^/\\]+$'), '');
                            messenger.showSnackBar(SnackBar(
                              content: const Text(Strings.downloadOpenFailed),
                              behavior: SnackBarBehavior.floating,
                              action: SnackBarAction(
                                label: Strings.openFolder,
                                onPressed: () => OpenFilex.open(dir),
                              ),
                            ));
                          }
                        } else if (result.status ==
                            DownloadStatus.cancelled) {
                          messenger.showSnackBar(const SnackBar(
                            content: Text(Strings.downloadCancelled),
                          ));
                        } else if (result.status ==
                            DownloadStatus.networkError) {
                          messenger.showSnackBar(const SnackBar(
                            content: Text(Strings.downloadNetworkError),
                          ));
                        } else {
                          messenger.showSnackBar(const SnackBar(
                            content: Text(Strings.downloadIoError),
                          ));
                        }
                        return;
                      }
                      // 音频：入后台队列 + Snackbar（带「查看」跳下载管理）。
                      viewModel.enqueueFile(file);
                      if (!context.mounted) return;
                      _showQueuedSnackBar(context, 1);
                    }

                    Future<void> runBatch(Child? folderNode) async {
                      final outcome = await showDialog<BatchDownloadOutcome>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => BatchDownloadDialog(
                          audioCount: viewModel.batchAudioCount(folderNode),
                          download: () async {
                            final n = viewModel.enqueueFolder(folderNode);
                            return BatchDownloadOutcome(
                              ok: n,
                              skipped: 0,
                              failed: 0,
                              cancelled: false,
                            );
                          },
                        ),
                      );
                      if (outcome == null || !context.mounted) return;
                      if (outcome.ok > 0) {
                        _showQueuedSnackBar(context, outcome.ok);
                      }
                    }

                    /// 点击文件：视频已下载 → 直接开本地；否则走下载弹窗。
                    /// 音频进播放管线；字幕预览。外层 try/catch 保证任何
                    /// 平台异常（OpenFilex 等）都有 SnackBar，不会静默无反应。
                    Future<void> handleFileTap(Child file) async {
                      try {
                        if (viewModel.isVideoFile(file)) {
                          final local =
                              await viewModel.localPathIfDownloaded(file);
                          if (local != null && context.mounted) {
                            final open = await OpenFilex.open(local);
                            AppLogger.info(
                                'OpenFilex 本地视频: type=${open.type} path=$local');
                            if (open.type != ResultType.done &&
                                context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(Strings.downloadOpenFailed)),
                              );
                            }
                            return;
                          }
                          await runDownload(
                            file,
                            openOnDone: true,
                            title: Strings.videoNeedsDownloadTitle,
                            prompt: Strings.videoNeedsDownloadPrompt,
                          );
                          return;
                        }
                        if (viewModel.isAudioFile(file)) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(const SnackBar(
                                content: Text(Strings.playStarting),
                                duration: Duration(seconds: 1),
                              ));
                          }
                          await viewModel.playFile(file, context);
                          return;
                        }
                        if (viewModel.isSubtitleFile(file)) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SubtitlePreviewScreen(
                                workId: work.id?.toString(),
                                file: file,
                              ),
                            ),
                          );
                          return;
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(Strings.unsupportedFileType),
                            ),
                          );
                        }
                      } catch (e) {
                        AppLogger.error('文件点击失败: ${file.title}', e);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(Strings.playFailed(e))),
                          );
                        }
                      }
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (viewModel.usingLocalDetail)
                          Material(
                            color: Theme.of(context)
                                .colorScheme
                                .tertiaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.cloud_off_outlined,
                                    size: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onTertiaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      Strings.detailOfflineBanner,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onTertiaryContainer,
                                          ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        viewModel.retryFromNetwork(),
                                    child: const Text(
                                        Strings.detailOfflineRetry),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        WorkFilesList(
                          files: viewModel.files!,
                          downloadedFileKeys: viewModel.downloadedFileKeys,
                          onFolderDownload: runBatch,
                          onFileTap: handleFileTap,
                          onFilePlay: handleFileTap,
                          onFileDownload: (file) => runDownload(
                            file,
                            openOnDone: false,
                            title: Strings.audioDownloadTitle,
                            prompt: Strings.audioDownloadPrompt,
                          ),
                        ),
                      ],
                    );
                  }

                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
        bottomSheet: const MiniPlayer(),
      ),
    );
  }
}
