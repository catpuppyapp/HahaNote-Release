import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/util/reveal_file.dart';
import 'package:hahanote_app/util/util.dart';
import 'package:hahanote_app/widget/line.dart';
import 'package:path/path.dart' as p;

import '../hahanote_lib_sync/storage/files/file_path.dart';
import '../hahanote_lib_sync/utils.dart';
import '../ui/app_layout_observer.dart';

const _TAG = "MediaBar";
const _iconSize = 20.0;

class MediaBar extends StatefulWidget {
  final String basePath;
  final String path;
  final IconData headingIcon;
  final void Function(String)? showMsg;
  final void Function(String)? showMsgLong;

  const MediaBar({
    super.key,
    required this.basePath,
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
  String fullPath = "";

  @override
  void initState() {
    super.initState();
    isRelativePath = !isHttpUrl(widget.path);
    fileName = p.basename(widget.path);
    fullPath = isRelativePath ? FilePath.fromString(widget.basePath+"/"+widget.path).toString() : widget.path;
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    if(isLandscapeLayout()) {
      screenWidth = screenWidth / 4.5;
    }else {
      screenWidth = screenWidth / 2.2;
    }

    // guess a width, else the file path cannot scroll
    // max 50 to ensure at least have 50 width
    screenWidth = max(50, screenWidth);

    final bar = Row(
      children: [
        Padding(
          padding: const EdgeInsetsGeometry.all(10),
          child: Icon(widget.headingIcon, size: 30),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsGeometry.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: screenWidth, child: singleScrollableRow2(children: [Text(fileName)])),
                  SizedBox(width: screenWidth, child: singleScrollableRow2(children: [
                    Text(isRelativePath
                      ? FilePath.genRelativePathSafe(widget.basePath, fullPath, ifErrReturnEmpty: false).toUnixPathStr()
                      : fullPath,
                      style: const TextStyle(fontSize: 12),
                    )
                  ])),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: t.play,
                  iconSize: _iconSize,
                  onPressed: () {
                    if(isRelativePath) {
                      openFileInExternal(fullPath, showMsgLong: widget.showMsgLong, callerTag: _TAG);
                    }else {
                      launchUrlExtByStr(fullPath);
                    }
                  },
                  icon: Icon(Icons.play_circle_outline),
                ),
                IconButton(
                  tooltip: t.copyPath,
                  iconSize: _iconSize,
                  onPressed: () {
                    copyText(fullPath);
                  },
                  icon: Icon(Icons.copy),
                ),
                if(isRelativePath) IconButton(
                  tooltip: t.revealInFileExplorer,
                  iconSize: _iconSize,
                  onPressed: () {
                    revealFile(fullPath, showMsgLong: widget.showMsgLong);
                  },
                  icon: Icon(Icons.folder_outlined),
                ),
              ],
            )
          ],
        )
      ],
    );


    return Padding(
      padding: const EdgeInsetsGeometry.all(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey,
            width: 1,
          ),
        ),
        child: bar,
      ),
    );
  }
}
