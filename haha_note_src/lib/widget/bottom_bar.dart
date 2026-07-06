import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/widget/dialogs.dart' show Dialogs;
import 'package:flutter/material.dart';

// 小于65按钮按下阴影不圆，高度不够
const double bottomBarHeight = 65;
// 显示 BottomBar 的容器的底部padding，避免长按选择模式，然后 BottomBar 出现后覆盖住长按的条目
const double bottomBarContainerBottomPadding = bottomBarHeight+5;
// const double bottomBarContainerBottomPadding = bottomBarHeight;

class BottomBar<T> extends StatelessWidget {
  final List<T> selectedFileList;
  final void Function(String) showMsg;
  final void Function(String) showMsgLong;
  final List<Widget> children;
  final String Function(T) itemInfoTextGenerator;

  const BottomBar({
    super.key,
    required this.selectedFileList,
    required this.showMsg,
    required this.showMsgLong,
    required this.itemInfoTextGenerator,
    required this.children,
  });


  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: bottomBarHeight,
      child: Row(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: () {
                  Dialogs.showCopyDialog(
                    context,
                    title: t.selected,
                    text: selectedFileList.map((it) => itemInfoTextGenerator(it)).join("\n\n"),
                    showMsg: showMsg
                  );
                },
                child: Padding(
                  // 加点padding防止按不到
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(selectedFileList.length.toString(), style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              // horizontal滚动方向加反转true，可使列表右对齐，但条目顺序会反，
              // 所以把list再reverse一下，最后就负负得正了
              reverse: true,
              children: children.reversed.toList(),
            ),
          ),
        ],
      )
    );
  }

}
