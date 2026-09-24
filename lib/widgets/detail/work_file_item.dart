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

  /// 「翻译+播放」回调（仅音频）；null 不显示图标。
  final Function(Child file)? onFileTranslatePlay;

  /// 长按音频 → 从专辑内手工选择字幕；null 不响应长按。
  final Function(Child file)? onFilePickSubtitle;

  const WorkFileItem({
    super.key,
    required this.file,
    required this.indentation,
    this.onFileTap,
    this.onFileDownload,
    this.downloadedFileKeys,
    this.onFilePlay,
    this.onFileTranslatePlay,
    this.onFilePickSubtitle,
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

  Widget? _buildTrailing(
    bool isAudio,
    bool isVideo,
    bool downloaded,
    ColorScheme colorScheme,
  ) {
    final children = <Widget>[];

    if (isAudio && onFileTranslatePlay != null) {
      children.add(IconButton(
        icon: const Icon(Icons.record_voice_over_outlined, size: 20),
        tooltip: Strings.translatePlayTooltip,
        onPressed: () async {
          try {
            await onFileTranslatePlay!.call(file);
          } catch (e) {
            AppLogger.error('翻译播放按钮回调失败: ${file.title}', e);
          }
        },
      ));
    }

    if (downloaded) {
      if (onFilePlay != null && (isAudio || isVideo)) {
        children.add(IconButton(
          icon: const Icon(Icons.play_arrow, size: 22),
          tooltip: Strings.downloadJobPlay,
          onPressed: () async {
            try {
              await onFilePlay!.call(file);
            } catch (e) {
              AppLogger.error('播放按钮回调失败: ${file.title}', e);
            }
          },
        ));
      }
      children.add(const Tooltip(
        message: Strings.downloadedBadgeTooltip,
        child: Icon(Icons.download_done, size: 20, color: Colors.green),
      ));
    } else if (isAudio && onFileDownload != null) {
      children.add(IconButton(
        icon: const Icon(Icons.download_outlined, size: 20),
        tooltip: Strings.downloadToLocalTooltip,
        onPressed: () => onFileDownload!.call(file),
      ));
    } else if (isVideo) {
      children.add(const Icon(Icons.download_outlined, size: 20));
    }

    if (children.isEmpty) return null;
    return Row(mainAxisSize: MainAxisSize.min, children: children);
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
        trailing: _buildTrailing(isAudio, isVideo, downloaded, colorScheme),
        dense: true,
        onLongPress: (isAudio && onFilePickSubtitle != null)
            ? () async {
                try {
                  await onFilePickSubtitle!.call(file);
                } catch (e) {
                  AppLogger.error('选择字幕回调失败: ${file.title}', e);
                }
              }
            : null,
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
