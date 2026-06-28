import 'dart:async';
import 'dart:convert' show utf8, jsonEncode, jsonDecode;
import 'dart:isolate';

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart' show App, UserInfo;
import 'package:cloud_disk_note_app/cloud_disk_note/client/client.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/crypto/encrypt.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/crypto/key_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/my_http_overrides.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/remote.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/oidlize.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/stream.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_path.dart' show FilePath;
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/config.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/temp/temp_dir.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/utils.dart' show writeStreamToFile;
import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/time/time_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart' show getJsonStrFromByteStream;
import 'package:cloud_disk_note_app/config/app_config.dart';
import 'package:cloud_disk_note_app/util/app_info.dart';

import '../../../main.dart';

part 'lock.g.dart';

const _TAG = "lock.dart";

// TODO 考虑改成多少比较合适，2分钟？或者让用户可调？
const defaultHoldTimeInMilliseconds = 180_000;
const autoRenewalIntervalInMs = 60_000;

@myJsonSerializable
class Lock implements JsonByteStream, Oidlize {

  // 这个oid决定锁的存储位置
  // 如果是仓库锁，常量oid，repoLock
  // 这个oid既是存锁的oid，也是资源oid，
  VersionOid oid;

  LockType type;

  // 具体什么数据，取决于lock type，可用from json转换为具体类型
  Map<String, dynamic> data;

  // 谁在占用锁，若oid不同，
  // 即使是同一设备发出的不同请求，也一样不能操作
  // 例如：设备a先执行了同步，未完成就执行另一个，第2个操作会因为锁oid不匹配而终止
  // 生成锁的时候一般随机生成这个oid
  VersionOid ownerOid;

  final bool autoRenewal;
  // 锁定的资源的oid
  // 如果锁定的是仓库，则为常量oid repoLock
  // VersionOid resourceOid;

  // 区分哪个客户端在执行操作
  Client client;

  // 任务名，例如 sync
  String actName;

  // 描述任务相关信息，例如：正在同步xx文件
  String actDesc;

  // 创建时间一旦创建永远不变
  final TimeData createAt;

  // 如果续期，这个时间会更新
  TimeData lockAt;

  //创建时间，加这个秒数，就是过期时间
  int expireAfterMilliseconds;

  @override
  Future<String> toOidStr(KeyData contentKeyData) async {
    return oid.value;
  }

  Lock({VersionOid? oid, LockType? type, Map<String, dynamic>? data, VersionOid? ownerOid, required this.client,
    TimeData? lockAt, TimeData? createAt, this.expireAfterMilliseconds = defaultHoldTimeInMilliseconds,
    this.autoRenewal = true,
    this.actName = '',
    this.actDesc = ''})
  : oid = oid ?? VersionOid(),
    type = type ?? LockType.repoLock,
    data = data ?? {},
    ownerOid = ownerOid ?? VersionOid.randomOid(),
    lockAt = lockAt ?? TimeData.now(),
    createAt = createAt ?? TimeData.now()
  ;


  factory Lock.fromJson(Map<String, dynamic> json) => _$LockFromJson(json);

  Map<String, dynamic> toJson() => _$LockToJson(this);


  static Lock newRepoLock({
    required Client client,
    String actName = '',
    String actDesc = '',
    bool autoRenewal = true,
    Map<String, dynamic>? data,
  }) {
    return Lock(
      oid: VersionOid.repoLock,
      type: LockType.repoLock,
      client: client,
      actName: actName,
      actDesc: actDesc,
      autoRenewal: autoRenewal,
      data: data
    );
  }

