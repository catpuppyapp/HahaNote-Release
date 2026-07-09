import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:hahanote_app/hahanote_lib_sync/app.dart';
import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/isolate_pool/jobs.dart';
import 'package:hahanote_app/main.dart' show initSubIsolate;

const _TAG = "isolate_pool.dart";


final actions = {
  "computeHash": computeHash,
  "echo": echo,
  "checkFileDeleted": checkFileDeleted,
};

class IsolatePool {
  static int hostCpuCores = 8;
  static const int maxIsolatesCount = 8;  // 由于现在上传的时候只能串行，所以就算这个设置得更高，也不一定会快多少，只是计算快了，但上传还是会拉跨
  static const int minIsolatesCount = 2;
  static int defaultIsolatePoolSize = maxIsolatesCount;

  // 1 busy，worker不可用；0 可用来执行任务
  // Map<String, int> worksBusyState = {};
  // 需要加1 个定时检查任务已经已经全部完成的isolate
  final List<SendPort?> workersSendPorts;

  // 若非null，代表线程池出错，调用者应抛出异常
  // 调用者应在使用线程池时调用 isolatePollInstance.throwIfErr() 来抛出异常。
  String? _errMsg;

  // 已完成任务数
  int _doneCount = 0;
  // 任务总数
  int _taskCount = 0;
  // 指示没更多任务需要添加了(await for时获取result，自动更新此变量）
  bool _noMoreTasks = false;
  // 已经关过流了，避免重关
  bool _closeCalled = false;
  List<Isolate> workers = [];
  bool inited = false;

  final StreamController<dynamic> _resultStreamController = StreamController<dynamic>();

  IsolatePool._({required this.workersSendPorts});

  static void initCpuCores() {
    hostCpuCores = Platform.numberOfProcessors;
    defaultIsolatePoolSize = hostCpuCores.clamp(minIsolatesCount, maxIsolatesCount);
    App.logger.debug(_TAG, "cpu cores: $hostCpuCores, default isolate pool size: $defaultIsolatePoolSize");
  }

  void throwIfErr() {
    final errMsg= _errMsg;
    if(errMsg != null) {
      throw errMsg;
    }
  }

  // 上传 libgit2 src带.git文件夹，1万5千多个文件：
  // 上传：4:31 （单线程）
  // 下载：2:15 （下载部分没并行化，所以没区别）
  // 上传：3:29 （8）
  // 下载：2:15
  // 上传：3:23 （16）
  // 下载：2:15
  // rust上传：3:11
  // dart上传：3:12
  // 8个比1个提升快1/4，16个比8个提升不大，边际效应递减？也可能是因为我的cpu只有8个核，总之暂时先用8个吧
  // 后来小于4mib的文件直接在内存处理了，上传速度提升到了2:47，下载没影响，依然2:10秒左右
  // 后来又进行了优化，小文件直接存内存，避免写入硬盘，最后上传lg2文件夹1万多个文件变成耗时1:12秒了（在电脑，手机估计还得10分钟以上）
  // 20260301 更新：后来好像又优化了代码？也可能是存在波动，反正性能又提升了，多线程上传lg2变成55秒了，然后对比了下单线程，1分39秒。
  static Future<IsolatePool> create({final int? size}) async {
    final size2 = size ?? defaultIsolatePoolSize;
    // 先填充null占位，后续会填入真实send port
    final pool = IsolatePool._(workersSendPorts: List<SendPort?>.filled(size2, null, growable: false));
    await pool.init();
    return pool;
  }

