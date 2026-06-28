import 'dart:convert' show jsonEncode, utf8, jsonDecode;
import 'dart:io' show File;

import 'package:cloud_disk_note_app/cloud_disk_note/crypto/encrypt.dart' show EncryptedData;
import 'package:cloud_disk_note_app/cloud_disk_note/crypto/key_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/stream.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/time/time_data.dart';

import '../../utils.dart' show getJsonStrFromByteStream;

part 'repo_info.g.dart';

@myJsonSerializable
class RepoInfo implements JsonByteStream {
  // 用id来判断仓库是否匹配
  // 这个相当于repoId，全局唯一
  String id;

  // 这个是文件序列化版本，并非仓库更新历史版本history
  // 这个指的是RepoInfo这个class是否有增删字段导致序列化时不兼容（类字段变化导致解析json失败），
  // 但其实这个字段没用，
  // 因为如果不兼容，要么直接解析失败，要么剩余字段使用默认值，根本没法根据版本采用不同的解析方式，除非手动读取jsonmap然后做判断，但那样有些麻烦
  // 或者不同version可携带不同的Map存自定义数据，依靠这个来正常解析，但这个类也没携带附加数据，
  // 所以这个字段对这个类来说其实没什么用
  int version;
  // 仓库格式版本，类似数据库存储引擎、网络通信协议版本，之类的
  // 这个指的是仓库存储的数据格式是否有变化，或者文件存放路径是否有变化，
  // 比如之前使用分离的filesinfo，后来整合到files.map，就属于仓库格式变化
  // 如果格式变动，应保证向后兼容（新版兼容旧版），不用保证向前兼容（旧版兼容新版）
  int repoFormatVersion;
  TimeData createTime;
  TimeData updateTime;

  // 这个和本地Config的仓库名在创建时可能一样，但这个不允许修改，因为同步起来有点麻烦，
  // 本地Config里的repoName仅供用户本地分辨仓库，可修改，不会同步
  // 这个字段其实没什么意义，用户要查找某个仓库的话，直接列出远程的目录给他看就行，
  // 也用不上这个字段，所以这个字段理论上可删，不过暂时先保留吧
  String repoName;

  // 拉取时，可通过对比history最新条目
  // 来快速判断仓库是否和远程一样，若一样，可跳过合并步骤

  // 绑定用户的userid，避免用户注册新用户同步同一仓库，无限试用，白嫖
  String userId;

  RepoInfo({
    this.id = '',
    this.version = 1,
    this.repoFormatVersion = 1,
    this.repoName = '',
    this.userId = '',
    TimeData? createTime,
    TimeData? updateTime,
  }):createTime = createTime ?? TimeData.now(),
     updateTime = updateTime ?? TimeData.now();

  factory RepoInfo.fromJson(Map<String, dynamic> json) => _$RepoInfoFromJson(json);

  Map<String, dynamic> toJson() => _$RepoInfoToJson(this);

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

  static Future<RepoInfo> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return RepoInfo.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  static Future<RepoInfo> decrypt(KeyData contentKeyData, File file) async {
    final encryptedData = await EncryptedData.readFromFile(file);
    final rawData = await encryptedData.decryptThenUncompress(contentKeyData);

    return await fromJsonByteStream(rawData);
  }

}
