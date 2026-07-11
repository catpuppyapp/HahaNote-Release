import 'package:json_annotation/json_annotation.dart';

/// `explicitToJson: true` 的作用: 
/// 生成的toJson函数会显式调用嵌套字段的toJson，避免转换失败。
/// 若设为false则在实例包含其他对象时，即使对象实现了toJson函数，
/// 调用 instance.fromJson(instance.toJson) 也会报错，
/// 因为生成的代码里不会显式调用对象的toJson
const myJsonSerializable = JsonSerializable(explicitToJson: true);
