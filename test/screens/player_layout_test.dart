import 'package:aaplay/screens/player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// 播放页封面边长自适应（bug.txt 2026-09-28 ①）：小屏安卓上「封面 + 曲名 + 作品信息」
/// 曾超出封面区高度 → RenderFlex 溢出不裁剪，直接画到底部控件上。
/// `playerCoverSideFor` 是收缩封面的唯一决策点，这里锁定它的边界行为。
void main() {
  group('playerCoverSideFor', () {
    test('大屏封顶 320（宽度充足时）', () {
      expect(
        playerCoverSideFor(availableWidth: 1280, availableHeight: 900),
        320,
      );
    });

    test('按宽度取正方形：宽 360 → 296（减左右各 32）', () {
      expect(
        playerCoverSideFor(availableWidth: 360, availableHeight: 1000),
        296,
      );
    });

    test('矮屏按高度收缩，且不为负', () {
      // 高 300：300 - 196(chrome+kicker) = 104 < 120 → 保底 120。
      expect(
        playerCoverSideFor(availableWidth: 360, availableHeight: 300),
        120,
      );
      // 再矮也不为负（100 - 196 < 0 → 仍保底 120）。
      expect(
        playerCoverSideFor(availableWidth: 360, availableHeight: 100),
        120,
      );
      // 刚好能放下 120 的高度：120 + 196 = 316。
      expect(
        playerCoverSideFor(availableWidth: 360, availableHeight: 316),
        120,
      );
      // 略高一点则按高度线性放大：360 - 196 = 164。
      expect(
        playerCoverSideFor(availableWidth: 360, availableHeight: 360),
        164,
      );
    });

    test('无 kicker 时预算少 24 → 封面更大', () {
      final withKicker = playerCoverSideFor(
        availableWidth: 360,
        availableHeight: 400,
        hasKicker: true,
      );
      final withoutKicker = playerCoverSideFor(
        availableWidth: 360,
        availableHeight: 400,
        hasKicker: false,
      );
      expect(withoutKicker - withKicker, 24);
    });

    test('极窄宽度优先不越宽（保底高度让位）', () {
      // 宽 160 → 上限 96 < 保底 120 → 取 96，绝不出横向溢出。
      expect(
        playerCoverSideFor(availableWidth: 160, availableHeight: 900),
        96,
      );
    });

    test('异常宽度返回 0（交给上层裁剪，不抛错）', () {
      expect(
        playerCoverSideFor(availableWidth: double.infinity, availableHeight: 600),
        0,
      );
      expect(
        playerCoverSideFor(availableWidth: 32, availableHeight: 600),
        0,
      );
    });

    test('maxSide 可由调用方收紧', () {
      expect(
        playerCoverSideFor(
          availableWidth: 1000,
          availableHeight: 1000,
          maxSide: 200,
        ),
        200,
      );
    });
  });
}
