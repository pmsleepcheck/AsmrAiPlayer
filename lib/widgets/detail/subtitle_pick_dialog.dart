import 'package:flutter/material.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/models/file_path.dart';
import 'package:aaplay/core/subtitle/subtitle_loader.dart';
import 'package:aaplay/core/subtitle/utils/subtitle_matcher.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';

/// 从专辑文件树内选择字幕：同目录候选排最前，其余全树字幕随后。
/// 返回选中的字幕 [Child]；取消 → null。
Future<Child?> showSubtitlePickDialog(
  BuildContext context, {
  required Child audio,
  required Files files,
}) {
  return showDialog<Child>(
    context: context,
    builder: (dialogContext) {
      final sameDir = FilePath.getSiblings(audio, files);
      final local = <Child>[
        for (final c in sameDir)
          if (c.type != 'folder' &&
              SubtitleMatcher.isSubtitleFile(c.title) &&
              !identical(c, audio))
            c,
      ];
      final localPaths = local.map((c) => FilePath.getPath(c, files)).toSet();
      final rest = <Child>[
        for (final c in SubtitleLoader.collectSubtitleFiles(files.children))
          if (!localPaths.contains(FilePath.getPath(c, files))) c,
      ];
      final ordered = [...local, ...rest];

      return AlertDialog(
        title: const Text(Strings.pickSubtitleTitle),
        content: ordered.isEmpty
            ? const SizedBox(
                width: 320,
                child: Text(Strings.pickSubtitleEmpty),
              )
            : SizedBox(
                width: 360,
                height: 320,
                child: ListView.builder(
                  itemCount: ordered.length,
                  itemBuilder: (_, i) {
                    final sub = ordered[i];
                    final path = FilePath.getPath(sub, files) ?? sub.title ?? '';
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.subtitles_outlined, size: 20),
                      title: Text(sub.title ?? ''),
                      subtitle: Text(
                        path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(dialogContext).pop(sub),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(Strings.cancel),
          ),
        ],
      );
    },
  );
}
