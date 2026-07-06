// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Client _$ClientFromJson(Map<String, dynamic> json) => Client(
  id: json['id'] as String?,
  name: json['name'] as String?,
  createTime: json['createTime'] == null
      ? null
      : TimeData.fromJson(json['createTime'] as Map<String, dynamic>),
);

Map<String, dynamic> _$ClientToJson(Client instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'createTime': instance.createTime.toJson(),
};
