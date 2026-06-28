// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_path.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FilePathPair _$FilePathPairFromJson(Map<String, dynamic> json) => FilePathPair(
  left: json['left'] == null
      ? null
      : FilePath.fromJson(json['left'] as Map<String, dynamic>),
  right: json['right'] == null
      ? null
      : FilePath.fromJson(json['right'] as Map<String, dynamic>),
  isDir: json['isDir'] as bool? ?? false,
  extra: json['extra'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$FilePathPairToJson(FilePathPair instance) =>
    <String, dynamic>{
      'left': instance.left.toJson(),
      'right': instance.right.toJson(),
      'isDir': instance.isDir,
      'extra': instance.extra,
    };

FilePath _$FilePathFromJson(Map<String, dynamic> json) => FilePath(
  value: (json['value'] as List<dynamic>?)?.map((e) => e as String).toList(),
  isRelative: json['isRelative'] as bool? ?? false,
);

Map<String, dynamic> _$FilePathToJson(FilePath instance) => <String, dynamic>{
  'value': instance.value,
  'isRelative': instance.isRelative,
};
