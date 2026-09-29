// detail_viewmodel_playable_test.dart：`type` 不可信，扩展名优先。
//
// asmr.one 会把字幕（.vtt/.lrc/.txt）等文件下发成 `type:"audio"`。历史实现
// 里 `type=='audio'` 排在扩展名校验之前，这类文件于是拿到播放入口，最终被
// 送进 setAudioSource 把播放链锁死。这里通过静态入口
// `collectAudioWithSubtitles`（内部走同一个 `_isAudioChild`）锁住判定。
//
// @created 2026-09-28

import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/presentation/viewmodels/detail_viewmodel.dart';

Child _audio(String title) => Child(type: 'audio', title: title);

void main() {
  group('DetailViewModel 音频判定：扩展名优先于 API type', () {
    test('type=audio 的字幕不会被当成音频（否则拿到播放按钮 → 播放失败）', () {
      final pairs = DetailViewModel.collectAudioWithSubtitles([
        _audio('01.vtt'),
        _audio('02.lrc'),
        _audio('03.srt'),
        _audio('04.txt'),
        _audio('05.mp3'),
      ]);

      expect(pairs.map((p) => p.audio.title), ['05.mp3']);
    });

    test('type=audio 但扩展名不在白名单（元数据/压缩包/图片）→ 不是音频', () {
      final pairs = DetailViewModel.collectAudioWithSubtitles([
        _audio('album.json'),
        _audio('cover.jpg'),
        _audio('raw.zip'),
        _audio('01.mp3'),
      ]);

      expect(pairs.map((p) => p.audio.title), ['01.mp3']);
    });

    test('type 缺失时按扩展名兜底：白名单内 → 音频；字幕 → 不是', () {
      final pairs = DetailViewModel.collectAudioWithSubtitles([
        Child(title: '01.flac'),
        Child(title: '02.vtt'),
        Child(title: 'no-extension'),
      ]);

      expect(pairs.map((p) => p.audio.title), ['01.flac']);
    });

    test('type 非 audio 时不因扩展名翻案（type=text 的 .mp3 不是音频）', () {
      final pairs = DetailViewModel.collectAudioWithSubtitles([
        Child(type: 'text', title: '01.mp3'),
        Child(type: 'audio', title: '02.mp3'),
      ]);

      expect(pairs.map((p) => p.audio.title), ['02.mp3']);
    });
  });
}
