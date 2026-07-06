import 'package:hahanote_app/bean/bean.dart';
import 'package:hahanote_app/ext/iterable_ext.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 单行文件项 Widget：支持 onTap、onLongPress（移动端）和右键菜单（桌面/web）。
class DropdownMenuWidget extends StatefulWidget {
  final Future<void> Function()? onTap;
  final List<MenuItem> menuItems;
  final Widget child;

  const DropdownMenuWidget({
    super.key,
    this.onTap,
    required this.menuItems,
    required this.child
  });

  @override
  State<DropdownMenuWidget> createState() => _DropdownMenuWidgetState();
}

class _DropdownMenuWidgetState extends State<DropdownMenuWidget> {
  // 记录最近一次的全局点击位置，用于在该位置打开上下文菜单
  Offset? _tapPosition;
  List<PopupMenuItem<String>> menuItemList = [];

  @override
  void initState() {
    super.initState();

    for(final mi in widget.menuItems) {
      menuItemList.add(PopupMenuItem<String>(value: mi.value, child: Text(mi.text)));
    }
  }

  void _storeTapPosition(TapDownDetails details) {
    _tapPosition = details.globalPosition;
  }

  void _storeLongPressPosition(LongPressStartDetails details) {
    _tapPosition = details.globalPosition;
  }

  Future<void> _showContextMenu() async {
    final position = _tapPosition ?? Offset.zero;
    // 构造 RelativeRect 时使用相同的 dx/dy 放在 left/top/right/bottom
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: menuItemList,
    );

    final item = widget.menuItems.firstWhereOrNull((e) => e.value == selected);

    if(item != null) {
      await item.onClick?.call();
    }

  }

  // void _showSnack(String text) {
  //   if (!mounted) return;
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(content: Text(text), duration: const Duration(milliseconds: 800)),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque, // 避免点空白处穿透？
      onTapDown: _storeTapPosition, // 记录左键/触摸位置（备用）
      onSecondaryTapDown: _storeTapPosition, // 记录右键位置（桌面/web）
      onLongPressStart: _storeLongPressPosition, // 记录长按起始位置（移动端）
      onTap: () async {
        await widget.onTap?.call();
      },
      onLongPress: () {
        HapticFeedback.vibrate();
        // 长按（移动端）通常显示同样的上下文菜单
        _showContextMenu();
      },
      onSecondaryTap: () {
        // 右键单击（桌面/web）显示菜单
        _showContextMenu();
      },
      child: widget.child,
    );
  }
}
