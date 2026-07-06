import 'dart:io';

import 'package:characters/characters.dart';
import 'package:hahanote_app/hahanote_lib_sync/crypto/hash.dart';
import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/serialization/json.dart' show myJsonSerializable;
import 'package:hahanote_app/hahanote_lib_sync/serialization/map_key.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:hahanote_app/hahanote_lib_sync/string_ext.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:path/path.dart' as p;

import '../../serialization/oidlize.dart';

part 'file_path.g.dart';

// value of: FilePath.fromString('/') and FilePath.fromString("\\")
const _constSingleSeparatorFilePathValue = ['']; //只读，不要在创建FilePath实例时使用，不然append会报错，应仅在比较时使用
// value of: FilePath.fromString("")
// 注：FilePath.fromString('').toString() == ""，内部存储的数组会是空数组 []
// const emptyFilePathValue = <String>[];

List<String> _getSingleSeparatorFilePathValue() {
  return [''];
}

List<String> _getEmptyFilePathValue() {
  return [];
}


const unixPathSeparator = '/';
const winPathSeparator = '\\';

@myJsonSerializable
class FilePathPair {
  FilePath left;
  FilePath right;
  bool isDir;

  // 可以附加一些信息，例如左边的是不是目录，右边的是不是目录，
  // 移动前是否需要先删除目标之类的，不过暂时没用
  Map<String, dynamic> extra;

  FilePathPair({FilePath? left, FilePath? right, this.isDir = false, Map<String, dynamic>? extra})
    : left = left ?? FilePath(),
      right = right ?? FilePath(),
      extra = extra ?? {};


  factory FilePathPair.fromJson(Map<String, dynamic> json) => _$FilePathPairFromJson(json);

  Map<String, dynamic> toJson() => _$FilePathPairToJson(this);

  @override
  String toString() {
    return 'FilePathPair{left: $left, right: $right, isDir: $isDir, extra: $extra}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is FilePathPair && runtimeType == other.runtimeType &&
              left == other.left && right == other.right &&
              isDir == other.isDir && mapEquals(extra, other.extra);

  @override
  int get hashCode => Object.hash(left, right, isDir, extra);


}

/// 存储时：把路径存到数组，不包含分隔符。
/// 算oid时：路径名，统一使用'/'作为分隔符，首尾均不包含分隔符
/// 显示时：根据用户所在平台使用对应分隔符（若统一格式，优先考虑使用'/')
@myJsonSerializable
class FilePath implements MapKey, Oidlize {
  List<String> value;

  /// 这个字段多数情况下其实没用，就是在上传文件的时候，指定远程路径，用下这个字段，若为真，
  /// 则追加远程路径的basePath变成绝对路径，否则，不追加，直接使用，其他情况，似乎，用不到这个字段
  bool isRelative;

  @JsonKey(
    includeFromJson: false,
    includeToJson: false,
  )
  String? _cachedUnixStr;

  @JsonKey(
    includeFromJson: false,
    includeToJson: false,
  )
  String? _cachedWinStr;

  FilePath({List<String>? value, this.isRelative = false})
      : value = value ?? [];

  factory FilePath.fromJson(Map<String, dynamic> json) => _$FilePathFromJson(json);

  Map<String, dynamic> toJson() => _$FilePathToJson(this);


  // 兼容 /\混合的路径
  static FilePath fromString(String path, {bool isRelative = false}) {
    if(path.isEmpty) {
      return FilePath(value: _getEmptyFilePathValue(), isRelative: isRelative);
    }

    // 用户输入的路径，不一定什么样，所以，先规范化一下，再使用
    final replacedPath = canonicalizePath(path, pathSeparator: unixPathSeparator);
    return FilePath(
      value: replacedPath == unixPathSeparator
        // 替换后的路径如果只有路径分割符，则返回空value，不然的话，
        // 如果替换后的路径是 '/' split后会变成['', '']，toString会变成两个/，即 "//"
        ? _getSingleSeparatorFilePathValue()
        : replacedPath.split(unixPathSeparator),
      isRelative: isRelative
    );
  }


  static FilePath fromUnixString(String path, {bool isRelative = false}) {
    return fromString(path, isRelative: isRelative);
  }

