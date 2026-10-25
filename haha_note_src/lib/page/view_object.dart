import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hahanote_app/config/app_config.dart';
import 'package:hahanote_app/db/db.dart';
import 'package:hahanote_app/db/entity/repo_entity.dart';
import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/pack/obj_pack.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/repo.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/temp/temp_dir.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/state/my_page_state.dart' show MyPageState;
import 'package:hahanote_app/ui/ui.dart' show UI;
import 'package:hahanote_app/util/diff_data.dart';
import 'package:hahanote_app/util/fs.dart' show Fs;
import 'package:hahanote_app/util/reveal_file.dart';
import 'package:hahanote_app/widget/base_layout.dart';
import 'package:hahanote_app/widget/dialogs.dart' show Dialogs;
import 'package:hahanote_app/widget/diff_view.dart';
import 'package:path/path.dart' as p;

import '../bean/bean.dart';
import '../native_util/open_file.dart';
import '../util/util.dart';
import '../widget/pull_to_refresh_list.dart';

const _TAG = "view_object.dart";


class ViewObjectPage extends StatefulWidget {
  // 文件的相对路径
  final String path;
  final String oid;
  final String oidRight;  // 用于将来实现和任意oid比较，不过暂时只有和workdir比较
  const ViewObjectPage({
    super.key,
    required this.path,
    required this.oid,
    String? oidRight,
  }) : oidRight = oidRight ?? VersionOid.specialOidValueWorkdir;

  @override
  State<ViewObjectPage> createState() => _ViewObjectPageState();

}

class _ViewObjectPageState extends MyPageState<ViewObjectPage> {
  RepoEntity? openedRepo;
  // 这个tempDir可以清，是存解密后的本地文件的，不是用来存下载到downCache的文件的（不可清，且不在这管理）
  TempDir? tempDir;
  // 执行操作出错，设置这个字段，若文件加载出错，所有操作不可用，设置的是super.pageErr
  String err = '';
  // widget.path，文件在仓库下的相对路径
  late final String path;
  late final VersionOid oid;
  late final String shortOid;
  late final VersionOid oidRight;
  late final String shortOidRight;
  File? objFile;
  File? objFileRight;
  // 仓库路径加相对路径widget.path，拼接成的绝对路径
  String workdirFilePath = '';
  bool menuVisible = true;
  bool view = false;
  bool diff = false;
  bool showLineNum = false;
  bool neverShowLineNumIncorrectNote = AppConfig.getConfig().neverShowLineNumIncorrectNoteInDiffView;
  bool neverShowBlankLinesMayBeIgnored = AppConfig.getConfig().neverShowBlankLinesMayBeIgnoredInDiffView;
  String? objFileTextRight;
  String? objFileText;
  FileStat objFileStatRight = FileStat();
  FileStat objFileStat = FileStat();
  bool workdirFileExists = false;
  String objFileSize = "";
  String objFileSizeRight = "";
  String objFilePath = "";
  String objFilePathRight = "";
  String workdirFileName = "";
  bool loadingContent = false;
  String loadingContentErr = "";
  TextEditingController exportPath = TextEditingController(text: "");
  DiffData? diffData;
  bool firstTimeClickViewOrDiff = true;
  final GlobalKey<DiffViewState> diffViewStateKey = GlobalKey();
  final diffViewScrollController = ScrollController();


  void showLineNumAndBlankLinesIgnoredNoteIfNeed(bool diffContentVisible) {
    if(!diffContentVisible) {
      return;
    }

    if(showLineNum && neverShowLineNumIncorrectNote) {
      neverShowLineNumIncorrectNote = false;
      showMsg(t.lineNumIncorrectNote);
    }

    if(neverShowBlankLinesMayBeIgnored) {
      neverShowBlankLinesMayBeIgnored = false;
      showMsg(t.blankLinesMayBeIgnored);
    }

    if(AppConfig.getConfig().neverShowLineNumIncorrectNoteInDiffView || AppConfig.getConfig().neverShowBlankLinesMayBeIgnoredInDiffView) {
      AppConfig.update((it) async {
        it.neverShowLineNumIncorrectNoteInDiffView = neverShowLineNumIncorrectNote;
        it.neverShowBlankLinesMayBeIgnoredInDiffView = neverShowBlankLinesMayBeIgnored;
      });
    }
  }

