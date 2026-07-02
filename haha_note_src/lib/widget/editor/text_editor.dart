import 'package:cloud_disk_note_app/ui/ui.dart' show UI;
import 'package:cloud_disk_note_app/widget/editor/find.dart' show CodeFindPanelView;
import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:path/path.dart' as p;
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/github-dark.dart';

import '../../ui/my_fonts.dart';

const invalidLogicalKey = LogicalKeyboardKey(9999999);
final myEditorShortCuts = CodeForgeKeyboardShortcuts(
  // 禁用搜索和替换，使用我的快捷键触发
  showFindBar: const SingleActivator(
    invalidLogicalKey,
    control: true,
  ),
  showFindAndReplaceBar: const SingleActivator(
    invalidLogicalKey,
    control: true,
));

class TextEditor extends StatelessWidget {
  // 将原有的 CodeLineEditingController 替换为 CodeForgeController
  final CodeForgeController controller;
  // CodeForge 必须依赖具体的物理/虚拟文件路径来工作
  final String filePath;
  final double? fontSize;
  final void Function(String)? onChanged;
  final bool readOnly;
  final ScrollController? verticalScrollController;
  final bool softWrapEnabled;
  final bool lineNumEnabled;
  final UndoRedoController undoController;
  final FindController findController;

  const TextEditor({
    super.key,
    required this.filePath, // 外部实例化时需要传入当前打开的文件路径
    required this.controller,
    required this.undoController,
    required this.findController,
    this.fontSize,
    this.onChanged,
    this.readOnly = false,
    this.verticalScrollController,
    this.softWrapEnabled = true,
    this.lineNumEnabled = true,
  });

  // 根据文件后缀，动态为 CodeForge 匹配正确的单语言高亮
  Mode _getLanguage(String path) {
    // 给git config上排面，不过一般用不到
    // 算了，这代码大可不必，估计不会有打开gitconfig的需求
    // if(path.endsWith(".git/config") || path.endsWith(".git\\config") ||
    //   path.endsWith("/.gitconfig") || path.endsWith("\\.gitconfig")
    // ) {
    //   return langIni;
    // }

    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.md':
      case '.txt':
      case '.markdown':
        return langMarkdown;
      case '.json':
        return langJson;
      case '.html':
      case '.xml':
        return langXml;
      case '.dart':
        return langDart;
      case '.c':
      case '.h':
        return langC;
      case '.cpp':
      case '.hpp':
      case '.cc':
      case '.hh':
      case '.cxx':
      case '.hxx':
      case '.c++':
        return langCpp;
      case '.java':
        return langJava;
      case '.js':
      case '.jsx':
        return langJavascript;
      case '.kt':
        return langKotlin;
      case '.go':
        return langGo;
      case '.yaml':
      case '.yml':
        return langYaml;
      case '.rs':
        return langRust;
      case '.ini':
      case '.toml':
        return langIni;
      default:
        return langMarkdown; // 默认回退到 Markdown
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // CodeForge(
    //   // Enable/disable features
    //   enableFolding: true,        // Code folding
    //   enableGutter: true,         // Line numbers
    //   enableGutterDivider: false, // Gutter separator line(line number and content divider)
    //   enableGuideLines: true,     // Indentation guides
    //   enableLocalSuggestions: true,    // Enable or disable local word suggestions. False by default.
    //   enableKeyboardSuggestions: true // Suggestions from the OS keyboard
    //
    //   // Behavior
    //   readOnly: false,            // Read-only mode
    //   autoFocus: true,            // Auto-focus on mount
    //   lineWrap: false,            // Line wrapping
    // )
    return CodeForge(
      innerPadding: const EdgeInsets.only(top: 10, left: 10, right: 10, bottom: 60),
      lineWrap: softWrapEnabled,
      enableGutter: lineNumEnabled,
      enableGutterDivider: lineNumEnabled,
      controller: controller,
      findController: findController,
      undoController: undoController,
      verticalScrollController: verticalScrollController,
      scrollbarDecoration: const ScrollbarDecoration(thickness: 5),
      // filePath: filePath,
      readOnly: readOnly,
      language: _getLanguage(filePath), // 动态匹配语言
      editorTheme: UI.isDarkTheme() ? githubDarkTheme : githubTheme, // 保持原有主题切换
      // tabSize: 4,
      textStyle: TextStyle(
        fontFamily: myFontRegular,
        // fontFamily: myFontMono,
        // fontFamilyFallback: myFontFallbacksForMono,
        fontSize: fontSize,
      ),
      textDirection: Directionality.of(context),
      // 核心查找面板构建器
      finderBuilder: (context, finderController) {
        // 注意：如果原有的 CodeFindPanelView 内部强绑定了 re_editor 的控制器，
        // 记得将其内部改为接收 CodeForge 传出的 finderController
        return CodeFindPanelView(
          controller: finderController,
          readOnly: readOnly,
        );
      },
      // 保持搜索匹配时的文本高亮颜色
      matchHighlightStyle: MatchHighlightStyle(
        currentMatchStyle: TextStyle(
          backgroundColor: theme.colorScheme.primaryContainer,
        ),
        otherMatchStyle: TextStyle(
          backgroundColor: theme.colorScheme.secondaryContainer,
        ),
      ),
      autoFocus: true,
      keyboardShotcuts: myEditorShortCuts,
      // 输入法联想，若禁用则不会触发下划线选中文本，但是谷歌输入法会无法输入中文；
      // x fixed maybe) 若启用，有bug，联想触发时（有下划线），可能无法移动光标，甚至有可能丢失内容！
      enableKeyboardSuggestions: true,  // x fixed maybe, or never a bug, just my mistake?) ime suggestions, if enable, can be lost data on android
      enableLocalSuggestions: false, // I am not sure, maybe this is suggestions from file content context? not lsp or keyboard suggestions.
      extraLanguages: [langC, langJava, langXml, langDart, langRust],
    );
  }
}
