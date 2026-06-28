import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../ui/ui.dart';

abstract class MySvg {
  static Widget smallIcon(
    String assetPath, {
    String? semanticsLabel,
    double width = UI.smallIconSize,
    double height = UI.smallIconSize,
    ColorFilter? colorFilter,
  }) {
    return SvgPicture.asset(
      assetPath, 
      semanticsLabel: semanticsLabel,
      width: width,
      height: height,
      colorFilter: colorFilter,
    );
  }

}
