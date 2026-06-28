import 'dart:io' show FileSystemEntityType;
import 'dart:math';

import 'package:cloud_disk_note_app/bean/bean.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart' show t;
import 'package:cloud_disk_note_app/main.dart';
import 'package:cloud_disk_note_app/util/util.dart';
import 'package:cloud_disk_note_app/widget/checkbox_dialog.dart';
import 'package:cloud_disk_note_app/widget/enter_input_dialog.dart';
import 'package:cloud_disk_note_app/widget/path_chooser.dart';
import 'package:flutter/material.dart';

import '../cloud_disk_note/on_off_util.dart';
import '../cloud_disk_note/storage/repo/sync.dart';
import '../ui/ui.dart';
import '../util/fs.dart';

const _TAG = "dialogs.dart";

abstract class Dialogs {
  static Future<void> showOkOrNoDialog(
  BuildContext context,{
  required String title,
  required String text,
  // 可以传异步函数，但不会await，只会触发
  required VoidCallback onOk,
  VoidCallback? onCancel,
  bool showCancel = true,
  String? okText,
  String? cancelText,
  Widget? textContent,
}) async {
  await showWidgetContentOkOrNoDialog(
    context,
    title: SelectableText(title),
    content: textContent ?? SelectableText(text),
    onOk: onOk,
    onCancel: onCancel,
    showCancel: showCancel,
    okText: okText,
    cancelText: cancelText,
  );
}


