import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aaplay/core/audio/translation/loudness_meter.dart';

class StereoRmsResult {
  final double left;
  final double right;

  const StereoRmsResult({required this.left, required this.right});

  bool get isDegenerate => left <= 0 && right <= 0;

  /// 声强更高的一侧；退化（全 0）或差值过小视为无结论返回 null。
  ///
  /// 相对阈值：强侧至少比弱侧高 5%（或弱侧≈0），避免底噪抖动误判。
  String? get dominant {
    if (isDegenerate) return null;
    final hi = math.max(left, right);
    final lo = math.min(left, right);
    if (lo <= 0) return left >= right ? 'left' : 'right';
    if (hi / lo < 1.05) return null;
    return left > right ? 'left' : 'right';
  }

  Map<String, double> toJson() => {'left': left, 'right': right};
}

/// 纯 Dart 解析 16-bit PCM 立体声 WAV，输出左右声道 RMS（0..1）。
///
/// 仅支持：RIFF/WAVE、fmt PCM(1)/IEEE float(3)、16 或 32 bit、channels>=2。
/// 非 WAV / 不支持的格式返回 null——由调用方走「弹窗用户选择」兜底。
/// 样本过多时按步长抽样（约 20 万帧上限），避免整轨阻塞 UI 线程过久。
class WavStereoRms {
  static const int _maxFrames = 200000;

  /// [bytes] = 整个 WAV 文件内容；调用方负责读文件（且仅对 .wav 调用）。
  /// 头解析共用 `loudness_meter.dart` 的 [WavHeader]，与响度测量口径一致。
  static StereoRmsResult? analyze(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final header = WavHeader.parse(bytes, bytes.length);
    if (header == null || header.channels < 2 || !header.supported) {
      return null;
    }
    final data = ByteData.sublistView(bytes);
    final frameSize = header.frameSize;
    final totalFrames = header.dataLength ~/ frameSize;
    if (totalFrames <= 0) return null;

    final stride = math.max(1, totalFrames ~/ _maxFrames);
    var sumL = 0.0;
    var sumR = 0.0;
    var count = 0;

    for (var f = 0; f < totalFrames; f += stride) {
      final frameBase = header.dataOffset + f * frameSize;
      final l = header.readSample(data, frameBase);
      final r = header.readSample(
        data,
        frameBase + header.bytesPerSample,
      );
      if (l == null || r == null) break;
      sumL += l * l;
      sumR += r * r;
      count++;
    }
    if (count == 0) return null;

    return StereoRmsResult(
      left: math.sqrt(sumL / count),
      right: math.sqrt(sumR / count),
    );
  }
}
