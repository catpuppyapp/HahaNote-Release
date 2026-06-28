import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/status_item.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/utils.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/time/time_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ClipboardData, Clipboard, PlatformException;
import 'package:markdown/markdown.dart' as md;
import 'package:open_filex_plus/open_filex_plus.dart';
import 'package:path/path.dart' as p;
import 'package:process_runner/process_runner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cloud_disk_note/storage/files/file_path.dart';
import '../config/app_config.dart';
import '../constants/cons.dart';
import '../db/db.dart';
import '../i18n/strings.g.dart';
import '../native_util/open_file.dart';
import '../widget/dialogs.dart';


String formatDateTimeHumanFriendly(DateTime dt) {
  return TimeData.formatDateTime(dt);
}


Future<void> copyText(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

Future<String> readClipboardPlainText(String text) async {
  final data = await Clipboard.getData('text/plain');
  return data?.text ?? '';
}

int compareStringAsNumIfPossible(String str1, String str2, {bool ignoreCase = true}) {
  double? tryParse(String s) {
    if (s.isEmpty) return null;
    // 尝试直接解析；去掉逗号与空白，处理可能的千分位或其他非数字符号
    final cleaned = s.trim().replaceAll(',', '');
    return double.tryParse(cleaned);
  }

  final n1 = tryParse(str1);
  if (n1 != null) {
    final n2 = tryParse(str2);
    if (n2 != null) {
      return n1.compareTo(n2);
    }
  }

  if (ignoreCase) {
    return str1.toLowerCase().compareTo(str2.toLowerCase());
  } else {
    return str1.compareTo(str2);
  }
}

int getNowInSec() {
  return TimeData.nowInSec();
}

Future<String> createParentDirIfNeed(String path) async {
  await File(path).parent.create(recursive: true);
  return path;
}


// 注：不要调用 canLauncherUrl 判断是否能打开url，直接打开即可，判断的不准，有时能打开也提示不能
Future<bool> launchUrlExt(Uri uri) async {
  // 避免内嵌的webview，垃圾，若用webview，比如在授权，我想回到app页面，不点退出回不去，狗屎一样，
  // 一律用外部浏览器打开
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

// expect url like "https://example.com"
Future<bool> launchUrlExtByStr(String urlStr) async {
  final uri = Uri.tryParse(urlStr);
  if (uri == null) {
    return false;
  }

  return await launchUrlExt(uri);
}

// expect email like "abc@example.com", no mailto prefix
Future<bool> launchEmailExt(String email) async {
  final uri = Uri(
    scheme: 'mailto',
    path: email,
  );

  return launchUrlExt(uri);
}

// 参数接受null是为了方便写空值表达式，例如： shortStr(item?.name, 10) ?? other
String? shortStr(String? value, int maxLen, {bool showEllipsis = false}) {
  if(value == null) {
    return null;
  }

  if(value.length > maxLen) {
    return value.substring(0, maxLen) + (showEllipsis ? "…" : "");
  }

  return value;
}

Future<void> openUrlOrShowErrMsg({
  required String url,
  required void Function(String) showMsg,
  String? errMsg,
}) async {
  if (!await launchUrlExtByStr(url)) {
    showMsg(errMsg ?? t.openLinkFailed);
  }
}

Future<void> openEmailOrShowErrMsg({
  required String url,
  required void Function(String) showMsg,
  String? errMsg,
}) async {
  if (!await launchEmailExt(url)) {
    showMsg(errMsg ?? t.openLinkFailed);
  }
}

String statusTypeToString(String statusType) {
  if(statusType == StatusItemType.modified) {
    return t.modified;
  }

  if(statusType == StatusItemType.added) {
    return t.added;
  }

  if(statusType == StatusItemType.deleted) {
    return t.deleted;
  }

  return t.unknown;
}

Color? statusTypeToColor(String statusType) {
  if(statusType == StatusItemType.modified) {
    return Colors.blue;
  }

  if(statusType == StatusItemType.added) {
    return Colors.green;
  }

  if(statusType == StatusItemType.deleted) {
    return Colors.red;
  }

  return null;
}

// 若mime为null，在安卓会推测文件类型，如果不是文本，例如是图片，则会尝试使用外部app打开
// 若mime 传 mimeTextPlain ，则会使用内置文本编辑器将文件当作文本打开（在安卓会使用外部文本编辑器打开文件，若传mimeTextPlain，重点是一定把文件当作文本打开）
// x 废弃使用返回值了，改用页面是否可见来判断了）返回值若为true，代表editor修改并保存了文件，否则没保存。最近文件列表页面可根据此值决定是否从editor返回后刷新页面
Future<bool> openWithInternalEditor(
  String path, {
  required String? mime,
  required String callerTag,
  required BuildContext context,
  required void Function(String) showMsgLong,
}) async {
  if(path.isEmpty) {
    return false;
  }

  try {
    if(FileSystemEntityType.notFound == await getFileType(path)) {
      showMsgLong(t.fileDoesntExist);
      return false;
    }
  }catch(e, st) {
    // 仍将尝试打开文件，但可能会失败
    App.logger.debug(callerTag, "check file exists err (still will try open file, but can be failed): $e\n$st");
  }

  try {
    // 由于安卓调用外部编辑器了，无法在editor关闭文件时记录最后打开文件，所以，统一在这记了，然后文件关闭时，
    // 会在editor再记一下最后编辑位置相关的信息
    await Db.saveFileLastEditPos(FilePath.fromString(path), null);
  }catch(e, st) {
    App.logger.debug(callerTag, "record last opened file err: $e\n$st");
  }

  // 若平台是安卓，如果选择的是内置编辑器，则不进入此代码块，直接使用默认打开；否则尝试使用外部编辑器打开
  final textEditorPackageNameOnOnAndroid = AppConfig.getConfig().textEditorPackageNameOnOnAndroid;
  if(textEditorPackageNameOnOnAndroid.isNotEmpty && Platform.isAndroid) {
    try {
      await NativeOpenFile.openFileOnAndroid(
        path: path,
        mime: mime,
        packageName: textEditorPackageNameOnOnAndroid,
      );

      // 安卓调用外部编辑器，无法轻易判断用户什么时候从其他app返回，所以直接当作没修改，需手动刷新
      // 若想判断，可通过activity的onResume事件判断，但太麻烦，算了
      // 注：await NativeOpenFile.openFileOnAndroid 不会在从其他app切换回来后才返回，所以这里返回true无意义
      // return true;
      // return false;
    }catch(e, st) {
      // 如果是平台异常，代表调用平台代码了（例如调用安卓的java代码），一般是我自己调用的，包含特定的错误码，显示下
      // 其他异常正常显示给用户即可
      if(e is PlatformException) {
        // 如果是未找到editor，说明是安卓平台，没安装任何一个支持的文本编辑器，这时显示弹窗，包含支持的文本编辑器列表
        // 其他情况则显示错误代码和msg
        if(e.code == "EDITOR_NOT_FOUND") {
          if(!context.mounted) return false;

          await Dialogs.showSingleClickablePlainDialog(
            context,
            NativeOpenFile.supportedEditors,
            selected: (it) => false,
            itemText: (it) => it.name,
            onClick: (it) async {
              await openUrl(it.downLink, showMsgLong: showMsgLong);
            },
            header: Padding(
              padding: EdgeInsetsGeometry.directional(top: 10),
              child: SelectableText(t.pleaseInstallAnEditorToOpenFile),
            ),
          );
        }else {
          App.logger.debug(callerTag, "open file err(err code: 10383357): $e\n$st");
          showMsgLong("${e.code}: ${e.message}");
        }

      }else {
        App.logger.debug(callerTag, "open file err(err code: 17211153): $e\n$st");
        showMsgLong("$e");
      }


      // return false;
    }

    // x 实际已经不需要了，安卓改成离开app再返回就刷新了) 安卓无法判断，直接返回false，当作没修改，用户从外部返回后需手动刷新
    return false;
  }

  // 如果是内部文本编辑器不支持的类型，则使用外部程序打开
  if(!isInternalTextEditorSupportedType(p.basename(path), mime: mime)) {
    await openFileInExternal(path, showMsgLong: showMsgLong, callerTag: callerTag);
    return false;
  }

  // 执行到这，非安卓，且是内部文本编辑器支持的类型，使用内部文本编辑器打开

  // 非安卓（内置的re-editor在ios可能也有问题，但我的app不支持ios，所以无所谓），跳转到编辑器页面
  if(!context.mounted) return false;

  final editorChangedFile = await Navigator.pushNamed(
    context,
    Cons.routeEditorOpen,
    arguments: {"path": path},
  );

  // 若editor无返回值，当作改变了文件，返回true，触发recent files页面刷新
  if(editorChangedFile == null) {
    return true;
  }

  if(editorChangedFile is bool) {
    return editorChangedFile;
  }

  return true;
}

Future<void> openUrl(String url, {required void Function(String) showMsgLong}) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    showMsgLong("invalid url");
    return;
  }

  try {
    if (!await launchUrlExt(uri)) {
      showMsgLong("open link failed");
    }
  } catch (e) {
    showMsgLong("open link error: $e");
  }
}


