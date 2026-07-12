import 'package:flutter/material.dart';
import 'package:hahanote_app/util/reveal_file.dart';
import 'package:hahanote_app/util/util.dart';
import 'package:path/path.dart' as p;

import '../hahanote_lib_sync/utils.dart';

const _TAG = "MediaBar";

class MediaBar extends StatefulWidget {
  final String path;
  final IconData headingIcon;
  final void Function(String)? showMsg;
  final void Function(String)? showMsgLong;

  const MediaBar({
    super.key,
    required this.path,
    required this.headingIcon,
    required this.showMsg,
    required this.showMsgLong,
  });

  @override
  State<MediaBar> createState() => _MediaBarState();

}

class _MediaBarState extends State<MediaBar> {
  bool isRelativePath = false;
  String fileName = "";

  @override
  void initState() {
    super.initState();
    isRelativePath = !isHttpUrl(widget.path);
    fileName = p.basename(widget.path);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(widget.headingIcon),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fileName),
            const Divider(),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    if(isRelativePath) {
                      openFileInExternal(widget.path, showMsgLong: widget.showMsgLong, callerTag: _TAG);
                    }else {
                      launchUrlExtByStr(widget.path);
                    }
                  },
                  icon: Icon(Icons.play_circle_outline),
                ),
                IconButton(
                  onPressed: () {
                    copyText(widget.path);
                  },
                  icon: Icon(Icons.copy),
                ),
                if(isRelativePath) IconButton(
                  onPressed: () {
                    revealFile(widget.path, showMsgLong: widget.showMsgLong);
                  },
                  icon: Icon(Icons.folder_outlined),
                ),
              ],
            )
          ],
        )
      ],
    );
  }
}
