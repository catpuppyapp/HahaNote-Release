import 'package:flutter/widgets.dart';

extension StateExt<T extends StatefulWidget> on State<T> {
  void setStateSafe(VoidCallback fn) {
    if(!mounted) return;

    setState(fn);
  }
}
