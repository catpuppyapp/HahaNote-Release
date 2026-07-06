import 'dart:io' show File, FileMode;
import 'dart:isolate';

import 'package:hahanote_app/hahanote_lib_sync/utils.dart' show formatNowTimeWithOffset;

import 'app.dart';

const _TAG = "log.dart";

const resetPrintColor = '\x1B[0m';

// 仅限函数参数默认值使用这个，其他清空应使用 LogLevel.debug
const logLevelDebug = 2;

abstract class LogLevel {
  static const int err = 5;
  static const int warn = 4;
  static const int info = 3;
  static const int debug = logLevelDebug;
  static const int verbose = 1;

  static final values = [err, warn, info, debug, verbose];

  static String getStr(int level) {
    if(level == err) {
      return "ERROR";
    }else if(level == warn) {
      return "WARN";
    }else if(level == info) {
      return "INFO";
    }else if(level == debug) {
      return "DEBUG";
    }else if(level == verbose) {
      return "VERBOSE";
    }else {
      return "UNKNOWN";
    }
  }

  static bool isDebug(int level) => level < info;

  static bool isValid(int logLevel) {
    return logLevel == err || logLevel == warn || logLevel == info || logLevel == debug || logLevel == verbose;
  }
}

// 在flutter环境下，可以用 debugPrint替换print
typedef LogPrinter = Future<void> Function(int logLevel, String logMsg, {required void Function(Object?) doPrint});

abstract class Log {
  int getLevel();
  Future<void> err(String tag, Object? msg);
  Future<void> warn(String tag, Object? msg);
  Future<void> info(String tag, Object? msg);
  Future<void> debug(String tag, Object? msg);
  Future<void> verbose(String tag, Object? msg);


  static Future<void> defaultPrinter(int logLevel, String logMsg, {required void Function(Object?) doPrint}) async {
    final msg = '$logMsg$resetPrintColor';
    if(logLevel == LogLevel.err) {
      doPrint('\x1B[31m$msg');
    }else if(logLevel == LogLevel.warn) {
      doPrint('\x1B[33m$msg');
    }else if(logLevel == LogLevel.info) {
      doPrint('\x1B[38;5;208m$msg');
    }else if(logLevel == LogLevel.debug) {
      doPrint('\x1B[36m$msg');
    }else { // if(logLevel == LogLevel.verbose)
      doPrint(msg);
    }
  }
}



ReceivePort _rp = ReceivePort();
SendPort? _logWriterSp;
final DefaultLog logInstance = DefaultLog._(logLevel: LogLevel.debug, logPrinter: Log.defaultPrinter);
// 只使用 print，不写入文件的普通的logger，用最低级的日志等级，打印一切内容，用作 print 的平替（统一调用这个实例，方便日后修改）
final DefaultLog printLogInstance = DefaultLog._(logLevel: LogLevel.verbose, logPrinter: Log.defaultPrinter);
Isolate? currentLogWriterIsolate;

class DefaultLog implements Log {
  // value of `LogLevel`
  int logLevel;

  // 若指定，会把数据写入到文件
  String logFilePath;

  void Function(Object?) doPrint;
  // 构造实例时：
  // 若指定此值非null，会调用指定函数打印log；
  // 若null，不会打印log，
  // 否则会用print打印
  LogPrinter? logPrinter;
  
  DefaultLog._({required this.logLevel, this.logFilePath = '', this.logPrinter, this.doPrint = print});

  @override
  int getLevel() {
    return logLevel;
  }

  // 因为有可能重复调用，用 [caller] 在出错的时候分辨是哪个调用者导致的错误
  Future<void> startWriterIsolate({required String caller}) async {
    if(logFilePath.isEmpty) {
      return;
    }

    // 已经初始化过了，可能用户改了日志等级导致重新初始化，先杀之前isolate
    if(_logWriterSp != null || currentLogWriterIsolate != null) {
      _logWriterSp = null;
      final lastLogWriterIsolate = currentLogWriterIsolate;
      currentLogWriterIsolate = null;

      try {
        lastLogWriterIsolate?.kill(priority: Isolate.immediate);
      }catch(e, st) {
        // 一般不会出错的
        App.printLogger.debug(_TAG, "caller: $caller, kill last log writer isolate err: $e\n$st");
      }

      try {
        _rp.close();
      }catch(e, st) {
        // 一般不会出错的
        App.printLogger.debug(_TAG, "caller: $caller, close last logger receive port err: $e\n$st");
      }

      _rp = ReceivePort();
    }


    App.printLogger.debug(_TAG, "caller: $caller, starting a new log writer isolate");

    // 若不这么写，会捕获this，this不可send，报错
    final String logFilePath2 = logFilePath;
    // 启动子线程，写入内容到文件
    currentLogWriterIsolate = await Isolate.spawn((SendPort parentSp) async {
      final logFile = File(logFilePath2);
      if(!logFile.existsSync()) {
        logFile.parent.createSync(recursive: true);
      }


      final subRp = ReceivePort();
      parentSp.send(subRp.sendPort);

      final logWriter = await logFile.open(mode: FileMode.append);
      subRp.listen((msg) {
        logWriter.writeStringSync(msg.toString());
        logWriter.flushSync();
      });

    }, _rp.sendPort);


    _rp.listen((m) {
      if(m is SendPort) {
        _logWriterSp = m;
        App.printLogger.debug(_TAG, "caller: $caller, logger writer ready");
      }
    });

  }

  Future<void> _printLog(int level, String tag, Object? msg) async {
    //生成log msg
    final levelStr = LogLevel.getStr(level);
    final logMsg = "\n${formatNowTimeWithOffset()}    $levelStr    $tag    $msg\n";

    // 打印log
    await logPrinter?.call(level, logMsg, doPrint: doPrint);

    // 写入文件
    _logWriterSp?.send(logMsg);
  }

  @override
  Future<void> err(String tag, Object? msg) async {
    if(logLevel > LogLevel.err) {
      return;
    }

    await _printLog(LogLevel.err, tag, msg);
  }

  @override
  Future<void> warn(String tag, Object? msg) async {
    if(logLevel > LogLevel.warn) {
      return;
    }

    await _printLog(LogLevel.warn, tag, msg);
  }

  @override
  Future<void> info(String tag, Object? msg) async {
    if(logLevel > LogLevel.info) {
      return;
    }

    await _printLog(LogLevel.info, tag, msg);
  }

  @override
  Future<void> debug(String tag, Object? msg) async {
    if(logLevel > LogLevel.debug) {
      return;
    }

    await _printLog(LogLevel.debug, tag, msg);
  }

  @override
  Future<void> verbose(String tag, Object? msg) async {
    if(logLevel > LogLevel.verbose) {
      return;
    }

    await _printLog(LogLevel.verbose, tag, msg);
  }

}
