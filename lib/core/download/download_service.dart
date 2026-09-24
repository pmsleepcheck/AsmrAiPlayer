import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aaplay/core/download/album_metadata_writer.dart';
import 'package:aaplay/core/download/models/download_entry.dart';
import 'package:aaplay/core/download/models/work_snapshot.dart';
import 'package:aaplay/core/download/storage/i_download_repository.dart';
import 'package:aaplay/core/download/storage/i_work_snapshot_repository.dart';
import 'package:aaplay/core/network/proxy_config.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/utils/logger.dart';

enum DownloadStatus {
  success,
  alreadyExists,
  cancelled,
  networkError,
  ioError,
}

class DownloadResult {
  final DownloadStatus status;

  /// 完成（success / alreadyExists）时的本地绝对路径，否则 null。
  final String? localPath;

  const DownloadResult(this.status, [this.localPath]);

  bool get isPlayable =>
      status == DownloadStatus.success ||
      status == DownloadStatus.alreadyExists;
}

/// 本地媒体下载服务。
///
/// - 用**独立 `Dio()`**（无 `AuthInterceptor`、不随节点轮换）：媒体
///   `mediaDownloadUrl` 是 API 下发的预签名/限时绝对地址，与 asmr 节点无关，
///   `LockCachingAudioSource` 也是无 token 直取（见 spike 结论）。
/// - Android 落盘在**外部应用专属目录** `getExternalStorageDirectory()`
///   （`/storage/emulated/0/Android/data/<pkg>/files/downloads/<workId>/`）：
///   该目录在所有 Android 版本均无需声明存储权限、规避 scoped storage，
///   且可经 USB/MTP 在电脑端访问；卸载随 App 清理。取不到时回退 App 内部
///   `getApplicationDocumentsDirectory()`。非 Android 平台仍用内部目录
///   （`getExternalStorageDirectory()` 在 iOS 会抛 `UnsupportedError`）。
/// - 原子写复刻 `SubtitleImportService`：tmp → (备份旧文件) → rename → upsert，
///   任一步失败回滚，**新文件确认前绝不破坏已存在的好文件**。
/// - 容量 LRU 复刻 `AudioCacheManager`：删不掉的文件仍计入容量、不丢弃，
///   避免实际占用突破上限。
class DownloadService {
  static const int _maxTotalSize = 4 * 1024 * 1024 * 1024; // 4 GB

  final IDownloadRepository _repository;
  final Dio _dio;
  final AppSettingsService? _settings;
  final IWorkSnapshotRepository? _snapshots;

  /// [settings] 可选：提供时挂应用内代理（`ProxyConfig.apply`）并允许读取
  /// 附加缓存目录配置；单元测试不传即可保持裸 `Dio()` 行为不变。
  /// [snapshots] 可选：`download()` 写 `album.json` 时 work/files 未直传
  /// 的回退数据源（从 `work_snapshots` 表回填）。
  DownloadService({
    required IDownloadRepository repository,
    Dio? dio,
    AppSettingsService? settings,
    IWorkSnapshotRepository? snapshots,
  })  : _repository = repository,
        _dio = dio ?? Dio(),
        _settings = settings,
        _snapshots = snapshots {
    if (settings != null) {
      ProxyConfig.apply(_dio, settings);
    }
  }

