import 'dart:convert' show utf8, jsonEncode, jsonDecode;
import 'dart:io';
import 'dart:typed_data';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/app_key.dart';
import 'package:hahanote_app/hahanote_lib_sync/client/client.dart';
import 'package:hahanote_app/hahanote_lib_sync/crypto/encrypt.dart' show EncryptedData;
import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/obj_buf.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/session.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/datamap/data_map.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/empty_remote_impl.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/local_dir.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/pack/obj_pack.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/json.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/oidlize.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/stream.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/file_ext.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_info.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/virtual_file.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/msg/msg.dart' show Msg;
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/path_place_holder.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/repo.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync_history.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/related_oids.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';
import 'package:hahanote_app/hahanote_lib_sync/string_ext.dart';
import 'package:hahanote_app/hahanote_lib_sync/sync_config.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';
import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav_client;

part 'remote.g.dart';

const _TAG = "remote.dart";


// 目前只有webdav应用此值
const remoteConnectTimeoutInMs = 180_000;

// 值越大越省流量，但越有可能发生冲突，反之，费流量，但冲突的概率降低
// 1分钟续一次锁，拉太频繁也没意义
const gitPullIntervalInMs = 15_000;

// 之前允许上传空文件，后来pack文件加了magic，
// 已经实际上没有上传空文件的需求了，所以禁止上传空文件了
const allowUploadEmptyFile = false;

class DetermineResult {
  bool supportAutoCreateNonexistsPath;
  bool needEndsWithSeparatorEvenPathIsFile;

  DetermineResult({this.supportAutoCreateNonexistsPath = false, this.needEndsWithSeparatorEvenPathIsFile = false});

  @override
  String toString() {
    return 'DetermineResult{supportAutoCreateNonexistsPath: $supportAutoCreateNonexistsPath, needEndsWithSeparatorEvenPathIsFile: $needEndsWithSeparatorEvenPathIsFile}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is DetermineResult && runtimeType == other.runtimeType &&
              supportAutoCreateNonexistsPath ==
                  other.supportAutoCreateNonexistsPath &&
              needEndsWithSeparatorEvenPathIsFile ==
                  other.needEndsWithSeparatorEvenPathIsFile;

  @override
  int get hashCode =>
      Object.hash(
          supportAutoCreateNonexistsPath, needEndsWithSeparatorEvenPathIsFile);


}

class RemoteFile {
  bool isDir;
  String name;
  //基于远程仓库的根目录的绝对路径，之前是相对路径，后来改成绝对了，不过，具体还是取决于 path.isRelative 来判断
  FilePath path;
  // 最后修改时间，毫秒 since utc epoch
  int mTimeMs;
  // 若是目录，大小可能为0
  int length;
  RemoteFile({
    required this.isDir,
    required this.name,
    required this.path,
    required this.mTimeMs,
    required this.length
  });

  RemoteFile.empty({this.isDir = false, this.name = '', FilePath? path, this.mTimeMs = 0, this.length = 0})
    : path = path ?? FilePath();

  static Future<RemoteFile> fromFile(File file, FilePath path) async {
    return RemoteFile(
      isDir: false,
      name: p.basename(file.path),
      path: path,
      mTimeMs: (await file.lastModified()).millisecondsSinceEpoch,
      length: (await file.length())
    );
  }
  static Future<RemoteFile> fromDir(Directory file, FilePath path) async {
    return RemoteFile(
      isDir: true,
      name: p.basename(file.path),
      path: path,
      mTimeMs: (await file.stat()).modified.millisecondsSinceEpoch,
      length: 0
    );
  }

  static RemoteFile fromDropboxEntry(Map<String, dynamic> entry) {
    // dir没这字段，需要处理下
    final String? serverModified = entry["server_modified"];
    final int mtime;
    if(serverModified != null) {
      mtime = parseDateTime(serverModified).millisecondsSinceEpoch;
    }else {
      mtime = 0;
    }

    return RemoteFile(
      isDir: entry[".tag"] != "file",
      name: p.basename(entry["name"]),
      path: FilePath.fromUnixString(entry["path_display"]),
      mTimeMs: mtime,
      length: entry["size"] ?? 0
    );
  }

  static RemoteFile fromWebdavFile(webdav_client.File webDavFile) {
    return RemoteFile(
      isDir: webDavFile.isDir ?? false,
      // 取下basename，避免服务器返回的文件名其实是路径，之前有bug，就会这样
      name: p.basename(webDavFile.name ?? ''),
      path: FilePath.fromUnixString(webDavFile.path ?? ''),
      mTimeMs: webDavFile.mTime?.millisecondsSinceEpoch ?? 0,
      length: webDavFile.size ?? 0
    );
  }

  @override
  String toString() {
    return 'RemoteFile{isDir: $isDir, name: $name, path: $path, mTimeMs: $mTimeMs, length: $length}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is RemoteFile && runtimeType == other.runtimeType &&
              isDir == other.isDir && name == other.name &&
              path == other.path && mTimeMs == other.mTimeMs &&
              length == other.length;

  @override
  int get hashCode => Object.hash(isDir, name, path, mTimeMs, length);

}


class RemoteFileSimple {
  bool isDir;
  // 默认绝对路径
  FilePath path;
  RemoteFileSimple(this.isDir, this.path);

  @override
  String toString() {
    return 'RemoteFileSimple{isDir: $isDir, path: $path}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is RemoteFileSimple && runtimeType == other.runtimeType &&
              isDir == other.isDir && path == other.path;

  @override
  int get hashCode => Object.hash(isDir, path);


}

class RemoteType {
  String value;

  RemoteType({this.value = ''});

  // 避免remote为null，所以创建个空对象，实际没用
  static final empty = RemoteType(value: "empty");

  static final localDir = RemoteType(value: "LocalDir");
  static final dropbox = RemoteType(value: "Dropbox");
  // static final googleDrive = RemoteType(value: "GoogleDrive");
  // static final oneDrive = RemoteType(value: "OneDrive");
  // static final nextCloud = RemoteType(value: "NextCloud");
  static final webDAV = RemoteType(value: "WebDAV");

  static final supportedTypes = [
    dropbox,
    webDAV,
    localDir,  // 用于测试，或者用户可能本地目录是挂载的，比如本地目录是onedrive，设置可以用git做backend，如果不嫌麻烦的话
  ];

  static final supportedTypeValues = supportedTypes.map((t) => t.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is RemoteType && runtimeType == other.runtimeType &&
              value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    return value;
  }

  // 在UI显示的text
  String toText() {
    if(value == localDir.value) {
      return "$value (Git Supported)";
    }

    return value;
  }

}

class RemoteDataType {
  final String value;
  RemoteDataType({required this.value});

  static final objectsPfs = RemoteDataType(value: "objectsPfs");
  static final filesPfs = RemoteDataType(value: "filesPfs");
  static final msgPfs = RemoteDataType(value: "msgPfs");

  static final objects = RemoteDataType(value: "objects");
  static final files = RemoteDataType(value: "files");
  static final msg = RemoteDataType(value: "msg");
  static final locks = RemoteDataType(value: "locks");

  // 顺序不要乱，被依赖的放左边，(不过其实上传会先上传到缓存，所以就算顺序不是这样也没事)
  static final pfsTypes = [objectsPfs, filesPfs, msgPfs];

  // 不可变的数据类型，只要路径存在，就一定是最新的
  // 对于files来说，oid是其相对路径（unix格式）计算出的hash，即使关联的文件内容变化，oid也不会变，所以总是需要重新上传
  // 对于objects来说，目录名oid是其原始数据的hash，若一样，则代表原始数据一样，无需重复上传或下载（但加密后的文件会不同，因为有nonce和压缩包的时间戳）
  // 对于msg来说，oid是随机生成的，但每个msg一旦创建就不可修改，若修改则是删除旧的再创建新的，所以，若oid一样，也无需重复上传或下载
  bool isImmutable() {
    return this == RemoteDataType.objects || this == RemoteDataType.objectsPfs || this == RemoteDataType.msg || this == RemoteDataType.msgPfs;
  }

  bool isPfs() {
    return this == RemoteDataType.objectsPfs || this == RemoteDataType.filesPfs || this == RemoteDataType.msgPfs;
  }

  bool isNormalType() {
    return this == RemoteDataType.objects || this == RemoteDataType.files || this == RemoteDataType.msg || this == RemoteDataType.locks;
  }

  bool isLocalSupportedDataType() {
    // 本地不支持 lock 类型，因为没必要在本地存lock
    return this == RemoteDataType.objects || this == RemoteDataType.files || this == RemoteDataType.msg;
  }

  RemoteDataType? getPfsType() {
    if(value == objects.value) {
      return objectsPfs;
    }else if(value == files.value) {
      return filesPfs;
    }else if(value == msg.value) {
      return msgPfs;
    }else {
      return null;
    }
  }

  RemoteDataType? getNonPfsType() {
    if(value == objectsPfs.value) {
      return objects;
    }else if(value == filesPfs.value) {
      return files;
    }else if(value == msgPfs.value) {
      return msg;
    }else {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is RemoteDataType && runtimeType == other.runtimeType &&
              value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    return value;
  }


}


class SyncTaskType {
  static final renameBatch = "renameBatch";
}

class SyncTaskState {
  static final started = "started";
  static final finished = "finished";

}

@myJsonSerializable
class SyncTask {
  String type;
  String state;
  Map<String, dynamic> data;

  SyncTask({this.type = '', String? state, Map<String, dynamic>? data})
      : state = state ?? SyncTaskState.started,
        data = data ?? {};

  factory SyncTask.fromJson(Map<String, dynamic> json) => _$SyncTaskFromJson(json);

  Map<String, dynamic> toJson() => _$SyncTaskToJson(this);

}

@myJsonSerializable
class SyncTaskDataRenameBatch {
  List<FilePathPair> items;

  SyncTaskDataRenameBatch({List<FilePathPair>? items})
      : items = items ?? [];

  factory SyncTaskDataRenameBatch.fromJson(Map<String, dynamic> json) => _$SyncTaskDataRenameBatchFromJson(json);

  Map<String, dynamic> toJson() => _$SyncTaskDataRenameBatchToJson(this);

}

@myJsonSerializable
class SyncCacheInfo implements JsonByteStream {
  int ver;
  List<SyncTask> tasks;

  SyncCacheInfo({this.ver = 1, List<SyncTask>? tasks})
      : tasks = tasks ?? [];

  factory SyncCacheInfo.fromJson(Map<String, dynamic> json) => _$SyncCacheInfoFromJson(json);

  Map<String, dynamic> toJson() => _$SyncCacheInfoToJson(this);

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

  static Future<SyncCacheInfo> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return SyncCacheInfo.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  static Future<SyncCacheInfo> decrypt(KeyData contentKeyData, File file) async {
    final encryptedData = await EncryptedData.readFromFile(file);
    final rawData = await encryptedData.decryptThenUncompress(contentKeyData);

    return await fromJsonByteStream(rawData);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SyncCacheInfo && runtimeType == other.runtimeType &&
              ver == other.ver &&
              listEquals(tasks, other.tasks);

  @override
  int get hashCode => Object.hash(ver, tasks);

  @override
  String toString() {
    return 'SyncCacheInfo{ver: $ver, tasks: $tasks}';
  }

  void addTask(SyncTask syncTask) {
    tasks.add(syncTask);
  }


}

///注意：remote内部函数返回的remotexxxPath一般都是remote可用的绝对路径，也能返回相对路径，
/// 但是那样外部调用者还得手动处理才能获得绝对路径，不太方便，比如local_dir实现，我想看下某个文件的路径，这时期望的一般是绝对路径；
/// 外部调用remote系列函数时，一般传相对路径，可通过path.isRelative来判断，也可传绝对路径，但外部调用者得手动追加basePath，不太方便，
/// 目前是怎么方便怎么来，虽然行为不统一，但通过preHandlePath()处理过也能用，没bug最好别改。
abstract class Remote implements ClosableSession {
  static final cacheDirName = "cache";
  static final syncCacheDirName = "syncCache";
  // cache/syncCache/info.enc
  // 里面记录了把files里的文件重命名到哪
  static final syncCacheInfoFileName = "info.enc";
  static final syncCacheReadyFileName = "ready.enc";
  // cache/syncCache/files
  static final syncCacheFilesDirName = "files";

  // pfs/files|objects|msg/pfs.enc|N.pack
  static final pfsDirName = "pfs";
  static final pfsFileName = "pfs.enc";

  static final String objMapFileName = "objMap.enc";

  // sessionStorage key
  static final keyWillDelFiles = "keyWillDelFiles";
  static final keyWillDelObjs = "keyWillDelObjs";
  static final keyWillDelMsg = "keyWillDelMsg";

  static final keyEncFilesPfsPath = "keyEncFilesPfsPath";
  static final keyEncObjectsPfsPath = "keyEncObjectsPfsPath";
  static final keyEncMsgPfsPath = "keyEncMsgPfsPath";
  static final keyEncMsgMapPath = "keyEncMsgMapPath";
  static final keyEncFilesMapPath = "keyEncFilesMapPath";

  // 有时候会从父配置创建子remote在其他Isolate运行，但只需要主remote执行初始化，
  // 所以需要区分下是否是child
  // 例如：dropbox，主remote需要续accessToken，但子不能续，否则主的会失效
  // 注：带 get 的字段之所以能override是因为其是getter函数，若是普通字段，不能override，父类和子类各用各的字段，
  //     简单来说，子类可覆盖父类行为，不能覆盖属性
  bool get isChild;
  /// local/ftp/sftp/webdav/onedrive/google drive/ etc
  RemoteType get type;

  // 若是专门上传lock的remote，会做一些差异处理，
  // 例如git，对lock uploader remote，每次上传都会执行推送，
  // 对主remote则只会在commitSession时才执行
  bool get isLockUploader;

  /// 若 false，可能在preHandlePath()时调用remote.mkdir()自动创建目录（还有其他参数协助判断，
  /// 由于调用remote.mkdir()会多发请求，所以如无必要，尽量不调用，而是先尝试直接执行操作若失败再尝试建目录再操作
  /// 参见：[doActIfErrAndDontSupportAutoMkdirsThenMkdirsThenTryAgain]）
  /// 如不确定，应设为false，然后在uploadFile/rename/copy这种需要中间目录存在的函数中
  /// 调用 [doActIfErrAndDontSupportAutoMkdirsThenMkdirsThenTryAgain] 来处理
  bool get supportAutoCreateNonexistsPath;
  // 据我测试，有的webdav平台（例如日本的infiniteCloud），即使目标是文件，末尾也许要 / ，
  // 所以用这个变量控制下 _appendPathSeparatorIfIsDir 的行为，
  // 此变量若true，一律确保末尾添加 /，否则dir添加，file不添加
  bool needEndsWithSeparatorEvenPathIsFile = false;

  // 必须得是绝对路径 basePath.isRelative must be false，否则可能会在preHandle时追加前置路径
  abstract FilePath basePath;

  abstract String pathSeparator;

  // PackFileStorage? filesPfs;
  ObjPackFileStorage? objectsPfs;
  FindResultMap? objPfsFindResultMap;
  // PackFileStorage? msgPfs;
  String lastFilesPfsContentId = '';
  String lastObjectsPfsContentId = '';
  String lastMsgPfsContentId = '';

  // 话说这个好像只在远程，本地用不到？
  // ObjMap? objMap;
  // String lastObjMapContentId = '';

  // 本来是用来实现untrack文件和ignore文件用的，但后来发现不用，
  // 但远程需要一个ignore文件，独立于所有设备，每次sync前fetch远程的ignore文件，
  // 取出ignore列表，忽略文件时也要更新对应文件，不过index就不需要了，
  // 日后实现忽略机制时，替换成ignore文件
  // Index? index;
  // static final indexFileName = "index.enc";  //TODO 将来改成ignore.enc
  // String lastIndexContentId = '';

  // 会话若不变，下载的pack不用重复计算hash
  /// 注：这个sessionId和上传时记录的sessionId不是同一个
  String currentSessionId = '';
  String sessionActName = '';
  String sessionActDesc = '';
  // 在最后调用renameBatch前，都能rollback
  // 但由于后来改成上传到syncCache，若成功，则下次继续任务，若失败，下次清理，因此不需要手动
  // 回滚了，所以这个函数并没什么用了，仅用来指示当前状态是否是可回滚
  bool sessionCanRollback = false;
  Map<String, dynamic> sessionStorage = {};
  ThrowIfInterrupted? throwIfSessionInterrupted;

  // files和msg只包含应用产生的元数据，比较小，直接存单文件map
  // obj则包含二禁止文件，所以用pack打包管理
  static final mapDirName = "map";
  static final filesMapFileName = "files.map.enc";
  static final msgMapFileName = "msg.map.enc";
  // 存储files 版本历史的目录，文件名格式为 "$historyNodeOid.$filesMapFileName"
  // 例如："abc123...省略.files.map.enc"
  static const filesBakDirName = "filesBak";
  DataMap? filesMap;
  String lastFilesMapContentId = "";
  DataMap? msgMap;
  String lastMsgMapContentId = "";

  // Map<String, Set<ObjRef>>? _objAddRefsMap;  // add ref
  // Map<String, Set<String>>? _objDeRefsMap;  // remove ref

  // objOid: fileInfo/msgOid's ref count
  // 增加引用，计数加1，减少引用，减1，ref count 可能是负数，最终和obj pfs里的ref count相加，若结果小于0则移除obj
  Map<String, int>? _objAddRefsCountMap; // add/remove ref count
  // Map<String, Map<String, int>>? _objDeRefsCountMap;  // remove ref count


  // 相当于内存版的 tempDir.pushCacheDir()
  // 同步时，session commit，执行push时，
  // 如果小文件或objBuf没满，push时把文件字节存到这个对象里；
  // 否则存到 tempDir.pushCacheDir()
  // 存储逻辑参见：remote._pushDataToCache()
  // 所有检查 tempDir.pushCacheDir() 是否有某个文件的代码，都应同时检查文件是否在此buf里（用文件oid从buf找值）
  ObjBuf? _objBuf;

  int packMaxLen = defaultPackFileMaxLenInBytes;



  Future<bool> Function()? isLockRenewaling;
  Future<void> Function()? remoteSessionCommitBegin;
  Future<void> Function()? remoteSessionCommitEnd;

  int lastGitPullAtInMs = 0;

  Client? client;

  Future<void> necessaryCheck() async {
    if(basePath.isRelative) {
      throw RemoteException("basePath must be absolute");
    }
  }

  /// 注意：子类在重写此函数时，应首先调用 super.doInit() ，会执行些必须的检测，避免remote有误
  // 执行一些必须的最小化的初始化任务，不开会话也能用
  // 例如创建客户端、刷新token，都可放到这里
  // 注：这个tempDir应该在doInit执行完毕后可清理，不要往里面放重要的东西，doInit和session应使用不同的tempDir，避免依赖
  Future<void> doInit(
    TempDir tempDir, {
    DetermineResult? determineResult,
    // remote能用后，执行探测或其他操作前，调用此函数，
    // 可在创建仓库时用来检测仓库是否存在之类的（因为探测时会创建临时文件，所以若放到探测后再检测仓库是否存在会不准确）
    // 若返回true，继续执行初始化，否则取消执行后续代码（return）
    // 建议遵循根据返回值决定是否终止init，但直接在onReady里抛异常来终止init也行，由调用者自己决定
    Future<bool> Function(Remote)? onReady,
    required int packMaxLen,
  }) async {
    await necessaryCheck();
    this.packMaxLen = packMaxLen;
  }

  /// 必须先拿到远程的lock，才能开始 session，否则若多设备同时同步，会冲突导致数据错乱
  /// 每次调用sync前，应先reset
  /// 执行同步操作必须自行确保传给fetch/push系列函数的是相同的tempDir，否则可能出现重复下载数据的问题
  /// sessionTempDir不要和普通操作用相同的tempDir，应单独创建一个（不过设计上用一个也不会冲突），其使用fetchCache和pushCache目录存储下载的.pack文件和缓存待上传的用户文件
  /// 调用remote前应先创建session，否则fetchData、pushData无法正常工作
  /// [actName] 代表操作名，[actDesc] 代表操作描述，当一个session未销毁就创建另一个时，会报错，并返回actName和actDesc
  /// 同一个session 期间，应该使用同一个tempDir实例
  Future<String> sessionStart(
    final String actName,
    final String actDesc,
    final KeyData contentKeyData,
    final TempDir tempDir, {
    // 可用来取消下载
    required final ThrowIfInterrupted? throwIfInterrupted,
    // 若会话需要执行的操作不需要pfs和objMap，则传假即可，
    // 例如若更新master key时重新上传contentKey和masterKeyExtra，
    // 则不需要下载这两个东西
    final bool requireFetchObjPfs = true,
    final bool requireFetchFilesMap = true,
    final bool requireFetchMsgMap = true,

    // final bool requireFetchObjMap = true,

    // 如果是单纯下载文件，不想管syncCache的事，这个传false
    final bool commitSyncCache = true,
    // 这里接收的是会被复用的tempDir里的文件，可拷贝，但不要move或rename，否则影响后续remote的操作
    // Future<void> Function(File? pfsFile)? latestObjPfsFileReceiver,



    required Future<bool> Function()? isLockRenewaling,
    required Future<void> Function()? remoteSessionCommitBegin,
    required Future<void> Function()? remoteSessionCommitEnd,
    required Client client,
  }) async {
    if(sessionStarted()) {
      throw RemoteBusyException(actName, actDesc, "remote busy now, please try again later: act: $actName, desc: $actDesc");
    }


    // 初始化session相关变量
    final newSessionId = randomString(32);
    sessionActName = actName;
    sessionActDesc = actDesc;
    currentSessionId = newSessionId;
    sessionCanRollback = true;
    sessionStorage.clear();
    throwIfSessionInterrupted = throwIfInterrupted;
    this.client = client;

    // 目前20260329只有git backend才需要这些东西
    if(type.value == RemoteType.localDir.value && (this as LocalDir).config.isGitBackend) {
      this.isLockRenewaling = isLockRenewaling;
      this.remoteSessionCommitBegin = remoteSessionCommitBegin;
      this.remoteSessionCommitEnd = remoteSessionCommitEnd;
    }

    // _objAddRefsMap = {};
    // _objDeRefsMap = {};
    _objAddRefsCountMap = {};

    _objBuf = ObjBuf();

    // 初始化可能出错的变量
    Future<String> doUnsafeAct() async {
      if(commitSyncCache) {
        // 尝试关闭上次未完成的上传会话，若不关，可能会占用用户的存储空间配额？
        // 这个没什么用，dropbox，不用关，也没关的接口，应该不会占用配额，无所谓
        await closeUnfinishedSession();
        // 检查是否有未完成的同步任务，有的话继续处理，然后再开始新的同步
        await commitSyncCacheIfNeed(contentKeyData, tempDir, throwIfNonExists: false);
        // 清下远程临时目录
        await deleteIfExists(remoteTempRootPath(), isDir: true);
      }

      final downTasks = <Future Function()>[];
      // pfs 会存到fetchCache里, fetchCache/files/pfs.enc fetchCache/objects/pfs.enc fetchCache/msg/pfs.enc
      // 需要推送的数据会放到pushCache里，例如 pushCache/files|objects|msg/oid/data.enc
      // 两个cache 共用一个tempDir
      if(requireFetchObjPfs) {
        downTasks.add(() => fetchObjectsPfs(contentKeyData, tempDir));
        // await latestObjPfsFileReceiver?.call(objPfsFile);
      }

      if(requireFetchFilesMap) {
        downTasks.add(() => fetchFilesMap(contentKeyData, tempDir));
      }

      if(requireFetchMsgMap) {
        downTasks.add(() => fetchMsgMap(contentKeyData, tempDir));
      }

      await runTaskConcurrencyIfAllow(downTasks, isRead: true);

      return currentSessionId;
    }

    // 若出错取消会话，不然再执行会提示remote busy
    try {
      return await doUnsafeAct();
    }catch(e) {
      await sessionCancel(newSessionId);
      rethrow;
    }

  }

