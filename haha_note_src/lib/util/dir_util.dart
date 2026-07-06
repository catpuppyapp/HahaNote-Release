import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/util/fs.dart' show Fs;


const _TAG = "dir_util.dart";


typedef MatchCallback = bool Function(int srcIdx, String srcItem);
typedef MatchedCallback = void Function(int srcIdx, String srcItem);
typedef CanceledCallback = bool Function();



class DirSearchUtil {
  /// 真正的广度优先搜索，一层一层地查找
  static Future<void> realBreadthFirstSearch({
    required Directory dir,
    required MatchCallback match,
    required MatchedCallback matchedCallback,
    required CanceledCallback canceled,
  }) async {
    final subDirs = <FileSystemEntity>[];
    await _addAllFilesToList(dir, subDirs, canceled);
    if (canceled()) return;

    while (subDirs.isNotEmpty) {
      if (canceled()) return;

      final subDirsCopy = subDirs.toList(growable: false);
      subDirs.clear();

      for (var i = 0; i < subDirsCopy.length; i++) {
        if (canceled()) return;

        final subDir = subDirsCopy[i];
        final subDirPath = subDir.absolute.path;
        if (match(i, subDirPath)) {
          matchedCallback(i, subDirPath);
        }

        if (subDir is Directory) {
          await _addAllFilesToList(subDir, subDirs, canceled);
        }
      }
    }
  }

  static Future<void> _addAllFilesToList(
    Directory dir,
    List<FileSystemEntity> subDirs,
    CanceledCallback canceled,
  ) async {
    // 由于有可能没权限读取目录，所以可能会抛异常，必须捕获，不然搜索目录会中断
    try {
      if (!await dir.exists()) return;

      await for(final d in dir.list(followLinks: false)) {
        if (canceled()) return;
        // 只添加文件和目录
        if(Fs.isAppAllowedFileEntityType(d)) {
          subDirs.add(d);
        }
      }
    }catch(e) {
      App.logger.debug(_TAG, "list dir err: $e");
    }
  }
}
