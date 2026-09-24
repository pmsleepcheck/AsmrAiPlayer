import 'package:flutter_test/flutter_test.dart';
import 'package:aaplay/core/audio/translation/ear_channel_router.dart';
import 'package:aaplay/core/audio/translation/ear_side.dart';

void main() {
  group('EarChannelRouter.filterFor', () {
    test('left：lavfi pan 只留左声道（右静音）', () {
      final f = EarChannelRouter.filterFor(EarSide.left);
      expect(f, startsWith('lavfi=[aformat=channel_layouts=stereo,pan='));
      expect(f, contains('c0=0.5*c0+0.5*c1'));
      expect(f, contains('c1=0'));
      expect(f, isNot(contains('c0=0|')));
      expect(f, endsWith(']'));
    });

    test('right：lavfi pan 只留右声道（左静音）', () {
      final f = EarChannelRouter.filterFor(EarSide.right);
      expect(f, startsWith('lavfi=[aformat=channel_layouts=stereo,pan='));
      expect(f, contains('c0=0|c1=0.5*c0+0.5*c1'));
      expect(f, endsWith(']'));
    });

    test('左右滤镜互不相同且覆盖两种侧', () {
      final l = EarChannelRouter.filterFor(EarSide.left);
      final r = EarChannelRouter.filterFor(EarSide.right);
      expect(l, isNot(equals(r)));
      expect(EarChannelRouter.filterFor(EarSide.left.flipped), equals(r));
      expect(EarChannelRouter.filterFor(EarSide.right.flipped), equals(l));
    });

    test('filterFor 是纯函数、稳定输出', () {
      expect(
        EarChannelRouter.filterFor(EarSide.left),
        equals(EarChannelRouter.filterFor(EarSide.left)),
      );
    });
  });
}
