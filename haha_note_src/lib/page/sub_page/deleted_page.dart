import 'package:hahanote_app/bean/bean.dart' show LabelValue, ActRegion, MenuItem;
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_info.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/repo.dart' show Repo;
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/related_oids.dart';
import 'package:hahanote_app/constants/cons.dart' show Cons;
import 'package:hahanote_app/db/db.dart';
import 'package:hahanote_app/db/entity/repo_entity.dart';
import 'package:hahanote_app/ext/state_ext.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/page/base/searchable_widget_state.dart';
import 'package:hahanote_app/util/fs.dart';
import 'package:hahanote_app/util/util.dart' show formatDateTimeHumanFriendly, copyText;
import 'package:hahanote_app/widget/custom_list_view.dart';
import 'package:hahanote_app/widget/dialogs.dart' show Dialogs;
import 'package:flutter/material.dart';

import '../../hahanote_lib_sync/storage/files/file_path.dart';
import '../../ui/ui.dart';


const _TAG = "deleted_page.dart";

class DeletedPage extends StatefulWidget {
  final bool showScaffold;
  final void Function(String msg) showMsg;
  final void Function(String msg) showMsgLong;
  final Future<void> Function<T extends RelatedOids>({
    List<T>? delItemsWhenSync,
    RemoteDataType? remoteDataType,
    required ThrowIfInterrupted? throwIfInterruptedByCaller,
    SyncProgressCb? syncProgressCbByCaller,
  }) doSync;

  const DeletedPage({super.key, required this.showScaffold, required this.showMsg, required this.showMsgLong, required this.doSync});

  @override
  State<DeletedPage> createState() => DeletedPageState();

}

class DeletedPageState extends SearchableWidgetState<DeletedPage> {
  RepoEntity? openedRepo;
  Repo? repo;

  Future<void> _view(FileInfo item) async {
    if(!mounted) return;

    final oid = item.lastNode()?.oid;
    if(oid == null) {
      // 已删除条目上的oid不应该为null，都没创建过怎么删除？所以这里不应该被执行到
      widget.showMsg("oid of last node is null");
      return;
    }

    Navigator.pushNamed(
      context,
      Cons.routeViewObject,
      // 解密过的obj的2进制文件
      arguments: {"path": item.path, "oid": oid.value}
    );
  }



  Future<void> showRestoreDialog(ActRegion actRegion) async {
    final isAll = actRegion == ActRegion.all;
    await Dialogs.showOkOrNoDialog(
      context,
      title: isAll ? t.restoreAll : t.restore,
      text: isAll ? t.restoreAllAsk : t.restoreSelectedAsk,
      onOk: () => _doRestore(actRegion)
    );
  }


  Future<void> _doRestore(ActRegion actRegion) async {
    await doAct(
      actName: "restore",
      actDesc: "restore deleted files",
      actRegion: actRegion,
      showMsg: widget.showMsg,
      showMsgLong: widget.showMsgLong,
      getRepo: () async => repo,
      allowRepoIsNull: false,
      getOpenedRepo: () async => null,
      allowOpenedRepoIsNull: true,
      act: (repo, openedRepo, items) async {
        // 恢复文件
        await repo!.restoreDeletedFileInfo(
          items.toList().cast<FileInfo>(),
          progressCb: (act, allCount, currentAt, extraInfo) => setStateSafe(() {
            progressText = genSyncProgressText(act, allCount, currentAt, extraInfo);
          }),
          throwIfInterrupted: () {
            if(!mounted) {
              // 这里恢复的都是本地工作目录没有的文件，所以顶多多些文件，不会少，就算恢复了也没事
              // 用户离开页面了，提示用户恢复已取消
              throw t.restoreCanceledNote;
            }
          },
        );

        // 执行同步，然后回收站应该就空了
        await widget.doSync(
          // throwIfInterruptedByCaller: () {
          //   if(!mounted) {
          //     throw AppException("page already disposed, task canceled(step 2, sync): restore all deleted files (maybe some files already restored to workdir)");
          //   }
          // },
          throwIfInterruptedByCaller: null,
          syncProgressCbByCaller: (act, allCount, currentAt, extraInfo) => setStateSafe(() {
            progressText = genSyncProgressText(act, allCount, currentAt, extraInfo);
          })
        );
      },
    );
  }

  Future<void> showDeleteDialog(ActRegion actRegion) async {
    await Dialogs.showOkOrNoDialog(
      context,
      title: actRegion == ActRegion.all ? t.deleteAll : t.delete,
      text: t.permanentlyDeleteFilesAsk,
      onOk: () => _doDelete(actRegion)
    );
  }

  Future<void> _doDelete(ActRegion actRegion) async {
    await doAct(
      actName: "delete",
      actDesc: "delete items",
      actRegion: actRegion,
      showMsg: widget.showMsg,
      showMsgLong: widget.showMsgLong,
      getRepo: () async => repo,
      allowRepoIsNull: false,
      getOpenedRepo: () async => null,
      allowOpenedRepoIsNull: true,
      act: (repo, openedRepo, items) async {
        await widget.doSync(
          remoteDataType: RemoteDataType.files,
          delItemsWhenSync: items.toList().cast<RelatedOids>(),
          // 离开页面没必要取消同步
          // throwIfInterruptedByCaller: () {
          //   if(!mounted) {
          //     throw AppException("page already disposed, task canceled: clear deleted files");
          //   }
          // },
          throwIfInterruptedByCaller: null,
          syncProgressCbByCaller: (act, allCount, currentAt, extraInfo) => setStateSafe(() {
            progressText = genSyncProgressText(act, allCount, currentAt, extraInfo);
          })
        );
      }
    );
  }


