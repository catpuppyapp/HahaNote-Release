import 'dart:convert';
import 'dart:io';

import 'package:cloud_disk_note_app/cloud_disk_note/crypto/key_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart' show bytesToHex, concatStream;
import 'package:cryptography/cryptography.dart' show Sha256, Sha1;

import '../storage/repo/sync.dart';



Future<List<int>> sha1Stream(
  Stream<List<int>> stream, {
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  // Create a sink
  final algorithm = Sha1();
  final sink = algorithm.newHashSink();

  // Add any number of chunks
  await for(final bytes in stream) {
    throwIfInterrupted?.call();
    sink.add(bytes);
  }

  // Calculate the hash
  sink.close();
  final hash = await sink.hash();
  return hash.bytes;
}

Future<List<int>> sha256Stream(
  Stream<List<int>> stream, {
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  // Create a sink
  final algorithm = Sha256();
  final sink = algorithm.newHashSink();

  await for (final chunk in stream) {
    throwIfInterrupted?.call();
    sink.add(chunk);
  }

  // Calculate the hash
  sink.close();
  final hash = await sink.hash();

  return hash.bytes;
}

Future<List<int>> hashStream(
  Stream<List<int>> stream, {
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  return sha256Stream(stream, throwIfInterrupted: throwIfInterrupted);
}

Future<String> hashStreamToHexStr(
  Stream<List<int>> stream, {
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  return sha256StreamToHexStr(stream, throwIfInterrupted: throwIfInterrupted);
}

Future<String> sha256StreamToHexStr(
  Stream<List<int>> stream, {
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  return bytesToHex(await hashStream(stream, throwIfInterrupted: throwIfInterrupted));
}

Future<List<int>> hashStreamWithKeyData(
  KeyData keyData,
  Stream<List<int>> stream, {
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  return hashStream(
    concatStream(Stream.value(keyData.contentPadding), stream),
    throwIfInterrupted: throwIfInterrupted
  );
}

Future<List<int>> hashStrWithKeyData(
  KeyData keyData,
  String string, {
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  return hashStream(
    Stream.fromIterable([keyData.contentPadding, utf8.encode(string)]),
    throwIfInterrupted: throwIfInterrupted
  );
}


Future<List<int>> hashStr(
  String string, {
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  return hashStream(
    Stream.fromIterable([utf8.encode(string)]),
    throwIfInterrupted: throwIfInterrupted
  );
}


// 先计算下hash，看下文件是否已经存在于objects目录，
// 若存在，则不会继续压缩和加密
Future<List<int>> hashFileWithKeyData(
  KeyData keyData,
  File file, {
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  return hashStreamWithKeyData(keyData, file.openRead(), throwIfInterrupted: throwIfInterrupted);
}

Future<List<int>> hashBytesWithKeyData(
  KeyData keyData,
  List<int> bytes, {
  required ThrowIfInterrupted? throwIfInterrupted,
}) async {
  return hashStreamWithKeyData(keyData, Stream.value(bytes), throwIfInterrupted: throwIfInterrupted);
}

// Stream<List<int>> hashThenForward(
//   Stream<List<int>> data,
//   CompressedData compressedData
// ) async* {
//   // Create a sink
//   final algorithm = Sha256();
//   final sink = algorithm.newHashSink();

//   await for (final chunk in data) {
//     sink.add(chunk);
//     yield chunk;
//   }

//   // Calculate the hash
//   sink.close();
//   final hash = await sink.hash();

//   compressedData.rawDataHash = hash.bytes;
// }
