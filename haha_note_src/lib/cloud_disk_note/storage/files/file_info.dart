import 'dart:convert';
import 'dart:io' show File;

import 'package:cloud_disk_note_app/cloud_disk_note/crypto/encrypt.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart' show myJsonSerializable;
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/oidlize.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/stream.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_path.dart' show FilePath;
import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/related_oids.dart' show RelatedOids;
import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart';

import '../../crypto/key_data.dart' show KeyData;
import '../../utils.dart' show listEquals, getJsonStrFromByteStream;

part 'file_info.g.dart';

// 这个值至少2，不然存储的时候，新节点顶替旧节点，会出现历史版本为1，且oid是“Deleted”，会报错
const _maxFileInfoHistoryCount = 30;

@myJsonSerializable
class FileInfo implements JsonByteStream, RelatedOids, Oidlize {

  // 存的是在workdir下的相对路径
  // unix style
  String path;

  // 只记录文件历史，
  // 不记录 dir 改变成 文件 或者 文件已删除的历史，
  // 那种属于特殊情况，用type来判断
  // 只要files目录存在对应条目，这个列表就不可能为空，必然有条目
  // 列表正序排列，向后追加最新条目，因为这样的话，如果底层list是数组，
  // 比较方便，若往头添加，有可能需要完全创建个新数组
  // 至少两个元素：zero，和file或者dir。
  List<VersionNode> history = [];

  VersionNode getLatestVersion() {
    return curNode();
  }

  // bool isDeletedFile() {
  //   final latestVer = getLatestVersion();
  //   // 对于已删除条目来说，至少有2条记录，因此-2是安全的
  //   return latestVer.isDeleted() && history[history.length - 2].isFile();
  // }
  //
  // bool isDeletedDir() {
  //   final latestVer = getLatestVersion();
  //   return latestVer.isDeleted() && history[history.length - 2].isDir();
  // }

  bool isDeleted() {
    final latestVer = getLatestVersion();
    return latestVer.isDeleted();
  }

  FileInfo({this.path = '', List<VersionNode>? history})
      : history = history ?? [];

  factory FileInfo.fromJson(Map<String, dynamic> json) => _$FileInfoFromJson(json);

  Map<String, dynamic> toJson() => _$FileInfoToJson(this);

  static Future<FileInfo> decrypt(KeyData contentKeyData, File file) async {
    final encryptedData = await EncryptedData.readFromFile(file);
    final rawData = await encryptedData.decryptThenUncompress(contentKeyData);

    return await fromJsonByteStream(rawData);
  }

  static Future<FileInfo> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return FileInfo.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  FilePath pathToFilePath() {
    return FilePath.fromString(path, isRelative: true);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is FileInfo && runtimeType == other.runtimeType &&
              path == other.path && listEquals(history, other.history);

  @override
  int get hashCode => Object.hash(path, history);

  @override
  Future<String> toOidStr(KeyData contentKeyData) async {
    return pathToFilePath().toOidStr(contentKeyData);
  }

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

  void addNode(
    VersionNode node, {
    // 这个listener是用来在删除节点后移除其关联的obj的
    required Future<void> Function(VersionNode deletedNode, FileInfo)? removedOverLimitedNodeHandler
  }) {
    if(history.isEmpty && node.oid == VersionOid.deleted) {
      throw AppException("trying add a 'Deleted' node to a new FileInfo");
    }

    if(history.isNotEmpty) {
      final cur = curNode();
      if(cur.oid == node.oid) {
        throw AppException("previous node oid same with new, oid=${node.oid}");
      }
    }

    history.add(node);

    // 版本过多，移除第一个
    if(history.length > _maxFileInfoHistoryCount) {
      removedOverLimitedNodeHandler?.call(history.removeAt(0), this);
    }
  }

  VersionNode curNode() {
    // 如果一个文件的versions列表为空，就没存在的必要，因此-1就安全的
    return history[history.length - 1];
  }

  // 比如最后的节点是删除，可快速调用这个来获取上个节点恢复文件
  VersionNode? lastNode() {
    if(history.length > 1) {
      return history[history.length - 2];
    }

    return null;
  }

  @override
  Stream<VersionOid> allRelatedObjectsOids() async* {
    for(final h in history) {
      yield h.oid;
    }
  }

  @override
  Future<String> selfOidStr(KeyData contentKeyData) async {
    return await toOidStr(contentKeyData);
  }

  @override
  String toString() {
    return 'FileInfo{path: $path, history: $history}';
  }

  static Future<VersionOid> pathToOid(String path, KeyData contentKeyData) async {
    return await FilePath.fromString(path).toOid(contentKeyData);
  }


}
