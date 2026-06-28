import 'dart:io' show Directory, HttpClient, HttpOverrides, SecurityContext, File, HttpClientBasicCredentials;

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/bundle_certs.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/http.dart';
import 'package:cloud_disk_note_app/util/fs.dart';
import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../utils.dart';

const _TAG = "my_http_overrides.dart";


class MyHttpOverrides extends HttpOverrides {
  static List<int> userCerts = [];

  String proxyHost = "";
  int proxyPort = 0;
  String proxyUser = "";
  String proxyPassword = "";

  // 这两个暂时不用，但保留
  String realm = ""; // idk what propose
  List<String> bypassHosts = const []; // e.g. ['localhost', '127.0.0.1', 'internal.local']


  static Future<void> init({String? certsDirPath}) async {
    await MyHttpOverrides.loadUserCerts(certsDirPath ?? await Fs.getUserTlsCertDirPath());
    _setGlobalHttpClient();
  }

  static void initForIsolate(List<int> userCertsFromMainIsolate) {
    userCerts = userCertsFromMainIsolate;
    _setGlobalHttpClient();
  }

  static void _setGlobalHttpClient() {
    final appConfig = AppConfig.getConfig();
    final myHttpOverride = MyHttpOverrides();
    myHttpOverride.proxyHost = appConfig.syncConfig.proxyHost;
    myHttpOverride.proxyPort = appConfig.syncConfig.proxyPort;
    myHttpOverride.proxyUser = appConfig.syncConfig.proxyUser;
    myHttpOverride.proxyPassword = appConfig.syncConfig.proxyPassword;

    // set global http override
    HttpOverrides.global = myHttpOverride;

    // create global http instance
    try {
      appHttpClient?.close();
    } catch (e, st) {
      App.logger.debug(_TAG, "close http client err: $e\n$st");
    }

    appHttpClient = http.Client();
  }

  static Future<void> loadUserCerts(String certsDirPath) async {
    final buffer = <int>[];

    try {
      await for(final fileEntity in Directory(certsDirPath).list(recursive: true, followLinks: false)) {
        try {
          if(fileEntity is! File) {
            continue;
          }

          buffer.addAll(await fileEntity.readAsBytes());
        }catch(_) {

        }
      }

    } catch (_) {}

    userCerts = buffer;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    SecurityContext sc = SecurityContext(withTrustedRoots: false);
    if(bundledCertsBytes.isNotEmpty) {
      sc.setTrustedCertificatesBytes(bundledCertsBytes);
    }

    try {
      // 加载用户证书

      // 警告：任一证书文件无效，都会导致tls不可用
      if(userCerts.isNotEmpty) {
        sc.setTrustedCertificatesBytes(userCerts);
      }

      // 来源：https://juejin.cn/post/7376526544615211045
      // 似乎可修复开了vpn的时候触发的：connection closed before full header was received 错误。
      // 但是，可能会增加中间人攻击等安全问题，所以算了，还是禁用吧。
      // 翻译：Renegotiation = re negotiation = 重协商
      // sc.allowLegacyUnsafeRenegotiation = true;

    }catch(e) {
      App.logger.debug(_TAG, "set user's tls certs for http client error, will use default http client without user certs: $e");
    }

    final client = super.createHttpClient(sc);

    try {
      setProxy(client);
    }catch(e) {
      App.logger.debug(_TAG, "http set proxy err: $e");
    }

    return client;
  }

  void setProxy(HttpClient client) {
    if(isInvalidHostOrPort(proxyHost, proxyPort)) {
      return;
    }

    client.findProxy = (Uri uri) {
      final host = uri.host;
      for (final pattern in bypassHosts) {
        // endsWith匹配域名，例如 host=www.baidu.com，patter=baidu.com，可匹配成功
        if (host == pattern || host.endsWith(pattern)) return "DIRECT";
      }

      return "PROXY $proxyHost:$proxyPort;";
    };

    // Optional: add proxy authentication for proxies requiring basic auth
    if (proxyUser.isNotEmpty || proxyPassword.isNotEmpty) {
      client.authenticateProxy = (String host, int port, String scheme, String? realm) async {
        client.addProxyCredentials(
          proxyHost,
          proxyPort,
          this.realm,
          HttpClientBasicCredentials(proxyUser, proxyPassword),
        );

        return true;
      };
    }
  }
}
