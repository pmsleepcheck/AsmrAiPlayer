import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:aaplay/core/download/models/download_entry.dart';
import 'package:aaplay/core/download/storage/i_download_repository.dart';
import 'package:aaplay/core/network/proxy_config.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';
import 'package:aaplay/data/models/files/child.dart';
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

  /// [settings] 可选：提供时挂应用内代理（`ProxyConfig.apply`）；
  /// 单元测试不传即可保持裸 `Dio()` 行为不变。
  DownloadService({
    required IDownloadRepository repository,
    Dio? dio,
    AppSettingsService? settings,
  })  : _repository = repository,
        _dio = dio ?? Dio() {
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
  /// 扩展名）。物理唯一性由 `_destPath` 的 `<fileKey>/` 子目录保证，故此处
  /// 不再用 md5 命名——用户在电脑上看到的就是接口文件列表里的名字。
  static String diskFileName(Child file) {
    return sanitizeFileName(file.title ?? '');
  }

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

  Future<Directory> _workDir(String workId) async {
    final base = await _baseDir();
    final dir = Directory(p.join(base.path, 'downloads', workId));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// 落盘路径 = `<下载根>/downloads/<workId>/<fileKey>/<原始标题>`。
  /// 每个文件独占 `<fileKey>/` 子目录：同一作品树内不同文件夹的同名文件
  /// （如各章节都有 `01.mp3`，但 hash/url 不同 → fileKey 不同）互不覆盖，
  /// 同时文件名保持接口原样、用户在电脑上可读。tmp/bak/dest 同处该子目录，
  /// 同卷 rename 原子写不变量不受影响。
  Future<String> _destPath(String workId, Child file) async {
    final dir = await _workDir(workId);
    final sub = Directory(p.join(dir.path, fileKey(file)));
    if (!await sub.exists()) await sub.create(recursive: true);
    return p.join(sub.path, diskFileName(file));
  }

  /// best-effort 删除已空的 `<fileKey>/` 子目录（删文件后调用），
  /// 让用户可见的下载文件夹不残留空 md5 目录；失败无害（与孤儿文件同理）。
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
  /// DB miss 时做**磁盘回退**：直接看 `downloads/<workId>/<key>/` 下是否已有
  /// 成品文件（排除 `.dl_tmp`/`.dl_bak`），命中则 best-effort 回填 DB 行。
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

  /// 磁盘回退：`downloads/<workId>/<key>/` 下已有成品 → 回填 DB 并返回。
  Future<DownloadEntry?> _recoverFromDisk(String workId, String key) async {
    try {
      final base = await _baseDir();
      final sub = Directory(p.join(base.path, 'downloads', workId, key));
      if (!await sub.exists()) return null;
      await for (final entity in sub.list(followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (path.endsWith('.dl_tmp') || path.endsWith('.dl_bak')) continue;
        final stat = await entity.stat();
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
    } catch (e) {
      AppLogger.warning('磁盘回退扫描失败: $workId/$key ($e)');
    }
    return null;
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

  /// 最终回退：按 `diskFileName(file)` 扫该作品所有 `<fileKey>/` 子目录。
  /// 仅唯一命中时回填主 key（同名多份 = 歧义，宁可 miss 不误配）。
  Future<String?> _recoverByFileName(String workId, Child file) async {
    try {
      final name = diskFileName(file);
      final base = await _baseDir();
      final workDir = Directory(p.join(base.path, 'downloads', workId));
      if (!await workDir.exists()) return null;
      final matches = <String>[];
      await for (final keyDir in workDir.list(followLinks: false)) {
        if (keyDir is! Directory) continue;
        final candidate = File(p.join(keyDir.path, name));
        if (await _filePresent(candidate.path)) matches.add(candidate.path);
      }
      if (matches.length == 1) {
        final path = matches.single;
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
      if (matches.length > 1) {
        AppLogger.warning('同名多份磁盘文件，跳过模糊回退: $workId/$name');
      }
    } catch (e) {
      AppLogger.warning('按文件名磁盘回退失败: $e');
    }
    return null;
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

  /// 扫 `downloads/<workId>/<fileKey>/` → fileKey→绝对路径（一 key 取一个成品）。
  Future<Map<String, String>> _diskPathsForWork(String workId) async {
    final out = <String, String>{};
    try {
      final base = await _baseDir();
      final workDir = Directory(p.join(base.path, 'downloads', workId));
      if (!await workDir.exists()) return out;
      await for (final keyDir in workDir.list(followLinks: false)) {
        if (keyDir is! Directory) continue;
        final key = p.basename(keyDir.path);
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
      AppLogger.warning('磁盘扫描下载目录失败: $workId ($e)');
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
  Future<DownloadResult> download({
    required String workId,
    required Child file,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
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
        return DownloadResult(DownloadStatus.alreadyExists, existingPath);
      }

      destPath = await _destPath(workId, file);
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
      keysToRemove.add(p.basename(p.dirname(path)));
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
