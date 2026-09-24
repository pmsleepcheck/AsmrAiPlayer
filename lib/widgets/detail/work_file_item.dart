import 'package:flutter/material.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/utils/logger.dart';
import 'package:aaplay/utils/file_size_formatter.dart';

class WorkFileItem extends StatelessWidget {
  final Child file;
  final double indentation;
  final Function(Child file)? onFileTap;
  final Function(Child file)? onFileDownload;

  /// 已下载 fileKey 集合（来自 DetailViewModel 批量查询）；null = 未接入。
  final Set<String>? downloadedFileKeys;

  /// 已下载文件的「播放」回调（音频进播放管线 / 视频开本地文件）。
  /// null 时不显示播放按钮（仍显示已下载角标）。
  final Function(Child file)? onFilePlay;

  const WorkFileItem({
    super.key,
    required this.file,
    required this.indentation,
    this.onFileTap,
    this.onFileDownload,
    this.downloadedFileKeys,
    this.onFilePlay,
  });

  static const _videoExtensions = {'mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v'};

  static const _subtitleExtensions = {'vtt', 'lrc', 'srt', 'txt'};

  /// 与 `PlaybackContext.playlistAudioExtensions` 对齐：type 缺失时按扩展名兜底。
  static const _audioExtensions = {
    'mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg', 'opus', 'wma', 'mp4a',
  };

  bool get _isVideo {
    if ((file.type ?? '').toLowerCase() == 'video') return true;
    final ext = file.title?.split('.').last.toLowerCase();
    return ext != null && _videoExtensions.contains(ext);
  }

  bool get _isAudio {
    if (_isVideo) return false;
    final t = (file.type ?? '').toLowerCase();
    if (t == 'audio') return true;
    if (t.isNotEmpty) return false;
    final ext = file.title?.split('.').last.toLowerCase();
    return ext != null && _audioExtensions.contains(ext);
  }

  bool get _isSubtitle {
    final ext = file.title?.split('.').last.toLowerCase();
    return ext != null && _subtitleExtensions.contains(ext);
  }

  bool get _isDownloaded {
    final keys = downloadedFileKeys;
    if (keys == null || file.title == null) return false;
    // 兼容新/旧 fileKey（历史预签名 URL 行）。
    for (final key in DownloadService.candidateKeys(file)) {
      if (keys.contains(key)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // 视频扩展名优先于 API `type`：asmr.one 会把视频错标 type=audio，
    // 若当音频会进播放管线导致"播放列表为空"。这类文件按视频处理
    // （走下载到本地用外部播放器的流程）。
    final bool isVideo = _isVideo;
    final bool isAudio = _isAudio && !isVideo;
    final bool isSubtitle = !isAudio && !isVideo && _isSubtitle;
    final bool tappable = isAudio || isVideo || isSubtitle;
    final bool downloaded = _isDownloaded;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(left: indentation),
      child: ListTile(
        title: Text(
          file.title ?? '',
          style: TextStyle(
            color: colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          FileSizeFormatter.format(file.size),
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        leading: Icon(
          isAudio
              ? Icons.audio_file
              : isVideo
                  ? Icons.movie_outlined
                  : isSubtitle
                      ? Icons.subtitles_outlined
                      : Icons.insert_drive_file,
          color: isAudio
              ? Colors.green
              : isVideo
                  ? Colors.deepPurple
                  : isSubtitle
                      ? Colors.orange
                      : Colors.blue,
        ),
        trailing: downloaded
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onFilePlay != null && (isAudio || isVideo))
                    IconButton(
                      icon: const Icon(Icons.play_arrow, size: 22),
                      tooltip: Strings.downloadJobPlay,
                      onPressed: () async {
                        try {
                          await onFilePlay!.call(file);
                        } catch (e) {
                          AppLogger.error('播放按钮回调失败: ${file.title}', e);
                        }
                      },
                    ),
                  const Tooltip(
                    message: Strings.downloadedBadgeTooltip,
                    child: Icon(Icons.download_done, size: 20, color: Colors.green),
                  ),
                ],
              )
            : isAudio && onFileDownload != null
                ? IconButton(
                    icon: const Icon(Icons.download_outlined, size: 20),
                    tooltip: Strings.downloadToLocalTooltip,
                    onPressed: () => onFileDownload!.call(file),
                  )
                : isVideo
                    ? const Icon(Icons.download_outlined, size: 20)
                    : null,
        dense: true,
        onTap: tappable
            ? () async {
                AppLogger.debug('点击文件: ${file.title} (${file.type})');
                try {
                  await onFileTap?.call(file);
                } catch (e) {
                  AppLogger.error('文件点击回调失败: ${file.title}', e);
                }
              }
            : null,
      ),
    );
  }
}
