import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/native_util/common.dart' show appNativeMethodChannel;
import 'package:flutter/services.dart';

const _TAG = "TaskMan";

class TaskMan {
  static Future<void> moveToBackground() async {
    if(!Platform.isAndroid) {
      return;
    }

    try {
      await appNativeMethodChannel.invokeMethod('moveToBackground');
    }catch(e, st) {
      App.logger.debug(_TAG, "call moveToBackground err: $e\n$st");

      // 正常退出兜底（相当于安卓平台按返回键时执行的操作）
      await SystemNavigator.pop();
    }
  }

  static Future<void> startForegroundService() async {
    if(!Platform.isAndroid) {
      return;
    }

    try {
      await appNativeMethodChannel.invokeMethod('startForegroundService');
    }catch(e, st) {
      App.logger.debug(_TAG, "call startForegroundService err: $e\n$st");
    }
  }

  static Future<void> stopForegroundService() async {
    if(!Platform.isAndroid) {
      return;
    }

    try {
      await appNativeMethodChannel.invokeMethod('stopForegroundService');
    }catch(e, st) {
      App.logger.debug(_TAG, "call stopForegroundService err: $e\n$st");
    }
  }

}
