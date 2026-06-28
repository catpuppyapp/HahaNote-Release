// import 'dart:io' show File;
//
// import 'package:cloud_disk_note_app/cloud_disk_note/crypto/encrypt.dart';
// import 'package:cloud_disk_note_app/cloud_disk_note/crypto/key_data.dart';
// import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/remote.dart';
// import 'package:cloud_disk_note_app/cloud_disk_note/storage/msg/msg.dart' show Msg;
// import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/repo.dart' show Repo;
// import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart';
//
// import '../files/file_info.dart' show FileInfo;
// import '../utils.dart' show getFileAndMakeSureParentDirExist;
//
// @Deprecated("并没使用这个类")
// abstract class Cache {
//   /// 直接返回缓存的解密后的文件，如果没有，先解密，后缓存
//   static Future<File> decryptFile(RemoteDataType remoteDataType, VersionOid oid, KeyData keyData, String cacheDirPath, String remoteDataDirPath) async {
//     var cachedPath = '';
//     var originPath = '';
//     final oidStr = oid.value;
//
//     if(remoteDataType == RemoteDataType.objects) {
//       cachedPath = Repo.getCachedObjectPathByOidStr(cacheDirPath, oidStr);
//       originPath = Repo.getObjectPathByOidStr(remoteDataDirPath, oidStr);
//     }else if(remoteDataType == RemoteDataType.files) {
//       // file info 同路径可能变化，最好不要cache
//       throw StateError("doesn't support cache file info (code: 19786585): $remoteDataType");
//     }else if(remoteDataType == RemoteDataType.msg) {
//       cachedPath = Repo.getCachedMsgPathByOidStr(cacheDirPath, oidStr);
//       originPath = Repo.getMsgPathByOidStr(remoteDataDirPath, oidStr);
//     }else if(remoteDataType == RemoteDataType.locks) {
//       // 仓库lock都在 locks/repoLock目录，不能缓存，因为就算data.enc变了，路径也不变
//       throw StateError("doesn't support cache lock (code: 14197095): $remoteDataType");
//     }else {
//       // code 用来定位错误信息在代码中的位置
//       throw StateError("unknown remote data type (code: 16568844): $remoteDataType");
//     }
//
//     final cachedFile = await getFileAndMakeSureParentDirExist(cachedPath);
//     if(!await cachedFile.exists()) {
//       final encryptedData = await EncryptedData.readFromFile(File(originPath));
//       final data = await encryptedData.decryptThenUncompress(keyData);
//       final ioSink = cachedFile.openWrite();
//       await for(final d in data) {
//         ioSink.add(d);
//       }
//
//       await ioSink.flush();
//       await ioSink.close();
//     }
//
//     return cachedFile;
//   }
//
//   static Future<FileInfo> decryptFileInfo(VersionOid oid, KeyData keyData, String cacheDirPath, String remoteDataDirPath) async {
//     final file = await decryptFile(RemoteDataType.files, oid, keyData, cacheDirPath, remoteDataDirPath);
//     return FileInfo.fromJsonByteStream(file.openRead());
//   }
//
//   static Future<Msg> decryptMsg(VersionOid oid, KeyData keyData, String cacheDirPath, String remoteDataDirPath) async {
//     final file = await decryptFile(RemoteDataType.files, oid, keyData, cacheDirPath, remoteDataDirPath);
//     return Msg.fromJsonByteStream(file.openRead());
//   }
// }
