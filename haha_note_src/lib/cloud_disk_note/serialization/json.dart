import 'package:json_annotation/json_annotation.dart';

/// 若不加 explicitToJson: true，则 instance.fromJson(instance.toJson)
/// 有可能因为嵌套非直接能转换成json的类型而失败，例如TimeData类，就会转换失败
const myJsonSerializable = JsonSerializable(explicitToJson: true);
