import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/byte_reader.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/stream.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';

abstract class KeyExtraData implements ByteStream {
  static final magic = [0xe4, 0x0d, 0x45, 0x48, 0xbe, 0xa5, 0xe8, 0xc0];
  int get version; // 1 byte

  
  static Future<KeyExtraData> readFromStream(Stream<List<int>> input) async {
    final byteReader = ByteReader(input);
    final tmpMagic = (await byteReader.readBytes(magic.length))!;
    if (!bytesEquals(magic, tmpMagic)) {
      throw FormatException("format err: code 11408798, bad magic: ${bytesListToHexStrList(tmpMagic)}");
    }

    final tmpVersion = await byteReader.readByte();
    if (tmpVersion == 1) {
      return await _readKeyExtraDataV1(byteReader, KeyExtraDataV1());
    }

    throw UnsupportedError("unsupported key extra data version: $tmpVersion");
  }

  Stream<List<int>> writeHeaderToStream() async* {
    yield magic;
    yield intToBytes(version, 1);
  }

  static KeyExtraData genFromKeyData(KeyData keyData) {
    if (keyData.version == 1) {
      keyData as KeyDataV1;
      final keyExtraDataV1 = KeyExtraDataV1();
      keyExtraDataV1.saltLen = keyData.saltLen;
      keyExtraDataV1.saltData = keyData.saltData;
      keyExtraDataV1.contentPaddingLen = keyData.contentPaddingLen;
      keyExtraDataV1.contentPadding = keyData.contentPadding;
      return keyExtraDataV1;
    }

    throw UnsupportedError("unsupported key version: ${keyData.version}");
  }
  
}

class KeyExtraDataV1 extends KeyExtraData {
  @override
  final version = 1;

  int saltLen=0;  // 2 bytes
  List<int> saltData=[];
  int contentPaddingLen=0;  //2 bytes
  List<int> contentPadding=[];

  @override
  Stream<List<int>> toByteStream() async* {
    yield* writeHeaderToStream();

    yield intToBytes(saltLen, 2);
    yield saltData;
    yield intToBytes(contentPaddingLen, 2);
    yield contentPadding;
  }
}

Future<KeyExtraData> _readKeyExtraDataV1(ByteReader byteReader, KeyExtraDataV1 keyExtraDataV1) async {
  keyExtraDataV1.saltLen = intFromBytes((await byteReader.readBytes(2))!, 0, 2);
  keyExtraDataV1.saltData = (await byteReader.readBytes(keyExtraDataV1.saltLen))!;
  keyExtraDataV1.contentPaddingLen = intFromBytes((await byteReader.readBytes(2))!, 0, 2);
  keyExtraDataV1.contentPadding = (await byteReader.readBytes(keyExtraDataV1.contentPaddingLen))!;
  return keyExtraDataV1;
}