  static Future<Isolate> spawnNewLockTask(
    Remote srcRemote,
    RemoteConfig remoteConfig,
    KeyData contentKeyData,
    // 临时目录的basePath
    String tempDirBasePath,
    Client client,
    ReceivePort parentReceivePort, {
    // 例如 sync的时候调用，这个任务名可以是sync
    required String actName,
    required String actDesc,
  }) async {
    // 这样是为了让子线程可拷贝数据
    final remoteConfigJsonStr = jsonEncode(remoteConfig.toJson());
    // 用TransferableTypedData传字节貌似可避免拷贝？暂时用不上，没研究
    final contentKeyDataBytes = await contentKeyData.toBytes();
    final clientJsonStr = jsonEncode(client.toJson());

    final appConfigStr = jsonEncode(AppConfig.getConfig());
    int logLevel = App.logger.getLevel();
    bool devModeOn = App.devModeOn;
    final userCerts = MyHttpOverrides.userCerts;
    final remoteSupportAutoCreateNonexistsPath = srcRemote.supportAutoCreateNonexistsPath;
    final remoteNeedEndsWithSeparatorEvenPathIsFile = srcRemote.needEndsWithSeparatorEvenPathIsFile;
    final appVersion = AppInfo.version;
    final remoteLastGitPullAtInMs = srcRemote.lastGitPullAtInMs;
    final packMaxLen = srcRemote.packMaxLen;

    return await Isolate.spawn((SendPort parentSp) async {
      final rp = ReceivePort();

      final lockTempDir = await TempDir.create(
        tempDirBasePath,
        "lock_${actName}_",
      );


      void sendErrToParent(Object? err, StackTrace? st) {
        parentSp.send({"type": lockCmdErr, "err": err.toString(), "st": st.toString()});
      }


      try {
        await initSubIsolate();
        AppInfo.version = appVersion;  // http请求，user agent，会携带版本号，所以初始化下

        App.init(logLevel: logLevel, devModeOn: devModeOn);
        await AppConfig.setConfig(
          AppConfig.fromJson(jsonDecode(appConfigStr)),
          save: false,
        );

        MyHttpOverrides.initForIsolate(userCerts);

        parentSp.send(rp.sendPort);
        final client = Client.fromJson(jsonDecode(clientJsonStr));
        final repoLock = Lock.newRepoLock(
          client: client,
          actName: actName,
          actDesc: actDesc,
        );
        final remoteConfig = RemoteConfig.fromJson(
          jsonDecode(remoteConfigJsonStr),
        );
        // isChild 不是配置文件中的参数，是个额外参数，用来判断某个remote是否是派生的，
        // 如果是，则会有些限制，不能start session之类的，避免和主remote冲突
        final remote = await ConfigUtil.createRemoteFromConfig(
          remoteConfig,
          isChild: true,
          isLockUploader: true,
          // 避免主仓库刚git pull过，子仓库又拉
          lastGitPullAtInMs: remoteLastGitPullAtInMs,
        );

        remote.client = client;
        remote.sessionActName = actName;
        remote.sessionActDesc = actDesc;

        await remote.doInit(
          lockTempDir,
          determineResult: DetermineResult(
            supportAutoCreateNonexistsPath: remoteSupportAutoCreateNonexistsPath,
            needEndsWithSeparatorEvenPathIsFile: remoteNeedEndsWithSeparatorEvenPathIsFile
          ),
          packMaxLen: packMaxLen,
        );

        final contentKeyData = await KeyData.readFromStream(
          Stream.fromIterable([contentKeyDataBytes]),
        );

        Object? lockErrMsg;
        StackTrace? lockErrSt;
        final lockRenewalTask = await repoLock.tryLock(
          remote,
          contentKeyData,
          lockTempDir,
          lockFailedHandler: (Lock? holder, Object? error, StackTrace? st) {
            lockErrMsg = error;
            lockErrSt = st;
          }
        );

        // 没拿到锁
        if(lockRenewalTask == null) {
          // parentSp.send(lockCmdAcquireLockFailed);
          sendErrToParent(lockErrMsg, lockErrSt);
          return;
        }

        // 成功拿到了锁
        parentSp.send(lockCmdAcquireLockSuccess);

        bool finished = false;
        // 续锁成功后，等待主线程回复一个响应，若无恢复，说明只线程崩了，这时应取消任务
        Timer? renewalSuccessMainResponseTimer;
        final renewResponseTimeInSec = 10;
        bool remoteSessionCommitting = false;
        rp.listen((m) async {
          if(m == lockCmdFinished) {
            finished = true;
          }else if(m == lockCmdMainStillAliveResponse) {
            renewalSuccessMainResponseTimer?.cancel();
            renewalSuccessMainResponseTimer = null;
          }else if(m == lockCmdRemoteSessionCommitBegin) {
            remoteSessionCommitting = true;
          }else if(m == lockCmdRemoteSessionCommitEnd) {
            remoteSessionCommitting = false;
          }
        });

        final oneTimeDelay = 200; // ms
        // 每200毫秒检查一次finished，不然延迟太长
        final checkCount = lockRenewalTask.perMs / oneTimeDelay;
        outerLoop: while(!finished) {
          // 间隔几秒续一次锁，每次等待时间不能直接用续订时间，因为续订时间可能是几秒，
          // 但程序应该尽快检测到任务是否已经finished，所以这里拆分成比较短的时间单位，循环检查n次
          for(var i = 0; i < checkCount; i++) {
            // 每隔几毫秒检查一次任务是否已经完成
            await Future.delayed(Duration(milliseconds: oneTimeDelay));
            if(finished) {
              break outerLoop;
            }
          }

          while(remoteSessionCommitting) {
            // 避免在remote提交会话时上传锁（git backend需要，不然这边提交，那边也提交，会冲突）
            await Future.delayed(Duration(milliseconds: oneTimeDelay));
            if(finished) {
              break outerLoop;
            }
          }

          if(finished) {
            break outerLoop;
          }

          // 续锁
          // 据chatgpt说，这里的lockRenewalTask虽被闭包捕获，
          // 但其实是值拷贝，因此修改它不影响父线程的同名变量
          parentSp.send(lockCmdRenewalBegin);

          if(!await lockRenewalTask.renewal()) {
            lockRenewalTask.cancel();

            parentSp.send(lockCmdRenewalFailed);

            // 续锁失败，退出
            break;
          }else {
            // 续锁成功，给主线程发个信号，等回复，若无回复，则可能主线程崩了，应中止
            // 若timer不为null，说明上个事件还没收到响应，则不发新的信号，
            // 若主线程超时不应，最后会取消任务，若应，则再下次续锁成功后会发新的信号
            if(renewalSuccessMainResponseTimer == null) {
              parentSp.send(lockCmdRenewalSuccess);
              renewalSuccessMainResponseTimer = Timer(
                Duration(seconds: renewResponseTimeInSec),
                () {finished = true;}
              );
            }
          }

          parentSp.send(lockCmdRenewalEnd);

        }

        // 解锁
        parentSp.send(lockCmdRenewalBegin);
        await repoLock.unlockIfHeldByOur(remote, contentKeyData, lockTempDir);
        parentSp.send(lockCmdRenewalEnd);

        parentSp.send(lockCmdUnlocked);
      }catch(e, st) {
        sendErrToParent(e, st);
      }finally {
        await lockTempDir.clean();
        rp.close();
        // 在内部退出，不要在外部kill
        Isolate.exit();
      }


    }, 
    // 如果闭包不能捕获某些变量，可把这个参数改成map，例如：{"mainSp": mainSp, "otherParams": otherParams}
    parentReceivePort.sendPort);
  }

