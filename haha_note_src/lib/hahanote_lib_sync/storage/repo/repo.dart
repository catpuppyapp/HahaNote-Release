import 'dart:convert';
import 'dart:io' show Directory, File, FileSystemEntityType;
import 'dart:isolate' show SendPort, ReceivePort;
import 'dart:typed_data';

import 'package:hahanote_app/hahanote_lib_sync/app.dart' show App;
import 'package:hahanote_app/hahanote_lib_sync/app_key.dart';
import 'package:hahanote_app/hahanote_lib_sync/client/client.dart' show Client;
import 'package:hahanote_app/hahanote_lib_sync/crypto/encrypt.dart';
import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/crypto/key_extra_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/datamap/data_map.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/dropbox.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/empty_remote_impl.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/lock/lock.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/pack/obj_pack.dart' show ObjPackFileStorage, ObjRef;
import 'package:hahanote_app/hahanote_lib_sync/serialization/json.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/oidlize.dart';
import 'package:hahanote_app/hahanote_lib_sync/simple_ignore_matcher.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_info.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/msg/msg.dart' show Msg, MsgType;
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart' show Config, ConfigUtil, RemoteConfigDataForDropbox;
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/index.dart' show Index;
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/repo_info.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/status_item.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync_history.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/related_oids.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';
import 'package:hahanote_app/hahanote_lib_sync/sync_config.dart';
import 'package:hahanote_app/hahanote_lib_sync/time/time_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';
import 'package:hahanote_app/util/util.dart' show createParentDirIfNeed;
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../../crypto/hash.dart' show hashFileWithKeyData;
import '../../isolate_pool/isolate_pool.dart';
import '../../remotes/local_dir.dart';
import '../files/virtual_file.dart';
import '../utils.dart';

part 'repo.g.dart';

const _TAG = "repo.dart";

const supportedRepoFormatVersions = [1];

// status of local repo
abstract class RepoStatusVal {
  static const int err = -1;
  static const int none = 0; // init state
  static const int dirty = 1;  // some files need to push
  static const int clean = 2; // nothing to push, but no promise to pull, due to check remote status need network, is heavy, so only check remote status when sync

}

class RepoStatus {
  int value;
  // if value is err, then this is msg, else can ignore it
  String msg;

  RepoStatus({this.value = RepoStatusVal.none, this.msg = ''});

  @override
  String toString() {
    return 'value: $value, msg: $msg';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepoStatus &&
          runtimeType == other.runtimeType &&
          value == other.value &&
          msg == other.msg;

  @override
  int get hashCode => Object.hash(value, msg);

  static Future<RepoStatus> checkRepoStatus(
    String repoPath, {
    required ThrowIfInterrupted throwIfInterrupted,
  }) async {
    try {
      final repo = await Repo.open(repoPath);
      return await repo.checkStatus(throwIfInterrupted: throwIfInterrupted);
    }catch(e) {  // 打开仓库有可能出错，所以得捕获下
      return RepoStatus(value: RepoStatusVal.err, msg: e.toString());
    }
  }
}


class KeyDataPath {
  String masterKey;
  String masterKeyExtraData;
  String contentKey;

  KeyDataPath({this.masterKey = '', this.masterKeyExtraData = '', this.contentKey = ''});

}

// 同步时要创建新的sync history，但需要和旧的对比，因此创建一个这个对象，包含新旧syncHistory
class SyncHistoryPair {
  final SyncHistory remote;
  // 若初次同步则不存在
  final SyncHistory? local;
  final Set<String>? changes;

  SyncHistoryPair({required this.remote, required this.local, this.changes});
}

class ExportFailedItem {
  String relativePath;
  String oid;
  String errMsg;

  ExportFailedItem({required this.relativePath, required this.oid, required this.errMsg});

  @override
  String toString() {
    return 'relativePath: $relativePath, oid: $oid, errMsg: $errMsg';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ExportFailedItem && runtimeType == other.runtimeType &&
              relativePath == other.relativePath && oid == other.oid &&
              errMsg == other.errMsg;

  @override
  int get hashCode => Object.hash(relativePath, oid, errMsg);

}

@myJsonSerializable
class LocalSyncCacheInfo {
  int mergeMode;

  LocalSyncCacheInfo({this.mergeMode = MergeMode.mergeRemoteAndWorkdir});

  factory LocalSyncCacheInfo.fromJson(Map<String, dynamic> json) => _$LocalSyncCacheInfoFromJson(json);

  Map<String, dynamic> toJson() => _$LocalSyncCacheInfoToJson(this);


  @override
  String toString() {
    return 'mergeMode: $mergeMode';
  }

}

class OidAndPath {
  VersionOid oid;
  String path;

  OidAndPath({required this.oid, this.path = ''});

  @override
  String toString() {
    return 'OidAndPath{oid: $oid, path: $path}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is OidAndPath && runtimeType == other.runtimeType &&
              oid == other.oid && path == other.path;

  @override
  int get hashCode => Object.hash(oid, path);
}



// 本地用的仓库锁，避免多个任务冲突
class LockToken {
  String actName;
  String actDesc;
  String id;

  LockToken({this.actName = '', this.actDesc = '', String? id})
    : id = id ?? randomString(32);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is LockToken && runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'actName: $actName, actDesc: $actDesc, id: $id';
  }
}

class Repo {
  // key: FilePath(仓库路径).mapKey(); value: 字符串非空非null则代表本地仓库正在被使用，否则代表仓库空闲
  // 备忘：如果以后拆分cli和gui，这个需要改成文件锁，并且像remote lock一样支持自动续期和设置过期时间。
  //      如果在gui里可直接调用cli的代码，就不需要弄文件锁了，但是那样得做函数binding，麻烦
  static final Map<String, LockToken> repoPathLocalLockMap = {};

  // 返回null代表仓库没锁定，否则代表仓库已锁定，返回的token包含现在占据锁的操作的信息
  static LockToken? lockLocalRepoByPath(String repoPath, LockToken token) {
    final key = FilePath.fromString(repoPath).toMapKey();
    final currentToken = repoPathLocalLockMap[key];
    if(currentToken != null) {
      // 仓库已锁，调用者获取锁失败
      return currentToken;
    }else {
      // 仓库没锁定
      repoPathLocalLockMap[key] = token;
      // 调用者获取锁成功
      return null;
    }
  }

  // 返回null代表解锁成功，否则失败，返回的是当前占据锁的token
  static LockToken? freeLocalRepoLockByPath(String repoPath, LockToken token) {
    final key = FilePath.fromString(repoPath).toMapKey();
    final currentToken = repoPathLocalLockMap[key];
    if(currentToken == null) {
      // 没人占用锁，解锁自然成功
      return null;
    }

    if(currentToken.id == token.id) {
      repoPathLocalLockMap.remove(key);
      return null;
    }

    // 返回非null，解锁失败
    return currentToken;
  }


  // x 取消后缀了，冲突的概率应该很小，谁会给文件名起这名啊？） 后缀是为了避免和用户的文件或目录名冲突
  static const String dataDirName = '.haha_note';

  // 忽略app相关的目录， 这个对用户来说是不可编辑的，但是后续会提供用户可编辑的忽略目录，
  // 可按规则忽略目录或文件
  static const defaultIgnorePathList = [dataDirName];

  static const ignoreFileName = ".haha_ignore";
  // 在syncCache创建此文件，内部记录mergeMode，若是远程覆盖本地，即使工作目录的对应条目路径是文件也会删除
  // static const mergeModeFileName = "mergeMode";

  // files in this dir, will be uploaded
  static final String remoteDirName = 'remote';
  static final String remoteFilesDirName = 'files';
  static final String remoteObjectsDirName = 'objects';
  static final String remoteMsgDirName = 'msg';
  static final String remoteLocksDirName = 'locks';
  static final String cacheDirName = 'cache';
  static final String syncCacheDirName = 'syncCache';
  static final String downCacheDirName = 'downCache';
  static final String debugDirName = 'debug';
  // static final String syncCacheFilesDirName = 'files';

  static final String keysDirName = 'keys';

  // 数据存放路径示例：hash/data.enc
  static final String remoteDataFileName = 'data.enc';
  static final String decryptedDataFileSuffix = '.dec';

  static final String localIndexFileName = 'index.json';
  // 记录上次同步信息
  static final String localLastSyncInfoFileName = 'lastSyncInfo.json';
  // 文件是个json对象，记录了workdir删除的文件，删除前检测文件的修改时间，
  // 可选检测：如果大于这个json文件的最后修改时间，则，不会删除对应的文件
  // 文件放在本地的 cache/syncCache/ 目录下
  static final String workdirWillDeleteFileName = 'workdirWillDelete.json';
  // 这个记录了要覆盖的文件的信息
  static final String workdirWillOverwriteFileName = 'workdirWillOverwrite.json';
  // syncCache，这个记录要删除的文件的路径，无校验，直接删的那种，
  // 例如本地的fileInfo的data.enc，属于缓存的文件，无条件删除是ok的，就放这里
  static final String deleteAnywayFilesFileName = 'deleteAnywayFiles.json';

  // config要加密，因为要存储access token和webdav的密码
  static final String localConfigFileNameFileName = 'config.enc';
  static final String infoJsonFileName = 'info.json';
  static final String readyFileName = 'ready'; // 用来标记缓存就绪


  // 在远程仓库根目录，本地的 remote根目录
  static final String repoInfoFileName = 'repoInfo.enc';
  static final String syncHistoryFileName = 'syncHistory.enc';

  // 本地的temp 目录
  static final String tempDirName = 'temp';
  static final String gitDirName = '.git';
  // 给tempDir和syncCache用的，workdir的名字，正式目录本身就是workdir，不用管这个
  static final String workdirDirName = 'workdir';

  static final encryptedFileSuffix = ".enc";
  static final backupFileSuffix = ".bak";

  // 主密码附加数据，用于验证主密码
  // 这个是用户的主密码的附加数据，包含salt和content padding，用appkey加密，
  // 必须存，不然无法验证用户输入的主密码，通常的非e2ee架构，
  // 都是直接把派生出的hash以及派生时使用的参数存上的，
  // 验证用户密码时，让用户输入明文密码，重新用相同参数派生，再比较是否相同，
  // 但是，e2ee应用不能存用户主密码派生的hash，不然就能解密用户数据，
  // 但又必须要能验证用户输入的主密码是否正确，
  // 所以，要么指望用户把salt完全记住，这不太可能，能记住代表短，
  // 记不住，就解密不了文件，除非用户用密码管理器，把salt存上，但这样用户体验就下降了，
  // 而且让用户记住salt在交互上感觉有些奇怪，所以算了，
  // 如果非要记住的话，可以把明文密码派生出的hash，转换为hex，给用户存上，
  // 就是通常的e2ee应用提供的"recovery key"，但让用户记这个东西，比让他记密码可能更苛刻，
  // 所以这个功能可以日后再说，目前先不用做，以后做的时候也需要先验证用户密码，再给他看recovery key，
  // 总之，salt必须存到远程仓库，但存了就有可能泄漏。。。
  // 不过salt就算泄漏，也并不代表黑客就能碰撞出用户的主密码，他还是必须要计算，
  // 所以，如果用户设置了10位以上且包含字母数字的随机密码，还算是比较安全的。
  // 加上每个用户的salt是随机的，因此预计算是现实的，所以还是安全的。
  static final String masterKeyExtraDataFileName = "masterKeyExtraData.enc";

  static final String masterKeyFileName = 'masterKey.enc';
  static final String contentKeyFileName = 'contentKey.enc';



  // 这玩意不好，而且有syncHistory，没必要弄个这个，若非要搞，
  // 不如弄个本地的上次同步信息，把同步时间、同步状态（成功完成，发生异常，中断）都记上
  // static final forceSyncFlagFileName = "flag_forceSync";

  // path包含用户的文件(workdir)和仓库数据，两者类似git的workdir和.git目录的关系
  final String path;
  Remote remote;
  String repoName;
  Client client;
  Repo({required this.path, required this.repoName, Remote? remote, Client? client})
  : remote = remote ?? emptyRemoteImplInstance,
    client = client ?? Client();


  static Future<Repo> open(String repoPath) async {
    return fromRepoPath(repoPath, createIfNoExists: false);
  }

  static Future<Repo> fromRepoPath(String repoPath, {final bool createIfNoExists = false}) async {
    final repoPathCanonical = FilePath.canonicalizePath(repoPath);
    final configFile = File(getConfigPathByRepoPath(repoPathCanonical));
    Config? config = await readConfig(configFile);

    if(config == null) {
      if(!createIfNoExists) {
        throw AppException("repo config file doesn't exist, path: ${configFile.absolute.path}");
      }

      // 创建新配置并写入到仓库目录
      // 仓库config文件不存在，可能初次创建仓库，创建个空的配置文件，然后保存
      // repoName随机生成一个，允许用户编辑
      config = Config(repoName: "repo_${randomString(8)}");

      await writeConfig(config, configFile.absolute.path);
    }

    return fromConfig(repoPathCanonical, config);
  }


  static Future<Repo> fromConfig(String repoPath, Config config) async {
    final remote = await ConfigUtil.createRemoteFromConfig(config.remoteConfig);
    final client = await ConfigUtil.createClientFromConfig(config);

    return Repo(
      path: FilePath.canonicalizePath(repoPath),
      remote: remote,
      repoName: config.repoName,
      client: client
    );
  }


  static Future<Config?> readConfig(File configFile) async {
    if(await configFile.exists()) {
      // 若存在但数据有误，则会在这抛异常，调用者自己处理，这不删除对应文件
      // config用AppKeyData加密和解密
      final jsonStr = await utf8.decodeStream(await AppKey.decryptDataWithAppKey(() async => await EncryptedData.readFromFile(configFile)));

      return Config.fromJson(jsonDecode(jsonStr));
    }else {
      return null;
    }
  }

  static Future<void> writeConfig(Config config, String configPath) async {
    // 把路径规范化再写入
    config.remoteConfig.basePath = FilePath.fromString(config.remoteConfig.basePath).toUnixPathStr();

    final encData = await AppKey.encryptDataWithAppKey(config.toJsonByteStream());
    final configFile = await getFileAndMakeSureParentDirExist(configPath);
    await encData.writeToFile(configFile);
  }

  // 写入配置到当前仓库的配置文件
  Future<void> writeConfigToDisk(Config config) async {
    await writeConfig(config, getConfigPathByRepoPath(path));
  }

  static String getConfigPathByRepoPath(String repoPath) {
    return p.join(repoPath, dataDirName, localConfigFileNameFileName);
  }

  Future<Config> getConfig() async {
    final config = await readConfig(File(getConfigPathByRepoPath(path)));

    if(config == null) {
      throw AppException("get repo config err: config doesn't exist");
    }

    return config;
  }

  Future<void> updateConfig(Config config) async {
    await writeConfig(
      config,
      getConfigPathByRepoPath(path)
    );
  }

  Future<Config> updateConfigThenGet(Future<void> Function(Config config) onUpdate) async {
    final config = await getConfig();
    await onUpdate(config);

    await writeConfig(
      config,
      getConfigPathByRepoPath(path)
    );

    return config;
  }

  String getDataDirPath() {
    return Repo.getDataDirPathByRepoPath(path);
  }

  String getCacheDirPath() {
    return p.join(getDataDirPath(), cacheDirName);
  }

  String getSyncCacheDirPath() {
    return p.join(getCacheDirPath(), syncCacheDirName);
  }

  String getRepoDebugDirPath() {
    return p.join(getDataDirPath(), debugDirName);
  }

  // String getSyncCacheFilesDirPath() {
  //   return p.join(getSyncCacheDirPath(), syncCacheFilesDirName);
  // }

  Future<TempDir> createTempDir(String prefix) async {
    // 路径：仓库workdir路径/仓库数据目录路径/temp
    return await TempDir.create(getTempDirBasePath(), prefix);
  }

  String getTempDirBasePath() {
    return p.join(path, dataDirName, tempDirName);
  }

  // remote/pfs
  static String getPfsDirPath(String remoteDataDirPath) {
    return p.join(remoteDataDirPath, Remote.pfsDirName);
  }

  static String getPfsDirPathByType(RemoteDataType pfsType, String remoteDataDirPath) {
    if(pfsType == RemoteDataType.objectsPfs) {
      return getPfsObjectsDirPath(remoteDataDirPath);
    }

    if(pfsType == RemoteDataType.filesPfs) {
      return getPfsFilesDirPath(remoteDataDirPath);
    }

    // if(pfsType == RemoteDataType.msgPfs) {
    // }
    return getPfsMsgDirPath(remoteDataDirPath);

  }

  //  dirName: remote/pfs/objects|files|msg/pfs.enc，其中 objects|files|msg 就是dirName，期望是objects|files|msg之一，但不做判断
  static String getPfsFilePathWithSpecifiedDirName(String remoteDataDirPath, String dirName) {
    return p.join(remoteDataDirPath, Remote.pfsDirName, dirName, Remote.pfsFileName);
  }

  // e.g. remote/pfs/objects/pfs.enc
  static String getPfsFilePathByType(RemoteDataType pfsType, String remoteDataDirPath) {
    return p.join(getPfsDirPathByType(pfsType, remoteDataDirPath), Remote.pfsFileName);
  }

  static String getRemoteDataDirNameByPfsType(RemoteDataType pfsType) {
    // if (!pfsType.isPfs()) {
    //   throw AppException("expect pfs remote data type, but got '${pfsType.value}', 12840547");
    // }

    return pfsType == RemoteDataType.objectsPfs
      ? Repo.remoteObjectsDirName
      : pfsType == RemoteDataType.filesPfs
      ? Repo.remoteFilesDirName
      : Repo.remoteMsgDirName;
  }


  // 例如：仓库dataDir/remote/pfs/files
  // 若传 syncCache路径作为参数，则返回：仓库dataDir/cache/syncCache/pfs/files
  static String getPfsFilesDirPath(String remoteDataDirPath) {
    return p.join(getPfsDirPath(remoteDataDirPath), Repo.remoteFilesDirName);
  }

  // e.g. dataDir/remote/pfs/objects
  static String getPfsObjectsDirPath(String remoteDataDirPath) {
    return p.join(getPfsDirPath(remoteDataDirPath), Repo.remoteObjectsDirName);
  }

  // e.g. dataDir/remote/pfs/objects/pfs.enc
  static String getObjectPfsFilePath(String remoteDataDirPath) {
    return p.join(getPfsObjectsDirPath(remoteDataDirPath), Remote.pfsFileName);
  }

  static String getPfsMsgDirPath(String remoteDataDirPath) {
    return p.join(getPfsDirPath(remoteDataDirPath), Repo.remoteMsgDirName);
  }

  /// remote/files/oid/data.enc
  static String getFileInfoPathByOidStr(String remoteDataDirPath, String pathOidStr) {
    return p.join(remoteDataDirPath, Repo.remoteFilesDirName, pathOidStr, Repo.remoteDataFileName);
  }

  static String getMsgPathByOidStr(String remoteDataDirPath, String pathOidStr) {
    return p.join(remoteDataDirPath, Repo.remoteMsgDirName, pathOidStr, Repo.remoteDataFileName);
  }

  static String getLockPathByOidStr(String remoteDataDirPath, String pathOidStr) {
    return p.join(remoteDataDirPath, Repo.remoteLocksDirName, pathOidStr, Repo.remoteDataFileName);
  }

  /// remote/objects/oid/data.enc
  /// 注：这个以前是正式目录用的，后来改成给tempDir用了，目录只有一层，方便处理，正式目录应使用 getLocalRemoteObjectPathByOidStr()，
  ///    区别在于后者会按hash拆分目录，避免目录有过多文件导致加载文件列表时卡顿
  // static String getObjectPathByOidStrForTempDir(String remoteDataDirPath, String oidStr) {
  //   return p.join(remoteDataDirPath, Repo.remoteObjectsDirName, oidStr, Repo.remoteDataFileName);
  // }

  /// 由于本地remote目录可能有很多文件，可能超过1万，所以用hash号分目录避免一个目录存过多文件
  /// e.g. remote/objects/ab/cd/efg...省略/data.enc
  /// 取出一个data.enc的hash则直接拼一下其上三个parent的name即可
  static String getLocalRemoteObjectPathByOidStr(String remoteDataDirPath, String oidStr) {
    return p.join(remoteDataDirPath, Repo.remoteObjectsDirName, oidStr.substring(0, 2), oidStr.substring(2, 4), oidStr.substring(4), Repo.remoteDataFileName);
  }

  /// 通过obj的data.enc取出obj hash
  static String getLocalRemoteObjectOidStrByPath(String dataFilePath) {
    final pathArr = dataFilePath.replaceAll("\\", "/").split("/");
    final len = pathArr.length;
    return pathArr[len-4] + pathArr[len-3] + pathArr[len-2];
  }

  /// datadir/cache/objects/oid/data.enc.dec
  static String getCachedObjectPathByOidStr(String cacheDirPath, String oidStr) {
    return p.join(cacheDirPath, Repo.remoteObjectsDirName, oidStr, Repo.remoteDataFileName+Repo.decryptedDataFileSuffix);
  }

  static String getCachedFileInfoPathByOidStr(String cacheDirPath, String oidStr) {
    return p.join(cacheDirPath, Repo.remoteFilesDirName, oidStr, Repo.remoteDataFileName+Repo.decryptedDataFileSuffix);
  }

  static String getCachedMsgPathByOidStr(String cacheDirPath, String oidStr) {
    return p.join(cacheDirPath, Repo.remoteMsgDirName, oidStr, Repo.remoteDataFileName+Repo.decryptedDataFileSuffix);
  }

  static String getCachedLockPathByOidStr(String cacheDirPath, String oidStr) {
    return p.join(cacheDirPath, Repo.remoteLocksDirName, oidStr, Repo.remoteDataFileName+Repo.decryptedDataFileSuffix);
  }

  // static String getOidDataPathByType(RemoteDataType remoteDataType, String remoteDataDirPath, String oidStr) {
  //   if(remoteDataType == RemoteDataType.objects) {
  //     return getLocalRemoteObjectPathByOidStr(remoteDataDirPath, oidStr);
  //   }
  //
  //   // 这两个目录使用map了，不用目录结构了
  //   // if(remoteDataType == RemoteDataType.files) {
  //   //   return getFileInfoPathByOidStr(remoteDataDirPath, oidStr);
  //   // }
  //   //
  //   // if(remoteDataType == RemoteDataType.msg) {
  //   //   return getMsgPathByOidStr(remoteDataDirPath, oidStr);
  //   // }
  //
  //   throw AppException("get oid data path by type err: unsupported remote data type: $remoteDataType, err code: 18016439");
  // }

  String getMasterKeyPath() {
    // 这个是在本地的keys目录，不是remote/keys
    return p.join(path, dataDirName, keysDirName, masterKeyFileName);
  }

  String getMasterKeyExtraDataPath() {
    return p.join(path, dataDirName, Repo.remoteDirName, keysDirName, masterKeyExtraDataFileName);
  }

  String getContentKeyPath() {
    return p.join(path, dataDirName, Repo.remoteDirName, keysDirName, contentKeyFileName);
  }

  /// 应该先让用户连接一个远程仓库再init？
  /// force: if true, will overwrite when folder is not empty
  /// 返回存放key的目录
  Future<KeyDataPath> initKey(
    String masterPass, {
    required bool moveToDataDir
  }) async {
    final tempDir = await createTempDir("initKey");
    try {
      final basePath = getDataDirPath();

      await createDir(basePath);

      // 用主密码派生密钥
      final masterKeyData = await KeyData.deriveMasterKey(masterPass);

      // 压缩密钥，然后用app内置密码加密派生的密钥（不上传）
      final encryptedData = await AppKey.encryptDataWithAppKey(masterKeyData.toByteStream());

      final tempMasterKeyFile = await tempDir.createTempFile();
      // 把加密后的密钥写入到文件 app配置目录/keys/masterKey.enc
      await writeStreamToFile(
        tempMasterKeyFile,
        encryptedData.toByteStream(),
      );

      // 存主密码附加数据（salt、contentPadding）
      final encryptedMasterKeyExtraData = await AppKey.encryptDataWithAppKey(
        KeyExtraData.genFromKeyData(masterKeyData).toByteStream(),
      );

      final tempMasterKeyExtraDataFile = await tempDir.createTempFile();

      // 把主密码salt写入到文件 app配置目录/keys/mks.enc
      await writeStreamToFile(
        tempMasterKeyExtraDataFile,
        encryptedMasterKeyExtraData.toByteStream(),
      );

      // 随机生成“内容密钥”
      final contentKeyData = await KeyData.deriveContentKey();
      // 用上面派生的密钥加密压缩后的内容密钥文件
      final encryptedContentKeyData = await EncryptedData.compressThenEncrypt(
        contentKeyData.toByteStream(),
        masterKeyData,
      );

      final tempContentKeyFile = await tempDir.createTempFile();

      // 把加密后的密钥写入到文件 app配置目录/remotes/keys/contentKey.enc
      await writeStreamToFile(
        tempContentKeyFile,
        encryptedContentKeyData.toByteStream(),
      );

      // push key
      await pushKey(tempContentKeyFile, tempMasterKeyExtraDataFile);

      // 移动到正式目录
      if(moveToDataDir) {
        final masterKeyFile = await getFileAndMakeSureParentDirExist(getMasterKeyPath());
        final masterKeyExtraDataFile = await getFileAndMakeSureParentDirExist(getMasterKeyExtraDataPath());
        final contentKeyFile = await getFileAndMakeSureParentDirExist(getContentKeyPath());
        // 若出问题，可提示用户把bak文件全部取消 bak 文件后缀即可
        await safeRename(masterKeyFile, masterKeyFile.absolute.path+backupFileSuffix);  // 这个源文件可能不存在，所以用safeRename
        await tempMasterKeyFile.rename(masterKeyFile.absolute.path);  // 这个如果出错，应抛异常
        await safeRename(masterKeyExtraDataFile, masterKeyExtraDataFile.absolute.path+backupFileSuffix);
        await tempMasterKeyExtraDataFile.rename(masterKeyExtraDataFile.absolute.path);
        await safeRename(contentKeyFile, contentKeyFile.absolute.path+backupFileSuffix);
        await tempContentKeyFile.rename(contentKeyFile.absolute.path);


        return KeyDataPath(masterKey: masterKeyFile.absolute.path, masterKeyExtraData: masterKeyExtraDataFile.absolute.path, contentKey: contentKeyFile.absolute.path);
      }

      return KeyDataPath(masterKey: tempMasterKeyFile.absolute.path, masterKeyExtraData: tempMasterKeyExtraDataFile.absolute.path, contentKey: tempContentKeyFile.absolute.path);

    }finally {
      await tempDir.clean();
    }
  }