  @override
  void initState() {
    super.initState();

    path = widget.path;
    workdirFileName = p.basename(path);
    oid = VersionOid(value: widget.oid);
    shortOid = oid.shortValue();
    oidRight = VersionOid(value: widget.oidRight);
    shortOidRight = oidRight.shortValue();
    showLineNum = AppConfig.getConfig().showLineNumInDiffView;

    _doInit();

  }

  @override
  void dispose() {
    // 在后台慢慢删吧，不用await
    tempDir?.clean();
    exportPath.dispose();

    super.dispose();
  }


  @override
  bool handleKeyPress(KeyEvent event, bool isControlDown, bool isAltDown, bool isShiftDown) {
    final pressedKey = event.logicalKey;

    // 退出选择模式
    if(pressedKey == LogicalKeyboardKey.escape
        && !isControlDown && !isAltDown && !isShiftDown
        && mounted
    ) {
      if(backHandler()) {
        return true;
      }
    }

    if(pressedKey == LogicalKeyboardKey.f5 && !isControlDown && !isAltDown && !isShiftDown) {
      refresh();
      return true;
    }

    return false;
  }

  Future<void> _doInit() async {
    await _loadObjFile(oid, isLeft: true);
    await _loadObjFile(oidRight, isLeft: false);
  }


  Future<void> _loadObjFile(VersionOid oid, {required bool isLeft}) async {
    final leftOrRight = getLeftOrRightText(isLeft);

    // 排除deleted，把deleted当空文件处理
    if(oid.value != VersionOid.deleted.value && ObjRef.isInvalidOid(oid.value)) {
      setState(() {
        pageErr = "invalid $leftOrRight oid: ${oid.value}";
      });

      return;
    }

    // 若文件加载出错，所有操作不可用，设置的是super.pageErr
    // 不直接使用pageErr，因为每次调用 doActWithPageLoading()，pageErr都会重置
    await doActWithPageLoading(
      actName: "load object file",
      act: () async {
        final repoFromDb = await Db.getOpenedRepo();
        openedRepo = repoFromDb;
        if(repoFromDb == null) {
          setState(() {
            err = "Opened repo is null";
          });
          return;
        }

        // 设置workdir文件信息
        if(workdirFilePath.isEmpty) {
          workdirFilePath = FilePath.canonicalizePath(p.join(repoFromDb.path, path));
          workdirFileExists = await File(workdirFilePath).exists();
        }

        // initTempDir
        await initTempDir();

        // fetch obj of the oid
        final objectFile = oid.isWorkdir() ? (await getWorkdirFile()) : (await _getOrFetchObj(oid));
        if(!await objectFile.exists()) {
          throw AppException("get $leftOrRight object failed, file doesn't exist, err code: 16760530");
        }

        if(isLeft) {
          objFile = objectFile;
          objFileSize = Fs.readableSize(await objectFile.length());
          objFilePath = FilePath.canonicalizePath(objectFile.absolute.path);
        }else {
          objFileRight = objectFile;
          objFileSizeRight = Fs.readableSize(await objectFile.length());
          objFilePathRight = FilePath.canonicalizePath(objectFile.absolute.path);
        }

      }
    );

    refreshUI();
  }

  // 若文件存在，返回，若不存在，创建空的临时文件替代
  // 用空文件替代 deleted oid和workdir文件不存在的情况，以简化逻辑
  // 注：当workdir文件存在时，此函数返回的是workdir对应文件的本体，不是拷贝
  Future<File> getWorkdirFile() async {
    final file = File(workdirFilePath);
    if(await file.exists()) {
      return file;
    }

    return await tempDir!.createTempFile();
  }

  Future<void> initTempDir() async {
    final repo = await Repo.open(openedRepo!.path);
    if(tempDir == null) {
      tempDir = await repo.createTempDir("localObj");
    }
  }


