import 'dart:convert' show utf8, jsonEncode, jsonDecode;
import 'dart:io' show File;

import 'package:hahanote_app/hahanote_lib_sync/client/client.dart';
import 'package:hahanote_app/hahanote_lib_sync/crypto/encrypt.dart' show EncryptedData;
import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart' show RemoteType, Remote, remoteConnectTimeoutInMs;
import 'package:hahanote_app/hahanote_lib_sync/remotes/dropbox.dart' show Dropbox;
import 'package:hahanote_app/hahanote_lib_sync/remotes/empty_remote_impl.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/local_dir.dart' show LocalDir;
import 'package:hahanote_app/hahanote_lib_sync/remotes/webdav.dart' show Webdav;
import 'package:hahanote_app/hahanote_lib_sync/serialization/json.dart' show myJsonSerializable;
import 'package:hahanote_app/hahanote_lib_sync/serialization/stream.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart' show FilePath;
import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show getJsonStrFromByteStream;

import 'sync.dart';

part 'config.g.dart';

@myJsonSerializable
class Config implements JsonByteStream {
  int ver;
  // 这个仓库名仅限本地，设计上可修改，不过用户可通过文件夹名和路径分辨仓库，
  // 所以暂时先不给用户显示这个字段，创建时可能会repoInfo的repoName一样，
  // 但后续修改这个不会影响那个，那个并没修改的打算，可能创建了就不能改了
  String repoName;
  RemoteConfig remoteConfig;
  Client client;

  int mergeMode;

  // 仓库级别的封包文件大小设置，和全局设置共存，仓库作用域优先全局，若此值小于等于0，则使用全局配置，否则上传数据包时遵循此值来封包
  // 作用参见全局设置对应字段：SyncConfig.packFileMaxLenInBytes
  int packFileMaxLenInBytes;

  Config({
    this.ver = 1,
    this.repoName = '', 
    RemoteConfig? remoteConfig, 
    Client? client, 
    this.mergeMode = MergeMode.mergeRemoteAndWorkdir, 
    this.packFileMaxLenInBytes = 0,
  })
  : remoteConfig = remoteConfig ?? RemoteConfig(),
    client = client ?? Client();


  factory Config.fromJson(Map<String, dynamic> json) => _$ConfigFromJson(json);

  Map<String, dynamic> toJson() => _$ConfigToJson(this);

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }


  static Future<Config> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return Config.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  static Future<Config> decrypt(KeyData contentKeyData, File file) async {
    final encryptedData = await EncryptedData.readFromFile(file);
    final rawData = await encryptedData.decryptThenUncompress(contentKeyData);

    return await fromJsonByteStream(rawData);
  }

  String mergeModeToText() {
    return MergeMode.toText(mergeMode);
  }

}

@myJsonSerializable
class RemoteConfig {
  /// one of `RemoteType.supportedTypeValues`
  String type;
  /// unix format path
  String basePath;

  Map<String, dynamic> data;

  RemoteConfig({this.type = '', this.basePath = '', Map<String, dynamic>? data})
  : data = data ?? {};

  factory RemoteConfig.fromJson(Map<String, dynamic> json) => _$RemoteConfigFromJson(json);

  Map<String, dynamic> toJson() => _$RemoteConfigToJson(this);

  dynamic typedData() {
    if(type == RemoteType.dropbox.value) {
      return RemoteConfigDataForDropbox.fromJson(data);
    }

    if(type == RemoteType.webDAV.value) {
      return RemoteConfigDataForWebdav.fromJson(data);
    }

    if(type == RemoteType.localDir.value) {
      return RemoteConfigDataForLocalDir.fromJson(data);
    }

    return null;
  }

  String typeToText() {
    if(type == RemoteType.localDir.value && RemoteConfigDataForLocalDir.fromJson(data).isGitBackend) {
      return "$type (Git)";
    }

    return type;
  }

}

@myJsonSerializable
class RemoteConfigDataForWebdav {
  String host;
  String user;
  String password;
  int timeoutInMs;  // 连接超时，默认60秒
  bool debugMode;

  RemoteConfigDataForWebdav({this.host = '', this.user = '', this.password = '',
    this.timeoutInMs = remoteConnectTimeoutInMs, this.debugMode = false});


  factory RemoteConfigDataForWebdav.fromJson(Map<String, dynamic> json) => _$RemoteConfigDataForWebdavFromJson(json);

  Map<String, dynamic> toJson() => _$RemoteConfigDataForWebdavToJson(this);

}

@myJsonSerializable
class RemoteConfigDataForLocalDir {
  bool isGitBackend;
  String gitPullUrl;
  String gitPushUrl;
  String gitSyncUrl;
  String gitPath; // git.exe路径，默认使用系统环境变量的git，所以此字段可为空

