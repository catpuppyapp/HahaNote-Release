
extension IetrableExt<T> on Iterable<T> {
  T? firstWhereOrElse(bool Function(T element) test, {T? Function()? orElse}) {
    for (final element in this) {
      if (test(element)) return element;
    }

    return orElse?.call();
  }

  /// 返回第一个满足 [test] 的元素；若无匹配则返回 null。
  T? firstWhereOrNull(bool Function(T element) test) {
    return firstWhereOrElse(test, orElse: () => null);
  }

  T? firstWhereOrElseIndexed(bool Function(int index, T element) test, {T? Function()? orElse}) {
    var i = 0;
    for (final element in this) {
      if (test(i, element)) return element;
      i++;
    }
    return orElse?.call();
  }

  /// 可选：提供带索引的版本
  T? firstWhereOrNullIndexed(bool Function(int index, T element) test) {
    return firstWhereOrElseIndexed(test, orElse: () => null);
  }
}
