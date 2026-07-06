// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'msg.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Msg _$MsgFromJson(Map<String, dynamic> json) => Msg(
  type: json['type'] == null
      ? null
      : MsgType.fromJson(json['type'] as Map<String, dynamic>),
  title: json['title'] as String? ?? '',
  text: json['text'] as String? ?? '',
  oid: json['oid'] == null
      ? null
      : VersionOid.fromJson(json['oid'] as Map<String, dynamic>),
  createTime: json['createTime'] == null
      ? null
      : TimeData.fromJson(json['createTime'] as Map<String, dynamic>),
  checked: json['checked'] as bool? ?? false,
  resolved: json['resolved'] as bool? ?? false,
  remark: json['remark'] as String? ?? '',
  data: json['data'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$MsgToJson(Msg instance) => <String, dynamic>{
  'type': instance.type.toJson(),
  'title': instance.title,
  'text': instance.text,
  'oid': instance.oid.toJson(),
  'createTime': instance.createTime.toJson(),
  'checked': instance.checked,
  'resolved': instance.resolved,
  'remark': instance.remark,
  'data': instance.data,
};

MsgType _$MsgTypeFromJson(Map<String, dynamic> json) =>
    MsgType(value: (json['value'] as num).toInt());

Map<String, dynamic> _$MsgTypeToJson(MsgType instance) => <String, dynamic>{
  'value': instance.value,
};

MsgDataConflict _$MsgDataConflictFromJson(Map<String, dynamic> json) =>
    MsgDataConflict(
      path: json['path'] as String?,
      localOid: json['localOid'] == null
          ? null
          : VersionOid.fromJson(json['localOid'] as Map<String, dynamic>),
      workdirOid: json['workdirOid'] == null
          ? null
          : VersionOid.fromJson(json['workdirOid'] as Map<String, dynamic>),
      remoteOid: json['remoteOid'] == null
          ? null
          : VersionOid.fromJson(json['remoteOid'] as Map<String, dynamic>),
      resolveStrategy: (json['resolveStrategy'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$MsgDataConflictToJson(MsgDataConflict instance) =>
    <String, dynamic>{
      'path': instance.path,
      'localOid': instance.localOid?.toJson(),
      'workdirOid': instance.workdirOid?.toJson(),
      'remoteOid': instance.remoteOid?.toJson(),
      'resolveStrategy': instance.resolveStrategy,
    };
