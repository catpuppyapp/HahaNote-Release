import 'dart:io' show Platform, FileSystemEntity, Directory, FileSystemEntityType, File, exit;
import 'dart:math' show min;

import 'package:hahanote_app/bean/bean.dart';
import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/log.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/my_http_overrides.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/remote.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/config.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/repo.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/related_oids.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';
import 'package:hahanote_app/config/app_config.dart';
import 'package:hahanote_app/config/portable.dart' show initPortableMode;
import 'package:hahanote_app/constants/cons.dart';
import 'package:hahanote_app/db/db.dart' show Db;
import 'package:hahanote_app/db/entity/repo_entity.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/mock/mock.dart' show Mock;
import 'package:hahanote_app/native_util/open_file.dart';
import 'package:hahanote_app/native_util/task_man.dart';
import 'package:hahanote_app/page/create_repo.dart';
import 'package:hahanote_app/page/editor.dart';
import 'package:hahanote_app/page/file_history.dart';
import 'package:hahanote_app/page/repo_status.dart';
import 'package:hahanote_app/page/sub_page/about_page.dart';
import 'package:hahanote_app/page/sub_page/conflict_list.dart';
import 'package:hahanote_app/page/sub_page/deleted_page.dart';
import 'package:hahanote_app/page/sub_page/recent_files.dart';
import 'package:hahanote_app/page/sub_page/settings_page.dart';
import 'package:hahanote_app/page/sync_history.dart';
import 'package:hahanote_app/page/tls_cert_manage.dart';
import 'package:hahanote_app/page/view_object.dart';
import 'package:hahanote_app/shortcut/shortcut.dart';
import 'package:hahanote_app/state/global.dart';
import 'package:hahanote_app/state/my_page_state.dart' show MyPageState;
import 'package:hahanote_app/ui/app_layout_observer.dart';
import 'package:hahanote_app/ui/my_fonts.dart';
import 'package:hahanote_app/ui/ui.dart';
import 'package:hahanote_app/util/app_info.dart';
import 'package:hahanote_app/util/dir_util.dart';
import 'package:hahanote_app/util/fs.dart';
import 'package:hahanote_app/util/permission.dart' show showRequestPermissionDialogIfIsAndroid;
import 'package:hahanote_app/util/regex_util.dart' show RegexUtil;
import 'package:hahanote_app/util/reveal_file.dart';
import 'package:hahanote_app/util/util.dart';
import 'package:hahanote_app/widget/base_layout.dart';
import 'package:hahanote_app/widget/bottom_bar.dart';
import 'package:hahanote_app/widget/buttons.dart';
import 'package:hahanote_app/widget/cards.dart';
import 'package:hahanote_app/widget/changelog_dialog.dart';
import 'package:hahanote_app/widget/dialogs.dart' show Dialogs;
import 'package:hahanote_app/widget/dropdown_menu.dart' show DropdownMenuWidget;
import 'package:hahanote_app/widget/file_info_dialog.dart' show FileInfoDialog;
import 'package:hahanote_app/widget/line.dart';
import 'package:hahanote_app/widget/pull_to_refresh_list.dart';
import 'package:hahanote_app/widget/search_text_field.dart';
import 'package:hahanote_app/widget/sort_dialog.dart';
import 'package:code_forge/code_forge.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_single_instance/flutter_single_instance.dart';
import 'package:lifecycle/lifecycle.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'hahanote_lib_sync/exception/exception.dart';
import 'hahanote_lib_sync/isolate_pool/isolate_pool.dart';
import 'hahanote_lib_sync/sync_config.dart';
import 'page/markdown_file_preview.dart';
import 'ui/app_theme.dart';
import 'util/localized_text.dart';
import 'widget/my_svg.dart';
import 'widget/repo_options_dialog.dart';

const _TAG = "main.dart";

//代码里面引用的话，引用这个
// const appNameForCode = "haha_note";


// 需要在 pubspec.yaml 里配置assets，然后使用 Image.asset 加载
const appIconPath = "assets/icon/icon.png";
const authorEmail = "luckyclover33xx@gmail.com";
const projectUrl = "https://github.com/catpuppyapp/HahaNote-Release";
const privacyPolicyUrl = "https://github.com/catpuppyapp/HahaNote-Release/blob/main/privacy_policy.md";
const authorUrl = "https://github.com/Bandeapart1964";
const reportBugUrl = "https://github.com/catpuppyapp/HahaNote-Release/issues/new";
const updateUrl = "https://github.com/catpuppyapp/HahaNote-Release/releases";
const buyVipUrl = "https://github.com/catpuppyapp/HahaNote-Release/blob/main/buy_vip.md";
const donateUrl = "https://github.com/catpuppyapp/PuppyGit/blob/main/donate.md";
const gitBackendTutorialUrl = "https://github.com/catpuppyapp/HahaNote-Release/blob/main/git_backend.md";
const donateUrlKofi = "https://ko-fi.com/bandeapart1964";
bool landscapeLayoutInited = false;

Future<void> main() async {
  //显示绘制边框
  // debugPaintSizeEnabled = true;

  WidgetsFlutterBinding.ensureInitialized();
  // 监听屏幕尺寸变化
  WidgetsBinding.instance.addObserver(AppLayoutObserver());

  // BEGIN: avoid multi instance on win/mac/linux
  if(isPcPlatform()) {
    // Must add this line.
    await windowManager.ensureInitialized();

    await exitIfAlreadyRunning();
  }
  // END: avoid multi instance on win/mac/linux

  // BEGIN: init
  await RustLib.init();
  initPortableMode();
  // 先初始化一下，让Logger能用，config初始化后会再次初始化logger为配置文件中的日志等级
  await initSyncLibAndLog();
  initLibs();
  await AppInfo.init();
  await initDb();
  await AppConfig.init();
  // 配置初始化后，重新初始化logger为配置中的等级，这里不需要await，影响app启动时间，反正后续初始化好就行，晚点也没事
  reInitSyncLibAndLogWithConfig();
  IsolatePool.initCpuCores();
  await MyHttpOverrides.init();
  await initLanguage();
  await UI.initTheme();
  await initFonts();
  await printPaths();

  // 依赖配置文件读取窗口size，所以放下面
  await initWindow();

  // END: init

  // BEGIN: test
  // await testHashCompute();
  // END: test

  runApp(MyApp(isDarkTheme: UI.isDarkTheme()));

}

Future<void> exitIfAlreadyRunning() async {
  // 是第一个实例，noop
  if(await FlutterSingleInstance().isFirstInstance()) {
    return;
  }

  // 不是第一个实例，则：聚焦已启动的实例，然后退出当前实例

  // 注意这里用的printLogger，不写入日志到文件，因为这时候能写入文件的日志类还没初始化
  App.printLogger.debug(_TAG, "App is already running, will focus existed instance and exit current");

  // 聚焦之前的实例
  final err = await FlutterSingleInstance().focus();
  if(err != null) {
    App.printLogger.debug(_TAG, "Error focusing running instance: $err");
  }

  // 退出当前实例
  exit(0);
}

// 获取所有显示器的最小宽高，避免窗口超过屏幕大小导致无法调大小
Size? getDeviceMinSize() {
  try {
    return getDeviceMinSizeNoCatch();
  }catch(e, st) {
    App.logger.debug(_TAG, "get device min size err: $e\n$st");
    return null;
  }
}

Size? getDeviceMinSizeNoCatch() {
  final displays = WidgetsBinding.instance.platformDispatcher.views.firstOrNull?.platformDispatcher.displays;
  if(displays == null || displays.isEmpty) {
    return null;
  }

  final firstDisplay = displays.first;
  double minWidth = firstDisplay.size.width / firstDisplay.devicePixelRatio;
  double minHeight = firstDisplay.size.height / firstDisplay.devicePixelRatio;
  if(displays.length == 1) {
    return Size(minWidth, minHeight);
  }

  bool isFirst = true;
  for(final d in displays) {
    if(isFirst) {
      isFirst = false;
      continue;
    }
    minWidth = min(minWidth, d.size.width / d.devicePixelRatio);
    minHeight = min(minHeight, d.size.height / d.devicePixelRatio);
  }

  return Size(minWidth, minHeight);
}