  Future<void> pushKey(File contentKeyFile, File masterKeyExtraDataFile) async {
    final remoteContentKeyPath = remote.getRemoteContentKeyPath();
    final remoteMasterKeyExtraDataPath = remote.getRemoteMasterKeyExtraDataPath();

    // 重命名旧文件，如果有
    // rename 'contentKey.enc' to 'contentKey.enc.bak'
    await remote.renameSafe(
      remoteContentKeyPath,
      remoteContentKeyPath.copyThenRename(remoteContentKeyPath.name()+Repo.backupFileSuffix),
      isDir: false
    );
    await remote.renameSafe(
      remoteMasterKeyExtraDataPath,
      remoteMasterKeyExtraDataPath.copyThenRename(remoteMasterKeyExtraDataPath.name()+Repo.backupFileSuffix),
      isDir: false
    );

    // 上传新文件
    await remote.uploadFile(remoteContentKeyPath, contentKeyFile);
    await remote.uploadFile(remoteMasterKeyExtraDataPath, masterKeyExtraDataFile);
  }

  Future<void> downloadKeys() async {
    final remoteContentKeyPath = remote.getRemoteContentKeyPath();
    final remoteMasterKeyExtraDataPath = remote.getRemoteMasterKeyExtraDataPath();

    final tempDir = await createTempDir("downloadKeys");

    try {
      final tempContentKeyFile = await tempDir.createTempFile();
      final tempMasterKeyExtraDataFile = await tempDir.createTempFile();

      // 上传
      final downloadContentKeyDataSuccess = await remote.downloadToFileNoThrow(remoteContentKeyPath, tempContentKeyFile, tempDir);
      if(!downloadContentKeyDataSuccess) {
        throw AppException("The remote repository does not have a content key file.");
      }

      final downloadMasterKeyExtraDataSuccess = await remote.downloadToFileNoThrow(remoteMasterKeyExtraDataPath, tempMasterKeyExtraDataFile, tempDir);
      if(!downloadMasterKeyExtraDataSuccess) {
        throw AppException("The remote repository does not have a master key extra data file.");
      }

      final contentKeyFile = await getFileAndMakeSureParentDirExist(getContentKeyPath());

      // 备份旧文件，如果有
      await safeRename(contentKeyFile, contentKeyFile.absolute.path+Repo.backupFileSuffix);

      // 把下载的key移动到本地的 remote/keys
      await tempContentKeyFile.rename(contentKeyFile.absolute.path);

      final masterKeyExtraDataFile = await getFileAndMakeSureParentDirExist(getMasterKeyExtraDataPath());

      // 备份旧文件，如果有
      await safeRename(masterKeyExtraDataFile, masterKeyExtraDataFile.absolute.path+Repo.backupFileSuffix);

      // 把下载的key移动到本地的 remote/keys
      await tempMasterKeyExtraDataFile.rename(masterKeyExtraDataFile.absolute.path);


    }finally {
      await tempDir.clean();
    }
  }

  /// 如果验证通过，将会把masterPass生成的key存到本地的 keys/masterKey.enc
  /// return: null or Exception
  Future<VerifyMasterKeyFailedException?> verifyMasterKey(String masterPass, {required bool moveToDataDirIfVerified}) async {
    final tempDir = await createTempDir("verifyMasterKey");

    try {
      final masterKeyExtraData = await getMasterKeyExtraData();

      final masterKey = await KeyData.deriveMasterKey(masterPass, keyExtraData: masterKeyExtraData);
      final contentKeyEncData = await EncryptedData.readFromFile(File(getContentKeyPath()));

      // 如果解密成功，说明masterPass是正确密码
      final contentKeyBytes = await contentKeyEncData.decryptThenUncompress(masterKey);

      // 读取数据，验证是否正确，这步必须，不读不知道错没错
      final contentKeyData = await KeyData.readFromStream(contentKeyBytes);
      // 若能解密出contentKey，应该就不会为空？所以这步是否多余？
      if(contentKeyData.key.isEmpty) {
        return VerifyMasterKeyFailedException("content key bytes is empty");
      }

      if(moveToDataDirIfVerified) {
        //备份旧文件，如果有的话
        final masterKeyFile = await getFileAndMakeSureParentDirExist(getMasterKeyPath());
        await safeRename(masterKeyFile, masterKeyFile.absolute.path+backupFileSuffix);

        //把新文件移动过去
        final tempMasterKeyFile = await tempDir.createTempFile();
        // masterkey验证通过后，在本地用appkey加密，并且不会上传到远程
        final encData = await AppKey.encryptDataWithAppKey(masterKey.toByteStream());
        await writeStreamToFile(tempMasterKeyFile, encData.toByteStream());
        await tempMasterKeyFile.rename(masterKeyFile.absolute.path);
      }

      return null;
    }catch(e) {
      return VerifyMasterKeyFailedException(e.toString(), data: e);
    }finally {
      await tempDir.clean();
    }
  }

  Future<void> initRepoInfo(TempDir tempDir) async {
    final repoInfo = RepoInfo(id: VersionOid.randomOid().value, repoName: repoName, userId: App.emptyUserId);
    await pushRepoInfo(repoInfo, await getContentKey(), tempDir, true);
  }

  Future<void> initSyncHistory(TempDir tempDir) async {
    final syncHistory = SyncHistory();
    await pushSyncHistory(syncHistory, await getContentKey(), tempDir, true);
  }

  Future<KeyData> getMasterKey() async {
    final masterKeyFile = File(getMasterKeyPath());
    return await KeyData.readFromStream(await AppKey.decryptDataWithAppKey(() async => await EncryptedData.readFromFile(masterKeyFile)));
  }

  Future<KeyData> getContentKey({KeyData? masterKeyData}) async {
    final masterKey = masterKeyData ?? await getMasterKey();
    final contentKeyFile = File(getContentKeyPath());
    final encData = await EncryptedData.readFromFile(contentKeyFile);
    return await KeyData.readFromStream(await encData.decryptThenUncompress(masterKey));
  }


  Future<KeyExtraData> getMasterKeyExtraData() async {
    final extraFile = File(getMasterKeyExtraDataPath());
    return await KeyExtraData.readFromStream(await AppKey.decryptDataWithAppKey(() async => await EncryptedData.readFromFile(extraFile)));
  }


  // 检查与否其实无所谓，直接throw就行，如果能取消，自然就取消，
  // 取消不了说明已经执行到最后一步（上传了远程syncCache/info.enc或者下一步就是上传此文件）了，取消不了了
  bool syncCanBeCanceled() {
    // 若能回滚则能取消，否则基本操作已经完成，只剩重命名了，就无法取消了
    return remote.sessionCanRollback;
  }

  Future<SyncResult> syncWithLock<T extends RelatedOids>({
    KeyData? paramContentKeyData,
    bool force = false,
    ThrowIfInterrupted? throwIfSyncCanceled,
    SyncProgressCb? syncProgressCb,
    bool forceForCommitChanges = false,

    // 删除回收站条目和冲突msg用的
    RemoteDataType? remoteDataType,
    List<T>? delItemsWhenSync,
    bool needInitRemote = true,
  }) async {
    final contentKeyData = paramContentKeyData ?? await getContentKey();
    return await doActWithLock(
      contentKeyData,
      actName: "sync",
      actDesc: "sync files",
      needInitRemote: needInitRemote,
      act: (throwIfLockLost, isLockRenewaling, remoteSessionCommitBegin, remoteSessionCommitEnd) async {
        void throwIfInterrupted() {
          // 锁被别人抢了
          throwIfLockLost();

          // 外部取消了任务，比如用户点击了取消按钮
          throwIfSyncCanceled?.call();
        }

        return await sync(
          contentKeyData,
          force: force,
          throwIfSyncCanceled: throwIfInterrupted,
          syncProgressCb: syncProgressCb,
          forceForCommitChanges: forceForCommitChanges,

          remoteDataType: remoteDataType,
          delItemsWhenSync: delItemsWhenSync,
          isLockRenewaling: isLockRenewaling,
          remoteSessionCommitBegin: remoteSessionCommitBegin,
          remoteSessionCommitEnd: remoteSessionCommitEnd,
        );
      }
    );
  }

  // 先获取仓库本地锁，再获取远程锁，然后执行任务
  Future<T> doActWithLock<T>(
    KeyData contentKeyData, {
    required String actName,
    required String actDesc,
    required bool needInitRemote,
    required Future<T> Function(
      ThrowIfInterrupted throwIfLockLost,
      Future<bool> Function() isLockRenewaling,
      Future<void> Function() remoteSessionCommitBegin,
      Future<void> Function() remoteSessionCommitEnd,
    ) act,
  }) async {
    // 先获取仓库本地锁，若获取失败，说明仓库正在执行操作，就不用获取远程锁了
    final localLockToken = LockToken(actName: actName, actDesc: actDesc);
    final localLocked = lockLocalRepoByPath(path, localLockToken);
    if(localLocked != null) {
      throw RepoBusyException(actName: localLocked.actName, actDesc: localLocked.actDesc);
    }

    try {
      // 先init再拿锁，其实还有个问题，假如当前有任务正在执行，那我这一刷新，这个仓库的任务的access token就失效了啊！
      // 所以：必须先拿本地锁，若能拿到，再去拿远程锁，这样就能确保本地没冲突了
      // 因为锁也需要访问远程仓库，所以，必须先刷新token，不过如果调用者刚刷新过，就没必要刷了
      if(needInitRemote) {
        final tempDirForInitRemote = await createTempDir("init_remote");
        try {
          await remote.doInit(tempDirForInitRemote, packMaxLen: await getEffectPackMaxLen());
        }finally {
          await tempDirForInitRemote.clean();
        }
      }


      final mainRp = ReceivePort();

      await Lock.spawnNewLockTask(
        remote,
        await remote.toRemoteConfig(),
        contentKeyData,
        getTempDirBasePath(),
        client,
        mainRp,
        actName: actName,
        actDesc: actDesc
      );

      bool? locked;
      SendPort? childSp;
      bool unlockSuccess = false;
      String errMsg = "";
      // 是否正在续锁，若后端是git，需要避免在续锁时提交
      bool lockRenewaling = false;

      mainRp.listen((m) async {
        if(m is SendPort) {
          childSp = m;

          // 锁续订失败，续定任务取消
        }else if(m == lockCmdRenewalFailed || m == lockCmdAcquireLockFailed) {
          locked = false;
        }else if(m == lockCmdAcquireLockSuccess) {
          locked = true;
        }else if(m == lockCmdUnlocked) {
          unlockSuccess = true;
        }else if(m is Map) {
          // 暂时只用Map传错误信息，以后若添加更多类型的命令，需要做判断
          // err
          // if(m["type"] == lockCmdErr)
          locked = false;
          unlockSuccess = true;
          errMsg = m["err"];
          App.logger.debug(_TAG, "#doActWithLock err(from child Isolate): $m");
        }else if(m == lockCmdRenewalSuccess) {
          // 续锁成功，回复一个信息，告知子线程，主线程还活着
          childSp?.send(lockCmdMainStillAliveResponse);
        }else if(m == lockCmdRenewalBegin) {
          lockRenewaling = true;
        }else if(m == lockCmdRenewalEnd) {
          lockRenewaling = false;
        }
      });

      // 等，直到拿到或释放锁
      App.logger.debug(_TAG, "#doActWithLock: waiting for lock...");

      while(locked == null) {
        await Future.delayed(Duration(milliseconds: 100));
      }

      if(!locked!) {
        throw StateError("require lock failed, if no task running, lock will auto expired after ${defaultHoldTimeInMilliseconds/1000}s, error is: $errMsg");
      }


      void throwIfLockLost() {
        if(!locked!) {
          throw StateError("Lock lost");
        }
      }

      bool isGitBackend = false;
      if(remote.type.value == RemoteType.localDir.value) {
        isGitBackend = (remote as LocalDir).config.isGitBackend;
      }

      Future<bool> isLockRenewaling() async {
        return lockRenewaling;
      }

      Future<void> remoteSessionCommitBegin() async {
        if(!isGitBackend) {
          return;
        }

        // 若git后端，避免提交会话和上传lock冲突，等待，直到上传锁结束
        while(await isLockRenewaling()) {
          await Future.delayed(Duration(seconds: 1));
        }

        childSp?.send(lockCmdRemoteSessionCommitBegin);
      }

      Future<void> remoteSessionCommitEnd() async {
        if(!isGitBackend) {
          return;
        }

        childSp?.send(lockCmdRemoteSessionCommitEnd);
      }

      // dart根本没有能力保证finally一定会执行，catch与否都无法保证
      try {
        return await act(throwIfLockLost, isLockRenewaling, remoteSessionCommitBegin, remoteSessionCommitEnd);
      }finally {
        if(childSp != null) {
          try {
            // 发送信号，让子线程自己退出，不要直接杀，不然不会清缓存目录
            childSp!.send(lockCmdFinished);

            // 等10秒，等到子线程退出，100毫秒检查一次，检查100次
            final waitCount = 100;
            for(var i = 0; i < waitCount; i++) {
              await Future.delayed(Duration(milliseconds: 100));

              if(unlockSuccess) {
                App.logger.debug(_TAG, "#doActWithLock(): unlock success");
                break;
              }
            }
          }catch(e) {
            App.logger.debug(_TAG, "#doActWithLock() err: send finished msg to child isolate err: $e");
          }

        }else {
          App.logger.debug(_TAG, "#doActWithLock() err: send finished msg err: lock send port is null");
        }

        // 关闭父线程接收器
        mainRp.close();
      }

    }finally {
      freeLocalRepoLockByPath(path, localLockToken);
    }

  }

  String getRemoteDataDirPath() {
    return p.join(path, dataDirName, remoteDirName);
  }

  String getRemoteFilesDirPath() {
    return p.join(getRemoteDataDirPath(), remoteFilesDirName);
  }

  String getRemoteObjectsDirPath() {
    return p.join(getRemoteDataDirPath(), remoteObjectsDirName);
  }

  String getRemoteMsgDirPath() {
    return p.join(getRemoteDataDirPath(), remoteMsgDirName);
  }


  /// 比较本地和远程目录有哪些文件不同
  /// 拉消息（更新本地消息，以远程为准）
  /// 拉文件（可能会有冲突，创建msg，上传obj，但不可能推送fileinfo）
  /// 推文件（更新file info和关联obj，不创建msg，不会有冲突）
  // Future<void> sync_old(
  //   KeyData contentKeyData,
  //   bool Function() taskCanceled, {
  //   required bool pullEvenRepoInfoIsLatest
  // }) async {
  //   final tempDir = await createTempDir("sync");
  //
  //   try {
  //     final remoteDataDirPath = getRemoteDataDirPath();
  //     final workdirFullPath = path;
  //
  //
  //     // 校验仓库info，若为最新，无需pull
  //     // 读取本地仓库信息
  //     final repoInfoEncData = await EncryptedData.readFromFile(File(getRepoInfoPath()));
  //     final repoInfo = await RepoInfo.fromJsonByteStream(repoInfoEncData.decryptThenUncompress(contentKeyData));
  //
  //     // 下载远程仓库info
  //     final remoteRepoInfoTempFile = await downloadRepoInfo(tempDir);
  //     final remoteRepoInfoEncData = await EncryptedData.readFromFile(remoteRepoInfoTempFile);
  //     final remoteRepoInfo = await RepoInfo.fromJsonByteStream(remoteRepoInfoEncData.decryptThenUncompress(contentKeyData));
  //
  //     if(remoteRepoInfo.id != repoInfo.id) {
  //       throw AppException("Repo id doesn't match");
  //     }
  //
  //     // TODO 完事后把这几个print删掉
  //     var start = TimeData.now().utcMilliseconds;
  //     // 拉msg
  //     await pullAllMsg(contentKeyData, remoteDataDirPath, remote, taskCanceled);
  //     logger("pullAllMsg done:"+ (start - TimeData.now().utcMilliseconds).toString());
  //
  //     start = TimeData.now().utcMilliseconds;
  //     final index = await getIndex();
  //     MergeResult? mergeResult;
  //     // 本地数据不是最新，需合并
  //     if(pullEvenRepoInfoIsLatest || remoteRepoInfo.lastNode() != repoInfo.lastNode()) {
  //       // pull
  //       mergeResult = await pull(contentKeyData, remoteDataDirPath, workdirFullPath, taskCanceled, index);
  //     }else {
  //       mergeResult = MergeResult();
  //     }
  //     logger("pull done:"+ (start - TimeData.now().utcMilliseconds).toString());
  //
  //     start = TimeData.now().utcMilliseconds;
  //
  //     // 先更新远程仓库info，再push，避免push中断，文件修改，但更新仓库失败，导致拉取的不知道数据变了
  //     remoteRepoInfo.addNode(VersionNode(oid: VersionOid.randomOid(), clientName: client.name));
  //     final nextRepoInfoEncData = await EncryptedData.compressThenEncrypt(remoteRepoInfo.toJsonByteStream(), contentKeyData);
  //     final tempNextRepoInfo = await tempDir.createTempFile();
  //     await writeStreamToFile(tempNextRepoInfo, nextRepoInfoEncData.toByteStream());
  //     await remote.upload(remote.getRemoteRepoInfoPath(), tempNextRepoInfo.openRead());
  //     safeRename(tempNextRepoInfo, getRepoInfoPath());
  //
  //     // push
  //     // await push(contentKeyData, remoteDataDirPath, workdirFullPath, mergeResult, taskCanceled, index);
  //     logger("push done:"+ (start - TimeData.now().utcMilliseconds).toString());
  //
  //     // 更新索引
  //     await writeIndex(index, tempDir);
  //   }finally {
  //     await tempDir.clean();
  //   }
  //
  // }

  // 这个函数，理论上，如果本地workdir对应路径是目录，而远程是文件，在覆盖或提交时，应该会报错，需要用户手动删除或复制对应目录到仓库外
  Future<void> useRemoteFilesMapOverwriteWorkdir({
    required KeyData contentKeyData,
    required SyncHistory remoteSyncHistory,
    required ThrowIfInterrupted? throwIfInterrupted,
    required SyncProgressCb? progressCb,
    required TempDir tempDir,
  }) async {
    progressCb?.call(SyncProgressAct.willUseRemoteFilesOverwriteWorkdir, 0, 0, "");

    // 用远程文件列表覆盖本地workdir，把待删除待覆盖的workdir文件和syncHistory、filesMap、msgMap都添加到syncCache，更新索引，提交本地syncCache就行了
    final remote = this.remote;
    final remoteFilesMap = remote.filesMap!;
    final workdirBasePath = getWorkdirPath();

    Set<String> handledRelativePath = {};
    // workdir将会被删除的条目（会先记录到syncCache，在同步后再真删除workdir的文件）
    final workdirDeletedFiles = WorkdirFiles();
    // workdir将会被覆盖为远程最新版本的条目（会先存到syncCache/workdir，在同步后再真覆盖）
    final workdirOverwriteFiles = WorkdirFiles();
    final localSyncCacheDirPath = getSyncCacheDirPath();
    // final remoteDataDirPath = getRemoteDataDirPath();

    Future<void> downloadFileAndAddToWorkdirWillOverwriteList(VersionOid remoteObjOid, FilePath workdirFilePath, FilePath relativePath, String lfLatestOidStr) async {
      // 把文件存到syncCache里先，提交后再拷贝到正式目录
      // syncCache/workdir/文件在正式目录下的相对路径
      final workdirFileFullPathInSyncCache = await getFileAndMakeSureParentDirExist(
        p.join(
          localSyncCacheDirPath,
          Repo.workdirDirName,
          relativePath.toString()
        )
      );

      final localObjFile = await getLocalOrFetch(
        RemoteDataType.objects,
        remoteObjOid,
        tempDir,
        // localRemoteDataDirPath: remoteDataDirPath,
        // remoteDataDirForFetch: remoteDataDirPath,

        // 之前是下载到syncCache是为了确保下载文件到syncCache，再rename到正式目录，避免write stream时中断导致文件不完整（无法完全保证），
        // 但直接下载到remoteDataDirPath也一样，因为fetchData时，本身就是先下载到临时文件再rename到正式目录的
        // remoteDataDirForFetch: syncCacheDirPath,

        moveToRemoteDataDirAfterDownload: true
      );

      //解密数据
      final encryptedObj = await EncryptedData.readFromFile(localObjFile);
      final decryptedObj = await encryptedObj.decryptThenUncompress(contentKeyData);

      //存储到workdir对应path
      final tempFile = await tempDir.createTempFile();
      await writeStreamToFile(tempFile, decryptedObj);
      await tempFile.rename(workdirFileFullPathInSyncCache.absolute.path);

      await workdirOverwriteFiles.addFile(relativePath, workdirFilePath.toFile(), lfLatestOidStr);
    }

    Future<void> addToWorkdirWillDeleteList(FilePath workdirFilePath, FilePath relativePath, String lfLatestOidStr) async {
      await workdirDeletedFiles.addFile(relativePath, workdirFilePath.toFile(), lfLatestOidStr);
    }


    final allCount = remoteFilesMap.data.values.length;
    int count = 0;
    // 找出本地和远程都有，且不一样的条目，用远程覆盖本地
    // 找出本地无远程有的条目，用远程覆盖本地
    for(final fileInfoJsonMap in remoteFilesMap.data.values) {
      count++;
      throwIfInterrupted?.call();

      final fileInfo = FileInfo.fromJson(fileInfoJsonMap);
      // String act, int allCount, int currentAt, String extraInfo
      progressCb?.call(SyncProgressAct.handleChanges, allCount, count, fileInfo.path);
      final relativePath = FilePath.fromString(fileInfo.path, isRelative: true);
      handledRelativePath.add(relativePath.toUnixPathStr());
      final workdirFilePath = FilePath.fromString(p.join(workdirBasePath, relativePath.toString()));
      final workdirFileType = await getFileType(workdirFilePath.toString());
      final remoteObjOid = fileInfo.getLatestVersion().oid;
      if(remoteObjOid.value == VersionOid.deleted.value) {
        if(workdirFileType == FileSystemEntityType.notFound) {
          continue;
        }

        // 这里就不做这个判断了，若对应条目是目录，删除时会报错，因为只删文件，不删目录，到时候让用户手动去删除目录吧，若改成直接删除，会直接删除整个目录下所有文件，无法恢复
        // if(workdirFileType != FileSystemEntityType.file) {
        //   await overwriteLocalFile(remoteObjOid, workdirFilePath);
        //   continue;
        // }
        await addToWorkdirWillDeleteList(workdirFilePath, relativePath, "");
      }else {  // 远程不是删除
        if(workdirFileType == FileSystemEntityType.notFound) {  // 本地不存在，直接覆盖
          await downloadFileAndAddToWorkdirWillOverwriteList(remoteObjOid, workdirFilePath, relativePath, "");
        }else if(workdirFileType == FileSystemEntityType.file) {  // 本地存在文件，检查hash是否匹配
          // 注释编号：11285410
          // 若对应路径是目录，会报错
          // 有4种处理方案：
          // 1. 直接在计算hash时报错（目前是这样，报错后需用户手动删除对应目录，触发情况应该不高，而且这样百分百不会误删某目录下多个文件，所以暂且先这样）
          // 2. 会添加对应路径到待删除列表，但删除时只删File类型，所以实际会报错，需用户手动介入 （目前实际在计算hash时就报错了，所以不会发生这种情况）
          // 3. 直接在这调用Dir的递归删除，删除路径，Dir的递归删除对文件和路径都有效，然后再添加远程文件到workdir待覆盖列表
          // 4. 把提交本地commitSyncCache时的覆盖调用改成先调用Dir递归删除，再覆盖
          // 5. 不推荐：先添加一个workdir待删除记录，并且把提交syncCache时处理workdir待删除的调用改成使用Dir递归删除，然后再添加一条workdir覆盖记录，这样就能先删后覆盖了
          final workdirFileOidStr = await hashFileToHexWithKeyDataForSync(filePath: workdirFilePath.toString(), contentKeyData: contentKeyData, throwIfInterrupted: throwIfInterrupted);
          if(workdirFileOidStr == remoteObjOid.value) {
            continue;
          }

          await downloadFileAndAddToWorkdirWillOverwriteList(remoteObjOid, workdirFilePath, relativePath, workdirFileOidStr);
        }else {  // 本地非文件类型，先删除，后覆盖
          // 先删除，再覆盖，MergeMode为remoteOverwriteWorkdir时有做特殊处理，即使目标类型不是文件也会强制删除（调用递归删除）
          // 不需要添加到删除列表，remote overwrite workdir 模式下覆盖前会先删对应路径
          // await addToWorkdirWillDeleteList(workdirFilePath, relativePath, "");
          await downloadFileAndAddToWorkdirWillOverwriteList(remoteObjOid, workdirFilePath, relativePath, "");
        }
      }
    }

    throwIfInterrupted?.call();


    progressCb?.call(SyncProgressAct.findingChanges, 0, 0, "");

    // 找出本地有远程无的条目，删除
    final newIndex = Index();
    final lastContentIdOfNewIndex = newIndex.contentId;
    final ignores = await getIgnores();

    await forEachFiles(
      workdirBasePath,
      // item就是workdir目录下的文件
      (workdirFileEntity) async {
        throwIfInterrupted?.call();
        count++;

        final workdirFileEntityPath = workdirFileEntity.absolute.path;

        final relativePath = FilePath.genRelativePath(workdirBasePath, workdirFileEntityPath);
        if(handledRelativePath.contains(relativePath.toUnixPathStr())) {
          return true;
        }

        handledRelativePath.add(relativePath.toUnixPathStr());

        final workdirFilePath = FilePath.fromString(workdirFileEntityPath);


        progressCb?.call(SyncProgressAct.checkingChanges, allCount, count, relativePath.toUnixPathStr());


        if(SimpleIgnoreMatcher.shouldIgnore(ignores, relativePath.toUnixPathStr())) {
          // 忽略的条目，若路径是目录，不进入目录，返回false
          return false;
        }


        // 在这里若是目录则返回是没问题的，不会遗漏文件；
        // 如果remote对应路径是文件，本地是目录，
        // 那么会在上面遍历remote files values时处理。
        // 参见：注释编号：11285410
        if(workdirFileEntity is! File) {
          // 即使条目不是目录，内部文件可能未被忽略，所以这里返回true，条目目录本身，但进入目录检查其内部文件
          return true;
        }

        final remoteFileInfoJsonMap = remoteFilesMap.get(await relativePath.toOid(contentKeyData));
        if(remoteFileInfoJsonMap == null) {
          await addToWorkdirWillDeleteList(workdirFilePath, relativePath, "");
          return true;
        }

        final remoteFileInfo = FileInfo.fromJson(remoteFileInfoJsonMap);
        final remoteObjOid = remoteFileInfo.getLatestVersion().oid;
        if(remoteObjOid.value == VersionOid.deleted.value) {
          await addToWorkdirWillDeleteList(workdirFilePath, relativePath, "");
          return true;
        }else {
          final workdirFileOidStr = await hashFileToHexWithKeyDataForSync(filePath: workdirFilePath.toString(), contentKeyData: contentKeyData, throwIfInterrupted: throwIfInterrupted);
          if(workdirFileOidStr == remoteObjOid.value) {
            await newIndex.addFile(relativePath, workdirFilePath.toFile(), workdirFileOidStr, lastContentIdOfNewIndex);
            return true;
          }

          await downloadFileAndAddToWorkdirWillOverwriteList(remoteObjOid, workdirFilePath, relativePath, workdirFileOidStr);
          return true;
        }
      },
    );



    throwIfInterrupted?.call();
    progressCb?.call(SyncProgressAct.movingDownloadedFiles, 0, 0, "");

    if(workdirOverwriteFiles.isNotEmpty()) {
      final willOverwriteInSyncCache = await getFileAndMakeSureParentDirExist(p.join(localSyncCacheDirPath, Repo.workdirWillOverwriteFileName));
      await writeStrToFile(willOverwriteInSyncCache, jsonEncode(workdirOverwriteFiles.toJson()));
    }

    throwIfInterrupted?.call();

    if(workdirDeletedFiles.isNotEmpty()) {
      final willDelFileInSyncCache = await getFileAndMakeSureParentDirExist(p.join(localSyncCacheDirPath, Repo.workdirWillDeleteFileName));
      await writeStrToFile(willDelFileInSyncCache, jsonEncode(workdirDeletedFiles.toJson()));
    }

    throwIfInterrupted?.call();

    await writeIndex(newIndex, p.join(localSyncCacheDirPath, localIndexFileName));
    throwIfInterrupted?.call();

    // 把最新syncHistory存到本地syncCache，稍后会提交
    final syncHistoryFileInSyncCache = await getFileAndMakeSureParentDirExist(p.join(localSyncCacheDirPath, syncHistoryFileName));
    remoteSyncHistory.rollbackOnce();  //因为同步前会插入一个新节点，所以这里需要回滚，不然会和远程不一致
    final encData = await EncryptedData.compressThenEncrypt(remoteSyncHistory.toJsonByteStream(), contentKeyData);
    await encData.writeToFile(syncHistoryFileInSyncCache);
    throwIfInterrupted?.call();

    await latestPfsFileHandler(
      RemoteDataType.objectsPfs,
      null,
      remote.objectsPfs!,
      contentKeyData,
      tempDir
    );

    await latestFilesMapHandler(remote.filesMap!, contentKeyData, tempDir);
    throwIfInterrupted?.call();
    // await writeMergeMode(localSyncCacheDirPath, MergeMode.remoteOverwriteWorkdir);
    await createSyncCacheInfo(mergeMode: MergeMode.remoteOverwriteWorkdir);
    await commitSyncCacheIfNeed();
  }

