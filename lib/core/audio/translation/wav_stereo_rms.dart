import 'dart:math' as math;
import 'dart:typed_data';

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
  static StereoRmsResult? analyze(Uint8List bytes) {
    if (bytes.length < 44) return null;
    final data = ByteData.sublistView(bytes);

    // RIFF....WAVE
    if (!_fourCC(data, 0, 'RIFF') || !_fourCC(data, 8, 'WAVE')) return null;

    int? audioFormat;
    int? numChannels;
    int? bitsPerSample;
    int? dataOffset;
    int? dataLength;

    var pos = 12;
    while (pos + 8 <= bytes.length) {
      final chunkId = _fourCCString(data, pos);
      final chunkSize = data.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (chunkId == 'fmt ' && body + 16 <= bytes.length) {
        audioFormat = data.getUint16(body, Endian.little);
        numChannels = data.getUint16(body + 2, Endian.little);
        bitsPerSample = data.getUint16(body + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = body;
        dataLength = math.min(chunkSize, bytes.length - body);
        break;
      }
      // chunk 以偶数字节对齐
      pos = body + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (audioFormat == null ||
        numChannels == null ||
        bitsPerSample == null ||
        dataOffset == null ||
        dataLength == null) {
      return null;
    }
    if (numChannels < 2) return null;
    if (audioFormat != 1 && audioFormat != 3) return null;
    if (bitsPerSample != 16 && bitsPerSample != 32) return null;
    if (dataLength <= 0) return null;

    final bytesPerSample = bitsPerSample ~/ 8;
    final frameSize = bytesPerSample * numChannels;
    final totalFrames = dataLength ~/ frameSize;
    if (totalFrames <= 0) return null;

    final stride = math.max(1, totalFrames ~/ _maxFrames);
    var sumL = 0.0;
    var sumR = 0.0;
    var count = 0;

    for (var f = 0; f < totalFrames; f += stride) {
      final frameBase = dataOffset + f * frameSize;
      final l = _readSample(data, frameBase, audioFormat, bitsPerSample);
      final r = _readSample(
        data,
        frameBase + bytesPerSample,
        audioFormat,
        bitsPerSample,
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

  static double? _readSample(
    ByteData data,
    int offset,
    int audioFormat,
    int bitsPerSample,
  ) {
    if (offset + bitsPerSample ~/ 8 > data.lengthInBytes) return null;
    if (audioFormat == 3) {
      return data.getFloat32(offset, Endian.little);
    }
    // PCM 16
    return data.getInt16(offset, Endian.little) / 32768.0;
  }

  static bool _fourCC(ByteData data, int offset, String tag) {
    if (offset + 4 > data.lengthInBytes) return false;
    for (var i = 0; i < 4; i++) {
      if (data.getUint8(offset + i) != tag.codeUnitAt(i)) return false;
    }
    return true;
  }

  static String _fourCCString(ByteData data, int offset) {
    if (offset + 4 > data.lengthInBytes) return '';
    final sb = StringBuffer();
    for (var i = 0; i < 4; i++) {
      sb.writeCharCode(data.getUint8(offset + i));
    }
    return sb.toString();
  }
}
