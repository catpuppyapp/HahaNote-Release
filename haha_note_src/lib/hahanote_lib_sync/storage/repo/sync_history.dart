import 'dart:convert' show jsonEncode, utf8, jsonDecode;
import 'dart:io' show File;

import 'package:hahanote_app/hahanote_lib_sync/client/client.dart' show Client;
import 'package:hahanote_app/hahanote_lib_sync/crypto/encrypt.dart' show EncryptedData;
import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/json.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/stream.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';
import 'package:hahanote_app/hahanote_lib_sync/time/time_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show getJsonStrFromByteStream;

part 'sync_history.g.dart';

// 单个节点最多记录推送或更新了多少个条目，超过此限制则会执行全量同步
const maxRecordItems = 60;
// 最多记录多少个历史节点
const maxRecordNodes = 30;

@myJsonSerializable
class SyncHistory implements JsonByteStream {
  // 这个是文件序列化版本，并非仓库更新历史版本history
  int version;

  // 递增，例如，有时候同步历史在更新期间中断，没finished，
  // 或者某次上传大量文件，不如直接需要全量同步，
  // 这时，可以只拉取比当前版本大的file info，来减少需要下载的文件数
  int syncVersion;

  // 拉取时，可通过对比history最新条目
  // 来快速判断仓库是否和远程一样，若一样，可跳过合并步骤
  List<SyncHistoryNode> history;

  SyncHistory({
    this.version = 1,
    this.syncVersion = 0,
    List<SyncHistoryNode>? history
  }):
    history = history ?? []
  ;

  factory SyncHistory.fromJson(Map<String, dynamic> json) => _$SyncHistoryFromJson(json);

