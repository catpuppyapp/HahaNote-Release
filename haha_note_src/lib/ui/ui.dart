import 'dart:async';
import 'dart:math' show min, max;

import 'package:hahanote_app/db/db.dart' show Db;
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/util/util.dart';
import 'package:hahanote_app/widget/bottom_bar.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/global.dart';
import 'app_theme.dart';

abstract class UI {
  // checkbox 复选框在左边还是右边，默认右边，安卓左边，我感觉左边好，所以改左边
  static const myCheckBoxControlAffinity = ListTileControlAffinity.leading;

  static const double defaultScreenPadding = 16;

  static const verticalDividerWidth1 = VerticalDivider(width: 1, thickness: 1);

  // 因为脚手架默认是不设高度的，
  // 所以这个其实只是脚手架 top bar 大概的高度，
  // 如果自己在body里实现topbar，则用这个指定高度
  static const double topBarHeight = 50;
  static const Offset offsetTopBarMenu = Offset(0, topBarHeight);

  static const double verticalHeight = 16;
  static const double horizontalHeight = 16;

  static const _colorErrDark = Color(0xFFEA5B5B);
  static const _colorErrLight = Color(0xFFEA5B5B);

  static const _buttonColorNormalDark = Color(0xFF7189C5);
  static const _buttonColorNormalLight = Color(0xFFA9BEED);

  // BEGIN: 字体大小调整
  // 或许拆分出 value font size和zoom font size更好？
  static const double editorFontSizeDefault = 14;
  static const double editorFontSizeMin = 11;
  static const double editorFontSizeMax = 60;
  static const double editorFontSizeAdjustStep = 1;
  static const double markdownPreviewerFontSizeDefault = 1;
  static const double markdownPreviewerFontSizeMin = 1;
  static const double markdownPreviewerFontSizeMax = 5;
  static const double markdownPreviewerFontSizeAdjustStep = 0.1;
  static const double diffViewFontSizeDefault = 1;
  static const double diffViewFontSizeMin = 1;
  static const double diffViewFontSizeMax = 5;
  static const double diffViewFontSizeAdjustStep = 0.1;
  // END: 字体大小调整

  // 用来在主题更改时重新构建整个MaterialApp从而不需手动重启就看到最新的主题
  static final ValueNotifier<AppTheme> themeNotifier = ValueNotifier(AppTheme.defaultValue);

  static bool snackBarIsShowing = false;
  static int lastSnackBackShowKeepTimeInSec = 0;

  // static const listPadding = EdgeInsets.fromLTRB(UI.defaultScreenPadding, UI.defaultScreenPadding, UI.defaultScreenPadding, bottomBarContainerBottomPadding);
  static const listPadding = EdgeInsets.only(left: UI.defaultScreenPadding, right: UI.defaultScreenPadding, bottom: bottomBarContainerBottomPadding);
  static const listPaddingOnlyBottom = EdgeInsets.only(bottom: bottomBarContainerBottomPadding);

  static const defaultCheckboxDescPadding = EdgeInsets.symmetric(vertical: 5, horizontal: 16);
  // static Future<void> init() async {
  //   await initTheme();
  //   await initToast();
  // }

  static const subtitleTextColor = Color.fromARGB(255, 123, 123, 123);
  static const subTitleTextStyle = TextStyle(color: subtitleTextColor);

  static const double smallIconSize = 18;

  static Future<void> initTheme() async {
    themeNotifier.value = AppTheme(themeMode: await Db.getThemeMode(), colorScheme: await Db.getColorScheme());
  }


  static Future<void> setThemeMode(ThemeMode mode) async {
    if(mode == themeNotifier.value.themeMode) {
      return;
    }

    themeNotifier.value = themeNotifier.value.copyWith(themeMode: mode);

    await Db.setThemeMode(mode);
  }

  static ThemeMode getThemeMode() {
    return themeNotifier.value.themeMode;
  }

  static bool isDarkTheme() {
    final themeMode = themeNotifier.value.themeMode;

    if(themeMode == ThemeMode.system) {
      // 主题模式是跟随系统，需要判断下
      final brightness = PlatformDispatcher.instance.platformBrightness;
      return brightness == Brightness.dark;
    }else {
      // 非跟随系统，直接返回
      return themeMode == ThemeMode.dark;
    }
  }

  static Color getColorErr() {
    if(isDarkTheme()) {
      return _colorErrDark;
    }else {
      return _colorErrLight;
    }
  }

  static Color buttonColorNormal() {
    if(isDarkTheme()) {
      return _buttonColorNormalDark;
    }else {
      return _buttonColorNormalLight;
    }
  }

