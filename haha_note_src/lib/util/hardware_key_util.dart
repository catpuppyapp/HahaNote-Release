import 'package:flutter/services.dart';

abstract class HardwareKeyUtil {
  static bool isShiftPressed() {
    return HardwareKeyboard.instance.isShiftPressed;
  }

  static bool isCtrlPressed() {
    return HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
  }

  static bool isAltPressed() {
    return HardwareKeyboard.instance.isAltPressed;
  }

}
