import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:glob/glob.dart';

const _TAG = "simple_ignore_matcher.dart";

class SimpleIgnoreMatcher {
  /// 检查路径是否应该被忽略
  static bool shouldIgnore(List<Glob> patterns, String path) {
    for(final pattern in patterns) {
      try {
        if(pattern.matches(path)) {
          return true;
        }
      }catch(e) {
        App.logger.debug(_TAG, "match pattern with path err: pattern=$pattern, path=$path, err=$e");
      }
    }

    return false;
  }
}
