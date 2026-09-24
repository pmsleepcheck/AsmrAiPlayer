import 'ear_side.dart';

/// 从文件名启发式判定主耳侧：含 左/右/left/right → [EarSide]，否则 null。
///
/// 纯函数，无 IO。英文按整词匹配（避免把 `bright`/`copyright` 判成 right）；
/// 中文/日文汉字直接子串匹配。两侧同时出现视为无法判定（交波形/弹窗）。
class EarSideFilenameDetector {
  // 整词但把 `_`/`-` 当边界（`Right_Ear` 要命中），字母紧邻不命中
  // （`bright`/`leftover`/`copyright` 不误判）。
  static final RegExp _leftEn =
      RegExp(r'(?<![A-Za-z])left(?![A-Za-z])', caseSensitive: false);
  static final RegExp _rightEn =
      RegExp(r'(?<![A-Za-z])right(?![A-Za-z])', caseSensitive: false);
  static const String _leftCjk = '左';
  static const String _rightCjk = '右';

  /// 返回主耳；无法判定或左右冲突返回 null。
  static EarSide? detect(String? fileName) {
    final name = fileName ?? '';
    if (name.isEmpty) return null;

    final hasLeft = _leftEn.hasMatch(name) || name.contains(_leftCjk);
    final hasRight = _rightEn.hasMatch(name) || name.contains(_rightCjk);
    if (hasLeft && hasRight) return null;
    if (hasLeft) return EarSide.left;
    if (hasRight) return EarSide.right;
    return null;
  }
}
