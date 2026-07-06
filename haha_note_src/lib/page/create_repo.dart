import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/client/client.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/dropbox.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/local_dir.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/oauth2/dropbox_oauth2.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/webdav.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/repo.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:hahanote_app/hahanote_lib_sync/sync_config.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';
import 'package:hahanote_app/db/db.dart' show Db;
import 'package:hahanote_app/db/entity/repo_entity.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/state/my_page_state.dart' show MyPageState;
import 'package:hahanote_app/ui/ui.dart' show UI;
import 'package:hahanote_app/util/form_validator.dart' show FormValidator;
import 'package:hahanote_app/util/fs.dart' show Fs;
import 'package:hahanote_app/util/util.dart' show launchUrlExt, copyText, openUrlOrShowErrMsg;
import 'package:hahanote_app/widget/base_layout.dart';
import 'package:hahanote_app/widget/dialogs.dart';
import 'package:hahanote_app/widget/path_chooser.dart';
import 'package:hahanote_app/widget/radios.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../native_util/task_man.dart';
import '../widget/my_text_form_field.dart';

const _TAG = "create_repo.dart";

const _defaultRepoName = "haha_repo";

class CreateRepoMode {
  int value;

  CreateRepoMode(this.value);

  static final create = CreateRepoMode(1);
  static final edit = CreateRepoMode(2);
  static final import = CreateRepoMode(3);

  static bool isUnknownMode(int mode) => mode != create.value && mode != import.value && mode != edit.value ;

  @override
  String toString() {
    return value.toString();
  }

  static String valueToText(final int value) {
    if(value == create.value) {
      return "create";
    }

    if(value == edit.value) {
      return "edit";
    }

    if(value == import.value) {
      return "import";
    }

    return "unknown";
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreateRepoMode &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;
}


class CreateRepoPage extends StatefulWidget {

  // one value of `CreateRepoMode`
  final int mode;
  // only useful for edit mode
  final String repoPath;

  const CreateRepoPage({super.key, required this.mode, this.repoPath = ''});

  @override
  State<CreateRepoPage> createState() => _CreateRepoPageState();

  String getTitle() {
    if(mode == CreateRepoMode.create.value) {
      return t.create;
    }else if(mode == CreateRepoMode.edit.value) {
      return t.edit;
    }else if(mode == CreateRepoMode.import.value) {
      return t.import;
    }

    return t.unknown;
  }
}

class _CreateRepoPageState extends MyPageState<CreateRepoPage> {
  // 注：late init 最好还是少用，若忘了初始化，会在运行时抛异常而不是编译时
  final TextEditingController localRepoPath = TextEditingController(text: "");
  final TextEditingController remoteRepoPath = TextEditingController(text: "");
  final TextEditingController masterPass = TextEditingController(text: "");
  final TextEditingController confirmMasterPass = TextEditingController(text: "");
  final TextEditingController clientName = TextEditingController(text: "");
  String remoteRepoPathErr = '';
  String formErr = '';

  final TextEditingController remoteWebdavUser = TextEditingController(text: "");
  final TextEditingController remoteWebdavPass = TextEditingController(text: "");
  final TextEditingController remoteWebdavHost = TextEditingController(text: "");

  bool remoteLocalDirIsGitBackend = false;
  final TextEditingController remoteLocalDirGitPullUrl = TextEditingController(text: "");
  final TextEditingController remoteLocalDirGitPushUrl = TextEditingController(text: "");
  final TextEditingController remoteLocalDirGitSyncUrl = TextEditingController(text: "");

  // 授权后，获取到的用户名和头像
  RemoteConfigDataForDropbox remoteDropboxConfig = RemoteConfigDataForDropbox();


  final list = RemoteType.supportedTypes;
  SelectionItem selectedRemoteType = SelectionItem.empty();

  List<SelectionItem> selectionList = [];
  bool reloading = false;
  bool loading = true;

  HttpServer? oauth2Server;
  bool oauth2ServerLaunched = false;
  AuthData? dropboxAuthData;
  // ai说这个key用全局的，方便通过key获取同一form的state，不清楚，先这么用了
  final _formKey = GlobalKey<FormState>();


