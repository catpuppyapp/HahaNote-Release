

class AppException implements Exception {
  final String message;
  AppException([this.message = 'Unknown err']);

  @override
  String toString() => '${selfName()}: $message';

  String selfName() => 'AppException';
}

class StreamConsumedException extends AppException {
  StreamConsumedException([super.message = 'Stream already consumed']);

  @override
  String selfName() => 'StreamConsumedException';
}

class NoLoginException extends UserException {
  NoLoginException([super.message = 'Please login']);

  @override
  String selfName() => 'NoLoginException';
}

class NotVipException extends UserException {
  final int minLv;
  NotVipException({String message = 'requires vip', required this.minLv}) : super(message);

  @override
  String selfName() => 'NotVipException';
}

class VipExpiredException extends UserException {
  VipExpiredException([super.message = 'vip has expired']);

  @override
  String selfName() => 'VipExpiredException';
}

class VerifyMasterKeyFailedException extends AppException {
  final Object? data;

  VerifyMasterKeyFailedException(super.message, {this.data});

  @override
  String selfName() => 'VerifyMasterKeyFailedException';
}


class RemoteException extends AppException {
  /// 附加信息，可以是原始异常，也可以是别的
  final Object? data;

  RemoteException(super.message, {this.data});

  @override
  String selfName() => 'RemoteException';
}

class RemoteNotFoundException extends RemoteException {
  RemoteNotFoundException(super.message, {super.data});

  @override
  String selfName() => 'RemoteNotFoundException';
}

class RemoteBusyException extends AppException {
  final String actName;
  final String actDesc;

  RemoteBusyException(this.actName, this.actDesc, super.message);

  @override
  String selfName() => 'RemoteBusyException';
}


class RemoteBatchTaskException extends RemoteException {
  // 用List<Map<String, dynamic>>也行，不会报错，但是用dynamic更保险
  // List<Map<String, dynamic>> errItems;

  // 这个保险点
  List<dynamic> errItems;

  RemoteBatchTaskException(this.errItems, super.message, {super.data});

  @override
  String selfName() => 'RemoteBatchTaskException';
}


class TaskCanceledException extends AppException {
  TaskCanceledException([super.message = 'Task canceled']);

  @override
  String selfName() => 'TaskCanceledException';
}

class UserException extends AppException {
  UserException([super.message = 'User Invalid']);

  @override
  String selfName() => 'UserException';
}

class StatusDirtyException extends AppException {
  StatusDirtyException([super.message = 'Status dirty']);

  @override
  String selfName() => 'StatusDirtyException';
}

class WorkdirOverwrittenByRemote extends AppException {
  WorkdirOverwrittenByRemote([super.message = 'Workdir files were overwritten by the remote, you can re-sync after making changes again']);

  @override
  String selfName() => 'WorkdirOverwrittenByRemote';
}

class InvalidPathTypeException extends AppException {
  InvalidPathTypeException([super.message = 'Path type invalid']);

  @override
  String selfName() => 'InvalidPathTypeException';
}


class LocalNotFoundException extends AppException {
  LocalNotFoundException([super.message = 'Data Not Found in Local']);

  @override
  String selfName() => 'LocalNotFoundException';
}

class RepoBusyException extends AppException {
  String actName;
  String actDesc;

  RepoBusyException({required this.actName, required this.actDesc}) : super("Repo busy now");

  @override
  String selfName() => 'RepoBusyException';

  @override
  String toString() {
    return "Repo busy now: $actName: $actDesc";
  }
}

