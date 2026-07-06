import 'dart:convert';

import 'package:hahanote_app/hahanote_lib_sync/crypto/encrypt.dart';
import 'package:hahanote_app/hahanote_lib_sync/crypto/key_extra_data.dart' show KeyExtraData, KeyExtraDataV1;
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart' show AppException;
import 'package:hahanote_app/hahanote_lib_sync/serialization/byte_reader.dart' show ByteReader;
import 'package:hahanote_app/hahanote_lib_sync/serialization/stream.dart' show ByteStream;
import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show bytesEquals, bytesListToHexStrList, intToBytes, randomSalt, randomBytesSafe, intFromBytes;
import 'package:cryptography/cryptography.dart';

const _currentKeyDataVersion = 1;
const _contentKeyLen = xxx20KeyLen; // 字节, xchacha20固定32字节长度密钥
const _minSaltLen = 24;
const _minContentPaddingLen = 32;

abstract class KeyDataType {
  // 无效类型，0，有效类型一律从1开始
  static final invalid = 0;

  // 内嵌，不可复现，缺少salt等参数
  // 基本上，永远不会改，除非重新设计存储库
  static final appKey = 1;

  // 从用户输入的密码派生的，可通过再输入密码，用同样参数来判断是否一致
  // 不会上传到远程仓库
  static final masterKey = 2;

  // 随机生成，不可复现，用来加密文件
  // 会上传到远程仓库
  static final contentKey = 3;
}


// 共用的key data
abstract class KeyData implements ByteStream {
  // 随便输的，用来快速判断文件类型
  static const magic = [0x2b, 0xf8, 0xb0, 0xf6, 0x11, 0x13, 0x07, 0x6f];
  abstract final int version; // 1 byte
  int reserved = 0;  // 1byte
  int type = KeyDataType.invalid; // 1byte

  // key
  abstract int keyLen; //2 bytes
  List<int> key = []; // key data in bytes

  // content padding，用此key加密文件时，
  // 会先在文件头部追加padding
  // 1. 避免空文件，
  // 2. 避免通过hash碰撞出内容
  // (不过对于空文件而言，这个变量的hash会暴露，但只要这个字段够长，就安全)
  // 当初创建变量的时候，首先想到的是padding，但现在看来，实际上其作用相当于hash salt，每个key加密文件时使用各自的salt，
  // 这个salt不能随机，因为要用来计算hash，若随机，需要给每个文件单独生成固定的salt，很麻烦，所以统一每个key固定一个slat即可，
  // 这个salt仅用于和文件原始内容拼接，然后计算hash，验证文件是否相同，并不用来保证“保密”，
  // 保证保密性并且每个文件各自使用唯一的salt(或称nonce)，由encrypt函数确保，
  // 简单来说就是不管用什么算法加密，xChaCah20或Aes都行，但要确保每次加密文件时，
  // 为文件生成唯一的真随机salt，就行。
  // 这里的salt负责计算hash，加密的salt负责保密和防内容碰撞以及位反转破解（好像salt重复能通过位反转得到明文之类的，忘了）。
  abstract final int contentPaddingLen;  // 2bytes
  List<int> contentPadding = [];


  static Future<KeyData> readFromStream(Stream<List<int>> input) async {
    final byteReader = ByteReader(input);

    final tmpMagic = (await byteReader.readBytes(magic.length))!;
    if (!bytesEquals(magic, tmpMagic)) {
      throw FormatException("format err: code 15305247, bad magic: ${bytesListToHexStrList(tmpMagic)}");
    }

    final tmpVersion = (await byteReader.readByte())!;
    if (tmpVersion == 1) {
      final keyData = KeyDataV1();
      keyData.reserved = (await byteReader.readByte())!;
      keyData.type = (await byteReader.readByte())!;
      
      return _readKeyDataV1(byteReader, keyData);
    }

    throw UnsupportedError("unsupported encryptor version: $tmpVersion");
  }

  // 创建的时候默认最新版本
  // 读取的时候按文件内部版本调用对应函数读取
  static Future<KeyData> deriveMasterKey(
    String masterPass, {
    int version = _currentKeyDataVersion,
    KeyExtraData? keyExtraData,
  }) async {
    if (version == 1) {
      return _deriveMasterKeyV1(masterPass, keyExtraData);
    }

    throw UnsupportedError("unsupported key data version: $version");
  }

  static Future<KeyData> deriveContentKey({
    int version = _currentKeyDataVersion,
  }) async {
    if (version == 1) {
      return _deriveKeyContentKeyV1();
    }

    throw UnsupportedError("unsupported key data version: $version");
  }

