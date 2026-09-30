import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/events/playback_event_hub.dart';
import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/core/audio/models/subtitle.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/fish_tts_service.dart';
import 'package:aaplay/core/audio/translation/smart_ear_analyzer.dart';
import 'package:aaplay/core/audio/translation/translation_session_controller.dart';
import 'package:aaplay/core/subtitle/i_subtitle_service.dart';
import 'package:aaplay/widgets/player/translation_controls.dart';

class _NoopAudioService implements IAudioPlayerService {
  @override
  Future<void> setVolume(double volume) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('未预期调用: ${invocation.memberName}');
}

class _NoopSubtitleService implements ISubtitleService {
  @override
  Stream<SubtitleList?> get subtitleStream => const Stream.empty();

  @override
  Stream<Subtitle?> get currentSubtitleStream => const Stream.empty();

  @override
  Subtitle? get currentSubtitle => null;

  @override
  void updatePosition(Duration position) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('未预期调用: ${invocation.memberName}');
}

/// 播放页「智能(实验)」开关 + 分析状态文案。
void main() {
  late TranslationSessionController session;
  late FishTtsConfigStore config;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    config = FishTtsConfigStore(prefs: prefs);

    await GetIt.I.reset();
    GetIt.I.registerSingleton<FishTtsConfigStore>(config);
    session = TranslationSessionController(
      subtitleService: _NoopSubtitleService(),
      eventHub: PlaybackEventHub(),
      tts: FishTtsService(config: config),
      config: config,
      audio: _NoopAudioService(),
    );
    GetIt.I.registerSingleton<TranslationSessionController>(session);
  });

  tearDown(() async {
    session.dispose();
    await GetIt.I.reset();
    SmartEarAnalyzer.clearCache();
  });

  Future<void> pumpControls(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TranslationControls()),
      ),
    );
    await tester.pump();
  }

  testWidgets('会话关闭时不显示智能行（只有自动音量一个开关）', (tester) async {
    await pumpControls(tester);

    expect(find.text(Strings.translationSmartEarLabel), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('会话打开后出现「智能(实验)」开关', (tester) async {
    await session.beginSession(EarSide.right);
    await pumpControls(tester);

    expect(find.text(Strings.translationSmartEarLabel), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(session.smartEar, isFalse);
  });

  testWidgets('拨智能开关 → 持久化', (tester) async {
    await session.beginSession(EarSide.right);
    await pumpControls(tester);

    // 第二个开关 = 智能耳（第一个是自动音量）。
    await tester.tap(find.byType(Switch).at(1));
    await tester.pump();

    expect(session.smartEar, isTrue);
    expect(config.translationSmartEar, isTrue);
  });

  testWidgets('状态文案随 smartStatus 变化（分析中/已就绪/不支持/失败）',
      (tester) async {
    await session.beginSession(EarSide.right);
    await session.setSmartEar(true);
    await pumpControls(tester);

    // 无曲目上下文 → idle（不显示文案）。
    expect(find.text(Strings.smartEarStatusAnalyzing), findsNothing);

    session.debugSetSmartTimeline(null, SmartEarStatus.analyzing);
    await tester.pump();
    expect(find.text(Strings.smartEarStatusAnalyzing), findsOneWidget);

    const timeline = EarTimeline(
      windowMs: 1000,
      durationMs: 1000,
      sides: [EarSide.left, EarSide.right],
    );
    session.debugSetSmartTimeline(timeline, SmartEarStatus.ready);
    await tester.pump();
    expect(find.text(Strings.smartEarStatusReady), findsOneWidget);
    expect(session.smartTimeline, isNotNull);

    session.debugSetSmartTimeline(null, SmartEarStatus.unsupported);
    await tester.pump();
    expect(find.text(Strings.smartEarStatusUnsupported), findsOneWidget);

    session.debugSetSmartTimeline(null, SmartEarStatus.failed);
    await tester.pump();
    expect(find.text(Strings.smartEarStatusFailed), findsOneWidget);
  });
}
