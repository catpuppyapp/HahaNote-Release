import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_path.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/utils.dart';
import 'package:cloud_disk_note_app/util/fs.dart' show Fs;
import 'package:cloud_disk_note_app/util/util.dart';
import 'package:flutter/widgets.dart';

const _TAG = "bean.dart";

typedef Canceler = void Function();

class FileItem {
  String name;
  FilePath path;
  String lastModified;
  int size;

  FileItem({this.name = '', FilePath? path, this.lastModified = '', this.size = 0})
  : path = path ?? FilePath();

  static FileItem fromPath(String path) {
    final item = FileItem();
    if(path.isEmpty) {
      return item;
    }

    item.path = FilePath.fromString(path);
    item.name = item.path.name();

    return item;
  }

  // 返回值可用来取消计算目录大小
  Future<Canceler?> setLastModifiedAndStartCountSize(
    void Function(int) sizeChangedCallback
  ) async {
    final path = this.path.toString();
    final fileType = await getFileType(path);

    bool sizeCountCanceled = false;
    try {
      if(fileType == FileSystemEntityType.directory) {
        final dir = Directory(path);
        lastModified = formatDateTimeHumanFriendly(dir.statSync().modified);
        // 不await，异步计算
        Fs.countDirSize(dir, count: (s) {
          size += s;
          sizeChangedCallback(size);
        }, canceled: () => sizeCountCanceled);

        return () { sizeCountCanceled = true; };
      }else if(fileType == FileSystemEntityType.file) {
        final file = File(path);
        lastModified = formatDateTimeHumanFriendly(file.statSync().modified);
        size = await file.length();
        sizeChangedCallback(size);

        return null;
      }else {
        // 不支持 link等非file非dir的类型
        return null;
      }
    }catch(e) {
      App.logger.debug(_TAG, "set last modified and count size err: path=$path, err=$e");
      sizeCountCanceled = true;
      sizeChangedCallback(size);

      return null;
    }
  }
}

class MenuItem {
  final String value;
  final String text;
  final Future<void> Function()? onClick;

  MenuItem({this.value = "", this.text = "", this.onClick});

  static final divider = MenuItem(value: "MENU_ITEM_DIVIDER_15802383");
}

class LabelValue {
  String label;
  String value;
  IconData? icon;
  FontWeight? valueFontWeight;
  // 显示在条目左侧的图片，例如：[头像] 用户名，其中头像的url就可存进此字段
  String headingImgUrl;
  Color? valueColor;

  // 若非null，将使用此text style并无视 valueFontWeight 和 valueColor
  TextStyle? textStyle;

  LabelValue({this.label = '', this.value = '', this.icon, this.valueFontWeight, this.headingImgUrl = "", this.valueColor, this.textStyle});

  @override
  String toString() {
    return 'LabelValue{label: $label, value: $value, icon: $icon, valueFontWeight: $valueFontWeight, headingImgUrl: $headingImgUrl, valueColor: $valueColor, textStyle: $textStyle}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is LabelValue && runtimeType == other.runtimeType &&
              label == other.label && value == other.value &&
              icon == other.icon && valueFontWeight == other.valueFontWeight &&
              headingImgUrl == other.headingImgUrl &&
              valueColor == other.valueColor && textStyle == other.textStyle;

  @override
  int get hashCode =>
      Object.hash(
          label,
          value,
          icon,
          valueFontWeight,
          headingImgUrl,
          valueColor,
          textStyle);


}

class ContentItem {
  String name;
  String content;
  // 若是仓库子目录，则相对路径，否则绝对路径
  String path;
  // 百分百绝对路径
  String fullPath;
  int lastTouchedAt;
  String parentPath;

  ContentItem({this.name = '', this.content = '', this.path = '', this.fullPath = '', this.lastTouchedAt = 0, this.parentPath = ''});

  @override
  String toString() {
    return 'ContentItem{name: $name, content: $content, path: $path, fullPath: $fullPath, lastTouchedAt: $lastTouchedAt, parentPath: $parentPath}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ContentItem && runtimeType == other.runtimeType &&
              name == other.name && content == other.content &&
              path == other.path && parentPath == other.parentPath &&
              fullPath == other.fullPath && lastTouchedAt == other.lastTouchedAt;

  @override
  int get hashCode => Object.hash(name, content, path, fullPath, lastTouchedAt, parentPath);

}

class FileStat {
  int length;
  int lastModified;

  FileStat({this.length = 0, this.lastModified = 0});

  static FileStat fromFileSync(File file) {
    try {
      return FileStat(length: file.lengthSync(), lastModified: file.statSync().modified.millisecondsSinceEpoch);
    }catch(e) {
      return FileStat();
    }
  }

  static Future<FileStat> fromFile(File file) async {
    try {
      return FileStat(
        length: await file.length(),
        lastModified: (await file.stat()).modified.millisecondsSinceEpoch,
      );
    } catch (e) {
      return FileStat();
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is FileStat && runtimeType == other.runtimeType &&
              length == other.length && lastModified == other.lastModified;

  @override
  int get hashCode => Object.hash(length, lastModified);

  @override
  String toString() {
    return 'FileStat{length: $length, lastModified: $lastModified}';
  }

}

class TextValueSelected {
  // ui显示的文本，例如：“选项1”，根据语言不同
  String text;
  // 代码使用的值，例如："value"，所有语言相同value
  String value;
  // 是否选中
  bool selected;

  String desc;

  TextValueSelected({required this.text, required this.value, this.selected = false, this.desc = ""});


  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is TextValueSelected && runtimeType == other.runtimeType &&
              text == other.text && value == other.value &&
              selected == other.selected && desc == other.desc;

  @override
  int get hashCode => Object.hash(text, value, selected, desc);

  @override
  String toString() {
    return 'text: $text, value: $value, selected: $selected, desc: $desc';
  }

  TextValueSelected copy({String? text, String? value, bool? selected, String? desc}) {
    return TextValueSelected(
      text: text ?? this.text,
      value: value ?? this.value,
      selected: selected ?? this.selected,
      desc: desc ?? this.desc,
    );
  }

}

// 操作的影响范围：用来告诉某些函数，操作的来源，比如可多选的列表，有时候是点顶栏，删除所有，有的是多选模式下，点底栏按钮，只删除选中条目
enum ActRegion { all, selected }

// 和FileStat重复了。。。。
// class FileModifiedInfo {
//   int? size;
//   int? mTime;

//   static Future<FileModifiedInfo?> fromFile(File file) async {
//     try {
//       final fmi = FileModifiedInfo();
//       final stat = await file.stat();
//       fmi.mTime = stat.modified.millisecondsSinceEpoch;
//       fmi.size = await file.length();

//       return fmi;
//     }catch(e, st) {
//       App.logger.debug("FileModifiedInfo", "fromFile() err: $e\n$st");
      
//       return null;
//     }
//   }

//   @override
//   bool operator ==(Object other) =>
//       identical(this, other) ||
//       other is FileModifiedInfo &&
//           runtimeType == other.runtimeType &&
//           size == other.size &&
//           mTime == other.mTime;

//   @override
//   int get hashCode => Object.hash(size, mTime);

//   @override
//   String toString() {
//     return 'size: $size, mTime: $mTime';
//   }

// }