  Stream<List<int>> writeHeaderToStream() async* {
    yield magic;
    yield intToBytes(version, 1);
    yield intToBytes(reserved, 1);
    yield intToBytes(type, 1);
  }
}

// 算法：argon2id key data
//密钥文件格式：
//文件头：
// magic: 8字节
// version: 1字节：例如 1，不同版本有不同的函数读取，但文件头格式相同，例如：版本1是用argon2id哈希密码的，所以后面跟的是argon2id的参数，版本2可能改成别的，后面跟的参数格式也不同
// reserved: 1 字节：默认0x00，避免日后有用

// argon2id参数区：
// iterations: 4 字节，大端，相当于 unit32
// memorySizeKB: 同上
// parallelism: 同上
// hashLength: 同上

//salt
// saltLen：2字节，最大 65535
// saltData: 长度为saltLen字节，也就是先读上面的salt长度，取出salt数据长度，再根据长度去读salt

//密钥
// keyLen: 2字节
// key，根据上面keyLen的值去读

// 附加字段：
// metaLen: 4字节，大端，相当于 uint32，默认没数据时，全0
// meta 数据

// 读回时先校验 magic 与 version，再按字段长度逐一读取；使用 Big‑Endian 保证跨语言一致。
class KeyDataV1 extends KeyData {
  @override
  final version = 1;
  // 创建实例时随机生成这几个参数（限定范围）
  // argon2id, each 4 bytes
  // recommend settings, see: https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#argon2id
  // 这个必须硬编码，
  // 不然在不存在加密后的主密码的情况下验证用户输入的主密码时不知道该用什么参数
  // 例如：需要用能否解密 content key 来验证用户输入的 master password 是否正确
  // 这时，如果这几个参数不是常量，我怎么知道当初派生的是否是哪些参数？
  // 不知道参数就无法派生出相同的key，就绝对无法解密content key，那用户的内容不就全成砖了？
  // 不过这几个参数还是会写入2进制文件，
  // 从文件恢复对象的时候还是要遵守文件中的值，这样日后若代码里改了参数，仍可兼容旧代码中的参数
  int iterations = 2;  // 4bytes
  // 随便输的，比上面的网站建议值稍大点，避免被人直接用网站的数据套上去碰撞
  int memorySizeKb = 22171; // 4bytes
  int parallelism = 1; // 2bytes

  // 派生key的时候用的salt，salt不同，
  // 即使原明文password相同，派生出的密码也不一样
  // 这个如果一样，就能离线计算并碰撞hash，所以不能一样
  // 但如果完全加密，就无法验证用户输入的主密码，所以必须把这个值存上
  // 平衡一下，用app密钥加密此数据，存到单独文件，【上传的远程仓库】
  // master key遵守最小saltLen，其他类型的key可能不遵守，因为这个主要是用来验证的，其他的key可能不需要验证，只有master key需要
  int saltLen = _minSaltLen; // 2 bytes
  List<int> saltData = [];

  // 指定32字节，xchacha20的key固定32字节
  @override
  int keyLen = xxx20KeyLen; // 2bytes

  @override
  int contentPaddingLen = _minContentPaddingLen;  // 2 bytes

  @override
  Stream<List<int>> toByteStream() async* {
    yield* super.writeHeaderToStream();

    yield intToBytes(iterations, 4);
    yield intToBytes(memorySizeKb, 4);
    yield intToBytes(parallelism, 2);

    yield intToBytes(saltLen, 2);
    yield saltData!;

    yield intToBytes(keyLen, 2);
    yield key!;

    yield intToBytes(contentPaddingLen, 2);
    yield contentPadding!;
  }
}

