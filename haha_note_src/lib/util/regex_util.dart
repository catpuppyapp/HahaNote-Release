// Dart 版本的 RegexUtil
// 说明：保持与原 Kotlin 行为一致，默认字符串比较支持 ignoreCase。
// 注意：Dart 的 String 没有直接 ignoreCase 参数，使用 toLowerCase() 做不区分大小写比较。

/// TODO 转换完未测试，有时间，检查下
class RegexUtil {
  static const String _extMatchFlag = '*.';
  static const int _extFlagLen = 2; // _extMatchFlag.length
  static const int _extFlagLenSubOne = 1; // _extFlagLen - 1 (保留前导'.')

  static const String _spaceChar = ' ';

  /// 若 target 或 keyword 为空则返回 false。
  /// 支持 pattern 中以 "*.ext" 形式的后缀匹配和普通关键字（用空格分隔）。
  static bool matchWildcard(String target, String keyword, {bool ignoreCase = true}) {
    if (target.isEmpty || keyword.isEmpty) return false;

    String t = target;
    String kWhole = keyword;
    if (ignoreCase) {
      t = target.toLowerCase();
      kWhole = keyword.toLowerCase();
    }

    // 完全匹配
    if (t == kWhole) return true;

    final parts = kWhole.split(_spaceChar);
    if (parts.isEmpty) return false;

    var needMatchExt = false;
    var extMatched = false;
    var validKeyword = false;

    for (final part in parts) {
      if (part.isEmpty) continue;
      validKeyword = true;

      if (part.length > _extFlagLen && part.startsWith(_extMatchFlag)) {
        // 是后缀匹配模式 like "*.txt"
        needMatchExt = true;
        if (!extMatched) {
          final suffix = part.substring(_extFlagLenSubOne); // 保留 '.'，如 ".txt"
          extMatched = t.endsWith(suffix);
        }
      } else {
        // 关键词片段必须都匹配
        if (!t.contains(part)) {
          return false;
        }
      }
    }

    return needMatchExt ? extMatched : validKeyword;
  }

  static bool matchWildcardList(String target, List<String> keywordList, {bool ignoreCase = true}) {
    return matchByPredicate(target, keywordList, (String tgt, String kw) {
      return matchWildcard(tgt, kw, ignoreCase: ignoreCase);
    });
  }

  static bool matchByPredicate(String target, List<String> keywordList, bool Function(String, String) predicate) {
    if (target.isEmpty || keywordList.isEmpty) return false;

    for (final kw in keywordList) {
      if (predicate(target, kw)) return true;
    }
    return false;
  }

  static bool equalsOrEndsWithExt(String target, List<String> keywordList, {bool ignoreCase = true}) {
    String t = ignoreCase ? target.toLowerCase() : target;

    for (final k0 in keywordList) {
      final k = ignoreCase ? k0.toLowerCase() : k0;
      if (k == t) return true;

      if (k.startsWith(_extMatchFlag)) {
        final suffix = k.substring(_extFlagLenSubOne); // 从 '.' 开始的后缀
        if (t.endsWith(suffix)) return true;
      }
    }

    return false;
  }
}
