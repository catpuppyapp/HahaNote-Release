import 'dart:convert' show jsonEncode, utf8, jsonDecode;
import 'dart:io' show File, Directory, IOSink;
import 'dart:typed_data';

import 'package:cloud_disk_note_app/cloud_disk_note/crypto/encrypt.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/crypto/key_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/remote.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/stream.dart' show JsonByteStream;
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/virtual_file.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/repo.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/temp/temp_dir.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/utils.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart' show VersionOid;
import 'package:cloud_disk_note_app/cloud_disk_note/time/time_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart';
import 'package:cloud_disk_note_app/ext/iterable_ext.dart';
import 'package:path/path.dart' as p show join;

part 'obj_pack.g.dart';

// 无条目时用-1替代索引，null替代值
// 返回false终止foreach
typedef ForEachPackItem = Future<bool> Function(ObjPackFileStorage storage, int packFileIndex, ObjPackFile? packFile, int packItemIndex, ObjPackItem? packItem);
// 返回true断言成功，无条目时也用-1和null替代，和foreach一样
typedef PredicatePackItem = ForEachPackItem;

// 150_000_000 Byte = 150 MB (按1000算的，不是按1024算的MiB）
// 153_600_000 是 150MiB，按1024算的
// const defaultEachPackMaxLenInBytes = 153_600_000;
// const defaultEachPackMaxLenInBytes = dropboxUploadMaxSizeInBytes;  // 限制在刚好够一个dropbox上传请求允许的最大值
const packFileNameExtension = ".pack";
// 这个会明文存到本地pushCache/objects|files|msg/oid 目录下，然后上传的时候存到加密的pfs.enc文件中
// const packItemExtraFileName = "extra.json";

const packFileMagic = [0xfa, 0x88, 0xce, 0x33, 0xeb, 0x9e, 0xd6, 0x25];


// `realPackFile` is real File, `packFile` is virtual file

/// oid+type 定位唯一一个数据库，目前type只有data，解压后的目录结构为item.oid为目录名，
/// 内部是不同类型的数据，例如 oid/data.enc，未来可能有 oid/info.enc
/// e.g. output json:
/// {
///   packMaxLen: 123,
///   packFiles: [
///     name: "0.pack",
///     len: 30000010,
///     hash: abcdefg12345,
///     items: [
///       {
///         oid: abc12321393,
///         type: "data",
///         offset: 0,
///         len: 10
///       },
///       {
///         oid: def12321393,
///         type: "data",
///         offset: 10,
///         len: 30000000
///       }
///    ],
///    name: "1.pack",
///     len: 500,
///     hash: gklcdefg12345,
///     items: [
///       {
///         oid: ghi12321393,
///         type: "data",
///         offset: 0,
///         len: 500
///       }
///    ]
/// }

@myJsonSerializable
class ObjPackFileStorage implements JsonByteStream {
  /// 类的版本号，或者理解为格式的版本号，或者理解为协议的版本号，若变化，数据结构可能不同
  /// 注：这个不是指示内容是否修改的版本号，contentId才是
  int ver;
  /// RemoteDataType的pfsType之一，用来指示这个pfs是存的什么数据
  String type;
  /// 每个pack文件，最大限制数，单位字节
  /// 最大的情况下，文件大小可能接近双倍此值，例如限制30mb，
  /// 文件大小现在是29mb，然后追加了一个29mb的文件，这时，就58mb了。
  /// 如果文件大小超过或等于此限制，直接打包到单独文件，否则合并到小的包里
  /// 这个大小可调，但最小值不能小于默认值，太小的话，文件会很零散，数量多时容易触发网盘的每秒下载量限制
  // @Deprecated("改成在查找合适的pack file时，从AppConfig读取，这个值不应该放到实例属性，因为一写入文件，下次从pfs文件里读取，就绕过config了，改config中的对应值就无效了")
  // int packMaxLen;

  List<ObjPackFile> packFiles;

  /// 若变化，说明数据有变化
  String contentId;

  ObjPackFileStorage({this.ver = 1, String? type, List<ObjPackFile>? packFiles, String? contentId})
  : type = type ?? RemoteDataType.objectsPfs.value,
    // 这个参数没用了，使用的时候查配置
    // packMaxLen = packMaxLen ?? SyncConfig.getConfig().packFileMaxLenInBytes,
    packFiles = packFiles ?? [],
    contentId = contentId ?? newContentId()
  ;


