// work_file_item_play_button_test.dart：播放按钮只给「能进播放器」的文件。
//
// 回归背景：已下载的字幕（asmr.one 下发 type=audio）曾拿到播放按钮，
// 点击后被送进 setAudioSource → mpv 卡在加载态 → 后续所有播放全部失败。
//
// @created 2026-09-28

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/widgets/detail/work_file_item.dart';

Child _child(String title, {String? type}) => Child(type: type, title: title);

/// 用真实 candidateKeys 构造「已下载」集合，避免测试因为
/// `downloaded==false` 而让播放按钮的断言空转通过。
Set<String> _downloaded(Child file) => DownloadService.candidateKeys(file).toSet();

Future<void> _pump(
  WidgetTester tester,
  Child file, {
  void Function(Child)? onFilePlay,
  void Function(Child)? onFileTap,
  void Function(Child)? onFileTranslatePlay,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WorkFileItem(
        file: file,
        indentation: 0,
        downloadedFileKeys: _downloaded(file),
        onFilePlay: onFilePlay,
        onFileTap: onFileTap,
        onFileTranslatePlay: onFileTranslatePlay,
      ),
    ),
  ));
}

void main() {
  group('WorkFileItem 播放按钮可见性（downloaded 恒为 true）', () {
    testWidgets('已下载字幕（type=audio）没有播放按钮和翻译按钮', (tester) async {
      var played = false;
      var tapped = false;
      await _pump(
        tester,
        _child('01.vtt', type: 'audio'),
        onFilePlay: (_) => played = true,
        onFileTranslatePlay: (_) => played = true,
        onFileTap: (_) => tapped = true,
      );

      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.record_voice_over_outlined), findsNothing);
      // 已下载角标仍然保留（信息不丢）。
      expect(find.byIcon(Icons.download_done), findsOneWidget);
      // 字幕仍可点 → 进字幕预览，但绝不触发播放回调。
      expect(find.byType(ListTile), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      await tester.pump();
      expect(tapped, isTrue);
      expect(played, isFalse);
    });

    testWidgets('已下载音频（type=audio + .mp3）有播放按钮与翻译按钮',
        (tester) async {
      await _pump(
        tester,
        _child('01.mp3', type: 'audio'),
        onFilePlay: (_) {},
        onFileTranslatePlay: (_) {},
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.record_voice_over_outlined), findsOneWidget);
    });

    testWidgets('type 缺失时按扩展名兜底：.flac 有播放按钮', (tester) async {
      await _pump(
        tester,
        _child('01.flac'),
        onFilePlay: (_) {},
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('已下载 album.json（type=audio）没有播放按钮也不可点',
        (tester) async {
      var tapped = false;
      await _pump(
        tester,
        _child('album.json', type: 'audio'),
        onFilePlay: (_) {},
        onFileTap: (_) => tapped = true,
      );

      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.record_voice_over_outlined), findsNothing);

      await tester.tap(find.byType(ListTile));
      await tester.pump();
      expect(tapped, isFalse);
    });

    testWidgets('已下载视频（错标 type=audio）保留播放按钮 → 走外部打开',
        (tester) async {
      await _pump(
        tester,
        _child('介绍视频.mp4', type: 'audio'),
        onFilePlay: (_) {},
      );

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });
  });
}