  static Color getColorOfFont() {
    if(isDarkTheme()) {
      return Colors.grey;
    }else {
      return Colors.black;
    }
  }


  static Color getSelectedBgColor(ThemeData theme, {bool? isDark}) {
    // return theme.colorScheme.surfaceContainer;
    // return theme.colorScheme.primaryContainer;
    return (isDark ?? isDarkTheme()) ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.surfaceDim;
    // return theme.colorScheme.surfaceContainerHighest;
  }

  static void switchSelected<T>({
    required T item,
    required List<T> selectedItems,
    required bool Function(T t1, T t2) equals,
  }) {
    final index = selectedItems.indexWhere((e) => equals(e, item));
    if (index != -1) {
      // 条目当前被选中了，移除
      selectedItems.removeAt(index);
    } else {
      // 条目当前未被选中，添加
      selectedItems.add(item);
    }
  }

  static void switchSelectSpan<T>({
    required int itemIdxOfItemList,
    required T item,
    required List<T> selectedItems,
    required List<T> itemList,
    required void Function(T) switchItemSelected,
    required void Function(T) selectIfNotInSelectedListElseNoop,
    required bool Function(T t1, T t2) equals,
  }) {
    //如果 已选条目列表为空 或 索引无效，选中条目，然后返回
    if(selectedItems.isEmpty || itemIdxOfItemList < 0 || itemIdxOfItemList >= itemList.length) {
      switchItemSelected(item);
      return;
    }


    //如果不为空，执行连续选中

    //取出最后一个选择的条目
    final lastSelectedItem = selectedItems.last;

    //在源list中查找最后一个条目的位置（索引）
    final lastSelectedItemIndexOfItemList = itemList.indexWhere((it) => equals(it, lastSelectedItem));

    //itemList查无选中列表的最后一个元素，发生这种情况的场景举例：完整列表，选中条目abc，过滤列表不包含abc，长按选择，过滤列表被传入此函数的itemList，这时，itemList就会查无abc，indexOf返回-1
    if(lastSelectedItemIndexOfItemList == -1) {
      switchItemSelected(item);
      return;
    }

    //如果长按的条目就是之前选中的条目，什么都不做（选中一个条目，然后长按它即可触发此条件）
    if(lastSelectedItemIndexOfItemList == itemIdxOfItemList) {
      return;
    }

    //min()
    final startIndex = min(lastSelectedItemIndexOfItemList, itemIdxOfItemList);
    //max()
    final endIndexExclusive = max(lastSelectedItemIndexOfItemList, itemIdxOfItemList) + 1;

    //检查索引是否有效
    if(startIndex >= endIndexExclusive
        || startIndex < 0 || startIndex >= itemList.length
        || endIndexExclusive < 0 || endIndexExclusive > itemList.length
    ) {
      return;
    }

    //选中范围内的条目 左闭右开 [startIndex, endIndexExclusive)
    //list.forEach(selectIfNotInSelectedListElseNoop) 等于 list.forEach{selectIfNotInSelectedListElseNoop(it)}
//        itemList.subList(startIndex, endIndexExclusive).forEach {selectIfNotInSelectedListElseNoop(it)}  //需要拷贝列表，bad
    for(var i = startIndex; i < endIndexExclusive; i++) {
      selectIfNotInSelectedListElseNoop(itemList[i]);  //不需要拷贝列表，good
    }
  }

  static void selectIfNotInSelectedListElseNoop<T>({
    required T item,
    required List<T> selectedItems,
    required bool Function(T t1, T t2) equals,
  }) {
    if(selectedItems.indexWhere((it) => equals(it, item)) == -1) {
      selectedItems.add(item);
    }
  }

  static void scrollTo(int index, ScrollController controller, {double itemHeight = 60}) {
    if(!controller.hasClients) return;

    final double targetPos = (index * itemHeight).clamp(0, controller.position.maxScrollExtent);
    // 若目标位置和当前位置不同则跳转
    if(targetPos != controller.position.pixels) {
      controller.jumpTo(targetPos);
    }
  }

  static void showMsgLong({
    required String text,
  }) {
    showMsg(text: text, keepInSec: 6);
  }

