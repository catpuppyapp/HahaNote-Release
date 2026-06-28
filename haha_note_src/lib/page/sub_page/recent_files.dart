import 'package:cloud_disk_note_app/bean/bean.dart' show ContentItem, ActRegion;
import 'package:cloud_disk_note_app/db/db.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:cloud_disk_note_app/page/base/searchable_widget_state.dart';
import 'package:cloud_disk_note_app/widget/content_item_waterfall.dart';
import 'package:flutter/material.dart';

import '../../ui/ui.dart';
import '../../widget/dialogs.dart';



const _TAG = "recent_files.dart";


class RecentFiles extends StatefulWidget {
  final bool showScaffold;
  final void Function(String msg) showMsg;
  final void Function(String msg) showMsgLong;
  final Future<bool> Function(String path) openWithInternalEditor;
  final Future<void> Function(String path) openInExt;
  final void Function(ContentItem) goToFilesAndRevealItem;

  const RecentFiles({
    super.key,
    required this.showScaffold,
    required this.showMsg,
    required this.showMsgLong,
    required this.openWithInternalEditor,
    required this.goToFilesAndRevealItem,
    required this.openInExt,
  });

  @override
  State<RecentFiles> createState() => RecentFilesState();

}

class RecentFilesState extends SearchableWidgetState<RecentFiles> {
  @override
  void showMsg(String msg) {
    widget.showMsg(msg);
  }

  @override
  void showMsgLong(String msg) {
    widget.showMsgLong(msg);
  }

  @override
  Future<void> doLoadItems() async {
    final openedRepo = await Db.getOpenedRepo();

    if(openedRepo == null) {
      return;
    }

    final contentItems = await openedRepo.recentFilesToContentItems();
    // 最后修改时间降序排列
    contentItems.sort((a, b) => b.lastTouchedAt.compareTo(a.lastTouchedAt));

    items = contentItems;
  }

  @override
  List<Widget> getActions() {
    return [];
  }

  @override
  void initBase() {
    super.showScaffold = false;
    super.title = t.recent;
  }

  @override
  Widget itemBuilder<T>(BuildContext context, int index, T item) {
    // 这个页面用的自定义listview，所以不需要这个，这个是build list的item的
    throw UnimplementedError();
  }

  @override
  Future<bool> searchMatcher(String keyword, dynamic item) async {
    return item.path.toLowerCase().contains(keyword) || item.content.toLowerCase().contains(keyword);
  }

  bool equals(dynamic it1, dynamic it2) {
    return it1.fullPath == it2.fullPath;
  }

  @override
  Widget? getListView() {
    return ContentItemWaterfall(
      items: getActuallyList().toList().cast(),

      // 改成在底栏定位到文件管理器的当前文件了
      // onSecondLineClick: (idx, item) {
      //   widget.goToFilesAndRevealItem(item);
      // },

      selected: (idx, item) => isItemSelected(item),
      onClick: (idx, item) async {
        if(isSelectionModeOn) {
          setState(() {
            UI.switchSelected(
              item: item,
              selectedItems: selectedItems,
              equals: equals
            );
          });
        }else {
          await widget.openWithInternalEditor(item.fullPath);
        }
      },
      onLongPress: (idx, item) {
        setState(() {
          UI.switchSelectSpan(
            itemIdxOfItemList: idx,
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
    );
  }

  Future<void> showDeleteDialog(ActRegion actRegion) async {
    await Dialogs.showOkOrNoDialog(
      context,
      title: actRegion == ActRegion.all ? t.clear : t.delete,
      text: t.areYouSure,
      onOk: () => _doDelete(actRegion)
    );
  }

  Future<void> _doDelete(ActRegion actRegion) async {
    await doAct(
      actName: "delete",
      actDesc: "delete recent files",
      actRegion: actRegion,
      showMsg: widget.showMsg,
      showMsgLong: widget.showMsgLong,
      getRepo: () async => null,
      allowRepoIsNull: true,
      getOpenedRepo: () async {
        return await Db.getOpenedRepo();
      },
      allowOpenedRepoIsNull: false,
      act: (repo, openedRepo, items) async {
        for(final i in items) {
          i as ContentItem;
          openedRepo!.recentFiles.removeWhere((rf) => rf.path == i.fullPath);
        }

        await Db.updateRepo(openedRepo!);
      }
    );

  }


  @override
  String selectedItemInfoGenerator(dynamic item) {
    return (item as ContentItem).name;
  }

  @override
  bool isItemSelected(dynamic item) {
    item as ContentItem;
    return selectedItems.any((it) => item.fullPath == (it as ContentItem).fullPath);
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
      IconButton(
        icon: Icon(Icons.document_scanner_outlined),
        tooltip: t.showInFiles,
        onPressed: loading || selectedItems.length != 1 ? null : () async {
          final ContentItem? selected = selectedItems.firstOrNull;
          if(selected != null) {
            widget.goToFilesAndRevealItem(selected);
          }
        },
      ),
      IconButton(
        icon: Icon(Icons.open_in_new),
        tooltip: t.openInExt,
        onPressed: loading || selectedItems.length != 1 ? null : () async {
          final ContentItem? selected = selectedItems.firstOrNull;
          if(selected != null) {
            widget.openInExt(selected.fullPath);
          }
        },
      ),
      getSelectAllButton(),
      getQuitSelectionButton(),
    ];
  }

}

