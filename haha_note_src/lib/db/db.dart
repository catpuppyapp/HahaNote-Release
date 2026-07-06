import 'dart:convert';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/repo.dart';
import 'package:hahanote_app/hahanote_lib_sync/time/time_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';
import 'package:hahanote_app/config/app_config.dart';
import 'package:hahanote_app/constants/cons.dart' show Cons;
import 'package:hahanote_app/db/entity/repo_entity.dart';
import 'package:hahanote_app/ui/ui.dart' show UI;
import 'package:hahanote_app/util/fs.dart' show Fs;
import 'package:hahanote_app/widget/sort_dialog.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/adapters.dart';

import '../ui/app_theme.dart';

const _TAG = "db.dart";

// box名字
// 文件名会强制转成全小写，所以不要用驼峰，用 my_box 这种格式
const _boxApp = "app";
// other boxes if have
// const _boxOther = "other";

abstract class Db {
  static final _keyRepos = 'repos';
  // 最后打开的仓库的路径，注意是路径，不是id，因为路径既能当id用，又是一个有效信息，可用来打开仓库，而id只能用来找仓库
  static final _keyOpenedRepo = 'opened_repo';
  static final _keyLastHomePage = 'last_home_page';
  static final _keyThemeMode = 'theme_mode';
  static final _keyColorScheme = 'color_scheme';
  static final _keyFilesPageLastPath = 'files_page_last_path';
  // 全局排序模式
  static final _keyFilesPageGlobalSort = 'files_page_global_sort';
  // 指定目录排序模式
  // Map，key是unix style路径，value是sort对象
  static final _keyFilesPageSortMap = 'files_page_sort_map';
  static final _keyEditorFontSize = 'editor_font_size';
  static final _keyMarkdownPreviewerFontSize = 'markdown_previewer_font_size';
  static final _keyDiffViewFontSize = 'diff_view_font_size';
  static final _keyLoginedUserInfo = 'logined_user_info';
  static final _keyAppConfig = 'app_config';
  static final _keyAppVer = 'app_ver';

  static final List<String> _boxes = [_boxApp];


  static bool inited = false;

  static Future<void> init({bool reset = false}) async {
    if(inited) {
      return;
    }

    inited = true;

    // 存放路径，传的参数是在对应目录下的子目录，
    // 例如目录为 app/files，传个db，则db文件存储在 app/files/db目录下
    Hive.init(await Fs.getDbDirPath());

    if(reset) {
      for(final box in _boxes) {
        // 不存在的box不会报错
        await Hive.deleteBoxFromDisk(box);
      }
    }
  }

  static Future<Box> _getBox({String name = _boxApp}) async {
    // 相当于打开app db，是db，不是table
    return Hive.openBox(name);
  }

  /// [sortByDate] if true, sort by last update time desc
  static Future<List<RepoEntity>> getRepos({bool sortByDate = false}) async {
    final box = await _getBox();
    final String? jsonStr = box.get(_keyRepos);
    final repos = <RepoEntity>[];

    if(jsonStr == null) {
      return repos;
    }

    final List<dynamic> reposMap = jsonDecode(jsonStr);
    for(final r in reposMap) {
      repos.add(RepoEntity.fromJson(r));
    }

    if(repos.isEmpty) {
      return repos;
    }

    // sortByDate
    if(sortByDate) {
      repos.sort((a, b) {
        return b.lastUpdate.utcMs - a.lastUpdate.utcMs;
      });
    }

    return repos;
  }

  static Future<void> updateRepos(List<RepoEntity> repos) async {
    final box = await _getBox();
    await box.put(_keyRepos, jsonEncode(repos));
  }

  static String _genId() => randomString(32);


  static Future<RepoEntity?> getRepo(String repoId, {List<RepoEntity>? provideRepos}) async {
    final repos = provideRepos ?? await getRepos();
    for(final r in repos) {
      if(r.id == repoId) {
        return r;
      }
    }

    return null;
  }


  static Future<RepoEntity?> getRepoByPath(String path, {List<RepoEntity>? provideRepos}) async {
    final repos = provideRepos ?? await getRepos();
    for(final r in repos) {
      if(r.path == path) {
        return r;
      }
    }

    return null;
  }

  static Future<RepoEntity?> getOpenedRepo() async {
    final box = await _getBox();
    final String? repoPath = box.get(_keyOpenedRepo);
    if(repoPath == null || repoPath.isEmpty) {
      return null;
    }

    return getRepoByPath(repoPath);
  }