  static Future<void> showMsg({
    required String text,
    int keepInSec = 4,
  }) async {
    if(text.isEmpty) {
      return;
    }

    final msger = Global.scaffoldMessengerKey.currentState;
    if(msger == null) {
      return;
    }

    // 如果之前的snackBar还没隐藏，先等待
    // 最多等待之前的snackBar自动隐藏的超时时间那么多秒
    int count = 0;
    final maxWaitTimeInSec = lastSnackBackShowKeepTimeInSec;
    lastSnackBackShowKeepTimeInSec = keepInSec;

    while(snackBarIsShowing && count++ < maxWaitTimeInSec) {
      await Future.delayed(Duration(seconds: 1));
    }

    snackBarIsShowing = true;


    msger.showSnackBar(
      SnackBar(
        // 点击拷贝
        // content: InkWell(
        //   onTap: () => copyText(text),
        //   child: Text(text),
        // ),

        content: Text(text),
        duration: Duration(seconds: keepInSec),

        // showCloseIcon: true,  //关闭按钮太大，太占空间，而且可以下滑隐藏，所以不用显示了
        //注意：若有按钮，不会自动隐藏，不知道是否bug
        action: SnackBarAction(
          label: t.copy,
          onPressed: () {
            copyText(text);
          },
        ),
      ),
    );

    // action非null，不会自动隐藏，所以设个timer，使其超时隐藏
    Timer(Duration(seconds: keepInSec), () {
      try {
        msger.hideCurrentSnackBar();
      }catch(_) {
      }

      snackBarIsShowing = false;
    });
  }

  static Color getColorOfContainer(ThemeData theme) {
    // return UI.isDarkTheme() ? theme.colorScheme.inversePrimary : theme.colorScheme.primary;
    return theme.colorScheme.primaryContainer;
  }

  static Color getSecondaryColorOfFont() {
    return UI.isDarkTheme() ? Color(0xFFC6C6C6) : Colors.black87;
  }

  static Color secondTextColorInPrimaryColorContainer(ThemeData theme) {
    // return UI.isDarkTheme() ? Color(0xFF676767) : Colors.grey;
    return theme.colorScheme.onPrimaryContainer;
  }

  static Color firstTextColorInPrimaryColorContainer(ThemeData theme) {
    // return UI.isDarkTheme() ? Color(0xFF676767) : Colors.grey;
    return theme.colorScheme.onPrimaryContainer;
  }

  static Widget getBottomPaddingOfList() {
    return const SizedBox(height: bottomBarContainerBottomPadding);
  }


  // static FToast getToast(BuildContext context) {
  //   return FToast()..init(context);
  // }
  //
  // static void showToastLong(FToast fToast, String text, {int timeInSec = 6}) {
  //   showToast(fToast, text, timeInSec: timeInSec);
  // }
  //
  // static void showToast(FToast fToast, String text, {int timeInSec = 3}) {
  //   Widget toast = Container(
  //     padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
  //     decoration: BoxDecoration(
  //       borderRadius: BorderRadius.circular(25.0),
  //       color: Colors.greenAccent,
  //     ),
  //     child: Row(
  //       mainAxisSize: MainAxisSize.min,
  //       children: [
  //         Flexible(
  //           child: ConstrainedBox(
  //             constraints: BoxConstraints(maxWidth: 280),
  //             child: Text(
  //               text,
  //               softWrap: true,
  //               maxLines: 10,
  //               overflow: TextOverflow.ellipsis,
  //             ),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  //
  //
  //   fToast.showToast(
  //     child: toast,
  //     gravity: ToastGravity.BOTTOM,
  //     toastDuration: Duration(seconds: timeInSec),
  //   );
  // }

  static IconData getThemeIcon({ThemeMode? mode}) {
    switch (mode ?? UI.themeNotifier.value.themeMode) {
      case ThemeMode.system: return Icons.brightness_auto;
      case ThemeMode.light: return Icons.light_mode;
      case ThemeMode.dark: return Icons.dark_mode;
    }
  }

  static String getThemeText({ThemeMode? mode}) {
    switch (mode ?? UI.themeNotifier.value.themeMode) {
      case ThemeMode.system: return t.auto;
      case ThemeMode.light: return t.light;
      case ThemeMode.dark: return t.dark;
    }
  }

  static List<ThemeMode> getAllTheme() {
    return [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
  }

  static FlexScheme getColorScheme() {
    return themeNotifier.value.colorScheme;
  }

  static Future<void> setColorScheme(FlexScheme value) async {
    if(value == themeNotifier.value.colorScheme) {
      return;
    }

    themeNotifier.value = themeNotifier.value.copyWith(colorScheme: value);

    await Db.setColorScheme(value);
  }

  static List<FlexScheme> getAllColorSchemes() {
    return FlexScheme.values;
  }

  static Color secondaryTextColorInBlackOrWhiteContainer() {
    return UI.isDarkTheme() ? Colors.white38 : Colors.black54;
  }
}
