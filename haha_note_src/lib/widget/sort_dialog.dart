import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart';
import 'package:cloud_disk_note_app/db/db.dart' show Db;
import 'package:cloud_disk_note_app/i18n/strings.g.dart' show t;
import 'package:cloud_disk_note_app/widget/radios.dart' show RadiosWidget, SelectionItem;
import 'package:flutter/material.dart';

import '../ui/ui.dart';

part 'sort_dialog.g.dart';

const _TAG = "sort_dialog.dart";

// 如果不用字符串，做单选按钮的key时，还要处理，麻烦
const _sortByName = "1";

@myJsonSerializable
class SortBy {
  final String value;

  SortBy({this.value = _sortByName});


  factory SortBy.fromJson(Map<String, dynamic> json) => _$SortByFromJson(json);

  Map<String, dynamic> toJson() => _$SortByToJson(this);


  static final name = SortBy(value: _sortByName);
  static final type = SortBy(value: "2");
  static final size = SortBy(value: "3");
  static final lastModifiedTime = SortBy(value: "4");

  static final values = [name, type, size, lastModifiedTime];

  static Future<List<SelectionItem>> toSelectionList() async {
    return await SelectionItem.toSelectionList(SortBy.values, (it) async {
      return SelectionItem.fromSortBy(it);
    });
  }

  String getText() {
    if(value == name.value) {
      return t.name;
    }

    if(value == type.value) {
      return t.type;
    }

    if(value == size.value) {
      return t.size;
    }

    if(value == lastModifiedTime.value) {
      return t.lastModifiedTime;
    }

    return '';
  }

  @override
  String toString() {
    return value;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SortBy && runtimeType == other.runtimeType &&
              value == other.value;

  @override
  int get hashCode => value.hashCode;


}

@myJsonSerializable
class SortRule {
  SortBy sortBy;
  bool ascending;
  bool foldersFirst;
  bool applyToThisFolderOnly;

  SortRule({
    SortBy? sortBy,
    this.ascending = true,
    this.foldersFirst = true,
    this.applyToThisFolderOnly = false,
  }) : sortBy = sortBy ?? SortBy.name;


  factory SortRule.fromJson(Map<String, dynamic> json) => _$SortRuleFromJson(json);

  Map<String, dynamic> toJson() => _$SortRuleToJson(this);


  static final defaultValue = SortRule();


  @override
  String toString() {
    return 'SortBy: $sortBy, ascending: $ascending, foldersFirst: $foldersFirst, applyToThisFolderOnly: $applyToThisFolderOnly';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SortRule && runtimeType == other.runtimeType &&
              sortBy == other.sortBy && ascending == other.ascending &&
              foldersFirst == other.foldersFirst &&
              applyToThisFolderOnly == other.applyToThisFolderOnly;

  @override
  int get hashCode =>
      Object.hash(sortBy, ascending, foldersFirst, applyToThisFolderOnly);


}

class _SortDialog extends StatefulWidget {
  final String path;
  final void Function(String) showMsg;
  final void Function(String) showMsgLong;

  const _SortDialog({
    this.path = '',
    required this.showMsg,
    required this.showMsgLong,
  });

  @override
  State<_SortDialog> createState() => _SortDialogState();
}

class _SortDialogState extends State<_SortDialog> {
  SortRule sortRule = SortRule.defaultValue;
  SelectionItem selectedItem = SelectionItem.fromSortBy(SortBy.name);
  var selectionList = <SelectionItem>[];
  bool reloading = false;
  bool loadingSelectionList = true;
  String err = "";

  @override
  void initState() {
    super.initState();

    doInit();
  }

  Future<void> doInit() async {
    if(reloading) {
      return;
    }

    reloading = true;

    setState(() {
      loadingSelectionList = true;
    });

    try {
      final newSelectionList = await SortBy.toSelectionList();
      setState(() {
        selectionList = newSelectionList;
      });

      sortRule = await Db.getSortByPath(widget.path);
      selectedItem = SelectionItem.fromSortBy(sortRule.sortBy);
      App.logger.debug(_TAG, "selectedItem: ${selectedItem.item}");
    }catch(e, st) {
      err = "err: $e";
      App.logger.debug(_TAG, "doInit err: $e\n$st");
    }finally {
      setState(() {
        reloading = false;
        loadingSelectionList =  false;
      });
    }
  }
  void _onConfirm() {
    sortRule.sortBy = SortBy(value: selectedItem.key);
    Navigator.of(context).pop(sortRule);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.sort),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: err.isNotEmpty ? [SelectableText(err, style: TextStyle(color: UI.getColorErr()))] : [
            if(!loadingSelectionList)
            RadiosWidget(
              selections: selectionList,
              defaultSelected: selectedItem,
              onChange: (newValue) {
                setState(() {
                  selectedItem = newValue;
                });
              },
            ),
            const Divider(),
            // Checkboxes (ascending, folders first)
            CheckboxListTile(
              controlAffinity: UI.myCheckBoxControlAffinity,
              title: Text(t.ascending),
              value: sortRule.ascending,
              onChanged: (v) {
                setState(() {
                  sortRule.ascending = v ?? true;
                });
              },
            ),
            CheckboxListTile(
              controlAffinity: UI.myCheckBoxControlAffinity,
              title: Text(t.folderFirst),
              value: sortRule.foldersFirst,
              onChanged: (v) {
                setState(() {
                  sortRule.foldersFirst = v ?? true;
                });
              },
            ),
            const Divider(),
            CheckboxListTile(
              controlAffinity: UI.myCheckBoxControlAffinity,
              title: Text(t.applyToThisFolderOnly),
              value: sortRule.applyToThisFolderOnly,
              onChanged: (v) {
                setState(() {
                  sortRule.applyToThisFolderOnly = v ?? false;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: _onConfirm,
          child: Text(t.ok),
        ),
      ],
    );
  }
}


Future<void> showSortDialog(
  BuildContext context, {
  required String path,
  required void Function(String) showMsg,
  required void Function(String) showMsgLong,
  required void Function(SortRule) onOk
}) async {
  final sortRule = await showDialog<SortRule>(
    context: context,
    builder: (context) {
      return _SortDialog(
        path: path,
        showMsg: showMsg,
        showMsgLong: showMsgLong,
      );
    },
  );

  if(sortRule == null) {
    return;
  }

  App.logger.debug(_TAG, "sortRule: $sortRule");

  onOk(sortRule);

}
