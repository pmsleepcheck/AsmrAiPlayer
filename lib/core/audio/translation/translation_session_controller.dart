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
import 'package:aaplay/core/audio/translation/loudness_meter.dart';
import 'package:aaplay/core/audio/translation/translation_mix_state.dart';
import 'package:aaplay/core/audio/translation/translation_volume_policy.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/works/work.dart';
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
///
/// **音量（2026-09-28）**：`_applyVolumes` 走 [TranslationVolumePolicy] ——
/// 自动音量开 + 两轨响度实测到 → 对齐到同响；否则回退 emphasis（=旧行为）。
/// 主轨响度在切曲时异步测（本地 wav/mp3，isolate 里跑，不阻塞起播），
/// 每段 TTS 在起播后异步测；两者的测量结果都不挡播放（先按回退音量出声，
/// 测到再补一次 `setVolume`）。手动音量 = 作品 `album.json` 记录 > 全局配置。
class TranslationSessionController extends ChangeNotifier {
  final ISubtitleService _subtitleService;
  final PlaybackEventHub _eventHub;
  final FishTtsService _tts;
  final FishTtsConfigStore _config;
  final IAudioPlayerService _audio;

  /// 解析当前播放文件的本地路径（在线流返回 null → 主轨不可测 → 回退）。
  final Future<String?> Function(String workId, Child file)? _resolveLocalPath;

  /// 读/写作品 `album.json` 的 `translationVolume`（按作品记住手动音量）。
  final Future<double?> Function(String workId)? _readWorkVolume;
  final Future<bool> Function(String workId, double volume)? _recordWorkVolume;

  TranslationMixState _state;

  AudioPlayer? _ttsPlayer;
  final List<StreamSubscription> _subs = [];

  /// 行号 epoch：新行/seek/切曲时 ++，废弃在途 TTS。
  int _epoch = 0;
  int? _spokenIndex;
  bool _ttsWasPlaying = false;
  String? _lastError;
  bool _speaking = false;

  // === 响度对齐用 ===
  String? _workId;
  Child? _currentFile;

  /// 主轨响度（换曲置 null；null = 未测/不可测 → 回退）。
  double? _mainRms;

  /// 当前这段 TTS 的响度（每段起播前置 null，测到后回填）。
  double? _ttsRms;

  /// 当前作品在 album.json 里记的手动音量；null = 没记 → 用全局配置。
  double? _workVolume;

  /// true = 现在的音量由手动值决定（自动关 / 会话关 / 任一轨不可测），
  /// 滑杆可拖；false = 两轨已进入响度对齐，手动值此刻不参与音量
  /// （UI 应置灰滑杆并提示，拖了也不会变 —— 避免「拖了没反应」）。
  bool get manualVolumeEffective {
    if (!_config.translationAutoVolume || !_state.enabled) return true;
    return !TranslationVolumePolicy.usable(_mainRms) ||
        !TranslationVolumePolicy.usable(_ttsRms);
  }

  /// 换曲时 ++，让在途的主轨测量作废。
  int _measureSeq = 0;
  bool _disposed = false;

  TranslationSessionController({
    required ISubtitleService subtitleService,
    required PlaybackEventHub eventHub,
    required FishTtsService tts,
    required FishTtsConfigStore config,
    required IAudioPlayerService audio,
    TranslationMixState? initial,
    Future<String?> Function(String workId, Child file)? resolveLocalPath,
    Future<double?> Function(String workId)? readWorkVolume,
    Future<bool> Function(String workId, double volume)? recordWorkVolume,
  })  : _subtitleService = subtitleService,
        _eventHub = eventHub,
        _tts = tts,
        _config = config,
        _audio = audio,
        _resolveLocalPath = resolveLocalPath,
        _readWorkVolume = readWorkVolume,
        _recordWorkVolume = recordWorkVolume,
        _state = initial ??
            TranslationMixState.idle(
              secondaryVolume: config.secondaryVolume,
            ) {
    _initStreams();
    _config.addListener(_onConfigChanged);
  }

  TranslationMixState get state => _state;
  bool get enabled => _state.enabled;
  EarSide? get mainEar => _state.mainEar;
  bool get translationPrimary => _state.translationPrimary;
  String? get lastError => _lastError;

  /// 自动响度对齐开关（默认开，存全局配置）。
  bool get autoVolume => _config.translationAutoVolume;

  /// 当前生效的手动音量（作品记录优先，否则全局配置）。
  double get manualVolume => _state.secondaryVolume;

