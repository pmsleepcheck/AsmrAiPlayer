import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/di/service_locator.dart';
import 'package:aaplay/core/download/download_queue_service.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/core/theme/app_spacing.dart';
import 'package:aaplay/utils/logger.dart';
import 'package:aaplay/widgets/sidebar/sidebar_menu.dart';

/// 下载管理：展示后台队列任务（排队/进度/结果），可取消、重试、清除已完成。
/// 顶部展示下载根路径并可一键在资源管理器中打开（Windows 用户找文件入口）。
/// 队列由 [DownloadQueueService]（GetIt 单例）驱动，离开本页下载继续。
class DownloadManagementScreen extends StatefulWidget {
  const DownloadManagementScreen({super.key});

  @override
  State<DownloadManagementScreen> createState() =>
      _DownloadManagementScreenState();
}

class _DownloadManagementScreenState extends State<DownloadManagementScreen> {
  String? _rootPath;

  @override
  void initState() {
    super.initState();
    _loadRoot();
  }

  Future<void> _loadRoot() async {
    try {
      final path = await getIt<DownloadService>().downloadsRootPath();
      if (mounted) setState(() => _rootPath = path);
    } catch (e) {
      AppLogger.warning('解析下载根路径失败: $e');
    }
  }

  Future<void> _openRoot() async {
    final path = _rootPath;
    if (path == null) return;
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(Strings.openFolderFailed)),
        );
      }
    } catch (e) {
      AppLogger.error('打开下载文件夹失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(Strings.openFolderFailed)),
        );
      }
    }
  }

  bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  Widget build(BuildContext context) {
    // 队列只注册在 GetIt，不在 Provider 祖先树里——必须用 getIt 取实例，
    // context.read 会抛 ProviderNotFound → release 灰屏。
    return ChangeNotifierProvider<DownloadQueueService>.value(
      value: getIt<DownloadQueueService>(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(Strings.downloadManagement),
          leading: _isDesktopPlatform
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: Strings.back,
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
          actions: [
            Consumer<DownloadQueueService>(
              builder: (context, queue, _) {
                final hasFinished = queue.jobs.any((j) =>
                    j.status == DownloadJobStatus.success ||
                    j.status == DownloadJobStatus.alreadyExists ||
                    j.status == DownloadJobStatus.failed ||
                    j.status == DownloadJobStatus.cancelled);
                if (!hasFinished) return const SizedBox.shrink();
                return TextButton(
                  onPressed: queue.clearFinished,
                  child: const Text(Strings.downloadClearFinished),
                );
              },
            ),
          ],
        ),
        drawer: const SidebarMenu(),
        body: Column(
          children: [
            if (_rootPath != null)
              Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: InkWell(
                  onTap: _openRoot,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space16,
                      vertical: AppSpacing.space8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_open_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.space8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                Strings.downloadRootLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              Text(
                                _rootPath!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.space8),
                        TextButton.icon(
                          onPressed: _openRoot,
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text(Strings.openFolder),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Consumer<DownloadQueueService>(
                builder: (context, queue, _) {
                  if (queue.jobs.isEmpty) {
                    return Center(
                      child: Text(
                        Strings.downloadQueueEmpty,
                        style: Theme.of(context)
                            .textTheme
                            .bodyLarge
                            ?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    );
                  }
                  final jobs = queue.jobs.reversed.toList();
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.space8),
                    itemCount: jobs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _DownloadJobTile(job: jobs[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DownloadJobTile extends StatelessWidget {
  const _DownloadJobTile({required this.job});

  final DownloadJob job;

  String _statusLabel(DownloadJobStatus s) => switch (s) {
        DownloadJobStatus.queued => Strings.downloadJobQueued,
        DownloadJobStatus.running => Strings.downloadJobRunning,
        DownloadJobStatus.success => Strings.downloadJobSuccess,
        DownloadJobStatus.alreadyExists => Strings.downloadJobExists,
        DownloadJobStatus.failed => Strings.downloadJobFailed,
        DownloadJobStatus.cancelled => Strings.downloadJobCancelled,
      };

  IconData _statusIcon(DownloadJobStatus s) => switch (s) {
        DownloadJobStatus.queued => Icons.schedule,
        DownloadJobStatus.running => Icons.downloading,
        DownloadJobStatus.success => Icons.check_circle_outline,
        DownloadJobStatus.alreadyExists => Icons.file_copy_outlined,
        DownloadJobStatus.failed => Icons.error_outline,
        DownloadJobStatus.cancelled => Icons.cancel_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final queue = context.read<DownloadQueueService>();
    final status = _statusLabel(job.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space16,
        AppSpacing.space12,
        AppSpacing.space8,
        AppSpacing.space12,
      ),
      child: Row(
        children: [
          Icon(
            _statusIcon(job.status),
            size: 22,
            color: switch (job.status) {
              DownloadJobStatus.success ||
              DownloadJobStatus.alreadyExists =>
                cs.primary,
              DownloadJobStatus.failed => cs.error,
              DownloadJobStatus.cancelled => cs.onSurfaceVariant,
              _ => cs.onSurfaceVariant,
            },
          ),
          const SizedBox(width: AppSpacing.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.space4),
                if (job.status == DownloadJobStatus.running)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: job.progress > 0 ? job.progress : null,
                        minHeight: 4,
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      Text(
                        '$status · ${(job.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  )
                else
                  Text(
                    status,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),
          if (job.status == DownloadJobStatus.queued ||
              job.status == DownloadJobStatus.running)
            IconButton(
              tooltip: Strings.downloadJobCancel,
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => queue.cancel(job.id),
            )
          else if (job.status == DownloadJobStatus.success ||
              job.status == DownloadJobStatus.alreadyExists)
            IconButton(
              tooltip: Strings.downloadJobPlay,
              icon: const Icon(Icons.play_arrow, size: 22),
              onPressed: job.canPlay ? () => queue.playNow(job.id) : null,
            )
          else if (job.status == DownloadJobStatus.failed ||
              job.status == DownloadJobStatus.cancelled)
            IconButton(
              tooltip: Strings.downloadJobRetry,
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: () => queue.retry(job.id),
            ),
        ],
      ),
    );
  }
}
