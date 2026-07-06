import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/app.dart' show App;
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/http.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart' show RemoteConfig, RemoteConfigDataForLocalDir;
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:hahanote_app/hahanote_lib_sync/string_ext.dart';
import 'package:hahanote_app/hahanote_lib_sync/time/time_data.dart';
import 'package:process_runner/process_runner.dart';

import '../../util/util.dart';


const _TAG = "local_dir.dart";

/// local dir as remote
class LocalDir extends Remote {
  
  @override
  RemoteType get type => RemoteType.localDir;

  @override
  bool supportAutoCreateNonexistsPath = true;

  @override
  bool isChild;

  @override
  bool isLockUploader;

  @override
  FilePath basePath;

  @override
  String pathSeparator;

  RemoteConfigDataForLocalDir config;



  LocalDir({
    required this.basePath,
    String? pathSeparator,
    required this.config,
    this.isChild = false,
    this.isLockUploader = false
  }) : pathSeparator = pathSeparator ?? Platform.pathSeparator;


  @override
  Future<void> doInit(
    TempDir tempDir, {
    DetermineResult? determineResult,
    Future<bool> Function(Remote)? onReady,
    required int packMaxLen,
  }) async {
    await super.doInit(tempDir, determineResult: determineResult, onReady: onReady, packMaxLen: packMaxLen);

    if(onReady != null && !await onReady(this)) {
      return;
    }

    // 先创建目录，不然git pull定位的目录不存在，就报错了
    await mkdir(basePath.copy());

    // 若是git backend，主线程需pull一下，子线程不需要，因为间隔时间不长，若子也pull，短时间执行两次，无意义
    if(isChild) {
      return;
    }

    // await testEmptyDirCheck(remoteRoot: r"remote_repos_root_path");
    await gitPull();
  }

  @override
  Future<void> downloadToFile(FilePath path, File file, TempDir tempDir) async {
    App.logger.debug(_TAG, "#download(): downloading '$path'");
    if(isLockUploader) {
      await gitPull();
    }

    final fullPath = await preHandlePath(path, makeSureParentExists: false);
    final srcFile = fullPath.toFile();
    final tempFile = await tempDir.createTempFile();
    await srcFile.copy(tempFile.absolute.path);

    // make sure parent dirs exists
    await file.parent.create(recursive: true);

    await tempFile.rename(file.absolute.path);
  }

  @override
  Future<List<RemoteFile>> listFiles(FilePath path) async {
    final fullPath = await preHandlePath(path);
    final fileType = await getFileType(fullPath.toString());
    if(fileType == FileSystemEntityType.file) {
      final f = fullPath.toFile();
      return [
        RemoteFile(
          isDir: false,
          name: fullPath.name(),
          path: FilePath.fromString(f.absolute.path),
          mTimeMs: (await f.lastModified()).millisecondsSinceEpoch,
          length: (await f.length())
        )
      ];
    }else if(fileType == FileSystemEntityType.directory) {
      final dir = fullPath.toDir();
      final result = <RemoteFile>[];

      await for(final f in dir.list(followLinks: false)) {
        final absPath = FilePath.fromString(f.absolute.path);
        if(f is File) {
          result.add(await RemoteFile.fromFile(f, absPath));
        }else if(f is Directory) {
          result.add(await RemoteFile.fromDir(f, absPath));
        }

        // 忽略非文件非目录的特殊文件
        // else {
        //   // 非文件，非目录，什么类型？快捷方式之类的？
        //   final stat = await f.stat();
        //   result.add(
        //     RemoteFile(
        //       isDir: false,
        //       name: p.basename(f.path),
        //       path: FilePath.fromString(f.absolute.path),
        //       mTimeMs: stat.modified.millisecondsSinceEpoch,
        //       length: 0
        //     )
        //   );
        // }
      }

      return result;
    }

    return [];
  }

