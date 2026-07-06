import 'dart:io';
import 'dart:isolate' show TransferableTypedData;
import 'dart:typed_data';

import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart';

import '../../cons.dart';

// 主要两个用途：
// 1 计算hash时，若小，直接在内存；否则先拷贝再计算
// 2 用做File和字节数组的通用容器
class VirtualFile {
  // 单个Isolate，最多缓存多少字节的数据，
  // 由于sync时会创建8个Isolate，
  // 而且Isolate间无法共享内存，因此这个数应该用*8来考虑
  // 如果上传文件比计算hash快（消费快于生产），则并不需要这个限制，但是，
  // 实际上计算hash比上传文件快很多，所以若不限制，可能积压内存会上百兆导致app崩溃(电脑一般不会崩，手机会)
  // 单位：字节
  static const int maxBufSize = 5242880;  // 5MiB，*8=40MiB，所有Isolate最多占用40MiB
  // 当前线程已缓存的数据大小，main线程由于此值会复用，所以每次使用VirtualFile前，应重置此值为0，子Isolate一般不会复用，所以无所谓
  static int _bufferedDataSize = 0;

  static const maxElementSize = 4194304;  // 4*1024*1024 = 4MiB，单位：字节

  String? dataFilePath;  //用字符串而不是File，因为字符串更容易跨Isolate传输
  Uint8List? dataBuf;
  String workdirBasePath = "";
  String workdirFilePath = "";
  int dataLen = 0;

  // main线程应在每次使用VirtualFile前重置此值；子线程若复用，也需要重置此值（计算hash时不用重置）
  static reset() {
    _bufferedDataSize = 0;
  }

  static Future<VirtualFile> ofBytes(Uint8List dataBytes) async {
    final it = VirtualFile();
    it.dataBuf = dataBytes;
    it.dataLen = dataBytes.length;
    return it;
  }

  static Future<VirtualFile> ofFile(String path) async {
    final it = VirtualFile();
    it.dataFilePath = path;
    it.dataLen = await File(path).length();
    return it;
  }


  // 小文件直接存内存，大文件存硬盘
  static Future<VirtualFile> fromWorkdirFile(final String workdirBasePath, final File workdirFile, final TempDir tempDir) async {
    final it = VirtualFile();
    it.workdirBasePath = workdirBasePath;
    it.workdirFilePath = workdirFile.absolute.path;
    final workdirFileSize = await workdirFile.length();
    final newSize = workdirFileSize + _bufferedDataSize;
    // 单元素大小超了或者总大小超了就存文件，否则存内存
    if(workdirFileSize > maxElementSize || newSize > maxBufSize) {
      final copiedFile = await tempDir.createWorkdirFileCopy(workdirBasePath, it.workdirFilePath);
      it.dataFilePath = copiedFile.absolute.path;
      it.dataLen = await copiedFile.length();
    }else {
      final bb = BytesBuilder(copy: false);
      await for(final b in workdirFile.openRead()) {
        bb.add(b);
      }

      it.dataBuf = bb.takeBytes();
      it.dataLen = it.dataBuf!.length;
      _bufferedDataSize += it.dataLen;  // 用拷贝到内存的准确的文件大小，而不是之前计算的（因为若用之前计算的，有很小概率之前计算后用户修改了文件，导致大小不一致）
    }

    return it;
  }

  // workdirFilePath 是工作目录下的文件的完整路径，例如 C:/repo1/abc.txt，不是在workdir下的相对路径
  static Future<VirtualFile> fromWorkdirPath(final String workdirBasePath, final String workdirFilePath, final TempDir tempDir) {
    return fromWorkdirFile(workdirBasePath, File(workdirFilePath), tempDir);
  }

  FilePath relativePath() {
    return FilePath.genRelativePath(workdirBasePath, workdirFilePath);
  }

  Future<String> hashWithKeyData(KeyData contentKeyData) {
    // 若buf不为null，优先使用buf
    // 这个有可能在子isolate计算，传不了中断函数，妈的，这个隔离模型真是狗屎，若用户在计算大文件的hash，有可能卡住
    // 比如，用户调用了repo status，然后有个大文件，计算半天，用户返回，这时，只有等到计算完毕才能执行同步，因为锁被占用了
    // 不过也能改成让status不占用锁，但也有问题，有可能导致两个isolate针对同一文件在计算hash
    if(dataBuf != null) {
      return hashBytesToHexWithKeyDataForSync(bytes: dataBuf!, contentKeyData: contentKeyData, throwIfInterrupted: null);
    }else {
      return hashFileToHexWithKeyDataForSync(filePath: File(dataFilePath!).absolute.path, contentKeyData: contentKeyData, throwIfInterrupted: null);
    }
  }

  Future<void> clear() async {
    // 如果是存内存的数据，clear时减去buffered data size
    if(dataBuf != null) {
      _bufferedDataSize -= dataLen;
      if(_bufferedDataSize < 0) {
        throw AppException("virtual file buffered size less than 0");
      }
    }


    // 重置字段
    dataBuf = null;
    dataFilePath = null;
    workdirBasePath = "";
    workdirFilePath = "";
    dataLen = 0;
  }

  Future<int> length() async {
    return dataLen;
  }

  Stream<List<int>> dataStream() async* {
    if(dataBuf != null) {
      yield dataBuf!;
    }else {
      yield* File(dataFilePath!).openRead();
    }
  }

  // 注：转移到map后这个实例就不能用了
  Future<List<dynamic>> toTransferableList() async {
    // 可以添加null
    final list = <dynamic>[];

    list.add(dataBuf != null ? TransferableTypedData.fromList([dataBuf!]) : null);
    list.add(dataFilePath);
    list.add(workdirBasePath);
    list.add(workdirFilePath);
    list.add(dataLen);

    // 转移之后这个就不能用了，转移之后没有再用的需求，所以可直接clear()，
    // 若有复用需求，可添加变量控制是否clear()（正常来说，除非代码写错，否则没必要在转移后再用这个virtual file实例）
    await clear();
    return list;
  }

  static VirtualFile fromTransferableList(List<dynamic> list) {
    final it = VirtualFile();
    final TransferableTypedData? dataBuf = list[0];
    if(dataBuf != null) {
      it.dataBuf = dataBuf.materialize().asUint8List();
    }

    it.dataFilePath = list[1];
    it.workdirBasePath = list[2];
    it.workdirFilePath = list[3];
    it.dataLen = list[4];

    // 这个size应该不会超过 maxBufSize*8（当前线程限制最大buf大小*线程数量）
    _bufferedDataSize += it.dataLen;

    return it;
  }

  // 最多读取 n bytes
  Future<List<int>> readNBytes(int n) async {
    if(n < 1) {
      return const [];
    }

    final len = await length();
    if(len < 1) {
      return const [];
    }

    // 执行到这，len 和 n 必然大于或等于1
    // 由于len和n必然大于等于1，因此，maxN必然大于等于1
    final maxN = len < n ? len : n;

    if(dataBuf != null) {
      return dataBuf!.sublist(0, maxN);
    }else {
      final bb = BytesBuilder(copy: false);
      await for(final b in File(dataFilePath!).openRead(0, maxN)) {
        bb.add(b);
      }
      return bb.takeBytes();
    }
  }

  Future<List<int>> getMagic({final int magicLen = Cons.magicLen}) {
    return readNBytes(magicLen);
  }
}
