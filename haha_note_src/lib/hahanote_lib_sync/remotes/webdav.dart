import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart' show RemoteException;
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/http.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart' show RemoteConfig, RemoteConfigDataForWebdav;
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart' show TempDir;
import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show doInterruptibleTask, safeDeleteFile;
import 'package:webdav_client/webdav_client.dart' as webdav_client;

import '../app.dart';


const _TAG = "webdav.dart";

class Webdav extends Remote {
  @override
  RemoteType get type => RemoteType.webDAV;

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

  webdav_client.Client? webdavClient;



  RemoteConfigDataForWebdav config;
  // File sessionRecordFile;

  // Dropbox({required this.basePath, required this.getToken, required this.sessionRecordFile});
  Webdav({
    required this.basePath,
    required this.config,
    this.isChild = false,
    this.isLockUploader = false,
  });

  static Webdav fromConfig(RemoteConfig remoteConfig) {
    return Webdav(
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

    await _initWebdavClient();

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

    final cancelToken = webdav_client.DavCancelToken();

    final tempFile = await tempDir.createTempFile();

    try {
      await doInterruptibleTask(
        task: webdavClient!.read2File(
          fullPathStr,
          tempFile.absolute.path,
          onProgress: (count, total) {},
          cancelToken: cancelToken
        ),
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
    var list = await webdavClient!.readDir(fullPathStr);
    for (final f in list) {
      files.add(RemoteFile.fromWebdavFile(f));
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
        final cancelToken = webdav_client.DavCancelToken();

        try {
          await doInterruptibleTask(
            task: webdavClient!.writeFromFile(
              file.absolute.path,
              tempPathStr,
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

    await webdavClient!.remove(fullPathStr);
  }

  @override
  Future<void> mkdir(FilePath path) async {
    App.logger.debug(_TAG, "#mkdir(): path='$path'");

    final fullPath = await preHandlePath(path, makeSureParentExists: false);
    await webdavClient!.mkdirAll(_appendPathSeparatorIfIsDir(fullPath, true));
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
          await webdavClient!.rename(fromFullPathStr, toFullPathStr, true);
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
        await webdavClient!.copy(_appendPathSeparatorIfIsDir(fromFullPath, isDir), _appendPathSeparatorIfIsDir(toFullPath, isDir), true);
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
    webdav_client.File webdavFile;
    try {
      // 先用原始path读取

      // 有些webdav客户端，读取目录末尾需要加/，但我只凭路径怎么知道是目录还是文件？
      // 所以都尝试下，先读原始路径，如果出错，末尾加个/试试
      webdavFile = await webdavClient!.readProps(fullPathStr);
      if(webdavFile.path == null || webdavFile.path!.isEmpty) {
        final logMsg = "read metadata err, will treat path as dir and try again (append '/' then try again)";
        throw RemoteException(logMsg);
      }
    }catch(e, st) {
      App.logger.debug(_TAG, "get metadata of path '$fullPathStr' err: $e\n$st");
      // 出错了，尝试给path末尾加/再读取，若再出错就不管了
      webdavFile = await webdavClient!.readProps(_appendPathSeparatorIfIsDir(fullPath, true));
    }

    if(webdavFile.path == null || webdavFile.path!.isEmpty) {
      throw RemoteException("get metadata of path err, path='$fullPath'");
    }

    return RemoteFile.fromWebdavFile(webdavFile);
  }



  // 注：这个函数不修改入参path
  String _appendPathSeparatorIfIsDir(final FilePath path, bool isDir) {
    return super.appendPathSeparatorIfIsDir(path, isDir);
  }

  Future<void> _initWebdavClient() async {
    final client = webdav_client.newClient(
      config.host,
      user: config.user,
      password: config.password,
      debug: config.debugMode,
    );


    // Set the public request headers
    client.setHeaders({
      'accept-charset': 'utf-8',
      ...getAppRequestHeader()
    });

    // Set the connection server timeout time in milliseconds.
    // 连接超时
    // client.setConnectTimeout(config.timeoutInMs);
    client.setConnectTimeout(remoteConnectTimeoutInMs);

    // Set send data timeout time in milliseconds.
    // 上传数据超时，并不是延迟，而是你上传数据超过这个时间，就等于超时
    // Dio options.dart里写了： `null` or `Duration.zero` means no timeout limit.
    // 但这个 webdav client的接口有问题，不允许传null和Duration.zero，所以，传0替代，效果一样，永不超时
    client.setSendTimeout(0);

    // Set transfer data time in milliseconds.
    // 下载数据超时，并不是延迟，而是你下载数据超过这个时间，就等于超时
    client.setReceiveTimeout(0);

    // Test whether the service can connect
    // try {
    //   await client.ping();
    // } catch (e, st) {
    //   App.logger.debug(_TAG, '#_initWebdavClient err: $e, stackTrace: $st');
    //   rethrow;
    // }

    webdavClient = client;
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
  // 并发写有可能导致移动文件或删除文件出错，算了，不用了
  // @override
  // int get maxConcurrencyWrite => 3;

}
