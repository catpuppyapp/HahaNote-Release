import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/ext/iterable_ext.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/native_util/common.dart' show appNativeMethodChannel;
import 'package:hahanote_app/util/util.dart';

const mimeTextPlain = "text/plain";


class NativeOpenFile {

  static final supportedPcEditors = [
    AppInfoAndLink.system,
    const AppInfoAndLink(name: "Zed", downLink: "https://zed.dev/download", packageName: "zed"),
    const AppInfoAndLink(name: "VSCodium", downLink: "https://github.com/VSCodium/vscodium/releases", packageName: "codium"),
    const AppInfoAndLink(name: "VSCode", downLink: "https://code.visualstudio.com/Download", packageName: "code"),
    const AppInfoAndLink(name: "Notepad++", downLink: "https://notepad-plus-plus.org/downloads", packageName: "notepad++"),
  ];


  static final supportedAndroidEditors = [
    AppInfoAndLink.system,
    const AppInfoAndLink(name: "Markor", downLink: "https://github.com/gsantner/markor/releases", packageName: "net.gsantner.markor"),
    const AppInfoAndLink(name: "PuppyGit", downLink: "https://github.com/catpuppyapp/PuppyGit/releases", packageName: "com.catpuppyapp.puppygit.play.pro"),
    const AppInfoAndLink(name: "Squircle-CE", downLink: "https://github.com/massivemadness/Squircle-CE/releases", packageName: "com.blacksquircle.ui"),
    const AppInfoAndLink(name: "QuickEdit Pro", downLink: "https://play.google.com/store/apps/details?id=com.rhmsoft.edit.pro", packageName: "com.rhmsoft.edit.pro"),
    const AppInfoAndLink(name: "QuickEdit", downLink: "https://play.google.com/store/apps/details?id=com.rhmsoft.edit", packageName: "com.rhmsoft.edit"),
    const AppInfoAndLink(name: "Acode Paid", downLink: "https://play.google.com/store/apps/details?id=com.foxdebug.acode", packageName: "com.foxdebug.acode"),
    const AppInfoAndLink(name: "Acode", downLink: "https://github.com/Acode-Foundation/Acode/releases", packageName: "com.foxdebug.acodefree"),
  ];


  static final supportedPcEditorsAndBuiltIn = [
    AppInfoAndLink.builtIn,
    ...supportedPcEditors
  ];


  static final supportedAndroidEditorsAndBuiltIn = [
    // 默认选中内置，若是内置，直接使用内置打开 (过去空字符串代表"Auto"，会逐个尝试使用支持的外部编辑器打开文件)
    AppInfoAndLink.builtIn,
    ...supportedAndroidEditors
  ];

  static Future<void> openFileOnAndroid({
    required String path,
    String? mime,  //不指定则由安卓端guess
    String? packageName, // 指定要用哪个包名打开，不指定弹出系统文件选择器
  }) async {
    if(!Platform.isAndroid) {
      throw AppException("platform is not android");
    }

    String? packageNameWillUse = packageName;
    if(packageName != null && packageName.isNotEmpty) {
      final found = supportedAndroidEditors.firstWhereOrNull((it) => it.packageName == packageName);
      // 若指定的包名无效，则不使用包名，会自动按支持的编辑器顺序尝试打开
      if(found == null) {
        packageNameWillUse = null;
      }
    }


    await appNativeMethodChannel.invokeMethod('openFileWithApp', {
      'path': path,
      'mime': mime,
      'packageName': packageNameWillUse,  // 为null则逐个尝试支持的编辑器
    });
  }

  static Future<void> openFileOnPc({
    required String path,
    required String packageName,
    required String callerTag,
    required void Function(String) showMsgLong,
  }) async {
    if(!isPcPlatform()) {
      throw AppException("platform is not pc");
    }

    if(packageName == AppInfoAndLink.system.packageName) {
      // 若是使用SYSTEM默认关联程序打开，则调用此函数，此函数在pc打开文件会有写权限，
      // (btw 若在安卓，默认只读权限，所以我在安卓手写的intent添加写权限启动activity)
      await openFileInExternal(path, showMsgLong: showMsgLong, callerTag: callerTag);
      return;
    }

    await runCmd([packageName, path]);
  }

}

class AppInfoAndLink {
  static final builtIn = AppInfoAndLink(name: t.builtIn, downLink: "", packageName: "");
  static final system = AppInfoAndLink(name: t.system, downLink: "", packageName: "SYSTEM");

  final String name;
  final String downLink;
  final String packageName;

  const AppInfoAndLink({required this.name, required this.downLink, required this.packageName});

}
