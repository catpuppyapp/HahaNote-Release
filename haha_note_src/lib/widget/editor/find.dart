import 'package:hahanote_app/i18n/strings.g.dart' show t;
import 'package:flutter/material.dart';
import 'package:code_forge/code_forge.dart'; // 1. 替换为 CodeForge 核心库

// 布局常量保持不变
const double _kDefaultFindPanelHeight = 48.0;
const double _kDefaultFindIconSize = 20.0;
const double _kDefaultFindIconWidth = 32.0;
const double _kDefaultFindIconHeight = 32.0;
const double _kDefaultFindInputFontSize = 13.0;
const double _kDefaultFindResultFontSize = 12.0;

class CodeFindPanelView extends StatefulWidget implements PreferredSizeWidget {
  // 2. 将控制器类型更换为 CodeForge 的查找控制器
  final FindController controller;
  final bool readOnly;

  const CodeFindPanelView({
    super.key,
    required this.controller,
    required this.readOnly,
  });

  @override
  Size get preferredSize {
    // CodeForge 内部通过 replaceMode 属性直接维护当前模式
    final double height = controller.isReplaceMode
        ? (_kDefaultFindPanelHeight * 2)
        : _kDefaultFindPanelHeight;
    return Size(double.infinity, height);
  }

  @override
  State<CodeFindPanelView> createState() => CodeFindPanelViewState();
}

class CodeFindPanelViewState extends State<CodeFindPanelView> {
  final EdgeInsetsGeometry margin = EdgeInsets.zero;
  final Color? iconColor = null;
  final Color? iconSelectedColor = null;
  final double iconSize = _kDefaultFindIconSize;
  final double inputFontSize = _kDefaultFindInputFontSize;
  final double resultFontSize = _kDefaultFindResultFontSize;
  final Color? inputTextColor = null;
  final Color? resultFontColor = null;
  final EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4);

  late final FindController controller;

  @override
  void initState() {
    super.initState();
    controller = widget.controller;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 3. 使用 ListenableBuilder 监听 CodeForge 控制器状态，替代原先的 ValueNotifier 机制
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFindRow(context),
              if (controller.isReplaceMode) _buildReplaceRow(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFindRow(BuildContext context) {
    // 4. 从 CodeForge 直接读取总匹配数和当前匹配索引 (0-indexed)
    final int total = controller.matchCount;
    final int current = controller.currentMatchIndex;

    final String result = total == 0
        ? t.none
        : '${current + 1}/$total';

    return SizedBox(
      height: _kDefaultFindPanelHeight,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180),
              child: Padding(
                padding: padding,
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    _buildTextField(
                      context: context,
                      // 使用 CodeForge 内置的查找文本控制器和焦点树
                      controller: controller.findInputController,
                      focusNode: controller.findInputFocusNode,
                      hintText: t.find,
                      rightPadding: 60,
                    ),
                    Positioned(
                      right: 10,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCheckText(
                            context: context,
                            text: 'Aa',
                            checked: controller.caseSensitive,
                            onPressed: () => controller.toggleCaseSensitive(),
                          ),
                          const SizedBox(width: 10),
                          _buildCheckText(
                            context: context,
                            text: '.*',
                            checked: controller.isRegex, // 对应 CodeForge 的正则状态
                            onPressed: () => controller.toggleRegex(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(width: 8),
                Text(
                  result,
                  style: TextStyle(
                    color: resultFontColor ?? Colors.grey,
                    fontSize: resultFontSize,
                  ),
                ),
                const SizedBox(width: 6),
                _buildIconButton(
                  onPressed: total == 0 ? null : () => controller.previous(),
                  icon: Icons.keyboard_arrow_up,
                  tooltip: t.previous,
                ),
                const SizedBox(width: 6),
                _buildIconButton(
                  onPressed: total == 0 ? null : () => controller.next(),
                  icon: Icons.keyboard_arrow_down,
                  tooltip: t.next,
                ),
                const SizedBox(width: 6),
                _buildIconButton(
                  onPressed: () {
                    // 这个判断没意义，能点到close按钮，肯定是Active
                    // if(!controller.isActive) return;

                    controller.toggleActive();
                  },
                  icon: Icons.close,
                  tooltip: t.close,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplaceRow(BuildContext context) {
    final int total = controller.matchCount;

    return SizedBox(
      height: _kDefaultFindPanelHeight,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180),
              child: Padding(
                padding: padding,
                child: _buildTextField(
                  context: context,
                  // 使用 CodeForge 内置的替换文本控制器和焦点树
                  controller: controller.replaceInputController,
                  focusNode: controller.replaceInputFocusNode,
                  hintText: t.replace,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(width: 8),
                _buildIconButton(
                  onPressed: total == 0 ? null : () => controller.replace(),
                  icon: Icons.find_replace,
                  tooltip: t.replace,
                ),
                const SizedBox(width: 6),
                _buildIconButton(
                  onPressed: total == 0 ? null : () => controller.replaceAll(),
                  icon: Icons.done_all,
                  tooltip: t.replaceAll,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    double rightPadding = 0,
  }) {
    return TextField(
      maxLines: 1,
      focusNode: focusNode,
      controller: controller,
      style: TextStyle(color: inputTextColor, fontSize: inputFontSize),
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        filled: true,
        fillColor: Theme.of(context).canvasColor,
        contentPadding: EdgeInsets.only(
          left: 10,
          top: 10,
          bottom: 10,
          right: rightPadding,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildCheckText({
    required BuildContext context,
    required String text,
    required bool checked,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Text(
          text,
          style: TextStyle(
            color: checked ? (iconSelectedColor ?? Theme.of(context).primaryColor) : (iconColor ?? Colors.grey),
            fontSize: inputFontSize,
            fontWeight: checked ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    VoidCallback? onPressed,
    String? tooltip,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: iconSize),
      constraints: const BoxConstraints(
        maxWidth: _kDefaultFindIconWidth,
        maxHeight: _kDefaultFindIconHeight,
      ),
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      splashRadius: 18,
    );
  }
}
