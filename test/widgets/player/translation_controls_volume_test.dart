import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/events/playback_event_hub.dart';
import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/core/audio/models/subtitle.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/fish_tts_service.dart';
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

/// 播放页音量面板（Step 6）：自动开关 + 手动滑杆 + 百分比。
void main() {
  late TranslationSessionController session;
  late FishTtsConfigStore config;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    config = FishTtsConfigStore(prefs: prefs);
    await config.setSecondaryVolume(0.7);

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
  });

  Future<void> pumpControls(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TranslationControls()),
      ),
    );
    await tester.pump();
  }

  testWidgets('渲染自动音量开关、滑杆与百分比', (tester) async {
    await pumpControls(tester);

    expect(find.text(Strings.translationAutoVolumeLabel), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    // 默认手动音量 70%
    expect(find.text(Strings.percentLabel(70)), findsOneWidget);
  });

  testWidgets('拨开关 → 持久化自动音量', (tester) async {
    await pumpControls(tester);
    expect(session.autoVolume, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(session.autoVolume, isFalse);
    expect(config.translationAutoVolume, isFalse);
  });

  testWidgets('拖滑杆 → 手动音量变化并按作品生效', (tester) async {
    await pumpControls(tester);

    await tester.drag(find.byType(Slider), const Offset(-200, 0));
    await tester.pump();

    expect(session.manualVolume, lessThan(0.7));
    expect(config.secondaryVolume, session.manualVolume);
  });
}
