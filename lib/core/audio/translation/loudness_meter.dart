import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:glint_audio_pure/glint_audio_pure.dart';

/// WAV 头信息（RIFF/WAVE，fmt `PCM=1` / `IEEE float=3`）。
///
/// 独立于「双耳检测」的 `WavStereoRms.analyze`，但两者共用这份解析
/// （`wav_stereo_rms.dart` 也调用 [WavHeader.parse]），保证判定一致。
class WavHeader {
  final int audioFormat;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;

  /// `data` chunk 起点（文件内绝对偏移，指向第一个采样字节）。
  final int dataOffset;

  /// `data` 长度：`min(chunk 里的 size, 文件总长 - dataOffset)`。
  /// Fish Audio 返回的 WAV 头是占位值（data size ≈ 4294967040），必须这样截断。
  final int dataLength;

  const WavHeader({
    required this.audioFormat,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.dataOffset,
    required this.dataLength,
  });

  bool get supported {
    if (channels < 1 || dataLength <= 0) return false;
    if (audioFormat == 1) {
      return bitsPerSample == 16 || bitsPerSample == 24 || bitsPerSample == 32;
    }
    if (audioFormat == 3) return bitsPerSample == 32;
    return false;
  }

  int get bytesPerSample => bitsPerSample ~/ 8;
  int get frameSize => bytesPerSample * channels;

  /// 从文件头部字节解析。[head] 不必包含整个 `data`，但必须含 `fmt ` 与
  /// `data` 的 chunk 头（常规 WAV 前几百字节即够）；[totalLength] 是整个
  /// 文件长度，用于截断 `data` 长度。
  static WavHeader? parse(Uint8List head, int totalLength) {
    if (head.length < 44) return null;
    if (!_fourCC(head, 0, 'RIFF') || !_fourCC(head, 8, 'WAVE')) return null;
    final data = ByteData.sublistView(head);

    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataOffset;
    int? dataLength;

    var pos = 12;
    while (pos + 8 <= head.length) {
      final id = _fourCCString(head, pos);
      final size = data.getUint32(pos + 4, Endian.little);
      final body = pos + 8;
      if (id == 'fmt ' && body + 16 <= head.length) {
        audioFormat = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bitsPerSample = data.getUint16(body + 14, Endian.little);
        // WAVE_FORMAT_EXTENSIBLE：真实格式在 SubFormat GUID 的头两字节。
        if (audioFormat == 0xFFFE && body + 26 <= head.length) {
          audioFormat = data.getUint16(body + 24, Endian.little);
        }
      } else if (id == 'data') {
        dataOffset = body;
        dataLength = math.min(size, totalLength - body);
        break;
      }
      // chunk 以偶数字节对齐
      pos = body + size + (size.isOdd ? 1 : 0);
    }

    if (audioFormat == null ||
        channels == null ||
        sampleRate == null ||
        bitsPerSample == null ||
        dataOffset == null ||
        dataLength == null) {
      return null;
    }
    return WavHeader(
      audioFormat: audioFormat,
      channels: channels,
      sampleRate: sampleRate,
      bitsPerSample: bitsPerSample,
      dataOffset: dataOffset,
      dataLength: dataLength,
    );
  }

  /// 读一个采样并归一到 `-1..1`；越界返回 null。
  double? readSample(ByteData data, int offset) {
    if (offset + bytesPerSample > data.lengthInBytes) return null;
    if (audioFormat == 3) {
      return data.getFloat32(offset, Endian.little);
    }
    if (bitsPerSample == 24) {
      // 24-bit 有符号 LE（ASMR 发布里最常见）。
      final b0 = data.getUint8(offset);
      final b1 = data.getUint8(offset + 1);
      final b2 = data.getUint8(offset + 2);
      var v = (b2 << 16) | (b1 << 8) | b0;
      if (v & 0x800000 != 0) v -= 0x1000000;
      return v / 8388608.0;
    }
    if (bitsPerSample == 32) {
      return data.getInt32(offset, Endian.little) / 2147483648.0;
    }
    return data.getInt16(offset, Endian.little) / 32768.0;
  }

  static bool _fourCC(Uint8List bytes, int offset, String tag) {
    if (offset + 4 > bytes.length) return false;
    for (var i = 0; i < 4; i++) {
      if (bytes[offset + i] != tag.codeUnitAt(i)) return false;
    }
    return true;
  }

