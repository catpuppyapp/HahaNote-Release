import 'package:flutter/material.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
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
  /// remote path to get the default name of the path,
  /// it will append the name of remote path to the storage path (local path),
  /// e.g. while creating a repo, remote path is "/some_path/my_repo",
  /// then the local path can be: /storage/emulated/0/haha_repos/my_repo
  final String Function()? remotePath;

  /// if is true, will append [_defaultReposParentName] to the storage path
  final bool isRepoStorage;

  const AppStorages({
    super.key,
    this.onPathClick,
    this.textController,
    required this.showMsg,
    this.isRepoStorage = true,
    this.remotePath,
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
                  final pathPrefix = widget.isRepoStorage ? "$path/$_defaultReposParentName" : path;
                  final path2 = pathPrefix + (widget.remotePath == null ? "" : "/${FilePath.fromString(widget.remotePath!()).name()}");
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
