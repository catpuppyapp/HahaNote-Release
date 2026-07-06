import 'dart:async' show TimeoutException;
import 'dart:convert' show utf8;
import 'dart:io';
import 'dart:math';

import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/repo/sync.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/utils.dart';
import 'package:collection/collection.dart' show DeepCollectionEquality;
import 'package:cryptography/cryptography.dart' show SecureRandom;
import 'package:cryptography/helpers.dart' show randomBytes;


// const randomCharCandidates = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
// 禁用大写字母，不然如果创建文件或目录，windows和dropbox都不区分大小写，可能会出错，只要尝试次数足够多，有可能出错，就等于一定会出错，所以必须规避
const randomCharCandidates = 'abcdefghijklmnopqrstuvwxyz0123456789';
const _hexChars = [
  '0',
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  'a',
  'b',
  'c',
  'd',
  'e',
  'f'
];


Future<void> createDir(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}

// 好像没用，日后可删
// Future<bool> isDirectoryEmpty(String path) async {
//   final dir = Directory(path);
//   // 目录不存在当作空目录
//   if (!await dir.exists()) return true;
//
//   try {
//     // 只取第一个条目以避免遍历全部
//     await for (final _ in dir.list(recursive: false).take(1)) {
//       return false;
//     }
//
//     return true;
//   } catch (e) {
//     rethrow;
//   }
// }

int random(int start, int endInclusive) {
  return start +
      Random().nextInt(endInclusive - start + 1); // start <= n <= end
}

// must ensure `value` is uint32
// big edian
List<int> intToBytes(int value, int length) {
  // 可能不执行 & 也行？
  // 如果底层是直接截取低8位的话，就行。我不确定，所以&下，保险。
  if(length == 8){
    return [
      0xFF & (value >> 56),
      0xFF & (value >> 48),
      0xFF & (value >> 40),
      0xFF & (value >> 32),
      0xFF & (value >> 24),
      0xFF & (value >> 16),
      0xFF & (value >> 8),
      0xFF & value,
    ];
  }else if(length == 4) {
    return [
      0xFF & (value >> 24),
      0xFF & (value >> 16),
      0xFF & (value >> 8),
      0xFF & value,
    ];
  }else if(length == 2) {
    return [
      0xFF & (value >> 8),
      0xFF & value,
    ];
  }else if(length == 1) {
    return [0xFF & value];
  }

  throw UnsupportedError("unsupported length: $length");
}

int intFromBytes(List<int> bytes, int start, int end) {
  int result = 0;
  for(int i = start; i < end; i++) {
    result = (result << 8) | (bytes[i] & 0xff);
  }

  return result;
}

List<int> randomSalt(int length) {
  return randomBytesSafe(length);
}

List<int> randomBytesSafe(int length) {
  if(length < 1) {
    throw AppException("length must greater than 0, err code: 13187993");
  }

  // return randomBytes(length, random: SecureRandom.safe);
  // 之前是safe，后来safe被标为弃用了，库里注释建议使用defaultRandom
  return randomBytes(length, random: SecureRandom.defaultRandom);
}

// List<int> randomBytes(int length) {
//   final rng = Random.secure();
//   final b = <int>[];
//   for (var i = 0; i < length; i++) {
//     b.add(rng.nextInt(256));
//   }
//   return b;
// }


String _genRandomString(Random rand, int length, {String prefix='', String suffix = ''}) {
  StringBuffer sb = StringBuffer(prefix);
  for(var i = 0; i < length; i++) {
    sb.write(randomCharCandidates[rand.nextInt(randomCharCandidates.length)]);
  }

  sb.write(suffix);

  return sb.toString();
}

String randomString(int length, {String prefix='', String suffix = ''}) {
  return _genRandomString(Random.secure(), length, prefix: prefix, suffix: suffix);
}

String randomStringUnsafeButFaster(int length, {String prefix='', String suffix = ''}) {
  return _genRandomString(Random(), length, prefix: prefix, suffix: suffix);
}

