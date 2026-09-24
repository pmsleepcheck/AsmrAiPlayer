import './models/audio_track_info.dart';
import './models/playback_context.dart';

abstract class IAudioPlayerService {
  // 基础播放控制
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> previous();
  Future<void> next();
  Future<void> dispose();

  /// 主音轨音量（0..1）。翻译混播的主次 emphasis 用；实现应 best-effort，
  /// 失败不抛到调用方 UI 主路径（由实现内部收敛）。
  Future<void> setVolume(double volume);

  // 上下文管理
  Future<void> playWithContext(PlaybackContext context);

  // 状态访问
  AudioTrackInfo? get currentTrack;
  PlaybackContext? get currentContext;

  // 状态持久化
  Future<void> savePlaybackState();
  Future<void> restorePlaybackState();
}
