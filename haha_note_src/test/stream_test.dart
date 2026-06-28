import 'dart:async';

class ProducerConsumer<T> {
  // 单订阅：默认；若需多订阅改为 broadcast: true
  final StreamController<T> _controller = StreamController<T>();

  // 生产者调用：推送一条消息
  void push(T value) {
    if (!_controller.isClosed) _controller.add(value);
  }

  // 生产者调用：推送错误
  void pushError(Object error, [StackTrace? stackTrace]) {
    if (!_controller.isClosed) _controller.addError(error, stackTrace);
  }

  // 生产者调用：关闭流（表示没有更多数据）
  Future<void> close() => _controller.close();

  // 调用者使用 await for 订阅的 Stream
  Stream<T> get stream => _controller.stream;
}

Future<void> main() async {
  final pc = ProducerConsumer<int>();

  // 模拟生产者：每秒推送一个值，5秒后关闭
  Timer.periodic(Duration(seconds: 1), (timer) {
    final value = timer.tick;
    print('Producer: push $value');
    pc.push(value);
    if (value >= 5) {
      timer.cancel();
      pc.close();
    }
  });

  // 消费者：使用 await for 逐条接收
  await for (final v in pc.stream) {
    print('Consumer received: $v');
  }

  print('Stream closed, consumer finished.');
}
