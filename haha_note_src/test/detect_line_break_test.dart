// Copyright (c) 2020, Instantiations, Inc. Please see the AUTHORS
// file for details. All rights reserved. Use of this source code is governed by
// a BSD-style license that can be found in the LICENSE file.

import 'dart:convert';

import 'package:hahanote_app/util/fs.dart';
import 'package:flutter_test/flutter_test.dart';
// import 'package:re_editor/re_editor.dart';


Future<void> main() async {
  test('Test detect line break', () async {
    final rChar = utf8.encode("\r");
    final nChar = utf8.encode("\n");

    expect(rChar.length, 1);
    expect(nChar.length, 1);

    expect(rChar[0], Fs.lineBreakCRByte);
    expect(nChar[0], Fs.lineBreakLfByte);

    final text1 = "abc\ndef";
    // expect(TextLineBreak.lf, await Fs.detectLineBreakOfStream(Stream.value(utf8.encode(text1))));

    final text2 = "abc\r\ndef";
    // expect(TextLineBreak.crlf, await Fs.detectLineBreakOfStream(Stream.value(utf8.encode(text2))));

    final text3 = "abc\rdef";
    // expect(TextLineBreak.cr, await Fs.detectLineBreakOfStream(Stream.value(utf8.encode(text3))));
  });

}
