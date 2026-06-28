// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'repo_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RepoInfo _$RepoInfoFromJson(Map<String, dynamic> json) => RepoInfo(
  id: json['id'] as String? ?? '',
  version: (json['version'] as num?)?.toInt() ?? 1,
  repoFormatVersion: (json['repoFormatVersion'] as num?)?.toInt() ?? 1,
  repoName: json['repoName'] as String? ?? '',
  userId: json['userId'] as String? ?? '',
  createTime: json['createTime'] == null
      ? null
      : TimeData.fromJson(json['createTime'] as Map<String, dynamic>),
  updateTime: json['updateTime'] == null
      ? null
      : TimeData.fromJson(json['updateTime'] as Map<String, dynamic>),
);

Map<String, dynamic> _$RepoInfoToJson(RepoInfo instance) => <String, dynamic>{
  'id': instance.id,
  'version': instance.version,
  'repoFormatVersion': instance.repoFormatVersion,
  'createTime': instance.createTime.toJson(),
  'updateTime': instance.updateTime.toJson(),
  'repoName': instance.repoName,
  'userId': instance.userId,
};
