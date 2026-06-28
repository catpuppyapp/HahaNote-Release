
import 'dart:io' show Directory, File;

import 'package:cloud_disk_note_app/cloud_disk_note/storage/utils.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  // 测试linux /tmp目录是否可直接创建文件并读写，结果：能，无需特殊权限
  final tempDir = Directory("/tmp/HahaNoteTempTest")..createSync(recursive: true);
  final tempFile = File(p.join(tempDir.absolute.path, "tempFile12345"));
  await writeStrToFile(tempFile, "test auto create Nonexistents dirs");

}
