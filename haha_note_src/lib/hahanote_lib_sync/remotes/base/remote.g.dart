// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SyncTask _$SyncTaskFromJson(Map<String, dynamic> json) => SyncTask(
  type: json['type'] as String? ?? '',
  state: json['state'] as String?,
  data: json['data'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$SyncTaskToJson(SyncTask instance) => <String, dynamic>{
  'type': instance.type,
  'state': instance.state,
  'data': instance.data,
};

SyncTaskDataRenameBatch _$SyncTaskDataRenameBatchFromJson(
  Map<String, dynamic> json,
) => SyncTaskDataRenameBatch(
  items: (json['items'] as List<dynamic>?)
      ?.map((e) => FilePathPair.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SyncTaskDataRenameBatchToJson(
  SyncTaskDataRenameBatch instance,
) => <String, dynamic>{'items': instance.items.map((e) => e.toJson()).toList()};

SyncCacheInfo _$SyncCacheInfoFromJson(Map<String, dynamic> json) =>
    SyncCacheInfo(
      ver: (json['ver'] as num?)?.toInt() ?? 1,
      tasks: (json['tasks'] as List<dynamic>?)
          ?.map((e) => SyncTask.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$SyncCacheInfoToJson(SyncCacheInfo instance) =>
    <String, dynamic>{
      'ver': instance.ver,
      'tasks': instance.tasks.map((e) => e.toJson()).toList(),
    };
