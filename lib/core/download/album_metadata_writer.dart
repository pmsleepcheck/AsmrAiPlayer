import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:aaplay/core/download/models/work_snapshot.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/utils/logger.dart';

/// 下载落盘时在作品根目录写 `album.json`（专辑/作品元数据 sidecar）。
///
/// - payload 复用 [WorkSnapshot.toJson]（`{work, files?, updatedAt}`），
///   与 SQLite `work_snapshots` 同 schema，`WorkSnapshot.fromJson` 直接
///   round-trip；扫盘时读回导入快照（见 `DownloadService.scanRoots`）。
/// - 位置固定 `<workDir>/album.json`（workId 根一层、不在 `<fileKey>/` 内）：
///   既有 fileKey 层磁盘扫描只进子目录，不会把 sidecar 误当媒体行。
/// - 原子写 `album.json.dl_tmp` → rename；**best-effort** —— 任何 IO 失败
///   只 log warning，绝不让元数据写失败影响下载结果。
class AlbumMetadataWriter {
  static const String fileName = 'album.json';

  /// sidecar-only 键：音频树路径 → 字幕树路径（不进 SQLite `work_snapshots`）。
  static const String subtitleMatchesKey = 'subtitleMatches';

  /// sidecar-only 键：落盘文件名 → `fileKey`（md5 身份）。拍平布局下
  /// 路径不再含 md5 层，扫盘/回退靠它把磁盘文件映射回 DB `file_key`。
  static const String fileKeysKey = 'fileKeys';

  /// sidecar-only 键：该作品的「翻译轨手动音量」(0..1)。
  /// 播放页手动调节后写入，下次播同一作品读回（跨设备拷走文件夹即带走）。
  static const String translationVolumeKey = 'translationVolume';

  /// 纯 payload 构造（供单测直接验证 round-trip，无 IO）。
  static Map<String, dynamic> payload({
    required Work work,
    Files? files,
    int? updatedAt,
  }) {
    return WorkSnapshot(
      work: work,
      files: files,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
    ).toJson();
  }

  static File _file(Directory workDir) => File(p.join(workDir.path, fileName));

  static Future<Map<String, dynamic>?> _readJson(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _atomicWrite(File dest, Map<String, dynamic> json) async {
    final tmp = File('${dest.path}.dl_tmp');
    try {
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
        flush: true,
      );
      await tmp.rename(dest.path);
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// 读 `subtitleMatches`（损坏/缺失 → 空 map；非 String 值忽略）。
  static Future<Map<String, String>> readSubtitleMatches(
      Directory workDir) async {
    final json = await _readJson(_file(workDir));
    final raw = json?[subtitleMatchesKey];
    if (raw is! Map) return {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v is String) out[k] = v;
    });
    return out;
  }

  /// 读 `fileKeys`（损坏/缺失 → 空 map；非 String 值忽略）。
  static Future<Map<String, String>> readFileKeys(Directory workDir) async {
    final json = await _readJson(_file(workDir));
    final raw = json?[fileKeysKey];
    if (raw is! Map) return {};
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v is String) out[k] = v;
    });
    return out;
  }

  /// 记录「落盘文件名 → fileKey」（读-合并-写；同名覆盖）。
  /// album.json 不存在则建最小 sidecar。best-effort 语义由调用方保证。
  static Future<void> recordFileKey(
    Directory workDir, {
    required String fileName,
    required String fileKey,
  }) async {
    final dest = _file(workDir);
    final json = await _readJson(dest) ?? <String, dynamic>{};
    final raw = json[fileKeysKey];
    final map = <String, dynamic>{
      if (raw is Map) ...raw,
    };
    map[fileName] = fileKey;
    json[fileKeysKey] = map;
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    await _atomicWrite(dest, json);
  }

  /// 记录一条匹配。[overwrite] = false 时 key 已存在则不改（自动匹配语义）；
  /// true 时覆盖（手工选择语义）。album.json 不存在则建最小 sidecar。
  static Future<void> recordSubtitleMatch(
    Directory workDir, {
    required String audioPath,
    required String subtitlePath,
    bool overwrite = false,
  }) async {
    final dest = _file(workDir);
    final json = await _readJson(dest) ?? <String, dynamic>{};
    final raw = json[subtitleMatchesKey];
    final matches = <String, dynamic>{
      if (raw is Map) ...raw,
    };
    if (!overwrite && matches.containsKey(audioPath)) return;
    matches[audioPath] = subtitlePath;
    json[subtitleMatchesKey] = matches;
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    await _atomicWrite(dest, json);
  }

  /// 读「翻译轨手动音量」（缺失/损坏/非数值 → null）。
  static Future<double?> readTranslationVolume(Directory workDir) async {
    final json = await _readJson(_file(workDir));
    final raw = json?[translationVolumeKey];
    if (raw is! num) return null;
    final v = raw.toDouble();
    if (v.isNaN || v < 0) return null;
    return v > 1 ? 1 : v;
  }

  /// 记录音量（读-合并-写；album.json 不存在则建最小 sidecar）。
  /// best-effort 语义由调用方保证。
  static Future<void> recordTranslationVolume(
    Directory workDir, {
    required double volume,
  }) async {
    final dest = _file(workDir);
    final json = await _readJson(dest) ?? <String, dynamic>{};
    json[translationVolumeKey] = volume.clamp(0.0, 1.0);
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    await _atomicWrite(dest, json);
  }

  /// best-effort 把 [work]（+[files]）写入 `<workDir>/album.json`，
  /// 并**保留**已有 `subtitleMatches`（读-合并-写，避免下次下载抹掉匹配记录）。
  static Future<void> write(
    Directory workDir, {
    required Work work,
    Files? files,
  }) async {
    File? tmp;
    try {
      if (!await workDir.exists()) {
        await workDir.create(recursive: true);
      }
      final dest = _file(workDir);
      final existing = await _readJson(dest);
      final next = payload(work: work, files: files);
      final matches = existing?[subtitleMatchesKey];
      if (matches is Map && matches.isNotEmpty) {
        next[subtitleMatchesKey] = matches;
      }
      final keys = existing?[fileKeysKey];
      if (keys is Map && keys.isNotEmpty) {
        next[fileKeysKey] = keys;
      }
      final vol = existing?[translationVolumeKey];
      if (vol is num) {
        next[translationVolumeKey] = vol;
      }
      tmp = File('${dest.path}.dl_tmp');
      await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(next),
        flush: true,
      );
      await tmp.rename(dest.path);
    } catch (e) {
      AppLogger.warning('写入 album.json 失败（不影响下载结果）: $e');
      try {
        if (tmp != null && await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }
}