  factory ObjPackFileStorage.fromJson(Map<String, dynamic> json) => _$ObjPackFileStorageFromJson(json);

  Map<String, dynamic> toJson() => _$ObjPackFileStorageToJson(this);

  @override
  Stream<List<int>> toJsonByteStream() async* {
    yield utf8.encode(jsonEncode(toJson()));
  }

  static Future<ObjPackFileStorage> fromJsonByteStream(Stream<List<int>> byteStream) async {
    return ObjPackFileStorage.fromJson(jsonDecode(await getJsonStrFromByteStream(byteStream)));
  }

  static Future<ObjPackFileStorage> decrypt(KeyData contentKeyData, File file) async {
    final encryptedData = await EncryptedData.readFromFile(file);
    final rawData = await encryptedData.decryptThenUncompress(contentKeyData);

    return await fromJsonByteStream(rawData);
  }

  /// e.g. '0.pack'
  static String genPackName(int index) {
    return "$index$packFileNameExtension";
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

  // 若有重复PackItem，throw
  Future<void> throwIfHaveDuplicationOrPackFileLengthLessThan0({required String errCode}) async {
    final Set<String> set = {};
    await forEachPackItem(
      (storage, packFileIndex, packFile, packItemIndex, packItem) async {
        if(packFile == null || packItem == null) {
          return true;
        }

        if(packFile.len < 0) {
          throw AppException("pack file length less than 0, length: ${packFile.len}, pack file name: ${packFile.name}, err code: $errCode");
        }

        if(set.contains(packItem.oid)) {
          throw AppException("objects have duplication in pack file, item oid '${packItem.oid}', pack file name: ${packFile.name}, err code: $errCode");
        }

        set.add(packItem.oid);

        // continue foreach
        return true;
      }
    );
  }

  Future<void> forEachPackItem(
    // 返回false终止foreach
    // 如果无条目，索引传-1，值传null
    ForEachPackItem forEach
  ) async {
    if(packFiles.isEmpty) {
      await forEach(this, -1, null, -1, null);
      return;
    }

    for(final (packFileIndex, packFile) in packFiles.indexed) {
      if(packFile.items.isEmpty) {
        if(!await forEach(this, packFileIndex, packFile, -1, null)) {
          return;
        }
      }

      for(final (packItemIndex, packItem) in packFile.items.indexed) {
        if(!await forEach(this, packFileIndex, packFile, packItemIndex, packItem)) {
          return;
        }
      }
    }
  }

  // Future<void> removeItemFromPackFile(PackFindResult findResult, File realPackFile, TempDir tempDir) async {
  //   await ObjPackFile.throwIfIsNotPackFile(realPackFile, 12806083);
  //
  //   final packFile = findResult.packFile!;
  //   final packItemIndex = findResult.packItemIndex;
  //   final targetLen = findResult.packItem!.len;
  //
  //   final tempFile = await tempDir.createTempFile();
  //   final tempFileIoSink = tempFile.openWrite();
  //   await ObjPackFile.initIoSink(tempFileIoSink, close: false);
  //   var writtenCount = packFileMagic.length;
  //
  //   var found = false;
  //   for(final (itemIdx, item) in packFile.items.indexed) {
  //     if(itemIdx != packItemIndex) {
  //       final data = ObjPackFile.getItemData(realPackFile, item);
  //       await tempFileIoSink.addStream(data);
  //       writtenCount += item.len;
  //
  //       if(found) {
  //         // 这个调整的是相对偏移量，用item.offset是对的，不应该使用baseOffset
  //         item.offset -= targetLen;
  //
  //         if(item.offset < 0) {
  //           throw AppException("pack item offset less than 0, must something wrong! offset = ${item.offset}, err code: 14388860");
  //         }
  //       }
  //     }else {
  //       found = true;
  //     }
  //
  //   }
  //
  //   await tempFileIoSink.close();
  //
  //   final srcFileLen = await realPackFile.length();
  //   final expectedLen = srcFileLen - targetLen;
  //   if(writtenCount != expectedLen) {
  //     final newFileLen = await tempFile.length();
  //     final packFileLenWithHeader = packFile.lenWithHeader();
  //     throw AppException("pack file length incorrect: srcFileLen: $srcFileLen, targetLen: $targetLen, expectedLen: $expectedLen, packFileLenWithHeader(should be equals to srcFileLen): $packFileLenWithHeader, but got writtenCount: $writtenCount, newFileLen: $newFileLen");
  //   }
  //
  //   await tempFile.rename(realPackFile.absolute.path);
  //
  //   packFile.items.removeAt(packItemIndex);
  //   // 逻辑长度，不用算二进制文件的magic
  //   packFile.len -= targetLen;
  //
  //
  //   if(packFile.len < 0) {
  //     throw AppException("pack file length - targetLen, result less than 0, must something wrong! pack file len after subtracted = ${packFile.len}, targetLen = $targetLen, err code: 18648665");
  //   }
  //
  //   updateContentId();
  // }

  // 好像并没有写入pack文件后再调用find的需求，所以这里不需要更新find result map，若调用这个再使用旧版contentId相关的find result map，会抛异常
  Future<void> _writeDataToPackFile(
    ObjPackFile packFile,
    VersionOid oid,
    File realPackFile,
    VirtualFile dataFile,
    String lastContentId, {
    PackItemType? packItemType,
    // required Set<ObjRef> refs,
    required int refsCount,
    Map<String, dynamic>? extraForPackItem,
  }) async {
    if(refsCount < 1) {
      throw AppException("can't add an obj without ref count, obj oid is '$oid', refsCount is '$refsCount', err code: 15882920");
    }

    await ObjPackFile.throwIfIsNotPackFile(realPackFile, 13759979);

    // if(await dataFile.length() < 1) {
    //   throw AppException("disallow add empty file to pack, err code: 14157314");
    // }

    if(!listEquals(EncryptedData.magic, await dataFile.getMagic())) {
      throw AppException("disallow to add non-encrypted file to pack, err code: 11709516");
    }

    final packItemType2 = packItemType ?? PackItemType.data;

    // append data
    await appendStreamToFile(realPackFile, dataFile.dataStream());

    // 创建新条目
    final packItem = ObjPackItem(rc: refsCount);
    if(extraForPackItem != null && extraForPackItem.isNotEmpty) {
      packItem.extra.addAll(extraForPackItem);
    }

    // if(refs.isNotEmpty) {
    //   packItem.addAllRefs(refs);
    // }

    packItem.oid = oid.value;
    packItem.type = packItemType2.value;
    packItem.offset = packFile.len;
    packItem.len = await dataFile.length();

    // update pack
    packFile.items.add(packItem);
    packFile.len += packItem.len;

    final realPackFileLen = await realPackFile.length();
    final packFileLenWithHeader = packFile.lenWithHeader();
    if(realPackFileLen != packFileLenWithHeader) {
      final dataFileLen = await dataFile.length();
      throw AppException("realPackFileLen != packFileLenWithHeader: realPackFileLen=$realPackFileLen, packFileLenWithHeader=$packFileLenWithHeader, dataFileLen=$dataFileLen, err code: 16159580");
    }
    // packFile.hash = await hashStreamToHexStr(realPackFile.openRead());

    updateContentId(lastContentId);
  }

  /// 把文件的数据追加到packFile里
  Future<void> appendDataToPackFile(int packFileIndex, VersionOid oid, File realPackFile, VirtualFile dataFile, String lastContentId, {PackItemType? packItemType, required int refsCount, Map<String, dynamic>? extraForPackItem}) async {
    final packFile = packFiles[packFileIndex];

    await _writeDataToPackFile(packFile, oid, realPackFile, dataFile, lastContentId, packItemType: packItemType, refsCount: refsCount, extraForPackItem: extraForPackItem);
  }

  /// 新增一个packFile条目，并把数据写入到对应路径
  /// 会把文件存到saveTo目录下，例如saveTo等于 pushCache/willPush/files，且当前packFiles.length为12，
  /// 则新增的文件可能为 pushCache/willPush/files/12.pack
  Future<File> addPackFile(VersionOid oid, Directory saveTo, VirtualFile dataFile, String lastContentId, {PackItemType? packItemType, required int refsCount, Map<String, dynamic>? extraForPackItem}) async {
    final newFileName = genPackName(packFiles.length);
    final packFile = ObjPackFile(name: newFileName);
    final newPackFile = File(p.join(saveTo.absolute.path, newFileName));
    if(await newPackFile.exists() && (await newPackFile.length()) > 0) {
      throw AppException("target file: '${newPackFile.absolute.path}' already exists and is not empty!, err code: 11004040");
    }

    await ObjPackFile.initFile(newPackFile);

    await _writeDataToPackFile(packFile, oid, newPackFile, dataFile, lastContentId, packItemType: packItemType, refsCount: refsCount, extraForPackItem: extraForPackItem);

    packFiles.add(packFile);

    return newPackFile;
  }

  Future<bool> contains(VersionOid oid, {PackItemType? packItemType, required FindResultMap findResultMap}) async {
    final result = await find(oid, packItemType: packItemType, findResultMap: findResultMap);
    return result.foundItem();
  }

  Future<PackFindResult> find(VersionOid oid, {PackItemType? packItemType, required FindResultMap findResultMap}) async {
    if(findResultMap.contentId != contentId) {
      throw AppException("find result map content id and obj pack content id didn't match, err code: 16286847");
    }

    final packItemType2 = packItemType ?? PackItemType.data;
    final result = findResultMap.data[oid.value];
    if(result == null || result.packItem!.type != packItemType2.value) {
      // null或type不同，返回空结果，代表未找到（其实type目前无用，20260310）
      return PackFindResult.notFound();
    }

    // 非null，且type相等，且oid相等
    return result;

    // return await findByPredication(
    //   (storage, packFileIndex, packFile, packItemIndex, packItem) async {
    //     if(packItem == null) {
    //       return false;
    //     }
    //
    //     return packItem.oid == oid.value && packItem.type == packItemType2.value;
    //   }
    // );
  }

  /// 如果找不到，则调用add追加一个新的PackFile，否则，将数据追加到返回的条目中。
  Future<PackFindResult> findAFileLessThanMaxLen(int fileLen, {required int packMaxLen}) async {
    // x 废弃，应该优先把文件添加到大小为0的pack中，而不是新建）超过大小的，单独建个pack
    // if(fileLen >= packMaxLen) {
    //   return null;
    // }

    // final packMaxLen = packMaxLenParam ?? getPackMaxLenFromConfig();

    for(final (packFileIndex, packFile) in packFiles.indexed) {
      if(packFile.len == 0 || (packFile.len + fileLen) <= packMaxLen) {
        return PackFindResult(packFileIndex: packFileIndex, packFile: packFile);
      }
    }

    return PackFindResult.notFound();

    // 如果找不到，单独建pack，否则可以下载然后塞到这个packFile里
    // return findByPredication(
    //   (storage, packFileIndex, packFile, packItemIndex, packItem) async {
    //     // 如果等于null说明一个.pack文件都没有，应该当作没找到，然后创建第一个pack文件(0.pack)
    //     if(packFile == null) {
    //       return false;
    //     }
    //
    //     // 如果不加，会两倍大小，也行，但是packMaxLen的设置就不那么符合直觉了，
    //     // 不过就算加了文件大小意义也不大，因为如果文件大小超了maxLen，单独一个.pack，
    //     // 其实还是会很大，拆分太麻烦，所以不拆了
    //     // 空 .pack 文件或者能合并到现有文件中，则返回true
    //     return packFile.len == 0 || (packFile.len + fileLen) <= packMaxLen;
    //   }
    // );
  }

  /// 单位字节
  /// 比如下载了一个pack，然后想追加数据，先调用此函数，若能追加则追加，
  /// 不能则调用findAFileLessThanMaxLen()，若能找到，则下载对应文件，追加，上传，若找不到合适条目，则调用addPackFile创建一个新的条目
  // bool canAppendDataToThisFile(
  //   ObjPackFile packFile, {
  //   required int dataLen,
  //   required int packMaxLen,
  // }) {
  //   return packFile.len + dataLen <= packMaxLen;
  // }

  Future<PackFindResult> findByPredication(PredicatePackItem predication) async {
    PackFindResult result = PackFindResult();
    await forEachPackItem(
      (storage, packFileIndex, packFile, packItemIndex, packItem) async {
        if(await predication(storage, packFileIndex, packFile, packItemIndex, packItem)) {
          result.packFileIndex = packFileIndex;
          result.packFile = packFile;
          result.packItemIndex = packItemIndex;
          result.packItem = packItem;

          // break foreach
          return false;
        }

        // continue foreach
        return true;
      }
    );

    return result;
  }

  Future<void> extractByPredication(
    Directory packFilesDir,
    Directory outputDir, {
    /// 为ture, predication匹配多次，否则只匹配一次
    required bool matchOnce,
    required bool Function(ObjPackItem) predication,
  }) async {
    await forEachPackItem(
      (storage, packFileIndex, packFile, packItemIndex, packItem) async {
        if(packFile == null || packItem == null) {
          // return true，继续foreach
          return true;
        }

        if(predication(packItem)) {
          final realPackFile = File(p.join(packFilesDir.absolute.path, packFile.name));
          // 不一定下载所有packs，所以可能对应文件不存在
          if(!await realPackFile.exists()) {
            return !matchOnce;
          }

          // 不是有效的pack文件，跳过
          if(!await ObjPackFile.isPackFile(realPackFile)) {
            return !matchOnce;
          }

          // e.g. outputDir is objects will got `objects/oid/data.enc`
          final targetFile = await getFileAndMakeSureParentDirExist(p.join(outputDir.absolute.path, packItem.oid, PackItemType.getFileNameByType(packItem.type)));
          await extractFromPackFile(realPackFile, packItem, targetFile);

          return !matchOnce;
        }

        return true;
      }
    );
  }

  Future<void> extractFromPackFile(File realPackFile, ObjPackItem packItem, File targetFile) async {
    await ObjPackFile.throwIfIsNotPackFile(realPackFile, 16900527);

    final dataStream = ObjPackFile.getItemData(realPackFile, packItem);
    await writeStreamToFile(targetFile, dataStream);
  }

  /// 解压oid对应的数据到file
  /// [packFilesDir] pack file存储目录
  Future<void> extractTo(VersionOid oid, Directory packFilesDir, Directory outputDir, {PackItemType? packItemType}) async {
    final packItemType2 = packItemType ?? PackItemType.data;

    await extractByPredication(
      packFilesDir,
      outputDir,
      matchOnce: true,
      predication: (packItem) {
        return packItem.oid == oid.value && packItem.type == packItemType2.value;
      }
    );
  }


  /// 解压所有文件到目录，目录结构按oid分组，例如 oid/data.enc
  Future<void> extractAllTo(Directory packFilesDir, Directory outputDir) async {
    await extractByPredication(
      packFilesDir,
      outputDir,
      matchOnce: false,
      predication: (packItem) {
        return true;
      }
    );
  }

  Future<FindResultMap> toFindResultMap() async {
    final frm = FindResultMap();
    frm.contentId = contentId;

    await forEachPackItem(
      (storage, packFileIndex, packFile, packItemIndex, packItem) async {
        if(packItem != null) {
          frm.data[packItem.oid] = PackFindResult(
            packFileIndex: packFileIndex,
            packFile: packFile,
            packItemIndex: packItemIndex,
            packItem: packItem
          );
        }

        return true;
      }
    );

    return frm;
  }

  // fastRemoveIfPossible 若为真，当 findResults 集合数量和packFile的items数量相等时，
  // 不会直接包含检测，直接跳过所有，调用者可先设置此值为真，若失败，
  // 可能findResults集合可能有误，但不一定数据有误；再设置为假再执行一次，若还失败，则数据有误，应抛出异常
  Future<void> removeItemsFromPackFile(
    // 此函数不应该修改这个集合，否则先调用fast若失败再禁用fast，执行结果会出错
    final Set<PackFindResult> findResults,
    File realPackFile,
    TempDir tempDir,
    String lastContentId, {
    bool fastRemoveIfPossible = false
  }) async {
    if(findResults.isEmpty) {
      return;
    }

    // 从文件里删除条目，然后把剩余的数据重新写入到file
    await ObjPackFile.throwIfIsNotPackFile(realPackFile, 14002490);

    final tempFile = await tempDir.createTempFile();
    final tempFileIoSink = tempFile.openWrite();
    await ObjPackFile.initIoSink(tempFileIoSink, close: false);
    var writtenCount = packFileMagic.length;
    var deletedCount = 0;

    final packFile = findResults.first.packFile!;
    final List<ObjPackItem> newItems = [];

    final maybeIsRemoveAll = findResults.length == packFile.items.length;
    // 删除所有条目，这里假设要删除一定在packFile中并且无重复
    if(fastRemoveIfPossible && maybeIsRemoveAll) {
      // 直接检查大小，如果待删除集合条目数和总条目数相同，则直接删除所有
      for(final item in findResults) {
        // 统计这个数量是为了后面比较下删除的数据大小是否和期望相等，若不相等则抛异常，
        // 能在一定程度上避免数据出错 (但若偶然数量匹配，则还是会出错)
        deletedCount += item.packItem!.len;
      }
    }else {
      // 逐个检查是否存在于待删除集合
      int lastOffset = 0;
      for(final item in packFile.items) {
        // 在待删除的条目列表则跳过，不写入新文件
        if(findResults.firstWhereOrNull((it) => it.packItem!.oid == item.oid) != null) {
          deletedCount += item.len;
          continue;
        }

        // 把没删除的写入到文件
        final data = ObjPackFile.getItemData(realPackFile, item);
        await tempFileIoSink.addStream(data);
        writtenCount += item.len;
        newItems.add(item.copy(newOffset: lastOffset));
        lastOffset += item.len;
      }
    }

    await tempFileIoSink.flush();
    await tempFileIoSink.close();

    final srcFileLen = await realPackFile.length();
    final expectedLen = srcFileLen - deletedCount;
    if(writtenCount != expectedLen) {
      final newFileLen = await tempFile.length();
      final packFileLenWithHeader = packFile.lenWithHeader();
      throw AppException("pack file length incorrect: srcFileLen: $srcFileLen, deletedCount: $deletedCount, expectedLen: $expectedLen, packFileLenWithHeader(should be equals to srcFileLen): $packFileLenWithHeader, but got writtenCount: $writtenCount, newFileLen: $newFileLen, err code: 12741933");
    }

    await tempFile.rename(realPackFile.absolute.path);

    packFile.items = newItems;
    // 逻辑长度，不用算二进制文件的magic
    packFile.len = writtenCount - packFileMagic.length;


    if(packFile.len < 0) {
      throw AppException("pack file length - targetLen, result less than 0, must something wrong! pack file len after subtracted = ${packFile.len}, deletedCount = $deletedCount, err code: 19512465");
    }

    updateContentId(lastContentId);
  }
}

@myJsonSerializable
class ObjPackFile {
  int ver;
  /// 关联的实际的文件的名字，0.pack 1.pack 之类的
  final String name;
  /// 所有数据的总长度，不包含二进制文件header字节数（例如magic，就属于header，其大小是不包含在内的）
  int len;
  
