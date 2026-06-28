import 'package:cloud_disk_note_app/bean/bean.dart' show LabelValue, MenuItem;
import 'package:cloud_disk_note_app/ext/iterable_ext.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:cloud_disk_note_app/ui/ui.dart';
import 'package:cloud_disk_note_app/widget/base_layout.dart';
import 'package:flutter/material.dart';

import 'line.dart';

typedef ItemWidgetBuilder<T> = Widget Function(BuildContext context, int index, T item);
typedef ItemTapCallback<T> = void Function(int index, T item);
typedef RefreshCallback = Future<void> Function();

class CustomListView<T> extends StatelessWidget {
  final List<T> items;
  final ItemWidgetBuilder<T> itemBuilder;
  final bool showDivider;
  final EdgeInsetsGeometry? padding;
  final RefreshCallback? onRefresh;
  final bool shrinkWrap;

  const CustomListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.showDivider = true,
    this.padding,
    this.onRefresh,
    this.shrinkWrap = false,
  });

  @override
  Widget build(BuildContext context) {
    if(items.isEmpty) {
      return BaseLayout.defaultScreenPaddingContainer(child: Center(child: SelectableText(t.nothing),));
    }

    Widget list = ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding ?? UI.listPadding,
      shrinkWrap: shrinkWrap,
      itemCount: items.length,
      separatorBuilder: (context, index) =>
      showDivider ? const Divider(height: 1) : const SizedBox.shrink(),
      itemBuilder: (context, index) {
        final item = items[index];
        final child = itemBuilder(context, index, item);
        return child;
      },
    );

    if (onRefresh != null) {
      return RefreshIndicator(
        onRefresh: onRefresh!,
        child: list,
      );
    }
    return list;
  }
}



class LabelValueTile extends StatelessWidget {
  final List<LabelValue> items;
  final List<MenuItem> menuItems;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool textCopiable;

  const LabelValueTile({
    super.key,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.textCopiable = true,
    required this.items,
    required this.menuItems,
  });

  Widget _buildMenu(BuildContext context) {
    final items = <PopupMenuEntry<String>>[];
    for(final m in menuItems) {
      if(m.value == MenuItem.divider.value) {
        items.add(
          // PopupMenuItem<String>(value: m.value, child: const Divider())
          const PopupMenuDivider()
        );
        continue;
      }

      items.add(
        PopupMenuItem<String>(
          value: m.value,
          child: Text(m.text),
        )
      );
    }

    return PopupMenuButton<String>(
      onSelected: (value) {
        final item = menuItems.firstWhereOrNull((i) => value == i.value);
        item?.onClick?.call();
      },
      itemBuilder: (context) => items,
      icon: Icon(Icons.more_vert),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4), // 可选：间距
      // padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? UI.getSelectedBgColor(theme) : null, // 条目背景色
        borderRadius: BorderRadius.circular(6), // 可选：圆角
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          // 若不加padding，按下阴影，会和文字紧挨着，难看
          padding: EdgeInsetsGeometry.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for(final item in items)
                      singleScrollableLabelValueRow(item, textSelectable: textCopiable),
                  ],
                ),
              ),

              if(menuItems.isNotEmpty) _buildMenu(context),
            ],
          ),
        ),
      ),
    );
  }

}