  Future<void> init() async {
    // 为实现简单，不支持重用
    if(inited) {
      throw AppException("not supported to reuse isolate pool");
    }

    inited = true;

    final ReceivePort mainReceivePort = ReceivePort();
    final msp = mainReceivePort.sendPort;

    int logLevel = App.logger.getLevel();
    bool devModeOn = App.devModeOn;

    for(var i = 0; i < workersSendPorts.length; i++) {
      final isolate = await Isolate.spawn(
        _isolateEntryPoint,
        {
          "name": i,
          "mainSp": msp,
          // 第1个Isolate负责定时向main isolate 发送检查是否关闭的msg
          "checkClose": i == 0,

          // init logger
          "logLevel": logLevel,
          "devModeOn": devModeOn,
        },
        debugName: "Isolate_pool_worker_$i",
      );

      workers.add(isolate);
    }


    // 避免main receive port关闭的代码被重复调用
    bool closed = false;
    var readyCount = 0;
    mainReceivePort.listen((m) async {
      final name = m["name"];
      if(m["type"] == "init") {
        workersSendPorts[name] = m["data"];
        readyCount++;
      }else if(m["type"] == "result") {
        // 推送给await for的调用者
        _resultStreamController.add(m["data"]);
        // 更新已完成任务数
        ++_doneCount;
      }else if(m["type"] == "checkClose") {
        if((m["force"] == true || (_noMoreTasks && _doneCount == _taskCount)) && !closed) {
          closed = true;

          _closeStream();
          // 这个如果重复调用似乎不会抛异常
          mainReceivePort.close();
        }
      }else if(m["type"] == "err") {
        // 把流关了
        msp.send({"type": "checkClose", "force": true});
        await Future.delayed(const Duration(seconds: 1)); // 等1秒，尽量等待关闭后再继续抛错误
        // 设置错误信息，调用者通过 throwIfErr() 检查并抛出异常
        _errMsg = m["msg"] ?? "sub isolate got an unknown error";

        // 注：直接在listen抛异常不会导致当前Isolate抛异常，所以，在这设置错误，在外部抛
      }
    });

    // 等待所有isolates创建完成
    while(readyCount != workersSendPorts.length) {
      if(readyCount > workersSendPorts.length) {
        throw AppException("create isolates err, expect ${workersSendPorts.length} isolates, but got: $readyCount");
      }

      await Future.delayed(const Duration(milliseconds: 50));
    }
  }



  void runComputeHashTask(List data) {
    runTaskByName("computeHash", data);
  }

  void runCheckFileDeletedTask(List data) {
    runTaskByName("checkFileDeleted", data);
  }

  void runEchoTask(dynamic data) {
    runTaskByName("echo", data);
  }

  void runTaskByName(String name, dynamic data) {
    _getAnWorker().send({"type": name, "data": data});
  }

  SendPort _getAnWorker() {
    // 不选daemon isolate所以减1
    final workerIndex = _taskCount % workersSendPorts.length;
    ++_taskCount;
    return workersSendPorts[workerIndex]!;
  }

  Future<void> terminate() async {
    // try graceful close all workers
    for(final sp in workersSendPorts) {
      try {
        sp?.send({"type": "close"});
      }catch(e, st) {
        App.logger.debug(_TAG, "send close to worker err: $e\n$st");
      }
    }

    // wait for close
    // await Future.delayed(const Duration(milliseconds: 200));

    // kill workers
    // 倒序，给优雅关闭留点时间
    // for(int i = workers.length - 1; i >= 0; i--) {
    //   try {
    //     workers[i].kill();
    //   }catch(e, st) {
    //     App.logger.debug(_TAG, "kill worker err: $e\n$st");
    //   }
    // }

    // reset workers list
    // fixed-length list, so can't clear
    // for(int i = 0; i < workersSendPorts.length; i++) {
    //   workersSendPorts[i] = null;
    // }
    //
    // workers.clear();
  }


  Stream<dynamic> results() {
    _noMoreTasks = true;
    return _resultStreamController.stream;
  }

  Future<void> _closeStream() async {
    if(_closeCalled) {
      return;
    }

    _closeCalled = true;

    try {
      if(!_resultStreamController.isClosed) {
        await _resultStreamController.close();
      }
    }catch(e, st) {
      App.logger.debug(_TAG, "close stream failed: $e\n$st");
    }
  }
}

Future<void> _isolateEntryPoint(Map initMsg) async {
  // await RustLib.init();
  await initSubIsolate();

  // 不需要联网，所以不用初始化这个
  // MyHttpOverrides.initForIsolate(userCerts);

  App.init(logLevel: initMsg["logLevel"], devModeOn: initMsg["devModeOn"]);


  final int name = initMsg["name"];  //索引
  final SendPort mainSp = initMsg["mainSp"];
  final rp = ReceivePort();
  bool closed = false;
  rp.listen((msg) async {
    final type = msg["type"];
    if(type == "computeHash" || type == "echo" || type == "checkFileDeleted") {
      try {
        final result = await actions[type]!(msg["data"]);
        // throw AppException("test throw exception, err code: 18444114!");
        // 统计done的数目和任务数目来判断是否所有任务都完成
        mainSp.send({"name": name, "type": "result", "data": result});
      }catch(e, st) {
        mainSp.send({"type": "err", "msg": "${Isolate.current.debugName ?? "subIsolate_$name"} err: $e\n$st"});
      }
    }else if(type == "close" && !closed) {
      closed = true;
      rp.close();
      Isolate.exit();
    }
  });

  final bool checkClose = initMsg["checkClose"];
  if(checkClose) {
    // 定时让main检查是否任务已经结束
    () async {
      while(!closed) {
        await Future.delayed(const Duration(milliseconds: 100));
        mainSp.send({"type": "checkClose"});
      }
    }();
  }

  mainSp.send({"name": name, "type": "init", "data": rp.sendPort});
}