  // static String getMergeModePath(String basePath) {
  //   return p.join(basePath, mergeModeFileName);
  // }
  //
  // Future<void> writeMergeMode(String basePath, int mergeMode) async {
  //   File(getMergeModePath(basePath)).writeAsStringSync(mergeMode.toString(), flush: true);
  // }
  //
  // Future<int> readMergeMode(String basePath) async {
  //   final file = File(getMergeModePath(basePath));
  //   int? result;
  //   if(await file.exists()) {
  //     result = int.tryParse((await file.readAsString()).trim());
  //   }
  //
  //   return result ?? MergeMode.mergeRemoteAndWorkdir;
  // }

  Future<SyncResult> sync<T extends RelatedOids>(
    KeyData contentKeyData, {
    // 强制检测所有文件更新，无视index和同步历史中记录的推送文件列表
    required bool force,
    ThrowIfInterrupted? throwIfSyncCanceled,
    SyncProgressCb? syncProgressCb,
    // 传给remote.sessionCommit()的force选项，功能：
    // 1. 待上传的数据（注意是检查后，发现需要上传的数据，不是所有的本地数据），
    // 即使remoteDataType是不可变的（例如objects和msg），
    // 也强制从.pack里和pfs删除对应文件和其记录，然后重新上传，
    // 一般没必要开启这个选项，除非远程仓库对应数据有误，但对用户来说，
    // 其实不太好判断某个数据是否有误，所以，其实没有需要此选项的场景？
    bool forceForCommitChanges = false,

    required RemoteDataType? remoteDataType,
    required List<T>? delItemsWhenSync,
    Future<bool> Function()? isLockRenewaling,
    Future<void> Function()? remoteSessionCommitBegin,
    Future<void> Function()? remoteSessionCommitEnd,
  }) async {
    final tempDir = await createTempDir("sync");

    syncProgressCb?.call(SyncProgressAct.commitLocalSyncCache, 0, 0, "");

    await commitSyncCacheIfNeed();

    SyncHistory? remoteSyncHistory;
    // SyncHistoryNode? latestHistoryNode;
    // final nextSyncVersion = 0;
    final emptyFilePath = "";

    final lastSyncInfo = await getLastSyncInfo();

    syncProgressCb?.call(SyncProgressAct.remoteReady, 0, 0, emptyFilePath);

    // if remote is dropbox, check username and avatar, if changed, update repo config
    final remote = this.remote;
    if(remote is Dropbox) {
      final repoConfig = await getConfig();
      if(repoConfig.remoteConfig.type == RemoteType.dropbox.value) {
        final remoteConfigBefore = RemoteConfigDataForDropbox.fromJson(repoConfig.remoteConfig.data);
        final remoteConfigLatest = remote.config;
        // uid 相等（确保是同一个用户），但用户名或头像不相等，更新配置文件
        if(remoteConfigBefore.uid == remoteConfigLatest.uid && 
        (remoteConfigBefore.avatar != remoteConfigLatest.avatar || 
          remoteConfigBefore.username != remoteConfigLatest.username
        )) {
          repoConfig.remoteConfig.data = remoteConfigLatest.toJson();
          await writeConfigToDisk(repoConfig);
        }
      }else {
        // this should never happenes
        throw AppException("remote type and repo config type didn't match, remote is Dropbox, but repo config type is: ${repoConfig.remoteConfig.type}");
      }
    }

    final sessionId = await remote.sessionStart(
      "sync",
      "sync data",
      contentKeyData,
      tempDir,
      throwIfInterrupted: throwIfSyncCanceled,

      isLockRenewaling: isLockRenewaling,
      remoteSessionCommitBegin: remoteSessionCommitBegin,
      remoteSessionCommitEnd: remoteSessionCommitEnd,

      client: client,
    );

    int remoteFilesCount = remote.filesMap?.size() ?? 0;


    try {
      // final forceSyncFlagFile = getForceSyncFlagFile();
      // if(await forceSyncFlagFile.exists()) {
      //   force = true;
      //   App.logger.debug(_TAG, "#sync(): force sync enabled, because flag file exists, reason is: ${await forceSyncFlagFile.readAsString()}");
      // }

      final remoteDataDirPath = getRemoteDataDirPath();
      final workdirBasePath = path;

      final Index index;
      if(force) {  // force，清空index，强制重新检查所有文件的修改
        syncProgressCb?.call(SyncProgressAct.forceSyncAlert, 0, 0, emptyFilePath);

        // 清空索引，强制重新检测所有文件修改
        // 会重新计算所有文件的hash，若文件多，性能会很差
        index = await cleanIndex();
      }else {  // 非force，读取Index
        index = await getIndex();
      }


      // 读取syncHistory
      final syncHistoryPair = await getNextSyncHistory(contentKeyData, tempDir, force: force);
      // 注意，这里的 syncHistoryPair.remote 已经包含了新节点，只是state为started而不是finished
      remoteSyncHistory = syncHistoryPair.remote;

      // 检查是否需要执行远程覆盖本地
      final config = await getConfig();
      int mergeMode = config.mergeMode;
      // 如果changes为空，代表远程没文件更新，不需要合并
      // 如果changes为null或非空，代表远程很可能有新的文件需要拉取，进一步检测本地是否有需要上传的条目，若有，则代表需要合并，抛出特定异常
      if(mergeMode == MergeMode.remoteOverwriteWorkdir) {
        final changes = syncHistoryPair.changes;
        if(changes == null || changes.isNotEmpty) { // 远程很可能有文件需要拉取
          // 检查是否本地有需要上传的条目
          // 不能创建新tempDir，否则fetchCache目录会不可用，应该不会有污染，如果这里的操作会污染tempDir的话，
          // 可在finally里删除tempDir.workdir()，但应该不需要
          // final tempDir = await createTempDir("remoteOverwriteWd");

          try {
            VirtualFile.reset();
            final workdirBasePath = getWorkdirPath();
            final localFileMap = await getLocalFilesMap(contentKeyData);

            // 检查是否有文件需要推送
            await findLocalChanges(
              index: index,  // 此函数不会修改此index
              lastContentIdOfIndex: index.contentId,
              newIndex: null,
              lastContentIdOfNewIndex: null,
              filesMap: localFileMap,
              contentKeyData: contentKeyData,
              workdirBasePath: workdirBasePath,
              throwIfInterrupted: throwIfSyncCanceled,
              progressCb: syncProgressCb,
              tempDir: tempDir,
              isPathHandled: null,
              // 通过文件在仓库workdir下的相对路径计算出来的fileInfoOid
              getFileInfoForComputeHashTaskContextData: (VersionOid fileInfoOid) async {
                final fileInfoJsonMap = localFileMap.get(fileInfoOid);
                return fileInfoJsonMap == null ? null : FileInfo.fromJson(fileInfoJsonMap);
              },
              createNewNodeForModifiedAndAddedHandler: false,
              modifiedHandler: ({required String relativePathUnixStr, required int sizeInBytes, required File workdirFileEntity, required VersionNode? versionNode, required FileInfo fileInfoWillPush, required VirtualFile virtualFile}) async {
                throw StatusDirtyException();
              },
              addedHandler: ({required String relativePathUnixStr, required int sizeInBytes, required File workdirFileEntity, required VersionNode? versionNode, required VirtualFile virtualFile}) async {
                throw StatusDirtyException();
              },
              deletedHandler: ({required String path, required String pathOidStr}) async {
                throw StatusDirtyException();
              },
            );
          }on StatusDirtyException catch(e) {
            // 若抛这个异常，代表有需要推送的条目，结合上面已经判断有需要拉取的条目，两者结合，就代表需要merge
            // 由于启用了若需要合并则远程覆盖本地的选项，所以，这里执行远程覆盖本地
            await useRemoteFilesMapOverwriteWorkdir(
              contentKeyData: contentKeyData,
              remoteSyncHistory: remoteSyncHistory!,
              throwIfInterrupted: throwIfSyncCanceled,
              progressCb: syncProgressCb,
              tempDir: tempDir,
            );

            throw WorkdirOverwrittenByRemote();
          }
        }
      }




      syncProgressCb?.call(SyncProgressAct.handleChanges, 0, 0, emptyFilePath);
      // 改成diff一下本地和远程的差异，取出本地pfs和远程pfs的最新提交不同的条目
      // （clean 过也没事，本地有远程无的，应该删除workdir对应文件）

      final localSyncCacheDirPath = getSyncCacheDirPath();

      // Set<String>? objectsWhichNoRefsCanDel;
      // 如果有希望删除的远程条目，删
      if(delItemsWhenSync != null && delItemsWhenSync.isNotEmpty) {
        // 不需要待删除的objects本地路径列表了，sync时会检查远程无，本地有的fileinfo，然后把他们的objects data.enc文件路径添加到delete any way list里
        // objectsWhichNoRefsCanDel = await _delFileInfosOrMsgs(
        await _delFileInfosOrMsgs(
          contentKeyData,
          remoteDataType!,
          delItemsWhenSync,
          tempDir,
          throwIfInterrupted: throwIfSyncCanceled,
          syncProgressCb: syncProgressCb,
          // 若需要待删除的objs本地路径列表则设为true，这不需要，原因见上
          returnObjectsCanDeleteList: false
        );
      }

      throwIfSyncCanceled?.call();

      final syncResult = await doSync(
        contentKeyData,
        remoteDataDirPath,
        workdirBasePath,
        this,
        tempDir,
        index,
        localSyncCacheDirPath,
        throwIfSyncCanceled,
        syncProgressCb,
        syncHistoryPair.changes,
        (encData) {
          return true;
          // 若force，强制下载所有file info并进行检查，否则，仅下载比当前版本新的文件
          // if(force) {
          //   return true;
          // }

          // 废弃了，有可能导致出错，比如上传file info成功，但移动到本地目录失败，这时如果跳过条目，本地就会缺文件，
          // 不过暂时保留此字段
          // 这个东西其实可有可无，因为多数时候通过syncHistory来执行增量同步
          // 不过暂时保留，将来如果有数字溢出风险的话，再注释这段代码
          // return encData.syncVersion > lastSyncVersion;
        },
        // deletedFileInfoOrMsgs: objectsWhichNoRefsCanDel,
      );

      throwIfSyncCanceled?.call();


      // await pullAllMsg(
      //   contentKeyData,
      //   localSyncCacheDirPath,
      //   throwIfSyncCanceled
      // );

      // throwIfSyncCanceled?.call();

      // if(syncResult.hasFails()) {
      //   final List<FailedItem> failedItems;
      //   if(syncResult.fails.length > maxRecordItems) {
      //     failedItems = syncResult.fails.sublist(0, maxRecordItems);
      //   }else {
      //     failedItems = syncResult.fails;
      //   }
      //
      //   await createForceSyncFlagFile("has fails item when last sync at ${formatNowTimeWithOffset()}, all failed items are ${syncResult.fails.length}, maximum record $maxRecordItems: $failedItems");
      // }else {
      //   await deleteForceSyncFlagFile();
      // }

      // 同步完成后先更新远程，后更新本地的索引等数据，因为若远程更新成功，
      // 本地更新失败其实问题不大，不会漏文件，但反过来问题就大了，会漏文件或者必须全量同步

      // 即使有fails条目，也要提交会话，因为有可能有推送成功的
      syncProgressCb?.call(SyncProgressAct.committingChanges, 0, 0, emptyFilePath);

      throwIfSyncCanceled?.call();

      // 把最新syncHistory先存到本地syncCache
      final syncHistoryNodeType = delItemsWhenSync == null || delItemsWhenSync.isEmpty ? HistoryNodeType.sync : HistoryNodeType.clean;
      final trueMarkedFinishedFalseRollbacked = await _writeSyncHistoryToSyncCacheAndWillPushDir(
        remoteSyncHistory!,
        syncResult,
        contentKeyData,
        tempDir,
        // 若有删除条目，则是同步节点type为clean（下次sync一定全量同步）；否则为sync（下次sync可能增量同步）
        nodeType: syncHistoryNodeType
      );

      throwIfSyncCanceled?.call();


      // 更新索引到本地syncCache，成功后再放到本地正式目录
      await writeIndex(
        syncResult.newIndex,
        p.join(localSyncCacheDirPath, localIndexFileName)
      );

      throwIfSyncCanceled?.call();

      final newSyncHistoryNodeOid = trueMarkedFinishedFalseRollbacked ? remoteSyncHistory.getLatestVersion()!.oid.value : null;

      // 提交远程修改
      await remote.sessionCommit(
        sessionId,
        contentKeyData,
        tempDir,
        force: forceForCommitChanges,
        afterUploaded: () async {
          remoteFilesCount = remote.filesMap?.size() ?? 0;
          // 创建这个文件，代表本地一切就绪，就差重命名syncCache的文件到正式目录了
          // 若在这抛异常，那么远程数据ok，本地数据syncCache会被丢弃，下次同步，会用本地workdir最新修改加上一版的files map和远程的合并
          await createSyncCacheInfo(mergeMode: MergeMode.mergeRemoteAndWorkdir);
          // throw AppException("Planned cancel to check files under sync cache");
        },
        throwIfTaskCanceled: throwIfSyncCanceled,
        latestPfsFileHandler: latestPfsFileHandler,
        latestMsgMapHandler: latestMsgMapHandler,
        latestFilesMapHandler: latestFilesMapHandler,
        // 若 mark finished，必然至少一个节点，所以可断言 latest version(最新节点) 非null
        newSyncHistoryNodeOid: newSyncHistoryNodeOid,

      );

      // 更新同步历史
      // syncProgressCb?.call(SyncProgressAct.updatingSyncHistory, 0, 0, emptyFilePath);
      // remoteSyncHistory.markLatestNodeToFinished(syncResult);
      // await pushSyncHistory(remoteSyncHistory, contentKeyData, tempDir, true);

      // 更新索引
      // syncProgressCb?.call(SyncProgressAct.updatingIndex, 0, 0, emptyFilePath);
      // await writeIndex(syncResult.newIndex, tempDir);

      syncProgressCb?.call(SyncProgressAct.movingDownloadedFiles, 0, 0, emptyFilePath);
      await commitSyncCacheIfNeed();


      // 打印文本太多，把syncHistory输出到 repoDataDir/debug/syncHistory.enc.json 了，想看去那看
      // App.logger.debug(_TAG, "#sync(): updated remoteSyncHistory: $remoteSyncHistory");
      // App.logger.verbose(_TAG, "#sync(): syncResult: $syncResult");


      lastSyncInfo.updateToSuccess(
        msg: syncResult.brief(historyNodeType: syncHistoryNodeType),
        remoteFilesCount: remoteFilesCount
      );

        // 拷贝files map到filesBak目录
      if(newSyncHistoryNodeOid != null && newSyncHistoryNodeOid.isNotEmpty) {
        // 这个是files.map的备份，若无下次使用时会从远程下载，所以就算这里出错也没什么影响
        try {
          final tempFile = await tempDir.createTempFile();
          await File(getFilesMapFilePath(remoteDataDirPath)).copy(tempFile.absolute.path);
          final targetPath = genLocalFilesBakPath(newSyncHistoryNodeOid);
          await getFileAndMakeSureParentDirExist(targetPath);
          await tempFile.rename(targetPath);
        }catch(e, st) {
          App.logger.warn(_TAG, "sync success but backup files map to local failed: $e\n$st");
        }
      }

      return syncResult;
    }catch(e, st) {
      await remote.sessionCancel(sessionId);

      // 第一个参数是rollbackSuccess与否，
      // 改成先上传文件到 syncCache 后，实际上不需要rollback了，所以默认传true即可
      lastSyncInfo.updateToError(rollbackSuccess: true, msg: e.toString(), remoteFilesCount: remoteFilesCount);

      // await createForceSyncFlagFile("sync err: $e");

      // 这里不需要传错误信息，后面会rethrow，上层直接捕获就行
      // 避免界面出错导致这里抛异常而覆盖原本的同步异常。(比如用户离开页面，此函数无法更新state，这个函数就会报错)
      try {
        syncProgressCb?.call(SyncProgressAct.syncCanceledByErr, 0, 0, emptyFilePath);
      }catch(e, st) {
        App.logger.debug(_TAG, "call sync progress cb err: $e\n$st");
      }


      // 然后抛出异常，上层捕获，提示用户同步出错以及原因
      rethrow;
    }finally {
      await updateLastSyncInfo(lastSyncInfo, tempDir);
      await tempDir.clean();
    }
  }

  Future<SyncHistoryPair> getNextSyncHistory(
    KeyData contentKeyData,
    TempDir tempDir, {
    required bool force
  }) async {
    // 读取本地仓库信息
    RepoInfo repoInfo = await getRepoInfo(contentKeyData);

    // 下载远程仓库info
    final remoteRepoInfoTempFile = await downloadRepoInfo(tempDir);
    final remoteRepoInfo = await RepoInfo.decrypt(contentKeyData, remoteRepoInfoTempFile);

    // 本地和远程仓库id不匹配
    if(repoInfo.id != remoteRepoInfo.id) {
      if(App.devModeOn) {
        App.logger.debug(_TAG, "Repo id not match, local: '${repoInfo.id}', remote: '${remoteRepoInfo.id}', err code: 17868122");
      }

      throw AppException("Repo id not match");
    }

    if(!supportedRepoFormatVersions.contains(repoInfo.repoFormatVersion)) {
      // 由于旧版没检查格式，所以如果文件有大变化，比如把files.map和msg.map和obj.pfs整合到一起了，
      // 那为了确保旧版不会再使用旧格式的files.map，应将其重命名或删除，
      // 这样若用户降级使用旧版，虽没不支持的格式版本的提示，但也会报错而终止同步，不至于损坏远程仓库
      // 如果用户更新app，然后新版更新了仓库版本，之后用户又降级为旧版，就会执行到这里
      throw AppException("Unsupported repo version '${repoInfo.repoFormatVersion}', please update app to latest then try again");
    }

    // userId和当前登录的用户id不匹配（后续压缩包也会检查若id不匹配拒绝压缩和解压缩）
    // App.throwIfUserIdInvalid(repoInfo.userId);

    // 若是force，无视本地历史，不查找新旧历史记录间更新的文件，禁用增量更新，检查全部文件的修改
    // import的时候需设置 force为true，之所以在这判断force而不是在查找changes那里，
    // 是因为有可能会判断如果本地最新节点和远程完全一样，则跳过处理本地和远程文件的逻辑？（好像没有？忘了，
    // 但是问题不大，这里设null：1 pfs比对会触发全量同步，不跳过任何一个条目 2 最后本地syncHistory会更新成和remote syncHistory一样，
    // 符合对force效果的期待）
    final SyncHistory? localSyncHistory = force ? null : await getSyncHistory(contentKeyData: contentKeyData);
    final remoteSyncHistoryFile = await downloadSyncHistory(tempDir);
    final remoteSyncHistory = await SyncHistory.decrypt(contentKeyData, remoteSyncHistoryFile);
    localSyncHistory?.rollbackLocalIfNeeded(remoteSyncHistory);

    // 若force，全量更新，否则增量更新
    final changes = remoteSyncHistory.findUpdatedFilesSince(localSyncHistory);
    // final lastSyncVersion = syncHistory?.syncVersion ?? 0;
    // 不需要更新这个了，远程syncHistory的最新节点的创建时间就是上次同步时间，本地仓库则可通过lastSyncInfo获取
    // remoteRepoInfo.updateTime = TimeData.now();
    // 先更新远程仓库info，再push，避免push中断，文件修改，但更新仓库失败，导致拉取的不知道数据变了
    // remoteRepoInfo.addNode(VersionNode(oid: VersionOid.randomOid(), clientName: client.name));

    // 更新仓库同步版本
    // deprecated，不用这个字段了
    // nextSyncVersion = ++remoteSyncHistory.syncVersion;

    // 上传新的sync history，状态为started，同步完成后更新为finished并追加本次同步pushed文件名单
    final newHistoryNode = SyncHistoryNode(client: client, syncVersion: 0);
    remoteSyncHistory.addNode(newHistoryNode);
    // await pushSyncHistory(remoteSyncHistory, contentKeyData, tempDir, true);
    return SyncHistoryPair(remote: remoteSyncHistory, local: localSyncHistory, changes: changes);
  }