  static Future<void> showWidgetContentOkOrNoDialog(
    BuildContext context,{
    required Widget title,
    required Widget content,
    // 可以传异步函数，但不会await，只会触发
    required VoidCallback onOk,
    VoidCallback? onCancel,
    bool showCancel = true,
    String? okText,
    String? cancelText,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) {
        return AlertDialog(
          title: title,
          content: content,
          actions: [
            if(showCancel) TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: Text(cancelText ?? t.cancel)),
            TextButton(onPressed: () => Navigator.of(dctx).pop(true), child: Text(okText ?? t.ok)),
          ],
        );
      },
    );

    if(confirmed == true) {
      onOk();
    }else {
      onCancel?.call();
    }
  }

  static Future<void> showCopyDialog(
    BuildContext context, {
    required String title,
    required String text,
    required void Function(String) showMsg
  }) async {
    await Dialogs.showWidgetContentCopyDialog(
      context,
      title: SelectableText(title),
      content: SelectableText(text),
      showMsg: showMsg,
      textOnCopy: text,
    );
  }

  static Future<void> showWidgetContentCopyDialog(
    BuildContext context, {
    required Widget title,
    required Widget content,
    required void Function(String) showMsg,  // 显示 'Copied' 提示
    required String textOnCopy,  // 点拷贝按钮时拷贝的文字
  }) async {
    await Dialogs.showWidgetContentOkOrNoDialog(
      context,
      title: title,
      content: content,
      okText: t.copy,
      cancelText: t.close,
      onOk: () {
        copyText(textOnCopy);
        showMsg(t.copied);
      }
    );
  }

  // 返回 true，代表显示了购买vip弹窗，不应执行后续的vip操作；否则没显示，应继续执行后续操作。
  static Future<bool> showBuyVipDialogIfThrow(
    BuildContext context, {
    // 若此函数抛异常，将显示购买vip的弹窗，否则不显示
    required Future<void> Function() throwIfIsNotVip,
    required void Function(String) showMsg,
  }) async {
    try {
      await throwIfIsNotVip();

      // 通过检测，调用者应执行后续操作
      return false;
    }catch(e) {
      final String text;
      if(e is NotVipException) {
        text = t.requiresVipLv(vipLv: e.minLv);
      }else if(e is VipExpiredException) {
        text = t.vipExpired;
      }else {
        text = e.toString();
      }

      showWidgetContentOkOrNoDialog(
        context,
        title: SelectableText(t.requiresVip),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(text, style: TextStyle(fontSize: 18),),
            const SizedBox(height: 10),
            SelectableText(buyVipUrl),
          ],
        ),
        onOk: () async {
          await openUrlOrShowErrMsg(url: buyVipUrl, showMsg: showMsg);
        },
        okText: t.buy
      );

      // 未通过检测，调用者应中止后续操作
      return true;
    }
  }

  static Widget _getPlainDialog({
    int initIndex = -1,
    double itemSize = 0,
    required ScrollController scrollController,
    required List<Widget> children,
  }) {
    if(itemSize > 0) {
      initIndex = max(0, initIndex - 2);  // 跳转到目标的前两个条目，不然目标在最上方，不好看
      if(initIndex > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          UI.scrollTo(initIndex, scrollController, itemHeight: itemSize);
        });
      }
    }

    return Center(
      child: Dialog(
        child: Padding(
          padding: EdgeInsetsGeometry.all(12),
          child: SingleChildScrollView(
            controller: scrollController,
            scrollDirection: Axis.vertical,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        ),
      ),
    );
  }




  static Future<void> choosePathDialog(
    BuildContext context,{
    required String title,
    required TextEditingController pathController,
    required String textFiledLabel,
    required void Function(String) showMsg,
    required void Function(String) showMsgLong,
    required void Function() refreshUI,
    required bool trueDirFalseFile,
    required bool? trueExistErrFalseNoExistErrNullNoCheckExist,
    required bool errIfPathEmpty,
    required bool errIfPathNotAbsOrInvalid,
    // 要是上面的预设条件满足不了调用者的验证需求，可传这个函数验证，返回非null则弹窗不会关闭，并且在输入框下显示错误信息
    required String? Function(String? path, FileSystemEntityType?)? errIfCallerConsideredPathInvalid,
    required bool showFileChooserButton,

    required void Function(String path) onOk,
    VoidCallback? onCancel,
    Widget? contentOnTopOfPathChooser,
    Widget? contentOnBottomOfPathChooser,
  }) async {
    void closeDialog(BuildContext context) {
      if(context.mounted) {
        Navigator.of(context).pop(null);
      }
    }

    await showFormDialog(
      context,
      title: title,
      onOk: () async {
        onOk(pathController.text);
      },
      children: [
        if(contentOnTopOfPathChooser != null) contentOnTopOfPathChooser,
        PathChooser(
          path: pathController,
          textFileLabel: textFiledLabel,
          showMsg: showMsg,
          showMsgLong: showMsgLong,
          refreshUI: refreshUI,
          trueDirFalseFile: trueDirFalseFile,
          trueExistErrFalseNoExistErrNullNoCheckExist: trueExistErrFalseNoExistErrNullNoCheckExist,
          errIfPathEmpty: errIfPathEmpty,
          errIfPathNotAbsOrInvalid: errIfPathNotAbsOrInvalid,
          errIfCallerConsideredPathInvalid: errIfCallerConsideredPathInvalid,
          showFileChooserButton: showFileChooserButton,
          onFieldSubmitted: (value) async {
            onOk(value);
            closeDialog(context);
          },
        ),
        if(contentOnBottomOfPathChooser != null) contentOnBottomOfPathChooser,
      ],
    );
  }


  static Future<void> showSingleClickablePlainDialog<T>(
    BuildContext context,
    List<T> list, {
    required String Function(T) itemText,
    required bool Function(T) selected,
    required Future<void> Function(T) onClick,
    Widget? header,
  }) async {
    final scrollController = ScrollController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return _singleClickablePlainDialog(
          context,
          list,
          scrollController: scrollController,
          itemText: itemText,
          selected: selected,
          onClick: onClick,
          header: header,
        );
      }
    );

    try {
      scrollController.dispose();
    }catch(e, st) {
      App.logger.debug(_TAG, "showSingleClickablePlainDialog: dispose scrollController err: $e\n$st");
    }
  }

  static Future<void> showOnOffDialog(
    context, {
    required bool Function(bool trueOnFalseOff) isSelected,
    required Future<void> Function(bool trueOnFalseOff) onClick,
  }) async {
    await Dialogs.showSingleClickablePlainDialog(
      context,
      valuesOnAndOff,
      selected: (it) => isSelected(onOffToBool(it)),
      itemText: (it) => it,
      onClick: (it) async {
        await onClick(onOffToBool(it));
      },
    );
  }

  static Widget _singleClickablePlainDialog<T>(
    BuildContext context,
    List<T> list, {
    required ScrollController scrollController,
    required String Function(T) itemText,
    required bool Function(T) selected,
    required Future<void> Function(T) onClick,
    Widget? header,
  }) {
    final halfWidth = MediaQuery.of(context).size.width / 2;
    final selectedColor = Theme.of(context).primaryColor;

    final children = <Widget>[];
    if(header != null) {
      children.add(header);
    }
    int selectedIndex = -1;
    final double itemSize = 60;

    children.add(const SizedBox(height: 10));

    for(final (index, i) in list.indexed) {
      final isSelected = selected(i);
      if(isSelected) {
        selectedIndex = index;
      }
      children.add(InkWell(
        onTap: () async {
          await onClick(i);

          // 关弹窗
          if(context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: SizedBox(
          height: itemSize,
          width: halfWidth,
          child: Center(
            child: Text(
              itemText(i),
              style: isSelected ? TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: selectedColor
              ) : const TextStyle(fontSize: 18)
            ),
          )
        ),
      ));
    }

    children.add(const SizedBox(height: 10));

    return Dialogs._getPlainDialog(
      initIndex: selectedIndex,
      itemSize: itemSize,
      scrollController: scrollController,
      children: children,
    );
  }

  static Future<String?> showInputDialog(
    BuildContext context, {
    required String title,
    required Function(String) showMsg,
    required Function(String) showMsgLong,
    String? initialValue,
    List<String>? notes,
    bool initSelectAll = true,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    String? hintText,
  }) async {
    return await showDialog<String>(
      context: context,
      builder: (context) => EnterInputDialog(
        title: title,
        hintText: hintText ?? t.pleaseInput,
        initialValue: initialValue,
        showMsg: showMsg,
        showMsgLong: showMsgLong,
        notes: notes,
        initSelectAll: initSelectAll,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
      ),
    );
  }

  static Future<void> showCheckboxDialog(
    BuildContext context, {
    required String title,
    required List<TextValueSelected> options,
    required Future<void> Function(Map<String, TextValueSelected>) onOk,
  }) async {
    final result = await showDialog<Map<String, TextValueSelected>>(
      context: context,
      builder: (context) {
        // 返回值是 Map{value: TextValueSelected}
        return CheckboxDialog(title: title, options: options,);
      },
    );

    if(result == null) {
      return;
    }

    await onOk(result);
  }

  // 使用示例：
  // 1. 显示弹窗前创建一个变量（在函数内创建也行，不必非得作为组件field）
  // ValueNotifier<String> loadingTextNotifier = ValueNotifier(t.loading);
  // 2. 执行任务前显示弹窗
  // 注：不要await，不然后续代码无法执行
  // Dialogs.showLoadingDialog(
  //   context,
  //   textNotifier: loadingTextNotifier,
  //   onCancel: () async {
  //     // 1. 最好在内部捕获异常，不然异常会被dialog吞掉
  //     // 2. 执行任务的函数应该通过页面的state或其他方式感知到任务已取消
  //     // 3. 这里应该等待执行任务函数，确保其执行完毕再取消
  //     setState(() => taskCanceled = true);
  //
  //     while(true) {
  //       await Future.delayed(Duration(millSeconds: 1000));
  //       if(taskAlreadyAborted) {
  //         break;
  //       }
  //     }
  //   },
  // );
  //
  // 3. 执行任务（以下是模拟任务）
  // try{
  //   Timer.periodic(Duration(seconds: 2), (timer) {
  //     valueNotifier.value = randomStringUnsafeButFaster(10);
  //   });
  // }finally {
  //   不管任务是否正常完成，一律调用这个关弹窗，弹窗本身不会自己关闭，一律由调用者控制
  //   if(context.mounted) {
  //     await Dialogs.closeLoadingDialog(context);
  //   }
  // }
  //
  static Future<void> showLoadingDialog(
    BuildContext context,{
    String? title,
    // 改此值，loading text变化
    ValueNotifier<String>? loadingTextNotifier,
    void Function(String)? showMsg,
    void Function(String)? showMsgLong,
    Future<void> Function()? onCancel,
  }) async {
    final halfWidthOfScreen = MediaQuery.of(context).size.width / 2;
    bool cancelPressed = false;
    await showDialog(
      barrierDismissible: false,
      // fullscreenDialog: true,  // 这个不知道干嘛的，好像不是把内容撑满屏幕，也不影响屏蔽点击，所以不用传
      context: context,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: title != null ? SelectableText(title) : null,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // AbsorbPointer 是 Flutter 中的一个用于拦截指针事件（触摸/点击/手势）的 Widget
                // 弹窗本身就可屏蔽外部点击，所以不需要这个了
                // AbsorbPointer(
                //   absorbing: true,
                //   child: ,
                // )

                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: 20),
                    const CircularProgressIndicator(),
                    SizedBox(height: 20),

                    // 这个只会导致关联的组件刷新，不会导致整个函数被执行，也不会导致取消被反复执行
                    if(loadingTextNotifier != null)
                      ValueListenableBuilder<String>(
                        valueListenable: loadingTextNotifier,
                        builder: (context, value, _) {
                          return SizedBox(
                            width: halfWidthOfScreen,
                            child: Center(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SelectableText(value),
                              ),
                            )
                          );
                        },
                      ),
                  ],
                )
              ],
            ),
            actions: onCancel != null ? [
              Center(
                child: TextButton(
                  // 禁用取消按钮可能不好使，因为界面可能不刷新，不过内部的cancelPressed好使
                  onPressed: cancelPressed ? null : () async {
                    // 避免重复点取消重复执行操作
                    if(cancelPressed) {
                      return;
                    }

                    cancelPressed = true;

                    // 执行取消
                    try {
                      await onCancel();
                    }catch(e, st) {
                      App.logger.debug(_TAG, "cancel task err, $e\n$st");
                      showMsgLong?.call("cancel task err: $e");
                    }

                    // x 取消之后不关弹窗，避免和外部的关弹窗冲突
                    // if(context.mounted) {
                    //   Navigator.of(context).pop(null);
                    // }
                  },
                  child: Text(t.cancel)
                )
              ),
            ] : null,
          )
        );
      }
    );
  }

  static Future<void> closeLoadingDialog(BuildContext context) async {
    Navigator.pop(context);
  }

  // 调用 await Dialogs.closeLoadingDialog() 关闭弹窗
  static Future<void> showUnCancelableLoadingDialog(
    BuildContext context,{
    ValueNotifier<String>? loadingTextNotifier,
  }) async {
    await showLoadingDialog(
      context,
      loadingTextNotifier: loadingTextNotifier
    );
  }

  static Future<void> showFormDialog(
    BuildContext context, {
    String? title,
    Future<void> Function()? onOk,
    VoidCallback? onCancel,
    required List<Widget> children,
  }) async {
    void closeDialog(BuildContext context) {
      if(context.mounted) {
        Navigator.of(context).pop(null);
      }
    }

    final _formKey = GlobalKey<FormState>();

    await showDialog<String>(
      context: context,
      builder: (dctx) {
        return AlertDialog(
          title: title != null ? SelectableText(title) : null,
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
          actions: [
            // cancel为null，清路径，关弹窗；非null，调用用户函数
            TextButton(
                onPressed: () {
                  closeDialog(dctx);

                  onCancel?.call();
                },
                child: Text(t.cancel)
            ),

            // onOk为null，验证路径，关弹窗；非null，调用用户自定义函数
            TextButton(
                onPressed: () async {
                  if(!_formKey.currentState!.validate()) {
                    return;
                  }

                  // 得先关弹窗，后调onOk, 不然会影响loadingDialog显示
                  closeDialog(dctx);

                  await onOk?.call();
                },
                child: Text(t.ok)
            ),
          ],
        );
      }
    );
  }



  static Future<void> showCancelableLoadingDialogAndDoTask(
    BuildContext context, {
    required Future<void> Function(
      void Function() throwIfCanceled,
      SyncProgressCb progressCb,
    ) task,
  }) async {
    await showLoadingDialogAndDoTask(
      context,
      cancelable: true,
      task: task,
    );
  }

  static Future<void> showUnCancelableLoadingDialogAndDoTask(
    BuildContext context, {
    required Future<void> Function(
      void Function() throwIfCanceled,
      SyncProgressCb progressCb,
    ) task,
  }) async {
    await showLoadingDialogAndDoTask(
      context,
      cancelable: false,
      task: task,
    );
  }

  static Future<void> showLoadingDialogAndDoTask(
    BuildContext context, {
    required bool cancelable,
    required Future<void> Function(
      void Function() throwIfCanceled,
      SyncProgressCb progressCb,
    ) task,
  }) async {
    try {
      bool taskCanceled = false;
      ValueNotifier<String> progressText = ValueNotifier(t.loading);

      Dialogs.showLoadingDialog(
        context,
        loadingTextNotifier: progressText,
        // loadingDialog做了处理，如果已经点了取消，再点也无效，onCancel只会调用一次，
        // 所以就算已经点了取消也无需禁用取消按钮，但逻辑上来说，禁用更好，不然能点，但点了无效，令人困惑
        onCancel: !cancelable || taskCanceled ? null : () async {
          taskCanceled = true;
          progressText.value = t.canceling;
        }
      );

      void throwIfCanceled() {
        if(taskCanceled || !context.mounted) {
          throw TaskCanceledException();
        }
      }

      void progressCb(String act, int allCount, int currentAt, String relativePath) {
        progressText.value = genSyncProgressText(act, allCount, currentAt, relativePath);
      }


      await task(throwIfCanceled, progressCb);

    }finally {
      // 不管任务是否正常完成，一律调用这个关弹窗，弹窗本身不会自己关闭，一律由调用者控制
      if(context.mounted) {
        await Dialogs.closeLoadingDialog(context);
      }
    }
  }


  static Future<void> showUpdatePackFileSizeDialog(
    BuildContext context, {
    required bool isGlobal,
    required int currentSizeInBytes,
    required int defaultPackFileMaxLenInBytes,
    required void Function(String) showMsg,
    required void Function(String) showMsgLong,
    required Future<void> Function(int newSize) onSave,
  }) async {
    // 注：若想改限制的大小限制，直接改[sizeLimitAtLeast]和[sizeLimitAtMost]即可，
    // 底层没限制，就在这里输入的时候限制了下而已

    final sizeLimitAtLeast = 1;  // MiB
    // 限制最大 100MiB，若太大，每次上传1个小文件，
    // 需要下载超过100MiB，有点太大，
    // 这个只是小文件聚合包的文件大小，超过此大小的文件会单独封包上传
    final sizeLimitAtMost = 100;

    final sizeLimitAtLeastInBytes = 1024 * 1024 * sizeLimitAtLeast;  // Bytes
    final sizeLimitAtMostInBytes = 1024 * 1024 * sizeLimitAtMost;

    final sizeLimit = t.packFileSizeLimit(least: Fs.humanFriendlySize(sizeLimitAtLeastInBytes), most: Fs.humanFriendlySize(sizeLimitAtMostInBytes));
    final sizeNote = t.packFileSizeNote(recommendedMinSizeForDropbox: Fs.humanFriendlySize(defaultPackFileMaxLenInBytes));
    final value = await Dialogs.showInputDialog(
      context,
      title: t.packFileSize,
      initialValue: Fs.humanFriendlySize(currentSizeInBytes),
      showMsg: showMsg,
      showMsgLong: showMsgLong,
      notes: isGlobal ? [sizeLimit, sizeNote] : [t.setToZeroToUseGlobalSettings, sizeLimit, sizeNote]
    );

    if(value == null || value.isEmpty) {
      return;
    }

    final double userInputSize;
    final int userInputSizeInBytes;
    try {
      userInputSize = Fs.parseUserInputSize(value);
      // MiB to Bytes
      // toInt()会取整，截断小数部分
      userInputSizeInBytes = (userInputSize * 1024 * 1024).toInt();
    }catch(e, st) {
      showMsgLong("err: $e");
      App.logger.debug(_TAG, "parse user input size err: $e\n$st");
      return;
    }


    // same as current config
    if(userInputSizeInBytes == currentSizeInBytes) {
      return;
    }


    if(userInputSizeInBytes < sizeLimitAtLeastInBytes) {
      // 若设置的是仓库级配置，允许用户输入0以使用全局设置，否则报错然后返回
      if(isGlobal || userInputSizeInBytes != 0) {
        showMsgLong("err: at least $sizeLimitAtLeast MiB");
        return;
      }
    }

    if(userInputSizeInBytes > sizeLimitAtMostInBytes) {
      showMsgLong("err: at most $sizeLimitAtMost MiB");
      return;
    }

    await onSave(userInputSizeInBytes);
  }

}

