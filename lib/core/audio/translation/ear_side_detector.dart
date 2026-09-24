import 'dart:io';
import 'dart:typed_data';

import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/utils/logger.dart';
import 'ear_mark_repository.dart';
import 'ear_side.dart';
import 'ear_side_filename_detector.dart';
import 'wav_stereo_rms.dart';

/// 检测结果来源（用于日志/调试；用户感知层面只有「有侧」或「弹窗」）。
enum EarDetectSource {
  /// 用户既有标记。
  mark,

  /// 文件名启发式。
  filename,

  /// 本地 WAV 左右声道声强。
  waveform,

  /// 无法判定，需弹窗。
  unknown,
}

class EarDetectResult {
  final EarSide? side;
  final EarDetectSource source;

  const EarDetectResult(this.side, this.source);

  bool get needsPrompt => side == null;
}

/// 左右耳检测链：用户标记 → 文件名 → 本地立体声 WAV RMS → 弹窗兜底。
///
/// [keys] = 持久化键，通常传 `DownloadService.candidateKeys(file)`；
/// 缺省时退化为 `file.title`（弱键，仅测试/无 download 层上下文用）。
class EarSideDetector {
  final EarMarkRepository marks;

  /// [resolveLocalPath]：给定音频 Child 返回本地绝对路径（未下载 → null）。
  /// 由调用方注入（DownloadService），便于单测注入假实现。
  final Future<String?> Function(Child file)? resolveLocalPath;

  EarSideDetector({
    required this.marks,
    this.resolveLocalPath,
  });

  Future<EarDetectResult> detect(
    Child file, {
    List<String>? keys,
    Future<String?> Function(Child file)? resolveLocalPath,
  }) async {
    final effective =
        (keys != null && keys.isNotEmpty) ? keys : _fallbackKeys(file);

    for (final k in effective) {
      final marked = marks.get(k);
      if (marked != null) {
        return EarDetectResult(marked, EarDetectSource.mark);
      }
    }

    final byName = EarSideFilenameDetector.detect(file.title);
    if (byName != null) {
      await _persistKeys(effective, byName);
      return EarDetectResult(byName, EarDetectSource.filename);
    }

    final byWave = await _detectByWaveform(file, resolveLocalPath);
    if (byWave != null) {
      await _persistKeys(effective, byWave);
      return EarDetectResult(byWave, EarDetectSource.waveform);
    }

    return const EarDetectResult(null, EarDetectSource.unknown);
  }

  /// 弹窗用户选择后的落库入口。
  Future<void> persistChoice(Child file, EarSide side, {List<String>? keys}) {
    final effective =
        (keys != null && keys.isNotEmpty) ? keys : _fallbackKeys(file);
    return _persistKeys(effective, side);
  }

  List<String> _fallbackKeys(Child file) {
    final title = file.title;
    if (title == null || title.isEmpty) return const [];
    return [title];
  }

  Future<void> _persistKeys(List<String> keys, EarSide side) async {
    for (final k in keys) {
      try {
        await marks.mark(k, side);
      } catch (e) {
        AppLogger.warning('耳侧标记写入失败 $k: $e');
      }
    }
  }

  Future<EarSide?> _detectByWaveform(
    Child file,
    Future<String?> Function(Child file)? override,
  ) async {
    final resolver = override ?? resolveLocalPath;
    if (resolver == null) return null;
    String? path;
    try {
      path = await resolver(file);
    } catch (e) {
      AppLogger.warning('解析本地路径失败（跳过波形检测）: $e');
      return null;
    }
    if (path == null) return null;
    if (!path.toLowerCase().endsWith('.wav')) return null;
    try {
      final bytes = await File(path).readAsBytes();
      final rms = WavStereoRms.analyze(Uint8List.fromList(bytes));
      if (rms == null) return null;
      final dominant = rms.dominant;
      if (dominant == 'left') return EarSide.left;
      if (dominant == 'right') return EarSide.right;
      return null;
    } catch (e) {
      AppLogger.warning('WAV 波形耳侧检测失败: $e');
      return null;
    }
  }
}
