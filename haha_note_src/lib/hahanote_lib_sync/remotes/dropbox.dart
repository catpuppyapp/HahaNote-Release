import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart' show RemoteException, RemoteBatchTaskException, RemoteNotFoundException;
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/http.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/oauth2/dropbox_oauth2.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart' show RemoteConfig, RemoteConfigDataForDropbox;
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart' show TempDir;
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';

import '../app.dart';
import '../sync_config.dart';


const _TAG = "dropbox.dart";




class DropboxUserInfo {
  String accountId;
  String displayName;
  String avatarUrl;

  DropboxUserInfo({this.accountId = '', this.displayName = '', this.avatarUrl = ''});

  @override
  String toString() {
    return 'DropboxUserInfo{accountId: $accountId, displayName: $displayName, avatarUrl: $avatarUrl}';
  }

  // 可解析 2/users/get_account 或 2/users/get_current_account 返回的数据，
  // 两者返回的数据结构不完全相同，但取我需要的这几个字段的路径是一致的
  static DropboxUserInfo fromMap(Map<String, dynamic> map) {
    App.logger.debug(_TAG, "dropbox user info http response: $map");
    return DropboxUserInfo(
      // 一定有
      accountId: map['account_id'],

      // 应该有
      displayName: map['name']?['display_name'] ?? '',

      // 不一定有
      avatarUrl: map['profile_photo_url'] ?? ''
    );
  }


}

class DropboxSessionInfo {
  String sessionId;
  int offset;

  DropboxSessionInfo({this.sessionId = "", this.offset = 0});

  void reset() {
    sessionId = "";
    offset = 0;
  }

}

class Dropbox extends Remote {
  // key 是 refreshToken，value 是 accessToken
  // 作用：假如，有多个Dropbox实例，一刷新token，其他实例就废了，所以搞个map，这样，所有使用
  // 同一 refreshToken 的，都会关联到同一个accessToken，若信息，则会更新对应的值。
  // 这样做的优点：减少跨线程刷新token出错的概率
  // 缺点：
  //   1 如果之前使用旧accessToken的请求已经发出，那么还是有可能出错，取决于Dropbox是否会
  //     立刻吊销旧accessToken，
  //   2 如果期望的是新的一刷新token，旧的实例全失效，那用了这个map，就反过来了，
  //     就算新的一刷新token，旧的也还是能用（可以靠Repo.doActWithLock()
  //     来保证同一时间只有一个remote可操控远程仓库了，执行可能冲突的操作前，先加锁再操作就行了）
  static final tokenMap = <String, String>{};
  // static final oauth2ClientId = DropboxOauth2.clientId;

  // 本来用来记录上传会话，若未完成，下次同步时取消的，但后来发现不能取消未完成的上传会话，记录没什么卵用，不过暂时保留这个类
  DropboxSessionInfo dropboxSessionInfo = DropboxSessionInfo();

  @override
  RemoteType get type => RemoteType.dropbox;

  @override
  bool supportAutoCreateNonexistsPath = true;

  @override
  bool isChild;

  @override
  bool isLockUploader;

  @override
  FilePath basePath;

  @override
  String pathSeparator = '/';

  RemoteConfigDataForDropbox config;

  // Dropbox({required this.basePath, required this.getToken, required this.sessionRecordFile});
  Dropbox({required this.basePath, required this.config, this.isChild = false, this.isLockUploader = false});

