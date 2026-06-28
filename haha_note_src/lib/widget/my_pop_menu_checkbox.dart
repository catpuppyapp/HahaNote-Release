import 'package:flutter/material.dart';

import '../ui/ui.dart';

class MyPopMenuCheckbox extends StatefulWidget {
  final String text;
  final bool value;
  final String? subtext;
  final void Function(bool? it)? onChanged;

  const MyPopMenuCheckbox({
    super.key,
    required this.text,
    required this.value,
    required this.onChanged,
    this.subtext,
  });

  @override
  State<MyPopMenuCheckbox> createState() => MyPopMenuCheckboxState();
}

class MyPopMenuCheckboxState extends State<MyPopMenuCheckbox> {
  bool value = false;

  @override
  void initState() {
    super.initState();
    value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    // 这个是在菜单项的勾选框，若勾选框在左边感觉很别扭，所以勾选框放右边，若有快捷键文字，放到Text下面
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.text),
            if(widget.subtext?.isNotEmpty == true)
              Text(widget.subtext!, style: TextStyle(color: UI.secondaryTextColorInBlackOrWhiteContainer(), fontSize: 12))
          ],
        ),
        Checkbox(
          value: value,
          onChanged: widget.onChanged == null ? null : (it) {
          if(it == null) return;

          widget.onChanged!(it);
          setState(() {
            value = it;
          });
        }),
      ],
    );
  }

}
