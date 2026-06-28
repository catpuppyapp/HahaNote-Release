import 'dart:convert' show utf8, jsonEncode, jsonDecode;
import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/crypto/encrypt.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/crypto/hash.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/crypto/key_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/remote.dart' show RemoteDataType;
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/datamap/data_map.dart' show DataMap;
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/pack/obj_pack.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/oidlize.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/stream.dart' show JsonByteStream;
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_info.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_path.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/virtual_file.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/msg/msg.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/index.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/path_place_holder.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/repo.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/sync_history.dart' show maxRecordItems, HistoryNodeType;
import 'package:cloud_disk_note_app/cloud_disk_note/storage/utils.dart' show getFileType, getFileAndMakeSureParentDirExist, writeStreamToFile, writeStrToFile, isFileNonExistsOrEmpty;
import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/string_ext.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/time/time_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart';
import 'package:path/path.dart' as p;

import '../temp/temp_dir.dart' show TempDir;

part 'sync.g.dart';

const _TAG = "sync.dart";

// typedef ConflictHandler = Future<void> Function(FileInfo localFileInfo, FileInfo remoteFileInfo);
typedef ThrowIfInterrupted = void Function();
typedef SyncProgressCb = void Function(String act, int allCount, int currentAt, String extraInfo);

abstract class SyncProgressAct {
  static final cleanCachedData = "clean cached data";
  static final cleanTempFiles = "clean temp files";
  static final cleanIndex = "clean index";
  static final deleting = "deleting";
  static final done = "done";
  static final scanning = "scanning";
  static final creating = "creating";
  static final willUseRemoteFilesOverwriteWorkdir = "will use remote files overwrite workdir";
  static final initFilesMap = "init files map";
  static final initMsgMap = "init msg map";
  static final initObjPfs = "init obj pfs";
  static final initLastSyncInfo = "init last sync info";
  static final searchingCache = "searching cache";
  static final commitLocalSyncCache = "commit local sync cache";
  static final deletingRemote = "deleting remote";
  static final deletingLocal = "deleting local";
  static final exporting = "exporting";
  static final err = "err";
  static final objNotFound = "obj not found";
  static final foundLocalCache = "found local cache";
  static final handling = "handling";
  static final downloading = "downloading";
  static final checkingCache = "checking cache";
  static final deleteFinished = "delete finished";
  static final syncFiles = "sync files";
  static final downloadRepoInfo = "download repo info";
  static final downloadSyncHistory = "download sync history";
  static final downloadKeys = "download keys";

  static final initKey = "init key";
  static final initSyncHistory = "init sync history";
  static final initRepoInfo = "init repo info";

  // remote 初始化好了（remote.doInit()后），就绪了，能用了，调用者要是想用remote执行点操作，比如获取dropbox用户信息，就是现在！
  static final remoteReady = "remote ready";

  static final deletingObject = "deleting object";

  static final downloadingFiles = "downloading files";
  static final updatingFiles = "updating files";
  static final checkingDeletedItems = "checking deleted items";
  static final checkingChanges = "checking changes";
  static final uploadingChanges = "uploading changes";
  static final deletingFiles = "deleting files";

  // 回调里检查下，如果是这两个，提示用户，可能会很耗时
  static String forceSyncAlert = "will do force sync, maybe need a long time";
  // 上次同步之后，后续的同步要么有未完成的（状态停留在started），要么上传完了，但推送的文件太多，
  // 可以判断出到底是哪种情况，但徒增代码，且没多大用，所以不做具体判断，
  // x 废弃，改成diff本地和远程的filePfs来查找修改的文件了）以上情况都需要本次同步fetch所有文件并检查更新
  static String handleChanges = "handle changes";

  static String committingChanges = "committing changes";

  static String updatingSyncHistory = "updating sync history";

  static String updatingIndex = "updating index";

  // static String hasErrWillTryRollback = "has error, will try rollback";
  static String syncCanceledByErr = "sync canceled by err";

  // 把下载到syncCache里的文件移动到正式目录
  static String movingDownloadedFiles = "moving downloaded files";

  // 计算hash查找workdir修改的文件？
  static String findingChanges = "finding changes";
}

class ConflictResolveStrategy {
  final int value;

  ConflictResolveStrategy(this.value);

  // 工作目录的文件覆盖远程，上传一个新版本 (目前 20260414 实际采用的只有这个策略，并且没有给用户留设置项）
  static final workdirOverwriteRemote = ConflictResolveStrategy(1);
  // 远程的文件覆盖工作目录，不用上传新版本
  static final remoteOverwriteWorkdir = ConflictResolveStrategy(2);

  @override
  String toString() {
    return value.toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ConflictResolveStrategy &&
              runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;

  static bool isKnown(ConflictResolveStrategy conflictResolveStrategy) {
    return conflictResolveStrategy == workdirOverwriteRemote
        || conflictResolveStrategy == remoteOverwriteWorkdir
    ;
  }

  static String valueToText(int value) {
    if(value == workdirOverwriteRemote.value) {
      return "workdirOverwriteRemote";
    }

    if(value == remoteOverwriteWorkdir.value) {
      return "remoteOverwriteWorkdir";
    }

    return "unknown";
  }


  static String genWhoOverwriteWho(MsgDataConflict msgData) {
    return msgData.resolveStrategy == ConflictResolveStrategy.workdirOverwriteRemote.value
      ? "${msgData.workdirOid?.shortValue()} overwrite ${msgData.remoteOid?.shortValue()}"
      : "${msgData.remoteOid?.shortValue()} overwrite ${msgData.workdirOid?.shortValue()}";
  }
}
//
// class MergeResult {
//   // 已删除、已更新，push时忽略这些条目
//   Map<FilePath, FileInfoPair> updatedItems = {};
//
//   // 冲突条目，用来在push时给路径加Tag
//   Map<FilePath, FileInfoPair> conflictItems = {};
//   List<FilePath> notAFile = [];
//
//   Map<FilePath, FileInfo> untouchedRemoteFileInfosForPush = {};
//
//   bool isConflictItem(FilePath relativePath) {
//     return conflictItems.containsKey(relativePath);
//   }
// }

//
//
// class FileInfoPair {
//   // 本地 remote/files 目录
//   FileInfo? localFileInfo;
//
//   // 从远程仓库下载下来的存放在指定目录的 remote/files
//   FileInfo? remoteFileInfo;
//
//   FileInfoPair({this.localFileInfo, this.remoteFileInfo});
//
//
// }
//


class SyncResult {
  SyncResultForHistoryNode result = SyncResultForHistoryNode();
  // 同步后的最新索引
  final newIndex = Index();

  SyncResultForHistoryNode toResultForNode() {
    // 数量全记，条目不全记，只记最关键的pushedItem，
    // 让其他客户端同步时能知道别的客户端上传了多少个文件即可
    return SyncResultForHistoryNode(
      pushedCount: result.pushedCount,
      conflictsCount: result.conflictsCount,
      updatedCount: result.updatedCount,
      deletedCount: result.deletedCount,
      pushed: result.pushed,
      conflicts: result.conflicts,
      updated: result.updated,
      deleted: result.deleted,
    );
  }

  String brief({required int historyNodeType}) {
    final syncResultBrief = result.brief();

    // 如果节点类型是Clean，显示"Clean"前缀，同时检测，若syncResultBrief非空，
    // 代表Clean时顺便上传了文件，
    // 这时追加syncResultBrief，示例"Clean, pushed: n, deleted: m"；
    // 如果节点类型是普通的Sync，直接显示brief即可
    return historyNodeType == HistoryNodeType.clean
        ? "${HistoryNodeType.textOf(historyNodeType)}${syncResultBrief.isEmpty ? "" : ", $syncResultBrief"}"
        : syncResultBrief;
  }

  @override
  String toString() {
    return 'result: $result, newIndex: $newIndex';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SyncResult && runtimeType == other.runtimeType &&
              result == other.result && newIndex == other.newIndex;

  @override
  int get hashCode => Object.hash(result, newIndex);


}

@myJsonSerializable
class SyncResultForHistoryNode {
  // 如果数量太多，不会保留所有条目列表，但count会记录准确数量
  int updatedCount;
  // 更新了本地的哪些条目（拉取哪些文件到本地）
  List<String> updated; //仅供参考
  int pushedCount;
  //代表更新了远程的哪些条目（推送哪些fileinfo到远程），
  // 保证：记了的路径，对应远程条目不一定更新过，但没记的一定没更新过
  // 严格记录每次推送的文件列表，用来避免全量同步，
  // 相当于包含conflict、updated、deleted条目的去重后的路径集合
  List<PushedItem> pushed;  // 这个不是仅供参考，这个在没超过 maxRecordItems 的情况下，绝对准确，超过的情况下会执行全量同步
  int deletedCount;
  // 本地和远程都有
  // 本地哪些条目因为远程不存在对应条目而被删除；(overwrite本地文件）
  // 以及把远程哪些条目因为本地不存在而更新成已删除；（本地不存在对应文件，远程创建一个oid为已删除的最新节点）
  List<String> deleted;  //仅供参考
  int conflictsCount;
  // 哪些路径有冲突，具体是否pushed取决于冲突策略，如果是本地覆盖远程，则会推送，否则不会，若推，则会同时把路径记录到pushed条目
  List<ConflictItem> conflicts;  // 仅供参考

  SyncResultForHistoryNode({this.updatedCount = 0, List<String>? updated, this.pushedCount = 0,
    List<PushedItem>? pushed, this.deletedCount = 0, List<String>? deleted, this.conflictsCount = 0,
    List<ConflictItem>? conflicts
  })
  : updated = updated ?? [],
    pushed = pushed ?? [],
    deleted = deleted ?? [],
    conflicts = conflicts ?? []
  ;

  factory SyncResultForHistoryNode.fromJson(Map<String, dynamic> json) => _$SyncResultForHistoryNodeFromJson(json);

  Map<String, dynamic> toJson() => _$SyncResultForHistoryNodeToJson(this);

