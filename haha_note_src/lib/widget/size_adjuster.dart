import 'package:flutter/material.dart';

Widget getFontSizeAdjuster(
  BuildContext context, {
  required VoidCallback? onMinus,
  required VoidCallback? onPlus,
  required VoidCallback? onClose,
  bool closeVisible = true,
}) {
  return Positioned(
    bottom: 40, // 距离底部高度
    left: 0,
    right: 0,
    child: Center(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border(
            top: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
            left: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
            right: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: onMinus,
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: onPlus,
            ),
            if(closeVisible) ...[
              const SizedBox(width: 5),
              // 中间的小分割线
              Container(
                width: 1,
                height: 20,
                color: Colors.grey.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 5),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ]
          ],
        ),
      ),
    ),
  );
}
