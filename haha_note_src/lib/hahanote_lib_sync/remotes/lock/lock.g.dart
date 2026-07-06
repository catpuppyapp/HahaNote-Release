// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lock.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Lock _$LockFromJson(Map<String, dynamic> json) => Lock(
  oid: json['oid'] == null
      ? null
      : VersionOid.fromJson(json['oid'] as Map<String, dynamic>),
  type: json['type'] == null
      ? null
      : LockType.fromJson(json['type'] as Map<String, dynamic>),
  data: json['data'] as Map<String, dynamic>?,
  ownerOid: json['ownerOid'] == null
      ? null
      : VersionOid.fromJson(json['ownerOid'] as Map<String, dynamic>),
  client: Client.fromJson(json['client'] as Map<String, dynamic>),
  lockAt: json['lockAt'] == null
      ? null
      : TimeData.fromJson(json['lockAt'] as Map<String, dynamic>),
  createAt: json['createAt'] == null
      ? null
      : TimeData.fromJson(json['createAt'] as Map<String, dynamic>),
  expireAfterMilliseconds:
      (json['expireAfterMilliseconds'] as num?)?.toInt() ??
      defaultHoldTimeInMilliseconds,
  autoRenewal: json['autoRenewal'] as bool? ?? true,
  actName: json['actName'] as String? ?? '',
  actDesc: json['actDesc'] as String? ?? '',
);

Map<String, dynamic> _$LockToJson(Lock instance) => <String, dynamic>{
  'oid': instance.oid.toJson(),
  'type': instance.type.toJson(),
  'data': instance.data,
  'ownerOid': instance.ownerOid.toJson(),
  'autoRenewal': instance.autoRenewal,
  'client': instance.client.toJson(),
  'actName': instance.actName,
  'actDesc': instance.actDesc,
  'createAt': instance.createAt.toJson(),
  'lockAt': instance.lockAt.toJson(),
  'expireAfterMilliseconds': instance.expireAfterMilliseconds,
};

LockType _$LockTypeFromJson(Map<String, dynamic> json) =>
    LockType(value: (json['value'] as num?)?.toInt() ?? 0);

Map<String, dynamic> _$LockTypeToJson(LockType instance) => <String, dynamic>{
  'value': instance.value,
};