  // @Deprecated("导出的是文件，但这个是让选文件夹的路径，反直觉，弃用")
  // Future<void> _exportDialogSelectDir() async {
  //   // android or other
  //   final String? directoryPath = await getDirectoryPath();
  //   App.logger.debug(_TAG, "directoryPath: $directoryPath");
  //   if (directoryPath == null) {
  //     // user canceled
  //     return;
  //   }
  //
  //   // 取出 ext，带.
  //   final nameWithoutExt = p.basenameWithoutExtension(path);
  //   final ext = p.extension(path);
  //
  //   // 若文件存在，会覆盖
  //   await _restoreToPath(
  //     p.join(directoryPath, '$nameWithoutExt (ver $shortOid)$ext'),
  //   );
  // }

  // if compare a to b, return b; (clicked from file history compare to previous)
  // if compare a to workdir, return a. (clicked from file history compare to workdir)
  File? getExpectedFile() {
    return oidRight.isWorkdir() ? objFile : objFileRight;
  }

  VersionOid getExpectedOid() {
    return oidRight.isWorkdir() ? oid : oidRight;
  }

  String getExpectedFilePath() {
    return oidRight.isWorkdir() ? objFilePath : objFilePathRight;
  }

  // this size always expect show file size that clicked in file history page
  // if compare obj to workdir, show obj file size; (the left obj file is the clicked item)
  // if compare obj1 to obj2, show obj2 file size.  (the right obj file is the clicked item)
  String getExpectedFileSize() => oidRight.isWorkdir() ? objFileSize : objFileSizeRight;

  // export to specified path
  Future<void> _export() async {
    final srcFile = getExpectedFile();
    // srcFile为null，无文件可导出，返回
    if(srcFile == null) {
      showMsgLong("src file is null");
      return;
    }

    final directoryPath = File(workdirFilePath).parent.absolute.path;
    final nameWithoutExt = p.basenameWithoutExtension(workdirFilePath);
    // 取出 ext，带.，例如 abc.txt，ext为.txt
    final ext = p.extension(workdirFilePath);
    final suggestedName = '$nameWithoutExt (ver $shortOid)$ext';
    final initFilePath = FilePath.canonicalizePath(p.join(directoryPath, suggestedName));

    await exportToFile(
      callerTag: _TAG,
      showMsg: showMsg,
      showMsgLong: showMsgLong,
      // for save
      suggestedName: suggestedName,
      // 不一定会被应用，比如我设置的 路径是  C:/abc_1，可能显示 C:/abc
      initDirPath: directoryPath,

      context: context,
      // 生成文件名，默认在workdirFile的相同路径下，带 (ver 版本号)
      directoryPath: directoryPath,
      initFilePath: initFilePath,
      exportPath: exportPath,
      refreshUI: refresh,
      doExport: (destPath, trueSaveAsFalseExport) async {
        // e.g. export to userSelectedDir/abc (ver abcdef123).txt
        // 若文件存在，会询问是否覆盖

        // if is save as, system dialog will show overwrite ask dialog when file exists
        // if is export, need show that ask by ourself
        bool canceled = false;
        if(!trueSaveAsFalseExport && (await File(destPath).exists())) {
          bool isOk = await Dialogs.showOkOrNoDialog(
            context,
            title: t.overwrite,
            text: t.fileAlreadyExistsOverwriteAsk,
            onOk: (){}
          );

          canceled = !isOk;
        }

        // 询问若存在是否覆盖，用户选择取消
        if(canceled) {
          return;
        }

        await _restoreToPath(
          getExpectedFilePath(),
          destPath,
          trueIsRestoreFalseIsExport: false,
          srcOid: getExpectedOid(),
        );
      }
    );
  }

  // restore to workdir
  Future<void> _restore() async {
    if(workdirFilePath.isEmpty) {
      showMsg("workdir file path is empty");
      return;
    }

    await Dialogs.showOkOrNoDialog(
      context,
      title: t.restore,
      text: t.areYouSure,
        onOk: () {
          doActWithPageLoading(
            actName: "restore objects",
            act: () async {
              await _restoreToPath(
                getExpectedFilePath(),
                workdirFilePath,
                trueIsRestoreFalseIsExport: true,
                srcOid: getExpectedOid(),
              );
            }
          );
        }
    );
  }