  /// 把syncHistory，写入到本地 cache/syncCache/syncHistory.enc （稍后会移动到本地dataDir/remote 目录）
  /// 和 tempDir/pushCache/willPush/syncHistory.enc （稍后会推送到远程）
  /// 会修改传入的remoteSyncHistory
  /// 若将最新节点标记为完成，则返回true；若回滚了(没上传文件，回滚到上个历史节点)，返回false
  Future<bool> _writeSyncHistoryToSyncCacheAndWillPushDir(
    // 会修改这个，标记最新节点为完成或回滚（若无文件推送）
    SyncHistory remoteSyncHistory,
    final SyncResult syncResult,
    final KeyData contentKeyData,
    final TempDir tempDir, {
    // int? finishState,
    required final int nodeType,
  }) async {
    final localSyncCacheDirPath = getSyncCacheDirPath();
    // x 废弃了，创建拷贝与否都无所谓了，后来直接上传到临时目录，所以不需要回滚了) 创建个拷贝，不然回滚有问题
    // final copiedRemoteSyncHistory = remoteSyncHistory.copy();
    final trueMarkedFinishedFalseRollbacked = await remoteSyncHistory.markLatestNodeToFinished(
      syncResult,
      // finishState: finishState,
      nodeType: nodeType,
      removedHistoryNodeHandler: (node) async {
        // 在历史记录中对应的节点由于超过数量限制被顶替掉时，删除其关联的filesMap
        FilePath? filesBakPath;
        try {
          // 删除远程
          filesBakPath = remote.genRemoteFilesMapBakFilePath(historyNodeOid: node.oid.value);
          await remote.delete(filesBakPath, isDir: false);

          // 删除本地
          await deleteFileIfExists(File(genLocalFilesBakPath(node.oid.value)));
        }catch(e, st) {
          App.logger.debug(_TAG, "remove files map of history node err, usually is ok, you can del remote file by your self, path '$filesBakPath', err: $e\n$st");
        }
      }
    );

    // 把syncHistory.enc拷贝到本地syncCache/syncHistory.enc，然后提交本地syncCache时会被数据拷贝到本地remoteDataDir
    final syncHistoryFileInSyncCache = await getFileAndMakeSureParentDirExist(p.join(localSyncCacheDirPath, syncHistoryFileName));
    final encData = await EncryptedData.compressThenEncrypt(remoteSyncHistory.toJsonByteStream(), contentKeyData);
    await encData.writeToFile(syncHistoryFileInSyncCache);

    // 放本地待推送的远程目录 tempDir/pushCache/willPush
    if(trueMarkedFinishedFalseRollbacked) {
      await syncHistoryFileInSyncCache.copy(p.join((await tempDir.pushCacheWillPushDir()).absolute.path, syncHistoryFileName));
    }


    // 如果是debug模式，输出明文sync history到本地，用来检查同步历史记录的是否正确
    if(App.devModeOn) {
      // dataDir/debug/syncHistory.enc.json
      final syncHistoryFileInDebugDir = await getFileAndMakeSureParentDirExist(p.join(getRepoDebugDirPath(), "$syncHistoryFileName.json"));
      await writeStreamToFile(syncHistoryFileInDebugDir, remoteSyncHistory.toJsonByteStream());
    }

    // 没把最新节点标记为finished，说明回滚了，sync history没更新，不必上传，所以返回null
    return trueMarkedFinishedFalseRollbacked;
  }

  Future<void> commitSyncCacheIfNeed() async {
    await doCommitSyncCacheIfNeed();
    if((await getFileType(getSyncCacheDirPath())) != FileSystemEntityType.notFound) {
      throw AppException("local path 'cache/syncCache' dir still exists after committed, maybe remove syncCache dir then try again, err code: 18496123");
    }
  }

  Future<void> doCommitSyncCacheIfNeed() async {
    final syncCacheDirPath = getSyncCacheDirPath();
    final syncCacheDir = Directory(syncCacheDirPath);

    final syncCacheReadyFile = getSyncCacheReadyFile();
    // 不存在 syncCache/info.json 文件，说明上次任务可能 中断了 或者 成功完成了
    // 中断的情况：如果在创建此文件前中止同步，就不存在这文件了，这时，清了这个目录，重新同步即可
    // 成功完成的情况：如果同步成功完成，syncCache已经被使用并清理了，就不存在这个文件了，这时，继续同步即可
    if(!await syncCacheReadyFile.exists()) {
      App.logger.debug(_TAG, "#commitSyncCacheIfNeed(): File 'syncCache/ready' doesn't exist, maybe last sync aborted or successfully finished, anyway, will delete syncCache of repo");
      await safeDeleteDir(syncCacheDir);
      if(await syncCacheDir.exists()) {
        throw AppException("delete syncCache dir failed, please remove it then try again, path: '$syncCacheDirPath'");
      }

      return;
    }

    // 若存在ready文件，info文件必然存在
    final syncCacheInfoFile = getSyncCacheInfoFile();
    final localSyncCacheInfo = LocalSyncCacheInfo.fromJson(jsonDecode(await syncCacheInfoFile.readAsString()));
    final remoteDataDirPath = getRemoteDataDirPath();

    // 释放空间的时候，本地的这两个目录是可删除的，里面存的都是enc文件，若无，可联网下载
    // final files = Directory(p.join(syncCacheDirPath, remoteFilesDirName));
    // final msgs = Directory(p.join(syncCacheDirPath, remoteMsgDirName));
    await _moveObjectsFromSyncCacheToRemoteDataDir(syncCacheDirPath, remoteDataDirPath);

    // files和msg直接用map了，不需要这个了
    // await _moveFilesFromSyncCache(files, remoteFilesDirName);
    // await _moveFilesFromSyncCache(msgs, remoteMsgDirName);


    final msgMapFileInCache = File(getMsgMapFilePath(syncCacheDirPath));
    if(await msgMapFileInCache.exists()) {
      await msgMapFileInCache.rename(await createParentDirIfNeed(getMsgMapFilePath(remoteDataDirPath)));
    }

    final filesMapFileInCache = File(getFilesMapFilePath(syncCacheDirPath));
    if(await filesMapFileInCache.exists()) {
      await filesMapFileInCache.rename(await createParentDirIfNeed(getFilesMapFilePath(remoteDataDirPath)));
    }



    // 取出索引文件，更新下，然后覆盖到正式目录
    final indexFile = File(p.join(syncCacheDirPath, localIndexFileName));
    // 假如index文件不存在，说明之前已经完成了这段步骤，index应该已经移动到了正式目录
    if(await indexFile.exists()) {
      // 这个值从文件读取，可保证对本地同步缓存的使用逻辑和创建时期望的一致，但有个问题：如果用户先使用 remoteOverwriteWorkdir ，
      // 然后同步出错，然后使用 mergeRemoteAndWorkdir ，那么提交本次同步缓存时，依然会遵循创建缓存时的 remoteOverwriteWorkdir ，
      // 但这样是符合逻辑的，虽然有可能误删文件，但概率很小，所以就这样吧
      final isRemoteOverwriteWorkdir = localSyncCacheInfo.mergeMode == MergeMode.remoteOverwriteWorkdir;
      // 如果更新workdir文件的流程执行到一半中断，会导致index没写入到硬盘，
      // 然后重新执行，那么，已经删除和移动的条目在index中保存的数据将不会被移除和更新（因为之前移动过这些文件了，所以这次syncCache已经没有这些文件），
      // 最终会导致index和workdir不匹配，会怎样？（由于文件的修改时间和大小很难凑巧完全匹配，因此这个一般会触发重新计算hash，应该不会对数据正确性有影响，具体：
      //   1 假设索引有旧文件，实际已删除，那么这种文件不会使用索引，其在检查workdir修改时由于不存在，会被忽略，而在diff files map时，由于不存在，直接赋值Deleted oid，因此索引不影响结果；
      //   2 假设索引有旧文件，实际已更新成新文件，那么文件大小和修改时间会不匹配，使用时会触发重新计算hash，因此不会导致数据有误）
      // 目前，如果index为空，顶多计算workdir文件的hash，然后和remote的对比，
      // 而下面的过程如果中断，
      // 则可能index中包含多余条目（本该deleted）和
      // 错误数据（本该是覆盖后的文件的修改时间和大小），
      // 多余数据在上面说的遍历过程中，不会对数据正确性有影响，顶多影响性能，
      // 错误的数据则会触发hash重新验证，顶多也就有些性能影响，
      // 综上所述，如果下面的代码中断，index数据出错，只会影响性能，不会影响数据正确性。
      // （完全没必要：如果实在不放心，可增加一个flag文件，如果下次检测这个文件存在，则说明index开始同步，
      // 但没完成，这时可执行某些操作，比如清空index，就相当于强制同步了。）


      // 这个index需要更新下面覆盖的文件条目信息，然后再写入到本地文件
      // 注：这里不用担心读取失败，只要最终保证syncCache有效的文件被创建，这个就一定成功写入了
      final indexWhichWillUpdate = await Index.fromJsonByteStream(
          Stream.value(await indexFile.readAsBytes())
      );

      final lastContentIdOfIndex = indexWhichWillUpdate.contentId;

      // 覆盖和删除workdir的文件
      final workdirPath = getWorkdirPath();

      // 要删除的workdir的文件
      final workdirDeleteFile = File(p.join(syncCacheDirPath, workdirWillDeleteFileName));
      if(await workdirDeleteFile.exists()) {
        final workdirDeleteItems = await WorkdirFiles.fromFile(workdirDeleteFile);
        for(final relativePathUnixStr in workdirDeleteItems.items.keys) {
          // 这个key一律用的unix字符串，所以这里也用fromUnixString()处理
          final relativePath = FilePath.fromUnixString(relativePathUnixStr);
          final relativePathStr = relativePath.toString();
          final workdirFileFullPath = p.join(workdirPath, relativePathStr);
          final fileInWorkdirFileType = await getFileType(workdirFileFullPath);
          if(fileInWorkdirFileType != FileSystemEntityType.notFound && fileInWorkdirFileType != FileSystemEntityType.file) {
            // 这个路径在远程是个文件，但在本地却是个目录，所以覆盖会失败，避免用户摸不着头脑，特地抛个异常告诉用户怎么处理
            throw InvalidPathTypeException("commit local sync cache err: when delete file, expect 'file' but got: '$fileInWorkdirFileType', path is '$workdirFileFullPath', please rename or move or delete the path, then re-sync");
          }

          // 如果workdir对应的路径不是文件，而是目录，这里会报错，解决方案就是手动去把对应目录删除（小概率发生）
          // 或者把这改用 await Directory(path).delete(recursive: true)，但是，如果改成这样，有可能误删整个目录下所有文件，若有重要文件，无法恢复（File.delete()若传recursive也可删除目录，关键在于是否递归，而不是Directory还是File对象）
          final fileInWorkdir = File(workdirFileFullPath);
          // exists和recursive true，以及文件实体为File，3者都是必须的，见下面注释
          // 若路径不是File，则exists会返回假，从而避免删除目录
          if(await fileInWorkdir.exists()) {  // 由于下面使用了递归删除，若不判断exists，会误删目录，
            await fileInWorkdir.delete(recursive: true); // 若不传recursive true，可能会删除文件失败，errno=5，在windows，其他系统未测试
          }


          // 若删除文件后其所在目录为空，删，不然删除文件后会留下空目录
          final parent = fileInWorkdir.parent;
          try {
            // recursive为假，仅会删除非空目录
            await parent.delete(recursive: false);
          }catch(_) {
            // 这个删除出错也无所谓，顶多留个空目录
          }

          indexWhichWillUpdate.remove(relativePath, lastContentIdOfIndex);
        }

        await workdirDeleteFile.delete();
      }

      // 要覆盖的文件
      // 拷贝文件的时候 index对应条目的信息，要刷新下
      final workdirOverwriteFile = File(p.join(syncCacheDirPath, workdirWillOverwriteFileName));
      if(await workdirOverwriteFile.exists()) {
        final workdirOverwriteItems = await WorkdirFiles.fromFile(workdirOverwriteFile);
        for(final relativePathUnixStr in workdirOverwriteItems.items.keys) {
          // 这个key一律用的unix字符串
          final relativePath = FilePath.fromUnixString(relativePathUnixStr);
          final relativePathStr = relativePath.toString();
          // 不检测了，直接覆盖，正常来说如果同步中断，应该先重新同步，再编辑，
          // 要是用户没同步，直接编辑，被覆盖了活该
          // 路径：syncCache/workdir/文件在正式目录下的相对路径
          final fileInSyncCache = File(p.join(syncCacheDirPath, workdirDirName, relativePathStr));
          // 正常来说都该是存在，不过若本函数中断，例如停电，下次恢复后对应文件可能已经被移动到正式目录，
          // 因此在这就不存在了，所以还是需要判断下
          if(await fileInSyncCache.exists()) {
            // 在正式workdir的文件
            final workdirFileFullPath = p.join(workdirPath, relativePathStr);
            final fileInWorkdir = await getFileAndMakeSureParentDirExist(workdirFileFullPath);
            final fileInWorkdirFileType = await getFileType(workdirFileFullPath);
            // 若是覆盖模式，先删除，后重命名
            if(isRemoteOverwriteWorkdir) {  // 若是远程覆盖本地，就算对应路径是文件夹也一并删除，若不删除，要么需要用户手动介入删除，要么下次同步就会文件夹内容覆盖远程，破坏remote 覆盖本地的约定
              if(fileInWorkdirFileType != FileSystemEntityType.notFound) {  // 不用file的exists判断是为了即使路径存在且是目录也可返回真并删除目录，做notFound判断是因为若不存在对应路径，删除时会报错
                // recursive为true，即使是目录也可删除
                await fileInWorkdir.delete(recursive: true); // 若不传recursive true，可能会删除文件失败，errno=5，在windows，其他系统未测试
              }
            }else {  // 非远程覆盖本地模式（即远程和本地workdir合并 模式），则判断，如果对应路径不是文件并且存在（比如是目录），则抛异常，提示用户手动处理
              if(fileInWorkdirFileType != FileSystemEntityType.notFound && fileInWorkdirFileType != FileSystemEntityType.file) {
                // 这个路径在远程是个文件，但在本地却是个目录，所以覆盖会失败，避免用户摸不着头脑，特地抛个异常告诉用户怎么处理
                throw InvalidPathTypeException("commit local sync cache err: when overwrite file, expect 'file' but got: '$fileInWorkdirFileType', path is '$workdirFileFullPath', please rename or move or delete the path, then re-sync");
              }
            }

            await fileInSyncCache.rename(fileInWorkdir.absolute.path);
            //如果在这中断，索引对应条目元数据会和workdir最新文件的不匹配，下次同步时会触发hash校验（不过问题不大，影响性能，不影响数据正确性）
            // 更新索引，最后一个参数是文件oid，这个oid先不算了，意义不大，目前match的时候不比较oid
            await indexWhichWillUpdate.addFile(relativePath, fileInWorkdir, '', lastContentIdOfIndex);
          }
        }

        await workdirOverwriteFile.delete();
      }

      // 更新索引，先拷贝到临时目录，再rename到正式目录
      await writeIndex(indexWhichWillUpdate, getIndexPath());

    }

    // 无条件删除的文件，例如本地缓存的objects和fileinfo的data.enc文件
    final deleteAnyWayFiles = File(p.join(syncCacheDirPath, deleteAnywayFilesFileName));
    if(await deleteAnyWayFiles.exists()) {
      final JsonStrSet filePaths = await JsonStrSet.fromJsonByteStream(deleteAnyWayFiles.openRead());
      await for(final fPath in filePaths.restoredRepoBasedPathToAbs(this)) {
        final file = File(fPath);
        await safeDeleteFile(file);

        // 删除空的父目录，非空则不会删除
        try {
          file.parent.delete(recursive: false);
        }catch(_) {

        }
      }
    }

    // 移动pfs文件到正式目录
    for(final pfsType in RemoteDataType.pfsTypes) {
      await _movePfsFileFromSyncCache(pfsType);
    }

    // 覆盖同步历史
    final syncHistoryFile = File(p.join(syncCacheDirPath, syncHistoryFileName));
    if(await syncHistoryFile.exists()) {
      await syncHistoryFile.rename(getSyncHistoryPath());
    }


    // 最后删除cache/syncCache目录
    await syncCacheDir.delete(recursive: true);

    // if(await getFileType(syncCacheReadyFile.absolute.path) != FileSystemEntityType.notFound) {
    //   throw AppException("delete syncCache info failed, err code: 19215902");
    // }

    // 改成由调用本函数的函数在执行完本函数后自行检查了，若在这检查，万一上面return，会绕过此检查，可能导致在synCache存在时执行后续的同步等操作
    // 这里不加括号也可以，会先确保 await func() 执行完再执行 != 判断
    // if((await getFileType(syncCacheDir.absolute.path)) != FileSystemEntityType.notFound) {
    //   throw AppException("delete syncCache failed, err code: 17322010");
    // }
  }

  Future<void> _movePfsFileFromSyncCache(RemoteDataType pfsType) async {
    final pfsInSyncCacheFile = File(
      p.join(
        getPfsDirPathByType(pfsType, getSyncCacheDirPath()),
        Remote.pfsFileName
      )
    );

    if(await pfsInSyncCacheFile.exists()) {
      final remoteDataDirPath = getRemoteDataDirPath();
      final pfsFile = await getFileAndMakeSureParentDirExist(
        p.join(
          getPfsDirPathByType(pfsType, remoteDataDirPath),
          Remote.pfsFileName
        )
      );

      await pfsInSyncCacheFile.rename(pfsFile.absolute.path);
    }

  }

  // syncCache下的objects目录是扁平的 objOid/data.enc
  // remoteDataDir下的objects目录是按hash分文件夹的 objOid[0,2)/objOid[2,4)/objOid[4,len)/data.enc
  Future<void> _moveObjectsFromSyncCacheToRemoteDataDir(String syncCacheDirPath, String remoteDataDirPath) async {
    final targetDirName = remoteObjectsDirName;
    final syncCacheObjectsDir = Directory(p.join(syncCacheDirPath, targetDirName));
    final remoteDataObjectsDir = Directory(p.join(remoteDataDirPath, targetDirName));

    // 注释的是本地目录过去也使用扁平化obj oid目录结构的代码，由于和syncCache目录结构一样，
    // 因此直接重命名即可，不过后来考虑到本地可能会有过万缓存的obj文件，一个目录下条目太多可能导致列出目录时卡顿，
    // 所以本地改成按hash分文件夹了（抄的git的方案）
    // if((!await targetDir.exists()) && await dir.exists()) {
      // 避免中间目录不存在，先创建下
      // await targetDir.create(recursive: true);
      // 避免rename失败，先删除下
      // await targetDir.delete();
      // await dir.rename(targetDir.absolute.path);
      // return;
    // }

    // if(await targetDir.exists() && await isEmptyDir(targetDir) && await dir.exists()) {
    //   await targetDir.delete();
    //   await dir.rename(targetDir.absolute.path);
    //   return;
    // }

    // 目的不存在，创建
    if(!await remoteDataObjectsDir.exists()) {
      await remoteDataObjectsDir.create(recursive: true);
    }

    // 源不存在，直接返回
    if(!await syncCacheObjectsDir.exists()) {
      return;
    }

    await for(final i in syncCacheObjectsDir.list(followLinks: false)) {
      // 源存在且非空，抛异常，因为这个函数弃用了
      throw AppException("save object to sync cache is deprecated");
      
      if(i is Directory) {
        // syncCache/objects/oid/data.enc
        final dataFile = File(p.join(i.absolute.path, remoteDataFileName));
        if(await dataFile.exists()) {
          // targetDir: 例如：remote/objects
          // p.basename(i.path)，是hash，例如：abc123
          // targetFile整体路径示例：本地dataDir/remote/objects/objOid[0,2)/objOid[2,4)/objOid[4,len)/data.enc
          final targetFile = await getFileAndMakeSureParentDirExist(getLocalRemoteObjectPathByOidStr(remoteDataDirPath, p.basename(i.path)));
          await dataFile.rename(targetFile.absolute.path);
        }
      }
    }

    await syncCacheObjectsDir.delete(recursive: true);
  }

  File getSyncCacheInfoFile() {
    return File(p.join(getSyncCacheDirPath(), infoJsonFileName));
  }

  File getSyncCacheReadyFile() {
    return File(p.join(getSyncCacheDirPath(), readyFileName));
  }

  Future<void> createSyncCacheInfo({required int mergeMode}) async {
    // recursive为真，则会创建不存在的父目录
    final infoFile = await getSyncCacheInfoFile().create(recursive: true);
    await infoFile.writeAsString(jsonEncode(LocalSyncCacheInfo(mergeMode: mergeMode).toJson()), flush: true);

    // mark sync cache ready for commit
    await getSyncCacheReadyFile().create(recursive: true);
  }

  Future<RepoInfo> getRepoInfo(KeyData contentKeyData, {File? file}) async {
    final repoInfo = await RepoInfo.decrypt(contentKeyData, file ?? File(getRepoInfoPath()));
    return repoInfo;
  }

  //
  // Future<MergeResult> pull(
  //   KeyData contentKeyData,
  //   String remoteDataDirPath,
  //   String workdirFullPath,
  //   bool Function() taskCanceled,
  //   Index index,
  // ) async {
  //   final tempDir = await createTempDir("pull");
  //
  //   try {
  //
  //     // TODO 小优化点：这里可以优化，在下载时转换，不用再循环一次，不过文件不多，影响不大
  //     await remote.fetchAllFileInfos(remoteDataDirPath, tempDir, moveToRemoteDataDirAfterDownload: false);
  //
  //     // include deleted items
  //     final remoteFiles = <FilePath, FileInfo>{};
  //     // 把远程的file info 列出来
  //     await RemoteStorageUtil.forEachFiles(
  //       contentKeyData,
  //       tempDir.filesDir(),
  //         (it) {
  //         remoteFiles[it.relativePath] = it;
  //       }
  //     );
  //
  //     // 把本地的file info列出来
  //     final localFiles = <FilePath, FileInfo>{};
  //     final localRemoteDataDir = getAndMakeSureDirExists(p.join(remoteDataDirPath, Repo.remoteFilesDirName));
  //     await RemoteStorageUtil.forEachFiles(
  //       contentKeyData,
  //       localRemoteDataDir,
  //       (it) {
  //         localFiles[it.relativePath] = it;
  //       }
  //     );
  //
  //     final mergeResult = await merge(
  //       contentKeyData,
  //       remoteDataDirPath,
  //       workdirFullPath,
  //       localFiles,
  //       remoteFiles,
  //       remote,
  //       tempDir,
  //       index
  //     );
  //
  //     return mergeResult;
  //   }finally {
  //     await tempDir.clean();
  //
  //   }
  // }
  //
  // Future<void> push(
  //   KeyData contentKeyData,
  //   String remoteDataDirPath,
  //   String workdirFullPath,
  //   MergeResult mergeResult,
  //   bool Function() taskCanceled,
  //   Index index,
  // ) async {
  //   final tempDir = await createTempDir("push");
  //   try {
  //
  //     //本地工作目录所有文件
  //     final ignores = defaultIgnorePathList;
  //     final workdirItems = <FilePath, FileItem>{};
  //     await forEachFiles(
  //       workdirFullPath,
  //       (item) {
  //         if(ignores.contains(genRelativePath(workdirFullPath, item.absolute.path))) {
  //           //跳过，不扫描
  //           return false;
  //         }
  //
  //         final relativePath = FilePath.fromString(genRelativePath(workdirFullPath, item.absolute.path), isRelative: true);
  //         if (item is File) {
  //           final indexItem = index.items[relativePath];
  //           if(indexItem != null && indexItem.matchFile(item)) {
  //             // 跟索引一样，没改过，不需要推送，忽略
  //             // 由于之前pull更新文件后会更新索引，
  //             //   所以，如果进到这里，
  //             //   要么文件一直和索引匹配，
  //             //   要么刚被pull更新过，
  //             //   如果是刚更新过，不需要push，因此，不用添加到workdirItems
  //             return true;
  //           }
  //
  //           // 更新索引
  //           index.items[relativePath.toMapKey()] = IndexItem.fromFile(item);
  //
  //           // 文件不在索引 或者 和索引不匹配，可能需要推送
  //           workdirItems[relativePath] = FileItem(
  //             relativePath: relativePath,
  //             fullPath: FilePath.fromString(item.absolute.path),
  //           );
  //         }else {
  //           // 若是目录，忽略
  //           index.items.remove(relativePath);
  //         }
  //
  //         return true;
  //       }
  //     );
  //
  //     // 把远程的file info 列出来
  //     final remoteFiles = mergeResult.untouchedRemoteFileInfosForPush;
  //
  //     await updateFileInfosAndPush(contentKeyData, remoteDataDirPath, tempDir, workdirItems, remoteFiles, remote, mergeResult, taskCanceled, path, index);
  //   }finally {
  //     await tempDir.clean();
  //   }
  // }

  Future<void> pullAllMsg(
    KeyData contentKeyData,
    String syncCacheDirPath,
    ThrowIfInterrupted? throwIfSyncCanceled,
  ) async {
    final tempDir = await createTempDir("pullAllMsg");

    try {
      // 先删除正式目录的本地msg目录
      final msgDir = Directory(getRemoteMsgDirPath());
      if(await msgDir.exists()) {
        await msgDir.delete(recursive: true);
      }

      // 下载所有msg到syncCache
      // await remote.fetchAllMsg(
      //   syncCacheDirPath,
      //   tempDir,
      //   moveToRemoteDataDirAfterDownload: true
      // );

    }finally {
      await tempDir.clean();
    }
  }

