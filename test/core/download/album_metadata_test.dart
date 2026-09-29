import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/download/album_metadata_writer.dart';
import 'package:aaplay/core/download/models/work_snapshot.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';

void main() {
  Work mkWork({String title = '测试专辑', int id = 42}) =>
      Work(id: id, title: title, sourceId: '$id');

  group('AlbumMetadataWriter.payload', () {
    test('WorkSnapshot.toJson round-trip：fromJson 还原同名作品', () {
      final work = mkWork();
      final payload = AlbumMetadataWriter.payload(
        work: work,
        updatedAt: 1700000000000,
      );
      final snap = WorkSnapshot.fromJson(payload);
      expect(snap.work.title, work.title);
      expect(snap.work.id, work.id);
      expect(snap.work.sourceId, work.sourceId);
      expect(snap.updatedAt, 1700000000000);
      expect(snap.files, isNull);
    });

    test('含 files 树时 round-trip 保留 children', () {
      final files = Files(
        type: 'tree',
        title: 'tree',
        children: const [],
      );
      final payload = AlbumMetadataWriter.payload(
        work: mkWork(),
        files: files,
        updatedAt: 1,
      );
      final snap = WorkSnapshot.fromJson(payload);
      expect(snap.files, isNotNull);
      expect(snap.files!.title, 'tree');
    });

    test('payload 键集合与 SQLite 快照同 schema（work/files?/updatedAt）', () {
      final payload = AlbumMetadataWriter.payload(
        work: mkWork(),
        updatedAt: 7,
      );
      expect(payload.keys.toList()..sort(), ['updatedAt', 'work']);
      expect(payload['updatedAt'], 7);
      expect(payload['work'], isA<Map<String, dynamic>>());
    });
  });

  group('AlbumMetadataWriter.write (IO)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('aaplay_album_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('写入 <workDir>/album.json，内容可 fromJson 解析', () async {
      final work = mkWork(title: '写入测试');
      await AlbumMetadataWriter.write(tmp, work: work);

      final file = File('${tmp.path}${Platform.pathSeparator}album.json');
      expect(await file.exists(), isTrue);
      final decoded = jsonDecode(await file.readAsString());
      expect(decoded, isA<Map<String, dynamic>>());
      final snap = WorkSnapshot.fromJson(decoded as Map<String, dynamic>);
      expect(snap.work.title, '写入测试');
      // 不残留 tmp。
      expect(
        await File('${file.path}.dl_tmp').exists(),
        isFalse,
      );
    });

    test('workDir 不存在时自动创建', () async {
      final nested =
          Directory('${tmp.path}${Platform.pathSeparator}a${Platform.pathSeparator}b');
      expect(await nested.exists(), isFalse);
      await AlbumMetadataWriter.write(nested, work: mkWork());
      expect(
        await File(
                '${nested.path}${Platform.pathSeparator}album.json')
            .exists(),
        isTrue,
      );
    });

    test('覆盖写：第二次 write 替换旧内容（rename 原子）', () async {
      await AlbumMetadataWriter.write(tmp, work: mkWork(title: '旧'));
      await AlbumMetadataWriter.write(tmp, work: mkWork(title: '新'));
      final file = File('${tmp.path}${Platform.pathSeparator}album.json');
      final snap =
          WorkSnapshot.fromJson(jsonDecode(await file.readAsString())
              as Map<String, dynamic>);
      expect(snap.work.title, '新');
    });
  });

  group('AlbumMetadataWriter subtitleMatches', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('aaplay_matches_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('record（overwrite:false）已有 key 不覆盖；手工 overwrite:true 覆盖', () async {
      await AlbumMetadataWriter.recordSubtitleMatch(
        tmp,
        audioPath: '/a/01.mp3',
        subtitlePath: '/a/auto.vtt',
      );
      await AlbumMetadataWriter.recordSubtitleMatch(
        tmp,
        audioPath: '/a/01.mp3',
        subtitlePath: '/a/other.vtt',
      );
      var m = await AlbumMetadataWriter.readSubtitleMatches(tmp);
      expect(m['/a/01.mp3'], '/a/auto.vtt');

      await AlbumMetadataWriter.recordSubtitleMatch(
        tmp,
        audioPath: '/a/01.mp3',
        subtitlePath: '/a/manual.vtt',
        overwrite: true,
      );
      m = await AlbumMetadataWriter.readSubtitleMatches(tmp);
      expect(m['/a/01.mp3'], '/a/manual.vtt');
    });

    test('write 合并保留 subtitleMatches（下载重写不抹掉）', () async {
      await AlbumMetadataWriter.recordSubtitleMatch(
        tmp,
        audioPath: '/a/01.mp3',
        subtitlePath: '/a/01.vtt',
        overwrite: true,
      );
      await AlbumMetadataWriter.write(tmp, work: mkWork(title: '重写'));

      final m = await AlbumMetadataWriter.readSubtitleMatches(tmp);
      expect(m['/a/01.mp3'], '/a/01.vtt');

      final decoded = jsonDecode(
              await File('${tmp.path}${Platform.pathSeparator}album.json')
                  .readAsString())
          as Map<String, dynamic>;
      final snap = WorkSnapshot.fromJson(decoded);
      expect(snap.work.title, '重写');
      expect(decoded[AlbumMetadataWriter.subtitleMatchesKey], isA<Map>());
    });

    test('无 album.json 时 record 建最小 sidecar；read 空 → {}', () async {
      expect(await AlbumMetadataWriter.readSubtitleMatches(tmp), isEmpty);
      await AlbumMetadataWriter.recordSubtitleMatch(
        tmp,
        audioPath: '/x.mp3',
        subtitlePath: '/x.vtt',
      );
      final m = await AlbumMetadataWriter.readSubtitleMatches(tmp);
      expect(m['/x.mp3'], '/x.vtt');
    });
  });

  group('AlbumMetadataWriter fileKeys', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('aaplay_filekeys_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('record 合并写入；write 重写 album 不抹掉 fileKeys', () async {
      await AlbumMetadataWriter.recordFileKey(
        tmp,
        fileName: '01.mp3',
        fileKey: 'aaa111',
      );
      await AlbumMetadataWriter.recordFileKey(
        tmp,
        fileName: '02.mp3',
        fileKey: 'bbb222',
      );
      var m = await AlbumMetadataWriter.readFileKeys(tmp);
      expect(m, {'01.mp3': 'aaa111', '02.mp3': 'bbb222'});

      await AlbumMetadataWriter.recordFileKey(
        tmp,
        fileName: '01.mp3',
        fileKey: 'renamed-key',
      );
      m = await AlbumMetadataWriter.readFileKeys(tmp);
      expect(m['01.mp3'], 'renamed-key');
      expect(m['02.mp3'], 'bbb222');

      await AlbumMetadataWriter.write(tmp, work: mkWork(title: '重写'));
      m = await AlbumMetadataWriter.readFileKeys(tmp);
      expect(m['01.mp3'], 'renamed-key');
      expect(m['02.mp3'], 'bbb222');
    });

    test('无 album.json 时 read → {}；record 建最小 sidecar', () async {
      expect(await AlbumMetadataWriter.readFileKeys(tmp), isEmpty);
      await AlbumMetadataWriter.recordFileKey(
        tmp,
        fileName: 'a.mp3',
        fileKey: 'k',
      );
      final m = await AlbumMetadataWriter.readFileKeys(tmp);
      expect(m['a.mp3'], 'k');
    });
  });

  group('AlbumMetadataWriter translationVolume（翻译手动音量按作品记住）', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('aaplay_tvol_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('无 album.json → null；record 建最小 sidecar 并可读回', () async {
      expect(await AlbumMetadataWriter.readTranslationVolume(tmp), isNull);
      await AlbumMetadataWriter.recordTranslationVolume(tmp, volume: 0.85);
      expect(await AlbumMetadataWriter.readTranslationVolume(tmp), 0.85);
      // 最小 sidecar：文件已存在且是合法 JSON
      final json = jsonDecode(
        await File('${tmp.path}/album.json').readAsString(),
      );
      expect(json, isA<Map<String, dynamic>>());
    });

    test('再次 record 覆盖同键、不碰别的键', () async {
      await AlbumMetadataWriter.recordFileKey(
        tmp,
        fileName: 'a.mp3',
        fileKey: 'k1',
      );
      await AlbumMetadataWriter.recordTranslationVolume(tmp, volume: 0.5);
      await AlbumMetadataWriter.recordTranslationVolume(tmp, volume: 0.3);
      expect(await AlbumMetadataWriter.readTranslationVolume(tmp), 0.3);
      expect((await AlbumMetadataWriter.readFileKeys(tmp))['a.mp3'], 'k1');
    });

    test('write 重写 album.json 不丢 translationVolume', () async {
      await AlbumMetadataWriter.recordTranslationVolume(tmp, volume: 0.42);
      await AlbumMetadataWriter.write(tmp, work: mkWork(title: '重写音量'));
      expect(await AlbumMetadataWriter.readTranslationVolume(tmp), 0.42);
      // 且 work 本体已写入
      final json = jsonDecode(
        await File('${tmp.path}/album.json').readAsString(),
      ) as Map<String, dynamic>;
      expect(json['work'], isA<Map<String, dynamic>>());
    });

    test('越界值钳位；非数值读为 null', () async {
      await AlbumMetadataWriter.recordTranslationVolume(tmp, volume: 2.5);
      expect(await AlbumMetadataWriter.readTranslationVolume(tmp), 1.0);
      await AlbumMetadataWriter.recordTranslationVolume(tmp, volume: -1);
      expect(await AlbumMetadataWriter.readTranslationVolume(tmp), 0.0);

      // 手工塞坏值
      final file = File('${tmp.path}/album.json');
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      json[AlbumMetadataWriter.translationVolumeKey] = 'oops';
      await file.writeAsString(jsonEncode(json));
      expect(await AlbumMetadataWriter.readTranslationVolume(tmp), isNull);
    });
  });
}
