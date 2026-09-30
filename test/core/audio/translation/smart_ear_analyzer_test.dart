import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glint_audio_pure/glint_audio_pure.dart';

import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/smart_ear_analyzer.dart';

/// 立体声 PCM16 WAV：每段给定左右幅度与秒数。
Uint8List buildStereoWav(
  List<({double left, double right, double seconds})> segments, {
  int sampleRate = 44100,
}) {
  final frames = segments.fold<int>(
    0,
    (sum, s) => sum + (s.seconds * sampleRate).round(),
  );
  final dataLen = frames * 4;
  final buf = BytesBuilder();
  void tag(String s) => buf.add(s.codeUnits);
  void u32(int v) =>
      buf.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  void u16(int v) => buf.add([v & 255, (v >> 8) & 255]);

  tag('RIFF');
  u32(36 + dataLen);
  tag('WAVE');
  tag('fmt ');
  u32(16);
  u16(1); // PCM
  u16(2); // stereo
  u32(sampleRate);
  u32(sampleRate * 4);
  u16(4); // block align
  u16(16); // bits
  tag('data');
  u32(dataLen);
  int i16(double v) => (v * 32767).round().clamp(-32768, 32767);
  for (final s in segments) {
    final n = (s.seconds * sampleRate).round();
    final l = i16(s.left) & 0xFFFF;
    final r = i16(s.right) & 0xFFFF;
    for (var i = 0; i < n; i++) {
      buf.add([l & 255, l >> 8, r & 255, r >> 8]);
    }
  }
  return buf.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('classify（单窗判定）', () {
    test('内容耳：强侧至少高 5%（与 WavStereoRms.dominant 同口径）', () {
      expect(
        SmartEarAnalyzer.classify(0.5, 0.05),
        EarSide.left,
      );
      expect(SmartEarAnalyzer.classify(0.05, 0.5), EarSide.right);
      // 5% 边界内 → 等响
      expect(SmartEarAnalyzer.classify(0.40, 0.39), isNull);
      expect(SmartEarAnalyzer.classify(0.40, 0.40), isNull);
    });

    test('静音 / 单边为 0 / 非数 → 等响或对侧', () {
      expect(SmartEarAnalyzer.classify(0, 0), isNull);
      expect(SmartEarAnalyzer.classify(1e-6, 1e-6), isNull);
      expect(SmartEarAnalyzer.classify(0.3, 0), EarSide.left);
      expect(SmartEarAnalyzer.classify(0, 0.3), EarSide.right);
      expect(SmartEarAnalyzer.classify(double.nan, 0.3), isNull);
      expect(SmartEarAnalyzer.classify(0.3, double.infinity), isNull);
    });
  });

  group('EarTimeline', () {
    test('sideAt 按窗定位，越界钳到首/尾', () {
      const t = EarTimeline(
        windowMs: 1000,
        durationMs: 3000,
        sides: [EarSide.left, null, EarSide.right],
      );
      expect(t.sideAt(0), EarSide.left);
      expect(t.sideAt(999), EarSide.left);
      expect(t.sideAt(1500), isNull); // 等响窗
      expect(t.sideAt(2500), EarSide.right);
      expect(t.sideAt(-10), EarSide.left);
      expect(t.sideAt(99999), EarSide.right);
    });

    test('encode/decode + JSON 往返', () {
      const sides = [EarSide.left, null, EarSide.right, null];
      const t = EarTimeline(windowMs: 5000, durationMs: 20000, sides: sides);
      expect(t.encodeSides(), 'L.R.');
      expect(EarTimeline.decodeSides('L.R.'), sides);

      final back = EarTimeline.fromJson(
        Map<String, dynamic>.from(t.toJson()),
      );
      expect(back.windowMs, 5000);
      expect(back.durationMs, 20000);
      expect(back.sides, sides);
    });
  });

  group('WAV 逐窗分析', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('smart_ear_');
      SmartEarAnalyzer.clearCache();
    });

    tearDown(() async {
      SmartEarAnalyzer.clearCache();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('左 1s → 右 1s → 等响 1s 得到三窗判定', () async {
      final path = '${tmp.path}/seg.wav';
      File(path).writeAsBytesSync(buildStereoWav([
        (left: 0.5, right: 0.05, seconds: 1.0),
        (left: 0.05, right: 0.5, seconds: 1.0),
        (left: 0.4, right: 0.4, seconds: 1.0),
      ]));

      final t = await SmartEarAnalyzer.analyzeFile(path);

      expect(t, isNotNull);
      expect(t!.windowMs, SmartEarAnalyzer.wavWindowMs);
      expect(t.windowCount, 3);
      expect(t.sides, [EarSide.left, EarSide.right, null]);
      expect(t.durationMs, closeTo(3000, 50));
    });

    test('左右同值（等价单声道内容）→ 全等响，交由轮播兜底', () async {
      final path = '${tmp.path}/mono.wav';
      File(path).writeAsBytesSync(buildStereoWav([
        (left: 0.5, right: 0.5, seconds: 1.2),
      ]));

      final t = await SmartEarAnalyzer.analyzeFile(path);

      expect(t, isNotNull);
      expect(t!.sides.every((s) => s == null), isTrue);
    });

    test('磁盘缓存：清掉内存缓存后仍能命中', () async {
      final path = '${tmp.path}/cached.wav';
      File(path).writeAsBytesSync(buildStereoWav([
        (left: 0.5, right: 0.05, seconds: 1.2),
      ]));
      Future<Directory> resolver() async => tmp;

      final first = await SmartEarAnalyzer.analyze(
        path,
        cacheDirResolver: resolver,
      );
      expect(first, isNotNull);
      final cacheFiles = Directory('${tmp.path}/${SmartEarAnalyzer.cacheDirName}')
          .listSync()
          .whereType<File>()
          .toList();
      expect(cacheFiles, hasLength(1));

      // 清内存 → 仍应从磁盘缓存拿到同一份（文件没变，key 不变）。
      SmartEarAnalyzer.clearCache();
      final second = await SmartEarAnalyzer.analyze(
        path,
        cacheDirResolver: resolver,
      );
      expect(second, isNotNull);
      expect(second!.sides, first!.sides);
      expect(second.windowMs, first.windowMs);
    });

    test('不支持的容器返回 null', () async {
      final path = '${tmp.path}/track.flac';
      File(path).writeAsBytesSync(List<int>.filled(4096, 7));
      expect(await SmartEarAnalyzer.analyzeFile(path), isNull);
      expect(await SmartEarAnalyzer.analyzeFile('${tmp.path}/nope.xyz'),
          isNull);
    });
  });

  group('MP3 扫描与分析', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('smart_ear_mp3_');
      SmartEarAnalyzer.clearCache();
    });

    tearDown(() async {
      SmartEarAnalyzer.clearCache();
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('帧扫描得到正确时长与窗偏移', () async {
      final path = '${tmp.path}/scan.mp3';
      final left = Float64List(44100 * 2);
      final right = Float64List(44100 * 2);
      for (var i = 0; i < left.length; i++) {
        left[i] = 0.5;
        right[i] = 0.05;
      }
      File(path).writeAsBytesSync(
        mp3EncodeStereo(left, right, sampleRate: 44100, bitrate: 128),
      );

      final scan = await SmartEarAnalyzer.debugScanMp3(path);

      expect(scan, isNotNull);
      // 2s 音频 → 时长接近 2000ms（帧粒度 ±~50ms）。
      expect(scan!.durationMs, closeTo(2000, 150));
      expect(scan.offsets, isNotEmpty);
      expect(scan.offsets.first, lessThan(64 * 1024)); // 首窗在文件头部
    });

    test('左响立体声 mp3 → 端到端判为左', () async {
      final path = '${tmp.path}/left.mp3';
      final left = Float64List(44100 * 2);
      final right = Float64List(44100 * 2);
      for (var i = 0; i < left.length; i++) {
        left[i] = 0.5;
        right[i] = 0.05;
      }
      File(path).writeAsBytesSync(
        mp3EncodeStereo(left, right, sampleRate: 44100, bitrate: 128),
      );

      final t = await SmartEarAnalyzer.analyzeFile(path);

      expect(t, isNotNull);
      expect(t!.windowMs, SmartEarAnalyzer.mp3WindowMs);
      expect(t.windowCount, 1); // 2s < 5s 窗
      expect(t.sides, [EarSide.left]);
    });

    test('右响立体声 mp3 → 判为右', () async {
      final path = '${tmp.path}/right.mp3';
      final left = Float64List(44100 * 2);
      final right = Float64List(44100 * 2);
      for (var i = 0; i < left.length; i++) {
        left[i] = 0.05;
        right[i] = 0.5;
      }
      File(path).writeAsBytesSync(
        mp3EncodeStereo(left, right, sampleRate: 44100, bitrate: 128),
      );

      final t = await SmartEarAnalyzer.analyzeFile(path);
      expect(t!.sides, [EarSide.right]);
    });

    test('损坏文件不抛异常、返回 null', () async {
      final path = '${tmp.path}/broken.mp3';
      File(path).writeAsBytesSync(List<int>.filled(8192, 0x33));
      expect(await SmartEarAnalyzer.analyzeFile(path), isNull);
    });
  });
}
