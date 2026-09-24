import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/models/playback_context.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';

Child _audio(String title) => Child(type: 'audio', title: title);
Child _video(String title) => Child(type: 'video', title: title);

void main() {
  Files tree(List<Child> children) => Files(children: children);

  group('PlaybackContext playlist extension gate', () {
    test('mp3/wav/flac/m4a/opus/aac 都可进同目录播放列表', () {
      for (final name in [
        'a.mp3',
        'b.wav',
        'c.flac',
        'd.m4a',
        'e.opus',
        'f.aac',
      ]) {
        final ctx = PlaybackContext(
          work: Work(id: 1),
          files: tree([_audio(name), _audio('other.$name')]),
          currentFile: _audio(name),
        );
        expect(ctx.playlist, isNotEmpty, reason: name);
      }
    });

    test('视频扩展名不进播放列表（空 → validate 抛）', () {
      final ctx = PlaybackContext(
        work: Work(id: 1),
        files: tree([_video('intro.mp4')]),
        currentFile: _video('intro.mp4'),
      );
      expect(ctx.playlist, isEmpty);
      expect(() => ctx.validate(), throwsA(isA<Object>()));
    });

    test('同目录过滤保持：仅同扩展名进列表', () {
      final current = _audio('01.flac');
      final ctx = PlaybackContext(
        work: Work(id: 1),
        files: tree([current, _audio('02.flac'), _audio('03.mp3')]),
        currentFile: current,
      );
      expect(ctx.playlist.map((c) => c.title), ['01.flac', '02.flac']);
    });
  });
}
