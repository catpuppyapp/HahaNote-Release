import 'dart:typed_data';

import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';

// 缓存小文件的object buffer，小文件直接在内存处理，无需落盘
class ObjBuf {
  // 单元素大小，避免一个大文件占满buf，导致多个小文件存到硬盘（硬盘，
  // 大量小文件读写（测硬盘io速度时，所谓的4K性能测的就是大量小文件读写实的性能），
  // 性能差；单个大文件读写，性能差别不大，所以，缓存同样大小的多个小文件到内存，要比缓存单个大文件性能提升明显）
  //单位 字节
  final int elementMaxSize;
  // buf总大小，超了就不存了，调用者自行放硬盘
  //单位 字节
  final int capacity;
  // key是oid；value是数据
  Map<String, Uint8List> storage = {};
  // 已经存了多少字节的数据
  int size = 0;

  // 单元素大小最大2MiB，总大小40MiB，注意，这个只是粗略限制，能保证差不多，但不能保证完全一致，
  // 因为文件流大小无法在读完文件流前得知，所以文件大小是根据压缩并加密前的原文件大小估算的，和压缩后的大小可能会有些差距
  // ObjBuf({this.elementMaxSize = 2097152, this.capacity = 41943040});  // 单元素最大大小2MiB
  ObjBuf({this.elementMaxSize = 4194304, this.capacity = 41943040});  // 单元素最大大小4MiB

  // 添加成功或集合中已有对应元素，返回true，否则返回false（例如超过容量大小，就会添加失败）
  Future<bool> addStream(
    VersionOid oid,
    Stream<List<int>> stream, {
    // 数据是否是不可变类型，例如 objects 是，file info 不是
    required bool isImmutable,
    // 加密数据精确大小在完全读取字节流前不确定，所以只是估计大小
    // 所以这个值是用原文件大小估计的值，可作参考，不会差太多
    required int estimateLen
  }) async {
    // 已添加对应对象，且对象是不可变的，就不用再添加了；若是可变的，则继续添加，新的覆盖旧的
    if(isImmutable && storage[oid.value] != null) {
      return true;
    }

    // 超过单元素大小了，不存了
    if(estimateLen > elementMaxSize) {
      return false;
    }

    // 超过buf总大小限制了，不存了（因为只是预估大小，所以只是有可能超，不是一定超了）
    final nextSize = estimateLen + size;
    if(nextSize > capacity) {
      return false;
    }

    // 把数据存到内存
    final bytes = await streamToBytes(stream);
    storage[oid.value] = bytes;
    size += bytes.length;  // 加上精确大小，而不是预估大小
    return true;
  }

  Future<void> clear() async {
    storage.clear();
    size = 0;
  }

  Uint8List? get(String oid) {
    return storage[oid];
  }
}
