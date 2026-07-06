import 'dart:convert';
import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/app_key.dart';
import 'package:hahanote_app/hahanote_lib_sync/crypto/encrypt.dart';
import 'package:hahanote_app/config/app_config.dart';
import 'package:hahanote_app/main.dart';
import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';


Future<void> main() async {
  // init
  initLibs();
  App.initDevMode();
  // App.setUser(UserInfo(id: "test"));
  await AppConfig.setConfig(AppConfig(), save: false);

  test('Test Encrypt decrypt', () async {
    final tempFile = File("tmp_encrypt_test");
    try {
      var src = utf8.encode("hello");
      final encData = await AppKey.encryptDataWithAppKey(Stream.value(src), compress: false);
      await encData.writeToFile(tempFile);

      final result = <int>[];
      await for(final b in await AppKey.decryptDataWithAppKey(() async => await EncryptedData.readFromFile(tempFile), uncompress: false)) {
        result.addAll(b);
      }

      expect(const ListEquality<int>().equals(result, src), true);

    }catch(e) {

      rethrow;
    }finally {
      try {
        await tempFile.delete();
      }catch(_){}

    }
  });

  test('Test Encrypt decrypt with compress', () async {
    final tempFile = File("tmp_encrypt_test");
    try {
      var src = utf8.encode("hello");
      final encData = await AppKey.encryptDataWithAppKey(Stream.value(src));
      await encData.writeToFile(tempFile);

      final result = <int>[];
      await for(final b in await AppKey.decryptDataWithAppKey(() async => await EncryptedData.readFromFile(tempFile))) {
        result.addAll(b);
      }

      expect(const ListEquality<int>().equals(result, src), true);

    }catch(e) {

      rethrow;
    }finally {
      try {
        await tempFile.delete();
      }catch(_){}

    }

  });

  test('Test encrypt data to file', () async {
    final tempFile = File("filepath");
    try {

      var src = utf8.encode("hello");
      final encData = await AppKey.encryptDataWithAppKey(Stream.value(src));
      await encData.writeToFile(tempFile);

    }catch(e) {

      rethrow;
    }finally {
      // try {
      //   await tempFile.delete();
      // }catch(_){}

    }
  });


  test('Test decrypt file', () async {
    final tempFile = File("filepath");
    try {
      final result = <int>[];
      await for(final b in await AppKey.decryptDataWithAppKey(() async => await EncryptedData.readFromFile(tempFile))) {
        result.addAll(b);
      }

      print("result str: ${utf8.decode(result)}");

    }catch(e) {

      rethrow;
    }finally {
      // try {
      //   await tempFile.delete();
      // }catch(_){}

    }
  });


  test('Test decrypt str', () async {
    final str = "abcdef";
    // 测试用旧版key加密，然后调用解密函数，如果解密成功，说明轮番尝试所有appkey机制有效，否则无效
    final encBytes = await AppKey.encryptStrToBytesWithAppKey(str, keyIdx: 1);
    final decryptedStr = await AppKey.decryptBytesToStrWithAppKey(encBytes);
    assert(str == decryptedStr);
  });

}
