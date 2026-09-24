import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/settings/app_settings_service.dart';

/// 管理附加缓存/扫描目录（Windows / Android 同一路径约定）。
///
/// 手动输入 + 目录选择器浏览（`FilePicker.getDirectoryPath`，失败回退提示
/// 手动输入）。空列表 = 仅默认下载根（旧行为）。
class DownloadDirsDialog extends StatefulWidget {
  final AppSettingsService settings;

  const DownloadDirsDialog({super.key, required this.settings});

  @override
  State<DownloadDirsDialog> createState() => _DownloadDirsDialogState();
}

class _DownloadDirsDialogState extends State<DownloadDirsDialog> {
  late final TextEditingController _controller;
  late final List<String> _dirs;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _dirs = List.from(widget.settings.downloadExtraDirs);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 归一化：trim + 去尾部分隔符（与 `DownloadService.downloadsRootPaths`
  /// 同一规则，保证重复判断一致）。
  String _normalize(String raw) {
    var path = raw.trim();
    while (path.length > 1 && (path.endsWith('/') || path.endsWith(r'\'))) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  void _add(String raw) {
    final path = _normalize(raw);
    if (path.isEmpty) {
      setState(() => _error = Strings.downloadDirsInvalid);
      return;
    }
    // 绝对路径启发式：Unix 根 / Windows 盘符。
    final isAbsolute =
        path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
    if (!isAbsolute) {
      setState(() => _error = Strings.downloadDirsInvalid);
      return;
    }
    final lower = path.toLowerCase();
    for (final d in _dirs) {
      if (_normalize(d).toLowerCase() == lower) {
        setState(() => _error = Strings.downloadDirsDuplicate);
        return;
      }
    }
    setState(() {
      _dirs.add(path);
      _controller.clear();
      _error = null;
    });
  }

  Future<void> _browse() async {
    try {
      final picked = await FilePicker.platform.getDirectoryPath(
        dialogTitle: Strings.downloadDirsBrowse,
      );
      if (picked == null) return;
      _add(picked);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = Strings.downloadDirsBrowseFailed);
    }
  }

  void _remove(int index) {
    setState(() {
      _dirs.removeAt(index);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text(Strings.downloadDirsTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Strings.downloadDirsDesc,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (_dirs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  Strings.downloadDirsEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _dirs.length,
                  itemBuilder: (context, index) {
                    final dir = _dirs[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.folder_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        dir,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: Strings.downloadDirsRemove,
                        icon: const Icon(Icons.close, size: 18),
                        color: theme.colorScheme.onSurfaceVariant,
                        onPressed: () => _remove(index),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: Strings.downloadDirsHint,
                errorText: _error,
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: Strings.downloadDirsBrowse,
                  icon: const Icon(Icons.folder_open_outlined),
                  color: theme.colorScheme.onSurfaceVariant,
                  onPressed: _browse,
                ),
              ),
              onSubmitted: _add,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(Strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            widget.settings.setDownloadExtraDirs(_dirs);
            Navigator.pop(context);
          },
          child: const Text(Strings.save),
        ),
      ],
    );
  }
}
