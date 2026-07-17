import 'package:hahanote_app/main.dart';
import 'package:hahanote_app/util/util.dart';
import 'package:flutter/material.dart';

import '../db/db.dart';
import '../i18n/strings.g.dart';
import '../util/app_info.dart';

const _changelog = """
- Make the colors in the recent files list clearer in dark theme
- fix markdown preview video/audio error
- update bundled certs
- 让最近文件列表的颜色在暗色模式下更清晰
- 修复markdown预览视频或音频出错
- 更新内置证书
""";

class ChangelogDialog extends StatelessWidget {
  const ChangelogDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.changelog),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton(
              onPressed: () => launchUrlExtByStr(donateUrlKofi),
              child: Text("♥ ${t.donateWelcomeText} ♥", style: TextStyle(fontSize: 20),)
            ),
            const Divider(height: 24), // 分割线

            // 更新日志内容
            SelectableText("${AppInfo.version}\n$_changelog"),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(t.close),
        ),
      ],
    );
  }
}

Future<void> showChangelogDialog(BuildContext context, {required Future<void> Function() onClose}) async {
  await showDialog(
    context: context,
    builder: (BuildContext context) {
      return const ChangelogDialog();
    },
  );

  // 把onClose放showDialog后面是有原因的，这样写，
  // 点按钮或点非弹窗区域，皆可调用onClose，
  // 若设onClose回调，只有点按钮才会调用
  await onClose();
}

Future<void> showChangeLogDialogIfNeed(BuildContext context) async {
  final savedAppVer = await Db.getAppVer();
  final currentAppVer = AppInfo.version;
  if(savedAppVer != currentAppVer) {
    if(!context.mounted) return;

    await showChangelogDialog(context, onClose: () async {
      await Db.setAppVer(currentAppVer);
    });
  }
}
