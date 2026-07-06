import 'package:hahanote_app/bean/bean.dart' show ContentItem;
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/widget/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../ui/ui.dart';


// 垂直布局，有以下元素：
// first line
// second line
// content

class ContentItemWaterfall extends StatefulWidget {
  final List<ContentItem> items;
  // 主体内容(至少包含content，可能还包含first line和second line)的onClick
  final void Function(int idx, ContentItem) onClick;
  final void Function(int idx, ContentItem)? onActClick;
  final void Function(int idx, ContentItem)? onSecondLineClick;
  final void Function(int idx, ContentItem)? onLongPress;
  final bool Function(int idx, ContentItem)? selected;

  const ContentItemWaterfall({
    super.key,
    required this.items,
    required this.onClick,
    this.onActClick,
    this.onSecondLineClick,
    this.onLongPress,
    this.selected,
  });

  @override
  State<ContentItemWaterfall> createState() => _ContentItemWaterfallState();
}

class _ContentItemWaterfallState extends State<ContentItemWaterfall> {

  // 2. 传入 ContentItem 对象进行构建
  Widget _buildContentCard(int idx, ContentItem item, ThemeData theme) {
    return Card(
      color: widget.selected?.call(idx, item) == true ? UI.getSelectedBgColor(theme) : null,
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                item.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            if(item.parentPath.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  item.parentPath,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),

            Divider(thickness: 0.3),

            // 内容区域
            Text(
              item.content,
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = widget.items;
    if(items.isEmpty) {
      return BaseLayout.defaultScreenPaddingContainer(child: Center(child: SelectableText(t.nothing)));
    }

    return MasonryGridView.extent(
      padding: UI.listPadding,
      // 设置卡片的最大宽度，系统会根据这个值自动决定排成几列
      maxCrossAxisExtent: 200,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];

        // 使用 InkWell 包装以获得水波纹效果
        return InkWell(
          borderRadius: BorderRadius.circular(10), // 保持和卡片一致的圆角，防止水波纹溢出
          onTap: () {
            widget.onClick(index, item);
          },
          onLongPress: widget.onLongPress == null ? null : () {
            widget.onLongPress?.call(index, item);
          },
          child: _buildContentCard(index, item, theme),
        );
      },
    );
  }

}