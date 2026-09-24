import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/utils/logger.dart';

enum DownloadJobStatus {
  queued,
  running,
  success,
  alreadyExists,
  failed,
  cancelled,
}

/// 队列实际执行的下载函数（生产接 `DownloadService.download`，单测可注入假实现）。
typedef QueueDownloadFn = Future<DownloadResult> Function({
  required String workId,
  required Child file,
  void Function(double progress)? onProgress,
  CancelToken? cancelToken,
});

/// 下载成功后自动播放的回调（生产接 `IAudioPlayerService.playWithContext`）。
/// 收 [DownloadJob] 快照所需数据，**不得**持有 DetailViewModel 等可被
/// dispose 的 UI 对象（详情页离开后队列仍会跑完）。
typedef QueuePlayJobFn = Future<void> Function(DownloadJob job);

/// 按 workId 读持久化详情快照（生产接 `IWorkSnapshotRepository`）。
/// 供 job 缺 work/files 时在播放前回填。
typedef QueueLoadSnapshotFn =
    Future<({Work work, Files? files})?> Function(String workId);

/// 后台队列中的单个下载任务（音频 + 可选配对字幕）。
class DownloadJob {
  DownloadJob({
    required this.id,
    required this.workId,
    required this.file,
    this.pairedSubtitle,
    this.work,
    this.files,
    this.playOnComplete = false,
  })  : status = DownloadJobStatus.queued,
        progress = 0;

  final int id;
  final String workId;
  final Child file;
  final Child? pairedSubtitle;

  /// 自动播放所需的快照（入队时从详情页拷贝；可空 = 尚未解析——
  /// [DownloadQueueService] 可在播放前从持久化详情快照回填）。
  Work? work;
  Files? files;

  /// 单曲音频下完后是否自动开始播放（批量下载保持 false）。
  final bool playOnComplete;

  DownloadJobStatus status;
  double progress;
  String? localPath;
  CancelToken? cancelToken;

  String get title => file.title ?? '';

  bool get canPlay =>
      work != null && files != null && file.title != null;

  /// 单曲下完后是否自动开始播放（批量下载保持 false）。
  bool get canAutoPlay => playOnComplete && canPlay;
}

/// 后台下载队列：**串行**执行（维持 DownloadService 容量 LRU/原子写的
/// 顺序下载不变量），入队后不依赖调用页面存活。
///
/// 会话级（不持久化）：进程退出即清空；中断的半成品由 DownloadService
/// 的 tmp 原子写兜底，不会留下损坏的成品文件。
class DownloadQueueService extends ChangeNotifier {
  DownloadQueueService({
    required QueueDownloadFn download,
    QueuePlayJobFn? playJob,
    QueueLoadSnapshotFn? loadSnapshot,
  })  : _download = download,
        _playJob = playJob,
        _loadSnapshot = loadSnapshot;

  final QueueDownloadFn _download;
  final QueuePlayJobFn? _playJob;
  final QueueLoadSnapshotFn? _loadSnapshot;

  final List<DownloadJob> _jobs = [];
  int _nextId = 1;
  bool _processing = false;
  bool _disposed = false;

  /// success 后的回调（配对字幕已 best-effort 尝试完）。
  void Function(DownloadJob job)? onJobCompleted;

  List<DownloadJob> get jobs => List.unmodifiable(_jobs);

  int get pendingCount => _jobs
      .where((j) =>
          j.status == DownloadJobStatus.queued ||
          j.status == DownloadJobStatus.running)
      .length;

  bool get isProcessing => _processing;

  /// 入队一个音频（及可选配对字幕）。返回 job id。
  /// [playOnComplete]/[work]/[files] 仅单曲下载用；批量入队不传。
  int enqueue({
    required String workId,
    required Child file,
    Child? pairedSubtitle,
    Work? work,
    Files? files,
    bool playOnComplete = false,
  }) {
    final job = DownloadJob(
      id: _nextId++,
      workId: workId,
      file: file,
      pairedSubtitle: pairedSubtitle,
      work: work,
      files: files,
      playOnComplete: playOnComplete,
    );
    _jobs.add(job);
    _safeNotify();
    _ensureProcessing();
    return job.id;
  }

  /// 批量入队，返回入队数量。**不**自动播放（避免 N 首连跳）。
  int enqueueAll(
    Iterable<({Child audio, Child? subtitle})> pairs, {
    required String workId,
    Work? work,
    Files? files,
  }) {
    var n = 0;
    for (final p in pairs) {
      enqueue(
        workId: workId,
        file: p.audio,
        pairedSubtitle: p.subtitle,
        work: work,
        files: files,
        playOnComplete: false,
      );
      n++;
    }
    return n;
  }

