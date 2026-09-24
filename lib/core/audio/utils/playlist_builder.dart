import 'package:get_it/get_it.dart';
import 'package:just_audio/just_audio.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/core/audio/cache/audio_cache_manager.dart';
import 'package:aaplay/utils/logger.dart';

class PlaylistBuilder {
  /// Build audio sources with per-item error handling.
  /// Returns a record of (sources, originalIndices) to maintain index mapping.
  ///
  /// 若提供 [workId]，先一次性批量解析该作品所有已下载文件（[resolveLocalPaths]，
  /// 默认走 `DownloadService.localPathsForWork`），把循环内逐轨一次 DB 查询
  /// 收敛为循环外一次；命中的文件直接用本地文件源（离线可放），否则回退到
  /// 原有的 `LockCachingAudioSource` 流式+缓存路径。
  ///
  /// [resolveLocalPaths] 是唯一为测试开的口子：注入一个计数 fake，断言
  /// 它在恢复一个 N 轨作品时只被调用一次（守住"N 次查询收敛为 1 次"）。
  static Future<(List<AudioSource>, List<int>)> buildAudioSources(
    List<Child> files, {
    String? workId,
    Future<Map<String, String>> Function(String workId)? resolveLocalPaths,
  }) async {
    final sources = <AudioSource>[];
    final originalIndices = <int>[];

    var localPaths = const <String, String>{};
    if (workId != null) {
      // 用 GetIt.I 直取（与 audio_player_service 中 GetIt.I<ISubtitleService>()
      // 同一模式），避免 import service_locator 造成 core/audio↔core/di 文件环。
      final resolve = resolveLocalPaths ??
          (String id) => GetIt.I<DownloadService>().localPathsForWork(id);
      try {
        localPaths = await resolve(workId);
      } catch (e) {
        // 批量解析失败（如 DB 打开异常）不该让整份播放列表全军覆没——
        // 退化为"当作没有本地下载"，逐轨仍可走网络流式播放。
        AppLogger.error('批量解析本地下载路径失败,回退为全部走网络播放', e);
      }
    }

    for (var i = 0; i < files.length; i++) {
      try {
        AudioSource? source;
        // 本地缓存合成 context 用 `file://` 绝对路径（DownloadEntry.filePath）：
        // 合成 Child 没有原 hash，candidateKeys 对不上 DB fileKey，必须先按
        // scheme 短路，否则会掉进网络 createAudioSource → 外部/挂起。
        final rawUrl = files[i].mediaDownloadUrl;
        if (rawUrl != null && rawUrl.isNotEmpty) {
          final parsed = Uri.tryParse(rawUrl);
          if (parsed != null && parsed.isScheme('file')) {
            source = AudioSource.uri(parsed);
          }
        }
        // title == null 的文件不可能已下载（download() 本身要求非空文件名
        // 才会落盘），跳过查表——避免命中 fileKey 在 hash/url/title 均缺时
        // 退化成的固定 key（md5('file')），与另一个同样退化的文件误撞。
        if (source == null && files[i].title != null) {
          // 命中查表要走 candidateKeys（新/旧 fileKey 都试）：历史预签名
          // URL 行的 DB key 可能是 legacyFileKey，只查 fileKey 会 miss，
          // 已下载文件被错误地回退到过期网络 URL → 挂起无反馈。
          String? localPath;
          for (final key in DownloadService.candidateKeys(files[i])) {
            localPath = localPaths[key];
            if (localPath != null) break;
          }
          if (localPath != null) {
            source = AudioSource.uri(Uri.file(localPath));
          }
        }
        source ??= await AudioCacheManager.createAudioSource(
          files[i].mediaDownloadUrl!,
          hash: files[i].hash,
        );
        sources.add(source);
        originalIndices.add(i);
      } catch (e) {
        AppLogger.error('创建音频源失败,跳过: ${files[i].title}', e);
      }
    }
    return (sources, originalIndices);
  }

  /// 把"原始文件列表里的目标下标"重映射到"过滤掉创建失败轨后的播放队列
  /// 下标"。目标轨本身精确存活 → 原样命中；目标轨被丢弃 → 退化取原列表里
  /// 排在它之后、第一个仍存活的轨；若其后再无存活轨（含全部轨都被丢弃的
  /// 极端情况）→ 退化到 0。纯函数，不含日志副作用，便于单测覆盖四种场景。
  static int remapIndex(List<int> originalIndices, int initialIndex) {
    final exact = originalIndices.indexOf(initialIndex);
    if (exact >= 0) return exact;
    for (var i = 0; i < originalIndices.length; i++) {
      if (originalIndices[i] >= initialIndex) return i;
    }
    return 0;
  }

  static Future<void> updatePlaylist(
    ConcatenatingAudioSource playlist,
    List<AudioSource> sources,
  ) async {
    await playlist.clear();
    await playlist.addAll(sources);
  }

  /// Returns the list of files that were successfully loaded (matching the player queue order).
  static Future<List<Child>> setPlaylistSource({
    required AudioPlayer player,
    required ConcatenatingAudioSource playlist,
    required List<Child> files,
    required int initialIndex,
    required Duration initialPosition,
    String? workId,
  }) async {
    final (sources, originalIndices) =
        await buildAudioSources(files, workId: workId);

    // Guard: empty playlist
    if (sources.isEmpty) {
      AppLogger.error('所有音频源创建失败,无法播放');
      throw Exception('无可用的音频源');
    }

    await updatePlaylist(playlist, sources);

    // Build filtered files list matching actual player queue
    final loadedFiles = originalIndices.map((i) => files[i]).toList();

    final remappedIndex = remapIndex(originalIndices, initialIndex);
    if (remappedIndex >= originalIndices.length ||
        originalIndices[remappedIndex] != initialIndex) {
      AppLogger.warning('原始索引 $initialIndex 不可用,使用替代索引 $remappedIndex');
    }

    // setAudioSource 会等平台侧加载完成：网络源/与并发 restore 交错时
    // 可永久挂起。本地 file:// 应瞬时完成；超时统一交给上层阶段化错误。
    await player
        .setAudioSource(
          playlist,
          initialIndex: remappedIndex,
          initialPosition: initialPosition,
        )
        .timeout(const Duration(seconds: 5));

    return loadedFiles;
  }
}