  /// 下载数据时，下载清单，如果本地有对应文件，验证下hash是否匹配，若匹配，不需要重新下载文件，
  String hash;
  
  List<ObjPackItem> items;


  ObjPackFile({this.ver = 1, this.name = '', this.len = 0, this.hash = '', List<ObjPackItem>? items})
  : items = items ?? [];


  factory ObjPackFile.fromJson(Map<String, dynamic> json) => _$ObjPackFileFromJson(json);

  Map<String, dynamic> toJson() => _$ObjPackFileToJson(this);

  static Future<void> initFile(File file) async {
    if(await file.exists() && await file.length() > 0) {
      throw AppException("file is not empty, can't init it to pack file");
    }

    await initIoSink(file.openWrite(), close: true);
  }
  
  static Future<void> initIoSink(IOSink sink, {required bool close}) async {
    sink.add(packFileMagic);

    if(close) {
      await sink.flush();
      await sink.close();
    }
  }

  static Future<bool> isPackFile(File file) async {
    if(await file.length() < packFileMagic.length) {
      return false;
    }

    final bb = BytesBuilder(copy: false);
    await for(final bytes in file.openRead(0, packFileMagic.length)) {
      bb.add(bytes);
    }

    final magicFromFile = bb.takeBytes();
    return listEquals(packFileMagic, magicFromFile);
  }

