import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/ext/iterable_ext.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:cloud_disk_note_app/native_util/common.dart' show appNativeMethodChannel;

const mimeTextPlain = "text/plain";


class NativeOpenFile {

  static final supportedEditors = [
    // 自动模式会按这个顺序进行尝试打开
    AppInfoAndLink(name: "Markor", downLink: "https://github.com/gsantner/markor/releases", packageName: "net.gsantner.markor"),
    AppInfoAndLink(name: "PuppyGit", downLink: "https://github.com/catpuppyapp/PuppyGit/releases", packageName: "com.catpuppyapp.puppygit.play.pro"),
    AppInfoAndLink(name: "Squircle-CE", downLink: "https://github.com/massivemadness/Squircle-CE/releases", packageName: "com.blacksquircle.ui"),
    AppInfoAndLink(name: "QuickEdit Pro", downLink: "https://play.google.com/store/apps/details?id=com.rhmsoft.edit.pro", packageName: "com.rhmsoft.edit.pro"),
    AppInfoAndLink(name: "QuickEdit", downLink: "https://play.google.com/store/apps/details?id=com.rhmsoft.edit", packageName: "com.rhmsoft.edit"),
    AppInfoAndLink(name: "Acode Paid", downLink: "https://play.google.com/store/apps/details?id=com.foxdebug.acode", packageName: "com.foxdebug.acode"),
    AppInfoAndLink(name: "Acode", downLink: "https://github.com/Acode-Foundation/Acode/releases", packageName: "com.foxdebug.acodefree"),
  ];

  static final supportedEditorsAndAuto = [
    // 默认选中内置，若是内置，直接使用内置打开，若是auto，按支持的列表逐个尝试，若是支持列表中的某个元素，直接使用其打开
    AppInfoAndLink(name: t.builtIn, downLink: "", packageName: ""),
    ...supportedEditors
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
      final found = supportedEditors.firstWhereOrNull((it) => it.packageName == packageName);
      // 若指定的包名无效，则不使用包名，会自动按支持的编辑器顺序尝试打开
      if(found == null) {
        packageNameWillUse = null;
      }
    }


    await appNativeMethodChannel.invokeMethod('openFileWithApp', {
      'path': path,
      'mime': mime,
      'packageName': packageNameWillUse,
    });
  }
}

class AppInfoAndLink {
  final String name;
  final String downLink;
  final String packageName;

  AppInfoAndLink({required this.name, required this.downLink, required this.packageName});

}
