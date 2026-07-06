import 'package:hahanote_app/hahanote_lib_sync/string_ext.dart';

Future<void> main() async {
  assert("".split("\n").length == 1);
  assert("".split("\n")[0] == "");
  assert(StringBuffer().toString() == "");
  var str1 = "1\n2";
  var out = str1.splitByLineBreak(trimAndDropEmpty: true);
  assert(out.length == 2);
  assert(out[0] == "1");
  assert(out[1] == "2");
  str1 = "1\r\n2";
  out = str1.splitByLineBreak(trimAndDropEmpty: true);
  assert(out.length == 2);
  assert(out[0] == "1");
  assert(out[1] == "2");
  str1 = "1\r2";
  out = str1.splitByLineBreak(trimAndDropEmpty: true);
  assert(out.length == 2);
  assert(out[0] == "1");
  assert(out[1] == "2");

  str1 = "1\n2\n";
  out = str1.splitByLineBreak(trimAndDropEmpty: true);
  assert(out.length == 2);
  assert(out[0] == "1");
  assert(out[1] == "2");

  assert("".splitByLineBreak(trimAndDropEmpty: true).length == 0);
  assert("".splitByLineBreak(trimAndDropEmpty: false).length == 1);
  assert("".splitByLineBreak(trimAndDropEmpty: false)[0] == "");
  assert(" ".splitByLineBreak(trimAndDropEmpty: false).length == 1);
  assert(" ".splitByLineBreak(trimAndDropEmpty: false)[0] == " ");
  assert("中\n文".splitByLineBreak(trimAndDropEmpty: true).length == 2);
  assert("中\n文".splitByLineBreak(trimAndDropEmpty: true)[0] == "中");
  assert("中\n文".splitByLineBreak(trimAndDropEmpty: true)[1] == "文");
}
