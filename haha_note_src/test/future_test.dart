Future<void> main() async {
  Future<void> task() async {
    throw "TEST ERR";
  }

  final future = task();
  try {
    await future;
  }catch(e) {
    // 会打印，await future与 await 会返回future的函数等价，都能用try...catch捕获到错误
    print("I caught the err: $e");
  }
}
