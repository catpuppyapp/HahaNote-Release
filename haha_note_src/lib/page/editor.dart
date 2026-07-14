import 'dart:io' show File;

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:hahanote_app/config/app_config.dart';
import 'package:hahanote_app/constants/cons.dart';
import 'package:hahanote_app/db/db.dart';
import 'package:hahanote_app/db/entity/repo_entity.dart';
import 'package:hahanote_app/i18n/strings.g.dart';
import 'package:hahanote_app/shortcut/shortcut.dart';
import 'package:hahanote_app/state/my_page_state.dart' show MyPageState;
import 'package:hahanote_app/ui/app_layout_observer.dart';
import 'package:hahanote_app/ui/ui.dart' show UI;
import 'package:hahanote_app/util/fs.dart' show Fs;
import 'package:hahanote_app/util/reveal_file.dart';
import 'package:hahanote_app/util/util.dart';
import 'package:hahanote_app/widget/base_layout.dart';
import 'package:hahanote_app/widget/dialogs.dart' show Dialogs;
import 'package:hahanote_app/widget/editor/text_editor.dart' show TextEditor;
import 'package:hahanote_app/widget/my_pop_menu_checkbox.dart';
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:lifecycle/lifecycle.dart' show LifecycleEvent;

import '../bean/bean.dart' show FileStat;
import '../ext/state_ext.dart';
import '../widget/markdown_html_previewer.dart';
import '../widget/pull_to_refresh_list.dart';
import '../widget/size_adjuster.dart';
import '../widget/text_and_shortcut.dart';

const _TAG = "editor.dart";

// 横屏，预览和编辑器是否同步滚动，感觉不好，故禁用，日后考虑设个设置项让用户控制
const scrollSyncEnabled = false;

// 如果文件由有效的utf8字符组成，那么读取不会报错，编辑器能正常打开，比较文件若不同则报错的逻辑可靠；
// 若文件有非法utf8字符，那么读取会报错，无法保存
// 所以如果打开一个非文本文件，理论上应该不会转码错误使文件损坏（但没严格测试）

class EditorPage extends StatefulWidget {
  final FilePath path;

  const EditorPage({super.key, required this.path});

  @override
  State<EditorPage> createState() => _EditorPageState();

}

class _EditorPageState extends MyPageState<EditorPage> {
  bool savedAtLeastOnce = false;

  RepoEntity? openedRepo;
  // CodeEditorStyle style = CodeEditorStyle(fontSize: UI.editorFontSizeDefault);
  double fontSize = UI.editorFontSizeDefault;

  int editorContentVer = 0;
  CodeForgeController? controller;
  FindController? findController;
  UndoRedoController? undoController;
  ScrollController? scrollController;
  String? lineBreak;  //打开文件时会检测文件的换行符，用来在保存时使用原本的换行符，若是空文件，使用\n

  String err = '';
  bool canSave = false;
  File? file;
  bool skipSaveOnce = false;
  // 这个初始值必须为true，不然在初次加载后会触发一次无意义的重载检查
  bool skipReloadCheckOnce = true;
  bool reloading = false;
  bool loadingFileContent = true;
  /// 这是路径是用来从db查关联的pos的，一律使用unix格式，不要用这个来打开文件，若是非linux系统，可能会打不开
  /// 如果想获取使用当前系统路径分隔符的路径，应使用 widget.path
  late final String pathStr;
  /// 这个是预览时加载相对路径的图片用的，一律是unix格式
  late final String basePath;
  late final String systemPathSeparatorPath;

  bool fontSizeAdjusterVisible = false;

  FileStat fileStat = FileStat();

  // 若true，启用分面板预览，否则跳转到独立页面预览，暂时没必要传参，以后有需要再改
  final bool useSplitPreviewPanel = isLandscapeLayout();
  bool editorPreviewEnabled = false;
  final previewState = GlobalKey<MarkdownHtmlPreviewerState>();
  final ScrollController previewScrollController = ScrollController();
  bool scrolling = false;
  String? content;  // 存在内存的文件内容，预览用
  final ValueNotifier<bool> undoNotifier = ValueNotifier(false);
  final ValueNotifier<bool> redoNotifier = ValueNotifier(false);
  final ValueNotifier<bool> needSaveNotifier = ValueNotifier(false);
  bool softWrapEnabled = true;
  bool lineNumEnabled = true;

  void updatePreviewContent(String? content) {
    this.content = editorPreviewEnabled ? myMdToHtml(content ?? "") : null;
  }

