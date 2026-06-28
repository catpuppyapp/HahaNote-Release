import 'package:package_info_plus/package_info_plus.dart';

import '../cloud_disk_note/app.dart';

const _TAG = "app_info.dart";

abstract class AppInfo {
  static String appName = "";
  static String packageName = "";
  static String version = "";
  static String buildNumber = "";

  static Future<void> init({bool printInfo = true}) async {
    try {
      final info = await PackageInfo.fromPlatform();
      appName = info.appName;        // 应用名称
      packageName = info.packageName;// 包名（Android）/ bundleId（iOS）
      version = info.version;        // 版本号（例如 "1.2.3"）
      buildNumber = info.buildNumber;// 构建号（例如 "45"）

      if(printInfo) {
        App.logger.info(_TAG, 'app info: appName: $appName, packageName: $packageName, version: $version, buildNumber: $buildNumber');
      }
    }catch(e, st) {
      App.logger.err(_TAG, 'get app info err: $e\n$st');
    }
  }
}
