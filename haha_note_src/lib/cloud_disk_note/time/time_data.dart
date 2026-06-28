import 'dart:typed_data';

import 'package:cloud_disk_note_app/cloud_disk_note/serialization/json.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/serialization/stream.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/utils.dart';

part 'time_data.g.dart';

@myJsonSerializable
class TimeData implements ByteStream {

  // 存储这个对象所需的bytes长度
  static final bytesLength = 12;

  // utc时间戳，单位毫秒 Milliseconds
  int utcMs;  // 8 bytes, else, in year of 2038 will overflow?
  // 时区偏移量，单位 分钟 Minute
  int offsetM;  // 4 bytes


  TimeData({this.utcMs = 0, this.offsetM = 0});

  factory TimeData.fromJson(Map<String, dynamic> json) => _$TimeDataFromJson(json);

  Map<String, dynamic> toJson() => _$TimeDataToJson(this);


  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeData &&
          runtimeType == other.runtimeType &&
          utcMs == other.utcMs &&
          offsetM == other.offsetM;

  @override
  int get hashCode => Object.hash(utcMs, offsetM);


  @override
  String toString() {
    return 'TimeData{utcMs: $utcMs, offsetM: $offsetM}';
  }

  static TimeData now() {
    final now = DateTime.now();
    // ~/ 是整数除法，截断小数部分（之前是把毫秒转换成秒，所以用了整除，但现在直接存毫秒了，不用除了）
    final timeData = TimeData();
    timeData.utcMs = now.toUtc().millisecondsSinceEpoch;
    timeData.offsetM = now.timeZoneOffset.inMinutes;

    return timeData;
  }

  static TimeData fromBytes(List<int> bytes) {
    final timeData = TimeData();
    timeData.utcMs = intFromBytes(bytes, 0, 8);
    timeData.offsetM = intFromBytes(bytes, 8, 12);

    return timeData;
  }

  static Future<TimeData> fromByteStream(Stream<List<int>> bytes) async {
    final bb = BytesBuilder(copy: false);
    await for(final b in bytes) {
      bb.add(b);
    }
    final list = bb.takeBytes();

    return TimeData.fromBytes(list);
  }

  @override
  Stream<List<int>> toByteStream() async* {
    yield intToBytes(utcMs, 8);
    yield intToBytes(offsetM, 4);
  }

  // if [useLocalTimeZone] is true, follow system time zone, else use [TimeData.offsetM]
  DateTime toDateTime({bool followSystemTimeOffset = true}) {
    final DateTime dateTime;

    if(followSystemTimeOffset) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(utcMs, isUtc: false);
    }else {
      final offsetInMs = offsetM * 60 * 1000;
      dateTime = DateTime.fromMillisecondsSinceEpoch(utcMs + offsetInMs, isUtc: true);
    }

    return dateTime;
  }

  String formattedStr({bool followSystemTimeOffset = true}) {
    return formatDateTime(toDateTime(followSystemTimeOffset: followSystemTimeOffset));
  }

  static String formatDateTime(DateTime dt) {
    String _twoDigits(int n) => n.toString().padLeft(2, '0');

    // 用来作为参照，比如，如果入参dt和now年相同，则不显示年份
    final now = DateTime.now();

    StringBuffer sb = StringBuffer();
    if(dt.year != now.year) {
      sb.write(dt.year.toString());
    }

    // 月日一起显示
    final month = _twoDigits(dt.month);
    final day = _twoDigits(dt.day);
    if(month != _twoDigits(now.month) || day != _twoDigits(now.day)) {
      if(sb.isNotEmpty) {
        sb.write("-");
      }

      sb.write(month);

      sb.write("-");

      sb.write(day);
    }

    // 时分秒一起显示
    final hour = _twoDigits(dt.hour);
    final minute = _twoDigits(dt.minute);
    final second = _twoDigits(dt.second);
    if(sb.isNotEmpty) {
      sb.write(" ");
    }

    sb.write(hour);

    sb.write(":");
    sb.write(minute);

    sb.write(":");
    sb.write(second);

    return sb.toString();
  }

  static int nowInSec() {
    return TimeData.now().utcMs ~/ 1000;
  }
}
