
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart' show myJsonSerializable;
import 'package:cloud_disk_note_app/cloud_disk_note/time/time_data.dart' show TimeData;
import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart' show randomString;

part 'client.g.dart';


/// 用户可以在客户端app生成一个名字，用来标识设备，
/// 默认随机生成或者获取设备名称（例如手机型号，电脑名）
///
/// 这个可以全局共用一个，也可每个仓库都单独生成，无所谓，主要用来区分是谁在执行操作，
/// 目前是每个仓库各生成各的，在本地配置文件，不同步到远程，日后可支持修改某些数据，例如设备名，
/// 这个东西的作用只是在某些时候，例如获取锁失败的时候，让用户知道是哪个设备在执行操作，
/// 用户自己的仓库，自己看了应该知道是哪个设备占用了锁
/// 若不加 explicitToJson: true，则 instance.fromJson(instance.toJson) 有可能因为嵌套非直接能转换成json的类型而失败，例如这个类里的timeData，就会转换失败
@myJsonSerializable
class Client {
  // 随机生成，不可修改
  String id;

  // name可供用户修改，但需限制长度并且只允许英语字符以避免字符串过长浪费空间和编码问题
  // 字母或数字，长度最多20位，
  // 作用是用来标识文件或仓库的某个版本是哪个客户端上传的
  String name;

  TimeData createTime;

  static String genClientName() {
    // 长度应小于 clientNameMaxLen
    return randomString(8, prefix: "client_");
  }

  static String genId() {
    return randomString(32);
  }

  static int clientNameMaxLen() {
    return 16;
  }

  Client({String? id, String? name, TimeData? createTime})
  : name = name ?? genClientName(),
    id = id ?? genId(),
    createTime = createTime ?? TimeData.now();


  factory Client.fromJson(Map<String, dynamic> json) => _$ClientFromJson(json);

  Map<String, dynamic> toJson() => _$ClientToJson(this);

  @override
  String toString() {
    return 'Client{id: $id, name: $name, createTime: $createTime}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Client &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          createTime == other.createTime;

  @override
  int get hashCode => Object.hash(id, name, createTime);
}
