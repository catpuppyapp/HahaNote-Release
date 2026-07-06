import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/path_place_holder.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';
import 'package:hahanote_app/util/form_validator.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  // p.join，
  // 如果被拼接的路径包含 / ，则不会拼接，而是返回最后一个包含 / 的路径，这傻逼逻辑
  print(p.join("abc", "/def"));
  print(p.join("abc", "C:\\def"));
  print(p.join("abc", "/def", "/ghi"));
  print(p.join("abc", "/def", "ghi"));  // 输出 "/def/ghi" or "/def\\ghi"，路径分割符取决于平台
  assert(p.join("abc", "/def") == "/def");
  assert(p.join("abc", "/def", "/ghi") == "/ghi");
  
  // 即使路径ends with slash，也能取出文件名
  final endsSlashPath = "/abc/file/";
  assert(p.basename(endsSlashPath) == "file");
  assert(p.basename(endsSlashPath) == FilePath.fromString(endsSlashPath).name());
  assert(p.basename("") == "");

  assert(FormValidator.errIfPathNotAbsOrInvalid("/", isWindows: true) != null);
  assert(FormValidator.errIfPathNotAbsOrInvalid("/", isWindows: false) != null);
  assert(FormValidator.errIfPathNotAbsOrInvalid("C:/", isWindows: true) != null);
  assert(FormValidator.errIfPathNotAbsOrInvalid("C:\\", isWindows: false) != null);
  assert(FormValidator.errIfIsRootPath("C:\\") != null);
  assert(FormValidator.errIfIsRootPath("/") != null);
  assert(FormValidator.errIfIsRootPath("/abc") == null);
  assert(FormValidator.errIfIsRootPath("C:/abc") == null);
  assert(FormValidator.errIfIsRootPath("C:\\abc") == null);

  assert(p.join("", "abc") == "abc");
  assert(p.join("", "/abc") == "/abc");
  assert(p.join("", "/abc/") == "/abc/");
  assert(p.join("", "\\abc/") == "\\abc/");
  assert(p.join("", "C:\\abc/") == "C:\\abc/");

  RepoPathPlaceHolder.test();

  assert(FilePath.genRelativePath("C:\\", "C:\\abc.txt").toUnixPathStr() == "abc.txt");
  assert(FilePath.genRelativePath("C:\\abc\\def", "C:\\abc\\def\\123.txt").toUnixPathStr() == "123.txt");
  assert(FilePath.genRelativePath("C:\\abc\\", "C:\\abc\\def\\123.txt").toUnixPathStr() == "def/123.txt");
  assert(FilePath.genRelativePath("C:\\abc", "C:\\abc\\def\\123.txt").toUnixPathStr() == "def/123.txt");
  assert(FilePath.genRelativePath("/home/user/abc", "/home/user/abc/123.txt").toUnixPathStr() == "123.txt");
  assert(FilePath.genRelativePath("/home/user/", "/home/user/abc/123.txt").toUnixPathStr() == "abc/123.txt");
  assert(FilePath.genRelativePath("/home/user", "/home/user/abc/123.txt").toUnixPathStr() == "abc/123.txt");
  assert(FilePath.fromString("C:\\abc/def/123").toUnixPathStr() == "C:/abc/def/123");
  assert(FilePath.fromString("C:\\abc/def/123").append("/").append("/").toUnixPathStr() == "C:/abc/def/123");
  assert(FilePath.fromString("C:\\abc/def/123").append("/").append("/s").toUnixPathStr() == "C:/abc/def/123/s");
  assert(FilePath.fromString("/abc/def///123").append("/").append("/s").toUnixPathStr() == "/abc/def/123/s");
  assert(FilePath.fromString("/abc/def///123").toUnixPathStr() == "/abc/def/123");


  final srcList = ["abc", "def"];
  assert(listEquals(srcList.sublist(0, 1)..add("123"), ["abc", "123"]));  // 测试sublist返回的list是否可写，结果 可写
  assert(listEquals(srcList, ["abc", "def"]));  // 测试sublist返回的list是否与源list无关，结果 是

  print("FilePath.canonicalizePath('/'): ${FilePath.canonicalizePath('/')}");
  print("Platform.pathSeparator: ${Platform.pathSeparator}");
  assert("".isEmpty);
  assert(''.isEmpty);
  assert(""=='');

  final ps = Platform.pathSeparator;
  assert(FilePath.canonicalizePath("C:/aBc/Def") == "C:${ps}aBc${ps}Def");
  assert(FilePath.canonicalizePath("C:/\\\\aBc////Def\\123.txt///") == "C:${ps}aBc${ps}Def${ps}123.txt");
  assert(FilePath.canonicalizePath("///aBc////Def///") == "${ps}aBc${ps}Def");
  assert(FilePath.canonicalizePath("///aBc////Def///123.txt//") == "${ps}aBc${ps}Def${ps}123.txt");
  assert(FilePath.canonicalizePath("///aBc////Def///") == "${ps}aBc${ps}Def");

  assert(FilePath.canonicalizePath('/') == ps);
  assert(FilePath.canonicalizePath('\\') == ps);
  assert(FilePath.canonicalizePath('\\//') == ps);
  assert(FilePath.canonicalizePath('///') == ps);
  assert(FilePath.canonicalizePath('\\\\') == ps);
  assert(FilePath.canonicalizePath('') == '');

  assert(FilePath.fromString("///aBc////Def///").append("123").toUnixPathStr() == "/aBc/Def/123");
  assert(FilePath.fromString("///aBc////Def///").append("123").toWindowsPathStr() == "\\aBc\\Def\\123");
  assert(FilePath.fromString("///aBc////Def///").append("/123").toWindowsPathStr() == "\\aBc\\Def\\123");
  assert(FilePath.fromString("///aBc////Def///").append("/123").toUnixPathStr() == "/aBc/Def/123");
  assert(FilePath.fromString("///aBc////Def///").append("/").toUnixPathStr() == "/aBc/Def");
  assert(FilePath.fromString("///aBc////Def///").append("//").toUnixPathStr() == "/aBc/Def");
  assert(FilePath.fromString("///aBc////Def///").append("/").append("/").toUnixPathStr() == "/aBc/Def");
  print(FilePath.fromString("///").append("/").append("/").toUnixPathStr());
  assert(FilePath.fromString("///").append("/").append("/").toUnixPathStr() == "/");
  assert(FilePath.fromString("///").append("//////").toUnixPathStr() == "/");
  assert(FilePath.fromString("///").toUnixPathStr() == "/");
  assert(FilePath.fromString("abc").toUnixPathStr != FilePath.fromString("path").toWindowsPathStr);

  assert(FilePath.fromString("/").toUnixPathStr() == '/');
  assert(FilePath.fromString("").toUnixPathStr() == '');
  assert(FilePath.fromString("").toWindowsPathStr() == '');
  assert(FilePath.fromString("/").toWindowsPathStr() == '\\');
  assert(FilePath.fromString("\\").toWindowsPathStr() == '\\');
  assert(FilePath.fromString("\\//").toWindowsPathStr() == '\\');
  assert(FilePath.fromString("/\\/\\").toUnixPathStr() == '/');

  assert(listEquals(FilePath.fromString("/").value, ['']));

  assert("/" == FilePath.fromString('/').toUnixPathStr());
  assert("\\" == FilePath.fromString('/').toString());
  assert("/" == FilePath.fromString('\\').toUnixPathStr());
  assert(FilePath.fromString('').toString() == '');
  assert("abc/def" == FilePath.fromString('abc/def').toUnixPathStr());
  assert("abc/def" == FilePath.fromString('abc/def').append("").toUnixPathStr());
  assert("abc/def" == FilePath.fromString('abc/def').append("\\").toUnixPathStr());
  assert("abc/def" == FilePath.fromString('abc/def').append("/").toUnixPathStr());
  assert(FilePath.fromString('/') == FilePath.fromString('\\'));
  assert(FilePath.fromString('/') == FilePath.fromString('\\'));

  assert(FilePath.fromString("path/abc").toUnixPathStr() == "path/abc");
  assert(FilePath.fromString("path/abc").toWindowsPathStr() == "path\\abc");
  assert(FilePath.fromString("//////").toWindowsPathStr() == "\\");
  assert(FilePath.fromString("abc//////def").toUnixPathStr() == "abc/def");

  assert(FilePath.fromString("abc//////def").append("/").toUnixPathStr() == "abc/def");
  assert(FilePath.fromString("abc//////def").append("").toUnixPathStr() == "abc/def");
  assert(FilePath.canonicalizePath("abc//////def/").replaceAll("\\", '/') == "abc/def");
  assert(FilePath.fromString(".").toUnixPathStr() == ".");
  assert(FilePath.fromString(".").toWindowsPathStr() == ".");
  assert(FilePath.fromString("./abc/").toWindowsPathStr() == ".\\abc");
  assert(FilePath.fromString("./abc").toUnixPathStr() == "./abc");
  assert(FilePath.fromString("").toWindowsPathStr() == "");
  assert(FilePath.fromString("/").toWindowsPathStr() == "\\");
  assert(FilePath.fromString("/").toUnixPathStr() == '/');

  print("FilePath.fromString(path/abc).toUnixPathStr(): ${FilePath.fromString("path/abc").toUnixPathStr()}");



  final sub = r"C:\test_path\12345678";
  assert(FilePath.genRelativePathSafe(r"C:\test", sub, ifErrReturnEmpty: false).toString() == sub);

  try {
    FilePath.genRelativePath(r"C:\test", sub);
    print("no err, wrong");
  }catch(e) {
    print("err, good, e: $e");
  }

  try {
    FilePath.genRelativePath("/abc/def/", "/abc/def");
    print("no err, wrong");
  }catch(e) {
    print("err, good, e: $e");
  }

  try {
    FilePath.genRelativePath("/abc/def/", "/abc/def//////");
    print("no err, wrong");
  }catch(e) {
    print("err, good, e: $e");
  }

  assert(FilePath.genRelativePath("/abc/def/", "/abc/def///123///abc.txt").toUnixPathStr() == "123/abc.txt");
  assert(FilePath.genRelativePath("/abc/def", "/abc/def//////abc.txt").toUnixPathStr() == "abc.txt");

  assert(FilePath.genRelativePath("/abc/", "/abc/def/123").length() == 2); // [def, 123]
  assert(FilePath.genRelativePath("/abc/", "/abc/def/123").toUnixPathStr() == "def/123");

  assert(p.normalize("C:/abc////////def//") == "C:\\abc\\def");
}
