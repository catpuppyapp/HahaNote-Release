import 'package:cloud_disk_note_app/bean/bean.dart' show LabelValue, MenuItem;
import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/repo.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/sync.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/sync_history.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:cloud_disk_note_app/page/base/searchable_page_state.dart';
import 'package:cloud_disk_note_app/util/util.dart' show formatDateTimeHumanFriendly;
import 'package:cloud_disk_note_app/widget/custom_list_view.dart';
import 'package:cloud_disk_note_app/widget/dialogs.dart';
import 'package:flutter/material.dart';

const _TAG = "sync_history.dart";


class SyncHistoryPage extends StatefulWidget {
  // 文件在仓库下的相对路径
  final String repoPath;

  const SyncHistoryPage({super.key, required this.repoPath});

  @override
  State<SyncHistoryPage> createState() => _SyncHistoryPageState();

}

class _SyncHistoryPageState extends SearchablePageState<SyncHistoryPage> {
  late final String repoPath;
  String currentClientId = '';
  final exportPath = TextEditingController(text: "");

  @override
  void disposeSub() {
    exportPath.dispose();
  }

  @override
  Future<void> doLoadItems() async {
    final repo = await Repo.fromRepoPath(repoPath);
    final syncHistory = await repo.getSyncHistory();
    if(syncHistory == null) {
      throw AppException("Sync history of repo is null");
    }

    // 代表当前设备的id，会在历史记录加粗显示
    // 由于client.name可修改，所以若用户改了可能匹配不上，但id不可修改，
    // 所以若用id匹配，即使用户改过client name，也可通过id匹配并高亮当前设备
    currentClientId = repo.client.id;

    // 按创建时间倒序输出，直接倒序列表即可
    items = syncHistory.history.reversed.toList();
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
      )
    ];
  }

  @override
  void initBase() {
    repoPath = widget.repoPath;
    super.title = t.history;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      requireLogin();
    });
  }

  @override
  Widget itemBuilder<T>(BuildContext context, int index, T item) {
    item as SyncHistoryNode;

    return LabelValueTile(
      items: [
        LabelValue(label: t.type, value: item.typeString(), icon: Icons.category_outlined),
        LabelValue(label: t.oid, value: item.oid.shortValue(), icon: Icons.commit),
        LabelValue(label: t.state, value: item.stateString(), icon: Icons.task_alt),
        LabelValue(label: t.createTime, value: formatDateTimeHumanFriendly(item.createTime.toDateTime()), icon: Icons.access_time_outlined),
        LabelValue(label: t.client, value: item.client.name, icon: Icons.devices, valueFontWeight: item.client.id == currentClientId ? FontWeight.bold : null),
        LabelValue(label: t.brief, value: item.resultBrief(), icon: Icons.notes_outlined),
      ],
      onTap: () {
        Dialogs.showOkOrNoDialog(
          context,
          title: item.oid.shortValue(),
          text: item.resultString(),
          showCancel: false,
          onOk: () {}
        );
      },
      menuItems: [
        MenuItem(
          value: "export",
          text: t.export,
          onClick: () async {
            await Dialogs.choosePathDialog(
              context,
              title: t.export,
              pathController: exportPath,
              textFiledLabel: t.path,
              showMsg: showMsg,
              showMsgLong: showMsgLong,
              refreshUI: refreshUI,
              trueDirFalseFile: true,
              trueExistErrFalseNoExistErrNullNoCheckExist: true,
              errIfPathEmpty: true,
              errIfPathNotAbsOrInvalid: true,
              errIfCallerConsideredPathInvalid: null,
              showFileChooserButton: true,
              contentOnTopOfPathChooser: Column(
                children: [
                  SelectableText(t.exportFilesFromNodeNote),
                  const SizedBox(height: 10),
                  SelectableText(t.cannotExportPermanentlyDeletedFilesNote),
                  const SizedBox(height: 30),
                ],
              ),
              onOk: (filePath) async {
                if(filePath.isEmpty) {
                  return;
                }

                bool taskCanceled = false;

                void throwIfInterrupted() {
                  if(taskCanceled || !mounted) {
                    throw TaskCanceledException();
                  }
                }

                String errMsg = "";
                ValueNotifier<String> loadingTextNotifier = ValueNotifier(t.loading);
                Dialogs.showLoadingDialog(
                  context,
                  loadingTextNotifier: loadingTextNotifier,
                  onCancel: () async {
                    taskCanceled = true;
                    loadingTextNotifier.value = t.canceling;
                  }
                );

                try {
                  final repo = await Repo.open(repoPath);
                  final fails = await repo.exportFilesOfHistoryNode(
                    historyNodeOid: item.oid,
                    exportPath: filePath,
                    throwIfInterrupted: throwIfInterrupted,
                    progressCb: (String act, int allCount, int currentAt, String relativePath) {
                      String actText = genSyncProgressText(act, allCount, currentAt, relativePath);
                      loadingTextNotifier.value = actText;
                    },
                  );

                  if(fails.isEmpty) {
                    showMsg(t.success+": $filePath");
                  }else {
                    final sb = StringBuffer("some files may not be exported:\n\n");
                    for(final f in fails) {
                      sb.write(f.toString());
                      sb.write("\n\n");
                    }

                    errMsg = sb.toString();
                  }
                }catch(e, st) {
                  App.logger.debug(_TAG, "export files of history node '${item.oid}' err: $e\n$st");
                  errMsg = e.toString();
                }finally {
                  if(context.mounted) {
                    await Dialogs.closeLoadingDialog(context);
                  }
                }

                // 有导出失败的条目，显示
                if(errMsg.isNotEmpty) {
                  if(context.mounted) {
                    Dialogs.showCopyDialog(
                      context,
                      title: t.error,
                      text: errMsg,
                      showMsg: showMsg
                    );
                  }
                }
              }
            );
          },
        ),
      ],
    );
  }

  @override
  Future<bool> searchMatcher(String keyword, dynamic item) async {
    item as SyncHistoryNode;

    return item.typeString().toLowerCase().contains(keyword) ||
        item.stateString().toLowerCase().contains(keyword) ||
        item.client.name.toLowerCase().contains(keyword) ||
        item.oid.shortValue().toLowerCase().contains(keyword) ||
        item.oid.value == keyword ||  // 可精确匹配完整oid
        formatDateTimeHumanFriendly(item.createTime.toDateTime()).toLowerCase().contains(keyword) ||
        item.resultBrief().toLowerCase().contains(keyword);
  }

}

