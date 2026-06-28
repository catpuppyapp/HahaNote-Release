// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SyncConfig _$SyncConfigFromJson(Map<String, dynamic> json) => SyncConfig(
  dropboxSingleUploadMaxSizeInBytes:
      (json['dropboxSingleUploadMaxSizeInBytes'] as num?)?.toInt() ??
      _defaultDropboxSingleUploadMaxSizeInBytes,
  packFileMaxLenInBytes:
      (json['packFileMaxLenInBytes'] as num?)?.toInt() ??
      defaultPackFileMaxLenInBytes,
  compressLevel: (json['compressLevel'] as num?)?.toInt() ?? 6,
  proxyHost: json['proxyHost'] as String? ?? "",
  proxyPort: (json['proxyPort'] as num?)?.toInt() ?? defaultProxyPort,
  proxyUser: json['proxyUser'] as String? ?? "",
  proxyPassword: json['proxyPassword'] as String? ?? "",
  logLevel: (json['logLevel'] as num?)?.toInt() ?? LogLevel.warn,
  devModeOn: json['devModeOn'] as bool? ?? false,
);

Map<String, dynamic> _$SyncConfigToJson(SyncConfig instance) =>
    <String, dynamic>{
      'dropboxSingleUploadMaxSizeInBytes':
          instance.dropboxSingleUploadMaxSizeInBytes,
      'packFileMaxLenInBytes': instance.packFileMaxLenInBytes,
      'compressLevel': instance.compressLevel,
      'proxyHost': instance.proxyHost,
      'proxyPort': instance.proxyPort,
      'proxyUser': instance.proxyUser,
      'proxyPassword': instance.proxyPassword,
      'logLevel': instance.logLevel,
      'devModeOn': instance.devModeOn,
    };
