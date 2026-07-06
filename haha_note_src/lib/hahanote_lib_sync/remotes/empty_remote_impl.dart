import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart' show Remote, RemoteFile, RemoteType;
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart' show RemoteConfig;
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart';

final emptyRemoteImplInstance = EmptyRemoteImpl();

class EmptyRemoteImpl extends Remote {
  @override
  FilePath basePath = FilePath();

  @override
  bool isChild = false;

  @override
  bool isLockUploader = false;

  @override
  String pathSeparator = '/';

  @override
  RemoteType get type => RemoteType.empty;

  @override
  bool get supportAutoCreateNonexistsPath => throw UnimplementedError();

  @override
  Future<void> copy(FilePath from, FilePath to, {required bool isDir, bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) {
    throw UnimplementedError();
  }

  @override
  Future<void> delete(FilePath path, {required bool isDir, bool gitPushIfNeed = true}) {
    throw UnimplementedError();
  }

  @override
  Future<void> downloadToFile(FilePath path, File file, TempDir tempDir) {
    throw UnimplementedError();
  }

  @override
  Future<RemoteFile> getMetadata(FilePath path) {
    throw UnimplementedError();
  }

  @override
  Future<List<RemoteFile>> listFiles(FilePath path) {
    throw UnimplementedError();
  }

  @override
  Future<void> mkdir(FilePath path) {
    throw UnimplementedError();
  }

  @override
  Future<void> rename(FilePath from, FilePath to, {required bool isDir, bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) {
    throw UnimplementedError();
  }

  @override
  Future<void> uploadFile(FilePath path, File file, {bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) {
    throw UnimplementedError();
  }

  @override
  Future<RemoteConfig> toRemoteConfig() async {
    throw UnimplementedError();
  }


}
