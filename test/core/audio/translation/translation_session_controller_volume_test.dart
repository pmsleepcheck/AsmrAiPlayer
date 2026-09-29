import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aaplay/core/audio/events/playback_event.dart';
import 'package:aaplay/core/audio/events/playback_event_hub.dart';
import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/core/audio/models/audio_track_info.dart';
import 'package:aaplay/core/audio/models/subtitle.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/fish_tts_service.dart';
import 'package:aaplay/core/audio/translation/translation_session_controller.dart';
import 'package:aaplay/core/subtitle/i_subtitle_service.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/works/work.dart';

/// TranslationSessionController 的音量接线（TODO 20260928-translation-volume-auto-manual Step 5）：
/// - 切曲 → 主轨响度实测（本地 wav / resolveLocalPath）
/// - 手动音量 → 全局配置 + 作品 album.json（作品记录优先读回）
/// - 自动开关默认开、改动即持久化 + 通知
///
/// 策略本体（两轨都测到时的对齐数学）由 translation_volume_policy_test 覆盖；
/// 这里只测控制器把测量结果/配置/作品记录喂给策略的通路。
class _FakeAudioService implements IAudioPlayerService {
  final List<double> volumes = [];

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('未预期调用: ${invocation.memberName}');
}

class _FakeSubtitleService implements ISubtitleService {
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

/// 16-bit/44.1k 单声道恒定值 wav（RMS ≈ 采样值本身，便于断言）。
Uint8List buildConstantWav({required double value, double seconds = 0.05}) {
  const sampleRate = 44100;
  final frames = (sampleRate * seconds).round();
  final dataLen = frames * 2;
  final buf = BytesBuilder();
  void tag(String s) => buf.add(s.codeUnits);
  void u32(int v) => buf.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  void u16(int v) => buf.add([v & 255, (v >> 8) & 255]);

  final sample = (value * 32767).round().clamp(-32768, 32767);
  tag('RIFF');
  u32(36 + dataLen);
  tag('WAVE');
  tag('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  tag('data');
  u32(dataLen);
  for (var i = 0; i < frames; i++) {
    final v = sample & 0xFFFF;
    buf.add([v & 255, (v >> 8) & 255]);
  }
  return buf.toBytes();
}

void main() {
  late Directory tmp;
  late String mainWavPath;
  late FishTtsConfigStore store;
  late _FakeAudioService audio;
  late TranslationSessionController controller;
  late PlaybackEventHub hub;

  final workVolumes = <String, double>{};

  Future<void> settle() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  void emitTrack({required int workId, String fileTitle = '01.mp3'}) {
    hub.emit(
      TrackChangeEvent(
        AudioTrackInfo(
          title: fileTitle,
          artist: '',
          coverUrl: '',
          url: 'https://example.com/$fileTitle',
        ),
        Child(
          type: 'audio',
          title: fileTitle,
          mediaDownloadUrl: 'https://example.com/$fileTitle',
        ),
        Work(id: workId, title: '作品$workId', sourceId: '$workId'),
      ),
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = FishTtsConfigStore(prefs: prefs);
    audio = _FakeAudioService();
    hub = PlaybackEventHub();
    workVolumes.clear();

    tmp = await Directory.systemTemp.createTemp('tsc_volume_');
    mainWavPath = '${tmp.path}/main.wav';
    File(mainWavPath).writeAsBytesSync(
      buildConstantWav(value: 0.4),
    );

    controller = TranslationSessionController(
      subtitleService: _FakeSubtitleService(),
      eventHub: hub,
      tts: FishTtsService(
        config: store,
        cacheDirResolver: () async => tmp,
      ),
      config: store,
      audio: audio,
      resolveLocalPath: (workId, file) async => mainWavPath,
      readWorkVolume: (workId) async => workVolumes[workId],
      recordWorkVolume: (workId, volume) async {
        workVolumes[workId] = volume;
        return true;
      },
    );
  });

  tearDown(() async {
    controller.dispose();
    hub.dispose();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('切曲后主轨响度被实测；TTS 未测到前仍回退 emphasis（main=1.0）', () async {
    await controller.beginSession(EarSide.left);
    expect(controller.autoVolume, isTrue);

    emitTrack(workId: 42);
    await settle();

    expect(controller.currentWorkId, '42');
    expect(controller.debugMainRms, isNotNull);
    expect(controller.debugMainRms!, closeTo(0.4, 0.01));
    // 只测到主轨 → policy 回退 emphasis（primary 主轨 1.0）
    expect(audio.volumes.last, 1.0);
  });

  test('手动音量：写全局配置 + 记到当前作品 + 立即生效', () async {
    emitTrack(workId: 42);
    await settle();

    await controller.setManualVolume(0.6);
    await settle();

    expect(controller.manualVolume, 0.6);
    expect(store.secondaryVolume, 0.6);
    expect(workVolumes['42'], 0.6);
    // 主轨（primary）不受手动值影响
    expect(audio.volumes.last, 1.0);
  });

  test('换作品：album.json 记录优先于全局；无记录回退全局', () async {
    workVolumes['7'] = 0.3;
    await store.setSecondaryVolume(0.9);

    emitTrack(workId: 7);
    await settle();
    expect(controller.manualVolume, 0.3);

    emitTrack(workId: 8);
    await settle();
    expect(controller.manualVolume, 0.9);
  });

  test('自动开关：默认开，setAutoVolume 持久化并通知', () async {
    expect(controller.autoVolume, isTrue);
    expect(store.translationAutoVolume, isTrue);

    var notified = 0;
    controller.addListener(() => notified++);
    await controller.setAutoVolume(false);

    expect(controller.autoVolume, isFalse);
    expect(store.translationAutoVolume, isFalse);
    expect(notified, greaterThan(0));
  });

  test('会话关时主轨音量恒 1.0（不因手动音量被拉低）', () async {
    emitTrack(workId: 42);
    await settle();
    await controller.setManualVolume(0.2);
    await settle();

    expect(controller.enabled, isFalse);
    expect(audio.volumes.last, 1.0);
  });

  test('两轨响度都已知 → 对齐：响的一侧被压下来（0.4/0.1 → 0.25）', () async {
    await controller.beginSession(EarSide.left);
    emitTrack(workId: 42);
    await settle();
    // 只测到主轨 → 还在回退 emphasis，滑杆可用
    expect(controller.manualVolumeEffective, isTrue);

    await controller.debugApplyRms(main: 0.4, tts: 0.1);

    expect(audio.volumes.last, closeTo(0.25, 1e-9));
    // 对齐生效期间手动值不参与 → UI 应置灰滑杆
    expect(controller.manualVolumeEffective, isFalse);
  });

  test('自动关 → 对齐失效回退 emphasis，滑杆重新可用', () async {
    await controller.beginSession(EarSide.left);
    await controller.setAutoVolume(false);
    await controller.debugApplyRms(main: 0.4, tts: 0.1);

    expect(audio.volumes.last, 1.0); // primary emphasis
    expect(controller.manualVolumeEffective, isTrue);
  });
}
