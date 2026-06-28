// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'repo_entity.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RepoEntity _$RepoEntityFromJson(Map<String, dynamic> json) => RepoEntity(
  id: json['id'] as String? ?? '',
  name: json['name'] as String?,
  path: json['path'] as String? ?? '',
  lastUpdate: json['lastUpdate'] == null
      ? null
      : TimeData.fromJson(json['lastUpdate'] as Map<String, dynamic>),
  recentFiles: (json['recentFiles'] as List<dynamic>?)
      ?.map((e) => FilePos.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$RepoEntityToJson(RepoEntity instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'path': instance.path,
      'lastUpdate': instance.lastUpdate.toJson(),
      'recentFiles': instance.recentFiles.map((e) => e.toJson()).toList(),
    };

FilePos _$FilePosFromJson(Map<String, dynamic> json) => FilePos(
  path: json['path'] as String? ?? '',
  index: (json['index'] as num?)?.toInt() ?? 0,
  offset: (json['offset'] as num?)?.toInt() ?? 0,
  extIndex: (json['extIndex'] as num?)?.toInt() ?? 0,
  extOffset: (json['extOffset'] as num?)?.toInt() ?? 0,
  lastTouchedAt: (json['lastTouchedAt'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$FilePosToJson(FilePos instance) => <String, dynamic>{
  'path': instance.path,
  'lastTouchedAt': instance.lastTouchedAt,
  'index': instance.index,
  'offset': instance.offset,
  'extIndex': instance.extIndex,
  'extOffset': instance.extOffset,
};
