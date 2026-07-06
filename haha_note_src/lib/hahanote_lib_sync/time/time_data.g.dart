// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'time_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TimeData _$TimeDataFromJson(Map<String, dynamic> json) => TimeData(
  utcMs: (json['utcMs'] as num?)?.toInt() ?? 0,
  offsetM: (json['offsetM'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$TimeDataToJson(TimeData instance) => <String, dynamic>{
  'utcMs': instance.utcMs,
  'offsetM': instance.offsetM,
};
