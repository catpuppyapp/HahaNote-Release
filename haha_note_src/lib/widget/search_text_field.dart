import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:cloud_disk_note_app/widget/loading.dart';
import 'package:flutter/material.dart';

class SearchTextFiled extends StatefulWidget {
  final TextEditingController keyword;
  final bool searching;
  final void Function(String value) onSearch;
  final bool showClear;


  const SearchTextFiled({
    super.key,
    required this.keyword,
    required this.searching,
    required this.onSearch,
    required this.showClear
  });

  @override
  State<SearchTextFiled> createState() => SearchTextFiledState();
}
class SearchTextFiledState extends State<SearchTextFiled> {
  final focusNode = FocusNode();
  
  @override
  void initState() {
    super.initState();
    focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    focusNode.removeListener(_onFocusChange);
    focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // if(focusNode.hasFocus) {  // 得到焦点

    // }else {  // 失去焦点
      // x 测试了，根本没卵用，所以注释了） 若不unfocus，有可能再次重新自动聚焦。
      // 例如，若不unfocus，在安卓手机先在搜索框输入东西，
      // 然后点条目菜单或滑出侧栏使输入框失焦，
      // 关闭菜单或侧栏后，会重新自动聚焦输入框并弹出键盘
      // 若unfocus，则需要再次手动点击搜索框才能使搜索框聚焦
      // focusNode.unfocus();
      // x 不会报错，与期望一致）测试多次调用unfocus是否会报错，期望不会
      // focusNode.unfocus();
      // focusNode.unfocus();
      // focusNode.unfocus();
    // }

    // 在焦点变化时刷新UI显示clear按钮
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  focusNode: focusNode,
                  controller: widget.keyword,
                  decoration: InputDecoration(
                    hintText: t.search,
                    prefixIcon: Icon(Icons.search),
                    suffixIcon: widget.showClear || widget.keyword.text.isNotEmpty || focusNode.hasFocus ? IconButton(
                      onPressed: () {
                        // onSearch 被设计为搜索空字符串即退出搜索，
                        // 所以 清空关键字+传空字符串给onSearch=等于退出搜索
                        widget.keyword.text = "";
                        widget.onSearch("");
                        focusNode.unfocus();
                      },
                      icon: Icon(Icons.clear)
                    ) : null,
                    border: OutlineInputBorder(),
                    // isDense若true，输入框更紧凑，占更少空间
                    isDense: true,
                  ),
                  onSubmitted: (value) {
                    widget.onSearch(value);
                  },
                ),
              ),
            ],
          ),
          if(widget.searching) horizontalLoadingBar(),
        ],
      )
    );
  }
}