  Future<void> _restoreToPath(
    final String srcFullPath,
    final String destFullPath, {
    required final bool trueIsRestoreFalseIsExport,
    // 虽然恢复目标是路径，但比较的是两个oid，所以src必然有关联的oid，
    // 这里接收这个参数是为了判断源oid是否是deleted，若是则删除dest path关联的文件
    required VersionOid srcOid,
  }) async {
    final srcCanonicalFullPath = FilePath.canonicalizePath(srcFullPath);
    if(srcCanonicalFullPath.isEmpty) {
      showMsgLong("src path is empty");
      return;
    }

    final destCanonicalFullPath = FilePath.canonicalizePath(destFullPath);
    if(destCanonicalFullPath.isEmpty) {
      showMsgLong("dest path is empty");
      return;
    }

    if(srcCanonicalFullPath == destCanonicalFullPath) {
      showMsgLong("src and dest are the same");
      return;
    }

    setState(() {
      pageLoading = true;
      pageErr = "";
      pageErrClosable = false;
    });

    try {
      final openedRepo = this.openedRepo;
      if(openedRepo == null) {
        showMsg("repo is null");
        return;
      }

      final srcObjFile = File(srcCanonicalFullPath);

      // 若是恢复且oid是删除，则删除对应条目；
      // 否则，则导出包含对应数据的文件到指定路径（若oid是删除则导出空文件）
      if(trueIsRestoreFalseIsExport && srcOid.isDeleted()) {
        await deleteFileIfExists(File(destCanonicalFullPath));
        showMsgLong("${t.deleted}: $destCanonicalFullPath");
      }else {
        await getFileAndMakeSureParentDirExist(destCanonicalFullPath);
        await srcObjFile.copy(destCanonicalFullPath);
        showMsgLong("${t.success}: $destCanonicalFullPath");
      }

    }catch(e) {
      pageErr = e.toString();
      pageErrClosable = true;
    }finally {
      setState(() {
        pageLoading = false;
      });

      // 如果恢复或导出到正在对比的文件路径，则需要重载diff文本
      if(destCanonicalFullPath == objFilePath
        || destCanonicalFullPath == objFilePathRight) {
        await _loadDiffText();
      }
    }
  }

  Future<File> _getOrFetchObj(VersionOid oid) async {
    final file = await _doGetOrFetchObj(oid);
    final ext = p.extension(workdirFileName);
    // 若文件以.结尾，后缀名就会是.，这样的后缀没什么意义，所以放弃
    if(ext.isNotEmpty && ext != ".") {
      // 让临时文件和工作目录的保持相同的后缀，这样的话，比如预览图片，方便外部程序分辨类型
      return await file.rename(file.absolute.path+ext);
    }else {
      return file;
    }
  }

  // 若返回空文件，则对应oid关联的内容本来就为空 或者 oid无效（例如oid为Deleted）
  // 若对应obj不存在，抛异常
  Future<File> _doGetOrFetchObj(VersionOid oid) async {
    final repo = await Repo.open(openedRepo!.path);
    var tempDir = this.tempDir!;

    // 无效oid，创建个空文件即可
    if(ObjRef.isInvalidOid(oid.value)) {
      return await tempDir.createTempFile();
    }

    // 先检查本地是否有，若有则用
    File? file = await repo.getTypedLocalData(RemoteDataType.objects, oid, repo.getRemoteDataDirPath(), tempDir);
    if(file != null) {
      App.logger.debug(_TAG, "found cached files in local, will use it, object oid: $oid");
      return file;
    }

    App.logger.debug(_TAG, "local cache not found, will download it, object oid: $oid");


    // 从远程下载（有缓存，重复下载同一文件或在同一.pack的objects，性能不会太差）
    final fetchedData = await repo.fetchDataCachedWithLock(
      {oid},
      throwIfInterrupted: () {
        if(!mounted) {
          // 页面若卸载，取消下载任务，但有可能还是下载成功并且已经移动加密文件到正式 objects 目录了，无法保证
          throw AppException("page already disposed, task canceled: download object '$oid'");
        }
      },
      progressCb: (curAct, _, _, _) => setState(() => pageLoadingText = curAct),
    );

    file = fetchedData[oid.value];

    if(file == null) {
      throw RemoteNotFoundException("object not found: $oid");
    }

    // 把文件从 cache/downCache 下的temp目录移动到当前页面使用的temp目录，离开页面时就自动清理文件了
    return await file.rename((await tempDir.createTempFile()).absolute.path);
  }

