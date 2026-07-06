import 'package:hahanote_app/main.dart' show defaultBackHandler;
import 'package:hahanote_app/ui/app_layout_observer.dart';
import 'package:hahanote_app/ui/ui.dart' show UI;
import 'package:flutter/material.dart';

abstract class BaseLayout {
  // static Scaffold newScaffoldWithList(
  //   BuildContext context, {
  //   String title = '',
  //   Widget? drawer,
  //   List<Widget>? actions,
  //   List<Widget>? children,
  // }) {
  //   return newScaffold(
  //     context,
  //     title: title,
  //     actions: actions,
  //     drawer: drawer,
  //     body: ListView(
  //       padding: EdgeInsets.all(UI.defaultScreenPadding),
  //       children: children ?? [],
  //     ),
  //   );
  // }

  static Widget newScaffoldWithScrollableColumn(
    BuildContext context, {
    List<Widget>? actions,
    Widget? drawer,
    String title = '',
    List<Widget>? children,
  }) {
    return newScaffold(
      context,
      title: title,
      actions: actions,
      drawer: drawer,
      body: Expanded(
        child: SingleChildScrollView(
          child: getPaddingColumn(children: children),
        )
      ),
    );
  }

  static Widget newScaffoldWithColumn(
    BuildContext context, {
    String title = '',
    Widget? drawer,
    List<Widget>? actions,
    List<Widget>? children,
    Key? key,
    EdgeInsetsGeometry? padding,
  }) {
    return newScaffold(
      context,
      title: title,
      body: getPaddingColumn(
        children: children,
        padding: padding,
      ),
      drawer: drawer,
      actions: actions,
      key: key,
    );
  }

  static Widget getPaddingColumn({
    EdgeInsetsGeometry? padding,
    required List<Widget>? children,
  }) {
    return Padding(
      // 貌似 EdgeInsets 和 EdgeInsetsGeometry 没区别，后者是前者父类
      padding: padding ?? EdgeInsets.all(UI.defaultScreenPadding),
      child: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: children ?? [],
        ),
      ),
    );
  }

  static Scaffold newScaffold_deprecated(
    BuildContext context, {
    String title = '',
    required Widget body,
    List<Widget>? actions,
    Widget? drawer
  }) {
    return Scaffold(
      drawer: drawer,

      // 有bug，手机滑动，不滚
      // 如果内容被遮挡，试下 SafeArea
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            pinned: false,
            floating: true,
            snap: true,
            expandedHeight: UI.topBarHeight,
            flexibleSpace: FlexibleSpaceBar(title: Text(title)),
            backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            actions: actions,
          ),
        ],
        body: body,
      ),
    );
  }

  static Widget newScaffold(
    BuildContext context, {
    String title = '',
    List<Widget>? actions,
    Widget? drawer,
    Key? key,
    Widget? fab,
    required Widget body,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: isLandscapeLayoutNotifier,
      builder: (_, bool isLandscape, __) {
        final appBar = AppBar(
          // 若是手机，小点字，不然手机屏幕太小，多数情况下看不到几个字，标题栏就失去了意义
          title: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              title,
              style: isLandscape
                ? null
                : const TextStyle(fontSize: 15)
            )
          ),
          actions: actions,
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        );

        return Scaffold(
          key: key,
          drawer: isLandscape ? null : drawer,
          appBar: isLandscape ? null : appBar,
          floatingActionButton: fab,
          // 如果内容被遮挡，试下 SafeArea
          body: isLandscape ? Row(
            // 不然默认情况下会垂直居中
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if(drawer != null) drawer,
              // 如果有侧边栏，建议加一条优雅的垂直分割线
              if (drawer != null) UI.verticalDividerWidth1,
              Expanded(
                child: Column(
                  children: [
                    appBar,
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ) : SafeArea(child: body),
        );
      }
    );
  }

  static Widget backWrapper(
    BuildContext context, {
    // 设为假可拦截返回，否则不拦截
    bool canPop = false,
    required Future<bool> Function() onBack,
    required Widget child
  }) {
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if(didPop) return;

        // 返回false说明其没处理，继续pop，否则当作处理了，不继续pop
        if(!await onBack()) {
          defaultBackHandler(context, exit: true);
        }
      },
      child: child,
    );
  }


  // static Widget backWrapper_deprecated({
  //   required VoidCallback onBack,
  //   required Widget child
  // }) {
  //   return KeyboardListener(
  //     // BUG警告：若启用这个会导致输入框调用onChange在re-build页面时失焦
  //     // 若禁用..requestFocus()，会导致组件没拿到焦点，按esc无效可以在想要使其生效的时候手动调用requestFocus()，
  //     // 不过处理起来有点麻烦，所以先不用了
  //     focusNode: FocusNode()..requestFocus(), // 确保捕获焦点
  //     onKeyEvent: (KeyEvent event) {
  //       if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
  //         onBack();
  //       }
  //     },
  //     child: PopScope(
  //       canPop: false,
  //       onPopInvokedWithResult: (didPop, result) async {
  //         if(didPop) return;
  //         onBack();
  //       },
  //       child: child,
  //     )
  //   );
  // }

  static Widget defaultScreenPaddingContainer({
    EdgeInsets? padding,
    required Widget child
  }) {
    return Padding(
      padding: padding ?? EdgeInsetsGeometry.all(UI.defaultScreenPadding),
      child: child,
    );
  }
}