  void _addItem(List<dynamic> list, dynamic item) {
    // 只记录最多 maxRecordItems 个，多了就不记了
    if(list.length < maxRecordItems) {
      list.add(item);
    }
  }

  void addUpdatedItem(UpdatedItem item) {
    // 为了兼容性所以存字符串
    _addItem(updated, item.toString());
    updatedCount++;
  }

  void addPushedItem(PushedItem item) {
    _addItem(pushed, item);
    pushedCount++;
  }

  void addDeletedItem(DeletedItem item) {
    // 为了兼容性所以存字符串
    _addItem(deleted, item.toString());
    deletedCount++;
  }

  void addConflictsItem(ConflictItem item) {
    _addItem(conflicts, item);
    conflictsCount++;
  }

  @override
  String toString() {
    final sb = StringBuffer();
    final suffix = "\n\n";
    if(pushedCount > 0) {
      sb.write("pushed: $pushedCount");
      sb.write(suffix);
    }

    if(conflictsCount > 0) {
      sb.write("conflicts: $conflictsCount");
      sb.write(suffix);
    }

    if(updatedCount > 0) {
      sb.write("updated: $updatedCount");
      sb.write(suffix);
    }

    if(deletedCount > 0) {
      sb.write("deleted: $deletedCount");
      sb.write(suffix);
    }

    if(pushed.isNotEmpty) {
      sb.write("pushed:\n${pushed.join('\n')}");
      sb.write(suffix);
    }

    if(conflicts.isNotEmpty) {
      sb.write("conflicts:\n${conflicts.join('\n')}");
      sb.write(suffix);
    }

    if(updated.isNotEmpty) {
      sb.write("updated:\n${updated.join('\n')}");
      sb.write(suffix);
    }

    if(deleted.isNotEmpty) {
      sb.write("deleted:\n${deleted.join('\n')}");
      sb.write(suffix);
    }

    final updateNote = sb.toString().removeSuffix(suffix);
    // 注意：如果是彻底删除“已删除”条目，那么即使提示没文件更新，对应的Object也依然被删除了
    return updateNote.isEmpty ? "No files updated at this sync" : "Updated files (up to $maxRecordItems records):\n\n$updateNote";
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SyncResultForHistoryNode &&
              runtimeType == other.runtimeType &&
              updatedCount == other.updatedCount && listEquals(updated, other.updated) &&
              pushedCount == other.pushedCount && listEquals(pushed, other.pushed) &&
              deletedCount == other.deletedCount && listEquals(deleted, other.deleted) &&
              conflictsCount == other.conflictsCount && listEquals(conflicts, other.conflicts);

  @override
  int get hashCode =>
      Object.hash(
          updatedCount,
          updated,
          pushedCount,
          pushed,
          deletedCount,
          deleted,
          conflictsCount,
          conflicts);

  String brief() {
    final sb = StringBuffer();
    final suffix = ", ";
    if(pushedCount > 0) {
      sb.write("pushed: $pushedCount");
      sb.write(suffix);
    }

    if(conflictsCount > 0) {
      sb.write("conflicts: $conflictsCount");
      sb.write(suffix);
    }

    if(updatedCount > 0) {
      sb.write("updated: $updatedCount");
      sb.write(suffix);
    }

    if(deletedCount > 0) {
      sb.write("deleted: $deletedCount");
      sb.write(suffix);
    }

    return sb.toString().removeSuffix(suffix);
  }

}

@myJsonSerializable
class ConflictItem {
  String path;
  // 冲突msg id
  String conflictId;

  ConflictItem({this.path = '', this.conflictId = ''});


  factory ConflictItem.fromJson(Map<String, dynamic> json) => _$ConflictItemFromJson(json);

  Map<String, dynamic> toJson() => _$ConflictItemToJson(this);

  @override
  String toString() {
    return 'path: $path, conflictId: $conflictId';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ConflictItem && runtimeType == other.runtimeType &&
              path == other.path && conflictId == other.conflictId;

  @override
  int get hashCode => Object.hash(path, conflictId);


}

@myJsonSerializable
class PushedItem {
  String path;
  // 推送的那个版本的obj的hash
  String objOid;

  PushedItem({this.path = '', this.objOid = ''});


  factory PushedItem.fromJson(Map<String, dynamic> json) => _$PushedItemFromJson(json);

  Map<String, dynamic> toJson() => _$PushedItemToJson(this);

  @override
  String toString() {
    return 'path: $path, objOid: $objOid';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is PushedItem && runtimeType == other.runtimeType &&
              path == other.path && objOid == other.objOid;

  @override
  int get hashCode => Object.hash(path, objOid);
}

@myJsonSerializable
class UpdatedItem {
  String path;
  String oldOid;
  String newOid;

  UpdatedItem({this.path = '', this.oldOid = '', this.newOid = ''});


  factory UpdatedItem.fromJson(Map<String, dynamic> json) => _$UpdatedItemFromJson(json);

  Map<String, dynamic> toJson() => _$UpdatedItemToJson(this);

  @override
  String toString() {
    return 'path: $path, oldOid: $oldOid, newOid: $newOid';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is UpdatedItem && runtimeType == other.runtimeType &&
              path == other.path && oldOid == other.oldOid &&
              newOid == other.newOid;

  @override
  int get hashCode => Object.hash(path, oldOid, newOid);

}

@myJsonSerializable
class DeletedItem {
  String path;
  String oldOid;

  DeletedItem({this.path = '', this.oldOid = ''});


  factory DeletedItem.fromJson(Map<String, dynamic> json) => _$DeletedItemFromJson(json);

  Map<String, dynamic> toJson() => _$DeletedItemToJson(this);

  @override
  String toString() {
    return 'path: $path, oldOid: $oldOid';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is DeletedItem && runtimeType == other.runtimeType &&
              path == other.path && oldOid == other.oldOid;

  @override
  int get hashCode => Object.hash(path, oldOid);

}

@myJsonSerializable
class FailedItem {
  String path;
  String errMsg;

  FailedItem({this.path = '', this.errMsg = ''});

  factory FailedItem.fromJson(Map<String, dynamic> json) => _$FailedItemFromJson(json);

  Map<String, dynamic> toJson() => _$FailedItemToJson(this);

  @override
  String toString() {
    return 'path: $path, errMsg: $errMsg';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is FailedItem && runtimeType == other.runtimeType &&
              path == other.path && errMsg == other.errMsg;

  @override
  int get hashCode => Object.hash(path, errMsg);

}

@myJsonSerializable
class WorkdirFiles {
  // key是FilePath.mapKey()
  Map<String, WorkdirFileItem> items;

  WorkdirFiles({Map<String, WorkdirFileItem>? items})
  : items = items ?? {};

  factory WorkdirFiles.fromJson(Map<String, dynamic> json) => _$WorkdirFilesFromJson(json);

  Map<String, dynamic> toJson() => _$WorkdirFilesToJson(this);

  @override
  String toString() {
    return 'items: $items';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is WorkdirFiles && runtimeType == other.runtimeType &&
              mapEquals(items, other.items);

  @override
  int get hashCode => items.hashCode;

  // 这个file是被覆盖或者被删除的源文件的信息，到时会校验，如果匹配则会覆盖或删除
  Future<void> addFile(FilePath relativePath, File targetFile, String oid) async {
    //简化判断逻辑，不然删除的还得特别处理
    if(oid == VersionOid.deleted.value) {
      oid = '';
    }

    items[relativePath.toMapKey()] = await WorkdirFileItem.fromFile(targetFile, oid);
  }

  bool contains(FilePath relativePath) {
    return items.containsKey(relativePath.toMapKey());
  }

  bool isEmpty() {
    return items.isEmpty;
  }

  bool isNotEmpty() {
    return !isEmpty();
  }

  static Future<WorkdirFiles> fromFile(File file) async {
    return WorkdirFiles.fromJson(jsonDecode(await file.readAsString()));
  }

  WorkdirFileItem? get(FilePath relativePath) {
    return items[relativePath.toMapKey()];
  }

}

@myJsonSerializable
class WorkdirFileItem {
  int expectMTimeMs;
  int expectFileLen;
  // 用contentKeyData计算出的文件oid
  String expectFileOid;

  WorkdirFileItem({this.expectMTimeMs = 0, this.expectFileLen = 0, this.expectFileOid = ''});

  factory WorkdirFileItem.fromJson(Map<String, dynamic> json) => _$WorkdirFileItemFromJson(json);

  Map<String, dynamic> toJson() => _$WorkdirFileItemToJson(this);

  // 从本地文件生成的时候按道理来说该计算下oid，更精准，但一般只比较修改时间和大小即可，不要求那么精准
  // 不行，index那个oid不匹配的话，顶多全量同步，但这个若不匹配，该覆盖的文件就不会覆盖了，还是得记下
  static Future<WorkdirFileItem> fromFile(File targetFile, String oid) async {
    // 这的东西都是要删或覆盖的，如果不存在，也得记录上对应条目，不过属性全为默认即可
    if(!await targetFile.exists()) {
      return WorkdirFileItem();
    }

    return WorkdirFileItem(
      expectMTimeMs: (await targetFile.lastModified()).millisecondsSinceEpoch,
      expectFileLen: await targetFile.length(),
      expectFileOid: oid
    );
  }

  // oid虽然存了，但覆盖本地文件的时候就不计算了，所以不比较oid
  bool match(WorkdirFileItem other) {
    // oid若非空，只检查oid
    if(expectFileOid.isNotEmpty && other.expectFileOid.isNotEmpty) {
      return expectFileOid == other.expectFileOid;
    }

    return expectMTimeMs == other.expectMTimeMs &&
        expectFileLen == other.expectFileLen;
  }

  @override
  String toString() {
    return 'expectMTimeMs: $expectMTimeMs, expectFileLen: $expectFileLen, expectFileOid: $expectFileOid';
  }


  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is WorkdirFileItem && runtimeType == other.runtimeType &&
              expectMTimeMs == other.expectMTimeMs &&
              expectFileLen == other.expectFileLen &&
              expectFileOid == other.expectFileOid;

