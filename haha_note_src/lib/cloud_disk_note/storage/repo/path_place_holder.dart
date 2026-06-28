

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/remote.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_path.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/repo.dart';

const _TAG = "path_place_holder.dart";

// 注：replace的时候一律替换为unix style，恢复的时候，恢复成平台指定的style (主要是 /和\分隔符的区别）
class RepoPathPlaceHolder {
  // 仓库根目录/.CloudDiskNote 就是dataDir
  // repo data dir, e.g. .CloudDiskNote
  static final dataDir = ":data:";

  // local repo path or remote basePath
  static final base = ":base:";

  static final _baseFp = FilePath(value: [base]);
  static final _dataDirFp = FilePath(value: [dataDir]);

  // final workdirPrefix = "#workdir#";
  // final remoteFilesDirPrefix = "#remoteFiles#";
  // final remoteObjectsDirPrefix = "#remoteObjects#";
  // final remoteMsgDirPrefix = "#remoteMsg#";
  // final remotePfsFilesDirPrefix = "#remotePfsFiles#";
  // final remotePfsObjectsDirPrefix = "#remotePfsObjects#";
  // final remotePfsMsgDirPrefix = "#remotePfsMsg#";

  static void test() {
    final repoPath = r"C:\abc\repo";
    final repoDataDirPath = "$repoPath\\${Repo.dataDirName}";
    final repoSubPathUnderDataDir = "cache\\syncCache\\files\\abc.txt";
    final repoTargetPath = "$repoDataDirPath\\$repoSubPathUnderDataDir";


    App.printLogger.debug(_TAG, "_replacePrefixForStr(repoPath, repoDataDirPath, repoTargetPath): ${_replacePrefixForStr(repoPath, repoDataDirPath, repoTargetPath)}");
    App.printLogger.debug(_TAG, 'FilePath.fromString(dataDir+"/"+repoSubPathUnderDataDir).toUnixPathStr(): ${FilePath.fromString(dataDir+"/"+repoSubPathUnderDataDir).toUnixPathStr()}');


    if(FilePath.fromString(_restorePrefixForStr(repoPath, repoDataDirPath, _replacePrefixForStr(repoPath, repoDataDirPath, repoTargetPath))).toUnixPathStr() != FilePath.fromString(repoTargetPath).toUnixPathStr()) {
      throw AppException("repo path err, err code: 10526048");
    }

    if(_replacePrefixForStr(repoPath, repoDataDirPath, repoTargetPath) != FilePath.fromString(dataDir+"/"+repoSubPathUnderDataDir).toUnixPathStr()) {
      throw AppException("repo path err, err code: 18312263");
    }

    // 替换后的路径应该只有 unix path separator /
    if(!_replacePrefixForStr(repoPath, repoDataDirPath, repoTargetPath).contains("/")) {
      throw AppException("repo path err, err code: 13475429");
    }

    if(_replacePrefixForStr(repoPath, repoDataDirPath, repoTargetPath).contains("\\")) {
      throw AppException("repo path err, err code: 11875327");
    }

    final repoPath2 = "/abc/repos/my_repo";
    final repoDataDirPath2 = "$repoPath2/${Repo.dataDirName}";
    final repoTargetPath2 = "$repoDataDirPath2/cache/syncCache/files/abc.txt";

    if(FilePath.fromString(_restorePrefixForStr(repoPath2, repoDataDirPath2, _replacePrefixForStr(repoPath2, repoDataDirPath2, repoTargetPath2))).toUnixPathStr() != FilePath.fromString(repoTargetPath2).toUnixPathStr()) {
      throw AppException("repo path err, err code: 13542693");
    }

    final remoteBasePath = FilePath.fromUnixString("/repo");
    final remoteSubPath = "cache/syncCache/files/abc.txt";
    final remoteTargetPath = FilePath.fromUnixString("/repo/$remoteSubPath");


    App.printLogger.debug(_TAG, "_replacePrefixForFilePath(remoteBasePath, remoteTargetPath): ${_replacePrefixForFilePath(remoteBasePath, remoteTargetPath).toUnixPathStr()}");
    App.printLogger.debug(_TAG, 'FilePath.fromString(base+"/"+remoteSubPath).toUnixPathStr(): ${FilePath.fromString(base+"/"+remoteSubPath).toUnixPathStr()}');


    if(_restorePrefixForFilePath(remoteBasePath, _replacePrefixForFilePath(remoteBasePath, remoteTargetPath)) != remoteTargetPath) {
      throw AppException("remote path err, err code: 15098966");
    }

    if(_replacePrefixForFilePath(remoteBasePath, remoteTargetPath).toUnixPathStr() != FilePath.fromString(base+"/"+remoteSubPath).toUnixPathStr()) {
      throw AppException("remote path err, err code: 18840092");
    }

    // 替换后的路径应该只有 unix path separator /
    if(!_replacePrefixForFilePath(remoteBasePath, remoteTargetPath).toUnixPathStr().contains("/")) {
      throw AppException("remote path err, err code: 14474574");
    }

    if(_replacePrefixForFilePath(remoteBasePath, remoteTargetPath).toUnixPathStr().contains("\\")) {
      throw AppException("remote path err, err code: 11520937");
    }
  }

