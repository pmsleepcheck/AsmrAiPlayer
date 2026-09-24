/// download_queue_panel.dart：可折叠下载队列面板（合并页顶部）。
/// 初始展开 iff `pendingCount > 0`；用户手动折叠/展开后本会话内尊重其选择，
/// 但新任务从 0→有 pending 且用户尚未手动操作过时会自动展开。
///
/// 队列只在 GetIt（`DownloadQueueService`），必须用 `.value` 提供 Provider。
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/di/service_locator.dart';
import 'package:aaplay/core/download/download_queue_service.dart';
import 'package:aaplay/core/theme/app_colors.dart';
import 'package:aaplay/core/theme/app_radius.dart';
import 'package:aaplay/core/theme/app_spacing.dart';

class DownloadQueuePanel extends StatefulWidget {
  const DownloadQueuePanel({super.key});

  /// 展开区最大高度（内部滚动），避免长队列挤掉下方本地文件区。
  static const double maxBodyHeight = 280;

  @override
  State<DownloadQueuePanel> createState() => _DownloadQueuePanelState();
}

class _DownloadQueuePanelState extends State<DownloadQueuePanel> {
  bool _expanded = false;
  bool _userToggled = false;

  @override
  void initState() {
    super.initState();
    final queue = getIt<DownloadQueueService>();
    _expanded = queue.pendingCount > 0;
    queue.addListener(_onQueueChanged);
  }

  @override
  void dispose() {
    if (getIt.isRegistered<DownloadQueueService>()) {
      getIt<DownloadQueueService>().removeListener(_onQueueChanged);
    }
    super.dispose();
  }

  void _onQueueChanged() {
    if (_userToggled || !mounted) return;
    final should = getIt<DownloadQueueService>().pendingCount > 0;
    if (should != _expanded) {
      setState(() => _expanded = should);
    }
  }

  void _toggle() {
    setState(() {
      _userToggled = true;
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 队列只注册在 GetIt，不在 Provider 祖先树里——必须用 getIt 取实例，
    // context.read 会抛 ProviderNotFound → release 灰屏。
    return ChangeNotifierProvider<DownloadQueueService>.value(
      value: getIt<DownloadQueueService>(),
      child: Consumer<DownloadQueueService>(
        builder: (context, queue, _) {
          final cs = Theme.of(context).colorScheme;
          final pending = queue.pendingCount;
          final hasFinished = queue.jobs.any((j) =>
              j.status == DownloadJobStatus.success ||
              j.status == DownloadJobStatus.alreadyExists ||
              j.status == DownloadJobStatus.failed ||
              j.status == DownloadJobStatus.cancelled);

          return Material(
            color: cs.surface,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: _toggle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.space16,
                      vertical: AppSpacing.space12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.download_outlined,
                          size: 20,
                          color: cs.primary,
                        ),
                        const SizedBox(width: AppSpacing.space12),
                        Text(
                          Strings.downloadManagement,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (pending > 0) ...[
                          const SizedBox(width: AppSpacing.space8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.space8,
                              vertical: AppSpacing.space4,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: AppRadius.fullAll,
                              color: cs.primaryContainer,
                            ),
                            child: Text(
                              Strings.downloadActiveCount(pending),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: cs.onPrimaryContainer),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (_expanded && hasFinished)
                          TextButton(
                            onPressed: queue.clearFinished,
                            child: const Text(Strings.downloadClearFinished),
                          ),
                        Icon(
                          _expanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: cs.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expanded)
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: DownloadQueuePanel.maxBodyHeight,
                    ),
                    child: queue.jobs.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.space24,
                            ),
                            child: Text(
                              Strings.downloadQueueEmpty,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.space8,
                            ),
                            itemCount: queue.jobs.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              indent: AppSpacing.space16,
                              endIndent: AppSpacing.space16,
                            ),
                            itemBuilder: (context, index) => _DownloadJobTile(
                              job: queue.jobs[index],
                            ),
                          ),
                  ),
                Divider(
                  height: 1,
                  thickness: AppColors.dividerThickness,
                  color: cs.outlineVariant,
                ),
              ],
            ),
          );
        },
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
