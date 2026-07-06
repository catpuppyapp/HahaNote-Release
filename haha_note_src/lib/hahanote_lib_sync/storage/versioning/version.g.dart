// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'version.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

VersionNode _$VersionNodeFromJson(Map<String, dynamic> json) => VersionNode(
  oid: json['oid'] == null
      ? null
      : VersionOid.fromJson(json['oid'] as Map<String, dynamic>),
  tag: json['tag'] == null
      ? null
      : VersionTag.fromJson(json['tag'] as Map<String, dynamic>),
  createTime: json['createTime'] == null
      ? null
      : TimeData.fromJson(json['createTime'] as Map<String, dynamic>),
  fileSizeInBytes: (json['fileSizeInBytes'] as num?)?.toInt() ?? 0,
  client: json['client'] == null
      ? null
      : Client.fromJson(json['client'] as Map<String, dynamic>),
  note: json['note'] as String? ?? "",
  extra: json['extra'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$VersionNodeToJson(VersionNode instance) =>
    <String, dynamic>{
      'oid': instance.oid.toJson(),
      'tag': instance.tag.toJson(),
      'createTime': instance.createTime.toJson(),
      'fileSizeInBytes': instance.fileSizeInBytes,
      'client': instance.client.toJson(),
      'note': instance.note,
      'extra': instance.extra,
    };

VersionOid _$VersionOidFromJson(Map<String, dynamic> json) =>
    VersionOid(value: json['value'] as String? ?? '');

Map<String, dynamic> _$VersionOidToJson(VersionOid instance) =>
    <String, dynamic>{'value': instance.value};

VersionTag _$VersionTagFromJson(Map<String, dynamic> json) =>
    VersionTag(value: json['value'] as String? ?? '');

Map<String, dynamic> _$VersionTagToJson(VersionTag instance) =>
    <String, dynamic>{'value': instance.value};