  static Dropbox fromConfig(RemoteConfig remoteConfig, {bool isChild = false}) {
    return Dropbox(
      basePath: FilePath.fromString(remoteConfig.basePath),
      config: remoteConfig.typedData(),
      isChild: isChild
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

    // 只有主remote需要执行获取新token的函数，子不需要，否则主的token会被吊销
    if(!isChild) {
      await _getNewAccessToken();
    }

    if(onReady != null && !await onReady(this)) {
      return;
    }

    // BEGIN: TEST
    // x) test 是否会命中 not found错误的判断
    // await testHitRemoteNotFoundException();

    // x) test 空目录和不存在
    // await testEmptyDirCheck();
    // END: TEST
  }


  @override
  Future<void> downloadToFile(FilePath path, File file, TempDir tempDir) async {
    App.logger.debug(_TAG, "#download(): downloading '$path'");

    final fullPath = await preHandlePath(path, makeSureParentExists: false);

    final throwIfInterrupted = throwIfSessionInterrupted;

    await HttpUtil.sendRequest(
      type.value,
      method: HttpMethod.post,
      uri: Uri.parse('https://content.dropboxapi.com/2/files/download'),
      header: await _getHeader(dropboxApiArg: {'path': fullPath.toUnixPathStr()}),
      parseResponseToJsonMap: false,
      throwIfInterrupted: throwIfInterrupted,
      responseHandler: (response) async {
        final tempFile = await tempDir.createTempFile();

        try {
          // 这个函数是兼容中断或不中断的（remote开没开会话皆可正常执行下载）
          await writeStreamToFile(
            tempFile,
            response.stream,
            throwIfInterrupted: throwIfInterrupted
          );
        }catch(e) {
          // 出错删除文件（可能是任务取消了）
          // 删除文件不一定成功，有可能因为io冲突之类的失败，
          // 所以，调用者最好下载到匿名临时文件，再移动到目标路径
          await safeDeleteFile(tempFile);
          rethrow;
        }

        await file.parent.create(recursive: true);
        await tempFile.rename(file.absolute.path);
      }
    );
  }

  @override
  Future<List<RemoteFile>> listFiles(FilePath path) async {
    App.logger.debug(_TAG, "#listFiles(): listing '$path'");

    // 检查下路径类型，如果是file，调用getMetadata，然后直接返回；
    // 若是目录，继续调用listFolder
    final metadata = await getMetadata(path);
    if(!metadata.isDir) {
      return [metadata];
    }

    final fullPath = await preHandlePath(path);
    final result = <RemoteFile>[];

    final uri = Uri.parse("https://api.dropboxapi.com/2/files/list_folder");
    final header = await _getHeader(contentType: HttpContentType.json);
    final httpResponse = await HttpUtil.sendRequest(
      type.value,
      method: HttpMethod.post,
      uri: uri,
      header: header,
      body: jsonEncode({
        "include_deleted": false,
        "include_has_explicit_shared_members": false,
        "include_media_info": false,
        // 这个似乎需要开启才能列出 Apps 目录的内容？无所谓，反正有写权限就行，没的话写入时会报错
        "include_mounted_folders": true,
        // 包含不可下载文件，官方举例：Google Docs，不能下载我列它干嘛？我这个函数似乎列的东西都得是能下载的吧，大概。
        "include_non_downloadable_files": false,
        "path": fullPath.toUnixPathStr(),
        "recursive": false
      }),
      parseResponseToJsonMap: true,
    );

    final responseMap = httpResponse.responseMap!;



    void addEntries(Map<String, dynamic> responseMap) {
      final entries = responseMap["entries"];
      for(final entry in entries) {
        result.add(RemoteFile.fromDropboxEntry(entry));
      }
    }

    addEntries(responseMap);

    bool hasMore = responseMap["has_more"];
    if(!hasMore) {
      return result;
    }

    final String cursor = responseMap["cursor"];
    final continueUri = Uri.parse("https://api.dropboxapi.com/2/files/list_folder/continue");
    while(hasMore) {
      final httpResponse = await HttpUtil.sendRequest(
        type.value,
        method: HttpMethod.post,
        uri: continueUri,
        header: header,
        body: jsonEncode({
          "cursor": cursor
        }),
        parseResponseToJsonMap: true,
      );

      final responseMap = httpResponse.responseMap!;


      addEntries(responseMap);

      hasMore = responseMap["has_more"];
    }

    return result;
  }

  @override
  Future<void> uploadFile(FilePath path, File file, {bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#uploadFile(): uploading '${file.absolute.path}' to '$path'");
    await throwIfFileIsNotEmptyOrEncrypted(file);

    final startUri = Uri.parse("https://content.dropboxapi.com/2/files/upload_session/start");

    // test，改小分块大小，测试用
    // final appConfig = AppConfig.getConfig().copy()..dropboxSingleUploadMaxSizeInBytes = 4194304;
    // 正式
    final syncConfig = SyncConfig.getConfig();

    final fileSizeInBytes = await file.length();
    final oneTimeEnough = fileSizeInBytes <= syncConfig.dropboxSingleUploadMaxSizeInBytes;
    final startHeader = await _getHeader(
      dropboxApiArg: {"close": oneTimeEnough},
      contentType: HttpContentType.binary
    );

    final raf = await file.open();
    final throwIfCanceled = throwIfSessionInterrupted;

    try {

      // 若数据不满足读取的大小，则返回的数组小于请求读取的大小
      Uint8List? startData = await raf.read(syncConfig.dropboxSingleUploadMaxSizeInBytes);
      var offset = startData.lengthInBytes;
      dropboxSessionInfo.offset = offset;
      final startHttpResponse = await HttpUtil.sendRequest(
        type.value,
        method: HttpMethod.post,
        uri: startUri,
        header: startHeader,
        bodyBytes: startData,
        parseResponseToJsonMap: true,
      );

      throwIfCanceled?.call();

      // maybe help free mem?
      startData = null;

      final responseMap = startHttpResponse.responseMap!;
      final String sessionId = responseMap["session_id"];


      dropboxSessionInfo.sessionId = sessionId;
      await recordSession();

      final finishUri = Uri.parse("https://content.dropboxapi.com/2/files/upload_session/finish");
      final finishPath = await preHandlePath(path);
      // finish不用传data，直接多发一个append请求即可，这样逻辑更简单，代码更好写，而且也不差那一个请求
      final finishData = Uint8List(0);
      Future<void> sendFinishRequest() async {
        throwIfCanceled?.call();

        final finishHeader = await _getHeader(
          dropboxApiArg: {
            "commit": {
              "autorename": false,
              "mode": "overwrite",
              "mute": true,  // mute为true的作用是不给用户显示“上传了某某文件”的通知
              "path": finishPath.toUnixPathStr(),
              "strict_conflict": false,  //忘了，好像是上传前版本id，完成前版本id，之类的检查的东西，false应该会默认覆盖？
            },
            "cursor" : {
              "offset": offset,
              "session_id": sessionId
            }
          },
          contentType: HttpContentType.binary
        );

        await HttpUtil.sendRequest(
          type.value,
          method: HttpMethod.post,
          uri: finishUri,
          header: finishHeader,
          bodyBytes: finishData,
          parseResponseToJsonMap: true,
        );

      }

      if(oneTimeEnough) {
        await sendFinishRequest();
        await removeSession();
        return;
      }


      // 超过分块大小，需要append

      final appendUri = Uri.parse("https://content.dropboxapi.com/2/files/upload_session/append_v2");
      while(offset < fileSizeInBytes) {
        throwIfCanceled?.call();

        final data = await raf.read(syncConfig.dropboxSingleUploadMaxSizeInBytes);
        final nextOffset = offset + data.lengthInBytes;
        final appendHeader = await _getHeader(
          dropboxApiArg: {
            // 如果nextOffset大于或等于文件大小，则说明这次上传的就是最后的数据了，
            // 因此close应设为true
            "close": nextOffset >= fileSizeInBytes,
            "cursor" : {
              "offset": offset,
              "session_id": sessionId
            }
          },
          contentType: HttpContentType.binary
        );

        await HttpUtil.sendRequest(
          type.value,
          method: HttpMethod.post,
          uri: appendUri,
          header: appendHeader,
          bodyBytes: data,
          parseResponseToJsonMap: true,
        );


        offset = nextOffset;
        dropboxSessionInfo.offset = offset;
        await recordSession();
      }

      throwIfCanceled?.call();

      await sendFinishRequest();
      removeSession();

    }finally {
      await raf.close();
    }

  }

  @override
  Future<void> delete(FilePath path, {required bool isDir, bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#delete(): deleting '$path', isDir: $isDir");

    final fullPath = await preHandlePath(path);
    try {
      await _sendJsonRequest(
        api: "https://api.dropboxapi.com/2/files/delete_v2",
        data: {"path": fullPath.toUnixPathStr()}
      );
    }catch(e) {
      // 要删除条目，但路径是not found，即路径本来就不存在，所以不算错误；若不是not found，则抛
      if(e is! RemoteNotFoundException) {
        rethrow;
      }
    }
  }

  @override
  Future<void> mkdir(FilePath path) async {
    App.logger.debug(_TAG, "#mkdir(): path='$path'");

    final fullPath = await preHandlePath(path, makeSureParentExists: false);

    await _sendJsonRequest(
      api: "https://api.dropboxapi.com/2/files/create_folder_v2",
      data: {
        "autorename": false,
        "path": fullPath.toUnixPathStr()
      }
    );
  }

  @override
  Future<void> rename(FilePath from, FilePath to, {required bool isDir, bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#rename(): from='$from', to: $to");

    final fromFullPath = await preHandlePath(from);
    final toFullPath = await preHandlePath(to);

    // make sure target doesn't exist, else will got conflict, then failed
    await _makeSureTargetNonexists(toFullPath);

    await _sendJsonRequest(
      api: "https://api.dropboxapi.com/2/files/move_v2",
      data: {
        "allow_ownership_transfer": false,
        "allow_shared_folder": false,
        "autorename": false,
        "from_path": fromFullPath.toUnixPathStr(),
        "to_path": toFullPath.toUnixPathStr()
      }
    );
  }

  @override
  Future<void> renameBatch(List<FilePathPair> paths, {bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#renameBatch(): paths='$paths'");

    if(paths.isEmpty) {
      return;
    }

    final pathsForRequest = <Map<String, String>>[];
    final remoteFileSimple = <RemoteFileSimple>[];
    for(final p in paths) {
      pathsForRequest.add({
        "from_path": (await preHandlePath(p.left)).toUnixPathStr(),
        "to_path": (await preHandlePath(p.right)).toUnixPathStr()
      });

      remoteFileSimple.add(RemoteFileSimple(false, p.right));
    }

    await _makeSureTargetsNonexists(remoteFileSimple);

    final httpResponse = await _sendJsonRequest(
        api: "https://api.dropboxapi.com/2/files/move_batch_v2",
        data: {
          "allow_ownership_transfer": false,
          "autorename": false,
          "entries": pathsForRequest
        }
    );

    App.logger.debug(_TAG, "#renameBatch() result: ${httpResponse.responseMap}");

    await _awaitAsyncJobFinished(httpResponse, "https://api.dropboxapi.com/2/files/move_batch/check_v2");

  }


  @override
  Future<void> copy(FilePath from, FilePath to, {required bool isDir, bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#copy(): from='$from', to='$to'");

    if(isDir) {
      throw RemoteException("doesn't support copy dir, 12288124");
    }


    final fromFullPath = await preHandlePath(from);
    final toFullPath = await preHandlePath(to);

    await _makeSureTargetNonexists(toFullPath);

    await _sendJsonRequest(
        api: "https://api.dropboxapi.com/2/files/copy_v2",
        data: {
          "allow_ownership_transfer": false,
          "allow_shared_folder": false,
          "autorename": false,
          "from_path": fromFullPath.toUnixPathStr(),
          "to_path": toFullPath.toUnixPathStr()
        }
    );
  }



  @override
  Future<void> deleteBatch(List<RemoteFileSimple> files, {bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#deleteBatch(): files='$files'");

    if(files.isEmpty) {
      return;
    }

    final pathsForRequest = <Map<String, String>>[];
    for(final f in files) {
      pathsForRequest.add({
        "path": (await preHandlePath(f.path)).toUnixPathStr()
      });
    }

    final httpResponse = await _sendJsonRequest(
      api: "https://api.dropboxapi.com/2/files/delete_batch",
      data: {"entries": pathsForRequest}
    );

    await _awaitAsyncJobFinished(httpResponse, "https://api.dropboxapi.com/2/files/delete_batch/check");

  }

  @override
  Future<RemoteFile> getMetadata(FilePath path) async {
    App.logger.debug(_TAG, "#getMetadata(): path='$path'");

    final fullPath = await preHandlePath(path);
    final httpResponse = await _sendJsonRequest(
      api: "https://api.dropboxapi.com/2/files/get_metadata",
      data: {
        "include_deleted": false,
        "include_has_explicit_shared_members": false,
        "include_media_info": false,
        "path": fullPath.toUnixPathStr()
      },
    );

    final responseMap = httpResponse.responseMap!;

    return RemoteFile.fromDropboxEntry(responseMap);
  }


  // @override
  // Future<void> recordSession() async {
  //   // e.g. sessionIdabcdefg\n123
  //   final ioSink = sessionRecordFile.openWrite();
  //   ioSink.write(dropboxSessionInfo.sessionId);
  //   ioSink.write("\n");
  //   ioSink.write(dropboxSessionInfo.offset);
  //   await ioSink.flush();
  //   await ioSink.close();
  // }
  //
  // @override
  // Future<void> removeSession() async {
  //   await sessionRecordFile.openWrite().close();
  //   dropboxSessionInfo.reset();
  // }
  //
  // @override
  // Future<List<dynamic>> getRecordedSessions() async {
  //   final reader = sessionRecordFile.openRead();
  //   final buf = <int>[];
  //   await for(final b in reader) {
  //     buf.addAll(b);
  //   }
  //
  //   // split sessionId and offset
  //   final tempStrs = utf8.decoder.convert(buf).split("\n");
  //   int offset;
  //   try {
  //     offset = int.parse(tempStrs[1]);
  //   }catch(e) {
  //     offset = 0;
  //   }
  //
  //   final pair = Pair(tempStrs[0], offset);
  //   return [pair];
  // }
  //
  // @override
  // Future<void> closeUnfinishedSession() async {
  //   final sessions = await getRecordedSessions();
  //   final appendUri = Uri.parse("https://content.dropboxapi.com/2/files/upload_session/append_v2");
  //
  //   for(final session in sessions) {
  //     session as Pair<String, int>;
  //
  //     final appendHeader = await _getHeader(
  //       dropboxApiArg: {
  //         "close": true,
  //         "cursor" : {
  //           "offset": session.second,
  //           "session_id": session.first
  //         }
  //       },
  //       contentType: HttpContentType.binary
  //     );
  //
  //     final appendHttpResponse = await HttpUtil.sendRequest(
  //       this,
  //       method: HttpMethod.post,
  //       uri: appendUri,
  //       header: appendHeader,
  //       bodyBytes: Uint8List(0)
  //     );
  //
  //
  //   }
  // }

  Future<void> _getNewAccessToken() async {
    App.logger.info(_TAG, "_getNewAccessToken: will refresh access token if need");

    if(config.refreshToken.isEmpty) {
      App.logger.debug(_TAG, "refreshToken is empty, can't get new accessToken, err code: 13632358");
      return;
    }

    await DropboxOauth2.refreshToken(config);

    tokenMap[config.refreshToken] = config.accessToken;

    // 刷新下用户信息
    await getUserInfo(updateConfig: true);
  }

  String _getAccessToken() {
    // map里是最新的，优先使用map，config里的若中间有其他实例刷新，则会失效
    return tokenMap[config.refreshToken] ?? config.accessToken;
  }

  Future<Map<String, String>> _getHeader({
    Map<String, dynamic>? dropboxApiArg,
    String? contentType,
    bool withCredential = true
  }) async {
    final header = await HttpUtil.newHeader(contentType: contentType);

    if(withCredential) {
      header['Authorization'] = 'Bearer ${_getAccessToken()}';
    }

    if(dropboxApiArg != null) {
      header['Dropbox-API-Arg'] = jsonEncode(dropboxApiArg);
    }

    return header;
  }


  Future<HttpResponse> _sendJsonRequest({
    required String api,
    required Map<String, dynamic> data,
  }) async {
    final uri = Uri.parse(api);
    final header = await _getHeader(contentType: HttpContentType.json);

    final httpResponse = await HttpUtil.sendRequest(
      type.value,
      method: HttpMethod.post,
      uri: uri,
      header: header,
      body: jsonEncode(data),
      parseResponseToJsonMap: true,
    );

    return httpResponse;
  }

  Future<void> _awaitAsyncJobFinished(HttpResponse httpResponse, String api) async {
    final responseMap = httpResponse.responseMap!;
    final asyncJobId = responseMap["async_job_id"];
    if(asyncJobId != null) {
      // 查询，直到操作完成
      while(true) {
        // 400ms检查一次
        await Future.delayed(const Duration(milliseconds: 400));

        final httpResponse = await _sendJsonRequest(
            api: api,
            data: {
              "async_job_id": asyncJobId
            }
        );

        final responseMap = httpResponse.responseMap!;
        // ".tag": "in_progress"
        // 只能保证所有操作都完成了，不能保证一定成功
        if(responseMap[".tag"] != "in_progress") {
          // 检查是否有错误
          // final errItems = <Map<String, dynamic>>[];  // 这个类型不会报错，也行
          final errItems = <dynamic>[];  //这个比较保险，用这个吧，列表元素实际类型是 Map<String, dynamic>
          // 取出列表
          // 不能用 List<Map<String, dynamic>>，会报错，用List<dynamic>或 List，皆可
          final List<dynamic> entries = responseMap["entries"];
          for(final entry in entries) {
            // delete batch, not found是能接受的错误
            // delete batch check, not found, json格式
            // {
            //   ".tag": "complete",
            //   "entries": [
            //     {
            //       ".tag": "failure",
            //       "failure": {
            //         ".tag": "path_lookup",
            //         "path_lookup": {
            //           ".tag": "not_found"
            //         }
            //       }
            //     },
            //     {
            //       ".tag": "failure",
            //       "failure": {
            //         ".tag": "path_lookup",
            //         "path_lookup": {
            //           ".tag": "not_found"
            //         }
            //       }
            //     }
            //   ]
            // }

            // move batch, not found, json
            //{
            //   ".tag": "complete",
            //   "entries": [
            //     {
            //       ".tag": "failure",
            //       "failure": {
            //         ".tag": "relocation_error",
            //         "relocation_error": {
            //           ".tag": "from_lookup",
            //           "from_lookup": {
            //             ".tag": "not_found"
            //           }
            //         }
            //       }
            //     }
            //   ]
            // }


            // dynamic也能当map用
            if(entry[".tag"] == "success") {
              continue;
            }

            // failure or other err
            final failure = entry["failure"];
            if(failure != null) {
              // 检查，可以接受的错误，比如删除或移动文件，对应条目not_found，其实可以接受
              // 例如：
              // 1. renameBatch: 对于同一个文件执行rename，第一次移动成功，再移动就会因为源文件已经移动而失败，这种就是可接受的
              // 2. renameBatch: 在覆盖某些文件前，对可能存在的旧版文件进行若有则移动，无则忽略，这时也会not_found，也可接受
              // 3. deleteBatch: 和renameBatch的场景一样，先删一个文件，再删文件已经没了，这时报错，可接受，使删除操作幂等不报错，
              //    或者，覆盖某些文件前若对应路径已经有文件则先删除，这时not_found也可接受
              // delete batch v2 删除文件，not found错误
              if(failure["path_lookup"]?[".tag"] == "not_found") {
                continue;
              }else if(failure["relocation_error"]?["from_lookup"]?[".tag"] == "not_found") {
                // move batch 移动文件，源文件不存在（把a移动到b，a不存在，提交syncCache时，若中断过，
                // 并且提交前没检查条目是否存在，就可能出现这个错误，例如这次批量移动a到b成功，但网络中断，
                // 远程操作其实已经成功，源路径已经不存在，下次重新提交syncCache，再移动，
                // 就会源路径不存在报错，不过我移动前进行了处理，只移动syncCache下存在的路径，
                // 所以这个错误其实不会发生，但这里还是处理下吧）
                continue;
              }
            }


            errItems.add(entry);
          }

          // 若有错误，抛出，包含错误条目的信息
          if(errItems.isNotEmpty) {
            throw RemoteBatchTaskException(errItems, "${errItems.length} items got err: $errItems");
          }

          // 无错误会执行到这，然后正常退出
          break;
        }
      }
    }
  }


  Future<void> _makeSureTargetNonexists(FilePath path) async {
    await delete(path, isDir: false);
  }

  Future<void> _makeSureTargetsNonexists(List<RemoteFileSimple> paths) async {
    await deleteBatch(paths);
  }

  @override
  Future<RemoteConfig> toRemoteConfig() async {
    final remoteConfig = RemoteConfig();
    remoteConfig.basePath = basePath.toUnixPathStr();
    remoteConfig.type = type.value;
    remoteConfig.data = config.toJson();

    return remoteConfig;
  }

  Future<DropboxUserInfo> getUserInfo({required bool updateConfig}) async {
    //   // api 1:这个不需要提供account_id，但team和非team用户返回的字段不同
    //   // curl -X POST https://api.dropboxapi.com/2/users/get_current_account \
    //   // --header "Authorization: Bearer <get access token>"
    //
    //   // api 2: 需要提供account_id，但返回的结果字段固定
    //   // curl -X POST https://api.dropboxapi.com/2/users/get_account \
    //   // --header "Authorization: Bearer <get access token>" \
    //   // --header "Content-Type: application/json" \
    //   // --data "{\"account_id\":\"dbid:AAH4f99T0taONIb-OurWxbNQ6ywGRopQngc\"}"
    //
    //   // 上面两个api其实都行，因为我只支持dropbox个人用户(之前觉得方案2返回数据比较稳定，所以采用的方案2，但需额外权限，所以后来换成方案1了)
    //   // api 2需要额外请求一个权限，所以后来我弃用了
    //   // 2/users/get_account api 需要额外dropbox权限 sharing.read ，所以弃用
    //   // 注：这个api返回的数据结构和 2/users/get_current_account 解析起来一样，所以无需修改DropboxUserInfo.fromMap
    //   final httpResponse = await _sendJsonRequest(
    //     api: "https://api.dropboxapi.com/2/users/get_account",
    //     data: {
    //       "account_id": config.accountId
    //     }
    //   );

    final httpResponse = await _sendJsonRequest(
      api: "https://api.dropboxapi.com/2/users/get_current_account",
      data: {}
    );

    final userInfo = DropboxUserInfo.fromMap(httpResponse.responseMap!);

    if(updateConfig) {
      // 只是更新内存中的数据，不会写入硬盘
      config.username = userInfo.displayName;
      config.avatar = userInfo.avatarUrl;
    }

    return userInfo;
  }


  // 注：dropbox 似乎不支持并发写，有可能触发 too_many_write_operations，所以禁用；
  //    并发读我不确定是否易报错，若日后确定并发读可用，则可拆分出allowConcurrencyRead和allowConcurrencyWrite，
  //    两者分别对应读操作和写操作，读操作包含下载、exists等，写操作包含上传、rename、delete等
  // 由于dropbox支持批量rename和delete，所以重写了那两个函数，并不需要使用此变量
  // 但是上传是单个上传的，依赖并发上传才能同时上传多个，所以设此变量为true
  // 注：上传多个小文件有效，若大文件，可能单文件上传就能跑满带宽，并发执行意义不大
  @override
  int get maxConcurrencyRead => 3;

  // dropbox应禁用并发写，至少针对同一目录不同文件的并发写，有可能触发 too_many_write_operations；没测试针对不同目录的并发写是否会有问题
  // 默认是禁用，所以就不用override了
  // @override
  // int get maxConcurrencyWrite => 1;

}
