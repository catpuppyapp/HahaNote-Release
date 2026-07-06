import 'package:hahanote_app/hahanote_lib_sync/client/client.dart' show Client;
import 'package:hahanote_app/hahanote_lib_sync/serialization/json.dart';
import 'package:hahanote_app/hahanote_lib_sync/time/time_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show randomString, mapEquals;

part 'version.g.dart';

@myJsonSerializable
class VersionNode {
  // 等于zero，代表删除了，具体是目录还是文件需要查看上一版本来判断；
  // 等于dir，代表是目录；
  // 否则就是文件。
  VersionOid oid;
  VersionTag tag;
  TimeData createTime;
  int fileSizeInBytes;
  // 创建节点的客户端名，可能是随便起的，只是用来标识下
  Client client;
  String note;
  Map<String, dynamic> extra;


  VersionNode({VersionOid? oid, VersionTag? tag, TimeData? createTime, this.fileSizeInBytes = 0, Client? client, this.note = "", Map<String, dynamic>? extra})
    : oid = oid ?? VersionOid(),
      tag = tag ?? VersionTag.normal,
      createTime = createTime ?? TimeData.now(),
      client = client ?? Client(),
      extra = extra ?? {}
  ;

  factory VersionNode.fromJson(Map<String, dynamic> json) => _$VersionNodeFromJson(json);

  Map<String, dynamic> toJson() => _$VersionNodeToJson(this);


  // bool isFile() {
  //   return oid != VersionOid.dir;
  // }
  //
  // bool isDir() {
  //   return oid == VersionOid.dir;
  // }

  bool isDeleted() {
    return oid == VersionOid.deleted;
  }

  @override
  String toString() {
    return 'VersionNode{oid: $oid, tag: $tag, createTime: $createTime, fileSizeInBytes: $fileSizeInBytes, client: $client, note: $note, extra: $extra}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is VersionNode && runtimeType == other.runtimeType &&
              oid == other.oid && tag == other.tag &&
              createTime == other.createTime &&
              fileSizeInBytes == other.fileSizeInBytes &&
              client == other.client && note == other.note && mapEquals(extra, other.extra);

  @override
  int get hashCode => Object.hash(oid, tag, createTime, fileSizeInBytes, client, note, extra);


}

@myJsonSerializable
class VersionOid {
  final String value;

  const VersionOid({this.value = ''});

  static VersionOid of(String value) {
    return VersionOid(value: value);
  }

  // 特殊oid，用来代表文件已不存在。

  // x 废弃：如果一个文件没提交过，版本历史应该为空，否则为其第一版的hash，不需要这个条目
  // 初次提交，文件的上一版本就会是这个
  // 注意：空文件不会是这个id，
  // 空文件由于有padding，所以hash实际不会为空，
  // 并且不同仓库的padding是不一样的，
  // 所以用来代表空文件的hash也是不一样的，
  // 但空文件和有内容的文件处理起来一样，无需特殊处理。
  // static final init = VersionOid(value: "Init");

  // 代表文件被删除
  // 被删除的文件的版本历史至少有两条记录，因为一个文件必须先存在，才能被删除
  // 如果清理仓库，则直接把对应文件条目删掉，这时其版本历史为空
  // 按照规范，oid都应该用纯小写的，因为需要用oid创建文件或目录但有些系统不区分大小写
  // 但是这个我写的时候忘了，而且实际上Deleted也不会在系统创建，所以没影响，就是看着难受
  static const deleted = VersionOid(value: "Deleted");

  // 实际已经废弃，放弃同步空目录了
  // // 特殊oid，用来代表路径是个目录。
  // // 会出现这个id的场景：
  // 1 之前是文件，后来改成目录，
  // 2 是个空目录
  // @Deprecated("不同步目录了！")
  // static const dir = VersionOid(value: "Dir");

  // 由于所有的设备都用同一个仓库锁，所以这个名字设为常量
  // 非仓库锁，会生成随机oid存在在远程仓库的locks目录，例如：locks/oid/data.enc
  static const repoLock = VersionOid(value: "repoLock");

  // 特殊oid，代表工作目录的文件
  // 注：这些特殊oid应该短点，小于等于shortOid的限制长度（默认10），不然调用shortOid时会被截断
  static const specialOidValueWorkdir = "workdir";
  static const workdir = VersionOid(value: specialOidValueWorkdir);

  factory VersionOid.fromJson(Map<String, dynamic> json) => _$VersionOidFromJson(json);

  Map<String, dynamic> toJson() => _$VersionOidToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VersionOid &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;


  @override
  String toString() {
    return value;
  }

  static VersionOid randomOid() {
    return VersionOid(value: randomString(64));
  }

  // 返回一个10位的value
  String shortValue() {
    return short(value);
  }

  static String short(String value, {final int length = 10}) {
    if(value.length > length) {
      return value.substring(0, length);
    }

    return value;
  }
}

@myJsonSerializable
class VersionTag {
  // 这个类型当初该用int，通过toString()显示对应字符串
  String value = '';

  VersionTag({this.value = ''});

  //普通的版本更新
  static final normal = VersionTag(value: "1");
  // 本地和远程版本存在冲突，本地的版本覆盖了远程的版本（被覆盖的远程版本可在冲突中心找到）
  static final conflictOverwrite = VersionTag(value: "2");

  // 在冲突中心解决了冲突，并提交了新版本
  // （若文件和上一版本没区别，则fileInfo不会添加新节点，
  // 仅会将冲突通知标记为已解决）
  static final conflictResolved = VersionTag(value: "3");
  // 同路径，文件变成了文件夹
  static final typeChanged = VersionTag(value: "4");


  factory VersionTag.fromJson(Map<String, dynamic> json) => _$VersionTagFromJson(json);

  Map<String, dynamic> toJson() => _$VersionTagToJson(this);


  @override
  String toString() {
    if(value == normal.value) {
      return "Normal";
    }

    if(value == conflictOverwrite.value) {
      return "ConflictOverwrite";
    }

    if(value == conflictResolved.value) {
      return "ConflictResolved";
    }

    if(value == typeChanged.value) {
      return "TypeChanged";
    }

    // 其他类型，直接返回值，可能是旧版的带描述性的字符串，或者是用户自定义的描述文本之类的（并没允许用户自定义，不过当初设计的时候有这个考虑）
    return value;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VersionTag &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}
