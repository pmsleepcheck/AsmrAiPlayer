// playback_context_playable_test.dart：锁定「可播放」判定的唯一来源。
//
// 回归背景：字幕（.vtt/.lrc/.srt/.txt）等不可播放文件一旦被当成音频送进
// setAudioSource，mpv 会卡在加载态，下一次 stop() 与在途加载交错即把播放
// 串行链锁死——表现为「点一次坏文件后所有播放都失败，重启才恢复」。
//
// @created 2026-09-28

import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/models/playback_context.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';

Child _child(String title, {String? type}) =>
    Child(type: type, title: title, mediaDownloadUrl: 'https://cdn/$title');

void main() {
  group('PlaybackContext.extensionOf', () {
    test('常规扩展名返回小写、不含点', () {
      expect(PlaybackContext.extensionOf('01.MP3'), 'mp3');
      expect(PlaybackContext.extensionOf('a.b.flac'), 'flac');
      expect(PlaybackContext.extensionOf('中文 标题.wav'), 'wav');
    });

    test('无扩展名 / 空名 / 纯点结尾 / 隐藏文件名 → null', () {
      expect(PlaybackContext.extensionOf('track'), isNull);
      expect(PlaybackContext.extensionOf(''), isNull);
      expect(PlaybackContext.extensionOf(null), isNull);
      expect(PlaybackContext.extensionOf('track.'), isNull);
      // 历史实现用 split('.').last，会把 ".mp3" 当成扩展名 mp3。
      expect(PlaybackContext.extensionOf('.mp3'), isNull);
    });
  });

  group('PlaybackContext.isPlayableAudioTitle（播放按钮 / 播放列表唯一闸门）', () {
    test('白名单内的音频扩展名 → 可播放', () {
      for (final title in [
        '01.mp3',
        'track.wav',
        'x.flac',
        'y.m4a',
        'z.opus',
        'v.ogg',
        'w.wma',
        'u.mp4a',
        't.aac',
        's.m4A',
      ]) {
        expect(PlaybackContext.isPlayableAudioTitle(title), isTrue,
            reason: '$title 应可播放');
      }
    });

    test('字幕 / 视频 / 元数据 / 临时文件 → 一律不可播放', () {
      for (final title in [
        '01.vtt',
        '01.lrc',
        '01.srt',
        '01.txt',
        'intro.mp4',
        'album.json',
        'cover.jpg',
        '01.mp3.part',
        '01.wav.dl_tmp',
        'track',
        '',
        null,
      ]) {
        expect(PlaybackContext.isPlayableAudioTitle(title), isFalse,
            reason: '$title 不应被当成可播放音频');
      }
    });
  });

  group('字幕永远进不了播放列表', () {
    test('当前文件是字幕 → 播放列表为空且 validate 抛错', () {
      final files = Files(type: 'tree', title: 'work', children: [
        _child('01.mp3', type: 'audio'),
        _child('01.vtt', type: 'audio'),
      ]);
      final ctx = PlaybackContext(
        work: Work(title: 'work'),
        files: files,
        currentFile: files.children![1],
      );

      expect(ctx.playlist, isEmpty);
      expect(() => ctx.validate(), throwsA(isA<Object>()));
    });

    test('当前文件是音频 → 同目录同扩展名入列，字幕不会混进来', () {
      final files = Files(type: 'tree', title: 'work', children: [
        _child('01.mp3', type: 'audio'),
        _child('02.mp3', type: 'audio'),
        _child('01.vtt', type: 'audio'),
        _child('02.lrc', type: 'audio'),
        _child('intro.mp4', type: 'audio'),
      ]);
      final ctx = PlaybackContext(
        work: Work(title: 'work'),
        files: files,
        currentFile: files.children![0],
      );

      expect(ctx.playlist.map((c) => c.title), ['01.mp3', '02.mp3']);
      expect(() => ctx.validate(), returnsNormally);
    });

    test('视频 / 元数据作为当前文件同样得到空播放列表', () {
      for (final title in ['intro.mp4', 'album.json', 'cover.jpg']) {
        final files = Files(type: 'tree', title: 'work', children: [
          _child('01.mp3', type: 'audio'),
          _child(title, type: 'audio'),
        ]);
        final ctx = PlaybackContext(
          work: Work(title: 'work'),
          files: files,
          currentFile: files.children![1],
        );
        expect(ctx.playlist, isEmpty, reason: '$title 不应产生播放列表');
      }
    });
  });
}
