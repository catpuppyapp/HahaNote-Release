import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 一个支持部分文字可点击的 Widget
/// 使用示例：
/// ClickableTextWidget(
///   normalTextBefore: '阅读并同意 ',
///   clickableText: '服务条款',
///   normalTextAfter: ' 和 隐私政策',
///   onTapClickable: () {
///     // 点击处理：比如跳转页面或打开 url
///     print('服务条款 被点击');
///   },
///   // 可选：自定义样式
///   clickableStyle: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
/// )
class ClickableTextWidget extends StatelessWidget {
  final String normalTextBefore;
  final String clickableText;
  final String normalTextAfter;
  final VoidCallback onTapClickable;
  final TextStyle? normalStyle;
  final TextStyle? clickableStyle;

  const ClickableTextWidget({
    super.key,
    this.normalTextBefore = '',
    required this.clickableText,
    this.normalTextAfter = '',
    required this.onTapClickable,
    this.normalStyle,
    this.clickableStyle,
  });

  @override
  Widget build(BuildContext context) {
    final defaultNormal =
        normalStyle ?? TextStyle(fontSize: 14);
        // normalStyle ?? TextStyle(color: Colors.black, fontSize: 14);  //黑色文字
    final defaultClickable =
        clickableStyle ?? TextStyle(color: Colors.blue, fontSize: 14);
        // clickableStyle ?? TextStyle(color: Colors.blue, fontSize: 14, decoration: TextDecoration.underline);  //下划线版

    return RichText(
      text: TextSpan(
        children: [
          if (normalTextBefore.isNotEmpty)
            TextSpan(text: normalTextBefore, style: defaultNormal),
          TextSpan(
            text: clickableText,
            style: defaultClickable,
            recognizer: TapGestureRecognizer()..onTap = onTapClickable,
          ),
          if (normalTextAfter.isNotEmpty)
            TextSpan(text: normalTextAfter, style: defaultNormal),
        ],
      ),
    );
  }
}
