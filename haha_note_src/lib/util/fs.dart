import 'dart:convert';
import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';
import 'package:hahanote_app/config/portable.dart';
import 'package:hahanote_app/util/byte_count.dart' show ByteCountingSink;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory, getApplicationDocumentsDirectory;

import '../hahanote_lib_sync/pair.dart';

const _TAG = "fs.dart";


abstract class Fs {

  // app 的外部目录：/storage/emulated/0/Android/包名/files
  // static Future<Directory?> getAppExternalStorageFilesDir() async {
  //   final dir = await getExternalStorageDirectory();
  //   if(dir != null) {
  //     await getAndMakeSureDirExists(dir.absolute.path);
  //     App.logger.debug(_TAG, "getAppExternalStorageFilesDir: ${dir.absolute.path}");
  //   }else {
  //     App.logger.debug(_TAG, "getAppExternalStorageFilesDir: dir is null");
  //   }
  //
  //   return dir;
  // }

  static String getExtStoragePath() {
    if(Platform.isAndroid) {
      return '/storage/emulated/0';
    }else if(Platform.isWindows){
      return 'C:/';
    }else {
      return '/';
    }
  }

  // 辅助：格式化大小与时间
  static String readableSize(int bytes) {
    int numAfterDot = 2;
    int count = 1024; // MiB 1024, MB 1000

    if (bytes < count) return '$bytes B';
    final kb = bytes / count;
    if (kb < count) return '${kb.toStringAsFixed(numAfterDot)} KiB';
    final mb = kb / count;
    if (mb < count) return '${mb.toStringAsFixed(numAfterDot)} MiB';
    final gb = mb / count;
    if (gb < count) return '${gb.toStringAsFixed(numAfterDot)} GiB';
    final tb = gb / count;
    return '${tb.toStringAsFixed(numAfterDot)} TiB';
  }

  static String humanFriendlySize(int bytes) {
    return readableSize(bytes);
  }

  static Future<void> countDirSize(
    FileSystemEntity entity, {
    required void Function(int) count,
    required bool Function() canceled
  }) async {
    if(canceled()) {
      count(0);
      return;
    }

    if(entity is File) {
      try {
        count(await entity.length());
      }catch (_) {
        count(0);
      }
    }else if(entity is Directory) {
      try {
        await for (final child in entity.list(followLinks: false)) {
          if(canceled()) {
            return;
          }

          // 如果for循环遍历那里改成 递归: true，则这里可以改成判断，若是文件，则计算大小并追加即可，
          // 就不用递归调用当前函数了，但我不确定哪样性能好，所以暂时先不改
          await countDirSize(child, count: count, canceled: canceled);
        }
      }catch (_) {
        // 忽略无法访问的文件/目录
      }
    }
  }

  // 若是移动（isCopy为假），则调用者需在调用后自行删除src目录
  static Future<void> copyOrMoveFilesOfDirectory(Directory source, Directory destination, {required bool isCopy}) async {
    // 1. 如果目标目录不存在，先创建它
    if (!await destination.exists()) {
      await destination.create(recursive: true);
    }

    // 2. 遍历源目录中的所有实体 (文件或文件夹)
    await for (var src in source.list(followLinks: false)) {
      // 获取实体在目标路径中的新路径
      final target = p.join(destination.path, p.basename(src.path));

      if (src is Directory) {
        // 如果是目录，递归调用
        await copyOrMoveFilesOfDirectory(src, Directory(target), isCopy: isCopy);
        if(!isCopy) {
          await src.delete(recursive: false);
        }
      } else if (src is File) {
        // 如果是文件，直接拷贝
        if(isCopy) {
          await src.copy(target);
        }else {
          await src.rename(target);
        }
      }
    }
  }

  static Future<void> delFileOrDir(String path) async {
    await Directory(path).delete(recursive: true);
  }

