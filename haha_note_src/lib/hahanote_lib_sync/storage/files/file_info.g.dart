// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FileInfo _$FileInfoFromJson(Map<String, dynamic> json) => FileInfo(
  path: json['path'] as String? ?? '',
  history: (json['history'] as List<dynamic>?)
      ?.map((e) => VersionNode.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$FileInfoToJson(FileInfo instance) => <String, dynamic>{
  'path': instance.path,
  'history': instance.history.map((e) => e.toJson()).toList(),
};
