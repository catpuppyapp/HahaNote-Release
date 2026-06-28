
Future<void> main() async {
  // try {
  //   throw "outter err";
  // }catch(_) {  // 无论这里是否catch，rethrow皆可正常工作
  //   try {
  //     throw "inner err";
  //   }catch(e) {
  //
  //   }
  //
  //   // 由于inner err被catch了，所以会throw outter err
  //   rethrow;
  // }

  // try {
  //   throw "outter err";
  // }catch(_) {
  //   try {
  //     throw "inner err";
  //   }finally {
  //     // 还是会throw outter err
  //     rethrow;
  //
  //   }
  // }

  try {
    throw "outter err";
  }catch(_) {  // 无论这里是否catch，rethrow皆可正常工作
    try {
      throw "inner err";
    }catch(e) {
      rethrow;  // 这里会throw inner error
    }

    // 由于inner err被catch了，所以会throw outter err
    rethrow;
  }
}
