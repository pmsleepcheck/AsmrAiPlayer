import 'package:aaplay/core/audio/events/playback_event.dart';
import 'package:aaplay/core/audio/models/audio_track_info.dart';
import 'package:aaplay/core/audio/models/playback_context.dart';
import 'package:aaplay/core/audio/models/file_path.dart';
import 'package:aaplay/core/subtitle/i_subtitle_service.dart';
import 'package:aaplay/core/subtitle/utils/subtitle_matcher.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/core/audio/models/subtitle.dart';
import 'dart:async';
import 'package:aaplay/core/subtitle/subtitle_loader.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/core/audio/events/playback_event_hub.dart';
import 'package:just_audio/just_audio.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/core/subtitle/subtitle_import_service.dart';
import 'package:aaplay/core/audio/translation/translation_session_controller.dart';
import 'package:rxdart/rxdart.dart';

class PlayerViewModel extends ChangeNotifier {
  final IAudioPlayerService _audioService;
  final PlaybackEventHub _eventHub;
  final ISubtitleService _subtitleService;
  // late：字幕相关字段只在导入/移除字幕路径用到，
  // 首次访问才向 GetIt 取值，VM 层单测无需为它们注册依赖。
  late final _subtitleLoader = GetIt.I<SubtitleLoader>();
  late final _importService = GetIt.I<SubtitleImportService>();
  late final _downloadService = GetIt.I<DownloadService>();

  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isToggling = false;
  String? _errorMessage;
  bool _isUserImportedSubtitle = false;
  int _loadVersion = 0;
  // position 是 5Hz 高频字段，单独走 ValueNotifier 而不进 notifyListeners()：
  // 全应用只有 mini_player_progress/waveform_progress 两个 widget 在 build
  // 期读它，若跟其余低频字段（标题/封面/isPlaying）合用 notifyListeners()，
  // 播放时挂在同一个 PlayerViewModel 上的所有订阅者（含 mini player 的两个
  // Hero、封面图、MiniPlayerControls 等）都会被拖进每秒 5 次的重建。
  final _positionNotifier = ValueNotifier<Duration?>(null);
  Duration? _duration;
  Subtitle? _currentSubtitle;

  final List<StreamSubscription> _subscriptions = [];

  static const _tag = 'PlayerViewModel';

  PlayerViewModel({
    required IAudioPlayerService audioService,
    required PlaybackEventHub eventHub,
    required ISubtitleService subtitleService,
  })  : _audioService = audioService,
        _eventHub = eventHub,
        _subtitleService = subtitleService {
    _initStreams();
    _requestInitialState();
  }