Future<void> initWindow() async {
  if(!isPcPlatform()) {
    return;
  }

  landscapeLayoutInited = true;

  double width = AppConfig.getConfig().windowWidth;
  double height = AppConfig.getConfig().windowHeight;
  final deviceMinSize = getDeviceMinSize();
  if(deviceMinSize != null) {
    width = min(deviceMinSize.width, width);
    height = min(deviceMinSize.height, height);
    // 高度减N是为了避免窗口标题栏有可能超过屏幕高度
    height = (height==deviceMinSize.height ? height-40 : height).clamp(100, deviceMinSize.height);
  }

  final size = Size(width, height);
  // 更新窗口比例
  isLandscapeLayoutNotifier.value = isLandscapeMode(size);

  WindowOptions windowOptions = WindowOptions(
    size: size,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

Future<void> reInitSyncLibAndLogWithConfig() async {
  // 读完配置后再初始化一次日志
  final appConfig = AppConfig.getConfig();
  await initSyncLibAndLog(
    force: true,
    logLevel: appConfig.syncConfig.logLevel,
    devModeOn: appConfig.syncConfig.devModeOn,
  );
}

Future<void> printPaths() async {
  App.logger.info(_TAG, "app data dir at: ${await Fs.getAppDataDirPath()}");
  App.logger.info(_TAG, "app temp dir at: ${await Fs.getAppTempDirPath()}");
}

Future<void> initSubIsolate() async {
  initPortableMode();

  // 在isolate无效，妈的
  // await AppInfo.init();
}

// 由于在test环境测试不了rust bridge的函数，所以就在这测了
// Future<void> testHashCompute() async {
//   final tempFile = await Fs.createTempFile(prefix: "temp_test_hash_compute");
//   try {
//     final dartHash = bytesToHex(
//       await hashFileWithKeyData(AppKey.keyData, tempFile),
//     );
//     final rustHash = await rustComputeSha256(
//       path: tempFile.absolute.path,
//       contentPadding: AppKey.keyData.contentPadding,
//     );
//
//     App.logger.debug(_TAG, "dartHash $dartHash");
//     App.logger.debug(_TAG, "rustHash $rustHash");
//
//     if (dartHash != rustHash) {
//       throw "rust hash and dart hash not match";
//     }
//   }finally {
//     await tempFile.delete();
//   }
// }

void initLibs() {
  // if(Platform.isWindows) {
  //   loadLibForPc("extLibs/zstd/eszstd-win64.dll");
  // }else if(Platform.isLinux) {
  //   loadLibForPc("extLibs/zstd/eszstd-linux64.so");
  // }else if(Platform.isMacOS)   {
  //   loadLibForPc("extLibs/zstd/eszstd-mac64.dylib");
  // }
}

Future<void> initDb() async {
  await Db.init();
}

Future<void> initSyncLibAndLog({bool? devModeOn, int? logLevel, bool force = false}) async {
  App.init(
    force: force,
    // 正式发行版禁用dev模式，dev模式会打印明文files.map.enc和syncHistory等信息
    devModeOn: devModeOn ?? kDebugMode,
    logLevel: logLevel ?? (kDebugMode ? LogLevel.debug : LogLevel.warn),
    logFilePath: await Fs.getLogFilePath(),
    doPrint: (Object? o) {
      // 非debug模式print可能影响UI性能，
      // 而且Log有独立Isolate，可输出到文件，不需要print
      if(kDebugMode) {
        debugPrint(o.toString());
      }
  });
}


Future<void> initLanguage() async {
  try {
    final curLanguage = AppConfig.getConfig().language;

    for(final rawLang in AppLocaleUtils.supportedLocalesRaw) {
      if(curLanguage == rawLang) {
        // parse 如果解析无效不会报错，会使用默认（en），
        // 所以，仅在匹配时才parse，避免明明选的“自动检测”却匹配到英语
        final parsed = AppLocaleUtils.parse(rawLang);
        await LocaleSettings.setLocale(parsed);
        return;
      }
    }

    // 无匹配则自动
    await LocaleSettings.useDeviceLocale();
  }catch(e, st) {
    App.logger.debug(_TAG, "parse local err, will auto detect: err=$e, st=$st");
    await LocaleSettings.useDeviceLocale();
  }
}

// 这个并不是硬退出，是切到后台
void softExitApp() {
  TaskMan.moveToBackground();
}

// void hardExitApp() {
//   exit(0);
// }

bool defaultBackHandler(BuildContext context, {required bool exit}) {
  if(!context.mounted) {
    return false;
  }

  final navigator = Navigator.of(context);
  // 用maybe pop有可能返回不了，所以用pop了
  // await Navigator.maybePop(context);

  // 若是顶级页面，无法pop，否则能
  if(navigator.canPop()) {
    navigator.pop();
    return true;
  }

  // 若无法pop，可能是顶级页面，执行退出
  if(exit) {
    softExitApp();
    return true;
  }

  return false;
}


class MyApp extends StatefulWidget {
  final bool isDarkTheme;
  const MyApp({super.key, required this.isDarkTheme});


  @override
  State<MyApp> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    if(!landscapeLayoutInited) {
      // 平板之类的会在这初始化是否横屏模式，若是pc会在上面initWindows()时初始化
      landscapeLayoutInited = true;
      final size = MediaQuery.sizeOf(context);
      isLandscapeLayoutNotifier.value = isLandscapeMode(size);
    }

    return ValueListenableBuilder<AppTheme>(
      valueListenable: UI.themeNotifier,
      builder: (_, AppTheme appTheme, __) {
        return MaterialApp(
          navigatorObservers: [defaultLifecycleObserver],
          navigatorKey: Global.navigatorKey,
          scaffoldMessengerKey: Global.scaffoldMessengerKey,
          debugShowCheckedModeBanner: false,
          title: t.appName,
          // theme: ThemeData(
          //   colorScheme: ColorScheme.fromSeed(seedColor: colorOfTheme, brightness: Brightness.light),
          // ),
          // // 若不指定darkTheme，默认使用 theme，若theme不指定，默认使用 ThemeData.light
          // darkTheme: ThemeData(
          //   colorScheme: ColorScheme.fromSeed(seedColor: colorOfTheme, brightness: Brightness.dark),
          // ),
          theme: FlexThemeData.light(scheme: appTheme.colorScheme, fontFamily: myFontRegular),
          darkTheme: FlexThemeData.dark(scheme: appTheme.colorScheme, fontFamily: myFontRegular),
          // theme: ThemeData.light(useMaterial3: true),
          // darkTheme: ThemeData.dark(useMaterial3: true),
          themeMode: appTheme.themeMode,
          home: MyHomePage(title: t.appName),

          // The MaterialApp configures the top-level Navigator to search for routes in the following order:
          // 1. For the / route, the home property, if non-null, is used.
          //
          // 2. Otherwise, the routes table is used, if it has an entry for the route.
          //
          // 3. Otherwise, onGenerateRoute is called, if provided. It should return a non-null value for any valid route not handled by home and routes.
          //
          // 4. Finally if all else fails onUnknownRoute is called.

          routes: <String, WidgetBuilder> {
            Cons.routeRepoCreate: (BuildContext bc) => CreateRepoPage(mode: CreateRepoMode.create.value),

            Cons.routeRepoEdit: (BuildContext bc) {
              final args = ModalRoute.of(bc)!.settings.arguments as Map;
              return CreateRepoPage(mode: CreateRepoMode.edit.value, repoPath: args['repoPath']);
            },

            Cons.routeRepoImport: (BuildContext bc) => CreateRepoPage(mode: CreateRepoMode.import.value),

            Cons.routeEditorOpen: (BuildContext bc) {
              final args = ModalRoute.of(bc)!.settings.arguments as Map;
              return EditorPage(
                path: FilePath.fromString(args['path']),
              );
            },

            Cons.routeFileHistory: (BuildContext bc) {
              final args = ModalRoute.of(bc)!.settings.arguments as Map;
              return FileHistoryPage(
                path: args['path'],
              );
            },

            Cons.routeSyncHistory: (BuildContext bc) {
              final args = ModalRoute.of(bc)!.settings.arguments as Map;
              return SyncHistoryPage(
                repoPath: args['repoPath'],
              );
            },

            Cons.routeRepoStatus: (BuildContext bc) {
              final args = ModalRoute.of(bc)!.settings.arguments as Map;
              return RepoStatusPage(
                repoPath: args['repoPath'],
              );
            },

            Cons.routeViewObject: (BuildContext bc) {
              final args = ModalRoute.of(bc)!.settings.arguments as Map;
              return ViewObjectPage(
                path: args['path'],
                oid: args['oid']
              );
            },

            Cons.routeTlsCertManage: (BuildContext bc) {
              return TlsCertManage();
            },

            Cons.routeMarkdownPreview: (BuildContext bc) {
              final args = ModalRoute.of(bc)!.settings.arguments as Map;
              return MarkdownFilePreview(
                path: args['path'],
                initialScrollOffset: args['initialScrollOffset']
              );
            },
          }
        );
      }
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends MyPageState<MyHomePage> {
  bool wasLeavedPage = false;

  //// BEGIN: no repo opened home page
  bool repoStatusLoading = false;
  final Map<String, RepoStatus> repoStatusMap = {};
  //// END: no repo opened home page

  //// BEGIN: repo page
  bool loadingHome = false;

  RepoEntity? openedRepo;
  int currentPage = Cons.homePageCodeHome;
  Repo? repo;
  Config? repoConfig;
  int syncedFilesCount = 0;
  // String dropboxUsername = '';
  // String dropboxAvatar = '';
  // String syncProgressText = '';
  // key is repo path; value is progress text
  Map<String, String> syncProgressMap = {};
  Map<String, String> syncErrMap = {};
  String lastSyncedAt = '';
  bool repoSyncing = false;
  bool syncCanceled = false;
  bool checkingLogin = false;
  String openRepoErrMsg = '';
  List<RepoEntity> repos = [];
  bool showCheckConflicts = false;
  // 这个只能保证尽量尝试，不知道在安卓是不是按返回会销毁main Isolate，
  // 反正有时候并不会执行到 sync函数的入参 throwIfInterrupted，就直接退出了，
  // 最终结果是同步会终止，但是是强行终止，try catch finally的代码都不会被执行，
  // 不过续锁的subIsolate还是会继续执行，通过检测主线程是否继续存活来终止了
  bool disposed = false;
  //// END: repo page

  //// BEGIN: files page
  List<FileSystemEntity> fileList = [];
  String loadFilesErr = '';
  FilePath currentPath = FilePath();
  List<FileSystemEntity> selectedFileList = [];
  // 粘贴时目标路径已经存在，先把这些条目存上，然后询问用户怎么处理
  List<FileSystemEntity> targetExistsListWhenPaste = [];
  // '' 非拷贝模式，'copy' 拷贝模式，'move' 移动模式
  String pasteMode = '';
  // 搜索模式，查找结果
  List<FileSystemEntity> foundFileList = [];
  // 用来在关键字改变后取消之前的搜索任务
  String filesPageSearchId = '';
  // 得存，不然无法刷新搜索结果
  final filesPageSearchKeyword = TextEditingController(text: '');
  bool filesPageSearching = false;
  bool filesPageIsLoading = false;
  final ScrollController filesPageScrollController = ScrollController();
  final Map<String, double> filesPageScrollOffsets = {};
  Map<String, SortRule> filesPageSortMap = {};
  SortRule filesPageGlobeSort = SortRule.defaultValue;
  final breadcrumbScrollController = ScrollController();
  //// END: files page

  final openRepoPathController = TextEditingController(text: '');

  //// BEGIN: editor page

  //// END: editor page


  //// BEGIN: recent files page

  //// END: recent files page

  final GlobalKey<ConflictListPageState> conflictPageKey = GlobalKey();
  final GlobalKey<DeletedPageState> deletedPageKey = GlobalKey();
  final GlobalKey<SettingsPageState> settingsPageKey = GlobalKey();
  final GlobalKey<RecentFilesState> recentFilesPageKey = GlobalKey();

  @override
  void initState() {
    super.initState();

    disposed = false;

    showChangeLogDialogIfNeed(context);
    loadHome();

    // 初次使用，可能需要弹窗之类的
    if(AppConfig.getConfig().isFirstUse) {
      // 若是安卓且是初次使用，显示请求权限 dialog
      if(Platform.isAndroid) {
        // 如果不加这个，可能会报错，因为当前widget还没就绪
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await showRequestPermissionDialogIfIsAndroid(
            context,
            showMsg: showMsg,
          );
        });
      }

      // 设置为false，避免再次弹窗
      AppConfig.update((it) async {
        it.isFirstUse = false;
      });
    }
  }

  @override
  void dispose() {
    // 或许大概也许能比mounted更早知道组件被disposed了，然后今早让sync函数知道
    disposed = true;
    repoStatusMap.clear();

    try {
      openRepoPathController.dispose();
    }catch(_) {}
    try {
    }catch(_) {}
    try {
      filesPageSearchKeyword.dispose();
    }catch(_) {}
    try {
      filesPageScrollOffsets.clear();
    }catch(_) {}
    try {
      filesPageScrollController.dispose();
    }catch(_) {}
    try {
      breadcrumbScrollController.dispose();
    }catch(_) {}
    super.dispose();
  }

  @override
  void onLifecycleEvent(LifecycleEvent event) {
    // 先调用父类函数，更新pageVisible
    super.onLifecycleEvent(event);

    if(!pageVisible) {
      wasLeavedPage = true;
    }else if(wasLeavedPage) { // page now is visible and wasLeavedPage
      wasLeavedPage = false;
      App.logger.verbose(_TAG, "onLifecycleEvent: reloadCheck: reload files or recent files");

      if(currentPage == Cons.homePageCodeFiles) {
        // 仅当文件管理器页面未启用搜索模式时离开页面再返回才重载，避免搜索后，临时离开页面再返回，丢失搜索结果
        if(filesPageSearchId.isEmpty) {
          _loadFiles(currentPath);
        }
      }else if(currentPage == Cons.homePageCodeRecentFiles) {
        final recentFilesState = recentFilesPageKey.currentState;
        if(recentFilesState != null && recentFilesState.searchId.isEmpty) {
          recentFilesState.loadItems();
        }
      }
    }
  }

  @override
  bool handleKeyPress(KeyEvent event, bool isControlDown, bool isAltDown, bool isShiftDown) {
    final pressedKey = event.logicalKey;
    if(pressedKey == LogicalKeyboardKey.escape
        && !isControlDown && !isAltDown && !isShiftDown
        && mounted
    ) {
      // 传false，禁止esc键调用退出app的函数，退出app的函数只在手机上调用，按esc说明有键盘，用不到，想退出可用alt+f4之类的快捷键
      if(_backHandler()) {
        return true;
      }
    }

    // Alt + ArrowUp，返回上级页面
    if(isAltDown && pressedKey == LogicalKeyboardKey.arrowUp) {
      if(currentPage == Cons.homePageCodeFiles) {
        _toParentDir();
        return true;
      }
    }

    if(pressedKey == LogicalKeyboardKey.f5 && !isControlDown && !isAltDown && !isShiftDown) {
      // F5重载文件列表
      if(currentPage == Cons.homePageCodeFiles) {
        _refreshFileList();
        return true;
      }else if(currentPage == Cons.homePageCodeConflict) {
        conflictPageKey.currentState?.loadItems();
        return true;
      }else if(currentPage == Cons.homePageCodeDeleted) {
        deletedPageKey.currentState?.loadItems();
        return true;
      }else if(currentPage == Cons.homePageCodeRecentFiles) {
        recentFilesPageKey.currentState?.loadItems();
        return true;
      }else if(currentPage == Cons.homePageCodeRepo 
        || currentPage == Cons.homePageCodeHome  // 在主页响应F5是为了刷新仓库列表状态
      ) {
        loadHome();
        return true;
      }
    }

    // Ctrl+T，sync
    if(repo != null && pressedKey == LogicalKeyboardKey.keyT && isControlDown && !isAltDown && !isShiftDown) {
      _doSync();
      return true;
    }

    // Ctrl+G, repo status
    if(pressedKey == LogicalKeyboardKey.keyG && isControlDown && !isAltDown && !isShiftDown) {
      goToRepoStatusPage();
      return true;
    }

    // Ctrl+H, sync history
    if(pressedKey == LogicalKeyboardKey.keyH && isControlDown && !isAltDown && !isShiftDown) {
      goToSyncHistoryPage();
      return true;
    }

    if(currentPage == Cons.homePageCodeFiles) {
      // Ctrl+N, create file
      if(pressedKey == LogicalKeyboardKey.keyN && isControlDown && !isAltDown && !isShiftDown) {
        showCreateFileDialog();
      }
    }

    return false;
  }

  String _getSyncTextOfOpenedRepo(final RepoEntity? openedRepo, Map<String, String> textMap) {
    return textMap[openedRepo?.path ?? ""] ?? "";
  }

  // 传仓库，避免切换仓库后实例变化导致设错仓库
  void setSyncProgressTextOfOpenedRepo(final RepoEntity? openedRepo, final String text, Map<String, String> textMap) {
    final path = openedRepo?.path ?? "";
    if(path.isEmpty) {
      return;
    }

    textMap[path] = text;
  }

  String getSyncProgressText(final RepoEntity? openedRepo) {
    return _getSyncTextOfOpenedRepo(openedRepo, syncProgressMap);
  }

  // 传仓库，避免切换仓库后实例变化导致设错仓库
  void setSyncProgressText(final RepoEntity? openedRepo, final String text) {
    setSyncProgressTextOfOpenedRepo(openedRepo, text, syncProgressMap);
  }

  String getSyncErrText(final RepoEntity? openedRepo) {
    return _getSyncTextOfOpenedRepo(openedRepo, syncErrMap);
  }

  // 传仓库，避免切换仓库后实例变化导致设错仓库
  void setSyncErrText(final RepoEntity? openedRepo, final String text) {
    setSyncProgressTextOfOpenedRepo(openedRepo, text, syncErrMap);
  }

  // 闭包捕获仓库，不然一切换仓库，进度就设错了
  SyncProgressCb getSyncProgressCb(RepoEntity openedRepo) {
    // 注：extraInfo可能是path，也可能是oid（比如删除msg时）
    return (String act, int allCount, int currentAt, String extraInfo) {
      String actText = genSyncProgressText(act, allCount, currentAt, extraInfo);


      setState(() {
        setSyncProgressText(openedRepo, actText);

        // 如果用户在设置这个之前切换仓库，也会设错，期望他不会在remoteReady前切换仓库吧，不处理了，小概率事件
        // 在remote就绪后（执行过doInit，能用了），更新dropbox用户信息为最新
        // if(act == SyncProgressAct.remoteReady) {
        //   final remote = repo?.remote;
        //   if(remote is Dropbox) {
        //     dropboxUsername = remote.config.username;
        //     dropboxAvatar = remote.config.avatar;
        //   }
        // }
      });
    };
  }


  void throwIfSyncCanceled() {
    if(disposed) {
      throw "sync canceled by page disposed";
    }

    if(!mounted) {
      throw "sync canceled by page unmounted";
    }

    if(syncCanceled) {
      // 由于sync函数里捕获到异常会调用progress cb设置 progress text为sync canceled by err，
      // 然后回显到界面，并且那个错误的顺序在这个后面，
      // 所以用户可能看不到这个sync canceled by user，而是看到sync canceled by err
      throw "sync canceled by user";
    }
  }

  Future<void> _goToLoginPageThenReloadHome() async {
    // 从登录页面返回后刷新页面，避免登录成功后仍显示请登录
    await loadHome();
  }

  Widget loginOrRegisterButton() {
    return Column(
      children: [
        const SizedBox(height: 15,),
        getWideButton(
          context,
          t.loginOrRegister,
          onPressed: () async {
            await _goToLoginPageThenReloadHome();
          },
        ),
        const SizedBox(height: 15,)
      ],
    );
  }

  List<Widget> getPageHome(BuildContext context) {
    final repos = this.repos;

    final openRepoButton = TextButton(
      onPressed: () async {
        await Dialogs.choosePathDialog(
          context,
          title: t.open,
          pathController: openRepoPathController,
          textFiledLabel: t.path,
          showMsg: showMsg,
          showMsgLong: showMsgLong,
          refreshUI: refreshUI,
          trueDirFalseFile: true,
          trueExistErrFalseNoExistErrNullNoCheckExist: false,
          errIfPathEmpty: true,
          errIfPathNotAbsOrInvalid: true,
          errIfCallerConsideredPathInvalid: null,
          showFileChooserButton: true,
          onOk: (directoryPath) async {
            App.logger.debug(_TAG, "open repo path: $directoryPath");
            if (directoryPath.isEmpty) {
              return;
            }

            try {
              await Db.saveRepoThenSetOpened(RepoEntity.fromPath(directoryPath));
            }catch(e) {
              App.logger.debug(_TAG, "save repo then set to opened err: path=$directoryPath, err=$e");
              showMsgLong("err: $e");
            }finally {
              await loadHome();
            }
          }
        );
      },
      child: Text(t.open),
    );

    final children = <Widget>[
      Wrap(
        spacing: 8.0, // 项间横向间距
        runSpacing: 8.0, // 换行后的纵向间距
        children: [
          TextButton(
            onPressed: () async {
              await Navigator.pushNamed(
                context,
                Cons.routeRepoCreate,
                arguments: {},
              );

              // 从创建仓库页面返回后，重载页面(包含仓库列表)
              await loadHome();
            },
            child: Text(t.create),
          ),
          TextButton(
            onPressed: () async {
              await Navigator.pushNamed(
                context,
                Cons.routeRepoImport,
                arguments: {},
              );

              await loadHome();
            },
            child: Text(t.import),
          ),
          openRepoButton,
        ]
      ),


      const SizedBox(height: 20),

      Expanded(
        child: getCard(
          child: PullToRefreshList(
            loading: repoStatusLoading,
            err: "",
            listIsEmpty: repos.isEmpty,
            onRefresh: () async {
              await _checkRepoStatus();
            },
            child: ListView.separated(
              itemCount: repos.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = repos[index];
                final name = item.name;
                final path = item.path;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                      try {
                        await Db.setOpenedRepo(path);
                      }finally {
                        await loadHome();
                      }
                    },
                    child: doubleScrollableLine(
                      "",
                      path,
                      line1Widget: singleScrollableRow2(
                        children: [
                          IconButton(
                            icon: Icon(
                              _getIconByRepoPath(path),
                              color: _getColorByRepoPath(path),
                            ),
                            iconSize: 20,
                            tooltip: _getRepoStatusTextByRepoPath(path),
                            onPressed: () {
                              final text = _getRepoStatusTextByRepoPath(path);
                              Dialogs.showCopyDialog(
                                context,
                                title: name,
                                text: text,
                                showMsg: showMsg,
                              );
                            },
                          ),
                          Text(name, style: const TextStyle(fontSize: 18))
                        ],
                      ),
                      trailingIcon: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: t.delete,
                        onPressed: () async {
                          try {
                            await _delRepo(item);
                          }finally {
                            await loadHome();
                          }
                        },
                      )
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ];

    return children;
  }

  Future<void> _delRepo(RepoEntity repoEntity) async {
    await Db.delRepoById(repoEntity);
    // 从列表删除仓库后，从map移除其状态
    repoStatusMap.remove(repoEntity.path);
  }

  IconData? _getIconByRepoPath(String path) {
    return Icons.circle;
  }

  Color? _getColorByRepoPath(String path) {
    final statusVal = repoStatusMap[path]?.value;
    if(statusVal == RepoStatusVal.clean) {
      return Colors.green;
    }

    if(statusVal == RepoStatusVal.dirty) {
      return Colors.blue;
    }

    if(statusVal == RepoStatusVal.err) {
      return Colors.red;
    }

    // 没颜色，正在加载
    return null;
  }

  String _getRepoStatusTextByRepoPath(String path) {
    return repoStatusDesc(repoStatusMap[path]);
  }

  void throwIfPageInvisible() {
    if(!pageVisible) {
      throw "task canceled: user left the page";
    }

    if(disposed) {
      throw "task canceled by page disposed";
    }

    if(!mounted) {
      throw "task canceled by page unmounted";
    }
  }

  Future<void> _checkRepoStatus() async {
    if(repoStatusLoading) {
      return;
    }

    repoStatusLoading = true;
    refreshUI();

    try {
      final tasks = <Future Function()>[];
      for(final repoEntity in repos) {
        // 并发执行是ok的
        final curStatus = repoStatusMap[repoEntity.path];
        if(curStatus == null || curStatus.value != RepoStatusVal.none) { // status 不等于 none 代表上个check status任务已经执行完毕，可执行第2次，否则代表没执行完毕，应等待上个结束再执行下个
          // 创建个空状态占位，避免重复执行执行，比如登录前，执行此函数，
          // 登录后自动刷新，又执行，若不创建这个，就重复执行了，然后就会抛出RepoBusy的异常
          repoStatusMap[repoEntity.path] = RepoStatus();

          Future task() async {
            repoStatusMap[repoEntity.path] = await RepoStatus.checkRepoStatus(
              repoEntity.path,
              throwIfInterrupted: () {
                if(openedRepo != null) {
                  // 用户点了列表中的某个仓库，列表检查status可中止了
                  throw TaskCanceledException("task canceled: user opened a repo '${openedRepo?.name}'");
                }

                throwIfPageInvisible();
              },
            );
            refreshUI();
          }

          tasks.add(task);
        }
      }

      // do not await, else ui can not update instantly
      // eagerError must be false, else if a repo got err, others will not check
      futureFunctionPool(tasks, max: 3, eagerError: false);
    }catch(e, st) {
      App.logger.debug(_TAG, "loading repos status err: $e\n$st");
      showMsgLong("loading repos status err: $e");
    }finally {
      repoStatusLoading = false;
      refreshUI();
    }
  }

  Future<void> closeRepo() async {
    await Db.delOpenedRepo();
    await Db.setFilesLastPath(null);
    await Db.setLastOpenedPage(null);

    // fix: files 搜索列表非空时，切换仓库，进入文件页面，列表没刷新
    _clearSearch();

    await loadHome();
  }

  Future<void> _cancelSync() async {
    // 执行取消
    syncCanceled = true;
    refreshUI();
  }

  Future<void> _doSync<T extends RelatedOids>({
    // BEGIN: 删除file info和msg时使用的参数
    List<T>? delItemsWhenSync,
    RemoteDataType? remoteDataType,
    ThrowIfInterrupted? throwIfInterruptedByCaller,
    SyncProgressCb? syncProgressCbByCaller,
    // END
  }) async {
    final repo = this.repo;
    if(repo == null) {
      showMsg(t.repoInvalid);
      return;
    }

    // 防重入
    if(repoSyncing) {
      return;
    }

    setState(() {
      repoSyncing = true;
      syncCanceled = false;
    });


    // 如果检查登录失败，后面就不会执行了

    // 执行同步
    bool syncCompleteWithoutConflicts = false;
    try {
      final openedRepo = this.openedRepo;
      if(openedRepo == null) {
        showMsg(t.noRepoOpened);
        return;
      }

      setState(() {
        setSyncErrText(openedRepo, "");
        setSyncProgressText(openedRepo, t.syncing);
        showCheckConflicts = false;
      });

      showMsg(t.syncStarted);

      // 检查是否登录
      setState(() {
        // 设为真，目的是为了在检查时禁用同步按钮
        checkingLogin = true;
        setSyncProgressText(openedRepo, t.checkingLogin);
      });

      try {
        // return是为了在没登录时，跳转到登录页面，再返回后不继续执行同步，
        // 避免点击按钮后，进入登录页面，登录成功，返回，
        // 自动继续同步，感觉不好，不如手动再点一下
        if(!await requireLogin()) {
          return;
        }
      }finally {
        setState(() {
          checkingLogin = false;
          setSyncProgressText(openedRepo, "");
        });
      }


      setState(() {
        setSyncProgressText(openedRepo, t.syncing);
      });

      final syncProgressCbOfOpenedRepo = getSyncProgressCb(openedRepo);
      final syncResult = await repo.syncWithLock(
        remoteDataType: remoteDataType,
        delItemsWhenSync: delItemsWhenSync,
        syncProgressCb: (String act, int allCount, int currentAt, String relativePath) {
          syncProgressCbOfOpenedRepo(act, allCount, currentAt, relativePath);
          syncProgressCbByCaller?.call(act, allCount, currentAt, relativePath);
        },
        throwIfSyncCanceled: () {
          throwIfSyncCanceled();
          throwIfInterruptedByCaller?.call();
        },
      );


      // 有冲突则提示用户；无冲突则清空progress text，提示同步完成
      final conflictsCount = syncResult.result.conflictsCount;
      if(conflictsCount > 0) {
        setState(() {
          setSyncProgressText(openedRepo, t.thereAreConflicts(count: conflictsCount));
          showCheckConflicts = true;
        });

        showMsg(t.syncCompleteWithConflicts(conflictsCount: conflictsCount));
      }else {
        setState(() {
          setSyncProgressText(openedRepo, "");
        });

        syncCompleteWithoutConflicts = true;
      }
    }catch(e, st) {
      // 由于需要判断是否有冲突，因此这个不能放到finally里，只能在try catch里分别设置了，不然还要加个是否有冲突的字段，写更多判断，麻烦
      setSyncProgressText(openedRepo, "");

      // 如果不是用户点按钮触发的取消，代表出错了，显示错误信息，记log
      if(!syncCanceled) {
        showMsgLong("sync err: $e");
        // 界面上如果文字过多，可滚动，可复制，可全选，显示大量文本完全没问题，
        // 所以把st打印出来方便我排查问题，release开了混淆，需要找build时的symbol map恢复一下变量名，
        // 之前没开这个出了个null断言异常，我完全不知道在哪出错了，然后想找也找不到，之后再同步也没再出现那个bug，
        // 要是偶然失败，网络原因，那还好，但要是有固定bug，就不好了，可惜当时没打印stack trace，
        // 用叹号做null断言的代码一大片，想找也没法找。。。
        setSyncErrText(openedRepo, "$e\n$st");

        // 这个日志必须上err级别，不然release时默认的warn会忽略debug日志，之前调试全用的debug记的error，
        // 可惜，要不然就能抓到上面说的那个bug了，以后捕获异常一律error级别，不重要的warn，量大又不重要的忽略，或者debug级别
        App.logger.err(_TAG, "sync err: $e\n$st");
      }
    }finally {
      try {
        final lastSyncInfo = await repo.getLastSyncInfo();
        lastSyncedAt = lastSyncInfo.lastSyncAtStr();
        syncedFilesCount = lastSyncInfo.syncedFilesCount;
        // 同步完成且无冲突，显示提示信息，之所以在这显示是因为在这取出lastSyncInfo，顺便，在上面显示的话还得单独调用下brief，而且会丢失节点是否是clean的信息
        if(syncCompleteWithoutConflicts) {
          final lastSyncMsg = lastSyncInfo.msg;
          showMsg("${t.syncComplete}${lastSyncMsg.isEmpty ? "" : ": $lastSyncMsg"}");
        }
      }catch(e, st) {
        App.logger.err(_TAG, "get last sync info err: $e\n$st");
        showMsgLong("get last sync info err: $e");
      }

      setState(() {
        repoSyncing = false;

        // 若为真，代表用户触发了取消同步，同步按钮将禁用，这个如果触发，sync会抛异常，进入上面的catch语句，执行到这时，sync已经被取消了（值为true），所以应该关闭取消（重置为false）
        syncCanceled = false;
      });
    }
  }


  void goToRepoStatusPage() {
    final openedRepo = this.openedRepo;
    if(openedRepo == null) {
      return;
    }

    Navigator.pushNamed(
      context,
      Cons.routeRepoStatus,
      arguments: {"repoPath": openedRepo.path},
    );
  }


  void goToSyncHistoryPage() {
    final openedRepo = this.openedRepo;
    if(openedRepo == null) {
      return;
    }

    Navigator.pushNamed(
      context,
      Cons.routeSyncHistory,
      arguments: {"repoPath": openedRepo.path},
    );
  }


  // 若 fromDrawer 为true，点击检查冲突后会关闭drawer
  List<Widget> _getSyncButton({bool fromDrawer = false}) {
    final openedRepo = this.openedRepo;
    final syncProgressText = getSyncProgressText(openedRepo);
    final syncErrText = getSyncErrText(openedRepo);
    final progressOrErrText = syncErrText.isNotEmpty ? syncErrText : syncProgressText.isNotEmpty ? syncProgressText : t.lastSyncedAt(time: lastSyncedAt);

    return [
      const SizedBox(height: 20),
      getPaddingForButton(
        child: getWideButton(
          context,
          repoSyncing ? t.cancel : t.sync,
          // 如果正在同步，会显示取消，并且只能点按钮取消，不能通过快捷键取消，避免误触发
          secondLineText: repoSyncing ? "" : ShortCuts.getKeyBindingOfSync(),
          bgColor: repoSyncing ? UI.getColorErr() : null,
          // 若已经点了取消，则不能再取消
          onPressed: syncCanceled || checkingLogin ? null : () {
            if(repoSyncing) {
              Dialogs.showOkOrNoDialog(
                context,
                title: t.cancel,
                text: t.areYouSure,
                onOk: () {
                  _cancelSync();
                }
              );
            }else {
              _doSync();
            }
          }
        ),
      ),
      const SizedBox(height: 10),
      getPaddingForButton(
        child: InkWell(
          onTap: () {
            Dialogs.showCopyDialog(
              context,
              title: t.info,
              text: progressOrErrText,
              showMsg: showMsg
            );
          },
          child: Center(child: Text(progressOrErrText, style: TextStyle(color: syncErrText.isNotEmpty ? UI.getColorErr() : null),)),
        ),
      ),
      if(showCheckConflicts)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                currentPage = Cons.homePageCodeConflict;
                setSyncProgressText(openedRepo, "");
                showCheckConflicts = false;
              });

              if(fromDrawer) {
                Navigator.pop(context);
              }
            },
            child: Text(t.check)
          ),
        ),
      const SizedBox(height: 10),

      if(openedRepo != null)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: () {
                goToRepoStatusPage();
              },
              child: textAndDescButtonSmall(context, t.status, ShortCuts.getKeyBindingOfRepoStatus()),
            ),
            TextButton(
              onPressed: () {
                goToSyncHistoryPage();
              },
              child: textAndDescButtonSmall(context, t.history, ShortCuts.getKeyBindingOfSyncHistory())
            ),
            if(!fromDrawer) PopupMenuButton<String>(
              iconSize: 18,
              onSelected: (v) async {
                if (v == 'reload') {
                  await loadHome();
                } else if (v == 'edit') {
                  await _editRepoInfo();
                } else if (v == 'ignore') {
                  await _openIgnoreFile();
                } else if (v == 'delete') {
                  await showDeleteRepoDialog();
                } else if (v == 'close') {
                  await closeRepo();
                } else if (v == 'options') {
                  await _repoOptions();
                } else if (v == 'createKeepFileInEmptyDir') {
                  await _createKeepFiles();
                } else if (v == 'clean') {
                  // await _cleanTempDir();
                  await showCleanRepoDialog();
                } else if (v == 'packFileSize') {
                  await _showUpdatePackFileSizeDialog();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'close', child: Text(t.close)),
                PopupMenuItem(value: 'reload', child: Text(t.reload)),
                PopupMenuItem(value: 'edit', child: Text(t.edit)),
                PopupMenuItem(value: 'ignore', child: Text(t.ignore)),
                PopupMenuItem(value: 'createKeepFileInEmptyDir', child: Text(t.keepEmptyDir)),
                PopupMenuItem(value: 'packFileSize', child: Text(t.packFileSize)),
                PopupMenuItem(value: 'options', child: Text(t.options)),
                PopupMenuItem(value: 'clean', child: Text(t.clean)),
                PopupMenuItem(value: 'delete', child: Text(t.delete)),
              ],
            )
          ],
        ),

      const SizedBox(height: UI.verticalHeight),
    ];
  }

  Future<void> _showUpdatePackFileSizeDialog() async {
    final repo = this.repo;
    if(repo == null) {
      showMsgLong(t.repoInvalid);
      return;
    }

    await Dialogs.showUpdatePackFileSizeDialog(
      context,
      isGlobal: false,
      currentSizeInBytes: (await repo.getConfig()).packFileMaxLenInBytes,
      defaultPackFileMaxLenInBytes: defaultPackFileMaxLenInBytes,
      showMsg: showMsg,
      showMsgLong: showMsgLong,
      onSave: (newSize) async {
        await repo.updateConfigThenGet((config) async {
          config.packFileMaxLenInBytes = newSize;
        });
      }
    );
  }


  bool openRepoErr() {
    return openRepoErrMsg.isNotEmpty;
  }

  Future<void> _editRepoInfo() async {
    await Navigator.pushNamed(
      context,
      Cons.routeRepoEdit,
      arguments: {"repoPath": openedRepo?.path ?? ""},
    );

    // 重新加载仓库信息
    loadHome();
  }

  Future<void> _openIgnoreFile() async {
    // 打开ignore文件让用户编辑即可
    final repo = this.repo;
    if(repo == null) {
      showMsg(t.repoInvalid);
      return;
    }

    final ignoreFile = await repo.getIgnoreFile(createIfNoExists: true);
    await _openWithInternalEditor(ignoreFile.absolute.path, mime: mimeTextPlain);
  }

  Future<void> _repoOptions() async {
    final openedRepo = this.openedRepo;
    if(openedRepo == null) {
      showMsg(t.repoInvalid);
      return;
    }

    await showRepoOptionsDialog(
      context,
      repoPath: openedRepo.path,
      showMsg: showMsg,
      showMsgLong: showMsgLong,
      onOk: (config) async {
        final repo = await Repo.open(openedRepo.path);
        await repo.updateConfig(config);
        // 刷新页面显示修改后的选项
        await loadHome();
      }
    );
  }

  // Future<void> _cleanTempDir() async {
  //   final repo = this.repo;
  //   if(repo == null) {
  //     showMsg(t.repoInvalid);
  //     return;
  //   }
  //
  //   await Dialogs.showOkOrNoDialog(
  //     context,
  //     title: t.clean,
  //     text: t.cleanTempFilesDesc,
  //     onOk: () async {
  //       await Dialogs.showCancelableLoadingDialogAndDoTask(
  //         context,
  //         task: (throwIfCanceled, progressCb) async {
  //           try {
  //             await repo.cleanTempDirWithLocalLock(
  //               throwIfInterrupted: throwIfCanceled,
  //               progressCb: progressCb
  //             );
  //
  //             showMsg(t.done);
  //           }on TaskCanceledException catch(e) {
  //             showMsgLong(e.message);
  //           }catch (e, st) {
  //             showMsgLong("clean temp files err: $e");
  //             App.logger.debug(_TAG, "clean temp files err: $e\n$st");
  //           }
  //         }
  //       );
  //     }
  //   );
  // }

  Future<void> _createKeepFiles() async {
    final repo = this.repo;
    if(repo == null) {
      showMsg(t.repoInvalid);
      return;
    }

    await Dialogs.showOkOrNoDialog(
      context,
      title: t.keepEmptyDir,
      text: t.keepEmptyDirDesc,
      onOk: () async {
        await Dialogs.showCancelableLoadingDialogAndDoTask(
          context,
          task: (throwIfCanceled, progressCb) async {
            try {
              await repo.createKeepFileInEmptyDirsWithLock(
                throwIfInterrupted: throwIfCanceled,
                progressCb: progressCb
              );

              showMsg(t.done);
            }catch (e, st) {
              App.logger.debug(_TAG, "create keep files err: $e\n$st");
              showMsgLong("create keep files err: $e");
            }
          }
        );
      }
    );
  }

  List<Widget> getPageRepo(BuildContext context) {
    if(openRepoErr()) {
      // 打开仓库出错，显示错误信息、关闭和重载按钮
      final children = <Widget>[
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // Centered wide "同步" button at the top
                // 支持取消同步：先弹窗请求用户确认，再决定
                // 判断是否可取消(判断与否皆可，直接同步开始后，允许取消，然后执行下面的取消逻辑，点击取消后禁用取消按钮即可)：调用 Repo.syncCanBeCanceled()
                // 执行取消：在调用 Repo.syncWithLock()时传入一个函数，
                //          用户点击取消按钮则改此函数使用的flag值以使函数抛出异常，
                //          然后同步任务就取消了
                Center(child: SelectableText(openRepoErrMsg, style: TextStyle(color: UI.getColorErr()),)),

                const SizedBox(height: 20),
                getPaddingForButton(
                  child: getWideButton(
                    context,
                    t.reload,
                    onPressed: () async {
                      await loadHome();
                    }
                  ),
                ),
                const SizedBox(height: 24),
                getPaddingForButton(
                  child: getWideButton(
                    context,
                    t.close,
                    onPressed: () async {
                      await closeRepo();
                    }
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ];

      return children;
    }


    // 已打开仓库有效

    final repo = this.repo;
    final repoConfig = this.repoConfig;

    // loading
    if(repo == null || repoConfig == null) {
      return [];
    }


    // Field data (could be made dynamic)
    final fields = <LabelValue>[];
    final fieldItemTextStyle = const TextStyle(fontSize: 16);

    fields.add(LabelValue(icon: Icons.category, label: t.remoteType, value: repoConfig.remoteConfig.typeToText(), textStyle: fieldItemTextStyle));

    final remoteConfigData = repoConfig.remoteConfig.typedData();
    if(remoteConfigData is RemoteConfigDataForDropbox) {
      fields.add(LabelValue(icon: Icons.person, label: t.user, value: remoteConfigData.username, headingImgUrl: remoteConfigData.avatar, textStyle: fieldItemTextStyle));
    }else if(remoteConfigData is RemoteConfigDataForWebdav) {
      fields.add(LabelValue(icon: Icons.person, label: t.user, value: remoteConfigData.user, textStyle: fieldItemTextStyle));
      fields.add(LabelValue(icon: Icons.cloud, label: t.host, value: remoteConfigData.host, textStyle: fieldItemTextStyle));
    }


    fields.add(LabelValue(icon: Icons.folder_outlined, label: t.remotePath, value: repoConfig.remoteConfig.basePath, textStyle: fieldItemTextStyle));
    fields.add(LabelValue(icon: Icons.folder, label: t.localPath, value: repo.path, textStyle: fieldItemTextStyle));

    // 创建仓库时随机生成的代表当前设备的名字
    fields.add(LabelValue(icon: Icons.devices, label: t.client, value: repo.client.name, textStyle: fieldItemTextStyle));
    // 已上传的文件数量
    fields.add(LabelValue(icon: Icons.upload_file_outlined, label: t.files, value: syncedFilesCount.toString(), textStyle: fieldItemTextStyle));
    // 合并模式：如果同时需要拉取和推送，怎么合并远程和本地的文件
    fields.add(LabelValue(icon: Icons.merge, label: t.mergeMode, value: mergeModeToLocalizedText(repoConfig.mergeMode), textStyle: fieldItemTextStyle));

    final children = [
      // const SizedBox(height: 20),

      // Centered wide "同步" button at the top
      // 支持取消同步：先弹窗，用户若点确定，则取消
      // 判断是否可取消(判断与否皆可，直接同步开始后，允许取消，然后执行下面的取消逻辑，点击取消后禁用取消按钮即可)：调用 Repo.syncCanBeCanceled()
      // 执行取消：在调用 Repo.syncWithLock()时传入一个函数，
      //          用户点击取消按钮则改此函数使用的flag值以使函数抛出异常，
      //          然后同步任务就取消了
      ..._getSyncButton(),

      // const SizedBox(height: 8),
      if(isPcPlatform())
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          // spacing: 8,
          // runSpacing: 8,
          children: [
            IconButton(
              tooltip: t.openInExt,
              onPressed: () async {
                await _openFileInExternal(openedRepo?.path ?? "");
              }, 
              icon: Icon(Icons.folder, size: UI.smallIconSize)
            ),

            IconButton(
              tooltip: "Zed",
              onPressed: () async {
                try {
                  await runCmd(["zed", openedRepo?.path ?? ""]);
                }catch(e) {
                  showMsgLong("err: $e");
                }
              },
              icon: MySvg.smallIcon(UI.isDarkTheme() ? "assets/etc/zed_dark.svg" : "assets/etc/zed_light.svg", semanticsLabel: "Zed"),
            ),
            IconButton(
              tooltip: "VSCodium",
              onPressed: () async {
                try {
                  await runCmd(["codium", openedRepo?.path ?? ""]);
                }catch(e) {
                  showMsgLong("err: $e");
                }
              },
              icon: MySvg.smallIcon("assets/etc/vscodium.svg", semanticsLabel: "VSCodium", colorFilter: const ColorFilter.mode(Colors.blue, BlendMode.srcIn)),
            ),
            IconButton(
              tooltip: "VSCode",
              onPressed: () async {
                try {
                  await runCmd(["code", openedRepo?.path ?? ""]);
                }catch(e) {
                  showMsgLong("err: $e");
                }
              }, 
              icon: MySvg.smallIcon("assets/etc/vscode.svg", semanticsLabel: "VSCode")
            ),
          ],
        ),
      // List of fields, each on one row with label left and value right
      Expanded(
        child: getCard(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: fields.length,
            separatorBuilder: (_, __) => const Divider(height: 40),
            itemBuilder: (context, index) {
              return singleScrollableLabelValueRow(
                fields[index],
                textSelectable: true,
              );
            },
          ),
        ),
      ),
    ];

    return children;
  }

  Future<void> showDeleteRepoDialog() async {
    final keyDeleteRemote = "deleteRemote";
    final keyDeleteLocal = "deleteLocal";

    await Dialogs.showCheckboxDialog(
      context,
      title: t.delete,
      options: [
        TextValueSelected(text: t.deleteRemote, value: keyDeleteRemote),
        TextValueSelected(text: t.deleteLocal, value: keyDeleteLocal),
      ],
      onOk: (result) async {
        await Dialogs.showCancelableLoadingDialogAndDoTask(
          context,
          task: (throwIfCanceled, progressCb) async {
            bool? deleteRemote;
            bool? deleteLocal;

            final openedRepo = this.openedRepo;

            bool success = false;

            try {
              if (openedRepo == null) {
                showMsg("no repo opened");
                return;
              }

              final repo = this.repo;
              if (repo == null) {
                showMsg("repo invalid");
                return;
              }

              deleteRemote = result[keyDeleteRemote]!.selected;
              deleteLocal = result[keyDeleteLocal]!.selected;

              if (!deleteRemote && !deleteLocal) {
                return;
              }

              await repo.deleteRepo(
                deleteRemote: deleteRemote,
                deleteLocal: deleteLocal,
                throwIfInterrupted: () {
                  try {
                    throwIfCanceled();
                  } on TaskCanceledException catch (_) {  // 若是取消异常，抛出特定提示；其他异常则不处理（正常抛出）
                    throw t.deleteRepoCanceledNote;
                  }
                },
                progressCb: progressCb
              );

              success = true;
              showMsg(t.deleted);
            } catch (e, st) {
              App.logger.debug(_TAG, "delete repo err: params(deleteRemote=$deleteRemote, deleteLocal=$deleteLocal)\nerr: $e\n$st");
              showMsgLong("err: $e");
            } finally {
              if (success) {
                // 删除成功且删除了本地，则从仓库列表移除仓库，然后关闭仓库
                if (deleteLocal == true && openedRepo != null) {
                  await _delRepo(openedRepo);
                  await closeRepo();
                }
              }
            }
          }
        );
      }
    );
  }




  Future<void> showCleanRepoDialog() async {
    final repo = this.repo;
    if (repo == null) {
      showMsg(t.repoInvalid);
      return;
    }


    final keyTempFiles = "tempFiles";
    final keyIndex = "index";
    final keyDownloadCache = "downloadCache";
    final keyObjectsCache = "objectsCache";

    await Dialogs.showCheckboxDialog(
      context,
      title: t.clean,
      options: [
        TextValueSelected(text: t.tempFiles, value: keyTempFiles, desc: t.cleanTempFilesDesc),
        TextValueSelected(text: t.index, value: keyIndex, desc: t.cleanIndexDesc),
        TextValueSelected(text: t.downloadCache, value: keyDownloadCache),
        TextValueSelected(text: t.objectsCache, value: keyObjectsCache),
      ],
      onOk: (result) async {
        await Dialogs.showCancelableLoadingDialogAndDoTask(
          context,
          task: (throwIfCanceled, progressCb) async {
            try {
              final cleanTempFiles = result[keyTempFiles]!.selected;
              final cleanIndex = result[keyIndex]!.selected;
              final cleanDownloadCache = result[keyDownloadCache]!.selected;
              final cleanObjectsCache = result[keyObjectsCache]!.selected;

              if (!cleanTempFiles && !cleanIndex && !cleanDownloadCache && !cleanObjectsCache) {
                return;
              }

              if(cleanTempFiles) {
                throwIfCanceled();
                progressCb(SyncProgressAct.cleanTempFiles, 0, 0, "");

                await repo.cleanTempDirWithLocalLock(
                  throwIfInterrupted: throwIfCanceled,
                  progressCb: progressCb,
                );
              }

              if(cleanIndex) {
                throwIfCanceled();
                progressCb(SyncProgressAct.cleanIndex, 0, 0, "");

                await repo.cleanIndexWithLocalLock();
              }

              if(cleanDownloadCache || cleanObjectsCache) {
                throwIfCanceled();
                progressCb(SyncProgressAct.cleanCachedData, 0, 0, "");

                await repo.cleanCachedDataWithLocalLock(
                  cleanDownloadCache: cleanDownloadCache,
                  cleanObjectsCache: cleanObjectsCache,
                  throwIfInterrupted: throwIfCanceled,
                  progressCb: progressCb,
                );
              }

              showMsg(t.done);
            } catch (e, st) {
              App.logger.debug( _TAG, "clean repo err: $e\n$st", );
              showMsgLong("err: $e");
            }
          },
        );
      },
    );
  }

  void _copyRepoRelativePath(String fullPath) {
    // copyTextThenShowMsg(FilePath.genRelativePathSafe(openedRepo?.path ?? "", fullPath, ifErrReturnEmpty: false).toString());
    // 拷贝相对路径一般都是为引用资源，这时需要的是 unix styled path
    copyTextThenShowMsg(FilePath.genRelativePathSafe(openedRepo?.path ?? "", fullPath, ifErrReturnEmpty: false).toUnixPathStr());
  }

  void goToFileHistoryPage(String path) {
    final repo = this.repo;

    // 跳转到历史页面，列出历史，点击可预览，
    // 可和workdir最新文件diff，可恢复，可导出至指定目录（弹出系统文件选择器）

    final FilePath relativePath;
    if(Mock.enable) {
      relativePath = FilePath.genRelativePath(File(path).parent.absolute.path, path);
    }else {
      if(repo == null) {
        App.logger.debug(_TAG, "_history: repo is null");
        showMsg(t.repoInvalid);
        return;
      }

      relativePath = FilePath.genRelativePathSafe(repo.getWorkdirPath(), path, ifErrReturnEmpty: true);
    }

    if(!mounted) return;

    Navigator.pushNamed(
      context,
      Cons.routeFileHistory,
      arguments: {"path": relativePath.toUnixPathStr()},
    );
  }

  Future<void> _rename(String path) async {
    final oldName = FilePath.fromString(path).name();
    final oldNameNoExt = p.basenameWithoutExtension(oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dctx) {
        final ctrl = TextEditingController.fromValue(
          TextEditingValue(
            text: oldName,
            selection: TextSelection(baseOffset: 0, extentOffset: oldNameNoExt.length),
          )
        );

        void submit(String? value) {
          Navigator.of(dctx).pop(value ?? ctrl.text);
        }

        return AlertDialog(
          title: Text(t.rename),
          content: TextField(controller: ctrl, autofocus: true, onSubmitted: submit),
          actions: [
            TextButton(onPressed: () => Navigator.of(dctx).pop(), child: Text(t.cancel)),
            TextButton(onPressed: () => submit(null), child: Text(t.ok)),
          ],
        );
      },
    );


    if(newName == null || newName.isEmpty) {
      return;
    }

    try {
      final path1 = FilePath.fromString(path);
      if(path1.name() == newName) {
        // 新旧名称相同
        return;
      }

      final path2 = path1.copyThenRename(newName);
      final path2Str = path2.toString();
      if(await getFileType(path2Str) != FileSystemEntityType.notFound) {
        // 新名称已存在
        showMsgLong(t.pathAlreadyExists);
        return;
      }

      final fileType = await getFileType(path);

      final FileSystemEntity newItem;
      if(fileType == FileSystemEntityType.directory) {
        path1.toDir().renameSync(path2Str);
        newItem = Directory(path2Str);
      }else {
        path1.toFile().renameSync(path2Str);
        newItem = File(path2Str);
      }

      if(filesPageSearchId.isNotEmpty) {
        // search mode 直接 rename列表元素，避免触发递归搜索
        final foundIdx = foundFileList.indexWhere((it) => it.absolute.path == path);
        if(foundIdx >= 0) {
          foundFileList[foundIdx] = newItem;
        }
      }

      // 重命名后更新已选择条目列表
      final renamedItemIdxInSelectedList = selectedFileList.indexWhere((it) => it.absolute.path == path1.toString());
      if(renamedItemIdxInSelectedList != -1) {
        selectedFileList[renamedItemIdxInSelectedList] = newItem;
      }
    }catch(e) {
      App.logger.debug(_TAG, "rename file err: path=$path, newName=$newName, err=$e");
      showMsgLong("err: $e");
    }finally {
      if(filesPageSearchId.isEmpty) {
        await _loadFiles(currentPath);
      }else {
        refreshUI();
      }
    }

  }

  Future<void> _delete(List<FileSystemEntity> list) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) {
        return AlertDialog(
          title: SelectableText(t.delete),
          content: SelectableText(list.length == 1 ? t.fileWillBeDeleted(name: p.basename(list[0].path)) : t.nItemsWillBeDeleted(n: list.length.toString())),
          actions: [
            TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: Text(t.cancel)),
            TextButton(onPressed: () => Navigator.of(dctx).pop(true), child: Text(t.ok)),
          ],
        );
      },
    );


    if(confirmed != true) {
      return;
    }

    if(filesPageIsLoading) {
      showMsgLong(t.anotherTaskRunningPleaseTryAgainLater);
      return;
    }

    // 我不确定setState什么时机被调用，所以为了确保立刻更新loading变量，在外部赋值，再调用setState
    filesPageIsLoading = true;
    setState(() {});

    bool hasErrShowed = false;
    try {
      for(final item in list) {
        final path = item.absolute.path;
        try {
          await Fs.delFileOrDir(path);

          if(filesPageSearchId.isNotEmpty) {
            // search mode，删除条目
            final foundIdx = foundFileList.indexWhere((it) => it.absolute.path == path);
            if(foundIdx >= 0) {
              foundFileList.removeAt(foundIdx);
            }
          }

          fileList.removeWhere((it) => it.absolute.path == path);

          selectedFileList.removeWhere((it) => it.absolute.path == path);
        }catch(e) {
          App.logger.debug(_TAG, "delete path '$path' err: $e");

          // 避免错误很多无限刷屏，只显示一个错误，让用户知道出错了就行了
          if(!hasErrShowed) {
            hasErrShowed = true;
            showMsgLong("err: $e");
          }
        }
      }

      // 直接从选择模式移除对应条目了，所以这里判定如果列表为空则退出选择模式，否则不需要退出
      if(selectedFileList.isEmpty) {
        _quitSelectionModeForFiles();
      }

      // 不用刷新页面，直接从条目列表移除对应条目了
      // if(filesPageSearchId.isEmpty) {
      //   // 非搜索模式才刷新页面
      //   await _loadFiles(currentPath);
      // }
    }finally {
      // 这里就算setState被延误调用也无所谓，顶多就是其他任务晚点执行，并不会出错，所以不必先解除loading再调用setState
      setState(() {
        filesPageIsLoading = false;
      });
    }
  }

  void _showFileInfo(String path) {
    final fileItem = FileItem.fromPath(path);

    showDialog<void>(
      context: context,
      builder: (ctx) => FileInfoDialog(
        fileItem: fileItem,
      ),
    );
  }


  // mime若为null会猜，否则使用指定mime
  Future<bool> _openWithInternalEditor(String path, {required String? mime}) async {
    return await openWithInternalEditor(path, mime: mime, callerTag: _TAG, context: context, showMsgLong: showMsgLong);
  }


  Future<void> _doSearchFiles(FilePath path) async {
    try {
      await _doSearchFilesNoCatch(path);
    }catch(e, st) {
      App.logger.debug(_TAG, "search files err: $e\n$st");
      showMsgLong("search files err: $e");
    }finally {
      filesPageSearching = false;
      setState(() {});
    }
  }

  Future<void> _doSearchFilesNoCatch(FilePath path) async {
    final keyword = filesPageSearchKeyword.text;
    if(keyword.isEmpty) {
      await _loadFiles(path);
      return;
    }

    foundFileList.clear();
    filesPageSearching = true;
    currentPath = path;
    setState(() {});

    final keywordLow = keyword.toLowerCase();
    final searchId = randomStringUnsafeButFaster(32);
    filesPageSearchId = searchId;
    await DirSearchUtil.realBreadthFirstSearch(
      dir: path.toDir(),
      match: (idx, path) {
        final name = p.basename(path);
        //匹配名称 或 "*.txt"之类的后缀
        return name.toLowerCase().contains(keywordLow)
          // RegexUtil内部会忽略大小写（实际上是再转一次toLowerCase()），所以这里直接传原参数给它就行
          || RegexUtil.matchWildcard(name, keywordLow);
      },
      matchedCallback: (idx, item) {
        final type = getFileTypeSync(item);
        if(type == FileSystemEntityType.directory) {
          foundFileList.add(Directory(item));
        }else {
          foundFileList.add(File(item));
        }
        setState((){});
      },
      canceled: () => searchId != filesPageSearchId || !mounted,
    );

  }

  void _clearSearch() {
    setState(() {
      filesPageSearching = false;
      filesPageSearchId = '';
      filesPageSearchKeyword.text = '';
      foundFileList.clear();
    });
  }

  int filesComparator(FileSystemEntity o1, FileSystemEntity o2, SortRule sortRule) {
    int sortByName() => compareStringAsNumIfPossible(
        p.basenameWithoutExtension(o1.path), p.basenameWithoutExtension(o2.path));
    int sortByType() => compareStringAsNumIfPossible(
        p.extension(o1.path), p.extension(o2.path));

    int getFileEntitySize(FileSystemEntity entity) {
      if(entity is File) {
        return entity.lengthSync();
      }

      return 0;
    }

    int compareResult;
    final sortMethod = sortRule.sortBy;
    if (sortMethod == SortBy.name) {
      compareResult = sortByName();
    } else if (sortMethod == SortBy.type) {
      compareResult = sortByType();
    } else if (sortMethod == SortBy.size) {
      compareResult = getFileEntitySize(o1).compareTo(getFileEntitySize(o2));
    } else { // LAST_MODIFIED
      compareResult = o1.statSync().modified.millisecondsSinceEpoch.compareTo(o2.statSync().modified.millisecondsSinceEpoch);
    }

    // if equals and not sorting by name, try name
    if (compareResult == 0 && sortMethod != SortBy.name) {
      compareResult = sortByName();
    }

    // if still equals and not sorting by type, try type
    if (compareResult == 0 && sortMethod != SortBy.type) {
      compareResult = sortByType();
    }

    final ascend = sortRule.ascending;
    if (compareResult > 0) {
      return ascend ? 1 : -1;
    } else if (compareResult < 0) {
      return ascend ? -1 : 1;
    } else {
      // 若仍相等，返回 non-zero 以避免被视为“相同键”时被去重：
      // 可按 name + path 保证稳定唯一性，示例用 name compare 再比较 hashCode
      final tie = p.basenameWithoutExtension(o1.path).compareTo(p.basenameWithoutExtension(o2.path));
      if (tie != 0) return ascend ? tie : -tie;
      return ascend ? o1.hashCode.compareTo(o2.hashCode) : o2.hashCode.compareTo(o1.hashCode);
    }
  }
  
  /// 若name不为空，定位到path目录下的对应文件
  Future<void> _loadFiles(FilePath path, {String name = ''}) async {
    try {
      await _doLoadFiles(path, name: name);
    }finally {
      refreshUI();
    }
  }

  /// 若name不为空，定位到path目录下的对应文件
  Future<void> _doLoadFiles(FilePath path, {String name = ''}) async {
    App.logger.verbose(_TAG, "_doLoadFiles: path=$path, name=$name");

    _clearSearch();
    setState(() {
      currentPage = Cons.homePageCodeFiles;
      fileList.clear();
    });

    // save scroll position of last path
    try {
      final curPathMapKey = currentPath.toMapKey();
      filesPageScrollOffsets[curPathMapKey] = filesPageScrollController.offset;
    }catch(_) {

    }

    final pathMapKey = path.toMapKey(); // unix path
    final pathStr = path.toString();  // platform styled path

    // 移除所有当前目录的子目录的滚动位置信息
    try {
      filesPageScrollOffsets.removeWhere((key, value) => key.startsWith("$pathMapKey/"));
    }catch(_) {
    }

    try {
      final showRepoDataDirInFiles = AppConfig.getConfig().showRepoDataDirInFiles;
      final sortRule = filesPageSortMap[pathMapKey] ?? filesPageGlobeSort;

      // ai说dart的这个SplayTreeSet如果不返回0，会引发未定义异常，甚至死循环，不像java那么安全，所以不用它排序了，改用list.sort()了
      // var dirSortedSet = SplayTreeSet<FileSystemEntity>((a, b) {
      //   return filesComparator(a, b, sortRule);
      // });
      // var fileSortedSet = SplayTreeSet<FileSystemEntity>((a, b) {
      //   return filesComparator(a, b, sortRule);
      // });

      loadFilesErr = '';
      final newDirList = <FileSystemEntity>[];
      final newFileList = <FileSystemEntity>[];
      await for(final fe in Directory(pathStr).list(followLinks: false)) {
        if(!Fs.isAppAllowedFileEntityType(fe)) {
          continue;
        }

        if(!showRepoDataDirInFiles && p.basename(fe.path) == Repo.dataDirName) {
          continue;
        }

        if(sortRule.foldersFirst) {
          if(fe is Directory) {
            newDirList.add(fe);
          }else {
            newFileList.add(fe);
          }
        }else {
          newFileList.add(fe);
        }
      }

      newDirList.sort((a, b) {
        return filesComparator(a, b, sortRule);
      });
      newFileList.sort((a, b) {
        return filesComparator(a, b, sortRule);
      });

      if(sortRule.foldersFirst) {
        newDirList.addAll(newFileList);
      }

      // 非文件夹优先，则文件夹和文件都会添加到newFileList，所以直接返回它就行
      fileList = sortRule.foldersFirst ? newDirList : newFileList;
    }catch(e) {
      setState(() {
        loadFilesErr = e.toString();
      });
    }

    setState(() {
      currentPath = path;
    });

    // 若出错直接返回
    if(loadFilesErr.isNotEmpty) {
      return;
    }

    // 若没错，保存最后打开路径，并定位到指定条目；若有错就不保存当前目录了，避免app重启后恢复当前目录，又崩溃，导致app无法启动

    // 保存路径一律用unix path
    await Db.setFilesLastPath(pathMapKey);

    // 滚动到指定条目，如果指定了文件名的话
    if(name.isNotEmpty) {
      final foundIdx = fileList.indexWhere((it) => p.basename(it.path) == name);
      if(foundIdx >= 0) {
        // 重置选择模式
        _resetSelectionMode(rebuild: false);
        selectedFileList.add(fileList[foundIdx]);
        final double guessedOffset = foundIdx * 60;
        filesPageScrollOffsets[pathMapKey] = guessedOffset;
      }
    }


    // 尝试恢复上次滚动位置，如果有的话
    try {
      final offset = filesPageScrollOffsets.remove(pathMapKey);

      // 文件列表为空，就不需要恢复滚动位置了，要不然jumpTo会报错
      if(fileList.isEmpty) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final double finalOffset = offset != null ? offset.clamp(0, filesPageScrollController.position.maxScrollExtent) : 0;
          if(finalOffset != filesPageScrollController.position.pixels) {
            // 滚动位置应在 0 到 max像素之间，clamp将返回值限制在两个入参的闭区间，并且左参数应小于等于右参数
            filesPageScrollController.jumpTo(finalOffset);
          }
        }catch(e) {
          App.logger.debug(_TAG, "restore scroll position err (err code: 16461459): $e");
        }
      });
    }catch(e) {
      App.logger.debug(_TAG, "restore scroll position err (err code: 19455231): $e");
    }
  }

  void _resetSelectionMode({bool rebuild = true}) {
    selectedFileList.clear();
    pasteMode = '';
    if(rebuild) {
      refreshUI();
    }
  }

  Future<void> _openFileInExternal(String path) async {
    await openFileInExternal(path, showMsgLong: showMsgLong, callerTag: _TAG);
  }

  Widget _buildBreadcrumbs() {
    final parts = currentPath.getValueCopy();
    final crumbs = <Widget>[];

    final lastIdx = parts.length - 1;
    for (var idx = 0; idx < parts.length; idx++) {
      final List<String> pathValue = [];
      for(var idx2 = 0; idx2 <= idx; idx2++) {
        pathValue.add(parts[idx2]);
      }

      final fileItem = FileItem(name: parts[idx], path: FilePath(value: pathValue));
      final fullPath = fileItem.path.toString();
      crumbs.add(
        DropdownMenuWidget(
          menuItems: [
            // open with
            MenuItem(value: "open_in_ext", text: t.openInExt, onClick: () async {
              _openFileInExternal(fullPath);
            }),
            MenuItem(value: "revealInFileExplorer", text: t.revealInFileExplorer, onClick: () async {
              revealFile(fullPath, showMsgLong: showMsgLong);
            }),
            MenuItem(value: "info", text: t.info, onClick: () async {
              _showFileInfo(fullPath);
            }),
            MenuItem(value: "copy_path", text: t.copyPath, onClick: () async {
              copyTextThenShowMsg(fullPath);
            }),
            MenuItem(value: "copy_relative_path", text: t.copyRelativePath, onClick: () async {
              _copyRepoRelativePath(fullPath);
            }),
            MenuItem(value: "go_to", text: t.goTo, onClick: () async {
              final path = await Dialogs.showInputDialog(
                context,
                title: t.goTo,
                initialValue: fullPath,
                showMsg: showMsg,
                showMsgLong: showMsgLong,
                textInputAction: TextInputAction.go,
              );

              App.logger.debug(_TAG, "path to go: $path");

              if(path == null || path.isEmpty) {
                return;
              }

              final fileType = await getFileType(path);
              if(fileType == FileSystemEntityType.notFound) {
                showMsgLong(t.pathDoesntExist);
                return;
              }

              final filePath = FilePath.fromString(path);
              if(fileType == FileSystemEntityType.directory) {
                _loadFiles(filePath);
                return;
              }

              // file or其他类型，打开父目录，选中文件
              _loadFiles(filePath.parent(), name: p.basename(path));

            }),
          ],
          onTap: () async {
            try {
              await _loadFiles(fileItem.path);
              // 如果需要刷新 UI，请在 loadFiles 内或外部调用 setState
            } catch (e) {
              // 可根据需要显示错误提示
              App.logger.debug(_TAG, 'Failed to load ${fileItem.path.toUnixPathStr()}: $e');
            }
          },
          child: Text(
            idx == 0 && fileItem.name.isEmpty ? 'root' : fileItem.name,
            style: idx == lastIdx ? TextStyle(fontWeight: FontWeight.bold) : null,
          ),
        ),
      );

      // 添加分隔符（最后一项不加）
      if (idx < parts.length - 1) {
        crumbs.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(' > ', style: TextStyle(color: Colors.grey)),
        ));
      }
    }

    // 自动滚动到面包屑末尾（滚到最右边，显示路径最后一个条目的名字）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (breadcrumbScrollController.hasClients) {
        breadcrumbScrollController.jumpTo(
          breadcrumbScrollController.position.maxScrollExtent,
        );
      }
    });

    return SingleChildScrollView(
      controller: breadcrumbScrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: crumbs,
      ),
    );
  }


  Future<void> _createFolder(FilePath path) async {
    await path.toDir().create(recursive: true);
  }

  Future<void> _createFile(FilePath path) async {
    await path.toFile().create(recursive: true);
  }


  Future<void> _refreshFileList() async {
    if(currentPage != Cons.homePageCodeFiles) {
      return;
    }

    if(filesPageSearchId.isEmpty) {
      await _loadFiles(currentPath);
    }else {
      await _doSearchFiles(currentPath);
    }
  }



  List<Widget> getActionsFiles() {
    return [
      IconButton(
        icon: Icon(Icons.home),
        tooltip: t.home,
        onPressed: () async {
          await _loadFiles(FilePath.fromString(openedRepo?.path ?? ''));
        },
      ),
      IconButton(
        icon: Icon(Icons.refresh),
        tooltip: t.refresh,
        onPressed: () async {
          await _refreshFileList();
        },
      ),
      IconButton(
        icon: Icon(Icons.sort),
        tooltip: t.sort,
        onPressed: () async {
          final path = currentPath.toMapKey();
          await showSortDialog(
            context,
            path: path,
            showMsg: showMsg,
            showMsgLong: showMsgLong,
            onOk: (result) async {
              // 更新ui
              if(result.applyToThisFolderOnly) {
                filesPageSortMap[path] = result;
              }else {
                filesPageSortMap.remove(path);
                filesPageGlobeSort = result;
              }

              _loadFiles(currentPath);

              // 存储修改到db （注意，就算上面loadFiles出错也会更新设置项，小概率发生，后果可接受，不用处理）
              if(result.applyToThisFolderOnly) {
                await Db.setSortByPath(path, result);
              }else {
                // null to remove sort rule for path
                await Db.setSortByPath(path, null);
                await Db.setGlobalSort(result);
              }
            }
          );
        },
      ),
      IconButton(
        icon: Icon(Icons.add),
        tooltip: t.create,
        onPressed: showCreateFileDialog,
      ),
    ];
  }

  Future<void> showCreateFileDialog() async {
    try {
      // 新建文件夹：弹窗获取名称并调用外部方法创建，然后刷新
      final nameWithType = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          void submit(String? value) {
            Navigator.of(ctx).pop("fil:${value ?? ctrl.text}");
          }

          return AlertDialog(
            title: Text(t.tNew),
            content: TextField(controller: ctrl, autofocus: true, onSubmitted: submit),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t.cancel)),
              // dir: 前缀是为了区分是创建目录还是文件
              TextButton(onPressed: () => Navigator.of(ctx).pop("dir:${ctrl.text}"), child: Text(t.folder)),
              TextButton(onPressed: () => submit(null), child: Text(t.file)),
            ],
          );
        },
      );

      if(nameWithType == null) {
        return;
      }

      final isCreateDir = nameWithType.substring(0, 3) == "dir";
      final name = nameWithType.substring(4);
      if(name.isEmpty) {
        return;
      }

      final target = currentPath.copy().append(name);
      if(await getFileType(target.toString()) != FileSystemEntityType.notFound) {
        throw t.pathAlreadyExists;
      }

      if(isCreateDir) {
        await _createFolder(target);
      }else {
        await _createFile(target);
      }

      // 若非搜索模式，刷新页面
      if(filesPageSearchId.isEmpty) {
        // 注意：如果创建的目录末尾有空格，
        // Win系统似乎会删除末尾空格导致路径无效，(其他系统没测试，可能也有类似问题)
        // 就算使用Directory.create()返回的Directory对象也依然如此，
        // 可能移除末尾空格能解决，但没必要为这种罕见情况写特殊代码，所以不改了

        // 若是创建目录，打开创建的目录，否则刷新当前页面
        await _loadFiles(isCreateDir ? target : currentPath);
      }

      if(!isCreateDir) {
        await _openWithInternalEditor(target.toString(), mime: mimeTextPlain);
      }
    }catch(e, st) {
      showMsgLong("err: $e");
      App.logger.debug(_TAG, "create file or folder err: $e\n$st");
    }
  }

  bool filesItemEquals(dynamic it1, dynamic it2) {
    return it1.absolute.path == it2.absolute.path;
  }

  List<Widget> getPageFiles(BuildContext context) {
    final theme = Theme.of(context);
    final selectedBgColor = UI.getSelectedBgColor(theme);

    // 当前展示的列表：如果在搜索模式且有结果则用 foundFileList，否则用 fileList
    final displayList = filesPageSearchId.isNotEmpty ? foundFileList : fileList;

    final isSelectionModeOn = selectedFileList.isNotEmpty;
    final currentPathStr = currentPath.toString();

    return [
      // 顶部：搜索 + 操作按钮
      SearchTextFiled(
        keyword: filesPageSearchKeyword,
        searching: filesPageSearching,
        showClear: filesPageSearchId.isNotEmpty,
        onSearch: (keyword) {
          if(keyword.isEmpty) {
            _loadFiles(currentPath);
          }else {
            _doSearchFiles(currentPath);
          }
        },
      ),

      // 面包屑
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _buildBreadcrumbs()),
      const Divider(),

      // 文件列表区域
      Expanded(
        child: PullToRefreshList(
          loading: filesPageIsLoading,
          err: loadFilesErr,
          listIsEmpty: displayList.isEmpty,
          onRefresh: () async {
            await _refreshFileList();
          },
          child: ListView.separated(
            // 即使内容不足一屏也能下拉，不然内容不足时无法触发下拉刷新
            physics: const AlwaysScrollableScrollPhysics(),
            controller: filesPageScrollController,
            padding: UI.listPaddingOnlyBottom,
            itemCount: displayList.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, idx) {
              final fse = displayList[idx];
              final name = p.basename(fse.path);
              final isDir = fse is Directory;
              var subtitle = '';
              var fullPath = '';
              var itemParentDirRelativePathUnderCurrentPath = '';
              try {
                fullPath = fse.absolute.path;
                final stat = fse.statSync();
                final modified = formatDateTimeHumanFriendly(stat.modified);
                // dir不要直接显示大小，需要递归计算，费cpu
                // 目录则显示“目录 · 最后修改时间”；文件则显示“文件大小 · 最后修改时间”
                subtitle = "${isDir ? t.dir : Fs.readableSize(stat.size)} · $modified";

                // 如果是搜索模式，显示当前路径下的文件的相对路径的父目录
                // 例如当前路径为 /abc，当前条目路径为 /abc/def/456.txt，则显示 def
                if(filesPageSearchId.isNotEmpty) {
                  itemParentDirRelativePathUnderCurrentPath = FilePath.genRelativePathSafe(currentPathStr, fullPath, ifErrReturnEmpty: false).parent().toUnixPathStr();
                }
              } catch (_) {}

              final selected = selectedFileList.any((e) => e.absolute.path == fullPath);

              return ListTile(
                leading: IconButton(
                  icon: Icon(getIconByFileName(p.basename(fse.path), isDir: isDir)),
                  onPressed: () {
                    setState(() {
                      UI.switchSelected(
                        item: fse,
                        selectedItems: selectedFileList,
                        equals: filesItemEquals
                      );
                    });
                  },
                  onLongPress: () {
                    setState(() {
                      UI.switchSelectSpan(
                        itemIdxOfItemList: idx,
                        item: fse,
                        selectedItems: selectedFileList,
                        itemList: displayList,
                        equals: filesItemEquals,
                        switchItemSelected: (it) => UI.switchSelected(
                          item: it,
                          selectedItems: selectedFileList,
                          equals: filesItemEquals
                        ),
                        selectIfNotInSelectedListElseNoop: (it) => UI.selectIfNotInSelectedListElseNoop(
                          item: it,
                          selectedItems: selectedFileList,
                          equals: filesItemEquals
                        )
                      );
                    });
                  },
                ),
                title: Text(name),
                subtitle: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subtitle),

                    // 搜索模式，显示相对路径
                    if(itemParentDirRelativePathUnderCurrentPath.isNotEmpty)
                      Text(itemParentDirRelativePathUnderCurrentPath)
                  ],
                ),
                selected: selected,
                selectedTileColor: selectedBgColor,
                onTap: () async {
                  if(isSelectionModeOn && !isPasteModeOn()) { // 选择模式且不是拷贝或粘贴
                    setState(() {
                      UI.switchSelected(
                        item: fse,
                        selectedItems: selectedFileList,
                        equals: filesItemEquals
                      );
                    });
                  }else if(!isSelectionModeOn || selectedFileList.indexWhere((item) => item.absolute.path == fullPath) < 0) { // 非选择模式 或 未选中当前条目
                    if(isDir) {
                      await _loadFiles(FilePath.fromString(fullPath));
                    }else if(!isSelectionModeOn) {
                      // 选择模式或粘贴模式，默认点文件不会直接打开
                      // mime传null，让程序猜
                      await _openWithInternalEditor(fullPath, mime: null);
                    } // else 粘贴模式且点击的条目是文件，则不执行操作
                  }
                },
                onLongPress: () {
                  // paste mode，禁用长按选择，避免修改已选则条目列表
                  if(isPasteModeOn()) {
                    return;
                  }

                  setState(() {
                    UI.switchSelectSpan(
                      itemIdxOfItemList: idx,
                      item: fse,
                      selectedItems: selectedFileList,
                      itemList: displayList,
                      equals: filesItemEquals,
                      switchItemSelected: (it) => UI.switchSelected(
                          item: it,
                          selectedItems: selectedFileList,
                          equals: filesItemEquals
                      ),
                      selectIfNotInSelectedListElseNoop: (it) => UI.selectIfNotInSelectedListElseNoop(
                        item: it,
                        selectedItems: selectedFileList,
                        equals: filesItemEquals
                      )
                    );
                  });
                },
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'open_in_ext') {
                      _openFileInExternal(fse.absolute.path);
                    } else if (v == 'open_as_text') {
                      await _openWithInternalEditor(fullPath, mime: mimeTextPlain);
                    } else if (v == 'rename') {
                      _rename(fullPath);
                    } else if (v == 'delete') {
                      await _delete([fse]);
                    } else if (v == 'info') {
                      _showFileInfo(fullPath);
                    } else if (v == 'copy_path') {
                      copyTextThenShowMsg(fullPath);
                    } else if (v == 'copy_relative_path') {
                      _copyRepoRelativePath(fullPath);
                    } else if (v == 'history') {
                      goToFileHistoryPage(fullPath);
                    } else if (v == 'revealInFileExplorer') {
                      revealFile(fullPath, showMsgLong: showMsgLong);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'open_in_ext', child: Text(t.openInExt)),
                    if(fse is! Directory) PopupMenuItem(value: 'open_as_text', child: Text(t.openAsText)),
                    PopupMenuItem(value: 'revealInFileExplorer', child: Text(t.revealInFileExplorer)),
                    PopupMenuItem(value: 'rename', child: Text(t.rename)),
                    PopupMenuItem(value: 'delete', child: Text(t.delete)),
                    PopupMenuItem(value: 'info', child: Text(t.info)),
                    PopupMenuItem(value: 'copy_path', child: Text(t.copyPath)),
                    PopupMenuItem(value: 'copy_relative_path', child: Text(t.copyRelativePath)),
                    PopupMenuItem(value: 'history', child: Text(t.history)),
                  ],
                ),
              );
            },
          ),
        ),
      ),

      // 条件显示的底部操作栏
      if(isSelectionModeOn)
        BottomBar(
          selectedFileList: selectedFileList,
          showMsg: showMsg,
          showMsgLong: showMsgLong,
          // 显示unix styled str，这样想在md文件里引用资源时，方便直接打开资源目录，选中期望的文件，批量拷贝目录，若是平台指定的str，
          // 引用的资源不支持windows路径分割符，可能导致引用无效
          itemInfoTextGenerator: (it) => FilePath.genRelativePathSafe(currentPathStr, it.absolute.path, ifErrReturnEmpty: false).toUnixPathStr(),
          children: (!isPasteModeOn() ? [
            IconButton(
              icon: Icon(Icons.delete),
              tooltip: t.delete,
              onPressed: filesPageIsLoading || selectedFileList.isEmpty ? null : () async {
                // 拷贝一下，不然会在删除条目后从已选择列表移除对应条目时发生并发冲突
                await _delete(selectedFileList.toList());
              },
            ),
            IconButton(
              icon: Icon(Icons.cut),
              tooltip: t.move,
              onPressed: filesPageIsLoading || selectedFileList.isEmpty ? null : () async {
                _switchSelectionMode("move");
              },
            ),
            IconButton(
              icon: Icon(Icons.copy),
              tooltip: t.copy,
              onPressed: filesPageIsLoading || selectedFileList.isEmpty ? null : () async {
                _switchSelectionMode('copy');
              },
            ),
            IconButton(
              icon: Icon(Icons.select_all),
              tooltip: t.selectAll,
              onPressed: filesPageIsLoading ? null : () async {
                // 全选时不清列表，退出选择模式时清，用户体验更好，
                // 想象一下，过滤出.txt文件，全选，再过滤.md文件全选，若清了，
                // 点全选后，就只能选择.md，之前全选的.txt就丢了
                // selectedFileList.clear();

                // 避免重复添加
                for(final it in displayList) {
                  final foundIdx = selectedFileList.indexWhere((it2) => it2.path == it.path);
                  if(foundIdx < 0) {
                    selectedFileList.add(it);
                  }
                }

                refreshUI();
              },
            ),
            IconButton(
              icon: Icon(Icons.close),
              tooltip: t.quit,
              onPressed: filesPageIsLoading ? null : () {
                _quitSelectionModeForFiles();
              },
            ),
          ] : [
            IconButton(
              icon: Icon(Icons.paste),
              tooltip: t.paste,
              onPressed: filesPageIsLoading || selectedFileList.isEmpty ? null : () async {
                await _doPaste(ask_0_skip_1_overwrite_2_merge_3: 0);
              },
            ),
            // 用来指示是剪切还是复制
            IconButton(
              icon: Icon(isCopyMode() ? Icons.copy : Icons.cut),
              tooltip: isCopyMode() ? t.copy : t.move,
              onPressed: null,
            ),
            IconButton(
              icon: Icon(Icons.close),
              tooltip: t.quit,
              onPressed: filesPageIsLoading ? null : () {
                _quitSelectionModeForFiles(quitPasteMode: true);
              },
            ),
          ]),
        ),
    ];
  }





  List<Widget> onClickLogout(BuildContext context) {
    final children = <Widget>[];

    return children;
  }


  Future<void> loadHome() async {
    if(loadingHome) {
      return;
    }

    loadingHome = true;

    try {
      await doLoadHome();
    }catch(e, st) {
      App.logger.debug(_TAG, "load home err: $e\n$st");
      showMsgLong("load home err: $e");
    }finally {
      loadingHome = false;
    }
  }

  Future<void> doLoadHome() async {
    lastSyncedAt = "";
    filesPageSortMap = await Db.getSortMap();
    filesPageGlobeSort = await Db.getGlobalSort();

    final repoEntity = await Db.getOpenedRepo();
    openedRepo = repoEntity;
    setState(() {});

    if(repoEntity == null) { // home page (repo list)
      final repos = await Db.getRepos(sortByDate: true);
      setState(() {
        this.repos = repos;
        currentPage = Cons.homePageCodeHome;
      });

      _checkRepoStatus();
    }else {  // repo page
      final lastOpened = await Db.getLastOpenedPage();
      setState(() {
        currentPath = FilePath.fromString(repoEntity.path);
        currentPage = lastOpened;
        // 先清错误信息，后面打开若有错误会设置
        openRepoErrMsg = '';
      });

      try {
        final tempRepo = await Repo.open(repoEntity.path);
        final tempRepoConfig = await tempRepo.getConfig();
        final lastSyncInfo = await tempRepo.getLastSyncInfo();
        setState(() {
          if(lastSyncInfo.time.utcMs > 0) {
            lastSyncedAt = lastSyncInfo.lastSyncAtStr();
          }

          repo = tempRepo;
          repoConfig = tempRepoConfig;
          syncedFilesCount = lastSyncInfo.syncedFilesCount;
        });

        // if(tempRepoConfig.remoteConfig.type == RemoteType.dropbox.value) {
        //   final dropbox = tempRepo.remote as Dropbox;
        //   setState(() {
        //     // 这里显示的是授权时的用户名和头像，若用户后来改过也不会更新，不过没关系，会在执行同步时更新
        //     dropboxUsername = dropbox.config.username;
        //     dropboxAvatar = dropbox.config.avatar;
        //   });
        // }
      }catch(e, st) {
        App.logger.debug(_TAG, "open repo err: $e\n$st");
        setState(() {
          openRepoErrMsg = e.toString();
        });
      }

      // init files
      try {
        // 如果上次最后使用的是files页面，加载文件列表
        if(currentPage == Cons.homePageCodeFiles) {
          await _loadFiles(FilePath.fromString(await Db.getFilesLastPage() ?? repoEntity.path));
        }
      }catch(e) {
        App.logger.debug(_TAG, "init Files page err: $e");
      }
    }
  }

  Future<void> updateStateAndSaveLastOpened(int pageCode) async {
    setState(() {
      currentPage = pageCode;
    });

    await Db.setLastOpenedPage(pageCode);
  }

  List<Widget> drawerItems(BuildContext context) {
    final theme = Theme.of(context);
    final selectedBgColor = UI.getSelectedBgColor(theme);

    final List<Widget> items = [];

    final List<Widget> middle;

    Future<void> drawerOnClick(int pageCode) async {
      // 关闭 Drawer
      if(!isLandscapeLayout()) {
        Navigator.pop(context);
      }

      await updateStateAndSaveLastOpened(pageCode);
    }

    final openedRepo = this.openedRepo;

    if(openedRepo == null) {
      middle = [
        // 菜单项：点击后导航或关闭 Drawer
        ListTile(
          selected: currentPage == Cons.homePageCodeHome,
          leading: Icon(Icons.home),
          title: Text(t.home),
          selectedTileColor: selectedBgColor,
          onTap: () async {
            await drawerOnClick(Cons.homePageCodeHome);
          },
        ),
      ];
    }else {
      middle = [
        ListTile(
          selected: currentPage == Cons.homePageCodeRepo,
          leading: Icon(Icons.inventory),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.repo),
              Text(shortStr(openedRepo.name, 30, showEllipsis: true) ?? "", style: TextStyle(fontSize: 13, color: UI.getSecondaryColorOfFont()),),
            ]
          ),
          selectedTileColor: selectedBgColor,
          onTap: () async {
            await drawerOnClick(Cons.homePageCodeRepo);
          },
        ),
        ListTile(
          selected: currentPage == Cons.homePageCodeFiles,
          leading: Icon(Icons.folder),
          title: Text(t.files),
          selectedTileColor: selectedBgColor,
          onTap: () async {
            await drawerOnClick(Cons.homePageCodeFiles);
            // 非搜索模式，刷新页面，否则保持不变（不刷新搜索列表）
            if(filesPageSearchId.isEmpty) {
              await _loadFiles(currentPath);
            }
          },
        ),
        ListTile(
          selected: currentPage == Cons.homePageCodeRecentFiles,
          leading: Icon(Icons.list_alt),
          title: Text(t.recent),
          selectedTileColor: selectedBgColor,
          onTap: () async {
            await drawerOnClick(Cons.homePageCodeRecentFiles);
          },
        ),

        // 列出冲突消息，可查看和删除
        // TODO 这个页面需要支持分页，点击加载更多即可
        ListTile(
          selected: currentPage == Cons.homePageCodeConflict,
          leading: Icon(Icons.difference),
          title: Text(t.conflict),
          selectedTileColor: selectedBgColor,
          onTap: () async {
            await drawerOnClick(Cons.homePageCodeConflict);
          },
        ),
        ListTile(
          selected: currentPage == Cons.homePageCodeDeleted,
          leading: Icon(Icons.delete),
          title: Text(t.deleted),
          selectedTileColor: selectedBgColor,
          onTap: () async {
            await drawerOnClick(Cons.homePageCodeDeleted);
          },
        ),
      ];
    }

    items.addAll(middle);

    items.add(
      ListTile(
        selected: currentPage == Cons.homePageCodeSettings,
        leading: Icon(Icons.settings),
        title: Text(t.settings),
        selectedTileColor: selectedBgColor,
        onTap: () async {
          await drawerOnClick(Cons.homePageCodeSettings);
        },
      ),
    );

    items.add(
      ListTile(
        selected: currentPage == Cons.homePageCodeAbout,
        leading: Icon(Icons.info),
        title: Text(t.about),
        selectedTileColor: selectedBgColor,
        onTap: () async {
          await drawerOnClick(Cons.homePageCodeAbout);
        },
      )
    );

    // close repo button
    if(openedRepo != null) {
      items.add(const Divider());
      items.add(
        ListTile(
          selected: false,
          leading: Icon(Icons.close),
          title: Text(t.close),
          selectedTileColor: selectedBgColor,
          onTap: () async {
            await closeRepo();

            // close drawer if is not landscape layout
            if(!isLandscapeLayout()) {
              if(!context.mounted) return;
              Navigator.pop(context);
            }
          },
        )
      );
    }

    items.add(SizedBox(height: UI.verticalHeight,));

    return items;
  }

  void _switchSelectionMode(String mode) {
    if(currentPage != Cons.homePageCodeFiles) {
      return;
    }

    setState(() {
      pasteMode = mode;
    });
  }

  // 返回的布尔值代表是否执行了操作
  bool _toParentDir() {
    if(currentPage != Cons.homePageCodeFiles) {
      return false;
    }

    final curPathUnixStyleStr = currentPath.toUnixPathStr();

    final openedRepo = this.openedRepo;
    if(openedRepo != null) {
      // 等于仓库根目录，禁止再返回上级（可通过点面包屑绕过）
      if(curPathUnixStyleStr == openedRepo.path) {
        return false;
      }
    }

    if(Platform.isAndroid) {
      // 若是安卓，返回到 /storage/emulated/0 则退出
      if(curPathUnixStyleStr == Fs.getExtStoragePath()) {
        return false;
      }
    }

    // 无打开仓库退回到 root / 退出
    if(currentPath.canGoParent()) {
      _loadFiles(currentPath.parent());

      return true;
    }

    return false;
  }

  bool _backHandler() {
    // if drawer opened, handle it first
    if(!isLandscapeLayout() && Global.scaffoldKey.currentState?.isDrawerOpen == true) {
      softExitApp();
      return true;
    }

    if(currentPage == Cons.homePageCodeFiles) {
      if(_quitSelectionModeForFiles()) {
        return true;
      }

      if(_toParentDir()) {
        return true;
      }
    }else if(currentPage == Cons.homePageCodeRecentFiles) {
      if(recentFilesPageKey.currentState?.isSelectionModeOn == true) {
        recentFilesPageKey.currentState?.quitSelection();
        return true;
      }
    }else if(currentPage == Cons.homePageCodeConflict) {
      if(conflictPageKey.currentState?.isSelectionModeOn == true) {
        conflictPageKey.currentState?.quitSelection();
        return true;
      }
    }else if(currentPage == Cons.homePageCodeDeleted) {
      if(deletedPageKey.currentState?.isSelectionModeOn == true) {
        deletedPageKey.currentState?.quitSelection();
        return true;
      }
    }

    // 横屏布局下侧栏常驻展开，所以无需判断；否则判断，若侧栏已展开，退出，若侧栏未展开，展开侧栏
    if(!isLandscapeLayout()) {
      final scaffold = Global.scaffoldKey.currentState;
      if(scaffold != null) {
        if(scaffold.isDrawerOpen) {
          softExitApp();
          return true;
        }else {
          scaffold.openDrawer();
          return true;
        }
      }
    }

    return false;
  }

  // 按返回键不退出粘贴模式而是返回上级目录，只有按下底栏关闭按钮时才退出粘贴模式
  bool _quitSelectionModeForFiles({bool quitPasteMode = false}) {
    if(currentPage != Cons.homePageCodeFiles) {
      return false;
    }


    // 普通选择模式下，清列表，退出选择模式；
    // 拷贝或粘贴模式下不清列表，从拷贝或粘贴模式返回选择模式
    if(!isPasteModeOn()) {
      // 非拷贝粘贴模式，接下来判断是否是选择模式
      if(selectedFileList.isNotEmpty) {
        // 是选择模式，退出
        setState(() {
          selectedFileList = [];
        });

        return true;
      }
    }else if(quitPasteMode) {
      // 退出粘贴模式
      setState(() {
        pasteMode = '';
      });

      return true;
    }

    return false;
  }

  bool isPasteModeOn() {
    return pasteMode.isNotEmpty;
  }

  bool isCopyMode() {
    return pasteMode == 'copy';
  }

  Future<void> _doPaste({required int ask_0_skip_1_overwrite_2_merge_3}) async {
    if(filesPageIsLoading) {
      showMsgLong("paste err: another task running");
      return;
    }

    filesPageIsLoading = true;
    setState(() {});

    try {
      if(!isPasteModeOn()) {
        return;
      }

      final List<FileSystemEntity> list;
      if(ask_0_skip_1_overwrite_2_merge_3 == 0) {
        // 若是ask，清空此变量等待接收已存在条目
        targetExistsListWhenPaste = [];

        list = selectedFileList.toList();
      } else {
        list = targetExistsListWhenPaste.toList();
      }

      if(list.isEmpty) {
        showMsgLong("no items selected");
        return;
      }


      // 若是1，就代表跳过，就不用执行了，若不是1，则执行
      if(ask_0_skip_1_overwrite_2_merge_3 != 1) {
        final targetPath = currentPath.copy();
        final targetPathStr = targetPath.toString();
        final isCopy = isCopyMode();

        for(final i in list) {
          final path = i.absolute.path;
          await Fs.copyOrMovePath(
            path,
            targetPathStr,
            isCopy: isCopy,
            existsTargetFileHandler: (srcPath, targetPath) async {
              if(ask_0_skip_1_overwrite_2_merge_3 == 0) {
                // 先存上，问用户，再处理
                targetExistsListWhenPaste.add(i);
                return true;
              }else if(ask_0_skip_1_overwrite_2_merge_3 == 1) {
                // 这个似乎不会执行到，问完用户，若选跳过，直接清列表，就不用执行到这了
                return true;
              }else if(ask_0_skip_1_overwrite_2_merge_3 == 2) {
                // 覆盖，先把目标删除，再粘贴，这个有点危险，一般要么合并目录，覆盖文件，要么跳过，很少会有把目录整个删除再覆盖的
                // 用Directory无论文件还是目录皆可删除
                await Directory(targetPath).delete(recursive: true);
                // return false，让函数继续处理
                return false;
              }else { // == 3, merge
                // return false, 会覆盖已存在文件，若目录存在，会用源目录文件覆盖目标目录中已存在文件，和windows的文件夹合并策略一致
                return false;
              }
            }
          );
        }
      }


      // 非0说明用户作出了选择，并且执行完了操作，可清了
      if(ask_0_skip_1_overwrite_2_merge_3 != 0) {
        targetExistsListWhenPaste = [];
      }

      if(targetExistsListWhenPaste.isEmpty) {
        // 退出选择模式
        setState(() {
          pasteMode = '';
        });

        _quitSelectionModeForFiles();

        // 若非搜索模式，重载列表
        if(filesPageSearchId.isEmpty) {
          await _loadFiles(currentPath);
        }
      }
    }catch(e, st) {
      App.logger.debug(_TAG, "$pasteMode files err: $e\n$st");
      showMsgLong("$pasteMode err: $e");
    }finally {
      filesPageIsLoading = false;
      setState(() {});
    }

    final context = this.context;
    if(!context.mounted) return;

    if(ask_0_skip_1_overwrite_2_merge_3 == 0 && targetExistsListWhenPaste.isNotEmpty) {
      await Dialogs.showOkOrNoDialog(
        context,
        title: t.conflict,
        text: t.askMergeDirsAndFiles,
        onOk: () {
          _doPaste(ask_0_skip_1_overwrite_2_merge_3: 3);
        },
        onCancel: () {
          _doPaste(ask_0_skip_1_overwrite_2_merge_3: 1);
        }
      );
    }
  }

  String getPageTitle() {
    if(currentPage == Cons.homePageCodeFiles) {
      return currentPath.name();
    }else if(currentPage == Cons.homePageCodeConflict) {
      return t.conflict;
    }else if(currentPage == Cons.homePageCodeDeleted) {
      return t.deleted;
    }else if(currentPage == Cons.homePageCodeAbout) {
      return t.about;
    }else if(currentPage == Cons.homePageCodeSettings) {
      return t.settings;
    }else if(currentPage == Cons.homePageCodeRecentFiles) {
      return t.recent;
    }else {
      final openedRepo = this.openedRepo;
      if(openedRepo == null) {
        return t.home;
      }

      return openedRepo.name;
    }
  }

  Widget? _getDrawerHeader() {
    if(!App.accountSystemEnabled) {
      return null;
    }

    final currentThemeMode = UI.themeNotifier.value.themeMode;

    // final theme = Theme.of(context);

    // final buttonBgColor = UI.isDarkTheme() ? theme.colorScheme.inversePrimary : theme.colorScheme.primaryFixedDim;
    // final buttonTextColor = UI.isDarkTheme() ? Colors.white70 : Colors.black87;

    // final textButtonStyle = TextButton.styleFrom(
    //   minimumSize: Size(50, 30),
    //   backgroundColor: buttonBgColor, // 背景色
    //   foregroundColor: buttonTextColor, // 文本和图标颜色
    //   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    // );

    // final clickableTextStyle = TextStyle(
    //   color: UI.isDarkTheme() ? Colors.blue : Color(0xFF5BD9EA),
    //   fontSize: 14,
    // );

    // Widget userInfoLine(String text) {
    //   return SelectableText(text, style: TextStyle(color: Colors.white));
    // }

    return Stack(
      children: [
        // if(isLoggedIn())
        //   UserAccountsDrawerHeader(
        //     decoration: BoxDecoration(
        //       color: UI.getColorOfContainer(theme)
        //     ),
        //     accountName: Text(user.name),
        //     accountEmail: Text(user.email),
        //     currentAccountPicture: CircleAvatar(child: Text(user.name.isEmpty ? "" : user.name[0])),
        //   ),

        // 右上角的主题切换按钮
        Positioned(
          top: 3,
          right: 3,
          child: PopupMenuButton<ThemeMode>(
            // 根据当前状态显示图标
            icon: Icon(
              UI.getThemeIcon(),
              color: Colors.white,
            ),
            onSelected: (ThemeMode mode) {
              UI.setThemeMode(mode);
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                value: ThemeMode.system,
                child: ListTile(
                  selected: currentThemeMode == ThemeMode.system,
                  leading: Icon(Icons.brightness_auto),
                  title: Text(t.auto),
                ),
              ),
              PopupMenuItem(
                value: ThemeMode.light,
                child: ListTile(
                  selected: currentThemeMode == ThemeMode.light,
                  leading: Icon(Icons.light_mode),
                  title: Text(t.light),
                ),
              ),
              PopupMenuItem(
                value: ThemeMode.dark,
                child: ListTile(
                  selected: currentThemeMode == ThemeMode.dark,
                  leading: Icon(Icons.dark_mode),
                  title: Text(t.dark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _getDrawerFooter() {
    // 没有打开的仓库(用openedRepo == null来判断)，或者打开仓库出错，则不显示同步按钮
    if(openedRepo == null || openRepoErr()) {
      return SizedBox(width: 1,);
    }

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: UI.isDarkTheme() ? Colors.black26 : Colors.white, // 背景色（可选）
          border: Border(
            top: BorderSide(
              color: Colors.grey, // 边框颜色
              width: 1.0,         // 边框宽度
            ),
          ),
        ),
        child: Column(
          children: _getSyncButton(fromDrawer: true)
        )
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // drawer
    final drawer = DrawerTheme(
      data: const DrawerThemeData(
        // 在这里把圆角彻底砍掉（变为直角）
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
      ),
      child: NavigationDrawer(
        header: _getDrawerHeader(),
        footer: _getDrawerFooter(),
        children: drawerItems(context),
      ),
    );

    // 子页面
    List<Widget> children = [];
    List<Widget> actions = [];
    // 若没打开任何仓库，则显示home页面
    // 否则恢复上次打开的页面
    if(openedRepo == null) {
      children = getPageHome(context);
      actions = [
        IconButton(
          icon: Icon(Icons.refresh),
          tooltip: t.refresh,
          onPressed: () async {
            await loadHome();
          },
        ),
      ];
    }else if(currentPage == Cons.homePageCodeHome) {
      children = getPageHome(context);
    }else if(currentPage == Cons.homePageCodeRepo) {
      children = getPageRepo(context);
      actions = [
        IconButton(
          icon: Icon(Icons.refresh),
          tooltip: t.refresh,
          onPressed: () async {
            await loadHome();
          },
        ),
      ];
    }else if(currentPage == Cons.homePageCodeFiles) {
      children = getPageFiles(context);
      actions = getActionsFiles();
    }else if(currentPage == Cons.homePageCodeConflict) {
      actions = [
        IconButton(
          icon: Icon(Icons.refresh),
          tooltip: t.refresh,
          onPressed: () {
            conflictPageKey.currentState?.loadItems();
          },
        ),
        IconButton(
          icon: Icon(Icons.checklist),
          tooltip: t.selectionMode,
          onPressed: () {
            conflictPageKey.currentState?.letSelectModeOn();
          },
        )
      ];
    }else if(currentPage == Cons.homePageCodeDeleted) {
      actions = [
        IconButton(
          icon: Icon(Icons.refresh),
          tooltip: t.refresh,
          onPressed: () {
            deletedPageKey.currentState?.loadItems();
          },
        ),
        IconButton(
          icon: Icon(Icons.checklist),
          tooltip: t.selectionMode,
          onPressed: () {
            deletedPageKey.currentState?.letSelectModeOn();
          },
        )
      ];
    }else if(currentPage == Cons.homePageCodeRecentFiles) {
      actions = [
        IconButton(
          icon: Icon(Icons.refresh),
          tooltip: t.refresh,
          onPressed: () {
            recentFilesPageKey.currentState?.loadItems();
          },
        ),
        IconButton(
          icon: Icon(Icons.checklist),
          tooltip: t.selectionMode,
          onPressed: () {
            recentFilesPageKey.currentState?.letSelectModeOn();
          },
        )
      ];
    }


    final title = getPageTitle();
    final Widget child;

    if(currentPage == Cons.homePageCodeRecentFiles) {
      child = BaseLayout.newScaffold(
        context,
        title: title,
        drawer: drawer,
        actions: actions,
        key: Global.scaffoldKey,
        body: RecentFiles(
          key: recentFilesPageKey,
          showScaffold: false,
          showMsg: showMsg,
          showMsgLong: showMsgLong,

          // 从最近文件列表打开的文件一律当文本文件打开，mime传text/plain
          // openWithInternalEditor: (path) => _openWithInternalEditor(path, mime: mimeTextPlain),

          // 让程序猜打开方式，有时候点的文件并不是文本文件，也会出现在最近文件列表，这时候用文本方式打开并不合适
          openWithInternalEditor: (path) => _openWithInternalEditor(path, mime: null),

          openInExt: _openFileInExternal,
          goToFilesAndRevealItem: (item) {
            final fp = FilePath.fromString(item.fullPath);
            _loadFiles(fp.parent(), name: fp.name());
          },
        )
      );
    }else if(currentPage == Cons.homePageCodeConflict) {
      child = BaseLayout.newScaffold(
        context,
        title: title,
        drawer: drawer,
        actions: actions,
        key: Global.scaffoldKey,
        body: ConflictListPage(
          key: conflictPageKey, 
          showScaffold: false, 
          showMsg: showMsg,
          showMsgLong: showMsgLong, 
          showInFiles: (relativePath) {
            final openedRepo = this.openedRepo;
            if(openedRepo == null) {
              showMsgLong("no repo opened");
              return;
            }

            _loadFiles(FilePath.fromString(p.join(openedRepo.path, relativePath)).parent(), name: p.basename(relativePath));
          },
          doSync: _doSync,
        )
      );
    }else if(currentPage == Cons.homePageCodeDeleted) {
      child = BaseLayout.newScaffold(
        context,
        title: title,
        drawer: drawer,
        actions: actions,
        key: Global.scaffoldKey,
        body: DeletedPage(key: deletedPageKey, showScaffold: false, showMsg: showMsg, showMsgLong: showMsgLong, doSync: _doSync,)
      );
    }else if(currentPage == Cons.homePageCodeSettings) {
      child = BaseLayout.newScaffold(
        context,
        title: title,
        drawer: drawer,
        actions: actions,
        key: Global.scaffoldKey,
        body: SettingsPage(key: settingsPageKey, showScaffold: false, showMsg: showMsg, showMsgLong: showMsgLong, copyTextThenShowMsg: copyTextThenShowMsg,)
      );
    }else if(currentPage == Cons.homePageCodeAbout) {
      child = BaseLayout.newScaffold(
        context,
        title: title,
        drawer: drawer,
        actions: actions,
        key: Global.scaffoldKey,
        body: AboutPage(
          appName: t.appName,
          appDesc: t.appDesc,
          appIconAsset: appIconPath,
          authorEmail: authorEmail,
          projectUrl: projectUrl,
          privacyPolicyUrl: privacyPolicyUrl,
          authorUrl: authorUrl,
          reportBugUrl: reportBugUrl,
          updateUrl: updateUrl,
          showMsg: showMsg,
        )
      );
    }else {
      child = BaseLayout.newScaffoldWithColumn(
        context,
        title: title,
        drawer: drawer,
        actions: actions,
        key: Global.scaffoldKey,
        children: children,
        // 文件管理器页面自带padding，不需使用默认页面padding
        padding: currentPage == Cons.homePageCodeFiles ? EdgeInsets.all(0) : null,
      );
    }

    return BaseLayout.backWrapper(
      context,
      onBack: () async {
        return _backHandler();
      },
      child: child
    );

    //
    // return BaseLayout.newScaffoldWithColumn(
    //   context,
    //   openedRepo?.name ?? '',
    //   children,
    //   drawer: drawer
    // );
  }

}