  int lenWithHeader() {
    return len + packFileMagic.length;
  }

  static Stream<List<int>> getItemData(File realPackFile, ObjPackItem item) {
    // 给偏移量加上文件的header字节长度
    final baseOffset = item.offset + packFileMagic.length;
    return realPackFile.openRead(baseOffset, baseOffset + item.len);
  }

  // code用来定位错误信息在代码中的位置，可以定位到调用者是谁
  static Future<void> throwIfIsNotPackFile(File realPackFile, int code) async {
    if(!await isPackFile(realPackFile)) {
      throw AppException("'${realPackFile.absolute.path}' is not a pack file, err code: $code");
    }
  }

  bool isEmpty() {
    return len < 1;
  }
}


@myJsonSerializable
class ObjPackItem {
  int ver;
  // 用oid+type来唯一定位一个数据块
  String oid;
  // value of PackItemType
  String type;

  /// bytes offset in pack file
  /// 偏移量从0开始，若文件有header（例如magic），自行计算偏移
  /// 从0开始的好处：方便迁移文件，即使文件header变化，offset也一直可用，相当于'相对路径'和'绝对路径'的区别
  int offset;
  /// data length in byte
  int len;

  /// create time
  TimeData ctime;

  // 整体引用数，为0时删除对象
  int rc;

