import 'package:characters/characters.dart';

extension StringExt on String {
  String removePrefix(String prefix) {
    if(startsWith(prefix)) {
      return substring(prefix.length);
    }

    return this;
  }

  String removeSuffix(String suffix) {
    if(endsWith(suffix)) {
      return substring(0, length - suffix.length);
    }

    return this;
  }

  // 包含在chars里的都视做分割符
  // 一般来说chars是单个字符，但其实不一定，比如dart 的 characters 会把 \r\n 视做一个字符
  List<String> splitByChars(List<String> chars, {bool trimAndDropEmpty = false}) {
    if(isEmpty) {
      return trimAndDropEmpty ? [] : [""];
    }

    StringBuffer sb = StringBuffer();
    final result = <String>[];
    bool cleared = false;

    void addAndClear() {
      if(trimAndDropEmpty) {
        final str = sb.toString().trim();
        if(str.isNotEmpty) {
          result.add(str);
        }
      }else {
        result.add(sb.toString());
      }

      sb.clear();

      cleared = true;
    }

    // 注意：characters会把\r\n视做同一个字符。。。。。。。。。
    for(final i in characters) {
      if(chars.contains(i)) {
        addAndClear();
      }else {
        sb.write(i);

        cleared = false;
      }
    }

    if(!cleared) {
      addAndClear();
    }

    return result;
  }

  List<String> splitByLineBreak({required bool trimAndDropEmpty}) {
    // \n 用的应该比 \r 多，所以放前面，提高匹配率
    return splitByChars(const ["\n", "\r\n", "\r"], trimAndDropEmpty: trimAndDropEmpty);
  }
}
