// import 'dart:io' show File;

// import 'package:cloud_disk_note_app/cloud_disk_note/app.dart';
// import 'package:cloud_disk_note_app/cloud_disk_note/app_key.dart';
// import 'package:cloud_disk_note_app/cloud_disk_note/crypto/hash.dart';
// import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart';
// import 'package:cloud_disk_note_app/src/rust/api/simple.dart';
// import 'package:cloud_disk_note_app/src/rust/frb_generated.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_test/flutter_test.dart';

// Future<void> main() async {
//   test('Test rust sha256 and dart sha256 result same or not', () async {
//     WidgetsFlutterBinding.ensureInitialized();

//     App.initDevMode();
//     await RustLib.init();

//     final tempFile = File(r"E:\testNoteApp\gui\haha_repo_zlib_conflict_fixed\hi.txt");
//     final dartHash = bytesToHex(await hashFileWithKeyData(AppKey.keyData, tempFile));
//     final rustHash = await rustComputeSha256(path: tempFile.absolute.path, contentPadding: AppKey.keyData.contentPadding);

//     expect(dartHash == rustHash, true);
//   });
// }
