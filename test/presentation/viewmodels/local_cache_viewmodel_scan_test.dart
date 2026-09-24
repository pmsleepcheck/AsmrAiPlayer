import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/core/download/models/download_entry.dart';
import 'package:aaplay/core/download/models/work_snapshot.dart';
import 'package:aaplay/core/download/storage/i_download_repository.dart';
import 'package:aaplay/core/download/storage/i_work_snapshot_repository.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/presentation/viewmodels/local_cache_viewmodel.dart';

class _UnusedRepo implements IDownloadRepository {
  @override
  Future<DownloadEntry?> find(String workId, String fileKey) async => null;
  @override
  Future<void> upsert(DownloadEntry entry) async {}
  @override
  Future<void> remove(String workId, String fileKey) async {}
  @override
  Future<List<DownloadEntry>> listByWork(String workId) async => const [];
  @override
  Future<List<DownloadEntry>> listAllOldestFirst() async => const [];
}

class _NullSnapshots implements IWorkSnapshotRepository {
  @override
  Future<void> save(String workId, {required Work work, Files? files}) async {}
  @override
  Future<WorkSnapshot?> load(String workId) async => null;
  @override
  Future<void> remove(String workId) async {}
}

/// 覆写扫盘/列表的假服务：单测不碰 path_provider 与真实磁盘。
class _StubDownloadService extends DownloadService {
  final int scanResult;
  final Object? scanError;
  final List<DownloadEntry> entries;
  int scanCalls = 0;
  int listCalls = 0;

  _StubDownloadService({
    required this.entries,
    this.scanResult = 0,
    this.scanError,
  }) : super(repository: _UnusedRepo());

  @override
  Future<int> scanDownloadsRoots() async {
    scanCalls++;
    final err = scanError;
    if (err != null) throw err;
    return scanResult;
  }

  @override
  Future<List<DownloadEntry>> listAllDownloads() async {
    listCalls++;
    return entries;
  }
}

LocalCacheViewModel _vm(_StubDownloadService service) => LocalCacheViewModel(
      downloadService: service,
      snapshotRepository: _NullSnapshots(),
    );

DownloadEntry _entry(String id) => DownloadEntry(
      workId: id,
      fileKey: 'k$id',
      fileName: '$id.mp3',
      filePath: '/tmp/$id.mp3',
      mediaType: 'audio',
      sourceUrl: '',
      size: 1,
      createdAt: 1,
    );

void main() {
  test('load(scan: true) 扫盘后再列 DB，记录 lastScanAdded', () async {
    final service = _StubDownloadService(
      entries: [_entry('1'), _entry('2')],
      scanResult: 2,
    );
    final vm = _vm(service);
    await vm.load(scan: true);
    expect(service.scanCalls, 1);
    expect(service.listCalls, 1);
    expect(vm.lastScanAdded, 2);
    expect(vm.groups, hasLength(2));
    expect(vm.visibleCount, 2);
    expect(vm.error, isNull);
    vm.dispose();
  });

  test('scanAndLoad 返回新增数并刷新分组', () async {
    final service = _StubDownloadService(
      entries: [_entry('9')],
      scanResult: 5,
    );
    final vm = _vm(service);
    final added = await vm.scanAndLoad();
    expect(added, 5);
    expect(vm.lastScanAdded, 5);
    expect(service.scanCalls, 1);
    expect(service.listCalls, 1);
    expect(vm.visibleCount, 1);
    vm.dispose();
  });

  test('扫盘抛错：scanAndLoad 返回 null，列表仍加载', () async {
    final service = _StubDownloadService(
      entries: [_entry('1')],
      scanError: StateError('io'),
    );
    final vm = _vm(service);
    final added = await vm.scanAndLoad();
    expect(added, isNull);
    expect(service.listCalls, 1);
    expect(vm.visibleCount, 1);
    expect(vm.lastScanAdded, isNull);
    vm.dispose();
  });

  test('load(scan: true) 扫盘抛错：error 不被置位，列表正常', () async {
    final service = _StubDownloadService(
      entries: [_entry('3')],
      scanError: StateError('io'),
    );
    final vm = _vm(service);
    await vm.load(scan: true);
    expect(vm.error, isNull);
    expect(vm.groups, hasLength(1));
    vm.dispose();
  });

  test('未调用 scan 时 lastScanAdded 为 null', () {
    final vm = _vm(_StubDownloadService(entries: const []));
    expect(vm.lastScanAdded, isNull);
    vm.dispose();
  });

  test('load() 不带 scan：不触发扫盘', () async {
    final service = _StubDownloadService(entries: [_entry('1')]);
    final vm = _vm(service);
    await vm.load();
    expect(service.scanCalls, 0);
    expect(vm.lastScanAdded, isNull);
    vm.dispose();
  });
}
