import 'dart:convert' show jsonDecode;
import 'dart:typed_data' show Uint8List;

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart' show RemoteException, RemoteNotFoundException;
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/remote.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/sync.dart' show ThrowIfInterrupted;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../util/app_info.dart';


const _TAG = "http.dart";

// for dropbox
const myRetryAfterKey = "myRetryAfterKey";

// 同一个实例即可，可复用连接，避免每次都创建新tcp连接，3次握手浪费时间
http.Client? appHttpClient;

typedef TokenGetter = Future<String> Function();

/// [count] 上传或下载了多少， [total]总共多少
typedef RemoteProgressCb = void Function(int count, int? total)?;


// 相关：dropbox、webdav_client、request(连接haha note server的那里)
// 代码：dropbox和request使用的都是HttpUtil.sendRequest()，统一改下就行（就在当前页面）
//      webdav使用的是dio，需要单独改下
Map<String, String> getAppRequestHeader() {
  return {
    // app发出的请求一律使用此UA
    // 为什么设置UA: 因为infini-cloud.net(原teracloud.jp)，可能使用ua来帮开发者排查问题
    // dart默认UA是什么：dart 版本号，例如：'Dart/3.9 (dart:io)'，(注：不带引号，这里用引号只是为了指明范围，因为UA里有空格，不指可能混淆)
    // 示例：HahaNote/1.0.0
    "User-Agent": "HahaNote/${AppInfo.version}",
  };
}


abstract class HttpMethod {
  static final String get = "GET";
  static final String post = "POST";
}

class HttpContentType {
  static final String binary = "application/octet-stream";
  static final String json = "application/json";
  static final String form = "application/x-www-form-urlencoded";
}

class HttpResponse {
  http.StreamedResponse response;
  // void Function() close;
  Map<String, dynamic>? responseMap;

  HttpResponse(
    this.response, {
    // required this.close,
    Map<String, dynamic>? responseMap
  });
}

abstract class HttpUtil {
  static Future<HttpResponse> sendPuppyGitHttpRequest({
    // 告知是谁在调用，若是Remote调用，传Remote.type即可
    required String caller,
    required String actName,
    required String url,
  }) async {
    final httpResponse = await HttpUtil.sendRequest(
      caller,
      method: HttpMethod.get,
      uri: Uri.parse(url),
      header: {},
      parseResponseToJsonMap: true
    );

    final res = httpResponse.responseMap;
    if(res?["code"] != 0) {
      throw "$actName err: ${res?["msg"]}";
    }

    return httpResponse;
  }