  static Future<void> setOpenedRepo(String path,{bool setLastOpenedPageToRepo = true}) async {
    final box = await _getBox();
    // 存的时候一律unix style
    await box.put(_keyOpenedRepo, FilePath.fromString(path).toUnixPathStr());
    await touchRepoByPath(path);

    if(setLastOpenedPageToRepo) {
      // 设置完仓库后，把初始启动页设为仓库页面 (fix 打开仓库后没显示仓库页面，而是停留在新建仓库和仓库列表页面）
      await setLastOpenedPage(Cons.homePageCodeRepo);
    }
  }

  static Future<void> touchRepoByPath(String path) async {
    final repo = await getRepoByPath(path);
    if(repo != null) {
      await updateRepo(repo);
    }
  }

  static Future<void> delOpenedRepo() async {
    final box = await _getBox();
    await box.delete(_keyOpenedRepo);
  }


  /// [touch] if ture, update repo last used time
  static Future<RepoEntity?> getIfOpenedRepoGood({
    bool touch = true,
    Future<void> Function(RepoEntity, String err)? openRepoFailedHandler
  }) async {
    final repoEntity = await getOpenedRepo();
    if(repoEntity == null) {
      return null;
    }

    // 更新仓库最后使用时间
    if(touch) {
      await updateRepo(repoEntity);
    }

    try {
      final repo = await Repo.open(repoEntity.path);
      repo.path;
      return repoEntity;
    }catch(e) {
      App.logger.debug(_TAG, "open repo failed: repo path=${repoEntity.path}, err=$e");

      await openRepoFailedHandler?.call(repoEntity, e.toString());
      // 解除无法打开的仓库，下次就直接查出null，省得try open了
      // 好像没必要清？
      // final box = await _getBox();
      // await box.delete(_keyOpenedRepo);

      return null;
    }
  }

  static Future<void> saveRepo(
    RepoEntity repo, {
    List<RepoEntity>? provideRepos,
    bool throwIfPathAlreadyExists = true
  }) async {
    final repos = provideRepos ?? await getRepos();
    if(repo.id.isEmpty) {
      repo.id = _genId();
    }

    // 应该永远不会发生，除非重复添加从db读取出来的仓库还没更新id
    if((await getRepo(repo.id, provideRepos: repos)) != null) {
      throw AppException("repo id already exists: ${repo.id}, err code: 15413989");
    }

    // x 废弃）存储前先把路径规范化一下，会在路径分隔符转换成当前系统的格式，且移除末尾分隔符
    // x 例如：C:/abc\abc，和C:\abc\abc/，都会转换成  C:\abc\abc，
    // 但是不能百分百防止重复路径被存入数据库：因为盘符和路径的大小写会保持不变，例如 c:/aBc\abc，转换后会变成c:\aBc\abc
    // 存储的文字路径，强制转换为unix字符串，统一格式，使用时若有必要，可再用FilePath.fromString转回来，不过实际上windows也支持/分隔的路径，因此一般不用特殊处理
    repo.path = FilePath.fromString(repo.path).toUnixPathStr();

    if(repo.path.isEmpty) {
      throw AppException("repo path is empty, err code: 17826616");
    }

    final existedRepo = await getRepoByPath(repo.path, provideRepos: repos);
    if(existedRepo != null) {
      if(throwIfPathAlreadyExists) {
        throw AppException("repo path already exists: ${repo.path}, err code: 15440814");
      }

      // 若不抛异常，就更新已经存在的仓库的最后更新时间
      existedRepo.lastUpdate = TimeData.now();
    }else {
      // 不存在相同路径的仓库，添加
      repos.add(repo);
    }

    await updateRepos(repos);
  }

  static Future<void> updateRepo(RepoEntity repo, {List<RepoEntity>? provideRepos}) async {
    final repos = provideRepos ?? await getRepos();
    if(await getRepo(repo.id, provideRepos: repos) == null) {
      throw AppException("repo doesn't exist: ${repo.id}, err code: 18682451");
    }

    // 必须根据路径删除，若根据id删除，假设两个仓库路径相同，id不同，更新后会仓库会重复
    await delRepoByPath(repo, provideRepos: repos, save: false);
    repo.lastUpdate = TimeData.now();
    repos.add(repo);

    await updateRepos(repos);
  }

