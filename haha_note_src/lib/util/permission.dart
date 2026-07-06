import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/native_util/permission_requester.dart';
import 'package:hahanote_app/widget/buttons.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../i18n/strings.g.dart';
import '../widget/dialogs.dart';

const _TAG = "permission.dart";

const _permissionManageStorage = "manageStorage";
const _permissionDisableBatteryOptimization = "disableBatteryOptimization";

const appNeededPermissionList = [
  _permissionManageStorage,
  _permissionDisableBatteryOptimization,
];

String getTextOfPermission(String permission) {
  if(permission == _permissionManageStorage) {
    return t.manageStorage;
  }else if(permission == _permissionDisableBatteryOptimization) {
    return t.disableBatteryOptimization;
  }else {
    return "";
  }
}

Future<void> doActByPermission(
  BuildContext context,
  String permission, {
  required void Function(String) showMsg,
}) async {
  if(permission == _permissionManageStorage) {
    requestStoragePermissionOnUI(
      onDenied: () async {
        showMsg(t.rejected);
      },
      onGranted: () async {
        showMsg(t.allowed);
      },
    );
  }else if(permission == _permissionDisableBatteryOptimization) {
    await Dialogs.showOkOrNoDialog(
      context,
      title: t.info,
      text: t.openAppInfoToDisableBatteryUsageDesc,
      onOk: () async {
        await openAppSettings();
      }
    );
  }else {
    showMsg("unknow permission: $permission");
  }
}

Future<void> showRequestPermissionDialogIfIsAndroid(
  BuildContext context,{
  required void Function(String) showMsg,
}) async {
  if(!Platform.isAndroid) {
    showMsg("err: is not Android device");
    return;
  }

  if(!context.mounted) {
    return;
  }

  await Dialogs.showOkOrNoDialog(
    context,
    title: t.permissions,
    text: "",
    onOk: () {},
    showCancel: false,
    okText: t.close,
    textContent: SingleChildScrollView(
      child: Column(
        spacing: 20,
        children: [
          TextButton(
            onPressed: () {
              doActByPermission(context, _permissionManageStorage, showMsg: showMsg);
            },
            child: textAndDescButton(context, t.manageStorage, t.manageStorageDesc),
          ),
          TextButton(
            onPressed: () {
              doActByPermission(context, _permissionDisableBatteryOptimization, showMsg: showMsg);
            },
            child: textAndDescButton(context, t.disableBatteryOptimization, t.disableBatteryOptimizationDesc),
          ),
        ],
      ),
    )
  );
}


Future<void> requestStoragePermissionOnUI({
  Future<void> Function()? onDenied,
  Future<void> Function()? onGranted,
}) async {
  if(await _requestStoragePermission()) {
    await onGranted?.call();
  }else {
    await onDenied?.call();
  }
}

Future<bool> _requestStoragePermission() async {
  if(!Platform.isAndroid) {
    return true;
  }


  final sdkInt = (await _getAndroidSdkInt()) ?? 0;

  // 这个鸟东西似乎没什么意义，直接请求manageExternalStorage即可，和安卓10以上13以下的逻辑一样
  // if (sdkInt >= 33) {
  //   // Android 13+: 请求细化媒体权限（按需组合）
  //   final statuses = await [
  //     Permission.photos, // maps to READ_MEDIA_IMAGES
  //     Permission.videos, // maps to READ_MEDIA_VIDEO
  //     Permission.audio,  // maps to READ_MEDIA_AUDIO
  //     Permission.manageExternalStorage
  //   ].request();
  //   return statuses.values.every((s) => s.isGranted);
  // } else

  if(sdkInt >= 30) {
    // Android 11+：推荐使用范围存储或 MANAGE_EXTERNAL_STORAGE 如果确实需要全部文件访问
    // if(await Permission.manageExternalStorage.isGranted) {
    //   return true;
    // }
      // 引导到设置页面申请 All files access
    return (await Permission.manageExternalStorage.request()).isGranted;
  }else {
    // Android 10 及以下：请求读写权限
    // if(await Permission.storage.isGranted) {
    //   return true;
    // }

    return (await Permission.storage.request()).isGranted;
  }
}

// helper: 获取 Android SDK 版本（使用 platform package 或 method channel）
Future<int?> _getAndroidSdkInt() async {
  try {
    // 推荐用 device_info_plus 插件获取 AndroidInfo.version.sdkInt
    // 这里假定 project 已添加 device_info_plus
    // import 'package:device_info_plus/device_info_plus.dart';
    final info = await DeviceInfoPlugin().androidInfo;
    return info.version.sdkInt;
  } catch (_) {
    return null;
  }
}

// 这个选项和在设置页面禁用电池优化允许app在后台运行的选项不同，设了没用，所以废弃
Future<void> deprecated_requestDisableBatteryOptimizaion({
  required void Function(String) showMsg,
}) async {
  try {
    await PermissionRequester.requestDisableBatteryOptimization();
  }catch(e) {
    App.logger.debug(_TAG, "request disable battery optimization err: $e");
  }

  if(await PermissionRequester.isAlreadyDisabledBatteryOptimization()) {
    showMsg(t.disabled);
  }else {
    showMsg(t.notDisabled);
  }
}
