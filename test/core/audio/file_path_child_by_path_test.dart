import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/models/file_path.dart';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/data/models/files/files.dart';

void main() {
  Child folder(String title, List<Child> children) =>
      Child(type: 'folder', title: title, children: children);
  Child file(String title) => Child(type: 'audio', title: title);

  test('getPath → childByPath 往返', () {
    final target = file('01.mp3');
    final root = Files(type: 'tree', title: 'tree', children: [
      folder('ch', [target, file('02.mp3')]),
    ]);
    final path = FilePath.getPath(target, root);
    expect(path, '/ch/01.mp3');
    expect(identical(FilePath.childByPath(root, path!), target), isTrue);
  });

  test('childByPath：不存在 / 中途非目录 → null', () {
    final root = Files(type: 'tree', title: 'tree', children: [
      folder('ch', [file('01.mp3')]),
    ]);
    expect(FilePath.childByPath(root, '/nope/01.mp3'), isNull);
    expect(FilePath.childByPath(root, '/ch/01.mp3/deep.vtt'), isNull);
    expect(FilePath.childByPath(root, '/'), isNull);
  });
}
