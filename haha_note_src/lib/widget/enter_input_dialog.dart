import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:flutter/material.dart';

/// 可复用的弹窗组件：按回车提交并关闭弹窗
class EnterInputDialog extends StatefulWidget {
  final String title;
  final String hintText;
  final String? initialValue;
  final void Function(String) showMsg;
  final void Function(String) showMsgLong;
  final List<String>? notes;
  final bool initSelectAll;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;

  const EnterInputDialog({
    super.key,
    required this.title,
    required this.hintText,
    this.initialValue, 
    required this.showMsg, 
    required this.showMsgLong,
    this.notes,
    this.initSelectAll = true,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = true,
  });

  @override
  State<EnterInputDialog> createState() => _EnterInputDialogState();
}

class _EnterInputDialogState extends State<EnterInputDialog> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    if(widget.initSelectAll && _controller.text.isNotEmpty) {
      _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    }

    // 自动聚焦输入框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    // 可在此加入验证，若无效则不关闭弹窗
    if (text.isEmpty) {
      // 示例：不允许空提交，聚焦并返回
      widget.showMsg(t.pleaseInput);
      _focusNode.requestFocus();
      return;
    }
    Navigator.of(context).pop(text); // 关闭弹窗并返回输入内容
  }

  List<Widget> getNotesWidgets() {
    final notes = widget.notes;
    final List<Widget> notesWidgets = [];
    if(notes != null && notes.isNotEmpty) {
      for(final n in notes) {
        notesWidgets.add(
            Row(
              children: [
                const SizedBox(height: 50),
                Expanded(child: SelectableText(n)),
              ],
            )
        );
      }
    }

    return notesWidgets;
  }

  @override
  Widget build(BuildContext context) {
    final notesWidgets = getNotesWidgets();

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        // width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              decoration: InputDecoration(hintText: widget.hintText),
              textInputAction: widget.textInputAction,
              keyboardType: widget.keyboardType,
              onSubmitted: (_) => _submit(), // 按回车后触发提交
            ),

            if(notesWidgets.isNotEmpty)
              Flexible(
                fit: FlexFit.loose,  // 使widget占据内容宽度和高度，不过分扩展
                child: SingleChildScrollView(
                  child: Column(
                    children: notesWidgets,
                  ),
                )
              )

          ],
        )
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(t.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(t.ok)),
      ],
    );
  }
}
