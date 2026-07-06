import 'dart:io' show File;

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/state/my_page_state.dart' show MyPageState;
import 'package:hahanote_app/util/fs.dart' show Fs;
import 'package:hahanote_app/widget/base_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:path/path.dart' as p;

import '../util/util.dart';
import '../widget/markdown_html_previewer.dart';
import '../widget/pull_to_refresh_list.dart';

const _TAG = "markdown_file_preview.dart";

class MarkdownFilePreview extends StatefulWidget {
  // 从指定文件路径读取内容，也用来获取文件当前路径，不然相对路径的资源无法解析
  final String path;
  final double initialScrollOffset;
  final ScrollController? scrollController;

  const MarkdownFilePreview({
    super.key,
    required this.path,
    this.initialScrollOffset = 0,
    this.scrollController,
  });

  @override
  State<MarkdownFilePreview> createState() => MarkdownFilePreviewState();

}

class MarkdownFilePreviewState extends MyPageState<MarkdownFilePreview> {
  String content = "";
  String err = "";
  File? file;
  String pathStr = "";
  bool loadingFileContent = false;
  String fileName = "";
  String basePath = "";
  late ScrollController scrollController;
  final previewState = GlobalKey<MarkdownHtmlPreviewerState>();

  @override
  void initState() {
    super.initState();

    scrollController = widget.scrollController ?? ScrollController();
    pathStr = widget.path;
    _loadFile(scrollToInitPos: true);
  }

  @override
  void dispose() {
    // 如果父组件没提供scrollController，则是本组件自己创建的，因此自己销毁，否则不管
    if(widget.scrollController == null) {
      scrollController.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFile({bool scrollToInitPos = false}) async {
    if (loadingFileContent) {
      return;
    }

    loadingFileContent = true;
    setState(() {});

    App.logger.debug(_TAG, "loading file");

    try {
      err = "";

      fileName = p.basename(pathStr);
      file = File(pathStr);
      basePath = file!.parent.absolute.path;

      content = myMdToHtml(await Fs.readFileAsStr(file!));


      if(scrollToInitPos) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if(scrollController.hasClients) {
            scrollController.jumpTo(widget.initialScrollOffset);
          }
        });
      }
    } catch (e) {
      setState(() {
        err = e.toString();
      });
    } finally {
      setState(() {
        loadingFileContent = false;
      });
    }
  }

  @override
  bool handleKeyPress(
    KeyEvent event,
    bool isControlDown,
    bool isAltDown,
    bool isShiftDown,
  ) {
    final pressedKey = event.logicalKey;

    if (pressedKey == LogicalKeyboardKey.f5 &&
        !isControlDown &&
        !isAltDown &&
        !isShiftDown
    ) {
      // F5重载文件
      _loadFile();
      return true;
    }

    if(pressedKey == LogicalKeyboardKey.escape
        && !isControlDown && !isAltDown && !isShiftDown
    ) {
      if(_backHandler()) {
        return true;
      }
    }

    return false;
  }

  bool _backHandler() {
    if(previewState.currentState?.fontSizeAdjusterVisible == true) {
      previewState.currentState?.saveAndCloseFontSizeAdjuster();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;

    body = BaseLayout.defaultScreenPaddingContainer(
      // 若正在加载或出错，则使用默认页面padding；否则代表加载完毕，设为0，然后由Markdown组件控制padding
      padding: loadingFileContent || err.isNotEmpty ? null : const EdgeInsets.all(0),
      child: PullToRefreshList(
        loading: loadingFileContent,
        err: err,
        listIsEmpty: false,
        onRefresh: () async {
          await _loadFile();
        },
        child: MarkdownHtmlPreviewer(
          key: previewState,
          scrollController: scrollController,
          data: content,
          basePath: basePath,
          showMsg: showMsg,
          showMsgLong: showMsgLong,
        ),
      ),
    );

    final child = BaseLayout.newScaffold(
      context,
      title: fileName,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: t.refresh,
          onPressed: _loadFile,
        ),
        IconButton(
          icon: const Icon(Icons.format_size),
          tooltip: t.fontSize,
          onPressed: () => previewState.currentState?.showFontSizeAdjuster(),
        ),
      ],
      body: body,
    );

    return BaseLayout.backWrapper(
      context,
      onBack: () async {
        return _backHandler();
      },
      child: child,
    );
  }
}