// derive key and write it into `keyData`
Future<KeyDataV1> _deriveMasterKeyV1(String masterPass, [KeyExtraData? keyExtraData]) async {
  KeyDataV1 keyData = KeyDataV1();

  keyData.type = KeyDataType.masterKey;

  final algorithm = Argon2id(
    parallelism: keyData.parallelism,
    memory: keyData.memorySizeKb,
    iterations: keyData.iterations,
    hashLength: keyData.keyLen,
  );

  KeyExtraDataV1? keyExtraDataV1;
  if(keyExtraData != null && keyExtraData.version == 1) {
    keyExtraDataV1 = keyExtraData as KeyExtraDataV1;
  }

  final saltData = keyExtraDataV1?.saltData ?? randomSalt(keyData.saltLen);
  if(saltData.length < _minSaltLen) {
    throw StateError("unexpected saltData length: ${saltData.length}");
  }
  keyData.saltData = saltData;
  keyData.saltLen = saltData.length;

  final newSecretKey = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(masterPass)),
    nonce: saltData,
  );

  // key bytes
  var key = await newSecretKey.extractBytes();

  // should never happens
  if(key.length < xxx20KeyLen) {
    throw StateError("unexpected key length: ${key.length}");
  }

  // write key into keyData
  keyData.keyLen = key.length;  // actually unnecessary for xxx20, cause should always be 32
  keyData.key = key;

  final contentPadding = keyExtraDataV1?.contentPadding ?? generateContentPadding(keyData.contentPaddingLen);
  if(contentPadding.length < _minContentPaddingLen) {
    throw StateError("unexpected contentPadding length: ${contentPadding.length}, err code: 10002550");
  }

  keyData.contentPadding = contentPadding;
  keyData.contentPaddingLen = contentPadding.length;

  return keyData;
}

// derive key and write it into `keyData`
Future<KeyDataV1> _deriveKeyContentKeyV1() async {
  KeyDataV1 keyData = KeyDataV1();

  keyData.type = KeyDataType.contentKey;

  // 直接随机数生成，不需要salt
  keyData.saltLen = 0;
  keyData.saltData = [];

  final key = generateContentKey();

  // content直接生成随机字节，不需要验证，
  //   所以也不需要salt(nonce)等验证原密码的参数

  // write key into keyData
  keyData.keyLen = key.length;
  keyData.key = key;

  // 用此key加密文件时，使用的padding，
  //   避免空文件的空字节流以及降低hash碰撞
  //  （要用源文件hash做objects里的文件名，
  //    所以如果不稍作处理，可能通过hash碰撞出内容）
  keyData.contentPadding = generateContentPadding(keyData.contentPaddingLen);
  if(keyData.contentPadding.length < _minContentPaddingLen) {
    throw StateError("unexpected contentPadding length: ${keyData.contentPadding.length}, err code: 19704870");
  }

  if(keyData.contentPadding.length != keyData.contentPaddingLen) {
    throw StateError("unexpected contentPadding length: ${keyData.contentPadding.length}, err code: 12836532");
  }

  return keyData;
}

// used to derive content key
// 生成一个字符串，再用它来派生内容密钥
List<int> generateContentKey() {
  // 直接生成32位随机字节即可
  return randomBytesSafe(_contentKeyLen);
}

List<int> generateContentPadding(int len) {
  // 理论上来说，可以没有这个padding，但我强制要这个，避免数据算hash被碰撞出来，
  // 例如 abc，hash是123，若加了padding，则可能是456，这样就无法通过hash碰撞出原内容了
  if(len < 1) {
    throw AppException("content padding cannot be empty");
  }
  return randomBytesSafe(len);
}


Future<KeyData> _readKeyDataV1(
  ByteReader byteReader,
  KeyDataV1 keyData,
) async {
  /**
   * 
    yield intToBytes(iterations, 4);
    yield intToBytes(memorySizeKb, 4);
    yield intToBytes(parallelism, 2);

    yield intToBytes(saltLen, 2);
    yield saltData!;

    yield intToBytes(keyLen, 2);
    yield key!;

    yield intToBytes(contentPaddingLen, 2);
    yield contentPadding!;
   */

  keyData.iterations = intFromBytes((await byteReader.readBytes(4))!, 0, 4);
  keyData.memorySizeKb = intFromBytes((await byteReader.readBytes(4))!, 0, 4);
  keyData.parallelism = intFromBytes((await byteReader.readBytes(2))!, 0, 2);
  keyData.saltLen = intFromBytes((await byteReader.readBytes(2))!, 0, 2);

  // 可能是空数组，比如预设的app key，用不到saltData，就留空了
  keyData.saltData = (await byteReader.readBytes(keyData.saltLen))!;

  keyData.keyLen = intFromBytes((await byteReader.readBytes(2))!, 0, 2);
  if(keyData.keyLen < 1) {
    throw AppException("key length is 0.");
  }
  keyData.key = (await byteReader.readBytes(keyData.keyLen))!;

  keyData.contentPaddingLen = intFromBytes((await byteReader.readBytes(2))!, 0, 2);
  if(keyData.contentPaddingLen < 1) {
    throw AppException("content padding length is 0.");
  }
  keyData.contentPadding = (await byteReader.readBytes(keyData.contentPaddingLen))!;

  return keyData;
}