  RemoteConfigDataForLocalDir({this.isGitBackend = false, this.gitPullUrl = '', this.gitPushUrl = '', this.gitSyncUrl = '', this.gitPath = ''});

  factory RemoteConfigDataForLocalDir.fromJson(Map<String, dynamic> json) => _$RemoteConfigDataForLocalDirFromJson(json);

  Map<String, dynamic> toJson() => _$RemoteConfigDataForLocalDirToJson(this);

}

@myJsonSerializable
class RemoteConfigDataForDropbox {
  String accessToken;
  String refreshToken;
  String accountId;
  String uid;
  int expiresIn;
  String tokenType;

  // 这两个信息是激活时存的，不一定准，后续可能更新也可能不
  String username;
  String avatar;

  RemoteConfigDataForDropbox({
    this.accessToken = '',
    this.refreshToken = '',
    this.accountId = '',
    this.uid = '',
    this.expiresIn = 0,
    this.tokenType = '',
    this.username = '',
    this.avatar = '',
  });


  factory RemoteConfigDataForDropbox.fromJson(Map<String, dynamic> json) => _$RemoteConfigDataForDropboxFromJson(json);

  Map<String, dynamic> toJson() => _$RemoteConfigDataForDropboxToJson(this);

  static Future<RemoteConfigDataForDropbox> parseFromResponseMap(Map<String, dynamic> resMap) async {
    // {
    //   "access_token": "sl.u.AbX9y6Fe3AuH5o66-gmJpR032jwAwQPIVVzWXZNkdzcYT02akC2de219dZi6gxYPVnYPrpvISRSf9lxKWJzYLjtMPH-d9fo_0gXex7X37VIvpty4-G8f4-WX45AcEPfRnJJDwzv-",
    //   "expires_in": 14400,
    //   "token_type": "bearer",
    //   "scope": "account_info.read files.content.read files.content.write files.metadata.read",
    //   "refresh_token": "nBiM85CZALsAAAAAAAAAAQXHBoNpNutK4ngsXHsqW4iGz9tisb3JyjGqikMJIYbd",
    //   "account_id": "dbid:AAH4f99T0taONIb-OurWxbNQ6ywGRopQngc",
    //   "uid": "12345"
    // }

    // 不需要 scope，完全开发者在后台控制即可，其他字段都需要，其中 access_token 和expires_in会经常变化，
    // refresh token在重新授权后会变化，其他字段为常量
    return RemoteConfigDataForDropbox(
      accessToken: resMap['access_token'],
      expiresIn: resMap['expires_in'],
      tokenType: resMap['token_type'],
      refreshToken: resMap['refresh_token'],
      accountId: resMap['account_id'],
      uid: resMap['uid'],
    );
  }

  void copyTo(RemoteConfigDataForDropbox other) {
    other.accessToken = accessToken;
    other.refreshToken = refreshToken;
    other.accountId = accountId;
    other.uid = uid;
    other.expiresIn = expiresIn;
    other.tokenType = tokenType;
    other.username = username;
    other.avatar = avatar;
  }

  @override
  String toString() {
    return 'RemoteConfigDataForDropbox{accessToken: $accessToken, refreshToken: $refreshToken, accountId: $accountId, uid: $uid, expiresIn: $expiresIn, tokenType: $tokenType, username: $username, avatar: $avatar}';
  }


}

abstract class ConfigUtil {

  static Future<Client> createClientFromConfig(Config config) async {
    return Client.fromJson(config.client.toJson());
  }

  static Future<Remote> createRemoteFromConfig(
    RemoteConfig remoteConfig, {
    bool isChild = false,
    bool isLockUploader = false,
    int lastGitPullAtInMs = 0,
  }) async {
    final remoteType = remoteConfig.type;
    if(!RemoteType.supportedTypeValues.contains(remoteType)) {
      return emptyRemoteImplInstance;
    }

    final basePath = FilePath.fromString(remoteConfig.basePath);

    if(remoteType == RemoteType.localDir.value) {
      final data = RemoteConfigDataForLocalDir.fromJson(remoteConfig.data);
      final remote = LocalDir(
        basePath: basePath,
        config: data,
        isChild: isChild,
        isLockUploader: isLockUploader,
      );

      remote.lastGitPullAtInMs = lastGitPullAtInMs;

      return remote;
    }

    if(remoteType == RemoteType.dropbox.value) {
      final data = RemoteConfigDataForDropbox.fromJson(remoteConfig.data);
      return Dropbox(
        basePath: basePath,
        config: data,
        isChild: isChild,
        isLockUploader: isLockUploader,
      );
    }

    if(remoteType == RemoteType.webDAV.value) {
      final data = RemoteConfigDataForWebdav.fromJson(remoteConfig.data);
      return Webdav(
        basePath: basePath,
        config: data,
        isChild: isChild,
        isLockUploader: isLockUploader,
      );
    }

    return emptyRemoteImplInstance;
  }

}
