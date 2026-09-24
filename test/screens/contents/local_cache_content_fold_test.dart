import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/di/service_locator.dart';
import 'package:aaplay/core/download/download_queue_service.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/core/download/models/download_entry.dart';
import 'package:aaplay/core/download/models/work_snapshot.dart';
import 'package:aaplay/core/download/storage/i_download_repository.dart';
import 'package:aaplay/core/download/storage/i_work_snapshot_repository.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/presentation/viewmodels/local_cache_viewmodel.dart';
import 'package:aaplay/screens/contents/local_cache_content.dart';

class _UnusedRepo implements IDownloadRepository {
  @override
  Future<DownloadEntry?> find(String workId, String fileKey) async => null;
  @override
  Future<void> upsert(DownloadEntry entry) async {}
  @override
  Future<void> remove(String workId, String fileKey) async {}
  @override
  Future<List<DownloadEntry>> listByWork(String workId) async => const [];
  @override
  Future<List<DownloadEntry>> listAllOldestFirst() async => const [];
}

class _NullSnapshots implements IWorkSnapshotRepository {
  @override
  Future<void> save(String workId, {required Work work, Files? files}) async {}
  @override
  Future<WorkSnapshot?> load(String workId) async => null;
  @override
  Future<void> remove(String workId) async {}
}

class _StubDownloadService extends DownloadService {
  final List<DownloadEntry> entries;

  _StubDownloadService({required this.entries})
      : super(repository: _UnusedRepo());

  @override
  Future<int> scanDownloadsRoots() async => 0;

  @override
  Future<List<DownloadEntry>> listAllDownloads() async => entries;

  @override
  Future<List<String>> downloadsRootPaths() async => const [];
}

DownloadEntry _entry(String workId, String name) => DownloadEntry(
      workId: workId,
      fileKey: 'k$workId$name',
      fileName: name,
      filePath: '/tmp/$name',
      mediaType: 'audio',
      sourceUrl: '',
      size: 1,
      createdAt: 1,
    );

Future<DownloadResult> _hangDownload({
  required String workId,
  required dynamic file,
  void Function(double progress)? onProgress,
  dynamic cancelToken,
  Work? work,
  Files? files,
}) =>
    Completer<DownloadResult>().future;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() async {
    await getIt.reset();
    final service = _StubDownloadService(entries: [
      _entry('w1', 'a.mp3'),
      _entry('w2', 'b.mp3'),
    ]);
    getIt.registerSingleton<DownloadService>(service);
    getIt.registerSingleton<DownloadQueueService>(
      DownloadQueueService(download: _hangDownload),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  Widget host() {
    final vm = LocalCacheViewModel(
      downloadService: getIt<DownloadService>() as _StubDownloadService,
      snapshotRepository: _NullSnapshots(),
    );
    return ChangeNotifierProvider<LocalCacheViewModel>.value(
      value: vm,
      child: const MaterialApp(
        home: Scaffold(body: LocalCacheContent()),
      ),
    );
  }

  testWidgets('分组默认折叠：见组头+条数，不见文件行', (tester) async {
    await tester.pumpWidget(host());
    await _settle(tester);

    expect(find.text('w1'), findsOneWidget);
    expect(find.text('w2'), findsOneWidget);
    expect(find.text(Strings.localCacheGroupCount(1)), findsNWidgets(2));
    expect(find.text('a.mp3'), findsNothing);
    expect(find.text('b.mp3'), findsNothing);
    // 组头收起 chevron（下载队列面板也收起 → 至少 2 个 expand_more）。
    expect(find.byIcon(Icons.expand_more).evaluate().length,
        greaterThanOrEqualTo(2));
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });

  testWidgets('点组头展开该组，再点折叠；另一组仍折叠', (tester) async {
    await tester.pumpWidget(host());
    await _settle(tester);

    await tester.tap(find.text('w1'));
    await tester.pump();

    expect(find.text('a.mp3'), findsOneWidget);
    expect(find.text('b.mp3'), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);

    await tester.tap(find.text('w1'));
    await tester.pump();

    expect(find.text('a.mp3'), findsNothing);
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });
}
