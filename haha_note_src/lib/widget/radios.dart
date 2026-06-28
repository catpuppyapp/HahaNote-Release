import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/remote.dart';
import 'package:cloud_disk_note_app/widget/sort_dialog.dart';
import 'package:flutter/material.dart';

/// Flutter code sample for [Radio].


class SelectionItem {
  // for find item
  String key;
  // visible
  String text;
  // item
  dynamic item;

  SelectionItem({required this.key, required this.text, required this.item});

  static SelectionItem empty() {
    return SelectionItem(key: "", text: "", item: "");
  }

  static Future<List<SelectionItem>> toSelectionList(
    List<dynamic> src,
    Future<SelectionItem> Function(dynamic) transform
  ) async {
    final result = <SelectionItem>[];
    for(final i in src) {
      result.add(await transform(i));
    }

    return result;
  }

  static SelectionItem fromRemoteType(RemoteType it) {
    return SelectionItem(key: it.value, text: it.toText(), item: it);
  }

  static SelectionItem fromSortBy(SortBy it) {
    return SelectionItem(key: it.value, text: it.getText(), item: it);
  }

  @override
  String toString() {
    return text;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SelectionItem && runtimeType == other.runtimeType &&
              key == other.key;

  @override
  int get hashCode => key.hashCode;


}

class RadiosWidget extends StatefulWidget {
  final List<SelectionItem> selections;
  final SelectionItem defaultSelected;
  final Function(SelectionItem newValue) onChange;

  const RadiosWidget({
    super.key,
    required this.selections,
    required this.defaultSelected,
    required this.onChange
  });

  @override
  State<RadiosWidget> createState() => _RadiosWidgetState();
}

class _RadiosWidgetState extends State<RadiosWidget> {
  late SelectionItem selected = widget.defaultSelected;


  @override
  void initState() {
    super.initState();
  }

  void _onClick(SelectionItem? value) {
    if(value == null) return;

    setState(() {
      selected = value;
    });

    widget.onChange(value);

  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for(final i in widget.selections) {
      final item = ListTile(
        title: Text(i.text),
        leading: Radio<SelectionItem>(value: i),
        onTap: () {
          _onClick(i);
        },
      );

      children.add(item);
    }

    return RadioGroup<SelectionItem>(
      groupValue: selected,
      onChanged: _onClick,
      child: Column(
        children: children,
      ),
    );
  }
}
