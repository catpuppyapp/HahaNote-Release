// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SyncHistory _$SyncHistoryFromJson(Map<String, dynamic> json) => SyncHistory(
  version: (json['version'] as num?)?.toInt() ?? 1,
  syncVersion: (json['syncVersion'] as num?)?.toInt() ?? 0,
  history: (json['history'] as List<dynamic>?)
      ?.map((e) => SyncHistoryNode.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$SyncHistoryToJson(SyncHistory instance) =>
    <String, dynamic>{
      'version': instance.version,
      'syncVersion': instance.syncVersion,
      'history': instance.history.map((e) => e.toJson()).toList(),
    };

SyncHistoryNode _$SyncHistoryNodeFromJson(Map<String, dynamic> json) =>
    SyncHistoryNode(
      type: (json['type'] as num?)?.toInt() ?? HistoryNodeType.sync,
      oid: json['oid'] == null
          ? null
          : VersionOid.fromJson(json['oid'] as Map<String, dynamic>),
      createTime: json['createTime'] == null
          ? null
          : TimeData.fromJson(json['createTime'] as Map<String, dynamic>),
      syncVersion: (json['syncVersion'] as num?)?.toInt() ?? 0,
      client: json['client'] == null
          ? null
          : Client.fromJson(json['client'] as Map<String, dynamic>),
      state: (json['state'] as num?)?.toInt() ?? HistoryNodeState.started,
      msg: json['msg'] as String? ?? '',
      result: json['result'] == null
          ? null
          : SyncResultForHistoryNode.fromJson(
              json['result'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$SyncHistoryNodeToJson(SyncHistoryNode instance) =>
    <String, dynamic>{
      'type': instance.type,
      'oid': instance.oid.toJson(),
      'createTime': instance.createTime.toJson(),
      'syncVersion': instance.syncVersion,
      'client': instance.client.toJson(),
      'state': instance.state,
      'msg': instance.msg,
      'result': instance.result.toJson(),
    };