  String getLeftOrRightText(bool isLeft) => isLeft ? "left" : "right";

  // 若内容未修改，返回false；否则返回true
  Future<bool> initTextOfObjFile({required bool isLeft}) async {
    final objFile = isLeft ? this.objFile : objFileRight;

    if(objFile == null) {
      showMsg("err: ${getLeftOrRightText(isLeft)} obj file is null");
      return false;
    }

    // use file stat to detect file loaded and not modified, if it is, then skip load text of the file
    // 用文件状态检测文件是否已加载且没被修改过，若是则跳过加载
    if(objFileStat == await FileStat.fromFile(objFile)) {
      return false;
    }

    // when reach here, file modified or first time loading
    final text = await Fs.readFileAsStr(objFile, returnEmptyIfFileDeleted: true);
    if(isLeft) {
      objFileText = text;
      objFileStat = await FileStat.fromFile(objFile);
    }else {
      objFileTextRight = text;
      objFileStatRight = await FileStat.fromFile(objFile);
    }

    return true;
  }

  Widget getViewWidget() {
    return Expanded(child: SingleChildScrollView(child: SelectableText(objFileText ?? '', style: TextStyle(fontSize: UI.editorFontSizeDefault),),));
  }

  Future<void> _loadDiffTextIfNeverLoad() async {
    if(diffData == null) {
      await _loadDiffText();
    }
  }

  Future<void> _loadDiffText({
    Future<void> Function()? onLoaded,
  }) async {
    if(loadingContent) {
      return;
    }

    // 不确定setState会不会立即调用回调函数，
    // 所以，先设置，后调用setState，确保非UI代码立刻可以检测到最新状态
    loadingContent = true;
    loadingContentErr = "";
    setState(() {});

    try {
      final objFileChanged = await initTextOfObjFile(isLeft: true);
      final objFileChangedRight = await initTextOfObjFile(isLeft: false);
      if(objFileChanged || objFileChangedRight) {
        final diffData = DiffData();
        diffData.oldText = objFileText ?? '';
        diffData.newText = objFileTextRight ?? '';
        diffData.init(previewOld: oidRight.isWorkdir());

        this.diffData = diffData;
      }
    }catch(e) {
      loadingContentErr = e.toString();
    }finally {
      setState(() {
        loadingContent = false;
      });
    }

    // do on loaded if no error
    if(loadingContentErr.isEmpty) {
      await onLoaded?.call();
    }

  }

  Widget getDiffWidget() {
    final preview = isPreview();
    final diffData = this.diffData;
    final list = diffData?.getLines(preview: preview) ?? [];

    return Expanded(
      flex: 6,
      child: PullToRefreshList(
        // 全设为假或空，目的是禁用，完全由child控制显示loading或错误
        loading: loadingContent,
        err: loadingContentErr,
        listIsEmpty: list.isEmpty,
        // 若diff 且列表为空，则内容相同；
        // 否则代表预览obj文本模式且列表为空，
        // 这时显示默认空列表文案即可，
        // 不过正常来说预览模式list不会为空，即使是空文件也会有个空行的
        listEmptyText: !preview && list.isEmpty ? t.contentsAreIdentical : null,
        onRefresh: () async {
          await refresh();
        },
        child: DiffView(
          key: diffViewStateKey,
          scrollController: diffViewScrollController,
          preview: preview,
          showMsg: showMsg,
          showLineNum: showLineNum,
          lines: list,
          oldLineNumWidth: diffData?.getOldLineNumWidth(preview: preview) ?? 0,
          newLineNumWidth: diffData?.getNewLineNumWidth(preview: preview) ?? 0,
        ),
      ),
    );
  }

  Future<void> _externalDiff(
    List<String> Function(String objFilePath, String objFileRightPath) genCmd,
  ) async {
    try {
      if(objFilePath.isEmpty) {
        throw "left obj path is empty";
      }

      if(objFilePathRight.isEmpty) {
        throw "right obj path is empty";
      }

      final cmd = genCmd(objFilePath, objFilePathRight);

      App.logger.debug(_TAG, "will call external diff tool, cmd: $cmd");

      await runCmd(cmd);

    }catch(e, st) {
      showMsgLong("err: $e");
      App.logger.debug(_TAG, "call external diff tool failed: $e\n$st");
    }
  }


