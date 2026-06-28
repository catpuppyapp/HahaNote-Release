// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'repo.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocalSyncCacheInfo _$LocalSyncCacheInfoFromJson(Map<String, dynamic> json) =>
    LocalSyncCacheInfo(
      mergeMode:
          (json['mergeMode'] as num?)?.toInt() ??
          MergeMode.mergeRemoteAndWorkdir,
    );

Map<String, dynamic> _$LocalSyncCacheInfoToJson(LocalSyncCacheInfo instance) =>
    <String, dynamic>{'mergeMode': instance.mergeMode};
