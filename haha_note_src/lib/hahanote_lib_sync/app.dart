import 'package:hahanote_app/hahanote_lib_sync/app_key.dart' show AppKey;
import 'package:hahanote_app/hahanote_lib_sync/log.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';


abstract class App {
  static bool _inited = false;
  static bool devModeOn = false;
  static final Log logger = logInstance;
  static final Log printLogger = printLogInstance;
  // after open source, remove account system, due to it waste my money
  static const bool accountSystemEnabled = false;

  // 开源后移除了账户系统，不需要这个了，空即可
  static const String emptyUserId = "";
  static const List<int> emptyUserIdBytes = [];

  static void initDevMode({bool verbose = false, String logFilePath = '', void Function(Object?) doPrint = print, final bool devModeOn = true}) {
    init(
      logLevel: verbose ? LogLevel.verbose : LogLevel.debug,
      logFilePath: logFilePath,
      doPrint: doPrint,
      devModeOn: devModeOn
    );
  }

  static void init({
    int logLevel = logLevelDebug,
    String logFilePath = '',
    void Function(Object?) doPrint = print,
    final bool devModeOn = false,
    final bool force = false,
  }) {
    if(_inited && !force) {
      return;
    }

    _inited = true;
    AppKey.init();

    App.devModeOn = devModeOn;

    final logger2 = logger;
    if(logger2 is DefaultLog) {
      logger2.logLevel = LogLevel.isValid(logLevel) ? logLevel : LogLevel.warn;
      logger2.doPrint = doPrint;
      logger2.logPrinter = Log.defaultPrinter;
      logger2.logFilePath = logFilePath;
      logger2.startWriterIsolate(caller: randomStringUnsafeButFaster(10));
    }
  }

}
