import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/i18n/strings.g.dart' show t;
import 'package:flutter/material.dart';

import '../hahanote_lib_sync/storage/repo/config.dart';
import '../hahanote_lib_sync/storage/repo/repo.dart';
import '../ui/ui.dart';


const _TAG = "repo_options_dialog.dart";

class RepoOptionsDialog extends StatefulWidget {
  final String repoPath;
  final void Function(String) showMsg;
  final void Function(String) showMsgLong;

  const RepoOptionsDialog({
    super.key,
    this.repoPath = '',
    required this.showMsg,
    required this.showMsgLong,
  });

  @override
  State<RepoOptionsDialog> createState() => RepoOptionsDialogState();
}

class RepoOptionsDialogState extends State<RepoOptionsDialog> {
  bool loading = false;
  Config? config;
  String err = "";

  @override
  void initState() {
    super.initState();

    doInit();
  }

  Future<void> doInit() async {
    if(loading) {
      return;
    }

    loading = true;

    setState(() {});

    try {
      final repo = await Repo.open(widget.repoPath);
      final config = await repo.getConfig();
      this.config = config;
    }catch(e, st) {
      err = "err: $e";
      App.logger.debug(_TAG, "doInit err: $e\n$st");
    }finally {
      setState(() {
        loading = false;
      });
    }
  }
  void _onConfirm() {
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.options),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: err.isNotEmpty ? [SelectableText(err, style: TextStyle(color: UI.getColorErr()))] : [
            CheckboxListTile(
              controlAffinity: UI.myCheckBoxControlAffinity,
              title: Text(t.remoteOverwriteWorkdirIfNeedMerge),
              value: config?.mergeMode == MergeMode.remoteOverwriteWorkdir,
              onChanged: (v) {
                if(v == null) {
                  return;
                }

                if(v) {
                  config?.mergeMode = MergeMode.remoteOverwriteWorkdir;
                }else {
                  config?.mergeMode = MergeMode.mergeRemoteAndWorkdir;
                }

                setState(() {});
              },
            ),
            Padding(
              padding: UI.defaultCheckboxDescPadding,
              child: SelectableText(t.remoteOverwriteWorkdirIfNeedMergeDesc, style: UI.subTitleTextStyle),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: _onConfirm,
          child: Text(t.ok),
        ),
      ],
    );
  }
}


Future<void> showRepoOptionsDialog(
  BuildContext context, {
  required String repoPath,
  required void Function(String) showMsg,
  required void Function(String) showMsgLong,
  required void Function(Config) onOk
}) async {
  final value = await showDialog<Config>(
    context: context,
    builder: (context) {
      return RepoOptionsDialog(
        repoPath: repoPath,
        showMsg: showMsg,
        showMsgLong: showMsgLong,
      );
    },
  );

  if(value == null) {
    return;
  }


  onOk(value);
}
