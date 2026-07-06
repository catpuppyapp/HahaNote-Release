import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:open_filex_plus/open_filex_plus.dart';

import '../hahanote_lib_sync/storage/files/file_path.dart';
import '../hahanote_lib_sync/storage/utils.dart';

const _TAG = "reveal_file.dart";

// showMsgLong用来显示错误
Future<void> revealFile(String filePath, {required void Function(String) showMsgLong}) async {
  try {
    // x 能，和预期一致）测试外部调用当前函数不await，然后内部函数_revealFile抛异常，这里能不能正常捕获，期望能
    await _revealFile(filePath);
  }catch(e, st) {
    App.logger.debug(_TAG, "revealFile err: $e\n$st");
    showMsgLong("revealFile err: $e");
  }
}

/// 在系统文件管理器中显示文件
/// 桌面端（Win/Mac/Linux）：打开资源管理器并高亮选中该文件
/// 移动端（Android/iOS）：优雅降级为打开文件所在的父目录
Future<void> _revealFile(String path) async {
  // 用FilePath处理下，返回的file的path会替换成对应系统路径分隔符，一般应该不需要，
  // 不过替换下也好，免得分隔符不对，打不开文件夹（是有可能发生的）
  final filePath = FilePath.fromString(path);
  // 判定存在与否其实无所谓，直接打开即可，系统的文件管理器应该有错误检测
  // if(!await filePath.exists()) {
  //   throw "path not found";
  // }

  // 不能直接用file判断，dir会当作不存在
  // if(!await file.exists()) {
  //   throw "file not found";
  // }

  final absolutePath = filePath.toString();
  final parentDirPath = filePath.parent().toString();

  if(Platform.isWindows) {
    await Process.run('explorer.exe', ['/select,', absolutePath]);
  }else if(Platform.isMacOS) {
    await Process.run('open', ['-R', absolutePath]);
  }else if(Platform.isLinux) {
    // Linux: 优先通过 DBus 唤起原生文件管理器并高亮选中
    final result = await Process.run('dbus-send', [
      '--session',
      '--print-reply',
      '--dest=org.freedesktop.FileManager1',
      '/org/freedesktop/FileManager1',
      'org.freedesktop.FileManager1.ShowItems',
      'array:string:"file://$absolutePath"',
      'string:""'
    ]);

    // 如果用户的桌面环境不支持 DBus（或执行失败），降级为直接打开父目录
    if (result.exitCode != 0) {
      await Process.run('xdg-open', [parentDirPath]);
    }
  }else if(Platform.isAndroid || Platform.isIOS) {
    // 移动端：没有"高亮选中"的系统 API。
    // 最符合用户直觉的替代方案是：调起系统的 Intent，直接打开该文件所在的目录。
    final result = await OpenFilex.open(parentDirPath);

    // 如果某些高度定制的 Android 手机连目录都不允许直接 open，
    // 则退一步，直接弹出选择框让用户操作这个文件本身。
    if(result.type != ResultType.done) {
      await OpenFilex.open(absolutePath);
    }
  }
}
