import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';

import '../ui/my_fonts.dart';
import '../ui/ui.dart';

class DiffData {
  String oldText = "";
  String newText = "";
  int contextLines = 3; // 上下文行数（前/后）
  double fontSize = 16;
  double lineNumFontSize = 12;
  List<DiffLine>? diffLines;
  List<DiffLine>? previewLines;
  double previewOldLineNumWidth = 0;
  double previewNewLineNumWidth = 0;
  double diffOldLineNumWidth = 0;
  double diffNewLineNumWidth = 0;

  void init() {
    if(previewLines != null && diffLines != null) {
      return;
    }


    if(previewLines == null) {
      final allLines = _buildPreviewLines(oldText);
      previewLines = _extractHunksWithContext(allLines, contextLines);
    }

    if(diffLines == null) {
      var allLines = <DiffLine>[];
      if (oldText != newText) {
        final diffs = _getDiff(oldText, newText);

        // 先构建完整的行（包含 unchanged / deleted / added / merged）
        allLines = _buildLines(diffs);
      }

      // 按 hunk 分组并仅保留每个 hunk 的前后 contextLines 行（合并相邻修改为一个 hunk）
      diffLines = _extractHunksWithContext(allLines, contextLines);
    }


    // 计算完清空oldText和newText
    oldText = "";
    newText = "";

    // 预先为每一行准备好 TextSpan（基于缓存的按需准备，内部会跳过已缓存的）
    for (final line in previewLines!) {
      line.prepareSpans(UI.isDarkTheme(), fontSize);
    }

    for (final line in diffLines!) {
      line.prepareSpans(UI.isDarkTheme(), fontSize);
    }

    // 初始化行号宽度
    _initLineNumFontSize(preview: true);
    _initLineNumFontSize(preview: false);
  }

  void _initLineNumFontSize({required bool preview}) {
    final lines = getLines(preview: preview);

    // 计算行号列宽度（一次性）
    final maxOld = lines.map((l) => l.oldLineNo ?? 0).fold(0, (p, n) => n > p ? n : p);
    final maxNew = lines.map((l) => l.newLineNo ?? 0).fold(0, (p, n) => n > p ? n : p);
    final oldDigits = maxOld.toString().length;
    final newDigits = maxNew.toString().length;
    final charWidth = lineNumFontSize * 0.6;
    if(preview) {
      previewOldLineNumWidth = oldDigits * charWidth;
      previewNewLineNumWidth = newDigits * charWidth;
    }else {
      diffOldLineNumWidth = oldDigits * charWidth;
      diffNewLineNumWidth = newDigits * charWidth;
    }
  }


  List<DiffLine> getLines({required bool preview}) {
    return (preview ? previewLines : diffLines)!;
  }

  double getOldLineNumWidth({required bool preview}) {
    return preview ? previewOldLineNumWidth : diffOldLineNumWidth;
  }

  double getNewLineNumWidth({required bool preview}) {
    return preview ? previewNewLineNumWidth : diffNewLineNumWidth;
  }

}



/// ---------- 数据结构 ----------
class DiffLine {
  final int? oldLineNo;
  final int? newLineNo;
  final DiffOp type;
  final String text;
  List<DiffChar>? chars;
  final bool isSeparator;

  // cached spans for rendering
  List<InlineSpan> cachedSpans = [];

  // key used to determine whether cachedSpans are still valid
  // String? _spansKey;
  bool calculated = false;

  // 包含删除、新增、未修改所有类型的文本，例如某一行删除了文字a，添加了文字b，这时`text`不包含已删除文本，这个会包含
  String textAll = "";

  DiffLine({
    this.oldLineNo,
    this.newLineNo,
    required this.type,
    required this.text,
    this.chars,
    this.isSeparator = false,
  });

  // shallow background by line type
  Color bgColor(bool isDark) {

    // 如果想新增行和删除行使用浅色背景颜色加深色背景颜色，注释这行，否则只针对新增和删除的文本显示颜色，未修改的不显示颜色
    return Colors.transparent;


    if (isSeparator) {
      return Colors.transparent;
    }
    switch (type) {
      case DiffOp.added:
        return isDark ? const Color(0xFF143A14) : const Color(0xFFCFFFE0);
      case DiffOp.deleted:
        return isDark ? const Color(0xFF3A1414) : const Color(0xFFFFE0E0);
      case DiffOp.modified:
      case DiffOp.unchanged:
        return Colors.transparent;
    }
  }

