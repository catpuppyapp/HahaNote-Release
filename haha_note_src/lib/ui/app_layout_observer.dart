import 'package:hahanote_app/config/app_config.dart';
import 'package:hahanote_app/util/util.dart';
import 'package:flutter/widgets.dart';

import '../config/display_mode.dart';

final ValueNotifier<bool> isLandscapeLayoutNotifier = ValueNotifier(false);


class AppLayoutObserver extends WidgetsBindingObserver {
  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    if(view == null) {
      return;
    }

    final size = view.physicalSize / view.devicePixelRatio;
    // aspectRatio = width / height
    isLandscapeLayoutNotifier.value = isLandscapeMode(size);

    // 如果是pc则保存窗口尺寸，若是手机之类的，可能只是旋转了屏幕，不必保存窗口尺寸，保存也没用
    if(isPcPlatform()) {
      AppConfig.update((it) async {
        it.windowWidth = size.width;
        it.windowHeight = size.height;
      });
    }
  }
}

bool isLandscapeLayout() {
  return isLandscapeLayoutNotifier.value;
  // return isPcPlatform();
}


// 判断是否横屏比例
bool isLandscapeMode(Size size) {
  final displayMode = AppConfig.getConfig().displayMode;
  if(displayMode != DisplayMode.auto) {
    return displayMode == DisplayMode.landscape;
  }

  // 宽度多过展开的侧栏(drawer)两倍，直接返回横屏模式
  // drawer宽度大约320，两倍即640
  if(size.width >= 640) {
    return true;
  }

  // 按比例决定横屏模式还是竖屏模式
  final aspectRatio = size.aspectRatio;
  if (aspectRatio > 1.5) {
    // 横屏
    return true;
  } else if (aspectRatio < 0.8) {
    // 窄屏模式：使用垂直布局
    return false;
  } else {
    // 横屏和竖屏之间
    return false;
  }
}