  /// 当只下载或查询但不上传的时候，可以sessionStart，然后cancel即可
  /// 示例：
  /// try {
  ///   await remote.sessionStart();
  ///   remote.downloadFile();
  ///   await remote.listFiles();
  /// }finally {
  ///   await remote.sessionCancel();
  /// }
  ///
  /// 如果需要提交的时候，则：
  /// try {
  ///   await remote.sessionStart();
  ///   remote.downloadFile();
  ///   await remote.listFiles();
  ///   // 若提交成功会自动重置会话
  ///   await remote.sessionCommit();
  /// }catch(e) {
  ///   // 若提交失败，则在这里手动取消会话
  ///   await remote.sessionCancel();
  ///   rethrow;
  /// }
  Future<void> sessionCancel(String sessionId, {bool throwIfErr = false}) async {
    try {
      _sessionCheck(sessionId, "session cancel", 13014690);
      await _sessionReset();
    }catch(e, st) {
      if(throwIfErr) {
        rethrow;
      }

      // 若抛了这就不用记了，没抛就记下错误
      App.logger.debug(_TAG, "sessionCancel err: $e, st: $st");
    }
  }

  /// 注：在改成把文件先上传到syncCache后移动到正式目录后，这个rollback与否其实无所谓了，若提交出错，执行下sessionCancel即可
  /// 在sync发生异常时执行。
  /// 不会推送数据，但fetch到本地和push到cache时拷贝到本地
  /// objects和files目录的文件不会撤回，若未修改的情况下再次执行同步将会上传这些文件
  /// 返回回滚成功还是失败，若无异常且返回true，则回滚成功
  @Deprecated("在改成把文件先上传到syncCache后移动到正式目录后，这个rollback与否其实无所谓了，若提交出错，执行下sessionCancel即可")
  Future<bool> sessionRollback(
    String sessionId,
    SyncHistory? latestSyncHistoryWhichIncludedCurrentNode,
    VersionOid? expectSyncHistoryNodeOid,
    KeyData contentKeyData,
    TempDir tempDir
  ) async {
    _sessionCheck(sessionId, "session rollback", 13095431);

    bool result = false;

    // 如果能回滚，说明还没提交数据到远程仓库正式目录（可能已经上传到临时目录），
    //  这时，删除最新的一条同步历史再上传即可，对其他设备来说，就等于没变化，
    //  不用同步（因为当前设备没上传数据），对当前设备来说，下次依然从上次的节点开始增量同步（避免了全量同步的性能问题）
    // 但是注意：及时回滚成功，本地workdir和fileinfo、objects，依然有可能被修改，会在下次同步时把本地有的远程无的上传，
    // 工作目录的文件，下次同步时，会再走一遍同步流程，如果需要上传则会上传对应文件
    if(sessionCanRollback) {
      // 避免重入
      sessionCanRollback = false;

      // 回滚syncHistory，然后上传
      if(latestSyncHistoryWhichIncludedCurrentNode != null && expectSyncHistoryNodeOid != null) {
        // 对syncHistory执行回滚
        latestSyncHistoryWhichIncludedCurrentNode.rollback(expectSyncHistoryNodeOid);

        // 上传回滚后的syncHistory
        // 这个回滚的意义在于让syncHistory没有未完成的节点（state保持在started的节点），
        // 这样的话下次就不会全量同步了
        final encData = await EncryptedData.compressThenEncrypt(latestSyncHistoryWhichIncludedCurrentNode.toJsonByteStream(), contentKeyData);
        final tempFile = await tempDir.createTempFile();
        await writeStreamToFile(tempFile, encData.toByteStream());
        await uploadFile(getRemoteSyncHistoryPath(), tempFile);
      }

      // 删除cache/syncCache目录
      await deleteIfExists(remoteSyncCacheRootPath(), isDir: true);

      // 删除远程临时目录
      await deleteIfExists(remoteTempRootPath(), isDir: true);

      // 回滚成功
      result = true;
    }

    await _sessionReset();

    return result;
  }

  Future<void> sessionCommit(
    String sessionId,
    KeyData contentKeyData,
    TempDir tempDir, {
    // 注：如果force为真，即使是不可变类型，也会删了重新上传，否则会跳过
    bool force = false,
    // 上传完文件后，不能回滚后，执行的任务
    Future<void> Function()? afterUploaded,

    // 自定义任务的作用：调用 `uploadFileToSyncCache()` 上传文件到syncCache，然后返回文件名和正式路径的path pair列表，
    // 任务成功完成后，本函数会创建info文件，随后若任务中断，后续客户端会继续执行未完成的任务
    // 若此参数为null将会执行默认的task，即sync相关的操作；若不为null，将会执行本函数，
    // 默认sync相关的操作将不会被执行
    // 这个参数的应用场景：例如需要修改主密码，这时就需要开启会话，但其实并不需要执行同步想关的操作
    Future<List<FilePathPair>> Function()? customTask,

    required ThrowIfInterrupted? throwIfTaskCanceled,
    // encPfsPath 是加密过的pfs的.enc文件的本地路径，在临时目录里，清tempDir前有效
    // 调用此函数会把tempDir里的文件移动到对应目录，所以调用后encPfsPath就无效了
    required Future<void> Function(
      RemoteDataType pfsType,
      String? encPfsPath,
      // 如果路径无效，则会使用最新的pfs创建最新的pfs.enc文件
      ObjPackFileStorage latestPfs,
      KeyData contentKeyData,
      TempDir tempDir
    )? latestPfsFileHandler,
    required Future<void> Function(DataMap? filesMap, KeyData contentKeyData, TempDir tempDir)? latestMsgMapHandler,
    required Future<void> Function(DataMap? filesMap, KeyData contentKeyData, TempDir tempDir)? latestFilesMapHandler,
    String? newSyncHistoryNodeOid,
  }) async {
    _sessionCheck(sessionId, "commit session", 13552069);


    Future<List<FilePathPair>> syncTask() async {
      // 这个只会下载pfs到本地，然后删除条目，实际不会上传东西
      // await _flushDelCache(tempDir, throwIfTaskCanceled: throwIfTaskCanceled);

      // 这个会实际上传，包含上面删除过条目的pfs，最后返回待重命名的文件列表
      return await _flushPushCache(
        contentKeyData,
        tempDir,
        force: force,
        throwIfTaskCanceled: throwIfTaskCanceled,
        newSyncHistoryNodeOid: newSyncHistoryNodeOid,
      );
    }

    // 这个好不好使，真难说，有待测试
    throwIfTaskCanceled?.call();


    throwIfTaskCanceled?.call();

    if(App.devModeOn) {
      // 在处理，还没上传，需要下载pack文件
      App.logger.info(_TAG, "profile: gathering push files, start: ${DateTime.now().millisecondsSinceEpoch}");
    }

    final pushedPaths = await (customTask?.call() ?? syncTask());

    if(App.devModeOn) {
      App.logger.info(_TAG, "profile: gathering push files, end: ${DateTime.now().millisecondsSinceEpoch}");
    }

    // 最后的中断检查
    throwIfTaskCanceled?.call();

    // 刚才是把pfs.enc和.pack文件们上传到了remote的cache/syncCache目录，现在把刚才推送的文件重命名到正式目录，执行到这就不能回滚了
    // x 废弃，后来改成了最终一致性的实现，废弃回滚了，现在只要上传数据完成，一律当作不能回滚，但在最后一个包含重命名信息的的文件上传前一律都是可中断的）：在重命名之前都是能回滚的，但之后就不能了
    sessionCanRollback = false;

    // 后面就不能中断也不能回滚了


    // 若一个都没推送，就不用提交了，否则提交
    if(pushedPaths.isNotEmpty) {

      if(App.devModeOn) {
        App.logger.info(_TAG, "profile: pushing files, start: ${DateTime.now().millisecondsSinceEpoch}");
      }
      // 上传完所有文件到 syncCache/files 目录后，上传 syncCache/info.enc，然后重命名文件，最后删除syncCacheInfoPath
      // 下次上传前检测这个文件是否存在，假如存在，说明上次在所有文件都上传完毕后，可能没有把所有文件都成功移动到正式目录，
      // 可能停电了或者怎样，根据文件里的信息继续移动文件即可
      await uploadSyncCacheInfo(contentKeyData, pushedPaths, tempDir);

      if(App.devModeOn) {
        App.logger.info(_TAG, "profile: pushing files, end: ${DateTime.now().millisecondsSinceEpoch}");
      }
      if(App.devModeOn) {
        App.logger.info(_TAG, "profile: committing remote sync cache, start: ${DateTime.now().millisecondsSinceEpoch}");
      }
      // await commitSyncCacheIfNeed(contentKeyData, tempDir, throwIfNonExists: true);
      await commitSyncCacheForPush(contentKeyData, tempDir, pushedPaths);
      if(App.devModeOn) {
        App.logger.info(_TAG, "profile: committing remote sync cache, end: ${DateTime.now().millisecondsSinceEpoch}");
      }
    }


    //// BEGIN: update local pfs file

    // 注：在提交远程文件前调用处理本地的函数其实也行，但是不保险，万一上传文件没报错，但实际上上传失败呢？
    // 虽然一般不会。先确认远程处理完毕，再覆盖本地，一般ok，最坏的情况顶多就是远程更新完了，本地文件没更新，导致下次同步，
    // 后用远程最新数据覆盖本地文件，workdir若没修改过，没问题，若在上传完成后，下次同步前修改过workdir的文件，则可能会发生冲突，
    // 但这个后果可以接受，比本地和远程不一致要强。

    if(App.devModeOn) {
      App.logger.info(_TAG, "profile: pfs handler, start: ${DateTime.now().millisecondsSinceEpoch}");
    }
    // 远程上传完了，处理本地
    // latestPfsFileHandler和afterUploaded的调用顺序不能换，不然还没拷贝pfs就以为任务完成了
    await latestPfsFileHandler?.call(
      RemoteDataType.objectsPfs,
      sessionStorage[keyEncObjectsPfsPath],
      objectsPfs!,
      contentKeyData,
      tempDir
    );

    // 只存本地的，是否加密都行，但避免用户修改，还是加了密
    await latestFilesMapHandler?.call(filesMap, contentKeyData, tempDir);
    await latestMsgMapHandler?.call(msgMap, contentKeyData, tempDir);


    if(App.devModeOn) {
      App.logger.info(_TAG, "profile: pfs handler, end: ${DateTime.now().millisecondsSinceEpoch}");
    }
    //// END: update local pfs file

    // 主要是创建一个 syncCache/info.enc ，用来标记syncCache的文件已经就绪，可以rename到正式目录了
    await afterUploaded?.call();

    await _sessionReset();

  }

  // 异常信息末尾的code是用来帮助在代码中定位的
  void _sessionCheck(String sessionId, String sessionAct, int code) {
    if(sessionId.isEmpty) {
      throw RemoteException("$sessionAct failed: sessionId is empty, err code: $code");
    }

    if(sessionId != currentSessionId) {
      throw RemoteException("$sessionAct failed: sessionId doesn't match: sessionId=$sessionId, currentSessionId=$currentSessionId, err code: $code");
    }
  }

  Future<void> _sessionReset() async {
    await gitPush("session_reset");

    objectsPfs = null;
    objPfsFindResultMap = null;
    // filesPfs = null;
    // msgPfs = null;
    lastObjectsPfsContentId = '';
    lastFilesPfsContentId = '';
    lastMsgPfsContentId = '';

    // objMap = null;
    // lastObjMapContentId = '';

    msgMap = null;
    lastMsgMapContentId = '';
    filesMap = null;
    lastFilesMapContentId = '';

    sessionStorage.clear();
    sessionCanRollback = false;
    sessionActName = '';
    sessionActDesc = '';
    currentSessionId = '';
    throwIfSessionInterrupted = null;

    // _objAddRefsMap = null;
    // _objDeRefsMap = null;
    _objAddRefsCountMap = null;

    _objBuf = null;

    isLockRenewaling = null;
    remoteSessionCommitBegin = null;
    remoteSessionCommitEnd = null;

    client = null;
  }

  ObjPackFileStorage getPfsByType(RemoteDataType pfsType) {
    if(!pfsType.isPfs()) {
      throw RemoteException("expect pfs type but got '${pfsType.value}', err code: 13242283");
    }

    if(pfsType != RemoteDataType.objectsPfs) {
      throw RemoteException("only support object pfs, but got: ${pfsType.value}, err code: 13622042");
    }

    return objectsPfs!;
  }
  //
  // Future<void> _fetchPfs(RemoteDataType pfsType, KeyData contentKeyData, TempDir tempDir) async {
  //   if(!pfsType.isPfs()) {
  //     throw RemoteException("expect pfs remote data type, but got '${pfsType.value}', 12840547", null);
  //   }
  //
  //   final isFilePfs = pfsType == RemoteDataType.filesPfs;
  //   final isMsgPfs = pfsType == RemoteDataType.msgPfs;
  //   final String keyEncPfsPath;
  //   if(isFilePfs) {
  //     filesPfs = null;
  //     lastFilesPfsContentId = '';
  //     keyEncPfsPath = keyEncFilesPfsPath;
  //   }else if(isMsgPfs) {
  //     msgPfs = null;
  //     lastMsgPfsContentId = '';
  //     keyEncPfsPath = keyEncMsgPfsPath;
  //   }else {
  //     objectsPfs = null;
  //     lastObjectsPfsContentId = '';
  //     keyEncPfsPath = keyEncObjectsPfsPath;
  //   }
  //
  //   final pfsPath = getRemotePfsPathByType(pfsType);
  //   final PackFileStorage pfs;
  //   if(await exists(pfsPath)) {
  //     // 存到 tempDir/fetchCache/files|objects|msg 里
  //     final tempFile = await getPfsFileByTypeFromFetchCache(pfsType, tempDir);
  //     await downloadToFile(pfsPath, tempFile, tempDir);
  //
  //     // 存到缓存，后续如果没更新，直接使用这个pfs文件即可，若更新，会替换为最新的pfs文件存储路径
  //     sessionStorage[keyEncPfsPath] = tempFile.absolute.path;
  //
  //     pfs = await PackFileStorage.decrypt(contentKeyData, tempFile);
  //   }else {
  //     // 若不存在，则新建一个，push的时候就会创建了
  //     pfs = PackFileStorage(type: pfsType.value);
  //   }
  //
  //   if(isFilePfs) {
  //     filesPfs = pfs;
  //     lastFilesPfsContentId = pfs.contentId;
  //   }else if(isMsgPfs) {
  //     msgPfs = pfs;
  //     lastMsgPfsContentId = pfs.contentId;
  //   }else {
  //     objectsPfs = pfs;
  //     lastObjectsPfsContentId = pfs.contentId;
  //   }
  // }

  Future<void> initPfsFromRemoteDataDirByType(RemoteDataType pfsType, KeyData contentKeyData, String remoteDataDirPath) async {
    // if(!pfsType.isPfs()) {
    //   throw RemoteException("type '$pfsType' is not a pfs type, err code: 16759189");
    // }

    if(pfsType != RemoteDataType.objectsPfs) {
      throw RemoteException("only support object pack file type, but got type: $pfsType, err code: 12930229");
    }

    final String pfsFilePath;
    if(pfsType == RemoteDataType.filesPfs) {
      pfsFilePath = p.join(Repo.getPfsFilesDirPath(remoteDataDirPath), pfsFileName);
    }else if(pfsType == RemoteDataType.msgPfs) {
      pfsFilePath = p.join(Repo.getPfsMsgDirPath(remoteDataDirPath), pfsFileName);
    }else { // obj pfs
      pfsFilePath = p.join(Repo.getPfsObjectsDirPath(remoteDataDirPath), pfsFileName);
    }

    final File pfsFile = File(pfsFilePath);

    final ObjPackFileStorage pfs = await ObjPackFileStorage.decrypt(contentKeyData, pfsFile);

    objectsPfs = pfs;
    lastObjectsPfsContentId = pfs.contentId;
    objPfsFindResultMap = await pfs.toFindResultMap();
  }

  Future<void> initMsgMapFromRemoteDataDir(KeyData contentKeyData, String remoteDataDirPath) async {
    final file = File(Repo.getMsgMapFilePath(remoteDataDirPath));
    msgMap = await DataMap.decrypt(contentKeyData, file);
  }

  // 用本地仓库的remote目录下的files map初始化remote的参数，下载缓存的时候用
  Future<void> initFilesMapFromRemoteDataDir(KeyData contentKeyData, String remoteDataDirPath) async {
    final file = File(Repo.getFilesMapFilePath(remoteDataDirPath));
    filesMap = await DataMap.decrypt(contentKeyData, file);
  }


  Future<File> getPackFileByNameFromFetchCache(String packFileName, RemoteDataType pfsType, TempDir tempDir, {File? pfsFile}) async {
    // .pack file和 pfs.enc在同一目录，所以替换下最后的文件名即可
    // 若有pfsFile，则直接使用pfsFile的父路径后追加packFileName，例如pfsFile路径是 基路径/pfs/objects/pfs.enc，取其父目录追加.pack则变为 fetchCache/pfs/objects/N.pack，其中n是pack索引
    // 若无pfsFile，则根据pfsType获取对应类型的pfs文件存储路径，例如pfsType为objPfs，则对应路径为 基路径/pfs/objects/pfs.enc
    return await getFileAndMakeSureParentDirExist(
      p.join((pfsFile ?? await getPfsFileByTypeFromFetchCache(pfsType, tempDir)).parent.absolute.path, packFileName)
    );
  }

  Future<File> getPfsFileByTypeFromFetchCache(RemoteDataType pfsType, TempDir tempDir) async {
    return await getFileAndMakeSureParentDirExist(
      // e.g. tempDir/fetchCache/pfs/files/pfs.enc
      // push时如果修改pfs.enc，拷贝到 pushCache/willPush/pfs/files|objects|msg 目录再修改，别动fetchCache里的
      Repo.getPfsFilePathByType(pfsType, (await tempDir.fetchCacheDir()).absolute.path)
    );
  }

  // Future<void> fetchFilesPfs(KeyData contentKeyData, TempDir tempDir) async {
  //   await _fetchPfs(RemoteDataType.filesPfs, contentKeyData, tempDir);
  // }

  Future<File?> fetchFilesMap(KeyData contentKeyData, TempDir tempDir) async {
    final remotePath = remoteFilesMapPath();

    final tempFile = await tempDir.createTempFile();
    await downloadToFile(remotePath, tempFile, tempDir);
    filesMap = await DataMap.decrypt(contentKeyData, tempFile);

    lastFilesMapContentId = filesMap!.contentId;
    return tempFile;
  }

  Future<File?> fetchMsgMap(KeyData contentKeyData, TempDir tempDir) async {
    final remotePath = remoteMsgMapPath();

    final tempFile = await tempDir.createTempFile();
    await downloadToFile(remotePath, tempFile, tempDir);
    msgMap = await DataMap.decrypt(contentKeyData, tempFile);

    lastMsgMapContentId = msgMap!.contentId;
    return tempFile;
  }

  // 返回pfs文件（下载到的临时文件）
  Future<File?> fetchObjectsPfs(KeyData contentKeyData, TempDir tempDir) async {
    objectsPfs = null;
    lastObjectsPfsContentId = '';
    objPfsFindResultMap = null;
    final keyEncPfsPath = keyEncObjectsPfsPath;

    final pfsType = RemoteDataType.objectsPfs;
    final pfsPath = getRemotePfsPathByType(pfsType);
    final ObjPackFileStorage pfs;

    // 存到 tempDir/fetchCache/files|objects|msg 里
    final tempFile = await getPfsFileByTypeFromFetchCache(pfsType, tempDir);
    await downloadToFile(pfsPath, tempFile, tempDir);

    // 存到缓存，后续如果没更新，直接使用这个pfs文件即可，若更新，会替换为最新的pfs文件存储路径
    sessionStorage[keyEncPfsPath] = tempFile.absolute.path;

    pfs = await ObjPackFileStorage.decrypt(contentKeyData, tempFile);

    objectsPfs = pfs;
    lastObjectsPfsContentId = pfs.contentId;
    objPfsFindResultMap = await pfs.toFindResultMap();

    return tempFile;
  }



  // 将来改成fetchIgnore对象
  // Future<void> fetchIndex(KeyData contentKeyData, TempDir tempDir) async {
  //   final remotePath = remoteIndexPath();
  //
  //   if(await exists(remotePath)) {
  //     final tempFile = await tempDir.createTempFile();
  //     await downloadToFile(remotePath, tempFile);
  //     index = await Index.decrypt(contentKeyData, tempFile);
  //   }else {
  //     index = Index();
  //   }
  //
  //   lastIndexContentId = index!.contentId;
  // }

  // Future<void> upload(FilePath path, int fileSizeInBytes, Stream<List<int>> data);

  Future<void> uploadFile(FilePath path, File file, {bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true});

  /// 返回远程的临时文件路径，这个路径可用来rename啥的
  Future<FilePath> uploadFileToTemp(File file) async {
    final tempPath = genRemoteTempFilePath();
    await uploadFile(tempPath, file);
    return tempPath;
  }

