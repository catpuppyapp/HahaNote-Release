import 'dart:convert';

import 'package:hahanote_app/db/entity/repo_entity.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';

// 注：用debug模式测试，否则不会抛异常，可能因为hive在单独isolate使用？
Future<void> main() async {
  final Map<String, dynamic> repoMap = {"id":"abc"};
  print(RepoEntity.fromJson(repoMap).lastUpdate);
  print(RepoEntity.fromJson(jsonDecode(jsonEncode(repoMap))).lastUpdate);
  print(RepoEntity.fromJson(jsonDecode(jsonEncode(repoMap))).name.isEmpty);


  // 提供目录名即可
  Hive.init("test/res");
  // Hive.registerAdapters();
  // 会创建 myBox.hive和myBox.lock
  // 文件名会强制转成全小写，所以不要用驼峰，用 my_box 这种格式
  final box = await Hive.openBox("myBox");
  await box.put("ints", [1,2,3]);
  // hive可直接存int数组
  print(await box.get("ints"));
  // return;
  box.put("r", [RepoEntity(path: 'abc/def').toJson()]);
  final List<Map<String, dynamic>> r = box.get("r");
  print(r);
  print(ThemeMode.system.toString());
  // box.put("abc", 123);
  // print(box.get("abc"));

  // box.put("tm", ThemeMode.system);
  // print(box.get("tm"));
  // 报错，说没写对应类型的适配器
  // box.put('time', TimeData.now());
  // print(box.get("time"));

  // 这个写了适配器并且在上面调用了Hive.registerAdapters()，所以就不会出错了
  // box.put("repo", RepoEntity(path: FilePath.fromString('abc').toUnixPathStr()));
  // print(box.get("repo"));

  // 只删打开的
  // await Hive.deleteFromDisk();

  // 打开与否都可删除且不存在的box不会报错
  await Hive.deleteBoxFromDisk('not_exists');  // 不报错
  await Hive.deleteBoxFromDisk('mybox');  // 存在的，正常删除
}
