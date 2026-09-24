import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aaplay/core/audio/events/playback_event_hub.dart';
import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/core/audio/models/subtitle.dart';
import 'package:aaplay/core/subtitle/i_subtitle_service.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/ear_channel_router.dart';
import 'package:aaplay/core/audio/translation/fish_tts_config.dart';
import 'package:aaplay/core/audio/translation/fish_tts_service.dart';
import 'package:aaplay/core/audio/translation/translation_mix_state.dart';
import 'package:aaplay/utils/logger.dart';

/// 双耳「翻译+播放」会话：第二 AudioPlayer 播 Fish TTS 字幕朗读。
///
/// - [beginSession]：列表「翻译+播放」入口（已解析主耳）→ enabled=true。
/// - [endSession]：普通播放入口调用 → 翻译关闭、主耳清除、音量复位、清 `af`。
/// - 字幕行变更 → synthesize（磁盘缓存）→ 临时 mp3 → `_ttsPlayer` 播放。
/// - 主轨 pause/play/seek/切曲/stop 通过 [PlaybackEventHub] 同步翻译轨。
/// - 「方向」= [TranslationMixState.swapped]（主次音量 emphasis + 主耳对调）。
/// - 真分耳：`_applyVolumes` 会连带 `EarChannelRouter.apply`（主轨→mainEar、
///   TTS→对侧；见 `ear_channel_router.dart`）。
class TranslationSessionController extends ChangeNotifier {
  final ISubtitleService _subtitleService;
  final PlaybackEventHub _eventHub;
  final FishTtsService _tts;
  final FishTtsConfigStore _config;
  final IAudioPlayerService _audio;

  TranslationMixState _state;

  AudioPlayer? _ttsPlayer;
  final List<StreamSubscription> _subs = [];

  /// 行号 epoch：新行/seek/切曲时 ++，废弃在途 TTS。
  int _epoch = 0;
  int? _spokenIndex;
  bool _ttsWasPlaying = false;
  String? _lastError;
  bool _speaking = false;

  TranslationSessionController({
    required ISubtitleService subtitleService,
    required PlaybackEventHub eventHub,
    required FishTtsService tts,
    required FishTtsConfigStore config,
    required IAudioPlayerService audio,
    TranslationMixState? initial,
  })  : _subtitleService = subtitleService,
        _eventHub = eventHub,
        _tts = tts,
        _config = config,
        _audio = audio,
        _state = initial ??
            TranslationMixState.idle(
              secondaryVolume: config.secondaryVolume,
            ) {
    _initStreams();
  }

  TranslationMixState get state => _state;
  bool get enabled => _state.enabled;
  EarSide? get mainEar => _state.mainEar;
  bool get translationPrimary => _state.translationPrimary;
  String? get lastError => _lastError;

  void _initStreams() {
    _subs.add(_eventHub.playbackState.listen((event) async {
      final playing = event.state.playing;
      final tts = _ttsPlayer;
      if (tts == null) return;
      try {
        if (!playing) {
          _ttsWasPlaying = tts.playing;
          await tts.pause();
        } else if (_state.enabled && _ttsWasPlaying) {
          await tts.play();
        }
      } catch (e) {
        AppLogger.warning('翻译轨随主轨暂停/恢复失败: $e');
      }
      // 非翻译相关状态也顺便把音量钉住（外部可能改过主轨 volume）。
      unawaited(_applyVolumes());
    }));

    _subs.add(_eventHub.trackChange.listen((_) {
      _resetSpeech('trackChange');
    }));

    _subs.add(_eventHub.contextChange.listen((_) {
      _resetSpeech('contextChange');
    }));

    _subs.add(_eventHub.playbackCleared.listen((_) {
      endSession();
      _resetSpeech('cleared');
    }));

    _subs.add(_subtitleService.currentSubtitleStream.listen((sub) {
      _onSubtitle(sub);
    }));
  }

  /// 列表「翻译+播放」入口。
  Future<void> beginSession(EarSide ear) async {
    _state = _state.beginSession(ear);
    _state = _state.withSecondaryVolume(_config.secondaryVolume);
    _lastError = null;
    _spokenIndex = null;
    notifyListeners();
    await _applyVolumes();
    final cur = _subtitleService.currentSubtitle;
    if (cur != null) _onSubtitle(cur, force: true);
  }

  /// 普通播放入口：关翻译、清主耳、音量复位。
  Future<void> endSession() async {
    final was = _state.enabled;
    _state = _state.endSession();
    _state = _state.withSecondaryVolume(_config.secondaryVolume);
    if (was) {
      _epoch++;
      await _stopTtsPlayer();
    }
    _spokenIndex = null;
    notifyListeners();
    await _applyVolumes();
  }

