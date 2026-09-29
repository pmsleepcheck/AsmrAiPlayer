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

  group('LocalCacheViewModel.isPlayableEntry（本地缓存播放按钮闸门）', () {
    test('type=audio 的字幕不可播放（历史上它拿到播放按钮 → 锁死播放链）', () {
      for (final name in ['01.vtt', '02.lrc', '03.srt', '04.txt']) {
        final e = _entry(fileName: name, mediaType: 'audio');
        expect(LocalCacheViewModel.isAudioEntry(e), isFalse, reason: name);
        expect(LocalCacheViewModel.isPlayableEntry(e), isFalse, reason: name);
      }
    });

    test('type=audio 的元数据 / 临时文件不可播放', () {
      for (final name in [
        'album.json',
        'cover.jpg',
        '01.mp3.part',
        '02.wav.dl_tmp',
      ]) {
        final e = _entry(fileName: name, mediaType: 'audio');
        expect(LocalCacheViewModel.isPlayableEntry(e), isFalse, reason: name);
      }
    });

    test('音频与视频可播放，按钮入口保留', () {
      expect(
        LocalCacheViewModel.isPlayableEntry(
            _entry(fileName: '01.mp3', mediaType: 'audio')),
        isTrue,
      );
      expect(
        LocalCacheViewModel.isPlayableEntry(
            _entry(fileName: '01.flac', mediaType: '')),
        isTrue,
      );
      expect(
        LocalCacheViewModel.isPlayableEntry(
            _entry(fileName: 'intro.mp4', mediaType: '')),
        isTrue,
      );
    });
  });
}
