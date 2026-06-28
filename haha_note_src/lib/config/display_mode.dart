import '../i18n/strings.g.dart';

class DisplayMode {
  static const values = [auto, portrait, landscape];
  static const auto = 0;
  static const portrait = 1;
  static const landscape = 2;

  static String toText(int displayMode) {
    if(displayMode == portrait) {
      return t.portrait;
    }

    if(displayMode == landscape) {
      return t.landscape;
    }

    return t.auto;
  }
}
