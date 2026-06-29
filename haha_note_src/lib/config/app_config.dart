
import 'dart:convert';

import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/sync_config.dart';
import 'package:cloud_disk_note_app/db/db.dart';
import 'package:cloud_disk_note_app/ext/iterable_ext.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart';
import 'package:cloud_disk_note_app/native_util/open_file.dart';

import 'display_mode.dart';

part 'app_config.g.dart';

const _TAG = "app_config.dart";


AppConfig? _config = null;
bool _inited = false;

const languageAuto = "Auto";

@myJsonSerializable
class AppConfig {
  SyncConfig syncConfig;

  String textEditorPackageNameOnAndroid;
  String textEditorPackageNameOnPc;

  String language;

  bool showLineNumInDiffView;

  // 判断是否是初次使用
  bool isFirstUse;
  bool neverShowLineNumIncorrectNoteInDiffView;
  bool neverShowBlankLinesMayBeIgnoredInDiffView;

  bool showRepoDataDirInFiles;

  // pc端使用此变量决定打开editor时是否默认打开预览面板
  bool editorPreviewEnabled;
  bool editorSoftWrapEnabled;
  bool editorLineNumEnabled;
  double windowWidth;
  double windowHeight;
  int displayMode;

  AppConfig({
    SyncConfig? syncConfig,
    this.textEditorPackageNameOnAndroid = "",  //默认值空，之前是自动在支持的编辑器里逐个尝试，后来使用code_forge后，空代表hhnote内置编辑器
    this.textEditorPackageNameOnPc = "",
    this.language = "",  // 空，auto，自动检测设备语言
    this.showLineNumInDiffView = false,
    this.isFirstUse = true,
    this.neverShowLineNumIncorrectNoteInDiffView = true,
    this.neverShowBlankLinesMayBeIgnoredInDiffView = true,
    this.showRepoDataDirInFiles = false,
    this.editorPreviewEnabled = false,
    this.editorSoftWrapEnabled = false,  // large file may take performance issue if enabled
    this.editorLineNumEnabled = false,
    this.windowWidth = 1280,
    this.windowHeight = 720,
    this.displayMode = DisplayMode.auto,
  }) : syncConfig = syncConfig ?? SyncConfig();


  factory AppConfig.fromJson(Map<String, dynamic> json) => _$AppConfigFromJson(json);

  Map<String, dynamic> toJson() => _$AppConfigToJson(this);

  static Future<void> init() async {
    if(_inited) {
      return;
    }

    _inited = true;

    await setConfig(await Db.getAppConfig(), save: false);
  }

  // 这个只读，不要改，若改，使用update
  static AppConfig getConfig() {
    return _config!;
  }

  static Future<void> setConfig(AppConfig config, {required bool save}) async {
    // 设置底层同步库
    await SyncConfig.setConfig(config.syncConfig, save: save);

    // 设置当前库
    _config = config;
    if(save) {
      await Db.setAppConfig(config);
    }
  }

  /// 使用方法：
  /// await update((config) {
  ///   config.abc = 123;
  /// });
  /// // when await returned, settings will be updated
  static Future<void> update(Future<void> Function(AppConfig) handler) async {
    final copied = _config?.copy();
    if(copied == null) {
      App.logger.debug(_TAG, "update settings failed, config is null");
      throw AppException("config is null");
    }

    await handler(copied);

    // 更新实例
    await setConfig(copied, save: true);
  }

  AppConfig copy() {
    return AppConfig.fromJson(jsonDecode(jsonEncode(this)));
  }

  String getTextOfTextEditorPackageNameOnAndroid() {
    return _getNameOfEditor(NativeOpenFile.supportedAndroidEditors, textEditorPackageNameOnAndroid);
  }

  String getTextOfTextEditorPackageNameOnPc() {
    return _getNameOfEditor(NativeOpenFile.supportedPcEditors, textEditorPackageNameOnPc);
  }

  String _getNameOfEditor(List<AppInfoAndLink> editors, String target) {
    final found = editors.firstWhereOrNull((it) => it.packageName == target);
    if(found != null) {
      return found.name;
    }

    return t.builtIn;
  }

  String getCurLanguageText() {
    return language.isEmpty ? languageAuto : language;
  }

  String getCurDisplayModeText() {
    return DisplayMode.toText(displayMode);
  }
}