  Map<String, dynamic> toJson() => _$SyncHistoryToJson(this);

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }


  static Future<SyncHistory> decrypt(KeyData contentKeyData, File file) async {
    final encryptedData = await EncryptedData.readFromFile(file);
    final rawData = await encryptedData.decryptThenUncompress(contentKeyData);

    return await fromJsonByteStream(rawData);
  }


  static Future<SyncHistory> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return SyncHistory.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  /// 如果return null, 需要全量同步；否则只同步集合内的元素，若空，则代表没推送东西，不需要同步远程条目，只需要检查workdir的文件修改（untracked和本地修改）
  Set<String>? findUpdatedFilesSince(SyncHistory? other) {
    if(other == null) {
      return null;
    }

    // 如果另一个版本没同步完成，返回null，需要全量同步
    final otherLatest = other.getLatestVersion();
    // 如果当前版本（remote最新版本）状态未完成，则无法确定修改了多少文件，需要全量同步
    final latest = getLatestVersion();

    if(otherLatest == null || latest == null) {
      return null;
    }

    // 若最新节点一样，即使两个节点type都是Clean，也没差异，所以返回空集合
    if(otherLatest.oid.value == latest.oid.value) {
      return {};
    }

    // 可能执行了clean等操作，返回null，执行全量同步，稳妥
    if(latest.type != HistoryNodeType.sync || otherLatest.type != HistoryNodeType.sync) {
      return null;
    }

    // 最新节点一样，且上次同步操作成功完成（finished or needFullSync都行），没有需要拉取的
    // 如果是started，说明上次操作没顺利完成，所以不能返回空集合，而是在下面返回null，然后全量同步
    if(otherLatest.state != HistoryNodeState.started && otherLatest == latest) {
      return {};
    }

    if(otherLatest.state != HistoryNodeState.finished) {
      return null;
    }

    if(latest.state != HistoryNodeState.finished) {
      return null;
    }

    final oid = otherLatest.oid;

    final filePaths = <String>{};
    var found = false;
    for(final h in history) {
      if(found) {
        // 中间节点可能执行过清理，返回null，全量同步
        if(h.type != HistoryNodeType.sync) {
          return null;
        }

        // 中间有同步未完成的节点（注：早期未使用syncCache机制前可能会有这个状态，
        // 现在其实应该不会有了，但还是保持这个代码，没必要删）
        if(h.state != HistoryNodeState.finished) {
          return null;
        }

        for(final pushedItem in h.result.pushed) {
          filePaths.add(pushedItem.path);
        }
      }else {
        if(h.oid == oid) {
          found = true;
        }
      }
    }

    // 远程同步历史若包含本地同步历史，则found为true，返回自从本地最新历史节点后所有推送的节点的集合；
    // 若远程同步历史不包含本地同步历史，found为false，则返回null执行全量同步；
    return found ? filePaths : null;
  }

  SyncHistoryNode? getLatestVersion() {
    return history.lastOrNull;
  }

  // 如果mark最新节点为finished了，返回true；如果回滚了，返回false；
  Future<bool> markLatestNodeToFinished(
    SyncResult syncResult, {
    int nodeType = HistoryNodeType.sync,

    // 用来删除node关联的files map
    required Future<void> Function(SyncHistoryNode) removedHistoryNodeHandler
  }) async {
    // 如果本次sync一个文件都没推送，并且当前syncNode的上个节点是正常完成，那么，删除当前节点（空节点）
    // 大于等于2，是因为同步前，有一个节点，然后创建一个节点，标记为started，同步完成后，将此节点再标记为finished或need full sync，
    // 所以，大于等于2就代表之前有一个节点。
    // 这里期望的是，如果之前有一个节点，并且当前没推送文件，就删除当前节点。
    // 一个都没推送的话，就没更新节点的必要，所以做这个判断。
    // nodeType为最新节点type，若为 sync，则说明本次操作是普通同步，可回滚；若不是sync，例如是clean，则不能回滚，必须记录一个节点（因为clean增删多少个文件不可控，应触发全量同步）
    if(nodeType == HistoryNodeType.sync && syncResult.result.pushedCount < 1 && history.length >= 2) {
      final lastLast = history[history.length - 2];
      // 若上上个节点state不是正常完成（finished）或type不是sync（例如可能是clean），
      // 那么需要当前节点标记为已完成来避免下次的全量同步，所以这时不能删除当前节点。
      // 这个判断严格些好，若不回滚，顶多多个空节点；若错误回滚，可能导致同步信息有误（全量同步可能能解决）
      if(lastLast.state == HistoryNodeState.finished && lastLast.type == HistoryNodeType.sync) {
        // 若上个节点是finished且当前节点没推送任何条目，则可删除当前节点
        history.removeAt(history.length - 1);
        return false;
      }
    }


    // 历史条目数过多，删除最旧的
    if(history.length > maxRecordNodes) {
      final removedNode = history.removeAt(0);
      await removedHistoryNodeHandler(removedNode);
    }


    // 更新当前节点（最后一个节点，最新节点）为已完成
    // 由于sync前必然会添加一个节点，sync结束才调用此方法，所以可断言lastVersion非null
    final last = getLatestVersion()!;
    last.result = syncResult.toResultForNode();
    if(last.result.pushedCount > maxRecordItems) {
      last.state = HistoryNodeState.finishedButHaveTooManyFiles;
    }else {
      last.state = HistoryNodeState.finished;
    }

    // node type为sync时传null；若是清理（删除msg或fileInfo），则传clean
    last.type = nodeType;

    return true;
  }

  void addNode(SyncHistoryNode node) {
    history.add(node);
  }

  @override
  String toString() {
    return 'version: $version, syncVersion: $syncVersion, history: $history';
  }

  @Deprecated("废弃了，不需要回滚了，若失败根本不会上传")
  void rollback(VersionOid expectOid) {
    final latestVer = getLatestVersion();
    if(latestVer != null && latestVer.oid == expectOid && HistoryNodeState.isUnfinished(latestVer.state)) {
      // 目前回滚就是删除最后一个节点，实际上也可保留，但标记为已回滚，感觉没意义，直接删了省事
      history.removeLast();
    }
  }

  SyncHistory copy() {
    return SyncHistory.fromJson(jsonDecode(jsonEncode(toJson())));
  }

  void rollbackLocalIfNeeded(SyncHistory remoteSyncHistory) {
    final localLatest = getLatestVersion();
    if(localLatest == null) {
      return;
    }

    // 若本地已经是finished系列状态，返回
    if(!HistoryNodeState.isUnfinished(localLatest.state)) {
      return;
    }

    // 执行到这，本地最新节点状态为未完成（started），下面找，如果在远程
    // 对应oid的节点不是未完成，说明之前同步完成了，但本地文件syncInfo代表完成的文件
    // 没创建就中断了，可能停电，或者创建文件出错，这时就可以回滚，撤销本地最新的一个节点，
    // 执行增量同步，不回滚也行，但会执行全量同步，性能可能差些。
    // （远程如果后来同步过很多节点，可能会把本地记录的这个清掉，
    // 这种情况想回滚也回滚不了，只能全量同步了）
    final remoteLatest = remoteSyncHistory.getLatestVersion();
    if(remoteLatest == null) {
      return;
    }

    // 如果远程包含本地节点，则回滚本地的最后一个提交
    // 若不包含（比如远程节点同步次数超过限制，移除了旧的节点），则不回滚
    for(final h in remoteSyncHistory.history) {
      // 本地最新节点在远程历史记录中，并且本地的状态和远程状态不同（本地是unfinished，
      // 若和远程不同，则远程是finished或finishedButHaveTooManyFiles，等代表完成的状态，
      // 这时，回滚本地最新节点（不过 20260203 由于改用了保证最终一致性的 类 原子提交，所以这个判断可能有些多余了，
      // 远程节点同步要么成功（非started），要么失败（保持旧节点），所以其实不需要回滚了，
      // 但先保留这些代码以免日后有用
      if(h.oid == localLatest.oid && h.state != localLatest.state) {
        history.removeLast();
      }
    }
  }

  void rollbackOnce() {
    if(history.isNotEmpty) {
      history.removeLast();
    }
  }


}

