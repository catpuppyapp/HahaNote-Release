import 'package:cloud_disk_note_app/main.dart';
import 'package:cloud_disk_note_app/util/util.dart';
import 'package:flutter/material.dart';

import '../db/db.dart';
import '../i18n/strings.g.dart';
import '../util/app_info.dart';

const _changelog = """
- remove unused dependencies
- update text editor
- 移除无用依赖
- 更新文本编辑器
""";

class ChangelogDialog extends StatelessWidget {
  final VoidCallback onClose;
  const ChangelogDialog({super.key, required this.onClose});

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
            onClose();
            Navigator.of(context).pop();
          },
          child: Text(t.close),
        ),
      ],
    );
  }
}

Future<void> showChangelogDialog(BuildContext context, {required VoidCallback onClose}) async {
  await showDialog(
    context: context,
    builder: (BuildContext context) {
      return ChangelogDialog(onClose: onClose);
    },
  );
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