  // 不要直接用这个，用相关方法
  // 一旦创建不要修改，因为以后可能会把obj pfs 映射成set以避免foreach查找条目来提升性能，
  // 如果修改这个，那么set和list关联的对象就不一样了，通过set查找再修改就无效了
  // 这个只记录被哪些对象引用，不记录引用数
  // final Set<ObjRef> refs;

  Map<String, dynamic> extra;

  ObjPackItem({this.ver = 1, this.oid = '', this.type = '', this.offset = 0, this.len = 0, this.rc = 0, TimeData? ctime,
    Set<ObjRef>? refs,
    Map<String, dynamic>? extra})
  : ctime = ctime ?? TimeData.now(),
    // refs = refs ?? {},
    extra = extra ?? {};

  factory ObjPackItem.fromJson(Map<String, dynamic> json) => _$ObjPackItemFromJson(json);

  Map<String, dynamic> toJson() => _$ObjPackItemToJson(this);

  void addRc([final int count = 1]) {
    rc+=count;
  }

  // 可以直接给addRc传负数
  // void delRc([final int count = 1]) {
  //   rc-=count;
  // }

  // void addRef(ObjRef ref) {
  //   if(!ObjRef.isInvalidOid(ref.oid)) {
  //     refs.add(ref);
  //   }
  // }


