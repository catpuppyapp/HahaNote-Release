// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SyncResultForHistoryNode _$SyncResultForHistoryNodeFromJson(
  Map<String, dynamic> json,
) => SyncResultForHistoryNode(
  updatedCount: (json['updatedCount'] as num?)?.toInt() ?? 0,
  updated: (json['updated'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  pushedCount: (json['pushedCount'] as num?)?.toInt() ?? 0,
  pushed: (json['pushed'] as List<dynamic>?)
      ?.map((e) => PushedItem.fromJson(e as Map<String, dynamic>))
      .toList(),
  deletedCount: (json['deletedCount'] as num?)?.toInt() ?? 0,
  deleted: (json['deleted'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
  conflictsCount: (json['conflictsCount'] as num?)?.toInt() ?? 0,
  conflicts: (json['conflicts'] as List<dynamic>?)
      ?.map((e) => ConflictItem.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SyncResultForHistoryNodeToJson(
  SyncResultForHistoryNode instance,
) => <String, dynamic>{
  'updatedCount': instance.updatedCount,
  'updated': instance.updated,
  'pushedCount': instance.pushedCount,
  'pushed': instance.pushed.map((e) => e.toJson()).toList(),
  'deletedCount': instance.deletedCount,
  'deleted': instance.deleted,
  'conflictsCount': instance.conflictsCount,
  'conflicts': instance.conflicts.map((e) => e.toJson()).toList(),
};

ConflictItem _$ConflictItemFromJson(Map<String, dynamic> json) => ConflictItem(
  path: json['path'] as String? ?? '',
  conflictId: json['conflictId'] as String? ?? '',
);

Map<String, dynamic> _$ConflictItemToJson(ConflictItem instance) =>
    <String, dynamic>{'path': instance.path, 'conflictId': instance.conflictId};

PushedItem _$PushedItemFromJson(Map<String, dynamic> json) => PushedItem(
  path: json['path'] as String? ?? '',
  objOid: json['objOid'] as String? ?? '',
);

Map<String, dynamic> _$PushedItemToJson(PushedItem instance) =>
    <String, dynamic>{'path': instance.path, 'objOid': instance.objOid};

UpdatedItem _$UpdatedItemFromJson(Map<String, dynamic> json) => UpdatedItem(
  path: json['path'] as String? ?? '',
  oldOid: json['oldOid'] as String? ?? '',
  newOid: json['newOid'] as String? ?? '',
);

Map<String, dynamic> _$UpdatedItemToJson(UpdatedItem instance) =>
    <String, dynamic>{
      'path': instance.path,
      'oldOid': instance.oldOid,
      'newOid': instance.newOid,
    };

DeletedItem _$DeletedItemFromJson(Map<String, dynamic> json) => DeletedItem(
  path: json['path'] as String? ?? '',
  oldOid: json['oldOid'] as String? ?? '',
);

Map<String, dynamic> _$DeletedItemToJson(DeletedItem instance) =>
    <String, dynamic>{'path': instance.path, 'oldOid': instance.oldOid};

FailedItem _$FailedItemFromJson(Map<String, dynamic> json) => FailedItem(
  path: json['path'] as String? ?? '',
  errMsg: json['errMsg'] as String? ?? '',
);

Map<String, dynamic> _$FailedItemToJson(FailedItem instance) =>
    <String, dynamic>{'path': instance.path, 'errMsg': instance.errMsg};

WorkdirFiles _$WorkdirFilesFromJson(Map<String, dynamic> json) => WorkdirFiles(
  items: (json['items'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, WorkdirFileItem.fromJson(e as Map<String, dynamic>)),
  ),
);

Map<String, dynamic> _$WorkdirFilesToJson(WorkdirFiles instance) =>
    <String, dynamic>{
      'items': instance.items.map((k, e) => MapEntry(k, e.toJson())),
    };

WorkdirFileItem _$WorkdirFileItemFromJson(Map<String, dynamic> json) =>
    WorkdirFileItem(
      expectMTimeMs: (json['expectMTimeMs'] as num?)?.toInt() ?? 0,
      expectFileLen: (json['expectFileLen'] as num?)?.toInt() ?? 0,
      expectFileOid: json['expectFileOid'] as String? ?? '',
    );

Map<String, dynamic> _$WorkdirFileItemToJson(WorkdirFileItem instance) =>
    <String, dynamic>{
      'expectMTimeMs': instance.expectMTimeMs,
      'expectFileLen': instance.expectFileLen,
      'expectFileOid': instance.expectFileOid,
    };

SyncInfo _$SyncInfoFromJson(Map<String, dynamic> json) => SyncInfo(
  state: (json['state'] as num?)?.toInt(),
  msg: json['msg'] as String? ?? '',
  time: json['time'] == null
      ? null
      : TimeData.fromJson(json['time'] as Map<String, dynamic>),
  syncedFilesCount: (json['syncedFilesCount'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$SyncInfoToJson(SyncInfo instance) => <String, dynamic>{
  'state': instance.state,
  'msg': instance.msg,
  'time': instance.time.toJson(),
  'syncedFilesCount': instance.syncedFilesCount,
};

JsonStrSet _$JsonStrSetFromJson(Map<String, dynamic> json) => JsonStrSet(
  storage: (json['storage'] as List<dynamic>?)?.map((e) => e as String).toSet(),
);

Map<String, dynamic> _$JsonStrSetToJson(JsonStrSet instance) =>
    <String, dynamic>{'storage': instance.storage.toList()};