  static String _fourCCString(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return '';
    final sb = StringBuffer();
    for (var i = 0; i < 4; i++) {
      sb.writeCharCode(bytes[offset + i]);
    }
    return sb.toString();
  }
}

/// 音频响度测量（线性 RMS，`0..1`）——翻译音量自动对齐的取数口。
///
/// - **WAV**：解析头部后按 10%/50%/90% 三处**分窗随机读**（60 分钟 wav 有
///   数百 MB，绝不整读），帧对齐 + 抽样。
/// - **MP3**：头（跳过 ID3v2）/中/尾各 ≤512KB 一窗，`glint_audio_pure` 纯
///   Dart 解码（逐字节 resync，可从任意偏移起解），结果按样本数加权合并；
///   解码跑在 [Isolate.run] 里，不卡 UI。
/// - 其它容器（flac/ogg/…）→ `null`，调用方回退固定比例。
/// - 结果按 `路径|大小|mtime` 进程内 LRU 缓存，重复切歌不重复解码。
class LoudnessMeter {
  LoudnessMeter._();

  static const int _headBytes = 64 * 1024;
  static const int _wavWindowBytes = 256 * 1024;

  /// mp3 抽样窗大小：纯 Dart 解码实测约 2.8s/MB，96KB×3 ≈ 0.8s（isolate 里跑，
  /// 且不阻塞起播——先按回退音量起播，测完再补一次 setVolume）。
  static const int _mp3WindowBytes = 96 * 1024;

  /// 小于此大小的 mp3（TTS 片段）整段解码，不抽窗。
  static const int _smallFileBytes = 2 * 1024 * 1024;

  static const int _maxCached = 64;

  /// 采样帧上限（每个 WAV 窗口内），避免超长文件算太久。
  static const int _maxFramesPerWindow = 60000;

  static final Map<String, double> _cache = <String, double>{};
  static final Map<String, Future<double?>> _inflight = {};

  @visibleForTesting
  static void clearCache() {
    _cache.clear();
    _inflight.clear();
  }

  @visibleForTesting
  static int get cacheSize => _cache.length;