  // prepare TextSpan list; text color unified, changed regions use deeper background
  void prepareSpans(bool isDark, double fontSize) {
    // build a key to detect whether we can reuse cachedSpans
    // final key = '${isDark}_${fontSize}_${type.index}_${text.hashCode}_${chars.hashCode}';
    //
    // if (cachedSpans.isNotEmpty && _spansKey == key) {
    //   // cache hit
    //   return;
    // }
    //
    // _spansKey = key;

    if(calculated) {
      return;
    }

    calculated = true;

    // 初始化为和text一样，然后若是modified line，会计算添加和删除的内容，然后重新赋值此变量
    textAll = text;

    final normalTextColor = isDark ? Colors.white : Colors.black;

    final deepAdd = isDark
        ? const Color(0xFF1F6F43)
        : const Color(0xFFB7E4C7);

    final deepDel = isDark
        ? const Color(0xFF8B2E2E)
        : const Color(0xFFFFC9C9);

    final baseTextStyle = TextStyle(
      color: normalTextColor,
      // fontSize: fontSize,
      // height: 1.25,
    ).toMono();

    // ===== helper：flush buffer into span =====
    InlineSpan buildSpan(String text, DiffOp? type) {
      if (type == DiffOp.added) {
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            color: deepAdd,
            child: Text(text, style: baseTextStyle),
          ),
        );
      }
      if (type == DiffOp.deleted) {
        return WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            color: deepDel,
            child: Text(text, style: baseTextStyle),
          ),
        );
      }

      return WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Text(text, style: baseTextStyle),
      );
    }

    // ===== case 1：char-level diff =====
    if (chars != null && chars!.isNotEmpty) {
      final spans = <InlineSpan>[];
      final buffer = StringBuffer();
      final textAllBuffer = StringBuffer();
      DiffOp? lastType;

      void flush() {
        if (buffer.isEmpty) return;

        final bufferedText = buffer.toString();
        buffer.clear();

        spans.add(buildSpan(bufferedText, lastType));
        textAllBuffer.write(bufferedText);
      }

      for (final c in chars!) {
        if (lastType != c.type) {
          flush();
          lastType = c.type;
        }
        buffer.write(c.char);
      }
      flush();

      cachedSpans = spans;
      textAll = textAllBuffer.toString();
      return;
    }

    // ===== case 2：line-level diff =====
    if (type == DiffOp.added) {
      cachedSpans = [
        buildSpan(text, DiffOp.added),
      ];
    } else if (type == DiffOp.deleted) {
      cachedSpans = [
        buildSpan(text, DiffOp.deleted),
      ];
    } else {
      cachedSpans = [
        buildSpan(text, DiffOp.unchanged),
      ];
    }
  }
}

class DiffChar {
  final String char;
  final DiffOp type;
  DiffChar(this.char, this.type);
}

enum DiffOp { added, deleted, modified, unchanged }

/// ---------- 预览行构建 ----------
List<DiffLine> _buildPreviewLines(String text) {
  final lines = <DiffLine>[];
  final allLines = text.split('\n');
  for (int i = 0; i < allLines.length; i++) {
    // 这里的DiffOp若传 added，背景绿色; deleted 红色; modified，由于实际上没有被删除的文本，背景透明; 若传unchanged，直接不显示
    // AI写的下头代码，凑合用先
    lines.add(DiffLine(oldLineNo: i + 1, newLineNo: null, type: DiffOp.modified, text: allLines[i]));
  }
  return lines;
}

/// ---------- 构建完整行（按字符来源） ----------
/// 产生包含 oldLineNo/newLineNo、type、per-char chars（当需要时）的行序列
List<DiffLine> _buildLines(List<Diff> diffs) {
  final lines = <DiffLine>[];
  int oldLineNo = 1;
  int newLineNo = 1;

  final oldLineBuf = StringBuffer();
  final newLineBuf = StringBuffer();

  void flushLine() {
    if (oldLineBuf.isEmpty && newLineBuf.isEmpty) return;

    final oldText = oldLineBuf.toString();
    final newText = newLineBuf.toString();

    final mergedChars = _charDiff(oldText, newText);
    final hasChange = mergedChars.any((c) => c.type != DiffOp.unchanged);

    if (hasChange) {
      if (oldText.isNotEmpty && newText.isEmpty) {
        // 删除整行
        lines.add(DiffLine(
          oldLineNo: oldLineNo++,
          newLineNo: null,
          type: DiffOp.deleted,
          text: oldText,
          chars: mergedChars.where((c) => c.type != DiffOp.added).toList(),
        ));
      } else if (newText.isNotEmpty && oldText.isEmpty) {
        // 新增整行
        lines.add(DiffLine(
          oldLineNo: null,
          newLineNo: newLineNo++,
          type: DiffOp.added,
          text: newText,
          chars: mergedChars.where((c) => c.type != DiffOp.deleted).toList(),
        ));
      } else {
        // 修改行（部分新增/删除）
        lines.add(DiffLine(
          oldLineNo: oldLineNo++,
          newLineNo: newLineNo++,
          type: DiffOp.modified,
          text: newText,
          chars: mergedChars,
        ));
      }
    } else {
      // 完全未修改
      lines.add(DiffLine(
        oldLineNo: oldLineNo++,
        newLineNo: newLineNo++,
        type: DiffOp.unchanged,
        text: oldText,
        chars: mergedChars,
      ));
    }

    oldLineBuf.clear();
    newLineBuf.clear();
  }

  for (final diff in diffs) {
    final text = diff.text;
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == '\n') {
        flushLine();
        continue;
      }
      if (diff.operation == DIFF_EQUAL) {
        oldLineBuf.write(ch);
        newLineBuf.write(ch);
      } else if (diff.operation == DIFF_DELETE) {
        oldLineBuf.write(ch);
      } else if (diff.operation == DIFF_INSERT) {
        newLineBuf.write(ch);
      }
    }
  }

  flushLine(); // 处理最后一行

  return lines;
}

