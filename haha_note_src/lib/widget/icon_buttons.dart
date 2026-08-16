import 'package:flutter/material.dart';

// 建这个主要是为了统一inline icon的默认大小
class InlineIconButton extends StatelessWidget {
  final double iconSize;
  final VoidCallback onPressed;
  final Widget icon;

  const InlineIconButton({
    super.key,
    this.iconSize = 18,
    required this.onPressed,
    required this.icon,
  });


  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: iconSize,
      onPressed: onPressed,
      icon: icon,
    );
  }

}
