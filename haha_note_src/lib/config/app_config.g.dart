// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppConfig _$AppConfigFromJson(Map<String, dynamic> json) => AppConfig(
  syncConfig: json['syncConfig'] == null
      ? null
      : SyncConfig.fromJson(json['syncConfig'] as Map<String, dynamic>),
  textEditorPackageNameOnAndroid:
      json['textEditorPackageNameOnAndroid'] as String? ?? "",
  textEditorPackageNameOnPc: json['textEditorPackageNameOnPc'] as String? ?? "",
  language: json['language'] as String? ?? "",
  showLineNumInDiffView: json['showLineNumInDiffView'] as bool? ?? false,
  isFirstUse: json['isFirstUse'] as bool? ?? true,
  neverShowLineNumIncorrectNoteInDiffView:
      json['neverShowLineNumIncorrectNoteInDiffView'] as bool? ?? true,
  neverShowBlankLinesMayBeIgnoredInDiffView:
      json['neverShowBlankLinesMayBeIgnoredInDiffView'] as bool? ?? true,
  showRepoDataDirInFiles: json['showRepoDataDirInFiles'] as bool? ?? false,
  editorPreviewEnabled: json['editorPreviewEnabled'] as bool? ?? false,
  editorSoftWrapEnabled: json['editorSoftWrapEnabled'] as bool? ?? false,
  editorLineNumEnabled: json['editorLineNumEnabled'] as bool? ?? false,
  windowWidth: (json['windowWidth'] as num?)?.toDouble() ?? 1280,
  windowHeight: (json['windowHeight'] as num?)?.toDouble() ?? 720,
  displayMode: (json['displayMode'] as num?)?.toInt() ?? DisplayMode.auto,
);

Map<String, dynamic> _$AppConfigToJson(AppConfig instance) => <String, dynamic>{
  'syncConfig': instance.syncConfig.toJson(),
  'textEditorPackageNameOnAndroid': instance.textEditorPackageNameOnAndroid,
  'textEditorPackageNameOnPc': instance.textEditorPackageNameOnPc,
  'language': instance.language,
  'showLineNumInDiffView': instance.showLineNumInDiffView,
  'isFirstUse': instance.isFirstUse,
  'neverShowLineNumIncorrectNoteInDiffView':
      instance.neverShowLineNumIncorrectNoteInDiffView,
  'neverShowBlankLinesMayBeIgnoredInDiffView':
      instance.neverShowBlankLinesMayBeIgnoredInDiffView,
  'showRepoDataDirInFiles': instance.showRepoDataDirInFiles,
  'editorPreviewEnabled': instance.editorPreviewEnabled,
  'editorSoftWrapEnabled': instance.editorSoftWrapEnabled,
  'editorLineNumEnabled': instance.editorLineNumEnabled,
  'windowWidth': instance.windowWidth,
  'windowHeight': instance.windowHeight,
  'displayMode': instance.displayMode,
};
