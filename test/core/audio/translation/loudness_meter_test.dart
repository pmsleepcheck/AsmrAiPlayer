import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glint_audio_pure/glint_audio_pure.dart';
import 'package:aaplay/core/audio/translation/loudness_meter.dart';
import 'package:aaplay/core/audio/translation/wav_stereo_rms.dart';

import 'dart:io';

/// 合成 WAV：[channels] 声道，16bit PCM（float32 用 [buildFloatWav]）。
Uint8List buildWav({
  int channels = 1,
  int sampleRate = 44100,
  double amplitude = 0.5,
  double frequency = 440,
  double seconds = 1.0,
  bool bogusDataSize = false,
}) {
  const bitsPerSample = 16;
  final totalFrames = (sampleRate * seconds).round();
  const bytesPerSample = bitsPerSample ~/ 8;
  final dataSize = totalFrames * bytesPerSample * channels;
  final buf = BytesBuilder();
  void tag(String s) => buf.add(s.codeUnits);
  void u32(int v) => buf.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  void u16(int v) => buf.add([v & 255, (v >> 8) & 255]);

  tag('RIFF');
  u32(36 + dataSize);
  tag('WAVE');
  tag('fmt ');
  u32(16);
  u16(1); // PCM
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * bytesPerSample * channels);
  u16(bytesPerSample * channels);
  u16(bitsPerSample);
  tag('data');
  u32(bogusDataSize ? 4294967040 : dataSize);

  for (var f = 0; f < totalFrames; f++) {
    final v = amplitude * math.sin(2 * math.pi * frequency * f / sampleRate);
    for (var c = 0; c < channels; c++) {
      final sample = c == 1 && channels > 1 ? 0.0 : v;
      final i = (sample * 32767).round().clamp(-32768, 32767);
      u16(i & 0xFFFF);
    }
  }
  return buf.toBytes();
}

Uint8List buildFloatWav() {
  // 用 PCM16 构造器不行：这里单独产 float32 头 + float 数据。
  const sampleRate = 44100;
  const seconds = 0.5;
  final totalFrames = (sampleRate * seconds).round();
  final dataSize = totalFrames * 4; // mono float32
  final buf = BytesBuilder();
  void tag(String s) => buf.add(s.codeUnits);
  void u32(int v) => buf.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  void u16(int v) => buf.add([v & 255, (v >> 8) & 255]);

  tag('RIFF');
  u32(36 + dataSize);
  tag('WAVE');
  tag('fmt ');
  u32(16);
  u16(3); // IEEE float
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 4);
  u16(4);
  u16(32);
  tag('data');
  u32(dataSize);
  for (var f = 0; f < totalFrames; f++) {
    final v = 0.5 * math.sin(2 * math.pi * 440 * f / sampleRate);
    final bd = ByteData(4)..setFloat32(0, v, Endian.little);
    buf.add(bd.buffer.asUint8List());
  }
  return buf.toBytes();
}

