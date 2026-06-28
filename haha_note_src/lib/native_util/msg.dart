
import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/native_util/common.dart' show appNativeMethodChannel;

class NativeMsg {
  static Future<void> showOnAndroid({
    required String msg,
    bool longDuration = false
  }) async {
    if(!Platform.isAndroid) {
      throw AppException("platform is not android, err code: 16484721");
    }

    await appNativeMethodChannel.invokeMethod('showMsg', {
      'msg': msg,
      'longDuration': longDuration,
    });
  }
}
