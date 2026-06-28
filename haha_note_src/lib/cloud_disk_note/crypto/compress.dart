
import 'dart:io' show ZLibCodec, ZLibOption;

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/crypto/key_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart' show StreamConsumedException, UserException;
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/byte_reader.dart' show ByteReader;
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/stream.dart' show ByteStream;
import 'package:cloud_disk_note_app/cloud_disk_note/sync_config.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/time/time_data.dart' show TimeData;
import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart' show intToBytes, bytesEquals, bytesListToHexStrList, concatStream, intFromBytes;
import 'package:freezed_annotation/freezed_annotation.dart';

// 这个是默认值，配置文件可调，会记录到压缩文件内，
// 因此修改配置后，不同压缩文件的level不一样也能正常解压缩（好像不记也能正常解压缩？）
// const _zstdLevel = 3;

// 当前压缩数据版本，内部用的，以后可能换实现
const currentCompressedDataVersion = 1;

abstract class CompressedData implements ByteStream {
  static const magic = [0x57, 0x97, 0xe8, 0x2f, 0xe1, 0x76, 0xb7, 0xb0];
  abstract final int version;  // 1byte

  TimeData createTime = TimeData.now();


  @override
  Stream<List<int>> toByteStream();

  Stream<List<int>> writeHeaderToStream() async* {
    yield magic;
    yield intToBytes(version, 1);
    yield* createTime.toByteStream();
  }

  static Future<CompressedData> readFromStream(Stream<List<int>> input) async {
    final byteReader = ByteReader(input);
    final tmpMagic = await byteReader.readBytes(magic.length);
    if (!bytesEquals(magic, tmpMagic!)) {
      throw FormatException("format err: code 17492658, bad magic: ${bytesListToHexStrList(tmpMagic)}");
    }

    final tmpVersion = await byteReader.readByte();
    if (tmpVersion == 1) {
      final compressedData = CompressedDataV1();
      compressedData.createTime = await _readTime(byteReader);
      return _readCompressedDataV1(byteReader, compressedData);
    }

    throw UnsupportedError("unsupported compressed version: $tmpVersion");
  }

  static Future<TimeData> _readTime(ByteReader byteReader) async {
    return TimeData.fromBytes((await byteReader.readBytes(12))!);
  }

  static Future<CompressedData> compress(
    Stream<List<int>> data, {
    int version = currentCompressedDataVersion,
  }) async {
    if (version == 1) {
      return _compressV1(data);
    }

    throw UnsupportedError("unsupported compressed version: $version");
  }

  static Future<CompressedData> compressWithKeyData(
    Stream<List<int>> data,
    KeyData keyData,{
    int version = currentCompressedDataVersion,
  }) {
    // 拼接 padding和内容
    return compress(concatStream(Stream.fromIterable([keyData.contentPadding!]), data));
  }


  /// 外部应该调用 [uncompressWithKeyData]
  @protected
  Stream<List<int>> uncompress();

  /// 流程：校验content padding，返回去除padding后的数据
  /// 返回原始数据流，如果去除padding后无内容，
  /// 再读流应该不用报错，如果用await for读，
  /// 没测试，日后再说
  Stream<List<int>> uncompressWithKeyData(KeyData keyData);

}

class CompressedDataV1 extends CompressedData {
  @override
  final int version = 1;
  // AppConfig可调
  int level = 3;  //1 byte
  Stream<List<int>>? compressedStream;
  bool _byteStreamConsumed = false;

  // 认证数据，解压时会验证此数据，例如可以存上userId,
  // 表明数据属于哪个用户，避免用户切换账号，无限试用，白嫖同步功能
  int authDataLen = 0; // 2bytes，最多可存2的16次方，也就是65536个英文字符，够用了
  List<int> authData = [];


  @override
  Stream<List<int>> toByteStream() async* {
    if(_byteStreamConsumed) {
      throw StreamConsumedException();
    }
    _byteStreamConsumed = true;

    yield* super.writeHeaderToStream();

    yield intToBytes(level, 1);

    yield intToBytes(authDataLen, 2);
    yield authData;

    yield* compressedStream!;
  }

  @override
  Stream<List<int>> uncompress() {
    // final codec = ZstdCodec(level: level);
    return compressedStream!.transform(ZLibCodec().decoder);
  }

  @override
  Stream<List<int>> uncompressWithKeyData(KeyData keyData) async* {
    // 压缩格式：key data的content padding + 数据
    final dataWithPadding = uncompress();
    final byteReader = ByteReader(dataWithPadding);
    
    // verify padding, if haven't padding, means data didn't match the key data
    final tmpContentPadding = (await byteReader.readBytes(keyData.contentPaddingLen))!;
    if(!bytesEquals(tmpContentPadding, keyData.contentPadding!)) {
      throw FormatException("format err: code 10533550, bad padding: ${bytesListToHexStrList(tmpContentPadding)}");
    }

    yield* byteReader.remainingStream() ;
  }
}


Future<CompressedData> _compressV1(Stream<List<int>> data) async {
  // final user = App.getUserOrThrow();
  final compressedData = CompressedDataV1();
  compressedData.authData = App.emptyUserIdBytes;
  compressedData.authDataLen = compressedData.authData.length;

  final syncConfig = SyncConfig.getConfig();
  compressedData.level = syncConfig.compressLevel.clamp(ZLibOption.minLevel, ZLibOption.maxLevel);

  // final codec = ZstdCodec(level: compressedData.level);
  compressedData.compressedStream = data.transform(ZLibCodec(level: compressedData.level).encoder);

  return compressedData;
}

Future<CompressedData> _readCompressedDataV1(
  ByteReader byteReader, 
  CompressedDataV1 compressedData
) async {
  compressedData.level = (await byteReader.readByte())!;
  // 注：读取不能禁用，因为之前有账号系统时创建的数据是包含用户id的，所以必须读取数据使reader光标向后移动
  final userIdLen = intFromBytes((await byteReader.readBytes(2))!, 0, 2);
  // 如果账号系统禁用，就不验证用户id和封包中的id是否匹配了
  if(App.accountSystemEnabled && userIdLen < 1) {
    throw UserException("invalid user id length");
  }

  final userIdBytes = (await byteReader.readBytes(userIdLen))!;
  if(App.accountSystemEnabled && !bytesEquals(App.emptyUserIdBytes, userIdBytes)) {
    throw UserException("The data belongs to another user");
  }

  compressedData.authDataLen = userIdLen;
  compressedData.authData = userIdBytes;

  compressedData.compressedStream = byteReader.remainingStream();
  return compressedData;
}

