import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/utils/logger.dart';

/// 睡眠定时器：选定时长后到点自动 **暂停** 播放（用 `pause()` 而非
/// `stop()`——`stop()` 会清空持久化播放态，睡眠场景需可恢复）。
///
/// 刻意 **不持久化**：这是会话级控制，重启后静默重新计时是坏 UX，
/// 也避开 `playback_state` 持久化不变量。
///
/// UI 显示 **剩余时间**（[remaining]，1s ticker 刷新），不是固定总时长。
class SleepTimerController extends ChangeNotifier {
  static const _tag = 'SleepTimer';

  /// 可选时长档（分钟）。`null` 即对话框里的「关闭」。
  static const List<int> presetMinutes = [15, 30, 45, 60, 90];

  final IAudioPlayerService _audioService;

  Timer? _timer;
  Timer? _ticker;
  int? _minutes;
  Duration _remaining = Duration.zero;

  SleepTimerController(this._audioService);

  /// 当前选定时长（分钟）；`null` = 未设置/已关闭。
  int? get minutes => _minutes;

  bool get isActive => _timer != null;

  /// 距离到点的剩余时间；未激活时为零。
  Duration get remaining => isActive ? _remaining : Duration.zero;

  /// 设置定时时长。`null` 或 `<= 0` = 取消。重复设置会先取消旧 Timer。
  void setMinutes(int? minutes) {
    _timer?.cancel();
    _timer = null;
    _ticker?.cancel();
    _ticker = null;

    if (minutes == null || minutes <= 0) {
      final wasActive = _minutes != null || _remaining > Duration.zero;
      _minutes = null;
      _remaining = Duration.zero;
      if (wasActive) notifyListeners();
      return;
    }

    _minutes = minutes;
    _remaining = Duration(minutes: minutes);
    _timer = Timer(_remaining, _onExpire);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    notifyListeners();
  }

  void cancel() => setMinutes(null);

  void _onTick() {
    if (_remaining <= Duration.zero) return;
    final next = _remaining - const Duration(seconds: 1);
    _remaining = next.isNegative ? Duration.zero : next;
    notifyListeners();
  }

  void _onExpire() {
    _timer = null;
    _ticker?.cancel();
    _ticker = null;
    _minutes = null;
    _remaining = Duration.zero;
    notifyListeners();
    _audioService.pause().catchError(
          (Object e) => AppLogger.error('[$_tag] 到点暂停失败', e),
        );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }
}
