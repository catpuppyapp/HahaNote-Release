// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'data_map.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DataMap _$DataMapFromJson(Map<String, dynamic> json) => DataMap(
  contentId: json['contentId'] as String?,
  remoteDataType: json['remoteDataType'] as String? ?? "",
  data: (json['data'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as Map<String, dynamic>),
  ),
);

Map<String, dynamic> _$DataMapToJson(DataMap instance) => <String, dynamic>{
  'contentId': instance.contentId,
  'remoteDataType': instance.remoteDataType,
  'data': instance.data,
};
