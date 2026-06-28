// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sort_dialog.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SortBy _$SortByFromJson(Map<String, dynamic> json) =>
    SortBy(value: json['value'] as String? ?? _sortByName);

Map<String, dynamic> _$SortByToJson(SortBy instance) => <String, dynamic>{
  'value': instance.value,
};

SortRule _$SortRuleFromJson(Map<String, dynamic> json) => SortRule(
  sortBy: json['sortBy'] == null
      ? null
      : SortBy.fromJson(json['sortBy'] as Map<String, dynamic>),
  ascending: json['ascending'] as bool? ?? true,
  foldersFirst: json['foldersFirst'] as bool? ?? true,
  applyToThisFolderOnly: json['applyToThisFolderOnly'] as bool? ?? false,
);

Map<String, dynamic> _$SortRuleToJson(SortRule instance) => <String, dynamic>{
  'sortBy': instance.sortBy.toJson(),
  'ascending': instance.ascending,
  'foldersFirst': instance.foldersFirst,
  'applyToThisFolderOnly': instance.applyToThisFolderOnly,
};
