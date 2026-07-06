import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show HttpResponse;

import 'package:hahanote_app/hahanote_lib_sync/app.dart' show App;
import 'package:hahanote_app/hahanote_lib_sync/crypto/hash.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/http.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';

import '../../../native_util/task_man.dart';

const _TAG = 'dropbox_oauth2.dart';

const _caller = 'dropbox_oauth2';

class AuthData {
  Uri uri;
  String verifier;
  String challenge;
  String state;

  AuthData({required this.uri, this.verifier = '', this.challenge = '', this.state = ''});
}

String _rnd(int n) {
  return randomString(n);
}

Future<String> _genChallenge(String str) async {
  return base64Url.encode(await hashStr(str, throwIfInterrupted: null)).replaceAll('=', '');
}

abstract class DropboxOauth2 {
  // 用PKCE 授权流程，不需要appsecret，直接在本地起个服务器，然后随机生成的一次性的授权码，完成验证就行了
  // dropbox称此字段为appKey
  static final clientId = "l1lvivv1cxvce2f";

  // http://127.0.0.1:37859/oauth2/cb
  static final host = '127.0.0.1';
  static final port = 37859;
  static final redirect = '/oauth2/cb';
  static final redirectUri = 'http://$host:$port$redirect';

  // 接收code的地址
  static final oauthDomain = 'www.dropbox.com';
  static final oauthUrlPath = '/oauth2/authorize';

  static Future<AuthData> genAuthData({
    // dropbox 关于此参数的描述: Up to 2000 bytes of arbitrary data that will be passed back to your redirect URI.
    // This parameter should be used to protect against cross-site request forgery (CSRF).
    // See Sections 4.4.1.8 and 4.4.2.5 of the OAuth 2.0 threat model spec.
    // 这个是会回传给 [redirectUri] 的数据，作用：
    // 1. 相当于nonce，可防止黑客伪造授权，确保这个授权是你这次发起的，生成后，先存下，接收code后验证此值再丢弃，可为此值设置有效期
    // 2. 可用来携带用户id，这样你自己的后端服务器收code时，知道这个code是和哪个用户关联的
    //
    // 注：我这不需要'作用2'，因为我的实现是本地启动个服务器，完全本地接收，并不需要后端服务器参与，
    // 也不需要区分是哪个用户在接收code，就算需要，我的app客户端也可以自己判断，因为登录后客户端肯定持有客户id。
    String stateData = '',
  }) async {
    final verifier = _rnd(64);
    final challenge = await _genChallenge(verifier);

    // dropbox 附加数据有长度限制，不要超过2000字节
    // 取附带数据：[DropboxOauth2.getStateData(state)]
    final state = '${_rnd(16)}:$stateData';

    final authUri = Uri.https(oauthDomain, oauthUrlPath, {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state':state,
      'token_access_type': 'offline',
    });

    return AuthData(uri: authUri, verifier: verifier, challenge: challenge, state: state);
  }

  static String getStateData(String state) {
    final indexOfSplit = state.indexOf(':');
    // 若没 stateData ，则index+1等于字符串长度，但不会越界，而是会返回空字符串
    return state.substring(indexOfSplit+1);
  }

  static Future<HttpServer> startServer() async {
    await TaskMan.startForegroundService();
    // 启动服务器
    return await HttpServer.bind(host, port);
  }

  static Future<RemoteConfigDataForDropbox?> authorize({
    required HttpServer server,
    // 之所以做参数是因为这样更灵活，调用者可自己决定是
    // 提供复制按钮让用户自己手动复制打开还是自动在浏览器打开
    required Future<void> Function(AuthData) openAuthLink,
    required final AuthData authData
  }) async {

    await openAuthLink(authData);

    // 等待响应
    try {
      await for (var req in server) {
        if (req.uri.path == redirect) {
          final q = req.uri.queryParameters;

          req.response.headers.contentType = ContentType.html;
          req.response.statusCode = 200;

          if (q['state'] != authData.state) {
            await _writeOneLineHtmlThenClose(req.response, 'bad state');
            break;
          }

          final code = q['code'];
          if (code == null || code.isEmpty) {
            await _writeOneLineHtmlThenClose(req.response, 'no code');
            break;
          }

          await _writeOneLineHtmlThenClose(req.response, 'Done. Please back to App.');

          final resMap = await _exchange(code, authData.verifier);
          // App.logger.debug(_TAG, "token response map: $resMap");

          return await RemoteConfigDataForDropbox.parseFromResponseMap(resMap);
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }

        // 接收一次就下线
        break;
      }

      return null;
    } finally {
      await server.close();
    }
  }

