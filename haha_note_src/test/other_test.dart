import 'dart:convert';
import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/client/client.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/base/remote.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/remotes/pack/obj_pack.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_path.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/repo.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/utils.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart';
import 'package:flutter/widgets.dart';


Future<void> main() async {
  bool? a = null;
  a = false;
  assert(!a!);

  a = true;
  assert(!!a!);

  // 只有一个文件名的目录的父目录为空
  assert(FilePath.fromString("abc.txt").parent().toUnixPathStr() == "");
  assert(FilePath.fromString("abc.txt").parent().isEmpty());

  assert([1].sublist(0, 0).isEmpty);
  assert([1, 2].sublist(0, 0).isEmpty);
  assert([1].sublist(1, 1).isEmpty);
  assert([1, 2].sublist(1, 1).isEmpty);

  print(Remote.handleGitPushUrl("https://127.0.0.1:52520/pull?token=abc&repoNameOrId=xxx&async=1", "msgPrefix"));
  final expectedResult = "https://127.0.0.1:52520/pull?token=abc&repoNameOrId=xxx&async=0&resetIfErr=hard&cmtMsgPrefix=msgPrefix";
  assert(Remote.handleGitPushUrl("https://127.0.0.1:52520/pull?token=abc&repoNameOrId=xxx&async=1", "msgPrefix") == expectedResult);
  assert(Remote.handleGitPushUrl("https://127.0.0.1:52520/pull?token=abc&repoNameOrId=xxx&async=1&resetIfErr=hard", "msgPrefix") == expectedResult);
  assert(Remote.handleGitPushUrl("https://127.0.0.1:52520/pull?token=abc&repoNameOrId=xxx&async=1&resetIfErr=soft", "msgPrefix") == expectedResult);
  assert(Remote.handleGitPushUrl("https://127.0.0.1:52520/pull?token=abc&repoNameOrId=xxx&async=0&resetIfErr=hard", "msgPrefix") == expectedResult);
  assert(Remote.handleGitPushUrl(expectedResult, "") == expectedResult);
  assert(Remote.handleGitPushUrl(expectedResult, "otherCmtMsgPrefixWillNotUseDueToUrlAlreadyHadOne") == expectedResult);
  final noCmtMsgPrefix = "https://127.0.0.1:52520/pull?token=abc&repoNameOrId=xxx&async=0&resetIfErr=hard";
  assert(Remote.handleGitPushUrl(noCmtMsgPrefix, "") == noCmtMsgPrefix+"&cmtMsgPrefix=");
  assert(Remote.handleGitPushUrl(noCmtMsgPrefix, "abc") == noCmtMsgPrefix+"&cmtMsgPrefix=abc");

  // "abc" as int;  // cast，类型不匹配，报错
  // "abc" as int?;  // cast，类型不匹配，报错，即使可为null，只要类型不匹配，也依然会报错

  // "abc" is int;  // 只是bool判断，若类型不匹配返回false，但不会报错

  assert("abc" is! int); // true, is! == is not, "abc" is not int, so is true
  assert("abc" is String);  // true

  final num = 1928;
  final bytes = intToBytes(num, 8);
  assert(bytes.length == 8);
  final result = intFromBytes(bytes, 0, 8);
  print("result: $result");
  assert(num == result);

  final num2 = 123;
  final bytes2 = intToBytes(num2, 8);
  assert(bytes2.length == 8);
  final result2 = intFromBytes(bytes2, 0, 8);
  print("result2: $result2");
  assert(num2 == result2);

  final num3 = 123;
  final bytes3 = intToBytes(num3, 1);
  assert(bytes3.length == 1);
  final result3 = intFromBytes(bytes3, 0, 1);
  print("result3: $result3");
  assert(num3 == result3);

}

Future<void> main2() async {
  final result = [[1,2], [3]].fold<List<int>>([], (previous, element){ previous.addAll(element); return previous; });
  print(result); // [1, 2, 3]
  // return;
  final refSet = {ObjRef(type: ObjRefType.fileInfo, oid: "123")};
  final oldRefs = {ObjRef(type: ObjRefType.msg, oid: "123")};
  // 期望只有一个元素，且覆盖（与预期不符，
  // 没覆盖，依然是旧元素，Set若判定相等 则 新的不会覆盖旧的）
  refSet.addAll(oldRefs);
  // 改了hashcode和equals，期望只根据oid移除（与预期一致，
  // 具体细节：hashCode做第一轮判断，equals做最终裁决，
  // 例如添加，若hashCode不同，则认为一定不同，不会再比较equals，直接添加条目；
  // 移除时，若hashCode相同，则再使用equals进行比较）
  refSet.removeAll(oldRefs);

  print(refSet);  // 期望空

  final Set<String> set = {"abc"};
  print(set.length);

  set.add("def");

  print(set);
  // 结论：null可安全调用toString()转换为 "null" 字符串
  print(null.toString() == null); // false
  print(null.toString() == "null");  // true
  if(await isFileExistsAndEmpty(File("不存在的文件"))) {
    throw "err";
  }

  if(await isFileExistsAndEmpty(File("test/data/256KB.json"))) {
    throw "err";
  }

  if(!await isFileExistsAndEmpty(File("test/data/empty.txt"))) {
    throw "err";
  }
}

Future<void> maidfdn() async {

  final a = ('a','b',3);
  print(a.$2);
  final (a1, a2, a3) = a;
  print(a1);
}

Future<void> main222() async {
  await null;
  print(0x0a == 10);  // true
  print(0xff == 255);  // true
}

Future<void> main1111() async {
  // var user = UserInfo(id: "abc", vipLv: 10);
  // assert(!user.isInvalid());  // false
  // user = UserInfo(id: "", vipLv: 10);
  // assert(user.isInvalid()); // true
  // user = UserInfo(id: "1", vipLv: 10);
  // assert(!user.isInvalid()); // false
}

Future<void> main123() async {
  final json = '[{"id":"MdqnX5cEzFKePgBoe6eJcoAiON40AHWQ","name":"repo20260108","path":"E:/testNoteApp/gui/repo20260108","lastUpdate":{"utcMs":1767965557953,"offsetM":480}}]';
  for(final i in jsonDecode(json)) {
    print(i as Map<String, dynamic>);
  }
}

Future<void> fmain() async {
  final dynamic abc = null;

  print(abc is String);
  print(abc == null);
  // print(abc is null);

  print('${getTest(true) is int}');  // true
  print('${getTest(false) is int}');

  final map = <String, String>{};
  // true
  print('map["不存在的key"] == null: ${map["不存在的key"] == null}');

  final list = ['c', " "];
  for(final c in "abc def".characters) {
    print(c.toUpperCase());
    print(list.contains(c));
  }
}

// dynamic 返回null不会报错
dynamic getTest(bool flag) {
  return flag ? 10 : null;
}

Future<void> jsonTest() async {
  final repo = await Repo.fromRepoPath('ddd', createIfNoExists: true);

  final client = Client(id: "abc", name: "abcname");

  final client2 = Client.fromJson(jsonDecode(jsonEncode(client)));

  print(client2.name);

  final client3 = Client.fromJson(client.toJson());
  print(client3.name);
}
