
import 'dart:io' show File;

extension FileExt on File {
  Future<void> renameThenDelEmptyParent(String newPath) async {
    await rename(newPath);

    try {
      //若目录为空则会移除
      await parent.delete(recursive: false);
    }catch(_) {

    }
  }
}
