import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:aaplay/core/download/album_metadata_writer.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/core/download/models/download_entry.dart';
import 'package:aaplay/core/download/models/work_snapshot.dart';
import 'package:aaplay/core/download/storage/i_download_repository.dart';
import 'package:aaplay/core/download/storage/i_work_snapshot_repository.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';

/// 内存假 downloads 表：模拟 UNIQUE(work_id, file_key)。
class _MemDownloadRepo implements IDownloadRepository {
  final Map<String, DownloadEntry> _rows = {};

  String _k(String workId, String fileKey) => '$workId|$fileKey';

  Map<String, DownloadEntry> get rows => Map.unmodifiable(_rows);

  @override
  Future<DownloadEntry?> find(String workId, String fileKey) async =>
      _rows[_k(workId, fileKey)];

  @override
  Future<void> upsert(DownloadEntry entry) async =>
      _rows[_k(entry.workId, entry.fileKey)] = entry;

  @override
  Future<void> remove(String workId, String fileKey) async =>
      _rows.remove(_k(workId, fileKey));

  @override
  Future<List<DownloadEntry>> listByWork(String workId) async => _rows.values
      .where((e) => e.workId == workId)
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<List<DownloadEntry>> listAllOldestFirst() async {
    final list = _rows.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }
}

/// 内存假 work_snapshots。
class _MemSnapshotRepo implements IWorkSnapshotRepository {
  final Map<String, WorkSnapshot> _snap = {};

  WorkSnapshot? operator [](String workId) => _snap[workId];

  @override
  Future<void> save(String workId, {required Work work, Files? files}) async {
    _snap[workId] = WorkSnapshot(
      work: work,
      files: files,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<WorkSnapshot?> load(String workId) async => _snap[workId];

  @override
  Future<void> remove(String workId) async => _snap.remove(workId);
}

DownloadEntry _entry({
  required String workId,
  required String fileKey,
  required String filePath,
  int createdAt = 1,
}) {
  return DownloadEntry(
    workId: workId,
    fileKey: fileKey,
    fileName: p.basename(filePath),
    filePath: filePath,
    mediaType: 'audio',
    sourceUrl: '',
    size: 1,
    createdAt: createdAt,
  );
}

void main() {
  late Directory root;
  late Directory extra;
  late _MemDownloadRepo downloads;
  late _MemSnapshotRepo snapshots;
  late DownloadService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aaplay_scan_root_');
    extra = await Directory.systemTemp.createTemp('aaplay_scan_extra_');
    downloads = _MemDownloadRepo();
    snapshots = _MemSnapshotRepo();
    service = DownloadService(repository: downloads, snapshots: snapshots);
  });

  tearDown(() async {
    for (final d in [root, extra]) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  });

  /// 布局 `<root>/<workId>/<fileKey>/<name>`。
  Future<String> putFile(
    Directory base,
    String workId,
    String key,
    String name, {
    String content = 'x',
  }) async {
    final dir = Directory(p.join(base.path, workId, key));
    await dir.create(recursive: true);
    final f = File(p.join(dir.path, name));
    await f.writeAsString(content);
    return f.path;
  }