  /// Windows/MTP 设备保留名（电脑端打不开/复制异常，与"外部可见"目标冲突）。
  static final RegExp _reservedStem = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$',
    caseSensitive: false,
  );

  /// 文件名安全化：**保留接口原始标题**（含日文/中文等 Unicode），
  /// 仅把文件系统真正非法的字符（路径分隔符、Windows/FAT/exFAT 保留字、
  /// 控制字符）替换为 `_`，并去掉首尾空白与**首尾点**（尾随点 FAT/Windows
  /// 会吞；前导点在 macOS/Linux/文件管理器里成隐藏文件，违背"外部可见"）。
  /// 退化输入（空 / 清理后只剩 `_ . 空格` / `.` / `..`）回退为 `file`；
  /// 命中 Windows 保留名加 `_` 前缀避开。结果确定。最后按 UTF-8 字节裁剪到
  /// [_maxNameBytes] 以下、保留扩展名，避免外部 SD（FAT/exFAT 单文件名
  /// 255 字节上限）写入失败。
  static String sanitizeFileName(String name) {
    var cleaned = name
        .replaceAll(RegExp(r'[\x00-\x1F/\\:*?"<>|]'), '_')
        .trim()
        .replaceAll(RegExp(r'^[.\s]+'), '')
        .replaceAll(RegExp(r'[.\s]+$'), '');
    if (cleaned.isEmpty || RegExp(r'^[_.\s]*$').hasMatch(cleaned)) {
      return 'file';
    }
    if (_reservedStem.hasMatch(p.basenameWithoutExtension(cleaned))) {
      cleaned = '_$cleaned';
    }
    return _clampNameBytes(cleaned);
  }

  /// FAT/exFAT 单文件名上限 255 字节；留余量给 `.dl_tmp`/`.dl_bak` 后缀。
  static const int _maxNameBytes = 180;

  /// 按 UTF-8 字节裁剪文件名到 [_maxNameBytes]，保留扩展名，
  /// 不在多字节字符中间截断（逐字符重建）。若"扩展名"本身异常长
  /// （非真扩展名）则当作正文整体裁剪，保证结果**必定** ≤ 上限。
  static String _clampNameBytes(String name) {
    if (utf8.encode(name).length <= _maxNameBytes) return name;
    var ext = p.extension(name);
    if (utf8.encode(ext).length > _maxNameBytes - 8) ext = '';
    final base = name.substring(0, name.length - ext.length);
    final budget = _maxNameBytes - utf8.encode(ext).length;
    final buf = StringBuffer();
    var used = 0;
    for (final ch in base.runes) {
      final chBytes = utf8.encode(String.fromCharCode(ch)).length;
      if (used + chBytes > budget) break;
      buf.writeCharCode(ch);
      used += chBytes;
    }
    final clampedBase = buf.toString().trim();
    return clampedBase.isEmpty ? 'file$ext' : '$clampedBase$ext';
  }

  /// 稳定身份键：DB 去重 / 查询 / 删除 / **落盘子目录** 都用它，**不用展示名**。
  ///
  /// 不同标题（`a/b.mp4` vs `a:b.mp4`、大量非 ASCII、同一作品树内不同文件夹
  /// 下同名 `01.mp3`）必须算作不同下载，否则会互相误判命中（DB 行或物理
  /// 路径）。落盘名已改回接口原始标题（见 [diskFileName]），同名冲突由
  /// `_destPath` 的 `<fileKey>/` 子目录隔离。身份取 `hash`（API 提供，最稳）
  /// > **去 query/fragment 的** `mediaDownloadUrl` > `title`，md5 摘要。
  ///
  /// 预签名 URL 的 query（`X-Amz-*` 等）每次签发都变，**绝不能进身份**——
  /// 否则跨会话 `findCompleted` 必 miss，看起来就是「匹配不上已下载」。
  static String fileKey(Child file) {
    final hash = file.hash;
    if (hash != null && hash.isNotEmpty) {
      return md5.convert(utf8.encode(hash)).toString();
    }
    final url = file.mediaDownloadUrl;
    if (url != null && url.isNotEmpty) {
      return md5.convert(utf8.encode(_stripUrlNoise(url))).toString();
    }
    return md5.convert(utf8.encode(file.title ?? 'file')).toString();
  }

  /// 去掉 URL 的 query/fragment（预签名 token / 锚点不参与身份）。
  /// 注意 `Uri.replace(query: null)` 是「保留原 query」——必须重建无 query 的
  /// Uri。解析失败时原样返回（保守：不丢身份，宁可 key 略脏）。
  static String _stripUrlNoise(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return url;
    try {
      return Uri(
        scheme: u.scheme,
        userInfo: u.userInfo,
        host: u.host,
        port: u.hasPort ? u.port : null,
        path: u.path,
      ).toString();
    } catch (_) {
      // 无 host 的相对 URL 等：直接截断到 path。
      final noFragment = url.split('#').first;
      return noFragment.split('?').first;
    }
  }

  /// 旧算法（URL **原样**进 md5）：仅用于回查历史 DB 行/落盘目录。
  /// [hash] 存在时与 [fileKey] 相同；无 hash 且 URL 带 query 时不同。
  static String legacyFileKey(Child file) {
    final idSource = (file.hash != null && file.hash!.isNotEmpty)
        ? file.hash!
        : (file.mediaDownloadUrl ?? file.title ?? 'file');
    return md5.convert(utf8.encode(idSource)).toString();
  }

  /// 查询用候选 key：新 key 优先，旧 key 兜底（二者相同则只返回一个）。
  static List<String> candidateKeys(Child file) {
    final primary = fileKey(file);
    final legacy = legacyFileKey(file);
    return legacy == primary ? [primary] : [primary, legacy];
  }

  /// 落盘文件名 = **接口返回的原始标题**（仅做 FS 安全化，保留可读性与
  /// 扩展名）。拍平布局下物理唯一性由 [_destPath] 的同名序号
  /// （`名 (2).ext`）保证，不再依赖 `<fileKey>/` 子目录。
  static String diskFileName(Child file) {
    return sanitizeFileName(file.title ?? '');
  }

  /// 作品目录名：优先可读标题（FS 安全化），无标题回退 [workId]。
  /// 与数字 workId 目录并存；冲突序号由 `_workDir` 分配。
  static String workDirName({String? title, required String workId}) {
    final t = title?.trim();
    if (t == null || t.isEmpty) return sanitizeFileName(workId);
    return sanitizeFileName(t);
  }

  /// 同名冲突序号：`track.mp3` + n=2 → `track (2).mp3`；n=1 → 原名。
  /// 扩展名（最后一个 `.` 后的段）保留在末尾；无扩展名则整体加后缀。
  static String sequenceDiskName(String name, int n) {
    if (n <= 1) return name;
    final ext = p.extension(name);
    final stem = name.substring(0, name.length - ext.length);
    if (stem.isEmpty) return '$name ($n)';
    return '$stem ($n)$ext';
  }

  /// 旧布局子目录名是否像 md5 fileKey（32 位小写十六进制）。
  /// 拍平布局的作品根目录名是标题，**不能**当 fileKey 用。
  static bool looksLikeFileKey(String name) =>
      RegExp(r'^[0-9a-f]{32}$').hasMatch(name);

  /// 下载根目录：Android 优先外部应用专属目录（电脑可见、免权限），
  /// 取不到则回退内部私有目录；非 Android 仅用内部目录。
  Future<Directory> _baseDir() async {
    if (Platform.isAndroid) {
      try {
        final ext = await getExternalStorageDirectory();
        if (ext != null) return ext;
      } catch (e) {
        AppLogger.warning('外部存储目录不可用，回退 App 内部目录: $e');
      }
    }
    return getApplicationDocumentsDirectory();
  }

  /// 下载根目录绝对路径 `<base>/downloads`（Android=外部应用专属，
  /// 其余平台=应用文档目录）。供 UI 展示/在资源管理器中打开。
  Future<String> downloadsRootPath() async {
    final base = await _baseDir();
    return p.join(base.path, 'downloads');
  }

  /// 全部可扫描根目录 = 默认下载根 + 设置里的附加目录（Win/Android 同一
  /// 代码路径）。附加目录是**只读扫描源**（新下载仍写默认根）；路径归一化
  /// 去尾部分隔符并按字符串去重，默认根恒在首位。
  Future<List<String>> downloadsRootPaths() async {
    final out = <String>[];
    final seen = <String>{};
    void add(String raw) {
      var path = raw.trim();
      if (path.isEmpty) return;
      while (path.length > 1 &&
          (path.endsWith('/') || path.endsWith(r'\'))) {
        path = path.substring(0, path.length - 1);
      }
      if (seen.add(path)) out.add(path);
    }

    add(await downloadsRootPath());
    for (final dir in _settings?.downloadExtraDirs ?? const <String>[]) {
      add(dir);
    }
    return out;
  }

  /// 定位作品目录（默认根优先，其次附加目录）；都不存在 → null。
  ///
  /// 解析顺序：① legacy `<root>/<workId>`（数字目录，存量布局）→
  /// ② 子目录 `album.json` 的 `work.id == workId`（标题拍平布局）→
  /// ③ `work_snapshots` 标题 → `<root>/<sanitize(title)>`。
  Future<Directory?> findWorkDir(String workId) async {
    final roots = await downloadsRootPaths();
    for (final root in roots) {
      final legacy = Directory(p.join(root, workId));
      if (await legacy.exists()) return legacy;
    }
    for (final root in roots) {
      final rootDir = Directory(root);
      if (!await rootDir.exists()) continue;
      try {
        await for (final entity in rootDir.list(followLinks: false)) {
          if (entity is! Directory) continue;
          final owner = await _albumWorkId(entity);
          if (owner == workId) return entity;
        }
      } catch (e) {
        AppLogger.warning('扫描作品目录失败（跳过）: $root ($e)');
      }
    }
    try {
      final title = (await _snapshots?.load(workId))?.work.title;
      if (title != null && title.trim().isNotEmpty) {
        final name = workDirName(title: title, workId: workId);
        for (final root in roots) {
          final dir = Directory(p.join(root, name));
          if (await dir.exists()) return dir;
        }
      }
    } catch (_) {}
    return null;
  }

  /// 读 `<dir>/album.json` 的 `work.id`（字符串形式）；缺失/损坏 → null。
  Future<String?> _albumWorkId(Directory dir) async {
    try {
      final file = File(p.join(dir.path, AlbumMetadataWriter.fileName));
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final work = decoded['work'];
      if (work is! Map<String, dynamic>) return null;
      final id = work['id'];
      if (id == null) return null;
      return id.toString();
    } catch (_) {
      return null;
    }
  }

  /// 读 album.json 的 `subtitleMatches`（无文件 → 空 map，best-effort）。
  Future<Map<String, String>> readSubtitleMatches(String workId) async {
    try {
      final dir = await findWorkDir(workId);
      if (dir == null) return {};
      return await AlbumMetadataWriter.readSubtitleMatches(dir);
    } catch (e) {
      AppLogger.warning('读取 subtitleMatches 失败: $workId ($e)');
      return {};
    }
  }

  /// 写一条字幕匹配进 album.json（best-effort，失败只 log）。
  /// [overwrite] false = 自动匹配（已有记录不覆盖）；true = 手工选择。
  /// 目录不存在时在**默认根**下创建（下载只写默认根）。
  Future<bool> recordSubtitleMatch(
    String workId, {
    required String audioPath,
    required String subtitlePath,
    bool overwrite = false,
  }) async {
    try {
      var dir = await findWorkDir(workId);
      dir ??= await _workDir(workId);
      await AlbumMetadataWriter.recordSubtitleMatch(
        dir,
        audioPath: audioPath,
        subtitlePath: subtitlePath,
        overwrite: overwrite,
      );
      return true;
    } catch (e) {
      AppLogger.warning('写入 subtitleMatches 失败: $workId ($e)');
      return false;
    }
  }

  /// 扫描全部根目录（默认 + 附加），把「盘上有、DB 缺/失效」的文件回填进
  /// `downloads` 表，并把作品根下的 `album.json` 导入 `work_snapshots`。
  /// 返回本次**新增/修复**的条目数。仅显式触发（进页/下拉/按钮），不进播放
  /// 热路径。失败的单个目录只记日志，不中断其余根。
  Future<int> scanDownloadsRoots() async {
    final roots = await downloadsRootPaths();
    return scanRoots(roots);
  }

/// 对给定 [roots] 执行扫盘（供 [scanDownloadsRoots] 与单测注入临时目录）。
  ///
  /// 双布局（盘为准）：
  /// - **legacy** `<root>/<workId>/<fileKey>/<文件>`：fileKey 取路径段；
  /// - **拍平** `<root>/<标题>/<文件>`：workId = `album.json` 的 `work.id`
  ///   （无 sidecar 回退目录名），fileKey = sidecar `fileKeys`（无则合成
  ///   md5(path)，徽章可能 miss 但列表/删除可用）。
  /// - 已有有效行（文件在盘）**不改 path**（路径稳定不变量）；
  /// - 缺行/失效行 → upsert（`mediaType:''`）；
  /// - `album.json` → 仅当快照缺失或 sidecar 更新时写入 `work_snapshots`。
  Future<int> scanRoots(Iterable<String> roots) async {
    var added = 0;
    final byPath = <String, DownloadEntry>{};
    try {
      for (final e in await _repository.listAllOldestFirst()) {
        byPath[e.filePath] = e;
      }
    } catch (_) {}
    for (final root in roots) {
      try {
        final rootDir = Directory(root);
        if (!await rootDir.exists()) continue;
        await for (final workEntity in rootDir.list(followLinks: false)) {
          if (workEntity is! Directory) continue;
          final workId =
              await _albumWorkId(workEntity) ?? p.basename(workEntity.path);
          await _importAlbumIfNewer(workId, workEntity);
          final fileKeys = await AlbumMetadataWriter.readFileKeys(workEntity);
          await for (final child in workEntity.list(followLinks: false)) {
            if (child is File) {
              if (await _scanFlatFile(
                workId: workId,
                file: child,
                fileKeys: fileKeys,
                byPath: byPath,
              )) {
                added++;
              }
              continue;
            }
            if (child is! Directory) continue;
            // legacy：作品根下的 <fileKey>/ 子目录。
            final key = p.basename(child.path);
            // 有效行不改 path：DB 已有且文件在盘 → 跳过（只补缺/失效）。
            final existing = await _repository.find(workId, key);
            if (existing != null && await _filePresent(existing.filePath)) {
              continue;
            }
            if (existing != null) {
              try {
                await _repository.remove(workId, key);
              } catch (_) {}
            }
            await for (final f in child.list(followLinks: false)) {
              if (f is! File) continue;
              final path = f.path;
              if (path.endsWith('.dl_tmp') || path.endsWith('.dl_bak')) {
                continue;
              }
              final stat = await f.stat();
              try {
                final row = DownloadEntry(
                  workId: workId,
                  fileKey: key,
                  fileName: p.basename(path),
                  filePath: path,
                  mediaType: '',
                  sourceUrl: '',
                  size: stat.size,
                  createdAt: stat.modified.millisecondsSinceEpoch,
                );
                await _repository.upsert(row);
                byPath[path] = row;
                added++;
                AppLogger.debug('扫盘回填下载行: $workId/$key');
              } catch (e) {
                AppLogger.warning('扫盘回填下载行失败: $e');
              }
              break; // 一 key 一成品（DB UNIQUE(work_id, file_key)）。
            }
          }
        }
      } catch (e) {
        AppLogger.warning('扫盘目录失败（跳过）: $root ($e)');
      }
    }
    return added;
  }

  /// 拍平布局单文件回填：路径稳定优先；缺行经 `fileKeys`/合成 key upsert。
  /// 返回是否新增了 DB 行。
  Future<bool> _scanFlatFile({
    required String workId,
    required File file,
    required Map<String, String> fileKeys,
    required Map<String, DownloadEntry> byPath,
  }) async {
    final path = file.path;
    final name = p.basename(path);
    if (path.endsWith('.dl_tmp') || path.endsWith('.dl_bak')) return false;
    if (name == AlbumMetadataWriter.fileName) return false;
    try {
      final byHit = byPath[path];
      if (byHit != null && await _filePresent(path)) {
        return false; // 路径稳定：有效行不改。
      }
      final key = fileKeys[name] ??
          byHit?.fileKey ??
          md5.convert(utf8.encode(path)).toString();
      final existing = await _repository.find(workId, key);
      if (existing != null && await _filePresent(existing.filePath)) {
        return false; // 同 key 已有有效行（可能指向另一路径）。
      }
      if (existing != null) {
        try {
          await _repository.remove(workId, key);
        } catch (_) {}
      }
      final stat = await file.stat();
      final row = DownloadEntry(
        workId: workId,
        fileKey: key,
        fileName: name,
        filePath: path,
        mediaType: '',
        sourceUrl: '',
        size: stat.size,
        createdAt: stat.modified.millisecondsSinceEpoch,
      );
      await _repository.upsert(row);
      byPath[path] = row;
      AppLogger.debug('扫盘回填拍平下载行: $workId/$name');
      return true;
    } catch (e) {
      AppLogger.warning('扫盘回填拍平行失败: $path ($e)');
      return false;
    }
  }

  /// 读 `<workDir>/album.json`，仅当快照缺失或 sidecar 更新时导入
  /// `work_snapshots`（best-effort：解析/IO 失败只 log）。
  Future<void> _importAlbumIfNewer(String workId, Directory workDir) async {
    final repo = _snapshots;
    if (repo == null) return;
    try {
      final file = File(p.join(workDir.path, AlbumMetadataWriter.fileName));
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final sidecar = WorkSnapshot.fromJson(decoded);
      final existing = await repo.load(workId);
      if (existing != null && existing.updatedAt >= sidecar.updatedAt) {
        return;
      }
      await repo.save(
        workId,
        work: sidecar.work,
        files: sidecar.files,
      );
      AppLogger.debug('扫盘导入专辑快照: $workId');
    } catch (e) {
      AppLogger.warning('读取/导入 album.json 失败: $workId ($e)');
    }
  }

  /// 定位/创建写入用作品目录（**仅默认根**，与旧 `_workDir` 一致）。
  /// 已有目录（legacy 数字 / album 归属匹配 / 无 sidecar 的同名标题）直接用；
  /// 标题目录被**其他** `work.id` 占用时分配 `标题 (n)` 序号。
  Future<Directory> _workDir(String workId, {Work? work}) async {
    final existing = await findWorkDir(workId);
    if (existing != null) return existing;
    var w = work;
    if (w == null) {
      try {
        w = (await _snapshots?.load(workId))?.work;
      } catch (_) {}
    }
    final base = workDirName(title: w?.title, workId: workId);
    final baseDir = await _baseDir();
    var name = base;
    var n = 1;
    while (true) {
      final dir = Directory(p.join(baseDir.path, 'downloads', name));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
        return dir;
      }
      final owner = await _albumWorkId(dir);
      // 无 sidecar 的空/用户目录视为可复用；归属他人则加序号。
      if (owner == null || owner == workId) return dir;
      n++;
      name = sequenceDiskName(base, n);
      if (n > 1000) {
        // 防御：序号穷尽仍冲突 → 用 workId 兜底（可读性让位于可写）。
        final fallback =
            Directory(p.join(baseDir.path, 'downloads', sanitizeFileName(workId)));
        if (!await fallback.exists()) await fallback.create(recursive: true);
        return fallback;
      }
    }
  }

  /// 落盘路径 = `<下载根>/downloads/<作品标题>/<原始标题>`（拍平 + 同名序号）。
  /// tmp/bak/dest 同目录，同卷 rename 原子写不变量不变。
  /// 调用前应已通过 `localPathIfDownloaded` 去重（同 fileKey 已存在不进这里）。
  Future<String> _destPath(Directory workDir, Child file) async {
    final base = diskFileName(file);
    var name = base;
    var n = 1;
    while (true) {
      final dest = p.join(workDir.path, name);
      final busy = await File(dest).exists() ||
          await File('$dest.dl_tmp').exists() ||
          await File('$dest.dl_bak').exists();
      if (!busy) return dest;
      n++;
      name = sequenceDiskName(base, n);
      if (n > 10000) return dest; // 防御死循环
    }
  }

  /// best-effort 删除已空的作品目录（删文件后调用；含 album.json 则不会空）。
  /// 失败无害（与孤儿文件同理）。
  Future<void> _pruneEmptyDir(String filePath) async {
    try {
      final parent = Directory(p.dirname(filePath));
      if (await parent.exists() && await parent.list().isEmpty) {
        await parent.delete();
      }
    } catch (_) {}
  }

  /// 已完成且文件确实在盘上的下载记录（按稳定身份 [key] 查）；若 DB 有行但
  /// 文件已丢失，删除失效行（一致性：失效行会让 app 误判已下载）后返回 null。
  ///
  /// DB miss 时做**磁盘回退**：legacy `<workId>/<key>/` 或拍平目录
  /// `fileKeys` 反查；命中则 best-effort 回填 DB 行。
  /// Windows 上 DB 路径不稳/行丢失时，文件仍在盘上也能匹配。
  Future<DownloadEntry?> findCompleted(String workId, String key) async {
    final entry = await _repository.find(workId, key);
    if (entry != null) {
      if (await _filePresent(entry.filePath)) return entry;
      AppLogger.warning('下载记录指向缺失文件，清理失效行: ${entry.filePath}');
      try {
        await _repository.remove(workId, key);
      } catch (e) {
        AppLogger.error('清理失效下载行失败', e);
      }
    }
    return _recoverFromDisk(workId, key);
  }

  Future<bool> _filePresent(String path) async {
    try {
      return await File(path).exists();
    } catch (e) {
      // Windows/OneDrive 等瞬时不可见：保守视为缺失（与旧行为一致），
      // 磁盘回退仍会再扫一次目录。
      AppLogger.warning('检查下载文件存在性失败: $path ($e)');
      return false;
    }
  }

  /// 磁盘回退：legacy `<workId>/<key>/` 或拍平作品目录（`fileKeys` 反查
  /// [key] → 文件名）已有成品 → 回填 DB 并返回。
  /// 遍历 [downloadsRootPaths]（默认根优先，附加目录随后）。
  Future<DownloadEntry?> _recoverFromDisk(String workId, String key) async {
    for (final root in await downloadsRootPaths()) {
      try {
        final legacy = Directory(p.join(root, workId, key));
        final hit = await _firstMediaFile(legacy);
        if (hit != null) {
          return _upsertRecovered(workId, key, hit);
        }
        // 拍平：作品根下 fileKeys 反查。
        final workDir = Directory(p.join(root, workId));
        if (await workDir.exists()) {
          final flat = await _recoverFlat(workDir, workId, key);
          if (flat != null) return flat;
        }
        final owned = await _findOwnedWorkDir(root, workId);
        if (owned != null) {
          final flat = await _recoverFlat(owned, workId, key);
          if (flat != null) return flat;
        }
      } catch (e) {
        AppLogger.warning('磁盘回退扫描失败: $root/$workId/$key ($e)');
      }
    }
    return null;
  }

  /// 拍平作品目录内按 `fileKeys` 反查 [key]；命中且文件在盘 → 回填。
  Future<DownloadEntry?> _recoverFlat(
    Directory workDir,
    String workId,
    String key,
  ) async {
    final map = await AlbumMetadataWriter.readFileKeys(workDir);
    String? name;
    map.forEach((k, v) {
      if (v == key) name = k;
    });
    if (name == null) return null;
    final path = p.join(workDir.path, name!);
    if (!await _filePresent(path)) return null;
    return _upsertRecovered(workId, key, path);
  }

  /// 扫 [root] 下 album.json `work.id == workId` 的目录（拍平标题目录）。
  Future<Directory?> _findOwnedWorkDir(String root, String workId) async {
    final rootDir = Directory(root);
    if (!await rootDir.exists()) return null;
    try {
      await for (final entity in rootDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (await _albumWorkId(entity) == workId) return entity;
      }
    } catch (_) {}
    return null;
  }

  /// 目录下第一个非 tmp/bak 成品文件路径；无 → null。
  Future<String?> _firstMediaFile(Directory dir) async {
    if (!await dir.exists()) return null;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (path.endsWith('.dl_tmp') || path.endsWith('.dl_bak')) continue;
      if (p.basename(path) == AlbumMetadataWriter.fileName) continue;
      if (await _filePresent(path)) return path;
    }
    return null;
  }

  Future<DownloadEntry> _upsertRecovered(
    String workId,
    String key,
    String path,
  ) async {
    final stat = await File(path).stat();
    final recovered = DownloadEntry(
      workId: workId,
      fileKey: key,
      fileName: p.basename(path),
      filePath: path,
      mediaType: '',
      sourceUrl: '',
      size: stat.size,
      createdAt: stat.modified.millisecondsSinceEpoch,
    );
    try {
      await _repository.upsert(recovered);
      AppLogger.debug('磁盘回退回填下载行: $workId/$key');
    } catch (e) {
      AppLogger.warning('磁盘回填下载行失败（仍返回路径）: $e');
    }
    return recovered;
  }

  /// 若该文件已完整下载，返回本地路径（供离线播放走本地源）。
  ///
  /// 匹配顺序：新 [fileKey] → 旧 [legacyFileKey]（历史预签名 URL 行）→
  /// 按落盘文件名扫 `downloads/<workId>/*/`（仅**唯一**命中才认，避免同名误配）。
  Future<String?> localPathIfDownloaded(String workId, Child file) async {
    if (file.title == null) return null;
    for (final key in candidateKeys(file)) {
      final entry = await findCompleted(workId, key);
      if (entry != null) return entry.filePath;
    }
    return _recoverByFileName(workId, file);
  }

  /// 最终回退：按 `diskFileName(file)` 扫该作品目录——legacy 的
  /// `<fileKey>/` 子目录 **和** 拍平的作品根（含 ` (n)` 序号名）。
  /// 仅全局**唯一**命中才认（跨根同名多份 = 歧义，宁可 miss 不误配）。
  Future<String?> _recoverByFileName(String workId, Child file) async {
    try {
      final name = diskFileName(file);
      final matches = <String>[];
      final seenDirs = <String>{};

      for (final root in await downloadsRootPaths()) {
        final candidates = <Directory>[];
        void addDir(Directory d) {
          if (seenDirs.add(p.canonicalize(d.path))) candidates.add(d);
        }

        final legacy = Directory(p.join(root, workId));
        if (await legacy.exists()) addDir(legacy);
        final owned = await _findOwnedWorkDir(root, workId);
        if (owned != null) addDir(owned);
        for (final workDir in candidates) {
          // 拍平：作品根下的文件（含序号后缀）。
          await for (final entity in workDir.list(followLinks: false)) {
            if (entity is! File) continue;
            final path = entity.path;
            if (path.endsWith('.dl_tmp') || path.endsWith('.dl_bak')) {
              continue;
            }
            if (p.basename(path) == AlbumMetadataWriter.fileName) continue;
            if (p.basename(path) == name) {
              matches.add(path);
            } else if (_isSequencedOf(path, name)) {
              matches.add(path);
            }
          }
          // legacy：各 <fileKey>/ 子目录精确名。
          await for (final keyDir in workDir.list(followLinks: false)) {
            if (keyDir is! Directory) continue;
            final candidate = File(p.join(keyDir.path, name));
            if (await _filePresent(candidate.path)) matches.add(candidate.path);
          }
          // 同一逻辑目录只扫一次（legacy 根可能 = owned）。
        }
      }
      // 去重（同一路径被两种布局规则各加一次）。
      final unique = matches.toSet().toList();
      if (unique.length == 1) {
        final path = unique.single;
        AppLogger.debug('按文件名磁盘回退命中: $workId/$name');
        try {
          final stat = await File(path).stat();
          await _repository.upsert(DownloadEntry(
            workId: workId,
            fileKey: fileKey(file),
            fileName: name,
            filePath: path,
            mediaType: (file.type ?? '').toLowerCase(),
            sourceUrl: file.mediaDownloadUrl ?? '',
            size: stat.size,
            createdAt: stat.modified.millisecondsSinceEpoch,
          ));
        } catch (e) {
          AppLogger.warning('按文件名回填下载行失败（仍返回路径）: $e');
        }
        return path;
      }
      if (unique.length > 1) {
        AppLogger.warning('同名多份磁盘文件，跳过模糊回退: $workId/$name');
      }
    } catch (e) {
      AppLogger.warning('按文件名磁盘回退失败: $e');
    }
    return null;
  }

  /// [path] 是否为 `base` 的序号变体（`base (2).ext` 等，n≥2）。
  static bool _isSequencedOf(String path, String base) {
    final b = p.basename(path);
    final ext = p.extension(base);
    final stem = base.substring(0, base.length - ext.length);
    if (stem.isEmpty) return false;
    return RegExp(
      '^${RegExp.escape(stem)} \\(\\d+\\)${RegExp.escape(ext)}\$',
      caseSensitive: false,
    ).hasMatch(b);
  }

  /// 批量解析某作品所有已完整下载的文件，供恢复/构建一个 N 轨播放列表时
  /// 一次性查表，取代逐轨调用 [localPathIfDownloaded]（N 次 DB 查询收敛为
  /// 一次 [IDownloadRepository.listByWork]）。
  ///
  /// 语义与 [localPathIfDownloaded] 对齐：**不能省** `File.exists()` 这道
  /// 存在性闸门——Android 下载目录在 PC 上可见，用户可能已手动删除文件；
  /// 若不过滤，返回的路径会喂给 `AudioSource.uri(Uri.file(缺失路径))`，
  /// 这个构造调用本身不抛，缺失文件只会在真正播放时才炸 `PlayerException`，
  /// 而不是像今天这样自然回退到流式播放。失效行按 [findCompleted] 同样的
  /// 顺序清理（先判存在性，不存在再删 DB 行）。
  ///
  /// 调用方（[PlaylistBuilder]）需要自行处理 `title == null` 的文件：
  /// 这类文件不可能已下载（[download] 本身要求非空文件名才会落盘），
  /// 不应该用它退化的 fileKey 去查这份 map。
  Future<Map<String, String>> localPathsForWork(String workId) async {
    final entries = await _repository.listByWork(workId);
    final map = <String, String>{};
    for (final entry in entries) {
      if (await _filePresent(entry.filePath)) {
        map[entry.fileKey] = entry.filePath;
        continue;
      }
      AppLogger.warning('下载记录指向缺失文件，清理失效行: ${entry.filePath}');
      try {
        await _repository.remove(entry.workId, entry.fileKey);
      } catch (e) {
        AppLogger.error('清理失效下载行失败', e);
      }
    }
    // 磁盘回退：DB 丢行 / 旧 fileKey 目录名仍有效时，从目录名补 map。
    final disk = await _diskPathsForWork(workId);
    for (final e in disk.entries) {
      if (map.containsKey(e.key)) continue;
      map[e.key] = e.value;
      try {
        final stat = await File(e.value).stat();
        await _repository.upsert(DownloadEntry(
          workId: workId,
          fileKey: e.key,
          fileName: p.basename(e.value),
          filePath: e.value,
          mediaType: '',
          sourceUrl: '',
          size: stat.size,
          createdAt: stat.modified.millisecondsSinceEpoch,
        ));
      } catch (err) {
        AppLogger.warning('磁盘回填下载行失败: $err');
      }
    }
    return map;
  }

  /// 扫全部根的作品目录 → fileKey→绝对路径（一 key 一个成品；
  /// 默认根先命中者优先，附加目录仅补默认根没有的 key）。
  /// 双布局：legacy `<workId>/<fileKey>/` 子目录 + 拍平作品根
  /// （`fileKeys` sidecar 反查；无 sidecar 不猜合成 key）。
  Future<Map<String, String>> _diskPathsForWork(String workId) async {
    final out = <String, String>{};
    for (final root in await downloadsRootPaths()) {
      final candidates = <Directory>[];
      final seenDirs = <String>{};
      void addDir(Directory d) {
        if (seenDirs.add(p.canonicalize(d.path))) candidates.add(d);
      }

      try {
        final legacy = Directory(p.join(root, workId));
        if (await legacy.exists()) addDir(legacy);
        final owned = await _findOwnedWorkDir(root, workId);
        if (owned != null) addDir(owned);
        final title = (await _snapshots?.load(workId))?.work.title;
        if (title != null && title.trim().isNotEmpty) {
          final named = Directory(p.join(
            root,
            workDirName(title: title, workId: workId),
          ));
          if (await named.exists()) addDir(named);
        }
      } catch (e) {
        AppLogger.warning('磁盘扫描下载目录失败: $root/$workId ($e)');
      }

      for (final workDir in candidates) {
        try {
          // 拍平：fileKeys sidecar → 文件名。
          final map = await AlbumMetadataWriter.readFileKeys(workDir);
          for (final e in map.entries) {
            if (out.containsKey(e.value)) continue;
            final fp = p.join(workDir.path, e.key);
            if (await _filePresent(fp)) out[e.value] = fp;
          }
          // legacy：各 <fileKey>/ 子目录。
          await for (final keyDir in workDir.list(followLinks: false)) {
            if (keyDir is! Directory) continue;
            final key = p.basename(keyDir.path);
            if (out.containsKey(key)) continue;
            await for (final f in keyDir.list(followLinks: false)) {
              if (f is! File) continue;
              if (f.path.endsWith('.dl_tmp') || f.path.endsWith('.dl_bak')) {
                continue;
              }
              out[key] = f.path;
              break;
            }
          }
        } catch (e) {
          AppLogger.warning('磁盘扫描下载目录失败: ${workDir.path} ($e)');
        }
      }
    }
    return out;
  }

  /// 纯映射：DB 行列表 → fileKey→filePath；不做任何 IO，供单测直接构造
  /// [DownloadEntry] 验证。调用方需自行保证传入的行已按作品过滤
  /// （[localPathsForWork] 经 `listByWork(workId)` 保证）。
  static Map<String, String> pathsByFileKey(List<DownloadEntry> entries) {
    return {for (final e in entries) e.fileKey: e.filePath};
  }

  /// 下载一个文件（音频/视频/字幕）到本地下载目录（Android 为外部应用专属
  /// 目录，详见类文档）。幂等：已完整下载则直接返回。
  ///
  /// [work]/[files] 可选：直传时用于成功后写 `album.json` 专辑信息；
  /// 缺省时从 `_snapshots`（`work_snapshots` 表）回填，仍取不到则跳过写入
  /// （best-effort，绝不影响下载结果）。
  Future<DownloadResult> download({
    required String workId,
    required Child file,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
    Work? work,
    Files? files,
  }) async {
    final url = file.mediaDownloadUrl;
    final fileName = file.title;
    if (url == null || url.isEmpty || fileName == null || fileName.isEmpty) {
      AppLogger.warning('下载缺少 URL 或文件名: $fileName');
      return const DownloadResult(DownloadStatus.ioError);
    }

    // 主 key（去 query 的 URL）；写盘/回填统一用它。
    final key = fileKey(file);

    // 前置 IO/DB（去重查询、路径解析、tmp/bak 构造）也纳入同一 try：
    // DB 打开/迁移失败、path_provider/目录创建失败、File.exists 权限异常
    // 均收敛为 ioError + 清理，绝不外抛未捕获异步异常。
    String? destPath;
    File? tmpFile;
    File? bakFile;
    var backedUp = false;

    try {
      // 去重：已完整下载直接复用（正常早返回，不进 catch）。
      // localPathIfDownloaded 覆盖新/旧 fileKey + 文件名磁盘回退，
      // 比单查 findCompleted(workId, key) 更能匹配历史预签名 URL 落盘。
      final existingPath = await localPathIfDownloaded(workId, file);
      if (existingPath != null) {
        await _writeAlbum(workId, work: work, files: files);
        await _recordFileKey(workId, existingPath, key, work: work);
        return DownloadResult(DownloadStatus.alreadyExists, existingPath);
      }

      final workDir = await _workDir(workId, work: work);
      destPath = await _destPath(workDir, file);
      final tmpPath = '$destPath.dl_tmp';
      final bakPath = '$destPath.dl_bak';
      tmpFile = File(tmpPath);
      bakFile = File(bakPath);

      // 1. 先下载到临时文件——失败时不动既有任何文件。
      await _dio.download(
        url,
        tmpPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (onProgress != null && total > 0) {
            onProgress(received / total);
          }
        },
      );

      // 2. 既有同路径文件先挪到备份，便于失败回滚。
      if (await File(destPath).exists()) {
        await File(destPath).rename(bakPath);
        backedUp = true;
      }

      // 3. 同卷 rename 原子生效。
      await tmpFile.rename(destPath);

      // 4. 持久化 DB（文件已就位）。
      final size = await File(destPath).length();
      await _repository.upsert(DownloadEntry(
        workId: workId,
        fileKey: key,
        fileName: fileName,
        filePath: destPath,
        mediaType: (file.type ?? '').toLowerCase(),
        sourceUrl: url,
        size: size,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));

      // 5. 成功——丢弃刚被替换文件的备份。
      if (backedUp) {
        try {
          if (await bakFile.exists()) await bakFile.delete();
        } catch (_) {}
      }

      // 6. 容量回收（失败不影响本次下载结果）。排除刚完成的文件，
      //    避免"先返回 success 再被异步回收删掉"导致 OpenFilex 打开到空路径。
      unawaited(enforceCapacity(
        exceptWorkId: workId,
        exceptFileKey: key,
      ));

      // 7. 专辑信息 sidecar（best-effort：失败仅 log，不影响 success）。
      await _writeAlbum(workId, work: work, files: files);
      await _recordFileKey(workId, destPath, key, work: work);

      AppLogger.debug('下载完成: $workId/$fileName -> $destPath');
      return DownloadResult(DownloadStatus.success, destPath);
    } catch (e) {
      // 清理临时文件并还原用户原文件，失败绝不破坏既有数据。
      // 前置失败时 tmp/bak/destPath 可能尚未赋值——null 守卫，绝不 NPE。
      final tf = tmpFile;
      final bf = bakFile;
      final dp = destPath;
      try {
        if (tf != null && await tf.exists()) await tf.delete();
      } catch (_) {}
      if (backedUp && bf != null && dp != null) {
        try {
          await bf.rename(dp);
        } catch (_) {}
      }
      if (e is DioException && CancelToken.isCancel(e)) {
        AppLogger.debug('下载已取消: $workId/$fileName');
        return const DownloadResult(DownloadStatus.cancelled);
      }
      if (e is DioException) {
        AppLogger.error('下载网络错误: $workId/$fileName', e);
        return const DownloadResult(DownloadStatus.networkError);
      }
      AppLogger.error('下载失败: $workId/$fileName', e);
      return const DownloadResult(DownloadStatus.ioError);
    }
  }

  /// 全部已完成下载（本地缓存页主数据源；与
  /// [IDownloadRepository.listAllOldestFirst] 同序）。**仅返回文件仍在盘上的
  /// 条目**——DB 有行但文件被用户手动删掉时不当作可播放缓存。
  Future<List<DownloadEntry>> listAllDownloads() async {
    final entries = await _repository.listAllOldestFirst();
    final live = <DownloadEntry>[];
    for (final e in entries) {
      if (await _filePresent(e.filePath)) live.add(e);
    }
    return live;
  }

  /// 下载成功/已存在时写 `<workDir>/album.json`（best-effort）。
  /// [work] 缺省时从 `work_snapshots` 回填；仍无则跳过（不写空文件）。
  Future<void> _writeAlbum(
    String workId, {
    Work? work,
    Files? files,
  }) async {
    try {
      var w = work;
      var f = files;
      if (w == null) {
        final snap = await _snapshots?.load(workId);
        w = snap?.work;
        f ??= snap?.files;
      }
      if (w == null) return;
      final dir = await _workDir(workId, work: w);
      await AlbumMetadataWriter.write(dir, work: w, files: f);
    } catch (e) {
      AppLogger.warning('写入专辑信息失败（不影响下载结果）: $e');
    }
  }

  /// best-effort 写 `fileKeys[落盘文件名] = fileKey`（拍平布局身份回填）。
  Future<void> _recordFileKey(
    String workId,
    String path,
    String key, {
    Work? work,
  }) async {
    try {
      final dir = await _workDir(workId, work: work);
      await AlbumMetadataWriter.recordFileKey(
        dir,
        fileName: p.basename(path),
        fileKey: key,
      );
    } catch (e) {
      AppLogger.warning('写入 fileKeys 失败（不影响下载结果）: $e');
    }
  }

  /// 按已完成条目删除（本地缓存页）。与 [removeDownload] 同一不变量：
  /// **DB 行先行**——至少一行删除成功才动文件，避免失效行 + 文件被删。
  Future<void> removeByEntry(DownloadEntry entry) async {
    var dbRemoved = false;
    try {
      await _repository.remove(entry.workId, entry.fileKey);
      dbRemoved = true;
    } catch (e) {
      AppLogger.error('移除下载 DB 行失败（保留文件以免失效行）', e);
    }
    if (!dbRemoved) return;
    try {
      final f = File(entry.filePath);
      if (await f.exists()) await f.delete();
      await _pruneEmptyDir(entry.filePath);
    } catch (e) {
      AppLogger.warning('移除下载文件失败（DB 行已删，孤儿无害）: $e');
    }
  }

  Future<void> removeDownload(String workId, Child file) async {
    final keys = candidateKeys(file);
    String? path;
    try {
      for (final key in keys) {
        final entry = await _repository.find(workId, key);
        if (entry != null) {
          path = entry.filePath;
          break;
        }
      }
      // DB 全 miss 时按文件名找盘上成品（与 localPathIfDownloaded 对称）。
      path ??= await _recoverByFileName(workId, file);
    } catch (e) {
      AppLogger.error('查询待移除下载失败', e);
    }
    // DB 行先删（一致性关键：失效行会让 app 误判已下载）；覆盖新/旧 key。
    // 仅当至少一行删除成功才动文件——避免 DB 失败时留下失效行却删了文件。
    var dbRemoved = false;
    final keysToRemove = <String>{...keys};
    if (path != null) {
      // legacy 布局下 dirname 是 md5 fileKey；拍平布局下是**标题目录名**，
      // 绝不能当 fileKey 去删行（会误删同名 key 或空转）。
      final parentName = p.basename(p.dirname(path));
      if (looksLikeFileKey(parentName)) {
        keysToRemove.add(parentName);
      }
    }
    for (final key in keysToRemove) {
      try {
        await _repository.remove(workId, key);
        dbRemoved = true;
      } catch (e) {
        AppLogger.error('移除下载 DB 行失败（保留文件以免失效行）', e);
      }
    }
    if (dbRemoved && path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
        await _pruneEmptyDir(path);
      } catch (e) {
        AppLogger.warning('移除下载文件失败（DB 行已删，孤儿无害）: $e');
      }
    }
  }

  /// 真 LRU：总量超上限时从最旧开始逐条删（文件 + DB 行），直到不超上限。
  /// 删不掉的文件仍在盘上 → 必须继续计入容量、且不删其 DB 行（行仍有效），
  /// 否则容量统计偏小、实际占用可能远超上限。
  Future<void> enforceCapacity({
    String? exceptWorkId,
    String? exceptFileKey,
  }) async {
    try {
      final entries = await _repository.listAllOldestFirst();
      var total = 0;
      final live = <DownloadEntry>[];
      for (final e in entries) {
        try {
          final f = File(e.filePath);
          if (await f.exists()) {
            total += (await f.stat()).size;
            live.add(e);
          } else {
            // 文件已不在：清失效行，不计容量。
            await _repository.remove(e.workId, e.fileKey);
          }
        } catch (_) {
          // stat 失败但行可能仍指向占用文件：用 DB size 保守计容量、
          // 保留在 live（与"删不掉/不可 stat 文件仍计容量"不变量一致）。
          total += e.size;
          live.add(e);
        }
      }
      for (final e in live) {
        if (total <= _maxTotalSize) break;
        // 跳过刚完成的文件：不能把用户刚要的东西回收掉。
        if (e.workId == exceptWorkId && e.fileKey == exceptFileKey) continue;
        try {
          final f = File(e.filePath);
          int sz;
          try {
            sz = await f.exists() ? (await f.stat()).size : e.size;
          } catch (_) {
            sz = e.size;
          }
          await f.delete();
          await _repository.remove(e.workId, e.fileKey);
          await _pruneEmptyDir(e.filePath);
          total -= sz;
        } catch (_) {
          // 占用中删不掉：保留文件与 DB 行（行仍有效），容量继续计，跳过。
        }
      }
    } catch (e) {
      AppLogger.error('下载容量回收失败', e);
    }
  }
}
