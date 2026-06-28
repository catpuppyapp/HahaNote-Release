import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart' show App;
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_path.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/repo.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/utils.dart' show getANonexistFilePathUnderDir, getAndMakeSureDirExists, getFileAndMakeSureParentDirExist;
import 'package:path/path.dart' as p show join;


const _TAG = "temp_dir.dart";

/// 目录结构示例：
/// base:
///   files: 对应 remote/files ，缓存file info文件
///   objects：对应 remote/objects，缓存对象文件
///   workdir：对应用户的工作目录，需要创建工作目录文件拷贝时，存到这
class TempDir {
  Directory base;

  /// 用来存用户workdir下的数据，通常在仓库根目录，没这个目录，缓存的时候单独建一个
  /// 注意：这个目录结构是扁平的，不保持原workdir目录下的目录结构，文件名也是随机生成的
  /// 比如workdir有个文件路径是 abc/def/123.txt ，可能存储在 tempDir/workdir/abcdef123.temp
  /// 另外：与此相对，syncCache/workdir的目录结构不是扁平的，
  /// 而是和真正的workdir的相对路径是一样的，例如真正的文件在 repo/abc.txt，那么在syncCache/workdir的路径则为syncCache/workdir/abc.txt
  final workdirName = Repo.workdirDirName;
  final tempDirName = 'temp';

  /// 由于dropbox等网盘的api限制每秒调用数，就算不限制，若文件多，例如1万个，发1万个http请求也不现实，
  /// 因此，上传文件先存到此目录，保持目录结构 oid/data.enc ，然后整理，合并，再上传，
  /// 这里的不是pfs文件和.pack文件，是和本地remote目录一样的 data.enc
  final pushCacheDirName = 'pushCache';

  /// 下载的pfs.enc文件和.pack文件会缓存到这里，若对应.pack存在，不会重复下载，直接从里面取数据即可
  final fetchCacheDirName = 'fetchCache';

  /// 待推送的pfs.enc和.pack文件会存到这里，最后推送，目前(20251212)并没有删除.pack文件的机制，.pack文件只能加不能减，
  /// 若把里面的数据全移除，会是空的.pack文件，但不会把文件本身删除，日后实现清理，会考虑怎么清理这东西
  /// 这个目录在 pushCache 下，整体路径为：tempDir/pushCache/willPush，推送前会把pushCache里的data.enc整理，然后打包成.pack放到这里再推送
  final willPushDirName = 'willPush';

  static Future<TempDir> create(String basePath, String prefix) async {
    return await fromDir(
      Directory(
        await getANonexistFilePathUnderDir(
          // 路径：仓库workdir路径/仓库数据目录路径/temp
          // 例如：abc/.haha_note/temp
          basePath,
          fileNamePrefix: '${prefix}_',
          fileNameSuffix: ''
        )
      )
    );
  }

  static Future<TempDir> fromDir(Directory dir) async {
    final result = TempDir._(base: dir);

    await result.base.create(recursive: true);

    return result;
  }


  // 下划线开头，私有化构造器，重点是下划线开头，其他名字也行，例如`TempDir._c()`也行
  TempDir._({required this.base});

  Future<Directory> objDir() async {
    return await getAndMakeSureDirExists(p.join(base.absolute.path, Repo.remoteObjectsDirName));
  }

  // 用户的workdir的文件创建拷贝时会存到这下面
  Future<Directory> workdir() async {
    return await getAndMakeSureDirExists(p.join(base.absolute.path, workdirName));
  }

  Future<Directory> filesDir() async {
    return await getAndMakeSureDirExists(p.join(base.absolute.path, Repo.remoteFilesDirName));
  }

  Future<Directory> msgDir() async {
    return await getAndMakeSureDirExists(p.join(base.absolute.path, Repo.remoteMsgDirName));
  }

  Future<Directory> tempDir() async {
    return await getAndMakeSureDirExists(p.join(base.absolute.path, tempDirName));
  }

  Future<Directory> pushCacheDir() async {
    return await getAndMakeSureDirExists(p.join(base.absolute.path, pushCacheDirName));
  }

  // 和正式remote/objects下路径的区别在于，这个路径是直接oid/data.enc，
  // 没按oid分组，原因如下:
  // 1 因为这个目录多数情况下是临时处理完就删了，不会长期累积很多文件，
  //   顶多一次性有很多（用户应该不会一次上传5万个文件吧？顶多2万个以内估计），然后处理完就删除了;
  // 2 因为单层oid，然后下面放data.enc，这样方便处理，不用递归扫描目录
  // tempDir/pushCache/objects/oid/data.enc
  Future<File> getObjectPathUnderPushCacheDir(String oidStr, {bool createParent = false}) async {
    final path = genObjPathForTempDir((await pushCacheDir()).absolute.path, oidStr);
    return createParent ? await getFileAndMakeSureParentDirExist(path) : File(path);
  }

  // basePath/objects/oid/data.enc
  static String genObjPathForTempDir(String basePath, String oidStr) {
    return p.join(basePath, Repo.remoteObjectsDirName, oidStr, Repo.remoteDataFileName);
  }

  // tempDir/pushCache/willPush
  // pushCache里的数据需要再整理下，合并，然后再推送，这个目录用来存放最终需要推送的文件
  // 其下有 objects|files|msg，里面分别存储对应数据的 pfs.enc和 .pack 文件
  Future<Directory> pushCacheWillPushDir() async {
    return await getAndMakeSureDirExists(p.join((await pushCacheDir()).absolute.path, willPushDirName));
  }

  Future<Directory> fetchCacheDir() async {
    return await getAndMakeSureDirExists(p.join(base.absolute.path, fetchCacheDirName));
  }



  /// x 废弃此方案，因为并发计算有可能拷贝错文件，改成完全按照workdir原path来拷贝了，这样并发安全，就是路径可能会长）把仓库的workdir的文件，拷贝到临时目录的workdir，但文件名会变成随机生成的“字符串.temp”，
  /// 这样是为了避免在workdir不同目录相同文件名拷贝到同一文件夹时发生冲突。
  /// 拷贝后，最终 tempDir/workdir 下会有类似 "123abc123a.temp" 这样的随机文件名。
  Future<File> createWorkdirFileCopy(String workdirBasePath, String workdirFileFullPath) async {
    final relativePath = FilePath.genRelativePath(workdirBasePath, workdirFileFullPath);
    final tempWorkdir = await workdir();
    final tempFileFullPath = p.join(tempWorkdir.absolute.path, relativePath.toString());
    final tempFile = await getFileAndMakeSureParentDirExist(tempFileFullPath);
    await File(workdirFileFullPath).copy(tempFileFullPath);
    return tempFile;
  }

  Future<void> clean() async {
    try {
      await base.delete(recursive: true);
    }catch(e, st) {
      App.logger.debug(_TAG, "#clean() err: basePath=${base.absolute.path}\nerr=$e\nst=$st");
    }
  }

  Future<File> createTempFile({String suffix=".temp"}) async {
    return File(await getANonexistFilePathUnderDir((await tempDir()).absolute.path, fileNameSuffix: suffix)).create(recursive: true);
  }

  // tempDir/fetchCache/objects/oid/data.enc
  Future<File> getObjectFileUnderObjectsDir(String oidStr) async {
    return await getFileAndMakeSureParentDirExist(genObjPathForTempDir((await fetchCacheDir()).absolute.path, oidStr));
  }

}