  // 调了这个函数后记得调用pfs.updateContentId()来更新pfs的contentId，不然可能不会上传文件
  // void addAllRefs(Iterable<ObjRef> refs) {
  //   for(final ref in refs) {
  //     addRef(ref);
  //   }
  // }

  // 目前只需要copy with new offset，其他有需要再添加
  ObjPackItem copy({int? newOffset}) {
    return ObjPackItem(
      ver: ver,
      oid: oid,
      type: type,
      offset: newOffset ?? offset,
      len: len,
      ctime: ctime,
      // refs: refs,
      rc: rc,
      extra: extra,
    );
  }

  // 把引用从object的引用集合移除（解引用）
  // 例如从回收站删除了某个文件，那么就需要将它关联的所有object都解引用
  // void removeAllRefs(Set<String> oldRefs) {
  //   refs.removeWhere((it) {
  //     // it.oid是object的oid
  //     // oldRefs里包含的是file info或msg的oid
  //     // 这个操作本质上是把file info或msg从其关联的object上解引用
  //     // 在删除file info或msg 或 删除file info节点时（file info历史记录超过限制，移除最旧的）会触发这个操作
  //     final contains = oldRefs.contains(it.oid);
  //     if(contains) {
  //       oldRefs.remove(it.oid);
  //     }
  //
  //     return contains;
  //   });
  // }