  /// 取消：排队中直接标记 cancelled；进行中 abort 当前 CancelToken。
  void cancel(int jobId) {
    final job = _find(jobId);
    if (job == null) return;
    switch (job.status) {
      case DownloadJobStatus.queued:
        job.status = DownloadJobStatus.cancelled;
        _safeNotify();
      case DownloadJobStatus.running:
        job.cancelToken?.cancel();
      case DownloadJobStatus.success:
      case DownloadJobStatus.alreadyExists:
      case DownloadJobStatus.failed:
      case DownloadJobStatus.cancelled:
        break;
    }
  }

  /// 失败/取消的任务重新排队。
  void retry(int jobId) {
    final job = _find(jobId);
    if (job == null) return;
    if (job.status != DownloadJobStatus.failed &&
        job.status != DownloadJobStatus.cancelled) {
      return;
    }
    job.status = DownloadJobStatus.queued;
    job.progress = 0;
    job.localPath = null;
    _safeNotify();
    _ensureProcessing();
  }

  /// 清除已结束的任务。
  void clearFinished() {
    _jobs.removeWhere((j) =>
        j.status == DownloadJobStatus.success ||
        j.status == DownloadJobStatus.alreadyExists ||
        j.status == DownloadJobStatus.failed ||
        j.status == DownloadJobStatus.cancelled);
    _safeNotify();
  }

  /// 手动播放已下载完成的任务（下载管理页播放按钮）。
  /// job 缺 work/files 时先尝试 [loadSnapshot] 回填，再要求 [DownloadJob.canPlay]。
  Future<void> playNow(int jobId) async {
    final job = _find(jobId);
    if (job == null) return;
    if (!job.canPlay) await _hydrate(job);
    if (!job.canPlay) return;
    final play = _playJob;
    if (play == null) return;
    try {
      await play(job);
    } catch (e) {
      AppLogger.error('手动播放下载任务失败: ${job.title}', e);
      rethrow;
    }
  }

  /// 从持久化详情快照回填 job.work / job.files（best-effort）。
  Future<void> _hydrate(DownloadJob job) async {
    if (job.canPlay) return;
    final load = _loadSnapshot;
    if (load == null) return;
    try {
      final snap = await load(job.workId);
      if (snap != null) {
        job.work ??= snap.work;
        job.files ??= snap.files;
      }
    } catch (e) {
      AppLogger.warning('回填详情快照失败: ${job.title} ($e)');
    }
  }

  DownloadJob? _find(int id) {
    for (final j in _jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  void _ensureProcessing() {
    if (_processing) return;
    _processing = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (true) {
        DownloadJob? next;
        for (final j in _jobs) {
          if (j.status == DownloadJobStatus.queued) {
            next = j;
            break;
          }
        }
        if (next == null) break;
        await _runJob(next);
      }
    } finally {
      _processing = false;
      _safeNotify();
    }
  }

  Future<void> _runJob(DownloadJob job) async {
    final token = CancelToken();
    job.cancelToken = token;
    job.status = DownloadJobStatus.running;
    job.progress = 0;
    _safeNotify();

    try {
      final r = await _download(
        workId: job.workId,
        file: job.file,
        cancelToken: token,
        onProgress: (p) {
          job.progress = p;
          _safeNotify();
        },
      );
      if (r.status == DownloadStatus.cancelled) {
        job.status = DownloadJobStatus.cancelled;
        return;
      }
      if (r.isPlayable) {
        job.localPath = r.localPath;
        job.status = r.status == DownloadStatus.alreadyExists
            ? DownloadJobStatus.alreadyExists
            : DownloadJobStatus.success;
        final sub = job.pairedSubtitle;
        if (sub != null && !token.isCancelled) {
          try {
            await _download(
              workId: job.workId,
              file: sub,
              cancelToken: token,
            );
          } catch (e) {
            AppLogger.warning('配对字幕下载失败（不影响音频）: $e');
          }
        }
        // success 与 alreadyExists 都算「文件已在本地可播」——预检
        // findCompleted 命中 alreadyExists 时不播会让用户以为「下完没反应」。
        final completed = job.status == DownloadJobStatus.success ||
            job.status == DownloadJobStatus.alreadyExists;
        if (completed) onJobCompleted?.call(job);
        final play = _playJob;
        if (completed && job.playOnComplete) {
          if (!job.canPlay) await _hydrate(job);
          if (job.canAutoPlay && play != null) {
            try {
              await play(job);
            } catch (e) {
              AppLogger.error('下载完成自动播放失败: ${job.title}', e);
            }
          }
        }
        return;
      }
      job.status = switch (r.status) {
        DownloadStatus.networkError ||
        DownloadStatus.ioError =>
          DownloadJobStatus.failed,
        DownloadStatus.cancelled => DownloadJobStatus.cancelled,
        _ => DownloadJobStatus.failed,
      };
    } catch (e) {
      AppLogger.error('队列下载任务失败: ${job.title}', e);
      job.status = token.isCancelled
          ? DownloadJobStatus.cancelled
          : DownloadJobStatus.failed;
    } finally {
      job.cancelToken = null;
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final j in _jobs) {
      j.cancelToken?.cancel();
    }
    super.dispose();
  }
}