  static Future<HttpResponse> sendRequest(
    // 用来在错误信息标识是谁调用的
    String caller, {
    ThrowIfInterrupted? throwIfInterrupted,
    required String method,
    required Uri uri,
    required Map<String, String> header,
    required bool parseResponseToJsonMap,
    // dropbox append api成功返回null，失败返回json，所以如果不允许null response，解析json就报错了
    bool allowEmptyResponse = true,
    //body只能有一个，下面几个最终其实都会转换为字节传输

    // 若json，可编码为json字符串，再传body
    String? body,

    // 这个一般用来传二进制数据，但实际上什么都能传，
    // 比如json，可编码后传字节，不过一般没必要自己编码，自己编码还得手动添加charset header，麻烦，
    // 不如传字符串，让库处理
    Uint8List? bodyBytes,

    // 这个只有在用 x-www-form-urlencoded 时才能用，json不行
    Map<String, String>? bodyFields,

    // 状态码非200，若此参数为 false ，遵从[parseResponseToJsonMap]决定是否解析json；若 true ，抛异常
    bool throwIfStatusCodeNotOk = true,
    Future<void> Function(http.StreamedResponse)? responseHandler,
  }) async {
    header.addAll(getAppRequestHeader());

    int retryAfterInSec = -1;

    Future<HttpResponse> send() async {
      retryAfterInSec = -1;

      final request = http.Request(method, uri);
      request.headers.addAll(header);

      if(body != null) {
        request.body = body;
      }

      if(bodyBytes != null) {
        request.bodyBytes = bodyBytes;
      }

      if(bodyFields != null) {
        request.bodyFields = bodyFields;
      }
      
      final client = appHttpClient!;

      try {
        final streamedResponse = await client.send(request);

        throwIfInterrupted?.call();

        // 若没传自定义response handler，则走默认处理流程

        Future<HttpResponse> parseJsonOrThrow() async {
          // final httpResponse = HttpResponse(streamedResponse, close: () {client.close();});
          final httpResponse = HttpResponse(streamedResponse);
          if(parseResponseToJsonMap) {
            httpResponse.responseMap = await _parseJsonOrThrow(httpResponse, allowEmptyResponse: allowEmptyResponse);
          }

          if(retryAfterInSec < 1) {
            retryAfterInSec = httpResponse.responseMap?[myRetryAfterKey] ?? 0;
            App.logger.debug(_TAG, "retryAfterInSec from response map: $retryAfterInSec");
          }

          return httpResponse;
        }

        // 有时候，无效，得从json解析，草
        if(retryAfterInSec < 1){
          retryAfterInSec = int.tryParse(streamedResponse.headers["Retry-After"] ?? "") ?? 0;
          App.logger.debug(_TAG, "retryAfterInSec from header: $retryAfterInSec");
        }


        if(streamedResponse.statusCode != 200) {
          if(throwIfStatusCodeNotOk) {
            if(caller != RemoteType.dropbox.value) {
              // 读取响应体文本以获取错误信息
              final data = await streamedResponse.stream.bytesToString();
              throw RemoteException('http err: caller: $caller, uri: $uri, Dropbox-API-Arg: ${header["Dropbox-API-Arg"]}, statusCode: ${streamedResponse.statusCode}, data: $data, err code: 17024135');
            }else {
              // 之所以为 dropbox单独写个parseJsonOrThrow是为了在解析时检查错误是否是not found异常，若是，则抛出RemotNotFoundException，
              // 如果是delete操作，这个异常不算异常，会忽略
              final response = await parseJsonOrThrow();
              // 若上面解析没出错，则在这抛出异常，并携带解析好的 jsonMap，内部包含错误信息
              throw RemoteException('http err: caller: $caller, uri: $uri, Dropbox-API-Arg: ${header["Dropbox-API-Arg"]}, statusCode: ${streamedResponse.statusCode}, data: ${response.responseMap}, err code: 16000806', data: response.responseMap);
            }
          }
        }


        // 若传了自定义response handler，使用，然后返回
        if(responseHandler != null) {
          await responseHandler(streamedResponse);
          // 注：如果流已经在responseHandler里消费，就不能再消费这里返回的 HttpResponse.response
          return HttpResponse(streamedResponse);
        }

        return await parseJsonOrThrow();
      }finally {
        // 全局复用，所以不需要close了
        // try {
        //   client.close();
        // }catch(e, st) {
        //   App.logger.debug(_TAG, "close http client err: $e\n$st");
        // }
      }
    }

    int tried = 0;
    int maxTry = 5;
    while(true) {
      tried++;
      if(retryAfterInSec > 0) {
        // 至少等3秒
        // retryAfterInSec += 3;
        App.logger.debug(_TAG, "will retry request to '$uri' after sec: $retryAfterInSec");
        await Future.delayed(Duration(seconds: retryAfterInSec));
      }

      try {
        // send会重置retryAfterInSec
        final httpResponse = await send();
        return httpResponse;
      }catch(e, st) {
        App.logger.debug(_TAG, "request to '$uri' got an err (if no Retry-After header, then will throw, else will retry): tried=$tried, err:$e\n$st");

        // 如果没指示重试，直接抛异常
        if(retryAfterInSec < 1 || tried >= maxTry) {
          if(tried > 1) {
            // 大于1，有重试，请求至少执行了2次
            App.logger.debug(_TAG, "tried $tried times still got an error, maybe try find some way to avoid retry and resolve error?, uri=$uri");
          }
          rethrow;
        }

        // 在这个时间后重试，或许会晚几秒，因为我会基于这个时间再增加点时间，确保下次请求一定晚于这个时间（那万一源头本来就在可接受时间内增加了秒数呢？我这岂不是属于层层加码了？不过问题不大，反正后面没别人继续加码）
        App.logger.debug(_TAG, "response response include Retry-After header, the value is: $retryAfterInSec, will retry after this time (maybe later few seconds).");
      }
    }
  }

  static Future<Map<String, dynamic>> parseJsonResponse(http.StreamedResponse streamedResponse, {bool allowEmptyResponse = true}) async {
    try {
      final jsonStr = await streamedResponse.stream.bytesToString();
      final data = jsonDecode(jsonStr);
      if(data == null) {
        if(allowEmptyResponse) {
          return {};
        }else {
          throw "server response is empty";
        }
      }

      return data;
    }catch(e, st) {
      App.logger.debug(_TAG, "parse server response to json err: $e\n$st");
      throw RemoteException("parse server response to json err: $e", data: e);
    }
  }

  static Future<Map<String, dynamic>> _parseJsonOrThrow(HttpResponse httpResponse, {bool allowEmptyResponse = true}) async {
    final responseMap = await HttpUtil.parseJsonResponse(httpResponse.response, allowEmptyResponse: allowEmptyResponse);
    final error = responseMap["error"];
    final retryAfter = error?["retry_after"] ?? 0;
    // 若带重试值就不抛异常了，等待指定时间后重试
    if(error != null && retryAfter < 1) {
      // 这里解析，如果是not found，返回 RemoteNotFoundException；否则返回 RemoteException
      if(error[".tag"] == "path_lookup") {
        if(error["path_lookup"]?[".tag"] == "not_found") {
          throw RemoteNotFoundException(responseMap.toString(), data: responseMap);
        }
      }else if(error[".tag"] == "path") {
        // dropbox getMetadata api，路径不存在时，抛的异常
        if(error["path"]?[".tag"] == "not_found") {
          throw RemoteNotFoundException(responseMap.toString(), data: responseMap);
        }
      }

      throw RemoteException(responseMap.toString(), data: responseMap);
    }

    if(retryAfter > 0) {
      // for dropbox
      App.logger.warn(_TAG, "ignore error due to retryAfter > 0: retryAfter=$retryAfter, error=$error");
      responseMap[myRetryAfterKey] = retryAfter;
    }

    return responseMap;
  }


  static Future<Map<String, String>> newHeader({
    String? contentType,
  }) async {
    final header = <String, String>{};

    if(contentType != null) {
      header["Content-Type"] = contentType;
    }

    return header;
  }

}
