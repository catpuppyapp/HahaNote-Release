int i = 0;
// 两种写法等价，getter本质上是函数调用，只是个语法糖，让你不用写括号
int get test2 => ++i;
int get test {return ++i;}

Future<void> main() async {
  assert(test == 1);
  assert(test == 2);
  assert(test == 3);
  print(test); // 4
  assert(test2 == 5);
  print(test2); // 6
  return;
}
