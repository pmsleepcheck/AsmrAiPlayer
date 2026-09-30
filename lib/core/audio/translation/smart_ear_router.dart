import 'ear_side.dart';
import 'smart_ear_analyzer.dart';

/// 智能耳（实验）翻译路由的纯决策函数：**翻译轨**该播哪只耳。
///
/// 主轨始终保留原始立体声（不 pan），只有翻译轨被路由：
/// - 智能开 + 有时间线 → 内容更响的一侧取**对侧**（翻译压过内容的同侧）；
/// - 智能开 + 该窗等响/未知 → 一句左一句右轮播（按字幕行号奇偶，
///   偶数行左；seek 之后行号不变 → 结果稳定）；
/// - 智能关 / 时间线缺失（在线流、flac 等不支持的容器）→ [fallbackEar]
///   的对侧 = 和固定分耳完全一样的行为。
class SmartEarRouter {
  const SmartEarRouter._();

  static EarSide resolve({
    required bool smart,
    required EarSide fallbackEar,
    EarTimeline? timeline,
    int positionMs = 0,
    required int lineIndex,
  }) {
    if (!smart || timeline == null) return fallbackEar.flipped;
    final content = timeline.sideAt(positionMs);
    if (content != null) return content.flipped;
    return lineIndex.isEven ? EarSide.left : EarSide.right;
  }
}
