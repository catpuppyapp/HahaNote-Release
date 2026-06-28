import 'dart:convert';

class ByteCountingSink extends ByteConversionSink {
  int _count = 0;
  final void Function(int) _onDone;

  ByteCountingSink(this._onDone);

  @override
  void add(List<int> chunk) => _count += chunk.length;

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    // 正常来说这个函数的逻辑是 add(chunk.sublist(start, end))，
    // 即调用add 处理sublist，（还有对isLast的判断，可参考父类实现）
    // 但我们这里只需要统计大小，因此累加下count即可
    _count += (end - start);

    if(isLast) {
      close();
    }
  }

  @override
  void close() => _onDone(_count);
}