  @override
  void initState() {
    super.initState();

    doInit();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      requireLogin();
    });
  }

  @override
  void dispose() {
    doCloseOauth2Server();

    localRepoPath.dispose();
    remoteRepoPath.dispose();
    masterPass.dispose();
    confirmMasterPass.dispose();
    remoteWebdavUser.dispose();
    remoteWebdavPass.dispose();
    remoteWebdavHost.dispose();
    clientName.dispose();
    remoteLocalDirGitPullUrl.dispose();
    remoteLocalDirGitPushUrl.dispose();
    remoteLocalDirGitSyncUrl.dispose();
    super.dispose();
  }


  Future<void> doInit() async {
    if(reloading) {
      return;
    }

    reloading = true;

    setState(() {
      loading = true;
    });

    try {
      // 给安卓平台设个默认路径
      localRepoPath.text = Platform.isAndroid ? '/storage/emulated/0/$_defaultRepoName' : '';

      // 填个默认值，免得用户不知道填什么
      remoteRepoPath.text = '/$_defaultRepoName';
      masterPass.text = '';
      confirmMasterPass.text = '';

      remoteWebdavUser.text = '';
      remoteWebdavPass.text = '';
      remoteWebdavHost.text = '';

      clientName.text = "";



      if(widget.mode != CreateRepoMode.edit.value) {
        await initForCreateOrImport();
      }else {
        await initRepoByPath();
      }
    }catch(e) {
      App.logger.debug(_TAG, "doInit err: $e");
      showMsgLong("err: $e");
    }finally {
      setState(() {
        reloading = false;
        loading = false;
      });
    }

  }

  Future<void> initSelection() async {
    final newSelectionList = await SelectionItem.toSelectionList(list, (it) async {
      return SelectionItem.fromRemoteType(it);
    });

    selectionList = newSelectionList;
  }


  Future<void> initForCreateOrImport() async {
    clientName.text = Client.genClientName();

    await initSelection();

    selectedRemoteType = SelectionItem.fromRemoteType(list.first);
  }

  Future<void> initRepoByPath() async {
    await initSelection();

    final repoPath = widget.repoPath;
    // edit mode
    // 从路由参数中取出仓库path，查询，用仓库数据初始化页面（回显仓库数据）
    // 在路由创建此页面时传仓库id，不需要在这取，直接放到上级组件里，final变量，即可
    // 并不是所有都能改的，例如主密码就不能改
    final repo = await Repo.open(repoPath);
    final config = await repo.getConfig();

    // 不允许编辑本地仓库，所以这个值其实设不设都行，
    // 但是这个变量后面还会用到，为了减少多余判断，所以一并设置上
    localRepoPath.text = repoPath;

    selectedRemoteType = SelectionItem.fromRemoteType(RemoteType(value: config.remoteConfig.type));
    remoteRepoPath.text = config.remoteConfig.basePath;

    clientName.text = config.client.name;

    if(config.remoteConfig.type == RemoteType.webDAV.value) {
      final remoteData = RemoteConfigDataForWebdav.fromJson(config.remoteConfig.data);
      remoteWebdavHost.text = remoteData.host;
      remoteWebdavUser.text = remoteData.user;
      remoteWebdavPass.text = remoteData.password;
    }else if(config.remoteConfig.type == RemoteType.dropbox.value) {
      remoteDropboxConfig = RemoteConfigDataForDropbox.fromJson(config.remoteConfig.data);
    }else if(config.remoteConfig.type == RemoteType.localDir.value) {
      final remoteData = RemoteConfigDataForLocalDir.fromJson(config.remoteConfig.data);
      remoteLocalDirIsGitBackend = remoteData.isGitBackend;
      remoteLocalDirGitPullUrl.text = remoteData.gitPullUrl;
      remoteLocalDirGitPushUrl.text = remoteData.gitPushUrl;
      remoteLocalDirGitSyncUrl.text = remoteData.gitSyncUrl;
    }

  }

  bool dropboxAuthed() {
    return remoteDropboxConfig.accessToken.isNotEmpty
      && remoteDropboxConfig.refreshToken.isNotEmpty
      // 下面几个其实可选
      && remoteDropboxConfig.accountId.isNotEmpty
      && remoteDropboxConfig.uid.isNotEmpty
      // && remoteDropboxConfig.username.isNotEmpty
    ;
  }

  // 如何处理oauth2启动url，可浏览器打开，展示、提供复制按钮，都行
  Future<void> openAuthLink(AuthData authData) async {
    if(!await launchUrlExt(authData.uri)) {
      App.logger.debug(_TAG, "openAuthLink: launch url failed");
      // TODO 添加逻辑：若失败，显示复制按钮，提示用户可在浏览器打开进行授权
    }
  }

  void clearErr() {
    remoteRepoPathErr = '';
    formErr = '';
  }



  Future<void> startDropboxAuthorization() async {
    if(oauth2ServerLaunched) {
      return;
    }

    try {
      App.logger.debug(_TAG, "start dropbox oauth authorization");

      oauth2Server = await DropboxOauth2.startServer();
      setState(() {
        oauth2ServerLaunched = true;
      });

      dropboxAuthData ??= await DropboxOauth2.genAuthData();
      refreshUI();

      final dropboxConfig = await DropboxOauth2.authorize(server: oauth2Server!, openAuthLink: openAuthLink, authData: dropboxAuthData!);
      // App.logger.debug(_TAG, "dropboxConfig: $dropboxConfig");

      if(dropboxConfig != null) {
        final userInfo = await Dropbox(basePath: FilePath(), config: dropboxConfig)
        // 后面set state时会更新config，所以这里传false
            .getUserInfo(updateConfig: false);

        dropboxConfig.username = userInfo.displayName;
        dropboxConfig.avatar = userInfo.avatarUrl;

        setState(() {
          // 收到响应后应该已经关闭服务器了，所以服务器状态设为false，这样就不会显示手动关闭按钮了
          oauth2ServerLaunched = false;
          oauth2Server = null;

          dropboxConfig.copyTo(remoteDropboxConfig);
        });
      }else {
        App.logger.debug(_TAG, "dropbox config is null, authorize failed or canceled");
      }
    }catch(e, st) {
      App.logger.debug(_TAG, "dropbox auth err: $e\n$st");
      if(mounted) {
        // do not await this dialog, then can be early close the oauth2 server
        // 不要await这个弹窗，这样可更快执行到下面的 tryCloseOauth2Server
        Dialogs.showCopyDialog(context, title: t.error, text: "dropbox auth err: $e\n$st", showMsg: showMsg);
      }

      // if no exception then the server closed after authorized
      // 如果没异常，服务器会在授权后关闭，所以这里只需在catch里关一下即可，无需写到finally里
      await tryCloseOauth2Server();
    }

  }


  Future<void> doCloseOauth2Server() async {
    try {
      await oauth2Server?.close(force: true);
      oauth2Server = null;
    }catch(e, st) {
      App.logger.debug(_TAG, "close oauth2 server err: $e\n$st");
    }

    await TaskMan.stopForegroundService();
  }

  Future<void> tryCloseOauth2Server() async {
    if(!oauth2ServerLaunched) {
      return;
    }

    oauth2ServerLaunched = false;
    refreshUI();

    await doCloseOauth2Server();
    refreshUI();
  }


  Future<void> submit() async {
    // 如果类型是edit，则不允许取消，因为任务很短，只改本地文件，
    // 不允许取消时将“已取消”设为真，即可
    bool taskCanceled = widget.mode == CreateRepoMode.edit.value;
    ValueNotifier<String> progressText = ValueNotifier(t.loading);

    Dialogs.showLoadingDialog(
      context,
      loadingTextNotifier: progressText,
      onCancel: taskCanceled ? null : () async {
        taskCanceled = true;
        progressText.value = t.canceling;
      }
    );

    bool success = false;

    final tempDir = await Fs.createTempDirUnderAppTempDirPath("create_repo_page");

    try {
      clearErr();

      if(!_formKey.currentState!.validate()) {
        return;
      }

      final clientName = this.clientName.text;

      final remoteType = selectedRemoteType.key;

      if(remoteType == RemoteType.dropbox.value && !dropboxAuthed()) {
        setFormErr(t.pleaseAuthorizeDropbox);
        return;
      }

      final localRepoPath = this.localRepoPath.text;
      final repoPath = FilePath.fromString(localRepoPath);
      // 若是创建，检查 仓库/.haha_note 目录是否存在且非空；若是导入，检查仓库目录是否存在且非空
      final localRepoDataDirPath = Repo.getDataDirPathByRepoPath(repoPath.toString());

      // 非编辑模式则检查本地路径，编辑模式不允许编辑本地路径，所以也不用检查
      if(widget.mode != CreateRepoMode.edit.value) {
        final existedRepo = await Db.getRepoByPath(repoPath.toUnixPathStr());
        if(existedRepo != null) {
          // 仓库之前已经添加过了，不能重复添加
          setFormErr(t.repoAlreadyAdded);
          return;
        }

        // 检查本地仓库路径是否已经存在
        // final fileType = await getFileType(widget.mode == CreateRepoMode.create.value ? localRepoDataDirPath : localRepoPath);
        final fileType = await getFileType(localRepoDataDirPath);
        if(fileType != FileSystemEntityType.notFound) {
          // 路径存在且不是目录（可能是文件）
          if(fileType != FileSystemEntityType.directory) {
            throw t.localRepoPathAlreadyExists;
          }

          // 目录存在但非空
          if(!await isEmptyDir(Directory(localRepoDataDirPath))) {
            throw t.localRepoPathIsNotEmpty;
          }
        }
      }

      final Remote remote;
      final remoteBasePath = FilePath.fromString(remoteRepoPath.text);
      if(remoteType == RemoteType.dropbox.value) {
        remote = Dropbox(basePath: remoteBasePath, config: remoteDropboxConfig);
      }else if(remoteType == RemoteType.webDAV.value) {
        remote = Webdav(
          basePath: remoteBasePath,
          config: RemoteConfigDataForWebdav(
            host: remoteWebdavHost.text,
            user: remoteWebdavUser.text,
            password: remoteWebdavPass.text
          )
        );
      }else if(remoteType == RemoteType.localDir.value) {
        remote = LocalDir(
          basePath: remoteBasePath,
          config: RemoteConfigDataForLocalDir(
            isGitBackend: remoteLocalDirIsGitBackend,
            gitPullUrl: remoteLocalDirGitPullUrl.text,
            gitPushUrl: remoteLocalDirGitPushUrl.text,
            gitSyncUrl: remoteLocalDirGitSyncUrl.text,
          )
        );
      }else {
        // should never happened
        setFormErr(t.unknownRemoteType);
        return;
      }

      bool repoExistsCheckPassed = false;

      // 这里只是用来检测，仓库还没创建，这时，packMaxLen是多少其实都无所谓，所以随便传个全局值即可
      await remote.doInit(tempDir, packMaxLen: SyncConfig.getConfig().packFileMaxLenInBytes, onReady: (remote) async {
        // 2个结果，3种可能：
        // 1. true，一定存在
        // 2. false，不存在
        // 3. false，remote不可用，出错，所以返回false（后面会调用 `remote.throwIfAnythingWrong()` 来排除这种情况）
        if(widget.mode == CreateRepoMode.create.value) {
          // 若创建，远程路径不能存在
          if(await remote.isRepoExists()) {
            remoteRepoPathErr = t.remotePathAlreadyExists;
            return false;
          }
        }else if(widget.mode == CreateRepoMode.import.value) {
          // 若导入，远程路径必须存在
          if(!await remote.isRepoExists()) {
            remoteRepoPathErr = t.remotePathDoesntExist;
            return false;
          }
        }  // else 编辑模式，不需要检查远程路径是否存在，若有问题，仓库会不能用，用户可重新编辑

        repoExistsCheckPassed = true;

        return true;
      });

      // 仓库是否存在的检测未通过
      if(!repoExistsCheckPassed) {
        return;
      }


      // 若remote不可用，抛异常
      await remote.throwIfAnythingWrong(tempDir);


      // 创建仓库，写入数据库，设置当前创建的仓库为活跃，跳转到仓库页面

      Future<void> updateRemoteConfig(Repo repo) async {
        final config = await repo.getConfig();
        config.remoteConfig = await remote.toRemoteConfig();
        config.client.name = clientName;
        await repo.updateConfig(config);
      }

      if(widget.mode == CreateRepoMode.create.value
          || widget.mode == CreateRepoMode.import.value
      ) {
        final masterPass = this.masterPass.text;

        // 删除本地和远程目录
        Future<void> cleanIfTaskErrOrCanceled() async {
          // 删除本地目录:
          //   若是创建或导入，则只删除仓库的datadir（仓库/.haha_note）；
          // await safeDeleteDir(Directory(widget.mode == CreateRepoMode.create.value ? localRepoDataDirPath : localRepoPath));
          // 导入和创建仓库前都先检测确保 '本地仓库/.haha_note' 目录不存在或为空，所以，这里可删除.haha_note，不会误删用户数据（除非用户自己作死：例如在创建仓库执行期间往.haha_note目录放文件）
          await safeDeleteDir(Directory(localRepoDataDirPath));

          // 若是创建，则需要删远程，否则不需要
          if(widget.mode == CreateRepoMode.create.value) {
            try {
              // 创建仓库前检测了若远程仓库存在且包含非temp目录，则返回错误，
              // 所以，若执行到这里，仓库路径要么不存在，
              // 要么只包含temp目录，因此可安全删除
              // （除非用户作死：往 '远程仓库路径/temp' 目录下放重要的文件）
              await remote.delete(remoteBasePath.copy(), isDir: true);
            }catch(e, st) {
              // 创建仓库取消后，尝试删除远程路径错误
              App.logger.debug(_TAG, "after canceled '${CreateRepoMode.valueToText(widget.mode)}' repo, delete remote path err: $e\n$st");
            }
          }
        }

        void throwIfCanceled() {
          if(taskCanceled || !mounted) {
            throw TaskCanceledException();
          }
        }


        void syncProgressCb(String act, int allCount, int currentAt, String relativePath) {
          progressText.value = genSyncProgressText(act, allCount, currentAt, relativePath);
        }

        try {
          final repoNoInit = await Repo.fromRepoPath(localRepoPath, createIfNoExists: true);
          await updateRemoteConfig(repoNoInit);
          // 更新完配置后，重新初始化仓库
          final repo = await Repo.fromRepoPath(localRepoPath, createIfNoExists: false);
          final SyncResult syncResult;
          if(widget.mode == CreateRepoMode.create.value) {
            syncResult = await repo.initSync(
              masterPass,
              throwIfCanceled: throwIfCanceled,
              syncProgressCb: syncProgressCb
            );
          }else {
            // import
            syncResult = await repo.importSync(
              masterPass,
              throwIfCanceled: throwIfCanceled,
              syncProgressCb: syncProgressCb
            );
          }

          // 写入仓库到数据库
          final repoEntity = RepoEntity.fromFilePath(repoPath);
          await Db.saveRepoThenSetOpened(repoEntity);

          // 如果有冲突，显示个提示
          if(syncResult.result.conflictsCount > 0) {
            showMsgLong(t.syncCompleteWithConflicts(conflictsCount: syncResult.result.conflictsCount));
          }
        }catch(e, st) {
          App.logger.debug(_TAG, "mode: ${widget.mode}, err: $e, st: $st");

          // 出错或取消，执行清理
          await cleanIfTaskErrOrCanceled();
          rethrow;

        }
      }else if(widget.mode == CreateRepoMode.edit.value) {
        final repo = await Repo.fromRepoPath(localRepoPath, createIfNoExists: false);
        await updateRemoteConfig(repo);

        // x 不需要，因为不允许编辑仓库的本地路径，所以不会变) 更新db打开的仓库
        // Db.setOpenedRepo(localRepoPath.text);

        // x 直接改成手动从当前页面返回后重载已打开的仓库的信息了，所以是不是会自动刷新都不重要了) 是否需要通知上级页面重新读取配置文件初始化仓库？
        //   ，如果返回后上级页面会自动重读，就不需要，否则需要，到时候测试下
      }else {
        throw AppException("unknown mode: ${widget.mode}");
      }

      success = true;
      showMsg(t.success);
    }catch(e, st) {
      App.logger.debug(_TAG, "submit err: $e\n$st");
      setFormErr(e.toString());
    }finally {
      await tempDir.clean();

      // 校验以显示最新设置的错误
      if(!success) {
        _formKey.currentState!.validate();
      }

      if(mounted) {
        await Dialogs.closeLoadingDialog(context);

        if(success) {
          // 返回上级页面（若是从主页进入当前页面，则会自动打开opened_repo）
          Navigator.pop(context);
        }
      }
    }
  }

  void setFormErr(String err) {
    showMsgLong(err);
    setState(() {
      formErr = err;
    });
  }


  String? _remotePathValidator(String? value) {
    if(remoteRepoPathErr.isNotEmpty) {
      return remoteRepoPathErr;
    }

    final emptyErr = FormValidator.errIfPathEmpty(value);
    if(emptyErr != null) {
      return emptyErr;
    }

    // 远程路径，除非同步目标是本地目录，否则强制unix style（注：即使在这设置的时候可以非unix style path，就是可用windows带\路径分割符的路径，但存储时还是一律unix style）
    return FormValidator.errIfPathNotAbsOrInvalid(
      value,
      isWindows: selectedRemoteType.key == RemoteType.localDir.value
        ? Platform.isWindows
        : false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // final args = ModalRoute.of(context)!.settings.arguments as Map;

    if(CreateRepoMode.isUnknownMode(widget.mode)) {
      return BaseLayout.newScaffoldWithScrollableColumn(
        context,
        title: widget.getTitle(),
        children: [Text(t.unknownMode)]
      );
    }

    final formChildren = <Widget>[];

    final children = <Widget>[];
    if(!loading) {
      children.add(
        RadiosWidget(
          selections: selectionList,
          defaultSelected: selectedRemoteType,
          onChange: (newValue) {
            setState(() {
              selectedRemoteType = newValue;
            });
          },
        )
      );

      children.add(const SizedBox(height: UI.verticalHeight));


      if(selectedRemoteType.key == RemoteType.webDAV.value) {
        children.add(
          MyTextFormField(
            controller: remoteWebdavHost,
            decoration: InputDecoration(border: OutlineInputBorder(), labelText: t.host),
            validator: (value) {
              return FormValidator.errIfPathEmpty(value);
            }
          )
        );

        children.add(const SizedBox(height: UI.verticalHeight));

        children.add(
          MyTextFormField(
            controller: remoteWebdavUser,
            decoration: InputDecoration(border: OutlineInputBorder(), labelText: t.username),
          )
        );

        children.add(SizedBox(height: UI.verticalHeight));

        children.add(
          MyTextFormField(
            controller: remoteWebdavPass,
            obscureText: true,
            decoration: InputDecoration(border: OutlineInputBorder(), labelText: t.password),
          )
        );
      }else if(selectedRemoteType.key == RemoteType.dropbox.value) {
        // dropbox

        // 点击授权

        // 显示取消授权按钮，如果用户点了授权，啥也没干，就返回app，点这个可手动关闭服务器停止等待接收token
        if(oauth2ServerLaunched) {
          final authUrl = dropboxAuthData?.uri.toString() ?? "";
          children.add(
            Column(
              spacing: UI.verticalHeight,
              children: [
                SelectableText(t.openLinkByYourself, style: TextStyle(fontSize: 18),),

                SelectableText(authUrl),

                OutlinedButton(
                  onPressed:() {
                    copyText(authUrl);
                    showMsg(t.copied);
                  },
                  child: Text(t.copy)
                ),
              ],
            )
          );

          children.add(SizedBox(height: UI.verticalHeight * 2));

          children.add(
            ElevatedButton(
              onPressed: () async {
                await tryCloseOauth2Server();
              },
              child: Text(t.cancel),
            )
          );
        }else {
          children.add(
            ElevatedButton(
              onPressed: () async {
                await startDropboxAuthorization();
              },
              child: Text(remoteDropboxConfig.refreshToken.isNotEmpty ? t.reAuthorize : t.authorize),
            )
          );
        }

        children.add(SizedBox(height: UI.verticalHeight));


        // 显示dropbox用户名和头像（可能没头像，不过不会报错的）
        if(remoteDropboxConfig.username.isNotEmpty) {
          children.add(
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CircleAvatar(radius: 24, backgroundImage: NetworkImage(remoteDropboxConfig.avatar)),
                SizedBox(width: 12),
                Text(remoteDropboxConfig.username, style: TextStyle(fontSize: 16)),
              ],
            )
          );
        }

        children.add(SizedBox(height: UI.verticalHeight));

      }



      children.add(SizedBox(height: UI.verticalHeight));

      // 选择远程路径
      if(selectedRemoteType.key == RemoteType.localDir.value) {
        children.add(
          PathChooser(
            path: remoteRepoPath,
            textFileLabel: t.remotePath,
            showMsg: showMsg,
            showMsgLong: showMsgLong,
            refreshUI: refreshUI,
            trueDirFalseFile: true,

            // 禁用所有组件内置错误检测，改用自定义错误检测
            errIfPathEmpty: false,
            errIfPathNotAbsOrInvalid: false,
            showFileChooserButton: true,

            // 若是create，传null，后面使用回调检查仓库的data dir是否存在（注意这个检查的是data dir，不是仓库目录，仓库目录可以非空，直接创建并同步即可）；
            // 若是edit，传true，直接让widget内部自己检查仓库目录是否存在即可
            // trueExistErrFalseNoExistErrNullNoCheckExist: widget.mode == CreateRepoMode.create.value ? null : true,
            trueExistErrFalseNoExistErrNullNoCheckExist: null, // 由 errIfCallerConsideredPathInvalid 控制

            errIfCallerConsideredPathInvalid: (path, fileType) {
              return _remotePathValidator(path);
            },
          ),
        );

        children.add(
          Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.all(0),
              controlAffinity: UI.myCheckBoxControlAffinity,
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(Platform.isAndroid ? t.gitBackendRequiresPuppyGit : t.gitBackend),
                  IconButton(
                    iconSize: 18,
                    onPressed: ()=>openUrlOrShowErrMsg(url: gitBackendTutorialUrl, showMsg: showMsg),
                    icon: Icon(Icons.help)
                  )
                ]
              ),
              value: remoteLocalDirIsGitBackend,
              onChanged: (v) {
                setState(() {
                  remoteLocalDirIsGitBackend = !remoteLocalDirIsGitBackend;
                });
              },
            ),
          ),
        );

        // if is android, required PuppyGit Api url
        if(Platform.isAndroid && remoteLocalDirIsGitBackend) {
          children.add(
            MyTextFormField(
              controller: remoteLocalDirGitPullUrl,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: t.puppyGitPullUrl,
              ),
              validator: (value) {
                return FormValidator.errIfNullOrEmpty(value);
              },
            ),
          );
          children.add(SizedBox(height: UI.verticalHeight));

          children.add(
            MyTextFormField(
              controller: remoteLocalDirGitPushUrl,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: t.puppyGitPushUrl,
              ),
              validator: (value) {
                return FormValidator.errIfNullOrEmpty(value);
              },
            ),
          );
          children.add(SizedBox(height: UI.verticalHeight));

          children.add(
            MyTextFormField(
              controller: remoteLocalDirGitSyncUrl,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: t.puppyGitSyncUrl,
              ),
              validator: (value) {
                return FormValidator.errIfNullOrEmpty(value);
              },
            ),
          );
        }
      }else {
        children.add(
          MyTextFormField(
            controller: remoteRepoPath,
            decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: t.remotePath,
            ),
            validator: (value) {
              return _remotePathValidator(value);
            },
          ),
        );
      }


      // 编辑模式不支持修改本地路径，要想修改，直接移动仓库再重新打开就行，不用在这改

      // 创建或导入，可输入master password，编辑暂时禁止，因为修改master password不是一个简单的操作
      if(widget.mode != CreateRepoMode.edit.value) {  // create or import mode

        children.add(SizedBox(height: UI.verticalHeight+20));

        // 选择本地路径
        children.add(
          PathChooser(
            path: localRepoPath,
            textFileLabel: t.localPath,
            showMsg: showMsg,
            showMsgLong: showMsgLong,
            refreshUI: refreshUI,
            trueDirFalseFile: true,
            errIfPathEmpty: true,
            errIfPathNotAbsOrInvalid: true,
            showFileChooserButton: true,

            // 若是create，传null，后面使用回调检查仓库的data dir是否存在（注意这个检查的是data dir，不是仓库目录，仓库目录可以非空，直接创建并同步即可）；
            // 若是edit，传true，直接让widget内部自己检查仓库目录是否存在即可
            // trueExistErrFalseNoExistErrNullNoCheckExist: widget.mode == CreateRepoMode.create.value ? null : true,
            trueExistErrFalseNoExistErrNullNoCheckExist: null, // 由 errIfCallerConsideredPathInvalid 控制

            errIfCallerConsideredPathInvalid: (path, fileType) {
              // 非创建模式不检查此值，直接返回null，代表没错误 （非创建模式由 trueExistErrFalseNoExistErrNullNoCheckExist 控制是否报错）
              // if(widget.mode != CreateRepoMode.create.value) {
              //   return null;
              // }

              if(path == null || path.isEmpty) {
                return t.pleaseInput;
              }

              if(fileType != FileSystemEntityType.notFound) {
                // 若期望选择的是目录，则判断是否存在，若存在且非空，则报错
                if(fileType == FileSystemEntityType.directory) {
                  // 仓库数据目录 repo/.haha_note 非空则报错
                  final repoDataDirPath = Repo.getDataDirPathByRepoPath(path);
                  if(!isDirEmptyOrNoExistsSync(repoDataDirPath)) {
                    // 目录非空则报错
                    return t.pathAlreadyExists;
                  }
                }else {
                  // 期望目录但路径不是目录，报错
                  return t.invalidPath;
                }
              }

              if(selectedRemoteType.key == RemoteType.localDir.value && remoteRepoPath.text == path) {
                return t.remoteAndLocalPathsAreTheSame;
              }

              return null;
            },
          )
        );


        children.add(SizedBox(height: UI.verticalHeight+20));

        children.add(
          MyTextFormField(
            controller: masterPass,
            obscureText: true,
            decoration: InputDecoration(border: OutlineInputBorder(), labelText: t.masterPassword),
            validator: (value) {
              return FormValidator.errIfPathEmpty(value);
            }
          )
        );
        children.add(SizedBox(height: UI.verticalHeight));
        children.add(
          MyTextFormField(
            controller: confirmMasterPass,
            obscureText: true,
            decoration: InputDecoration(border: OutlineInputBorder(), labelText: t.confirmMasterPassword),
            validator: (value) {
              if(confirmMasterPass.text != masterPass.text) {
                return t.masterPasswordDidntMatch;
              }
              
              return null;
            }
          )
        );

        children.add(SizedBox(height: 5));

        children.add(
          Row(
            children: [
              Expanded(
                child: SelectableText(t.masterPasswordNote)
              )
            ],
          )
        );
      }

      children.add(SizedBox(height: UI.verticalHeight+20));
      children.add(
        MyTextFormField(
          controller: clientName,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: t.clientName),
          validator: (value) {
            // 检测是否为空
            final emptyErr = FormValidator.errIfPathEmpty(value);
            if(emptyErr != null) {
              return emptyErr;
            }

            // 检测是否过长
            if(value!.length > Client.clientNameMaxLen()) {
              return t.clientNameTooLong;
            }

            return null;
          }
        )
      );

      children.add(SizedBox(height: 5));

      children.add(
        Row(
          children: [
            Expanded(
              child: SelectableText(t.clientNameNote)
            )
          ],
        )
      );

      children.add(SizedBox(height: UI.verticalHeight));

      children.add(
        ElevatedButton(
          onPressed: () async {
            // 点击先清空form错误，之后提交时若有错，会重新设置
            setFormErr('');

            try {
              await submit();
            }catch(e, st) {
              App.logger.debug(_TAG, "submit form err: $e\n$st");
              setFormErr(e.toString());
            }
          },
          child: Text(t.submit),
        )
      );

      // 在提交按钮下面，显示连接服务器失败啊，验证主密码失败啊，之类的错误
      if(formErr.isNotEmpty) {
        children.add(SizedBox(height: UI.verticalHeight));

        children.add(SelectableText(formErr, style: TextStyle(color: Colors.red)));
      }

      children.add(SizedBox(height: UI.verticalHeight+30));


      formChildren.add(
        Form(
          key: _formKey,
          child: Column(
            children: children,
          ),
        )
      );


    }else {
      formChildren.add(
        Center(
          child: Text(t.loading),
        )
      );
    }

    return BaseLayout.newScaffold(
      context,
      title: widget.getTitle(),
      body: SingleChildScrollView(
        child: BaseLayout.getPaddingColumn(children: formChildren),
      ),
    );
  }

}
