import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aaplay/core/audio/events/playback_event_hub.dart';
import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/core/audio/models/subtitle.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/fish_tts_service.dart';
import 'package:aaplay/core/audio/translation/smart_ear_analyzer.dart';
import 'package:aaplay/core/audio/translation/translation_session_controller.dart';
import 'package:aaplay/core/subtitle/i_subtitle_service.dart';

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

/// 智能耳（实验）在会话控制器里的接线：开关、状态、翻译轨落耳。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TranslationSessionController session;
  late FishTtsConfigStore config;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    config = FishTtsConfigStore(prefs: prefs);

    session = TranslationSessionController(
      subtitleService: _NoopSubtitleService(),
      eventHub: PlaybackEventHub(),
      tts: FishTtsService(config: config),
      config: config,
      audio: _NoopAudioService(),
    );
  });

  tearDown(() async {
    session.dispose();
    SmartEarAnalyzer.clearCache();
  });

  EarTimeline timelineOf(List<EarSide?> sides, {int windowMs = 1000}) =>
      EarTimeline(
        windowMs: windowMs,
        durationMs: windowMs * sides.length,
        sides: sides,
      );

  test('智能关 → 翻译轨走固定分耳的对侧', () async {
    await session.beginSession(EarSide.right); // 内容在右
    expect(session.debugComputeTtsEar(), EarSide.left);
  });

  test('智能开但没有时间线 → 仍回落固定分耳的对侧', () async {
    await session.beginSession(EarSide.left);
    await session.setSmartEar(true);
    await Future<void>.delayed(Duration.zero); // 等 _syncSmartEar 跑完

    expect(session.smartEar, isTrue);
    expect(session.smartTimeline, isNull);
    // 没有曲目上下文 → 状态 idle（不是失败）。
    expect(session.smartStatus, SmartEarStatus.idle);
    expect(session.debugComputeTtsEar(), EarSide.right);
  });

  test('智能开 + 时间线 → 翻译落在内容的对侧（与行号无关）', () async {
    await session.beginSession(EarSide.right);
    await session.setSmartEar(true);
    session.debugSetSmartTimeline(
      timelineOf([EarSide.left, EarSide.right]),
      SmartEarStatus.ready,
    );

    session.debugSetRoute(positionMs: 500, lineIndex: 0);
    expect(session.debugComputeTtsEar(), EarSide.right); // 内容左 → 翻译右

    session.debugSetRoute(positionMs: 1500, lineIndex: 7);
    expect(session.debugComputeTtsEar(), EarSide.left); // 内容右 → 翻译左
  });

  test('智能开 + 等响窗 → 按行号一句左一句右', () async {
    await session.beginSession(EarSide.right);
    await session.setSmartEar(true);
    session.debugSetSmartTimeline(
      timelineOf([null, null]),
      SmartEarStatus.ready,
    );

    session.debugSetRoute(positionMs: 0, lineIndex: 0);
    expect(session.debugComputeTtsEar(), EarSide.left);
    session.debugSetRoute(positionMs: 500, lineIndex: 1);
    expect(session.debugComputeTtsEar(), EarSide.right);
  });

  test('关掉智能开关 → 状态与时间线一起清掉，回固定耳', () async {
    await session.beginSession(EarSide.right);
    await session.setSmartEar(true);
    session.debugSetSmartTimeline(
      timelineOf([EarSide.left]),
      SmartEarStatus.ready,
    );

    await session.setSmartEar(false);
    await Future<void>.delayed(Duration.zero);

    expect(session.smartTimeline, isNull);
    expect(session.smartStatus, SmartEarStatus.idle);
    expect(session.debugComputeTtsEar(), EarSide.left);
  });

  test('结束会话 → 清时间线回 idle', () async {
    await session.beginSession(EarSide.right);
    session.debugSetSmartTimeline(
      timelineOf([EarSide.right]),
      SmartEarStatus.ready,
    );

    await session.endSession();
    await Future<void>.delayed(Duration.zero);

    expect(session.enabled, isFalse);
    expect(session.smartTimeline, isNull);
    expect(session.smartStatus, SmartEarStatus.idle);
  });
}
