
import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/native_util/common.dart' show appNativeMethodChannel;

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
