import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show randomStringUnsafeButFaster;
import 'package:hahanote_app/state/my_page_state.dart' show MyPageState;
import 'package:hahanote_app/widget/base_layout.dart';
import 'package:hahanote_app/widget/custom_list_view.dart';
import 'package:hahanote_app/widget/pull_to_refresh_list.dart';
import 'package:hahanote_app/widget/search_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../ext/state_ext.dart';
import '../../i18n/strings.g.dart';
import '../../widget/bottom_bar.dart';

const _TAG = "searchable_page_state.dart";

abstract class SearchablePageState<T extends StatefulWidget> extends MyPageState<T> {
  String title = "";

  // 这个是当初基于其他页面创建此页面时的残留变量，
  // 用这个组件的都显示，所以都传true，所以没必要使用此变量了
  // bool showScaffold = false;

  String err = '';
  // file path
  List<dynamic> items = [];

  bool firstLoadingDone = false;

  bool loading = false;
  String progressText = "";

  List<dynamic> searchedItems = [];
  TextEditingController searchKeyword = TextEditingController(text: "");
  bool searching = false;
  String searchId = "";

  List<dynamic> selectedItems = [];
  bool selectedModeOn = false;

  // 初始化页面标题之类的
  void initBase();

  @override
  void initState() {
    super.initState();
    initBase();
    loadItems();
  }

  @override
  void dispose() {
    disposeSub();
    searchKeyword.dispose();
    super.dispose();
  }

  void disposeSub() {}


  @override
  bool handleKeyPress(KeyEvent event, bool isControlDown, bool isAltDown, bool isShiftDown) {
    final pressedKey = event.logicalKey;
    // f5刷新页面
    if(pressedKey == LogicalKeyboardKey.f5 && !isControlDown && !isAltDown && !isShiftDown) {
      loadItems();
      return true;
    }

    // 退出选择模式
    if(pressedKey == LogicalKeyboardKey.escape
        && !isControlDown && !isAltDown && !isShiftDown
        && mounted
    ) {
      if(backHandler()) {
        return true;
      }
    }

    return false;
  }

  Future<void> doLoadItems();
  Widget itemBuilder<T>(BuildContext context, int index, T item);
  List<Widget> getActions();


  List<dynamic> getActuallyList() {
    return searchId.isNotEmpty ? searchedItems : items;
  }

  Future<void> doActIfNotLoading({
    required Future<void> Function() act,
    Future<void> Function()? loadingOn,
    Future<void> Function()? loadingOff,
  }) async {
    if(loading) {
      return;
    }

    try {
      loading = true;
      setState((){});

      await loadingOn?.call();

      await act();
    }finally {
      loading = false;
      setState(() {});

      await loadingOff?.call();
    }
  }

  Future<void> loadItems() async {
    if(loading) {
      return;
    }

    loading = true;

    setState(() {
      err = '';
      items = [];
    });

    try {
      await doLoadItems();


      // 如果关键字非空，在刷新后执行搜索
      if(searchKeyword.text.isNotEmpty) {
        await search();
      }
    }catch(e, st) {
      err = e.toString();
      App.logger.debug(_TAG, "load items err: $e\n$st");
    }finally {
      firstLoadingDone = true;
      loading = false;
      progressText = "";
    }

    refreshUI();

  }

  Future<bool> searchMatcher(String keyword, dynamic item);

  Future<void> search() async {
    // 空也搜，确保逻辑完整
    // if(items.isEmpty) {
    //   return;
    // }

    if(searchKeyword.text.isEmpty) {
      searchId = "";
      searching = false;
      searchedItems.clear();

      setStateSafe(() {});

      return;
    }

    try {
      final sessionSearchId = randomStringUnsafeButFaster(20);
      setState(() {
        searchId = sessionSearchId;
        searching = true;
      });

      final searched = <dynamic>[];
      final keyword = searchKeyword.text.toLowerCase();
      for(final item in items) {
        // 搜索被取消了（用户可能点了搜索框的 x）
        if(sessionSearchId != searchId || !mounted) return;

        if(await searchMatcher(keyword, item)) {
          searched.add(item);
        }
      }

      searchedItems = searched;
    }catch(e, st) {
      App.logger.debug(_TAG, "search err: $e\n$st");
      showMsgLong("search err: $e");
    }finally {
      setStateSafe(() {
        searching = false;
      });
    }

  }

  // 如果想自定义搜索框下面的列表，重写这个
  Widget? getListView() {
    return null;
  }

  List<Widget> underSearchBarAboveListChildren() {
    return const [];
  }

  /// 可调用此函数生成 [underSearchBarAboveListChildren] 需要的值
  List<Widget> defaultUnderSearchBarAboveListChildren(String text) {
    if(text.isEmpty) {
      return const [];
    }

    return [
      Padding(
          padding: EdgeInsetsGeometry.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(text),
          )
      ),
      const Divider(),
    ];
  }

  String selectedItemInfoGenerator(dynamic item) {
    return "";
  }

  List<Widget> bottomBarChildrenBuilder() {
    return [];
  }

  bool isItemSelected(dynamic item) {
    return false;
  }

  Widget getSelectAllButton() {
    return IconButton(
      icon: Icon(Icons.select_all),
      tooltip: t.selectAll,
      onPressed: loading ? null : selectAll,
    );
  }

  void selectAll() {
    // 全选时不清列表，退出选择模式时清，用户体验更好，
    // 想象一下，过滤出.txt文件，全选，再过滤.md文件全选，若清了，
    // 点全选后，就只能选择.md，之前全选的.txt就丢了
    // selectedFileList.clear();

    // 避免重复添加
    for(final it in getActuallyList()) {
      if(!isItemSelected(it)) {
        selectedItems.add(it);
      }
    }

    setState(() {});
  }

  Widget getQuitSelectionButton() {
    return IconButton(
      icon: Icon(Icons.close),
      tooltip: t.quit,
      onPressed: loading ? null : quitSelection,
    );
  }

  void quitSelection() {
    setState(() {
      selectedModeOn = false;
      selectedItems = [];
    });
  }


  bool get isSelectionModeOn {
    final hasSelectedItem = selectedItems.isNotEmpty;
    if(hasSelectedItem && !selectedModeOn) {
      selectedModeOn = true;
    }

    return selectedModeOn;
  }

  void letSelectModeOn() {
    setState(() {
      selectedModeOn = true;
    });
  }

  bool backHandler() {
    if(isSelectionModeOn) {
      quitSelection();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final list = getActuallyList();

    final column = Column(
      children: [
        SearchTextFiled(
          keyword: searchKeyword,
          searching: searching,
          showClear: searchId.isNotEmpty,
          onSearch: (value) {
            search();
          },
        ),
        ...underSearchBarAboveListChildren(),
        Expanded(
          child: PullToRefreshList(
            loading: loading || !firstLoadingDone,
            err: err,
            listIsEmpty: list.isEmpty,
            progressText: progressText,
            onRefresh: () async {
              await loadItems();
            },
            child: getListView() ?? CustomListView(
              items: list,
              itemBuilder: itemBuilder
            ),
          ),
        ),

        if(isSelectionModeOn)
          BottomBar(
            selectedFileList: selectedItems,
            showMsg: showMsg,
            showMsgLong: showMsgLong,
            itemInfoTextGenerator: selectedItemInfoGenerator,
            children: bottomBarChildrenBuilder()
          ),
      ],
    );

    return BaseLayout.backWrapper(
      context,
      onBack: () async {
        return backHandler();
      },
      child: BaseLayout.newScaffold(
        context,
        title: title,
        actions: getActions(),
        body: column,
      )
    );
  }

}