Future<void> writeToFile(String filePath, Stream<List<int>> data) async {
  await writeStreamToFile(File(filePath), data);
}

Stream<T> concatStream<T>(Stream<T> a, Stream<T> b) async* {
  yield* a;
  yield* b;
}

List<int> bigIntToBytes(BigInt value, int length) {
  final bytes = List<int>.filled(length, 0);
  BigInt v = value;
  final ff = BigInt.from(0xff);
  for (int i = length - 1; i >= 0; i--) {
    bytes[i] = (v & ff).toInt();
    v = v >> 8;
  }
  return bytes;
}

BigInt bigIntFromBytes(List<int> bytes, int start, int end) {
  BigInt result = BigInt.zero;
  for(int i = start; i < end; i++) {
    result = (result << 8) | BigInt.from(bytes[i] & 0xff);
  }
  return result;
}


// 这个比较的范围太大了，比如：有可能传进来一个字符串和一个list比较，运行时才会报错
bool _collectionEquals(Object? b1, Object? b2) {
  return const DeepCollectionEquality().equals(b1, b2);
}

bool bytesEquals(List<int> b1, List<int> b2) {
  return _collectionEquals(b1, b2);
}

bool listEquals<T> (List<T> b1, List<T> b2) {
  return _collectionEquals(b1, b2);
}

bool mapEquals<T> (Map<String, dynamic> b1, Map<String, dynamic> b2) {
  return _collectionEquals(b1, b2);
}

// 输入字节数组，返回hex字符串，例如输入[10, 11]，返回ab
String bytesToHex(List<int> bytes) {
  final sb = StringBuffer();
  for(final x in bytes) {
    // 这个代码我也不知道怎么回事，
    // 来自： cryptography 包 的random_bytes.dart文件的 函数 randomBytesAsHexString()
    sb.write(_hexChars[x >> 4]);
    sb.write(_hexChars[0xF & x]);
  }
  return sb.toString();
}

/// 这个是拼接字符串，性能可能差点，但我没实际测试
String bytesToHex_Slow(List<int> bytes) {
  final StringBuffer buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }

  return buffer.toString();
}


/// return hex list like [0x0a, 0x0b]
List<String> genRandomBytesAsHexStr(int len) {
  final data = randomBytesSafe(len);
  return bytesListToHexStrList(data);
}

List<String> bytesListToHexStrList(List<int> bytes) {
  final result = <String>[];

  for(final x in bytes) {
    result.add("0x${_hexChars[x >> 4]}${_hexChars[0xF & x]}");
  }

  return result;
}


Future<String> getJsonStrFromByteStream(Stream<List<int>> byteStream) async {
  return getStrFromByteStream(byteStream);
}

Future<String> getStrFromByteStream(Stream<List<int>> byteStream) async {
  final sb = StringBuffer();

  // or `utf8.decoder.bind(byteStream)`
  await for (final chunk in byteStream.transform(utf8.decoder)) {
    sb.write(chunk);
  }

  return sb.toString();
}

/// safe rename，不会抛异常，如果成功，返回重命名后的文件，否则返回null
Future<File?> safeRename(File file, String newPath, {createParents = true}) async {
  try {
    if(!await file.exists()) {
      return null;
    }

    if(createParents) {
      await File(newPath).parent.create(recursive: true);
    }

    return await file.rename(newPath);
  }catch(e) {
    return null;
  }
}

Future<void> safeDeleteFile(File file) async {
  try {
    await file.delete();
  }catch(_) {
  }
}

Future<void> safeDeleteDir(Directory dir, {recursive = true}) async {
  try {
    await dir.delete(recursive: recursive);
  }catch(_) {
  }
}

// 创建个方法，方便替换实现
DateTime parseDateTime(String formattedTimeStr) {
  // 1. 解析字符串为 DateTime 对象
  // DateTime.parse() 方法能自动识别 ISO 8601 格式，包括末尾的 'Z' (表示 UTC)
  return DateTime.parse(formattedTimeStr);
}

