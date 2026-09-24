import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/core/download/models/download_entry.dart';
import 'package:aaplay/core/download/storage/i_work_snapshot_repository.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/utils/logger.dart';

/// 本地缓存过滤：全部 / 视频 / 音频。
enum LocalCacheFilter { all, video, audio }

/// 本地缓存页一条分组（按作品聚合的已下载文件）。
class LocalCacheWorkGroup {
  final String workId;
  final Work? work;
  final List<DownloadEntry> entries;

  const LocalCacheWorkGroup({
    required this.workId,
    required this.work,
    required this.entries,
  });

  String get title => work?.title ?? work?.sourceId ?? workId;

  String get subtitle =>
      work?.sourceId ?? Strings.unknownWork;
}

/// 「本地缓存」tab：列出全部已完成下载（DB 主数据源），按作品分组，
/// 可按类型过滤、播放、删除。**不扫盘做列表**（与
/// [DownloadService.listAllDownloads] 语义一致）；删除走
/// [DownloadService.removeByEntry]（DB 行先行不变量）。
class LocalCacheViewModel extends ChangeNotifier {
  final DownloadService _downloadService;
  final IWorkSnapshotRepository _snapshotRepository;

  LocalCacheViewModel({
    DownloadService? downloadService,
    IWorkSnapshotRepository? snapshotRepository,
  })  : _downloadService = downloadService ?? GetIt.I<DownloadService>(),
        _snapshotRepository = snapshotRepository ??
            GetIt.I<IWorkSnapshotRepository>();

  bool _isLoading = false;
  String? _error;
  LocalCacheFilter _filter = LocalCacheFilter.all;
  List<LocalCacheWorkGroup> _groups = const [];
  int? _totalCount;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  String? get error => _error;
  LocalCacheFilter get filter => _filter;
  List<LocalCacheWorkGroup> get groups => _groups;

  /// 当前过滤下可见条数；首次加载完成前为 null（AppBar 不显示 (0)）。
  int? get visibleCount => _totalCount;

  static const _videoExtensions = {'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v'};

  /// 视频判定与详情页一致：扩展名优先于不可靠的 API `media_type`。
  static bool isVideoEntry(DownloadEntry e) {
    if ((e.mediaType).toLowerCase() == 'video') return true;
    final ext = e.fileName.split('.').last.toLowerCase();
    return _videoExtensions.contains(ext);
  }

  static bool isAudioEntry(DownloadEntry e) {
    if (isVideoEntry(e)) return false;
    final t = e.mediaType.toLowerCase();
    if (t == 'audio') return true;
    // 历史行 mediaType 可能为 ''：非视频、有常见音频扩展名才当音频。
    if (t.isNotEmpty) return false;
    const audioExt = {
      'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wma', 'mp4a',
    };
    final ext = e.fileName.split('.').last.toLowerCase();
    return audioExt.contains(ext);
  }

  Future<void> load({bool silent = false}) async {
    if (_isLoading) return;
    _isLoading = true;
    if (!silent) {
      _error = null;
      notifyListeners();
    }
    try {
      final entries = await _downloadService.listAllDownloads();
      final filtered = entries.where((e) {
        switch (_filter) {
          case LocalCacheFilter.all:
            return true;
          case LocalCacheFilter.video:
            return isVideoEntry(e);
          case LocalCacheFilter.audio:
            return isAudioEntry(e);
        }
      }).toList();

      // 按 workId 分组，保持 listAllOldestFirst 内的时间顺序。
      final byWork = <String, List<DownloadEntry>>{};
      for (final e in filtered) {
        byWork.putIfAbsent(e.workId, () => []).add(e);
      }

      final groups = <LocalCacheWorkGroup>[];
      for (final e in byWork.entries) {
        Work? work;
        try {
          work = (await _snapshotRepository.load(e.key))?.work;
        } catch (err) {
          AppLogger.warning('读取本地缓存作品快照失败 ${e.key}: $err');
        }
        groups.add(LocalCacheWorkGroup(
          workId: e.key,
          work: work,
          entries: e.value.reversed.toList(), // 最新下载在前
        ));
      }

      if (_disposed) return;
      _groups = groups;
      _totalCount = filtered.length;
      _error = null;
    } catch (e) {
      AppLogger.error('加载本地缓存失败', e);
      if (!_disposed) _error = e.toString();
    } finally {
      if (!_disposed) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setFilter(LocalCacheFilter f) async {
    if (_filter == f) return;
    _filter = f;
    notifyListeners();
    await load();
  }

  /// 删除单条：成功后从内存移除并刷新计数（不整页 reload，避免闪烁）。
  Future<bool> removeEntry(DownloadEntry entry) async {
    try {
      await _downloadService.removeByEntry(entry);
      if (_disposed) return true;
      final next = <LocalCacheWorkGroup>[];
      for (final g in _groups) {
        if (g.workId != entry.workId) {
          next.add(g);
          continue;
        }
        final files = g.entries.where((e) => e.fileKey != entry.fileKey).toList();
        if (files.isNotEmpty) {
          next.add(LocalCacheWorkGroup(
            workId: g.workId,
            work: g.work,
            entries: files,
          ));
        }
      }
      _groups = next;
      if (_totalCount != null) {
        _totalCount = (_totalCount! - 1).clamp(0, 1 << 30);
      }
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.error('删除本地缓存条目失败', e);
      if (!_disposed) {
        _error = Strings.localCacheDeleteFailed;
        notifyListeners();
      }
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
