import 'package:flutter/material.dart';

import '../bean/bean.dart';
import 'net_img.dart';

Widget doubleScrollableLine(
  String line1Text,
  String line2Text, {
  String? line1HeadingIconUrl,
  String? line2HeadingIconUrl,
  Widget? trailingIcon,
  Widget? line1Widget,
  Widget? line2Widget,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              line1Widget ?? singleScrollableRow(line1Text, headingIconUrl: line1HeadingIconUrl, textStyle: const TextStyle(fontSize: 18)),
              line2Widget ?? singleScrollableRow(
                line2Text,
                textSelectable: true,
                headingIconUrl: line2HeadingIconUrl, textStyle: TextStyle(fontSize: 16, color: Colors.grey[700]),
              ),
            ],
          ),
        ),

        if(trailingIcon != null) trailingIcon,
      ],
    ),
  );
}

Widget singleScrollableRow(
  String text, {
  bool textSelectable = false,
  TextStyle? textStyle,
  String? headingIconUrl,
}) {
  return singleScrollableRow2(
    children: headingIconAndText(text, textSelectable: textSelectable, textStyle: textStyle, headingIconUrl: headingIconUrl),
  );
}

Widget singleScrollableRow2({
  final double spacing = 10,
  required List<Widget> children,
}) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      spacing: spacing,
      children: children,
    ),
  );
}

List<Widget> headingIconAndText(
  String text, {
  required bool textSelectable,
  required TextStyle? textStyle,
  required String? headingIconUrl,
}) {
  return [
    if(headingIconUrl != null && headingIconUrl.isNotEmpty)
      NetImg(
        url: headingIconUrl,
        width: 24,
        height: 24,
        fit: BoxFit.cover,
      ),

    textSelectable ? SelectableText(text, style: textStyle) : Text(text, style: textStyle)
  ];
}

Widget singleScrollableLabelValueRow(
  LabelValue item, {
  required bool textSelectable,
}) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      spacing: 8,
      children: [
        if(item.icon != null) Icon(item.icon, size: 15),
        ..._getLabelValueTextWidget(item, textSelectable: textSelectable),
      ],
    ),
  );
}


List<Widget> _getLabelValueTextWidget(LabelValue item, {required bool textSelectable}) {
  final textStyle = item.textStyle ?? TextStyle(fontWeight: item.valueFontWeight, color: item.valueColor);
  return headingIconAndText(item.value, textStyle: textStyle, headingIconUrl: item.headingImgUrl, textSelectable: textSelectable);
}