  @override
  void initState() {
    super.initState();

    pathStr = widget.path.toUnixPathStr();
    // 给img等引用相对路径的标签用的基路径，一律使用unix路径分隔符
    basePath = widget.path.parent().toUnixPathStr();
    systemPathSeparatorPath = widget.path.toString();
    editorPreviewEnabled = useSplitPreviewPanel && AppConfig.getConfig().editorPreviewEnabled;
    softWrapEnabled = AppConfig.getConfig().editorSoftWrapEnabled;
    lineNumEnabled = AppConfig.getConfig().editorLineNumEnabled;

    doInit();
  }

  Future<void> doInit() async {
    openedRepo = await Db.getIfOpenedRepoGood();
    await _initFontSize();
    await _loadFile();
  }

  @override
  void dispose() {
    disposeOldControllers();
    super.dispose();
  }

  void _handleControllerChange() {
    if (!mounted) return;

    needSaveNotifier.value = needSave();
  }

  void _handleUndoChange() {
    if (!mounted) return;

    undoNotifier.value = undoController?.canUndo ?? false;
    redoNotifier.value = undoController?.canRedo ?? false;
  }

  @override
  void onLifecycleEvent(LifecycleEvent event) {
    // 如果离开页面，执行保存；
    // 返回时检查是否需要重载
    if(event == LifecycleEvent.inactive) {
      // BUG: pc，切到其他app，当前app未最小化，依然可见，不会执行保存
      // 如果用 inactive来判断是否save，显示弹窗时也会执行save，
      // 就无法实现弹窗询问是否确认重载了（询问时不应该执行保存，否则询问就没意义了）
      // 所以这里用invisible替代，但是，invisible只有在app最小化时才会执行，
      // 所以切换窗口时不会自动保存，但是，如果再切换回来，由于下面是用active检测的，
      // 这时如果文件发生变化，会检测到并询问是否重载
      _save();
    }else if(event == LifecycleEvent.active) {
      // BUG: 在当前页面，点弹窗，返回，也会触发重载检查
      // 如果之前是inActive，现在是active，检测下内容是否发生了修改
      // 使用此变量之后再调用父类的函数，不然父类的状态更新了，就不知道之前是否是active了
      _reloadIfStatChanged();
    }


    // 调用下parent的，更新下page是否可见的状态变量
    super.onLifecycleEvent(event);

  }

  void _scrollSyncHandler(final ScrollController? src, final ScrollController? mirror) {
    if(!scrollSyncEnabled) {
      return;
    }

    _syncSrcScrollPosToMirror(src, mirror);
  }

  // 同步src的滚动位置到mirror
  void _syncSrcScrollPosToMirror(final ScrollController? src, final ScrollController? mirror) {
    if(src == null || mirror == null) {
      return;
    }

    if(!mounted || !editorPreviewEnabled) {
      return;
    }

    if(!src.hasClients || !mirror.hasClients) {
      return;
    }

    if(scrolling) {
      return;
    }
    scrolling = true;

    try {
      // 2. 获取当前这一帧的滚动位置
      double? currentPixels = src.position.pixels;
      final double targetPos = currentPixels.clamp(0, mirror.position.maxScrollExtent);
      if(targetPos == mirror.position.pixels) {
        // 目标位置就是当前位置，无需跳转
        return;
      }

      mirror.jumpTo(targetPos);
    }finally {
      scrolling = false;
    }
  }

  void editorToPreviewScrollSyncHandler() {
    _scrollSyncHandler(scrollController, previewScrollController);
  }


  void previewToEditorScrollSyncHandler() {
    _scrollSyncHandler(previewScrollController, scrollController);
  }

  Future<void> _initFontSize() async {
    final fontSizeFromDb = await Db.getEditorFontSize();
    if(fontSizeFromDb != fontSize) {
      _setFontSize(fontSizeFromDb);
    }
  }

  // 读取文件行，转换换行符为\n，不然editor处理可能会出错
  // 保存时再读取所有行，拼接上文件的原始换行符
  // 若文件为空，则使用\n作为换行符
  String getTextOfFile() {
    final contentAndLineBreak = Fs.readFileAndReplaceLineBreakToLfSync(file!);
    lineBreak = contentAndLineBreak.second;
    return contentAndLineBreak.first;
  }

  void _resetUndoAndNeedSaveState() {
    needSaveNotifier.value = false;
    undoNotifier.value = false;
    redoNotifier.value = false;
    undoController?.clear();
  }

