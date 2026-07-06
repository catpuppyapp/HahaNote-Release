import 'dart:io';

import 'package:hahanote_app/bean/bean.dart' show LabelValue, MenuItem;
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/repo.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/status_item.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/native_util/open_file.dart';
import 'package:hahanote_app/page/base/searchable_page_state.dart';
import 'package:hahanote_app/util/util.dart';
import 'package:hahanote_app/widget/custom_list_view.dart';
import 'package:flutter/material.dart';

import '../hahanote_lib_sync/app.dart';
import '../hahanote_lib_sync/storage/repo/sync.dart';
import '../constants/cons.dart';
import '../ui/ui.dart';
import '../util/fs.dart';
import '../widget/dialogs.dart';

const _TAG = "repo_status.dart";


class RepoStatusPage extends StatefulWidget {
  // 文件在仓库下的相对路径
  final String repoPath;

  const RepoStatusPage({super.key, required this.repoPath});

  @override
  State<RepoStatusPage> createState() => _RepoStatusPageState();

}

class _RepoStatusPageState extends SearchablePageState<RepoStatusPage> {
  late final String repoPath;
  bool disposed = false;
  Repo? repo;

  @override
  void disposeSub() {
    disposed = true;
  }

  void throwIfInterrupt() {
    if(disposed || !mounted) {
      throw "loading repo status canceled: user left the page";
    }
  }

