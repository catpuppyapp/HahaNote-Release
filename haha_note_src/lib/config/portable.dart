import 'dart:io';
import 'dart:isolate';

import 'package:hahanote_app/util/fs.dart';
import 'package:path/path.dart' as p;

import '../hahanote_lib_sync/app.dart';

const _TAG = "portable.dart";

bool isPortableMode = false;
String exePath = "";

const portableDataDirName = "portable_data";


void initPortableMode({String? debugName}) {
  if(!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    exePath = "";
    isPortableMode = false;
    return;
  }

  final finallyUsedDebugName = debugName ?? Isolate.current.debugName ?? "unknown_isolate";

  exePath = Fs.getExePath();
  if(exePath.isEmpty) {
    App.printLogger.debug(_TAG, "$finallyUsedDebugName: resolve exe path failed, err code: 19492494");
  }

  isPortableMode = exePath.isNotEmpty ? File(p.join(exePath, "portable")).existsSync() : false;

  // App.logger.info(_TAG, "executable path: $exePath, isPortableMode: $isPortableMode");
  // 调用这个函数时logger可能还没就绪，因为log文件路径依赖是否portable，所以，用print打印
  App.printLogger.debug(_TAG, "$finallyUsedDebugName: initPortableMode(): executable path: $exePath, isPortableMode: $isPortableMode");
}

// 由于用的p.join，所以传 name或 path都行，若path则会在便携data目录创建对应子目录
Future<Directory> getDirUnderPortableDataDir(String dirPath) async {
  final dir = Directory(p.join(exePath, portableDataDirName, dirPath));
  await dir.create(recursive: true);
  return dir;
}

// Directory getDirUnderPortableDataDirSync(String dirPath) {
//   final dir = Directory(p.join(exePath, portableDataDirName, dirPath));
//   dir.createSync(recursive: true);
//   return dir;
// }

// 便携模式下 `exePath/portable_data/temp` 相当于非便携模式下win系统的 `temp` 或 linux系统的`tmp` 目录（系统默认临时目录，不同系统路径和名字可能不同）
Future<Directory> getPortableTempDir() async {
  return await getDirUnderPortableDataDir("temp");
}

// 便携模式下 `exePath/portable_data/data` 相当于非便携模式下 `我的文档/haha_note` 目录
Future<Directory> getPortableAppDataDir() async {
  return await getDirUnderPortableDataDir("data");
}

// Directory getPortableAppDataDirSync() {
//   return getDirUnderPortableDataDirSync("data");
// }
