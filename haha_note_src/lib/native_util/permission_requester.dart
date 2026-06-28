
import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/native_util/common.dart' show appNativeMethodChannel;
import 'package:cloud_disk_note_app/util/app_info.dart';

class PermissionRequester {
  static Future<void> requestDisableBatteryOptimization() async {
    if(!Platform.isAndroid) {
      throw AppException("platform is not android, err code: 10782338");
    }

    await appNativeMethodChannel.invokeMethod('showDisableBatteryOptimizationSettings', {
      'packageName': AppInfo.packageName,
    });
  }

  static Future<bool> isAlreadyDisabledBatteryOptimization() async {
    if(!Platform.isAndroid) {
      throw AppException("platform is not android, err code: 17682755");
    }

    return true == await appNativeMethodChannel.invokeMethod('isAlreadyDisabledBatteryOptimization', {
      'packageName': AppInfo.packageName,
    });
  }
}