  static String replacePrefixForRepo(Repo repo, final String targetPath) {
    final result = _replacePrefixForStr(repo.path, repo.getDataDirPath(), targetPath);
    App.logger.debug(_TAG, "replacePrefixForRepo: '$targetPath' to '$result'");
    return result;

  }

  static String restorePrefixForRepo(Repo repo, final String targetPath) {
    final result = _restorePrefixForStr(repo.path, repo.getDataDirPath(), targetPath);
    App.logger.debug(_TAG, "restorePrefixForRepo: '$targetPath' to '$result'");
    return result;
  }

  static FilePath replacePrefixForRemote(Remote remote, final FilePath targetPath) {
    final result = _replacePrefixForFilePath(remote.basePath, targetPath);
    App.logger.debug(_TAG, "replacePrefixForRemote: '$targetPath' to '$result'");
    return result;
  }

  static FilePath restorePrefixForRemote(Remote remote, final FilePath targetPath) {
    final result = _restorePrefixForFilePath(remote.basePath, targetPath);
    App.logger.debug(_TAG, "restorePrefixForRemote: '$targetPath' to '$result'");
    return result;
  }

  /// 如果替换过，返回的字符串会是unix style / 分隔，否则是原字符串
  static String _replacePrefixForStr(final String repoPath, final String dataDirPath, final String targetPath) {
    final dfp = FilePath.fromString(dataDirPath);
    final tfp = FilePath.fromString(targetPath);
    if(tfp.startsWith(dfp)) {
      final newFp = tfp.sub(dfp.length());
      return newFp.prepend(dataDir).toUnixPathStr();
    }

    final rfp = FilePath.fromString(repoPath);
    if(tfp.startsWith(rfp)) {
      final newFp = tfp.sub(rfp.length());
      return newFp.prepend(base).toUnixPathStr();
    }

    return targetPath;
  }

  /// 如果恢复过，会替换成平台分隔符，否则是原字符串
  static String _restorePrefixForStr(final String repoPath, final String dataDirPath, final String targetPath) {
    final tfp = FilePath.fromString(targetPath);
    if(tfp.startsWith(_dataDirFp)) {
      final newFp = tfp.sub(_dataDirFp.length());
      return newFp.prepend(dataDirPath).toString();
    }

    if(tfp.startsWith(_baseFp)) {
      final newFp = tfp.sub(_baseFp.length());
      return newFp.prepend(repoPath).toString();
    }

    return targetPath;
  }

  // 此函数不应该修改传入的basePath和targetPath
  // 我知道这个final无法阻止修改实例字段，我加它只是为了表示代码不应该修改此参数的语义
  static FilePath _replacePrefixForFilePath(final FilePath basePath, final FilePath targetPath) {
    if(targetPath.startsWith(basePath)) {
      final newFp = targetPath.sub(basePath.length());
      return newFp.prepend(base);
    }

    return targetPath;
  }

  // 此函数不应该修改传入的basePath和targetPath
  static FilePath _restorePrefixForFilePath(final FilePath basePath, final FilePath targetPath) {
    if(targetPath.startsWith(_baseFp)) {
      final newFp = targetPath.sub(_baseFp.length());
      return newFp.prepend(basePath.toUnixPathStr());
    }

    return targetPath;
  }

}
