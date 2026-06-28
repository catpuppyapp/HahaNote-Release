import 'package:flutter/material.dart';

import '../ui/ui.dart';

class TextAndShortcut extends StatelessWidget {
  final String text;
  final String? shortcut;

  const TextAndShortcut({super.key, required this.text, this.shortcut});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(text),
        if(shortcut != null && shortcut!.isNotEmpty) Text(shortcut!, style: TextStyle(color: UI.secondaryTextColorInBlackOrWhiteContainer()))
      ],
    );
  }
}