  // 上传到 cache/syncCache/files 目录
  Future<void> uploadFileToSyncCache(
    File file, {
    // 加点提示，比如 files/0.pack，可以命名成files_0.pack_随机字符串
    required final String tempNamePrefix,
    // 若为真，返回的路径不会包含basePath，兼容性更好，这样如果用户拷贝仓库内容到另一个目录，文件依然能正常移动。
    // 例如路径为 /remoteRoot/abc.txt，只返回abc.txt，然后用户移动了仓库，basePath变成了 /anotherRemoteRoot，依然可以定位到当下的abc.txt
    final bool replaceBasePathToPlaceHolder = true,
    required Future<void> Function(FilePath remotePathOfUploadFile) onFinish
  }) async {
    final tempPath = genRemoteTempFilePath(base: remoteSyncCacheFilesDirPath(), prefix: tempNamePrefix);
    await uploadFile(tempPath, file);

    final FilePath remotePathOfUploadFile;
    if(replaceBasePathToPlaceHolder) {
      remotePathOfUploadFile = RepoPathPlaceHolder.replacePrefixForRemote(this, tempPath);
    }else {
      remotePathOfUploadFile = tempPath;
    }

    await onFinish(remotePathOfUploadFile);
  }

  Future<void> uploadSyncCacheInfo(
    KeyData contentKeyData,
    List<FilePathPair> pushedPaths,
    TempDir tempDir
  ) async {
    try {
      await uploadSyncCacheInfoNoGitPush(contentKeyData, pushedPaths, tempDir);
    }finally {
      // 上传sync cache info文件时，所有必须的文件都已经上传完了，先推送一下，看会不会成功，
      // 若成功再继续操作，如果不在这推送，直接提交syncCache，
      // 最后推送时发现超了git平台限制文件大小，然后报错，就白忙活了
      await gitPush("upload_sync_cache_info", must: true);
    }
  }

  Future<void> uploadSyncCacheInfoNoGitPush(
    KeyData contentKeyData,
    List<FilePathPair> pushedPaths,
    TempDir tempDir,
  ) async {
    final info = SyncCacheInfo();
    info.addTask(SyncTask(type: SyncTaskType.renameBatch, data: SyncTaskDataRenameBatch(items: pushedPaths).toJson()));

    // 本地的 tempDir/pushCache/willPush/syncCache/info.enc
    final file = await getFileAndMakeSureParentDirExist(
      p.join(
        (await tempDir.pushCacheWillPushDir()).absolute.path,
        syncCacheDirName,
        syncCacheInfoFileName
      )
    );

    if(App.devModeOn) {
      App.logger.debug(_TAG, "syncCache info will upload: ${info.toJson()}");
    }

    final encData = await EncryptedData.compressThenEncrypt(info.toJsonByteStream(), contentKeyData);
    await writeStreamToFile(file, encData.toByteStream());

    final remotePath = remoteSyncCacheInfoPath();
    await uploadFile(remotePath, file);

    // mark sync cache ready for commit
    // await uploadSyncCacheReadyFile(contentKeyData, tempDir);

  }

  // 废弃：远程仓库的 cache/syncCache/info.enc 这个文件本身就能代表syncCache已经就绪，无需再上传这个ready文件，多此一举
  // Future<void> uploadSyncCacheReadyFile(KeyData contentKeyData, TempDir tempDir) async {
  //   // 本地的 tempDir/pushCache/willPush/syncCache/ready.enc
  //   final file = await getFileAndMakeSureParentDirExist(
  //     p.join(
  //       (await tempDir.pushCacheWillPushDir()).absolute.path,
  //       syncCacheDirName,
  //       syncCacheReadyFileName
  //     )
  //   );
  //
  //   // 只要此文件存在，就代表syncCache就绪，内容无所谓
  //   final encData = await EncryptedData.compressThenEncrypt(Stream.value([1]), contentKeyData);
  //   await writeStreamToFile(file, encData.toByteStream());
  //
  //   await uploadFile(remoteSyncCacheReadyPath(), file);
  // }

  Future<void> commitSyncCacheIfNeedNoGitPush(
    KeyData contentKeyData,
    TempDir tempDir, {
    required bool throwIfNonExists
  }) async {

    Future<void> clearSyncCache(
      TempDir tempDir, {
      // key是 syncCache/files下的文件名，value是rename的源路径和目标路径
      // 若为null或空，不会检查所有期望的文件是否已经移动成功（syncCache/files不存在对应文件则成功）
      Map<String, FilePathPair>? expectedMoved,
    }) async {
      // BEGIN: 检查 syncCache/files 目录是否为空


      // 其实这个检查意义不大，如果这次重命名失败，谁能保证下次就一定会成功？而且如果失败，应该在之前就抛出异常
      // 并且如果是git后端，此检查会增加出错的概率，可能导致用户不知道怎么解决，
      // 比如：设备1，调用远程在更新锁时推送了部分文件到syncCache，
      // 然后停电，然后另一台设备之前也刚好在创建完整的syncCache后没电，并且它现在充电了，重新同步，
      // 这时，同步完后syncCache目录就会有设备1残留的文件，但其实这些文件直接删掉就行。
      // git后端还有别的问题，比如两台设备都在创建完远程的syncCache/info.enc后没电，
      // 然后其中一台先推送，另一台又推送，这时候文件历史就会被后一台的覆盖，前一台设备修改
      // 的数据虽然在那台设备的本地仍有缓存，但在文件历史中会丢失，同步历史节点也会丢失一个节点，
      // 这时候，只能依靠用户在丢失数据的那台设备使用的文本编辑器的备份机制来找到丢失的文件了。

      // 先看下远程的 cache/syncCache/files 里是否有文件
      final syncCacheFilesDirPath = remoteSyncCacheFilesDirPath();
      // 这样虽然多发一个请求，但出错的概率更小，因为如果只执行listFiles，
      // 并且try..catch来判断是否有文件，有可能偶然一次，网络不佳，
      // 然后后面直接删除目录，但如果先判断是否存在，再列的话，两个请求都网络临时出错的概率会低一些
      if(expectedMoved != null && expectedMoved.isNotEmpty && await exists(syncCacheFilesDirPath)) {
        // 若force 为 false，检查目录是否为空，若为空则删除；非空则不删除
        final files = await listFiles(syncCacheFilesDirPath);
      
        // 若临时重命名失败，可重新同步，再次尝试重命名或许能解决，若不能，可能哪里不对，只能靠用户手动去把syncCache/files下的文件移动到对应目录了，异常信息会打印源路径和期望移动到的目标路径，用户可根据此操作（其实若出错，用户很可能直接不用了，根本懒得操作）
        if(files.isNotEmpty) {
          // throw RemoteException("remote dir: '${syncCacheFilesDirPath.toUnixPathStr()}' is not empty!, maybe have some files rename failed, please try sync again.");
          final movedFailed = <FilePathPair>{};
          for(final f in files) {
            final pair = expectedMoved[f.name];
            if(pair != null) {
              movedFailed.add(pair);
            }
          }

          if(movedFailed.isNotEmpty) {
            throw RemoteException("move files from syncCache failed, please re-try sync or move these files manually:\n$movedFailed");
          }
        }
      }


      // END: 检查 syncCache/files 目录是否为空


      // syncCache/files 目录没东西了，可删除 syncCache/info.enc 了，但是，其实整个syncCache其实都没用了，所以直接把目录删了就行
      // 删除 /cache/syncCache 目录
      await deleteIfExists(remoteSyncCacheRootPath(), isDir: true);
    }

    // cache/syncCache/ready.enc
    // final readyFilePath = remoteSyncCacheReadyPath();
    // 若 syncCache/files 或者 syncCache/ready.enc 不存在，清缓存并返回，若进入此if，有如下两种可能：
    // 1. 若syncCache/files目录为空或不存在，则代表任务要么完成了但没文件需要移动，要么移动中断过，之前移动完了，但在删除目录前中断了；
    // 2. 若 syncCache/ready.enc不存在，要么数据没上传完整，要么上传完数据了，最后上传ready.enc时网络中断了
    // 以上两种可能的处理方式相同：直接把syncCache目录删除，继续同步即可（相当于重新上传和下载更改的文件，之前的流量就白费了，但一般不会有数据不匹配的问题（概率小，但不是0））

    // 检查是否存在 cache/syncCache/files
    final filesDirPath = remoteSyncCacheFilesDirPath();
    // 直接用info.enc当作代表syncCache ready file
    if(!await exists(filesDirPath) || !await exists(remoteSyncCacheInfoPath())) {
      if(throwIfNonExists) {
        throw RemoteException("commit sync cache err, files dir is empty or ready file nonexists, err code: 13003155");
      }

      await clearSyncCache(tempDir);
      return;
    }


    // 如果 syncCache/info.enc和syncCache/files目录都存在，才需要处理
    // 列出 cache/syncCache/files 下的文件，执行rename
    List<RemoteFile> files = await listFiles(filesDirPath);
    // 如果syncCache/files下没文件，没什么需要移动的，直接删除缓存目录，返回
    if(files.isEmpty) {
      if(throwIfNonExists) {
        throw RemoteException("commit sync cache err, no files under sync cache of remote, err code: 10510639");
      }

      await clearSyncCache(tempDir);

      return;
    }

    App.logger.debug(_TAG, "#commitSyncCacheIfNeed(): ${files.length} files under remote syncCache");

    final tempFile = await tempDir.createTempFile();
    await downloadToFile(remoteSyncCacheInfoPath(), tempFile, tempDir);
    final info = await SyncCacheInfo.decrypt(contentKeyData, tempFile);

    /// 暂时只需要重命名一个任务，也只创建这一个任务，只要文件存在，就一定有且只有这个任务，所以直接取出来即可，
    /// 日后，如果支持更多任务，则遍例into.task，找出未完成的任务，根据type执行特定的函数处理，处理完成后标记为finished
    List<FilePathPair>? renamePairs = SyncTaskDataRenameBatch.fromJson(info.tasks[0].data).items;

    // should not happens
    if(renamePairs.isEmpty) {
      if(throwIfNonExists) {
        throw RemoteException("commit sync cache err, no files under sync cache of remote, err code: 13823373");
      }

      await clearSyncCache(tempDir);

      return;
    }

    var cachedFilesNeedRenameToTargetPath = renamePairs;

    // 有可能之前重命名了几个文件，然后重新同步，这个数量就可能不匹配了，正常
    if(files.length != renamePairs.length) {
      // 同步结束，第一次提交syncCache，这个参数才会为真，这时如果数量不匹配，应该抛异常，因为一个都还没处理，理应匹配
      // 后续再次同步时，开启会话前提交syncCache，就不一定匹配了，因为之前的同步有可能中断，所以本次可能会数量不匹配
      if(throwIfNonExists) {
        throw RemoteException("commit sync cache err, files count doesn't match the sync cache info recorded, err code: 19129466");
      }

      cachedFilesNeedRenameToTargetPath = <FilePathPair>[];

      final namesMap = <String, FilePathPair>{};
      for(final pair in renamePairs) {
        // 左边的文件名，不该重复，用其做key，检测这个待移动的文件清单，是否有错误记录（重复记录）
        final fileName = p.basename(pair.left.toUnixPathStr());
        if(namesMap[fileName] != null) {
          // 一个源路径（或目标路径，不过这里只检测源路径）只应该出现1次，如果出现多次，说明哪里不对，不过出现两次其实也没什么关系吧？
          throw RemoteException("commit sync cache err, path repeated: '$fileName', err code: 10672399");
        }

        namesMap[fileName] = pair;
      }

      // help free mem?
      renamePairs = null;

      // 遍历renamePair，取出所有在 syncCache/files 仍存在的路径，执行批量重命名
      for(final f in files) {
        final pathPair = namesMap[f.name];
        if(pathPair != null) {
          cachedFilesNeedRenameToTargetPath.add(pathPair);
        }
      }
    }

    // 没有需要移动的文件，则删除缓存目录
    if(cachedFilesNeedRenameToTargetPath.isEmpty) {
      if(throwIfNonExists) {
        throw RemoteException("commit sync cache err, no files under sync cache of remote, err code: 17311522");
      }

      await clearSyncCache(tempDir);

      return;
    }

    // files下所有文件都应该被重命名，如果数量和实际需要重命名的不匹配，说明里面有别的东西或者用户修改过，放弃操作
    // 比如files有上次残留的文件，和这次的文件混了（其实不可能发生，除非exists函数检测不可靠），这时有可能文件数量不对，最好还是不要提交为妙
    if(cachedFilesNeedRenameToTargetPath.length != files.length) {
      throw RemoteException("commit sync cache err, have ${files.length} files under sync cache files dir, but only have ${cachedFilesNeedRenameToTargetPath.length} files need to rename, err code: 16549529");
    }

    // 重命名文件
    await renameBatch(cachedFilesNeedRenameToTargetPath);

    Map<String, FilePathPair> expectedMoved = {};
    for(final needRenameFile in cachedFilesNeedRenameToTargetPath) {
      expectedMoved[needRenameFile.left.name()] = needRenameFile;
    }

    // 清缓存目录
    // force为假，确保上面文件全重命名成功才删除syncCache
    await clearSyncCache(tempDir, expectedMoved: expectedMoved);

  }

  Future<void> commitSyncCacheIfNeed(
    KeyData contentKeyData,
    TempDir tempDir, {
    required bool throwIfNonExists
  }) async {
    try {
      await commitSyncCacheIfNeedNoGitPush(contentKeyData, tempDir, throwIfNonExists: throwIfNonExists);
      if(await exists(remoteSyncCacheRootPath())) {
        throw RemoteException("remote path 'cache/syncCache' dir still exists after committed, maybe remove syncCache dir then try again, err code: 15404752");
      }

      final tempFile = await tempDir.createTempFile();
      bool downSuccess = false;
      try {
        await downloadToFile(remoteSyncCacheInfoPath(), tempFile, tempDir);
        downSuccess = true;
      }catch(_){
      }finally {
        await safeDeleteFile(tempFile);
      }

      if(downSuccess) {
        // 上面删了syncCache目录，这还能成功下载其中的文件，说明删除失败了
        throw RemoteException("clear syncCache failed, err code: 16296113");
      }
    }finally {
      // 这里提交的是远程的sync cache，本地的是不需要git push的
      await gitPush("commit_sync_cache");
    }
  }


  // push时调用此函数提交同步缓存，不检查是否成功，只执行操作，
  // 下次同步前会调用另一个函数检查，这样可以减少上传文件时的网络请求，
  // 提升性能
  Future<void> commitSyncCacheForPush(
    KeyData contentKeyData,
    TempDir tempDir,
    List<FilePathPair> pushedPaths,
  ) async {
    try {
      // 尝试下载代表同步缓存已就绪的文件，若下载失败，抛异常
      try {
        final tempFile = await tempDir.createTempFile();
        await downloadToFile(remoteSyncCacheInfoPath(), tempFile, tempDir);
      }catch(e, st){
        throw RemoteException("commit syncCache failed, err code: 18958910, err:$e\n$st");
      }

      // 移动需要移动的文件
      await renameBatch(pushedPaths);
    }finally {
      // 这里提交的是远程的sync cache，本地的是不需要git push的
      await gitPush("commit_sync_cache_for_push");
    }
  }

  /// 先上传到临时目录，再重命名到path，在某些平台，这样做可降低上传文件未完成导致路径关联的文件不完整的概率
  /// 那直接把uploadFile改成实现成先上传到temp再重命名不就行了，为什么还要多此一举添加这个函数呢？
  // Future<void> uploadFileToTempThenRename(FilePath path, File file);

  // Future<void> uploadEncryptedData(FilePath path, int fileSizeInBytes, EncryptedData encryptedData) {
  //   return upload(path, fileSizeInBytes, encryptedData.toByteStream());
  // }

  Future<void> mkdir(FilePath path);
  Future<void> delete(FilePath path, {required bool isDir, bool gitPushIfNeed = true});
  Future<void> deleteIfExists(FilePath path, {required bool isDir}) async {
    if(await exists(path)) {
      await delete(path, isDir: isDir);
    }
  }

  Future<void> deleteBatch(List<RemoteFileSimple> files, {bool gitPushIfNeed = true}) async {
    if(files.isEmpty) {
      return;
    }

    final tasks = <Future Function()>[];
    for(final f in files) {
      tasks.add(() => delete(f.path, isDir: f.isDir, gitPushIfNeed: false));
    }

    await runTaskConcurrencyIfAllow(tasks, isRead: false);

    if(gitPushIfNeed && isLockUploader) {
      await gitPush("delete_batch");
    }
  }

  // 如果path 是个文件，则list包含文件本身；若是目录，列出其下所有文件和目录。
  Future<List<RemoteFile>> listFiles(FilePath path);

  /// 根据pfs.enc生成虚拟的路径，可以通过fetchData用这个oid下载数据
  Future<List<RemoteFile>> listFilesByType(RemoteDataType remoteDataType) async {
    _requireSession(12047025);

    final pfsType = remoteDataType.getPfsType();
    if(pfsType == null) {
      throw RemoteException("can't found pfs type for remote data type: ${remoteDataType.value}");
    }

    final pfs = getPfsByType(pfsType);
    final remoteFiles = <RemoteFile>[];
    for(final pf in pfs.packFiles) {
      for(final pi in pf.items) {
        remoteFiles.add(
          RemoteFile(
            isDir: true,
            name: pi.oid,
            path: genRemoteOidDirPathByType(
              remoteDataType,
              pi.oid
            ),
            mTimeMs: pi.ctime.utcMs,
            length: pi.len
          )
        );
      }
    }

    return remoteFiles;
  }

  // 此函数和uploadFile应该确保即使没开session也能正常调用
  Future<void> downloadToFile(FilePath path, File file, TempDir tempDir);

  // 注：此函数判断存在一般来说准，但是【判断不存在的结果不一定准】，例如网络问题抛异常，或其他原因抛异常，都会误认为文件不存在，
  // 所以不要依赖此函数做不存在则创建的判断，可能不准；若是必要文件，应该在初始化仓库时就创建空对象占位，日后总是当作文件一定存在来处理
  Future<bool> exists(FilePath path) async {
    // 注意：这个路径打印的时候可能是windows格式 \ 分割，因为这里直接用的toString，
    // 而toString是根据平台变化的，不过实际使用的时候会使用unix风格的路径
    App.logger.debug(_TAG, "#exists(): check path='$path'");

    final fullPath = await preHandlePath(path, makeSureParentExists: false);

    bool result;
    // 这个判断不一定准，但一般够用
    try {
      // 路径如果不存在，应该会抛异常，否则返回dir或file的元数据
      // final remoteFile = await getMetadata(fullPath);
      await getMetadata(fullPath);

      result = true;

      // 这个name检测没啥意义（remoteFile.path检测更没意义，webdav实现直接用的传参时的path，根本不是服务器返回的），
      // 如果文件不存在，会抛异常（不确定什么异常，有可能网络异常，有可能别的），若没抛异常，一般都是存在
      // if(remoteFile.name.isEmpty) {
      //   App.logger.debug(_TAG, "#exists() getMetadata success but file name is empty: path='$path', fullPath='$fullPath', remoteFile.path='${remoteFile.path}'");
      //
      //   result = false;
      // }else {
      //   result = true;
      // }

    }catch(e, st) {
      // rethrow;
      App.logger.debug(_TAG, "#exists() getMetadata err, if the file doesn't exist in remote, then this is ok: path='$path', fullPath='$fullPath'\nerr=$e\n$st");
      result = false;

      // 若是webdav，无法确定服务器到底会抛出什么异常(非webdav其实也很难确定)，所以，没法精确判断，
      // 怪只怪webdav没规定文件不存在时抛什么异常，也没定义判断路径是否存在的exists method
      // if(e is RemoteNotFoundException) {
      //   result = false;
      // }else {
      //   final errMsg = e.toString();
      //   App.logger.debug(_TAG, "#exists() getMetadata err, if the file doesn't exist in remote, then this is ok: path='$path', fullPath='$fullPath'\nerr=$errMsg\n$st");
      //
      //   if(errMsg.contains("Not Found") || errMsg.contains("NOT FOUND") || errMsg.contains("not found") || errMsg.contains("not_found")) {
      //     // 包含特定关键字则认为文件不存在
      //     result = false;
      //   }else {
      //     App.logger.debug(_TAG, "#exists() rethrows: path=$path\nerr: $e\n$st");
      //
      //     // 不包含特定关键字，则抛出异常，避免误认为文件不存在
      //     rethrow;
      //   }
      // }
    }

    App.logger.debug(_TAG, "#exists(): path='$path', fullPath='$fullPath', exists=$result");

    return result;

  }

  // Future<FilePath> createTempFile();