  @override
  int get hashCode => Object.hash(expectMTimeMs, expectFileLen, expectFileOid);

}

abstract class SyncInfoState {
  static int started = 1;

  static int finished = 2;

  // error, 100以上都是错误
  static int error = 100;
  static int errorButRollbackSuccess = 101;
}

@myJsonSerializable
class SyncInfo implements JsonByteStream {
  // value of `SyncInfoState`
  int state;
  String msg;
  TimeData time;
  // 已上传的文件数量，包含已删除条目（在已删除页面可见，若在已删除页面删除对应条目，则不会再包含）
  int syncedFilesCount;


  SyncInfo({int? state, this.msg = '', TimeData? time, this.syncedFilesCount = 0})
    : state = state ?? SyncInfoState.started,
      // 如果新建，整成空时间，不要用当前时间，会误以为刚同步过，不好
      time = time ?? TimeData();

  factory SyncInfo.fromJson(Map<String, dynamic> json) => _$SyncInfoFromJson(json);

  Map<String, dynamic> toJson() => _$SyncInfoToJson(this);

  @override
  String toString() {
    return 'state: $state, msg: $msg, time: $time, syncedFilesCount: $syncedFilesCount';
  }

  String lastSyncAtStr() {
    return "${time.formattedStr()}${msg.isEmpty ? "" : ", $msg"}";
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SyncInfo && runtimeType == other.runtimeType &&
              state == other.state && msg == other.msg && time == other.time && syncedFilesCount == other.syncedFilesCount;

  @override
  int get hashCode => Object.hash(state, msg, time, syncedFilesCount);


  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

  static Future<SyncInfo> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return SyncInfo.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  void updateToSuccess({String msg = '', required int remoteFilesCount}) {
    // 这里不更新时间，写入文件时再更新
    // time = TimeData.now();
    this.msg = msg;
    state = SyncInfoState.finished;
    syncedFilesCount = remoteFilesCount;
  }

  void updateToError({required bool rollbackSuccess, required String msg, required int remoteFilesCount}) {
    this.msg = msg;
    state = rollbackSuccess ? SyncInfoState.errorButRollbackSuccess : SyncInfoState.error;
    syncedFilesCount = remoteFilesCount;
  }

}


// class PfsDiffResult {
//   // 本地files pfs文件存在，执行diff：
//   // 1 本地有某条目，远程无，添加到删除列表 deleteWorkdirFiles
//   Set<PfsDiffItem> deleteIfWorkdirMatchLocalFileInfoLatestOidElseIsConflict = {};
//   // 2 本地无某条目，远程有，添加到代表覆盖workdir文件的overwriteWorkdirFiles列表
//   Set<PfsDiffItem> remoteOverwriteWorkdirIfFileDoesntExistOrMatchLocalFileInfoOrSkipIfOidMatchRemoteElseIsConflict = {};
//   // 3 本地有某条目，远程也有：
//   //   1. 若最新oid一样，如果workdir和远程oid不匹配或workdir文件不存在，则上传
//   Set<PfsDiffItem> uploadIfWorkdirOidDoesntMatchRemoteFileInfoLatestOidOrDoesntExist = {};
// //   2.1 若最新oid不一样，如果远程最新是删除，添加到删除列表（类型1），
// //   2.2 如果远程最新不是删除，添加到覆盖列表（类型2）
//
// // 4 本地远程皆无某条目，不用管，后面扫描workdir查找untracked条目时会处理这种情况
// }

class PfsDiffItem {
  FilePath relativePath;

  FileInfo? remoteFileInfo;
  // 以下两个node不可能都为null，至少一个可用，否则relativePath也可能为null，
  // 关键在于：如果两个都为null，这个实例就没必要创建，那种应该属于untracked条目，在那里创建才对
  VersionNode? remoteFileInfoLatestNode;
  FileInfo? localFileInfo;
  VersionNode? localFileInfoLatestNode;

  PfsDiffItem({
    required this.relativePath,

    required this.remoteFileInfo,
    required this.remoteFileInfoLatestNode,
    required this.localFileInfo,
    required this.localFileInfoLatestNode,
  });


}


Future<void> findFilesChanges(
  DataMap srcLocalDataMap,
  // 不要改这个，如果改，先深拷贝
  DataMap srcRemoteDataMap,
  KeyData contentKeyData,
  Set<String>? changes, {
  required Future<void> Function(PfsDiffItem) handler,
  required ThrowIfInterrupted? throwIfInterrupted,
  // 若源datamap可安全修改，则传true，否则false，若传false，使用datamap前会进行拷贝
  required final bool localDataMapCanSafeChange,
  required final bool remoteDataMapCanSafeChange,
}) async {
  if(changes != null && changes.isEmpty) {
    App.logger.debug(_TAG, "remote no changes since last sync, will skip diff them");
    return;
  }

  if(srcLocalDataMap.contentId == srcRemoteDataMap.contentId) {
    App.logger.debug(_TAG, "local and remote files maps contentId are the same, will skip diff them");
    return;
  }

  final localDataMap = localDataMapCanSafeChange ? srcLocalDataMap : srcLocalDataMap.copy();
  final remoteDataMap = remoteDataMapCanSafeChange ? srcRemoteDataMap : srcRemoteDataMap.copy();

  // 本地没有filsMap（原files pfs），可能是importSync，拉取远程所有数据
  if(localDataMap.data.isEmpty) {
    for(final Map<String, dynamic> fileInfoMap in remoteDataMap.data.values) {
      throwIfInterrupted?.call();

      final remoteFileInfo = FileInfo.fromJson(fileInfoMap);
      await handler(
        PfsDiffItem(
          relativePath: FilePath.fromString(remoteFileInfo.path, isRelative: true),
          remoteFileInfo: remoteFileInfo,
          remoteFileInfoLatestNode: remoteFileInfo.curNode(),
          localFileInfo: null,
          localFileInfoLatestNode: null,
        )
      );
    }
  }else {
    if(changes != null && changes.isNotEmpty) {
      for(final relativePathStr in changes) {
        throwIfInterrupted?.call();

        final relativePath = FilePath.fromString(relativePathStr, isRelative: true);
        final oid = await relativePath.toOid(contentKeyData);
        final localFileInfoMap = localDataMap.get(oid);
        final localFileInfo = localFileInfoMap == null ? null : FileInfo.fromJson(localFileInfoMap);
        final remoteFileInfoMap = remoteDataMap.get(oid);
        final remoteFileInfo = remoteFileInfoMap == null ? null : FileInfo.fromJson(remoteFileInfoMap);

        await handler(
          PfsDiffItem(
            relativePath: relativePath,
            remoteFileInfo: remoteFileInfo,
            remoteFileInfoLatestNode: remoteFileInfo?.curNode(),
            localFileInfo: localFileInfo,
            localFileInfoLatestNode: localFileInfo?.curNode(),
          )
        );
      }

      return;
    }

    // 下面是changes 为空或null的场景，全量更新，检查全部条目

    final localLastContentId = localDataMap.contentId;
    // 本地files pfs文件存在，执行diff：
    // 1 本地有某条目，远程无，添加到删除列表 deleteWorkdirFiles
    // 2 本地无某条目，远程有，添加到代表覆盖workdir文件的overwriteWorkdirFiles列表
    // 3 本地有某条目，远成也有：
    //   1. 若最新oid一样，跳过
    //   2. 若最新oid不一样，如果远程最新是删除，添加到删除列表，如果远程最新不是删除，添加到覆盖列表
    // 4 本地远程皆无某条目，不用管
    // 返回列表，然后sync函数删除deleteWorkdirFiles，覆盖存在于overwriteWorkdirFiles的本地文件就行了
    for(final entry in remoteDataMap.data.entries) {
      throwIfInterrupted?.call();

      final oid = VersionOid(value: entry.key);
      // final String path = entry.value["path"];  // FileInfo 的path字段名

      final FileInfo remoteFileInfo = FileInfo.fromJson(entry.value);

      final rRelativePath = FilePath.fromString(remoteFileInfo.path, isRelative: true);
      FileInfo? localFileInfo;
      final localValue = localDataMap.get(oid);
      if(localValue != null) {
        localFileInfo = FileInfo.fromJson(localValue);
      }

      if(localFileInfo == null) {
        // 远程有，本地无
        await handler(
          PfsDiffItem(
            relativePath: rRelativePath,
            remoteFileInfo: remoteFileInfo,
            remoteFileInfoLatestNode: remoteFileInfo.curNode(),
            localFileInfo: localFileInfo,
            localFileInfoLatestNode: localFileInfo?.curNode(),
          )
        );
      }else {
        // 远程有，本地有
        // 如果不同，则代表有更新，需要处理；
        // 如果相同，不用调用，后续会在查找workdir修改的和untracked文件时上传这些文件
        if(localFileInfo.curNode().oid.value != remoteFileInfo.curNode().oid.value) {
          await handler(
            PfsDiffItem(
              relativePath: rRelativePath,
              remoteFileInfo: remoteFileInfo,
              remoteFileInfoLatestNode: remoteFileInfo.curNode(),
              localFileInfo: localFileInfo,
              localFileInfoLatestNode: localFileInfo.curNode(),
            )
          );
        }

        // 理论上来说，remove不会增加hash冲突，所以也不会导致re-hash（取决于具体实现，但通常不会），所以remove的性能应该不会太差
        localDataMap.remove(oid, localLastContentId);
      }
    }

    // 剩下的就是远程无，本地有的条目，这种可能是远程执行过clean或者在回收站彻底删除了对应文件，
    // 导致某些fileInfo记录消失了，而本地没clean过也没删除过回收站条目，所以还有，
    // 这种条目应该当作已删除来处理，冲突判定逻辑也和已删除相同
    for(final lEntry in localDataMap.data.entries) {
      throwIfInterrupted?.call();

      // final oidStr = lEntry.key;
      // final String path = lEntry.value["path"];


      final FileInfo localFileInfo = FileInfo.fromJson(lEntry.value);
      await handler(
        PfsDiffItem(
          relativePath: FilePath.fromString(localFileInfo.path, isRelative: true),
          remoteFileInfo: null,
          remoteFileInfoLatestNode: null,
          localFileInfo: localFileInfo,
          localFileInfoLatestNode: localFileInfo.curNode(),
        )
      );
    }
  }
}

@myJsonSerializable
class JsonStrSet implements JsonByteStream {
  Set<String> storage;

