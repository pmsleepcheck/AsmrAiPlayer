import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/translation/ear_mark_repository.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EarMarkRepository', () {
    test('标记读写与覆盖', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = EarMarkRepository(prefs);

      expect(repo.get('k1'), isNull);
      await repo.mark('k1', EarSide.left);
      expect(repo.get('k1'), EarSide.left);

      await repo.mark('k1', EarSide.right);
      expect(repo.get('k1'), EarSide.right);

      await repo.clear('k1');
      expect(repo.get('k1'), isNull);
    });

    test('进程内实例共享同一 prefs 时第二个实例也能读到', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final a = EarMarkRepository(prefs);
      await a.mark('fileKeyA', EarSide.right);

      final b = EarMarkRepository(prefs);
      // b 的冷缓存从 prefs 字符串列表加载
      expect(b.get('fileKeyA'), EarSide.right);
    });
  });
}
