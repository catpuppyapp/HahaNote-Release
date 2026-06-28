import 'dart:io';

import 'package:cloud_disk_note_app/bean/bean.dart' show LabelValue;
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/my_http_overrides.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:cloud_disk_note_app/page/base/searchable_page_state.dart';
import 'package:cloud_disk_note_app/util/fs.dart' show Fs;
import 'package:cloud_disk_note_app/widget/dialogs.dart';
import 'package:cloud_disk_note_app/widget/list.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

const _TAG = "tls_cert_manage.dart";


class TlsCertManage extends StatefulWidget {
  // 文件在仓库下的相对路径

  const TlsCertManage({super.key});

  @override
  State<TlsCertManage> createState() => _TlsCertManageState();

}

class _TlsCertManageState extends SearchablePageState<TlsCertManage> {
  TextEditingController importPath = TextEditingController(text: "");
  String tlsCertDirPath = "";

  @override
  void dispose() {
    importPath.dispose();

    // 离开此页面时，reload证书
    MyHttpOverrides.init();

    super.dispose();
  }

  Future<void> _delete(String path) async {
    if(!mounted) return;

    try {
      await File(path).delete();
      items.remove(path);
      searchedItems.remove(path);
      refreshUI();
      showMsg(t.success);
    }catch(e) {
      showMsgLong("delete cert err: $e");
    }
  }

  Future<void> _import() async {
    // 执行完后，path会存到 pathController 里
    await Dialogs.choosePathDialog(
      context,
      title: t.import,
      pathController: importPath,
      textFiledLabel: t.path,
      showMsg: showMsg,
      showMsgLong: showMsgLong,
      refreshUI: refreshUI,
      trueDirFalseFile: false,
      trueExistErrFalseNoExistErrNullNoCheckExist: false,
      errIfPathEmpty: true,
      errIfPathNotAbsOrInvalid: true,
      errIfCallerConsideredPathInvalid: null,
      showFileChooserButton: true,
      onOk: (filePath) async {
        if(filePath.isEmpty) {
          return;
        }

        final fileName = p.basename(filePath);

        final savePath = File(p.join(await Fs.getUserTlsCertDirPath(), fileName));

        Future<void> save() async {
          try {
            await File(filePath).copy(savePath.absolute.path);
            showMsg(t.success);
            loadItems();
          }catch(e) {
            showMsgLong("import cert err: $e");
          }
        }

        if(await savePath.exists()) {
          if(!mounted) return;

          Dialogs.showOkOrNoDialog(
            context,
            title: t.overwrite,
            text: t.fileAlreadyExistsOverwriteAsk,
            onOk: () {
              // 就一句，没"then"，await与否无意义
              save();
            }
          );
        }else {
          await save();
        }
      }
    );
  }


  Future<void> _deleteAll() async {
    if(!mounted) return;
    final items = getActuallyList();
    bool neverShowErr = true;
    for (final path in items) {
      try {
        await File(path).delete();
      } catch (e) {
        // 只显示一次错误，避免删除多个文件出错导致msg刷屏
        if (neverShowErr) {
          neverShowErr = false;
          showMsgLong("delete cert err: $e");
        }
      }
    }

    items.clear();
    showMsg(t.done);
    await loadItems();
  }

  @override
  Future<void> doLoadItems() async {
    await for(final fileEntity in Directory(await Fs.getUserTlsCertDirPath()).list(recursive: true, followLinks: false)) {
      if(fileEntity is! File) {
        continue;
      }

      items.add(fileEntity.absolute.path);
    }
  }

  @override
  List<Widget> getActions() {
    return [
      IconButton(
        icon: Icon(Icons.refresh),
        tooltip: t.refresh,
        onPressed: () {
          loadItems();
        },
      ),
      IconButton(
        icon: Icon(Icons.delete_sweep),
        tooltip: t.deleteAll,
        onPressed: () {
          Dialogs.showOkOrNoDialog(
            context,
            title: t.deleteAll,
            text: t.areYouSure,
            onOk: () {
              _deleteAll();
            },
          );
        },
      ),
      IconButton(
        icon: Icon(Icons.download),
        tooltip: t.import,
        onPressed: () {
          _import();
        },
      )
    ];
  }

  @override
  void initBase() {
    super.title = t.tlsCerts;

    () async {
      tlsCertDirPath = await Fs.getUserTlsCertDirPath();
      setState(() {});
    }();
  }

  @override
  List<Widget> underSearchBarAboveListChildren() {
    return defaultUnderSearchBarAboveListChildren(tlsCertDirPath);
  }
  
  @override
  Widget itemBuilder<T>(BuildContext context, int index, T item) {
    item as String;

    return LabelValueTile(
      textCopiable: false, // avoid file name too long, cannot click to delete item
      items: [
        LabelValue(label: t.name, value: p.basename(item), icon: Icons.insert_drive_file),
      ],
      onTap: () {
        Dialogs.showOkOrNoDialog(
          context,
          title: t.delete,
          text: t.areYouSure,
          onOk: () {
            _delete(item);
          }
        );
      },
      menuItems: [],
    );
  }

  @override
  Future<bool> searchMatcher(String keyword, dynamic item) async {
    return p.basename(item).toLowerCase().contains(keyword);
  }

}