  @override
  Future<void> doLoadItems() async {
    repo = await Repo.fromRepoPath(repoPath);
    final statusItems = await repo!.status(
      throwIfInterrupted: throwIfInterrupt,
      progressCb: (String act, int allCount, int currentAt, String extraInfo) {
        String actText = genSyncProgressText(act, allCount, currentAt, extraInfo);
        setState(() {
          progressText = actText;
        });
      }
    );

    // 如果想排序，可以排
    items = statusItems;
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
        icon: Icon(Icons.checklist),
        tooltip: t.selectionMode,
        onPressed: () {
          letSelectModeOn();
        },
      )
    ];
  }

  @override
  void initBase() {
    repoPath = widget.repoPath;
    super.title = t.status;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      requireLogin();
    });
  }

  // mime若传null，则猜类型，对应默认打开方式；若传textMime，则当作文本打开
  Future<bool> _openWithInternalEditor(String path, {required String? mime}) async {
    return await openWithInternalEditor(path, mime: mime, callerTag: _TAG, context: context, showMsgLong: showMsgLong);
  }

  Future<void> _openFileInExternal(String path) async {
    await openFileInExternal(path, showMsgLong: showMsgLong, callerTag: _TAG);
  }

  Future<void> showFileDoesntExistOrDoAct(StatusItem item, {required Future<void> Function(File) act}) async {
    final file = File(item.getFullPathOfItem(widget.repoPath));
    if(!await file.exists()) {
      showMsgLong(t.fileDoesntExist);
      return;
    }

    await act(file);
  }

  Future<void> _view(StatusItem item) async {
    try {
      if(!mounted) return;

      final repo = this.repo;
      if(repo == null) {
        showMsg("repo is null");
        return;
      }

      final headNode = await repo.getHeadNodeOfFile(item.relativePathUnderWorkdir);
      if(headNode == null) {
        showMsgLong("not found head node of file");
        return;
      }

      // 上个节点是删除，无从diff，直接用文本编辑器打开文件即可
      // view obj把deleted当作空文件处理了，所以这里不用处理了
      // if(headNode.oid.value == VersionOid.deleted.value) {
      //   await showFileDoesntExistOrDoAct(
      //     item,
      //     act: (file) async {
      //       await _openWithInternalEditor(file.absolute.path, mime: null);
      //     }
      //   );
      //   return;
      // }

      if(!mounted) return;

      Navigator.pushNamed(
        context,
        Cons.routeViewObject,
        arguments: {"path": item.relativePathUnderWorkdir, "oid": headNode.oid.value}
      ); 
    }catch(e, st) {
      App.logger.debug(_TAG, "view status item err: $e\n$st");
      showMsgLong("view item err: $e");
    }
  }

  void _history(StatusItem item) {
    if(!mounted) return;

    Navigator.pushNamed(
      context,
      Cons.routeFileHistory,
      arguments: {"path": item.relativePathUnderWorkdir},
    );
  }

  String _getItemLastModifiedTime(StatusItem item) {
    try {
      final file = File(item.getFullPathOfItem(widget.repoPath));
      return formatDateTimeHumanFriendly(file.lastModifiedSync());
    }catch(_) {
      // 若文件不存在，会报错，返回空字符串即可
      return "";
    }
  }

  Future<void> _showRestoreItemsDialog(List<StatusItem> items) async {
    bool atLeastHandledOne = false;

    // 显示弹窗，删除文件，明确提示用户会删除硬盘上的文件
    // 删除成功后，刷新页面（页面需要支持多选，因为可能删除多个文件
    await Dialogs.showOkOrNoDialog(
      context,
      title: t.restore,
      text: t.statusRestoreDesc,
      onOk: () async {
        doActIfNotLoading(
          loadingOn: () async {
            setState(() {
              progressText = t.loading;
            });
          },
          loadingOff: () async {
            setState(() {
              progressText = "";
            });

            // 若全删完了，则退出选择模式；否则保持
            if(selectedItems.isEmpty) {
              quitSelection();
            }

            // 若至少操作了一个文件，则刷新页面
            if(atLeastHandledOne) {
              await loadItems();
            }
          },
          act: () async {
            if(items.isEmpty) return;

            await Dialogs.showCancelableLoadingDialogAndDoTask(
              context,
              task: (throwIfCanceled, progressCb) async {
                try {
                  final needRestoreItems = <OidAndPath>{};
                  final repo = await Repo.open(widget.repoPath);

                  for(final item in items) {
                    if(item.type == StatusItemType.deleted || item.type == StatusItemType.modified) {
                      final headNode = await repo.getHeadNodeOfFile(item.relativePathUnderWorkdir);
                      if(headNode != null) { // 若等于null，找不到head节点，无法恢复，一般不会发生这种情况
                        needRestoreItems.add(OidAndPath(oid: headNode.oid, path: item.relativePathUnderWorkdir));
                      }
                    }else if(item.type == StatusItemType.added) {
                      needRestoreItems.add(OidAndPath(oid: VersionOid.deleted, path: item.relativePathUnderWorkdir));
                    } // should no more else
                  }

                  if(needRestoreItems.isEmpty) {
                    return;
                  }


                  // 恢复条目
                  await repo.restoreFiles(
                    needRestoreItems,
                    throwIfInterrupted: throwIfCanceled,
                    progressCb: progressCb
                  );

                  atLeastHandledOne = true;
                  selectedItems.clear();
                }catch (e, st) {
                  // 若文件不存在，会报错
                  App.logger.debug(_TAG, "restore files err: $e\n$st");
                }
              }
            );
          }
        );
      }
    );
  }

  Future<void> _showDelItemsDialog(List<StatusItem> items) async {
    bool atLeastDeletedOne = false;

    // 显示弹窗，删除文件，明确提示用户会删除硬盘上的文件
    // 删除成功后，刷新页面（页面需要支持多选，因为可能删除多个文件
    await Dialogs.showOkOrNoDialog(
      context,
      title: t.delete,
      text: t.willDelFileOnDisk,
      onOk: () async {
        doActIfNotLoading(
          loadingOn: () async {
            setState(() {
              progressText = t.deleting;
            });
          },
          loadingOff: () async {
            setState(() {
              progressText = "";
            });

            // 若全删完了，则退出选择模式；否则保持
            if(selectedItems.isEmpty) {
              quitSelection();
            }

            // 若至少删除了一个文件，则刷新页面
            if(atLeastDeletedOne) {
              await loadItems();
            }
          },
          act: () async {
            if(items.isEmpty) return;

            for(final item in items) {
              try {
                await deleteFileIfExists(File(item.getFullPathOfItem(widget.repoPath)));
                atLeastDeletedOne = true;
                selectedItems.removeWhere((it) => it.relativePathUnderWorkdir == item.relativePathUnderWorkdir);
              }catch(e) {
                // 若文件不存在，会报错
                App.logger.debug(_TAG, "delete file '${item.relativePathUnderWorkdir}' failed: $e");
              }
            }

          }
        );
      }
    );
  }

  bool equals(dynamic it1, dynamic it2) {
    return it1.relativePathUnderWorkdir == it2.relativePathUnderWorkdir;
  }

  @override
  Widget itemBuilder<T>(BuildContext context, int index, T item) {
    item as StatusItem;
    final valueColor = statusTypeToColor(item.type);
    // 注：如果是已删除条目，此值应该是空字符串，但如果显示的是非空，说明判定文件为已删除后，
    // 文件又存在了，可能被外部程序创建了之类的，不过一般不会发生
    final lastModifiedTime = _getItemLastModifiedTime(item);

    return LabelValueTile(
      items: [
        LabelValue(label: t.name, value: item.name, icon: Icons.insert_drive_file, valueColor: valueColor, valueFontWeight: FontWeight.bold),
        if(item.parentPath.isNotEmpty) LabelValue(label: t.path, value: item.parentPath, icon: Icons.folder_outlined, valueColor: valueColor),
        LabelValue(label: t.size, value: Fs.readableSize(item.sizeInBytes), icon: Icons.sd_card_outlined, valueColor: valueColor),
        LabelValue(label: t.type, value: statusTypeToString(item.type), icon: Icons.category_outlined, valueColor: valueColor),
        if(lastModifiedTime.isNotEmpty) LabelValue(label: t.lastModifiedTime, value: lastModifiedTime, icon: Icons.access_time_outlined, valueColor: valueColor),
      ],
      onTap: isSelectionModeOn ? () => setState(() {
        UI.switchSelected(
          item: item,
          selectedItems: selectedItems,
          equals: equals
        );
      }) : () async {
        // 点条目主体：
        // 若是新增则编辑
        // 若是修改则跳转到和文件head节点的diff页面
        // 若是删除也跳转到和head的diff页面（里面做了处理，workdir文件不存在时可正常工作）
        if(item.type == StatusItemType.added) {
          await showFileDoesntExistOrDoAct(
            item,
            act: (file) async {
              await _openWithInternalEditor(file.absolute.path, mime: null);
            }
          );
        }else if(item.type == StatusItemType.modified || item.type == StatusItemType.deleted) {
          await _view(item);
        }else {
          showMsg(t.unknown);
        }
      },
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
          value: "open",
          text: t.open,
          onClick: () async {
            await showFileDoesntExistOrDoAct(
              item,
              act: (file) async {
                await _openWithInternalEditor(file.absolute.path, mime: null);
              }
            );
          },
        ),
        MenuItem(
          value: "open_in_ext",
          text: t.openInExt,
          onClick: () async {
            await showFileDoesntExistOrDoAct(
              item,
              act: (file) async {
                await _openFileInExternal(file.absolute.path);
              }
            );
          },
        ),
        MenuItem(
          value: "open_as_text",
          text: t.openAsText,
          onClick: () async {
            await showFileDoesntExistOrDoAct(
              item,
              act: (file) async {
                await _openWithInternalEditor(file.absolute.path, mime: mimeTextPlain);
              }
            );
          },
        ),
        MenuItem(
          value: "copy_path",
          text: t.copyPath,
          onClick: () async {
            await copyTextThenShowMsg(item.relativePathUnderWorkdir);
          },
        ),
        MenuItem(
          value: "copy_absolute_path",
          text: t.copyAbsolutePath,
          onClick: () async {
            await copyTextThenShowMsg(item.getFullPathOfItem(widget.repoPath));
          },
        ),
        MenuItem(
          value: "history",
          text: t.history,
          onClick: () async {
            _history(item);
          },
        ),
        // if(item.type != StatusItemType.deleted)  // 已删除条目也可尝试执行删除，因为status页面是已删除，但后来可能又创建了文件也说不定
        MenuItem(
          value: "delete",
          text: t.delete,
          onClick: () async {
            await _showDelItemsDialog([item]);
          },
        ),
      ],
    );
  }

  @override
  Future<bool> searchMatcher(String keyword, dynamic item) async {
    item as StatusItem;

    return item.relativePathUnderWorkdir.toLowerCase().contains(keyword) ||
        Fs.readableSize(item.sizeInBytes).toLowerCase().contains(keyword) ||

        // 避免干扰搜索结果，所以这个用等号判断
        item.type.toLowerCase() == keyword ||
        statusTypeToString(item.type).toLowerCase() == keyword ||
        _getItemLastModifiedTime(item).toLowerCase().contains(keyword)
    ;
  }


  @override
  String selectedItemInfoGenerator(dynamic item) {
    return (item as StatusItem).relativePathUnderWorkdir;
  }

  @override
  bool isItemSelected(dynamic item) {
    item as StatusItem;
    return selectedItems.any((it) => item.relativePathUnderWorkdir == (it as StatusItem).relativePathUnderWorkdir);
  }

  @override
  List<Widget> bottomBarChildrenBuilder() {
    return [
      IconButton(
        icon: Icon(Icons.restore),
        tooltip: t.restore,
        onPressed: loading || selectedItems.isEmpty ? null : () async {
          // cast()是为了转换类型
          // cast()返回的列表会并发修改异常，所以先用toList()创建新List再cast()
          // 如果先cast()再toList()，编译器会推断类型失败，因为只能推断出最终toList()的目标，
          // 但不知道中间的cast()期望什么类型，必须手动指定cast<Type>()，
          // 所以把cast()放到最后调用，这样可根据入参类型推断出目标类型，省得自己指定类型
          await _showRestoreItemsDialog(selectedItems.toList().cast());
        },
      ),
      IconButton(
        icon: Icon(Icons.delete),
        tooltip: t.delete,
        onPressed: loading || selectedItems.isEmpty ? null : () async {
          // cast()是为了转换类型
          // cast()返回的列表会并发修改异常，所以先用toList()创建新List再cast()
          // 如果先cast()再toList()，编译器会推断类型失败，因为只能推断出最终toList()的目标，
          // 但不知道中间的cast()期望什么类型，必须手动指定cast<Type>()，
          // 所以把cast()放到最后调用，这样可根据入参类型推断出目标类型，省得自己指定类型
          await _showDelItemsDialog(selectedItems.toList().cast());
        },
      ),
      getSelectAllButton(),
      getQuitSelectionButton(),
    ];
  }

}