/// 24-bit PCM mono WAV（真实下载里最常见的格式，28/35 个文件是它）。
Uint8List buildWav24({
  int sampleRate = 48000,
  int channels = 1,
  double amplitude = 0.5,
  double seconds = 1.0,
}) {
  final totalFrames = (sampleRate * seconds).round();
  final bytes = totalFrames * 3 * channels; // 24bit
  final buf = BytesBuilder();
  void tag(String s) => buf.add(s.codeUnits);
  void u32(int v) => buf.add([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);
  void u16(int v) => buf.add([v & 255, (v >> 8) & 255]);

  tag('RIFF');
  u32(36 + bytes);
  tag('WAVE');
  tag('JUNK'); // 真实文件里 fmt 前常有 JUNK chunk
  u32(28);
  buf.add(List<int>.filled(28, 0));
  tag('fmt ');
  u32(16);
  u16(1);
  u16(channels);
  u32(sampleRate);
  u32(sampleRate * 3 * channels);
  u16(3 * channels);
  u16(24);
  tag('data');
  u32(bytes);

  for (var f = 0; f < totalFrames; f++) {
    final v = amplitude * math.sin(2 * math.pi * 440 * f / sampleRate);
    for (var c = 0; c < channels; c++) {
      final sample = c == 1 && channels > 1 ? 0.0 : v;
      var i = (sample * 8388607).round();
      if (i > 8388607) i = 8388607;
      if (i < -8388608) i = -8388608;
      buf.add([i & 255, (i >> 8) & 255, (i >> 16) & 255]);
    }
  }
  return buf.toBytes();
}

Uint8List encodeMp3({
  double amplitude = 0.5,
  double seconds = 2.0,
  int sampleRate = 44100,
}) {
  final n = (sampleRate * seconds).round();
  final pcm = Float64List(n);
  for (var i = 0; i < n; i++) {
    pcm[i] = amplitude * math.sin(2 * math.pi * 440 * i / sampleRate);
  }
  return mp3EncodeMono(pcm, sampleRate: sampleRate, bitrate: 128);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('loudness_meter_test');
    LoudnessMeter.clearCache();
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
    LoudnessMeter.clearCache();
  });

  group('WavHeader.parse', () {
    test('解析 16bit PCM 头', () {
      final wav = buildWav(channels: 2, seconds: 0.2);
      final h = WavHeader.parse(wav, wav.length);
      expect(h, isNotNull);
      expect(h!.channels, 2);
      expect(h.bitsPerSample, 16);
      expect(h.audioFormat, 1);
      expect(h.supported, isTrue);
      expect(h.dataOffset, 44);
      expect(h.dataLength, wav.length - 44);
    });

    test('data chunk size 为占位大值时按文件长度截断', () {
      final wav = buildWav(seconds: 0.1, bogusDataSize: true);
      final h = WavHeader.parse(wav, wav.length);
      expect(h, isNotNull);
      expect(h!.dataLength, wav.length - 44);
      expect(h.supported, isTrue);
    });

    test('非 WAV / 头不足返回 null', () {
      expect(WavHeader.parse(Uint8List(43), 43), isNull);
      final junk = Uint8List.fromList(List<int>.filled(64, 7));
      expect(WavHeader.parse(junk, 64), isNull);
    });
  });

  group('LoudnessMeter wav', () {
    test('mono 16bit 正弦 RMS ≈ amplitude/√2', () async {
      final path = '${tmp.path}${Platform.pathSeparator}sine.wav';
      File(path).writeAsBytesSync(buildWav(seconds: 2.0));
      final rms = await LoudnessMeter.fileRms(path);
      expect(rms, isNotNull);
      expect(rms!, closeTo(0.5 / math.sqrt2, 0.02));
    });

    test('stereo（右声道静音）整体 RMS ≈ 单声道值/√2', () async {
      final path = '${tmp.path}${Platform.pathSeparator}stereo.wav';
      File(path).writeAsBytesSync(
        buildWav(channels: 2, seconds: 2.0),
      );
      final rms = await LoudnessMeter.fileRms(path);
      expect(rms, isNotNull);
      expect(rms!, closeTo(0.5 / math.sqrt2 / math.sqrt2, 0.02));
    });

    test('float32 WAV 可测', () async {
      final path = '${tmp.path}${Platform.pathSeparator}float.wav';
      File(path).writeAsBytesSync(buildFloatWav());
      final rms = await LoudnessMeter.fileRms(path);
      expect(rms, isNotNull);
      expect(rms!, closeTo(0.5 / math.sqrt2, 0.02));
    });

    test('WavStereoRms.analyze 仍按声道分别返回（重构无回归）', () {
      final wav = buildWav(channels: 2, seconds: 0.5);
      final r = WavStereoRms.analyze(wav);
      expect(r, isNotNull);
      expect(r!.left, closeTo(0.5 / math.sqrt2, 0.02));
      expect(r.right, lessThan(0.01));
      expect(r.dominant, 'left');
    });

    test('mono 文件仍返回 null（耳检测语义不变）', () {
      expect(WavStereoRms.analyze(buildWav(channels: 1)), isNull);
    });

    test('24bit PCM + JUNK 前置 chunk 可测（真实下载主流格式）', () async {
      final path = '${tmp.path}${Platform.pathSeparator}p24.wav';
      File(path).writeAsBytesSync(buildWav24(seconds: 2.0));
      final rms = await LoudnessMeter.fileRms(path);
      expect(rms, isNotNull);
      expect(rms!, closeTo(0.5 / math.sqrt2, 0.02));
    });

    test('24bit 立体声耳检测不再退化（解析共用）', () {
      final wav = buildWav24(channels: 2, seconds: 0.5);
      final r = WavStereoRms.analyze(wav);
      expect(r, isNotNull);
      expect(r!.left, closeTo(0.5 / math.sqrt2, 0.02));
      expect(r.right, lessThan(0.01));
      expect(r.dominant, 'left');
    });

    test('大文件走分窗路径：data 区远大于窗口仍可测', () async {
      // 用占位 data size 模拟「头与实际长度不一致」，并把 seconds 拉长到
      // 触发多窗口（> 256KB 数据）。
      final path = '${tmp.path}${Platform.pathSeparator}big.wav';
      File(path).writeAsBytesSync(buildWav(seconds: 4.0)); // ≈ 700KB
      final rms = await LoudnessMeter.fileRms(path);
      expect(rms, isNotNull);
      expect(rms!, closeTo(0.5 / math.sqrt2, 0.02));
    });
  });

  group('LoudnessMeter mp3', () {
    test('整段解码 RMS ≈ amplitude/√2', () async {
      final path = '${tmp.path}${Platform.pathSeparator}sine.mp3';
      File(path).writeAsBytesSync(encodeMp3(seconds: 2.0));
      final rms = await LoudnessMeter.fileRms(path);
      expect(rms, isNotNull);
      expect(rms!, closeTo(0.5 / math.sqrt2, 0.06));
    });

    test('切窗（多窗合并）与整段结果一致', () async {
      final bytes = encodeMp3(seconds: 3.0);
      final full = LoudnessMeter.mp3Rms([bytes]);
      final third = bytes.length ~/ 3;
      final windowed = LoudnessMeter.mp3Rms([
        bytes.sublist(0, third),
        bytes.sublist(third, 2 * third),
        bytes.sublist(2 * third),
      ]);
      expect(full, isNotNull);
      expect(windowed, isNotNull);
      expect(windowed!, closeTo(full!, 0.1));
    });

    test('空/垃圾字节返回 null 而不是抛异常', () {
      expect(LoudnessMeter.mp3Rms([]), isNull);
      expect(
        LoudnessMeter.mp3Rms([Uint8List.fromList(List<int>.filled(512, 3))]),
        isNull,
      );
    });

    test('不存在的文件返回 null', () async {
      expect(await LoudnessMeter.fileRms('${tmp.path}/nope.mp3'), isNull);
    });

    test('不支持的扩展名返回 null', () async {
      final path = '${tmp.path}${Platform.pathSeparator}x.flac';
      File(path).writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));
      expect(await LoudnessMeter.fileRms(path), isNull);
    });
  });

  group('缓存', () {
    test('同一文件命中缓存；clearCache 后重算', () async {
      final path = '${tmp.path}${Platform.pathSeparator}c.wav';
      File(path).writeAsBytesSync(buildWav(seconds: 0.5));
      final a = await LoudnessMeter.fileRms(path);
      expect(a, isNotNull);
      expect(LoudnessMeter.cacheSize, 1);
      final b = await LoudnessMeter.fileRms(path);
      expect(b, a);
      expect(LoudnessMeter.cacheSize, 1);

      LoudnessMeter.clearCache();
      expect(LoudnessMeter.cacheSize, 0);
      await LoudnessMeter.fileRms(path);
      expect(LoudnessMeter.cacheSize, 1);
    });
  });
}