  // Future<void> pullAllMsg_deprecated(
  //   KeyData contentKeyData,
  //   String remoteDataDirPath,
  //   ThrowIfInterrupted? throwIfSyncCanceled,
  // ) async {
  //   final tempDir = await createTempDir("pullAllMsg");
  //
  //   try {
  //     final remoteAllMsg = await remote.fetchAllMsg(
  //       remoteDataDirPath,
  //       tempDir,
  //       moveToRemoteDataDirAfterDownload: false
  //     );
  //
  //     final localMsgDir = getAndMakeSureDirExists(getMsgPath(remoteDataDirPath));
  //
  //     // 由于后来改成存到syncCache里了，而那个目录在使用时应该是空的，所以这个循环可能不会触发了
  //     await for(final fse in localMsgDir.list(followLinks: false)) {
  //       throwIfSyncCanceled?.call();
  //
  //       // msg dir name is hash (oid of msg)
  //       final msgDirName = p.basename(fse.absolute.path);
  //       var foundIdx = -1;
  //       for(var i = 0; i < remoteAllMsg.length; i++) {
  //         // 从远程的msg/oid/data.enc路径中取出oid，然后和msgDirName（也是oid）比较
  //         if(p.basename(p.dirname(remoteAllMsg[i].path)) == msgDirName) {
  //           foundIdx = i;
  //           break;
  //         }
  //       }
  //
  //       if(foundIdx == -1) {
  //         // 远程没有，本地有，删除本地
  //         safeDeleteDir(Directory(fse.absolute.path));
  //       }else {
  //         //远程有，本地有，从远程列表移除，剩下的就是只有远程有的了
  //         final fileType = await getFileType(Repo.getMsgPathByOidStr(remoteDataDirPath, msgDirName));
  //         // 若文件已经存在，从列表移除，否则维持在列表，之后的循环会复制文件
  //         if(fileType != FileSystemEntityType.notFound) {
  //           remoteAllMsg.removeAt(foundIdx);
  //         }
  //       }
  //     }
  //
  //     // 上面循环结束后剩下的就是只有远程有本地没有的了
  //
  //     // 把只有远程有的拷贝到本地
  //     for(final f in remoteAllMsg) {
  //       throwIfSyncCanceled?.call();
  //
  //       final file = getFileAndMakeSureParentDirExist(
  //         getMsgPathByOidStr(
  //           remoteDataDirPath,
  //           // 从路径取出oid
  //           // 假设 f.path是 msg/oid/data.enc
  //           // 则p.dirname() 为msg/oid，然后取basename()，
  //           // 就是oid了
  //           p.basename(p.dirname(f.path))
  //         )
  //       );
  //
  //       safeRename(f, file.absolute.path);
  //     }
  //
  //   }finally {
  //     await tempDir.clean();
  //   }
  // }

  // static String genMsgPath(String remoteDataDirPath) {
  //   return p.join(remoteDataDirPath, remoteMsgDirName);
  // }


  String getRepoInfoPath() {
    return p.join(path, dataDirName, remoteDirName, repoInfoFileName);
  }

  String getSyncHistoryPath() {
    return p.join(path, dataDirName, remoteDirName, syncHistoryFileName);
  }


  // 返回加密后的文件，如果移动到本地目录，则返回本地文件，否则返回远程文件
  Future<File> pushRepoInfo(RepoInfo repoInfo, KeyData contentKeyData, TempDir tempDir, bool moveToLocalRemote) async {
    // 备份旧的
    final remoteRepoInfoPath = remote.getRemoteRepoInfoPath();
    await remote.renameSafe(
      remoteRepoInfoPath,
      remoteRepoInfoPath.copyThenRename(remoteRepoInfoPath.name()+Repo.backupFileSuffix),
      isDir: false
    );


    // 上传新的
    // final syncVersion = 0;
    final encryptedData = await EncryptedData.compressThenEncrypt(repoInfo.toJsonByteStream(), contentKeyData);
    final tempFile = await tempDir.createTempFile();

    await writeStreamToFile(tempFile, encryptedData.toByteStream());

    await remote.uploadFile(remoteRepoInfoPath, tempFile);

    if(moveToLocalRemote) {
      final localRemoteRepoInfo = File(getRepoInfoPath());
      await tempFile.rename(localRemoteRepoInfo.absolute.path);
      return localRemoteRepoInfo;
    }

    if(App.devModeOn) {
      final file = await getFileAndMakeSureParentDirExist(p.join(getRepoDebugDirPath(), "$repoInfoFileName.json"));
      await writeStreamToFile(file, repoInfo.toJsonByteStream());
    }
    
    return tempFile;
  }

  Future<File> pushSyncHistory(
    SyncHistory syncHistory,
    KeyData contentKeyData,
    TempDir tempDir,
    bool moveToLocalRemote
  ) async {
    final encryptedData = await EncryptedData.compressThenEncrypt(syncHistory.toJsonByteStream(), contentKeyData);
    final tempFile = await tempDir.createTempFile();

    await writeStreamToFile(tempFile, encryptedData.toByteStream());

    await remote.uploadFile(remote.getRemoteSyncHistoryPath(), tempFile);

    if(moveToLocalRemote) {
      final file = await getFileAndMakeSureParentDirExist(getSyncHistoryPath());
      await tempFile.rename(file.absolute.path);
      return file;
    }

    return tempFile;
  }

  // 返回下载后的文件路径
  Future<File> downloadRepoInfo(TempDir tempDir, {bool moveToRemoteDataDir = false}) async {
    return await downloadFile(remote.getRemoteRepoInfoPath(), getRepoInfoPath(), tempDir, moveToRemoteDataDir: moveToRemoteDataDir);
  }

  Future<File> downloadSyncHistory(TempDir tempDir, {bool moveToRemoteDataDir = false}) async {
    return await downloadFile(remote.getRemoteSyncHistoryPath(), getSyncHistoryPath(), tempDir, moveToRemoteDataDir: moveToRemoteDataDir);
  }

  Future<File> downloadFile(FilePath remotePath, String localPath, TempDir tempDir, {bool moveToRemoteDataDir = false}) async {
    final tempFile = await tempDir.createTempFile();
    await remote.downloadToFile(remotePath, tempFile, tempDir);

    if(moveToRemoteDataDir) {
      final file = await getFileAndMakeSureParentDirExist(localPath);
      await safeRename(tempFile, file.absolute.path);
      return file;
    }

    return tempFile;
  }



  // 删除本地有，远程无的file infos
  // Future<void> cleanRemotedNonexistsFileInfos({
  //   required ThrowIfInterrupted? throwIfTaskCanceled,
  // }) async {
  //   final tempDir = await createTempDir("cleanRemotedNonexistsFileInfos");
  //
  //   try {
  //     List<RemoteFile>? allRemoteFiles = await remote.listFilesByType(RemoteDataType.files);
  //     final allRemoteFilesSet = <String>{};
  //     for(final r in allRemoteFiles) {
  //       allRemoteFilesSet.add(r.name);
  //     }
  //
  //     // maybe help free mem?
  //     allRemoteFiles = null;
  //
  //     await forEachFiles(
  //       getRemoteFilesDirPath(),
  //
  //       (fileEntity) async {
  //         throwIfTaskCanceled?.call();
  //
  //         if(fileEntity is Directory) {
  //           if(!allRemoteFilesSet.contains(p.basename(fileEntity.path))) {
  //             await safeDeleteDir(fileEntity);
  //           }
  //         }
  //         return true;
  //       }
  //     );
  //   }finally {
  //     await tempDir.clean();
  //   }
  // }






  // sync时会更新索引，不需要这个了
  // Future<void> updateIndex() {
  //   扫一遍根目录所有文件和目录，
  //   然后有两种方案：
  //   1. 所有子目录，把它们的修改时间记上
  //   2. 所有文件和目录，把它们的修改时间记上
  //   采用方案2吧，记的东西不多，应该不会太大，推送时使用索引，
  //   如果一个文件路径在workdir存在且修改时间和记录的一致，
  //   则直接从列表移除此元素，然后返回，不用push
  // }

  String getIndexPath() {
    return p.join(path, dataDirName, localIndexFileName);
  }

  Future<Index> getIndex() async {
    //从索引文件读取索引内容，若无文件，返回空索引对象即可
    final indexFile = File(getIndexPath());
    if(!await indexFile.exists()) {
      return Index();
    }

    try {
      // 写入index时若中断，可能损坏，导致读不出，这时返回空索引即可，
      // 只对性能有影响（因为会触发计算hash），对数据正确性无影响
      return await Index.fromJsonByteStream(indexFile.openRead());
    }catch(e) {
      return Index();
    }
  }

  Future<void> writeIndex(Index index, String targetPath) async {
    final tempDir = await createTempDir("writeIndex");
    try {
      //从索引文件读取索引内容，若无文件，返回空索引对象即可
      final tempFile = await tempDir.createTempFile();
      final bytes = index.toJsonByteStream();
      await writeStreamToFile(tempFile, bytes);
      await safeRename(tempFile, targetPath);
    }finally {
      await tempDir.clean();
    }
  }

  String getLastSyncInfoPath() {
    return p.join(path, dataDirName, localLastSyncInfoFileName);
  }

  Future<void> updateLastSyncInfo(SyncInfo syncInfo, TempDir tempDir) async {
    syncInfo.time = TimeData.now();

    final f = await tempDir.createTempFile();
    await writeStreamToFile(f, syncInfo.toJsonByteStream());
    await safeRename(f, getLastSyncInfoPath());
  }

  Future<SyncInfo> getLastSyncInfo() async {
    final f = File(getLastSyncInfoPath());
    return await SyncInfo.fromJsonByteStream(f.openRead());
  }

  Future<void> initLastSyncInfo(TempDir tempDir) async {
    await updateLastSyncInfo(SyncInfo(), tempDir);
  }

  Future<SyncHistory?> getSyncHistory({KeyData? contentKeyData, File? file}) async {
    try {
      return await SyncHistory.decrypt(contentKeyData ?? await getContentKey(), file ?? File(getSyncHistoryPath()));
    }catch(e) {
      return null;
    }
  }

  String getWorkdirPath() {
    return path;
  }


  Future<SyncResult> importSync(
    String masterPass, {
    bool moveToRemoteDataDir = true,
    ThrowIfInterrupted? throwIfCanceled,
    SyncProgressCb? syncProgressCb,
  }) async {
    final tempDir = await createTempDir("importSync");

    try {
      await remote.doInit(tempDir, packMaxLen: await getEffectPackMaxLen());
      throwIfCanceled?.call();
      await _throwIfRepoInited();

      throwIfCanceled?.call();

      final emptyFilePath = "";

      syncProgressCb?.call(SyncProgressAct.downloadKeys, 0, 0, emptyFilePath);

      await downloadKeys();
      final masterKeyVerifyErr = await verifyMasterKey(masterPass, moveToDataDirIfVerified: moveToRemoteDataDir);
      if(masterKeyVerifyErr != null) {
        throw masterKeyVerifyErr;
      }
      throwIfCanceled?.call();


      syncProgressCb?.call(SyncProgressAct.downloadSyncHistory, 0, 0, emptyFilePath);

      // 不下载仓库info的话，后面同步会报错，找不到仓库info文件
      await downloadSyncHistory(tempDir, moveToRemoteDataDir: moveToRemoteDataDir);
      throwIfCanceled?.call();


      syncProgressCb?.call(SyncProgressAct.downloadRepoInfo, 0, 0, emptyFilePath);

      await downloadRepoInfo(tempDir, moveToRemoteDataDir: moveToRemoteDataDir);

      throwIfCanceled?.call();

      await createDoNotTouchFile();

      throwIfCanceled?.call();

      final contentKeyData = await getContentKey();
      syncProgressCb?.call(SyncProgressAct.initFilesMap, 0, 0, emptyFilePath);
      await initFilesMap(contentKeyData, tempDir, upload: false);  // import仓库时，创建空的移动到本地目录就行了，init仓库时才需要上传
      syncProgressCb?.call(SyncProgressAct.initMsgMap, 0, 0, emptyFilePath);
      await initMsgMap(contentKeyData, tempDir, upload: false);
      syncProgressCb?.call(SyncProgressAct.initObjPfs, 0, 0, emptyFilePath);
      await initObjPfs(contentKeyData, tempDir, upload: false);

      syncProgressCb?.call(SyncProgressAct.initLastSyncInfo, 0, 0, emptyFilePath);
      await initLastSyncInfo(tempDir);

      syncProgressCb?.call(SyncProgressAct.syncFiles, 0, 0, emptyFilePath);

    }finally {
      await tempDir.clean();
    }

    // 执行同步
    return await syncWithLock(
      force: true,
      throwIfSyncCanceled: throwIfCanceled,
      syncProgressCb: syncProgressCb,
      needInitRemote: false,
    );

  }

  Future<void> _throwIfRepoInited({bool checkLocal = true, bool checkRemote = true}) async {
    final tempDir = await createTempDir("_throwIfRepoInited");
    try {
      // initSync和importSync最后一步都是下载或推送repoInfoPath，所以，如果这个文件存在，则当作仓库已经初始化
      if(checkLocal) {
        if(await File(getRepoInfoPath()).exists()) {
          throw AppException("#_throwIfRepoInited err: local repo already inited, err code: 11198075");
        }
      }

      if(checkRemote) {
        final repoInfoFile = await tempDir.createTempFile();
        try {
          final remotePath = remote.getRemoteRepoInfoPath();
          if(await remote.exists(remotePath)) {
            throw AppException("#_throwIfRepoInited err: remote repo already inited, err code: 13879371");
          }

          // 尝试下载，若成功，则抛异常
          // 下载成功则代表远程仓库已经存在，抛异常
          await remote.downloadToFile(remotePath, repoInfoFile, tempDir);
          if(await repoInfoFile.exists() && (await repoInfoFile.length()) > 0) {
            throw AppException("#_throwIfRepoInited err: remote repo already inited, err code: 19475375");
          }
        }catch(_) {
          // 下载失败代表文件不存在或怎样，不用抛异常，不过，如果偶然网络抽风，就可能误判了，只能说一般不会
        }
      }

    }finally {
      await tempDir.clean();
    }
  }

  Future<SyncResult> initSync(
    String masterPass, {
    bool moveToDataDir = true,
    ThrowIfInterrupted? throwIfCanceled,
    SyncProgressCb? syncProgressCb,
  }) async {
    final tempDir = await createTempDir("initSync");
    try {
      await remote.doInit(tempDir, packMaxLen: await getEffectPackMaxLen());

      throwIfCanceled?.call();

      await _throwIfRepoInited();
      throwIfCanceled?.call();

      // 必须先init key

      final emptyFilePath = "";

      syncProgressCb?.call(SyncProgressAct.initKey, 0, 0, emptyFilePath);

      await initKey(masterPass, moveToDataDir: moveToDataDir);
      throwIfCanceled?.call();



      syncProgressCb?.call(SyncProgressAct.initSyncHistory, 0, 0, emptyFilePath);

      await initSyncHistory(tempDir);

      throwIfCanceled?.call();

      syncProgressCb?.call(SyncProgressAct.initRepoInfo, 0, 0, emptyFilePath);

      // 最后下载repoInfo，到时候检测，只要有repoinfo就当inited了
      await initRepoInfo(tempDir);

      throwIfCanceled?.call();

      await createDoNotTouchFile();

      throwIfCanceled?.call();

      final contentKeyData = await getContentKey();
      syncProgressCb?.call(SyncProgressAct.initFilesMap, 0, 0, emptyFilePath);
      await initFilesMap(contentKeyData, tempDir, upload: true);
      syncProgressCb?.call(SyncProgressAct.initMsgMap, 0, 0, emptyFilePath);
      await initMsgMap(contentKeyData, tempDir, upload: true);
      syncProgressCb?.call(SyncProgressAct.initObjPfs, 0, 0, emptyFilePath);
      await initObjPfs(contentKeyData, tempDir, upload: true);

      syncProgressCb?.call(SyncProgressAct.initLastSyncInfo, 0, 0, emptyFilePath);
      await initLastSyncInfo(tempDir);

      syncProgressCb?.call(SyncProgressAct.syncFiles, 0, 0, emptyFilePath);
    }finally {
      await tempDir.clean();
    }


    // 执行同步
    return await syncWithLock(
      throwIfSyncCanceled: throwIfCanceled,
      syncProgressCb: syncProgressCb,
      // 上面init过了所以这就不需要了
      needInitRemote: false,
    );
  }

  Future<void> initFilesMap(KeyData contentKeyData, TempDir tempDir, {required bool upload}) async {
    final emptyObj = DataMap.createFilesMap();
    final encData = await EncryptedData.compressThenEncrypt(emptyObj.toJsonByteStream(), contentKeyData);
    await uploadEncDataToRemote(
      encData,
      remote.remoteFilesMapPath(),
      tempDir,
      upload: upload,
      moveToThisPathAfterUploaded: getFilesMapFilePath(getRemoteDataDirPath())
    );
  }

  Future<void> initMsgMap(KeyData contentKeyData, TempDir tempDir, {required bool upload}) async {
    final emptyObj = DataMap.createMsgMap();
    final encData = await EncryptedData.compressThenEncrypt(emptyObj.toJsonByteStream(), contentKeyData);
    await uploadEncDataToRemote(
      encData,
      remote.remoteMsgMapPath(),
      tempDir,
      upload: upload,
      moveToThisPathAfterUploaded: getMsgMapFilePath(getRemoteDataDirPath())
    );
  }

  Future<void> initObjPfs(KeyData contentKeyData, TempDir tempDir, {required bool upload}) async {
    final emptyObj = ObjPackFileStorage();
    final encData = await EncryptedData.compressThenEncrypt(emptyObj.toJsonByteStream(), contentKeyData);
    await uploadEncDataToRemote(
      encData,
      remote.remoteObjectsPfsPath(),
      tempDir,
      upload: upload,
      moveToThisPathAfterUploaded: getObjectPfsFilePath(getRemoteDataDirPath())
    );
  }

  Future<void> uploadEncDataToRemote(
    final EncryptedData encData,
    final FilePath remotePath,
    TempDir tempDir, {
    final bool upload = true,  // 若false，则不上传，只移动到本地目录时可传false，同时传入有效的本地路径
    final String? moveToThisPathAfterUploaded, // 若非null，上传完成后，移动到本地此路径
  }) async {
    final tempFile = await tempDir.createTempFile();
    await encData.writeToFile(tempFile);

    if(upload) {
      await remote.uploadFile(remotePath, tempFile);
    }

    if(moveToThisPathAfterUploaded != null) {
      await getFileAndMakeSureParentDirExist(moveToThisPathAfterUploaded);
      await tempFile.rename(moveToThisPathAfterUploaded);
    }
  }

  // 创建一个文件，警告用户别碰这个目录
  Future<void> createDoNotTouchFile() async {
    final file = File(p.join(getDataDirPath(), "DoNotTouchThisDir.txt"));
    if(await file.exists()) {
      return;
    }

    final str = "This is app data dir, do not touch it!";
    await writeStrToFile(file, str);
  }



  Future<void> _latestMapHandler(String targetPath, DataMap? map, KeyData contentKeyData, TempDir tempDir) async {
    final fileName = p.basename(targetPath);
    if(map == null) {
      throw AppException("data of '$fileName' is null, err code: 15022803");
    }

    final encFile = await tempDir.createTempFile();
    final encData = await EncryptedData.compressThenEncrypt(map.toJsonByteStream(), contentKeyData);
    await encData.writeToFile(encFile!);

    // e.g. syncCache/map/files.map.enc|msg.map.enc
    final targetFile = await getFileAndMakeSureParentDirExist(targetPath);

    await encFile!.rename(targetFile.absolute.path);


    if(App.devModeOn) {
      final file = await getFileAndMakeSureParentDirExist(p.join(getRepoDebugDirPath(), "$fileName.json"));
      await writeStreamToFile(file, map.toJsonByteStream());
    }
  }

  Future<void> latestMsgMapHandler(DataMap? msgMap, KeyData contentKeyData, TempDir tempDir) async {
    final syncCacheDirPath = getSyncCacheDirPath();
    // syncCache/map/msg.map.enc
    await _latestMapHandler(getMsgMapFilePath(syncCacheDirPath), msgMap, contentKeyData, tempDir);
  }

  Future<void> latestFilesMapHandler(DataMap? filesMap, KeyData contentKeyData, TempDir tempDir) async {
    final syncCacheDirPath = getSyncCacheDirPath();
    // syncCache/map/files.map.enc
    await _latestMapHandler(getFilesMapFilePath(syncCacheDirPath), filesMap, contentKeyData, tempDir);
  }

  // 把同步后的远程最新的pfs存到本地cache目录
  Future<void> latestPfsFileHandler(
    RemoteDataType pfsType,
    String? encPfsPath,
    ObjPackFileStorage latestPfs,
    KeyData contentKeyData,
    TempDir tempDir
  ) async {
    App.logger.debug(_TAG, "latestPfsFileHandler(): pfsType: $pfsType, encrypted pfs file path: $encPfsPath");

    if(pfsType != RemoteDataType.objectsPfs) {
      throw AppException("pfs type is '$pfsType', but now only support save objects pfs to local remote data dir, err code: 19110107");
    }

    if(App.devModeOn) {
      final file = await getFileAndMakeSureParentDirExist(p.join(getRepoDebugDirPath(), "${pfsType.value}.${Remote.pfsFileName}.json"));
      await writeStreamToFile(file, latestPfs.toJsonByteStream());
    }


    File? encPfsFile = null;

    Future<void> createPfsFile() async {
      App.logger.debug(_TAG, "latestPfsFileHandler(): encrypted pfs file path is null or file not exists, will create pfs file by latest pfs instance.");
      encPfsFile = await tempDir.createTempFile();
      final encData = await EncryptedData.compressThenEncrypt(latestPfs.toJsonByteStream(), contentKeyData);
      await encData.writeToFile(encPfsFile!);
    }

    // 有加密好的（若objs变了，remote上传新版的话，就会加密，否则不会），则直接用，无则自己加密然后存储
    if(encPfsPath != null && encPfsPath.isNotEmpty) {
      encPfsFile = File(encPfsPath);

      // 不存在则创建；存在则检查是否和本地一致若一致则不创建
      if(!await encPfsFile!.exists()) {
        await createPfsFile();
      }else {
        final oldPfsFileInRepoLocalRemoteDir = File(
          p.join(
            getPfsDirPathByType(
              pfsType,
              // 这里必须用真正的remote data dir path，检查正式目录的对应文件是否和要写入的完全一样，若一样，则不会重复写入
              getRemoteDataDirPath()
            ),
            Remote.pfsFileName
          )
        );

        // 如果旧的 仓库dataDir/remote/pfs/files|objects|msg/pfs.enc 存在，
        // 校验下hash，若一样，就不替换了，替换有可能会先删除后覆盖，万一出错呢？
        // 若一样就没必要冒风险了
        if(await oldPfsFileInRepoLocalRemoteDir.exists()) {
          // 这里其实直接用普通的hash函数就行，是否用contentKeyData无所谓，又不上传
          final hashOfLatestPfsFile = await hashFileWithKeyData(contentKeyData, encPfsFile!, throwIfInterrupted: null);
          final hashOfOldPfsFile = await hashFileWithKeyData(contentKeyData, oldPfsFileInRepoLocalRemoteDir, throwIfInterrupted: null);
          if(listEquals(hashOfLatestPfsFile, hashOfOldPfsFile)) {
            App.logger.debug(_TAG, "latestPfsFileHandler(): pfs file not updated.");
            return;
          }
        }
      }
    }else {
      await createPfsFile();
    }

    final syncCacheDirPath = getSyncCacheDirPath();
    // syncCache/pfs/files|objects|msg/pfs.enc
    final pfsFile = await getFileAndMakeSureParentDirExist(
      p.join(getPfsDirPathByType(pfsType, syncCacheDirPath), Remote.pfsFileName)
    );

    if(encPfsFile == null) {
      throw AppException("objects pfs.enc is null, err code: 17734609");
    }

    await encPfsFile!.rename(pfsFile.absolute.path);
  }



  // 创建一个文件，如果这个文件存在，则强制执行强制同步，文件内保存原因
  // File getForceSyncFlagFile() {
  //   return File(p.join(path, dataDirName, forceSyncFlagFileName));
  // }
  //
  // Future<void> deleteForceSyncFlagFile() async {
  //   // 不如改成清空
  //   safeDelete(getForceSyncFlagFile());
  // }
  //
  // Future<void> createForceSyncFlagFile(String reason) async {
  //   final file = getForceSyncFlagFile();
  //   final ioSink = file.openWrite();
  //   ioSink.write(reason);
  //   await ioSink.close();
  // }

  Future<void> pushLocalOnlyData() async {
    throw UnimplementedError();
  }

  Future<void> deleteRemoteOnlyData() async {
    throw UnimplementedError();
  }

  Future<void> untrackPath(FilePath path) async {
    throw UnimplementedError();

    // 判断下，如果path是个目录，把本地和远程所有此目录下的文件都移除（files类型的pfc.enc有在extra里记录文件path，可用来判断），
    // 若是文件则只移除单独文件，
    // 删除本地和远程文件，例如，untrack path为 abc/123.txt，
    // 则把本地对应文件在 files下的oid目录移除，
    // 然后把远程对应pfs条目和.pack里的东西删除（需开remote session)
    // 下载远程最新的ignore对象，添加这个path
    // 最后提交会话，上传pfs.enc、 .pack文件、和ignore对象(加密，然后上传到ignore.enc)
  }

  // 把远程所有的数据下载到本地的指定目录
  Future<void> downloadAllRemoteDataToLocal(Directory saveDir) async {
    // 检测目录若不为空则抛异常

  }

  // 把指定目录的所有数据上传到远程
  Future<void> uploadAllDataToRemote(Remote remote, Directory srcDir) async {
    // 检测远程若不为空则抛异常
  }

  Future<void> migrateRepoToAnotherRemote(Remote anotherRemote) async {
    // 先调用 downloadAllRemoteDataToLocal
    // 再调用 uploadAllDataToRemote
  }

  // cache/downCache
  String getDownCacheDirPath() {
    return p.join(getCacheDirPath(), downCacheDirName);
  }

  // cache/downCache/tempDir
  String getDownCacheTempDirPath() {
    return p.join(getDownCacheDirPath(), "tempDir");
  }

  // cache/downCache/objPfsId
  String getDownCacheObjPfsIdFilePath() {
    return p.join(getDownCacheDirPath(), "objPfsId");
  }


