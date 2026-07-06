import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/crypto/compress.dart' show CompressedData;
import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart' show StreamConsumedException;
import 'package:hahanote_app/hahanote_lib_sync/serialization/stream.dart' show WriteToFile, ByteStream, ByteStreamExt;
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart' show writeStreamToFile;
import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show intToBytes, bytesEquals, bytesListToHexStrList, intFromBytes;
import 'package:cryptography/cryptography.dart';

const _TAG = "encrypt.dart";

const xxx20KeyLen = 32;
const _xxx20MacLen = 16;
const currentEncryptedDataVersion = 1;

abstract class EncryptedData implements WriteToFile, ByteStream {
  static const magic = [0xba, 0x68, 0xa9, 0x96, 0x25, 0x46, 0x22, 0x8f];
  abstract int version;
  // x 这字段后来没用了，递增int不太好，早晚爆，不用了) 上传数据，会验证这个版本，如果小于本地，则更新
  int syncVersion = 0;  // 8 bytes
  Stream<List<int>>? encryptedStream;

  static int headerLen() {
    // 参考：writeHeaderToStream()，
    // 把要写入的数据的长度加起来就是这个返回值
    return magic.length + 1 + 8;
  }

  Stream<List<int>> writeHeaderToStream() async* {
    yield magic;
    yield intToBytes(version, 1);
    yield intToBytes(syncVersion, 8);
  }

  static Future<EncryptedData> encrypt(
    Stream<List<int>> data,
    List<int> secretKeyBytes, {
    int syncVersion = 0,
    int version = currentEncryptedDataVersion,
  }) async {
    if (version == 1) {
      return _encryptV1(data, secretKeyBytes);
    }

    throw UnsupportedError("unsupported encryptor version: $version");
  }

  static Future<EncryptedData> compressThenEncrypt(
    Stream<List<int>> data,
    KeyData keyData, {
    int syncVersion = 0,
    int version = currentEncryptedDataVersion,
  }) async {
    final compressedData = await CompressedData.compressWithKeyData(data, keyData);

    return await EncryptedData.encrypt(
      compressedData.toByteStream(),
      keyData.key
    );
  }

  static Future<EncryptedData> readFromFile(File file) async {
    App.logger.verbose(_TAG, "read enc data from file: ${file.path}");

    final raf = await file.open();

    try {
      // verify magic
      final tmpMagic = await raf.read(magic.length);
      if(!bytesEquals(magic, tmpMagic)) {
        throw FormatException("format err: code 10513596, bad magic: ${bytesListToHexStrList(tmpMagic)}");
      }

      // read data by version
      final tmpVersion = await raf.readByte();
      if (tmpVersion == 1) {
        final encData = EncryptedDataV1();
        encData.syncVersion = intFromBytes(await raf.read(8), 0, 8);
        return await _readEncryptedDataV1(raf, file, encData);
      }

      throw UnsupportedError("unsupported encrypt version: $tmpVersion, err code: 11403026");
    } finally {
      await raf.close();
    }
  }


  static Future<EncryptedData> readFromBytes(List<int> bytes) async {
    if(bytes.length < magic.length) {
      throw FormatException("format err: code 10186664, bad magic");
    }

    // verify magic
    int cursor = magic.length;
    final tmpMagic = bytes.sublist(0, cursor);
    if(!bytesEquals(magic, tmpMagic)) {
      throw FormatException("format err: code 13788139, bad magic: ${bytesListToHexStrList(tmpMagic)}");
    }

    // read data by version
    final tmpVersion = bytes[cursor++];
    if (tmpVersion == 1) {
      final encData = EncryptedDataV1();
      encData.syncVersion = intFromBytes(bytes.sublist(cursor, cursor+8), 0, 8);
      cursor += 8;
      return await _readEncryptedDataV1FromBytes(bytes, cursor, encData);
    }

    throw UnsupportedError("unsupported encrypt version: $tmpVersion, err code: 10638685");
  }

  /// return a decrypted stream
  /// 外部不应该调用这个，应该调用 [decryptThenUncompress]
  // @protected
  Stream<List<int>> decrypt(List<int> secretKeyBytes);

  // 这个由于没使用yield，所以外部可正常捕获异常
  Future<List<int>> decryptToBytes(List<int> secretKeyBytes) async {
    final stream = decrypt(secretKeyBytes);
    final bb = BytesBuilder(copy: false);
    await for(final b in stream) {
      bb.add(b);
    }

    return bb.takeBytes();
  }

  // 改用Future包Stream的原因：之前是直接返回Stream，
  // 内部使用 yield* 返回数据，但是【使用yield方式无法try catch捕获异常，同时这个函数内部又必须用await，所以改成返回Future了】
  // 如果函数内部不需要用await，可直接返回stream，这样外部调用时依然能捕获异常，重点是【若使用yield，则外部无法捕获异常】
  Future<Stream<List<int>>> decryptThenUncompress(KeyData keyData);

  @override
  Future<void> writeToFile(File file) async {
    await writeStreamToFile(file, toByteStream());
  }
}

