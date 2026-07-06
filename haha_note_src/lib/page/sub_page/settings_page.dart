import 'dart:io';

import 'package:hahanote_app/hahanote_lib_sync/log.dart';
import 'package:hahanote_app/hahanote_lib_sync/remotes/base/my_http_overrides.dart';
import 'package:hahanote_app/config/app_config.dart';
import 'package:hahanote_app/config/display_mode.dart';
import 'package:hahanote_app/constants/cons.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/main.dart';
import 'package:hahanote_app/native_util/open_file.dart';
import 'package:hahanote_app/ui/app_layout_observer.dart';
import 'package:hahanote_app/util/fs.dart';
import 'package:hahanote_app/util/util.dart';
import 'package:hahanote_app/widget/base_layout.dart';
import 'package:hahanote_app/widget/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../hahanote_lib_sync/on_off_util.dart';
import '../../hahanote_lib_sync/sync_config.dart';
import '../../ui/ui.dart';
import '../../util/permission.dart';
import '../../widget/my_text_form_field.dart';



const _TAG = "settings_page.dart";


class SettingsPage extends StatefulWidget {
  final bool showScaffold;
  final void Function(String msg) showMsg;
  final void Function(String msg) showMsgLong;
  final void Function(String text) copyTextThenShowMsg;

  const SettingsPage({
    super.key,
    required this.showScaffold,
    required this.showMsg,
    required this.showMsgLong,
    required this.copyTextThenShowMsg
  });

  @override
  State<SettingsPage> createState() => SettingsPageState();

}

class SettingsPageState extends State<SettingsPage> {
  String err = '';
  bool reloading = false;
  bool loading = true;
  late AppConfig _appConfig;
  // List<FileInfo> searchedItems = [];
  // TextEditingController searchKeyword = TextEditingController(text: "");
  // bool searching = false;
  // String searchId = "";

  late List<String> languageList;

  TextEditingController proxyHost = TextEditingController(text: "");
  TextEditingController proxyPort = TextEditingController(text: "");
  TextEditingController proxyUser = TextEditingController(text: "");
  TextEditingController proxyPassword = TextEditingController(text: "");

  String appConfigDirPath = "";

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    proxyHost.dispose();
    proxyPort.dispose();
    proxyUser.dispose();
    proxyPassword.dispose();