  Future<List<Msg>> getConflictMsgs() async {
    final file = File(getMsgMapFilePath(getRemoteDataDirPath()));
    if(await file.exists()) {
      final encData = await EncryptedData.readFromFile(file);
      final data = await encData.decryptThenUncompress(await getContentKey());
      final str = await byteStreamToString(data);
      final dataMap = DataMap.fromJson(jsonDecode(str));
      final list = <Msg>[];
      for(final Map<String, dynamic> item in dataMap.data.values) {
        final msg = Msg.fromJson(item);
        if(msg.type.value == MsgType.conflict.value) {
          list.add(msg);
        }
      }
      return list;
    }else {
      return [];
    }
  }

  Future<List<FileInfo>> getDeletedFiles() async {
    final file = File(getFilesMapFilePath(getRemoteDataDirPath()));
    if(await file.exists()) {
      final encData = await EncryptedData.readFromFile(file);
      final data = await encData.decryptThenUncompress(await getContentKey());
      final str = await byteStreamToString(data);
      final dataMap = DataMap.fromJson(jsonDecode(str));
      final list = <FileInfo>[];
      for(final Map<String, dynamic> item in dataMap.data.values) {
        final fileInfo = FileInfo.fromJson(item);
        if(fileInfo.getLatestVersion().oid.value == VersionOid.deleted.value) {
          list.add(fileInfo);
        }
      }
      return list;
    }else {
      return [];
    }
  }

  // Future<ObjPackFileStorage> getPfsByType(RemoteDataType pfsType) async {
  //   if(!pfsType.isPfs()) {
  //     throw AppException("type '$pfsType' is not a pfs type, err code: 18243626");
  //   }
  //
  //   if(pfsType != RemoteDataType.objectsPfs) {
  //     throw AppException("only support objects pfs type, but got: $pfsType");
  //   }
  //
  //   final pfsFile = File(p.join(getPfsDirPathByType(pfsType, getRemoteDataDirPath()), Remote.pfsFileName));
  //   if(!await pfsFile.exists()) {
  //     return ObjPackFileStorage();
  //   }else {
  //     return await ObjPackFileStorage.decrypt(await getContentKey(), pfsFile);
  //   }
  // }


  // 注意：本函数不会查找本地的 .haha_note/remote/objects 目录！并且会在下载出对象后将加密的obj移动到对应目录。
  //      若想先从本地 remote/objects 查找条目，应先调用 repo.getTypedLocalData()，
  //      可参考 view_object.dart 页面的使用方式
  // 本函数先在本地cache找，若无则去远程下载。
  // 本函数先去本地的cache找，这时只需要加本地锁；
  // 若仍然无，上远程锁+本地锁，去远程找，
  // 若还是无，可能有bug导致对应obj在有关联的情况下丢失了。
  // 从远程下载（有缓存，重复下载同一文件或在同一.pack的objects，性能不会太差）
  // 返回类型：返回的一律是解密后的数据，
  // remote data type = files -> FileInfo, msg -> Msg, obj -> File（解密过的）
  Future<Map<String, File>> fetchDataCachedWithLock(
    final Set<VersionOid> oids, {
    required ThrowIfInterrupted? throwIfInterrupted,
    required SyncProgressCb? progressCb,
  }) async {
    // 若false，对数据正确性来说更安全，就算下载失败，也不影响正式目录的数据，
    // 缺点则是就算刚点击打开过条目，下次再预览还会下载。。。。
    final bool moveToRemoteDataDirAfterDownload = true;
    final RemoteDataType remoteDataType = RemoteDataType.objects;

    return await _fetchDataCached(
      remoteDataType,
      oids,
      throwIfInterrupted: throwIfInterrupted,
      moveToRemoteDataDirAfterDownload: moveToRemoteDataDirAfterDownload,
      progressCb: progressCb,
    );
  }

  // 返回oid和path的map，例如oid 123，下载到了tempDir/abc/obj.temp，则返回{"123": "tempDir/abc/obj.temp"}
  Future<Map<String, File>> _fetchDataCached(
    final RemoteDataType remoteDataType,
    final Set<VersionOid> oids, {
    required ThrowIfInterrupted? throwIfInterrupted,
    required final bool moveToRemoteDataDirAfterDownload,
    required SyncProgressCb? progressCb,
  }) async {
    final funName = "_fetchDataCached";

    // 检查是否本地支持的数据类型，若后面只限定特定类型，这个可注释，所以注释了
    // if(!remoteDataType.isLocalSupportedDataType()) {
    //   throw AppException("$funName: unsupported remote data type: $remoteDataType, err code: 11211215");
    // }

    // 限定特定类型
    if(remoteDataType != RemoteDataType.objects) {
      throw AppException("$funName: only support fetch object data, but got type: $remoteDataType, err code: 15075145");
    }

    final result = <String, File>{};
    if(oids.isEmpty) {
      return result;
    }

    var needDownloadObjs = <VersionOid>{};


    String? downCacheDirPath;
    Directory? downCacheDir;
    // 固定使用 cache/downCache/tempDir 作为tempDir
    String? tempDirPath;
    TempDir? tempDir;



    // 用来存remote数据，objects pfs之类的
    // cache/downCache/remote
    // final remoteDirInDownCache = p.join(downCacheDirPath, 'remote');
    // 会检查这个id和remote最新obj pfs的content id是否一样，若一样，则复用tempDir，可减少下载.pack文件的请求，否则清缓存
    // 注：就算这个不是最新的contentId，也有可能不会联网下载文件，
    // 只要当前 tempDir (downCache/tempDir) 的pfs.enc包含对应 obj oid以及关联的 .pack文件，
    // 就会直接从tempDir里的.pack文件提取数据，从而避免联网（因为obj是不可变数据，所以可以这么搞）
    String? cachedObjPfsContentIdPath;
    File? cachedObjPfsContentIdFile;


    String? remoteDataDirPath;
    KeyData? contentKeyData;


    // 查找文件前，先在缓存的pfs里找，再看对应pack是否已经存在于缓存目录，若在，直接使用本地缓存，否则下载
    // downCache/tempDir/fetchCache/pfs/files/pfs.enc
    File? objPfsFileInFetchCacheOfTempDir;
    String? objPfsPathInFetchCacheOfTempDir;

    // 先只加本地锁，从本地查找，如果找不到再加远程锁，从远程查找
    final localLockToken = LockToken(actName: "findObjInLocal", actDesc: "find obj in local");
    final localLocked = lockLocalRepoByPath(path, localLockToken);
    if(localLocked != null) {
      throw RepoBusyException(actName: localLocked.actName, actDesc: localLocked.actDesc);
    }


    try {
      progressCb?.call(SyncProgressAct.commitLocalSyncCache, 0, 0, "");

      // 如果，未提交完，用户返回，是否会导致数据出错？应该不会，因为这个函数调用前有上本地锁，而且提交过程不可interrupt，
      // 所以问题不大，若提交未完成，用户就返回，下次再点进来，会提示repo busy，提交完成后，抛异常，repo free，后续就正常了，
      // 问题不大，很小概率会出错
      await commitSyncCacheIfNeed();


      progressCb?.call(SyncProgressAct.checkingCache, 0, 0, "");

      downCacheDirPath = getDownCacheDirPath();
      downCacheDir = Directory(downCacheDirPath);
      // 固定使用 cache/downCache/tempDir 作为tempDir
      tempDirPath = getDownCacheTempDirPath();
      tempDir = await TempDir.fromDir(Directory(tempDirPath));



      // 用来存remote数据，objects pfs之类的
      // cache/downCache/remote
      // final remoteDirInDownCache = p.join(downCacheDirPath, 'remote');
      // 会检查这个id和remote最新obj pfs的content id是否一样，若一样，则复用tempDir，可减少下载.pack文件的请求，否则清缓存
      // 注：就算这个不是最新的contentId，也有可能不会联网下载文件，
      // 只要当前 tempDir (downCache/tempDir) 的pfs.enc包含对应 obj oid以及关联的 .pack文件，
      // 就会直接从tempDir里的.pack文件提取数据，从而避免联网（因为obj是不可变数据，所以可以这么搞）
      cachedObjPfsContentIdPath = getDownCacheObjPfsIdFilePath();
      cachedObjPfsContentIdFile = File(cachedObjPfsContentIdPath);


      remoteDataDirPath = getRemoteDataDirPath();
      contentKeyData = await getContentKey();


      // 查找文件前，先在缓存的pfs里找，再看对应pack是否已经存在于缓存目录，若在，直接使用本地缓存，否则下载
      // downCache/tempDir/fetchCache/pfs/files/pfs.enc
      objPfsFileInFetchCacheOfTempDir = await remote.getPfsFileByTypeFromFetchCache(RemoteDataType.objectsPfs, tempDir);
      objPfsPathInFetchCacheOfTempDir = FilePath.canonicalizePath(objPfsFileInFetchCacheOfTempDir.absolute.path);

      ObjPackFileStorage? objPfs;
      try {
        if(await objPfsFileInFetchCacheOfTempDir.exists()) {
          objPfs = await ObjPackFileStorage.decrypt(contentKeyData, objPfsFileInFetchCacheOfTempDir);
        }
      }catch(e, st) {
        // 可能文件损坏或者怎样，总之本地文件有问题，后面会重新下载
        App.logger.debug(_TAG, "decrypt objects pfs err, file maybe broken, will re-download it, file path is '${objPfsFileInFetchCacheOfTempDir.absolute.path}'\nerr: $e\n$st");
      }

      if(objPfs != null) {
        final allCount = oids.length;
        int count = 0;

        final objPfsFindResultMap = await objPfs.toFindResultMap();
        // 检查本地缓存是否有对应文件
        for(final oid in oids) {
          count++;
          throwIfInterrupted?.call();

          // 已经下载过这个文件了
          if(result[oid.value] != null) {
            continue;
          }

          if(ObjRef.isInvalidOid(oid.value)) {
            continue;
          }

          progressCb?.call(SyncProgressAct.searchingCache, allCount, count, oid.value);

          // 由于提交了本地syncCache，所以这里说不定有数据了，因此检查下，本地若有，直接使用
          File? file = await getTypedLocalData(RemoteDataType.objects, oid, remoteDataDirPath, tempDir);
          if(file != null) {
            result[oid.value] = file;
            continue;
          }

          final findResult = await objPfs.find(oid, findResultMap: objPfsFindResultMap);
          if(!findResult.foundItem()) {
            needDownloadObjs.add(oid);
            continue;
          }

          // packFile
          final packFile = await remote.getPackFileByNameFromFetchCache(findResult.packFile!.name, RemoteDataType.objectsPfs, tempDir, pfsFile: objPfsFileInFetchCacheOfTempDir);
          if(!await packFile.exists()) {
            needDownloadObjs.add(oid);
            continue;
          }

          // 本地pack file存在，直接解压即可
          var targetFile = await tempDir.createTempFile();
          await objPfs.extractFromPackFile(packFile, findResult.packItem!, targetFile);

          throwIfInterrupted?.call();

          if(!await targetFile.exists()) {  // 这个不应该发生
            needDownloadObjs.add(oid);
            continue;
          }

          if(moveToRemoteDataDirAfterDownload) {
            final objPathInRemoteDataDir = Repo.getLocalRemoteObjectPathByOidStr(remoteDataDirPath, oid.value);
            await getFileAndMakeSureParentDirExist(objPathInRemoteDataDir);
            targetFile = await targetFile.rename(objPathInRemoteDataDir);
          }

          result[oid.value] = await decryptDataByType(remoteDataType, targetFile, tempDir);
        }
      }else {
        // 本地objpfs解密失败，要么损坏，要么有问题，要么无文件
        // 把所有oid当作待下载，然后清掉本地contentId文件
        needDownloadObjs = oids;
        // 删掉本地的contentId文件，使缓存无效，后面就会清缓存了
        // 之所以不try catch，而是判断存在再删除，是为了确保如果文件存在，则删除一定成功，若出错，则应抛异常
        if(await cachedObjPfsContentIdFile.exists()) {
          await cachedObjPfsContentIdFile.delete();
        }
      }

      if(needDownloadObjs.isEmpty) {
        App.logger.debug(_TAG, "$funName: all files found in cache, no need download.");
        return result;
      }

    } finally {
      freeLocalRepoLockByPath(path, localLockToken);
    }



    // 执行到这，本地有可能不存在object pfs文件，后面需自行判断

    throwIfInterrupted?.call();

    final throwIfInterruptedOuter = throwIfInterrupted;
    return await doActWithLock(
      contentKeyData,
      actName: "fetchDataCached",
      actDesc: "fetch data with cached",
      needInitRemote: true,
      act: (throwIfLockLost, isLockRenewaling, remoteSessionCommitBegin, remoteSessionCommitEnd) async {
        void throwIfInterrupted2() {
          // 锁被别人抢了
          throwIfLockLost();

          // 外部取消了任务，比如用户点击了取消按钮
          throwIfInterruptedOuter?.call();
        }

        throwIfInterrupted = throwIfInterrupted2;


        progressCb?.call(SyncProgressAct.downloading, 0, 0, "");
        // File? remoteObjPfsFile;

        // 开会话有可能处理上次未完成的上传任务，不过这里不用在意
        final sessionId = await remote.sessionStart(
          'download file (cached)',
          'download file with cache',
          contentKeyData!,
          tempDir!,
          // requireFetchPfs: true,
          // x 提交下，没毛病）不管sync的事，若数据没移动完成，有错，无所谓，同步后重试就行了
          // commitSyncCache: false,
          throwIfInterrupted: throwIfInterrupted,
          // 用不到这files map和msg map，这里只需fetch obj pfs就行了（默认fetch，无需传参）
          requireFetchFilesMap: false,
          requireFetchMsgMap: false,
          // latestObjPfsFileReceiver: (objPfsFile) async {
          //   remoteObjPfsFile = objPfsFile;
          // }

          isLockRenewaling: isLockRenewaling,
          remoteSessionCommitBegin: remoteSessionCommitBegin,
          remoteSessionCommitEnd: remoteSessionCommitEnd,
          client: client,
        );

        // if(remoteObjPfsFile == null) {
        //   throw AppException("fetch remote object pfs file failed");
        // }

        throwIfInterrupted?.call();


        Future<void> resetDownCache({required String latestObjPfsContentId}) async {
          // 如果远程有推送新版本，sync history最新节点和本地不一致，则会清空downCache，重新下载pack文件，否则会复用
          App.logger.debug(_TAG, "$funName: local downCache invalid, will clear downCache and re-download objects");

          if(!await objPfsFileInFetchCacheOfTempDir!.exists()) {
            throw AppException("not found objects pfs in fetch cache, err code: 16086632");
          }

          // 要清downCache和其下的temp dir (downCache/tempDir)，所以先备份下objects pfs.enc文件，清完恢复，不然后续remote下载文件等操作都依赖这个文件

          // downCacheDir 目录必然存在，因为remote.sessionStart()时会下载obj pfs.enc到其下tempDir/fetchCache
          await for(final f in downCacheDir!.list(recursive: true, followLinks: false)) {
            // 不确定目录遍历的顺序，避免递归删除目录导致某些目录不存在，只删文件，不删目录
            if(f is! File) {
              continue;
            }

            // 不删除刚下载到 tempDir/fetchCache 下的 objects pfs.enc文件
            if(FilePath.canonicalizePath(f.absolute.path) == objPfsPathInFetchCacheOfTempDir) {
              continue;
            }

            // 删除其余文件
            await f.delete();
          }

          // await downCacheDir.create(recursive: true);  // 创建cachedObjPfsContentIdPath文件的父目录时就会创建这个目录了，所以这不需要单独创建
          await getFileAndMakeSureParentDirExist(cachedObjPfsContentIdPath!);

          // 最后再更新id，这样可确保content id文件若存在，匹配的obj pfs.enc一定存在
          await writeStrToFile(cachedObjPfsContentIdFile!, latestObjPfsContentId);
        }


        final remoteObjPfsContentId = remote.objectsPfs!.contentId;
        if(await cachedObjPfsContentIdFile!.exists()) {
          // 检查本地缓存是否最新，若不是最新则清缓存目录，然后拷贝最新的到缓存目录
          final localCachedObjPfsContentId = (await cachedObjPfsContentIdFile.readAsString()).trim();
          // 比较下缓存的obj pfs文件是否和远程一致即可
          if(localCachedObjPfsContentId != remoteObjPfsContentId) {
            await resetDownCache(latestObjPfsContentId: remoteObjPfsContentId);
          }else {
            // 若执行到这，不会清cache目录，可复用本地缓存在 downCache/tempDir/fetchCache/pfs/objects 的 obj *.pack 文件，避免更多下载
            App.logger.debug(_TAG, "$funName: local downCache matched remote latest sync history, so can be avoid download *.pack files which already exists in local downCache dir");
          }
        }else {
          // 若本地无缓存obj pfs文件，则清缓存目录，然后拷贝最新的到本地
          await resetDownCache(latestObjPfsContentId: remoteObjPfsContentId);
        }


        try {

          // 可以开始使用remote了

          throwIfInterrupted?.call();


          // 这里不下载pfs.enc，也不提交会话（用取消替代），只是下载files|msg|objects/oid/data.enc，
          // 这些目录下的文件都是可以删除的，缺了就下载就行（忘了有无写对应逻辑，所以不要加清空这几个目录的功能），
          // 所以直接使用仓库正式remote data dir即可
          final allCount = needDownloadObjs.length;
          int count = 0;
          for(final oid in needDownloadObjs) {
            try {
              count++;
              throwIfInterrupted?.call();

              // 已经下载过这个文件了
              if(result[oid.value] != null) {
                continue;
              }

              if(ObjRef.isInvalidOid(oid.value)) {
                continue;
              }

              progressCb?.call(SyncProgressAct.downloading, allCount, count, oid.value);

              // 由于提交了本地syncCache，所以这里说不定有数据了，因此检查下，本地若有，直接使用
              File? file = await getTypedLocalData(RemoteDataType.objects, oid, remoteDataDirPath!, tempDir);
              if(file != null) {
                result[oid.value] = file;
                continue;
              }


              file = await remote.fetchObject(
                oid,
                remoteDataDirPath,
                tempDir,
                moveToRemoteDataDirAfterDownload: moveToRemoteDataDirAfterDownload,
              );

              throwIfInterrupted?.call();

              result[oid.value] = await decryptDataByType(remoteDataType, file, tempDir);

            }catch(e) {
              // 下载错误的条目直接跳过即可，最后返回的时候通过result[oid]是否为null判断某个对象是否下载成功
              App.logger.verbose(_TAG, "$funName: download object err: oid=$oid");
            }
          }

          return result;
        }finally {
          // 不要清整个tempDir，要复用里面的数据呢，若缓存失效，会在上面重置
          // await tempDir.clean();
          // x 这个目录也不能清，因为返回的文件在这个目录呢）可把tempDir下的temp目录清了，里面存的都是不可复用的临时文件，名字随机的，就算想复用也不知道哪个文件是干嘛的
          // await safeDeleteDir(await tempDir.tempDir());

          await remote.sessionCancel(sessionId);
        }
      },
    );
  }

  Future<dynamic> decryptDataByType(
    final RemoteDataType remoteDataType,
    final File file,
    final TempDir tempDir
  ) async {
    if(await file.exists()) {
      final contentKeyData = await getContentKey();

      // TODO 考虑是否加入：如果解密失败，删除本地文件的逻辑
      //      如果下载文件被中断，会经常导致文件损坏，就加入这个逻辑，然后就会触发重下，
      //      若不经常导致本地出现损坏文件，就不用加这个逻辑
      if(remoteDataType == RemoteDataType.files) {
        return await FileInfo.decrypt(contentKeyData, file);
      }else if(remoteDataType == RemoteDataType.msg) {
        return await Msg.decrypt(contentKeyData, file);
      }else {
        final encryptedData = await EncryptedData.readFromFile(file);
        final rawData = await encryptedData.decryptThenUncompress(contentKeyData);
        final tempFile = await tempDir.createTempFile();
        await writeStreamToFile(tempFile, rawData);
        return tempFile;
      }
    }else {
      return null;
    }
  }


  // 如果是files，返回fileinfo；msg，返回msg对象；obj，返回解密后的File；若文件不存在，返回null
  Future<dynamic> getTypedLocalData(
    final RemoteDataType remoteDataType,
    final VersionOid oid,
    final String remoteDataDirPath,
    final TempDir tempDir
  ) async {
    if(remoteDataType == RemoteDataType.objects) {
      final file = await getLocalData(remoteDataType, oid, remoteDataDirPath, tempDir);
      return await decryptDataByType(remoteDataType, file, tempDir);
    }else if(remoteDataType == RemoteDataType.files) {
      final dataMap = await getLocalFilesMap(await getContentKey());
      final jsonMap = dataMap.get(oid);
      if(jsonMap != null) {
        return FileInfo.fromJson(jsonMap);
      }
      return null;
    }else if(remoteDataType == RemoteDataType.msg) {
      final dataMap = await getLocalMsgMap(await getContentKey());
      final jsonMap = dataMap.get(oid);
      if(jsonMap != null) {
        return Msg.fromJson(jsonMap);
      }
      return null;
    }else {
      throw AppException("unsupported to get local data for remote data type: $remoteDataType, err code: 11456016");
    }
  }

  Future<File> getLocalData(
    final RemoteDataType remoteDataType,
    final VersionOid oid,
    final String remoteDataDirPath,
    final TempDir tempDir,
  ) async {
    // if(!remoteDataType.isLocalSupportedDataType()) {
    //   throw AppException("unsupported remote data type: $remoteDataType, err code: 18641774");
    // }


    if(remoteDataType != RemoteDataType.objects) {
      throw AppException("only support fetch object data, but got type: $remoteDataType, err code: 13834033");
    }


    // 文件有可能不存在，自行检查吧
    return File(getLocalRemoteObjectPathByOidStr(remoteDataDirPath, oid.value));
  }

  // 注意：下载的是未解密的文件
  Future<File> getLocalOrFetch(
    final RemoteDataType remoteDataType,
    final VersionOid oid,
    final TempDir tempDir, {

    //会在这个目录查找本地有无对应obj，这个目录一般是正式的 remote data dir
    // required final String localRemoteDataDirPath,

    // 若本地对应obj不存在，则需fetch，会把fetch后的文件存到这个目录，
    // x 废弃，直接下载到正式目录了，因为当初期望的是先下载到syncCache再rename以避免write stream中断导致文件不完整（无法完全保证），
    // 但其实fetchData本身就是下载到临时文件再rename，所以多此一举了）如果是正在同步，可能会把syncCache传到这个参数，先把文件存到syncCache
    // required final String remoteDataDirForFetch,

    required final bool moveToRemoteDataDirAfterDownload,
    bool deleteLocalThenReFetch = false
  }) async {
    // if(!remoteDataType.isLocalSupportedDataType()) {
    //   throw AppException("unsupported remote data type: $remoteDataType, err code: 12452159");
    // }


    if(remoteDataType != RemoteDataType.objects) {
      throw AppException("only support fetch object data, but got type: $remoteDataType, err code: 10504251");
    }

    final localRemoteDataDirPath = getRemoteDataDirPath();
    // 这个是用的真的 remoteDataDirPath，因为需要检测本地文件是否存在，
    // 下面fetch的时候可能会用syncCache里的路径
    final localRemoteFile = await getLocalData(remoteDataType, oid, localRemoteDataDirPath, tempDir);

    if(deleteLocalThenReFetch) {
      await safeDeleteFile(localRemoteFile);
    }

    if(await localRemoteFile.exists()) {
      // 检查本地仓库的dataDir/remote/objects/oid/data.enc 是否存在，若存在，则不需要下载，直接使用缓存的即可
      return localRemoteFile;
    }


    // 本地无，下载，先下载到syncCache，同步完成后再移动到正式目录(仓库dataDir/remote/objects)
    // 下次获取同一对象会优先从本地的 tempDir/fetchCache里获取，若对象推送过，则会从 tempDir/pushCache 里获取
    final downloadedFile = await remote.fetchObject(
      oid,
      localRemoteDataDirPath,
      tempDir,
      moveToRemoteDataDirAfterDownload: moveToRemoteDataDirAfterDownload,
    );

    return downloadedFile;
  }



  // Future<FileInfo?> getLocalFileInfo(String path) async {
  //   final fp = FilePath.fromString(path);
  //   final contentKeyData = await getContentKey();
  //   final oid = await fp.toOid(contentKeyData);
  //
  //   final filePath = getFileInfoPathByOidStr(getRemoteDataDirPath(), oid.value);
  //
  //   final file = File(filePath);
  //   if(!await file.exists()) {
  //     return null;
  //   }
  //
  //   return FileInfo.decrypt(contentKeyData, file);
  // }

  Future<Msg?> getLocalMsg(String oid) async {
    final filePath = getMsgPathByOidStr(getRemoteDataDirPath(), oid);

    final file = File(filePath);
    if(!await file.exists()) {
      return null;
    }

    final contentKeyData = await getContentKey();
    return Msg.decrypt(contentKeyData, file);
  }