  void _initStreams() {
    // 播放状态事件 - 状态变化时通知（播放/暂停/缓冲等）
    _subscriptions.add(
      _eventHub.playbackState.listen(
        (event) {
          _isPlaying = event.state.playing;
          _positionNotifier.value =
              event.position; // fallback position for pause/resume
          _duration = event.duration;
          _isBuffering =
              event.state.processingState == ProcessingState.buffering ||
                  event.state.processingState == ProcessingState.loading;
          notifyListeners();
        },
        onError: (error) => debugPrint('$_tag - 播放状态流错误: $error'),
      ),
    );

    // 音轨变更事件
    _subscriptions.add(
      _eventHub.trackChange.listen(
        (event) {
          notifyListeners();
        },
        onError: (error) => debugPrint('$_tag - 音轨变更流错误: $error'),
      ),
    );

    // 播放进度 - UI更新路径：节流到200ms，减少rebuild频率。
    // 只写 positionNotifier，不再 notifyListeners()——避免 5Hz 广播波及
    // 不读 position 的订阅者（见字段声明处注释）。
    _subscriptions.add(
      _eventHub.playbackProgress
          .throttleTime(const Duration(milliseconds: 200))
          .listen(
        (event) {
          _positionNotifier.value = event.position;
        },
        onError: (error) => debugPrint('$_tag - 播放进度流错误: $error'),
      ),
    );

    // 播放进度 - 字幕同步路径：保持全精度，不触发rebuild
    _subscriptions.add(
      _eventHub.playbackProgress.listen(
        (event) {
          _subtitleService.updatePosition(event.position);
        },
        onError: (error) => debugPrint('$_tag - 字幕同步流错误: $error'),
      ),
    );

    // 上下文变更事件
    _subscriptions.add(
      _eventHub.contextChange.listen(
        (event) async {
          await _loadSubtitleIfAvailable(event.context);
          final position = _positionNotifier.value;
          if (position != null) {
            _subtitleService.updatePosition(position);
          }
        },
        onError: (error) => debugPrint('$_tag - 上下文流错误: $error'),
      ),
    );

    // 初始状态流
    _subscriptions.add(
      _eventHub.initialState.listen(
        (event) {
          if (event.track != null) {
            notifyListeners();
          }
          if (event.context != null) {
            _loadSubtitleIfAvailable(event.context!);
          }
        },
        onError: (error) => debugPrint('$_tag - 初始状态流错误: $error'),
      ),
    );

    // 错误事件
    _subscriptions.add(
      _eventHub.errors.listen(
        (event) {
          _errorMessage = '播放错误: ${event.operation}';
          AppLogger.error(
              '播放错误事件: ${event.operation}', event.error, event.stackTrace);
          notifyListeners();
        },
        onError: (error) => debugPrint('$_tag - 错误事件流错误: $error'),
      ),
    );

    // 清空状态事件
    _subscriptions.add(
      _eventHub.playbackCleared.listen(
        (_) {
          _isPlaying = false;
          _isBuffering = false;
          _positionNotifier.value = null;
          _duration = null;
          _isUserImportedSubtitle = false;
          _subtitleService.clearSubtitle();
          notifyListeners();
        },
        onError: (error) => debugPrint('$_tag - 清空状态流错误: $error'),
      ),
    );

    // 播放完成事件
    _subscriptions.add(
      _eventHub.playbackCompleted.listen(
        (event) {
          _isPlaying = false;
          notifyListeners();
        },
        onError: (error) => debugPrint('$_tag - 播放完成流错误: $error'),
      ),
    );

    _initSubtitleStreams();
  }

  void _initSubtitleStreams() {
    _subscriptions.add(
      _subtitleService.subtitleStream.listen(
        (subtitleList) {
          debugPrint('$_tag - 字幕列表更新: ${subtitleList != null ? '已加载' : '未加载'}');
        },
        onError: (error) => debugPrint('$_tag - 字幕流错误: $error'),
      ),
    );

    _subscriptions.add(
      _subtitleService.currentSubtitleStream.listen(
        (subtitle) {
          _currentSubtitle = subtitle;
          notifyListeners();
        },
        onError: (error) => debugPrint('$_tag - 当前字幕流错误: $error'),
      ),
    );
  }

  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  String? get errorMessage => _errorMessage;
  bool get isUserImportedSubtitle => _isUserImportedSubtitle;
  Duration? get position => _positionNotifier.value;
  ValueListenable<Duration?> get positionListenable => _positionNotifier;
  Duration? get duration => _duration;
  Subtitle? get currentSubtitle => _currentSubtitle;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> playPause() async {
    if (_isToggling) return;
    _isToggling = true;
    try {
      if (_isPlaying) {
        await _audioService.pause();
      } else {
        // just_audio's play() Future only completes when playback later
        // pauses/stops, so awaiting resume() here would pin _isToggling and
        // make the next pause tap a no-op. Fire it; playbackState events
        // drive the UI. resume()/play() has no internal error wrapper, so
        // route failures to the existing PlaybackErrorEvent path.
        unawaited(_audioService.resume().catchError((Object e, StackTrace st) {
          _eventHub.emit(PlaybackErrorEvent('resume', e, st));
        }));
      }
    } finally {
      _isToggling = false;
    }
  }

  Future<void> seek(Duration position) async {
    // 翻译轨：跳变后废弃在途 TTS 行，避免朗读过期字幕。
    try {
      GetIt.I<TranslationSessionController>().notifySeek();
    } catch (_) {
      // DI 未注册（纯单测）时忽略。
    }
    await _audioService.seek(position);
  }

