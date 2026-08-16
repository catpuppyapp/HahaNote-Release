import 'package:flutter/material.dart';
import 'package:hahanote_app/native_util/storage_util.dart';
import 'package:hahanote_app/util/app_info.dart';
import 'package:hahanote_app/widget/clickable_text.dart';

import '../i18n/strings.g.dart';
import 'dialogs.dart';
import 'icon_buttons.dart';

const _TAG = "app_storages.dart";
const _defaultReposParentName = "haha_repos";

class AppStorages extends StatefulWidget {
  final void Function(String)? onPathClick;
  final TextEditingController? textController;
  final void Function(String) showMsg;

  /// if is true, will append [_defaultReposParentName] to the storage path
  final bool isRepoStorage;

  const AppStorages({
    super.key,
    this.onPathClick,
    this.textController,
    required this.showMsg,
    this.isRepoStorage = true,
  });

  @override
  State<AppStorages> createState() => AppStoragesState();

}

class AppStoragesState extends State<AppStorages> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          flex: 8,
          child: Wrap(
            runSpacing: 8,
            children: [
              for(final (idx, path) in AppInfo.storagePaths.indexed) ClickableTextWidget(
                clickableText: StorageUtil.getStoragePathNameByIdx(idx)+", ",
                onTapClickable: () {
                  // 如果是存储仓库的路径，追加上默认的仓库父文件夹名
                  final path2 = widget.isRepoStorage ? "$path/$_defaultReposParentName" : path;
                  if(widget.onPathClick == null) {
                    if(widget.textController != null) {
                      widget.textController!.text = path2;
                      widget.textController!.selection = TextSelection(baseOffset: path2.length, extentOffset: path2.length);
                    }
                  }else {
                    widget.onPathClick!(path2);
                  }
                },
              )
            ],
          ),
        ),

        InlineIconButton(
            onPressed: () {
              Dialogs.showCopyDialog(
                context,
                title: t.info,
                text: t.storagePathsDesc,
                showMsg: widget.showMsg
              );
            },
            icon: Icon(Icons.help)
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: content,
    );
  }
}
