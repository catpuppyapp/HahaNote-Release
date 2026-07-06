import 'dart:convert';
import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';

/// 生成证书文件：
/// 使用方法：
/// 1. 去 https://curl.se/docs/caextract.html 下载mozilla证书
/// 2. 将证书文件放到 'test/res/bundled_certs.pem'
/// 3. 修改当前函数注释中的"更新于"后面的时间，然后执行当前函数
/// 4. 移动生成的证书字节文件 'test/res/bundled_certs.dart' 到 'lib/hahanote_lib_sync/remotes/base/bundled_certs.dart'
/// 5. 启动程序，测试网络连接是否正常
Future<void> main() async {
  final prefixString = r'''
// 更新于：20260629
// 证书包发布日期：20260514
// 来源：https://curl.se/docs/caextract.html
// r代表raw字符串，可保留转义字符，例如\、\n等
// """这种格式代表多行字符串，可保留换行符"""
const bundledCertsBytes=[''';

  final out = await getFileAndMakeSureParentDirExist('test/res/bundled_certs.dart');
  final bundledCertsBytes = utf8.encode(File('test/res/bundled_certs.pem').readAsStringSync());
  final lastIdx = bundledCertsBytes.length - 1;
  final sb = StringBuffer(prefixString);
  for(final (idx, b) in bundledCertsBytes.indexed) {
    sb.write(b.toString());
    if(idx < lastIdx) {
      sb.write(',');
    }
  }

  sb.write('];\n');
  out.writeAsStringSync(sb.toString(), flush: true);
}
