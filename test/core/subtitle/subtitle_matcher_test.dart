import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/subtitle/utils/subtitle_matcher.dart';
import 'package:aaplay/core/subtitle/subtitle_loader.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';

void main() {
  Child sub(String title) => Child(type: 'text', title: title);
  Child audio(String title) => Child(type: 'audio', title: title);
  Child folder(String title, List<Child> children) =>
      Child(type: 'folder', title: title, children: children);

  group('SubtitleMatcher 优先级链', () {
    test('① 全文件名精确匹配', () {
      final hit = SubtitleMatcher.findMatchingSubtitle(
        '01.mp3',
        [sub('01.vtt'), sub('02.vtt')],
      );
      expect(hit?.title, '01.vtt');
    });

    test('① 忽略大小写；base / fullName+ext 两种候选', () {
      expect(
        SubtitleMatcher.findMatchingSubtitle(
            'Track.MP3', [sub('track.VTT')])?.title,
        'track.VTT',
      );
      expect(
        SubtitleMatcher.findMatchingSubtitle(
            'a.mp3', [sub('a.mp3.lrc')])?.title,
        'a.mp3.lrc',
      );
    });

    test('② 规范化全名：空白/全角空格/破折号差异仍命中', () {
      final hit = SubtitleMatcher.findMatchingSubtitle(
        'My  Song　-  ver.mp3',
        [sub('my song - ver.vtt')],
      );
      expect(hit?.title, 'my song - ver.vtt');
    });

    test('③ 去字符：标点/括号不同但核心字符相同', () {
      final hit = SubtitleMatcher.findMatchingSubtitle(
        '【ASMR】深夜低语（01）.mp3',
        [sub('ASMR 深夜低语 01.vtt')],
      );
      expect(hit?.title, 'ASMR 深夜低语 01.vtt');
    });

    test('③ 去字符 Levenshtein：小差异仍命中，完全无关不命中', () {
      final near = SubtitleMatcher.findMatchingSubtitle(
        'chapter-one-final.mp3',
        [sub('chapter-one-fina.vtt')],
      );
      expect(near, isNotNull);

      final miss = SubtitleMatcher.findMatchingSubtitle(
        'zzz.mp3',
        [sub('completely-different-title.vtt')],
      );
      expect(miss, isNull);
    });

    test('无候选 / 非字幕扩展名 → null', () {
      expect(SubtitleMatcher.findMatchingSubtitle('01.mp3', []), isNull);
      expect(
        SubtitleMatcher.findMatchingSubtitle('01.mp3', [sub('01.txt')]),
        isNull,
      );
    });
  });

  group('SubtitleLoader.collectSubtitleFiles + 全树兜底', () {
    test('collect 递归收集 vtt/lrc，跳过其他', () {
      final tree = [
        folder('a', [audio('01.mp3'), sub('01.vtt'), sub('note.txt')]),
        folder('b', [folder('c', [sub('02.lrc')])]),
        sub('root.srt'),
      ];
      final all = SubtitleLoader.collectSubtitleFiles(tree);
      expect(all.map((c) => c.title), ['01.vtt', '02.lrc']);
    });

    test('findSubtitleFile：同目录优先；跨目录走全树兜底', () {
      final files = Files(type: 'tree', title: 'tree', children: [
        folder('audio', [audio('track.mp3')]),
        folder('subs', [sub('track.vtt')]),
      ]);
      final loader = SubtitleLoader(dio: DioLite());
      final hit = loader.findSubtitleFile(
        files.children![0].children![0],
        files,
      );
      expect(hit?.title, 'track.vtt');
    });

    test('findSubtitleFile：同目录精确命中优先于全树其他', () {
      final files = Files(type: 'tree', title: 'tree', children: [
        folder('ch1', [audio('01.mp3'), sub('01.vtt')]),
        folder('ch2', [sub('01-spoiler.vtt')]),
      ]);
      final loader = SubtitleLoader(dio: DioLite());
      final hit = loader.findSubtitleFile(
        files.children![0].children![0],
        files,
      );
      expect(hit?.title, '01.vtt');
    });
  });
}

/// 仅用于构造 SubtitleLoader；匹配路径不发起网络请求。
class DioLite extends Fake implements Dio {}