  Future<Set<String>?> _delFileInfosOrMsgs<T extends RelatedOids>(
    KeyData contentKeyData,
    RemoteDataType remoteDataType,
    List<T> items,
    TempDir tempDir, {
    required ThrowIfInterrupted? throwIfInterrupted,
    SyncProgressCb? syncProgressCb,
    required bool returnObjectsCanDeleteList
  }) async {
    // 只有这两个需要删除，其他的，例如objects，属于files和msg的附属品，如果files和msg移除，会把关联的objects移除
    if(remoteDataType != RemoteDataType.files && remoteDataType != RemoteDataType.msg) {
      throw AppException("doesn't support delete remote data type: $remoteDataType");
    }

    if(items.isEmpty) {
      return null;
    }

    throwIfInterrupted?.call();

    final remoteDataDirPath = getRemoteDataDirPath();


    int count = 0;
    int allCount = items.length;
    final Set<String>? objectsWhichNoRefsCanDel = returnObjectsCanDeleteList ? {} : null;
    final workdirPath = getWorkdirPath();
    for(final item in items) {
      throwIfInterrupted?.call();
      count++;


      // use to let sync progress show fileInfo path or msg oid
      // file info or msg
      // path or msg oid
      String itemDescText = "";
      final RelatedOids relatedOids;
      if(item is FileInfo) {
        final remoteLatestItem = remote.filesMap!.get(await item.toOid(contentKeyData));
        if (remoteLatestItem == null) {
          // 可能本地没删对应条目，但远程删除了，跳过
          continue;
        }

        if(await isExistsFileForRepo(p.join(workdirPath, item.path))) {
          // workdir存在对应文件，不删除对应条目
          App.logger.debug(_TAG, "_delFileInfosOrMsgs: workdir exists path: '${item.path}', so will not delete it");
          continue;
        }

        relatedOids = FileInfo.fromJson(remoteLatestItem);
        itemDescText = item.path;  // 远程本地path一样，所以这个不必用remote的，直接用item的就行
      }else if(item is Msg) {
        final remoteLatestItem = remote.msgMap!.get(item.oid);
        if (remoteLatestItem == null) {
          // 可能本地没删对应条目，但远程删除了，跳过
          continue;
        }

        final msg = Msg.fromJson(remoteLatestItem);
        relatedOids = msg;
        // 冲突msg带path，可取出，正常应该不会执行到 ?? 后面
        itemDescText = msg.data["path"] ?? msg.oid.value;
      }else {
        throw AppException("unsupported item type: ${item.runtimeType}");
      }

      syncProgressCb?.call(
        SyncProgressAct.deletingObject,
        allCount,
        count,
        itemDescText
      );

      await remote.deleteDataAndRelatedOids(
        contentKeyData,
        remoteDataType,
        relatedOids,
        tempDir,
        canDelObjsHandler: (oid) async {
          if(objectsWhichNoRefsCanDel != null) {
            // 本地remoteDataDir的obj文件
            final localObjFilePath = Repo.getLocalRemoteObjectPathByOidStr(remoteDataDirPath, oid);
            // 把obj的路径添加进去就行，msg和file info都是map条目，本地没data.enc文件了，所以也不需要删除
            objectsWhichNoRefsCanDel.add(localObjFilePath);
          }


          // 废弃：改成在提交syncCache时删除
          // 原地删除
          // if(await objFile.exists()) {
          //   await safeDeleteFile(objFile);
          //
          //   // 删除父目录（若为空）
          //   try {
          //     await objFile.parent.delete(recursive: false);
          //   }catch(_) {
          //
          //   }
          // }
        }
      );
    }

    return objectsWhichNoRefsCanDel;
  }

  // remoteDataDirPath/map/msg.map.enc
  static String getMsgMapFilePath(String remoteDataDirPath) {
    return p.join(remoteDataDirPath, Remote.mapDirName, Remote.msgMapFileName);
  }

  // remoteDataDirPath/map/files.map.enc
  static String getFilesMapFilePath(String remoteDataDirPath) {
    return p.join(remoteDataDirPath, Remote.mapDirName, Remote.filesMapFileName);
  }

  Future<DataMap> getLocalFilesMap(KeyData contentKeyData) async {
    final file = File(getFilesMapFilePath(getRemoteDataDirPath()));
    return await DataMap.decrypt(contentKeyData, file);
  }

  Future<DataMap> getLocalMsgMap(KeyData contentKeyData) async {
    final file = File(getMsgMapFilePath(getRemoteDataDirPath()));
    return await DataMap.decrypt(contentKeyData, file);
  }

  static String getDataDirPathByRepoPath(String repoPath) {
    return p.join(repoPath, dataDirName);
  }

  // 恢复工作目录对应文件到指定oid；
  // 注：若oid是Deleted，会删除工作目录的文件
  Future<void> restoreFiles(
    Set<OidAndPath> items, {
    SyncProgressCb? progressCb,
    ThrowIfInterrupted? throwIfInterrupted,
    // 若为null，使用仓库默认的workdir path
    String? outputPath,
    Future<void> Function(String relativePath, String oid)? objNotFoundHandler,
  }) async {
    if(items.isEmpty) {
      return;
    }

    final tempDir = await createTempDir("restoreFiles");

    try {
      int allCount = items.length;
      int count = 0;
      final workdirBasePath = outputPath ?? getWorkdirPath();
      final remoteDataDirPath = getRemoteDataDirPath();
      final contentKeyData = await getContentKey();

      // Map{relativePath: oid}
      final needDownloadFiles = <String, String>{};
      final needDownloadOids = <VersionOid>{};
      // {oid: relatedFilesCount}
      // if relatedFilesCount == 1, then rename file, else copy
      final needDownloadFilesCount = <String, int>{};

      for(final item in items) {
        throwIfInterrupted?.call();
        count++;
        progressCb?.call(SyncProgressAct.handling, allCount, count, item.path);

        final workdirFileFullPath = p.join(workdirBasePath, item.path);
        final workdirFile = File(workdirFileFullPath);

        final lastOid = item.oid;

        // 目标oid是Deleted，直接删除
        if(lastOid.value == VersionOid.deleted.value) {
          await deleteFileIfExists(workdirFile);
          continue;
        }

        // 若workdir对应文件存在，判断oid是否相同，若相同则不需要恢复
        if(await workdirFile.exists()) {
          final hashOfWorkdirFile = await hashFileToHexWithKeyDataForSync(
            filePath: workdirFileFullPath,
            contentKeyData: contentKeyData,
            throwIfInterrupted: throwIfInterrupted,
          );
          if(hashOfWorkdirFile == lastOid.value) {
            // 若workdir对应文件存在并且和版本历史中的删除前的上一版本一样，则不需要恢复
            continue;
          }
        }

        throwIfInterrupted?.call();

        // 本地文件不存在或hash和版本历史中的不同，执行恢复

        // 先检查本地是否有，若有则用
        File? decryptedObjFile = await getTypedLocalData(RemoteDataType.objects, lastOid, remoteDataDirPath, tempDir);
        if(decryptedObjFile != null) {
          progressCb?.call(SyncProgressAct.foundLocalCache, allCount, count, item.path);
          throwIfInterrupted?.call();

          App.logger.debug(_TAG, "found cached files in local, will use it, object oid: $lastOid");
          await getFileAndMakeSureParentDirExist(workdirFileFullPath);
          await decryptedObjFile.rename(workdirFileFullPath);
          continue;
        }

        needDownloadFiles[item.path] = lastOid.value;
        needDownloadOids.add(lastOid);

        final objRelatedFilesCount = needDownloadFilesCount[lastOid.value];
        needDownloadFilesCount[lastOid.value] = objRelatedFilesCount != null ? objRelatedFilesCount+1 : 1;
      }

      // 文件在本地没有，得下载了
      App.logger.debug(_TAG, "local cache not found, will download objects");

      progressCb?.call(SyncProgressAct.downloading, allCount, count, "");


      // 上面的代码先在本地 .haha_note/remote/objects 里找，这时不需要锁；
      // 若无，调用本函数；
      // 本函数先去本地的cache找，这时只需要加本地锁；
      // 若仍然无，上远程锁+本地锁，去远程找，
      // 若还是无，可能有bug导致对应obj在有关联的情况下丢失了。
      // 从远程下载（有缓存，重复下载同一文件或在同一.pack的objects，性能不会太差）
      final downloadedObjs = await fetchDataCachedWithLock(
        needDownloadOids,
        throwIfInterrupted: throwIfInterrupted,
        progressCb: progressCb,
      );

      needDownloadOids.clear();

      allCount = needDownloadFiles.entries.length;
      count = 0;
      for(final entry in needDownloadFiles.entries) {
        throwIfInterrupted?.call();
        count++;

        final String relativePathUnderWorkdir = entry.key;
        final String oidStr = entry.value;

        progressCb?.call(SyncProgressAct.handling, allCount, count, relativePathUnderWorkdir);

        final File? decryptedObjFile = downloadedObjs[oidStr];  // 一般来说，只要下载成功，就不会为null
        if(decryptedObjFile == null) {
          progressCb?.call(SyncProgressAct.objNotFound, allCount, count, relativePathUnderWorkdir);
          await objNotFoundHandler?.call(relativePathUnderWorkdir, oidStr);
          continue;
        }


        final workdirFileFullPath = p.join(workdirBasePath, relativePathUnderWorkdir);

        await getFileAndMakeSureParentDirExist(workdirFileFullPath);
        final objRelatedFilesCount = needDownloadFilesCount[oidStr]!;

        // 如果一个obj关联单个文件，则移动，否则拷贝
        // 注：若一个obj关联多个文件，最后一次也会执行移动，不过之前都是拷贝，
        //    最后一次执行移动而不是拷贝可确保最后执行完操作后
        //    文件被移出 cache/downCache/temp 目录
        if(objRelatedFilesCount < 2) {  // 实际不会为null，只会大于等于1
          await decryptedObjFile.rename(workdirFileFullPath);
        }else {
          await decryptedObjFile.copy(workdirFileFullPath);
          needDownloadFilesCount[oidStr] = objRelatedFilesCount-1;
        }
      }

    }finally {
      await tempDir.clean();
    }
  }

  Future<void> restoreDeletedFileInfo(
    List<FileInfo> files, {
    SyncProgressCb? progressCb,
    ThrowIfInterrupted? throwIfInterrupted,
  }) async {
    if(files.isEmpty) {
      return;
    }

    int count = 0;
    int allCount = 0;
    final needRestoreFiles = <OidAndPath>{};
    for(final f in files) {
      throwIfInterrupted?.call();
      count++;
      progressCb?.call(SyncProgressAct.scanning, allCount, count, f.path);

      if(f.curNode().oid.value != VersionOid.deleted.value) {
        continue;
      }

      final lastOid = f.lastNode()?.oid;
      if(lastOid == null) {
        App.logger.warn(_TAG, "file only have a 'Deleted' node: repoName=$repoName, filePath=${f.path}");
        continue; // should never happens, 如果当前节点是删除，必然存在上个节点且不是删除，不过就算不是其实也无所谓，只是逻辑上不对，实际上可无视
      }

      // 因为是从已删除条目列表调用此函数，所以这个检查稍微有点意义，
      // 否则可能会尝试把文件恢复为无效id，但一般id都是有效的，所以命中此if判断的概率应该几乎是0
      if(ObjRef.isInvalidOid(lastOid.value)) {
        continue;
      }

      needRestoreFiles.add(OidAndPath(oid: lastOid, path: f.path));

    }

    await restoreFiles(needRestoreFiles, progressCb: progressCb, throwIfInterrupted: throwIfInterrupted);

  }


  Future<void> deleteRepo({
    required final bool deleteRemote,
    required final bool deleteLocal,
    ThrowIfInterrupted? throwIfInterrupted,
    SyncProgressCb? progressCb,
  }) async {
    if(!deleteRemote && !deleteLocal) {
      return;
    }

    final actName = "deleteRepo";
    if(deleteRemote) {
      progressCb?.call(SyncProgressAct.deletingRemote, 0, 0, "");
      final tempDir = await createTempDir(actName);
      try {
        await remote.doInit(tempDir, packMaxLen: await getEffectPackMaxLen());
        throwIfInterrupted?.call();
        await remote.deleteRepo(client, actName);
      }finally {
        await tempDir.clean();
      }
    }

    throwIfInterrupted?.call();

    if(deleteLocal) {
      progressCb?.call(SyncProgressAct.deletingLocal, 0, 0, "");
      await cancelableDelete(Directory(path), throwIfInterrupted: throwIfInterrupted, progressCb: progressCb);
    }
  }

  // Future<List<ExportFailedItem>> exportFilesOfHistoryNodeWithLock({
  //   required VersionOid historyNodeOid,
  //   required String exportPath,
  //   ThrowIfInterrupted? throwIfInterrupted,
  //   SyncProgressCb? progressCb,
  // }) async {
  //   final contentKeyData = await getContentKey();
  //   return await doActWithLock(
  //     contentKeyData,
  //     actName: "exportFilesOfHistoryNode",
  //     actDesc: "export files of history node with lock",
  //     needInitRemote: true,
  //     act: (throwIfLockLost, isLockRenewaling, remoteSessionCommitBegin, remoteSessionCommitEnd) async {
  //       void throwIfInterruptedWithLock() {
  //         // 锁被别人抢了
  //         throwIfLockLost();
  //
  //         // 外部取消了任务，比如用户点击了取消按钮
  //         throwIfInterrupted?.call();
  //       }
  //
  //       return await _exportFilesOfHistoryNode(
  //         contentKeyData: contentKeyData,
  //         historyNodeOid: historyNodeOid,
  //         exportPath: exportPath,
  //         throwIfInterrupted: throwIfInterruptedWithLock,
  //         progressCb: progressCb,
  //
  //         isLockRenewaling: isLockRenewaling,
  //         remoteSessionCommitBegin: remoteSessionCommitBegin,
  //         remoteSessionCommitEnd: remoteSessionCommitEnd,
  //       );
  //     }
  //   );
  // }
  //
  // // 返回导出失败的条目，若空，则全部成功
  // Future<List<ExportFailedItem>> _exportFilesOfHistoryNode({
  //   required KeyData contentKeyData,
  //   required VersionOid historyNodeOid,
  //   required String exportPath,
  //   required ThrowIfInterrupted? throwIfInterrupted,
  //   required SyncProgressCb? progressCb,
  //
  //   Future<bool> Function()? isLockRenewaling,
  //   Future<void> Function()? remoteSessionCommitBegin,
  //   Future<void> Function()? remoteSessionCommitEnd,
  // }) async {
  //   if(!isDirEmptyOrNoExistsSync(exportPath)) {
  //     throw AppException("export dir already exists and is not empty, path: $exportPath");
  //   }
  //
  //   final actName = "_exportFilesOfHistoryNode";
  //   final tempDir = await createTempDir(actName);
  //
  //   try {
  //     final result = <ExportFailedItem>[];
  //
  //     await _doActWithRemoteSessionWithoutCommit(
  //       actName: actName,
  //       actDesc: "export files of history node",
  //       contentKeyData: contentKeyData,
  //       throwIfInterrupted: throwIfInterrupted,
  //       progressCb: progressCb,
  //       tempDir: tempDir,
  //
  //       isLockRenewaling: isLockRenewaling,
  //       remoteSessionCommitBegin: remoteSessionCommitBegin,
  //       remoteSessionCommitEnd: remoteSessionCommitEnd,
  //
  //       act: () async {
  //         final tempFile = await tempDir.createTempFile();
  //         // 下载对应版本的files.map，有可能失败，不用捕获，直接抛就行
  //         await remote.downloadToFile(remote.genRemoteFilesMapBakFilePath(historyNodeOid: historyNodeOid.value), tempFile, tempDir);
  //         final filesMapOfNode = await DataMap.decrypt(contentKeyData, tempFile);
  //         // final remoteDataDirPath = getRemoteDataDirPath();
  //
  //         // 开始导出
  //         final allCount = filesMapOfNode.data.values.length;
  //         int count = 0;
  //
  //         // 创建导出目录，若不创建，节点无文件或所有文件都是已删除时，就没导出目录了，感觉不合逻辑
  //         await getAndMakeSureDirExists(exportPath);
  //
  //         // 若节点无文件或所有文件都是已删除，则会创建空目录，内部无文件
  //         for(final fileJsonMap in filesMapOfNode.data.values) {
  //           count++;
  //           throwIfInterrupted?.call();
  //
  //           final fileInfo = FileInfo.fromJson(fileJsonMap);
  //           final curNode = fileInfo.curNode();
  //           if(curNode.oid == VersionOid.deleted) {
  //             continue;
  //           }
  //
  //           progressCb?.call(SyncProgressAct.downloading, allCount, count, fileInfo.path);
  //
  //           try {
  //             final localObjFile = await getLocalOrFetch(
  //               RemoteDataType.objects,
  //               curNode.oid,
  //               tempDir,
  //               // localRemoteDataDirPath: remoteDataDirPath,
  //               // remoteDataDirForFetch: remoteDataDirPath,  // 直接fetch到正式目录即可
  //               moveToRemoteDataDirAfterDownload: true
  //             );
  //
  //             throwIfInterrupted?.call();
  //
  //             progressCb?.call(SyncProgressAct.exporting, allCount, count, fileInfo.path);
  //
  //             //解密数据
  //             final encryptedObj = await EncryptedData.readFromFile(localObjFile);
  //             final decryptedObj = await encryptedObj.decryptThenUncompress(contentKeyData);
  //
  //             throwIfInterrupted?.call();
  //
  //             final exportFilePath = await getFileAndMakeSureParentDirExist(p.join(exportPath, fileInfo.path));
  //             // 导出一般是导到空目录或无关目录，没必要先拷贝到临时文件再rename到正式目录，直接写到正式目录即可，
  //             // 若操作中断或出错，就算文件损坏也符合逻辑，只确保操作成功完成所有存在的文件正确即可，不存在的文件可能是远程已经没对应obj了，没办法导出
  //             await writeStreamToFile(exportFilePath, decryptedObj);
  //           }catch(e, st) {
  //             App.logger.debug(_TAG, "export file '${fileInfo.path}' failed: $e\n$st");
  //             result.add(ExportFailedItem(relativePath: fileInfo.path, oid: curNode.oid.value, errMsg: e.toString()));
  //             continue;
  //           }
  //         }
  //       }
  //     );
  //
  //     return result;
  //   }finally {
  //     await tempDir.clean();
  //   }
  // }

  Future<List<ExportFailedItem>> exportFilesOfHistoryNode({
    required VersionOid historyNodeOid,
    required String exportPath,
    required ThrowIfInterrupted? throwIfInterrupted,
    required SyncProgressCb? progressCb,
  }) async {
    if(!isDirEmptyOrNoExistsSync(exportPath)) {
      throw AppException("export dir already exists and is not empty, path: $exportPath");
    }

    final filesMap = await downloadFilesMapByVer(historyNodeOid.value);
    if(filesMap == null) {
      throw AppException("version of files map not found: $historyNodeOid");
    }

    final oidAndPathSet = <OidAndPath>{};
    for(final i in filesMap.data.values) {
      final fi = FileInfo.fromJson(i);
      oidAndPathSet.add(OidAndPath(oid: fi.getLatestVersion().oid, path: fi.path));
    }

    // 创建导出目录，若不创建，节点无文件或所有文件都是已删除时，就没导出目录了，感觉不合逻辑
    await getAndMakeSureDirExists(exportPath);
    final result = <ExportFailedItem>[];

    await restoreFiles(
      oidAndPathSet,
      progressCb: progressCb,
      throwIfInterrupted: throwIfInterrupted,
      outputPath: exportPath,
      objNotFoundHandler: (relativePath, oid) async {
        result.add(ExportFailedItem(relativePath: relativePath, oid: oid, errMsg: "obj not found"));
      }
    );

    return result;
  }

  // remote/filesBak/historyNodeOid.files.map.enc
  String genLocalFilesBakPath(String historyNodeOid) {
    return p.join(getRemoteDataDirPath(), Remote.filesBakDirName, Remote.genFilesMapNameByOid(historyNodeOid));
  }

  // 注：因为备份的files map是和history node oid关联的，所以这个 ver是history node oid，并不是files map的content id
  Future<DataMap?> downloadFilesMapByVer(String versionOid) async {
    final tempDir = await createTempDir("downloadFilesMapByVer");
    try {
      return await doActWithLocalLock(
        actName: "downloadFilesMapByVer",
        actDesc: "download specified version of files map",
        act: () async {
          // 先从本地找，若无则下载
          final localCachedFilesMapBakFile = await getFileAndMakeSureParentDirExist(genLocalFilesBakPath(versionOid));
          if(!await localCachedFilesMapBakFile.exists()) {
            await remote.doInit(tempDir, packMaxLen: await getEffectPackMaxLen());
            final tempFile = await tempDir.createTempFile();
            await remote.downloadToFile(remote.genRemoteFilesMapBakFilePath(historyNodeOid: versionOid), tempFile, tempDir);

            // 下载后移动到本地目录
            await tempFile.rename(localCachedFilesMapBakFile.absolute.path);
          }

          final contentKeyData = await getContentKey();
          return await DataMap.decrypt(contentKeyData, localCachedFilesMapBakFile);
        }
      );
    }finally {
      await tempDir.clean();
    }
  }

  // 做些需要开会话又不需要提交的任务
  // 注：对remote执行只读操作，不提交会话，但会提交本地和远程的同步缓存以确保数据最新
  Future<void> _doActWithRemoteSessionWithoutCommit({
    required String actName,
    required String actDesc,
    required KeyData contentKeyData,
    required ThrowIfInterrupted? throwIfInterrupted,
    required SyncProgressCb? progressCb,
    required TempDir tempDir,

    Future<bool> Function()? isLockRenewaling,
    Future<void> Function()? remoteSessionCommitBegin,
    Future<void> Function()? remoteSessionCommitEnd,

    required Future<void> Function() act,
  }) async {
    final emptyFilePath = "";
    progressCb?.call(SyncProgressAct.commitLocalSyncCache, 0, 0, emptyFilePath);

    // 先提交syncCache，确保本地数据最新（这步不能中断）
    await commitSyncCacheIfNeed();

    throwIfInterrupted?.call();

    progressCb?.call(SyncProgressAct.remoteReady, 0, 0, emptyFilePath);

    // 这里不用init remote，因为获取锁的时候init了，init一次就行，不然这里init会导致上传锁时用的token失效，就废了

    final sessionId = await remote.sessionStart(
      actName,
      actDesc,
      contentKeyData,
      tempDir,
      throwIfInterrupted: throwIfInterrupted,

      isLockRenewaling: isLockRenewaling,
      remoteSessionCommitBegin: remoteSessionCommitBegin,
      remoteSessionCommitEnd: remoteSessionCommitEnd,
      client: client,
    );

    throwIfInterrupted?.call();

    try {
      await act();
    }catch(e, st) {
      App.logger.debug(_TAG, "#_doActWithRemoteSessionWithoutCommit: $actName err: $e\n$st");
      progressCb?.call(SyncProgressAct.err, 0, 0, emptyFilePath);
      rethrow;
    }finally {
      await remote.sessionCancel(sessionId);
    }
  }

  Future<List<StatusItem>> status({
    ThrowIfInterrupted? throwIfInterrupted,
    SyncProgressCb? progressCb,
  }) async {
    // 先获取仓库本地锁，若获取失败，说明仓库正在执行操作，就不用获取远程锁了
    final localLockToken = LockToken(actName: "repoStatus", actDesc: "repo status to show local changes");
    final localLocked = lockLocalRepoByPath(path, localLockToken);
    if(localLocked != null) {
      throw RepoBusyException(actName: localLocked.actName, actDesc: localLocked.actDesc);
    }

    try {
      final tempDir = await createTempDir("status");
      try {
        return await _status(
          throwIfInterrupted: throwIfInterrupted,
          progressCb: progressCb,
          tempDir: tempDir,
        );
      }finally {
        await tempDir.clean();
      }
    }finally {
      freeLocalRepoLockByPath(path, localLockToken);
    }
  }

  Future<List<StatusItem>> _status({
    ThrowIfInterrupted? throwIfInterrupted,
    SyncProgressCb? progressCb,
    required TempDir tempDir,
  }) async {
    final String? remote;  // 屏蔽 变量名remote，避免误调用实例同名字段

    VirtualFile.reset();

    final index = await getIndex();
    final lastContentIdOfIndex = index.contentId;
    final contentKeyData = await getContentKey();
    final workdirBasePath = getWorkdirPath();

    final statusItems = <StatusItem>[];


    throwIfInterrupted?.call();

    final localFileMap = await getLocalFilesMap(contentKeyData);

    await findLocalChanges(
      index: index,
      lastContentIdOfIndex: lastContentIdOfIndex,
      newIndex: null,
      lastContentIdOfNewIndex: null,
      filesMap: localFileMap,
      contentKeyData: contentKeyData,
      workdirBasePath: workdirBasePath,
      throwIfInterrupted: throwIfInterrupted,
      progressCb: progressCb,
      tempDir: tempDir,
      isPathHandled: null,
      // 通过文件在仓库workdir下的相对路径计算出来的fileInfoOid
      getFileInfoForComputeHashTaskContextData: (VersionOid fileInfoOid) async {
        final fileInfoJsonMap = localFileMap.get(fileInfoOid);
        return fileInfoJsonMap == null ? null : FileInfo.fromJson(fileInfoJsonMap);
      },
      createNewNodeForModifiedAndAddedHandler: false,
      modifiedHandler: ({required String relativePathUnixStr, required int sizeInBytes, required File workdirFileEntity, required VersionNode? versionNode, required FileInfo fileInfoWillPush, required VirtualFile virtualFile}) async {
        if(fileInfoWillPush.curNode().oid.value == VersionOid.deleted.value) {
          statusItems.add(StatusItem.create(type: StatusItemType.added, relativePathUnderWorkdir: relativePathUnixStr, sizeInBytes: sizeInBytes));
        }else {
          statusItems.add(StatusItem.create(type: StatusItemType.modified, relativePathUnderWorkdir: relativePathUnixStr, sizeInBytes: sizeInBytes));
        }
      },
      addedHandler: ({required String relativePathUnixStr, required int sizeInBytes, required File workdirFileEntity, required VersionNode? versionNode, required VirtualFile virtualFile}) async {
        statusItems.add(StatusItem.create(type: StatusItemType.added, relativePathUnderWorkdir: relativePathUnixStr, sizeInBytes: sizeInBytes));
      },

      // pathOidStr可能用来下载对应的file info文件
      deletedHandler: ({required String path, required String pathOidStr}) async {
        // 这样其实有点浪费性能，如果在上面启动检测删除的task那个循环里，根据路径把FileInfo先存到map里，
        // 性能会更好，但是，如果平时删除的条目很少，那样有可能会浪费内存，我判断用户应该不会频繁删文件，
        // 所以选择目前这个性能可能比较差但省内存的方案，因为大多数情况下用户不会删文件或者删也不会删很多文件，
        // 所以要么根本不会执行到这里，要么就少数几个文件被删除了，然后执行到这而已，所以多数情况下都选择节省内存的方案更划算
        // 正常来说fileInfoJsonMap永远不会为null，因为对应条目本来就是从localFileMap遍历得来的，
        // 不过这里还是只做null check不做null断言（会抛异常），就算出错顶多就是文件大小有误而已（比如大小不该是0的却显示0），没必要抛异常
        final fileInfoJsonMap = localFileMap.get(await FilePath.fromString(path).toOid(contentKeyData));
        // 注意这里获取的是curNode而不是lastNode的大小，因为若文件status为已删除，那么之前的最新节点必然不是删除，所以获取其最新节点的大小即可
        final int size = fileInfoJsonMap != null ? FileInfo.fromJson(fileInfoJsonMap).curNode().fileSizeInBytes : 0;

        statusItems.add(StatusItem.create(type: StatusItemType.deleted, relativePathUnderWorkdir: path, sizeInBytes: size));
      },
      // file maybe updated, but no changes, so only need update modified time in index
      unmodifiedHandler: ({required String relativePathUnixStr, required File workdirFileEntity}) async {
        final oldItem = index.getByPathStr(relativePathUnixStr);
        if(oldItem == null) {
          return;
        }

        index.setByPathStr(
          relativePathUnixStr,
          oldItem.copyWith(mTimeMs: (await workdirFileEntity.lastModified()).millisecondsSinceEpoch),
          lastContentIdOfIndex,
        );
      }
  );

    if(index.contentId != lastContentIdOfIndex) {
      await writeIndex(index, getIndexPath());
    }

    return statusItems;
  }

