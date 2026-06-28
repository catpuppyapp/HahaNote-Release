import 'package:cloud_disk_note_app/bean/bean.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_path.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/time/time_data.dart';
import 'package:cloud_disk_note_app/ext/iterable_ext.dart';
import 'package:cloud_disk_note_app/util/fs.dart' show Fs;
import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart' show HiveObject;
import 'package:path/path.dart' as p show basename;

part 'repo_entity.g.dart';

const _maxRecentFiles = 20;

/// 存在db的仓库实体
@myJsonSerializable
class RepoEntity extends HiveObject {
  /// 相当于数据库的key
  String id;

  /// 用来给用户看是哪个仓库
  String name;

  /// 仓库的完整路径，在列表中唯一！
  /// Unix格式
  String path;

  /// 上次使用时间，可根据这个时间排序
  TimeData lastUpdate;

  List<FilePos> recentFiles;

  // id 为空时会在添加到db时自动生成
  // 不required，这样转换json的时候若缺值，不会报错
  RepoEntity({this.id = '', String? name, this.path = '', TimeData? lastUpdate, List<FilePos>? recentFiles})
    : name = name ?? p.basename(path),
      lastUpdate = lastUpdate ?? TimeData.now(),
      recentFiles = recentFiles ?? []
  ;

  factory RepoEntity.fromJson(Map<String, dynamic> json) => _$RepoEntityFromJson(json);

  Map<String, dynamic> toJson() => _$RepoEntityToJson(this);

  static RepoEntity fromPath(String path) {
    return RepoEntity(path: path);
  }

  static RepoEntity fromFilePath(FilePath filePath) {
    return RepoEntity(path: filePath.toUnixPathStr());
  }

  @override
  String toString() {
    return 'RepoEntity{id: $id, name: $name, path: $path, lastUpdate: $lastUpdate}, recentFiles: $recentFiles';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is RepoEntity && runtimeType == other.runtimeType &&
              id == other.id && name == other.name && path == other.path &&
              lastUpdate == other.lastUpdate;

  @override
  int get hashCode => Object.hash(id, name, path, lastUpdate);


  // 在界面显示的时候，倒序即是添加时间从新到旧
  // keepLastPos 若为true，使用上次pos；例如，有时候只是想记录下打开过这个文件，或者更新其最后打开时间，
  // 并不想修改上次记录的滚动位置等信息，就应传true
  void addPathToRecentFiles(FilePos pos, {required final bool keepLastPos}) {
    final path = pos.path;
    final fp = FilePath.fromString(path);
    // 保存时，一律unix style path
    final path2 = fp.toUnixPathStr();

    // 移除已存在，避免重复
    final index = recentFiles.indexWhere((it) => it.path == path2);
    if(index >= 0) {
      final lastPos = recentFiles.removeAt(index);
      if(keepLastPos) {
        pos.index = lastPos.index;
        pos.offset = lastPos.offset;
        pos.extIndex = lastPos.extIndex;
        pos.extOffset = lastPos.extOffset;
      }
    }

    // 新增
    recentFiles.add(pos);

    if(recentFiles.length > _maxRecentFiles) {
      recentFiles.removeAt(0);
    }
  }

  FilePos? getPosByPath(String path) {
    if(recentFiles.isEmpty) {
      return null;
    }

    final path2 = FilePath.fromString(path).toUnixPathStr();
    return recentFiles.firstWhereOrNull((it) => it.path == path2);
  }

  Future<List<ContentItem>> recentFilesToContentItems() async {
    if(recentFiles.isEmpty) {
      return [];
    }

    final result = <ContentItem>[];
    for(final item in recentFiles) {
      final path = item.path;
      final filePath = FilePath.genRelativePathSafe(this.path, path, ifErrReturnEmpty: false);
      result.add(
        ContentItem(
          name: filePath.name(),
          content: await Fs.readShortContent(path),
          // 如果条目路径是仓库下的文件，则返回相对路径，否则返回条目的绝对路径
          path: filePath.toUnixPathStr(),
          // 永远是绝对路径
          fullPath: path,
          lastTouchedAt: item.lastTouchedAt,
          parentPath: filePath.parent().toUnixPathStr(),
        )
      );
    }

    return result;
  }

}

@myJsonSerializable
class FilePos {
  String path;
  int lastTouchedAt;
  int index;
  int offset;
  int extIndex;
  int extOffset;

  FilePos({this.path = '', this.index = 0, this.offset = 0, this.extIndex = 0, this.extOffset = 0, this.lastTouchedAt = 0});

  factory FilePos.fromJson(Map<String, dynamic> json) => _$FilePosFromJson(json);

  Map<String, dynamic> toJson() => _$FilePosToJson(this);

  @override
  String toString() {
    return 'FilePos{path: $path, index: $index, offset: $offset, extIndex: $extIndex, extOffset: $extOffset, lastTouchedAt: $lastTouchedAt}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is FilePos && runtimeType == other.runtimeType &&
              path == other.path && index == other.index &&
              offset == other.offset && lastTouchedAt == other.lastTouchedAt;

  @override
  int get hashCode => Object.hash(path, index, offset, lastTouchedAt);

  // 保存文件和定位信息
  static FilePos fromCodeLineSelection(String path, TextSelection? selection) {
    return FilePos(
      path: path,
      lastTouchedAt: TimeData.now().utcMs,
      index: selection?.start ?? 0,
      offset: selection?.baseOffset ?? 0,
      extIndex: selection?.end ?? 0,
      extOffset: selection?.extentOffset ?? 0,
    );
  }

  // 有时候只需要跳转，不需要路径，就可调用这个
  static FilePos fromCodeLineSelectionWithoutPath(TextSelection selection) {
    return FilePos(
      index: selection.start,
      offset: selection.baseOffset,
      extIndex: selection.end,
      extOffset: selection.extentOffset
    );
  }

  static FilePos fromLineNum(int lineNum) {
    if(lineNum < 1) {
      // lineNum 必须大于等于1
      lineNum = 1;
    }

    final index = lineNum - 1;
    return FilePos(
      // 只用来跳转行，不需要用到path
      index: index,
      offset: 0,
      extIndex: index,
      extOffset: 0
    );
  }

  TextSelection toSelection() {
    return TextSelection(baseOffset: index, extentOffset: extIndex);
  }
}