  static Future<void> copyOrMovePath(
    String src,
    String targetDir, {
    required bool isCopy,
    // 返回true，代表handler处理了，返回false，代表handler未处理，本函数将采用“合并”模式，若是文件，覆盖，若是目录，合并
    required Future<bool> Function(String srcPath, String targetPath) existsTargetFileHandler
  }) async {
    final srcType = await getFileType(src);
    if(srcType != FileSystemEntityType.file && srcType != FileSystemEntityType.directory) {
      throw AppException("unsupported file type: $srcType, err code: 13991621");
    }

    final srcIsDir = srcType == FileSystemEntityType.directory;

    final srcPath = FilePath.fromString(src);
    final targetDirPath = FilePath.fromString(targetDir);

    final srcPathStr = srcPath.toString();
    final targetDirPathStr = targetDirPath.toString();

    if(targetDirPathStr.startsWith(srcPathStr)) {
      // 'dirs are the same' or 'targetPath is sub of src'
      return;
    }

    // 源和目标相同，创建副本
    var targetPath = targetDirPath.copy().append(p.basename(srcPathStr));
    if(targetPath == srcPath) {
      // 移动一个文件到它自己所在的路径，无效
      // 拷贝则创建副本
      if(!isCopy) {
        return;
      }

      // 生成一个类似：原始文件名(随机字符串).原始文件名扩展 的路径
      // 例如 原始路径为：/abc/123.txt，生成 /abc/123 (copy asdf123).txt
      final nonexistPath = await getANonexistFilePathUnderDir(
        targetDirPathStr,
        fileNamePrefix: "${p.basenameWithoutExtension(srcPathStr)} (copy ",
        fileNameSuffix: ")${p.extension(srcPathStr)}",
        minLen: 8,
      );

      targetPath = FilePath.fromString(nonexistPath);
    }


    final targetType = await getFileType(targetPath.toString());
    if(targetType != FileSystemEntityType.notFound && targetType != srcType) {
      throw AppException("src and target type didn't match, src type: $srcType, target type: $targetType");
    }

    // 源和目标名字一样，调用handler
    if(await targetPath.exists()) {
      // 若handler返回true代表它处理了，我们不用处理了直接返回
      if(await existsTargetFileHandler(srcPathStr, targetPath.toString())) {
        return;
      }
    }

    // 执行操作，如果目标文件存在，覆盖，如果目标目录存在，合并（用源目录的文件覆盖目标目录的文件，源目录没有但目标目录有的文件保持不变）

    if(srcIsDir) {
      final srcDir = srcPath.toDir();
      await Fs.copyOrMoveFilesOfDirectory(srcDir, targetPath.toDir(), isCopy: isCopy);
      if(!isCopy) {
        // 目录应该空了，普通删除即可
        await srcDir.delete(recursive: false);
      }
    }else {  // is File
      if(isCopy) {
        await srcPath.toFile().copy(targetPath.toString());
      }else {
        // will overwrite if target exists
        await srcPath.toFile().rename(targetPath.toString());
      }
    }
  }

  static bool isAppAllowedFileEntityType(FileSystemEntity entity) {
    return entity is File || entity is Directory;
  }


