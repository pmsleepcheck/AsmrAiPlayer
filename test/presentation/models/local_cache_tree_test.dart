import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/download/models/download_entry.dart';
import 'package:aaplay/presentation/models/local_cache_tree.dart';

DownloadEntry _e(String path, {String? name, String workId = '1'}) {
  final segs = path
      .split(RegExp(r'[\\/]+'))
      .where((s) => s.isNotEmpty)
      .toList();
  return DownloadEntry(
    workId: workId,
    fileKey: 'key-$path',
    fileName: name ?? segs.last,
    filePath: path,
    mediaType: 'audio',
    sourceUrl: 'https://example.com/$path',
    size: 1,
    createdAt: 0,
  );
}

void main() {
  group('LocalCacheTree.build', () {
    test('空输入返回空列表', () {
      expect(LocalCacheTree.build(const []), isEmpty);
    });

    test('扁平布局（<标题>/<文件>）没有文件夹节点，顺序不变', () {
      final a = _e(r'C:\dl\作品\a.mp3');
      final b = _e(r'C:\dl\作品\b.mp3');
      final nodes = LocalCacheTree.build([a, b]);

      expect(nodes, hasLength(2));
      expect(nodes.every((n) => n.isFile), isTrue);
      expect(nodes.map((n) => n.name), ['a.mp3', 'b.mp3']);
      expect(nodes[0].entry, same(a));
      expect(nodes[1].entry, same(b));
    });

    test('多级目录保留真实层级：文件夹在前、文件在后、fileCount 正确', () {
      final mp3 = _e(r'C:\dl\W\01_通常\MP3\01.mp3');
      final wav = _e(r'C:\dl\W\01_通常\WAV\01.wav');
      final lrc = _e(r'C:\dl\W\LRC or Script\CN\01.lrc');
      final nodes = LocalCacheTree.build([mp3, wav, lrc]);

      expect(nodes.map((n) => n.name), ['01_通常', 'LRC or Script']);
      expect(nodes.every((n) => !n.isFile), isTrue);
      expect(nodes[0].path, r'C:\dl\W\01_通常');
      expect(nodes[0].fileCount, 2);
      expect(nodes[1].fileCount, 1);

      final normal = nodes[0];
      expect(normal.children.map((n) => n.name), ['MP3', 'WAV']);
      expect(normal.children[0].children.single.name, '01.mp3');
      expect(normal.children[0].children.single.entry, same(mp3));
      expect(normal.children[1].children.single.entry, same(wav));
    });

    test('旧布局 <workId>/<md5>/<文件> 保留 md5 层', () {
      final f1 = _e(
        r'C:\dl\1649862\00d45357ba236997c8f7285215d4d828\Track05.mp3',
      );
      final f2 = _e(
        r'C:\dl\1649862\047bf2682a4869bf193a9609c343186f\Track07.mp3',
      );
      final nodes = LocalCacheTree.build([f1, f2]);

      expect(nodes.map((n) => n.name), [
        '00d45357ba236997c8f7285215d4d828',
        '047bf2682a4869bf193a9609c343186f',
      ]);
      expect(nodes[0].path,
          r'C:\dl\1649862\00d45357ba236997c8f7285215d4d828');
      expect(nodes[0].fileCount, 1);
      expect(nodes[0].children.single.entry, same(f1));
      expect(nodes[1].children.single.entry, same(f2));
    });

    test('同一作品扁平文件与 md5 子目录混合：文件夹在前、根下文件在后', () {
      final flat = _e(r'C:\dl\1653004\01_x.mp3');
      final nested = _e(r'C:\dl\1653004\408a42d2\01_y.mp3');
      final nodes = LocalCacheTree.build([flat, nested]);

      expect(nodes, hasLength(2));
      expect(nodes[0].isFile, isFalse);
      expect(nodes[0].name, '408a42d2');
      expect(nodes[1].isFile, isTrue);
      expect(nodes[1].name, '01_x.mp3');
      expect(nodes[1].entry, same(flat));
      expect(nodes[0].fileCount, 1);
    });

    test('同名目录大小写不一致按同一目录处理（公共前缀大小写不敏感）', () {
      // `Sub` / `sub` 是同一个 Windows 目录：公共前缀直接吃掉它，
      // 两个文件落在同一个根下，不会裂成两个节点。
      final nodes = LocalCacheTree.build([
        _e(r'C:\dl\W\Sub\a.mp3'),
        _e(r'C:\dl\W\sub\b.mp3'),
      ]);

      expect(nodes.every((n) => n.isFile), isTrue);
      expect(nodes.map((n) => n.name), ['a.mp3', 'b.mp3']);
    });

    test('公共前缀含大小写差异也能剥净（不产生多余层级）', () {
      final nodes = LocalCacheTree.build([
        _e(r'C:\dl\W\MP3\a.mp3'),
        _e(r'C:\dl\w\mp3\b.mp3'),
      ]);

      expect(nodes.every((n) => n.isFile), isTrue);
      expect(nodes.map((n) => n.name), ['a.mp3', 'b.mp3']);
    });

    test('跨盘符（无公共前缀）不崩，盘符成为根节点', () {
      final nodes = LocalCacheTree.build([
        _e(r'C:\a\x.mp3'),
        _e(r'D:\b\y.mp3'),
      ]);

      expect(nodes.map((n) => n.name), ['C:', 'D:']);
      expect(nodes[0].fileCount, 1);
      expect(nodes[1].fileCount, 1);
      expect(nodes[0].children.single.name, 'a');
      expect(nodes[0].children.single.children.single.name, 'x.mp3');
    });

    test('正斜杠路径同样可用（分隔符混合）', () {
      final nodes = LocalCacheTree.build([
        _e('/data/downloads/W/CD1/a.mp3'),
        _e('/data/downloads/W/CD2/b.mp3'),
      ]);

      expect(nodes.map((n) => n.name), ['CD1', 'CD2']);
      expect(nodes[0].path, '/data/downloads/W/CD1');
      expect(nodes[1].fileCount, 1);
    });

    test('文件夹节点的 children 非空、文件节点 children 恒为空', () {
      final folder = LocalCacheTree.build([
        _e(r'C:\dl\W\CD1\a.mp3'),
        _e(r'C:\dl\W\CD2\b.mp3'),
      ]).first;
      final file = LocalCacheTree.build([
        _e(r'C:\dl\W\a.mp3'),
        _e(r'C:\dl\W\b.mp3'),
      ]).first;

      expect(folder.isFile, isFalse);
      expect(folder.children, hasLength(1));
      expect(file.isFile, isTrue);
      expect(file.children, isEmpty);
    });
  });
}
