import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
import 'package:cloud_disk_note_app/i18n/strings.g.dart' show t;
import 'package:cloud_disk_note_app/widget/base_layout.dart';
import 'package:flutter/material.dart';

const _TAG = "loading.dart";

// @Deprecated("使用 Dialogs.showLoadingDialog() 替代")
// class BlockingLoading extends StatelessWidget {
//   final bool visible;
//   final Widget? child;
//   final Color barrierColor;
//   final Widget loader;
//   final Widget? text;
//   final String actionText;
//   final VoidCallback? action;
//
//   const BlockingLoading({
//     super.key,
//     required this.visible,
//     this.child,
//     this.barrierColor = const Color(0x80888888),
//     this.loader = const CircularProgressIndicator(),
//     this.text,
//     this.actionText = '',
//     this.action
//   });
//
//   @override
//   Widget build(BuildContext context) {
//     return Stack(
//       children: [
//         if (child != null) child!,
//         if (visible)
//           Positioned.fill(
//             child: Container(
//               color: barrierColor,
//               alignment: Alignment.center,
//               child: Column(
//                 mainAxisSize: MainAxisSize.max,
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   AbsorbPointer(
//                     absorbing: true,
//                     child: BaseLayout.defaultScreenPaddingContainer(
//                       child: Column(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           loader,
//                           const SizedBox(height: 5),
//                           text ?? Text(t.loading),
//                         ],
//                       )
//                     ),
//                   ),
//                   const SizedBox(height: 10),
//                   if (actionText.isNotEmpty && action != null)
//                   // 按钮不被 AbsorbPointer 屏蔽，正常可点击
//                     OutlinedButton(onPressed: action, child: Text(actionText)),
//                 ],
//               ),
//             ),
//           ),
//       ],
//     );
//   }
//
// }


Widget horizontalLoadingBar({double height = 2.0, Color? color}) {
  return SizedBox(
    height: height,
    child: LinearProgressIndicator(
      backgroundColor: (color ?? Colors.blue).withValues(alpha: 0.2),
      valueColor: AlwaysStoppedAnimation<Color>(color ?? Colors.blue),
      minHeight: height,
    ),
  );
}



Future<void> doActWithLoading({
  required String actName,
  required bool Function() isLoadingOn,
  required VoidCallback loadingOn,
  required VoidCallback loadingOff,
  void Function(Object? err)? onErr,
  required Future<void> Function() act,
}) async {
  if(isLoadingOn()) {
    return;
  }

  loadingOn();

  try {
    await act();
  }catch(e) {
    App.logger.debug(_TAG, "$actName err: $e");
    onErr?.call(e);
  }finally {
    loadingOff();
  }
}
