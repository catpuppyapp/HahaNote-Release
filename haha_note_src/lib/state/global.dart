import 'package:flutter/material.dart' show ScaffoldState, GlobalKey, ScaffoldMessengerState;
import 'package:flutter/widgets.dart';

class Global {

  // 后来不用fluttertoast了，就不需要这个了
  // 传这个给MaterialApp即可在无BuildContext的情况下导航页面
  // navigatorKey.currentState?.pushNamed('/detail');
  // navigatorKey.currentState?.pop();
  //
  //  注意事项 (AI说的)
  //
  //  确保 key 已经被挂载到应用（即 MaterialApp 已构建）再调用 currentState，否则为 null。
  //  避免滥用：在可以使用 BuildContext 的地方优先用 Navigator.of(context)；navigatorKey 更适合跨层或无 context 场景。
  //  可与路由观察、嵌套路由或自定义 Navigator 配合使用来实现更复杂的导航管理
  //  （例如在顶层处理深度链接、通知跳转（需重试判断navigatorKey.currentState非null，框架就绪后再导航，或者用firebase等外部渠道推送消息，然后跳转）、全局对话框等）。
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // 用来定位scaffold组件打开和关闭drawer
  static final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

  // usage scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(content: Text('hi')));
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
}