  Future<void> _reloadFile() async {
    // return _loadFile();
    if(reloading || loadingFileContent) {
      return;
    }
    reloading = true;
    loadingFileContent = true;
    setState(() {});

    try {
      final file = this.file;
      if(file == null) {
        return;
      }

      final controller = this.controller;
      if(controller == null) {
        return;
      }

      final lastPos = FilePos.fromCodeLineSelectionWithoutPath(controller.selection);
      
      err = '';
      final text = getTextOfFile();
      final editorCurrentText = getEditorText(restoreLineBreak: false);
      if(text == editorCurrentText) { // text no change, skip
        App.logger.debug(_TAG, "content no changed, reload canceled");
      }else { // text changed, update
        controller.text = text;

        if(useSplitPreviewPanel) {
          updatePreviewContent(text);
        }

        _resetUndoAndNeedSaveState();

        // 重载后恢复上次编辑位置
        // 必须等一下页面刷新，不然可能报 editor not initialized 错误
        // 注：就算等了，还是会报disposed错误，原因不明，我明明没dispose滚动controller啊
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          _doGoToPos(lastPos);
        });
      }

      editorContentVer = controller.contentVersion;
      fileStat = await FileStat.fromFile(file);
      canSave = true;
    }catch(e) {
      setState(() {
        err = e.toString();
      });
    }finally {
      setState(() {
        loadingFileContent = false;
        reloading = false;
      });
    }
  }

  void disposeOldControllers() {
    try {
      updateLastEditPos();
    }catch(e, st) {
      App.logger.debug(_TAG, 'update last edit pos err: $e\n$st');
    }

    try {
      findController?.dispose();
    }catch(e, st) {
      App.logger.debug(_TAG, 'dispose editor find controller err: $e\n$st');
    }

    try {
      if(useSplitPreviewPanel) {
        // 只有pc端才显示预览面板，才需要添加和移除这个滚动监听handler
        scrollController?.removeListener(editorToPreviewScrollSyncHandler);
        previewScrollController.removeListener(previewToEditorScrollSyncHandler);
      }
      undoController?.removeListener(_handleUndoChange);
      controller?.removeListener(_handleControllerChange);
    }catch(e, st) {
      App.logger.debug(_TAG, 'remove controller listeners err: $e\n$st');
    }

    try {
      scrollController?.dispose();
    }catch(e, st) {
      App.logger.debug(_TAG, 'dispose editor scroll controller err: $e\n$st');
    }

    try {
      previewScrollController.dispose();
    }catch(e, st) {
      App.logger.debug(_TAG, 'dispose preview scroll controller err: $e\n$st');
    }

    try {
      undoController?.dispose();
    }catch(e, st) {
      App.logger.debug(_TAG, 'dispose undo controller err: $e\n$st');
    }

    try {
      controller?.dispose();
    }catch(e, st) {
      App.logger.debug(_TAG, 'dispose editor controller err: $e\n$st');
    }
  }

  Future<void> _loadFile() async {
    if(reloading) {  //这里无需判断loadingFileContent，因为其初始值为true，若判断，无法初始化文件，还得改判定机制，麻烦
      return;
    }
    reloading = true;
    loadingFileContent = true;
    setState(() {});

    canSave = false;  // 这个是为了加载出错时禁用保存功能？
    try {
      err = '';
      file = widget.path.toFile();
      final text = getTextOfFile();
      // dispose old controllers
      // disposeOldControllers();

      // create new controllers
      controller = CodeForgeController();
      controller!.text = text;
      editorContentVer = controller!.contentVersion;
      controller!.addListener(_handleControllerChange);
      scrollController = ScrollController();
      undoController = UndoRedoController();
      undoController!.addListener(_handleUndoChange);
      findController = FindController(controller!);
      if(useSplitPreviewPanel) {
        updatePreviewContent(text);
        scrollController!.addListener(editorToPreviewScrollSyncHandler);
        previewScrollController.addListener(previewToEditorScrollSyncHandler);
      }
      fileStat = await FileStat.fromFile(file!);
      canSave = true;  // 加载文件成功，可以保存文件

      _resetUndoAndNeedSaveState();

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final openedRepo = await Db.getOpenedRepo();
        if(openedRepo == null) {
          // 这样有个缺点，如果没打开仓库，编辑文件，就不记录位置了，可创建一个没打开仓库时的虚仓库，如果有必要的话
          return;
        }

        final pos = openedRepo.getPosByPath(pathStr);
        if(pos == null) {
          return;
        }

        _goToPos(pos);
      });

    }catch(e) {
      setState(() {
        err = e.toString();
      });
    }finally {
      setState(() {
        loadingFileContent = false;
        reloading = false;
      });
    }
  }

  Future<void> updateLastEditPos() async {
    final controller = this.controller;

    if(controller == null) {
      return;
    }

    await Db.saveFileLastEditPos(FilePath.fromString(pathStr), controller.selection);
  }

  void _goToLineByIndex(int lineIndex, {TextSelection? selection}) {
    try {
      _goToLineByIndexNoCatch(lineIndex, selection: selection);
    }catch(e, st) {
      App.logger.debug(_TAG, "go to line by index err: $e\n$st");
    }
  }

  void _goToLineByIndexNoCatch(int lineIndex, {TextSelection? selection}) {
    final controller = this.controller;
    if(controller == null) return;

    // 注：必须先selection再scroll to line，不然目标行会在最底部
    // selection也带跳转行的功能，但不会尝试使目标行在视觉中心，所以设置为selection后还是需要滚动到目标行

    // 定位光标位置
    if(selection == null) {
      // 若为null，定位到行开头
      final cursorPos = controller.getLineStartOffset(lineIndex);
      controller.selection = TextSelection(baseOffset: cursorPos, extentOffset: cursorPos);
    }else {
      // selection非null，定位到具体列或选择范围
      controller.selection = selection;
    }

    // 跳转到目标行（索引，0开始）
    controller.scrollToLine(lineIndex);
    // 必须focus，不然中文这种带缓冲的输入法，可能会光标漂移，不知道漂到哪里去
    controller.focusNode?.requestFocus();

    // if disabled scroll sync,
    // need set force sync scroll once
    // to let preview scroll to the pos of editor
    if(!scrollSyncEnabled) {
      () async {
        await Future.delayed(const Duration(milliseconds: 500));
        _syncSrcScrollPosToMirror(scrollController, previewScrollController);
      }();
    }
  }

  void _doGoToPos(FilePos pos) {
    final controller = this.controller;
    if(controller == null) return;

    _goToLineByIndex(controller.getLineAtOffset(pos.index), selection: pos.toSelection());
  }

  void _goToPos(FilePos pos) {
    final controller = this.controller;
    if(controller == null) {
      return;
    }


    try {
      _doGoToPos(pos);
    }catch(e, st) {
      // 有可能跳转无效，小概率发生，可能因为controller和editor还没绑定上
      App.logger.debug(_TAG, "go to pos err: $e\n$st");
    }
  }

  bool _backHandler() {
    if(fontSizeAdjusterVisible) {
      _saveAndCloseFontSizeAdjuster();
      return true;
    }

    if(findController?.isActive == true) {
      findController?.toggleActive();
      return true;
    }

    _save();

    return false;
  }

  @override
  bool handleKeyPress(KeyEvent event, bool isControlDown, bool isAltDown, bool isShiftDown) {
    final pressedKey = event.logicalKey;
    if(pressedKey == LogicalKeyboardKey.escape
        && !isControlDown && !isAltDown && !isShiftDown
        && mounted
    ) {
      if(_backHandler()) {
        return true;
      }
    }

    if(isControlDown && pressedKey == LogicalKeyboardKey.keyS) {
      // Ctrl+S
      _save(); // 调用你的保存函数
      return true; // 表示已处理该事件，阻止冒泡
    }

    if(isControlDown && pressedKey == LogicalKeyboardKey.keyW) {
      // Ctrl+W
      _showCloseDialog();
      return true;
    }

    if(isControlDown && pressedKey == LogicalKeyboardKey.keyF) {
      // Ctrl+F
      _switchFindMode();
      return true;
    }

    if(isControlDown && pressedKey == LogicalKeyboardKey.keyR) {
      // Ctrl+R
      _switchReplaceMode();
      return true;
    }

    if(isControlDown && pressedKey == LogicalKeyboardKey.keyG) {
      // Ctrl+G
      _showGoToLineDialog(context);
      return true;
    }

    if(isControlDown && pressedKey == LogicalKeyboardKey.keyP) {
      // Ctrl+P, preview markdown
      _preview();
      return true;
    }

    if(isControlDown && pressedKey == LogicalKeyboardKey.keyH) {
      // Ctrl+H, go to history
      _goToHistory();
      return true;
    }

    if(!isControlDown && !isShiftDown && isAltDown && pressedKey == LogicalKeyboardKey.arrowUp) {
      // Alt + Up ,move line up
      controller?.moveLineUp();
      return true;
    }

    if(!isControlDown && !isShiftDown && isAltDown && pressedKey == LogicalKeyboardKey.arrowDown) {
      // Alt + Down ,move line down
      controller?.moveLineDown();
      return true;
    }

    if(isControlDown && !isShiftDown && !isAltDown && pressedKey == LogicalKeyboardKey.keyX) {
      // Ctrl + X, cut line
      if(_copyOrCutLine(trueCopyFalseCut: false)) {
        return true;
      }
    }

    if(isControlDown && !isShiftDown && !isAltDown && pressedKey == LogicalKeyboardKey.keyC) {
      // Ctrl + C, copy line
      if(_copyOrCutLine(trueCopyFalseCut: true)) {
        return true;
      }
    }

    // if(isControlDown && isShiftDown && pressedKey == LogicalKeyboardKey.keyZ) {
    //   // xTODO bug： 会触发，但不一定有效，因为Ctrl+Shift+Z包含Ctrl+Z，可能和Editor内置的快捷键冲突了？
    //   //   后来改了下code_forge源码，解决了
    //   if(undoController?.canRedo == true) {
    //     undoController?.redo();
    //   }
    //   return true;
    // }

    if(pressedKey == LogicalKeyboardKey.f5 && !isControlDown && !isAltDown && !isShiftDown) {
      // F5重载文件
      _showReloadDialog();
      return true;
    }

    if(pressedKey == LogicalKeyboardKey.f3 && !isControlDown && !isAltDown) {
      _goToNextKeyword(toNext: !isShiftDown);
      return true;
    }

    if(pressedKey == LogicalKeyboardKey.f4 && !isControlDown && !isAltDown && !isShiftDown) {
      // reveal file
      _revealFile();
      return true;
    }

    return false;
  }

  bool _copyOrCutLine({required bool trueCopyFalseCut}) {
    final controller = this.controller;
    if(controller != null && controller.selection.isCollapsed) {
      final start = controller.selection.start;
      final lineIdx = controller.getLineAtOffset(start);
      final text = controller.getLineText(lineIdx);
      copyText(text);

      // if is cut, delete then copy
      if(!trueCopyFalseCut) {
        final lineStart = controller.getLineStartOffset(lineIdx);
        controller.selection = TextSelection(baseOffset: lineStart, extentOffset: lineStart+text.length);
        controller.delete();
      }
      return true;
    }

    return false;
  }

  Future<void> _revealFile() async {
    await revealFile(systemPathSeparatorPath, showMsgLong: showMsgLong);
  }

  void _switchFindMode() {
    // findController?.toggleActive();
    // 直接这个，一步到位
    _switchReplaceMode();
  }

  void _goToNextKeyword({bool toNext = true}) {
    final findController = this.findController;
    if(findController == null) return;

    if(toNext) {
      findController.next();
    }else {
      findController.previous();
    }

    // TODO 选中高亮文本
  }

  void _switchReplaceMode() {
    final findController = this.findController;
    if(findController == null) return;

    if(!findController.isActive) {  // 开启，并打开搜索和替换框
      findController.toggleActive();
      // 若非替换模式，打开
      if(!findController.isReplaceMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          findController.toggleReplaceMode();
        });
      }
    }else {  //关闭
      findController.toggleActive();
    }

  }

  Future<void> _undo() async {
    undoController?.undo();
    refreshUI();
  }

  Future<void> _redo() async {
    undoController?.redo();
    refreshUI();
  }

  bool needSave() {
    final controller = this.controller;
    if(controller == null) {
      return false;
    }

    return editorContentVer != controller.contentVersion;
  }

  Future<void> _reloadIfStatChanged() async {
    App.logger.debug(_TAG, "reload check called");
    if(skipReloadCheckOnce) {
      App.logger.debug(_TAG, "reload check skipped");
      skipReloadCheckOnce = false;
      return;
    }

    final file = this.file;
    if(file == null) {
      return;
    }

    final latestStat = await FileStat.fromFile(file);
    if(latestStat == fileStat) {
      App.logger.debug(_TAG, "reload check skipped: stat no change");
      return;
    }

    _reloadFile();
  }

  Future<void> _preview() async {
    if(useSplitPreviewPanel) {
      final newValue = !editorPreviewEnabled;
      editorPreviewEnabled = newValue;
      if(newValue) {
        updatePreviewContent(getEditorText(restoreLineBreak: false));
        // 打开预览面板后滚动到编辑器面板的位置（尽量，不保证精准，因为渲染后的内容高度可能和文字不同）
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final editorSc = scrollController;
          if(editorSc == null || !editorSc.hasClients || !previewScrollController.hasClients) {
            return;
          }

          previewScrollController.jumpTo(editorSc.position.pixels.clamp(0, previewScrollController.position.maxScrollExtent));
        });
      }else {
        updatePreviewContent(null);
      }

      setStateSafe(() {});
      AppConfig.update((config) async => config.editorPreviewEnabled = newValue);
    }else {
      editorPreviewEnabled = false;
      updatePreviewContent(null);
      await Navigator.pushNamed(
        context,
        Cons.routeMarkdownPreview,
        arguments: {
          "path": systemPathSeparatorPath,
          "initialScrollOffset": scrollController?.offset ?? 0,
        }
      );
    }
  }

  String? getEditorText({required bool restoreLineBreak}) {
    final controller = this.controller;
    if(controller == null) return null;

    final text = controller.text;
    if(!restoreLineBreak || lineBreak == Fs.lf) {
      return text;
    }

    // 文件原本是crlf，保存时需要替换下
    return text.replaceAll(Fs.lf, Fs.crlf);
  }

  // allowSkip，在生命周期之类自动触发的地方，设为true，其他地方，手动触发的，一律设为假
  void _save() {
    if(err.isNotEmpty) {
      App.logger.debug(_TAG, "page had an err, so will not save file, err: $err");
      return;
    }

    App.logger.debug(_TAG, "save called");

    if(skipSaveOnce) {
      App.logger.debug(_TAG, "save skipped");
      // 这个变量和ui无关，只用于在执行操作时判断，所以不需要setState
      skipSaveOnce = false;
      return;
    }


    final controller = this.controller;
    final file = this.file;

    if(loadingFileContent) {
      // 正加载文件呢，不能保存
      App.logger.debug(_TAG, "save canceled: loading file content, please try again later");
      return;
    }

    if(controller == null || file == null) {
      App.logger.debug(_TAG, "save canceled: file is null, maybe loading failed?");
      return;
    }

    // 避免并发冲突
    if(!canSave) {
      App.logger.debug(_TAG, "save canceled: can't save, maybe already called save by other task?");
      return;
    }

    canSave = false;

    try {
      if(needSave()) {
        final newText = getEditorText(restoreLineBreak: true);
        if(newText == null) {
          throw "get content of editor err, err code: 12622770";
        }
        Fs.writeStrToFileSync(file, newText);
        editorContentVer = controller.contentVersion;
        needSaveNotifier.value = false;
        fileStat = FileStat.fromFileSync(file);
        savedAtLeastOnce = true;
        updatePreviewContent(newText);
        // showMsg(t.saved);
      }


    }catch(e) {
      showMsgLong("save failed: $e");
    }finally {
      canSave = true;
      setStateSafe(() {});
    }
  }


  Future<void> _showReloadDialog() async {
    // 如果 needSave 为false，说明内容在从文件读取后或者上次保存之后未在本editor修改过，直接重载（注意是本editor没改，外部程序可能改过，但外部程序不归我们管，只要我们读取后没修改过，就直接重载，无需提示，这样用户用外部程序修改文件后，如果editor没及时更新，可按f5一键重载而无需弹窗确认）
    // 否则内容不同，询问是否确定重载
    if(!needSave()) {
      await _reloadFile();
      return;
    }

    // 弹窗询问是否确定重载
    await _showDialog(
      t.reload,
      act: _reloadFile,
    );
  }

  void backToParentPage() {
    // 返回值代表editor是否曾保存过文件，若是父页面可能需要刷新（不过后来在父页面判断，
    // 若父页面invisible过，再切换到visible时则刷新，所以此值实际上没用了）
    Navigator.of(context).pop(savedAtLeastOnce);
  }

  Future<void> _showCloseDialog() async {
    final controller = this.controller;

    if(controller == null) {
      backToParentPage();
      return;
    }


    void act() {
      skipSaveOnce = true;
      backToParentPage();
    }

    if(!needSave()) {
      act();
      return;
    }

    await _showDialog(
      t.close,
      act: act
    );
  }

  Future<void> _showGoToLineDialog(BuildContext context) async {
    if(!context.mounted) {
      return;
    }

    final controller = this.controller;
    if(controller == null) {
      return;
    }

    final maxLineNum = controller.lineCount;
    _skipEventForDialog();

    final value = await Dialogs.showInputDialog(
      context,
      title: t.goTo,
      showMsg: showMsg,
      showMsgLong: showMsgLong,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.go,
      hintText: '1-$maxLineNum',
    );

    // 若等于null，可能是点了取消
    if(value != null) {
      final n = int.tryParse(value.trim());
      if(n != null) {
        // 限制在1和最大行号中间
        _goToLineByIndex((n-1).clamp(0, maxLineNum-1));
      }
    }
  }

  void _skipEventForDialog() {
    skipSaveOnce = true;
    skipReloadCheckOnce = true;
  }


  Future<void> _showDialog(
    String title, {
    required VoidCallback act
  }) async {
    _skipEventForDialog();

    await Dialogs.showOkOrNoDialog(
      context,
      title: title,
      text: t.unsavedDateWillLost,
      onOk: act
    );
  }

  void _setFontSize(double value) {
    setState(() {
      fontSize = value;
    });
  }

  void _saveAndCloseFontSizeAdjuster() {
    setState(() {
      fontSizeAdjusterVisible = false;
    });

    // save to db
    Db.saveEditorFontSize(fontSize);

    previewState.currentState?.saveAndCloseFontSizeAdjuster();
  }

  Widget _getFontSizeAdjuster() {
    final fontSizeMin = UI.editorFontSizeMin;
    final fontSizeMax = UI.editorFontSizeMax;
    return getFontSizeAdjuster(
      context,
      onMinus: fontSize <= fontSizeMin ? null : () => _setFontSize(fontSize - UI.editorFontSizeAdjustStep),
      onPlus: fontSize >= fontSizeMax ? null : () => _setFontSize(fontSize + UI.editorFontSizeAdjustStep),
      onClose: _saveAndCloseFontSizeAdjuster,
    );
  }

  Future<void> _goToHistory() async {
    final openedRepo = this.openedRepo;
    if(openedRepo == null) {
      showMsg(t.noRepoOpened);
      return;
    }

    Navigator.pushNamed(
      context,
      Cons.routeFileHistory,
      arguments: {"path": FilePath.genRelativePathSafe(openedRepo.path, pathStr, ifErrReturnEmpty: true).toUnixPathStr()},
    );
  }

  // 有确定参数则用，无则将原参数取反
  Future<void> _switchSoftWrap({bool? value}) async {
    final it = value ?? !softWrapEnabled;
    setState(() => softWrapEnabled = it);
    // 得再刷新下state，不然可能无法显示最新状态
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() {});
    });
    await AppConfig.update((config) async => config.editorSoftWrapEnabled = it);
  }

  Future<void> _switchLinNum({bool? value}) async {
    final it = value ?? !lineNumEnabled;
    setState(() => lineNumEnabled = it);
    // 得再刷新下state，不然行号可能无法正确显示和隐藏
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      setState(() {});
    });
    await AppConfig.update((config) async => config.editorLineNumEnabled = it);
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    final controller = this.controller;
    final findController = this.findController;
    final scrollController = this.scrollController;
    final undoController = this.undoController;

    final fileReady = !loadingFileContent && err.isEmpty && controller != null && findController != null && undoController != null;
    if(fileReady) {
      final textEditor = Stack(
        children: [
          // 页面主体内容层
          TextEditor(
            filePath: systemPathSeparatorPath,
            controller: controller,
            verticalScrollController: scrollController,
            undoController: undoController,
            findController: findController,
            softWrapEnabled: softWrapEnabled,
            fontSize: fontSize,
            lineNumEnabled: lineNumEnabled,
            // onChanged: (v) {
            //   // 这个判断不准啊！文件内容没改变一样会调用这个函数，
            //   // 例如选择范围改变了，也会调用，所以用它来判断是否启用保存并不靠谱
            //   if(canSave) return;
            //
            //   setState(() {
            //     canSave = true;
            //   });
            // },
          ),

          // font size adjuster
          if(fontSizeAdjusterVisible) _getFontSizeAdjuster(),
        ],
      );

      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: textEditor),
          if(editorPreviewEnabled) UI.verticalDividerWidth1,
          if(editorPreviewEnabled) Expanded(
            child: PullToRefreshList(
              loading: loadingFileContent,
              err: "", //  若出错，只在editor编辑面板显示即可，这个预览面板不用显示错误
              listIsEmpty: false,
              onRefresh: () async {
                updatePreviewContent(getEditorText(restoreLineBreak: false));
                setStateSafe(() {});
              },
              child: MarkdownHtmlPreviewer(
                key: previewState,
                scrollController: previewScrollController,
                fontSizeAdjusterCloseVisible: false,
                data: content ?? "",
                basePath: basePath,
                showMsg: showMsg,
                showMsgLong: showMsgLong,
              ),
            ),
          ),
        ],
      );

    }else {
      body = BaseLayout.defaultScreenPaddingContainer(
        child: Center(
          child: SelectableText(
            // err.isEmpty ? "controller is null: ${controller == null}, findController is null: ${findController == null}"
            err.isEmpty ? t.loading : err,
            style: err.isEmpty ? null : TextStyle(color: UI.getColorErr())
          )
        ),
      );
    }

    final child = BaseLayout.newScaffold(
      context,
      title: widget.path.name(),
      actions: [
        ValueListenableBuilder<bool>(
          valueListenable: undoNotifier,
          builder: (_, bool canUndo, __) {
            return IconButton(
              icon: const Icon(Icons.undo),
              tooltip: "${t.undo} (${ShortCuts.getKeyBindingOfUndo()})",
              onPressed: canUndo ? _undo : null,
            );
          }
        ),
        ValueListenableBuilder<bool>(
          valueListenable: redoNotifier,
          builder: (_, bool canRedo, __) {
            return IconButton(
              icon: const Icon(Icons.redo),
              tooltip: "${t.redo} (${ShortCuts.getKeyBindingOfRedo()})",
              onPressed: canRedo ? _redo : null,
            );
          }
        ),
        ValueListenableBuilder<bool>(
          valueListenable: needSaveNotifier,
          builder: (_, bool value, __) {
            return IconButton(
              icon: const Icon(Icons.save),
              tooltip: "${t.save} (${ShortCuts.getKeyBindingOfSave()})",
              onPressed: value ? _save : null,
            );
          }
        ),
        IconButton(
          icon: const Icon(Icons.remove_red_eye),
          tooltip: "${t.preview} (${ShortCuts.getKeyBindingOfPreview()})",
          onPressed: err.isEmpty ? _preview : null,
        ),
        PopupMenuButton<String>(
          onOpened: () {
            _skipEventForDialog();
          },
          offset: UI.offsetTopBarMenu,
          icon: Icon(Icons.more_vert),
          onSelected: (value) async {
            if(value == 'find') {
              _switchFindMode();
            }else if(value == 'replace') {
              _switchReplaceMode();
            }else if(value == 'goTo') {
              _showGoToLineDialog(context);
            }else if(value == 'reload') {
              _showReloadDialog();
            }else if(value == 'close') {
              _showCloseDialog();
            }else if(value == 'history') {
              _goToHistory();
            }else if(value == 'fontSize') {
              setState(() {
                fontSizeAdjusterVisible = true;
              });
              previewState.currentState?.showFontSizeAdjuster();
            }else if(value == 'openInExt') {
              openFileInExternal(systemPathSeparatorPath, showMsgLong: showMsgLong, callerTag: _TAG);
            }else if(value == 'revealInFileExplorer') {
              _revealFile();
            }else if(value == 'softWrap') {
              _switchSoftWrap();
            }else if(value == 'lineNum') {
              _switchLinNum();
            }
          },
          itemBuilder: (context) {
            return <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'close',
                child: TextAndShortcut(text: t.close, shortcut: "Ctrl+W"),
              ),

              PopupMenuItem<String>(
                value: 'reload',
                child: TextAndShortcut(text: t.reload, shortcut: "F5"),
              ),

              PopupMenuItem<String>(
                value: 'openInExt',
                child: TextAndShortcut(text: t.openInExt),
              ),

              PopupMenuItem<String>(
                value: 'revealInFileExplorer',
                child: TextAndShortcut(text: t.revealInFileExplorer, shortcut: "F4"),
              ),

              if(fileReady)
              PopupMenuItem<String>(
                value: 'find',
                child: TextAndShortcut(text: t.find, shortcut: "Ctrl+F"),
              ),

              if(fileReady)
              PopupMenuItem<String>(
                value: 'replace',
                child: TextAndShortcut(text: t.replace, shortcut: "Ctrl+R"),
              ),

              if(fileReady)
              PopupMenuItem<String>(
                value: 'goTo',
                child: TextAndShortcut(text: t.goTo, shortcut: "Ctrl+G"),
              ),

              if(fileReady)
              PopupMenuItem<String>(
                value: 'fontSize',
                child: TextAndShortcut(text: t.fontSize),
              ),

              if(fileReady)
              PopupMenuItem<String>(
                value: 'softWrap',
                child: MyPopMenuCheckbox(
                  text: t.softWrap,
                  value: softWrapEnabled,
                  onChanged: (it) => _switchSoftWrap(value: it)
                ),
              ),

              if(fileReady)
              PopupMenuItem<String>(
                value: 'lineNum',
                child: MyPopMenuCheckbox(
                  text: t.lineNumber,
                  value: lineNumEnabled,
                  onChanged: (it) => _switchLinNum(value: it)
                ),
              ),

              PopupMenuItem<String>(
                value: 'history',
                child: TextAndShortcut(text: t.history, shortcut: "Ctrl+H"),
              ),

            ];
          },
        ),
      ],
      fab: isPcPlatform() ? null : ValueListenableBuilder<bool>(
        valueListenable: needSaveNotifier,
        builder: (_, bool value, __) {
          if(!value) {
            return const SizedBox.shrink();
          }

          return IconButton(
            icon: const Icon(Icons.save),
            tooltip: "${t.save} (${ShortCuts.getKeyBindingOfSave()})",
            // 内容变了，需要保存，并且能保存（加载完毕并且当前没有在执行保存）则启用保存，否则禁用
            onPressed: value && canSave ? _save : null,
          );
        }
      ),
      body: body,
    );

    return BaseLayout.backWrapper(
      context,
      onBack: () async {
        return _backHandler();
      },
      child: child
    );

  }

}

