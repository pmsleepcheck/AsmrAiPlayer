import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/download/models/download_entry.dart';
import 'package:aaplay/presentation/viewmodels/local_cache_viewmodel.dart';

DownloadEntry _entry({
  String fileName = 'a.mp3',
  String mediaType = 'audio',
}) {
  return DownloadEntry(
    workId: '1',
    fileKey: 'k',
    fileName: fileName,
    filePath: 'C:/x/$fileName',
    mediaType: mediaType,
    sourceUrl: '',
    size: 1,
    createdAt: 1,
  );
}

void main() {
  group('LocalCacheViewModel.isVideoEntry / isAudioEntry (pure)', () {
    test('media_type=video → video，不是 audio', () {
      final e = _entry(fileName: '介绍视频.mp4', mediaType: 'video');
      expect(LocalCacheViewModel.isVideoEntry(e), isTrue);
      expect(LocalCacheViewModel.isAudioEntry(e), isFalse);
    });

    test('API 错标 type=audio 但扩展名是视频 → 按视频', () {
      final e = _entry(fileName: 'intro.mp4', mediaType: 'audio');
      expect(LocalCacheViewModel.isVideoEntry(e), isTrue);
      expect(LocalCacheViewModel.isAudioEntry(e), isFalse);
    });

    test('media_type=audio 且非视频扩展名 → audio', () {
      final e = _entry(fileName: '01.mp3', mediaType: 'audio');
      expect(LocalCacheViewModel.isVideoEntry(e), isFalse);
      expect(LocalCacheViewModel.isAudioEntry(e), isTrue);
    });

    test('历史空 media_type：音频扩展名 → audio；未知扩展名 → 都不是', () {
      final mp3 = _entry(fileName: 'track.flac', mediaType: '');
      expect(LocalCacheViewModel.isAudioEntry(mp3), isTrue);

      final vtt = _entry(fileName: '01.vtt', mediaType: '');
      expect(LocalCacheViewModel.isVideoEntry(vtt), isFalse);
      expect(LocalCacheViewModel.isAudioEntry(vtt), isFalse);
    });
  });
}