Future<void> openFileInExternal(String path, {required void Function(String)? showMsgLong, required String callerTag}) async {
  try {
    final result = await OpenFilex.open(path);
    if(result.type != ResultType.done) {
      throw "type: ${result.type}, msg: ${result.message}";
    }
  }catch(e, st) {
    showMsgLong?.call("err: $e");
    App.logger.debug(callerTag, "open in ext err: $e\n$st");
  }
}

bool isPcPlatform() {
  return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
}

// bool isMobilePlatform() {
//   // 有个Fuchsia比较特殊，我不知道是移动平台还是pc，但没什么人用，故不作特殊判断
//   return !isPcPlatform();
// }

String reverseStr(String s) {
  if(s.isEmpty) {
    return s;
  }

  return String.fromCharCodes(s.runes.toList().reversed);
}

bool isInternalTextEditorSupportedType(String fileName, {String? mime}) {
  if(mime == mimeTextPlain) {
    return true;
  }

  final name = fileName.toLowerCase();
  return name.endsWith(".txt") || name.endsWith(".md")
      || name.endsWith(".markdown") || name.endsWith(".text")
      || name.endsWith(".log") || name.endsWith(".ini")
      || name.endsWith(".conf") || name.endsWith(".xml")
      || name.endsWith(".json") || name.endsWith(".yml") || name.endsWith(".yaml");
}

