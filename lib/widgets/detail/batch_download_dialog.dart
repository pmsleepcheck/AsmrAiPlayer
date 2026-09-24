import 'package:flutter/material.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/presentation/viewmodels/detail_viewmodel.dart';

/// 文件夹 / 整部作品「下载全部」**确认**对话框：
/// 阶段 1 = 确认（共 [audioCount] 个音频，含匹配字幕）；[audioCount]==0 时
/// 只显示「无可下载音频」并以 null pop。
/// 点「下载」后调用 [download]（入后台队列、立即返回），以
/// [BatchDownloadOutcome] pop（`ok` = 入队数）；确认阶段取消 → pop(null)。
/// 实时进度不在本弹窗展示 —— 见「下载管理」页。
class BatchDownloadDialog extends StatefulWidget {
  final int audioCount;
  final Future<BatchDownloadOutcome> Function() download;

  const BatchDownloadDialog({
    super.key,
    required this.audioCount,
    required this.download,
  });

  @override
  State<BatchDownloadDialog> createState() => _BatchDownloadDialogState();
}

class _BatchDownloadDialogState extends State<BatchDownloadDialog> {
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    BatchDownloadOutcome outcome;
    try {
      outcome = await widget.download();
    } catch (_) {
      outcome = BatchDownloadOutcome(
        ok: 0,
        skipped: 0,
        failed: widget.audioCount,
        cancelled: false,
      );
    }
    if (mounted) Navigator.of(context).pop(outcome);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.audioCount == 0) {
      return AlertDialog(
        title: const Text(Strings.batchDownloadTitle),
        content: const Text(Strings.batchDownloadEmpty),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(Strings.confirm),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text(Strings.batchDownloadTitle),
      content: Text(_starting
          ? Strings.downloadQueued
          : Strings.batchDownloadConfirm(widget.audioCount)),
      actions: [
        TextButton(
          onPressed: _starting
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text(Strings.downloadCancel),
        ),
        TextButton(
          onPressed: _starting ? null : _start,
          child: const Text(Strings.downloadConfirm),
        ),
      ],
    );
  }
}