  JsonStrSet({Set<String>? storage})
    : storage = storage ?? {};


  factory JsonStrSet.fromJson(Map<String, dynamic> json) => _$JsonStrSetFromJson(json);

  Map<String, dynamic> toJson() => _$JsonStrSetToJson(this);

  void add(String str) {
    storage.add(str);
  }

  void addAll(Set<String>? strs) {
    if(strs == null) {
      return;
    }

    storage.addAll(strs);
  }

  // 会把str对应的路径替换成基于仓库基本路径或dataDir前缀的路径
  void addRepoBasedPath(Repo repo, String path) {
    add(getRepoBasedPath(repo, path));
  }

  Stream<String> restoredRepoBasedPathToAbs(Repo repo) async* {
    for(final path in storage) {
      yield RepoPathPlaceHolder.restorePrefixForRepo(repo, path);
    }
  }

  void removeByRepoBasedPath(Repo repo, String path) {
    final pathWillRemove = getRepoBasedPath(repo, path);
    // 路径如果已经被添加到待移除的列表，移除，因为这个对象刚推，可能有用，不该删除
    storage.removeWhere((it) => it == pathWillRemove);
  }

  bool isEmpty() => storage.isEmpty;

  bool isNotEmpty() => !isEmpty();

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

  static Future<JsonStrSet> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return JsonStrSet.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  static String getRepoBasedPath(Repo repo, String path) {
    return RepoPathPlaceHolder.replacePrefixForRepo(repo, path);
  }

}

class CopiedFile {
  VirtualFile? file;
  String oidStr;

  CopiedFile({this.file, this.oidStr = ''});

