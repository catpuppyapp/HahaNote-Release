import 'dart:io';

import 'package:cloud_disk_note_app/ui/my_fonts.dart';
import 'package:cloud_disk_note_app/util/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_html_all/flutter_html_all.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:re_highlight/styles/github-dark.dart';
import 'package:re_highlight/styles/github.dart';

import '../db/db.dart';
import '../i18n/strings.g.dart';
import '../ui/ui.dart';
import 'my_highlight_view.dart';
import 'size_adjuster.dart';

const _TAG = "markdown_html_previewer.dart";

class MarkdownHtmlPreviewer extends StatefulWidget {
  final String data;
  final String basePath;
  final void Function(String msg)? showMsg;
  final void Function(String msg)? showMsgLong;
  final bool fontSizeAdjusterCloseVisible; // if false，显示字体大小调整器时，不显示关闭按钮，上级页面控制关闭和保存时可设此值为false
  final ScrollController scrollController;

  const MarkdownHtmlPreviewer({
    super.key,
    required this.data,
    required this.basePath,
    this.showMsg,
    this.showMsgLong,
    this.fontSizeAdjusterCloseVisible = true,
    required this.scrollController,
  });

  @override
  State<MarkdownHtmlPreviewer> createState() => MarkdownHtmlPreviewerState();

}

class MarkdownHtmlPreviewerState extends State<MarkdownHtmlPreviewer> {
  bool fontSizeAdjusterVisible = false;
  double fontSize = UI.markdownPreviewerFontSizeDefault;

  @override
  void initState() {
    super.initState();

    _initFontSize();
  }

  Future<void> _initFontSize() async {
    final fontSizeFromDb = await Db.getMarkdownPreviewerFontSize();
    if(fontSizeFromDb != fontSize) {
      _setFontSize(fontSizeFromDb);
    }
  }

  void showFontSizeAdjuster() {
    setState(() {
      fontSizeAdjusterVisible = true;
    });
  }

  void _setFontSize(double value) {
    setState(() {
      fontSize = value;
    });
  }

  void saveAndCloseFontSizeAdjuster() {
    setState(() {
      fontSizeAdjusterVisible = false;
    });

    // save to db
    Db.saveMarkdownPreviewerFontSize(fontSize);
  }

  Widget _getFontSizeAdjuster() {
    final fontSizeMin = UI.markdownPreviewerFontSizeMin;
    final fontSizeMax = UI.markdownPreviewerFontSizeMax;
    return getFontSizeAdjuster(
      context,
      onMinus: fontSize <= fontSizeMin ? null : () => _setFontSize(fontSize - UI.markdownPreviewerFontSizeAdjustStep),
      onPlus: fontSize >= fontSizeMax ? null : () => _setFontSize(fontSize + UI.markdownPreviewerFontSizeAdjustStep),
      onClose: saveAndCloseFontSizeAdjuster,
      closeVisible: widget.fontSizeAdjusterCloseVisible,
    );
  }