  group('DownloadService.scanRoots', () {
    test('磁盘有文件、DB 无行 → 回填 1 条（mediaType 空，扩展名分类）',
        () async {
      final path = await putFile(root, 'w1', 'k1', '01.mp3');

      final added = await service.scanRoots([root.path]);

      expect(added, 1);
      final row = await downloads.find('w1', 'k1');
      expect(row, isNotNull);
      expect(row!.filePath, path);
      expect(row.fileName, '01.mp3');
      expect(row.mediaType, '');
      expect(row.size, greaterThan(0));
    });

    test('DB 已有有效行（文件在盘）→ 不改 file_path（路径稳定）', () async {
      final path = await putFile(root, 'w1', 'k1', '01.mp3');
      final existing = _entry(
        workId: 'w1',
        fileKey: 'k1',
        filePath: path,
        createdAt: 99,
      );
      await downloads.upsert(existing);

      final added = await service.scanRoots([root.path]);

      expect(added, 0);
      final row = await downloads.find('w1', 'k1');
      expect(row!.filePath, path);
      expect(row.createdAt, 99);
      expect(row.mediaType, 'audio'); // 未被扫盘覆写成 ''
    });

    test('失效行（文件被移走但 key 下有新文件）→ 删旧行再回填新 path',
        () async {
      final stalePath = p.join(
          root.path, 'w1', 'k1', 'gone.mp3'); // 盘上不存在
      await downloads.upsert(_entry(
        workId: 'w1',
        fileKey: 'k1',
        filePath: stalePath,
      ));
      final fresh = await putFile(root, 'w1', 'k1', '01.mp3');

      final added = await service.scanRoots([root.path]);

      expect(added, 1);
      final row = await downloads.find('w1', 'k1');
      expect(row!.filePath, fresh);
    });

    test('跳过 .dl_tmp / .dl_bak；album.json 在 work 根不当媒体行',
        () async {
      final keyDir = Directory(p.join(root.path, 'w1', 'k1'))
        ..createSync(recursive: true);
      File(p.join(keyDir.path, '01.mp3.dl_tmp')).writeAsStringSync('t');
      File(p.join(keyDir.path, '01.mp3.dl_bak')).writeAsStringSync('b');
      // work 根的 sidecar（File，非 Directory）。
      File(p.join(root.path, 'w1', 'album.json')).writeAsStringSync('{}');

      final added = await service.scanRoots([root.path]);

      expect(added, 0);
      expect(await downloads.find('w1', 'k1'), isNull);
      expect(
        downloads.rows.values.where((e) => e.fileKey == 'album.json'),
        isEmpty,
      );
    });

    test('多根：默认根 + 附加目录都能回填', () async {
      await putFile(root, 'wA', 'kA', 'a.mp3');
      await putFile(extra, 'wB', 'kB', 'b.mp3');

      final added = await service.scanRoots([root.path, extra.path]);

      expect(added, 2);
      expect(await downloads.find('wA', 'kA'), isNotNull);
      expect(await downloads.find('wB', 'kB'), isNotNull);
    });

    test('不存在的根目录：跳过不抛、不影响其他根', () async {
      await putFile(root, 'w1', 'k1', '01.mp3');
      final missing = p.join(root.path, '__nope__');

      final added = await service.scanRoots([missing, root.path]);

      expect(added, 1);
      expect(await downloads.find('w1', 'k1'), isNotNull);
    });

    test('album.json 存在且快照缺失 → 按 work.id 导入（非目录名）', () async {
      await putFile(root, 'w1', 'k1', '01.mp3');
      final work = Work(id: 1, title: '导入作品', sourceId: 'w1');
      File(p.join(root.path, 'w1', 'album.json')).writeAsStringSync(
        jsonEncode(WorkSnapshot(
          work: work,
          files: null,
          updatedAt: 1700000000000,
        ).toJson()),
      );

      final added = await service.scanRoots([root.path]);

      expect(added, 1);
      final snap = await snapshots.load('1');
      expect(snap, isNotNull);
      expect(snap!.work.title, '导入作品');
      // 媒体行也挂在 album 的 work.id 下（与目录名 w1 解耦）。
      expect(await downloads.find('1', 'k1'), isNotNull);
      expect(await downloads.find('w1', 'k1'), isNull);
      // save() 接口本身会把 updatedAt 盖成 now（与 WorkSnapshotRepository
      // 一致），此处只断言导入成功、不依赖 sidecar 的时间戳透传。
      expect(snap.updatedAt, greaterThan(0));
    });

    test('album.json 比现有快照旧 → 不覆盖', () async {
      await putFile(root, 'w1', 'k1', '01.mp3');
      final newer = Work(id: 1, title: '较新快照', sourceId: 'w1');
      await snapshots.save('1', work: newer);
      final before = (await snapshots.load('1'))!;

      final album = File(p.join(root.path, 'w1', 'album.json'));
      album.writeAsStringSync(
        '{"work":{"id":1,"title":"旧sidecar","source_id":"w1"},"updatedAt":1}',
      );

      await service.scanRoots([root.path]);

      final after = (await snapshots.load('1'))!;
      expect(after.work.title, before.work.title);
      expect(after.updatedAt, before.updatedAt);
    });

    test('album.json 损坏：不抛，仍回填媒体行（workId 回退目录名）', () async {
      await putFile(root, 'w1', 'k1', '01.mp3');
      File(p.join(root.path, 'w1', 'album.json')).writeAsStringSync('not json');

      final added = await service.scanRoots([root.path]);

      expect(added, 1);
      expect(await downloads.find('w1', 'k1'), isNotNull);
      expect(await snapshots.load('w1'), isNull);
    });
  });

