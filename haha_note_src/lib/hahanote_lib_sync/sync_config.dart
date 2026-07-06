import 'dart:convert';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/json.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';

import 'log.dart';

part 'sync_config.g.dart';

const _TAG = "sync_config.dart";


// dropbox 单个上传请求限制大小
// dropbox 允许的单次上传最大是150MiB
// 开启会话上传，调用append，除最后一个携带close的请求外，其他必须是4194304(4MiB)的倍数
// const int _uploadMaxSizeInBytes = 4194304 * 8; // * 8 = 32MiB // debug，搞小点，好测试
// const int _uploadMaxSizeInBytes = 4194304 * 30; // * 30 = 120MiB // release，尽量大，避免上传请求太多，dropbox罢工
// const int dropboxUploadMaxSizeInBytes = 4194304 * 35; // * 35 = 146MiB // release，尽量大，避免上传请求太多，dropbox罢工

// 超过这个大小的话，不是不能上传，而是需要分段上传（dropbox的会话上传）
const _defaultDropboxSingleUploadMaxSizeInBytes = 4194304 * 35;  // 146MiB

// 多个小文件可能聚合到一个pack里，这个不能太大，
// 不然下载一个几kb的文件可能要下载上百兆的pack file，
// 成本太高（没办法，网盘是当无状态存储器用的，无法下载指定范围的文件，
// 就算能，大量下载发很多请求也很难绷）
// 注意：如果没下载频率限制并且延迟很低，封包大小应该改小点，改成1或2mb
// dropbox注意事项：dropbox会话上传的api，封包大小似乎必须是 4194304 的倍数，
//                但是！和这个参数并不冲突，只是上传时需要把文件按4194304倍数拆分而已，
//                由 _defaultDropboxSingleUploadMaxSizeInBytes 控制
// const defaultPackFileMaxLenInBytes = 4194304 * 8;  // 32 MiB
// const defaultPackFileMaxLenInBytes = 4194304 * 4;  // 16 MiB
// const defaultPackFileMaxLenInBytes = 4194304 * 2;  // 8 MiB
const defaultPackFileMaxLenInBytes = 4194304;  // 4 MiB

const defaultProxyPort = 1080;

SyncConfig? _config = null;


@myJsonSerializable
class SyncConfig {
  // * 35 = 146MiB // release，尽量大，避免上传请求太多，dropbox罢工
  int dropboxSingleUploadMaxSizeInBytes;
  // 合并小文件的封包最大限制，若超过会创建新的.pack文件，建议小于等于dropbox单次上传限制大小，这样的话，上传一个聚合了多个小文件的pack，只需一个请求
  // 注意：如果文件本身大小超过这个限制，会单独创建封包文件，并且不会按这个大小封包，而是直接原大小上传
  int packFileMaxLenInBytes;

  // zstd压缩等级，越高越慢，但不一定能显著减少文件大小
  // @Deprecated("改用zlib了")
  // int zstdLevel;

  // 加密，压缩时，默认压缩等级，zip的
  int compressLevel;

  String proxyHost;
  int proxyPort;
  String proxyUser;
  String proxyPassword;

  int logLevel;
  bool devModeOn;

  SyncConfig({
    this.dropboxSingleUploadMaxSizeInBytes = _defaultDropboxSingleUploadMaxSizeInBytes,
    // 这个不是pack file的限制大小，是整合小文件的pack file的文件大小，例如这个大小可以是32MiB，但你依然可上传80MiB的文件
    this.packFileMaxLenInBytes = defaultPackFileMaxLenInBytes,
    // this.zstdLevel = 3,
    this.compressLevel = 6,  // ZLibOption.defaultLevel 就是 6
    // http proxy settings
    this.proxyHost = "",
    this.proxyPort = defaultProxyPort,
    this.proxyUser = "",
    this.proxyPassword = "",
    this.logLevel = LogLevel.warn,
    this.devModeOn = false,
  });


  factory SyncConfig.fromJson(Map<String, dynamic> json) => _$SyncConfigFromJson(json);

  Map<String, dynamic> toJson() => _$SyncConfigToJson(this);


  // 这个只读，不要改，若改，使用update
  static SyncConfig getConfig() {
    return _config!;
  }

  static Future<void> setConfig(SyncConfig config, {required bool save}) async {
    _config = config;
  }

  /// 使用方法：
  /// await update((config) {
  ///   config.abc = 123;
  /// });
  /// // when await returned, settings will be updated
  static Future<void> update(Future<void> Function(SyncConfig) handler) async {
    final copied = _config?.copy();
    if(copied == null) {
      App.logger.debug(_TAG, "update sync config failed, config is null");
      throw AppException("sync config is null");
    }

    await handler(copied);
    await setConfig(copied, save: true);
  }

  SyncConfig copy() {
    return SyncConfig.fromJson(jsonDecode(jsonEncode(this)));
  }

  String getFormattedHttpProxyText() {
    if(isInvalidHostOrPort(proxyHost, proxyPort)) {
      return "";
    }

    return "$proxyHost:$proxyPort";
  }

  bool isHttpProxyEnabled() {
    return !isInvalidHostOrPort(proxyHost, proxyPort);
  }
}
