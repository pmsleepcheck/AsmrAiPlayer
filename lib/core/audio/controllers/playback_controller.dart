import 'package:aaplay/utils/logger.dart';
import 'package:just_audio/just_audio.dart';
import '../models/playback_context.dart';
import '../state/playback_state_manager.dart';
import '../utils/playlist_builder.dart';
import '../utils/audio_error_handler.dart';
import '../events/playback_event_hub.dart';
import '../events/playback_event.dart';
import '../models/play_mode.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/works/work.dart';

class PlaybackController {
  final AudioPlayer _player;
  final PlaybackStateManager _stateManager;
  final ConcatenatingAudioSource _playlist;
  final PlaybackEventHub _eventHub;

  PlaybackController({
    required AudioPlayer player,
    required PlaybackStateManager stateManager,
    required ConcatenatingAudioSource playlist,
    required PlaybackEventHub eventHub,
  })  : _player = player,
        _stateManager = stateManager,
        _playlist = playlist,
        _eventHub = eventHub;

  // 基础播放控制
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> stop() => _player.stop();
  Future<void> seek(Duration position, {int? index}) =>
      _player.seek(position, index: index);

  // 播放列表控制
  Future<void> next() async {
    try {
      AppLogger.debug('尝试切换下一曲');
      if (_stateManager.currentContext == null) {
        AppLogger.debug('当前上下文为空，无法切换下一曲');
        return;
      }

      if (_player.hasNext) {
        AppLogger.debug('执行切换到下一曲');
        await _player.seekToNext();
      } else {
        AppLogger.debug('没有下一曲可切换');
      }
    } catch (e, stack) {
      AppLogger.error('切换下一曲失败', e, stack);
      _eventHub.emit(PlaybackErrorEvent('next', e, stack));
      AudioErrorHandler.handleError(
        AudioErrorType.playback,
        '切换下一曲',
        e,
        stack,
      );
    }
  }

  Future<void> previous() async {
    try {
      AppLogger.debug('尝试切换上一曲');
      if (_stateManager.currentContext == null) {
        AppLogger.debug('当前上下文为空，无法切换上一曲');
        return;
      }

      if (_player.hasPrevious) {
        AppLogger.debug('执行切换到上一曲');
        await _player.seekToPrevious();
      } else {
        AppLogger.debug('没有上一曲可切换');
      }
    } catch (e, stack) {
      AppLogger.error('切换上一曲失败', e, stack);
      _eventHub.emit(PlaybackErrorEvent('previous', e, stack));
      AudioErrorHandler.handleError(
        AudioErrorType.playback,
        '切换上一曲',
        e,
        stack,
      );
    }
  }

  // 串行化 setPlaybackContext：首帧后的 restorePlaybackState 与用户点播
  // 会并发调用 just_audio 的 stop/setAudioSource——交错可导致平台侧死锁/
  // 永久挂起（表现为 playWithContext 15s 超时）。同链排队后前一个结束
  // （成功或失败）才开下一个；失败只进日志，不卡住链尾。
  Future<void> _setContextChain = Future<void>.value();

  // 播放上下文设置
  Future<void> setPlaybackContext(PlaybackContext originalContext,
      {Duration? initialPosition}) {
    final run = _setContextChain.then((_) => _setPlaybackContext(
          originalContext,
          initialPosition: initialPosition,
        ));
    _setContextChain = run.then((_) {}, onError: (Object e, StackTrace s) {
      AppLogger.warning('setPlaybackContext 链内失败（不阻塞后续）: $e');
    });
    return run;
  }

  Future<void> _setPlaybackContext(PlaybackContext originalContext,
      {Duration? initialPosition}) async {
    try {
      AppLogger.debug(
          '准备设置播放上下文: workId=${originalContext.work.id}, file=${originalContext.currentFile.title}');
      AppLogger.debug(
          '播放列表状态: 长度=${originalContext.playlist.length}, 当前索引=${originalContext.currentIndex}');

      // 验证上下文
      try {
        originalContext.validate();
      } catch (e) {
        AppLogger.error('播放上下文验证失败', e);
        rethrow;
      }

      // 1. 先停止当前播放
      AppLogger.debug('停止当前播放');
      await _player.stop();

      // 2. 设置新的播放源
      AppLogger.debug('设置播放源: 初始位置=${initialPosition?.inMilliseconds}ms');
      List<Child> loadedFiles;
      try {
        loadedFiles = await PlaylistBuilder.setPlaylistSource(
          player: _player,
          playlist: _playlist,
          files: originalContext.playlist,
          initialIndex: originalContext.currentIndex,
          initialPosition: initialPosition ?? Duration.zero,
          workId: originalContext.work.id.toString(),
        );
      } catch (e, stack) {
        AppLogger.error('设置播放源失败', e, stack);
        rethrow;
      }

      // 3. 加载成功后更新上下文
      var context = originalContext;
      if (loadedFiles.length != originalContext.playlist.length) {
        final currentFile = loadedFiles.contains(originalContext.currentFile)
            ? originalContext.currentFile
            : loadedFiles.first;
        context = PlaybackContext.withFilteredPlaylist(
          work: originalContext.work,
          files: originalContext.files,
          currentFile: currentFile,
          playlist: loadedFiles,
          playMode: originalContext.playMode,
        );
      }
      _stateManager.updateContext(context);

      // Set loop mode based on play mode
      await _player.setLoopMode(context.playMode.toLoopMode());

      // 4. 更新轨道信息
      AppLogger.debug('更新轨道信息');
      _updateTrackAndContext(context.currentFile, context.work);

      AppLogger.debug('播放上下文设置完成');
    } catch (e, stack) {
      AppLogger.error('设置播放上下文失败', e, stack);
      _eventHub.emit(PlaybackErrorEvent('setPlaybackContext', e, stack));
      AudioErrorHandler.handleError(
        AudioErrorType.context,
        '设置播放上下文',
        e,
        stack,
      );
      rethrow;
    }
  }

  // 私有辅助方法
  void _updateTrackAndContext(Child file, Work work) {
    AppLogger.debug('更新轨道和上下文: file=${file.title}');
    _stateManager.updateTrackAndContext(file, work);
  }
}