  /// 当前播放作品 id（手动音量写 album.json 用）。
  String? get currentWorkId => _workId;

  /// 实测响度（诊断/单测；null = 未测或该轨不可测 → 回退 emphasis）。
  @visibleForTesting
  double? get debugMainRms => _mainRms;

  @visibleForTesting
  double? get debugTtsRms => _ttsRms;

  /// 单测用：直接喂两轨响度并重算音量（真实路径 = 切曲测主轨、
  /// `_speak` 起播后测该段 TTS）。替代真实测量，用来断言
  /// 「对齐后响的一侧 volume < 1」这条验收。
  @visibleForTesting
  Future<void> debugApplyRms({double? main, double? tts}) async {
    _mainRms = main;
    _ttsRms = tts;
    await _applyVolumes();
  }

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

    _subs.add(_eventHub.trackChange.listen((event) {
      _resetSpeech('trackChange');
      _onContext(work: event.work, file: event.file);
    }));

    _subs.add(_eventHub.contextChange.listen((event) {
      _resetSpeech('contextChange');
      _onContext(
        work: event.context.work,
        file: event.context.currentFile,
      );
    }));

    _subs.add(_eventHub.playbackCleared.listen((_) {
      endSession();
      _resetSpeech('cleared');
      _onCleared();
    }));

