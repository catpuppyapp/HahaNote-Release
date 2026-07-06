import 'package:hahanote_app/ui/ui.dart';
import 'package:flutter/material.dart';

class TextBar extends StatelessWidget {
  final String text;

  const TextBar({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: UI.isDarkTheme() ? Colors.black87 : Colors.black26, // 在这里设置背景颜色
      ),
      child: Title(
        color: UI.isDarkTheme() ? Colors.white : Colors.grey,
        child: Padding(
          padding: EdgeInsetsGeometry.all(8),
          child: Row(children: [Text(text, style: TextStyle(fontWeight: FontWeight.bold))]),
        ),
      ),
    );
  }
}