class EncryptedDataV1 extends EncryptedData {
  @override
  int version = 1;

  int nonceLen = 24; // 1byte
  List<int>? nonce;
  List<int>? mac;  //固定长度
  bool _byteStreamConsumed = false;

  @override
  Stream<List<int>> toByteStream() async* {
    if(_byteStreamConsumed) {
      throw StreamConsumedException();
    }
    _byteStreamConsumed = true;

    yield* writeHeaderToStream();

    yield intToBytes(nonceLen, 1);
    yield nonce!;
    yield* encryptedStream!;
    yield mac!;
  }

  @override
  Stream<List<int>> decrypt(List<int> secretKeyBytes) {
    final cipher = Xchacha20.poly1305Aead();
    final decryptedData = cipher.decryptStream(
      encryptedStream!,
      secretKey: SecretKey(secretKeyBytes),
      nonce: nonce!,
      mac: Mac(mac!),
    );

    return decryptedData;
  }

  @override
  Future<Stream<List<int>>> decryptThenUncompress(KeyData keyData) async {
    final decryptedDataWithPadding = decrypt(keyData.key);
    final compressData = await CompressedData.readFromStream(decryptedDataWithPadding);
    return compressData.uncompressWithKeyData(keyData);
  }

}

// 加密的时候默认使用最新版本，解密的时候根据文件中的版本号使用对应解密器
Future<EncryptedData> _encryptV1(
  Stream<List<int>> data,
  List<int> secretKeyBytes, {
  int syncVersion = 0,
}) async {
  final cipher = Xchacha20.poly1305Aead();
  final nonce = cipher.newNonce();
  final secretKey = SecretKey(secretKeyBytes);

  final encryptData = EncryptedDataV1();

  final encryptedStream = cipher.encryptStream(
    data,
    secretKey: secretKey,
    nonce: nonce,
    onMac: (mac) {
      // 类似数据hash，用来校验数据，存上即可
      // 调用时机：当你用 await for 消费完encryptedStream后，会自动调用onMac
      // 之所以这么设计可能是因为返回流的函数无法返回另一个返回值，只能不断yield 流中的数据，而mac又必须消费完流才能计算完毕，
      // 所以只能通过回调把mac传给调用者了，回调会在返回流的函数内部被执行，而只有流内部才知道哪个yield是最后一个，
      // 所以它也知道什么时机调用onMac，不过这种api还是挺恶心的，流本质上是函数，返回给调用者一个getter，
      // 使用的时候调用setter函数持续提供值，但做成返回值的样子，实际上隐藏了复杂性，表面上简化了，但有点反直觉
      encryptData.mac = List<int>.from(mac.bytes);
    },
  );

  encryptData.nonceLen = nonce.length;
  encryptData.nonce = nonce;
  encryptData.encryptedStream = encryptedStream;
  encryptData.syncVersion = syncVersion;

  return encryptData;
}

Future<EncryptedData> _readEncryptedDataV1(
  RandomAccessFile raf,
  File file,
  EncryptedDataV1 encryptData,
) async {
  encryptData.nonceLen = await raf.readByte();
  encryptData.nonce = await raf.read(encryptData.nonceLen);

  // read mac from end of stream
  final encryptDataStreamStart = await raf.position();
  final encryptDataStreamEnd = await raf.length() - _xxx20MacLen;
  await raf.setPosition(encryptDataStreamEnd);
  encryptData.mac = await raf.read(_xxx20MacLen);

  encryptData.encryptedStream = file.openRead(
    encryptDataStreamStart,
    encryptDataStreamEnd,
  );

  return encryptData;
}

Future<EncryptedData> _readEncryptedDataV1FromBytes(
  List<int> bytes,
  int initCursor,
  EncryptedDataV1 encryptData,
) async {
  int cursor = initCursor;
  encryptData.nonceLen = bytes[cursor++];
  encryptData.nonce = bytes.sublist(cursor, cursor + encryptData.nonceLen);
  cursor += encryptData.nonceLen;

  // read mac from end of stream
  final macStartIndex = bytes.length - _xxx20MacLen;
  encryptData.mac = bytes.sublist(macStartIndex);

  encryptData.encryptedStream = Stream.value(bytes.sublist(cursor, macStartIndex));

  return encryptData;
}

// abstract class EncryptDatalized {
//   Future<EncryptedData> toEncryptedData(KeyData keyData);
// }

// 这个是只加密不压缩的
Future<List<int>> encryptStrToBytes(String clearText, KeyData keyData) async {
  final encData = await EncryptedData.encrypt(Stream.value(utf8.encode(clearText)), keyData.key);
  return await encData.toBytes();
}

// 这个是只解密不解压缩的，和 [encryptStrToBytes] 配套使用
Future<String> decryptBytesToStr(List<int> encryptedBytes, KeyData keyData) async {
  final encData = await EncryptedData.readFromBytes(encryptedBytes);
  final bytes = await encData.decryptToBytes(keyData.key);
  return utf8.decode(bytes);
}
