import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/sync.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart';
import 'package:path/path.dart' as p;


// 返回值若为 true，递归扫描当前目录，否则跳过（例如app数据目录，就可以通过返回false来跳过扫描）
typedef FileForEach = Future<bool> Function(FileSystemEntity);

Future<bool> isEmptyDir(Directory dir) async {
  try {
    final lister = dir.list(followLinks: false);
    await for (final _ in lister) {
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}




Future<void> _scan(
  String rootPath,
  Directory dir,
  FileForEach forEach,
) async {
  // final relativePath = rootPath == dir.absolute.path ? FilePath() : FilePath.fromString(genRelativePath(rootPath, dir.absolute.path), isRelative: true);
  // final parentMatchIndex = relativePath.value.isEmpty ? false : (index?.contains(relativePath) ?? false);
  await for (final item in dir.list(followLinks: false)) {
    // 若forEach返回假则不会扫描此目录
    if(await forEach(item)) {
      if(item is Directory) {
        await _scan(rootPath, item, forEach);
      }
    }
  }

  // x 废弃，更不更新目录的IndexItem并无意义，因为如果改目录内已有文件的内容，目录修改时间并不会变化，所以还得检测每个文件的修改时间
  // 目录下的条目都遍历完了，更新目录索引
  // index?.add(relativePath, IndexItem.fromDir(dir));
}


Future<void> forEachFiles(
  String rootPath,
  FileForEach forEach,
) async {
  final root = Directory(rootPath);
  if (!await root.exists()) {
    throw StateError("path doesn't exist: path = $rootPath");
  }

  if (!await isEmptyDir(root)) {
    await _scan(rootPath, root, forEach);
  }
}


/// 注意并发问题，有可能两个线程同时判断一个文件不存在，然后并发创建，不一定最后会是哪个文件存在于对应路径
/// return file full path
Future<String> getANonexistFilePathUnderDir(
  String basePath, {
  String fileNamePrefix = "",
  String fileNameSuffix = ".temp",
  final int minLen = 16,
  final int maxLen = 24,
}) async {
  String genPath(int randomLen) {
    return p.join(basePath, randomString(randomLen, prefix: fileNamePrefix, suffix: fileNameSuffix));
  }

  // 超过次数还没找到一个不存在的文件名则增加随机字符串长度
  final shortLenMaxTries = 5;
  int triesCount = 0;

  var path = "";
  while(true) {
    path = genPath(triesCount > shortLenMaxTries ? maxLen : minLen);
    if(FileSystemEntityType.notFound == await getFileType(path)) {
      break;
    }

    // 如果生成随机字符串超过一定次数都还没生成一个在当前目录不存在的文件，
    // 则增加随机字符串长度
    if(triesCount <= shortLenMaxTries) {
      triesCount++;
    }
  }

  return path;
}


Future<FileSystemEntityType> getFileType(String fullPath) {
  return FileSystemEntity.type(fullPath, followLinks: false);
}

FileSystemEntityType getFileTypeSync(String fullPath) {
  return FileSystemEntity.typeSync(fullPath, followLinks: false);
}

/// return file full path
// Future<File> copyFileToDirWithRandomName(File file, Directory dir) async {
//   final target = await getANonexistFilePathUnderDir(dir.absolute.path);
//   return file.copy(target);
// }

Future<File> getFileAndMakeSureParentDirExist(String path) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  return file;
}

Future<Directory> getAndMakeSureDirExists(String path) async {
  // 重复创建不会报错，所以不用检查目录是否已存在
  return Directory(path).create(recursive: true);
}

Future<void> writeStreamToFile(
  File file,
  Stream<List<int>> data, {
  ThrowIfInterrupted? throwIfInterrupted
}) async {
  final ioSink = file.openWrite();

  try {
    if(throwIfInterrupted != null) {
      await for(final d in data) {
        throwIfInterrupted.call();
        ioSink.add(d);
      }
    }else {
      await ioSink.addStream(data);
    }
  }finally {
    await ioSink.flush();
    await ioSink.close();
  }
}

Future<void> writeBytesToFile(File file, List<int> data) async {
  final ioSink = file.openWrite();
  ioSink.add(data);
  await ioSink.flush();
  await ioSink.close();
}

Future<void> writeStrToFile(File file, String str) async {
  final ioSink = file.openWrite();
  ioSink.write(str);
  await ioSink.flush();
  await ioSink.close();
}

Future<List<int>> readBytesFromFile(File file) async {
  final bb = BytesBuilder(copy: false);
  await for(final b in file.openRead()) {
    bb.add(b);
  }

  return bb.takeBytes();
}

Future<void> appendStreamToFile(File file, Stream<List<int>> data) async {
  final ioSink = file.openWrite(mode: FileMode.writeOnlyAppend);
  await ioSink.addStream(data);
  await ioSink.flush();
  await ioSink.close();
}

T? mapGetOrNull<T>(Map<String, dynamic> map, String key) {
  final value = map[key];
  // null is 任何类型 都返回false，即使是可空类型，例如 null is Object?，也返回false，
  // 所以，若value是null，下面的表达式必然返回null
  return value is T ? value : null;
}

/// [callerPositionCode] 用来定位调用者在代码中的位置
Future<FileSystemEntityType> throwIfPathIsNotFileOrDir(String path, int callerPositionCode) async {
  final type = await getFileType(path);
  if(type != FileSystemEntityType.file && type != FileSystemEntityType.directory) {
    throw AppException("file type is not supported: $type, err code: $callerPositionCode");
  }

  return type;
}

Future<bool> isFileExistsAndEmpty(File file) async {
  if(!await file.exists()) {
    return false;
  }

  await for(final b in file.openRead(0, 1)) {
    // 至少有一个字节
    if(b.isNotEmpty) {
      return false;
    }
  }

  // 文件存在且是空文件（一个字节都没有）
  return true;
}


Future<bool> isFileNonExistsOrEmpty(File file) async {
  if(!await file.exists()) {
    // 文件不存在
    return true;
  }

  await for(final b in file.openRead(0, 1)) {
    // 至少有一个字节
    if(b.isNotEmpty) {
      return false;
    }
  }

  // 文件是空文件（一个字节都没有）
  return true;
}

// 目录不存在或空目录，返回真，否则返回假
bool isDirEmptyOrNoExistsSync(String path) {
  final dir = Directory(path);
  if(!dir.existsSync()) {
    return true;
  }

  for(final it in dir.listSync(recursive: false, followLinks: false)) {
    return false;
  }

  return true;
}

Future<Uint8List> streamToBytes(Stream<List<int>> stream) async {
  final bb = BytesBuilder(copy: false);
  await for(final b in stream) {
    bb.add(b);
  }

  return bb.takeBytes();
}

Future<void> deleteFileIfExists(File file) async {
  // exists判断使路径为目录时返回假避免删目录
  if(await file.exists()) {
    // recursive为true降低删除出错的概率，否则即使路径是文件也有可能删除出错，原因不明
    await file.delete(recursive: true);
  }
}

Future<void> cancelableDelete(
  Directory targetDir, {
  required ThrowIfInterrupted? throwIfInterrupted,
  required SyncProgressCb? progressCb,
}) async {
  progressCb?.call(SyncProgressAct.deleting, 0, 0, "");
  if(!await targetDir.exists()) {
    return;
  }

  // 用循环主要是为了响应 throwIfInterrupted
  await for(final file in targetDir.list(recursive: true, followLinks: false)) {
    throwIfInterrupted?.call();
    // x 已解决，把取消按钮改成固定水平居中显示了）这个路径显示了也看不清而且还导致弹窗大小变化，点不到文字，所以不显示了
    progressCb?.call(SyncProgressAct.deleting, 0, 0, file.path);

    if(file is File) {
      // 若不递归删除，即使文件也有可能删除失败，原因不明
      await file.delete(recursive: true);
    }
  }

  throwIfInterrupted?.call();

  progressCb?.call(SyncProgressAct.deleting, 0, 0, targetDir.path);

  // 删除剩余的空目录
  await targetDir.delete(recursive: true);
}