  Future<void> previous() async {
    await _audioService.previous();
  }

  Future<void> next() async {
    await _audioService.next();
  }

  Future<void> stop() async {
    await _audioService.stop();
  }

  @override
  void dispose() {
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _positionNotifier.dispose();
    super.dispose();
  }

  // 请求初始状态
  void _requestInitialState() {
    Future.microtask(() {
      _eventHub.emit(RequestInitialStateEvent());
    });
  }

  Future<void> _loadSubtitleIfAvailable(PlaybackContext context) async {
    final version = ++_loadVersion;
    final workId = context.work.id?.toString();
    final files = context.files;
    final fileName = context.currentFile.title;
    _isUserImportedSubtitle = false;

    // 1. album.json 已记录匹配（手工选择 / 历史自动结果）优先，
    //    避免自动链每次重算覆盖用户显式指定。
    Child? subtitleFile;
    String? audioPath;
    if (workId != null && fileName != null) {
      audioPath = FilePath.getPath(context.currentFile, files);
      if (audioPath != null) {
        final matches = await _downloadService.readSubtitleMatches(workId);
        if (_loadVersion != version) return;
        final recorded = matches[audioPath];
        if (recorded != null) {
          subtitleFile = FilePath.childByPath(files, recorded);
          if (subtitleFile != null &&
              SubtitleMatcher.isSubtitleFile(subtitleFile.title)) {
            AppLogger.debug('字幕命中 album.json 记录: $recorded');
          } else {
            subtitleFile = null;
          }
        }
      }
    }

    // 2. 自动链 ①全名 ②规范化 ③去字符模糊（同目录 → 全树）；命中补写记录。
    if (subtitleFile == null && fileName != null) {
      subtitleFile = _subtitleLoader.findSubtitleFile(context.currentFile, files);
      if (subtitleFile != null &&
          workId != null &&
          audioPath != null) {
        final subPath = FilePath.getPath(subtitleFile, files);
        if (subPath != null) {
          await _downloadService.recordSubtitleMatch(
            workId,
            audioPath: audioPath,
            subtitlePath: subPath,
            overwrite: false,
          );
          if (_loadVersion != version) return;
        }
      }
    }

    if (subtitleFile == null) {
      // 3. 用户导入兜底（user_subtitles，外部文件不在树内）。
      if (workId != null && fileName != null) {
        final entry = await _importService.findImported(workId, fileName);
        if (_loadVersion != version) return;
        if (entry != null) {
          final subtitleList =
              await _importService.loadLocalSubtitle(entry.subtitlePath);
          if (_loadVersion != version) return;
          if (subtitleList != null) {
            await _subtitleService.loadSubtitleFromContent(subtitleList);
            if (_loadVersion != version) return;
            _isUserImportedSubtitle = true;
            notifyListeners();
            return;
          }
          await _importService.removeImportedSubtitle(workId, fileName);
          if (_loadVersion != version) return;
        }
      }
      _subtitleService.clearSubtitle();
      AppLogger.debug('未找到字幕文件，清除现有字幕');
      return;
    }

    await _loadSubtitleContent(workId, subtitleFile, version);
  }

  /// 已下载本地字幕（离线）→ 在线 URL。
  Future<void> _loadSubtitleContent(
    String? workId,
    Child subtitleFile,
    int version,
  ) async {
    if (workId != null) {
      final localPath =
          await _downloadService.localPathIfDownloaded(workId, subtitleFile);
      if (_loadVersion != version) return;
      if (localPath != null) {
        final list = await _importService.loadLocalSubtitle(localPath);
        if (_loadVersion != version) return;
        if (list != null) {
          await _subtitleService.loadSubtitleFromContent(list);
          AppLogger.debug('使用已下载本地字幕: $localPath');
          return;
        }
      }
    }

    if (subtitleFile.mediaDownloadUrl != null) {
      await _subtitleService.loadSubtitle(subtitleFile.mediaDownloadUrl!);
    } else {
      _subtitleService.clearSubtitle();
      AppLogger.debug('字幕文件无可用 URL，清除现有字幕');
    }
  }