String formatNowTimeWithOffset() {
  return formatTimeWithOffset(DateTime.now());
}

String formatTimeWithOffset(DateTime dt) {
  return formatTime(dt, withMs: true, withOffset: true);
}

String formatTime(DateTime dt, {bool withMs = false, bool withOffset = false}) {
  // 转为本地时间（或保持 dt 已经是本地/所需时区）
  final local = dt.toLocal();

  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');

  final y = local.year;
  final m = two(local.month);
  final d = two(local.day);
  final hh = two(local.hour);
  final mm = two(local.minute);
  final ss = two(local.second);

  String ms = '';
  if(withMs) {
    ms = three(local.millisecond);
  }

  String tz = '';
  if(withOffset) {
    // 时区偏移，DateTime.timeZoneOffset 返回 Duration
    final off = local.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final offAbs = off.abs();
    final offHours = two(offAbs.inHours.remainder(24));
    final offMinutes = two(offAbs.inMinutes.remainder(60));
    tz = 'UTC$sign$offHours${offMinutes == '00' ? '' : ':$offMinutes'}';
  }

  final result = '$y-$m-$d $hh:$mm:$ss';
  if(withMs && withOffset) {
    return '$result.$ms $tz';
  }else if(!withMs && withOffset) {
    return '$result $tz';
  }else if(withMs && !withOffset) {
    return '$result.$ms';
  }else {
    return result;
  }
}

Future<void> doInterruptibleTask<T>({
  required Future<T> task,
  ThrowIfInterrupted? throwIfInterrupted,
  Duration? duration
}) async {
  if(throwIfInterrupted == null) {
    await task;
    return;
  }

  bool done = false;

  // 用 whenComplete，不管是正常完成还是onErr都会执行回调，
  // 只是返回结果不同，如果是正常完成，返回future的结果，若是onErr，
  // 则抛出异常
  task.whenComplete(() => done = true);

  duration = duration ?? Duration(milliseconds: 500);
  while(!done) {
    try {
      // 每500毫秒检查一次会话是否已经取消
      await task.timeout(duration);
    } on TimeoutException {
      // 检查任务是否已经取消，若取消则抛异常，结束当前函数
      throwIfInterrupted.call();
    }
  }
}

Future<String> byteStreamToString(Stream<List<int>> byteStream) async {
  final sb = StringBuffer();
  await for(final str in utf8.decoder.bind(byteStream)) {
    sb.write(str);
  }
  return sb.toString();
}

bool isInvalidHostOrPort(String host, int port) {
  return host.isEmpty || isInvalidPort(port);
}

bool isInvalidPort(int? port) {
  return port == null || port < 1;
}

Future<void> futureFunctionPool(
  List<Future Function()> futuresFunctions, {
  int max = 5,
  bool eagerError = true,
}) async {
  if(max < 1) {
    throw AppException("invalid `max` value, expected `max >= 1`, but got: $max");
  }

  if(futuresFunctions.isEmpty) {
    return;
  }

  if(futuresFunctions.length == 1) {
    await futuresFunctions[0]();
    return;
  }

  // 最多执行1个任务，一个一个等，其实就是非并发执行
  if(max == 1) {
    for(final f in futuresFunctions) {
      await f();
    }

    return;
  }

  // 并发执行
  final tasks = <Future>[];
  for(final f in futuresFunctions) {
    if(tasks.length < max) {
      tasks.add(f());
    }else {
      // eagerError: true，作用是任一任务出错就立刻抛异常；
      // 否则出错时，会先执行完所有任务，然后才抛出第一个错误，后续任务若有错，会被丢弃
      await Future.wait(tasks, eagerError: eagerError);
      tasks.clear();
    }
  }

  if(tasks.isNotEmpty) {
    await Future.wait(tasks, eagerError: eagerError);
    tasks.clear();
  }

}