  static Future<String> readShortContent(
    String path, {
    Encoding? encoding,
    int maxLen = 80,
  }) async {
    try {
      final sb = StringBuffer();
      final file = File(path);

      encoding = encoding ?? utf8;


      // 用来忽略空行
      bool lastWrittenIsLineBreak = true;

      // 1. 获取字节流并转换成字符流 (Stream<String>)
      // 注意：这里的 String 可能是单个字符，也可能是多个字符
      out: await for (final chunk in file.openRead().transform(encoding.decoder)) {
        if(chunk.contains('\n')) {
          var nothingWritten = true;
          final lines = (const LineSplitter()).convert(chunk);
          for(var i = 0; i < lines.length; i++) {
            final line = lines[i].trim();
            if(line.isEmpty) {
              continue;
            }


            if(i < lines.length - 1) {
              sb.write('$line\n');
              lastWrittenIsLineBreak = true;
            }else {
              sb.write(line);
              lastWrittenIsLineBreak = false;
            }


            nothingWritten = false;

            if(sb.length >= maxLen) {
              break out;
            }
          }

          if(nothingWritten && !lastWrittenIsLineBreak) {
            sb.write('\n');
            lastWrittenIsLineBreak = true;
          }
        }else {
          final str = chunk.trim();
          if(str.isEmpty) {
            continue;
          }

          sb.write(chunk);
          lastWrittenIsLineBreak = false;
        }

        if(sb.length >= maxLen) {
          break;
        }
      }

      final result = sb.toString().trim();

      // 由于chunk可能是多个字符，所以这个是有可能超的，若超了，截一下
      return result.length > maxLen ? result.substring(0, maxLen) : result;

    } catch (e) {
      App.logger.debug(_TAG, "readShortContent of file err: path=$path, err=$e");
      return "";
    }
  }

  // return 文件内容和文件原始的换行符
  // 本函数只支持处理\r\n和\n，不支持\r
  static Pair<String, String> readFileAndReplaceLineBreakToLfSync(File file) {
    final raf = file.openSync();
    try {
      final buf = List<int>.generate(8192, (idx) => 0, growable: false);
      final bytesRemovedCR = <int>[];
      bool trueCrlfFalseLf = false;
      // 只处理CRLF和LF，不处理纯CR，因为纯CR几乎已经绝迹
      // 加buffer读，或许可减少硬盘io
      var readCount = 0;
      while((readCount = raf.readIntoSync(buf)) > 0) {
        for(var i = 0; i < readCount; i++) {
          final b = buf[i];
          // 移除 \r
          if(b == lineBreakCRByte) {
            trueCrlfFalseLf = true;
            continue;
          }

          bytesRemovedCR.add(b);
        }
      }

      // allowMalformed 为 false会在数据非utf8编码时抛异常，可避免读取二进制文件；
      // 若为true，则会替换异常codeUnit为 U+FFFD (�)
      return Pair(utf8.decode(bytesRemovedCR, allowMalformed: false), trueCrlfFalseLf ? crlf : lf);
    }finally {
      raf.closeSync();
    }
  }

  static Future<String> readFileAsStr(
    File file, {
    Encoding? encoding,
    bool returnEmptyIfFileDeleted = false
  }) async {
    if(returnEmptyIfFileDeleted && !await file.exists()) {
      return "";
    }

    return await file.readAsString(encoding: encoding ?? utf8);
  }

  static int getStrBytesLen(
    String str, {
    Encoding? encoding,
  }) {
    encoding = encoding ?? utf8;

    var count = 0;
    // ByteCountingSink 接收的参数是个回调，只有在close时才会被调用，
    // 并不是每次转换后都调用，所以不用担心每次转换都调用而浪费性能
    final sink = ByteCountingSink((n) => count = n);
    // 逐chunk转换，然后sink的 add会被调用，每次调用会记数，就相当于逐字符转换，
    // 然后累加每个字符转换后的字节数，不会创建中间数组，因此性能最好
    final chunked = encoding.encoder.startChunkedConversion(sink);
    chunked.add(str);
    chunked.close();

    return count;
  }

  static void writeStrToFileSync(File file, String str) {
    file.writeAsStringSync(str, flush: true);
  }

  static Future<String> getAppDataDirPath() async {
    // windows下是我的文档；安卓下是app私有目录/data/data/包名/app_flutter
    final docDir = isPortableMode ? await getPortableAppDataDir() : await getApplicationDocumentsDirectory();
    // 我的文档/haha_note
    final appDataDir = Directory(p.join(docDir.absolute.path, "haha_note"));
    await appDataDir.create(recursive: true);
    return appDataDir.absolute.path;
  }


