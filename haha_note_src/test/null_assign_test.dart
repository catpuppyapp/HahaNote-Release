class Abc {
  int i  = 0;
}

Future<void> main() async {
  Abc? abc;
  abc?.i = 10;  // 若是null，则不会执行赋值
  assert(abc?.i == null); // true
  print('abc: ${abc?.i}');  // null

  abc = Abc();
  abc?.i = 100;
  assert(abc?.i == 100);  // true
  print('abc: ${abc?.i}');  // 100
  return;
}
