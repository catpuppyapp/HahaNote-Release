// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Config _$ConfigFromJson(Map<String, dynamic> json) => Config(
  ver: (json['ver'] as num?)?.toInt() ?? 1,
  repoName: json['repoName'] as String? ?? '',
  remoteConfig: json['remoteConfig'] == null
      ? null
      : RemoteConfig.fromJson(json['remoteConfig'] as Map<String, dynamic>),
  client: json['client'] == null
      ? null
      : Client.fromJson(json['client'] as Map<String, dynamic>),
  mergeMode:
      (json['mergeMode'] as num?)?.toInt() ?? MergeMode.mergeRemoteAndWorkdir,
  packFileMaxLenInBytes: (json['packFileMaxLenInBytes'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$ConfigToJson(Config instance) => <String, dynamic>{
  'ver': instance.ver,
  'repoName': instance.repoName,
  'remoteConfig': instance.remoteConfig.toJson(),
  'client': instance.client.toJson(),
  'mergeMode': instance.mergeMode,
  'packFileMaxLenInBytes': instance.packFileMaxLenInBytes,
};

RemoteConfig _$RemoteConfigFromJson(Map<String, dynamic> json) => RemoteConfig(
  type: json['type'] as String? ?? '',
  basePath: json['basePath'] as String? ?? '',
  data: json['data'] as Map<String, dynamic>?,
);

Map<String, dynamic> _$RemoteConfigToJson(RemoteConfig instance) =>
    <String, dynamic>{
      'type': instance.type,
      'basePath': instance.basePath,
      'data': instance.data,
    };

RemoteConfigDataForWebdav _$RemoteConfigDataForWebdavFromJson(
  Map<String, dynamic> json,
) => RemoteConfigDataForWebdav(
  host: json['host'] as String? ?? '',
  user: json['user'] as String? ?? '',
  password: json['password'] as String? ?? '',
  timeoutInMs:
      (json['timeoutInMs'] as num?)?.toInt() ?? remoteConnectTimeoutInMs,
  debugMode: json['debugMode'] as bool? ?? false,
);

Map<String, dynamic> _$RemoteConfigDataForWebdavToJson(
  RemoteConfigDataForWebdav instance,
) => <String, dynamic>{
  'host': instance.host,
  'user': instance.user,
  'password': instance.password,
  'timeoutInMs': instance.timeoutInMs,
  'debugMode': instance.debugMode,
};

RemoteConfigDataForLocalDir _$RemoteConfigDataForLocalDirFromJson(
  Map<String, dynamic> json,
) => RemoteConfigDataForLocalDir(
  isGitBackend: json['isGitBackend'] as bool? ?? false,
  gitPullUrl: json['gitPullUrl'] as String? ?? '',
  gitPushUrl: json['gitPushUrl'] as String? ?? '',
  gitSyncUrl: json['gitSyncUrl'] as String? ?? '',
  gitPath: json['gitPath'] as String? ?? '',
);

Map<String, dynamic> _$RemoteConfigDataForLocalDirToJson(
  RemoteConfigDataForLocalDir instance,
) => <String, dynamic>{
  'isGitBackend': instance.isGitBackend,
  'gitPullUrl': instance.gitPullUrl,
  'gitPushUrl': instance.gitPushUrl,
  'gitSyncUrl': instance.gitSyncUrl,
  'gitPath': instance.gitPath,
};

RemoteConfigDataForDropbox _$RemoteConfigDataForDropboxFromJson(
  Map<String, dynamic> json,
) => RemoteConfigDataForDropbox(
  accessToken: json['accessToken'] as String? ?? '',
  refreshToken: json['refreshToken'] as String? ?? '',
  accountId: json['accountId'] as String? ?? '',
  uid: json['uid'] as String? ?? '',
  expiresIn: (json['expiresIn'] as num?)?.toInt() ?? 0,
  tokenType: json['tokenType'] as String? ?? '',
  username: json['username'] as String? ?? '',
  avatar: json['avatar'] as String? ?? '',
);

Map<String, dynamic> _$RemoteConfigDataForDropboxToJson(
  RemoteConfigDataForDropbox instance,
) => <String, dynamic>{
  'accessToken': instance.accessToken,
  'refreshToken': instance.refreshToken,
  'accountId': instance.accountId,
  'uid': instance.uid,
  'expiresIn': instance.expiresIn,
  'tokenType': instance.tokenType,
  'username': instance.username,
  'avatar': instance.avatar,
};
