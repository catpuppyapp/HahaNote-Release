import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart' show RemoteException;
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart' show RemoteConfig, RemoteConfigDataForSftp;
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart' show TempDir;
import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show doInterruptibleTask, safeDeleteFile;

import '../app.dart';


const _TAG = "sftp.dart";

/// unimplemented yet, sftp does not supports copy, need down then upload, is bad
/// recommend use webdav instead
class Sftp extends Remote {
  @override
  RemoteType get type => RemoteType.sftp;

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

  SFTPConnect? storeClient;



  RemoteConfigDataForSftp config;

  Sftp({
    required this.basePath,
    required this.config,
    this.isChild = false,
    this.isLockUploader = false,
  });

  static Sftp fromConfig(RemoteConfig remoteConfig) {
    return Sftp(
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


    final tempFile = await tempDir.createTempFile();

    try {
      await doInterruptibleTask(
        task: storeClient!.downloadFile(fullPathStr, tempFile),
        throwIfInterrupted: throwIfSessionInterrupted
      );
    }catch(e) {
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
    var list = await storeClient!.listDirectoryContent(fullPathStr);
    for (final f in list) {
      files.add(RemoteFile.fromFtpEntry(f, parentPath: fullPathStr));
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

        try {
          await doInterruptibleTask(
            task: storeClient!.uploadFile(
              file,
              sRemoteName: tempPathStr,
            ),
            throwIfInterrupted: throwIfSessionInterrupted
          );
        }catch (e) {
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
      await storeClient!.deleteDirectory(fullPathStr);
    }else {
      await storeClient!.deleteFile(fullPathStr);
    }
  }

  @override
  Future<void> mkdir(FilePath path) async {
    App.logger.debug(_TAG, "#mkdir(): path='$path'");

    final fullPath = await preHandlePath(path, makeSureParentExists: false);
    await storeClient!.createFolderIfNotExist(_appendPathSeparatorIfIsDir(fullPath, true));
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
          await storeClient!.rename(fromFullPathStr, toFullPathStr);
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
      throw RemoteException("doesn't support copy dir");
    }

    final fromFullPath = await preHandlePath(from);
    final toFullPath = await preHandlePath(to);

    await doActIfErrAndDontSupportAutoMkdirsThenMkdirsThenTryAgain(
      actName: "copy",
      act: () async {
        // await storeClient!.doesNotSupportCopyYetCanUseDownThenUploadInstead(_appendPathSeparatorIfIsDir(fromFullPath, isDir), _appendPathSeparatorIfIsDir(toFullPath, isDir));
      },
      mkdirs: tryCreateParentsIfNeed ? () async {
        await mkdir(toFullPath.parent());
      } : null
    );
  }

  @override
  Future<RemoteFile> getMetadata(FilePath path) async {
    // TODO
    // App.logger.debug(_TAG, "#getMetadata(): path='$path'");
    //
    // final fullPath = await preHandlePath(path);
    // final fullPathStr = fullPath.toUnixPathStr();
    // Smb2Stat remoteFileStat;
    // remoteFileStat = await storeClient!.stat(fullPathStr);
    // if(!remoteFileStat.isDirectory && !remoteFileStat.isFile) {
    //   throw RemoteException("path is not file or dir");
    // }
    //
    // return RemoteFile.fromSmbFileStat(remoteFileStat, path: fullPathStr);
    return RemoteFile(isDir: false, name: "", path: path, mTimeMs: 0, length: 0);
  }



  // 注：这个函数不修改入参path
  String _appendPathSeparatorIfIsDir(final FilePath path, bool isDir) {
    return super.appendPathSeparatorIfIsDir(path, isDir);
  }

  Future<void> initStoreClient() async {
    if(storeClient != null) {
      await closeStoreClient(caller: "remote.initStoreClient");
    }

    final sftpConnect = SFTPConnect(
      config.host,
      user: config.user,
      pass: config.password,
      port: config.port,
      timeout: config.timeoutInMs * 1000,
      privateKey: config.privateKey,
      passphrase: config.passphrase,
      showLog: false,
      onVerifyHostKey: (type, fingerprint) async {
        // 用host查指纹，若无，中止连接，询问用户，若用户点是，
        // 保存指纹，重新连接，若有，检查，如果匹配，继续连接，
        // 如果不匹配，中止连接，然后弹窗询问“提示密钥变了，之前是a，现在是b”，
        // 重复以上流程
        // 在这里把指纹host都抛出去，抛出特定异常，给上层捕获
        return true;
      }
    );

    final success = await sftpConnect.connect();
    if(!success) {
      throw RemoteException("connect sftp error");
    }

    storeClient = sftpConnect;
  }

  @override
  Future<void> closeStoreClient({String caller = ""}) async {
    if(caller.isNotEmpty) {
      App.logger.debug(_TAG, "closeStoreClient called by '$caller', `storeClient` is null: ${storeClient == null}");
    }

    if(storeClient == null) {
      return;
    }

    await storeClient?.disconnect();
    storeClient = null;
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
  int get maxConcurrencyRead => 3;

  @override
  int get maxConcurrencyWrite => 3;

  @override
  Future<bool> exists(FilePath path) async {
    final fullPath = await preHandlePath(path);
    final fullPathStr = fullPath.toUnixPathStr();
    return await storeClient!.existFile(fullPathStr);
  }
}