  static Future<void> saveOrUpdateRepo(RepoEntity repo) async {
    if(repo.id.isEmpty) {
      await saveRepo(repo);
    }else {
      await updateRepo(repo);
    }
  }

  static Future<void> delRepoById(RepoEntity repo, {List<RepoEntity>? provideRepos, bool save = true}) async {
    await delRepoByPredication(
      provideRepos: provideRepos,
      save: save,
      predicate: (r) => r.id == repo.id
    );
  }

  static Future<void> delRepoByPredication({
    List<RepoEntity>? provideRepos,
    bool save = true,
    required bool Function(RepoEntity) predicate
  }) async {
    final repos = provideRepos ?? await getRepos();
    try {
      repos.removeWhere((r) => predicate(r));
      if(save) {
        await updateRepos(repos);
      }
    }catch(e) {
      App.logger.debug(_TAG, "delRepoByPredication err: $e");
    }
  }

  static Future<void> delRepoByPath(RepoEntity repo, {List<RepoEntity>? provideRepos, bool save = true}) async {
    await delRepoByPredication(
      provideRepos: provideRepos,
      save: save,
      predicate: (r) => r.path == repo.path
    );
  }

  static Future<void> setLastOpenedPage(int? pageCode) async {
    final box = await _getBox();
    if(pageCode == null) {
      await box.delete(_keyLastHomePage);
    }else {
      await box.put(_keyLastHomePage, pageCode);
    }
  }

  static Future<int> getLastOpenedPage() async {
    final box = await _getBox();
    return box.get(_keyLastHomePage) ?? Cons.homePageCodeRepo;
  }

  static String _themeModeToStr(ThemeMode themeMode) {
    if(themeMode == ThemeMode.dark) {
      return "dark";
    }else if(themeMode == ThemeMode.light) {
      return "light";
    }else {
      return "system";
    }
  }

  static ThemeMode? _themeModeFromStr(String? themeModeStr) {
    if(themeModeStr == null) {
      return null;
    }

    if(themeModeStr == "dark") {
      return ThemeMode.dark;
    }else if(themeModeStr == "light") {
      return ThemeMode.light;
    }else {
      return ThemeMode.system;
    }
  }

  static FlexScheme? _colorSchemeFromStr(String? str) {
    if(str == null || str.isEmpty) {
      return null;
    }

    for(final i in FlexScheme.values) {
      if(i.name == str) {
        return i;
      }
    }

    return null;
  }

  static Future<ThemeMode> getThemeMode({ThemeMode defaultValue = AppTheme.defaultThemeMode}) async {
    final box = await _getBox();
    return _themeModeFromStr(box.get(_keyThemeMode)) ?? defaultValue;
  }

  static Future<void> setThemeMode(ThemeMode themeMode) async {
    final box = await _getBox();
    await box.put(_keyThemeMode, _themeModeToStr(themeMode));
  }

  static Future<FlexScheme> getColorScheme({FlexScheme defaultValue = AppTheme.defaultColorScheme}) async {
    final box = await _getBox();
    return _colorSchemeFromStr(box.get(_keyColorScheme)) ?? defaultValue;
  }

  static Future<void> setColorScheme(FlexScheme value) async {
    final box = await _getBox();
    await box.put(_keyColorScheme, value.name);
  }

  static Future<void> saveRepoThenSetOpened(
    RepoEntity repo, {
    List<RepoEntity>? provideRepos,
    bool throwIfPathAlreadyExists = false
  }) async {
    final repos = provideRepos ?? await getRepos();

    // 先后顺序不能变，因为 saveRepo时会修改id和规范化path
    await saveRepo(
      repo,
      provideRepos: repos,
      throwIfPathAlreadyExists: throwIfPathAlreadyExists
    );

    await setOpenedRepo(repo.path);
  }

  static Future<void> setFilesLastPath(String? path) async {
    final box = await _getBox();
    if(path == null) {
      await box.delete(_keyFilesPageLastPath);
    }else {
      await box.put(_keyFilesPageLastPath, path);
    }
  }

  static Future<String?> getFilesLastPage() async {
    final box = await _getBox();
    return box.get(_keyFilesPageLastPath);
  }

  static Future<SortRule> getGlobalSort() async {
    final box = await _getBox();
    final jsonStr = box.get(_keyFilesPageGlobalSort);
    if(jsonStr == null) {
      return SortRule.defaultValue;
    }

    return SortRule.fromJson(jsonDecode(jsonStr));
  }