  Widget buildContent(BuildContext context) {
    return Html(
      data: widget.data,
      extensions: [
        // 拦截图片标签 <img>
        TagExtension(
          tagsToExtend: {"img"},
          builder: (extensionContext) {
            final attributes = extensionContext.attributes;
            final src = attributes['src'];
            final uri = src != null ? Uri.tryParse(src) ?? Uri() : Uri();
            final imgAlt = attributes['alt'];
            final width = double.tryParse(attributes['width'] ?? '');
            final height = double.tryParse(attributes['height'] ?? '');
            // 用文件后缀名判断是否是svg（可能不准，但一般够用）
            final isSvg = uri.path.endsWith(".svg");

            Widget buildErrorWidget(
                BuildContext context,
                Object error,
                StackTrace? stackTrace,
                ) {
              final Widget brokenImage = Icon(
                Icons.broken_image,
              );
              final String? alt = imgAlt;
              if (alt == null || alt.isEmpty) {
                return brokenImage;
              }
              return Row(
                children: [
                  brokenImage,
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(alt),
                  )
                ],
              );
            }

            Widget? imgWidget;
            bool trueLocalFalseNet = false;
            String path = "";

            if (uri.scheme == 'http' || uri.scheme == 'https') {
              path = uri.toString();
              if(isSvg) {
                // 这种不直接return，是为了下面处理点击打开图片的事件
                imgWidget = SvgPicture.network(
                  path,
                  width: width,
                  height: height,
                  errorBuilder: buildErrorWidget,
                );
              }else {
                imgWidget = Image.network(
                  path,
                  width: width,
                  height: height,
                  errorBuilder: buildErrorWidget,
                );
              }
            } else if (uri.scheme == 'data') {
              final UriData? uriData = uri.data;
              if (uriData == null) {
                return const SizedBox.shrink();
              }
              final String mimeType = uriData.mimeType;
              if (mimeType.startsWith('image/')) {
                if(isSvg) {
                  // 这种内存中的资源不好直接打开，直接返回即可，不需要后面的点击打开事件
                  return SvgPicture.memory(
                    uriData.contentAsBytes(),
                    width: width,
                    height: height,
                    errorBuilder: buildErrorWidget,
                  );
                }else {
                  return Image.memory(
                    uriData.contentAsBytes(),
                    width: width,
                    height: height,
                    errorBuilder: buildErrorWidget,
                  );
                }
              } else if (mimeType.startsWith('text/')) {
                return Text(uriData.contentAsString());
              }
              return const SizedBox.shrink();
            } else if (uri.scheme == 'resource') {
              if(isSvg) {
                return SvgPicture.asset(
                  '${uri.host}/${uri.path}',
                  width: width,
                  height: height,
                  errorBuilder: buildErrorWidget,
                );
              }else {
                return Image.asset(
                  '${uri.host}/${uri.path}',
                  width: width,
                  height: height,
                  errorBuilder: buildErrorWidget,
                );
              }
            } else {
              trueLocalFalseNet = true;
              path = p.join(widget.basePath, uri.path);
              if(isSvg) {
                imgWidget = SvgPicture.file(
                  File(path),
                  width: width,
                  height: height,
                  errorBuilder: buildErrorWidget,
                );
              }else {
                imgWidget = Image.file(
                  File(path),
                  width: width,
                  height: height,
                  errorBuilder: buildErrorWidget,
                );
              }
            }

            if(path.isEmpty) {
              return imgWidget;
            }

            // 查询当前图片是否被a链接包裹，若是，则禁用点击打开图片，不然会屏蔽a链接
            // 1. 获取当前节点的父节点
            var parentNode = extensionContext.node.parent;
            // 2. 循环向上查找，防止中间隔了 <span> 或 <strong> 等其他标签
            while (parentNode != null) {
              if (parentNode.localName == 'a') {
                // 当前标签被a标签包裹，直接返回
                return imgWidget;
              }
              parentNode = parentNode.parent; // 继续向上追溯
            }

            //执行到这代表当前标签未被a标签包裹，可添加点击事件打开文件

            // 如果img标签没被a标签包裹，则可点击img标签打开图片，否则不包裹，不然会屏蔽a链接
            return InkWell(
              onTap: () {
                if(trueLocalFalseNet) {
                  openFileInExternal(path, showMsgLong: widget.showMsgLong, callerTag: _TAG);
                }else {
                  launchUrlExtByStr(path);
                }
              },
              child: imgWidget,
            );
          },
        ),

        // 代码块语法高亮
        TagExtension(
          tagsToExtend: {"code"},
          builder: (extensionContext) {
            final codeText = extensionContext.element?.text ?? "";
            if(codeText.isEmpty) {
              return const SizedBox.shrink();
            }

            final isDarkTheme = UI.isDarkTheme();
            // inline代码块<code>content</code>
            // 大代码块 <pre><code>content</code></pre>
            // 所以需要判断下父标签是否为pre，若不是则直接返回个可复制文本即可
            final isBlockCode = extensionContext.element?.parent?.localName == 'pre';
            if(!isBlockCode) {
              return Container(
                decoration: BoxDecoration(
                  color: isDarkTheme ? Colors.white24 : Colors.black12,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  // 不要使用 SelectableText，因为外部包了可复制容器，若用 SelectableText 在这又会独立出一个可复制区域，不好
                  child: Text(
                    codeText,
                    style: TextStyle(color: isDarkTheme ? Color(0xdfd1d1d1): Colors.black87).toMono(),
                  ),
                ),
              );
            }

            // 2. 尝试从 class 属性（如 class="language-dart"）中提取编程语言
            String language = "text"; // 默认普通文本
            final classAttr = extensionContext.attributes["class"] ?? "";
            if (classAttr.contains("language-")) {
              language = classAttr.split("language-").last;
            }


            // 取主题
            final codeTheme = isDarkTheme ? githubDarkTheme : githubTheme;
            final codeBgColor = codeTheme['root']?.backgroundColor ?? Colors.grey[100];
            final codeFgColor = codeTheme['root']?.color ?? Colors.grey[700];

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: codeBgColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300, width: 0.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(language, style: TextStyle(color: codeFgColor)),
                        IconButton(
                          iconSize: 16,
                          color: codeFgColor,
                          onPressed: () {
                            copyText(codeText);
                            widget.showMsg?.call(t.copied);
                          },
                          icon: const Icon(Icons.copy),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 4),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal, // 必须：支持横向滚动，防止长代码手机端折行错乱
                    padding: const EdgeInsets.all(10),
                    child: MyHighlightView(
                      code: codeText,
                      language: language,
                      theme: codeTheme,
                      textStyle: isDarkTheme ? codeTextStyleDark : codeTextStyleLight,
                    ),
                  )
                ],
              ),
            );
          },
        ),

        // flutter_html包内置扩展标签
        TableHtmlExtension(),
        AudioHtmlExtension(),
        VideoHtmlExtension(),
        MathHtmlExtension(),
        // 这个必须放到我写的img标签处理器的下面，
        // 不然svg图片会被这个扩展拦截导致点svg图片不会打开对应资源（因为这个svg扩展处理器
        // 没写点击事件）
        // 这个的特点是支持直接在代码里绘制svg(虽然一般都是引用外部资源)，
        SvgHtmlExtension(),
        // markdown一般用不到Iframe，所以禁用
        // IframeHtmlExtension(),

        // support tex，reference: https://pub.dev/packages/flutter_html#tex
        // must use tex tag to wrap you content in markdown, example: <tex>i\hbar\frac{\partial}{\partial t}\Psi(\vec x,t) = -\frac{\hbar}{2m}\nabla^2\Psi(\vec x,t)+ V(\vec x)\Psi(\vec x,t)</tex>
        TagExtension(
          tagsToExtend: {"tex"},
          builder: (extensionContext) {
            return Math.tex(
              extensionContext.innerHtml,
              mathStyle: MathStyle.display,
              textStyle: extensionContext.styledElement?.style.generateTextStyle(),
              onErrorFallback: (FlutterMathException e) {
                //optionally try and correct the Tex string here
                return Text(e.message);
              },
            );
          }
        ),
      ],
      // 拦截链接点击 <a>
      onLinkTap: (url, _, __) {
        if(url == null) {
          return;
        }
        if(url.startsWith("https://") || url.startsWith("http://")) {
          launchUrlExtByStr(url);
        }
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Stack(
      // 填充可用空间
      fit: StackFit.expand,
      children: [
        SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          controller: widget.scrollController,
          child: SelectionArea(
            // MediaQuery的作用是放大字体
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(fontSize)),
              child: buildContent(context),
            ),
          ),

          // font size adjuster
        ),
        if(fontSizeAdjusterVisible) _getFontSizeAdjuster(),
      ],
    );
  }
}