  // 这里的空指的是无file info或msg引用此obj，即此obj可物理删除了
  bool canDel() {
    return rc < 1;
  }
  //   for(final r in refs) {
  //     // 如果不小心关联上deleted或其他无效引用，则忽略
  //     if(!ObjRef.isInvalidOid(r.oid)) {
  //       // 进入这里，必然关联了有效oid，所以返回false，代表非空
  //       return false;
  //     }
  //   }
  //
  //   // refs为空集合或者只关联了无效oid（代码有bug才会关联这个，
  //   // 没检查，应该没bug，直接在这判断，无所谓了）
  //   return true;
  // }

}


class PackItemType {
  final String value;


  PackItemType(this.value);

  /// data.enc
  /// 目前 20251205，就这一个类型，除非真的有必要，否则不会添加其他类型，因为影响的地方太多
  static final data = PackItemType("data");
  static final allTypes = [data];

  static String getFileNameByType(String type, {String prefix = '', String? suffix}) {
    // 无后缀默认 .enc
    final suffix2 = suffix ?? Repo.encryptedFileSuffix;
    // e.g. data.enc
    return prefix + type + suffix2;
  }

  // 根据type获取文件名，例如type data，默认远程仓库对应的文件名为 data.enc
  String fileName({String prefix = '', String? suffix}) {
    return getFileNameByType(value);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is PackItemType && runtimeType == other.runtimeType &&
              value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    return value;
  }


}

class PackFindResult {
  /// 用 packFileIndex + packItemIndex可定位到一个具体的文件的数据块
  int packFileIndex;
  ObjPackFile? packFile;
  int packItemIndex;
  ObjPackItem? packItem;

