import 'package:flutter/material.dart';

class NoAnimationScrollBehavior extends MaterialScrollBehavior {
  const NoAnimationScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child; // 彻底砍掉手机端边缘发光、拉伸视觉特效
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics(); // 强行让所有设备（含鼠标滚轮）到顶到底立刻卡死
  }
}

class NoAnimationScrollWrapper extends StatelessWidget {
  final Widget child;
  const NoAnimationScrollWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const NoAnimationScrollBehavior(),
      child: child,
    );
  }
}
