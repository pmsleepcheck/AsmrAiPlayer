import 'package:aaplay/core/download/models/download_entry.dart';

/// 本地缓存树节点：文件夹或文件（[entry] 非 null = 文件）。
///
/// [path] 兼作节点 key：同一棵树内唯一（文件夹展开/收起状态按它记忆），
/// 文件为 [DownloadEntry.filePath]，文件夹为目录绝对路径。
class LocalCacheNode {
  /// 展示名：文件夹 = 目录名；文件 = [DownloadEntry.fileName]。
  final String name;

  /// 文件夹的目录路径 / 文件的绝对路径。
  final String path;

  /// 文件条目；null = 文件夹。
  final DownloadEntry? entry;

  /// 子节点（仅文件夹）；文件恒为空列表。
  final List<LocalCacheNode> children;

  const LocalCacheNode.folder({
    required this.name,
    required this.path,
    this.children = const [],
  }) : entry = null;

  const LocalCacheNode.file({
    required this.name,
    required this.path,
    required this.entry,
  }) : children = const [];

  bool get isFile => entry != null;

  /// 子树内文件总数（文件夹节点显示「N 项」用）。
  int get fileCount =>
      isFile ? 1 : children.fold(0, (sum, node) => sum + node.fileCount);
}

/// 由 `DownloadEntry.filePath` 还原**磁盘真实文件夹树**的纯逻辑构建器。
///
/// 组（同一作品）内所有条目先取父目录的**公共前缀**作为树根：
/// - 扁平布局 `downloads/<标题>/<文件>` → 前缀即作品目录 → 根下直接是文件
///   （与「显示全部文件」一致，因为磁盘上确实没有子目录）；
/// - 多级目录 `…/<作品>/01_通常/MP3/x.mp3` → 保留 `01_通常/MP3` 真实层级；
/// - 旧布局 `…/<workId>/<md5>/x.mp3` → 保留 md5 层。
///
/// 子节点顺序：**文件夹在前、文件在后**，各自保持输入顺序
/// （不按字典序重排 → 音轨 01/02 的自然顺序不被 010/02 打乱）。
class LocalCacheTree {
  const LocalCacheTree._();

  /// 空输入返回空列表；不读磁盘、不做 IO。
  static List<LocalCacheNode> build(List<DownloadEntry> entries) {
    if (entries.isEmpty) return const [];

    final sep = entries.first.filePath.contains(r'\') ? r'\' : '/';
    // 绝对路径的根分隔符（Unix `/`、UNC `\`）要保留：公共前缀剥完后它仍在。
    final prefix = _leadingSeparator(entries.first.filePath);
    final parents = <List<String>>[
      for (final e in entries) _parentSegments(e.filePath),
    ];

    // 所有条目父目录的最长公共前缀（分隔符混合 / 大小写不敏感）。
    final ref = parents.first;
    var common = ref.length;
    for (final p in parents) {
      final limit = p.length < common ? p.length : common;
      var i = 0;
      while (i < limit && _same(ref[i], p[i])) {
        i++;
      }
      common = i;
      if (common == 0) break;
    }

    final root = _Dir('');
    final base = prefix + ref.sublist(0, common).join(sep);
    for (var i = 0; i < entries.length; i++) {
      var cur = root;
      for (final seg in parents[i].sublist(common)) {
        cur = cur.child(seg);
      }
      cur.files.add(entries[i]);
    }
    return _materialize(root, basePath: base, sep: sep);
  }

  /// 路径开头的根分隔符（`/`、`\`、UNC `\\`）；盘符路径（`C:\`）返回空串。
  static String _leadingSeparator(String path) {
    if (path.startsWith(r'\\')) return r'\\';
    if (path.startsWith(r'\')) return r'\';
    if (path.startsWith('/')) return '/';
    return '';
  }

  /// 拼一层子路径：空基址直接返回名字（跨盘符时的相对根），带尾分隔符不再补。
  static String _childPath(String base, String name, String sep) {
    if (base.isEmpty) return name;
    return base.endsWith(sep) ? '$base$name' : '$base$sep$name';
  }

  /// 路径 → 父目录段（去掉文件名）；无父目录（空/相对单段路径）返回空。
  static List<String> _parentSegments(String path) {
    final segs = _segments(path);
    return segs.length <= 1 ? const <String>[] : segs.sublist(0, segs.length - 1);
  }

  /// `/` 与 `\` 混用都拆（DB 里的绝对路径可能来自不同来源）。
  static List<String> _segments(String path) => path
      .split(RegExp(r'[\\/]+'))
      .where((s) => s.isNotEmpty)
      .toList();

  static bool _same(String a, String b) => a.toLowerCase() == b.toLowerCase();

  static List<LocalCacheNode> _materialize(
    _Dir dir, {
    required String basePath,
    required String sep,
  }) {
    final nodes = <LocalCacheNode>[];
    for (final sub in dir.dirs.values) {
      final path = _childPath(basePath, sub.name, sep);
      nodes.add(LocalCacheNode.folder(
        name: sub.name,
        path: path,
        children: _materialize(sub, basePath: path, sep: sep),
      ));
    }
    for (final e in dir.files) {
      nodes.add(LocalCacheNode.file(
        name: e.fileName,
        path: e.filePath,
        entry: e,
      ));
    }
    return nodes;
  }
}

/// 构建期临时目录节点；[dirs] key 为小写名（Windows 大小写不敏感合并），
/// value 保留**首次出现**的大小写用于展示。
class _Dir {
  _Dir(this.name);

  final String name;
  final Map<String, _Dir> dirs = <String, _Dir>{};
  final List<DownloadEntry> files = <DownloadEntry>[];

  _Dir child(String segment) =>
      dirs.putIfAbsent(segment.toLowerCase(), () => _Dir(segment));
}
