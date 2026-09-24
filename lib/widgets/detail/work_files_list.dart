import 'package:flutter/material.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/widgets/detail/work_folder_item.dart';
import 'package:aaplay/widgets/detail/work_file_item.dart';

class WorkFilesList extends StatelessWidget {
  final Files files;
  final Function(Child file)? onFileTap;
  final Function(Child file)? onFileDownload;

  /// 下载整部作品 / 某文件夹子树全部音频（含匹配字幕）。
  /// 参数为 null 代表整部作品，否则为该文件夹节点。
  final void Function(Child? folderNode)? onFolderDownload;

  /// 已下载 fileKey 集合（详情页角标）；null = 不显示。
  final Set<String>? downloadedFileKeys;

  /// 已下载文件播放（角标旁播放按钮）；null = 不显示按钮。
  final Function(Child file)? onFilePlay;

  const WorkFilesList({
    super.key,
    required this.files,
    this.onFileTap,
    this.onFileDownload,
    this.onFolderDownload,
    this.downloadedFileKeys,
    this.onFilePlay,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    Strings.fileList,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (onFolderDownload != null)
                  TextButton.icon(
                    onPressed: () => onFolderDownload!.call(null),
                    icon: const Icon(Icons.download_for_offline_outlined,
                        size: 18),
                    label: const Text(Strings.downloadAllTooltip),
                  ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          ...files.children
                  ?.map((child) => child.type == 'folder'
                      ? WorkFolderItem(
                          folder: child,
                          indentation: 0,
                          onFileTap: onFileTap,
                          onFileDownload: onFileDownload,
                          onFolderDownload: onFolderDownload,
                          downloadedFileKeys: downloadedFileKeys,
                          onFilePlay: onFilePlay,
                        )
                      : WorkFileItem(
                          file: child,
                          indentation: 0,
                          onFileTap: onFileTap,
                          onFileDownload: onFileDownload,
                          downloadedFileKeys: downloadedFileKeys,
                          onFilePlay: onFilePlay,
                        ))
                  .toList() ??
              [],
        ],
      ),
    );
  }
}