  FilePath genLockPath(Remote remote) {
    return remote.genRemoteLockPath(oid);
  }

  Future<AutoRenewalLockTask?> tryLock(
    Remote remote,
    KeyData keyData,
    TempDir tempDir, {
    LockFailedHandler? lockFailedHandler
  }) async {
    if(oid.value.isEmpty) {
      throw StateError("#tryLock() err: invalid empty lock oid");
    }

    // 以前分两个，后来发现用同一个就行
    final autoRenewalTaskTempDir = tempDir;

    final lockPath = genLockPath(remote);
    final exists = await remote.exists(lockPath);
    final tempLockFile = await tempDir.createTempFile();
    bool downloadLockSuccess = await remote.downloadToFileNoThrow(lockPath, tempLockFile, tempDir);

    var ourCreatedJustNow = false;
    // 没有人占用锁
    // 不存在且下载失败则创建锁
    if(!exists && !downloadLockSuccess) {
      // 远程几乎百分百没有锁（锁几乎百分百没被占用）

      // 上传
      await lockWithPath(remote, keyData, tempDir, lockPath);
      // 2次查询
      downloadLockSuccess = await remote.downloadToFileNoThrow(lockPath, tempLockFile, tempDir);

      // 下载还是失败
      if(!downloadLockSuccess) {
        lockFailedHandler?.call(null, "download remote lock failed, err code: 15219059", null);
        return null;
      }

      ourCreatedJustNow = true;
    }else if(exists && !downloadLockSuccess) {
      // 存在，但下载失败，可能网络不好
      lockFailedHandler?.call(null, "lock exists, but download failed, maybe network issue, please try again later, err code: 17070597", null);
      return null;
    }else if(!exists && downloadLockSuccess) {
      // 不存在但下载成功，可能锁正被别的客户端上传，然后又删了，也可能上传前临时删了之类的
      lockFailedHandler?.call(null, "lock doesn't exist but download successfully, maybe other client uploading lock?, err code: 12533702", null);
      return null;
    } // else if(exists && downloadLockSuccess) {}

    // 执行到这里，必然 '锁存在且下载成功'

    // 读取远程锁对象
    var encryptedLock = await EncryptedData.readFromFile(tempLockFile);
    var remoteLock = await fromJsonByteStream(await encryptedLock.decryptThenUncompress(keyData));

    void lockedByOtherOwner(String errCode) {
      lockFailedHandler?.call(remoteLock, "Locked by other owner: ${remoteLock.ownerOid.shortValue()}, clientName: ${remoteLock.client.name}, actDesc: ${remoteLock.actDesc}, err code: $errCode", null);
    }

    if(remoteLock.ownerOid == ownerOid) {
      if(ourCreatedJustNow) {
        // 锁是我方的，且是我方刚创建的，直接返回真
        return AutoRenewalLockTask(this, remote, keyData, autoRenewalTaskTempDir);
      }else {
        // x 废弃) 锁是我方的，但不是我方刚创建的，无条件续期
        // await _lockWithPath(remote, keyData, lockPath);

        // 已经锁定了，重复调用此方法，相当于重入了
        lockFailedHandler?.call(remoteLock, "doesn't support reentrant lock", null);
        return null;
      }
    }else {
      if(remoteLock.isExpired()) {
        // 锁不是我方的，但是过期了
        // 我方抢占
        await lockWithPath(remote, keyData, tempDir, lockPath);
      }else {
        // 锁不是我方的，且没过期
        lockedByOtherOwner("19065516");
        return null;
      }
    }

    // 二次查询
    downloadLockSuccess = await remote.downloadToFileNoThrow(lockPath, tempLockFile, tempDir);
    if(!downloadLockSuccess) {
      lockFailedHandler?.call(null, "download remote lock failed (2nd query)", null);
      return null;
    }

    encryptedLock = await EncryptedData.readFromFile(tempLockFile);
    remoteLock = await fromJsonByteStream(await encryptedLock.decryptThenUncompress(keyData));

    if(remoteLock.ownerOid == ownerOid) {
      return AutoRenewalLockTask(this, remote, keyData, autoRenewalTaskTempDir);
    }

    lockedByOtherOwner("11152898");
    return null;
  }

