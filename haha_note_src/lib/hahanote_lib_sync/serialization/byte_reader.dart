import 'dart:async';

class ByteReader {
  // final Stream<List<int>> _src;
  final StreamIterator<List<int>> _it;
  final List<int> _buf = [];

  ByteReader(Stream<List<int>> src) : _it = StreamIterator(src);

  Future<void> _ensure(int n) async {
    while (_buf.length < n) {
      final has = await _it.moveNext();
      if (!has) break;
      _buf.addAll(_it.current);
    }
  }

  Future<int?> readByte() async {
    await _ensure(1);
    if (_buf.isEmpty) return null;
    return _buf.removeAt(0);
  }

  Future<List<int>?> readBytes(int n) async {
    if(n < 1) {
      return const [];
    }

    await _ensure(n);
    if (_buf.isEmpty) return null;
    final take = n <= _buf.length ? n : _buf.length;
    final out = _buf.sublist(0, take);
    _buf.removeRange(0, take);
    return out;
  }

  // 返回从当前已消费位置开始直到源流结束的 Stream<List<int>>
  Stream<List<int>> remainingStream() {
    // final controller = StreamController<List<int>>(sync: true);
    final controller = StreamController<List<int>>();

    () async {
      try {
        //添加缓冲区数据
        if (_buf.isNotEmpty) controller.add(_buf);
        //添加原始流中后续数据
        while (await _it.moveNext()) {
          final chunk = _it.current;
          if (chunk.isNotEmpty) controller.add(chunk);
        }
        await controller.close();
      } catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    }();

    return controller.stream;
  }

  // 必要时显式释放迭代器（可选）
  Future<void> cancel() async {
    try {
      while (await _it.moveNext()) {
        // drain
      }
    } catch (_) {}
  }
}