@myJsonSerializable
class SyncHistoryNode {
  int type;
  VersionOid oid;

  TimeData createTime;

  int syncVersion;
  Client client;
  int state;
  // 附加信息，比如超过了多少个文件，建议全量同步之类的
  String msg;
  // 推送了多少个文件，有时候推送的文件很多，列表不会全记，但这个数量是准确的
  // 用 file path，别用oid，path 转oid易，oid转path难
  // 当前节点，上传了多少个文件
  SyncResultForHistoryNode result;

  SyncHistoryNode({
    this.type = HistoryNodeType.sync,
    VersionOid? oid,
    TimeData? createTime,
    this.syncVersion = 0,
    Client? client,
    this.state = HistoryNodeState.started,
    this.msg = '',
    SyncResultForHistoryNode? result,
  })
    : oid = oid ?? VersionOid.randomOid(),
      result = result ?? SyncResultForHistoryNode(),
      createTime = createTime ?? TimeData.now(),
      client = client ?? Client()
  ;


  factory SyncHistoryNode.fromJson(Map<String, dynamic> json) => _$SyncHistoryNodeFromJson(json);

  Map<String, dynamic> toJson() => _$SyncHistoryNodeToJson(this);


  static Future<SyncHistoryNode> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return SyncHistoryNode.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  static Future<SyncHistoryNode> decrypt(KeyData contentKeyData, File file) async {
    final encryptedData = await EncryptedData.readFromFile(file);
    final rawData = await encryptedData.decryptThenUncompress(contentKeyData);

    return await fromJsonByteStream(rawData);
  }


  @override
  String toString() {
    return 'type: $type, oid: $oid, createTime: $createTime, syncVersion: $syncVersion, client: $client, state: $state, msg: $msg, result: $result';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is SyncHistoryNode && runtimeType == other.runtimeType &&
              type == other.type && oid == other.oid && createTime == other.createTime &&
              syncVersion == other.syncVersion && client == other.client &&
              state == other.state && msg == other.msg &&
              result == other.result;

  @override
  int get hashCode =>
      Object.hash(
          type,
          oid,
          createTime,
          syncVersion,
          client,
          state,
          msg,
          result);

  String stateString() {
    return HistoryNodeState.textOf(state);
  }

  String typeString() {
    return HistoryNodeType.textOf(type);
  }

  String resultString() {
    return result.toString();
    // if(type == HistoryNodeType.sync) {
    //   return result.toString();
    // }
    //
    // if(type == HistoryNodeType.clean) {
    //   return "Cleaned";
    // }
    //
    // return "Unknown";
  }

  String resultBrief() {
    return result.brief();
    // if(type == HistoryNodeType.sync) {
    //   return result.brief();
    // }
    //
    // if(type == HistoryNodeType.clean) {
    //   return "Cleaned";
    // }
    //
    // return "Unknown";
  }
}

abstract class HistoryNodeState {
  // 操作开始执行了，但没成功结束，比如执行到一半设备没电了，这种情况应该全量同步
  static const int started = 1;

  // 操作执行，顺利完毕，这种情况如果同步的文件数量不多，可以增量同步，否则还是要全量同步一次
  static const int finished = 2;
  // 这个其实同步成功完成了，就是文件数量多，更新列表没记全，
  // 并不代表出错，和started状态不太一样，那个是开始了，没完成然后中断了，才会停留在那个状态
  static const int finishedButHaveTooManyFiles = 3;

  // 废弃：直接使用type clean+是否完成来判断即可
  // 执行了清理，删除回收站条目，冲突msg，之类的
  // static int cleaned = 4;

  // 如果要记错误，从400开始

  static bool isUnfinished(int state) {
    return state == started;
  }

  static String textOf(int value) {
    if(value == started) {
      return "Started";
    }

    if(value == finished) {
      return "Finished";
    }

    if(value == finishedButHaveTooManyFiles) {
      return "Finished (too many files)";
    }

    return "Unknown";
  }
}

abstract class HistoryNodeType {
  // 普通同步
  static const int sync = 1;

  // 清理数据（以及同步）
  static const int clean = 2;

  static String textOf(int value) {
    if(value == sync) {
      return "Sync";
    }

    if(value == clean) {
      return "Clean";
    }

    return "Unknown";
  }
}
