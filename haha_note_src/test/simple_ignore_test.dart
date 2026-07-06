import 'package:hahanote_app/hahanote_lib_sync/simple_ignore_matcher.dart';
import 'package:glob/glob.dart';

void main() {
  final rules = [
    Glob("abc/**.txt"),  // 匹配abc及子目录下的txt文件
    Glob("*.txt"),  // 匹配当前目录下的 txt文件
    Glob("**.log"),  // 匹配任意目录下的 log文件
    Glob("build/**"),  // 匹配build目录下所有文件
    Glob("build"),  // 匹配build目录本身
    Glob("doc/*.txt"),  // 匹配doc目录下的txt文件

  ];


  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "abc/def/123.txt"));
  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "abc/def/456.txt"));
  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "abc/456.txt"));
  // assert(SimpleIgnoreMatcher.shouldIgnore(rules, "456.txt"));
  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "build/456.txt"));
  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "build"));
  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "build/abc/def/"));  // matches build/**
  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "build/abc/def"));  // matches build/**
  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "doc/abc.txt"));
  assert(!SimpleIgnoreMatcher.shouldIgnore(rules, "not_doc/abc.txt"));
  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "not_doc/abc.log"));
  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "abc.log"));
  assert(SimpleIgnoreMatcher.shouldIgnore(rules, "abc/def/abc.log"));

  assert(Glob("**.txt").matches("456.txt"));
  assert(Glob("**.txt").matches("abc/456.txt"));
  assert(!Glob("**.txt").matches("abc/456.md"));
  assert(Glob("abc/**.txt").matches("abc/456.txt"));
  assert(Glob("abc/**.txt").matches("abc//def/456.txt"));  //多个/也不报错
  assert(Glob("abc/**.txt").matches("abc/def/456.txt"));
  assert(Glob("abc/**").matches("abc/456.txt"));
  assert(Glob("abc/**").matches("abc/dir/456.txt"));


  assert(Glob(".haha_note").matches(".haha_note"));
}