  @override
  Future<void> uploadFile(FilePath path, File file, {bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) async {
    App.logger.debug(_TAG, "#uploadFile(): uploading '${file.absolute.path}' to '$path'");
    await throwIfFileIsNotEmptyOrEncrypted(file);

    final fullPath = await preHandlePath(path);

    final tempFile = await getFileAndMakeSureParentDirExist(genRemoteTempFilePath().toString());

    await file.copy(tempFile.absolute.path);
    await tempFile.rename((await fullPath.makeSureParentExists()).toString());

    if(gitPushIfNeed && isLockUploader) {
      await gitPush("push_lock");
    }
  }

  @override
  Future<void> delete(FilePath path, {required bool isDir, bool gitPushIfNeed = true}) async {
    final fullPath = await preHandlePath(path);

    // 其实删文件和目录都能转换成目录删，不过还是不这么写了，不严谨
    // await fullPath.toDir().delete(recursive: true);

    if(isDir) {
      // 若不存在，删除会报错
      await fullPath.toDir().delete(recursive: true);
    }else {
      final file = fullPath.toFile();
      if(await file.exists()) {  // 判断存在是为了避免期望删文件时误删目录
        await file.delete(recursive: true);  // 递归是为了避免有些文件删除失败，原因不明，但递归就能删除
      }else {
        // 若路径存在，但类型不是File，exists也会返回假，然后抛出此异常
        throw RemoteNotFoundException("file not found: ${fullPath.toUnixPathStr()}");
      }
    }

    if(gitPushIfNeed && isLockUploader) {
      await gitPush("delete_lock");
    }
  }

  @override
  Future<void> mkdir(FilePath path) async {
    final fullPath = await preHandlePath(path, makeSureParentExists: false);

    App.logger.debug(_TAG, "#mkdir(): '$fullPath'");

    await Directory(fullPath.toString()).create(recursive: true);
  }

  @override
  Future<void> rename(FilePath from, FilePath to, {required bool isDir, bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) async {
    final fromFullPathStr = (await preHandlePath(from)).toString();
    final toFullPathStr = (await preHandlePath(to)).toString();

    // make sure is dir or file and get type
    final fileType = await throwIfPathIsNotFileOrDir(fromFullPathStr, 15737493);

    // make sure parent exists
    await getFileAndMakeSureParentDirExist(toFullPathStr);

    if(fileType == FileSystemEntityType.file) {
      // 文件若存在会自动删除再执行rename
      await File(fromFullPathStr).rename(toFullPathStr);
    }else {
      // dir
      // 目录若存在，不会自动覆盖，需要先删除目标目录
      // 但是：若路径存在，不应自动删除然后rename，这样容易误删文件，
      // 所以直接rename，若出错的原因是目标路径存在，
      // 用户可自行调用remote.delete，然后再调用rename
      // final toDir = Directory(toFullPathStr);
      // if(await toDir.exists()) {
      //   await toDir.delete(recursive: true);
      // }

      // 再rename
      await Directory(fromFullPathStr).rename(toFullPathStr);
    }

    if(gitPushIfNeed && isLockUploader) {
      await gitPush("rename_file");
    }
  }


  @override
  Future<void> copy(FilePath from, FilePath to, {required bool isDir, bool tryCreateParentsIfNeed = true, bool gitPushIfNeed = true}) async {
    if(isDir) {
      throw RemoteException("not support copy dir, 13628963");
    }

    await (await preHandlePath(from)).toFile().copy((await (await preHandlePath(to)).makeSureParentExists()).toString());

    if(gitPushIfNeed && isLockUploader) {
      await gitPush("copy_file");
    }
  }

  @override
  Future<bool> exists(FilePath path) async {
    if(isLockUploader) {
      await gitPull();
    }

    return (await preHandlePath(path, makeSureParentExists: false)).exists();
  }


  @override
  Future<RemoteFile> getMetadata(FilePath path) async {
    final fullPath = await preHandlePath(path);
    final type = await getFileType(fullPath.toString());
    if(type == FileSystemEntityType.notFound) {
      throw RemoteNotFoundException("not found, path: $path, err code: 17767066");
    }else if(type == FileSystemEntityType.file) {
      return await RemoteFile.fromFile(fullPath.toFile(), path);
    }else if(type == FileSystemEntityType.directory) {
      return await RemoteFile.fromDir(fullPath.toDir(), path);
    }

    throw RemoteException("file type is not supported: $type, err code: 19263378");
  }

  @override
  Future<void> doGitPull() async {
    if(!isLockUploader) {
      return;
    }

    if(!config.isGitBackend) {
      return;
    }

    // 避免短期内重复执行pull
    var nowInMs = TimeData.now().utcMs;
    if(nowInMs - lastGitPullAtInMs < gitPullIntervalInMs) {
      return;
    }

    lastGitPullAtInMs = nowInMs;

    final actName = "git pull";

    if(Platform.isAndroid) {
      await HttpUtil.sendPuppyGitHttpRequest(
        caller: type.value,
        actName: actName,
        url: config.gitPullUrl
      );
    }else {
      final workingDir = basePath.toDir();
      final workingDirPath = basePath.toString();

      ProcessRunner processRunner = ProcessRunner(defaultWorkingDirectory: workingDir);
      ProcessRunnerResult result = await runCmd(["git", "-C", workingDirPath, "pull"], runner: processRunner, workingDirectory: workingDir);

      App.logger.debug(_TAG, '$actName: git pull, stdout: ${result.stdout}');
      App.logger.debug(_TAG, '$actName: git pull, stderr: ${result.stderr}');

      if(result.exitCode != 0) {
        throw "$actName err:\nstderr=${result.stderr}\nstdout=${result.stdout}";
      }

      // Print interleaved stdout/stderr（交叉输出stdout/stderr，顺序可能会混在一起）:
      // App.logger.debug(_TAG, 'combined: ${result.output}');
    }
  }

  @override
  Future<void> doGitPush(String gitCommitMsg, {bool must = false}) async {
    if(!must && !isLockUploader) {
      return;
    }

    if(!config.isGitBackend) {
      return;
    }

    final actName = "git push";

    if(gitCommitMsg.isEmpty) {
      throw "$actName err: git commit msg cannot be empty";
    }

    if(Platform.isAndroid) {
      await HttpUtil.sendPuppyGitHttpRequest(
        caller: type.value,
        actName: actName,
        // 追加reset参数，不然的话，如果冲突，这边会dirty，还得手动去ppgit重置，麻烦
        // 末尾加冒号是为了避免提交信息和ppgit自动生成的粘连在一起，无法区分
        url: Remote.handleGitPushUrl(config.gitPushUrl, "$gitCommitMsg:")
      );
    }else {
      final workingDir = basePath.toDir();
      // 注：参数不能用引号包裹，会报错，就传普通的字符串就行
      final workingDirPath = basePath.toString();

      ProcessRunner processRunner = ProcessRunner(defaultWorkingDirectory: workingDir);
      ProcessRunnerResult? result;


      // 若输出非空，则有需要提交的文件，否则没有
      // `git status --porcelain=v1` 或 `git status -z -uall`都行，其中 -z代表使用\0分割输出(代码解析：output.split('\0'))，-uall的作用是列出目录中的每个文件的路径，否则默认只列目录名
      // porcelain据说是专为机器解析设计，输出更稳定，v1格式输出简洁，v2丰富（包含hash），这里用v1即可
      // 追加 -unormal 参数是为了避免用户修改配置文件导致git status默认输出等同于 -uall
      // 附注：git config status.showUntrackedFiles all，此命令会使仓库执行git status行为默认等同于追加了 -uall
      // 最终采用：`git status --porcelain=v1 -z -unormal`，用-unormal而不是-uall是因为我不需要文件路径，只要知道有文件需要提交即可，若需要文件路径，则需使用-uall参数替换-unormal
      result = await runCmd(["git", "-C", workingDirPath, "status", "--porcelain=v1", "-z", "-unormal"], runner: processRunner, workingDirectory: workingDir);
      App.logger.debug(_TAG, '$actName: git status, stdout: ${result.stdout}');
      App.logger.debug(_TAG, '$actName: git status, stderr: ${result.stderr}');
      // 如果有需要提交的文件，则addThenCommit
      if(result.stdout.isNotEmpty) {
        result = await runCmd(["git", "-C", workingDirPath, "add", "-A"], runner: processRunner, workingDirectory: workingDir);
        App.logger.debug(_TAG, '$actName: git add, stdout: ${result.stdout}');
        App.logger.debug(_TAG, '$actName: git add, stderr: ${result.stderr}');
        result = await runCmd(["git", "-C", workingDirPath, "commit", "-m", gitCommitMsg], runner: processRunner, workingDirectory: workingDir);
        App.logger.debug(_TAG, '$actName: git commit, stdout: ${result.stdout}');
        App.logger.debug(_TAG, '$actName: git commit, stderr: ${result.stderr}');
      }

      // 检查ahead和behind，和上游，若无上游则抛异常，若无ahead和behind，则不需要推送
      // 注意那个--format，不要改成--format="格式化字符串"这样，要把整个--format用字符串包起来，不然输出会变成包含引号的，例如"main|origin/main"那样
      // 因为包含引号，所以后面判断不是否需要推送总会得到“需要推送”的结果，因此性能才差
      // 获取当前分支和上游已经ahead, behind的命令：git branch "--format=%(if)%(HEAD)%(then)%(refname:short)|%(upstream:short)|%(upstream:track)%(end)"
      // 格式：本地分支|远程分支|领先落后
      // 输出类似：master|origin/master|[ahead 1, behind 1]
      // 若无对应条目，则对应栏位为空，例如无上游则会输出：master||
      result = await runCmd(["git", "-C", workingDirPath, "branch", "--format=%(if)%(HEAD)%(then)%(refname:short)|%(upstream:short)|%(upstream:track)%(end)"], runner: processRunner, workingDirectory: workingDir);
      // 输出："main|origin/main|[ahead 1, behind 5]"，若本地和远程一样，则没有最后一个ahead和behind，输出 "main|origin/main|"，以上命令对非HEAD分支会输出空行，所以需要trim
      final out = result.stdout.trim();
      // idx 0, local branch; 1, upstream branch short name; 2, ahead and behind count
      final localAndUpstreamAndAheadBehind = out.split("|");
      if(localAndUpstreamAndAheadBehind.length < 3) {
        throw "$actName: parse local branch and upstream err, command output is: $out";
      }
      final upstream = localAndUpstreamAndAheadBehind[1];
      if(upstream.isEmpty) {
        throw "$actName: parse upstream err: upstream is empty";
      }

      final aheadBehindCnt = localAndUpstreamAndAheadBehind[2];
      // if(!aheadBehindCnt.contains("ahead")) {
      if(aheadBehindCnt.isEmpty) {
        App.logger.debug(_TAG, "$actName: no need to push, because no ahead or behind");
        return;
      }

      try {
        result = await runCmd(["git", "-C", workingDirPath, "push"], runner: processRunner, workingDirectory: workingDir);

        App.logger.debug(_TAG, '$actName: git push, stdout: ${result.stdout}');
        App.logger.debug(_TAG, '$actName: git push, stderr: ${result.stderr}');
        // 貌似就算不检查exitCode，只要不是0，就会抛异常，所以我检查并抛异常的代码应该是可有可无的
        if(result.exitCode != 0) {
          throw "$actName err:\nstderr=${result.stderr}\nstdout=${result.stdout}";
        }

        // 确保本地分支和远程一致，避免有的平台推送失败可能不报错
        // `git rev-parse HEAD "HEAD@{upstream}"` 会输出两行，第一行是本地分支提交号，第2行是远程分支提交号
        result = await runCmd(["git", "-C", workingDirPath, "rev-parse", "HEAD", "HEAD@{upstream}"], runner: processRunner, workingDirectory: workingDir);
        final out = result.stdout.trim().splitByLineBreak(trimAndDropEmpty: true);
        if(out.length < 2) {
          throw "$actName: query branch info err after pushing, branch command output: $out";
        }

        // 注：这里其实获取远程和本地的分支，然后对比下提交号就行，不必计算ahead和behind，但我懒得去找对应的命令了，先这样吧
        // index 2是[ahead n, behind m]，推送后此栏位应为空，若不为空，则代表推送失败了
        if(out[0] != out[1]) {
          throw "$actName: local branch and upstream branch are not same after pushing, maybe push failed, branch command output: $out";
        }

      }catch(e) {
        // 推送失败，尝试回滚，不然git工作目录dirty
        try {
          result = await runCmd(["git", "-C", workingDirPath, "reset", '--hard', upstream], runner: processRunner, workingDirectory: workingDir);

          App.logger.debug(_TAG, '$actName: git reset, stdout: ${result.stdout}');
          App.logger.debug(_TAG, '$actName: git reset, stderr: ${result.stderr}');
          // x 不需要,reset hard会把所有提交的文件都重置，而之前提交了全部，所以reset hard就够了）删除没推送的文件: git clean -fd <path>
          // 其中 -fd，f是force，d是dir，默认只删文件，加了d的话，目录一起删
          // result = await runCmd(["git", "-C", workingDirPathQuoted, "clean", '-fd', workingDirPathQuoted], runner: processRunner, workingDirectory: workingDir);
          App.logger.debug(_TAG, '$actName: git push failed but reset hard successfully, workdir of git repo should be clean and fast-forwardable');

        }catch(e, st) {
          App.logger.err(_TAG, '$actName: git push failed and reset hard failed: $e\n$st');
        }

        // 重新抛出push失败的异常
        rethrow;
      }
    }

  }

  @override
  Future<RemoteConfig> toRemoteConfig() async {
    // 这个basePath其实用对应平台的分隔符也行，就是调用 bastPath.toString()，
    // 不过，为了统一格式，存配置文件的时候就强制用unix字符串了
    return RemoteConfig(type: type.value, basePath: basePath.toUnixPathStr(), data: config.toJson());
  }


}