  static Future<void> setGlobalSort(SortRule value) async {
    final box = await _getBox();
    await box.put(_keyFilesPageGlobalSort, jsonEncode(value));
  }

  // 返回 map：key=path，value=sort对象的json 字符串
  static Future<Map<String, SortRule>> getSortMap() async {
    try {
      final box = await _getBox();
      final jsonStr = box.get(_keyFilesPageSortMap);

      if(jsonStr == null) {
        return {};
      }

      final result = <String, SortRule>{};
      for(final entry in (jsonDecode(jsonStr) as Map<String, dynamic>).entries) {
        result[entry.key] = SortRule.fromJson(entry.value);
      }

      return result;
    }catch(e, st) {
      App.logger.debug(_TAG, "getSortMap err: $e\n$st");
      return {};
    }
  }

  static Future<SortRule> getSortByPath(String path) async {
    final map = await getSortMap();
    final resultByPath = map[path];
    if(resultByPath != null) {
      return resultByPath;
    }

    return await getGlobalSort();
  }

  static Future<void> setSortByPath(String path, final SortRule? value) async {
    final box = await _getBox();
    final map = await getSortMap();
    // 等于 null，则从map删除；否则添加到map
    if(value == null) {
      if(map.remove(path) != null) {
        // 删除成功则保存
        await box.put(_keyFilesPageSortMap, jsonEncode(map));
      }
    }else {
      map[path] = value;
      await box.put(_keyFilesPageSortMap, jsonEncode(map));
    }
  }

  static Future<void> saveEditorFontSize(double fontSize) async {
    final box = await _getBox();
    await box.put(_keyEditorFontSize, fontSize);
  }

  static Future<double> getEditorFontSize() async {
    final box = await _getBox();
    return await box.get(_keyEditorFontSize) ?? UI.editorFontSizeDefault;
  }


  static Future<void> saveMarkdownPreviewerFontSize(double fontSize) async {
    final box = await _getBox();
    await box.put(_keyMarkdownPreviewerFontSize, fontSize);
  }

  static Future<double> getMarkdownPreviewerFontSize() async {
    final box = await _getBox();
    return await box.get(_keyMarkdownPreviewerFontSize) ?? UI.markdownPreviewerFontSizeDefault;
  }

  static Future<void> saveDiffViewFontSize(double fontSize) async {
    final box = await _getBox();
    await box.put(_keyDiffViewFontSize, fontSize);
  }

  static Future<double> getDiffViewFontSize() async {
    final box = await _getBox();
    return await box.get(_keyDiffViewFontSize) ?? UI.diffViewFontSizeDefault;
  }




  static Future<AppConfig> getAppConfig() async {
    final box = await _getBox();
    try {
      final jsonMap = jsonDecode(await box.get(_keyAppConfig));
      return AppConfig.fromJson(jsonMap);
    }catch(e) {
      App.logger.debug(_TAG, "read config failed, will return new config, err: $e");
      // 这里不保存以免又失败，等用户什么时候修改了配置，再重新保存
      return AppConfig();
    }
  }

  static Future<void> setAppConfig(AppConfig config) async {
    final box = await _getBox();
    try {
      final jsonStr = jsonEncode(config);
      await box.put(_keyAppConfig, jsonStr);
    }catch(e) {
      App.logger.debug(_TAG, "save config failed, err: $e");
      rethrow;
    }
  }


  static Future<void> saveFileLastEditPos(final FilePath filePath, final TextSelection? pos) async {
    final openedRepo = await Db.getOpenedRepo();
    if(openedRepo == null) {
      return;
    }
    // 更新最后打开文件到仓库entity的列表，并且记住最后滚动位置
    // keepLastPos: pos == null 的作用：如果当前传入的pos为null，则尝试保持上次的位置信息
    openedRepo.addPathToRecentFiles(FilePos.fromCodeLineSelection(filePath.toUnixPathStr(), pos), keepLastPos: pos == null);
    await Db.updateRepo(openedRepo);
  }

  static Future<String> getAppVer() async {
    final box = await _getBox();
    return box.get(_keyAppVer) ?? "";
  }

  static Future<void> setAppVer(String value) async {
    final box = await _getBox();
    box.put(_keyAppVer, value);
  }

}
