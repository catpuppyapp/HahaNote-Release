
import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/storage/msg/msg.dart' show Msg;
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/repo.dart' show Repo;

import '../../crypto/key_data.dart' show KeyData;
import '../files/file_info.dart' show FileInfo;
import 'package:path/path.dart' as p;

import '../utils.dart' show isEmptyDir;

class RemoteStorageUtil {
  // 获取在 remotes/files 目录下的文件信息
  static Future<void> forEachFiles(
    KeyData contentKeyData,
    Directory remoteFilesDir,
    void Function(FileInfo) forEach,
  ) async {
    await for (final item in remoteFilesDir.list(followLinks: false)) {
      if (item is Directory) {
        // dir is empty
        if(await isEmptyDir(item)) {
          continue;
        }

        // file doesn't exist
        final fileInfoEncrypted = File(p.join(item.absolute.path, Repo.remoteDataFileName));
        if(!await fileInfoEncrypted.exists()) {
          continue;
        }

        // 解密file info为对象，然后过滤，然后添加到list
        final fileInfo = await FileInfo.decrypt(contentKeyData, fileInfoEncrypted);

        // for each
        forEach(fileInfo);
      }

    }
  }


  static Future<void> forEachMsgs(
    KeyData contentKeyData,
    Directory remoteMsgDir,
    void Function(Msg) forEach,
  ) async {
    await for (final item in remoteMsgDir.list(followLinks: false)) {
      if (item is Directory) {
        // dir is empty
        if(await isEmptyDir(item)) {
          continue;
        }

        // file doesn't exist
        final encryptedData = File(p.join(item.absolute.path, Repo.remoteDataFileName));
        if(!await encryptedData.exists()) {
          continue;
        }

        // 解密file info为对象，然后过滤，然后添加到list
        final data = await Msg.decrypt(contentKeyData, encryptedData);

        // for each
        forEach(data);
      }

    }
  }

  // TODO clean remote data
  static void clean() {
    // 优先删除远程，然后再拉取一下，
    // 标记一个强制远程覆盖本地，把本地有的远程没的都删了，就行了
    // 需要考虑如果部分删除成功，后果会怎样？不能有问题

    //files目录：
    // 删除已删除条目
    // 删除忽略的条目
    // 删除已经被其他文件cover的空目录

    // objects目录：
    // 删除所有无关联到任何files的objects

  }
}

// abstract class RemoteFileFilter {
//   static bool onlyFile(FileInfo fileInfo) {
//     final latest = fileInfo.getLatestVersion();
//     return !latest.isDeleted() && latest.isFile();
//   }
//
//   static bool onlyDir(FileInfo fileInfo) {
//     final latest = fileInfo.getLatestVersion();
//     return !latest.isDeleted() && latest.isDir();
//   }
//
//   static bool dirAndFile(FileInfo fileInfo) {
//     final latest = fileInfo.getLatestVersion();
//     return !latest.isDeleted();
//   }
//
//   static bool onlyDeleted(FileInfo fileInfo) {
//     final latest = fileInfo.getLatestVersion();
//     return latest.isDeleted();
//   }
//
//   /// get file and dir and deleted items
//   static bool all(FileInfo fileInfo) {
//     return true;
//   }
//
// }
