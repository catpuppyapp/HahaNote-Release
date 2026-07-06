
import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/virtual_file.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart' show isDeletedForRepo;
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart';
import 'package:path/path.dart' as p;

// List结构比Map简单，更省内存，性能更好；Map能给参数命名，代码可读性更好
Future<List> computeHash(List args) async {
  final String tempDirBasePath = args[0];
  final String workdirFileEntityPath = args[1];
  final String workdirBasePath = args[2];
  final List<int> contentKeyDataBytes = args[3];

  final tempDir = await TempDir.fromDir(Directory(tempDirBasePath));
  final virtualFile = await VirtualFile.fromWorkdirPath(workdirBasePath, workdirFileEntityPath, tempDir);
  final contentKeyData = await KeyData.readFromStream(Stream.value(contentKeyDataBytes));

  final hashOfWorkdirFile = await virtualFile.hashWithKeyData(contentKeyData);

  final List result = [];
  result.add(hashOfWorkdirFile);  // hashOfWorkdirFile
  result.add(await virtualFile.length());  // workdirFileCopyLen
  result.add(await virtualFile.toTransferableList());  // virtualFile
  // 通过这个参数让调用者读取结果时知道数据和workdir哪个文件关联
  result.add(workdirFileEntityPath);  // workdirFileEntityPath
  return result;
}

Future<dynamic> echo(dynamic args) async {
  final String data = args["data"];
  return {"data": data};
}

Future<List> checkFileDeleted(List args) async {
  final String workdirBasePath = args[0];
  final String relativePath = args[1];

  final workdirFileFullPath = p.join(workdirBasePath, relativePath);
  final deleted = await isDeletedForRepo(workdirFileFullPath);

  final List result = [];
  result.add(deleted);

  if(deleted) {
    final filePath = FilePath.fromString(relativePath, isRelative: true);
    result.add(filePath.toUnixPathStr());
    final List<int> contentKeyDataBytes = args[2];
    final contentKeyData = await KeyData.readFromStream(Stream.value(contentKeyDataBytes));
    result.add(await filePath.toOidStr(contentKeyData));
  }

  return result;
}
