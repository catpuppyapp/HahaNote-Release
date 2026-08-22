import 'package:hahanote_app/hahanote_lib_sync/utils.dart';

import 'exception/exception.dart';

// 全局锁，用来确保同一时间只有一个仓库在同步，以及其他互斥操作
// 目前主Isolate作用域有共享变量(VirtualFile，可能还有其他，忘了)，
// 所以需要锁来避免一个任务在使用变量时另一个任务被变量值清了等问题，
// 日后改成每个task一个isolate的话，就不需要这个全局lock了，到时给每个仓库使用各自独立的锁即可（就是创建globalLock前的方案）
// 简单来说：添加全局锁，是为了避免同时同步多个仓库导致共享变量VirtualFile冲突
class GlobalLock {
  static String _owner = "";
  static String _actName = "";
  static String _actDesc = "";

  static String lock({
    String actName = "",
    String actDesc = "",
    String owner = "",
  }) {
    if(owner.isNotEmpty && owner == _owner) {
      // re-entrant lock
      // 同一所有者，重入了
      return owner;
    }

    if(_owner.isEmpty) {
      final newOwner = randomString(12);
      _owner = newOwner;
      return newOwner;
    }else {
      throw GlobalLockLockErr(owner: _owner, actName: _actName, actDesc: _actDesc);
    }
  }

  static void unlock(String owner) {
    // 没获取到锁，但在finally里调用了unlock，就会为空，noop即可
    if(owner.isEmpty) {
      return;
    }

    if(_owner != owner) {
      throw GlobalLockUnlockErr(owner: _owner, actName: _actName, actDesc: _actDesc);
    }

    _owner = "";
    _actName = "";
    _actDesc = "";
  }
}
