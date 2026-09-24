/// 双耳音频的「主耳」侧（内容更强/需要保留为主音轨的那一侧）。
enum EarSide {
  left,
  right;

  static EarSide? tryParse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'left':
      case 'l':
      case '左':
        return EarSide.left;
      case 'right':
      case 'r':
      case '右':
        return EarSide.right;
      default:
        return null;
    }
  }

  /// 持久化用稳定字符串（与 [tryParse] 兼容）。
  String get storageValue => this == EarSide.left ? 'left' : 'right';

  EarSide get flipped => this == EarSide.left ? EarSide.right : EarSide.left;
}
