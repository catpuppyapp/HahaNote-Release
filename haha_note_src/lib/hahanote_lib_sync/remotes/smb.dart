import 'dart:io';
import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart' show RemoteException;
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/http.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart' show RemoteConfig, RemoteConfigDataForWebdav, RemoteConfigDataForSmb;
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart' show TempDir;
import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show doInterruptibleTask, safeDeleteFile;
import 'package:webdav_client/webdav_client.dart' as webdav_client;

import '../app.dart';


const _TAG = "smb.dart";

class Smb extends Remote {
  @override
  RemoteType get type => RemoteType.smb;

  // 先设置成假，doInit时会自动探测
  @override
  bool supportAutoCreateNonexistsPath = false;

  @override
  bool isChild;

  @override
  bool isLockUploader;

  @override
  FilePath basePath;

  @override
  String pathSeparator = '/';

  Smb2Pool? storeClient;



  RemoteConfigDataForSmb config;
  // File sessionRecordFile;

  // Dropbox({required this.basePath, required this.getToken, required this.sessionRecordFile});
  Smb({
    required this.basePath,
    required this.config,
    this.isChild = false,
    this.isLockUploader = false,
  });

  static Smb fromConfig(RemoteConfig remoteConfig) {
    return Smb(
      basePath: FilePath.fromString(remoteConfig.basePath),
      config: remoteConfig.typedData()
    );
  }

  @override
  Future<void> doInit(
    TempDir tempDir, {
    DetermineResult? determineResult,
    Future<bool> Function(Remote)? onReady,
    required int packMaxLen,
  }) async {
    await super.doInit(tempDir, determineResult: determineResult, onReady: onReady, packMaxLen: packMaxLen);

    await initStoreClient();

    if(onReady != null && !await onReady(this)) {
      return;
    }

    final result = determineResult ?? await determineServerBehavior(tempDir);
    supportAutoCreateNonexistsPath = result.supportAutoCreateNonexistsPath;
    needEndsWithSeparatorEvenPathIsFile = result.needEndsWithSeparatorEvenPathIsFile;

    // await testEmptyDirCheck();
  }

  @override
  Future<void> downloadToFile(FilePath path, File file, TempDir tempDir) async {
    final fullPath = await preHandlePath(path, makeSureParentExists: false);
    // fix 下载路径末尾无 / 导致下载失败
    var fullPathStr = _appendPathSeparatorIfIsDir(fullPath, false);

    final cancelToken = Smb2CancelToken();

    final tempFile = await tempDir.createTempFile();

    try {
      await doInterruptibleTask(
        task: storeClient!.downloadToFile(fullPathStr, tempFile.absolute.path, cancelToken: cancelToken),
        throwIfInterrupted: throwIfSessionInterrupted
      );
    }catch(e) {
      cancelToken.cancel("download interrupted by: $e");
      await safeDeleteFile(tempFile);
      rethrow;
    }

    await file.parent.create(recursive: true);
    await tempFile.rename(file.absolute.path);
  }

  @override
  Future<List<RemoteFile>> listFiles(FilePath path) async {
    App.logger.debug(_TAG, "#listFiles(): listing '$path'");
    final fullPath = await preHandlePath(path);

    // get meta data会自动尝试末尾有 / 和 无/ 来读取路径内容，所以这里不需要调用 _appendPathSeparatorIfIsDir
    final metadata = await getMetadata(fullPath);
    // 是file，直接返回
    if(!metadata.isDir) {
      return [metadata];
    }


    // 是dir，列出其中文件
    final fullPathStr = _appendPathSeparatorIfIsDir(fullPath, true);

    final files = <RemoteFile>[];
    var list = await storeClient!.listDirectory(fullPathStr);
    for (final f in list) {
      files.add(RemoteFile.fromSmbFile(f));
    }
    
    return files;
  }