  PackFindResult({this.packFileIndex = -1, this.packFile, this.packItemIndex = -1, this.packItem});

  static PackFindResult notFound() {
    return PackFindResult();
  }

  bool foundItem() {
    return packItem != null;
  }

  bool foundFile() {
    return packFile != null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is PackFindResult && runtimeType == other.runtimeType &&
              packFileIndex == other.packFileIndex &&
              packFile == other.packFile &&
              packItemIndex == other.packItemIndex &&
              packItem == other.packItem;

  @override
  int get hashCode =>
      Object.hash(packFileIndex, packFile, packItemIndex, packItem);

  @override
  String toString() {
    return 'PackFindResult{packFileIndex: $packFileIndex, packFile: $packFile, packItemIndex: $packItemIndex, packItem: $packItem}';
  }


}


@myJsonSerializable
class ObjRef {
  int type;
  String oid;
  // 如果item是file info，会存上其path，msg则不存
  String path;
  Map<String, dynamic> extra;


  // type 0 是无效类型，创建时，实际上此值必须指定
  ObjRef({this.type = 0, this.oid = '', this.path = '', Map<String, dynamic>? extra})
      : extra = extra ?? {};

  factory ObjRef.fromJson(Map<String, dynamic> json) => _$ObjRefFromJson(json);

  Map<String, dynamic> toJson() => _$ObjRefToJson(this);

  @override
  String toString() {
    return 'ObjRef{type: $type, oid: $oid, path: $path, extra: $extra}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ObjRef &&
              runtimeType == other.runtimeType &&
              oid == other.oid;

  @override
  int get hashCode => oid.hashCode;

  bool isWeak() {
    // 是否是弱引用，默认只有fileInfo是强引用，其他都是弱引用，
    // 删除object前，检测，只要不关联任何强引用，就可删除
    return ObjRefType.isWeakType(type);
  }


  // 如果是能关联到objMap，能删除的，返回真，否则返回假，（file info的oid或msg的oid返回真，否则假）
  // 也可用此方法判断是否是有效的可在本地删除或缓存的object oid
  static bool isInvalidOid(String? oid) {
    return oid == null || oid.isEmpty ||
        oid == VersionOid.deleted.value
        // || oid == VersionOid.dir.value
        || oid == VersionOid.repoLock.value;
  }

}

class ObjRefType {
  // 原本是用字符串的，但是，考虑到有可能会有很多objects，所以也会有很多ObjMapItem，
  // 如果用字符串，浪费空间，所以改用数字了，一个数字转成字符，固定1个字节（其实还是有点浪费）

  // 和目录名匹配，方便使用
  static final int fileInfo = 1;
  static final int msg = 2;
  // 这个好像没什么用？
  // static final String objects = "objects";

  static bool isWeakType(int type) {
    // return type != fileInfo && type != msg;
    // 暂时先禁用了
    return false;
  }

  static int fromRemoteDataType(RemoteDataType remoteDataType) {
    if(remoteDataType.value == RemoteDataType.files.value) {
      return fileInfo;
    }

    if(remoteDataType.value == RemoteDataType.msg.value) {
      return msg;
    }

    throw AppException("can't found ObjMapItemType for RemoteDataType: $remoteDataType");
  }
}


class FindResultMap {
  String contentId = "";

  // key 是obj oid
  // value 是find result
  Map<String, PackFindResult> data = {};

  @override
  String toString() {
    return 'contentId: $contentId, data: $data';
  }

}