  Future<void> unlockIfHeldByOur(Remote remote, KeyData keyData, TempDir tempDir) async {
    if(oid.value.isEmpty) {
      throw StateError("#unlock() err: invalid empty lock oid");
    }

    // 查询次数
    // 查两次好像没啥意义？
    final count = 1;
    final lockPath = genLockPath(remote);

    // 有人占用锁，检查下，如果是我方，则取消占用
    final tempLockFile = await tempDir.createTempFile();

    // 查询
    for(var i = 0; i < count; i++) {
      var downloadLockSuccess = await remote.downloadToFileNoThrow(lockPath, tempLockFile, tempDir);
      // 锁文件可能不存在，代表没有人占用锁
      if(!downloadLockSuccess) {
        return;
      }

      // 读取远程锁对象
      var encryptedLock = await EncryptedData.readFromFile(tempLockFile);
      var remoteLock = await fromJsonByteStream(await encryptedLock.decryptThenUncompress(keyData));

      // 不是我方占用，返回
      if(remoteLock.ownerOid != ownerOid) {
        return;
      }
    }

    // 查完，是我方占用，解除
    await remote.deleteByOid(RemoteDataType.locks, oid, tempDir);
  }

  Future<void> lockWithPath(Remote remote, KeyData keyData, TempDir tempDir,FilePath lockPath) async {
    // 把锁定时间更新为现在最新时间
    lockAt = TimeData.now();

    final encryptedData = await EncryptedData.compressThenEncrypt(toJsonByteStream(), keyData);
    final tempFile = await tempDir.createTempFile();
    await writeStreamToFile(tempFile, encryptedData.toByteStream());
    await remote.uploadFile(lockPath, tempFile);
  }

