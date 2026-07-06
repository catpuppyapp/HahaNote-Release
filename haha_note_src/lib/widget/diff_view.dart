import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/ui/ui.dart' show UI;
import 'package:hahanote_app/util/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/db.dart';
import '../util/diff_data.dart';
import 'size_adjuster.dart';

// const _TAG = "diff_view.dart";

/// GitHub 风格单文件 Diff Viewer（hunk 分组、上下文折叠）
class DiffView extends StatefulWidget {
  // 纯预览模式（只显示 oldText 内容，这时行号应该是准的）
  final bool preview;
  // 上下文行数（前/后）
  final int contextLines;
  // @Deprecated("默认值改成了和editor默认值相同，并且本组件支持调整字体大小，此字段已弃用")
  // final double fontSize;
  final double lineNumFontSize;
  final void Function(String) showMsg;
  // 行号可能不准，因为空行在比较时可能会被忽略，而且还可能把一行拆分成多行，这个算法有点毛病，自己实现一个有点麻烦，先凑合用吧
  final bool showLineNum;
  final List<DiffLine> lines;
  final double oldLineNumWidth;
  final double newLineNumWidth;

  const DiffView({
    super.key,
    this.preview = false,
    this.contextLines = 3, // 默认 3
    // this.fontSize = 16,
    this.lineNumFontSize = 12,
    required this.showMsg,
    this.showLineNum = false,
    required this.lines,
    this.oldLineNumWidth = 0,
    this.newLineNumWidth = 0,
  });

  @override
  State<DiffView> createState() => DiffViewState();
}

class DiffViewState extends State<DiffView> {
  final Set<int> _selectedIndices = {};
  int? _lastSelectedIndex;

  bool fontSizeAdjusterVisible = false;
  double fontSize = UI.diffViewFontSizeDefault;

  @override
  void initState() {
    super.initState();
    _initFontSize();
  }

  bool get selectionModeIsOn => _selectedIndices.isNotEmpty;

  void quitSelection() {
    setState(() {
      _selectedIndices.clear();
      _lastSelectedIndex = null;
    });
  }

  Future<void> _initFontSize() async {
    final fontSizeFromDb = await Db.getDiffViewFontSize();
    if(fontSizeFromDb != fontSize) {
      _setFontSize(fontSizeFromDb);
    }
  }

  void showFontSizeAdjuster() {
    setState(() {
      fontSizeAdjusterVisible = true;
    });
  }

  void _setFontSize(double value) {
    setState(() {
      fontSize = value;
    });
  }

  void saveAndCloseFontSizeAdjuster() {
    setState(() {
      fontSizeAdjusterVisible = false;
    });

    // save to db
    Db.saveDiffViewFontSize(fontSize);
  }

  Widget _getFontSizeAdjuster() {
    final fontSizeMin = UI.diffViewFontSizeMin;
    final fontSizeMax = UI.diffViewFontSizeMax;
    return getFontSizeAdjuster(
      context,
      onMinus: fontSize <= fontSizeMin ? null : () => _setFontSize(fontSize - UI.diffViewFontSizeAdjustStep),
      onPlus: fontSize >= fontSizeMax ? null : () => _setFontSize(fontSize + UI.diffViewFontSizeAdjustStep),
      onClose: saveAndCloseFontSizeAdjuster,
    );
  }

  Widget buildContent(BuildContext context) {
    final isDark = UI.isDarkTheme();
    final lineNumberBg = isDark ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);
    final lineNumberColor = isDark ? Colors.grey[500]! : Colors.grey[600]!;
    final theme = Theme.of(context);

    return Stack(
      children: [
        ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),

          // 这个页面的外部容器已经有页面padding，所以这里只加bottom padding即可，不然就会出现多余padding浪费空间
          padding: UI.listPaddingOnlyBottom,
          itemCount: widget.lines.length,
          itemBuilder: (context, index) {
            final line = widget.lines[index];
            if (line.isSeparator) return const Divider(height: 24);

            final isSelected = _selectedIndices.contains(index);

            Widget? getLineNumberWidget() {
              if(!widget.showLineNum) {
                return null;
              }

              return Container(
                color: lineNumberBg,
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                child: Row(
                  spacing: 2,
                  children: [
                    Container(
                      width: widget.oldLineNumWidth,
                      alignment: Alignment.centerRight,
                      child: Text(
                        line.oldLineNo?.toString() ?? '',
                        style: TextStyle(color: lineNumberColor, fontSize: widget.lineNumFontSize),
                      ),
                    ),
                    if (!widget.preview) Container(
                      width: widget.newLineNumWidth,
                      alignment: Alignment.centerRight,
                      child: Text(
                        line.newLineNo?.toString() ?? '',
                        style: TextStyle(color: lineNumberColor, fontSize: widget.lineNumFontSize),
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget getContentWidget() {
              return Expanded(
                child: Container(
                  color: isSelected
                      ? UI.getSelectedBgColor(theme, isDark: isDark)
                      : line.bgColor(isDark),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  // 使用 Text.rich 以支持软换行（softWrap）并避免水平滚动
                  child: Text.rich(
                    TextSpan(children: line.cachedSpans),
                    softWrap: true,
                  ),
                ),
              );
            }

            final lineNumWidget = getLineNumberWidget();

            return GestureDetector(
              key: ValueKey(index),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _selectedIndices.clear();
                  _selectedIndices.add(index);
                  _lastSelectedIndex = index;
                });
              },
              onLongPress: () {
                HapticFeedback.vibrate();

                setState(() {
                  if (_lastSelectedIndex != null) {
                    final start = _lastSelectedIndex!;
                    final end = index;
                    if (start <= end) {
                      for (int i = start; i <= end; i++) {
                        _selectedIndices.add(i);
                      }
                    } else {
                      for (int i = end; i <= start; i++) {
                        _selectedIndices.add(i);
                      }
                    }
                  } else {
                    _selectedIndices.add(index);
                  }
                  _lastSelectedIndex = index;
                });
              },
              child: RepaintBoundary(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,  // 让行号在行顶部，比如软换行有3行，在第一行显示行号
                  children: [
                    if(lineNumWidget != null) lineNumWidget,
                    getContentWidget(),
                  ],
                ),
              ),
            );
          },
        ),
        if (_selectedIndices.isNotEmpty)
          Positioned(
            bottom: 16,
            right: 16,
            child: Row(
              children: [
                FloatingActionButton(
                  heroTag: 'copySelection',
                  mini: true,
                  onPressed: () {
                    final selected = _selectedIndices.toList()..sort();
                    final linesText = selected.map((i) => widget.lines[i].textAll).join('\n');
                    copyText(linesText);
                    widget.showMsg(t.copied);
                  },
                  tooltip: t.copy,
                  child: const Icon(Icons.copy),
                ),

                const SizedBox(width: 8),

                FloatingActionButton(
                  heroTag: 'quitSelection',
                  mini: true,
                  onPressed: () {
                    quitSelection();
                  },
                  tooltip: t.quit,
                  child: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        if(fontSizeAdjusterVisible) _getFontSizeAdjuster()
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(fontSize)),
      child: buildContent(context),
    );
  }
}
