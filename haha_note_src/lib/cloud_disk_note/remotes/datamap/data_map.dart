import 'dart:convert';
import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/crypto/encrypt.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/remote.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/stream.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart';

import '../../crypto/key_data.dart';

part 'data_map.g.dart';

@myJsonSerializable
class DataMap implements JsonByteStream {
  String contentId;
  // a value of RemoteDataType，注意是普通的type，例如 RemoteDataType.files，不是pfs类型
  String remoteDataType;

  // key 一律使用oid，不要使用路径
  // value则根据类型为FileInfo或Msg
  // 由于解json的时候，data的value会被解成map，所以value写成dynamic也得手动转，
  // 写成具体对象可能不需要手动转，但内部也是先从map再转成具体对象的，所以性能没差别，还不如按需转
  Map<String, Map<String, dynamic>> data;


  DataMap({String? contentId, this.remoteDataType = "", Map<String, Map<String, dynamic>>? data})
   : contentId = contentId ?? newContentId(),
     data = data ?? {};


  factory DataMap.fromJson(Map<String, dynamic> json) => _$DataMapFromJson(json);

  Map<String, dynamic> toJson() => _$DataMapToJson(this);

  static DataMap createFilesMap() {
    return DataMap(remoteDataType: RemoteDataType.files.value);
  }

  static DataMap createMsgMap() {
    return DataMap(remoteDataType: RemoteDataType.msg.value);
  }

  // static DataMap createObjectsMap() {
  //   return DataMap(remoteDataType: RemoteDataType.objects.value);
  // }

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

  static Future<DataMap> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return DataMap.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  static Future<DataMap> decrypt(KeyData contentKeyData, File file) async {
    final encryptedData = await EncryptedData.readFromFile(file);
    final rawData = await encryptedData.decryptThenUncompress(contentKeyData);

    return await fromJsonByteStream(rawData);
  }


  static String newContentId() {
    return randomString(32);
  }

  void updateContentId(String lastContentId) {
    if(contentId.isNotEmpty && contentId != lastContentId) {
      return;
    }

    contentId = newContentId();
  }

  void remove(VersionOid key, String lastContentId) {
    data.remove(key.value);
    updateContentId(lastContentId);
  }


  Map<String, dynamic>? get(VersionOid key) {
    return data[key.value];
  }

  void set(VersionOid key, dynamic value, String lastContentId) {
    data[key.value] = value;
    updateContentId(lastContentId);
  }

  DataMap copy() {
    final Map<String, Map<String, dynamic>> dataCopy = {};
    for(final src in data.entries) {
      dataCopy[src.key] = src.value;
    }

    return DataMap(contentId: contentId, remoteDataType: remoteDataType, data: dataCopy);
  }


  int size() => data.length;

}