  Future<void> toggleTranslation() async {
    _state = _state.toggled;
    _state = _state.withSecondaryVolume(_config.secondaryVolume);
    _lastError = null;
    if (!_state.enabled) {
      _epoch++;
      await _stopTtsPlayer();
      _spokenIndex = null;
    }
    notifyListeners();
    await _applyVolumes();
    if (_state.enabled) {
      final cur = _subtitleService.currentSubtitle;
      if (cur != null) {
        _onSubtitle(cur, force: true);
      }
    }
  }

  Future<void> swapDirection() async {
    // 会话未开启时也允许切换默认主耳侧（播放页常显控件，bug.txt 3）。
    _state = _state.swapped;
    if (_state.mainEar == null) {
      _state = _state.withEar(EarSide.right.flipped);
    }
    _state = _state.withSecondaryVolume(_config.secondaryVolume);
    notifyListeners();
    await _applyVolumes();
  }

  /// seek 时由 UI 显式调用（PlayerViewModel.seek 桥接）。
  void notifySeek() => _resetSpeech('seek');

  Future<void> _applyVolumes() async {
    try {
      await _audio.setVolume(_state.mainVolume);
      final tts = _ttsPlayer;
      if (tts != null) {
        await tts.setVolume(_state.translationVolume);
      }
    } catch (e) {
      AppLogger.warning('应用混播音量失败: $e');
    }
    await _applyEarRouting();
  }

  /// 真左右耳隔离：enabled → mainEar 分耳，否则清 mpv `af`。
  Future<void> _applyEarRouting() async {
    await EarChannelRouter.apply(_state.enabled ? _state.mainEar : null);
  }

  void _onSubtitle(Subtitle? sub, {bool force = false}) {
    if (!_state.enabled) return;
    if (sub == null) return;
    final text = sub.text.trim();
    if (text.isEmpty) return;
    if (!force && _spokenIndex == sub.index) return;
    unawaited(_speak(sub.index, text));
  }

  Future<void> _speak(int index, String text) async {
    final epoch = ++_epoch;
    if (_speaking) {
      // 串行：上一请求作废即可，无需等待。
    }
    _speaking = true;
    try {
      final player = _ttsPlayer ??= () {
        // 角色认领必须在 AudioPlayer() 前（仅 media_kit 平台入队）。
        EarChannelRouter.expectTtsPlayer();
        return AudioPlayer();
      }();
      await player.stop();

      final bytes = await _tts.synthesize(text);
      if (epoch != _epoch || !_state.enabled) return;

      final path = await _writeTempClip(epoch, bytes);
      if (epoch != _epoch || !_state.enabled) return;

      await player.setAudioSource(
        AudioSource.file(path),
        preload: true,
      );
      if (epoch != _epoch || !_state.enabled) return;

      await player.setVolume(_state.translationVolume);
      // TTS 平台 init 可能刚完成：再推一次路由，确保 af 落到翻译轨。
      await _applyEarRouting();
      _spokenIndex = index;
      _lastError = null;
      final delayMs = _config.delayMs;
      if (delayMs > 0) {
        // 同声传译延迟：epoch 门控，新行/seek 会作废本次等待。
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        if (epoch != _epoch || !_state.enabled) return;
      }
      unawaited(player.play().catchError((Object e) {
        AppLogger.warning('翻译轨播放失败: $e');
        return null;
      }));
      notifyListeners();
    } on FishTtsException catch (e) {
      if (epoch != _epoch) return;
      _lastError = e.error.name;
      AppLogger.warning('翻译 TTS 失败: $e');
      notifyListeners();
    } catch (e, st) {
      if (epoch != _epoch) return;
      _lastError = 'error';
      AppLogger.error('翻译朗读未预期失败', e, st);
      notifyListeners();
    } finally {
      if (epoch == _epoch) _speaking = false;
    }
  }

  Future<String> _writeTempClip(int epoch, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final target = Directory(p.join(dir.path, 'fish_tts_clips'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    // 清掉同名旧 clip，避免磁盘堆积。
    final file = File(p.join(target.path, 'line_$epoch.mp3'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _stopTtsPlayer() async {
    final tts = _ttsPlayer;
    if (tts == null) return;
    try {
      await tts.stop();
    } catch (e) {
      AppLogger.warning('停止翻译轨失败: $e');
    }
  }

  void _resetSpeech(String reason) {
    _epoch++;
    _spokenIndex = null;
    _ttsWasPlaying = false;
    unawaited(_stopTtsPlayer());
    if (_state.enabled) {
      AppLogger.debug('翻译语音重置: $reason');
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final tts = _ttsPlayer;
    _ttsPlayer = null;
    tts?.dispose();
    super.dispose();
  }
}