  /// return relative path, without pathSeparator, prefix and suffix
  /// e.g. input: base "/abc/" sub "/abc/def/" return def
  static FilePath genRelativePath(String baseFullPath, String subFullPath) {
    if(baseFullPath.isEmpty) {
      throw AppException("base path is empty");
    }

    if(subFullPath.isEmpty) {
      throw AppException("sub path is empty");
    }

    // fromString转换完毕后末尾无 / ，为了避免匹配到非路径前缀，
    // 例如 base=/abc/def_123, sub=/abc/def_123_456/file.txt，若base末尾无/，会得到错误的相对路径_456/file.txt，
    // 因此将base path转换为规范化的unix style path后，为其末尾加个/
    // x 把toPathStr()改成规范路径后，这样不行了）or 在fromString()后append()一个/再toString()，也行: FilePath.fromString(baseFullPath).append(unixPathSeparator).toUnixPathStr()
    final baseDirPath = FilePath.fromString(baseFullPath).toUnixPathStr()+unixPathSeparator;
    final fileUnderBaseDirPath = FilePath.fromString(subFullPath).toUnixPathStr();

    if (!fileUnderBaseDirPath.startsWith(baseDirPath)) {
      throw AppException("sub path is not a sub path of base: base = $baseDirPath, subPath = $fileUnderBaseDirPath");
    }

    var relativePath = fileUnderBaseDirPath.substring(baseDirPath.length);
    // 移除所有前置 /，若字符串为空，starsWith'/'会返回假，终止循环
    while(relativePath.startsWith(unixPathSeparator)) {
      // 若startsWith / 为 true，字符串length >= 1， substring startIndex的极限就是字符串的length（是length，是最后索引+1，不是最后一个索引）
      relativePath = relativePath.substring(1);
    }

    if(relativePath.isEmpty) {
      throw AppException("sub path maybe same as base: base == subPath is '${baseDirPath == fileUnderBaseDirPath}', base = $baseDirPath, subPath = $fileUnderBaseDirPath");
    }

    return FilePath.fromString(relativePath, isRelative: true);
  }

  // 和 非safe的区别在于：如果路径不是基路径的子路径，若 [ifErrReturnEmpty] 为真则返回空path，否则会原样返回subFullPath而不是报错
  static FilePath genRelativePathSafe(
    String baseFullPath,
    String subFullPath, {
    required bool ifErrReturnEmpty,
  }) {
    try {
      return genRelativePath(baseFullPath, subFullPath);
    }catch(e) {
      return ifErrReturnEmpty ? FilePath.fromString("") : FilePath.fromString(subFullPath);
    }
  }

  FilePath parent() {
    // 如果length是0，无条目，返回空；
    // 如果length是1，取区间[0,0]，区间为空，还是会创建空数组
    // 所以，如果length < 2，直接返回空对象即可
    if(value.length < 2) {
      return FilePath(isRelative: isRelative);
    }

    final newPath = FilePath();
    newPath.isRelative = isRelative;
    newPath.value = value.sublist(0, value.length - 1);
    return newPath;
  }

  @override
  String toString() {
    return toPathStr(Platform.pathSeparator);
  }

  @override
  Future<String> toOidStr(KeyData contentKeyData) async {
    // 算hash，强制使用 unix路径分隔符
    return bytesToHex(await hashStrWithKeyData(contentKeyData, toUnixPathStr(), throwIfInterrupted: null));
  }

  // Stream<List<int>> _toByteStream(String separator) async* {
  //   final lastIdx = value.length - 1;
  //   这方法若以后用，改成 toUnixPathStr()，然后再转换成utf8字节
  //   for(var i = 0; i < value.length; i++) {
  //     // 如果是最后一个条目，不加 / 否则加
  //     if(i != lastIdx) {
  //       yield utf8.encoder.convert(value[i] + separator);
  //     }else {
  //       yield utf8.encoder.convert(value[i]);
  //     }
  //   }
  // }

  String toUnixPathStr() {
    _cachedUnixStr ??= toPathStr(unixPathSeparator);
    return _cachedUnixStr!;
  }

  String toWindowsPathStr() {
    _cachedWinStr ??= toPathStr(winPathSeparator);
    return _cachedWinStr!;
  }


  String toPathStr(String pathSeparator) {
    if(value.isEmpty) {
      return "";
    }

    // 如果value 等于 ['']，返回路径分割符，否则返回用路径分割符拼接后的字符串
    final result = listEquals(value, _constSingleSeparatorFilePathValue) ? pathSeparator : value.join(pathSeparator);

    return canonicalizePath(result, pathSeparator: pathSeparator);
  }

  File toFile({String base = ''}) {
    // 注：p.join(空字符串, abc)，结果一律等于 abc
    return File(p.join(base, toString()));
  }

  Directory toDir({String base = ''}) {
    return Directory(p.join(base, toString()));
  }

