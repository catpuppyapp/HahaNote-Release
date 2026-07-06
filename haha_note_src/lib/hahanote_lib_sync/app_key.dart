import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';

import 'app.dart';
import 'crypto/encrypt.dart';

const _TAG = "app_key.dart";

abstract class AppKey {
  static bool _inited = false;
  // 按时间降序排列，第一个是最新版，最后一个是最旧版
  static late List<KeyData> _keys;

  static const keyLen = 32;
  static const contentPaddingLen = 32;

  static void init() {
    if(_inited) {
      return;
    }

    _inited = true;


    // 新版在上，旧版在下
    final tempKeys = <KeyData>[];
    tempKeys.add(_getKey2());
    tempKeys.add(_getKey1());
    _keys = tempKeys;
  }

  static KeyData _getKey2() {
    // 32 字节，xxx20的密钥固定32字节
    final List<int> keyBytes = const [0x54, 0xb2, 0xcc, 0xea, 0x4f, 0x1b, 0x6e, 0xe5, 0x42, 0x51, 0x2a, 0xfe, 0x2e, 0x7c, 0x60, 0x4f, 0xc9, 0x66, 0xea, 0x94, 0x45, 0x32, 0xc1, 0xff, 0x32, 0x89, 0x23, 0x09, 0xe2, 0x30, 0x48, 0x6f];
    if(keyBytes.length != keyLen) {
      throw AppException("key length is ${keyBytes.length}, but expected $keyLen, err code: 18247728");
    }

    // 32字节
    // 这个是压缩文件前填充内容的padding，多长都行，但没必要太长
    final List<int> contentPadding = const [0x1d, 0x0f, 0x14, 0x23, 0x4c, 0xa8, 0xdb, 0xc6, 0x50, 0xc3, 0xca, 0xd9, 0xdd, 0x44, 0x01, 0x74, 0xdd, 0xb3, 0x97, 0x87, 0xf7, 0x90, 0xf3, 0x46, 0x96, 0xc1, 0xa0, 0x04, 0x59, 0xb7, 0x1c, 0xa3];
    if(contentPadding.length != contentPaddingLen) {
      throw AppException("content padding length is ${contentPadding.length}, but expected $contentPaddingLen, err code: 13032897");
    }

    final tmpKeyData = KeyDataV1();
    tmpKeyData.type = KeyDataType.appKey;
    tmpKeyData.keyLen = keyBytes.length;
    tmpKeyData.key = keyBytes;
    tmpKeyData.contentPaddingLen = contentPadding.length;
    tmpKeyData.contentPadding = contentPadding;

    return tmpKeyData;
  }

  static KeyData _getKey1() {
    // 32 字节，xxx20的密钥固定32字节
    final List<int> keyBytes = const [0x06, 0xec, 0x57, 0x30, 0x13, 0xd8, 0xab, 0xdb, 0xfc, 0xac, 0x2f, 0xad, 0xd7, 0xe8, 0x4a, 0x48, 0x3e, 0xfc, 0x54, 0xde, 0x8a, 0x9c, 0x6a, 0xb6, 0x8d, 0xd4, 0xee, 0x75, 0x4a, 0x16, 0x57, 0x78];

    if(keyBytes.length != keyLen) {
      throw AppException("key length is ${keyBytes.length}, but expected $keyLen, err code: 19899453");
    }

    // 32字节
    // 这个是压缩文件前填充内容的padding，多长都行，但没必要太长
    final List<int> contentPadding = const [0x71, 0xa6, 0x0f, 0xa2, 0x73, 0x4e, 0xd7, 0xba, 0x1f, 0xee, 0x39, 0x23, 0xa4, 0x4d, 0x6c, 0xd9, 0x9a, 0xf2, 0x80, 0xb2, 0x5c, 0xf4, 0xff, 0xa2, 0x4c, 0xeb, 0xcd, 0xe2, 0x8e, 0x9c, 0xfd, 0x21];

    if(contentPadding.length != contentPaddingLen) {
      throw AppException("content padding length is ${contentPadding.length}, but expected $contentPaddingLen, err code: 15450227");
    }

    final tmpKeyData = KeyDataV1();
    tmpKeyData.type = KeyDataType.appKey;
    tmpKeyData.keyLen = keyBytes.length;
    tmpKeyData.key = keyBytes;
    tmpKeyData.contentPaddingLen = contentPadding.length;
    tmpKeyData.contentPadding = contentPadding;

    return tmpKeyData;
  }

  // 这个是只加密不压缩的
  // keyIdx 默认0，即使用最新版加密，用旧版也行，但若用旧版，解密的时候会先失败几次，影响性能
  static Future<List<int>> encryptStrToBytesWithAppKey(String clearText, {int keyIdx = 0}) async {
    return await encryptStrToBytes(clearText, _keys[keyIdx]);
  }

  // 这个是只解密不解压缩的，和 [encryptStrToBytes] 配套使用
  static Future<String> decryptBytesToStrWithAppKey(List<int> encryptedBytes) async {
    return await forEachTryAppKeysWithAct((keyData) async {
      return await decryptBytesToStr(encryptedBytes, keyData);
    });
  }

  static Future<T> forEachTryAppKeysWithAct<T>(Future<T> Function(KeyData) foreach, {String actName = "decrypt_data"}) async {
    final lastIdx = _keys.length - 1;
    for(final (idx, keyData) in _keys.indexed) {
      try {
        // 若不await，无法catch异常，得设置回调onError，所以这里await以简化代码
        return await foreach(keyData);
      }catch(e, st) {
        // 如果错误类型与解密本身无关，则直接抛异常，不用再继续尝试后续key了
        if(e is UserException) {
          rethrow;
        }

        // 如果最后一个key解密还是失败，则抛异常，否则继续尝试用旧版本key解密
        if(idx == lastIdx) {
          App.logger.debug(_TAG, "$actName with app key failed(err code: 13049326): $e\n$st");
          throw AppException("$actName with app key failed: please update app then try again, err code: 18303947");
        }
      }
    }

    // 正常来说这个永远不会执行到，除非一个key都没有（不进入for循环），因为上面要么解密成功，返回结果，要么解密失败，在最后一个key出错时rethrow错误
    // 可能当前app不包含对应版本的appkey，例如用户使用最新版加密的文件，然后换回了旧版，就会这样，提示用户升级app即可
    throw AppException("$actName with app key failed: please update app then try again, err code: 11648817");
  }

  static Future<EncryptedData> encryptDataWithAppKey(Stream<List<int>> data, {bool compress = true, int keyIdx = 0}) async {
    final keyData = _keys[keyIdx];
    if(compress) {
      return await EncryptedData.compressThenEncrypt(data, keyData);
    }else {
      return await EncryptedData.encrypt(data, keyData.key);
    }
  }

  static Future<Stream<List<int>>> decryptDataWithAppKey(
    // 如果直接传encData，第一次解密失败后，由于已消费流，第2次必然报错，就没法轮番尝试所有appkey了
    Future<EncryptedData> Function() getEncData, {
    bool uncompress = true,
  }) async {
    return await forEachTryAppKeysWithAct((keyData) async {
      final encData = await getEncData();
      if(uncompress) {
        return await encData.decryptThenUncompress(keyData);
      }else {
        return encData.decrypt(keyData.key);
      }
    });
  }
}
