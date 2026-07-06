import 'dart:convert' show utf8, jsonEncode, jsonDecode;
import 'dart:io' show File;

import 'package:hahanote_app/hahanote_lib_sync/crypto/encrypt.dart';
import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/json.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/map_key.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/oidlize.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/stream.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/related_oids.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';
import 'package:hahanote_app/hahanote_lib_sync/time/time_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';

part 'msg.g.dart';

@myJsonSerializable
class Msg implements JsonByteStream, RelatedOids, Oidlize {
  MsgType type;
  String title;
  String text;

  VersionOid oid;

  TimeData createTime;


  /// 消息是否已读（冲突消息和普通消息都有可能用此字段）
  bool checked;

  /// 消息是否被标记为已解决（冲突消息用此字段）
  bool resolved;

  /// 备注，用户可以给冲突消息添加备注，普通消息也可添加备注
  String remark;




  /// 具体类型取决于type，先判断type，再用fromJson转成具体类型
  Map<String, dynamic> data;


  Msg({
    MsgType? type,
    this.title = '',
    this.text = '',
    VersionOid? oid,
    TimeData? createTime,
    this.checked = false,
    this.resolved = false,
    this.remark = '',
    Map<String, dynamic>? data
  })
    : type = type ?? MsgType.normal,
      oid = oid ?? VersionOid.randomOid(),
      createTime = createTime ?? TimeData.now(),
      data = data ?? {}
  ;

  factory Msg.fromJson(Map<String, dynamic> json) => _$MsgFromJson(json);

  Map<String, dynamic> toJson() => _$MsgToJson(this);

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

  @override
  Future<String> toOidStr(KeyData contentKeyData) async {
    return oid.value;
  }

  static Future<Msg> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return Msg.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }


  static Future<Msg> decrypt(KeyData contentKeyData, File file) async {
    final encryptedData = await EncryptedData.readFromFile(file);
    final rawData = await encryptedData.decryptThenUncompress(contentKeyData);

    return await fromJsonByteStream(rawData);
  }


  @override
  Stream<VersionOid> allRelatedObjectsOids() async* {
    if(type == MsgType.conflict) {
      final obj = MsgDataConflict.fromJson(data);
      if(obj.localOid != null) {
        yield obj.localOid!;
      }

      if(obj.workdirOid != null) {
        yield obj.workdirOid!;
      }

      if(obj.remoteOid != null) {
        yield obj.remoteOid!;
      }

    }

    // else if(type == MsgType.remoteIsFileButWorkdirIsDir) {
    //   final obj = MsgDataRemoteIsFileButWorkdirIsDir.fromJson(data);
    //   if(obj.remotePulledLatestOid != null) {
    //     yield obj.remotePulledLatestOid!;
    //   }
    // }
  }

  @override
  Future<String> selfOidStr(KeyData contentKeyData) async {
    return await toOidStr(contentKeyData);
  }

  @override
  String toString() {
    return 'Msg{type: $type, title: $title, text: $text, oid: $oid, createTime: $createTime, data: $data}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Msg && runtimeType == other.runtimeType &&
              type == other.type && title == other.title && text == other.text && oid == other.oid &&
              createTime == other.createTime && mapEquals(data, other.data);

  @override
  int get hashCode => Object.hash(type, title, text, oid, createTime, data);



}

@myJsonSerializable
class MsgType {
  final int value;


  MsgType({required this.value});

  factory MsgType.fromJson(Map<String, dynamic> json) => _$MsgTypeFromJson(json);

  Map<String, dynamic> toJson() => _$MsgTypeToJson(this);

  static final normal = MsgType(value: 1);
  // 拉取时，workdir的文件和本地最新版本不匹配，也和远程最新版本不匹配，说明在拉取前发生了修改，即冲突
  static final conflict = MsgType(value: 2);
  // 拉取时，对应路径，在远程仓库是文件，但本地对应路径是目录
  static final remoteIsFileButWorkdirIsDir = MsgType(value: 3);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is MsgType && runtimeType == other.runtimeType &&
              value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    return "$value";
  }


}

@myJsonSerializable
class MsgDataConflict {
  // unix style 相对路径
  String? path;

  // 只有当3个oid不同时，才会是冲突

  // 本地pfs记录的最新oid
  VersionOid? localOid;
  // workdir的文件oid
  VersionOid? workdirOid;
  // 远程pfs记录的最新oid
  VersionOid? remoteOid;

  /// 发现冲突时，当时的处理策略，值是[ConflictResolveStrategy]之一
  int resolveStrategy;


  MsgDataConflict({
    this.path,
    this.localOid,
    this.workdirOid,
    this.remoteOid,
    // 0 是无效策略
    this.resolveStrategy = 0,
  });


  factory MsgDataConflict.fromJson(Map<String, dynamic> json) => _$MsgDataConflictFromJson(json);

  Map<String, dynamic> toJson() => _$MsgDataConflictToJson(this);


  @override
  String toString() {
    return 'MsgDataConflict{path: $path, localOid: $localOid, workdirOid: $workdirOid, remoteOid: $remoteOid, resolveStrategy: $resolveStrategy}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is MsgDataConflict && runtimeType == other.runtimeType &&
              path == other.path &&
              localOid == other.localOid &&
              workdirOid == other.workdirOid &&
              remoteOid == other.remoteOid &&
              resolveStrategy == other.resolveStrategy;

  @override
  int get hashCode =>
      Object.hash(path, localOid, workdirOid,
          remoteOid, resolveStrategy);


  // 同步时自动处理，接受的那个版本(不是用户手动选择的，用户手动选择的不会记)
  VersionOid? acceptedOid() {
    if(resolveStrategy == ConflictResolveStrategy.remoteOverwriteWorkdir.value) {
      return remoteOid;
    }else if(resolveStrategy == ConflictResolveStrategy.workdirOverwriteRemote.value) {
      return workdirOid;
    }else {
      return null;
    }
  }

  String resolveStrategyToText() {
    return ConflictResolveStrategy.valueToText(resolveStrategy);
  }
}

//冲突文件目标类型
abstract class MsgDataConflictTargetType {
  static final local = "local";
  static final workdir = "workdir";
  static final remote = "remote";
}

// @Deprecated('如果文件变成目录，直接当文件已删除，不算冲突了')
// @myJsonSerializable
// class MsgDataRemoteIsFileButWorkdirIsDir {
//   FilePath? path;
//
//   VersionOid? remotePulledLatestOid;
//
//
//   MsgDataRemoteIsFileButWorkdirIsDir({
//     this.path,
//     this.remotePulledLatestOid,
//   });
//
//
//   factory MsgDataRemoteIsFileButWorkdirIsDir.fromJson(Map<String, dynamic> json) => _$MsgDataRemoteIsFileButWorkdirIsDirFromJson(json);
//
//   Map<String, dynamic> toJson() => _$MsgDataRemoteIsFileButWorkdirIsDirToJson(this);
//
//   @override
//   String toString() {
//     return 'MsgDataRemoteIsFileButWorkdirIsDir{path: $path, remotePulledLatestOid: $remotePulledLatestOid}';
//   }
//
//   @override
//   bool operator ==(Object other) =>
//       identical(this, other) ||
//           other is MsgDataRemoteIsFileButWorkdirIsDir &&
//               runtimeType == other.runtimeType &&
//               path == other.path &&
//               remotePulledLatestOid == other.remotePulledLatestOid;
//
//   @override
//   int get hashCode => Object.hash(path, remotePulledLatestOid);
//
//
// }
