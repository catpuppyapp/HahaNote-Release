import 'package:flutter/material.dart';
import 'package:hahanote_app/bean/bean.dart' show LabelValue, MenuItem, ActRegion;
import 'package:hahanote_app/constants/cons.dart' show Cons;
import 'package:hahanote_app/db/db.dart';
import 'package:hahanote_app/db/entity/repo_entity.dart';
import 'package:hahanote_app/ext/state_ext.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/msg/msg.dart' show MsgType, MsgDataConflict, Msg;
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/repo.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/related_oids.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/page/base/searchable_widget_state.dart';
import 'package:hahanote_app/util/hardware_key_util.dart';
import 'package:hahanote_app/util/util.dart' show copyText, formatDateTimeHumanFriendly;
import 'package:hahanote_app/widget/custom_list_view.dart';
import 'package:hahanote_app/widget/dialogs.dart' show Dialogs;
import 'package:path/path.dart' as p;

import '../../hahanote_lib_sync/storage/files/file_path.dart';
import '../../ui/ui.dart';

const _TAG = "conflict_list.dart";


class ConflictListPage extends StatefulWidget {
  final bool showScaffold;
  final void Function(String msg) showMsg;
  final void Function(String msg) showMsgLong;
  final void Function(String relativePath) showInFiles;
  final Future<void> Function<T extends RelatedOids>({
    List<T>? delItemsWhenSync,
    RemoteDataType? remoteDataType,
    required ThrowIfInterrupted? throwIfInterruptedByCaller,
    SyncProgressCb? syncProgressCbByCaller,
  }) doSync;

  const ConflictListPage({
    super.key, 
    required this.showScaffold, 
    required this.showMsg, 
    required this.showMsgLong, 
    required this.showInFiles, 
    required this.doSync
  });

  @override
  State<ConflictListPage> createState() => ConflictListPageState();

}

class ConflictListPageState extends SearchableWidgetState<ConflictListPage> {
  RepoEntity? openedRepo;
  Repo? repo;


  @override
  void initBase() {
    super.showScaffold = widget.showScaffold;
    super.title = t.conflicts;
  }


  Future<void> _view(
    Msg msg, {
    required String path,
    required String? oid,
    String? oidRight
  }) async {
    if(oid == null || oid.isEmpty) {
      showMsgLong("left oid is null or empty");
      return;
    }

    if(repo == null) {
      showMsgLong("repo is null");
      return;
    }

    if(msg.type != MsgType.conflict) {
      showMsgLong("msg type is not conflict");
      return;
    }

    Navigator.pushNamed(
      context,
      Cons.routeViewObject,
      arguments: {"path": path, "oid": oid, "oidRight": oidRight ?? VersionOid.specialOidValueWorkdir}
    );
  }

  Future<void> showDeleteDialog(ActRegion actRegion) async {
    await Dialogs.showOkOrNoDialog(
      context,
      title: actRegion == ActRegion.all ? t.deleteAll : t.delete,
      text: t.areYouSure,
      onOk: () => _doDelete(actRegion)
    );
  }

