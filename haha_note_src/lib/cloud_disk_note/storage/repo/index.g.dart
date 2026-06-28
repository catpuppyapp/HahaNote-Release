// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'index.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Index _$IndexFromJson(Map<String, dynamic> json) => Index(
  version: (json['version'] as num?)?.toInt() ?? 1,
  contentId: json['contentId'] as String?,
  items: (json['items'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, IndexItem.fromJson(e as Map<String, dynamic>)),
  ),
);

Map<String, dynamic> _$IndexToJson(Index instance) => <String, dynamic>{
  'version': instance.version,
  'contentId': instance.contentId,
  'items': instance.items.map((k, e) => MapEntry(k, e.toJson())),
};

IndexItem _$IndexItemFromJson(Map<String, dynamic> json) => IndexItem(
  mTimeMs: (json['mTimeMs'] as num?)?.toInt() ?? 0,
  isDir: json['isDir'] as bool? ?? false,
  len: (json['len'] as num?)?.toInt() ?? 0,
  oid: json['oid'] as String? ?? '',
);

Map<String, dynamic> _$IndexItemToJson(IndexItem instance) => <String, dynamic>{
  'mTimeMs': instance.mTimeMs,
  'isDir': instance.isDir,
  'len': instance.len,
  'oid': instance.oid,
};