  // 有的是上传完成，再移动到正式目录，这种不需要重命名，
  // 有的是直接边上传边更新对应路径的文件，这种需要先上传到临时目录，再重命名，
  // 加上obj -> file 的优先级，即可确保同步操作可在任意阶段中止而数据不出错
  Future<void> rename(FilePath from, FilePath to, {required bool isDir, bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true});
  /// 批量重命名，一次命名多个条目，可减少网络请求损耗，例如如果一个一个调用rename，
  /// 若有1万个文件，损耗将是1万乘1rtt，假设往返需要100ms，那么将会消耗100万ms，
  /// 大约16分钟，这是不可接受的，不过，有的平台不支持一个请求批量重命名n个文件，所以，
  /// 默认实现依然是逐个重命名，我只能通过封装小文件到.pack来减少文件数量，
  /// 但如果用户非要上传特别大的文件，没辙，就是会崩
  /// [gitPushIfNeed] 就算是true，也不一定会push，因为只有当remote实例是负责上传lock的实例时，这个函数才会执行push
  Future<void> renameBatch(List<FilePathPair> paths, {bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#renameBatch(): paths='$paths'");

    if(paths.isEmpty) {
      return;
    }

    final tasks = <Future Function()>[];
    for(final p in paths) {
      tasks.add(() => rename(p.left, p.right, isDir: p.isDir, gitPushIfNeed: false));
    }

    await runTaskConcurrencyIfAllow(tasks, isRead: false);

    if(gitPushIfNeed && isLockUploader) {
      await gitPush("rename_batch");
    }

  }

  Future<RemoteFile> getMetadata(FilePath path);

  /// return the err instead of throw
  Future<RemoteException?> renameSafe(FilePath from, FilePath to, {required bool isDir}) async {
    try {
      await rename(from, to, isDir: isDir);
      return null;
    }catch(e) {
      return RemoteException("$e, err code: 12761171", data: e);
    }
  }

  Future<RemoteException?> renameBatchSafe(List<FilePathPair> paths) async {
    try {
      await renameBatch(paths);
      return null;
    }catch(e) {
      return RemoteException("$e, err code: 16093509", data: e);
    }
  }

  Future<void> copy(FilePath from, FilePath to, {required bool isDir, bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true});

  /// 下载成功返回真，否则返回假
  Future<bool> downloadToFileNoThrow(FilePath path, File file, TempDir tempDir) async {
    try {
      await downloadToFile(path, file, tempDir);
      return true;
    }catch(e, st) {
      App.logger.debug(_TAG, "#downloadOrNull() err:\nremote path=$path\nlocal file path=${file.absolute.path}\nerr=$e\n$st");
      // App.logger.verbose(_TAG, "#downloadOrNull() err: $e\n$st");
      return false;
    }
  }


  String getDelCacheKeyByType(RemoteDataType pfsType) {
    if(pfsType == RemoteDataType.filesPfs) {
      return keyWillDelFiles;
    }else if(pfsType == RemoteDataType.objectsPfs) {
      return keyWillDelObjs;
    }else {
      return keyWillDelMsg;
    }
  }

  // Future<void> _deleteByOidToCache(RemoteDataType pfsType, VersionOid oid, TempDir tempDir) async {
  //   _requireSession(17840702);
  //
  //   if(!pfsType.isPfs()) {
  //     throw RemoteException("expect pfsType but got '$pfsType', 13638769", null);
  //   }
  //
  //   final cacheKey = getDelCacheKeyByType(pfsType);
  //
  //   var willDeleteList = mapGetOrNull<List<VersionOid>>(sessionStorage, cacheKey);
  //   if(willDeleteList == null) {
  //     willDeleteList = <VersionOid>[];
  //     sessionStorage[cacheKey] = willDeleteList;
  //   }
  //
  //   willDeleteList.add(oid);
  //
  //   // 检查下，如果文件在pushCache里，移除
  //   final fileInPushCache = await getLocalFileByOid(pfsType.getNonPfsType()!, (await tempDir.pushCacheDir()).absolute.path, oid);
  //   if(await fileInPushCache.exists()) {
  //     await fileInPushCache.delete();
  //
  //     // 删除空目录
  //     try {
  //       await fileInPushCache.parent.delete();
  //     }catch(_) {
  //
  //     }
  //   }
  // }

  Future<void> deRefWithObj({
    required VersionOid objOid,
    // file info或msg，等引用了此obj的对象的oid
    // required String refedOid,
  }) async {
    // 无效的根本不会关联，自然也不需要解除引用
    if(ObjRef.isInvalidOid(objOid.value)) {
      return;
    }

    // final deRefsMap = _objDeRefsMap!;
    // Set<String>? deRefSet = deRefsMap[objOid.value];
    // if(deRefSet == null) {
    //   deRefSet = {};
    //   deRefsMap[objOid.value] = deRefSet;
    // }
    //
    // deRefSet.add(refedOid);

    // 减少引用计数
    final refsCountMap = _objAddRefsCountMap!;
    final refCount = refsCountMap[objOid.value];
    refsCountMap[objOid.value] = (refCount ?? 0) - 1;
  }

  Future<void> deleteByOid(
    RemoteDataType remoteDataType,
    VersionOid oid,
    TempDir tempDir
  ) async {
    if(!remoteDataType.isNormalType()) {
      throw RemoteException("only support delete normal remote data type, but got: $remoteDataType, err code: 11443547");
    }

    if(remoteDataType == RemoteDataType.objects) {
      throw RemoteException("doesn't delete objects, please use delete object method instead, err code: 12750743");
    }

    // 一个oid，关联一个数据文件夹，
    // 目前暂定里面只有一个data.enc，
    // 若删，文件夹全删，所以这里isDir传true即可
    // 若想删除指定文件的话，可调用genRemoteXxxPath系列函数，
    // 生成路径，再手动调用delete
    if(remoteDataType == RemoteDataType.files) {
      filesMap!.remove(oid, lastFilesMapContentId);
    }else if(remoteDataType == RemoteDataType.msg) {
      msgMap!.remove(oid, lastMsgMapContentId);
    }else if(remoteDataType == RemoteDataType.locks) {
      // e.g. files/oid/data.enc
      // 只删locks/repoLock/data.enc文件，避免在不支持自动创建依赖目录的环境下，续锁时还需要重新创建目录（会多发请求，增加延迟）
      // 详细：如果，远程不支持自动创建目录，那么，在使用lock时，如果这里删除目录，则需要每次都发两个请求来续锁，一个用来创建目录，另一个用来创建文件
      // 但如果只删文件，下次续锁则只需要发1个请求
      await delete(genRemoteLockPath(oid), isDir: false);
    }else {
      throw RemoteException("does not support to delete the type by oid: $remoteDataType, err code: 18241256");
    }

  }

  // 删除FileInfo和Msg条目以及其关联的objects，
  // 不过这个只删远程，不删本地的，本地的files和objects设计成可全部清空，
  // 所以想删可直接扬了，而msg每次sync都会全量更新，所以无需手动清理
  // 不过这样有个特殊情况：用户对远程仓库执行了清理，然后本地有缓存，
  // 用户重新创建了某个远程数据已删除的路径的文件，在本地由于有缓存，还能看到版本历史和对应数据，
  // 然后一同步，版本历史就没了，而是用当前workdir的文件创建了一个全新的FileInfo，
  // 本地虽然还有对应的objects的data.enc，但已经没有办法找回数据了，这是符合逻辑的，因为本身
  // 用户清理之后，就不应该再有对应历史，有历史反而才是bug，
  // 所以无需处理
  Future<void> deleteDataAndRelatedOids(
    KeyData contentKeyData,
    RemoteDataType remoteDataType,
    RelatedOids relatedOids,
    TempDir tempDir, {
    // x 这参数好像没用了，好像在sync时会删除本地无远程有的条目？不确定，
    // 或者可以在设置页面加个选项“清除本地对象缓存”，可手动清 '仓库/.haha_note/remote/objects'，
    // 提示用户删了的话，需要时会重新联网下载) 引用为空，可删除的obj的handler
    required Future<void> Function(String oid)? canDelObjsHandler
  }) async {
    // final objItemType = ObjMapItemType.fromRemoteDataType(remoteDataType);

    // 删除FileInfo或Msg关联的objects
    // 不一定删除，先把这些oid和relatedOids.selfOid()的引用解除，若解除后无其他引用，提交时就会删除对应obj
    // selfOid 是fileinfo的path计算出的oid，或者msg的oid
    await for(final objOid in relatedOids.allRelatedObjectsOids()) {
      // 若对象引用删到0，最后提交时就会删除pack file中对应物理文件和obj pfs中对应item
      await deRefWithObj(objOid: objOid);
    }

    final selfOid = await relatedOids.selfOid(contentKeyData);
    // 删除对象本身 (files or msg，files 历史记录会无，因为整个条目都删了)
    await deleteByOid(
      remoteDataType,
      selfOid,
      tempDir,
    );

  }

  // 预处理传的路径
  // 注：final只是表明本函数不会修改传入的path，实际上就算标了final，也可修改path内部字段
  Future<FilePath> preHandlePath(final FilePath path, {bool makeSureParentExists = false}) async {
    if(path.isEmpty()) {
      throw RemoteException("#preHandlePath: invalid empty path, err code: 13520964");
    }

    // 如果是相对路径，转成绝对
    final FilePath path2;
    // startsWith check可避免remote误操作basePath以外的目录，比如basePath是 /abc/myrepo，path是 /，如果不加那个检测，
    // 同时isRelative错误设置为false，那么就会直接操作 / 目录！可能误删文件
    // 另外：path.isRelative必须保留，不能只依赖startsWith check，否则当basePath为 /abc/myrepo，
    // 但期望操作的路径为 /abc/myrepo/abc/myrepo 时，如果传入相对路径 /abc/myrepo 会错误判定为已经是根目录，
    // 这时startsWith check是无效的，只能依靠isRelative判断是否是相对路径
    if(path.isRelative) {
      final fullPath = path.copy().prepend(basePath.toUnixPathStr());
      path2 = RepoPathPlaceHolder.restorePrefixForRemote(this, fullPath);
    }else {
      path2 = RepoPathPlaceHolder.restorePrefixForRemote(this, path);
    }

    // 这里应该使用path2，不能用path，path可能是相对路径例如：:base:/abc，path2是还原后的真实路径
    // 注：toUnixPathStr() 内部有cache，所以重复调用不用担心性能问题
    if(!path2.toUnixPathStr().startsWith(basePath.toUnixPathStr())) {
      throw RemoteException("path must starts with basePath: path=${path2.toUnixPathStr()}, basePath=${basePath.toUnixPathStr()}");
    }

    path2.isRelative = false;

    // 确保父目录存在
    // 之前默认自动创建，但会多发很多请求，后来改成先探测是否支持自动创建不存在路径，
    // 如果不支持，uploadFile实现改成第一次直接传文件，如果失败，创建目录并重试上传，
    // 所以就不需要在这里创建了
    if(makeSureParentExists && !supportAutoCreateNonexistsPath) {
      await mkdir(path2.parent());
    }

    //返回处理后的路径
    return path2;
  }


  // /pfs
  FilePath remotePfsRootPath() {
    // 话说，其实这个basePath本来就是 abs 路径，所以copy()或copyAbs()实际上都行
    return basePath.copyAbs().append(pfsDirName);
  }

  // /pfs/objects
  FilePath remotePfsObjectsRootPath() {
    return remotePfsRootPath().append(Repo.remoteObjectsDirName);
  }

  // /pfs/files
  FilePath remotePfsFilesRootPath() {
    return remotePfsRootPath().append(Repo.remoteFilesDirName);
  }

  // /pfs/msg
  FilePath remotePfsMsgRootPath() {
    return remotePfsRootPath().append(Repo.remoteMsgDirName);
  }


  // /map
  FilePath remoteMapRootPath() {
    return basePath.copyAbs().append(mapDirName);
  }

  // /map/files.map.enc
  FilePath remoteFilesMapPath() {
    return remoteMapRootPath().append(filesMapFileName);
  }

  // /map/msg.map.enc
  FilePath remoteMsgMapPath() {
    return remoteMapRootPath().append(msgMapFileName);
  }

  // 生成在远程仓库查询用的path，不是本地的remote用的path！
  // 以前是：basePath/files|objects|msg
  // 后来，远程改存pfs，变成了 basePath/pfs/files|objects|msg
  // 本地的 remote/files 存的是解压后的enc，远程无对应目录，
  // 本地的 remote/pfs/files|objects|msg 对应远程的 basePath/pfs/files|objects|msg
  FilePath remoteObjectsRootPath() {
    // final path = [...basePath.value, Repo.remoteObjectsDirName];
    // return FilePath(value: path);
    return basePath.copyAbs().append(Repo.remoteObjectsDirName);
  }

  FilePath remoteFilesRootPath() {
    // final path = [...basePath.value, Repo.remoteFilesDirName];
    // return FilePath(value: path);
    return basePath.copyAbs().append(Repo.remoteFilesDirName);
  }

  FilePath remoteMsgRootPath() {
    // final path = [...basePath.value, Repo.remoteMsgDirName];
    // return FilePath(value: path);

    return basePath.copyAbs().append(Repo.remoteMsgDirName);
  }

  FilePath remoteLocksRootPath() {
    // final path = [...basePath.value, Repo.remoteLocksDirName];
    // return FilePath(value: path);
    return basePath.copyAbs().append(Repo.remoteLocksDirName);
  }

  FilePath remoteTempRootPath() {
    // final path = [...basePath.value, Repo.tempDirName];
    // return FilePath(value: path);

    return basePath.copyAbs().append(Repo.tempDirName);
  }

  FilePath remoteGitDirRootPath() {
    // final path = [...basePath.value, Repo.gitDirName];
    // return FilePath(value: path);

    return basePath.copyAbs().append(Repo.gitDirName);
  }

  // /cache
  FilePath remoteCacheRootPath() {
    // final path = [...basePath.value, Repo.cacheDirName];
    // return FilePath(value: path);

    return basePath.copyAbs().append(Repo.cacheDirName);
  }

  // /cache/syncCache
  FilePath remoteSyncCacheRootPath() {
    return remoteCacheRootPath().append(syncCacheDirName);
  }

  // /cache/syncCache/info.enc
  FilePath remoteSyncCacheInfoPath() {
    return remoteSyncCacheRootPath().append(syncCacheInfoFileName);
  }

  // /cache/syncCache/ready.enc
  // FilePath remoteSyncCacheReadyPath() {
  //   return remoteSyncCacheRootPath().append(syncCacheReadyFileName);
  // }

  // 目录: /cache/syncCache/files
  FilePath remoteSyncCacheFilesDirPath() {
    return remoteSyncCacheRootPath().append(syncCacheFilesDirName);
  }

  FilePath genRemoteTempFilePath({FilePath? base, String prefix = '', String suffix = '.temp'}) {
    final base2 = base ?? remoteTempRootPath();
    // final path = [...base2.value, randomString(32, prefix: prefix, suffix: suffix)];
    // return FilePath(value: path);

    return base2.copyAbs().append(randomString(24, prefix: prefix, suffix: suffix));
  }

  // 路径为在remote仓库目录的 pfs/files/pfs.enc
  FilePath remoteFilePfsPath() {
    final path = remotePfsFilesRootPath();
    path.append(pfsFileName);
    return path;
  }

  FilePath remoteObjectsPfsPath() {
    final path = remotePfsObjectsRootPath();
    path.append(pfsFileName);
    return path;
  }

  FilePath remoteMsgPfsPath() {
    final path = remotePfsMsgRootPath();
    path.append(pfsFileName);
    return path;
  }

  FilePath remoteObjMapPath() {
    // final path = [...basePath.value, objMapFileName];
    // return FilePath(value: path);

    return basePath.copyAbs().append(objMapFileName);
  }

  // FilePath remoteIndexPath() {
  //   final path = [...basePath.value, indexFileName];
  //   return FilePath(value: path);
  // }


  FilePath getRemotePfsPathByType(RemoteDataType pfsType) {
    if(!pfsType.isPfs()) {
      throw RemoteException("expect pfs remote data type, but got '${pfsType.value}', 10581268");
    }

    return pfsType == RemoteDataType.filesPfs
      ? remoteFilePfsPath()
      : pfsType == RemoteDataType.msgPfs
      ? remoteMsgPfsPath()
      : remoteObjectsPfsPath()
    ;
  }




  FilePath getRemoteDataRootPathByType(RemoteDataType remoteDataType) {
    if(!remoteDataType.isNormalType()) {
      throw RemoteException("expect normal remote data type, but got: ${remoteDataType.value}, err code: 11667530");
    }

    if(remoteDataType == RemoteDataType.objects) {
      return remoteObjectsRootPath();
    }else if(remoteDataType == RemoteDataType.files) {
      return remoteFilesRootPath();
    }else if(remoteDataType == RemoteDataType.msg) {
      return remoteMsgRootPath();
    }else {  // }else if(remoteDataType == RemoteDataType.lock) {
      return remoteLocksRootPath();
    }
  }

  /// 生成在远程仓库基本目录下的相对路径
  FilePath genRemoteObjPath(VersionOid oid) {
    final path = remoteObjectsRootPath().append(oid.value).append(Repo.remoteDataFileName);
    path.isRelative = false;
    return path;

    // final path = [...remoteObjectsRootPath().value, oid.value, Repo.remoteDataFileName];
    // return FilePath(value: path);
  }

  FilePath genRemoteFileInfoPath(VersionOid oid) {
    final path = remoteFilesRootPath().append(oid.value).append(Repo.remoteDataFileName);
    path.isRelative = false;
    return path;

    // final path = [...remoteFilesRootPath().value, oid.value, Repo.remoteDataFileName];
    // return FilePath(value: path);
  }

  String getRemoteDataDirNameByType(RemoteDataType remoteDataType) {
    // 到处都是判断的话，程序只会越来越慢
    // if(!remoteDataType.isNormalType()) {
    //   throw RemoteException("expect normal remote data type, but got: ${remoteDataType.value}, err code: 14316628");
    // }

    if(remoteDataType == RemoteDataType.files) {
      return Repo.remoteFilesDirName;
    }else if(remoteDataType == RemoteDataType.objects) {
      return Repo.remoteObjectsDirName;
    }else if(remoteDataType == RemoteDataType.msg) {
      return Repo.remoteMsgDirName;
    }else if(remoteDataType == RemoteDataType.locks) {
      return Repo.remoteLocksDirName;
    }else {
      throw RemoteException("expect normal remote data type, but got: ${remoteDataType.value}, err code: 14316628");
    }
  }

  FilePath getRemoteDirPathByType(RemoteDataType remoteDataType) {
    // if(!remoteDataType.isNormalType()) {
    //   throw RemoteException("expect normal remote data type, but got: ${remoteDataType.value}, err code: 14316628");
    // }

    if(remoteDataType == RemoteDataType.files) {
      return remoteFilesRootPath();
    }else if(remoteDataType == RemoteDataType.objects) {
      return remoteObjectsRootPath();
    }else if(remoteDataType == RemoteDataType.msg) {
      return remoteMsgRootPath();
    }else if(remoteDataType == RemoteDataType.locks) {
      return remoteLocksRootPath();
    }else {
      throw RemoteException("expect normal remote data type, but got: ${remoteDataType.value}, err code: 14316628");
    }
  }

  // 获取 data.enc的父目录，例如： /remoteRepoBasePath/files/oidStr
  FilePath genRemoteOidDirPathByType(RemoteDataType remoteDataType, String oidStr) {
    final dirPath = getRemoteDirPathByType(remoteDataType);
    return dirPath.append(oidStr);
  }

  FilePath genRemoteMsgPath(VersionOid oid) {
    final path = remoteMsgRootPath().append(oid.value).append(Repo.remoteDataFileName);
    path.isRelative = false;
    return path;

    // final path = [...remoteMsgRootPath().value, oid.value, Repo.remoteDataFileName];
    // return FilePath(value: path);
  }

  FilePath genRemoteLockPath(VersionOid oid) {
    final path = remoteLocksRootPath().append(oid.value).append(Repo.remoteDataFileName);
    path.isRelative = false;
    return path;

    // final path = [...remoteLocksRootPath().value, oid.value, Repo.remoteDataFileName];
    // return FilePath(value: path);
  }

  FilePath getRemoteRepoInfoPath() {
    return basePath.copyAbs().append(Repo.repoInfoFileName);

    // final path = [...basePath.value, Repo.repoInfoFileName];
    // return FilePath(value: path);
  }

  FilePath getRemoteSyncHistoryPath() {
    return basePath.copyAbs().append(Repo.syncHistoryFileName);

    // final path = [...basePath.value, Repo.syncHistoryFileName];
    // return FilePath(value: path);
  }

  // /basePath/filesBak
  FilePath getRemoteFilesBakDirPath() {
    return basePath.copyAbs().append(filesBakDirName);

    // final path = [...basePath.value, filesBakDirName];
    // return FilePath(value: path);
  }

  // /basePath/filesBak/oid.files.map.enc
  FilePath genRemoteFilesMapBakFilePath({required String historyNodeOid}) {
    if(historyNodeOid.isEmpty) {
      throw RemoteException("history node is empty, err code: 19250499");
    }

    return getRemoteFilesBakDirPath().append(genFilesMapNameByOid(historyNodeOid));
  }

  // 这个oid通常并不是filesMap的content oid，而是仓库历史节点的oid，因为filesMap是关联到仓库的历史记录节点的
  // 不过当初设计的不好，应该设计成history node关联一个files map content id，
  // 然后再根据content id备份files map，那样可以减少冗余的filesMap bak文件，不过影响不大，所以无所谓
  // e.g. oid.files.map.enc
  static String genFilesMapNameByOid(String oid) {
    return "$oid.$filesMapFileName";
  }

  FilePath getRemoteContentKeyPath() {
    return basePath.copyAbs().append(Repo.keysDirName).append(Repo.contentKeyFileName);

    // final path = [...basePath.value, Repo.keysDirName, Repo.contentKeyFileName];
    // return FilePath(value: path);
  }

  FilePath getRemoteMasterKeyExtraDataPath() {
    return basePath.copyAbs().append(Repo.keysDirName).append(Repo.masterKeyExtraDataFileName);

    // final path = [...basePath.value, Repo.keysDirName, Repo.masterKeyExtraDataFileName];
    // return FilePath(value: path);
  }

  // String genLocalObjectPath(String remoteDataDirPath, String oidStr) {
  //   return Repo.getObjectPathByOidStr(remoteDataDirPath, oidStr);
  // }

  String genLocalFileInfoPath(String remoteDataDirPath, String oidStr) {
    return Repo.getFileInfoPathByOidStr(remoteDataDirPath, oidStr);
  }

  String genLocalMsgPath(String remoteDataDirPath, String oidStr) {
    return Repo.getMsgPathByOidStr(remoteDataDirPath, oidStr);
  }

  String genLocalLockPath(String remoteDataDirPath, String oidStr) {
    return Repo.getLockPathByOidStr(remoteDataDirPath, oidStr);
  }

  // createParents 若明确查询，不需创建可传false，若不确定，就不用传或用默认值true，创建了顶多有几个空目录，无所谓的
  // Future<File> getLocalFileByOid(RemoteDataType remoteDataType, String basePath, VersionOid oid, {final bool createParents = true}) async {
  //   if(remoteDataType != RemoteDataType.objects && remoteDataType != RemoteDataType.locks) {
  //     // code 用来定位错误信息在代码中的位置
  //     throw RemoteException("unexpected remote data type: ${remoteDataType.value}, err code: 17122902");
  //   }
  //
  //   var path = '';
  //   final oidStr = oid.value;
  //
  //   if(remoteDataType == RemoteDataType.objects) {
  //     path = genLocalObjectPath(basePath, oidStr);
  //   }else {  // }else if(remoteDataType == RemoteDataType.lock) {
  //     path = genLocalLockPath(basePath, oidStr);
  //   }
  //
  //   return createParents ? await getFileAndMakeSureParentDirExist(path) : File(path);
  // }

  // FilePath genRemoteDataPath(RemoteDataType remoteDataType, VersionOid oid) {
  //   FilePath? path;
  //
  //   if(remoteDataType == RemoteDataType.objects) {
  //     path = genRemoteObjPath(oid);
  //   }else if(remoteDataType == RemoteDataType.files) {
  //     path = genRemoteFileInfoPath(oid);
  //   }else if(remoteDataType == RemoteDataType.msg) {
  //     path = genRemoteMsgPath(oid);
  //   }else if(remoteDataType == RemoteDataType.locks) {
  //     path = genRemoteLockPath(oid);
  //   }else {
  //     throw RemoteException("unknown remote data type (code: 14344664): $remoteDataType");
  //   }
  //
  //   return path;
  // }

  /// 返回下载后的文件，
  /// 下载文件到temp目录然后返回，如果已经在正式目录，直接把本地正式目录的数据移动到temp目录再返回；
  /// 如果移动到本地为true，则返回本地仓库的remote路径下的文件，否则返回temp中的文件
  Future<File> _fetchData(
    RemoteDataType remoteDataType,

    VersionOid oid,
    String remoteDataDirPath,
    TempDir tempDir, {
    bool force = false,
    // bool pushIfRemoteHaventDataButLocalHas = false,
    required bool moveToRemoteDataDirAfterDownload,
  }) async {
    if(remoteDataType != RemoteDataType.objects) {
      throw RemoteException("only support fetch remote data type object, but got type: $remoteDataType");
    }

    final pfsType = remoteDataType.getPfsType();
    final isPfsType = pfsType != null;
    if(!isPfsType) {
      throw RemoteException("please use download method to download the type: $remoteDataType, err code: 17781006");
    }

    if(isPfsType) {
      _requireSession(19857720);
    }

    // 如果是一上传就不会再修改的数据类型，检查是否已经存在于正式目录，若存在，直接复制到临时目录
    // 注意：fileInfo和lock不能偷这个懒，因为这些类型的文件有可能路径一样，但是文件内容不同，不过objects和msg可以偷懒，这两个一旦上传就不会再修改
    if(!force && remoteDataType.isImmutable()) {
      var file = File(Repo.getLocalRemoteObjectPathByOidStr(remoteDataDirPath, oid.value));
      if(await file.exists()) {
        // 拷贝文件到临时目录 TODO 需要测试，如果不需要拷贝，就不拷贝了，目前先禁用，看数据是否会出错。
        // final tempFile = getFileAndMakeSureParentDirExist(Repo.getFileInfoPathByOidStr(tempDir.base.absolute.path, oid.value));
        // await file.copy(tempFile.absolute.path);
        // return tempFile;

        // 检查远程是否存在
        // if(pushIfRemoteHaventDataButLocalHas) {
        //   if(isPfsType) {
        //     // pack 类型，若不存在，添加到缓存
        //     final pfs = getPfsByType(pfsType);
        //     final findResult = await pfs.find(oid);
        //     // 拷贝到cache里，稍后会上传
        //     if(!findResult.foundItem()) {
        //       await _pushDataToCache(pfsType, oid, file, tempDir);
        //     }
        //   }else {
        //     // 非pack类型，若不存在，直接上传，本地就是加密的文件，无需特殊处理
        //     final dataPath = genRemoteDataPath(remoteDataType, oid);
        //     if(!await exists(dataPath)) {
        //       await uploadFile(dataPath, file);
        //     }
        //   }
        // }

        // 不拷贝直接返回
        return file;
      }
    }

    // 先下载到临时文件
    // 下载到 tempDir/temp/oid
    final tempFile = await tempDir.getObjectFileUnderObjectsDir(oid.value);

    if(isPfsType) {
      // 检查文件是否在ObjBuf，若在直接使用；若不在，检查是否在 tempDir.pushCacheDir()，若在直接使用；若不在，下载或使用缓存的pack文件，然后提取文件。
      // 性能差别：objBuf better than tempDir.pushCacheDir() better than download and extract from pack file

      // 检查文件是否在obj buf（上传时，小文件存到内存中的objbuf对象里，大文件或objbuf满，则存硬盘）
      final objInBuf = _objBuf!.get(oid.value);
      if(objInBuf != null) {
        // 在objBuf里的肯定是小文件，直接write bytes就行，不需要Stream（Stream其实是封装的带buffer的一系列函数，
        // 带不带buffer不确定，肯定是一系列函数，要么调用获取函数时再从源拉取数据，要么就带buffer，先在内存存点，再拉）
        await writeBytesToFile(tempFile, objInBuf);
      }else {
        // 如果pushCache有文件，必是最新版，若无，从.pack文件里解压，.pack会被下载到tempDir/fetchCache里，
        // 下次再下载同一.pack内的数据会复用，所以实际上不会有多少网络请求，除非下载多个超过.pack容量限制的文件，
        // 那样就会下载很多.pack，导致网络请求变多
        // var fileInPushCache = await getLocalFileByOid(remoteDataType, (await tempDir.pushCacheDir()).absolute.path, oid, createParents: false);
        var fileInPushCache = await tempDir.getObjectPathUnderPushCacheDir(oid.value);

        if(await fileInPushCache.exists()) {
          // 直接使用pushCache/files|objects|msg/data.enc
          await fileInPushCache.copy(tempFile.absolute.path);
        }else {
          // 从.pack里解压
          final pfs = getPfsByType(pfsType);
          final findResult = await pfs.find(oid, findResultMap: objPfsFindResultMap!);
          // found
          if(findResult.foundItem()) {
            // fetchCache 里存的是pack文件，但files和objects和存正式文件的目录名对应，只是在fetchCache/files里存的是.pack文件，而不是提取出的.enc文件
            // e.g. tempDir/fetchCache/files/0.pack
            final packFile = await downloadPackFileToFetchCacheIfNeeded(pfsType, findResult, tempDir);

            await pfs.extractFromPackFile(packFile, findResult.packItem!, tempFile);
          }else {
            throw RemoteNotFoundException("oid doesn't exist in remote: ${oid.value}, err code: 12445962");
          }
        }
      }
    }else {
      // 非pfs type，也就是不打包的那种数据，话说不打包的会调用fetchData吗？好像不会来着？不过会不会无所谓，这个代码不用改。
      // 文件不存在，下载到temp目录，然后移动到正式目录，最后返回结果
      // final dataPath = genRemoteDataPath(remoteDataType, oid);
      // await downloadToFile(dataPath, targetFile, tempDir);

      throw RemoteException("please use download method to download the type: $remoteDataType, err code: 13022419");
    }

    // 就算要下载的文件大小为0，最起码也该创建这个文件，不可能不存在
    if(!await tempFile.exists()) {
      throw RemoteException("fetch data err: target file doesn't exist after download finished");
    }

    // 执行到这，文件下载成功了


    if(moveToRemoteDataDirAfterDownload) {
      final file = await getFileAndMakeSureParentDirExist(Repo.getLocalRemoteObjectPathByOidStr(remoteDataDirPath, oid.value));
      await tempFile.renameThenDelEmptyParent(file.absolute.path);

      // 注意这里返回的是正式目录的文件，不要删除（印象中应该没删除，也没出过错，所以问题不大）
      return file;
    }

    // 返回临时目录下的文件
    return tempFile;
  }

  Future<File> downloadPackFileToFetchCacheIfNeeded(RemoteDataType pfsType, PackFindResult findResult, TempDir tempDir) async {
    final targetFile = await getPackFileByNameFromFetchCache(findResult.packFile!.name, pfsType, tempDir);

    // 由于同一个session下，只有提交时才会上传，上传前会把.pack文件拷贝到pushCache/willPush/files|objects|msg/N.pack，
    // 然后才会修改对应的.pack文件，因此，在会话开始后，提交前，
    // 存在fetchCache里的远程下载的文件都是一样的，所以，检测下本地fetchCache里，如果已经存在对应文件，就不需要再次下载了
    if(!await targetFile.exists()) {
      if(findResult.packFile!.isEmpty()) {
        // pack文件大小为0，直接创建，无需下载
        await ObjPackFile.initFile(targetFile);
      }else {
        // 下载packFile到临时目录
        // 这个路径只是为了要前缀，例如：重命名前的路径可能是 files/pfs.enc，重命名后可能为 files/0.pack，由于 .pack 文件和pfs文件存在同一目录，所以可以这么搞
        final pfsPath = getRemotePfsPathByType(pfsType).copyThenRename(findResult.packFile!.name);

        // 下载到临时文件其实意义不大，因为如果这个操作出错，
        // 同步会中止，下次同步会创建新的临时目录，所以并不会使用损坏的文件，
        // 因此要么文件正常下载完成，可以使用，要么中止，被彻底丢弃，
        // 根本不会存在文件下载未完成，下次继续使用损坏的文件的情况
        // final tempFile = await tempDir.createTempFile();
        // await downloadToFile(pfsPath, tempFile);
        // await tempFile.rename(targetFile.absolute.path);

        await downloadToFile(pfsPath, targetFile, tempDir);
      }
    }

    return targetFile;
  }

  // Future<File> _deprecated_downloadPackFileIfNeeded(RemoteDataType remoteDataType, PackFindResult findResult, TempDir tempDir) async {
  //   final targetFile = getPackFileByName(findResult.packFile!.name, remoteDataType, tempDir);
  //   // 看下当前会话是否计算过hash，若计算过会缓存上，就不需要重新计算了
  //   final hashCacheKey = targetFile.absolute.path;
  //   var packFileHash = mapGetOrNull<String>(sessionStorage, hashCacheKey);
  //
  //   // 相等代表算过hash，算过代表文件存在，文件存在就不用下载了
  //   if(packFileHash != null && packFileHash.isNotEmpty && packFileHash == findResult.packFile!.hash) {
  //     return targetFile;
  //   }
  //
  //
  //   if(packFileHash == null || !await targetFile.exists()) {
  //     // 文件不存在，下载，然后存储hash
  //     // 下载packFile到临时目录
  //     // 这个路径只是为了要前缀，例如：重命名前的路径可能是 files/pfs.enc，重命名后可能为 files/0.pack，由于 .pack 文件和pfs文件存在同一目录，所以可以这么搞
  //     final pfsPath = getRemotePfsPathByType(remoteDataType).copyThenRename(findResult.packFile!.name);
  //     final pfsData = download(pfsPath);
  //     await writeStreamToFile(targetFile, pfsData);
  //     // 校验下hash
  //     final packFileHash = await hashStreamToHexStr(targetFile.openRead());
  //     sessionStorage[hashCacheKey] = packFileHash;
  //
  //     if(packFileHash != findResult.packFile!.hash) {
  //       throw RemoteException("packFile hash doesn't match, expect '${findResult.packFile!.hash}', got '$packFileHash', file path is '${targetFile.absolute.path}', err code: 11051479", null);
  //     }
  //   }else {
  //     // hash不是null 且 文件存在，说明hash不匹配，重复下载有可能解决，但万一文件本身就不对的话，重复下载等于浪费流量，所以直接抛异常了，正常情况下不应该出现这种情况，遇到这种情况，用户可以重试，还抛异常就没救了
  //     throw RemoteException("packFile hash doesn't match, expect '${findResult.packFile!.hash}', got '$packFileHash', file path is '${targetFile.absolute.path}', err code: 19235684", null);
  //   }
  //
  //   return targetFile;
  // }

  /// [oids] pass null to fetch all
  // Future<List<File>> _fetchDatas(
  //   RemoteDataType remoteDataType,
  //   List<String>? oids,
  //   String remoteDataDirPath,
  //   TempDir tempDir, {
  //   bool force = false,
  //   required bool moveToRemoteDataDirAfterDownload,
  // }) async {
  //   // oid列表不为null，且为空，直接不用下载了
  //   final downloadedFiles = <File>[];
  //   if(oids != null && oids.isEmpty) {
  //     return downloadedFiles;
  //   }
  //
  //   // 列出所有文件，然后下载
  //   final files = await listFilesByType(remoteDataType);
  //   for(final f in files) {
  //     // 必然是目录，因为路径是 oid/data.enc，如果不是目录，直接返回
  //     if(!f.isDir) {
  //       continue;
  //     }
  //
  //
  //     if(oids != null && !oids.contains(f.name)) {
  //       continue;
  //     }
  //
  //     // 下载
  //     final oid = VersionOid(value: f.name);
  //     final downloadedFile = await _fetchData(
  //       remoteDataType,
  //       oid,
  //       remoteDataDirPath,
  //       tempDir,
  //       force: force,
  //       moveToRemoteDataDirAfterDownload: moveToRemoteDataDirAfterDownload,
  //     );
  //
  //     downloadedFiles.add(downloadedFile);
  //   }
  //
  //   return downloadedFiles;
  // }

  /// 先在本地的remote/objects目录找下有无缓存，若无则下载，下载到缓存目录的objects目录中，然后移动到remote data dir/objects 目录下
  /// 注：本方法不会在下载后清理缓存，需要调用者自己清理
  /// 会下载到tempDir/objects/hash/data.enc
  /// 返回：下载的文件在缓存目录的绝对路径
  Future<File> fetchObject(
    VersionOid oid,
    String remoteDataDirPath,
    TempDir tempDir, {
    bool force = false,
    required bool moveToRemoteDataDirAfterDownload,
  }) {
    return _fetchData(
      RemoteDataType.objects,
      oid,
      remoteDataDirPath,
      tempDir,
      force: force,
      moveToRemoteDataDirAfterDownload: moveToRemoteDataDirAfterDownload,
    );
  }

  // Future<List<File>> fetchAllObjects(
  //   String remoteDataDirPath,
  //   TempDir tempDir, {
  //   bool force = false,
  //   required bool moveToRemoteDataDirAfterDownload
  // }) {
  //   return _fetchDatas(
  //     RemoteDataType.objects,
  //     null,
  //     remoteDataDirPath,
  //     tempDir,
  //     force: force,
  //     moveToRemoteDataDirAfterDownload: moveToRemoteDataDirAfterDownload
  //   );
  // }

  // Future<List<File>> fetchObjects(
  //   List<String> oids,
  //   String remoteDataDirPath,
  //   TempDir tempDir, {
  //   bool force = false,
  //   required bool moveToRemoteDataDirAfterDownload
  // }) {
  //   return _fetchDatas(
  //     RemoteDataType.objects,
  //     oids,
  //     remoteDataDirPath,
  //     tempDir,
  //     force: force,
  //     moveToRemoteDataDirAfterDownload: moveToRemoteDataDirAfterDownload
  //   );
  // }

  // 下载所有文件数据到缓存目录，可通过tempDir.filesDir()获取下载后的文件存储路径
  Future<FileInfo?> fetchFileInfo(
    //用文件在workdir的相对路径计算出的oid
    // 自己处理相对路径，错了找不到对象，不管
    VersionOid oid,
    TempDir tempDir, {
    bool force = false,
  }) async {
    final jsonMap = filesMap!.get(oid);
    if(jsonMap == null) {
      return null;
    }

    return FileInfo.fromJson(jsonMap);
  }

  Future<Msg?> fetchMsg(
    //用文件在workdir的相对路径计算出的oid
    VersionOid oid,
    TempDir tempDir, {
    bool force = false,
  }) async {
    final jsonMap = msgMap!.get(oid);
    if(jsonMap == null) {
      return null;
    }

    return Msg.fromJson(jsonMap);
  }

  // Future<List<File>> fetchAllMsg(
  //   String remoteDataDirPath,
  //   TempDir tempDir, {
  //   bool force = false,
  //   required bool moveToRemoteDataDirAfterDownload
  // }) {
  //   return _fetchDatas(
  //     RemoteDataType.msg,
  //     null,
  //     remoteDataDirPath,
  //     tempDir,
  //     force: force,
  //     moveToRemoteDataDirAfterDownload: moveToRemoteDataDirAfterDownload
  //   );
  // }


  // Future<List<File>> fetchFileInfos(
  //   List<FilePath> relativePaths,
  //   KeyData contentKeyData,
  //   String remoteDataDirPath,
  //   TempDir tempDir, {
  //   bool force = false,
  //   required bool moveToRemoteDataDirAfterDownload
  // }) async {
  //   final oids = <String>[];
  //   for(final rpath in relativePaths) {
  //     oids.add(await rpath.toOidStr(contentKeyData));
  //   }
  //
  //   return _fetchDatas(
  //     RemoteDataType.files,
  //     oids,
  //     remoteDataDirPath,
  //     tempDir,
  //     force: force,
  //     moveToRemoteDataDirAfterDownload: moveToRemoteDataDirAfterDownload
  //   );
  // }

  // Future<List<File>> fetchAllFileInfos(
  //   String remoteDataDirPath,
  //   TempDir tempDir, {
  //   bool force = false,
  //   required moveToRemoteDataDirAfterDownload
  // }) {
  //   return _fetchDatas(
  //     RemoteDataType.files,
  //     null,
  //     remoteDataDirPath,
  //     tempDir,
  //     force: force,
  //     moveToRemoteDataDirAfterDownload: moveToRemoteDataDirAfterDownload
  //   );
  // }

  /// return: 上传的objects的oid
  /// 若 remoteDataDir 不为空，会在上传完成后把加密后的objhash/data.enc移动到本地的remote/objects/objhash/data.enc
  /// 如果oid为空，会计算，否则直接用，错了不管，调用者需要确保rawfile不会被编辑(创建拷贝就行
  /// 如果oid不为空且remoteDataDir不为空，会先查看本地和远程的对应object是否存在，若存在，不会重新上传
  Future<void> pushRawFileToObject(
    VirtualFile rawFile,
    VersionOid oid,
    KeyData contentKeyData,
    String remoteDataDirPath,
    TempDir tempDir, {
    // 我得知道这个obj关联哪个fileinfo和msg
    // 不需要了，在上传msg和file info的时候，改成手动关联了，
    // 所以上传obj的时候空关联即可，但必须先上传obj后上传file info和msg（后来又修改了，
    // 所以这个也非必须了，只要提交前把关联整明白就行了，上传到object 到 pushCache时可以没有refs了）
    Set<ObjRef>? refs,
    bool force = false,
    required bool moveToRemoteDataDirAfterPushed,
    // 真的本地 remote 目录下的object路径是基于hash分目录的，
    // 假的（syncCache目录等）简化了处理，直接hash/data.enc，所以需要判断下
    // 通常调用这个函数时应该是真的remote data dir目录，所以此值是true的情况应该比较多
  }) async {
    if(ObjRef.isInvalidOid(oid.value)) {
      throw RemoteException("try pushing invalid object oid to remote, oid: ${oid.value}, err code: 17249635");
    }

    await _pushData(
      RemoteDataType.objects,
      rawFile,
      contentKeyData,
      oid,
      remoteDataDirPath,
      tempDir,
      force: force,
      moveToRemoteDataDirAfterPushed: moveToRemoteDataDirAfterPushed,
    );
  }

  /// 把数据先存到pushCache目录
  Future<void> _pushDataToCache(
    RemoteDataType pfsType,
    VersionOid oid,
    Stream<List<int>> dataStream,
    TempDir tempDir, {
    // 估算的要上传的数据大小，若流来自文件，则准；若来自enc data则不准但接近
    required int estimateLen,
    // if not null, copy data to path after pushed
    // 并不是直接拷贝的，会先拷贝到临时文件，再rename到此路径
    required String? copyToThisPathAfterPushed
  }) async {
    _requireSession(14598651);

    if(!pfsType.isPfs()) {
      throw RemoteException("expect pfs data type, but got '${pfsType.value}', err code: 16704365");
    }

    if(pfsType != RemoteDataType.objectsPfs) {
      throw RemoteException("only support push object data to cache, but got type: $pfsType");
    }

    final isImmutable = pfsType.isImmutable();
    final File? targetFile;
    // 先尝试添加数据到内存，若成功，直接返回，否则写入到文件
    if(await _objBuf!.addStream(oid, dataStream, estimateLen: estimateLen, isImmutable: isImmutable)) {
      targetFile = null;
    }else {
      // 若执行到这，说明文件过大，或内存buf满了，没办法，只能把数据存到硬盘上了，最后提交会话时会把内存和硬盘各扫一变，全部上传

      // e.g. tempDir/pushCache/objects/oid/data.enc
      targetFile = await tempDir.getObjectPathUnderPushCacheDir(oid.value);

      // 拷贝文件到pushCache目录，提交时会上传
      if(!isImmutable || !await targetFile.exists()) {
        await targetFile.parent.create(recursive: true);
        // 因为都是objects，不可变类型，所以检查下，若存在就不重复上传了
        await writeStreamToFile(targetFile, dataStream);
      }
    }

    // copy to local remote data dir or other path after pushed
    if(copyToThisPathAfterPushed != null) {
      final copyTargetFile = File(copyToThisPathAfterPushed);
      if(!await copyTargetFile.exists()) {
        final Stream<List<int>> data = targetFile == null ? Stream.value(_objBuf!.get(oid.value)!) : targetFile.openRead();
        final tempFile = await tempDir.createTempFile();
        await writeStreamToFile(tempFile, data);
        await tempFile.renameThenDelEmptyParent(copyToThisPathAfterPushed);
      }
    }

  }


  Future<Directory> getPfsSaveDirForPush(RemoteDataType pfsType, TempDir tempDir) async {
    // tempDir/pushCache/willPush
    // 本来想直接存到files等目录，但我不确定是否会导致遍历时多出这几个条目，所以创建个别的目录，用做最后的输出缓存
    // 把pfs.enc和 N.pack存到这里
    // e.g. tempDir/pushCache/willPush/pfs/files|objects|msg
    return await getAndMakeSureDirExists(Repo.getPfsDirPathByType(pfsType, (await tempDir.pushCacheWillPushDir()).absolute.path));
  }


  Future<Set<String>> _mergeObjBufToPack(
    RemoteDataType pfsType,
    TempDir tempDir, {
    bool force = false,  // 原本是用来检查如果此值为真且类型是不可变则覆盖式上传的，但后来弃用了此机制，若是不可变类型，一律不覆盖上传
    required ThrowIfInterrupted? throwIfTaskCanceled,
  }) async {
    if(pfsType != RemoteDataType.objectsPfs) {
      throw RemoteException("operate only support for object pfs, err code: 17742592");
    }

    final ObjPackFileStorage pfs;
    pfs = objectsPfs!;



    // tempDir/pushCache/pfs
    final pfsSaveDir = await getPfsSaveDirForPush(pfsType, tempDir);
    final pfsSaveDirPath = pfsSaveDir.absolute.path;

    final filePathsNeedPush = <String>{};


    for(final entry in _objBuf!.storage.entries) {
      final oid = VersionOid(value: entry.key);
      final dataBytes = entry.value;

      throwIfTaskCanceled?.call();


      // 由于后来改成在内存中的pfs实例中查找对象，然后往其refs里添加关联的msg和file info oid了，
      // x 不需要检查是否非空，一律添加_objRefsMap里的条目到refset，若重复，set会按oid自动去重）所以这里这个从文件中读取的objRefs很可能会是空
      final refsCnt = _objAddRefsCountMap![oid.value];
      if(refsCnt == null || refsCnt < 1) {
        throw RemoteException("try upload an object without refs? oid: ${oid.value}, err code: 18238271");
      }


      // x 废弃，如果一个packFile的所有packItems都删除，就会是空数组，
      // 对应的.pack文件大小就会是0，空文件，等等，这里检查的是data.enc文件大小啊，
      // data.enc大小不可能为0啊！，所以这个判断是有意义的？不对，还是没意义，
      // 因为这里上传的都是app生成的文件，所以应该不会出现大小为0的data.enc，因此不用判断，
      // 但如果，用户手动创建了文件，那有可能大小为0，有可能不为0，
      // 判断也没意义，所以，要么app生成的，不需要判断，要么用户手动在这个目录创建文件，判断也没意义，
      // 因此还是不需要判断，嗯，不判断了）正常不会出现size小于1的文件，检查文件大小是否为0
      final dataFileLen = dataBytes.length;
      // if(dataFileLen < 1) {
      //   continue;
      // }


      // x 由于重复条目根本不会上传，因此这里无需检查，最终通过判断refsCount集合是否为空以及objpfs是否有重复条目来判断操作是否有误即可）查找对应条目是否已经被上传
      // final findResult = await pfs.find(oid);
      // if(findResult.foundItem()) {
      //   // 因为限制了只能操作不可变数据，
      //   // 所以如果存在，就不用重新上传了
      //   // 但需要更新下附加信息，可能其他fileinfo或msg关联了同一个obj
      //   findResult.packItem!.addRc(refsCnt);
      //   pfs.updateContentId(lastObjectsPfsContentId);
      //
      //   _objAddRefsCountMap!.remove(oid.value);
      //
      //   continue;
      // }

      throwIfTaskCanceled?.call();

      // 需要上传
      final packFileFindResult = await pfs.findAFileLessThanMaxLen(dataFileLen, packMaxLen: packMaxLen);
      final File packFile;

      throwIfTaskCanceled?.call();

      final virtualFile = await VirtualFile.ofBytes(dataBytes);

      // 新增和追加共用一个缓存目录，因此不会重复添加且数据都会存到同一个地方，最后推送那个目录的文件即可
      if(packFileFindResult.foundFile()) {
        // 会从 pushCache/willPush/files|objects|msg/ 里找对应pack，如果有，则实际上不会执行下载
        final File cachedPackFile = await _downloadPackFileToPushCacheIfNeeded(
            packFileFindResult,
            pfsType,
            tempDir,
            // pfs,
            oid,
            saveDirPath: pfsSaveDirPath
        );

        // 追加数据到pack
        await pfs.appendDataToPackFile(packFileFindResult.packFileIndex, oid, cachedPackFile, virtualFile, lastObjectsPfsContentId, refsCount: refsCnt, extraForPackItem: {});
        packFile = cachedPackFile;
      }else {
        // 未找到，需要新增
        // 文件会输出到pfsSaveDir且更新pfs，下次，pfs查找时，就会包含这个.pack文件，若其有空间，
        // 就会进入上面的if，然后下载时从缓存里发现此文件，然后就不会重新下载，而是把数据累加到同一个文件中
        // 会把dataFile的内容追加到 pushCache/willPush/files|objects|msg/N.pack，N是packFiles的索引
        packFile = await pfs.addPackFile(oid, pfsSaveDir, virtualFile, lastObjectsPfsContentId, refsCount: refsCnt, extraForPackItem: {});
      }

      _objAddRefsCountMap!.remove(oid.value);

      // 添加到列表，稍后推送文件
      filePathsNeedPush.add(packFile.absolute.path);
    }

    return filePathsNeedPush;
  }

  Future<Set<String>> _mergeFileToPack(
    RemoteDataType pfsType,
    TempDir tempDir, {
    bool force = false,
    required ThrowIfInterrupted? throwIfTaskCanceled,
  }) async {
    if(pfsType != RemoteDataType.objectsPfs) {
      throw RemoteException("operate only support for object pfs, err code: 15089420");
    }

    final pushCacheDir = await tempDir.pushCacheDir();
    final pushCacheDirPath = pushCacheDir.absolute.path;
    final String dirPath = p.join(pushCacheDirPath, Repo.remoteObjectsDirName);
    final ObjPackFileStorage pfs = objectsPfs!;


    final dir = await getAndMakeSureDirExists(dirPath);

    // tempDir/pushCache/pfs
    final pfsSaveDir = await getPfsSaveDirForPush(pfsType, tempDir);
    final pfsSaveDirPath = pfsSaveDir.absolute.path;

    final filePathsNeedPush = <String>{};

    // pfs文件里存的原始数据的类型
    // final remoteDataType = pfsType.getNonPfsType()!;

    await for(final item in dir.list(followLinks: false)) {
      throwIfTaskCanceled?.call();

      // 目录结构和本地的appdata/remote目录一样：files/oid/data.enc，
      // 所以，这的item是其中的oid目录，若不是目录，就可返回了
      if(item is! Directory) {
        continue;
      }


      // files|objects|msg/oid/data.enc
      final dataFilePath = p.join(item.absolute.path, Repo.remoteDataFileName);
      final dataFile = File(dataFilePath);
      if(!await dataFile.exists()) {
        continue;
      }

      throwIfTaskCanceled?.call();


      // 目录名即是oid
      final oid = VersionOid(value: p.basename(item.path));

      // 由于后来改成在内存中的pfs实例中查找对象，然后往其refs里添加关联的msg和file info oid了，
      // x 不需要检查是否非空，一律添加_objRefsMap里的条目到refset，若重复，set会按oid自动去重）所以这里这个从文件中读取的objRefs很可能会是空
      final refsCnt = _objAddRefsCountMap![oid.value];
      if(refsCnt == null || refsCnt < 1) {
        throw RemoteException("try upload an object without refs? oid: ${oid.value}, err code: 17860159");
      }


      // x 废弃，如果一个packFile的所有packItems都删除，就会是空数组，
      // 对应的.pack文件大小就会是0，空文件，等等，这里检查的是data.enc文件大小啊，
      // data.enc大小不可能为0啊！，所以这个判断是有意义的？不对，还是没意义，
      // 因为这里上传的都是app生成的文件，所以应该不会出现大小为0的data.enc，因此不用判断，
      // 但如果，用户手动创建了文件，那有可能大小为0，有可能不为0，
      // 判断也没意义，所以，要么app生成的，不需要判断，要么用户手动在这个目录创建文件，判断也没意义，
      // 因此还是不需要判断，嗯，不判断了）正常不会出现size小于1的文件，检查文件大小是否为0
      final dataFileLen = await dataFile.length();
      // if(dataFileLen < 1) {
      //   continue;
      // }


      // 查找对应条目是否已经被上传
      // final findResult = await pfs.find(oid);
      // if(findResult.foundItem()) {
      //   // 因为限制了只能操作不可变数据，
      //   // 所以如果存在，就不用重新上传了
      //   // 但需要更新下附加信息，可能其他fileinfo或msg关联了同一个obj
      //   findResult.packItem!.addRc(refsCnt);
      //   pfs.updateContentId(lastObjectsPfsContentId);
      //
      //   // 清空，后续更新已存在obj的关联时就跳过对应条目了
      //   _objAddRefsCountMap!.remove(oid.value);
      //
      //   continue;
      // }

      throwIfTaskCanceled?.call();

      // 需要上传
      final packFileFindResult = await pfs.findAFileLessThanMaxLen(dataFileLen, packMaxLen: packMaxLen);
      final File packFile;

      throwIfTaskCanceled?.call();

      final virtualFile = await VirtualFile.ofFile(dataFilePath);

      // 新增和追加共用一个缓存目录，因此不会重复添加且数据都会存到同一个地方，最后推送那个目录的文件即可
      if(packFileFindResult.foundFile()) {
        // 会从 pushCache/willPush/files|objects|msg/ 里找对应pack，如果有，则实际上不会执行下载
        final File cachedPackFile = await _downloadPackFileToPushCacheIfNeeded(
          packFileFindResult,
          pfsType,
          tempDir,
          // pfs,
          oid,
          saveDirPath: pfsSaveDirPath
        );

        // 追加数据到pack
        await pfs.appendDataToPackFile(packFileFindResult.packFileIndex, oid, cachedPackFile, virtualFile, lastObjectsPfsContentId, refsCount: refsCnt, extraForPackItem: {});
        packFile = cachedPackFile;
      }else {
        // 未找到，需要新增
        // 文件会输出到pfsSaveDir且更新pfs，下次，pfs查找时，就会包含这个.pack文件，若其有空间，
        // 就会进入上面的if，然后下载时从缓存里发现此文件，然后就不会重新下载，而是把数据累加到同一个文件中
        // 会把dataFile的内容追加到 pushCache/willPush/files|objects|msg/N.pack，N是packFiles的索引
        packFile = await pfs.addPackFile(oid, pfsSaveDir, virtualFile, lastObjectsPfsContentId, refsCount: refsCnt, extraForPackItem: {});
      }


      // 清空，后续更新已存在obj的关联时就跳过对应条目了
      _objAddRefsCountMap!.remove(oid.value);


      // 添加到列表，稍后推送文件
      filePathsNeedPush.add(packFile.absolute.path);
    }

    return filePathsNeedPush;
  }

  // 返回合并后的，待推送的文件path列表
  // Future<Set<String>> _mergeFileToPackDeprecated(
  //   RemoteDataType pfsType,
  //   TempDir tempDir, {
  //   bool force = false,
  //   required ThrowIfInterrupted? throwIfTaskCanceled,
  // }) async {
  //   if(pfsType != RemoteDataType.objectsPfs) {
  //     throw RemoteException("operate only support for object pfs, err code: 19754643", null);
  //   }
  //   final pushCacheDir = await tempDir.pushCacheDir();
  //   final pushCacheDirPath = pushCacheDir.absolute.path;
  //   final String dirPath;
  //   final ObjPackFileStorage pfs;
  //   dirPath = p.join(pushCacheDirPath, Repo.remoteObjectsDirName);
  //   pfs = objectsPfs!;
  //
  //
  //   final dir = await getAndMakeSureDirExists(dirPath);
  //
  //   // tempDir/pushCache/pfs
  //   final pfsSaveDir = await getPfsSaveDirForPush(pfsType, tempDir);
  //   final pfsSaveDirPath = pfsSaveDir.absolute.path;
  //
  //   final filePathsNeedPush = <String>{};
  //
  //   // pfs文件里存的原始数据的类型
  //   final remoteDataType = pfsType.getNonPfsType()!;
  //
  //   await for(final item in dir.list(followLinks: false)) {
  //     throwIfTaskCanceled?.call();
  //
  //     // 目录结构和本地的appdata/remote目录一样：files/oid/data.enc，
  //     // 所以，这的item是其中的oid目录，若不是目录，就可返回了
  //     if(item is! Directory) {
  //       continue;
  //     }
  //
  //
  //     // files|objects|msg/oid/data.enc
  //     final dataFile = File(p.join(item.absolute.path, Repo.remoteDataFileName));
  //     if(!await dataFile.exists()) {
  //       continue;
  //     }
  //
  //     // 如果有extra文件，读取下，存到pfs.enc里
  //     final extraFile = File(p.join(dataFile.parent.absolute.path, packItemExtraFileName));
  //     Map<String, dynamic>? packItemExtraData;
  //     if(await extraFile.exists()) {
  //       packItemExtraData = jsonDecode(await extraFile.readAsString());
  //     }
  //
  //     // x 废弃，如果一个packFile的所有packItems都删除，就会是空数组，
  //     // 对应的.pack文件大小就会是0，空文件，等等，这里检查的是data.enc文件大小啊，
  //     // data.enc大小不可能为0啊！，所以这个判断是有意义的？不对，还是没意义，
  //     // 因为这里上传的都是app生成的文件，所以应该不会出现大小为0的data.enc，因此不用判断，
  //     // 但如果，用户手动创建了文件，那有可能大小为0，有可能不为0，
  //     // 判断也没意义，所以，要么app生成的，不需要判断，要么用户手动在这个目录创建文件，判断也没意义，
  //     // 因此还是不需要判断，嗯，不判断了）正常不会出现size小于1的文件，检查文件大小是否为0
  //     final dataFileLen = await dataFile.length();
  //     // if(dataFileLen < 1) {
  //     //   continue;
  //     // }
  //
  //
  //     // 目录名即是oid
  //     final oid = VersionOid(value: p.basename(item.path));
  //
  //     // 查找对应条目是否已经被上传
  //     final findResult = await pfs.find(oid);
  //     if(findResult.foundItem()) {
  //       // 不可变数据，如果存在，就不用重新上传了
  //       // 注：如果force为真，即使是不可变类型，也会删了重新上传
  //       if(!force && remoteDataType.isImmutable()) {
  //         continue;
  //       }else {
  //         // 删除旧的
  //         // 下载到 pushCache/willPush/files|objects|msg/文件名.pack
  //         final File cachedPackFile = await _downloadPackFileToPushCacheIfNeeded(
  //           findResult,
  //           pfsType,
  //           tempDir,
  //           pfs,
  //           oid,
  //           saveDirPath: pfsSaveDirPath
  //         );
  //
  //         await pfs.removeItemFromPackFile(findResult, cachedPackFile, tempDir);
  //       }
  //     }
  //
  //     // 需要上传
  //     final packFileFindResult = await pfs.findAFileLessThanMaxLen(dataFileLen);
  //     final File packFile;
  //     // 新增和追加共用一个缓存目录，因此不会重复添加且数据都会存到同一个地方，最后推送那个目录的文件即可
  //     if(packFileFindResult != null && packFileFindResult.foundFile()) {
  //       // 会从 pushCache/willPush/files|objects|msg/ 里找对应pack，如果有，则实际上不会执行下载
  //       final File cachedPackFile = await _downloadPackFileToPushCacheIfNeeded(
  //         packFileFindResult,
  //         pfsType,
  //         tempDir,
  //         pfs,
  //         oid,
  //         saveDirPath: pfsSaveDirPath
  //       );
  //
  //       // 追加数据到pack
  //       await pfs.appendDataToPackFile(packFileFindResult.packFileIndex, oid, cachedPackFile, dataFile, extraForPackItem: packItemExtraData);
  //       packFile = cachedPackFile;
  //     }else {
  //       // 未找到，需要新增
  //       // 文件会输出到pfsSaveDir且更新pfs，下次，pfs查找时，就会包含这个.pack文件，若其有空间，
  //       // 就会进入上面的if，然后下载时从缓存里发现此文件，然后就不会重新下载，而是把数据累加到同一个文件中
  //       // 会把dataFile的内容追加到 pushCache/willPush/files|objects|msg/N.pack，N是packFiles的索引
  //       packFile = await pfs.addPackFile(oid, pfsSaveDir, dataFile, extraForPackItem: packItemExtraData);
  //     }
  //
  //     // 添加到列表，稍后推送文件
  //     filePathsNeedPush.add(packFile.absolute.path);
  //   }
  //
  //   return filePathsNeedPush;
  // }

  /// 先看看pfsSaveDirPath里有无(此目录一般是tempDir/pushCache/willPush)，
  /// 若无，看tempDir/fetchCache，若无，则下载
  Future<File> _downloadPackFileToPushCacheIfNeeded(
    PackFindResult packFileFindResult,

    RemoteDataType pfsType,
    TempDir tempDir,
    // ObjPackFileStorage pfs,
    VersionOid oid, {
    /// 由于这个函数经常在循环里调用，所以，支持路径传参，不然每次都要检查路径是否存在，然后创建，浪费性能
    String? saveDirPath,
    bool moveToWillPushDirInsteadOfCopy = true
  }) async {
    if(pfsType != RemoteDataType.objectsPfs) {
      throw RemoteException("only support operate object pack file, err code: 15630487");
    }

    final pfsSaveDirPath = saveDirPath ?? (await getPfsSaveDirForPush(pfsType, tempDir)).absolute.path;

    // willPush里如果有对应pack文件，直接使用，否则下载到fetchCache，再移动或拷贝到willPush里
    // 先检查文件是否在本地，如果是在当前函数之前循环新建的packFile，远程不会有对应文件的
    // 如果这里有对应文件，要么是在else里新增的，要么是在下面的if不存在则下载的代码块里下载，然后拷贝到这里的
    // e.g. tempDir/pushCache/willPush/files|objects|msg/0.pack
    var packFile = File(p.join(pfsSaveDirPath, packFileFindResult.packFile!.name));
    // 本地没有，下载
    if(!await packFile.exists()) {
      // 如果当前已经执行到提交阶段，就不需要fetch cache了，直接下载到packFile path即可
      final downloadedPackFile = await downloadPackFileToFetchCacheIfNeeded(pfsType, packFileFindResult, tempDir);
      if(moveToWillPushDirInsteadOfCopy) {
        await downloadedPackFile.renameThenDelEmptyParent(packFile.absolute.path);
      }else {
        await downloadedPackFile.copy(packFile.absolute.path);
      }
    }

    return packFile;
  }

  // Future<void> _delFromPackFile(
  //   RemoteDataType pfsType,
  //   TempDir tempDir, {
  //   ThrowIfInterrupted? throwIfTaskCanceled
  // }) async {
  //   final List<VersionOid>? list;
  //   final ObjPackFileStorage pfs;
  //   if(pfsType != RemoteDataType.objectsPfs) {
  //     throw RemoteException("only support operate objects pack file, err code: 16407618", null);
  //   }
  //
  //   list = mapGetOrNull(sessionStorage, keyWillDelObjs);
  //   pfs = objectsPfs!;
  //
  //
  //   final pfsSaveDir = await getPfsSaveDirForPush(pfsType, tempDir);
  //   final pfsSaveDirPath = pfsSaveDir.absolute.path;
  //
  //   if(list != null && list.isNotEmpty) {
  //     for(final oid in list) {
  //       throwIfTaskCanceled?.call();
  //
  //       final foundResult = await pfs.find(oid);
  //
  //       if(foundResult.foundItem()) {
  //         final cachedPackFile = await _downloadPackFileToPushCacheIfNeeded(
  //           foundResult,
  //           pfsType,
  //           tempDir,
  //           pfs,
  //           oid,
  //           saveDirPath: pfsSaveDirPath
  //         );
  //
  //         await pfs.removeItemFromPackFile(foundResult, cachedPackFile, tempDir);
  //       }
  //     }
  //   }
  // }

  // 删完后文件存在pushCache里，然后调用flushPush，就推上去了
  // Future<void> _flushDelCache(
  //   TempDir tempDir, {
  //   required ThrowIfInterrupted? throwIfTaskCanceled,
  // }) async {
  //   await _delFromPackFile(RemoteDataType.objectsPfs, tempDir, throwIfTaskCanceled: throwIfTaskCanceled);
  // }


  // 返回修改后的文件路径，之后可以推送这些文件
  Future<Set<String>> _delNoRefedObjects(
    TempDir tempDir, {
    required ThrowIfInterrupted? throwIfTaskCanceled,
  }) async {
    // 如果引用计数集合为空，跳过
    final objectsPfs = this.objectsPfs;
    if(objectsPfs == null) {
      throw RemoteException("objects pfs is null, err code: 17608455");
    }

    final objPfsFindResultMap = this.objPfsFindResultMap;
    if(objPfsFindResultMap == null) {
      throw RemoteException("objects pfs result map is null, err code: 12707846");
    }

    if(objectsPfs.contentId != objPfsFindResultMap.contentId) {
      // 两者不相等，其实可用for each查找，但性能差，所以不如直接抛异常让程序员解决这两个变量不相等的bug
      throw RemoteException("objects pfs result map contentId and objects pfs contentId didn't match, err code: 12566129");
    }

    final refsCountMap = _objAddRefsCountMap!;
    if(refsCountMap.isEmpty && lastObjectsPfsContentId == objectsPfs.contentId) {
      // 若无新增或删除引用记数 且 pfs文件无修改，可跳过遍历pfs。
      // 影响：如果用非正常方式把某个obj的引用计数设为0，而不是通过refsCountMap，
      // 则这时会导致对应条目不会立即删除，直到下次通过refsCountMap添加或删除引用，
      // 也就是可能会导致“删除条目延迟”，后果可接受，所以跳过，以提升性能
      return {};
    }

    bool pfsChanged = false;
    final Map<String, Set<PackFindResult>> willRemovedObjsGroupedByPackFile = {};
    final handledRefsCount = <String>{}; // oid set include handled refs items
    for(final entry in refsCountMap.entries) {
      // refs count有可能是负数，因为有可能deRef过，导致减成负数了，不过正常来说只会归0，不会负，但负也行，这时会移除后续条目
      final findResult = await objectsPfs.find(VersionOid(value: entry.key), findResultMap: objPfsFindResultMap);
      if(findResult.foundItem()) {
        pfsChanged = true;
        handledRefsCount.add(entry.key);

        final packItem = findResult.packItem!;
        packItem.addRc(entry.value);

        if(packItem.canDel()) {
          final packFile = findResult.packFile!;
          Set<PackFindResult>? willRemovedItemsOfThisPackFile = willRemovedObjsGroupedByPackFile[packFile.name];
          if(willRemovedItemsOfThisPackFile == null) {
            willRemovedItemsOfThisPackFile = {};
            willRemovedObjsGroupedByPackFile[packFile.name] = willRemovedItemsOfThisPackFile;
          }

          willRemovedItemsOfThisPackFile.add(findResult);
        }
      }
    }

    // 删除已经处理过的条目
    if(refsCountMap.length == handledRefsCount.length) {
      // 由于会去重，而且handledRefsCount添加的全是refsCountMap的key，所以若两者长度相等，必然完全相同，直接清空即可
      refsCountMap.clear();
    }else {
      // 长度不相等，移除已经处理过的条目（移除性能比不过替换成占位符，但移除更省内存，用占位符处理有点麻烦，所以暂时先实现成移除，性能差别一般应该不会太大）
      for(final handledOid in handledRefsCount) {
        refsCountMap.remove(handledOid);
      }
    }

    handledRefsCount.clear();

    // 要解除关联的必然是已存在的objects，必然在上面的列表被遍历到，若没，则有bug
    // 后面还要添加新的引用，添加后此集合才应为空，所以这里不检测
    // throwIfObjDeRefsMapIsNotClean();

    if(pfsChanged) {
      objectsPfs.updateContentId(lastObjectsPfsContentId);
      objPfsFindResultMap.contentId = objectsPfs.contentId;
    }

    if(willRemovedObjsGroupedByPackFile.isEmpty) {
      return {};
    }

    final packFilesNeedPush = <String>{};

    // tempDir/pushCache/willPush/pfs
    final pfsType = RemoteDataType.objectsPfs;
    final pfsSaveDir = await getPfsSaveDirForPush(pfsType, tempDir);
    final pfsSaveDirPath = pfsSaveDir.absolute.path;
    final Map<String, File> packNameAndFileMap = {};

    throwIfTaskCanceled?.call();

    // 删除数据
    for(final foundResults in willRemovedObjsGroupedByPackFile.values) {
      throwIfTaskCanceled?.call();

      if(foundResults.isEmpty) {
        continue;
      }

      // 注意：N.pack 那些 pack file 一旦创建就不会删除，就算清空也会保留只有header长度的“空文件”
      //取出第一个只是为了下载pack文件用的，用其oid下载，file name作缓存map的key，若下载过，直接从map里取，避免重复下载
      final foundResultForDownloadPackFile = foundResults.first;
      final packFileName = foundResultForDownloadPackFile.packFile!.name;
      File? realPackFile = packNameAndFileMap[packFileName];
      // 若之前没下载过pack file，下载，下载后添加到map，下次就不会重复下载了（就算重复下载其实也是有缓存的，但会涉及硬盘io，还是慢）
      if(realPackFile == null) {
        final cachedPackFile = await _downloadPackFileToPushCacheIfNeeded(
          foundResultForDownloadPackFile,
          pfsType,
          tempDir,
          // objectsPfs!,
          VersionOid(value: foundResultForDownloadPackFile.packItem!.oid),
          saveDirPath: pfsSaveDirPath
        );

        packNameAndFileMap[packFileName] = cachedPackFile;
        realPackFile = cachedPackFile;
      }

      // fastRemoveIfPossible 若true，则foundResults.length和packFile.items.length相等的情况下直接跳过所有条目，创建一个空文件
      // 应仅在能保证foundResults不包含重复结果，并且其条目一定在packFiles内时，启用此选项，这里可以保证，故启用
      await objectsPfs!.removeItemsFromPackFile(foundResults, realPackFile, tempDir, lastObjectsPfsContentId, fastRemoveIfPossible: true);

      packFilesNeedPush.add(realPackFile.absolute.path);
    }

    return packFilesNeedPush;
  }

  void throwIfObjRefsMapIsNotClean() {
    if(_objAddRefsCountMap!.isNotEmpty) {
      throw RemoteException("have one or more object refs not referenced/de-referenced to the objects, err code: 12019923");
    }

    // for(final refs in _objAddRefsMap!.values) {
    //   if(refs.isNotEmpty) {
    //     throw RemoteException("have one or more object refs not referenced to the objects, err code: 12019923", null);
    //   }
    // }
  }

  // void throwIfObjDeRefsMapIsNotClean() {
  //
  //   for(final refs in _objDeRefsMap!.values) {
  //     if(refs.isNotEmpty) {
  //       throw RemoteException("have one or more object refs not de-referenced to the objects, err code: 13370794", null);
  //     }
  //   }
  // }

  Future<List<FilePathPair>> _flushPushCache(
    KeyData contentKeyData,
    TempDir tempDir, {
    bool force = false,
    required ThrowIfInterrupted? throwIfTaskCanceled,
    String? newSyncHistoryNodeOid,
  }) async {
    final packFilesWhichDeletedItemsNeedPush = await _delNoRefedObjects(tempDir, throwIfTaskCanceled: throwIfTaskCanceled);

    // 上传.pack文件到临时目录，然后调用者上传pfs.enc，就全了
    // 返回的FilePath是remote可用的path和匹配的重命名后的路径，可用来在最后一步调用renameBatch
    // 例如：上传文件12.pack到temp目录abcdef.temp，但这个文件实际是 files/oid/12.pack，
    // 这时file pair左边是远程临时目录下的文件路径，右边是正式路径，
    // 这样搞是为了避免部分上传成功，部分失败，导致数据有误

    final objPacksWillPushFromObjBuf = await _mergeObjBufToPack(
      RemoteDataType.objectsPfs,
      tempDir,
      force: force,
      throwIfTaskCanceled: throwIfTaskCanceled
    );

    // obj buf用完了，可清了（缓存文件的buf，尽量手动清一下，尽早释放内存）
    await _objBuf!.clear();

    final objPacksWillPush = await _mergeFileToPack(
      RemoteDataType.objectsPfs,
      tempDir,
      force: force,
      throwIfTaskCanceled: throwIfTaskCanceled
    );


    throwIfObjRefsMapIsNotClean();

    throwIfTaskCanceled?.call();

    // 整合所有待推送的文件到一个集合
    objPacksWillPush.addAll(objPacksWillPushFromObjBuf);
    objPacksWillPushFromObjBuf.clear();
    objPacksWillPush.addAll(packFilesWhichDeletedItemsNeedPush);
    packFilesWhichDeletedItemsNeedPush.clear();

    throwIfTaskCanceled?.call();

    await objectsPfs!.throwIfHaveDuplicationOrPackFileLengthLessThan0(errCode: "18321806");

    throwIfTaskCanceled?.call();

    final List<FilePathPair> pushedPaths = [];
    final willPushDirPath = (await tempDir.pushCacheWillPushDir()).absolute.path;

    final uploadTasks = <Future Function()>[];

    throwIfTaskCanceled?.call();

    // 逐个pfs推
    for(final remoteDataType in RemoteDataType.pfsTypes) {
      // 改成只有objects 使用 pfs了，msg 和files直接用map
      if(remoteDataType != RemoteDataType.objectsPfs) {
        continue;
      }

      throwIfTaskCanceled?.call();

      final Set<String> packFilePaths;
      final String dirName;
      final ObjPackFileStorage pfs;
      final String lastPfsContentId;
      final String keyEncPfsPath;
      packFilePaths = objPacksWillPush;
      dirName = Repo.remoteObjectsDirName;
      pfs = objectsPfs!;
      lastPfsContentId = lastObjectsPfsContentId!;
      keyEncPfsPath = keyEncObjectsPfsPath;

      final remotePfsPath = getRemotePfsPathByType(remoteDataType);

      // 顺序不能变，把pack放列表前面，避免先重命名pfs失败，然后指向不存在的pack

      throwIfTaskCanceled?.call();

      // 推送pack文件
      for(final packFilePath in packFilePaths) {
        throwIfTaskCanceled?.call();

        final packFileName = p.basename(packFilePath);

        // 前缀示例： msg_0.pack_，之后会追加上随机字符串.temp，最终文件名可能是：msg_0.pack_abc122随机字符串.temp
        uploadTasks.add(() =>
          uploadFileToSyncCache(
            File(packFilePath),
            tempNamePrefix: "${dirName}_${packFileName}_",
            onFinish: (tempPath) async {
              final pair = FilePathPair();
              pair.left = tempPath;
              // pfs.enc和.pack们在同一目录，所以取出pfs.enc，然后把末尾的文件名改成pack文件的名字即可
              pair.right = RepoPathPlaceHolder.replacePrefixForRemote(
                  this,
                  remotePfsPath.copyThenRename(packFileName)
              );

              pushedPaths.add(pair);
            }
          )
        );
      }

      throwIfTaskCanceled?.call();

      // 如果有packfile需要推送 或 contentId变了，说明修改了pfs.enc，否则说明没改，没改就不用推送
      // 注：通过pfs内部函数append或add或remove数据时，contentId会变
      if(packFilePaths.isNotEmpty || pfs.contentId != lastPfsContentId) {
        final encData = await EncryptedData.compressThenEncrypt(pfs.toJsonByteStream(), contentKeyData);

        // 推送 pfs.enc，例如推送 tempDir/pushCache/willPush/pfs/objects/pfs.enc 到远程临时目录
        final pfsTempFile = await getFileAndMakeSureParentDirExist(Repo.getPfsFilePathWithSpecifiedDirName(willPushDirPath, dirName));
        await encData.writeToFile(pfsTempFile);
        uploadTasks.add(() =>
          uploadFileToSyncCache(
            pfsTempFile,
            // 前缀 e.g. msg_pfs.enc_，最后上传的临时文件名格式为：msg_pfs.enc_随机字符串.temp
            tempNamePrefix: "${dirName}_${pfsFileName}_",
            onFinish: (pfsTempPath) async {
              throwIfTaskCanceled?.call();

              sessionStorage[keyEncPfsPath] = pfsTempFile.absolute.path;

              final pfsPair = FilePathPair();
              pfsPair.left = pfsTempPath;
              pfsPair.right = RepoPathPlaceHolder.replacePrefixForRemote(this, remotePfsPath);
              pushedPaths.add(pfsPair);
            }
          )
        );
      }
    }

    throwIfTaskCanceled?.call();

    // 把当前files map拷贝到临时文件
    // 若左值为null，说明本次没上传files map，直接使用原来的files map即可，若非null，则更新了，使用最新的files map
    Future<void> copyFilesMapToBakDir(FilePath filesMapOfThisHistoryNode) async {
      // 检查下源文件是否存在，若新建仓库，可能没有files map，就不需要拷贝了
      if(!await exists(filesMapOfThisHistoryNode)) {
        return;
      }

      // filesMap 存在，拷贝到syncCache，之后commit时会移动到bak目录
      final tempFilePath = genRemoteTempFilePath(base: remoteSyncCacheFilesDirPath(), prefix: "${filesMapFileName}_copy_");
      await copy(filesMapOfThisHistoryNode, tempFilePath, isDir: false);

      throwIfTaskCanceled?.call();

      final pathPairOfFilesMapCopy = FilePathPair();
      pathPairOfFilesMapCopy.left = tempFilePath;
      pathPairOfFilesMapCopy.right = RepoPathPlaceHolder.replacePrefixForRemote(
        this,
        genRemoteFilesMapBakFilePath(historyNodeOid: newSyncHistoryNodeOid!)
      );

      pushedPaths.add(pathPairOfFilesMapCopy);
    }

    final syncHistoryUpdated = newSyncHistoryNodeOid != null && newSyncHistoryNodeOid.isNotEmpty;
    final filesMapUpdated = lastFilesMapContentId != filesMap!.contentId;
    // 上传files map
    if(filesMapUpdated) {
      final encData = await EncryptedData.compressThenEncrypt(filesMap!.toJsonByteStream(), contentKeyData);

      // tempDir/pushCache/map/files.enc
      final tempFile = await getFileAndMakeSureParentDirExist(Repo.getFilesMapFilePath(willPushDirPath));

      await encData.writeToFile(tempFile);

      uploadTasks.add(() =>
        // 上传
        uploadFileToSyncCache(
          tempFile,
          tempNamePrefix: "${filesMapFileName}_",
          onFinish: (tempPath) async {
            throwIfTaskCanceled?.call();

            final pathPair = FilePathPair();
            pathPair.left = tempPath;
            pathPair.right = RepoPathPlaceHolder.replacePrefixForRemote(this, remoteFilesMapPath());
            pushedPaths.add(pathPair);

            // 若历史记录已更新，拷贝刚上传的filesMap，之后会移动到bak目录
            // 若历史记录没更新则不需要上传新的filesMap
            // ps. 其实如果filesMap更新，基本上，可以说，百分百历史记录也会更新，所以这个判断其实可有可无？不过保留也没什么坏处就是了，所以暂且保留
            if(syncHistoryUpdated) {
              await copyFilesMapToBakDir(tempPath);
            }
          }
        )
      );

    }

    throwIfTaskCanceled?.call();

    // 上传msg map
    if(lastMsgMapContentId != msgMap!.contentId) {
      final encData = await EncryptedData.compressThenEncrypt(msgMap!.toJsonByteStream(), contentKeyData);

      // tempDir/pushCache/map/files.enc
      final tempFile = await getFileAndMakeSureParentDirExist(Repo.getMsgMapFilePath(willPushDirPath));

      await encData.writeToFile(tempFile);

      uploadTasks.add(() =>
        uploadFileToSyncCache(
          tempFile,
          tempNamePrefix: "${msgMapFileName}_",
          onFinish: (tempPath) async {
            throwIfTaskCanceled?.call();

            final pathPair = FilePathPair();
            pathPair.left = tempPath;
            pathPair.right = RepoPathPlaceHolder.replacePrefixForRemote(this, remoteMsgMapPath());
            pushedPaths.add(pathPair);
          }
        )
      );
    }


    throwIfTaskCanceled?.call();

    if(syncHistoryUpdated) {  // 非null说明syncHistory更新了，需要上传 （忽然发现以前是不管更新与否都上传新的syncHistory）
      // 上传syncHistory
      // tempDir/pushCache/willPush/syncHistory.enc
      final syncHistoryEncFile = File(p.join((await tempDir.pushCacheWillPushDir()).absolute.path, Repo.syncHistoryFileName));
      uploadTasks.add(() =>
        uploadFileToSyncCache(
          syncHistoryEncFile,
          tempNamePrefix: "${Repo.syncHistoryFileName}_",
          onFinish: (tempPath) async {
            throwIfTaskCanceled?.call();

            final pathPair = FilePathPair();
            pathPair.left = tempPath;
            pathPair.right = RepoPathPlaceHolder.replacePrefixForRemote(
                this,
                getRemoteSyncHistoryPath()
            );
            pushedPaths.add(pathPair);
          }
        )
      );

      // 如果同步历史更新了但没文件更新，直接拷贝正式目录的filesMap即可（否则拷贝刚刚上传的）
      // 如果更新了文件，则会在上面上传完filesMap后拷贝，这里无需操作
      // 注：历史记录更新并不一定有文件需要推送，所以完全有可能更新了历史但没更新filesMap，所以这个判断不能省略
      //    比如上一个节点为Clean时，下个同步不管是否有文件更新都会创建新节点以标记当前同步历史已经在clean后检查过了，
      //    至于这么标记的意义，我忘了，可能是因为clean后不确定有哪些影响，所以需要检查下
      if(!filesMapUpdated) {
        await copyFilesMapToBakDir(remoteFilesMapPath());
      }
    }


    // 将来改成上传ignore文件
    // if(lastIndexContentId != index!.contentId) {
    //   final encData = await EncryptedData.compressThenEncrypt(index!.toJsonByteStream(), contentKeyData, syncVersion);
    //
    //   // tempDir/pushCache/willPush/index.enc
    //   final tempFile = getFileAndMakeSureParentDirExist(p.join(willPushDirPath, indexFileName));
    //
    //   await encData.writeToFile(tempFile);
    //
    //   // 上传
    //   final tempPath = await uploadFileToSyncCache(tempFile);
    //   final pathPair = FilePathPair();
    //   pathPair.left = tempPath;
    //   pathPair.right = remoteIndexPath();
    //   pushedPaths.add(pathPair);
    // }

    await runTaskConcurrencyIfAllow(uploadTasks, isRead: false);


    // 一个文件也没上传，记个log
    if(pushedPaths.isEmpty) {
      App.logger.debug(_TAG, "#_flushPushCache: no files pushed");
      // return pushedPaths;
    }

    return pushedPaths;
  }

  Future<VersionOid> _pushData(
    RemoteDataType remoteDataType,
    VirtualFile file,
    KeyData contentKeyData,
    VersionOid oid,
    String remoteDataDirPath,
    TempDir tempDir, {
    bool force = false,
    // 若true，本地无远程有，会下载；否则直接加密当前文件然后拷贝到本地对应目录；前者性能差，但本地和远程文件完全一样，后者性能好，但本地文件是重新加密的，明文和远程一样，但已加密文件不同。
    // 一般只保证明文相同即可，所以默认用后者。
    // bool fetchIfRemoteHaveDataButLocalHasnt = false,
    required bool moveToRemoteDataDirAfterPushed,
  }) async {
    if(remoteDataType != RemoteDataType.objects) {
      throw RemoteException("only support push remote data type object, but got type: $remoteDataType");
    }

    // final remoteDataPath = genRemoteDataPath(remoteDataType, oid);

    final pfsType = remoteDataType.getPfsType();
    final isPfsType = pfsType != null;

    // 以后这个函数只支持推送pfsType了，日后重构代码可直接删除后续代码中非pfsType的else分支
    if(!isPfsType) {
      throw RemoteException("only support call pushData for object pfsType, err code: 15965992");
    }

    if(isPfsType) {
      _requireSession(10422357);
    }


    // 加密数据
    // 若是pfs类型，返回Stream；否则File
    Future<dynamic> encDataToFile() async {
      final encryptedData = await EncryptedData.compressThenEncrypt(file.dataStream(), contentKeyData);

      if(isPfsType) {
        // pfs类型先返回stream，后续push to cache dir时，
        // 判断，如果文件过大或内存buffer capacity满了，则先存到硬盘然后再上传；
        // 否则直接存到内存然后从内存打包进pack file，最后再上传pack file
        return encryptedData.toByteStream();
      }else {
        // 非pfs类型（上传前不需打包，直接上传文件）
        // 先写到临时文件，再上传和移动，不然需要加密数据两次，因为一个加密流只能消费一次
        final tempFile = await tempDir.getObjectFileUnderObjectsDir(oid.value);
        await writeStreamToFile(tempFile, encryptedData.toByteStream());
        return tempFile;
      }
    }

    final localFile = await getFileAndMakeSureParentDirExist(Repo.getLocalRemoteObjectPathByOidStr(remoteDataDirPath, oid.value));

    Future<void> moveFileToLocal(dynamic tempFile) async {
      if(isPfsType) {
        tempFile as Stream<List<int>>;
        final tempFile2 = await tempDir.createTempFile();
        // 这个加密流肯定会消费的，不论是存到pushCache目录内对应文件；
        // 还是把流中数据读取到内存，都一定会消费，所以再移动就会报错，这时，应在push to cache函数里处理而不是这里，
        // 在那个函数里用目标文件拷贝到对应路径一份数据，那样不会报错。
        await writeStreamToFile(tempFile2, tempFile);
        await tempFile2.renameThenDelEmptyParent(localFile.absolute.path);

        // 这里没必要抛异常，原因有2：
        // 1. 如果本地有远程无对应obj，这时，不需上传，直接把本地文件加密，然后存到remoteDataDir即可，这时，这里就应该消费那个字节流
        // 2. 如果重复消费字节流，本身就会报错，而如果没报错，说明没重复消费，所以并不需要我刻意抛异常
        // throw RemoteException("data stream maybe consumed, should copy file instead of read stream, err code: 11515818", null);
      }else {
        tempFile as File;
        await tempFile.renameThenDelEmptyParent(localFile.absolute.path);
      }
    }



    if(!force && remoteDataType.isImmutable()) {
      // 检查本地是否已经存在文件
      final localExists = await localFile.exists();

      // 检查远程文件是否存在
      // final remoteExists = await exists(remoteDataPath);
      final bool remoteExists;
      if(isPfsType) {
        final pfs = getPfsByType(pfsType);
        // 用pack file storage检查是否存在对应的oid加类型（默认data）
        final findResult = await pfs.find(oid, findResultMap: objPfsFindResultMap!);
        remoteExists = findResult.foundItem();
      }else {
        // remoteExists = await exists(remoteDataPath);
        throw RemoteException("please use upload method to upload the type: $remoteDataType, err code: 14510967");
      }

      // 如果本地和远程都有，直接返回
      if(localExists && remoteExists) {
        return oid;
      } else if(!localExists && remoteExists) {
        //本地无，远程有：
        // 若期望下载，则直接下载，然后根据参数决定是否移动到本地目录；
        // 若不期望下载，直接把要上传的文件加密，然后根据参数决定是否移动到本地目录
        // 若下载则本地和远程的已加密文件一样，但下载可能受网络影响，性能较差；
        // 若不下载则本地和远程的已加密文件明文一样，但密文不同，因为nonce、compress的时间戳等参数不同，不过，不用联网下载，直接本地处理，性能更好
        if(moveToRemoteDataDirAfterPushed) {
          // 如果远程有对应的obj，本地直接移动到目录就行，不用下载了
          // 加密本地数据，然后拷贝到目标目录就行了，不用下载了
          final tempFile = await encDataToFile();
          // 执行到这里，无需上传文件，因为已经存在，直接加密然后移动到本地remoteDataDir即可
          // 这时，并不关心tempFile的类型，之前关心其类型主要是因为Stream只能消费1次，
          // 若多了就会报错，但在这，就算是Stream，也只会消费一次，所以无所谓File or Stream
          await moveFileToLocal(tempFile);
        }

        return oid;
      } else if(localExists && !remoteExists) {
        // 这的本地文件是已加密的，可直接上传
        // 这个不能上传了，还有，本地有，远程无，不要直接上传，存进pushCache，最后统一打包进pack上传
        if(isPfsType) {
          await _pushDataToCache(
            pfsType,
            oid,
            localFile.openRead(),
            tempDir,
            estimateLen: await localFile.length(),
            // 本地有，远程无，不需要拷贝，所以 copyToThisPathAfterPushed 传 null
            copyToThisPathAfterPushed: null
          );
        }else {
          throw RemoteException("please use upload method to upload the type: $remoteDataType, err code: 11033607");
        }

        // 本地已经有了，不需要移动，所以直接返回即可
        return oid;
      }
    }

    final tempFile = await encDataToFile();
    if(isPfsType) {
      // 这个类型断言主要是为了让我自己一看代码就知道类型，若出错，类型不对导致抛异常只是顺便
      tempFile as Stream<List<int>>;

      // 执行到这里，tempFile是一次性字节流，不能重复消费
      await _pushDataToCache(
        pfsType,
        oid,
        tempFile,
        tempDir,
        estimateLen: EncryptedData.headerLen() + await file.length(),
        copyToThisPathAfterPushed: moveToRemoteDataDirAfterPushed ? localFile.absolute.path : null
      );
    }else {
      throw RemoteException("please use upload method to upload the type: $remoteDataType, err code: 12047968");
    }

    return oid;
  }

  /// 上传 file info文件到 files/hash/data.enc，
  /// 上传完成后，如果 [remoteDataDirPath] 非空，
  /// 会把文件移动到本地的 remote/files/hash/data.enc 路径下，
  /// 若文件已存在，会覆盖
  Future<void> pushFileInfo(
    FileInfo fileInfo,
    KeyData contentKeyData,
    TempDir tempDir
  ) async {
    final history = fileInfo.history;
    // 历史为空，不应该添加！
    if(history.isEmpty) {
      throw RemoteException("fileInfo history is empty! path=${fileInfo.path}");
    }

    // 历史节点为1且是Deleted，异常！
    // 假如，长度不是1，那么，第一个节点是删除是可以理解的，
    // 因为可能节点数量超过限制，所以删除了第一个节点，但，如果只有一个节点，
    // 且状态为删除，就是异常的，不过要是把限制最多节点数改成1，那么只有一个且是删除就是正常的，
    // 但我不允许那个值为1
    if(history.length == 1 && history[0].oid.value == VersionOid.deleted.value) {
      throw RemoteException("fileInfo first history oid is 'Deleted'! path=${fileInfo.path}");
    }

    // 新增的节点和上一个一样，有问题！
    if(history.length > 1
        && history[history.length - 1].oid.value
            == history[history.length - 2].oid.value
    ) {
      throw RemoteException("fileInfo last 2 histories have same oid! path=${fileInfo.path}");
    }


    final fileInfoOid = await fileInfo.toOid(contentKeyData);
    filesMap!.set(fileInfoOid, fileInfo.toJson(), lastFilesMapContentId);


    // objRef描述object被谁引用（msg or file info）
    // final objRef = ObjRef(type: ObjRefType.fileInfo, oid: fileInfoOid.value, path: fileInfo.path);
    // await _linkObjRefWithRemoteData(objRef, fileInfo);
  }

  Future<void> pushMsg(
    Msg msg,
    KeyData contentKeyData,
    TempDir tempDir
  ) async {
    msgMap!.set(msg.oid, msg.toJson(), lastMsgMapContentId);

    // final objRef = ObjRef(type: ObjRefType.msg, oid: msg.oid.value);
    // await _linkObjRefWithRemoteData(objRef, msg);
  }

  Future<void> addRefToObj(VersionOid objOid) async {
    if(ObjRef.isInvalidOid(objOid.value)) {
      return;
    }

    // final refsMap = _objAddRefsMap!;
    // Set<ObjRef>? set = refsMap[objOid.value];
    // if(set == null) {
    //   set = {};
    //   refsMap[objOid.value] = set;
    // }
    //
    // set.add(ref);

    // 添加引用计数
    final refsCountMap = _objAddRefsCountMap!;
    final refCount = refsCountMap[objOid.value];
    refsCountMap[objOid.value] = (refCount ?? 0) + 1;
  }

  //
  // /// 创建新消息，其为旧消息的拷贝，但标记为已解决，然后上传新的，删除旧的
  // Future<VersionOid> markMsgAsResolved(
  //   Msg msg,
  //   bool trueResolvedFalseUnresolved,
  //   KeyData contentKeyData,
  //   String remoteDataDirPath,
  //   TempDir tempDir, {
  //   // 一般标记为解决，肯定已读，所以默认为true
  //   bool trueReadFalseUnread = true,
  //   String remark = '',
  //
  //   bool force = false,
  //   required bool moveToRemoteDataDirAfterPushed,
  // }) async {
  //   // 冲突消息才能标记为resolved
  //   if(msg.type != MsgType.conflict && msg.type != MsgType.remoteIsFileButWorkdirIsDir) {
  //     return VersionOid();
  //   }
  //
  //   if(msg.checked == trueReadFalseUnread && msg.resolved == trueResolvedFalseUnresolved && msg.remark == remark) {
  //     return VersionOid();
  //   }
  //
  //   // 创建新消息，哪都一样，就标记成resolved就行
  //   final newMsg = Msg();
  //   newMsg.type = msg.type;
  //   newMsg.title = msg.title;
  //   newMsg.data = msg.data;
  //
  //   // 已读不一定已解决，但已解决，一定已读
  //   newMsg.checked = trueReadFalseUnread;
  //   newMsg.resolved = trueResolvedFalseUnresolved;
  //   newMsg.remark = remark;
  //
  //   msg.checked = trueReadFalseUnread;
  //   msg.resolved = trueResolvedFalseUnresolved;
  //   msg.remark = remark;
  //
  //   // 从objMap移除旧msg关联，然后关联上新msg的oid
  //   await objMap!.removeRelatedOids(
  //     msg,
  //     ObjMapItemType.msg,
  //     contentKeyData,
  //     this,
  //     tempDir,
  //     // 后面还要关联到新msg，所以对应条目不应该删除
  //     removeSetIfNoMoreRef: false,
  //     callbackAfterRemovedItem: (oidSet) async {
  //       // 关联新msg的oid
  //       oidSet?.add(ObjMapItem(type: ObjMapItemType.msg, oid: newMsg.oid.value));
  //     }
  //   );
  //
  //   // 上传新消息
  //   await pushMsg(
  //     newMsg,
  //     contentKeyData,
  //     remoteDataDirPath,
  //     tempDir,
  //     moveToRemoteDataDirAfterPushed: moveToRemoteDataDirAfterPushed
  //   );
  //
  //   // 删除旧消息
  //   await deleteByOid(RemoteDataType.msg, msg.oid, tempDir);
  //
  //   return newMsg.oid;
  // }
  //
  //
  // /// 创建新消息，其为旧消息的拷贝，但标记为已读，然后上传新的，删除旧的
  // Future<VersionOid> markMsgAsRead(
  //   Msg msg,
  //   bool trueReadFalseUnread,
  //   KeyData contentKeyData,
  //   String remoteDataDirPath,
  //   TempDir tempDir, {
  //   String remark = '',
  //   bool force = false,
  //   required bool moveToRemoteDataDirAfterPushed,
  // }) async {
  //   // 废弃：因为冲突消息也可标记为已读
  //   // if(msg.type != MsgType.normal) {
  //   //   return VersionOid();
  //   // }
  //
  //   if(msg.checked == trueReadFalseUnread && msg.remark == remark) {
  //     return VersionOid();
  //   }
  //
  //   // 创建新消息，哪都一样，就标记成resolved就行
  //   final newMsg = Msg();
  //   newMsg.type = msg.type;
  //   newMsg.title = msg.title;
  //   newMsg.data = msg.data;
  //
  //   newMsg.checked = trueReadFalseUnread;
  //   newMsg.remark = remark;
  //
  //   msg.checked = trueReadFalseUnread;
  //   msg.remark = remark;
  //
  //   // 从objMap移除旧msg关联，然后关联上新msg的oid
  //   await objMap!.removeRelatedOids(
  //     msg,
  //     ObjMapItemType.msg,
  //     contentKeyData,
  //     this,
  //     tempDir,
  //     // 后面还要关联到新msg，所以对应条目不应该删除
  //     removeSetIfNoMoreRef: false,
  //     callbackAfterRemovedItem: (oidSet) async {
  //       // 关联新msg的oid
  //       oidSet?.add(ObjMapItem(type: ObjMapItemType.msg, oid: newMsg.oid.value));
  //     }
  //   );
  //
  //   // 上传新消息
  //   await pushMsg(
  //     newMsg,
  //     contentKeyData,
  //     remoteDataDirPath,
  //     tempDir,
  //     moveToRemoteDataDirAfterPushed: moveToRemoteDataDirAfterPushed
  //   );
  //
  //   // 删除旧消息
  //   await deleteByOid(RemoteDataType.msg, msg.oid, tempDir);
  //
  //   return newMsg.oid;
  // }

  void _requireSession(int code) {
    if(!sessionStarted()) {
      throw RemoteException("require session before call this method! err code: $code");
    }

    // 避免子remote调用会话相关函数导致和主remote的会话冲突
    if(isChild) {
      throw RemoteException("only main Remote instance allowed to call session functions! err code: $code");
    }
  }


  // 上传文件到网盘时，若开启会话会占用用户存储空间并且网盘提供清上传会话的api，
  // 则实现这个，清除会话，若不会占用，就不用管了，
  // 若清会话失败不期望抛出异常，在本函数内自行try catch，外部不管
  //
  // p.s dropbox开上传会话不会占用用户存储空间，而且dropbox也没提供能清session的api，
  // 所以不用处理
  @override
  Future<void> closeUnfinishedSession() async {

  }

  @override
  Future<List> getRecordedSessions() async {
    return [];
  }

  @override
  Future<void> recordSession() async {

  }

  @override
  Future<void> removeSession() async {

  }

  Future<RemoteConfig> toRemoteConfig();


  bool isEmptyImpl() {
    return type.value == emptyRemoteImplInstance.type.value;
  }

  // 如果不支持创建目录，执行操作出错，会创建目录然后重试
  Future<void> doActIfErrAndDontSupportAutoMkdirsThenMkdirsThenTryAgain({
    required String actName,
    required Future<void> Function() act,
    required Future<void> Function()? mkdirs,
  }) async {
    try {
      await act();
    }catch(e, st) {
      if(supportAutoCreateNonexistsPath) {
        rethrow;
      }

      if(mkdirs == null) {
        rethrow;
      }

      App.logger.debug(_TAG, "#$actName() err: $e,\nwill create parent dirs then try again");

      await mkdirs();
      await act();
    }
  }

  // 注：本函数不会修改类字段属性
  // 假如日后有许多参数需要检测，则返回一个DetermineResult，包含各种检测的结果
  Future<DetermineResult> determineServerBehavior(TempDir tempDir) async {
    // 已知支持自动创建目录 (local dir函数内部做了处理自动创建不存在的中间目录，所以也算支持)
    if(type == RemoteType.dropbox || type == RemoteType.localDir) {
      return DetermineResult(supportAutoCreateNonexistsPath: true, needEndsWithSeparatorEvenPathIsFile: false);
    }

    final result = DetermineResult();
    // 探测需要创建的临时文件（会在session提交会话时清掉整个temp目录，这个文件也就没了，所以这里不用管清理）
    // NEDC == NonExistsDirCheck
    final remoteTempPathBase = remoteTempRootPath().append("NEDC_${randomString(22)}");
    final remoteTempPath = remoteTempPathBase.copy()
      // 创建不存在的中间目录
      .append(randomString(10))
      // 文件名
      .append("testAutoMkdirs.temp");

    final tempUploadFile = await tempDir.createTempFile();

    // 探测，需uploadFile函数配合实现tryCreateParentsIfNeed，若传 false，不应自动创建，不然探测就没用了，可能会错误认为支持，实际不支持，上传时导致出错
    try {
      // 不创建缺失的父目录，直接上传文件
      final encData = await AppKey.encryptDataWithAppKey(Stream.value(utf8.encode("test auto create Nonexistents dirs")));
      await encData.writeToFile(tempUploadFile);

      await uploadFile(remoteTempPath, tempUploadFile, tryCreateParentsIfNeed: false);

      App.logger.debug(_TAG, "determineSupportAutoCreateNonexistentsDirs success, server support auto create no exists dirs");
      result.supportAutoCreateNonexistsPath = true;
    }catch(e, st) {
      App.logger.debug(_TAG, "determineSupportAutoCreateNonexistentsDirs err, server doesn't auto create no exists dirs: $e\n$st");
      // 创建缺失的父目录，再上传
      await mkdir(remoteTempPath.parent());
      await uploadFile(remoteTempPath, tempUploadFile, tryCreateParentsIfNeed: false);
      result.supportAutoCreateNonexistsPath = false;
    }finally {
      try {
        await delete(remoteTempPathBase, isDir: true);
      }catch(e, st) {
        App.logger.debug(_TAG, "determineSupportAutoCreateNonexistentsDirs err, clean remote temp path err: $e\n$st");
      }
    }

    // x 后来发现并非末尾带不带/的问题，带/绝对下载不下载，不带或许能下载下来，可能和缓存有关（infiniCloud有这问题，对下载失败的路径先调用exists()再下载就行了，原因不明），
    // 所以这个探测没用了）注：我发现有的平台，例如 infiniteCloud，行为不稳定，末尾不带/，文件路径，有时下载成功，有时候失败，但末尾带/一般不会出错，所以改成优先尝试末尾带/了
    // final tempDownloadFile = await tempDir.createTempFile();
    // final needEndsWithSeparatorEvenPathIsFileBeforeDetermine = needEndsWithSeparatorEvenPathIsFile;  // 保存之前的值，探测完之后恢复
    // try {
    //   // 必须设置这个，不然downloadToFile可能会自动追加/（取决于之前有无设置过这个值）
    //   needEndsWithSeparatorEvenPathIsFile = false;
    //   // download file without ends with '/'
    //   // e.g. /abc.txt
    //   await downloadToFile(remoteTempPath, tempDownloadFile, tempDir);
    //   result.needEndsWithSeparatorEvenPathIsFile = false;
    // }catch(e) {
    //   // 设为true，试下自动追加末尾/ (需要remote实现类遵循此字段来手动调用 appendPathSeparatorIfIsDir 追加/，可参考webdav类的代码)
    //   needEndsWithSeparatorEvenPathIsFile = true;
    //   // download file with ends with '/'
    //   // e.g. /abc.txt/
    //   // remoteTempPath.append("/")的写法失效了，因为FilePath现在转字符串强制规范化路径了，
    //   // 所以现在依赖 needEndsWithSeparatorEvenPathIsFile 为true以及 remote 实现类遵循 needEndsWithSeparatorEvenPathIsFile 了
    //   // await downloadToFile(remoteTempPath.append("/"), tempDownloadFile, tempDir);  // remoteTempPath.append("/") 失效了，转为字符串依然末尾不会追加/
    //
    //   await downloadToFile(remoteTempPath, tempDownloadFile, tempDir);
    //   result.needEndsWithSeparatorEvenPathIsFile = true;
    // }finally {
    //    needEndsWithSeparatorEvenPathIsFile = needEndsWithSeparatorEvenPathIsFileBeforeDetermine;
    // }

    return result;
  }

  bool sessionStarted() {
    return currentSessionId.isNotEmpty;
  }

  Future<bool> isEmptyOrEncrypted(File file) async {
    // 注：由于我所有magic头长度都一样，所以，这个也可用来读取pack文件头
    final tempMagic = file.openRead(0, EncryptedData.magic.length);
    final bb = BytesBuilder(copy: false);
    await for(final b in tempMagic) {
      bb.add(b);
    }

    final bytes = bb.takeBytes();

    // x 已废弃，现在.pack文件有magic了，永远不会为空，所以禁止上传空文件了！）注：允许空文件是因为.pack 文件可能为空，所以允许；
    // 若.pack文件有内容，则必然存储的已加密文件，因此.pack文件的
    // 头几个字节应该和加密文件匹配，所以直接用下面的magic判断即可，不需要额外处理
    if(bytes.isEmpty) {
      return allowUploadEmptyFile;
    }
    
    if(listEquals(bytes, EncryptedData.magic)) {
      return true;
    }

    // pack file的magic长度和encrypted data一样，所以可以直接比较
    if(listEquals(bytes, packFileMagic)) {
      return true;
    }

    return false;
  }

  Future<void> throwIfFileIsNotEmptyOrEncrypted(File file) async {
    if(!await isEmptyOrEncrypted(file)) {
      throw RemoteException("only empty or encrypted file allowed to upload");
    }
  }

  // 上传个文件测试下remote能否正常使用
  Future<void> throwIfAnythingWrong(TempDir tempDir) async {
    final encData = await AppKey.encryptDataWithAppKey(Stream.value([123]));
    final tempFile = await tempDir.createTempFile();
    // x 是因为确保es_compression lib，所以写入文件时出错了，然后误以为是操作系统io错误，其实是压缩库先出错，然后关流出错，根源在es_compression) linux在这报错
    await encData.writeToFile(tempFile);
    final remoteTempFile = await uploadFileToTemp(tempFile);

    // try remove temp file that used to test upload
    // 注：这个文件删除失败也无所谓，顶多远程的仓库路径/temp下有个临时文件
    try {
      await delete(remoteTempFile, isDir: false);
    }catch(e) {
      App.logger.debug(_TAG, "#throwIfAnythingWrong: delete remote temp file err: $e");
    }
  }

  Future<bool> isRepoExists() async {
    // return !await isDirEmptyOrNoExists(basePath.copy(), excludes: {remoteTempRootPath().toUnixPathStr()});
    return !await isDirEmptyOrNoExists(basePath.copy());
  }

  /// 检测某个目录是否 为空 或 不存在
  /// [excludes] 检查目录下是否存在条目时，会忽略指定目录，例如，期望仓库目录下若只有temp目录则视为空，可传temp目录到此路径下
  /// [excludes] expects unix styled abs path, like: /haha_repo/temp
  Future<bool> isDirEmptyOrNoExists(FilePath path, {Set<String>? excludes}) async {
    if(!await exists(path)) {
      return true;
    }

    final files = await listFiles(path);
    if(files.isEmpty) {
      // dir is empty
      return true;
    }

    if((excludes == null || excludes.isEmpty) && files.isNotEmpty) {
      return false;
    }

    // 如果文件条目数大于要排除的条目数，则必然包含至少一个非排除的路径，因此断定目录存在且非空，可直接返回false了
    if(excludes != null && files.length > excludes.length) {
      return false;
    }

    for(final i in files) {
      if(excludes?.contains(i.path.toUnixPathStr()) == true) {
        continue;
      }

      // dir is not empty
      return false;
    }

    // dir is empty
    return true;
  }

  // 返回结果代表远程是否已经存在或者上传了对应obj（代表对应obj是否可用，若可用，调用者可以为其关联msg或file info，否则不应关联）
  Future<bool> uploadObjIfLocalHasButRemoteNone(VersionOid oid, String remoteDataDirPath, TempDir tempDir) async {
    final findResult = await objectsPfs!.find(oid, findResultMap: objPfsFindResultMap!);
    // 远程存在对应条目，直接返回true
    if(findResult.foundItem()) {
      return true;
    }

    // 如果是真 remoteDataDirPath 则使用真实hash分割后的路径，否则使用之前直接生成 hash/data.enc 的路径
    final localObjFile = File(Repo.getLocalRemoteObjectPathByOidStr(remoteDataDirPath, oid.value));
    if(!await localObjFile.exists()) {
      // 远程没有对应条目，本地remote/objects也没有，
      // 返回false，调用者不应该为这个obj关联条目
      return false;
    }

    // 执行到这，远程没对应条目，但本地有，上传对应obj，然后返回true（obj可用，调用者可为其关联msg或file info）

    // 这里refs传null即可，调用者应使用 remote.addRefToObj() 关联object和msg或file info
    // 最后copy到本地目录也传null，因为这里是本地有远程无的情况，所以不需要传copy的路径
    await _pushDataToCache(
      RemoteDataType.objectsPfs,
      oid,
      localObjFile.openRead(),
      tempDir,
      estimateLen: await localObjFile.length(),
      copyToThisPathAfterPushed: null
    );

    return true;
  }

  String appendPathSeparatorIfIsDir(final FilePath path, bool isDir) {
    final pathStr = path.toUnixPathStr();

    // https://pub.dev/packages/webdav_client#cancel-request
    // 上面是我用的webdav_client依赖库，作者说有的webdav服务器要求路径末尾必须加/，
    // 所以判断下，如果是目录且末尾不是endsWith /，加个，若是文件且末尾endsWith /，移除
    if(isDir || needEndsWithSeparatorEvenPathIsFile) {
      if(pathStr.endsWith(pathSeparator)) {
        return pathStr;
      }

      return pathStr + pathSeparator;
    }else {
      return pathStr.removeSuffix(pathSeparator);
    }
  }


  // test dropbox 是否会命中 RemoteNotFoundException
  Future<void> testHitRemoteNotFoundException() async {
    await delete(genRemoteTempFilePath(), isDir: false);
    await deleteBatch([RemoteFileSimple(false, genRemoteTempFilePath())]);
    await renameBatch([FilePathPair(left: genRemoteTempFilePath(), right: genRemoteTempFilePath())]);
  }

  // test 能否正常检测目录是否为空或不存在
  Future<void> testEmptyDirCheck({String remoteRoot = '/'}) async {
    final remoteRootPath = FilePath.fromString(remoteRoot);

    // 目录存在且空
    if(!await isDirEmptyOrNoExists(remoteRootPath.copy().append("test_empty_dir"))) {
      throw "empty dir check err, err code: 10440213";
    }

    // 不存在的目录
    if(!await isDirEmptyOrNoExists(remoteRootPath.copy().append("noExistsPath_abckiqjkljdg"))) {
      throw "no exists dir check err, err code: 10439150";
    }

    // 存在，但内部只有temp目录
    final base = remoteRootPath.copy().append("test_only_temp_folder");
    if(!await isDirEmptyOrNoExists(base, excludes: {base.copy().append("temp").toUnixPathStr()})) {
      throw "dir exists but only have a temp dir check err, err code: 17748251";
    }
  }

  Future<void> gitPull() async {
    await notifyLockUploaderThenDoAct(doGitPull);
  }

  // 若remote是git backend则实现，否则不用
  Future<void> doGitPull() async {}

  /// commit msg不要有空格，避免http传参时出错（不过我实际测试了下，没报错，并且pcgit仓库路径有空格也不会报错，ppgit仓库名有空格也不会报错）
  Future<void> gitPush(String gitCommitMsg, {bool must = false}) async {
    await notifyLockUploaderThenDoAct(() async {
      // 给提交信息加上haha note的前缀
      await doGitPush(genCommitMsgPrefix() + gitCommitMsg, must: must);
    });
  }

  Future<void> doGitPush(String gitCommitMsg, {bool must = false}) async {}

  Future<void> awaitLockRenewalFinished() async {
    while((await isLockRenewaling?.call()) == true) {
      await Future.delayed(Duration(milliseconds: 200));
    }
  }

  // 让续的线程能感知到这边在执行任务，避免同时推送
  Future<void> notifyLockUploaderThenDoAct(Future<void> Function() act) async {
    await awaitLockRenewalFinished();

    await remoteSessionCommitBegin?.call();
    try {
      await act();
    }finally {
      await remoteSessionCommitEnd?.call();
    }
  }

  // 处理url，添加些参数
  static String handleGitPushUrl(final String rawPushUrl, final String gitCommitMsg) {
    final paramsSplitSign = "&";
    var pushUrl = rawPushUrl.split(paramsSplitSign);

    final sb = StringBuffer();
    for(final s in pushUrl) {
      // 这几个选项需要强制按规范来，不然无法保证同步有序和出错时重置为远程最新节点（若不重置，会冲突，需要人工合并）
      if(s.contains("async=")) {
        sb.write("async=0");
      }else if(s.contains("resetIfErr=")) {
        sb.write("resetIfErr=hard");
      }else {
        sb.write(s);
      }

      sb.write(paramsSplitSign);
    }

    var tempResult = sb.toString();
    if(!tempResult.contains("async=")) {
      sb.write("async=0");
      sb.write(paramsSplitSign);
    }
    if(!tempResult.contains("resetIfErr=")) {
      sb.write("resetIfErr=hard");
      sb.write(paramsSplitSign);
    }

    // 如果源url不包含此参数则添加，包含的话，保持原样（意味着用户可在url自定义cmtMsgPrefix）
    if(!tempResult.contains("cmtMsgPrefix=")) {
      sb.write("cmtMsgPrefix=$gitCommitMsg");
      sb.write(paramsSplitSign);
    }

    final result = sb.toString().removeSuffix(paramsSplitSign);
    App.logger.warn(_TAG, "git push url will use: $result");

    return result;
  }

  String genCommitMsgPrefix() {
    return "HahaNote(${client?.name})($sessionActName):";
  }

  Future<void> deleteRepo(final Client client, final String actName) async {
    try {
      this.client = client;
      sessionActName = actName;

      await delete(basePath.copyAbs(), isDir: true);

    }finally {
      try {
        // 创建空目录，不然git命令定位目录会提示目录不存在
        if(type.value == RemoteType.localDir.value) {
          await mkdir(basePath.copyAbs());
        }
        await gitPush("delete_repo");
      }finally {
        this.client = null;
        sessionActName = '';
      }
    }
  }

  // if true, will do batch actions in concurrency way
  // 本质上这是函数调用不用 => 改用 {} 写多行代码也行
  // 并发模式下，批量任务，若任一任务出错，立刻抛异常；否则即使出错也会先尝试执行所有任务，才抛出第一个异常
  bool get concurrencyTasksThrowIfAnyErr => true;
  // 1代表只有一个任务，即禁用并发
  int get maxConcurrencyRead => 1;
  int get maxConcurrencyWrite => 1;

  Future<void> runTaskConcurrencyIfAllow(
    List<Future Function()> tasks, {
    required bool isRead,
  }) async {
    await futureFunctionPool(
      tasks,
      max: isRead ? maxConcurrencyRead : maxConcurrencyWrite,
      eagerError: concurrencyTasksThrowIfAnyErr,
    );
  }

}