  @override
  Future<void> doLoadItems() async {
    final repoFromDb = await Db.getOpenedRepo();
    openedRepo = repoFromDb;
    if(repoFromDb == null) {
      setStateSafe(() {
        err = "Opened repo is null";
      });
      return;
    }

    final repo = await Repo.open(repoFromDb.path);
    this.repo = repo;
    final list = await repo.getDeletedFiles();
    // 删除时间降序排列
    list.sort((it1, it2) => it2.getLatestVersion().createTime.utcMs.compareTo(it1.getLatestVersion().createTime.utcMs));
    items = list;

  }

  @override
  List<Widget> getActions() {
    return [
      IconButton(
        icon: Icon(Icons.restore),
        tooltip: t.restoreAll,
        onPressed: loading || items.isEmpty ? null : () => showRestoreDialog(ActRegion.all),
      ),
      // 删除所有的按钮
      IconButton(
        icon: Icon(Icons.delete_sweep),
        tooltip: t.deleteAll,
        onPressed: loading || items.isEmpty ? null : () => showDeleteDialog(ActRegion.all),
      ),
    ];
  }

  @override
  void initBase() {
    super.showScaffold = widget.showScaffold;
    super.title = t.deleted;
  }


  @override
  String selectedItemInfoGenerator(dynamic item) {
    return (item as FileInfo).path;
  }

  @override
  bool isItemSelected(dynamic item) {
    item as FileInfo;
    return selectedItems.any((it) => item.path == (it as FileInfo).path);
  }

  @override
  List<Widget> bottomBarChildrenBuilder() {
    return [
      IconButton(
        icon: Icon(Icons.restore),
        tooltip: t.restore,
        onPressed: loading || selectedItems.isEmpty ? null : () async {
          await showRestoreDialog(ActRegion.selected);
        },
      ),
      IconButton(
        icon: Icon(Icons.delete),
        tooltip: t.delete,
        onPressed: loading || selectedItems.isEmpty ? null : () async {
          await showDeleteDialog(ActRegion.selected);
        },
      ),
      getSelectAllButton(),
      getQuitSelectionButton(),
    ];
  }


  void _history(FileInfo item) {
    if(!mounted) return;

    Navigator.pushNamed(
      context,
      Cons.routeFileHistory,
      arguments: {"path": item.path},
    );
  }

  bool equals(dynamic it1, dynamic it2) {
    return it1.path == it2.path;
  }

  @override
  Widget itemBuilder<T>(BuildContext context, int index, T item) {
    item as FileInfo;

    final lastNode = item.lastNode();
    final curNode = item.curNode(); // 用来取删除时间

    final filePath = FilePath.fromString(item.path);
    final parentPath = filePath.parent().toUnixPathStr();

    return LabelValueTile(
      items: [
        LabelValue(label: t.name, value: filePath.name(), icon: Icons.insert_drive_file, valueFontWeight: FontWeight.bold),
        if(parentPath.isNotEmpty) LabelValue(label: t.path, value: parentPath, icon: Icons.folder_outlined),
        LabelValue(label: t.size, value: Fs.readableSize(lastNode?.fileSizeInBytes ?? 0), icon: Icons.sd_card_outlined),
        LabelValue(label: t.oid, value: lastNode?.oid.shortValue() ?? '', icon: Icons.commit),
        LabelValue(
            label: t.createTime,
            value: formatDateTimeHumanFriendly(curNode.createTime.toDateTime()),
            icon: Icons.access_time_outlined
        ),
      ],
      onTap: isSelectionModeOn ? () => setState(() {
        UI.switchSelected(
          item: item,
          selectedItems: selectedItems,
          equals: equals
        );
      }) : () => _view(item),
      selected: isItemSelected(item),
      onLongPress: () {
        setState(() {
          UI.switchSelectSpan(
            itemIdxOfItemList: index,
            item: item,
            selectedItems: selectedItems,
            itemList: getActuallyList(),
            equals: equals,
            switchItemSelected: (it) => UI.switchSelected(
              item: it,
              selectedItems: selectedItems,
              equals: equals
            ),
            selectIfNotInSelectedListElseNoop: (it) => UI.selectIfNotInSelectedListElseNoop(
              item: it,
              selectedItems: selectedItems,
              equals: equals
            )
          );
        });
      },
      menuItems: [
        MenuItem(
          value: "history",
          text: t.history,
          onClick: () async {
            _history(item);
          },
        ),
        MenuItem(
          value: "copy_path",
          text: t.copyPath,
          onClick: () async {
            copyText(item.path);
          },
        ),
      ],
    );
  }

  @override
  Future<bool> searchMatcher(String keyword, dynamic item) async {
    item as FileInfo;
    final lastNode = item.lastNode();  // 显示和预览的是删除节点之前的节点的oid
    final curNode = item.curNode();  // 最新节点必然是已删除，所以用这个取删除时间
    return item.path.toLowerCase().contains(keyword) ||
        lastNode?.oid.shortValue().toLowerCase().contains(keyword) == true ||
        lastNode?.oid.value == keyword ||  // 可精确匹配完整oid
        Fs.readableSize(lastNode?.fileSizeInBytes ?? 0).toLowerCase().contains(keyword) ||
        formatDateTimeHumanFriendly(curNode.createTime.toDateTime()).toLowerCase().contains(keyword);

  }

  @override
  void showMsg(String msg) {
    widget.showMsg(msg);
  }

  @override
  void showMsgLong(String msg) {
    widget.showMsgLong(msg);
  }

}

