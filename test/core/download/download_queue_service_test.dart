import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/download/download_queue_service.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';

Child _file(String name) => Child(type: 'audio', title: name);

/// 可控假下载器：按文件名决定结果，并记录调用顺序。
class _FakeDownloader {
  final List<String> order = [];
  final Set<String> failTitles;
  final Duration delay;

  _FakeDownloader({this.failTitles = const {}, this.delay = Duration.zero});

  Future<DownloadResult> call({
    required String workId,
    required Child file,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    order.add(file.title ?? '');
    onProgress?.call(0.5);
    await Future<void>.delayed(delay);
    if (cancelToken?.isCancelled ?? false) {
      return const DownloadResult(DownloadStatus.cancelled);
    }
    if (failTitles.contains(file.title)) {
      return const DownloadResult(DownloadStatus.networkError);
    }
    onProgress?.call(1);
    return DownloadResult(DownloadStatus.success, '/tmp/${file.title}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('串行执行：入队顺序 = 下载顺序，完成后 status=success', () async {
    final fake = _FakeDownloader();
    final queue = DownloadQueueService(download: fake.call);

    queue.enqueue(workId: 'w', file: _file('a.mp3'));
    queue.enqueue(workId: 'w', file: _file('b.mp3'));
    queue.enqueue(workId: 'w', file: _file('c.mp3'));
    expect(queue.pendingCount, 3);

    await _waitIdle(queue);

    expect(fake.order, ['a.mp3', 'b.mp3', 'c.mp3']);
    expect(queue.jobs.map((j) => j.status),
        everyElement(DownloadJobStatus.success));
    expect(queue.pendingCount, 0);
    queue.dispose();
  });

  test('失败 job 标 failed 且不阻断后续；retry 重新排队', () async {
    final fake = _FakeDownloader(failTitles: {'b.mp3'});
    final queue = DownloadQueueService(download: fake.call);

    queue.enqueue(workId: 'w', file: _file('a.mp3'));
    queue.enqueue(workId: 'w', file: _file('b.mp3'));
    queue.enqueue(workId: 'w', file: _file('c.mp3'));
    await _waitIdle(queue);

    expect(queue.jobs[0].status, DownloadJobStatus.success);
    expect(queue.jobs[1].status, DownloadJobStatus.failed);
    expect(queue.jobs[2].status, DownloadJobStatus.success);

    queue.retry(queue.jobs[1].id);
    await _waitIdle(queue);
    expect(queue.jobs[1].status, DownloadJobStatus.failed); // 仍失败
    expect(fake.order.where((t) => t == 'b.mp3'), hasLength(2));
    queue.dispose();
  });

  test('排队中的 cancel 直接变 cancelled，不触发下载', () async {
    final fake = _FakeDownloader(delay: const Duration(milliseconds: 50));
    final queue = DownloadQueueService(download: fake.call);

    queue.enqueue(workId: 'w', file: _file('slow.mp3'));
    final second = queue.enqueue(workId: 'w', file: _file('never.mp3'));
    queue.cancel(second);

    await _waitIdle(queue);

    expect(queue.jobs[1].status, DownloadJobStatus.cancelled);
    expect(fake.order, ['slow.mp3']);
    queue.dispose();
  });

  test('配对字幕在主文件成功后 best-effort 下载', () async {
    final fake = _FakeDownloader();
    final queue = DownloadQueueService(download: fake.call);

    queue.enqueue(
      workId: 'w',
      file: _file('track.mp3'),
      pairedSubtitle: Child(type: 'text', title: 'track.vtt'),
    );
    await _waitIdle(queue);

    expect(fake.order, ['track.mp3', 'track.vtt']);
    expect(queue.jobs.single.status, DownloadJobStatus.success);
    queue.dispose();
  });

  test('clearFinished 只移除已结束任务', () async {
    final fake = _FakeDownloader(failTitles: {'bad.mp3'});
    final queue = DownloadQueueService(download: fake.call);
    queue.enqueue(workId: 'w', file: _file('ok.mp3'));
    queue.enqueue(workId: 'w', file: _file('bad.mp3'));
    await _waitIdle(queue);
    expect(queue.jobs, hasLength(2));
    queue.clearFinished();
    expect(queue.jobs, isEmpty);
    queue.dispose();
  });

  test('playOnComplete + work/files → 成功后触发 playJob', () async {
    final fake = _FakeDownloader();
    final played = <String>[];
    final queue = DownloadQueueService(
      download: fake.call,
      playJob: (job) async => played.add(job.title),
    );

    queue.enqueue(
      workId: 'w',
      file: _file('a.mp3'),
      work: Work(),
      files: Files(children: [_file('a.mp3')]),
      playOnComplete: true,
    );
    queue.enqueue(
      workId: 'w',
      file: _file('b.mp3'),
      work: Work(),
      files: Files(children: [_file('b.mp3')]),
      playOnComplete: false,
    );
    await _waitIdle(queue);

    expect(played, ['a.mp3']);
    queue.dispose();
  });

  test('playOnComplete 但缺 work/files 且无 loadSnapshot → 不触发 playJob',
      () async {
    final fake = _FakeDownloader();
    var played = false;
    final queue = DownloadQueueService(
      download: fake.call,
      playJob: (_) async => played = true,
    );

    queue.enqueue(
      workId: 'w',
      file: _file('a.mp3'),
      playOnComplete: true,
    );
    await _waitIdle(queue);

    expect(played, isFalse);
    queue.dispose();
  });

  test('playJob 抛错不影响任务 success 状态', () async {
    final fake = _FakeDownloader();
    final queue = DownloadQueueService(
      download: fake.call,
      playJob: (_) async => throw Exception('boom'),
    );

    queue.enqueue(
      workId: 'w',
      file: _file('a.mp3'),
      work: Work(),
      files: Files(children: [_file('a.mp3')]),
      playOnComplete: true,
    );
    await _waitIdle(queue);

    expect(queue.jobs.single.status, DownloadJobStatus.success);
    queue.dispose();
  });

  test('alreadyExists 也触发 playJob（预检命中仍要自动播）', () async {
    Future<DownloadResult> already({
      required String workId,
      required Child file,
      void Function(double progress)? onProgress,
      CancelToken? cancelToken,
    }) async =>
        DownloadResult(DownloadStatus.alreadyExists, '/tmp/${file.title}');
    var played = false;
    final queue = DownloadQueueService(
      download: already,
      playJob: (_) async => played = true,
    );

    queue.enqueue(
      workId: 'w',
      file: _file('a.mp3'),
      work: Work(),
      files: Files(children: [_file('a.mp3')]),
      playOnComplete: true,
    );
    await _waitIdle(queue);

    expect(queue.jobs.single.status, DownloadJobStatus.alreadyExists);
    expect(played, isTrue);
    queue.dispose();
  });

  test('playNow 在有 work/files 快照时触发 playJob', () async {
    final fake = _FakeDownloader();
    final played = <String>[];
    final queue = DownloadQueueService(
      download: fake.call,
      playJob: (job) async => played.add(job.title),
    );

    queue.enqueue(
      workId: 'w',
      file: _file('a.mp3'),
      work: Work(),
      files: Files(children: [_file('a.mp3')]),
      playOnComplete: false, // 批量：不自动播，但可手动 playNow
    );
    await _waitIdle(queue);
    expect(played, isEmpty);

    await queue.playNow(queue.jobs.single.id);
    expect(played, ['a.mp3']);
    queue.dispose();
  });

  test('playNow 无会话快照时经 loadSnapshot 回填 work/files', () async {
    final fake = _FakeDownloader();
    final played = <String>[];
    final queue = DownloadQueueService(
      download: fake.call,
      loadSnapshot: (workId) async =>
          (work: Work(id: 1), files: Files(children: [_file('a.mp3')])),
      playJob: (job) async => played.add(job.title),
    );

    // 入队不带 work/files（模拟会话快照丢失 / 仅持久化详情快照）。
    queue.enqueue(workId: '1', file: _file('a.mp3'), playOnComplete: false);
    await _waitIdle(queue);
    expect(queue.jobs.single.canPlay, isFalse);

    await queue.playNow(queue.jobs.single.id);
    expect(played, ['a.mp3']);
    expect(queue.jobs.single.work, isNotNull);
    queue.dispose();
  });

  test('playOnComplete 缺快照时经 loadSnapshot 回填后仍自动播', () async {
    final fake = _FakeDownloader();
    final played = <String>[];
    final queue = DownloadQueueService(
      download: fake.call,
      loadSnapshot: (workId) async =>
          (work: Work(), files: Files(children: [_file('a.mp3')])),
      playJob: (job) async => played.add(job.title),
    );

    queue.enqueue(workId: 'w', file: _file('a.mp3'), playOnComplete: true);
    await _waitIdle(queue);

    expect(played, ['a.mp3']);
    queue.dispose();
  });
}

/// 等队列 drain 完（processing 变 false 且无 pending）。
Future<void> _waitIdle(DownloadQueueService queue) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (!queue.isProcessing && queue.pendingCount == 0) {
      // 多等一拍，让 finally 里的 notify 落地。
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!queue.isProcessing && queue.pendingCount == 0) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw TimeoutException('queue did not become idle');
}
