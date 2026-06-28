import 'package:cloud_disk_note_app/bean/bean.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:flutter/material.dart';

import '../ui/ui.dart';

class CheckboxDialog extends StatefulWidget {
  final String title;
  final List<TextValueSelected> options;
  const CheckboxDialog({super.key, required this.title, required this.options});

  @override
  State<CheckboxDialog> createState() => _CheckboxDialogState();
}

class _CheckboxDialogState extends State<CheckboxDialog> {
  final Map<String, TextValueSelected> optionsBuf = {};

  @override
  void initState() {
    super.initState();

    for(final item in widget.options) {
      optionsBuf[item.value] = item;
    }
  }

  bool hasSelectedAny() {
    for(final item in optionsBuf.values) {
      if(item.selected) {
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for(final item in optionsBuf.values.toList())  // toList() ，拷贝集合，避免并发修改异常
              Column(
                // 让文本左对齐
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    value: item.selected,
                    onChanged: (v) => setState(
                      () => optionsBuf[item.value] = item.copy(selected: v),
                    ), // v有可能为null，若是，使用原来的值（若使用时感觉不对，可改成 v ?? false）
                    title: Text(item.text),
                    // leading 勾选框在左，否则在右，不设置默认在右
                    controlAffinity: UI.myCheckBoxControlAffinity,
                  ),
                  if(item.desc.isNotEmpty)
                    Padding(
                      padding: UI.defaultCheckboxDescPadding,
                      child: SelectableText(item.desc, style: UI.subTitleTextStyle),
                    ),
                ],
              ),
          ],
        )
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null), // 取消返回 null
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: hasSelectedAny() ? () => Navigator.of(context).pop(optionsBuf) : null,
          child: Text(t.ok),
        ),
      ],
    );
  }
}