  Future<void> findLocalChanges({
    required final Index index,  // 此函数不会修改此index，只会读取
    required final String lastContentIdOfIndex,
    required final Index? newIndex,
    required final String? lastContentIdOfNewIndex,  // 若newIndex为null，此值可传null
    required final DataMap filesMap,
    required final KeyData contentKeyData,
    required final String workdirBasePath,
    required final ThrowIfInterrupted? throwIfInterrupted,
    required final SyncProgressCb? progressCb,
    required final TempDir tempDir,
    required final Future<bool> Function(FilePath relativePath)? isPathHandled,
    // 通过文件在仓库workdir下的相对路径计算出来的fileInfoOid
    required final Future<FileInfo?> Function(VersionOid fileInfoOid) getFileInfoForComputeHashTaskContextData,
    required bool createNewNodeForModifiedAndAddedHandler,
    required final Future<void> Function({
      required String relativePathUnixStr,
      required int sizeInBytes,
      required File workdirFileEntity,
      required VersionNode? versionNode,
      required FileInfo fileInfoWillPush,
      required VirtualFile virtualFile,
    }) modifiedHandler,
    //can be update index item when check repo status
    final Future<void> Function({
      required String relativePathUnixStr,
      required File workdirFileEntity,
    })? unmodifiedHandler,
    required final Future<void> Function({
      required String relativePathUnixStr,
      required int sizeInBytes,
      required File workdirFileEntity,
      required VersionNode? versionNode,
      required VirtualFile virtualFile,
    }) addedHandler,  //新增的文件

    // pathOidStr可能用来下载对应的file info文件
    required final Future<void> Function({required String path, required String pathOidStr}) deletedHandler,
  }) async {
    int count = 0;
    int allCount = 0;
    // final emptyFilePath = FilePath();
    // 值是unix格式的filepath，用filePath.toMapKey()，比较合适，内部就是unixStr
    // 远程文件，在同步过程中，新增节点为 Deleted 的条目
    // 这个记录的是remote pfs将会删除的文件，但由于还没提交会话，
    // 所以remote的pfs实际还没删除，所以在查找应该更新成已删除的fileinfo时，会用到这个集合，
    // 跳过对应路径，因为对应条目提交时会标记为删除，所以此时就无需处理了
    // 遍历workdir查找untracked文件时，遍历与否这个都行，不会出错，但应该是没意义的，因为标记为删除的条目应该不会存在于workdir，否则就不会标记为删除

    throwIfInterrupted?.call();


    final filesMapDataValues = filesMap.data.values;
    count = 0;
    allCount = filesMapDataValues.length;
    progressCb?.call(SyncProgressAct.checkingDeletedItems, allCount, count, "");

    final bb = BytesBuilder(copy: false);
    await for(final b in contentKeyData.toByteStream()) {
      bb.add(b);
    }
    final contentKeyDataBytes = bb.takeBytes();

    int allCountNeedCheckDeleted = 0;
    final isolatePoolForCheckFileDeleted = await IsolatePool.create();
    try {
      // 查找那些已经记录到远程仓库，但后来文件被删除的那种条目
      // 更新已记录的文件为删除
      // 遍历pfs，找出所有没删除的，检查本地路径是否存在，若不存在，则标记为删除，不要用index来比较了，index一清，这个就不准了
      for(final jsonMap in filesMapDataValues) {
        throwIfInterrupted?.call();
        count++;
        progressCb?.call(SyncProgressAct.checkingDeletedItems, allCount, count, "");

        final remoteFileInfo = FileInfo.fromJson(jsonMap);

        final relativePath = FilePath.fromString(remoteFileInfo.path, isRelative: true);

        // 这种是刚才已经在上面的同步过程为remote file info创建了为Deleted的节点，
        // 属于已经检测过了，所以这里不用管，跳过即可
        // 若不跳过，重复检测，由于还是会从最新的pushCache里读取最新数据，所以【应该】实际不会出错，只是浪费性能？
        // 已处理过，跳过
        if(isPathHandled != null && await isPathHandled(relativePath)) {
          continue;
        }

        // 这里查找的是已删除的节点，如果已经是已删除，则跳过
        if(remoteFileInfo.curNode().oid.value == VersionOid.deleted.value) {
          continue;
        }


        // final workdirFileFullPath = p.join(workdirBasePath, relativePath.toString());


        isolatePoolForCheckFileDeleted.runCheckFileDeletedTask([
          workdirBasePath,
          relativePath.toString(),  // 要和 workdirBasePath 拼接，然后检查对应文件是否存在，所以这里用平台指定格式而不是unix styled path
          contentKeyDataBytes,
        ]);

        allCountNeedCheckDeleted++;
      }


      count = 0;
      allCount = allCountNeedCheckDeleted;
      isolatePoolForCheckFileDeleted.throwIfErr();

      await for(final List taskResult in isolatePoolForCheckFileDeleted.results()) {
        isolatePoolForCheckFileDeleted.throwIfErr();
        throwIfInterrupted?.call();

        count++;
        progressCb?.call(SyncProgressAct.checkingDeletedItems, allCount, count, "");

        final bool deleted = taskResult[0];
        if(!deleted) {
          continue;
        }

        await deletedHandler(
          path: taskResult[1],
          pathOidStr: taskResult[2],
        );
      }

      if(count != allCount) {
        throw AppException("handled count and all count didn't match: handled: $count, all: $allCount, err code: 15443485");
      }

    }finally {
      await isolatePoolForCheckFileDeleted.terminate();
    }


    throwIfInterrupted?.call();



    // 创建个新的index，不然已删除的文件的信息可能还会残留在index中

    // 推送untracked file和本地修改的文件
    final ignores = await getIgnores();
    count = 0;
    progressCb?.call(SyncProgressAct.checkingChanges, allCount, count, "");

    // 这个length不准，准不了，因为，扫描完之前不可能知道有多少文件
    allCount = index.length();

    final tempDirBasePath = tempDir.base.absolute.path;
    final isolatePool = await IsolatePool.create();
    final workdirResultNeedsData = <String, List>{};
    try {
      await forEachFiles(
        workdirBasePath,
        // item就是workdir目录下的文件
        (workdirFileEntity) async {
          throwIfInterrupted?.call();
          count++;

          // var relativePath = FilePath.fromString("!gen relative path failed!");

          // try {
          //
          // }catch(e) {
          //   syncResult.fails.add(FailedItem(relativePath: relativePath, errMsg: e.toString()));
          // }

          final workdirFileEntityPath = workdirFileEntity.absolute.path;

          final relativePath = FilePath.genRelativePath(workdirBasePath, workdirFileEntityPath);

          progressCb?.call(SyncProgressAct.checkingChanges, allCount, count, relativePath.toUnixPathStr());

          // 将来抽出单独方法判断是否忽略条目，并且支持用户增加忽略条目，如果可以，
          // x 不支持，我要搞个独立的ignore对象，上传到远程仓库，不用gitignore，兼容起来太麻烦) 支持.gitignore?
          // 只能忽略未同步过的文件，不能忽略已经同步的文件，若想忽略已经同步过的文件，需要先删除文件，再清file info
          // 支持通过后缀名、相对路径（一律用/分隔) 来忽略文件，是否支持通配符？考虑下
          // ignores里仅支持 '/' 路径分隔符的相对路径
          // x git的逻辑确实是，但我这个不是）已经被index追踪的不会跳过，所以"如果index不包含 且 忽略条目列表包含"，才会跳过
          // x git的逻辑确实是，但我这个不是）所以git如果想untrack一个文件，必须得remove from index，懂了
          // if(!index.contains(relativePath) && ignores.contains(relativePath.toUnixPathStr())) {
          if(SimpleIgnoreMatcher.shouldIgnore(ignores, relativePath.toUnixPathStr())) {
            return false;
          }

          // x 错误！如果文件名和数量均没变，只改变已存在文件的内容，目录的修改时间并不会变化！）如果父目录和索引匹配，其下文件无修改，直接跳过
          // if(item is File && parentMatchIndex) {
          //   return true;
          // }

          // 不是文件，是目录或者link或者unix sock，跳过
          // 这种不是文件的，如果之前有上传过fileInfo，会新增删除节点，
          // 但这里不用管，上面遍历pfs的时候会处理
          // 若没上传过对应fileInfo，无视即可
          if(!await isExistsFileForRepo(workdirFileEntityPath)) {
            return true;
          }

          if(workdirFileEntity is! File) {
            return true;
          }

          if(isPathHandled != null && await isPathHandled(relativePath)) {
            return true;
          }

          final indexItem = index.get(relativePath);

          // 注：假如以后要校验hash的话，不能直接算hash，要用keyData去算oid然后校验，
          // indexItem里存的是用contentKeyData和文件字节流算出的oid，不是单纯的hash
          if(indexItem != null && await indexItem.matchFile(workdirFileEntity)) {
            newIndex?.add(relativePath, indexItem, lastContentIdOfNewIndex);

            // 跟索引一样，没改过，不需要推送，忽略
            // 由于之前pull更新文件后会更新索引，
            //   所以，如果进到这里，
            //   要么文件一直和索引匹配，
            //   要么刚被pull更新过，
            //   如果是刚更新过，不需要push，因此，不用添加到workdirItems
            return true;
          }

          throwIfInterrupted?.call();

          //检查是否需要推送
          //计算hash



          isolatePool.runComputeHashTask([
            tempDirBasePath,
            workdirFileEntityPath,
            workdirBasePath,
            contentKeyDataBytes,
          ]);


          final fileInfoOid = await relativePath.toOid(contentKeyData);
          final fileInfo = await getFileInfoForComputeHashTaskContextData(fileInfoOid);

          workdirResultNeedsData[workdirFileEntityPath] = [
            fileInfo,
            relativePath,
            workdirFileEntity,
          ];

          return true;
        },
      );



      allCount = workdirResultNeedsData.length;
      count = 0;

      progressCb?.call(SyncProgressAct.checkingChanges, allCount, count, "");
      isolatePool.throwIfErr();
      // 内存换时间，不知道是否划算
      await for(final List taskResult in isolatePool.results()) {
        isolatePool.throwIfErr();
        throwIfInterrupted?.call();

        count++;
        final String hashOfWorkdirFile = taskResult[0];
        final int workdirFileCopyLen = taskResult[1];
        final virtualFile = VirtualFile.fromTransferableList(taskResult[2]);

        final String workdirFileEntityPath = taskResult[3];
        // 其实这相当于在手动恢复异步计算的上下文了。。。。。
        final List cachedData = workdirResultNeedsData[workdirFileEntityPath]!;
        final FileInfo? remoteFileInfo = cachedData[0];
        final FilePath relativePath = cachedData[1];
        final File workdirFileEntity = cachedData[2];  // 非File类型的FileSystemEntity都被跳过了，所以这里必然是File
        final relativePathUnixStr = relativePath.toUnixPathStr();

        progressCb?.call(SyncProgressAct.findingChanges, allCount, count, relativePathUnixStr);

        VersionOid? objOid;
        VersionNode? versionNode;
        if(createNewNodeForModifiedAndAddedHandler) {
          objOid = VersionOid(value: hashOfWorkdirFile);
          versionNode = VersionNode(oid: objOid, fileSizeInBytes: workdirFileCopyLen, client: client);
        }

        if(remoteFileInfo != null) {
          // modified
          // 更新远程的file info，本地最新的文件内容oid成为最新版本，可在通知中心或文件历史记录找到被覆盖的版本
          if(hashOfWorkdirFile != remoteFileInfo.getLatestVersion().oid.value) {
            await modifiedHandler(
              relativePathUnixStr: relativePathUnixStr,
              sizeInBytes: workdirFileCopyLen,
              workdirFileEntity: workdirFileEntity,
              versionNode: versionNode,
              // 同步时，modifiedHandler需要往这个file info添加新节点
              fileInfoWillPush: remoteFileInfo,
              virtualFile: virtualFile,
            );
          }else {
            // unmodified but reached here, that means
            // file not matched to old index item, maybe file updated but content no changed,
            // so we should update mTime of index item, then can avoid calculate hash
            // in next time sync or check status
            await unmodifiedHandler?.call(
              relativePathUnixStr: relativePathUnixStr,
              workdirFileEntity: workdirFileEntity,
            );
          }
        }else {
          // untracked
          // 新增文件，不需要传 fileInfoWillPush ，调用者若有需要，自己创建新的即可
          await addedHandler(
            relativePathUnixStr: relativePathUnixStr,
            sizeInBytes: workdirFileCopyLen,
            workdirFileEntity: workdirFileEntity,
            versionNode: versionNode,
            virtualFile: virtualFile,
          );
        }

        // 更新索引
        // 如果newIndex非null，应该是sync函数在调用本函数，这时，需要创建VersionNode，因此也会顺便创建objOid，所以它应该不为null
        // 如果newIndex为null，则应该是repo status函数调用本函数，这时，不需要创建VersioNode，objOid也为null，同时newIndex?.addFile根本不会被调用
        // 所以，objOid要么和newIndex一起为null，要么不被调用，因此把 objOid?.value ?? "" 改成 objOid!.value 也是可以的，
        // 但是，由于objOid在index中并不是必要字段，实际根据修改时间和大小来快速判断文件是否已修改，所以这里不对objOid做非空断言
        await newIndex?.addFile(relativePath, workdirFileEntity, objOid?.value ?? "", lastContentIdOfNewIndex);

        cachedData.clear();
      }

      if(count != allCount) {
        throw AppException("handled count and all count didn't match: handled: $count, all: $allCount, err code: 13092254");
      }


    }finally {
      workdirResultNeedsData.clear();
      await isolatePool.terminate();
    }


    throwIfInterrupted?.call();
  }

  // path is relative path under repo workdir
  Future<VersionNode?> getHeadNodeOfFile(String path) async {
    final tempDir = await createTempDir("getHeadNodeOfFile");
    try {
      final contentKeyData = await getContentKey();
      final FileInfo? fileInfo = await getTypedLocalData(
        RemoteDataType.files,
        await FileInfo.pathToOid(path, contentKeyData),
        getRemoteDataDirPath(),
        tempDir,
      );

      return fileInfo?.getLatestVersion();
    }finally {
      await tempDir.clean();
    }
  }

  Future<List<Glob>> getIgnores() async {
    final rules = <Glob>[];
    for(final i in Repo.defaultIgnorePathList) {
      rules.add(Glob(i));
    }

    final ignoreFile = await getIgnoreFile();
    if(await ignoreFile.exists()) {
      for(var line in await ignoreFile.readAsLines()) {
        try {
          line = line.trim();
          // 跳过空行和注释
          if(line.isEmpty || line.startsWith("#")) {
            continue;
          }

          // 非空行 且 非注释，添加
          rules.add(Glob(line));
        }catch(e) {
          App.logger.debug(_TAG, "invalid ignore line (invalid glob): line.length: ${line.length}, line: $line");
        }
      }
    }

    return rules;
  }

  String getIgnoreFilePath() {
    return p.join(path, ignoreFileName);
  }

  Future<File> getIgnoreFile({bool createIfNoExists = false}) async {
    final file = File(getIgnoreFilePath());
    if(createIfNoExists && !await file.exists()) {
      final sb = StringBuffer();
      // 这几个规则简单来说就是：忽略所有、忽略顶级目录、忽略非顶级目录所有、忽略非顶级目录下指定文件、忽略非顶级目录下的顶级目录的指定文件
      sb.write("# Lines starting with '#' are comments.\n");
      sb.write("# path/to/file/or/dir to ignore a file or dir (e.g., 'a.log', 'build', 'src/output')\n");
      sb.write("# **.log matches all .log files (e.g., 'a.log', 'abc/a.log')\n");
      sb.write("# *.log matches .log files in the root directory only (e.g., 'abc.log')\n");
      sb.write("# build/** matches all files within the 'build' directory (e.g., 'build/abc', 'build/def/abc.log')\n");
      sb.write("# dir/**.txt matches all .txt files in 'dir' and its subdirectories (e.g., 'dir/a.txt', 'dir/abc/a.txt')\n");
      sb.write("# dir/*.txt matches .txt files only in the top level of 'dir' (e.g., 'dir/a.txt', 'dir/b.txt')\n");

      await file.writeAsString(sb.toString(), flush: true);
    }

    return file;
  }

  Future<void> createKeepFileInEmptyDirsWithLock({
    ThrowIfInterrupted? throwIfInterrupted,
    SyncProgressCb? progressCb,
  }) async {
    await doActWithLocalLock(
      actName: "createKeepFile",
      actDesc: "create keep file to empty dirs",
      act: () async {
        await _createKeepFileInEmptyDirs(
          throwIfInterrupted: throwIfInterrupted,
          progressCb: progressCb,
        );
      }
    );
  }


  Future<void> _createKeepFileInEmptyDirs({
    ThrowIfInterrupted? throwIfInterrupted,
    SyncProgressCb? progressCb,
  }) async {
    progressCb?.call(SyncProgressAct.scanning, 0, 0, "");

    final ignores = await getIgnores();
    final emptyDirs = <Directory>[];
    final workdirBasePath = getWorkdirPath();
    await forEachFiles(
      workdirBasePath,
      // item就是workdir目录下的文件
      (workdirFileEntity) async {

        throwIfInterrupted?.call();

        if(workdirFileEntity is! Directory) {
          return false;
        }

        // 跳过忽略的目录
        if(SimpleIgnoreMatcher.shouldIgnore(ignores, FilePath.genRelativePath(workdirBasePath, workdirFileEntity.absolute.path).toUnixPathStr())) {
          return false;
        }

        bool isEmptyDir = true;
        // 如果一个目录只包含目录，那么不会在这个目录创建.keep，而是会在最末端的空目录创建，
        // 所以，这里只要进入for循环，就代表目录非空，包含文件或目录或别的都行，总之不会在其下创建keep文件
        await for(final f in workdirFileEntity.list(recursive: false, followLinks: false)) {
          isEmptyDir = false;
          break;
        }

        if(isEmptyDir) {
          // 放后面再添加，避免扫描时遍历到这个文件？我不确定遍历到是否会有除了性能外的影响，所以保险起见，在这只添加
          emptyDirs.add(workdirFileEntity);
        }

        return true;
      }
    );

    // 往所有新目录创建个空文件
    for(final d in emptyDirs) {
      throwIfInterrupted?.call();
      progressCb?.call(SyncProgressAct.creating, 0, 0, d.path);

      await File(p.join(d.absolute.path, ".keep")).create();
    }

    progressCb?.call(SyncProgressAct.done, 0, 0, "");

  }

  Future<void> cleanTempDirWithLocalLock({
    ThrowIfInterrupted? throwIfInterrupted,
    SyncProgressCb? progressCb,
  }) async {
    await doActWithLocalLock(
      actName: "cleanTempDir",
      actDesc: "clean temp dir",
      act: () async {
        await cancelableDelete(Directory(getTempDirBasePath()), throwIfInterrupted: throwIfInterrupted, progressCb: progressCb);
      }
    );
  }

  //清本地 cache/downCache 目录缓存的对象和 remote/objects 下缓存的对象
  // 不会清理cache/syncCache，那个目录设计上是需要最终被处理，所以不会手动清
  Future<void> cleanCachedDataWithLocalLock({
    required bool cleanDownloadCache,
    required bool cleanObjectsCache,
    ThrowIfInterrupted? throwIfInterrupted,
    SyncProgressCb? progressCb,
  }) async {
    if(!cleanDownloadCache && !cleanObjectsCache) {
      return;
    }

    await doActWithLocalLock(
      actName: "cleanCachedData",
      actDesc: "clean cached data",
      act: () async {
        if(cleanDownloadCache) {
          await cancelableDelete(Directory(getDownCacheDirPath()), throwIfInterrupted: throwIfInterrupted, progressCb: progressCb);
        }

        if(cleanObjectsCache) {
          await cancelableDelete(Directory(getRemoteObjectsDirPath()), throwIfInterrupted: throwIfInterrupted, progressCb: progressCb);
        }
      }
    );
  }

  Future<T> doActWithLocalLock<T>({
    required String actName,
    required String actDesc,
    required Future<T> Function() act,
  }) async {
    // 先获取仓库本地锁，若获取失败，说明仓库正在执行操作，就不用获取远程锁了
    final localLockToken = LockToken(actName: actName, actDesc: actDesc);
    final localLocked = lockLocalRepoByPath(path, localLockToken);
    if(localLocked != null) {
      throw RepoBusyException(actName: localLocked.actName, actDesc: localLocked.actDesc);
    }

    try {
      return await act();
    }finally {
      freeLocalRepoLockByPath(path, localLockToken);
    }
  }

  /// 清Index，然后返回空Index
  Future<Index> cleanIndex() async {
    final index = Index();
    await writeIndex(index, getIndexPath());
    return index;
  }

  Future<Index> cleanIndexWithLocalLock() async {
    return await doActWithLocalLock(
      actName: "cleanIndex", 
      actDesc: "clean index",
      act: cleanIndex,
    );
  }

  Future<RepoStatus> checkStatus({
    required ThrowIfInterrupted throwIfInterrupted,
  }) async {
    final actName = "checkStatus";
    final actDesc = "check repo status";
    final tempDir = await createTempDir("checkStatus");

    try {
      return await doActWithLocalLock(
        actName: actName,
        actDesc: actDesc,
        act: () async {
          final contentKeyData = await getContentKey();
          final index = await getIndex();
          final localFileMap = await getLocalFilesMap(contentKeyData);
          await findLocalChanges(
            index: index, // 此函数不会修改此index
            lastContentIdOfIndex: index.contentId,
            newIndex: null,
            lastContentIdOfNewIndex: null,
            filesMap: localFileMap,
            contentKeyData: contentKeyData,
            workdirBasePath: getWorkdirPath(),
            throwIfInterrupted: throwIfInterrupted,
            progressCb: null,
            tempDir: tempDir,
            isPathHandled: null,
            // 通过文件在仓库workdir下的相对路径计算出来的fileInfoOid
            getFileInfoForComputeHashTaskContextData: (VersionOid fileInfoOid) async {
              final fileInfoJsonMap = localFileMap.get(fileInfoOid);
              return fileInfoJsonMap == null
                ? null
                : FileInfo.fromJson(fileInfoJsonMap);
            },
            createNewNodeForModifiedAndAddedHandler: false,
            modifiedHandler: ({
              required String relativePathUnixStr,
              required int sizeInBytes,
              required File workdirFileEntity,
              required VersionNode? versionNode,
              required FileInfo fileInfoWillPush,
              required VirtualFile virtualFile,
            }) async {
              throw StatusDirtyException();
            },
            addedHandler: ({
              required String relativePathUnixStr,
              required int sizeInBytes,
              required File workdirFileEntity,
              required VersionNode? versionNode,
              required VirtualFile virtualFile,
            }) async {
              throw StatusDirtyException();
            },
            deletedHandler: ({required String path, required String pathOidStr}) async {
              throw StatusDirtyException();
            },
          );

          return RepoStatus(value: RepoStatusVal.clean);
        }
      );
    } on StatusDirtyException catch(_) {
      return RepoStatus(value: RepoStatusVal.dirty);
    } catch(e) {
      return RepoStatus(value: RepoStatusVal.err, msg: e.toString());
    } finally {
      await tempDir.clean();
    }
  }

  // 若仓库packSize有效，则使用，否则使用SyncConfig里的值
  // p.s. SyncConfig相当于全局设置
  Future<int> getEffectPackMaxLen() async {
    final repoConfig = await getConfig();
    if(repoConfig.packFileMaxLenInBytes > 0) {
      return repoConfig.packFileMaxLenInBytes;
    }
    return SyncConfig.getConfig().packFileMaxLenInBytes;
  }
}
