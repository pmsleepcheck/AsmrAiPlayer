import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/di/service_locator.dart';
import 'package:aaplay/core/download/download_queue_service.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/widgets/download/download_queue_panel.dart';

Child _file(String name) => Child(type: 'audio', title: name);

/// 挂起下载：pendingCount 保持 >0（running），用于初始展开规则。
Future<DownloadResult> _hang({
  required String workId,
  required Child file,
  void Function(double progress)? onProgress,
  CancelToken? cancelToken,
  Work? work,
  Files? files,
}) =>
    Completer<DownloadResult>().future;

/// 立即完成：入队后很快回到 pendingCount==0。
Future<DownloadResult> _instantOk({
  required String workId,
  required Child file,
  void Function(double progress)? onProgress,
  CancelToken? cancelToken,
  Work? work,
  Files? files,
}) async =>
    const DownloadResult(DownloadStatus.success, '/tmp/ok.mp3');

Future<void> _wait(WidgetTester tester, [int frames = 4]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _host() => const MaterialApp(
      home: Scaffold(body: DownloadQueuePanel()),
    );

void main() {
  setUp(() {
    getIt.registerSingleton<DownloadQueueService>(
      DownloadQueueService(download: _hang),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('无 pending → 默认折叠，不显示任务列表', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text(Strings.downloadQueueEmpty), findsNothing);
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    expect(find.byIcon(Icons.expand_less), findsNothing);
  });

  testWidgets('有 pending → 默认展开，显示空态文案（队列已挂起）', (tester) async {
    getIt<DownloadQueueService>()
        .enqueue(workId: 'w', file: _file('a.mp3'));
    await _wait(tester);

    await tester.pumpWidget(_host());
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    // 挂起下载尚未结束，但 jobs 非空时走列表而非 empty 文案
    expect(find.text('a.mp3'), findsOneWidget);
    expect(find.textContaining(Strings.downloadActiveCount(1)), findsOneWidget);
  });

  testWidgets('点头部可折叠/再展开（用户覆盖初始规则）', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.byIcon(Icons.expand_more), findsOneWidget);

    // 手动展开
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();
    expect(find.text(Strings.downloadQueueEmpty), findsOneWidget);

    // 再折叠
    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pump();
    expect(find.text(Strings.downloadQueueEmpty), findsNothing);
  });

  testWidgets('有已完成任务且展开时显示「清除已完成」', (tester) async {
    await getIt.reset();
    getIt.registerSingleton<DownloadQueueService>(
      DownloadQueueService(download: _instantOk),
    );
    getIt<DownloadQueueService>()
        .enqueue(workId: 'w', file: _file('done.mp3'));
    await _wait(tester, 10);

    // 新 panel 创建时 pendingCount==0 → 折叠；用户手动展开
    await tester.pumpWidget(_host());
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pump();

    expect(find.text(Strings.downloadClearFinished), findsOneWidget);
    await tester.tap(find.text(Strings.downloadClearFinished));
    await tester.pump();
    expect(find.text(Strings.downloadQueueEmpty), findsOneWidget);
  });
}