  static Future<String> createDirUnderAppDataDir(String dirName) async {
    final dir = Directory(p.join(await getAppDataDirPath(), dirName));
    await dir.create(recursive: true);
    return dir.absolute.path;
  }


  static Future<String> getDbDirPath() async {
    return createDirUnderAppDataDir("db");
  }

  static Future<String> getUserTlsCertDirPath() async {
    return createDirUnderAppDataDir("user_tls_cert");
  }

  static Future<String> getLogDirPath() async {
    return createDirUnderAppDataDir("log");
  }

  static Future<String> getLogFilePath() async {
    final file = File(p.join(await getLogDirPath(), "log.txt"));
    // 若文件存在不会重复创建，除非 exclusive传true（可选参数，默认false）
    await file.create(recursive: true);
    // 若日志文件大于5mib，删除
    if(await file.length() > 5 * 1024 * 1024) {
      try {
        await file.delete();
      }catch(e, st) {
        App.logger.debug(_TAG, "delete log file failed, err: $e\n$st");
      }
    }

    return file.absolute.path;
  }


  static Future<String> getAppTempDirPath() async {
    final tempDir = isPortableMode ? await getPortableTempDir() : await getTemporaryDirectory();
    await tempDir.create(recursive: true);
    return tempDir.absolute.path;
  }

  static Future<File> createTempFile({String prefix = "temp", String suffix = ".temp"}) async {
    final appTempDirPath = await getAppTempDirPath();
    final fileName = '${prefix}_${randomStringUnsafeButFaster(20)}$suffix';
    final file = File(p.join(appTempDirPath, fileName));
    await file.create();
    return file;
  }

  static Future<TempDir> createTempDirUnderAppTempDirPath(String prefix) async {
    return TempDir.create(await getAppTempDirPath(), prefix);
  }

  // 返回的是exe所在目录的path，不是exe本身的path，例如 exe路径为：C:\app\abc.exe，本函数会返回C:\app
  static String getExePath() {
    // Platform.resolvedExecutable 返回的是exe文件的完整路径，所以需要取父目录
    return File(Platform.resolvedExecutable).parent.absolute.path;
  }

  static const lineBreakCRByte = 0x0D;  // \r in utf8 (and ascii, utf8是ascii的超集，所以兼容)，十进制的13
  static const lineBreakLfByte = 0x0A;  // \n in utf8 (and ascii, utf8是ascii的超集，所以兼容)，十进制的10
  static const crlf = "\r\n";
  static const cr = "\r";
  static const lf = "\n";
  static Future<String> detectLineBreakOfStream(Stream<List<int>> stream) async {
    final r = lineBreakCRByte;  // \r
    final n = lineBreakLfByte;  // \n
    bool foundR = false;
    bool foundN = false;

    await for(final bytes in stream) {
      // maybe never empty?
      if(bytes.isEmpty) {
        continue;
      }

      if(!foundR) {
        final rI = bytes.indexOf(r);
        if(rI >= 0) {
          foundR = true;

          // 如果rI不是最后一个索引，看下它之后的一个字符是否是\n；
          // 若rI是最后一个索引，则在下次循环检测第一个字符是否是\n
          if(rI < bytes.length - 1) {
            foundN = bytes[rI + 1] == n;
            break;
          }
        }
      }else {
        foundN = bytes[0] == n;
        break;
      }

      if(!foundN) {
        final nI = bytes.indexOf(n);
        if(nI >= 0) {
          foundN = true;
          break;
        }
      }
    }

    if(foundR && foundN) {
      return crlf;
    }

    if(foundN && !foundR) {
      return lf;
    }

    if(!foundN && foundR) {
      return cr;
    }

    // 两个都没找到，文件可能为空，返回 lf
    return lf;
  }

  // 期望输入：10 MiB，返回 10。(暂时实现成无视空格后面的值，由调用者自行判断)
  static double parseUserInputSize(String value) {
    final arr = value.split(" ");
    return double.parse(arr[0]);
  }

}