  /// 手工选择：写 album.json（覆盖）并立即加载该字幕。
  Future<bool> assignSubtitleFromAlbum(Child subtitleChild) async {
    final context = currentContext;
    if (context == null) return false;
    final workId = context.work.id?.toString();
    final files = context.files;
    if (workId == null) return false;

    final audioPath = FilePath.getPath(context.currentFile, files);
    final subPath = FilePath.getPath(subtitleChild, files);
    if (audioPath == null || subPath == null) return false;

    final ok = await _downloadService.recordSubtitleMatch(
      workId,
      audioPath: audioPath,
      subtitlePath: subPath,
      overwrite: true,
    );
    if (!ok) AppLogger.warning('字幕已生效，但写入 album.json 失败');

    final version = ++_loadVersion;
    await _loadSubtitleContent(workId, subtitleChild, version);
    _isUserImportedSubtitle = false;
    notifyListeners();
    return true;
  }

  /// 手工选择（详情页，不依赖正在播放）：只写 album.json 记录。
  Future<bool> recordSubtitleMatchFor(
    Child audio,
    Child subtitle, {
    required Files files,
    required String workId,
  }) async {
    final audioPath = FilePath.getPath(audio, files);
    final subPath = FilePath.getPath(subtitle, files);
    if (audioPath == null || subPath == null) return false;
    return _downloadService.recordSubtitleMatch(
      workId,
      audioPath: audioPath,
      subtitlePath: subPath,
      overwrite: true,
    );
  }

  /// Import a subtitle file for the current audio.
  Future<ImportResult> importSubtitle() async {
    final context = currentContext;
    if (context == null) return ImportResult.cancelled;

    final workId = context.work.id?.toString();
    final fileName = context.currentFile.title;
    if (workId == null || fileName == null) return ImportResult.cancelled;

    final response = await _importService.importSubtitle(workId, fileName);
    if (response.result == ImportResult.success &&
        response.subtitleList != null) {
      // Verify we're still on the same track
      final currentWorkId = currentContext?.work.id?.toString();
      final currentFileName = currentContext?.currentFile.title;
      if (currentWorkId == workId && currentFileName == fileName) {
        await _subtitleService.loadSubtitleFromContent(response.subtitleList!);
        _isUserImportedSubtitle = true;
        notifyListeners();
      }
    }
    return response.result;
  }

  /// Remove imported subtitle and fall back to auto-match.
  Future<void> removeImportedSubtitle() async {
    final context = currentContext;
    if (context == null) return;

    final workId = context.work.id?.toString();
    final fileName = context.currentFile.title;
    if (workId == null || fileName == null) return;

    await _importService.removeImportedSubtitle(workId, fileName);
    _isUserImportedSubtitle = false;
    await _loadSubtitleIfAvailable(context);
  }

  AudioTrackInfo? get currentTrackInfo => _audioService.currentTrack;
  PlaybackContext? get currentContext => _audioService.currentContext;

  Future<void> seekToNextLyric() async {
    final currentSubtitle = _subtitleService.currentSubtitleWithState;
    final subtitleList = _subtitleService.subtitleList;

    if (currentSubtitle != null && subtitleList != null) {
      final nextSubtitle = currentSubtitle.subtitle.getNext(subtitleList);
      if (nextSubtitle != null) {
        await seek(nextSubtitle.start);
      }
    }
  }

  Future<void> seekToPreviousLyric() async {
    final currentSubtitle = _subtitleService.currentSubtitleWithState;
    final subtitleList = _subtitleService.subtitleList;

    if (currentSubtitle != null && subtitleList != null) {
      final previousSubtitle =
          currentSubtitle.subtitle.getPrevious(subtitleList);
      if (previousSubtitle != null) {
        await seek(previousSubtitle.start);
      }
    }
  }
}
