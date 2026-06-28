import 'dart:io';

import 'package:process_runner/process_runner.dart';

Future<void> main() async {
  ProcessRunner processRunner = ProcessRunner();
  // final workingDirPath = r"替换成你的git仓库目录";
  final workingDirPath = r"./";
  final workingDir = Directory(workingDirPath);
  var resultcmd = await processRunner.runProcess(["git", "-C", workingDirPath, "branch", '--format=%(if)%(HEAD)%(then)%(refname:short)|%(upstream:short)|%(upstream:track)%(end)'], workingDirectory: workingDir);
  // 输出："main|origin/main|[ahead 1, behind 5]"，若本地和远程一样，则没有最后一个ahead和behind，输出 "main|origin/main|"，以上命令对非HEAD分支会输出空行，所以需要trim
  var out = resultcmd.stdout.trim();
  print("out1: $out");
  print("out1: ${out.length}");

  resultcmd = await processRunner.runProcess(["git", "-C", workingDirPath, "status", "--porcelain=v1", "-z", "-unormal"], workingDirectory: workingDir);
  out = resultcmd.stdout.trim();
  print("out2: $out");
  print("out2: ${out.length}");
}