  group('DownloadService.scanRoots 拍平布局', () {
    /// 布局 `<root>/<标题>/<文件>` + album.json sidecar。
    Future<String> putFlat(
      Directory base,
      String dirName, {
      required Work work,
      required Map<String, String> fileKeys,
      required List<(String name, String content)> files,
    }) async {
      final workDir = Directory(p.join(base.path, dirName))
        ..createSync(recursive: true);
      File(p.join(workDir.path, 'album.json')).writeAsStringSync(
        jsonEncode({
          ...AlbumMetadataWriter.payload(work: work, updatedAt: 2),
          AlbumMetadataWriter.fileKeysKey: fileKeys,
        }),
      );
      late String first;
      for (final (name, content) in files) {
        final f = File(p.join(workDir.path, name))..writeAsStringSync(content);
        if (name == files.first.$1) first = f.path;
      }
      return first;
    }

    test('sidecar fileKeys 回填 file_key 与下载身份一致', () async {
      final key = 'a' * 32;
      final path = await putFlat(
        root,
        '夜の耳かき',
        work: Work(id: 7, title: '夜の耳かき', sourceId: 'r7'),
        fileKeys: {'01.mp3': key},
        files: [('01.mp3', 'x')],
      );

      final added = await service.scanRoots([root.path]);

      expect(added, 1);
      final row = await downloads.find('7', key);
      expect(row, isNotNull);
      expect(row!.filePath, path);
      expect(row.fileName, '01.mp3');
      final snap = await snapshots.load('7');
      expect(snap, isNotNull);
      expect(snap!.work.title, '夜の耳かき');
    });

    test('已有有效行路径稳定（拍平）', () async {
      final key = 'b' * 32;
      final path = await putFlat(
        root,
        '标题作品',
        work: Work(id: 8, title: '标题作品', sourceId: 'r8'),
        fileKeys: {'a.mp3': key},
        files: [('a.mp3', 'x')],
      );
      final existing = _entry(
        workId: '8',
        fileKey: key,
        filePath: path,
        createdAt: 42,
      );
      await downloads.upsert(existing);

      final added = await service.scanRoots([root.path]);

      expect(added, 0);
      final row = await downloads.find('8', key);
      expect(row!.filePath, path);
      expect(row.createdAt, 42);
    });

    test('无 fileKeys sidecar → 合成 md5(path) 回填（列表可用）', () async {
      final workDir = Directory(p.join(root.path, 'orphan'))..createSync();
      final f = File(p.join(workDir.path, 'b.mp3'))..writeAsStringSync('z');

      final added = await service.scanRoots([root.path]);

      expect(added, 1);
      final rows = downloads.rows.values
          .where((e) => e.filePath == f.path)
          .toList();
      expect(rows, hasLength(1));
      expect(rows.single.workId, 'orphan');
      expect(rows.single.fileKey, hasLength(32));
    });

    test('album.json 不当媒体行；.dl_tmp 跳过（拍平）', () async {
      final workDir = Directory(p.join(root.path, 'T'))..createSync();
      File(p.join(workDir.path, 'album.json')).writeAsStringSync('{}');
      File(p.join(workDir.path, 'x.mp3.dl_tmp')).writeAsStringSync('t');

      final added = await service.scanRoots([root.path]);

      expect(added, 0);
      expect(downloads.rows, isEmpty);
    });

    test('legacy 与拍平根可混扫', () async {
      await putFile(root, 'w1', 'k1', '01.mp3');
      await putFlat(
        root,
        '另一部',
        work: Work(id: 9, title: '另一部', sourceId: 'r9'),
        fileKeys: {'m.mp3': 'c' * 32},
        files: [('m.mp3', 'y')],
      );

      final added = await service.scanRoots([root.path]);

      expect(added, 2);
      expect(await downloads.find('w1', 'k1'), isNotNull);
      expect(await downloads.find('9', 'c' * 32), isNotNull);
    });
  });
}
