import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:path/path.dart' as p;

abstract class StatusItemType {
  static const modified = "Modified";
  static const added = "Added";
  static const deleted = "Deleted";
}

class StatusItem {
  /// value of [StatusItemType]
  final String type;

  /// 文件名
  final String name;

  /// 完整的相对路径
  final String relativePathUnderWorkdir;

  /// 文件大小
  final int sizeInBytes;

  ///父目录，在UI可显示文件名和父目录来避免直接显示完整相对路径（若直接显示完整相对路径，太长时，会看不到文件名）
  final String parentPath;

  StatusItem({this.type = '', this.name = '', this.relativePathUnderWorkdir = '', this.sizeInBytes = 0, this.parentPath = ''});

  static StatusItem create({
    required String type,
    required String relativePathUnderWorkdir,
    required int sizeInBytes,
  }) {
    final filePath = FilePath.fromString(relativePathUnderWorkdir);

    return StatusItem(
      type: type,
      relativePathUnderWorkdir: filePath.toUnixPathStr(),
      name: filePath.name(),
      sizeInBytes: sizeInBytes,
      parentPath: filePath.parent().toUnixPathStr(),
    );
  }

  String getFullPathOfItem(String basePath) {
    return FilePath.canonicalizePath(p.join(basePath, relativePathUnderWorkdir));
  }

  @override
  String toString() {
    return 'type: $type, name: $name, relativePathUnderWorkdir: $relativePathUnderWorkdir, sizeInBytes: $sizeInBytes';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is StatusItem && runtimeType == other.runtimeType &&
              type == other.type && name == other.name &&
              relativePathUnderWorkdir == other.relativePathUnderWorkdir &&
              sizeInBytes == other.sizeInBytes;

  @override
  int get hashCode =>
      Object.hash(type, name, relativePathUnderWorkdir, sizeInBytes);


}