  List<Widget> _getMenu() {
    return [
      Column(
        // 取消注释可让文本左对齐，但如果文件名很长，会撑起宽度，导致条目太偏左，很别扭，所以注释，
        // 注释此行则默认水平居中
        // crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 3),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text("${t.path}: "),
              SelectableText(path, style: TextStyle(fontWeight: FontWeight.w500)),
              // 垂直三点菜单
              PopupMenuButton<String>(
                onSelected: (action) async {
                  if(action == "copyObjectPath") {
                    copyTextThenShowMsg(objFilePath);
                  }else if (action == "copyObjPathRight") {
                    copyTextThenShowMsg(objFilePathRight);
                  }else if (action == "winMerge") {
                    final cmdName = "winmergeu";
                    await _externalDiff((objFilePath, objFileRightPath) {
                      // -e 按一次esc就可关闭窗口，使其行为表现的像Dialog
                      // -u 阻止添加文件到winmerge的最近文件列表
                      // 参见: https://manual.winmerge.org/en/Command_line.html
                      // ps. 这两个参数从.gitconfig里偷来的，应该是TortoiseGit加的这个配置
                      return [cmdName, "-e", "-u", objFilePath, objFileRightPath];
                    });
                  }else if (action == "meld") {
                    // 命令必须小写，不然linux不认，windows倒是无所谓大小写
                    final cmdName = "meld";
                    await _externalDiff((objFilePath, objFileRightPath) {
                      return [cmdName, objFilePath, objFileRightPath];
                    });
                  }else if (action == "kDiff3") {
                    final cmdName = "kdiff3";
                    await _externalDiff((objFilePath, objFileRightPath) {
                      return [cmdName, objFilePath, objFileRightPath];
                    });
                  }else if (action == "revealObj") {
                    revealFile(objFilePath, showMsgLong: showMsgLong);
                  }else if (action == "revealObjRight") {
                    revealFile(objFilePathRight, showMsgLong: showMsgLong);
                  }else if (action == "openObjAsText") {
                    _openWithInternalEditor(objFilePath, mime: mimeTextPlain);
                  }else if (action == "openObjAsTextRight") {
                    _openWithInternalEditor(objFilePathRight, mime: mimeTextPlain);
                  }else if (action == "openObjInExt") {
                    _openFileInExternal(objFilePath);
                  }else if (action == "openObjInExtRight") {
                    _openFileInExternal(objFilePathRight);
                  }
                },
                icon: Icon(Icons.more_vert, size: 18,), // 垂直三点图标
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  if(isPcPlatform()) ...[
                    PopupMenuItem<String>(
                      value: "winMerge",
                      child: Text("WinMerge"),
                    ),
                    PopupMenuItem<String>(
                      value: "meld",
                      child: Text("Meld"),
                    ),
                    PopupMenuItem<String>(
                      value: "kDiff3",
                      child: Text("KDiff3"),
                    ),
                    const PopupMenuDivider(),
                  ],
                  // 一般来说，rightOid，会比较可能是用户想要编辑的文件，
                  // 因为目标可能是workdir的最新版本内容，所以把rightOid放上面
                  PopupMenuItem<String>(
                    value: "openObjAsTextRight",
                    child: Text("${t.openAsText} [$shortOidRight]"),
                  ),

                  PopupMenuItem<String>(
                    value: "openObjInExtRight",
                    child: Text("${t.openInExt} [$shortOidRight]"),
                  ),
                  PopupMenuItem<String>(
                    value: "revealObjRight",
                    child: Text("${t.revealInFileExplorer} [$shortOidRight]"),
                  ),
                  PopupMenuItem<String>(
                    value: "copyObjPathRight",
                    child: Text("${t.copyPath} [$shortOidRight]"),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: "openObjAsText",
                    child: Text("${t.openAsText} [$shortOid]"),
                  ),
                  PopupMenuItem<String>(
                    value: "openObjInExt",
                    child: Text("${t.openInExt} [$shortOid]"),
                  ),
                  PopupMenuItem<String>(
                    value: "revealObj",
                    child: Text("${t.revealInFileExplorer} [$shortOid]"),
                  ),
                  PopupMenuItem<String>(
                    value: "copyObjectPath",
                    child: Text("${t.copyPath} [$shortOid]"),
                  ),

                ],
              ),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text("${t.size}: "),
              SelectableText(getExpectedFileSize(), style: TextStyle(fontWeight: FontWeight.w500))
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text("${t.oid}: "),
              SelectableText(getExpectedOid().shortValue(), style: TextStyle(fontWeight: FontWeight.w500))
            ],
          ),
        ],
      ),
      // 只有obj文件存在才显示view按钮
      if(objFile != null)
        const SizedBox(height: 10),
      if(objFile != null)
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 30,
          runSpacing: 10,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(value: view, onChanged: (newValue) async {
                  // 使diff view退出选择模式，不然若diff和view的内容行号不同，可能越界
                  diffViewStateKey.currentState?.quitSelection();

                  setState(() {
                    view = newValue;

                    if(!newValue) {
                      // 联动关闭diff按钮
                      diff = false;
                      // 确保关闭预览内容时，显示菜单，不然页面空白就尴尬了
                      menuVisible = true;
                    }

                    if(newValue && firstTimeClickViewOrDiff) {
                      // 第一次点预览或diff时，隐藏菜单
                      firstTimeClickViewOrDiff = false;
                      menuVisible = false;
                    }
                  });

                  if(newValue) {
                    await _loadDiffTextIfNeverLoad();
                  }
                }),
                Text(t.view),
              ],
            ),
            // 新逻辑修改为：若工作目录文件不存在且右oid是workdir，则会和空文件比较，所以diff按钮依然可以显示
            // if(workdirFileExists)  // 废弃逻辑：只有工作目录文件存在才显示diff按钮
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(value: diff, onChanged: (newValue) async {
                    // 使diff view退出选择模式，不然若diff和view的内容行号不同，可能越界
                    diffViewStateKey.currentState?.quitSelection();

                    setState(() {
                      diff = newValue;

                      // 联动打开view按钮
                      if(newValue && !view) {
                        view = true;
                      }

                      // 确保关闭预览内容时，显示菜单，不然页面空白就尴尬了
                      if(!newValue && !view) {
                        menuVisible = true;
                      }

                      if(newValue && firstTimeClickViewOrDiff) {
                        // 第一次点预览或diff时，隐藏菜单
                        firstTimeClickViewOrDiff = false;
                        menuVisible = false;
                      }

                      showLineNumAndBlankLinesIgnoredNoteIfNeed(newValue);
                    });

                    if(newValue) {
                      await _loadDiffTextIfNeverLoad();
                    }
                  }),
                  Text(t.diff)
                ],
              )
          ],
        ),
      // obj File存在才显示导出和restore
      if(objFile != null)
        const SizedBox(height: 10),
      if(objFile != null)
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 30,
          runSpacing: 10,
          children: [
            FilledButton(onPressed: _export, child: Text(t.export)),
            FilledButton(onPressed: _restore, child: Text(t.restore)),
          ],
        ),
      const SizedBox(height: 10),
    ];
  }

  Future<bool> _openWithInternalEditor(String path, {required String? mime}) async {
    return await openWithInternalEditor(path, mime: mime, callerTag: _TAG, context: context, showMsgLong: showMsgLong);
  }

  Future<void> _openFileInExternal(String path) async {
    await openFileInExternal(path, showMsgLong: showMsgLong, callerTag: _TAG);
  }

  bool backHandler() {
    final diffViewState = diffViewStateKey.currentState;
    if(diffViewState != null) {
      if(diffViewState.fontSizeAdjusterVisible) {
        diffViewState.saveAndCloseFontSizeAdjuster();
        return true;
      }
      if(diffViewState.selectionModeIsOn) {
        diffViewState.quitSelection();
        return true;
      }
    }

    return false;
  }

  bool isPreview() {
    return view && !diff;
  }

  Future<void> refresh() async {
    // 用于加载后恢复滚动位置
    final pos = UI.getPosOfScrollController(diffViewScrollController);

    //// test begin
    // if(posPreview <= 0 ) print("10000000");
    // if(pos <= 0 ) print("20000000");
    //// test end

    // 若页面加载出错，则重新初始化，比如仓库可能正在执行同步，占用了锁，这时预览obj就会报错；
    // 若页面加载没出错，仅重新加载diff文本（文件内容）
    if(pageErr.isNotEmpty) {
      view = false;
      diff = false;
      await _doInit();
    }else {
      if(view || diff) {
        await _loadDiffText(
          onLoaded: () async {
            // 尝试在重载后恢复滚动位置
            // 注：如果滚动前的delayed时间内快速点击刷新按钮，可能会恢复失败
            UI.restoreScrollPosAfterReloadedIfPosNotChangedAfterDelayed(pos, diffViewScrollController);
          }
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;

    if(pageErr.isNotEmpty) {
      body = BaseLayout.defaultScreenPaddingContainer(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                SelectableText(
                  pageErr,
                  style: TextStyle(color: UI.getColorErr()),
                ),
                const SizedBox(height: 10),
                if(pageErrClosable)
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        pageErrClosable = false;
                        pageErr = "";
                      });
                    },
                    child: Text(t.ok)
                  ),
                const SizedBox(height: 30),
              ],
            )
          )
        )
      );
    }else if(pageLoading) {
      body = BaseLayout.defaultScreenPaddingContainer(
        child: Center(child: SelectableText(pageLoadingText.isEmpty ? t.loading : pageLoadingText))
      );
    }else {
      // 上面四个按钮，下面预览/diff
      body = BaseLayout.defaultScreenPaddingContainer(
        padding: const EdgeInsets.symmetric(horizontal: UI.defaultScreenPadding),
        child: Column(
          children: [
            // 这里用 Flexible 而不是 Expanded 是因为 Flexible 默认 fit 为 FlexFit.loose，
            // 最多会占满全部可用空间，但允许更小，在此处可避免造成页面大量空白；
            // 若设为 FlexFit.tight ，则和 Expanded 效果一样，会直接占满全部可用空间
            // ps：看 Expanded 源码可得知，其实它等价于 Flexible(fit: FlexFit.tight)
            if(menuVisible || (!view && !diff))
              // Flexible(
              Expanded(
                flex: 4,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: double.infinity),  // 撑宽度
                      ..._getMenu(),
                    ],
                  )
                ),
              ),
            if(view || diff)
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // 撑宽度
                  const SizedBox(width: double.infinity),
                  IconButton(
                    tooltip: t.fontSize,
                    onPressed: () => diffViewStateKey.currentState?.showFontSizeAdjuster(),
                    icon: Icon(Icons.format_size),
                  ),
                  IconButton(
                    tooltip: t.lineNumber,
                    onPressed: () {
                      final newValue = !showLineNum;
                      showLineNum = newValue;
                      setState(() {});

                      // 这里不用await，确保调用了update就行，若await，
                      // 可能会导致下面的行号可能不准确的文案提示延迟
                      AppConfig.update((it) async {
                        it.showLineNumInDiffView = newValue;
                      });

                      showLineNumAndBlankLinesIgnoredNoteIfNeed(newValue);
                    },
                    icon: Icon(Icons.onetwothree),
                  ),
                  // 这个“隐藏content”好像多余，可用显示菜单再关闭diff替代
                  // TextButton(
                  //   onPressed: () {
                  //     setState(() {
                  //       view = !view;
                  //       if(!view) {
                  //         diff = false;
                  //         menuVisible = true;
                  //       }
                  //     });
                  //   },
                  //   child: Text(view ? t.hideContent : t.showContent)
                  // ),
                  IconButton(
                    tooltip: t.info,
                    onPressed: () {
                      setState(() {
                        menuVisible = !menuVisible;
                      });
                    },
                    icon: Icon(Icons.info),
                  ),
                ],
              ),
            if(diff)
              SelectableText(t.changesFromAToB(a: shortOid, b: shortOidRight)),
            if(view || diff)
              const Divider(),
            if(view || diff) getDiffWidget(),
          ],
        ),
      );
    }

    return BaseLayout.backWrapper(
      context,
      onBack: () async {
        return backHandler();
      },
      child: BaseLayout.newScaffold(
        context,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            tooltip: t.refresh,
            onPressed: () async {
              await refresh();
            },
          ),
        ],
        title: t.view,
        body: body,
      )
    );
  }
}

