import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:aaplay/core/audio/translation/ear_side_filename_detector.dart';
import 'package:aaplay/core/audio/translation/wav_stereo_rms.dart';

void main() {
  group('EarSideFilenameDetector', () {
    test('中文 左/右', () {
      expect(EarSideFilenameDetector.detect('左耳体验.mp3'), EarSide.left);
      expect(EarSideFilenameDetector.detect('右耳ONLY.wav'), EarSide.right);
    });

    test('英文整词 left/right，大小写不敏感', () {
      expect(EarSideFilenameDetector.detect('track LEFT 01.flac'), EarSide.left);
      expect(EarSideFilenameDetector.detect('Right_Ear.wav'), EarSide.right);
      expect(EarSideFilenameDetector.detect('my left.mp3'), EarSide.left);
    });

    test('英文非整词不误判', () {
      expect(EarSideFilenameDetector.detect('bright.mp3'), isNull);
      expect(EarSideFilenameDetector.detect('copyright.wav'), isNull);
      expect(EarSideFilenameDetector.detect('leftover.flac'), isNull);
    });

    test('左右同时出现 → 无法判定', () {
      expect(EarSideFilenameDetector.detect('左left双声道对比右right.wav'), isNull);
      expect(EarSideFilenameDetector.detect('左右对比.mp3'), isNull);
    });

    test('空/无关键词 → null', () {
      expect(EarSideFilenameDetector.detect(null), isNull);
      expect(EarSideFilenameDetector.detect(''), isNull);
      expect(EarSideFilenameDetector.detect('01 純音.wav'), isNull);
    });
  });

  group('EarSide', () {
    test('tryParse / storageValue / flipped', () {
      expect(EarSide.tryParse('left'), EarSide.left);
      expect(EarSide.tryParse('RIGHT'), EarSide.right);
      expect(EarSide.tryParse('左'), EarSide.left);
      expect(EarSide.tryParse('r'), EarSide.right);
      expect(EarSide.tryParse('nope'), isNull);
      expect(EarSide.left.storageValue, 'left');
      expect(EarSide.right.flipped, EarSide.left);
      expect(EarSide.tryParse(EarSide.right.storageValue), EarSide.right);
    });
  });

  group('WavStereoRms', () {
    Uint8List buildWav({
      required List<int> leftSamples,
      required List<int> rightSamples,
      int channels = 2,
    }) {
      final frames = leftSamples.length;
      final dataSize = frames * channels * 2;
      final bytes = ByteData(44 + dataSize);
      void fourcc(int off, String s) {
        for (var i = 0; i < 4; i++) {
          bytes.setUint8(off + i, s.codeUnitAt(i));
        }
      }

      fourcc(0, 'RIFF');
      bytes.setUint32(4, 36 + dataSize, Endian.little);
      fourcc(8, 'WAVE');
      fourcc(12, 'fmt ');
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little); // PCM
      bytes.setUint16(22, channels, Endian.little);
      bytes.setUint32(24, 44100, Endian.little);
      bytes.setUint32(28, 44100 * channels * 2, Endian.little);
      bytes.setUint16(32, channels * 2, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      fourcc(36, 'data');
      bytes.setUint32(40, dataSize, Endian.little);
      var o = 44;
      for (var i = 0; i < frames; i++) {
        bytes.setInt16(o, leftSamples[i], Endian.little);
        o += 2;
        bytes.setInt16(o, rightSamples[i], Endian.little);
        o += 2;
      }
      return bytes.buffer.asUint8List();
    }

    test('左声道更强 → dominant=left', () {
      final wav = buildWav(
        leftSamples: List.filled(64, 8000),
        rightSamples: List.filled(64, 100),
      );
      final rms = WavStereoRms.analyze(wav)!;
      expect(rms.left, greaterThan(rms.right));
      expect(rms.dominant, 'left');
    });

    test('右声道更强 → dominant=right', () {
      final wav = buildWav(
        leftSamples: List.filled(64, 50),
        rightSamples: List.filled(64, 12000),
      );
      final rms = WavStereoRms.analyze(wav)!;
      expect(rms.dominant, 'right');
    });

    test('左右接近 → dominant=null', () {
      final wav = buildWav(
        leftSamples: List.filled(64, 5000),
        rightSamples: List.filled(64, 5100),
      );
      final rms = WavStereoRms.analyze(wav)!;
      expect(rms.dominant, isNull);
    });

    test('非 WAV / 过短 → null', () {
      expect(WavStereoRms.analyze(Uint8List(10)), isNull);
      expect(WavStereoRms.analyze(Uint8List.fromList('ID3....not a wav'.codeUnits)), isNull);
    });
  });
}
