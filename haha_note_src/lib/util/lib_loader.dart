import 'dart:ffi';
import 'dart:io' show Platform, File;

import 'package:hahanote_app/util/fs.dart' show Fs;
import 'package:path/path.dart' as p;

import '../hahanote_lib_sync/app.dart';
import '../hahanote_lib_sync/storage/files/file_path.dart';

const _TAG = "lib_loader.dart";

// 先尝试基于可执行文件加载库（打包发行时可用）；
// 若失败，则直接使用相对路径加载（开发时可用），若还失败则抛异常
void loadLibForPc(String libRelativePath) {
  if(Platform.isAndroid || Platform.isIOS) {
    return;
  }

  final exePath = Fs.getExePath();
  App.logger.info(_TAG, "executable path: $exePath, try loading lib path: $libRelativePath");
  final libPath = FilePath.canonicalizePath(libRelativePath);
  var file = File(p.join(exePath, libPath));
  if (file.existsSync()) {
    // 优先加载可执行文件目录下的库（发行时走这里）
    DynamicLibrary.open(file.absolute.path);
  } else {
    // 若可执行文件目录下无库，则尝试使用相对路径加载（开发时走这里）
    DynamicLibrary.open(libPath);
  }
}
