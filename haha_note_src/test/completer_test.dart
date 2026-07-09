import 'dart:async';

void main() {
  // testCompleter();
  testTasks();
}

// Completer 和 Completer.sync() 的主要区别在于调用complete()函数是否是同步的，前者不是，后者是，
// 对于future.then()里的代码和await future然后执行后续代码的执行顺序没影响
void testCompleter() {
  // 示例 1: 普通 Completer(保证执行then，不保证执行c1.complete()和后续代码的时序，换句话说就是c1.complete是个不可await的异步任务，会立即返回）
  final c1 = Completer();
  c1.future.then((_) => print('普通 Completer: 任务完成'));
  c1.complete('完成');  // complete是个异步函数，所以后续代码大概率会先执行
  print('普通 Completer: 这一行会在回调之前打印');

  print('--- 分割线 ---');

  // 示例 2: Completer.sync
  final c2 = Completer.sync();
  c2.future.then((_) => print('Sync Completer: 任务完成'));
  c2.complete('完成');  // complete是个同步函数，所以后续代码在其返回后才执行
  print('Sync Completer: 这一行会在回调之后打印');
}


// 直接执行future和用microtask的区别主要在于优先级，microtask优先级更高，适合执行短时轻量任务
void testTasks() {
  print('1: 同步代码开始');

  // 放入事件队列，优先级比microtask低
  Future(() => print('A: 这是 Future (Event Queue)'));

  // 放入微任务队列
  scheduleMicrotask(() => print('B: 这是 microtask'));

  // 放入微任务队列，内部执行 scheduleMicrotask
  Future.microtask(() => print('C: 这是 Future.microtask'));

  print('2: 同步代码结束');
}
