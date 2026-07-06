import 'dart:convert' show utf8, jsonEncode, jsonDecode;
import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/crypto/encrypt.dart' show EncryptedData;
import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/json.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/stream.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show getJsonStrFromByteStream, randomString;

// 索引在本地，不上传，也不用加密

part 'index.g.dart';

@myJsonSerializable
class Index implements JsonByteStream {
  int version;
  String contentId;
  // String是相对路径，分隔符统一使用 '/'
  // map的key来自FilePath.mapKey()
  Map<String, IndexItem> items;

  Index({this.version = 1, String? contentId, Map<String, IndexItem>? items})
    : contentId = contentId ?? newContentId(),
      items = items ?? {};

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

  factory Index.fromJson(Map<String, dynamic> json) => _$IndexFromJson(json);

  Map<String, dynamic> toJson() => _$IndexToJson(this);


  static Future<Index> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return Index.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  static Future<Index> decrypt(KeyData contentKeyData, File file) async {
    final encryptedData = await EncryptedData.readFromFile(file);
    final rawData = await encryptedData.decryptThenUncompress(contentKeyData);

    return await fromJsonByteStream(rawData);
  }

  static String newContentId() {
    return randomString(32);
  }

  // only update if current content id same as lastContentId
  void updateContentId(String? lastContentId) {
    if(contentId.isNotEmpty && contentId != lastContentId) {
      return;
    }

    contentId = newContentId();
  }

  IndexItem? remove(FilePath relativePath, String lastContentId) {
    final removedItem = items.remove(relativePath.toMapKey());
    if(removedItem != null) {
      updateContentId(lastContentId);
    }

    return removedItem;
  }

  void add(FilePath relativePath, IndexItem? indexItem, String? lastContentId) {
    if(indexItem == null) {
      return;
    }

    items[relativePath.toMapKey()] = indexItem;

    updateContentId(lastContentId);
  }

  Future<void> addFile(FilePath relativePath, File file, String oid, String? lastContentId) async {
    add(relativePath, await IndexItem.fromFile(file, oid), lastContentId);
  }

  IndexItem? get(FilePath relativePath) {
    return items[relativePath.toMapKey()];
  }

  // make sure the pathStr is unix styled
  IndexItem? getByPathStr(String pathStr) {
    return items[pathStr];
  }

  void set(FilePath relativePath, IndexItem indexItem, String? lastContentId) {
    setByPathStr(relativePath.toMapKey(), indexItem, lastContentId);
  }

  // make sure the pathStr is unix styled
  void setByPathStr(String pathStr, IndexItem indexItem, String? lastContentId) {
    items[pathStr] = indexItem;
    updateContentId(lastContentId);
  }

  bool contains(FilePath filePath) {
    return items.containsKey(filePath.toMapKey());
  }

  // void shallowCopyFrom(Index other) {
  //   version = other.version;
  //   items = other.items;
  // }

  int length() {
    return items.length;
  }

  @override
  String toString() {
    if(items.length < 30) {
      return 'Index{version: $version, contentId: $contentId, items.length: ${items.length}, items: $items}';
    }else {
      return 'Index{version: $version, contentId: $contentId, items.length: ${items.length}}';
    }
  }


}


@myJsonSerializable
class IndexItem implements JsonByteStream {
  // 字段名占长度啊，所以整短点
  // 单位 毫秒
  int mTimeMs;
  bool isDir;
  int len;
  // 这个字段理论上是需要的，但实际上检测修改时间和大小，
  // 效率更高，不过准确性不加，暂时只存上这个字段，先不用
  // 注：这个不是单纯算出的文件hash，这个是和keyData拼接算出的oid，
  // 和objects目录下的目录名是对应的，是文件oid，如果要校验，也要同keyData去算，
  // 不能直接拿文件算
  String oid;


  factory IndexItem.fromJson(Map<String, dynamic> json) => _$IndexItemFromJson(json);

  Map<String, dynamic> toJson() => _$IndexItemToJson(this);


  IndexItem({this.mTimeMs = 0, this.isDir = false, this.len = 0, this.oid = ''});

  IndexItem copyWith({
    int? mTimeMs,
    bool? isDir,
    int? len,
    String? oid,
  }) {
    return IndexItem(
      mTimeMs: mTimeMs ?? this.mTimeMs,
      isDir: isDir ?? this.isDir,
      len: len ?? this.len,
      oid: oid ?? this.oid,
    );
  }

  static Future<IndexItem?> fromFile(File file, String oid) async {
    if(!await file.exists()) {
      return null;
    }

    final indexItem = IndexItem();
    indexItem.mTimeMs = (await file.lastModified()).millisecondsSinceEpoch;
    indexItem.len = await file.length();
    // indexItem.oid = oid;
    indexItem.oid = "";  // 由于并不用这个字段，所以不设置了
    return indexItem;
  }

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

  Future<bool> matchFile(File file) async {
    // 这其实很微妙，首先，index目前只记录文件，所以isDir总是假，其次，目前只在forEach本地目录
    // 时调用这个函数，因此file总是存在，所以不需要在这判断文件是否存在，
    // 那么问题来了：如果文件不存在是该当作match还是不match？
    // return !isDir && (await file.lastModified()).millisecondsSinceEpoch == mTimeMs && (await file.length()) == len;
    return (await file.lastModified()).millisecondsSinceEpoch == mTimeMs && (await file.length()) == len;
  }

  // static Future<IndexItem?> fromDir(Directory item) async {
  //   if(!await item.exists()) {
  //     return null;
  //   }
  //
  //   final indexItem = IndexItem();
  //   indexItem.mTimeMs =  (await item.stat()).modified.millisecondsSinceEpoch;
  //   indexItem.len = 0;
  //   indexItem.isDir = true;
  //   return indexItem;
  // }

  @override
  String toString() {
    return 'IndexItem{mTimeMs: $mTimeMs, isDir: $isDir, len: $len, oid: $oid}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is IndexItem && runtimeType == other.runtimeType &&
              mTimeMs == other.mTimeMs && isDir == other.isDir &&
              len == other.len && oid == other.oid;

  @override
  int get hashCode => Object.hash(mTimeMs, isDir, len, oid);


}