  static Future<Map<String, dynamic>> _exchange(
    String code,
    String verifier,
  ) async {
    final uri = Uri.https('api.dropboxapi.com', '/oauth2/token');
    // 这里直接从响应就能拿到token了，并不需要redirect_uri，只是用来验证，
    // 看是否和请求code时携带的redirect_uri匹配，
    // 而请求code时，
    // 会验证redirect_uri是否和开发者在平台绑定的回调地址匹配（可绑定多个），
    // 若匹配，才会调用回调
    final response = await HttpUtil.sendRequest(
      _caller,
      method: HttpMethod.post,
      uri: uri,
      header: await HttpUtil.newHeader(contentType: HttpContentType.form),
      parseResponseToJsonMap: true,
      bodyFields: {
        'code': code,
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code_verifier': verifier
      }
    );

    return response.responseMap!;
  }

  static Future<void> refreshToken(RemoteConfigDataForDropbox config) async {
    App.logger.info(_TAG, "refreshToken: refreshing token");

    // curl https://api.dropbox.com/oauth2/token \
    // -d grant_type=refresh_token \
    // -d refresh_token=<REFRESH_TOKEN> \
    // -d client_id=<APP_KEY>
    if(config.refreshToken.isEmpty) {
      throw RemoteException("refresh token is empty, can't get new access token");
    }

    // 这个是PKCE授权返回的refresh token，不需要app secret
    // curl https://api.dropbox.com/oauth2/token \
    // -d grant_type=refresh_token \
    // -d refresh_token=<REFRESH_TOKEN> \
    // -d client_id=<APP_KEY>
    final uri = Uri.parse("https://api.dropbox.com/oauth2/token");
    final header = await HttpUtil.newHeader(contentType: HttpContentType.form);

    final httpResponse = await HttpUtil.sendRequest(
      _caller,
      method: HttpMethod.post,
      uri: uri,
      header: header,
      bodyFields: {
        "grant_type": "refresh_token",
        "refresh_token": config.refreshToken,
        "client_id": clientId
      },
      parseResponseToJsonMap: true,
    );

    final String? newAccessToken = httpResponse.responseMap!["access_token"];
    if(newAccessToken == null || newAccessToken.isEmpty) {
      throw RemoteException("refresh token failed, maybe need re-authorize.");
    }

    // {
    //   "access_token": "sl.u.AbX9y6Fe3AuH5o66-gmJpR032jwAwQPIVVzWXZNkdzcYT02akC2de219dZi6gxYPVnYPrpvISRSf9lxKWJzYLjtMPH-d9fo_0gXex7X37VIvpty4-G8f4-WX45AcEPfRnJJDwzv-",
    //   "expires_in": 14400,
    //   "token_type": "bearer"
    // }
    config.accessToken = newAccessToken;
    config.expiresIn = httpResponse.responseMap!["expires_in"];
    config.tokenType = httpResponse.responseMap!["token_type"];

    App.logger.info(_TAG, "refreshToken: refresh token finished");
  }

  static Future<void> _writeOneLineHtmlThenClose(io.HttpResponse response, String content) async {
    response.write('<html lang="en"><body><div style="margin:300px auto;max-width:800px;text-align:center;"><h1 style="font-size:5rem;margin:0;color:#09C859;">$content</h1></div></body></html>');
    await response.close();
  }
}
