import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:aaplay/common/constants/strings.dart';
import 'package:aaplay/core/audio/i_audio_player_service.dart';
import 'package:aaplay/core/audio/models/playback_context.dart';
import 'package:aaplay/core/audio/translation/translation_play_flow.dart';
import 'package:aaplay/core/download/download_service.dart';
import 'package:aaplay/core/download/models/download_entry.dart';
import 'package:aaplay/core/download/storage/i_work_snapshot_repository.dart';
import 'package:aaplay/core/theme/app_spacing.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';
import 'package:aaplay/data/models/works/work.dart';
import 'package:aaplay/presentation/viewmodels/local_cache_viewmodel.dart';
import 'package:aaplay/utils/file_size_formatter.dart';
import 'package:aaplay/utils/logger.dart';
import 'package:aaplay/widgets/download/download_queue_panel.dart';

/// 「本地缓存」tab 正文（合并页）：上 = 可折叠下载队列（DownloadQueuePanel），
/// 下 = 本地文件浏览器（路径头 + 过滤 chips + 分组列表）。
class LocalCacheContent extends StatefulWidget {
  const LocalCacheContent({super.key});

  @override
  State<LocalCacheContent> createState() => _LocalCacheContentState();
}

class _LocalCacheContentState extends State<LocalCacheContent>
    with AutomaticKeepAliveClientMixin {
  String? _rootPath;
  int _extraRootCount = 0;
  bool _scanning = false;

  /// 已展开的作品（文件夹）分组 workId；**空集 = 默认全部折叠**。
  /// 放 State 而非 ViewModel：与数据 load 解耦，KeepAlive 跨 tab 保留。
  final Set<String> _expandedWorkIds = <String>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 进页首扫（scan 失败不阻断 DB 列表）。
      context.read<LocalCacheViewModel>().load(scan: true);
      _loadRoot();
    });
  }

  Future<void> _loadRoot() async {
    try {
      final paths = await GetIt.I<DownloadService>().downloadsRootPaths();
      if (mounted) {
        setState(() {
          _rootPath = paths.isEmpty ? null : paths.first;
          _extraRootCount = paths.length > 1 ? paths.length - 1 : 0;
        });
      }
    } catch (e) {
      AppLogger.warning('解析下载根路径失败: $e');
    }
  }

  /// 扫盘 + 刷新；弹「新增 N 项」/「扫描失败」。
  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final added =
          await context.read<LocalCacheViewModel>().scanAndLoad();
      if (!mounted) return;
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(
        content: Text(added == null
            ? Strings.localCacheScanFailed
            : Strings.localCacheScanResult(added)),
      ));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _openRoot() async {
    final path = _rootPath;
    if (path == null) return;
    try {
      final dir = Directory(path);
      if (!await dir.exists()) await dir.create(recursive: true);
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(Strings.openFolderFailed)),
        );
      }
    } catch (e) {
      AppLogger.error('打开下载文件夹失败', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(Strings.openFolderFailed)),
        );
      }
    }
  }

  /// 点播放：视频（无内置播放器）→ 系统打开；**音频永不走外部**——
  /// 缺快照/找不到叶子/空播放列表一律合成单曲 PlaybackContext 应用内播。
  Future<void> _play(DownloadEntry e) async {
    // 点击即反馈：初始化/加载源若慢，用户至少知道点中了。
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text(Strings.playStarting),
          duration: Duration(seconds: 1),
        ));
    }
    try {
      if (LocalCacheViewModel.isVideoEntry(e)) {
        await _openExternal(e.filePath);
        return;
      }
      await TranslationPlayFlow.prepareNormalPlay();
      final ctx = await _buildAudioContext(e);
      await GetIt.I<IAudioPlayerService>().playWithContext(ctx);
    } catch (err) {
      AppLogger.error('本地缓存播放失败: ${e.fileName}', err);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.playFailed(err))),
        );
      }
    }
  }

  /// 翻译+播放：Key → 耳侧（本地路径可波形）→ 开会话 → 同 [_play] 音频路径。
  Future<void> _translatePlay(DownloadEntry e) async {
    if (LocalCacheViewModel.isVideoEntry(e)) return;
    if (!mounted) return;
    final synthetic = _syntheticChild(e);
    final ok = await TranslationPlayFlow.prepareSession(
      context: context,
      file: synthetic,
      keys: [e.fileKey],
      resolveLocalPath: (_) async => e.filePath,
    );
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text(Strings.translationPlayStarting),
        duration: Duration(seconds: 1),
      ));
    try {
      final ctx = await _buildAudioContext(e);
      await GetIt.I<IAudioPlayerService>().playWithContext(ctx);
    } catch (err) {
      AppLogger.error('本地缓存翻译播放失败: ${e.fileName}', err);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Strings.playFailed(err))),
        );
      }
    }
  }

  Child _syntheticChild(DownloadEntry e) => Child(
        type: e.mediaType.isNotEmpty ? e.mediaType : 'audio',
        title: e.fileName,
        mediaDownloadUrl: Uri.file(e.filePath).toString(),
        size: e.size,
      );

  /// 优先完整快照树（同目录多曲 playlist）；否则/再失败 → 单曲合成 context。
  Future<PlaybackContext> _buildAudioContext(DownloadEntry e) async {
    Work? work;
    Files? files;
    try {
      final snap = await GetIt.I<IWorkSnapshotRepository>().load(e.workId);
      work = snap?.work;
      files = snap?.files;
    } catch (err) {
      AppLogger.warning('读取播放快照失败 ${e.workId}: $err');
    }

    if (work != null && files != null) {
      final child = _findLeaf(files, e);
      if (child != null) {
        final full = PlaybackContext(
          work: work,
          files: files,
          currentFile: child,
        );
        if (full.playlist.isNotEmpty) return full;
        // 扩展名不在白名单/FilePath 失败：仍应用内单曲，不回退外部。
        return PlaybackContext.withFilteredPlaylist(
          work: work,
          files: files,
          currentFile: child,
          playlist: [child],
        );
      }
    }
    return _syntheticSingleContext(e);
  }

  /// 无快照/叶子 miss：用 DownloadEntry 绝对路径合成单曲 context。
  /// `mediaDownloadUrl` 填 `file://`，PlaylistBuilder 按 scheme 短路建本地源
  /// （不依赖 md5(fileKey) 与合成 Child 对齐——hash 预像不可逆）。
  PlaybackContext _syntheticSingleContext(DownloadEntry e) {
    final child = Child(
      type: e.mediaType.isNotEmpty ? e.mediaType : 'audio',
      title: e.fileName,
      mediaDownloadUrl: Uri.file(e.filePath).toString(),
      size: e.size,
    );
    final files = Files(
      type: 'tree',
      title: e.fileName,
      children: [child],
    );
    final work = Work(
      id: int.tryParse(e.workId),
      title: e.fileName,
      sourceId: e.workId,
    );
    return PlaybackContext.withFilteredPlaylist(
      work: work,
      files: files,
      currentFile: child,
      playlist: [child],
    );
  }

  /// 打开外部文件（**仅视频**）；平台异常/非 done 一律 SnackBar，禁止静默失败。
  Future<void> _openExternal(String path) async {
    try {
      final r = await OpenFilex.open(path);
      if (r.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(Strings.downloadOpenFailed)),
        );
      }
    } catch (err) {
      AppLogger.error('打开本地文件失败: $path', err);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(Strings.downloadOpenFailed)),
        );
      }
    }
  }

  /// 在快照文件树里按 fileKey（新/旧）优先、唯一 fileName 兜底找叶子。
  Child? _findLeaf(Files files, DownloadEntry entry) {
    Child? byKey;
    Child? byTitle;
    var titleHits = 0;
    void walk(List<Child>? children) {
      if (children == null) return;
      for (final c in children) {
        if (c.type == 'folder') {
          walk(c.children);
          continue;
        }
        if (c.title == null) continue;
        if (DownloadService.candidateKeys(c).contains(entry.fileKey)) {
          byKey ??= c;
        }
        if (c.title == entry.fileName) {
          byTitle = c;
          titleHits++;
        }
      }
    }
    walk(files.children);
    return byKey ?? (titleHits == 1 ? byTitle : null);
  }

  Future<void> _confirmDelete(DownloadEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(Strings.localCacheDeleteConfirmTitle),
        content: Text(Strings.localCacheDeleteConfirm(e.fileName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(Strings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(Strings.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final success =
        await context.read<LocalCacheViewModel>().removeEntry(e);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? Strings.localCacheDeleted
          : Strings.localCacheDeleteFailed),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        // 下载队列（可折叠）：有 pending 默认展开，否则折叠。
        const DownloadQueuePanel(),
        Expanded(
          child: Consumer<LocalCacheViewModel>(
            builder: (context, vm, _) {
              return Column(
                children: [
                  Material(
                    color: cs.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.space16,
                        vertical: AppSpacing.space8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_rootPath != null)
                            InkWell(
                              onTap: _openRoot,
                              child: Row(
                                children: [
                                  Icon(Icons.folder_open_outlined,
                                      size: 18, color: cs.primary),
                                  const SizedBox(width: AppSpacing.space8),
                                  Expanded(
                                    child: Text(
                                      _extraRootCount > 0
                                          ? '$_rootPath · ${Strings.localCacheRootsSuffix(_extraRootCount)}'
                                          : _rootPath!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.space8),
                                  IconButton(
                                    tooltip: Strings.localCacheScanTooltip,
                                    visualDensity: VisualDensity.compact,
                                    onPressed: _scanning ? null : _scan,
                                    icon: _scanning
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Icon(Icons.sync_outlined,
                                            size: 20),
                                  ),
                                  TextButton.icon(
                                    onPressed: _openRoot,
                                    icon: const Icon(Icons.open_in_new,
                                        size: 16),
                                    label: const Text(Strings.openFolder),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: AppSpacing.space4),
                          Wrap(
                            spacing: AppSpacing.space8,
                            children: [
                              _FilterChip(
                                label: Strings.localCacheFilterAll,
                                selected:
                                    vm.filter == LocalCacheFilter.all,
                                onSelected: (_) =>
                                    vm.setFilter(LocalCacheFilter.all),
                              ),
                              _FilterChip(
                                label: Strings.localCacheFilterVideo,
                                selected:
                                    vm.filter == LocalCacheFilter.video,
                                onSelected: (_) =>
                                    vm.setFilter(LocalCacheFilter.video),
                              ),
                              _FilterChip(
                                label: Strings.localCacheFilterAudio,
                                selected:
                                    vm.filter == LocalCacheFilter.audio,
                                onSelected: (_) =>
                                    vm.setFilter(LocalCacheFilter.audio),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: _buildBody(context, vm, cs)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    LocalCacheViewModel vm,
    ColorScheme cs,
  ) {
    if (vm.isLoading && vm.groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.error != null && vm.groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(vm.error!,
                style: TextStyle(color: cs.error)),
            const SizedBox(height: AppSpacing.space12),
            TextButton(
              onPressed: () => vm.load(),
              child: const Text(Strings.retry),
            ),
          ],
        ),
      );
    }
    if (vm.groups.isEmpty) {
      // 可下拉触发扫盘（空态也要能发现附加目录里的文件；扫盘按钮亦在路径头）。
      return RefreshIndicator(
        onRefresh: _scan,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Text(
                  Strings.localCacheEmpty,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _scan,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.space16),
        children: [
          for (final g in vm.groups) ...[
            _GroupHeader(
              title: g.title,
              sourceId: g.work?.sourceId,
              count: g.entries.length,
              expanded: _expandedWorkIds.contains(g.workId),
              onTap: () => setState(() {
                if (!_expandedWorkIds.remove(g.workId)) {
                  _expandedWorkIds.add(g.workId);
                }
              }),
            ),
            if (_expandedWorkIds.contains(g.workId))
              for (final e in g.entries)
                ListTile(
                  dense: true,
                  leading: Icon(
                    LocalCacheViewModel.isVideoEntry(e)
                        ? Icons.movie_outlined
                        : Icons.audio_file,
                    color: LocalCacheViewModel.isVideoEntry(e)
                        ? Colors.deepPurple
                        : Colors.green,
                  ),
                  title: Text(e.fileName,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    FileSizeFormatter.format(e.size),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!LocalCacheViewModel.isVideoEntry(e))
                        IconButton(
                          tooltip: Strings.translatePlayTooltip,
                          icon: const Icon(Icons.record_voice_over_outlined,
                              size: 20),
                          onPressed: () => _translatePlay(e),
                        ),
                      IconButton(
                        tooltip: Strings.localCachePlayTooltip,
                        icon: const Icon(Icons.play_arrow, size: 22),
                        onPressed: () => _play(e),
                      ),
                      IconButton(
                        tooltip: Strings.localCacheDeleteTooltip,
                        icon: Icon(Icons.delete_outline,
                            size: 20, color: cs.error),
                        onPressed: () => _confirmDelete(e),
                      ),
                    ],
                  ),
                  onTap: () => _play(e),
                ),
            Divider(height: 1, color: cs.surfaceContainerHighest),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: cs.primaryContainer,
      labelStyle: TextStyle(
        color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// 作品（文件夹）分组头：可点折叠/展开 + 条数；默认收起见 [_expandedWorkIds]。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.sourceId,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final String title;
  final String? sourceId;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space16,
            AppSpacing.space16,
            AppSpacing.space8,
            AppSpacing.space4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (sourceId != null)
                      Text(
                        sourceId!,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.space8),
              Text(
                Strings.localCacheGroupCount(count),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
