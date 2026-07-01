import 'package:flutter/material.dart';
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';


class MyHighlightView extends StatefulWidget {
  final String code;
  final String language;
  final Map<String, TextStyle> theme;
  final TextStyle? textStyle;

  const MyHighlightView({
    super.key,
    required this.code,
    required this.language,
    required this.theme,
    required this.textStyle,
  });

  @override
  State<MyHighlightView> createState() => _MyHighlightViewState();

}

class _MyHighlightViewState extends State<MyHighlightView> {
  late final TextSpan textSpan;

  @override
  void initState() {
    super.initState();

    _renderCode();
  }

  void _renderCode() {
    // 1. 初始化 Highlight 引擎
    final highlight = Highlight();
    highlight.registerLanguages(builtinAllLanguages);

    // 2. 将代码解析为 TextSpan
    final highlightResult = highlight.highlight(code: widget.code, language: widget.language);
    final TextSpanRenderer renderer = TextSpanRenderer(widget.textStyle, widget.theme);
    highlightResult.render(renderer);
    textSpan = renderer.span ?? TextSpan();
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: textSpan,
    );
  }
}
