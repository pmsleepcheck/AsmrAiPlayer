import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:glint_audio_pure/glint_audio_pure.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ear_side.dart';
import 'loudness_meter.dart';

/// 智能耳分析状态（翻译页「智能(实验)」开关旁边的状态文案取数口）。
enum SmartEarStatus {
  /// 未开启 / 无曲目。
  idle,

  /// 分析中（后台 isolate + 磁盘缓存）。
  analyzing,

  /// 已就绪：逐句路由用 [EarTimeline]。
  ready,

  /// 不支持：拿不到本地文件（在线流）或容器无法解码（flac/ogg/…）。
  unsupported,

  /// 分析异常（文件不可读等）；回退固定耳。
  failed,
}

/// 智能耳时间线：随时间变化的「当前内容在哪只耳」。
///
/// 每个时间窗一个判定：
/// - [EarSide.left] / [EarSide.right] = 内容更响的一侧（翻译路由到**对侧**）；
/// - `null` = 左右等响 / 近静音 / 该窗解不出来 → 调用方按「一句左一句右」轮播。
class EarTimeline {
  const EarTimeline({
    required this.windowMs,
    required this.durationMs,
    required this.sides,
  });

  factory EarTimeline.fromJson(Map<String, dynamic> json) => EarTimeline(
        windowMs: (json['windowMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        sides: decodeSides((json['sides'] as String?) ?? ''),
      );

  final int windowMs;
  final int durationMs;

  /// 与时间轴一一对应的时间窗（`sides[i]` 覆盖 `[i*windowMs, (i+1)*windowMs)`）。
  final List<EarSide?> sides;

  int get windowCount => sides.length;

  /// 某毫秒时刻的内容耳；越界钳到首/尾窗，缺数据返回 null（→ 轮播）。
  EarSide? sideAt(int ms) {
    if (sides.isEmpty || windowMs <= 0) return null;
    var i = ms ~/ windowMs;
    if (i < 0) i = 0;
    if (i >= sides.length) i = sides.length - 1;
    return sides[i];
  }

  /// 落盘编码：`L`/`R`/`.`（等响或未知），比 JSON 数组省一个数量级空间。
  String encodeSides() => sides.map((s) {
        if (s == EarSide.left) return 'L';
        if (s == EarSide.right) return 'R';
        return '.';
      }).join();

  static List<EarSide?> decodeSides(String raw) => [
        for (final c in raw.split(''))
          c == 'L'
              ? EarSide.left
              : c == 'R'
                  ? EarSide.right
                  : null,
      ];

  Map<String, dynamic> toJson() => {
        'v': 1,
        'windowMs': windowMs,
        'durationMs': durationMs,
        'sides': encodeSides(),
      };
}

/// 智能耳（实验）分析器：本地 wav/mp3 的**逐窗左右 RMS** → [EarTimeline]。
///
/// - **WAV**：分窗随机读（1s 窗，每窗抽样 ≤1024 帧），一次读覆盖 8 个窗，
///   60 分钟文件也只有几百次 IO，不整读。
/// - **MP3**：两遍法 —— ① 顺序扫帧头（MPEG-1 Layer III，`mp3FrameSize`）
///   累加时间轴、记下每 5s 窗的字节偏移；② 按偏移抽 12KB 片 →
///   `Isolate.run(mp3Decode)` 分批解码算分声道 RMS。纯 Dart 解码很贵
///   （≈2.8s/MB），所以只解抽样片、且跑在 isolate。
/// - 其它容器（flac/ogg/…）→ `null` = 不支持，调用方回退固定耳。
/// - 结果按 `sha1(path|size|mtime)` 落盘缓存（`ear_analysis/<hash>.json`）+
///   进程内 LRU；同文件只算一次。
class SmartEarAnalyzer {
  SmartEarAnalyzer._();

  /// WAV 分窗粒度：1s（句子本身就是秒级，足够）。
  static const int wavWindowMs = 1000;

  /// 每个 WAV 窗抽样的帧数（≈23ms@44.1k）：只求方向，不要完整包络。
  static const int wavSampleFrames = 1024;

  /// 一次 IO 覆盖几个 WAV 窗（合并顺序读，减少随机 seek）。
  static const int wavWindowsPerRead = 8;

  /// MP3 分窗粒度：抽样解码贵，用 5s 粗窗。
  static const int mp3WindowMs = 5000;

  /// MP3 每窗抽样片：12KB ≈ 0.6s@192kbps，够算 RMS。
  static const int mp3SampleBytes = 12 * 1024;

  /// 解码分批大小（isolate 往返开销 vs 内存）。
  static const int mp3DecodeBatch = 24;

  /// 扫帧时的读块大小。
  static const int mp3ScanChunkBytes = 256 * 1024;

  static const int _headBytes = 64 * 1024;

  /// 与 `WavStereoRms.dominant` 同口径：强侧至少高 5% 才算「有方向」。
  static const double dominantRatio = 1.05;

  /// 小于该 RMS 视为静音/无效（与 `TranslationVolumePolicy` 同量级）。
  static const double invalidRms = 1e-4;

  static const String cacheDirName = 'ear_analysis';

  static const int _maxMemCached = 16;

  static final Map<String, EarTimeline> _mem = {};
  static final Map<String, Future<EarTimeline?>> _inflight = {};

  @visibleForTesting
  static void clearCache() {
    _mem.clear();
    _inflight.clear();
  }

  /// 单窗判定（纯函数）：内容耳 / 等响(null)。
  ///
  /// 静音或近静音 → null（等响），调用方轮播 —— 没有方向信息时轮播
  /// 正是「一句左一句右」的兜底。
  static EarSide? classify(double left, double right) {
    if (!left.isFinite || !right.isFinite) return null;
    if (left < invalidRms && right < invalidRms) return null;
    final hi = math.max(left, right);
    final lo = math.min(left, right);
    if (lo <= 0) return left >= right ? EarSide.left : EarSide.right;
    if (hi / lo < dominantRatio) return null;
    return left > right ? EarSide.left : EarSide.right;
  }

  /// 分析本地文件（带磁盘缓存 + 在途去重）。
  ///
  /// [cacheDirResolver] 缺省走 `getApplicationSupportDirectory()`；返回
  /// `null` 表示不支持/失败（调用方回退固定耳，不报错）。
  static Future<EarTimeline?> analyze(
    String path, {
    Future<Directory> Function()? cacheDirResolver,
  }) async {
    final file = File(path);
    FileStat stat;
    try {
      stat = await file.stat();
    } catch (_) {
      return null;
    }
    if (stat.type == FileSystemEntityType.notFound) return null;

    final key = sha1
        .convert(utf8.encode(
            '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}'))
        .toString();

    final hit = _mem.remove(key);
    if (hit != null) {
      _mem[key] = hit; // LRU：重新插到末尾
      return hit;
    }
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _analyzeCached(file, key, cacheDirResolver);
    _inflight[key] = future;
    try {
      final timeline = await future;
      if (timeline != null) {
        _mem[key] = timeline;
        while (_mem.length > _maxMemCached) {
          _mem.remove(_mem.keys.first);
        }
      }
      return timeline;
    } finally {
      _inflight.remove(key);
    }
  }

  static Future<EarTimeline?> _analyzeCached(
    File file,
    String key,
    Future<Directory> Function()? cacheDirResolver,
  ) async {
    Directory? cacheDir;
    try {
      cacheDir = await _resolveCacheDir(cacheDirResolver);
    } catch (_) {
      cacheDir = null;
    }
    final cacheFile =
        cacheDir == null ? null : File(p.join(cacheDir.path, '$key.json'));
    if (cacheFile != null) {
      try {
        if (await cacheFile.exists()) {
          final decoded = jsonDecode(await cacheFile.readAsString());
          if (decoded is Map<String, dynamic>) {
            final cached = EarTimeline.fromJson(decoded);
            // 半截/损坏的缓存（sides 与 duration 对不上）当没有。
            if (cached.sides.isNotEmpty && cached.windowMs > 0) {
              return cached;
            }
          }
        }
      } catch (_) {
        // 损坏 → 重算（下面统一落盘覆盖）。
      }
    }

    final timeline = await analyzeFile(file.path);
    if (timeline != null && cacheFile != null) {
      try {
        await cacheDir!.create(recursive: true);
        await cacheFile.writeAsString(
          jsonEncode(timeline.toJson()),
          flush: true,
        );
      } catch (e) {
        // 缓存写失败不影响结果。
        debugPrint('智能耳分析缓存写入失败: $e');
      }
    }
    return timeline;
  }

  /// 不经缓存直接分析（单测入口）。
  @visibleForTesting
  static Future<EarTimeline?> analyzeFile(String path) async {
    final file = File(path);
    int size;
    try {
      size = (await file.stat()).size;
    } catch (_) {
      return null;
    }
    if (size <= 0) return null;
    switch (_extension(path)) {
      case 'wav':
        return _analyzeWav(file, size);
      case 'mp3':
        return _analyzeMp3(file, size);
      default:
        return null;
    }
  }

  static String _extension(String path) {
    final i = path.lastIndexOf('.');
    if (i < 0) return '';
    return path.substring(i + 1).toLowerCase();
  }

  /// 缓存根目录：`<base>/ear_analysis/`（[cacheDirResolver] 换掉 base）。
  static Future<Directory> _resolveCacheDir(
    Future<Directory> Function()? cacheDirResolver,
  ) async {
    final custom = cacheDirResolver;
    final base = custom != null
        ? await custom()
        : await getApplicationSupportDirectory();
    return Directory(p.join(base.path, cacheDirName));
  }

  // === WAV ===

  static Future<EarTimeline?> _analyzeWav(File file, int size) async {
    final raf = await file.open();
    try {
      await raf.setPosition(0);
      final head = await raf.read(math.min(_headBytes, size));
      final h = WavHeader.parse(head, size);
      if (h == null || !h.supported || h.sampleRate <= 0) return null;
      if (h.dataLength <= 0) return null;

      final frameSize = h.frameSize;
      final totalFrames = h.dataLength ~/ frameSize;
      if (totalFrames <= 0) return null;

      final windowFrames =
          math.max(1, (h.sampleRate * wavWindowMs) ~/ 1000);
      final windowCount = (totalFrames + windowFrames - 1) ~/ windowFrames;
      final sampleFrames = math.min(windowFrames, wavSampleFrames);
      final windowBytes = windowFrames * frameSize;
      final dataEnd = h.dataOffset + h.dataLength;
      final sides = List<EarSide?>.filled(windowCount, null);
      var windowsRead = 0;

      for (var w0 = 0; w0 < windowCount; w0 += wavWindowsPerRead) {
        final wEnd = math.min(w0 + wavWindowsPerRead, windowCount);
        final start = h.dataOffset + w0 * windowFrames * frameSize;
        if (start >= dataEnd) break;
        final end =
            math.min(h.dataOffset + wEnd * windowFrames * frameSize, dataEnd);
        final len = end - start;
        if (len < frameSize) break;
        await raf.setPosition(start);
        final buf = await raf.read(len);
        if (buf.length < frameSize) break;
        for (var w = w0; w < wEnd; w++) {
          // 相对 dataOffset 的整窗偏移 → 天然帧对齐，无需再对齐。
          final local = (w - w0) * windowBytes;
          if (local + frameSize > buf.length) break;
          final avail = math.min(sampleFrames * frameSize, buf.length - local);
          if (avail < frameSize) break;
          final rms =
              _wavWindowRms(Uint8List.sublistView(buf, local, local + avail), h);
          if (rms == null) continue; // 读失败 → 该窗没有数据
          windowsRead++;
          sides[w] = classify(rms.$1, rms.$2);
        }
      }

      // 一个窗都没读到 = 文件读不出内容，别把「全等响」当结论。
      if (windowsRead == 0) return null;
      return EarTimeline(
        windowMs: wavWindowMs,
        durationMs: (totalFrames * 1000 / h.sampleRate).round(),
        sides: sides,
      );
    } finally {
      await raf.close();
    }
  }

  /// 分声道平方和 → `(leftRms, rightRms)`；读不全返回 null。
  static (double, double)? _wavWindowRms(Uint8List window, WavHeader h) {
    final data = ByteData.sublistView(window);
    final frames = window.length ~/ h.frameSize;
    if (frames <= 0) return null;
    var sumL = 0.0;
    var sumR = 0.0;
    var count = 0;
    for (var f = 0; f < frames; f++) {
      final base = f * h.frameSize;
      final l = h.readSample(data, base);
      if (l == null) break;
      double r;
      if (h.channels >= 2) {
        final v = h.readSample(data, base + h.bytesPerSample);
        if (v == null) break;
        r = v;
      } else {
        r = l; // 单声道：L=R → 必然等响 → 轮播
      }
      sumL += l * l;
      sumR += r * r;
      count++;
    }
    if (count == 0) return null;
    return (math.sqrt(sumL / count), math.sqrt(sumR / count));
  }

  // === MP3 ===

  static Future<EarTimeline?> _analyzeMp3(File file, int size) async {
    final scan = await _scanMp3(file, size);
    if (scan == null || scan.durationMs <= 0) return null;

    final windowCount =
        (scan.durationMs + mp3WindowMs - 1) ~/ mp3WindowMs;
    if (windowCount <= 0) return null;

    // 每窗的抽样片（缺偏移的尾窗用最后一帧偏移兜底）。
    final slices = List<Uint8List?>.filled(windowCount, null);
    final raf = await file.open();
    try {
      for (var w = 0; w < windowCount; w++) {
        final offset = w < scan.offsets.length
            ? scan.offsets[w]
            : (scan.offsets.isNotEmpty ? scan.offsets.last : -1);
        if (offset < 0 || offset >= size) continue;
        await raf.setPosition(offset);
        final len = math.min(mp3SampleBytes, size - offset);
        if (len < 64) continue;
        final buf = await raf.read(len);
        if (buf.length >= 64) slices[w] = buf;
      }
    } finally {
      await raf.close();
    }

    final sides = List<EarSide?>.filled(windowCount, null);
    var decodedCount = 0;
    for (var b = 0; b < windowCount; b += mp3DecodeBatch) {
      final end = math.min(b + mp3DecodeBatch, windowCount);
      final batch = <Uint8List>[];
      final batchIndex = <int>[];
      for (var w = b; w < end; w++) {
        final s = slices[w];
        if (s != null) {
          batch.add(s);
          batchIndex.add(w);
        }
      }
      if (batch.isEmpty) continue;
      final List<(double, double)?> results;
      try {
        results = await Isolate.run(() => _decodeBatchRms(batch));
      } catch (e) {
        debugPrint('智能耳 mp3 解码批次失败: $e');
        continue;
      }
      for (var i = 0; i < batchIndex.length && i < results.length; i++) {
        final r = results[i];
        if (r == null) continue;
        decodedCount++;
        sides[batchIndex[i]] = classify(r.$1, r.$2);
      }
    }

    // 一个窗都没解出来 = 这个 mp3 我们啃不动（编码变体/损坏）。
    if (decodedCount == 0) return null;

    return EarTimeline(
      windowMs: mp3WindowMs,
      durationMs: scan.durationMs,
      sides: sides,
    );
  }

  /// 测试入口：暴露 mp3 帧扫描结果（时长 + 每窗字节偏移）。
  @visibleForTesting
  static Future<({int durationMs, List<int> offsets})?> debugScanMp3(
    String path,
  ) async {
    final file = File(path);
    int size;
    try {
      size = (await file.stat()).size;
    } catch (_) {
      return null;
    }
    if (size <= 0) return null;
    return _scanMp3(file, size);
  }

  /// 顺序扫 MPEG-1 Layer III 帧头：累加时间轴 + 记录每个窗的字节偏移。
  ///
  /// 只读头不解码，成本 ≈ 整文件顺序读一遍（SSD 上 60 分钟 ≈ 1~2s，
  /// 在调用线程以 IO 等待为主）。返回 `null` = 非 MPEG-1 L3 / 扫不出帧。
  static Future<({int durationMs, List<int> offsets})?> _scanMp3(
    File file,
    int size,
  ) async {
    final raf = await file.open();
    try {
      var pos = await LoudnessMeter.id3v2End(raf, size);
      var timeMs = 0.0;
      var nextBoundary = 0.0;
      final offsets = <int>[];
      var frames = 0;

      while (pos + 4 < size) {
        await raf.setPosition(pos);
        final buf = await raf.read(math.min(mp3ScanChunkBytes, size - pos));
        if (buf.length < 4) break;
        var i = 0;
        var newPos = pos;
        while (i + 4 <= buf.length) {
          final frame = _parseFrameHeader(buf, i);
          if (frame == null) {
            i++;
            newPos = pos + i;
            continue;
          }
          final frameStartMs = timeMs;
          while (frameStartMs >= nextBoundary && offsets.length < 400000) {
            offsets.add(pos + i);
            nextBoundary += mp3WindowMs;
          }
          timeMs += frame.durationMs;
          frames++;
          if (i + frame.frameLength > buf.length) {
            // 帧跨读块边界：下一读从这帧结束处继续（头已计入时间轴）。
            newPos = pos + i + frame.frameLength;
            break;
          }
          i += frame.frameLength;
          newPos = pos + i;
        }
        if (newPos <= pos) break; // 无进展（残块）→ 终止
        pos = newPos;
      }

      if (frames == 0) return null;
      return (durationMs: timeMs.round(), offsets: offsets);
    } finally {
      await raf.close();
    }
  }

  /// MPEG-1 Layer III 帧头（4B）→ 帧长 / 时长 / 声道数；非法返回 null。
  ///
  /// 只认 MPEG-1（MPEG-2/2.5 的采样率表不同，`kMp3SampleRates` 不含，
  /// 这类文件直接判不支持）。
  static ({int frameLength, double durationMs, int channels})?
      _parseFrameHeader(Uint8List b, int i) {
    if (b[i] != 0xFF) return null;
    final b1 = b[i + 1];
    if ((b1 & 0xE0) != 0xE0) return null;
    final version = (b1 >> 3) & 0x3; // 3 = MPEG-1
    final layer = (b1 >> 1) & 0x3; // 1 = Layer III
    if (version != 3 || layer != 1) return null;
    final b2 = b[i + 2];
    final bitrateIdx = (b2 >> 4) & 0xF;
    final srIdx = (b2 >> 2) & 0x3;
    if (bitrateIdx == 0 || bitrateIdx == 15 || srIdx == 3) return null;
    final padding = (b2 >> 1) & 0x1;
    final bitrateKbps = kMp3Bitrates[bitrateIdx - 1];
    final sampleRate = kMp3SampleRates[srIdx];
    final frameLength =
        mp3FrameSize(bitrateKbps, sampleRate, padding: padding == 1);
    if (frameLength <= 4) return null;
    final mode = (b[i + 3] >> 6) & 0x3; // 3 = mono
    return (
      frameLength: frameLength,
      durationMs: 1152000.0 / sampleRate, // MPEG-1 L3: 1152 samples/帧
      channels: mode == 3 ? 1 : 2,
    );
  }

  /// 解一批抽样片 → 每片 `(leftRms, rightRms)`（isolate 中执行）。
  static List<(double, double)?> _decodeBatchRms(List<Uint8List> slices) {
    final out = <(double, double)?>[];
    for (final slice in slices) {
      if (slice.length < 64) {
        out.add(null);
        continue;
      }
      final Mp3Pcm pcm;
      try {
        pcm = mp3Decode(slice);
      } catch (_) {
        out.add(null); // 单片解不动 → 该窗等响（轮播）
        continue;
      }
      out.add(_pcmRms(pcm));
    }
    return out;
  }

  static (double, double) _pcmRms(Mp3Pcm pcm) {
    final samples = pcm.samples;
    final ch = pcm.channels < 1 ? 1 : pcm.channels;
    final frames = samples.length ~/ ch;
    if (frames == 0) return (0, 0);
    final stride = math.max(1, frames ~/ 50000);
    var sumL = 0.0;
    var sumR = 0.0;
    var count = 0;
    for (var f = 0; f < frames; f += stride) {
      final base = f * ch;
      sumL += samples[base] * samples[base];
      // 单声道 → L=R（等响），立体声 → 取前两声道（L,R 交织）。
      final r = ch >= 2 ? samples[base + 1] : samples[base];
      sumR += r * r;
      count++;
    }
    if (count == 0) return (0, 0);
    return (math.sqrt(sumL / count), math.sqrt(sumR / count));
  }
}
