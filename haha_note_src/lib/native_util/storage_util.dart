import 'dart:io';

import 'package:hahanote_app/native_util/common.dart' show appNativeMethodChannel;

import '../i18n/strings.g.dart';

const _TAG = "storage_util.dart";

class StorageUtil {
  /// path names, see: [getStoragePathNameByIdx]
  static Future<List<String>> getStoragePaths() async {
    return [await getExternalStorageRootPath(), await getExternalDataFilesDirPath(), await getInnerDataFilesDirPath()];
  }

  /// path values, see: [getStoragePaths]
  static String getStoragePathNameByIdx(int idx) {
    if(idx == 0) {
      return t.externalStorageRootPathName;
    }

    if(idx == 1) {
      return t.externalDataFilesDirPathName;
    }

    return t.innerDataFilesDirPathName;
  }

  static Future<String> getExternalStorageRootPath() async {
    if(!Platform.isAndroid) {
      return "";
    }

    return await appNativeMethodChannel.invokeMethod('getExternalStorageRootPath');
  }

  static Future<String> getExternalDataFilesDirPath() async {
    if(!Platform.isAndroid) {
      return "";
    }

    return await appNativeMethodChannel.invokeMethod('getExternalDataFilesDirPath');
  }

  static Future<String> getInnerDataFilesDirPath() async {
    if(!Platform.isAndroid) {
      return "";
    }

    return await appNativeMethodChannel.invokeMethod('getInnerDataFilesDirPath');
  }


}