  @override
  Future<void> uploadFile(FilePath path, File file, {bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#uploadFile(): uploading '${file.absolute.path}' to '$path'");
    await throwIfFileIsNotEmptyOrEncrypted(file);

    // 先上传到临时目录再重命名，避免有的直接在原路径写文件，然后中断，导致存在不完整的文件
    final tempPath = genRemoteTempFilePath();
    final tempPathStr = _appendPathSeparatorIfIsDir(tempPath, false);

    await doActIfErrAndDontSupportAutoMkdirsThenMkdirsThenTryAgain(
      actName: "uploadFile",
      act: () async {
        final cancelToken = Smb2CancelToken();

        try {
          await doInterruptibleTask(
            task: storeClient!.streamWrite(
              tempPathStr,
              file.openRead().map(Uint8List.fromList),
              onProgress: (c, t) {},
              cancelToken: cancelToken
            ),
            throwIfInterrupted: throwIfSessionInterrupted
          );
        }catch (e) {
          // 取消上传即可，不用管远程文件，上传到temp目录的，就算文件不完整也无妨，
          // 下次同步一调用remote.sessionStart()就把temp目录清了
          cancelToken.cancel("upload interrupted by: $e");
          rethrow;
        }

      },
      mkdirs: tryCreateParentsIfNeed ? () async {
        await mkdir(tempPath.parent());
      } : null
    );

    final fullPath = await preHandlePath(path);
    await rename(tempPath, fullPath, isDir: false, tryCreateParentsIfNeed: tryCreateParentsIfNeed);
  }

  @override
  Future<void> delete(FilePath path, {required bool isDir, bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#delete(): deleting '$path', isDir: $isDir");

    final fullPath = await preHandlePath(path);
    var fullPathStr = _appendPathSeparatorIfIsDir(fullPath, isDir);

    if(isDir) {
      await storeClient!.rmdir(fullPathStr, recursive: true);
    }else {
      await storeClient!.deleteFile(fullPathStr);
    }
  }

  @override
  Future<void> mkdir(FilePath path) async {
    App.logger.debug(_TAG, "#mkdir(): path='$path'");

    final fullPath = await preHandlePath(path, makeSureParentExists: false);
    await storeClient!.mkdir(_appendPathSeparatorIfIsDir(fullPath, true), recursive: true);
  }

  @override
  Future<void> rename(FilePath from, FilePath to, {required bool isDir, bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#rename(): from='$from', to: $to");

    final fromFullPath = await preHandlePath(from);
    final toFullPath = await preHandlePath(to);

    final fromFullPathStr = _appendPathSeparatorIfIsDir(fromFullPath, isDir);
    final toFullPathStr = _appendPathSeparatorIfIsDir(toFullPath, isDir);


    await doActIfErrAndDontSupportAutoMkdirsThenMkdirsThenTryAgain(
        actName: "rename",
        act: () async {
          // 最后一个参数是 overwrite
          await storeClient!.rename(fromFullPathStr, toFullPathStr, overwrite: true);
        },
        mkdirs: tryCreateParentsIfNeed ? () async {
          await mkdir(toFullPath.parent());
        } : null
    );
  }




  @override
  Future<void> copy(FilePath from, FilePath to, {required bool isDir, bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#copy(): from='$from', to='$to'");

    // 暂时不支持拷贝目录，因为没必要
    // 如果日后支持拷贝目录，则path需要用 `appendPathSeparatorIfIsDir()` 处理下
    // 如果拷贝目录，有可能会把目标目录的内容全删除再拷贝，慎用！！
    if(isDir) {
      throw RemoteException("doesn't support copy dir, 15233305");
    }

    final fromFullPath = await preHandlePath(from);
    final toFullPath = await preHandlePath(to);

    await doActIfErrAndDontSupportAutoMkdirsThenMkdirsThenTryAgain(
      actName: "copy",
      act: () async {
        // 最后一个参数是overwrite
        await storeClient!.copy(_appendPathSeparatorIfIsDir(fromFullPath, isDir), _appendPathSeparatorIfIsDir(toFullPath, isDir));
      },
      mkdirs: tryCreateParentsIfNeed ? () async {
        await mkdir(toFullPath.parent());
      } : null
    );
  }

  @override
  Future<RemoteFile> getMetadata(FilePath path) async {
    App.logger.debug(_TAG, "#getMetadata(): path='$path'");

    final fullPath = await preHandlePath(path);
    final fullPathStr = fullPath.toUnixPathStr();
    Smb2Stat remoteFileStat;
    remoteFileStat = await storeClient!.stat(fullPathStr);
    if(!remoteFileStat.isDirectory && !remoteFileStat.isFile) {
      throw RemoteException("path is not file and dir");
    }

    return RemoteFile.fromSmbFileStat(remoteFileStat, path: fullPathStr);
  }



  // 注：这个函数不修改入参path
  String _appendPathSeparatorIfIsDir(final FilePath path, bool isDir) {
    return super.appendPathSeparatorIfIsDir(path, isDir);
  }

  Future<void> initStoreClient() async {
    final storeClientTmp = await Smb2Pool.connect(
      host: config.host,
      share: config.share,
      user: config.user,
      password: config.password,
      seal: config.seal,
      signing: config.signing,
      domain: config.domain,
      timeout: Duration(milliseconds: config.timeoutInMs),
      workers: config.workers,
    );

    storeClient = storeClientTmp;
  }

  @override
  Future<void> closeStoreClient() async {
    await storeClient?.disconnect();
  }


  @override
  Future<RemoteConfig> toRemoteConfig() async {
    return RemoteConfig(
      type: type.value,
      basePath: basePath.toUnixPathStr(),
      data: config.toJson()
    );
  }

  @override
  int get maxConcurrencyRead => 5;
  // 并发写有可能导致移动文件或删除文件出错，算了，不用了
  // @override
  // int get maxConcurrencyWrite => 3;

}
