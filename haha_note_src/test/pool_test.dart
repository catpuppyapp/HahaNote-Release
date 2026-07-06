import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/isolate_pool/isolate_pool.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';


Future<void> main() async {
  final pool = await IsolatePool.create();

  try {

    final allTasks = 2;
    for(var i = 0; i<allTasks; i++) {
      pool.runEchoTask({"data": i.toString() + "_" + randomString(4)});
    }

    int count = 0;
    await for(final r in pool.results()) {
      ++count;
      print("echo: " + r["data"]);
    }

    if(count != allTasks) {
      throw AppException("count != allTask: count: $count, allTasks: $allTasks");
    }
  }finally {
    await pool.terminate();
  }


  // int i = 0;
  // print(i++ == 0);  // true
  // print(++i == 2);  // true
  // print(i == 2);  // true
}

Future<String> task(dynamic data) async {
  return "done_${data["name"]}";
}
