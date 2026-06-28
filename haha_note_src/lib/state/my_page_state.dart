import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart' show t;
import 'package:cloud_disk_note_app/main.dart' show defaultBackHandler;
import 'package:cloud_disk_note_app/native_util/msg.dart';
import 'package:cloud_disk_note_app/ui/ui.dart' show UI;
import 'package:cloud_disk_note_app/util/util.dart' show copyText;
import 'package:cloud_disk_note_app/widget/loading.dart' show doActWithLoading;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey;
import 'package:lifecycle/lifecycle.dart' show LifecycleAware, LifecycleMixin, LifecycleEvent;

const _TAG = 'my_page_state.dart';
const _refreshTokenIfAccessTokenExpiresTimeLessThanThisInSec = 1800;

class MyPageState<T extends StatefulWidget> extends State<T> with LifecycleAware, LifecycleMixin {
  bool pageVisible = true;
  bool pageActive = true;
  bool pageLoading = false;
  String pageLoadingText = "";
  String pageErr = '';
  bool pageErrClosable = false;
  bool userLoading = false;


  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyPress);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyPress);
    super.dispose();
  }


  @override
  void onLifecycleEvent(LifecycleEvent event) {
    App.logger.verbose(_TAG, "LifecycleEvent: $event");

    // visible不一定active，比如页面弹窗，这时visible但不active
    if(event == LifecycleEvent.invisible) {
      pageVisible = false;
    }else if(event == LifecycleEvent.visible) {
      pageVisible = true;
    }else if(event == LifecycleEvent.active) {
      pageActive = true;
    }else if(event == LifecycleEvent.inactive) {
      pageActive = false;
    }
  }

  /// 子类可覆盖此方法并返回false禁用快捷键handler [handleKeyPress]
  bool enableKeyHandler() {
    return true;
  }

  /// 子类可覆盖这个实现自定义快捷键处理
  bool handleKeyPress(KeyEvent event, bool isControlDown, bool isAltDown, bool isShiftDown) {
    return false;
  }

  /// 快捷键总handler，入口函数，会调用可被子类覆盖的 [handlerKeyPress] 函数
  bool _handleKeyPress(KeyEvent event) {
    // 如果禁用直接返回false，不要返回true，否则会影响按键的点击事件，比如如果这里返回true，在text editor按下键盘可能会失效
    if(!enableKeyHandler()) {
      return false;
    }

    // 这里不需要检测 mounted，只检测active即可，若active为真，必然mounted；
    // 若active为假，不管mounted与否，都不应该执行操作
    // 这个判断必须加，不然的话，可能会在不该响应的时候响应，例如：按快捷键弹窗的场景，若不在此设置inactive不响应，再按快捷键就会重复弹窗
    if(!pageActive) {
      return false;
    }

    if(event is! KeyDownEvent) {
      return false;
    }

    final isControlDown = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isAltDown = HardwareKeyboard.instance.isAltPressed;
    final isShiftDown = HardwareKeyboard.instance.isShiftPressed;

    // 调用子类方法，若处理了，直接返回true
    if(handleKeyPress(event, isControlDown, isAltDown, isShiftDown)) {
      return true;
    }

    final pressedKey = event.logicalKey;
    // 处理esc，按下返回
    if(pressedKey == LogicalKeyboardKey.escape
        && !isControlDown && !isAltDown && !isShiftDown
    ) {
      // 若能用esc，假设是pc，用键盘alt+f4退出app比较符合习惯，所以这里exit设为false，不然按esc就能直接关app了
      // 使用context的地方自行检测是否mounted
      if(defaultBackHandler(context, exit: false)) {
        return true;
      }
    }

    return false;
  }

  void showMsg(String text) {
    if(Platform.isAndroid && !pageVisible) {
      NativeMsg.showOnAndroid(msg: text, longDuration: false);
      return;
    }

    showScaffoldMsg(text);
  }

  void showMsgLong(String text) {
    if (Platform.isAndroid && !pageVisible) {
      NativeMsg.showOnAndroid(msg: text, longDuration: true);
      return;
    }

    showScaffoldMsgLong(text);
  }
  

  void showScaffoldMsg(String text) {
    UI.showMsg(text: text);
  }


  void showScaffoldMsgLong(String text) {
    UI.showMsgLong(text: text);
  }

  @override
  void setState(VoidCallback fn) {
    // 如果已经卸载页面，再调用setState会报错
    if(!mounted) return;

    super.setState(fn);
  }

  void refreshUI() {
    setState((){});
  }


  ///
  /// 如果想获取错误，可这么写：
  /// await doActWithPageLoading();
  /// logger(pageErr);
  Future<void> doActWithPageLoading({
    required String actName,
    required Future<void> Function() act,
    bool showErrIfHas = true,
    // 用来指示这个加载任务显示的错误是否可关闭，调用者可在执行任务后判断，若可关闭 pageErrClosable 会设为true
    bool errClosable = false,
  }) async {
    setState(() {
      pageErr = '';
      // 若执行任务出错，会将其设置为 `errClosable` 的值
      pageErrClosable = false;
    });

    await doActWithLoading(
      actName: actName,
      isLoadingOn: () {
        return pageLoading;
      },
      loadingOn: () {
        setState(() {
          pageLoading = true;
          // page loading text自己在外部设置
        });
      },
      loadingOff: () {
        setState(() {
          pageLoading = false;
          pageLoadingText = "";  // 子页面自己判断若这个变量为空是否显示自己的loading文本
        });
      },
      onErr: (err) {
        // 子类可通过检查pageErr来判断这个函数执行时有没有出错
        final errMsg = err.toString();
        setState(() {
          pageErr = errMsg;
          // 若为true，调用者应显示给用户一个关闭错误的按钮，或者弄个错误弹窗
          // 应该仅在致命错误，例如缺少某数据时页面无法工作的情况下才设置errClosable为false
          pageErrClosable = errClosable;
        });

        if(showErrIfHas) {
          showMsgLong(errMsg);
        }
      },
      act: () async {
        await act();
      }
    );
  }


  Future<void> copyTextThenShowMsg(String text) async {
    await copyText(text);
    showMsg(t.copied);
  }

  @Deprecated("account system removed after open source")
  Future<bool> requireLogin() async {
    return true;
  }

  @override
  Widget build(BuildContext context) {
    throw UnimplementedError();
  }

}
