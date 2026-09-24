import 'dart:math';
import 'package:aaplay/data/models/files/child.dart';
import 'package:aaplay/utils/logger.dart';

/// 字幕文件名匹配：优先级链
/// 1. 全文件名精确匹配
/// 2. 规范化全名匹配（小写、去扩展名、空白/全角空格折叠、常见破折号归一）
/// 3. 去字符模糊匹配（仅保留字母/数字/CJK/假名/谚文后先求全等，
///    再退 Levenshtein ≥ 0.6；前缀命中在模糊层内优先于纯编辑距离）
class SubtitleMatcher {
  static const supportedFormats = ['.vtt', '.lrc'];
  static const double _similarityThreshold = 0.6;

  /// 仅保留字母/数字与常见 CJK 字符，其余（空白、标点、括号等）全部去掉。
  static final RegExp _noise = RegExp(
    r'[^0-9a-z\u00c0-\u024f\u4e00-\u9fff\u3040-\u30ff\u31f0-\u31ff\uac00-\ud7af]+',
  );

  static bool isSubtitleFile(String? fileName) {
    if (fileName == null) return false;
    return supportedFormats
        .any((format) => fileName.toLowerCase().endsWith(format));
  }

  /// 在 [candidates]（同目录或已收集的全树字幕）内按 ①②③ 查找。
  static Child? findMatchingSubtitle(
      String audioFileName, List<Child> candidates) {
    final subtitleFiles =
        candidates.where((f) => isSubtitleFile(f.title)).toList();
    if (subtitleFiles.isEmpty) return null;

    final audioBase = _getBaseName(audioFileName);
    if (audioBase.trim().isEmpty) return null;

    // ① 全文件名精确匹配
    final exactMatch = _findExactMatch(audioFileName, subtitleFiles);
    if (exactMatch != null) {
      AppLogger.debug('字幕匹配[精确]: ${exactMatch.title}');
      return exactMatch;
    }

    // ② 规范化全名匹配
    final normalizedMatch = _findNormalizedMatch(audioBase, subtitleFiles);
    if (normalizedMatch != null) {
      AppLogger.debug('字幕匹配[规范化]: ${normalizedMatch.title}');
      return normalizedMatch;
    }

    // ③ 去字符模糊匹配
    final fuzzyMatch = _findStrippedMatch(audioBase, subtitleFiles);
    if (fuzzyMatch != null) {
      AppLogger.debug('字幕匹配[去字符模糊]: ${fuzzyMatch.title}');
      return fuzzyMatch;
    }

    return null;
  }

  /// ① 精确：`base+ext` / `fullName+ext` 与候选文件名（忽略大小写）相等。
  static Child? _findExactMatch(
      String audioFileName, List<Child> subtitleFiles) {
    final possibleNames = _getPossibleSubtitleNames(audioFileName);
    for (final name in possibleNames) {
      for (final file in subtitleFiles) {
        if (file.title?.toLowerCase() == name.toLowerCase()) {
          return file;
        }
      }
    }
    return null;
  }

  /// ② 规范化后全名相等。
  static Child? _findNormalizedMatch(
      String audioBase, List<Child> subtitleFiles) {
    final audioNorm = normalizeName(audioBase);
    if (audioNorm.isEmpty) return null;
    for (final file in subtitleFiles) {
      final subNorm = normalizeName(_getBaseName(file.title!));
      if (subNorm.isNotEmpty && subNorm == audioNorm) return file;
    }
    return null;
  }

  /// ③ 去字符后：全等 → 前缀 → Levenshtein ≥ 0.6。
  static Child? _findStrippedMatch(
      String audioBase, List<Child> subtitleFiles) {
    final audioStrip = stripNoise(audioBase);
    if (audioStrip.length < 3) return null;

    Child? bestExact;
    Child? bestPrefix;
    int bestPrefixDiff = 999999;
    Child? bestSimilar;
    double bestScore = 0.0;

    for (final file in subtitleFiles) {
      final subStrip = stripNoise(_getBaseName(file.title!));
      if (subStrip.isEmpty) continue;

      if (subStrip == audioStrip) {
        bestExact ??= file;
        continue;
      }

      if (subStrip.startsWith(audioStrip) ||
          audioStrip.startsWith(subStrip)) {
        final diff = (subStrip.length - audioStrip.length).abs();
        if (diff < bestPrefixDiff) {
          bestPrefixDiff = diff;
          bestPrefix = file;
        }
        continue;
      }

      final score = _similarity(audioStrip, subStrip);
      if (score > bestScore && score >= _similarityThreshold) {
        bestScore = score;
        bestSimilar = file;
      }
    }

    final hit = bestExact ?? bestPrefix ?? bestSimilar;
    if (hit != null && bestSimilar == hit) {
      AppLogger.debug(
          '字幕去字符相似度: ${hit.title} (${bestScore.toStringAsFixed(2)})');
    }
    return hit;
  }

  /// ② 的规范化：小写、去扩展名、trim、全角空格折叠、常见破折号归一。
  static String normalizeName(String name) {
    var t = _getBaseName(name).toLowerCase().trim();
    t = t.replaceAll('\u3000', ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceAll(RegExp(r'[‐-―−˗]'), '-');
    return t;
  }

  /// ③ 的去字符：仅保留 ASCII 字母数字、扩展拉丁、CJK、假名、谚文。
  static String stripNoise(String name) {
    return _getBaseName(name)
        .toLowerCase()
        .replaceAll(_noise, '');
  }

  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final maxLen = max(a.length, b.length);
    return 1.0 - (_levenshteinDistance(a, b) / maxLen);
  }

  static int _levenshteinDistance(String s, String t) {
    final m = s.length;
    final n = t.length;

    var prev = List<int>.generate(n + 1, (i) => i);
    var curr = List<int>.filled(n + 1, 0);

    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = s[i - 1] == t[j - 1] ? 0 : 1;
        curr[j] = min(min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }
    return prev[n];
  }

  static List<String> _getPossibleSubtitleNames(String audioFileName) {
    final baseName = _getBaseName(audioFileName);
    return [
      for (final format in supportedFormats) ...[
        '$baseName$format',
        '$audioFileName$format',
      ]
    ];
  }

  static String _getBaseName(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1) return fileName;
    return fileName.substring(0, lastDot);
  }
}
