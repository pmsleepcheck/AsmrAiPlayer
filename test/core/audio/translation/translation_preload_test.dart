import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aaplay/core/audio/events/playback_event_hub.dart';
import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/core/audio/models/subtitle.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/fish_tts_service.dart';
import 'package:aaplay/core/audio/translation/translation_session_controller.dart';
import 'package:aaplay/core/subtitle/i_subtitle_service.dart';

/// 只需要音量接口，其余走 noSuchMethod。
class _FakeAudioService implements IAudioPlayerService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('未预期调用: ${invocation.memberName}');
}

class _FakeSubtitleService implements ISubtitleService {
  SubtitleList? list;
  final StreamController<Subtitle?> currentCtrl =
      StreamController<Subtitle?>.broadcast();

  @override
  SubtitleList? get subtitleList => list;

  @override
  Stream<Subtitle?> get currentSubtitleStream => currentCtrl.stream;

  @override
  Subtitle? get currentSubtitle => null;

  @override
  Stream<SubtitleList?> get subtitleStream => const Stream.empty();

  @override
  void updatePosition(Duration position) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('未预期调用: ${invocation.memberName}');
}

/// 记录每次 synthesize 的文本（不发网络、不写盘）。
class _SpyTts extends FishTtsService {
  _SpyTts({required super.config, super.cacheDirResolver});

  final List<String> calls = [];
  bool failNext = false;

  @override
  Future<Uint8List> synthesize(String text) async {
    calls.add(text);
    if (failNext) {
      failNext = false;
      throw FishTtsException(FishTtsError.network, 'spy');
    }
    return Uint8List.fromList(const [1, 2, 3]);
  }
}

Subtitle _line(int index, String text) => Subtitle(
      start: Duration(seconds: index * 2),
      end: Duration(seconds: index * 2 + 2),
      text: text,
      index: index,
    );

/// bug.txt 2：翻译朗读**预合成下一句**——当前句起播时后台把下一句推进
/// Fish TTS 磁盘缓存，轮到它时命中缓存、消除句间延迟。
void main() {
  // `_speak` 会构造 just_audio AudioPlayer（audio_session / path_provider 都要
  // method channel），没有 binding 会在构造期抛断言。
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FishTtsConfigStore store;
  late _FakeSubtitleService subtitles;
  late _SpyTts tts;
  late TranslationSessionController controller;
  late PlaybackEventHub hub;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = FishTtsConfigStore(prefs: prefs);
    subtitles = _FakeSubtitleService();
    hub = PlaybackEventHub();
    tmp = await Directory.systemTemp.createTemp('tsc_preload_');
    tts = _SpyTts(config: store, cacheDirResolver: () async => tmp);
    controller = TranslationSessionController(
      subtitleService: subtitles,
      eventHub: hub,
      tts: tts,
      config: store,
      audio: _FakeAudioService(),
    );
  });

  tearDown(() async {
    controller.dispose();
    hub.dispose();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('起播当前句后预取下一句（只预取一句、同句不重复）', () async {
    await controller.beginSession(EarSide.left);
    subtitles.list = SubtitleList([_line(0, '第一句'), _line(1, '第二句')]);
    final first = subtitles.list!.subtitles.first;

    await controller.debugPreloadNext(first);
    expect(tts.calls, ['第二句']);
    expect(controller.debugPreloadedIndex, 0);

    // 同一行重复触发（force 重播 / 重复事件）不重复预取。
    await controller.debugPreloadNext(first);
    expect(tts.calls, ['第二句']);
  });

  test('最后一行没有下一句 → 不预取、不置去重位', () async {
    await controller.beginSession(EarSide.left);
    subtitles.list = SubtitleList([_line(0, '第一句'), _line(1, '第二句')]);

    await controller.debugPreloadNext(subtitles.list!.subtitles.last);

    expect(tts.calls, isEmpty);
    expect(controller.debugPreloadedIndex, isNull);
  });

  test('会话未开启不预取（不烧请求）', () async {
    subtitles.list = SubtitleList([_line(0, '第一句'), _line(1, '第二句')]);

    await controller.debugPreloadNext(subtitles.list!.subtitles.first);

    expect(tts.calls, isEmpty);
  });

  test('无字幕列表不预取', () async {
    await controller.beginSession(EarSide.left);
    subtitles.list = null;
    await controller.debugPreloadNext(_line(0, '第一句'));
    expect(tts.calls, isEmpty);
  });

  test('预取失败被吞掉（当前句不受影响），去重位仍记录', () async {
    await controller.beginSession(EarSide.left);
    subtitles.list = SubtitleList([_line(0, '第一句'), _line(1, '第二句')]);
    tts.failNext = true;

    await controller.debugPreloadNext(subtitles.list!.subtitles.first);

    expect(tts.calls, ['第二句']);
    expect(controller.debugPreloadedIndex, 0);
  });

  test('seek/重置后清掉去重位（下一次进同句会重新预取）', () async {
    await controller.beginSession(EarSide.left);
    subtitles.list = SubtitleList([_line(0, '第一句'), _line(1, '第二句')]);
    await controller.debugPreloadNext(subtitles.list!.subtitles.first);
    expect(controller.debugPreloadedIndex, 0);

    controller.notifySeek();

    expect(controller.debugPreloadedIndex, isNull);
  });

  test('字幕流驱动：当前句进 _speak、同时预取下一句', () async {
    await controller.beginSession(EarSide.left);
    subtitles.list = SubtitleList([
      _line(0, '第一句'),
      _line(1, '第二句'),
      _line(2, '第三句'),
    ]);

    subtitles.currentCtrl.add(subtitles.list!.subtitles.first);
    await subtitles.currentCtrl.close();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(tts.calls, containsAll(['第一句', '第二句']));
    expect(tts.calls, isNot(contains('第三句')));
  });
}