    super.dispose();
  }

  // 这代码是否应该抽出来？
  Future<void> init() async {
    if(reloading) {
      return;
    }

    reloading = true;

    setState(() {
      loading = true;
      err = '';
    });

    try {
      appConfigDirPath = await Fs.getAppDataDirPath();

      _appConfig = AppConfig.getConfig();

      proxyHost.text = _appConfig.syncConfig.proxyHost;
      proxyPort.text = _appConfig.syncConfig.proxyPort.toString();
      proxyUser.text = _appConfig.syncConfig.proxyUser;
      proxyPassword.text = _appConfig.syncConfig.proxyPassword;

      languageList = [languageAuto, ...AppLocaleUtils.supportedLocalesRaw];
    }catch(e) {
      err = e.toString();
    }finally {
      setState(() {
        reloading = false;
        loading = false;
      });
    }
  }

  Widget? getSubtitle(String text, {bool selectable = false}) {
    if(text.isEmpty) {
      return null;
    }

    final style = const TextStyle(fontSize: 13, color: Color(0xFF757575));
    return selectable ? SelectableText(text, style: style) : Text(text, style: style);
  }

  Widget getTitle(String text, {bool selectable = false}) {
    final style = const TextStyle(fontSize: 18, fontWeight: FontWeight.bold);
    return selectable ? SelectableText(text, style: style) : Text(text, style: style);
  }


  Future<void> updateConfig(Future<void> Function(AppConfig) handler) async {
    await AppConfig.update(handler);

    setState(() {
      _appConfig = AppConfig.getConfig();
    });
  }


  Future<void> showUpdateHttpProxyDialog() async {
    await Dialogs.showFormDialog(
      context,

      onOk: () async {
        final proxyHost = this.proxyHost.text;
        final proxyPort = int.tryParse(this.proxyPort.text) ?? defaultProxyPort;
        this.proxyPort.text = proxyPort.toString();
        final proxyUser = this.proxyUser.text;
        final proxyPassword = this.proxyPassword.text;

        // no changes
        if(proxyHost == _appConfig.syncConfig.proxyHost &&
            proxyPort == _appConfig.syncConfig.proxyPort &&
            proxyUser == _appConfig.syncConfig.proxyUser &&
            proxyPassword == _appConfig.syncConfig.proxyPassword
        ) {
          return;
        }

        await updateConfig((config) async {
          config.syncConfig.proxyHost = proxyHost;
          config.syncConfig.proxyPort = proxyPort;
          config.syncConfig.proxyUser = proxyUser;
          config.syncConfig.proxyPassword = proxyPassword;
        });

        await MyHttpOverrides.init();
      },

      children: [
        const SizedBox(height: 10,),

        MyTextFormField(
          controller: proxyHost,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: t.host),
          // 设为空即清空设置，所以不需要验证
          // validator: (value) {
          //   return FormValidator.errIfNullOrEmpty(value);
          // }
        ),
        const SizedBox(height: 10,),
        MyTextFormField(
          controller: proxyPort,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: t.port),
          // validator: (value) {
          //   final emptyErr = FormValidator.errIfNullOrEmpty(value);
          //   if(emptyErr != null) {
          //     return emptyErr;
          //   }
          //
          //   final intValue = int.tryParse(value ?? "");
          //   if(isInvalidPort(intValue)) {
          //     return t.invalid;
          //   }
          //
          //   return null;
          // }
        ),
        const SizedBox(height: 10,),

        MyTextFormField(
          controller: proxyUser,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: t.user),
        ),
        const SizedBox(height: 10,),

        MyTextFormField(
          controller: proxyPassword,
          decoration: InputDecoration(border: OutlineInputBorder(), labelText: t.password),
        ),
      ]
    );
  }

  Future<void> _showUpdatePackFileSizeDialog() async {
    await Dialogs.showUpdatePackFileSizeDialog(
      context,
      isGlobal: true,
      currentSizeInBytes: _appConfig.syncConfig.packFileMaxLenInBytes,
      defaultPackFileMaxLenInBytes: defaultPackFileMaxLenInBytes,
      showMsg: widget.showMsg,
      showMsgLong: widget.showMsgLong,
      onSave: (newSize) async {
        await updateConfig((config) async {
          config.syncConfig.packFileMaxLenInBytes = newSize;
        });
      }
    );
  }

  Future<void> updateShowRepoDataDirInFiles() async {
    final newValue = !_appConfig.showRepoDataDirInFiles;
    await updateConfig((config) async {
      config.showRepoDataDirInFiles = newValue;
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;

    if(loading) {
      body = BaseLayout.defaultScreenPaddingContainer(
          child: Center(child: SelectableText(t.loading))
      );
    }else if(err.isNotEmpty) {
      body = BaseLayout.defaultScreenPaddingContainer(
          child: Center(child: SelectableText(err))
      );
    }else {
      final content = Column(
        children: [
          // TextBar(text: t.general),

          ListTile(
            leading: Icon(Icons.language),
            title: getTitle(t.language),
            subtitle: getSubtitle(_appConfig.getCurLanguageText()),
            onTap: () {
              Dialogs.showSingleClickablePlainDialog(
                context,
                languageList,
                selected: (it) => it == _appConfig.getCurLanguageText(),
                itemText: (it) => it,
                onClick: (it) async {
                  if(it == _appConfig.getCurLanguageText()) {
                    return;
                  }

                  await updateConfig((config) async {
                    config.language = it;
                  });

                  widget.showMsg(t.changesWillTakeEffectOnNextStart);
                },
              );
            },
          ),
          ListTile(
            leading: Icon(UI.getThemeIcon()),
            title: getTitle(t.theme),
            subtitle: getSubtitle(UI.getThemeText()),
            onTap: () {
              Dialogs.showSingleClickablePlainDialog(
                context,
                UI.getAllTheme(),
                selected: (it) => it == UI.themeNotifier.value.themeMode,
                itemText: (it) => UI.getThemeText(mode: it),
                onClick: (it) async {
                  await UI.setThemeMode(it);
                },
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.color_lens),
            title: getTitle(t.colorScheme),
            subtitle: getSubtitle(UI.getColorScheme().name),
            onTap: () {
              Dialogs.showSingleClickablePlainDialog(
                context,
                UI.getAllColorSchemes(),
                selected: (it) => it == UI.themeNotifier.value.colorScheme,
                itemText: (it) => it.name,
                onClick: (it) async {
                  await UI.setColorScheme(it);
                },
              );
            },
          ),

          ListTile(
            leading: Icon(Icons.display_settings),
            title: getTitle(t.displayMode),
            subtitle: getSubtitle(_appConfig.getCurDisplayModeText()),
            onTap: () {
              Dialogs.showSingleClickablePlainDialog(
                context,
                DisplayMode.values,
                selected: (it) => it == _appConfig.displayMode,
                itemText: (it) => DisplayMode.toText(it),
                onClick: (it) async {
                  if(it == _appConfig.displayMode) {
                    return;
                  }

                  await updateConfig((config) async {
                    config.displayMode = it;
                  });

                  // 更新状态变量使布局修改立即生效
                  if(!context.mounted) return;
                  // 使用当前窗口的Size作为入参，函数内部会判断，若是自动模式，将使用入参判断是该使用横屏还是竖屏模式（响应式，立即生效，无需重启）
                  isLandscapeLayoutNotifier.value = isLandscapeMode(MediaQuery.sizeOf(context));
                },
              );
            },
          ),

          if(Platform.isAndroid)
            ListTile(
              leading: Icon(Icons.edit),
              title: getTitle(t.textEditor),
              subtitle: getSubtitle(_appConfig.getTextOfTextEditorPackageNameOnAndroid()),
              onTap: () {
                Dialogs.showSingleClickablePlainDialog(
                  context,
                  NativeOpenFile.supportedAndroidEditorsAndBuiltIn,
                  selected: (it) => it.packageName == _appConfig.textEditorPackageNameOnAndroid,
                  itemText: (it) => it.name,
                  onClick: (it) async {
                    if(it.packageName == _appConfig.textEditorPackageNameOnAndroid) {
                      return;
                    }

                    await updateConfig((config) async {
                      config.textEditorPackageNameOnAndroid = it.packageName;
                    });
                  },
                );
              },
            ),

          if(isPcPlatform())
            ListTile(
              leading: Icon(Icons.edit),
              title: getTitle(t.textEditor),
              subtitle: getSubtitle(_appConfig.getTextOfTextEditorPackageNameOnPc()),
              onTap: () {
                Dialogs.showSingleClickablePlainDialog(
                  context,
                  NativeOpenFile.supportedPcEditorsAndBuiltIn,
                  selected: (it) => it.packageName == _appConfig.textEditorPackageNameOnPc,
                  itemText: (it) => it.name,
                  onClick: (it) async {
                    if(it.packageName == _appConfig.textEditorPackageNameOnPc) {
                      return;
                    }

                    await updateConfig((config) async {
                      config.textEditorPackageNameOnPc = it.packageName;
                    });
                  },
                );
              },
            ),

          ListTile(
            leading: Icon(Icons.fingerprint),
            title: getTitle(t.tlsCerts),
            onTap: () {
              Navigator.of(context).pushNamed(Cons.routeTlsCertManage);
            },
          ),

          ListTile(
            leading: Icon(Icons.shopping_bag_outlined),
            title: getTitle(t.packFileSize),
            subtitle: getSubtitle(Fs.humanFriendlySize(_appConfig.syncConfig.packFileMaxLenInBytes)),
            onTap: () async {
              await _showUpdatePackFileSizeDialog();
            },
          ),
          
          ListTile(
            leading: Icon(Icons.http),
            title: getTitle(t.httpProxy),
            subtitle: getSubtitle(_appConfig.syncConfig.isHttpProxyEnabled() ? _appConfig.syncConfig.getFormattedHttpProxyText() : t.disabled),
            onTap: () async {
              await showUpdateHttpProxyDialog();
            },
          ),

          ListTile(
            leading: Icon(Icons.text_snippet_sharp),
            title: getTitle(t.logLevel),
            subtitle: getSubtitle(LogLevel.getStr(_appConfig.syncConfig.logLevel)),
            onTap: () {
              Dialogs.showSingleClickablePlainDialog(
                context,
                LogLevel.values,
                selected: (it) => it == _appConfig.syncConfig.logLevel,
                itemText: (it) => LogLevel.getStr(it),
                onClick: (it) async {
                  if(it == _appConfig.syncConfig.logLevel) {
                    return;
                  }

                  await updateConfig((config) async {
                    config.syncConfig.logLevel = it;
                  });

                  // 重新初始化logger
                  await reInitSyncLibAndLogWithConfig();
                },
              );
            },
          ),

          // 仅针对管理员显示开发模式选项，会在仓库数据目录存储/debug下存储files map等文件的明文内容
          // 注：就算默认隐藏，其实也可修改hive db里的字段来启用（未测试），不过没必要搞太严格，尽量隐藏即可
          // 而且我没做只有管理员才能启用devMode的判定，所以即使当前登录用户不是管理员，但若曾以管理员身份打开了设置，即使后续切换了用户也依然可保持打开，只是隐藏此设置项
          // if(App.getUser().isDeveloper())
          ListTile(
            leading: Icon(Icons.developer_mode),
            title: getTitle(t.devMode),
            subtitle: getSubtitle(boolToOnOff(_appConfig.syncConfig.devModeOn)),
            onTap: () {
              Dialogs.showOnOffDialog(
                context,
                isSelected: (it) => it == _appConfig.syncConfig.devModeOn,
                onClick: (it) async {
                  if(it == _appConfig.syncConfig.devModeOn) {
                    return;
                  }

                  await updateConfig((config) async {
                    config.syncConfig.devModeOn = it;
                  });

                  await reInitSyncLibAndLogWithConfig();
                },
              );
            },
          ),

          ListTile(
            leading: Icon(Icons.snippet_folder_rounded),
            title: getTitle(t.copyAppConfigDirPath),
            subtitle: getSubtitle(appConfigDirPath),
            onTap: () async {
              widget.copyTextThenShowMsg(appConfigDirPath);
            },
          ),

          ListTile(
            leading: Icon(Icons.storage),
            title: getTitle(t.repoDataDir),
            subtitle: getSubtitle(t.showRepoDataDirInFiles),
            // Switch会拦截触摸事件，所以即使这两个调用相同回调，也不会冲突，每次点击只会调用一次
            trailing: Switch(value: _appConfig.showRepoDataDirInFiles, onChanged: (v) async {
              await updateShowRepoDataDirInFiles();
            }),
            onTap: () async {
              await updateShowRepoDataDirInFiles();
            },
          ),

          if(Platform.isAndroid)
            ListTile(
              leading: Icon(Icons.list_alt_outlined),
              title: getTitle(t.permissions),
              onTap: () async {
                await showRequestPermissionDialogIfIsAndroid(
                  context,
                  showMsg: widget.showMsg,
                );
              },
            ),
          if(Platform.isAndroid)
            ListTile(
              leading: Icon(Icons.info_outline),
              title: getTitle(t.appInfo),
              onTap: () async {
                await openAppSettings();
              },
            ),



          UI.getBottomPaddingOfList(),
        ],
      );

      body = SingleChildScrollView(
        child: content
      );
    }

    return body;
  }


}

