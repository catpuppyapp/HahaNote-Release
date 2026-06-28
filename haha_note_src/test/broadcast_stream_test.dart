import 'dart:async';

void main() async {
  // 创建可多订阅的控制器（广播流）
  final controller = StreamController<int>.broadcast();

  // 生产者：每隔 1 秒发送一次，发送 1..5 后关闭
  Timer.periodic(Duration(seconds: 1), (timer) {
    final value = timer.tick;
    print('Producer: add $value');
    controller.add(value);
    if (value >= 5) {
      timer.cancel();
      controller.close();
    }
  });

  // 订阅者 A：立即订阅
  final subA = controller.stream.listen(
        (v) => print('Subscriber A received: $v'),
    onDone: () => print('Subscriber A done'),
    onError: (e) => print('Subscriber A error: $e'),
  );

  // 订阅者 B：延迟 2.5 秒后订阅（会错过已发送的前两条）
  Future.delayed(Duration(milliseconds: 2500), () {
    controller.stream.listen(
          (v) => print('Subscriber B received: $v'),
      onDone: () => print('Subscriber B done'),
      onError: (e) => print('Subscriber B error: $e'),
    );
  });

  // 订阅者 C：使用 await for（延迟 1 秒后）
  Future.delayed(Duration(seconds: 1), () async {
    await for (final v in controller.stream) {
      print('Subscriber C (await for) received: $v');
    }
    print('Subscriber C done');
  });

  // 可选：在某个时刻取消 A 的订阅（例如 4 秒后）
  Future.delayed(Duration(seconds: 4), () {
    subA.cancel();
    print('Subscriber A cancelled');
  });

  while(true) {
    await Future.delayed(Duration(milliseconds: 500));
  }
}