  /// 量一个本地文件的响度；不支持/不可读/缓存未命中失败时返回 `null`。
  static Future<double?> fileRms(String path) async {
    final file = File(path);
    FileStat stat;
    try {
      stat = await file.stat();
    } catch (_) {
      return null;
    }
    if (stat.type == FileSystemEntityType.notFound) return null;

    final key =
        '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // LRU：重新插到末尾
      return hit;
    }
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _measure(file, stat.size);
    _inflight[key] = future;
    try {
      final rms = await future;
      if (rms != null) {
        _cache[key] = rms;
        _trim();
      }
      return rms;
    } finally {
      _inflight.remove(key);
    }
  }

  static Future<double?> _measure(File file, int size) async {
    switch (_extension(file.path)) {
      case 'wav':
        return _wavFileRms(file, size);
      case 'mp3':
        return _mp3FileRms(file, size);
      default:
        return null;
    }
  }

  static String _extension(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return '';
    return path.substring(i + 1).toLowerCase();
  }

  static void _trim() {
    while (_cache.length > _maxCached) {
      _cache.remove(_cache.keys.first);
    }
  }

  // === WAV ===

  static Future<double?> _wavFileRms(File file, int size) async {
    final raf = await file.open();
    try {
      await raf.setPosition(0);
      final head = await raf.read(math.min(_headBytes, size));
      final h = WavHeader.parse(head, size);
      if (h == null || !h.supported) return null;

      final dataEnd = h.dataOffset + h.dataLength;
      if (dataEnd <= h.dataOffset) return null;

      final windowBytes = math.min(_wavWindowBytes, h.dataLength);
      var sum = 0.0;
      var count = 0;
      for (final fraction in const [0.1, 0.5, 0.9]) {
        var start =
            h.dataOffset + ((h.dataLength - windowBytes) * fraction).round();
        // 帧对齐（首窗起点也对齐，避免相位错位读到半帧）。
        start -= (start - h.dataOffset) % h.frameSize;
        if (start < h.dataOffset || start >= dataEnd) continue;
        final len = math.min(windowBytes, dataEnd - start);
        if (len < h.frameSize) continue;
        await raf.setPosition(start);
        final buf = await raf.read(len);
        final r = _wavWindowRms(buf, h);
        if (r == null) continue;
        sum += r.$1;
        count += r.$2;
      }
      if (count == 0) return null;
      final rms = math.sqrt(sum / count);
      return rms.isFinite ? rms : null;
    } finally {
      await raf.close();
    }
  }

  /// 返回 `(平方和, 样本数)`；窗口内抽样至多 [_maxFramesPerWindow] 帧。
  static (double, int)? _wavWindowRms(Uint8List window, WavHeader h) {
    final data = ByteData.sublistView(window);
    final totalFrames = window.length ~/ h.frameSize;
    if (totalFrames <= 0) return null;
    final stride = math.max(1, totalFrames ~/ _maxFramesPerWindow);

    var sum = 0.0;
    var count = 0;
    for (var f = 0; f < totalFrames; f += stride) {
      final base = f * h.frameSize;
      var frameSum = 0.0;
      var ok = true;
      for (var c = 0; c < h.channels; c++) {
        final s = h.readSample(data, base + c * h.bytesPerSample);
        if (s == null) {
          ok = false;
          break;
        }
        frameSum += s * s;
      }
      if (!ok) break;
      // 各声道能量平均 = 单声道下混后的响度（耳路由是 mono downmix）。
      sum += frameSum / h.channels;
      count++;
    }
    if (count == 0) return null;
    return (sum, count);
  }

  // === MP3 ===

  static Future<double?> _mp3FileRms(File file, int size) async {
    if (size <= 0) return null;
    final windows = <Uint8List>[];
    final raf = await file.open();
    try {
      if (size <= _smallFileBytes) {
        await raf.setPosition(0);
        final all = await raf.read(size);
        if (all.isNotEmpty) windows.add(all);
      } else {
        final headStart = await id3v2End(raf, size);
        if (headStart < size) {
          await raf.setPosition(headStart);
          final w = await raf.read(math.min(_mp3WindowBytes, size - headStart));
          if (w.isNotEmpty) windows.add(w);
        }
        final mid = size ~/ 2;
        if (mid + 4 < size) {
          await raf.setPosition(mid);
          final w = await raf.read(math.min(_mp3WindowBytes, size - mid));
          if (w.isNotEmpty) windows.add(w);
        }
        final tailStart = size > _mp3WindowBytes ? size - _mp3WindowBytes : 0;
        await raf.setPosition(tailStart);
        final w = await raf.read(math.min(_mp3WindowBytes, size - tailStart));
        if (w.isNotEmpty) windows.add(w);
      }
    } finally {
      await raf.close();
    }
    if (windows.isEmpty) return null;
    // 解码是纯 CPU 大头 → isolate；windows 是可发送的字节列表。
    try {
      return await Isolate.run(() => mp3Rms(windows));
    } catch (e) {
      return null;
    }
  }

  /// 对若干 mp3 字节窗解码并按样本数加权合并 RMS（可在 isolate 中执行）。
  static double? mp3Rms(List<Uint8List> windows) {
    var sum = 0.0;
    var count = 0;
    for (final w in windows) {
      if (w.length < 64) continue;
      final Mp3Pcm pcm;
      try {
        pcm = mp3Decode(w);
      } catch (_) {
        continue; // 单个窗解不动就跳过，别的窗还有机会
      }
      final samples = pcm.samples;
      if (samples.isEmpty) continue;
      var local = 0.0;
      for (var i = 0; i < samples.length; i++) {
        final s = samples[i];
        local += s * s;
      }
      sum += local;
      count += samples.length;
    }
    if (count == 0) return null;
    final rms = math.sqrt(sum / count);
    return rms.isFinite ? rms : null;
  }

  /// ID3v2 标签后的第一个字节偏移（无标签返回 0，越界钳到 [size]）。
  /// `smart_ear_analyzer.dart` 扫 mp3 帧头前也用它跳标签。
  static Future<int> id3v2End(RandomAccessFile raf, int size) async {
    if (size < 10) return 0;
    await raf.setPosition(0);
    final head = await raf.read(10);
    if (head.length < 10) return 0;
    if (head[0] != 0x49 || head[1] != 0x44 || head[2] != 0x33) return 0; // 'ID3'
    // syncsafe integer：每字节只取低 7 位。
    final tagBytes = ((head[6] & 0x7F) << 21) |
        ((head[7] & 0x7F) << 14) |
        ((head[8] & 0x7F) << 7) |
        (head[9] & 0x7F);
    final footer = (head[5] & 0x10) != 0 ? 10 : 0;
    final end = 10 + tagBytes + footer;
    return end >= size ? size : end;
  }
}
