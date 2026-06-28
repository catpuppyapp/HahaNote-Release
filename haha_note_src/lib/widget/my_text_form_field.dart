import 'package:flutter/material.dart';

// 特点是错误文案可复制可软换行（默认的 TextFormField 超过屏幕宽度会截断）
class MyTextFormField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscureText;
  final InputDecoration? decoration;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;

  const MyTextFormField({
    super.key,
    required this.controller,
    this.obscureText = false,
    this.decoration = const InputDecoration(),
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: decoration,
      validator: validator,
      errorBuilder: (bctx, value) {
        return SelectableText(value);
      },
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}
