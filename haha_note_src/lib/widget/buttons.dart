import 'package:hahanote_app/ui/ui.dart';
import 'package:flutter/material.dart';

import '../constants/cons.dart';
import '../i18n/strings.g.dart';

Widget getPaddingForButton({required Widget child}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24.0),
    child: SizedBox(
      width: double.infinity,
      height: 48,
      child: child
    )
  );
}

Widget getWideButton(
  BuildContext context,
  final String text, {
  final String secondLineText = "",
  final Color? bgColor,
  final Color? firstLineTextColor,
  final VoidCallback? onPressed
}) {
  final theme = Theme.of(context);
  return FilledButton(
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      backgroundColor: bgColor ?? UI.getColorOfContainer(theme)
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(text, style: TextStyle(fontSize: 18, color: UI.firstTextColorInPrimaryColorContainer(theme))),
        if(secondLineText.isNotEmpty)
          Text(secondLineText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: UI.secondTextColorInPrimaryColorContainer(theme)))
      ],
    )
  );
}

Widget textAndDescButton(
  BuildContext context,
  String text,
  String desc, {
  double fontSizeLine1 = 16,
  double fontSizeLine2 = 12,
}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text, style: TextStyle(fontSize: fontSizeLine1),),
      Text(desc, style: TextStyle(fontSize: fontSizeLine2, color: UI.secondTextColorInPrimaryColorContainer(Theme.of(context))))
    ],
  );
}

Widget textAndDescButtonSmall(BuildContext context, String text, String desc) {
  return textAndDescButton(context, text, desc, fontSizeLine1: 14, fontSizeLine2: 11);
}

Widget getForgotPassAndRegisterButtons(
  BuildContext context, {
  bool showRegister = true,
  bool showForgotPass = true,
}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if(showRegister)
            TextButton(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    Cons.routeUserRegister,
                  );
                },
                child: Text(t.register)
            ),
          if(showForgotPass)
            TextButton(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    Cons.routeUserForgotPassword,
                  );
                },
                child: Text(t.forgotPassword)
            ),
        ],
      )
    ],
  );
}