  bool isExpired() {
    return TimeData.now().utcMs > lockAt.utcMs + expireAfterMilliseconds;
  }

  bool isAboutToExpired() {
    return TimeData.now().utcMs > lockAt.utcMs + expireAfterMilliseconds - 10;
  }


  static Future<Lock> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return Lock.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

}

@myJsonSerializable
class LockType {
  final int value;

  LockType({this.value = 0});


  factory LockType.fromJson(Map<String, dynamic> json) => _$LockTypeFromJson(json);

  Map<String, dynamic> toJson() => _$LockTypeToJson(this);


  // 会存到 locks/repoLock/data.enc 目录下
  static final repoLock = LockType(value: 1);
  // 拉取时，远程文件覆盖本地工作目录的文件
  // 会存到 locks/锁hash/data.enc 目录下，锁hash是资源的oid
  static final dirLock = LockType(value: 2);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LockType &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    return "$value";
  }


}

/// [holder] 锁的实际持有者
typedef LockFailedHandler = void Function(Lock? holder, Object? error, StackTrace? st);

// 获取锁成功
// 子线程发现已经lock续订已经取消
final String lockCmdRenewalFailed = "renewalFailed";
final String lockCmdRenewalSuccess = "renewalSuccess";
final String lockCmdRenewalBegin = "lockCmdRenewalBegin";
final String lockCmdRenewalEnd = "lockCmdRenewalEnd";
final String lockCmdRemoteSessionCommitBegin = "lockCmdRemoteSessionCommitBegin";
final String lockCmdRemoteSessionCommitEnd = "lockCmdRemoteSessionCommitEnd";
final String lockCmdMainStillAliveResponse = "lockCmdMainStillAliveResponse";
// 父线程操作执行完了，让子取消续订，只有父线程向子线程发送这个命令，没有子向父发
final String lockCmdFinished = "finished";
final String lockCmdAcquireLockSuccess = "acquire lock success";
final String lockCmdAcquireLockFailed = "acquire lock failed";
// 这个只有子线程向父发
final String lockCmdUnlocked = "unlocked";
// 消息有此前缀代表子线程出错了
final String lockCmdErr = "LockErr";


class AutoRenewalLockTask {
  Lock lock;
  Remote remote;
  KeyData keyData;
  TempDir tempDir;
  bool canceled = false;

  // 每隔几毫秒续一次
  int perMs;

  AutoRenewalLockTask(
    this.lock,
    this.remote,
    this.keyData,
    this.tempDir, {
    this.perMs = autoRenewalIntervalInMs,
  });

  ///返回值：是否续定成功
  Future<bool> renewal() async {
    if(canceled) {
      return false;
    }

    final lockPath = lock.genLockPath(remote);
    final tempLockFile = await tempDir.createTempFile();
    var downloadLockSuccess = await remote.downloadToFileNoThrow(lockPath, tempLockFile, tempDir);

    // 没有人占用锁
    if(!downloadLockSuccess) {
      // 上锁
      await lock.lockWithPath(remote, keyData, tempDir, lockPath);
      // 重新下载
      downloadLockSuccess = await remote.downloadToFileNoThrow(lockPath, tempLockFile, tempDir);

      // 若还为null，说明上锁失败
      if(!downloadLockSuccess) {
        cancel();
        return false;
      }
    }


    var encryptedLock = await EncryptedData.readFromFile(tempLockFile);
    var remoteLock = await Lock.fromJsonByteStream(await encryptedLock.decryptThenUncompress(keyData));

    if(remoteLock.ownerOid == lock.ownerOid) {
      // 续期
      await lock.lockWithPath(remote, keyData, tempDir, lockPath);
      return true;
    }

    cancel();
    return false;
  }

  void cancel() {
    canceled = true;
  }
}
