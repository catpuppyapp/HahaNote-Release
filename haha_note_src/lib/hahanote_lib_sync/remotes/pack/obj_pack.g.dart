// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'obj_pack.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ObjPackFileStorage _$ObjPackFileStorageFromJson(Map<String, dynamic> json) =>
    ObjPackFileStorage(
      ver: (json['ver'] as num?)?.toInt() ?? 1,
      type: json['type'] as String?,
      packFiles: (json['packFiles'] as List<dynamic>?)
          ?.map((e) => ObjPackFile.fromJson(e as Map<String, dynamic>))
          .toList(),
      contentId: json['contentId'] as String?,
    );

Map<String, dynamic> _$ObjPackFileStorageToJson(ObjPackFileStorage instance) =>
    <String, dynamic>{
      'ver': instance.ver,
      'type': instance.type,
      'packFiles': instance.packFiles.map((e) => e.toJson()).toList(),
      'contentId': instance.contentId,
    };

ObjPackFile _$ObjPackFileFromJson(Map<String, dynamic> json) => ObjPackFile(
  ver: (json['ver'] as num?)?.toInt() ?? 1,
  name: json['name'] as String? ?? '',
  len: (json['len'] as num?)?.toInt() ?? 0,
  hash: json['hash'] as String? ?? '',
  items: (json['items'] as List<dynamic>?)
      ?.map((e) => ObjPackItem.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$ObjPackFileToJson(ObjPackFile instance) =>
    <String, dynamic>{
      'ver': instance.ver,
      'name': instance.name,
      'len': instance.len,
      'hash': instance.hash,
      'items': instance.items.map((e) => e.toJson()).toList(),
    };

ObjPackItem _$ObjPackItemFromJson(Map<String, dynamic> json) => ObjPackItem(
  ver: (json['ver'] as num?)?.toInt() ?? 1,
  oid: json['oid'] as String? ?? '',
  type: json['type'] as String? ?? '',
  offset: (json['offset'] as num?)?.toInt() ?? 0,
  len: (json['len'] as num?)?.toInt() ?? 0,
  rc: (json['rc'] as num?)?.toInt() ?? 0,
  ctime: json['ctime'] == null
      ? null
      : TimeData.fromJson(json['ctime'] as Map<String, dynamic>),
  extra: json['extra'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$ObjPackItemToJson(ObjPackItem instance) =>
    <String, dynamic>{
      'ver': instance.ver,
      'oid': instance.oid,
      'type': instance.type,
      'offset': instance.offset,
      'len': instance.len,
      'ctime': instance.ctime.toJson(),
      'rc': instance.rc,
      'extra': instance.extra,
    };

ObjRef _$ObjRefFromJson(Map<String, dynamic> json) => ObjRef(
  type: (json['type'] as num?)?.toInt() ?? 0,
  oid: json['oid'] as String? ?? '',
  path: json['path'] as String? ?? '',
  extra: json['extra'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$ObjRefToJson(ObjRef instance) => <String, dynamic>{
  'type': instance.type,
  'oid': instance.oid,
  'path': instance.path,
  'extra': instance.extra,
};