  Future<void> _doDelete(ActRegion actRegion) async {
    await doAct(
      actName: "delete",
      actDesc: "delete conflicts",
      actRegion: actRegion,
      showMsg: widget.showMsg,
      showMsgLong: widget.showMsgLong,
      getRepo: () async => repo,
      allowRepoIsNull: false,
      getOpenedRepo: () async => null,
      allowOpenedRepoIsNull: true,
      act: (repo, openedRepo, items) async {
        await widget.doSync(
          remoteDataType: RemoteDataType.msg,
          delItemsWhenSync: items.toList().cast<RelatedOids>(),
          // throwIfInterruptedByCaller: () {
          //   if(!mounted) {
          //     // 页面若卸载，取消下载任务，但有可能还是下载成功并且已经移动加密文件到正式 objects 目录了，无法保证
          //     throw AppException("page already disposed, task canceled: delete all conflicts");
          //   }
          // },
          throwIfInterruptedByCaller: null,  // 若想取消，可点取消同步按钮
          // 这里的extra info 是 path
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
    final list = await repo.getConflictMsgs();
    // 时间降序排列
    list.sort((it1, it2) => it2.createTime.utcMs.compareTo(it1.createTime.utcMs));
    items = list;
  }

  @override
  List<Widget> getActions() {
    return [
      // 删除所有的按钮
      IconButton(
        icon: Icon(Icons.delete_sweep),
        tooltip: t.deleteAll,
        onPressed: loading || items.isEmpty ? null : () => showDeleteDialog(ActRegion.all),
      ),
    ];
  }

  String getItemPath(Msg item) {
    return item.data["path"] ?? "";
  }

  @override
  String selectedItemInfoGenerator(dynamic item) {
    return getItemPath((item as Msg))+":${item.oid.shortValue()}";
  }

  @override
  bool isItemSelected(dynamic item) {
    item as Msg;
    return selectedItems.any((it) => item.oid.value == (it as Msg).oid.value);
  }

  @override
  List<Widget> bottomBarChildrenBuilder() {
    return [
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

  bool equals(dynamic it1, dynamic it2) {
    return it1.oid.value == it2.oid.value;
  }

  @override
  Widget itemBuilder(BuildContext context, int index, dynamic item, List items) {
    item as Msg;
    final itemData = MsgDataConflict.fromJson(item.data);
    final remoteOid = itemData.remoteOid;
    final localOid = itemData.localOid;
    final workdirOid = itemData.workdirOid;
    final itemPath = getItemPath(item);
    final filePath = FilePath.fromString(itemPath);
    final parentPath = filePath.parent().toUnixPathStr();
    final resolveStrategyIsWorkdirOverwriteRemote = itemData.resolveStrategy == ConflictResolveStrategy.workdirOverwriteRemote.value;

    void onLongPress() {
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
    }


    VersionOid? getOverwritten() => resolveStrategyIsWorkdirOverwriteRemote ? remoteOid : workdirOid;
    VersionOid? getOverwriter() => resolveStrategyIsWorkdirOverwriteRemote ? workdirOid : remoteOid;


    // 预览被覆盖的版本和覆盖它的版本的区别，
    // 例如，本地workdir覆盖了远程最新节点，则预览 远程最新节点 to workdir 的 changes
    Future<void> compareOverwrittenToOverwriter() async {
      _view(
          item,
          path: itemPath,
          // 被覆盖的版本：
          // 如果冲突覆盖策略是workdir覆盖remote，则remote；
          // 如果冲突策略是remote覆盖workdir，则workdir
          oid: getOverwritten()?.value,

          // 覆盖的版本
          oidRight: getOverwriter()?.value
      );
    }

    return LabelValueTile(
      items: [
        LabelValue(label: t.name, value: filePath.name(), icon: Icons.insert_drive_file, valueFontWeight: FontWeight.bold),
        if(parentPath.isNotEmpty) LabelValue(label: t.path, value: parentPath, icon: Icons.folder_outlined),
        LabelValue(label: t.oid, value: item.oid.shortValue(), icon: Icons.commit),
        LabelValue(label: t.createTime, value: formatDateTimeHumanFriendly(item.createTime.toDateTime()), icon: Icons.access_time_outlined),
        LabelValue(label: t.resolveStrategy, value: itemData.resolveStrategyToText(), icon: Icons.category_outlined),
        LabelValue(label: t.note, value: ConflictResolveStrategy.genWhoOverwriteWho(itemData), icon: Icons.notes),
      ],
      // 选择模式开，则切换选择；选择模式关则预览被覆盖的版本
      onTap: () {
        if(HardwareKeyUtil.isShiftPressed()) {
          onLongPress();
          return;
        }

        if(isSelectionModeOn || HardwareKeyUtil.isCtrlPressed()) {
          setState(() {
            UI.switchSelected(
              item: item,
              selectedItems: selectedItems,
              equals: equals
            );
          });

          return;
        }

        compareOverwrittenToOverwriter();
      },
      selected: isItemSelected(item),
      onLongPress: onLongPress,
      menuItems: [
        if(remoteOid != null)
        MenuItem(
          value: "remote",
          text: t.remote + ": " + remoteOid.shortValue(),
          onClick: () async {
            _view(item, path: itemPath, oid: remoteOid.value);
          },
        ),
        if(localOid != null)
        MenuItem(
          value: "local",
          text: t.local + ": " + localOid.shortValue(),
          onClick: () async {
            _view(item, path: itemPath, oid: localOid.value);
          },
        ),
        if(workdirOid != null)
        MenuItem(
          value: "workdir",
          text: t.workdir + ": " + workdirOid.shortValue(),
          onClick: () async {
            _view(item, path: itemPath, oid: workdirOid.value);
          },
        ),

        // 对比存在覆盖关系的版本：
        // 1. 被覆盖的版本和覆盖它的版本的区别（点击条目时的默认行为，默认是workdir覆盖remote，日后可能提供相反的选项，但没必要，所以大概率不会提供）
        // 2. 冲突发生时，本地files map最新节点oid和workdir版本的区别（若无冲突，workdir将覆盖本地最新节点）
        if((remoteOid != null && workdirOid != null)
            || (localOid != null && workdirOid != null))
        MenuItem.divider,
        if(remoteOid != null && workdirOid != null)
        MenuItem(
          value: "compareOverwrittenToOverwriter",
          // can assert not null due to 上面判断了 remoteOid != null 和 workdirOid != null
          text: t.aToBArrowRight(a: getOverwritten()!.shortValue(), b: getOverwriter()!.shortValue()),
          onClick: () async {
            compareOverwrittenToOverwriter();
          },
        ),
        if(localOid != null && workdirOid != null)
        MenuItem(
          value: "compareLocalToWorkdir",
          text: t.aToBArrowRight(a: localOid.shortValue(), b: workdirOid.shortValue()),
          onClick: () async {
            _view(item, path: itemPath, oid: localOid.value, oidRight: workdirOid.value);
          },
        ),
        MenuItem.divider,
        MenuItem(
          value: "history",
          text: t.history,
          onClick: () async {
            Navigator.pushNamed(
              context,
              Cons.routeFileHistory,
              arguments: {"path": getItemPath(item)},
            );
          },
        ),
        MenuItem(
          value: "show_in_files",
          text: t.showInFiles,
          onClick: () async {
            widget.showInFiles(getItemPath(item));
            // 关弹窗
            // Navigator.pop(context);
          },
        ),
        MenuItem.divider,
        MenuItem(
          value: "copy_file_name",
          text: t.copyFileName,
          onClick: () async {
            copyText(p.basename(getItemPath(item)));
          },
        ),
        MenuItem(
          value: "copy_relative_path",
          text: t.copyRelativePath,
          onClick: () async {
            copyText(getItemPath(item));
          },
        ),
        // MenuItem(
        //   value: "copy_oid",
        //   text: t.copyOid,
        //   onClick: () async {
        //     copyText(item.oid.value);
        //   },
        // ),
      ],
    );
  }

  @override
  Future<bool> searchMatcher(String keyword, dynamic item) async {
    item as Msg;
    final itemData = MsgDataConflict.fromJson(item.data);

    final path = getItemPath(item);
    return path.toString().toLowerCase().contains(keyword) ||
        item.oid.shortValue().toLowerCase().contains(keyword) ||
        item.oid.value == keyword ||  // 可精确匹配完整oid
        formatDateTimeHumanFriendly(item.createTime.toDateTime()).toLowerCase().contains(keyword) ||
        itemData.resolveStrategyToText().toLowerCase().contains(keyword) ||
        ConflictResolveStrategy.genWhoOverwriteWho(itemData).toLowerCase().contains(keyword);
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