    _subs.add(_subtitleService.currentSubtitleStream.listen((sub) {
      _onSubtitle(sub);
    }));
  }

  /// 配置（自动开关 / 全局手动音量）变化 → 立即重算并推音量。
  void _onConfigChanged() {
    if (_disposed) return;
    // 全局音量变了：没有作品级记录时跟全局；有记录的以作品记录为准。
    final v = _workVolume ?? _config.secondaryVolume;
    if (_state.secondaryVolume != v) {
      _state = _state.withSecondaryVolume(v);
    }
    unawaited(_applyVolumes());
    notifyListeners();
  }

  // === 当前曲目 / 响度 ===

  void _onContext({required Work work, required Child file}) {
    final workId = work.id?.toString(); // 与 DownloadService 的 workId 约定一致
    final workChanged = _workId != workId;
    final fileChanged = _currentFile?.title != file.title;
    _workId = workId;
    _currentFile = file;
    if (workChanged) {
      _workVolume = null;
      if (workId != null) unawaited(_loadWorkVolume(workId));
    }
    if (fileChanged || workChanged) {
      _measureSeq++;
      _mainRms = null;
      _ttsRms = null;
    }
    _syncManualVolume();
    if (fileChanged || workChanged || _mainRms == null) {
      unawaited(_maybeMeasureMain());
    }
    unawaited(_applyVolumes());
  }

  void _onCleared() {
    _workId = null;
    _currentFile = null;
    _workVolume = null;
    _mainRms = null;
    _ttsRms = null;
    _measureSeq++;
  }

  Future<void> _loadWorkVolume(String workId) async {
    final read = _readWorkVolume;
    if (read == null) return;
    double? v;
    try {
      v = await read(workId);
    } catch (e) {
      AppLogger.warning('读取作品音量失败: $workId ($e)');
      return;
    }
    if (_disposed || _workId != workId || v == null) return;
    _workVolume = v;
    _syncManualVolume();
    notifyListeners();
    await _applyVolumes();
  }

  /// 主轨响度：只在「会话开 + 自动开 + 还没测」时做一次（isolate 解码）。
  Future<void> _maybeMeasureMain() async {
    if (_disposed || !_state.enabled || !_config.translationAutoVolume) {
      return;
    }
    if (_mainRms != null) return;
    final workId = _workId;
    final file = _currentFile;
    if (workId == null || file == null) return;
    final seq = _measureSeq;

    String? path;
    try {
      path = await _resolveLocalPath?.call(workId, file);
    } catch (e) {
      AppLogger.warning('解析本地路径失败（主轨响度跳过）: $e');
    }
    path ??= _fileUriPath(file);
    if (path == null || path.isEmpty) return; // 在线流 → 回退比例

    final rms = await LoudnessMeter.fileRms(path);
    if (_disposed || seq != _measureSeq) return; // 已换曲，作废
    if (!_state.enabled || !_config.translationAutoVolume) return;
    _mainRms = rms;
    AppLogger.debug(
      '主轨响度: ${rms?.toStringAsFixed(4) ?? '不可测'} (${p.basename(path)})',
    );
    await _applyVolumes();
  }

  static String? _fileUriPath(Child file) {
    final raw = file.mediaDownloadUrl;
    if (raw == null || raw.isEmpty) return null;
    final parsed = Uri.tryParse(raw);
    if (parsed == null || !parsed.isScheme('file')) return null;
    return parsed.toFilePath();
  }

  /// 一段 TTS 的响度（起播后异步测，测到就补一次音量，不挡出声）。
  Future<void> _measureTtsClip(String path, int epoch) async {
    if (_disposed || !_config.translationAutoVolume) return;
    final rms = await LoudnessMeter.fileRms(path);
    if (_disposed || epoch != _epoch || !_state.enabled) return;
    _ttsRms = rms;
    await _applyVolumes();
  }

  // === 会话入口 ===

  /// 列表「翻译+播放」入口。
  Future<void> beginSession(EarSide ear) async {
    _state = _state.beginSession(ear);
    _syncManualVolume();
    _lastError = null;
    _spokenIndex = null;
    notifyListeners();
    await _applyVolumes();
    unawaited(_maybeMeasureMain());
    final cur = _subtitleService.currentSubtitle;
    if (cur != null) _onSubtitle(cur, force: true);
  }

  /// 普通播放入口：关翻译、清主耳、音量复位。
  Future<void> endSession() async {
    final was = _state.enabled;
    _state = _state.endSession();
    _syncManualVolume();
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
    _syncManualVolume();
    _lastError = null;
    if (!_state.enabled) {
      _epoch++;
      await _stopTtsPlayer();
      _spokenIndex = null;
    }
    notifyListeners();
    await _applyVolumes();
    if (_state.enabled) {
      unawaited(_maybeMeasureMain());
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
    _syncManualVolume();
    notifyListeners();
    await _applyVolumes();
  }

  /// 手动音量：全局配置 + 当前作品 album.json 都记（作品级优先读回）。
  ///
  /// [commit]=false 仅做拖动中的实时预览（不写配置/不写 album.json，
  /// 避免每帧一次 IO）；松手时用默认参数再调一次落盘。
  Future<void> setManualVolume(double volume, {bool commit = true}) async {
    final v = volume.clamp(0.0, 1.0);
    if (commit) {
      await _config.setSecondaryVolume(v); // 触发 listener（也会推一次音量）
    }
    _workVolume = v;
    _syncManualVolume();
    notifyListeners();
    final workId = _workId;
    final record = commit ? _recordWorkVolume : null;
    if (workId != null && record != null) {
      unawaited(() async {
        try {
          final ok = await record(workId, v);
          if (!ok) AppLogger.debug('作品音量记录未写入（非致命）: $workId');
        } catch (e) {
          AppLogger.warning('记录作品音量失败: $workId ($e)');
        }
      }());
    }
    await _applyVolumes();
  }

  /// 自动响度对齐开关（持久化到全局配置）。
  Future<void> setAutoVolume(bool value) =>
      _config.setTranslationAutoVolume(value);

  /// 把「作品记录 > 全局配置」的结果同步进当前 state。
  void _syncManualVolume() {
    final v = _workVolume ?? _config.secondaryVolume;
    if (_state.secondaryVolume != v) {
      _state = _state.withSecondaryVolume(v);
    }
  }

  /// seek 时由 UI 显式调用（PlayerViewModel.seek 桥接）。
  void notifySeek() => _resetSpeech('seek');

  Future<void> _applyVolumes() async {
    try {
      final plan = TranslationVolumePolicy.compute(
        state: _state,
        autoVolume: _config.translationAutoVolume,
        mainRms: _mainRms,
        ttsRms: _ttsRms,
      );
      await _audio.setVolume(plan.mainVolume);
      final tts = _ttsPlayer;
      if (tts != null) {
        await tts.setVolume(plan.translationVolume);
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
    // 新一段还没测：先按回退音量出声，测到再补（不阻塞起播）。
    _ttsRms = null;
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

      final plan = TranslationVolumePolicy.compute(
        state: _state,
        autoVolume: _config.translationAutoVolume,
        mainRms: _mainRms,
        ttsRms: null, // 本段未测 → 本段只用主轨那一侧的对齐结果
      );
      await player.setVolume(plan.translationVolume);
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
      unawaited(_measureTtsClip(path, epoch));
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
    _disposed = true;
    _config.removeListener(_onConfigChanged);
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
