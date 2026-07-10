import 'package:hahanote_app/hahanote_lib_sync/utils.dart';

Future<void> main() async {
  final tasks = [task1, task2, task3, task4, task5, task6, task7, task8, task9, task10];

  try {
    // eagerError: true, throw asap
    // eagerError: false, throw when all task done
    await futureFunctionPool(tasks, max: 3, eagerError: true);
    // await futureFunctionPool(tasks, max: 3, eagerError: false);
    // await futureFunctionPool(tasks, max: 1, eagerError: false);
    // await futureFunctionPool(tasks, max: 1, eagerError: true);
    // await futureFunctionPool([task3]);
    // await futureFunctionPool([task1]);
    // await futureFunctionPool([task1], max: 0);
    // await futureFunctionPool([task1], max: -1);
    print("all completed!");  // only saw this if all task done without err
  }catch(e) {
    print("error caught: $e");
  }
}

Future task1() async {
  print("task1 running");
  return 1;
}

Future task2() async {
  print("task2 running");
  return 2;
}

Future task3() async {
  print("task3 running");
  throw "ERR: task3 error";
}

Future task4() async {
  print("task4 running");
  return 4;
}

Future task5() async {
  print("task5 running");
  return 5;
}

Future task6() async {
  print("task6 running");
  return 6;
}

Future task7() async {
  print("task7 running");
  return 7;
}

Future task8() async {
  print("task8 running");
  return 8;
}

Future task9() async {
  print("task9 running");
  return 9;
}

Future task10() async {
  print("task10 running");
  return 10;
}