  static Future<CopiedFile> fromWorkdirFile(
    String workdirBasePath, 
    File? workdirFile,
    KeyData contentKeyData, 
    TempDir tempDir,
    Index index,
    FilePath relativePath, {
    VersionOid? localFiLatestOid,
  }) async {
    final copied = CopiedFile();
    copied.oidStr = VersionOid.deleted.value;
    final workdirFilePath = workdirFile?.absolute.path;
    if(workdirFile == null || await isDeletedForRepo(workdirFilePath!)) {
      // file: null, oid: deleted
      App.logger.debug(_TAG, "workdirFileOid: ${copied.oidStr}");
      return copied;
    }


    // is File and exists

    // 若索引匹配，不拷贝文件不计算hash，直接使用local fi最新oid
    if(localFiLatestOid != null) {
      final indexItem = index.get(relativePath);
      if(indexItem != null && await indexItem.matchFile(workdirFile)) {
        // 若匹配索引，则在上次同步后没改过，依然是本地最新file info oid，无需计算，
        // 这时也不需要file字段，因为如果和workdir和本地最新oid匹配，则会触发覆盖，
        // 并不会发生冲突或需要上传本地文件，因此，不需创建文件拷贝
        copied.oidStr = localFiLatestOid.value;
        return copied;
      }
    }


    // 拷贝到 tempDir/workdir/文件在真实workdir的相对路径
    copied.file = await VirtualFile.fromWorkdirPath(workdirBasePath, workdirFilePath, tempDir);
    copied.oidStr = await copied.file!.hashWithKeyData(contentKeyData);

    // App.logger.debug(_TAG, "workdirFileOid: ${copied.oidStr}");

    return copied;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is CopiedFile && runtimeType == other.runtimeType &&
              file == other.file && oidStr == other.oidStr;

  @override
  int get hashCode => Object.hash(file, oidStr);

  @override
  String toString() {
    return 'CopiedFile{file: $file, oidStr: $oidStr}';
  }


}

// 改成了直接从pfs里找出要删除的要覆盖，替换第一轮循环，保留后面的循环，
//  不用解密本地文件了，[syncCacheDirPath] 可以删了，直接用 syncCacheDirPath做参数[remoteDataDirPath]即可
Future<SyncResult> doSync(
  KeyData contentKeyData,

  /// 绝对路径
  String remoteDataDirPath,
  String workdirBasePath,


  Repo repo,
  // download/upload cache
  // 这个目录遵循 remote目录结构，包含files和objects文件以及仓库版本
  TempDir tempDir,
  Index index,
  String syncCacheDirPath,
  ThrowIfInterrupted? throwIfSyncCanceled,
  SyncProgressCb? syncProgressCb,
  Set<String>? changes,
  // 为true的会执行拉取和推送的检测，否则和本地的数据应该是一样的，直接忽略
  bool Function(EncryptedData) predication, {
  ConflictResolveStrategy? conflictResolveStrategy,

  // 不需要此参数了，因为本地会检查到远程已删除，但本地还存在的file info，
  // 然后删除他们关联的oid，并且最后远程已删除对应fileinfo或msg的最新map会覆盖本地的map
  // required Set<String>? deletedFileInfoOrMsgs,
}) async {
  // 重置当前线程缓存的数据记数
  VirtualFile.reset();

  final conflictResolveStrategy2 = conflictResolveStrategy ?? ConflictResolveStrategy.workdirOverwriteRemote;

  if(!ConflictResolveStrategy.isKnown(conflictResolveStrategy2)) {
    throw AppException("unknown conflict resolve strategy: ${conflictResolveStrategy2.value}");
  }

  final lastContentIdOfIndex = index.contentId;

  // final syncCacheDir = getAndMakeSureDirExists(syncCacheDirPath);

  final remote = repo.remote;
  // final lastSyncTime = await repo.getLastSyncTime();
  // final objMap = remote.objMap!;
  // final filesPfs = remote.filesPfs!;

  final syncResult = SyncResult();

  // final remoteFileInfoOidStrSet = <String>{};

  final client = repo.client;

  App.logger.debug(_TAG, "#doSync(): loop1 start at: ${DateTime.timestamp().millisecondsSinceEpoch}");


  // broadcast true或false没影响
  final emptyFileOidStr = bytesToHex(await hashStreamWithKeyData(contentKeyData, Stream.empty(broadcast: false), throwIfInterrupted: throwIfSyncCanceled));

  App.logger.debug(_TAG, "#doSync(): empty file oid is: $emptyFileOidStr");


  int count = 0;
  int allCount = 0;
  // final emptyFilePath = FilePath();

  // 值是unix格式的filepath，用filePath.toMapKey()，比较合适，内部就是unixStr
  // 远程文件，在同步过程中，新增节点为 Deleted 的条目
  // 这个记录的是remote pfs将会删除的文件，但由于还没提交会话，
  // 所以remote的pfs实际还没删除，所以在查找应该更新成已删除的fileinfo时，会用到这个集合，
  // 跳过对应路径，因为对应条目提交时会标记为删除，所以此时就无需处理了
  // 遍历workdir查找untracked文件时，遍历与否这个都行，不会出错，但应该是没意义的，因为标记为删除的条目应该不会存在于workdir，否则就不会标记为删除
  final remoteFilesDeletedWhenSync = <String>{};

  // 这个添加的是基于仓库的相对路径，删除的是
  // dataDir/remote/files|objects/oid/data.enc 这类非workdir下的文件，
  // 如果要删除workdir下的文件，应该使用workdirDeletedFiles
  // 应该把误删也无所谓的文件放这个列表，比如objects，删了的话用的时候若没有会自动下载，所以误删也无所谓，重要的文件不要往这放，若放，需确保希望文本存在时将其从这个列表移除
  final deleteAnywayFiles = JsonStrSet();
  // 这个是已删除的fileInfo和msg关联的objects，如果有这个列表，添加上，顺便删了
  // deleteAnywayFiles.addAll(deletedFileInfoOrMsgs);

  final handledFileInfoRelativePaths = <String>{};
  // workdir将会被删除的条目（会先记录到syncCache，在同步后再真删除workdir的文件）
  final workdirDeletedFiles = WorkdirFiles();
  // workdir将会被覆盖为远程最新版本的条目（会先存到syncCache/workdir，在同步后再真覆盖）
  final workdirOverwriteFiles = WorkdirFiles();


  // x 检查了，已确保）确保操作的是新增的或者remote的file info，不要上传local的，
  // 因为local的有可能out of date，比如远程已经更新了100次版本，
  // 早把本地的file info节点都淘汰了，若使用本地的就会关联无效obj
  Future<void> deleteFileInfoNode(VersionNode deletedNode, FileInfo fileInfo) async {
    await remote.deRefWithObj(objOid: deletedNode.oid);
  }


  // 更新workdir文件
  Future<void> overwriteWorkdirFile(
    FilePath relativePath,
    VersionOid? rfLatestOid,
    String workdirFileFullPath,

    // 计划是用本地file info节点来在删除或覆盖前验证文件hash的，若匹配则删除或覆盖，不过由于性能原因，实际上没验证，直接执行操作了
    VersionOid? lfLatestOid,
  ) async {
    if(rfLatestOid == null || rfLatestOid.value == VersionOid.deleted.value) {
      // 删除本地文件
      final workDirFile = File(workdirFileFullPath);

      // 这个是删除的，记录到列表先
      await workdirDeletedFiles.addFile(relativePath, workDirFile, lfLatestOid?.value ?? '');

      // 移除索引条目
      index.remove(relativePath, lastContentIdOfIndex);

      syncResult.result.addDeletedItem(DeletedItem(path: relativePath.toUnixPathStr(), oldOid: lfLatestOid?.shortValue() ?? ""));
    }else {
      final workdirFile = File(workdirFileFullPath);

      // 把文件存到syncCache里先，提交后再拷贝到正式目录
      // syncCache/workdir/文件在正式目录下的相对路径
      final workdirFileFullPathInSyncCache = await getFileAndMakeSureParentDirExist(
        p.join(
          syncCacheDirPath,
          Repo.workdirDirName,
          relativePath.toString()
        )
      );

      final objOid = rfLatestOid;
      final localObjFile = await repo.getLocalOrFetch(
        RemoteDataType.objects,
        objOid,
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

      await workdirOverwriteFiles.addFile(relativePath, workdirFile, lfLatestOid?.value ?? '');

      // 更新索引信息
      // 这个更新的还是真正的workdir文件的信息，不过其实没什么用，后面遍历文件时
      // 会直接检测，如果在将覆盖的文件列表，则直接跳过，因此这个index.match()与否就不重要了
      // 之后把syncCache的文件移动到正式目录时，移动文件后，会再更新对应条目的索引
      index.add(relativePath, await IndexItem.fromFile(workdirFile, objOid.value), lastContentIdOfIndex);
    }

    // 更新文件的总数，包含deleted
    // 例如更新了10个，其中3个是删除，之前会显示更新了7个，删了3个，（和上传文案： pushed 10, deleted 3 不匹配）
    // 现在(after 20260422)显示更新了10个删了3个（和上传文案： pushed 10, deleted 3 匹配）
    syncResult.result.addUpdatedItem(UpdatedItem(path: relativePath.toUnixPathStr(), oldOid: lfLatestOid?.shortValue() ?? "", newOid: rfLatestOid?.shortValue() ?? ""));
  }

  // 这个不用刻意覆盖了，如果fetch了，先到syncCache，后到本地正式目录，若没fetch，则无，但无所谓，
  // 使用时，先检查本地仓库dataDir/remote/files里是否有对应条目，若无，则下载即可
  // 更新本地的remote/files清单文件
  // void overwriteFileInfo(String fileInfoOidStr, File remoteFileInfoFile) {
  //   // 移动temp目录下的files文件到本地remote/files目录
  //   final localFileInfoFileInSyncCache = getFileAndMakeSureParentDirExist(
  //       Repo.getFileInfoPathByOidStr(syncCacheDirPath, fileInfoOidStr)
  //   );
  //
  //   // 有时候直接下载到 syncCache了，所以不需要移动
  //   if(remoteFileInfoFile.absolute.path != localFileInfoFileInSyncCache.absolute.path) {
  //     // 先移动到syncCache
  //     await remoteFileInfoFile.rename(localFileInfoFileInSyncCache.absolute.path);
  //   }
  // }

  Future<void> addNodeThenPush(
    FilePath fileInfoPath,
    VersionNode node,
  ) async {
    final fileInfoOid = await fileInfoPath.toOid(contentKeyData);

    final fileInfoForPush = await remote.fetchFileInfo(
      fileInfoOid,
      tempDir,
    );

    fileInfoForPush!.addNode(node, removedOverLimitedNodeHandler: deleteFileInfoNode);
    await remote.pushFileInfo(fileInfoForPush, contentKeyData, tempDir);

    // 关联obj
    await remote.addRefToObj(node.oid);

    // x 废弃，若出错，会尝试回滚，不用修改时间判断了）推送文件后，更新下最后同步时间，不然下次拉取还会下载这个file info
    // await repo.updateLastSyncTime(tempDir);

    syncResult.result.addPushedItem(PushedItem(path: fileInfoForPush.path, objOid: node.oid.shortValue()));

    // 新删除的东西，remote的pfs实例此时还没更新，所以到后面检测workdir删除的文件时，跳过即可，先记录下来，到时候才能跳过
    if(node.oid.value == VersionOid.deleted.value) {
      remoteFilesDeletedWhenSync.add(fileInfoForPush.path);
    }

  }

  Future<void> createFileInfoThenPush(
    FilePath relativePath,
    VersionNode node,
  ) async {
    if(node.oid == VersionOid.deleted) {
      throw AppException("#createFileInfoThenPush err: node oid is 'Deleted', err code: 14341334");
    }

    final fileInfoForPush = FileInfo(path: relativePath.toUnixPathStr());
    fileInfoForPush.addNode(node, removedOverLimitedNodeHandler: deleteFileInfoNode);
    await remote.pushFileInfo(fileInfoForPush, contentKeyData, tempDir);

    // final fileInfoOid = await fileInfoForPush.toOid(contentKeyData);
    await remote.addRefToObj(node.oid);

    // x 废弃，若出错，会尝试回滚，不用修改时间判断了）推送文件后，更新下最后同步时间，不然下次拉取还会下载这个file info
    // await repo.updateLastSyncTime(tempDir);

    syncResult.result.addPushedItem(PushedItem(path: fileInfoForPush.path, objOid: node.oid.shortValue()));
  }


  Future<Msg> createConflictMsgThenPush(
    VersionNode workdirFileNode,
    FilePath relativePath,
    VersionOid? localFiOid,
    VersionOid? remoteFiOid,
  ) async {
    final workdirFileOid = workdirFileNode.oid;
    final pathStr = relativePath.toUnixPathStr();
    final msgData = MsgDataConflict(
      path: pathStr,
      localOid: localFiOid,

      // 这个会是下一个file info的版本，并且将在同步后成为workdir的最新文件内容
      workdirOid: workdirFileOid,

      remoteOid: remoteFiOid,
      resolveStrategy: conflictResolveStrategy2.value
    );

    final msg = Msg(
      // 内容冲突
      title: "",  // 没必要记什么东西，浪费空间，若要取path，可去msgData里取
      type: MsgType.conflict,
      data: msgData.toJson()
    );

    // 输出示例：workdirOverwriteRemote, abc123 overwrite def456, conflict id: hjk789
    workdirFileNode.note = "${msgData.resolveStrategyToText()}, ${ConflictResolveStrategy.genWhoOverwriteWho(msgData)}, conflict id: ${msg.oid.shortValue()}";

    await remote.pushMsg(msg, contentKeyData, tempDir);

    // 让object关联上msg
    // final objRef = ObjRef(type: ObjRefType.msg, oid: msg.oid.value);
    if(localFiOid != null) {
      // 有可能远程更新节点超过数量限制，已经淘汰本地最新节点，这时，若本地有最新节点的object，
      // 则上传到远程，否则，冲突msg将关联到一个无效object（后果其实也没那么严重，
      // 因为如果一个节点被淘汰，那必然是超过10次都没使用过的节点，很可能已经没用了）
      final remoteHasObj = await remote.uploadObjIfLocalHasButRemoteNone(localFiOid, remoteDataDirPath, tempDir);

      // 只有当远程有对应节点时，才让msg关联对应obj，否则不用关联（对应obj可能超过历史记录数量限制被移除了）
      if(remoteHasObj) {
        await remote.addRefToObj(localFiOid);
      }
    }

    await remote.addRefToObj(workdirFileOid);

    if(remoteFiOid != null) {
      await remote.addRefToObj(remoteFiOid);
    }


    syncResult.result.addConflictsItem(ConflictItem(path: pathStr, conflictId: msg.oid.shortValue()));

    return msg;
  }


  Future<void> resolveConflict(
    VersionOid fileInfoOid,
    VersionNode workdirFileNode,
    FilePath relativePath,
    String workdirFileFullPath,
    // 有可能是deleted，所以可以为null
    VirtualFile? workdirFileCopy, {
    required VersionOid? lfLatestOid,
    // 既然有冲突，远程条目肯定不为null，否则就不会冲突，
    // 若远程条目为null，本地直接该清理清理（远程执行过清理，少了某些file info的情况，本地需清理对应file info关联的objects），
    // 该覆盖覆盖（workdir和local file info最新节点匹配的情况，直接使用remote file info覆盖workdir 文件）
    required VersionOid rfLatestOid,
  }) async {
    // 处理特殊情况：本地文件存在，但是空文件，这时直接用远程覆盖本地即可，就不当作冲突了
    // 本地文件虽然存在，但其实是空文件，这种情况就不用当作冲突了，直接用远程覆盖本地即可，
    // 就算删除也只是删除个空文件而已，而且远程remote file info还存在，
    // 有两种情况：
    // 1 远程最新节点是已删除，这种情况可去回收站找回记录，
    // 2 远程最新节点(rfLatestOid)不是已删除，这种情况会是远程文件内容覆盖本地的空文件，没数据丢失
    // 如果workdirFileNode.oid是Deleted，则文件必然已经删除或对仓库来说不存在，直接覆盖即可
    // 注：如果文件类型改变，比如之前是file，现在是dir，则这里覆盖时会报错。
    if(workdirFileNode.oid.value == VersionOid.deleted.value
        || await isFileNonExistsOrEmpty(File(workdirFileFullPath))
    ) {
      await overwriteWorkdirFile(
        relativePath,
        rfLatestOid,
        workdirFileFullPath,
        lfLatestOid
      );

      // 远程覆盖工作目录文件，obj肯定在远程啊，所以就不需要上传了，直接返回即可
      return;
    }

    // 必须先上传obj，再上传msg和file info，不然会找不到关联的obj而报错
    // 上传冲突的那个workdir文件
    if(workdirFileCopy != null) {
      // 路径如果已经被添加到待移除的列表，移除，因为这个对象刚推，可能有用，不该删除
      deleteAnywayFiles.removeByRepoBasedPath(repo, Repo.getLocalRemoteObjectPathByOidStr(remoteDataDirPath, workdirFileNode.oid.value));

      await remote.pushRawFileToObject(
        workdirFileCopy,
        workdirFileNode.oid,
        contentKeyData,
        remoteDataDirPath,
        tempDir,
        moveToRemoteDataDirAfterPushed: true,
      );
    }



    // 如果冲突合并策略不是本地覆盖远程，则创建冲突消息（目前只专注于本地覆盖远程的合并策略，
    //   若不是这个策略，可能细节有偏差，暂不处理，直接创建冲突消息）；
    // 如果远程为deleted，本地有文件，且冲突，则不创建冲突 msg，直接本地覆盖远程即可；
    // 如果远程为空文件，本地有文件且非空，则不创建 冲突msg， 直接把本地当作新增上传；
    // 若非以上情况，则 创建一个通知消息。

    // 下面两个条件的相反条件是：如果冲突处理策略是 workdirOverwriteRemote ，并且远程最新节点是已删除或者是空文件，则不创建冲突消息，这时，直接用workdir版本新增节点，并且标记为 conflictOverwrite 就行了

    // 如果冲突处理策略不是 workdirOverwriteRemote ，代表remote要覆盖本地有内容的数据了，必须创建冲突消息，不然本地workdir数据就丢了
    if(conflictResolveStrategy2 != ConflictResolveStrategy.workdirOverwriteRemote ||

      // 如果冲突处理策略是 workdirOverwriteRemote ，且远程节点是有内容的文件，则创建冲突消息，若远程节点是已删除或空文件，直接后面本地覆盖远程就行了
      (rfLatestOid.value != VersionOid.deleted.value && rfLatestOid.value != emptyFileOidStr)
    ) {
      await createConflictMsgThenPush(
        workdirFileNode,
        relativePath,
        lfLatestOid,
        rfLatestOid
      );
    }


    // final objectRelatedMsgOrFileInfos = <ObjRef>{};
    // objectRelatedMsgOrFileInfos.add(ObjRef(type: ObjRefType.msg, oid: msg.oid.value));

    // 根据冲突策略来处理:
    // 如果是workdir覆盖远程，则上传新节点到fileInfo；
    // 如果是远程覆盖workdir，则用远程最新节点覆盖workdir文件，用户可在冲突列表页面找到被覆盖的workdir文件版本
    if(conflictResolveStrategy2 == ConflictResolveStrategy.workdirOverwriteRemote) {
      // 更新远程的file info，本地最新的文件内容oid成为最新版本，可在通知中心或文件历史记录找到被覆盖的版本
      await addNodeThenPush(relativePath, workdirFileNode);
      // if(!ObjRef.isInvalidOid(fileInfoOid.value)) {
      //   objectRelatedMsgOrFileInfos.add(ObjRef(type: ObjRefType.fileInfo, oid: fileInfoOid.value, path: relativePath.toUnixPathStr()));
      // }
    }else if(conflictResolveStrategy2 == ConflictResolveStrategy.remoteOverwriteWorkdir) {
      await overwriteWorkdirFile(
        relativePath,
        rfLatestOid,
        workdirFileFullPath,
        lfLatestOid
      );
    }else {
      throw AppException("unknown conflict resolve strategy: $conflictResolveStrategy2");
    }
  }

  // x 废弃，改用files.map.enc后，不需要下载了，最后统一保存files map到本地即可）下载fileinfo的data.enc到syncCache
  // Future<FileInfo> downloadRemoteFileInfoFile(FilePath filePath) async {
  //   return (await remote.fetchFileInfo(
  //     filePath.toUnixPathStr(),
  //     syncCacheDirPath,
  //     tempDir,
  //     moveToRemoteDataDirAfterDownload: true
  //   ))!;
  // }

  Future<VersionNode> createConflictWorkdirFileNode(
    final String workdirFileHash,
    final int? fileSizeInBytes
  ) async {
    return VersionNode(
      oid: VersionOid(value: workdirFileHash),
      tag: VersionTag.conflictOverwrite,
      fileSizeInBytes: fileSizeInBytes ?? 0,
      client: client,
    );
  }



  /// 处理本地修改，三体运动，比较三个元素：
  /// 1. 本地 fileInfo 最新路径（记录在本地pfs.enc）
  /// 2. 远程 fileInfo 最新路径（记录在远程pfs.enc）
  /// 3. 以上比较后，比较workdir的文件hash是否与remote fileInfo匹配，再
  ///     根据需要执行 删除、覆盖、创建冲突msg 等操作。
  Future<void> pfsChangesHandler(PfsDiffItem pfsDiffItem) async {
    throwIfSyncCanceled?.call();
    count++;

    final relativePath = pfsDiffItem.relativePath;

    // allCount是0，代表进度不可测，就没必要显示 n/m 的比例数了
    syncProgressCb?.call(SyncProgressAct.updatingFiles, allCount, count, relativePath.toUnixPathStr());

    final fileInfoOid = await relativePath.toOid(contentKeyData);
    handledFileInfoRelativePaths.add(relativePath.toMapKey());

    final workdirFileFullPath = p.join(workdirBasePath, relativePath.toString());
    // 只要不是标准文件都当作已经删除
    final workdirFileIsDeleted = await isDeletedForRepo(workdirFileFullPath);
    final rfLatestNode = pfsDiffItem.remoteFileInfoLatestNode;
    final rfLatestOid = rfLatestNode?.oid;
    final remoteFileIsNullOrDel = rfLatestOid == null || rfLatestOid.value == VersionOid.deleted.value;



    // 现在workdir一定是文件或已删除了
    final workdirFile = File(workdirFileFullPath);

    final lfLatestNode = pfsDiffItem.localFileInfoLatestNode;
    final lfLatestOid = lfLatestNode?.oid;


    // App.logger.debug(_TAG, 'relativePath: $relativePath');
    // App.logger.debug(_TAG, 'rfOid: ${rfLatestOid?.value}');
    // App.logger.debug(_TAG, 'lfOid: ${lfLatestOid?.value}');

    // 本地无对应fileInfo
    if(rfLatestNode != null && lfLatestNode == null) {

      // 本地fileInfo无，workdir有
      if(!workdirFileIsDeleted) {
        final copiedFile = await CopiedFile.fromWorkdirFile(workdirBasePath, workdirFile, contentKeyData, tempDir, index, relativePath, localFiLatestOid: lfLatestOid);
        final workdirFileCopy = copiedFile.file!;
        final workdirFileHash = copiedFile.oidStr;

        //本地fi无，workdir有，远程fi有
        if(!remoteFileIsNullOrDel) {
          //检查hash是否一样，若不一样，则是冲突（本地fi无，workdir有hash1，远程fi有hash2，三者各不相同，则冲突）
          // 若一样，无需处理
          if(workdirFileHash != rfLatestOid!.value) {
            await resolveConflict(
              fileInfoOid,
              await createConflictWorkdirFileNode(workdirFileHash, await workdirFileCopy.length()),
              relativePath,
              workdirFileFullPath,
              workdirFileCopy,
              lfLatestOid: lfLatestOid,
              rfLatestOid: rfLatestOid
            );
          }
        }else {
          // 由于进入到这里时 rfLatestNode != null ，所以这时remote file必然是已删除，因此这个必然是远程最新节点为已删除但本地又创建了的文件，所以新增节点上传即可
          // 本地fi无，workdir有，远程fi无，上传 (这个属于删除又恢复的文件，所以远程fileInfo实际是存在的，只是最新节点是已删除)
          final workdirFileOid = VersionOid(value: workdirFileHash);
          await remote.pushRawFileToObject(
            workdirFileCopy,
            workdirFileOid,
            contentKeyData,
            remoteDataDirPath,
            tempDir,
            moveToRemoteDataDirAfterPushed: true,
          );

          await addNodeThenPush(
            relativePath,
            VersionNode(
              oid: workdirFileOid,
              tag: VersionTag.normal,
              fileSizeInBytes: await workdirFileCopy.length(),
              client: client,
            ),
          );
        }

        await copiedFile.file?.clear();

      }else {
        if(!remoteFileIsNullOrDel) {
          // 本地fi无，远程fi有，workdir无，覆盖
          await overwriteWorkdirFile(
            relativePath, rfLatestOid, workdirFileFullPath, lfLatestOid
          );

        }
        // else {
        //   // 本地fi无，远程fi无，workdir无，跳过
        // }
      }

      // 直接就下载到syncCache了，不需要overwrite了
      // await downloadRemoteFileInfoFile(relativePath);

      // overwriteFileInfo(fileInfoOid.value, await downloadRemoteFileInfoFile(fileInfoOid));
    }else if(rfLatestNode != null && lfLatestNode != null) {
      if(!workdirFileIsDeleted) {
        // 检查和本地是否匹配，若匹配，检查和远程是否匹配，若不匹配，则覆盖
        // 检查和本地是否匹配，若不匹配，检查和远程是否匹配，若不匹配，则冲突，若匹配，则只需覆盖file info
        final copiedFile = await CopiedFile.fromWorkdirFile(workdirBasePath, workdirFile, contentKeyData, tempDir, index, relativePath, localFiLatestOid: lfLatestOid);
        final workdirFileCopy = copiedFile.file;
        final workdirFileHash = copiedFile.oidStr;

        if(workdirFileHash == lfLatestOid!.value) {
          if(workdirFileHash != rfLatestOid!.value) {
            await overwriteWorkdirFile(
              relativePath,
              rfLatestOid,
              workdirFileFullPath,
              lfLatestOid
            );
          }
        }else {
          if(workdirFileHash != rfLatestOid!.value) {
            await resolveConflict(
              fileInfoOid,
              await createConflictWorkdirFileNode(workdirFileHash, await workdirFileCopy!.length()),
              relativePath,
              workdirFileFullPath,
              workdirFileCopy,
              lfLatestOid: lfLatestOid,
              rfLatestOid: rfLatestOid
            );
          }
        }

        await copiedFile.file?.clear();

      }else {
        // 本地workdir文件删除了
        final copiedFile = await CopiedFile.fromWorkdirFile(workdirBasePath, null, contentKeyData, tempDir, index, relativePath, localFiLatestOid: lfLatestOid);
        final workdirFileCopy = copiedFile.file;
        final workdirFileHash = copiedFile.oidStr;

        if(workdirFileHash == lfLatestOid!.value) {
          if(workdirFileHash != rfLatestOid!.value) {
            await overwriteWorkdirFile(
              relativePath,
              rfLatestOid,
              workdirFileFullPath,
              lfLatestOid
            );
          }
        }else {
          if(workdirFileHash != rfLatestOid!.value) {
            await resolveConflict(
              fileInfoOid,
              await createConflictWorkdirFileNode(workdirFileHash, await workdirFileCopy?.length()),
              relativePath,
              workdirFileFullPath,
              workdirFileCopy,
              lfLatestOid: lfLatestOid,
              rfLatestOid: rfLatestOid
            );
          }
        }

        await copiedFile.file?.clear();

      }

      // await downloadRemoteFileInfoFile(relativePath);

      // overwriteFileInfo(fileInfoOid.value, await downloadRemoteFileInfoFile(fileInfoOid));
    }else if(rfLatestNode == null && lfLatestNode != null) {
      // 放if外面是为了用来在删除本地obj时跳过此条目
      String? workdirFileHash;
      bool createdNewNode = false;

      if(!workdirFileIsDeleted) {
        // 检查和本地是否匹配，若匹配，删除，若不匹配，【新增节点】，上传
        final copiedFile = await CopiedFile.fromWorkdirFile(workdirBasePath, workdirFile, contentKeyData, tempDir, index, relativePath, localFiLatestOid: lfLatestOid);
        final workdirFileCopy = copiedFile.file;
        workdirFileHash = copiedFile.oidStr;

        // 本地fi和workdir文件相同，直接远程覆盖本地即可（由于远程可能因为执行过清理导致file info无了，所以这里的覆盖实际上是删除操作）
        if(lfLatestOid!.value == workdirFileHash) {
          // 删除文件 （注意：在这删除后，本地文件历史将丢失，因为远程可能对这个路径在回收站执行了删除，所以，
          // 这里删除workdir的文件后，最终会变成files map无此条目，工作目录也无此文件，就彻底删除了）
          await overwriteWorkdirFile(relativePath, rfLatestOid, workdirFileFullPath, lfLatestOid);
        }else {
          createdNewNode = true;

          final workdirFileOid = VersionOid(value: workdirFileHash);
          await remote.pushRawFileToObject(
            workdirFileCopy!,
            workdirFileOid,
            contentKeyData,
            remoteDataDirPath,
            tempDir,
            moveToRemoteDataDirAfterPushed: true,
          );


          // localFileInfo hash = 1
          // remoteFileInfo 不存在
          // workdirHash = 2
          // 这种情况严格来说算是冲突，但是由于远程不会丢失任何文件，所以当作新文件上传了
          await createFileInfoThenPush(
            relativePath,
            VersionNode(
              oid: workdirFileOid,
              fileSizeInBytes: await workdirFileCopy.length(),
              client: client
            )
          );
        }

        await copiedFile.file?.clear();

      }


      // 远程fi不存在，本地fi存在，本地workdir已删除或 没删除但已上传了最新版本，清理本地file info关联的objects:
      // 删除本地的fileInfo的data.enc，
      // 记录到待删除的fileInfo的文件列表，sync完成后再删除
      // 存储fileInfo文件路径时，遍历其所有关联的节点，把对应的obj也添加到待删除的集合
      final localFileInfo = pfsDiffItem.localFileInfo;
      if(localFileInfo != null) {
        // 把本地的fileinfo 路径添加到待删除集合
        // 把本地objects 路径添加到待删除集合
        // 注：只删其关联objs即可，不需要删除它本身，用远程files map覆盖本地时，自然就无了
        await for(final objOidInLocal in localFileInfo.allRelatedObjectsOids()) {
          // 不删除被新创建的file info的初始节点引用的那个objects，不然本地下次使用这个对象时还得下载，
          // 出现这种情况的场景：本地记录了文件内容hash为 123的版本，然后上面新创建节点时，
          // 内容也为123，这时会指向相同的object，object引用记数是按file的相对路径和msg的oid统计的，
          // 一个文件引用一个object 1次和100次没区别，除非有其他文件或msg引用，否则，
          // 不管某个path的历史记录包含一个object的oid多少次，都只需要减1次即可解除它和对应object的关联，
          // 因此，如果上面创建的新file info对象的初始节点引用了这里将被删除的oid，
          // 若不在这跳过对应条目，那上面上传的文件就指向了在本地不存在的object，
          // 不过实际上对应的object会上传到远程并和新file info建立关联，因此下次使用时就算本地没有也可以下载，
          // 还有，就算这里跳过，也有可能误删本地被其他file info或msg引用的objects文件，但若无，可下载，
          // 所以问题不大，要全部判断太难了，所以就不处理了，当初设计时，就直接将object设计成若无可下载的类型了
          if(createdNewNode && objOidInLocal.value == workdirFileHash) {
            continue;
          }

          // 先添加到list，最后提交时删除
          // 注：若多个文件引用同一obj，假设这个是已经被远程移除的，而另一个不是，
          // 那么这里其实会导致另一个fi使用的object被移除，
          // 下次查看其历史记录对应条目时，会重新下载
          if(!ObjRef.isInvalidOid(objOidInLocal.value)) {
            deleteAnywayFiles.addRepoBasedPath(repo, Repo.getLocalRemoteObjectPathByOidStr(remoteDataDirPath, objOidInLocal.value));
          }
        }

      }
    } // 最后还剩两者皆为null的情况，这种情况等于没这个fileInfo，不需要在这里处理
  }

  allCount = changes != null && changes.isNotEmpty ? changes.length : remote.filesMap!.size();
  syncProgressCb?.call(SyncProgressAct.checkingChanges, allCount, count, "");

  // BEGIN: DEBUG
  // final tmpLocalFilesMap = await repo.getLocalFilesMap(contentKeyData);
  // await writeStreamToFile(
  //     await getFileAndMakeSureParentDirExist(
  //         p.join(repo.getRepoDebugDirPath(), "local_files_map.json")),
  //     tmpLocalFilesMap.toJsonByteStream()
  // );
  //
  // final tmpRemoteFilesMap = remote.filesMap!;
  // await writeStreamToFile(
  //     await getFileAndMakeSureParentDirExist(
  //         p.join(repo.getRepoDebugDirPath(), "remote_files_map.json")),
  //     tmpRemoteFilesMap.toJsonByteStream()
  // );
  // throw "DEBUG: err code: 13221441";
  // END: DEBUG

  await findFilesChanges(
    // 这里会修改这个map，所以不要共享，单独取1个
    await repo.getLocalFilesMap(contentKeyData),
    // 这里也会修改，canSafeChange传false，使用前会进行拷贝
    remote.filesMap!,

    contentKeyData,
    changes,
    handler: pfsChangesHandler,
    throwIfInterrupted: throwIfSyncCanceled,
    localDataMapCanSafeChange: true,  // 从源文件读取的，且是独享的，可安全修改
    remoteDataMapCanSafeChange: false,  // 内存里共享的，不可安全修改
  );



  App.logger.debug(_TAG, "#doSync(): loop1 end at: ${DateTime.timestamp().millisecondsSinceEpoch}");


  throwIfSyncCanceled?.call();

  Future<bool> isPathHandled(FilePath relativePath) async {
    if(remoteFilesDeletedWhenSync.contains(relativePath.toMapKey())) {
      return true;
    }

    // 若在计划删除的列表，说明之前已经在同步时处理过了，改更新的fileInfo也更新过了，
    // 所以这里直接跳过
    if(workdirDeletedFiles.contains(relativePath)) {
      return true;
    }

    // 刚覆盖过的文件，怎么可能不存在呢？所以跳过
    if(workdirOverwriteFiles.contains(relativePath)) {
      return true;
    }

    if(handledFileInfoRelativePaths.contains(relativePath.toMapKey())) {
      return true;
    }

    return false;
  }


  // 处理本地删除、修改、新增的文件


  count = 0;
  allCount = index.length();

  // 创建个新的index，不然已删除的文件的信息可能还会残留在index中
  final newIndex = syncResult.newIndex;
  final lastContentIdOfNewIndex = newIndex.contentId;

  Future<void> pushModifiedOrAddedFileInfo(FileInfo? fileInfoWillPush, String relativePathUnixStr, VersionOid objOid, VirtualFile virtualFile) async {
    if(fileInfoWillPush == null) {
      return;
    }

    throwIfSyncCanceled?.call();

    syncProgressCb?.call(SyncProgressAct.uploadingChanges, allCount, count, relativePathUnixStr);
    deleteAnywayFiles.removeByRepoBasedPath(repo, Repo.getLocalRemoteObjectPathByOidStr(remoteDataDirPath, objOid.value));

    // x 现在不会了，改成先推obj，然后提交时才关联msg或file info了，推obj的时候不检查了）必须先推obj，若先推file info且之前没上传过这个obj，会提示找不到关联的对象而报错
    await remote.pushRawFileToObject(
      virtualFile,
      objOid,
      contentKeyData,
      remoteDataDirPath,
      tempDir,
      moveToRemoteDataDirAfterPushed: true,
    );

    await virtualFile.clear();

    await remote.pushFileInfo(
      fileInfoWillPush,
      contentKeyData,
      tempDir,
    );

    await remote.addRefToObj(objOid);

    syncResult.result.addPushedItem(PushedItem(path: relativePathUnixStr, objOid: objOid.shortValue()));
  }

  App.logger.debug(_TAG, "#doSync(): findLocalChanges start at: ${DateTime.timestamp().millisecondsSinceEpoch}");


  // 查找并上传删除、修改、新增的文件
  await repo.findLocalChanges(
    index: index,
    lastContentIdOfIndex: lastContentIdOfIndex,
    newIndex: newIndex,
    lastContentIdOfNewIndex: lastContentIdOfNewIndex,
    filesMap: remote.filesMap!,
    contentKeyData: contentKeyData,
    workdirBasePath: workdirBasePath,
    throwIfInterrupted: throwIfSyncCanceled,
    progressCb: syncProgressCb,
    tempDir: tempDir,
    isPathHandled: isPathHandled,
    // 通过文件在仓库workdir下的相对路径计算出来的fileInfoOid
    getFileInfoForComputeHashTaskContextData: (VersionOid fileInfoOid) async {
      try {
        // 若不是null，后续检测到的文件就是修改(modified)；若是null，则是新增(added)
        return await remote.fetchFileInfo(
          fileInfoOid,
          tempDir,
        );
      }catch(e) {
        if(e is! RemoteNotFoundException) {
          rethrow;
        }

        // 是RemoteNotFoundException，代表远程没有对应文件，返回 null
        return null;
      }
    },
    createNewNodeForModifiedAndAddedHandler: true,
    modifiedHandler: ({required String relativePathUnixStr, required int sizeInBytes, required File workdirFileEntity, required VersionNode? versionNode, required FileInfo fileInfoWillPush, required VirtualFile virtualFile}) async {
      fileInfoWillPush.addNode(versionNode!, removedOverLimitedNodeHandler: deleteFileInfoNode);
      await pushModifiedOrAddedFileInfo(fileInfoWillPush, relativePathUnixStr, versionNode.oid, virtualFile);
    },
    addedHandler: ({required String relativePathUnixStr, required int sizeInBytes, required File workdirFileEntity, required VersionNode? versionNode, required VirtualFile virtualFile}) async {
      final fileInfoWillPush = FileInfo(path: relativePathUnixStr);
      fileInfoWillPush.addNode(versionNode!, removedOverLimitedNodeHandler: deleteFileInfoNode);
      await pushModifiedOrAddedFileInfo(fileInfoWillPush, relativePathUnixStr, versionNode.oid, virtualFile);
    },

    // pathOidStr可能用来下载对应的file info文件
    deletedHandler: ({required String path, required String pathOidStr}) async {

      // 执行到这，当前条目为已删除，处理

      // final workdirFileFullPath = result["workdirFileFullPath"];
      // 检测本地文件是否存在，如果不存在，则更新条目为删除
      // 本地文件存在，直接返回
      // 存在的文件在后面遍历workdir查找修改和untracked文件时会处理，这里不用管，
      // 这里只找删除的
      // if(!await isDeletedForRepo(workdirFileFullPath)) {
      //   continue;
      // }

      // 远程有，本地无，已删除，更新远程最新版本为删除

      // 删除的文件，检查是否存在file path，若存在且最新状态不是删除，则标记为删除，若不存在，则不执行操作

      // syncProgressCb?.call(SyncProgressAct.deletingFiles, allCount, count, relativePath.toUnixPathStr());

      throwIfSyncCanceled?.call();

      FileInfo? fileInfoMayPush;
      try {
        // 这里下载是有可能不存在的
        fileInfoMayPush = await remote.fetchFileInfo(
          VersionOid(value: pathOidStr),
          tempDir,
        );
      }catch(e) {
        if(e is! RemoteNotFoundException) {
          rethrow;
        }
      }

      throwIfSyncCanceled?.call();

      // 这个删除的是远程的，并不是真删除，而是在远程fileinfo创建个已删除的节点
      if(fileInfoMayPush != null) {  // 不等于null，代表远程有对应条目，处理；若等于null，代表远程没有（同时本地也没有），不需处理
        final objOid = VersionOid.deleted;
        final remoteLatestOidBeforeAddDeletedNode = fileInfoMayPush.getLatestVersion().oid;
        if(remoteLatestOidBeforeAddDeletedNode.value != objOid.value) {  // 如果远程节点不是已删除，则添加一个已删除节点
          fileInfoMayPush.addNode(VersionNode(oid: objOid, client: client), removedOverLimitedNodeHandler: deleteFileInfoNode);

          // 推送
          await remote.pushFileInfo(
            fileInfoMayPush,
            contentKeyData,
            tempDir,
          );

          // 这里是把文件状态改成删除了，所以不需要更新obj引用，若调用也没事，内部会返回，但若调用还得计算file info oid，浪费性能，所以不调用
          // await remote.addRefToObj(node.oid, ObjRef(type: ObjRefType.fileInfo, oid: fileInfoOid.value, path: fileInfoForPush.path));


          // 推送文件后，更新下最后同步时间，不然下次拉取还会下载这个file info
          // await repo.updateLastSyncTime(tempDir);

          final String relativePathUnix = path;
          syncResult.result.addPushedItem(PushedItem(path: relativePathUnix, objOid: objOid.shortValue()));

          // 这里记录的并不是本地文件删除前的hash，因为已经删除了，无从得知其hash，所以记录的是远程当前最新节点，按理来说应该记录本地的file info的最新节点，但还得解析，所以算了，用远程最新节点凑合下吧
          syncResult.result.addDeletedItem(DeletedItem(path: relativePathUnix, oldOid: remoteLatestOidBeforeAddDeletedNode.shortValue()));
        }
      }
    },
  );

  App.logger.debug(_TAG, "#doSync(): findLocalChanges end at: ${DateTime.timestamp().millisecondsSinceEpoch}");


  throwIfSyncCanceled?.call();

  if(workdirOverwriteFiles.isNotEmpty()) {
    final willOverwriteInSyncCache = await getFileAndMakeSureParentDirExist(p.join(syncCacheDirPath, Repo.workdirWillOverwriteFileName));
    await writeStrToFile(willOverwriteInSyncCache, jsonEncode(workdirOverwriteFiles.toJson()));
  }

  throwIfSyncCanceled?.call();

  if(workdirDeletedFiles.isNotEmpty()) {
    final willDelFileInSyncCache = await getFileAndMakeSureParentDirExist(p.join(syncCacheDirPath, Repo.workdirWillDeleteFileName));
    await writeStrToFile(willDelFileInSyncCache, jsonEncode(workdirDeletedFiles.toJson()));
  }

  throwIfSyncCanceled?.call();

  if(deleteAnywayFiles.isNotEmpty()) {
    final file = await getFileAndMakeSureParentDirExist(p.join(syncCacheDirPath, Repo.deleteAnywayFilesFileName));
    await writeStrToFile(file, jsonEncode(deleteAnywayFiles.toJson()));
  }

  throwIfSyncCanceled?.call();

  return syncResult;

}

//
// Future<bool> _isFileOrDeleted(String fullPath) async {
//   final type = await getFileType(fullPath);
//   return type == FileSystemEntityType.file || type == FileSystemEntityType.notFound;
// }

// 下面两个函数主要用来判断workdir的文件是否存在，平时的时候还是用dart标准的File和Directory来判断
// 另外，同一路径，如果是文件，那么Directory(path).exists()将返回false，如果路径是目录，用File(path).exists()也会返回false


// 对仓库来说，只有file类型是file，dir、link、unix sock，什么的，都不当作文件
Future<bool> isExistsFileForRepo(String fullPath) async {
  final type = await getFileType(fullPath);
  return type == FileSystemEntityType.file;
}


// 对仓库来说，只要不是file，统统当作删除（dir、link、等不同步，当删除）
Future<bool> isDeletedForRepo(String fullPath) async {
  return !(await isExistsFileForRepo(fullPath));
}


// // 太复杂，如果文件不存在，有可能空，有可能真的不存在，这个逻辑加入到上面的同步逻辑里，复杂度会翻至少3倍，容易出错，算了
// Future<bool> isDeletedForRepo(String fullPath, {required bool emptyFileAsDeleted}) async {
//   //存在且是文件
//   if(await isFileForRepo(fullPath)) {
//     // 空文件当作删除
//     if(emptyFileAsDeleted) {
//       // 尝试读一个字节若能读到，说明文件非空
//       final byteStream = File(fullPath).openRead(0, 1);
//       await for(final b in byteStream) {
//         // 文件非空，返回false，代表文件未删除
//         return false;
//       }
//
//       // 文件为空，当作删除
//       return true;
//     }
//
//     // 空文件也当作存在而不是删除
//     return false;
//   }
//
//   // 不存在或非文件
//   return true;
// }

String genSyncProgressText(String act, int allCount, int currentAt, String extraInfo) {
  String text = act;

  if(allCount > 0) {
    // 总数已知
    text += ", $currentAt/$allCount";
  }else if(currentAt > 0) {
    // 总数未知，只显示正在处理第几个条目
    text += ", $currentAt";
  }

  if(extraInfo.isNotEmpty) {
    text += ", $extraInfo";
  }

  return text;
}

// sync 函数专用的hash函数，可能使用rust或ffi以提高性能
Future<String> hashFileToHexWithKeyDataForSync({
  required String filePath,
  required KeyData contentKeyData,
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  // dart
  return bytesToHex(await hashFileWithKeyData(contentKeyData, File(filePath), throwIfInterrupted: throwIfInterrupted));

  // rust (跨语言调用有性能开销，可以打包多个任务，减少调用) 
  // （若在isolate中调用，需确保isolate执行了 `await RustLib.init()` ）
  // return await rustComputeSha256(path: filePath, contentPadding: contentKeyData.contentPadding);
}

Future<String> hashBytesToHexWithKeyDataForSync({
  required List<int> bytes,
  required KeyData contentKeyData,
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  return bytesToHex(await hashBytesWithKeyData(contentKeyData, bytes, throwIfInterrupted: throwIfInterrupted));
}

abstract class MergeMode {
  // 因为 Local 可能指本地 FilesMap ，所以这里用 Workdir 明确指本地工作目录
  static const int mergeRemoteAndWorkdir = 1;  // 默认值
  static const int remoteOverwriteWorkdir = 2; // 已实现，托管git remote时有用
  // static const int workdirOverwriteRemote = 3;  // 未实现，这个模式似乎没用，就算是托管git remote，也不能用这个模式，会导致踢皮球，相当于双方都在强制推送，谁都不合并谁的代码。。。

  // 关联函数 mergeModeToLocalizedText()，要改连关联函数一起改
  static String toText(int mergeMode) {
    if(mergeMode == MergeMode.mergeRemoteAndWorkdir) {
      return "Merge Remote and Workdir";
    }

    if(mergeMode == MergeMode.remoteOverwriteWorkdir) {
      return "Remote Overwrite Workdir";
    }

    return "Unknown";
  }
}