IconData getIconByFileName(String fileName, {required bool isDir}) {
  // 除了folder，其他图标一律使用outlined
  if(isDir) {
    return Icons.folder;
  }

  final name = fileName.toLowerCase();
  if(isInternalTextEditorSupportedType(name)) {
    return Icons.text_snippet_outlined;
  }
  
  if(name.endsWith(".mp4") || name.endsWith(".mkv")
      || name.endsWith(".flv") || name.endsWith(".mov")
      || name.endsWith(".avi") || name.endsWith(".webm")
      || name.endsWith(".rmvb") || name.endsWith(".rm")) {
    return Icons.play_circle_outline;
  }

  if(name.endsWith(".jpg") || name.endsWith(".jpeg")
      || name.endsWith(".png") || name.endsWith(".gif")
      || name.endsWith(".webp") || name.endsWith(".svg")
      || name.endsWith(".bmp") || name.endsWith(".tif")
      || name.endsWith(".tiff") || name.endsWith(".ico")) {
    return Icons.image_outlined;
  }

  if(name.endsWith(".mp3") || name.endsWith(".ogg")
      || name.endsWith(".aac") || name.endsWith(".flac")
      || name.endsWith(".ape") || name.endsWith(".wav")
      || name.endsWith(".m4a") || name.endsWith(".amr")
      || name.endsWith(".opus")) {
    return Icons.music_note_outlined;
  }

  return Icons.insert_drive_file_outlined;
}

Future<ProcessRunnerResult> runCmd(
  List<String> cmd, {
  ProcessRunner? runner,
  Directory? workingDirectory,
  bool failOk = false,
}) async {
  ProcessRunner processRunner = runner ?? ProcessRunner(defaultWorkingDirectory: workingDirectory);
  return await processRunner.runProcess(cmd, workingDirectory: workingDirectory, failOk: failOk);

  // 默认情况下，faildOk = false，exitCode不为0本来就会抛异常
  // if (result.exitCode != 0) {
  //   throw result.stderr;
  // }
}

String myMdToHtml(String content) {
  return md.markdownToHtml(
    content,
    extensionSet: md.ExtensionSet.gitHubWeb,  // gitHubWeb 比 gitHubFlavored支持更多特性
  );
}