/// ---------- 将完整行按 hunk 分组并抽取每个 hunk 的上下文 ----------
/// - 将连续修改（非 unchanged 或包含 added/deleted chars）的区域视为一个或多个修改点
/// - 为每个修改块计算上下文 start/end（前后 context 行）
/// - 如果两个块的上下文范围相交或相邻，则合并为一个 hunk
/// - 返回的 list 为各 hunk 展开后的行序列，hunk 之间用 isSeparator 行分隔
List<DiffLine> _extractHunksWithContext(List<DiffLine> allLines, int context) {
  final modifiedIdx = <int>[];
  for (int i = 0; i < allLines.length; i++) {
    final l = allLines[i];
    if (l.isSeparator) continue;
    // consider line modified if:
    // - line.type != unchanged (added/deleted/modified)
    // - OR line.chars contains any added/deleted chars (merged line with changes)
    final hasCharChanges = l.chars != null && l.chars!.any((c) => c.type == DiffOp.added || c.type == DiffOp.deleted);
    if (l.type != DiffOp.unchanged || hasCharChanges) {
      modifiedIdx.add(i);
    }
  }

  if (modifiedIdx.isEmpty) return [];

  // Build initial ranges around each modified index
  final ranges = <List<int>>[];
  for (int idx in modifiedIdx) {
    final start = (idx - context).clamp(0, allLines.length - 1);
    final end = (idx + context).clamp(0, allLines.length - 1);
    ranges.add([start, end]);
  }

  // Merge overlapping/adjacent ranges into hunks
  ranges.sort((a, b) => a[0].compareTo(b[0]));
  final merged = <List<int>>[];
  for (final r in ranges) {
    if (merged.isEmpty) {
      merged.add([r[0], r[1]]);
    } else {
      final last = merged.last;
      if (r[0] <= last[1] + 1) {
        // overlap or adjacent: merge
        last[1] = r[1] > last[1] ? r[1] : last[1];
      } else {
        merged.add([r[0], r[1]]);
      }
    }
  }

  // Build result: for each merged hunk range, append the lines sublist; insert separators between hunks
  final result = <DiffLine>[];
  for (int h = 0; h < merged.length; h++) {
    final start = merged[h][0];
    final end = merged[h][1];
    result.addAll(allLines.sublist(start, end + 1));
    if (h < merged.length - 1) {
      result.add(DiffLine(oldLineNo: null, newLineNo: null, type: DiffOp.unchanged, text: '', isSeparator: true));
    }
  }

  return result;
}

/// 字符级 diff -> per-char 标注
List<DiffChar> _charDiff(String oldLine, String newLine) {
  final diffs = _getDiff(oldLine, newLine);
  final chars = <DiffChar>[];
  for (final diff in diffs) {
    for (var c in diff.text.split('')) {
      switch (diff.operation) {
        case DIFF_EQUAL:
          chars.add(DiffChar(c, DiffOp.unchanged));
          break;
        case DIFF_INSERT:
          chars.add(DiffChar(c, DiffOp.added));
          break;
        case DIFF_DELETE:
          chars.add(DiffChar(c, DiffOp.deleted));
          break;
      }
    }
  }
  return chars;
}

List<Diff> _getDiff(String oldText, String newText) {
  final dmp = DiffMatchPatch();
  // 我看源代码这个dead line不会导致抛异常啊，似乎只会导致提前返回，
  // 后面就不比较了。。我也不知道具体影响，总之先设成30秒吧
  // 单位秒
  dmp.diffTimeout = 30;
  // 不太清楚这俩是干嘛的，不过设为0似乎代表完整匹配？但也没见多完整啊，空行还是被删除了
  // dmp.matchThreshold = 0;
  // dmp.patchDeleteThreshold = 0;

  // 好像没什么用，输出还是会忽略空行导致行号不准确
  // return dmp.patch(oldText, newText);

  final diffs = dmp.diff(oldText, newText);

  // 不知道干嘛的，启用与否都会删除空行，所以启用吧
  dmp.diffCleanupSemantic(diffs);

  return diffs;
}