  String name() {
    if(value.isEmpty) {
      return "";
    }

    return value[value.length - 1];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilePath &&
          runtimeType == other.runtimeType &&
          isRelative == other.isRelative &&
          listEquals(value, other.value);

  @override
  int get hashCode => Object.hash(value, isRelative);

  // static String canonicalizePathDeprecated(String path) {
  //   // 避免path被处理成相对路径字符串，例如 '' 被normalize 为 '.'
  //   if(path.isEmpty) {
  //     return path;
  //   }
  //
  //   // 这个api和java的不太一样，非常迷惑，在windows下会全部变成小写，
  //   // 并且路径也会被改变，比如原本是e盘某路径，可能会变成g盘某路径，没搞懂，不用了
  //   // p.canonicalize(path);
  //
  //   // 这个貌似好使？行为类似java的canonicalPath?
  //   return p.normalize(path);
  // }

  static String canonicalizePath(String path, {final String? pathSeparator}) {
    // 避免path被处理成相对路径字符串，例如 '' 被normalize 为 '.'
    if(path.isEmpty) {
      return path;
    }

    final pathSeparator2 = pathSeparator ?? Platform.pathSeparator;

    if(path == unixPathSeparator || path == winPathSeparator) {
      return pathSeparator2;
    }

    final sb = StringBuffer();
    bool lastStrIsSeparator = false;
    for(final c in path.characters) {
      if(c == unixPathSeparator || c == winPathSeparator) {
        if(lastStrIsSeparator) {
          // 移除连续 path separator，例如 /abc/////def/123，移除abc和def间重复的/
          continue;
        }
        sb.write(pathSeparator2);
        lastStrIsSeparator = true;
      }else {
        sb.write(c);
        lastStrIsSeparator = false;
      }
    }

    final pathStr = sb.toString();
    // 无路径分割符 或 只有路径分割符，直接返回
    // 例如：'abc' or /
    if(pathStr.length == 1) {
      return pathStr;
    }

    // 末尾无路径分割符，直接返回
    if(!pathStr.endsWith(pathSeparator2)) {
      return pathStr;
    }

    // 末尾有路径分割符，移除，然后返回，例如 /abc/123/ ，返回 /abc/123
    return pathStr.removeSuffix(pathSeparator2);
  }

  Future<bool> exists() async {
    return (await getFileType(toString())) != FileSystemEntityType.notFound;
  }

  @override
  String toMapKey() {
    return toUnixPathStr();
  }

  void clearCachedValue() {
    _cachedUnixStr = null;
    _cachedWinStr = null;
  }

  FilePath prepend(String s) {
    final tempFp = fromString(s);
    if(tempFp.isNotEmpty()) {
      clearCachedValue();
      value = [...tempFp.value, ...value];
    }

    return this;
  }

  FilePath append(String s) {
    final tempFp = fromString(s);
    if(tempFp.isNotEmpty()) {
      clearCachedValue();
      value = [...value, ...tempFp.value];
    }

    return this;
  }

  // copy，然后把最后一个元素重命名
  // 例如有路径：abc/123.txt，传参newName="456.txt"，
  // 调用此方法后返回一个新的实例，路径为 abc/456.txt
  FilePath copyThenRename(String newName) {
    final copied = copy();
    return copied.rename(newName);
  }

  // 拷贝对象
  FilePath copy() {
    final newFp = FilePath();
    newFp.value = getValueCopy();
    newFp.isRelative = isRelative;
    return newFp;
  }

  // 拷贝对象并设置 isRelative 为 false
  FilePath copyAbs() {
    final copied = copy();
    copied.isRelative = false;
    return copied;
  }

  // 拷贝对象并设置 isRelative 为 true
  FilePath copyRelative() {
    final copied = copy();
    copied.isRelative = true;
    return copied;
  }


  FilePath rename(String newName) {
    final tempFp = fromString(newName);

    clearCachedValue();

    if(value.isEmpty) {
      value.addAll(tempFp.value);
    }else {
      value.removeAt(value.length - 1);
      value.addAll(tempFp.value);
    }

    return this;
  }

  // 如果路径完全是空字符串组成的，返回true
  bool isNotEmpty() {
    return !isEmpty();
  }

  bool isEmpty() {
    return value.isEmpty;

    // '/' 根路径分割出来就是length 2，这种情况就算值全是空字符串也并不异常
    // 其余的长度，1或大于2，若值为空字符串，则异常
    // if(value == constSingleSeparatorFilePathValue) {
    //   return false;
    // }
    //
    // for(final v in value) {
    //   if(v.isNotEmpty) {
    //     return false;
    //   }
    // }
    //
    // return true;
  }

  bool startsWith(FilePath other) {
    if(length() < other.length()) {
      return false;
    }

    for(final (i, v) in other.value.indexed) {
      if(value[i] != v) {
        return false;
      }
    }

    return true;
  }

  Future<FilePath> makeSureParentExists() async {
    if(value.length > 1) {
      await parent().toDir().create(recursive: true);
    }

    return this;
  }

  FilePath sub(int startAt, [int? end]) {
    return FilePath(value: value.sublist(startAt, end), isRelative: isRelative);
  }

  int length() {
    return value.length;
  }

  bool canGoParent() {
    return length() > 1;
  }

  FilePath root() {
    return length() > 1 ? FilePath(value: [value[0]], isRelative: isRelative) : FilePath(isRelative: isRelative);
  }

  List<String> getValueCopy() {
    return value.toList();
  }


  // 这个并不是readOnly，只是长度固定，内部字段依然可修改，例如 value[0] = "abc"，会修改第一个元素
  // List<String> getReadOnlyValueCopy() {
  //   return value.toList(growable: false);
  // }
}
