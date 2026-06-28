/// upload session，若不关闭，可能占用用户存储空间，如果上传失败，下次重新上传数据前应该先关闭之前的会话，这个和本地remote的session无关
abstract class ClosableSession {

  Future<void> recordSession();
  Future<void> removeSession();

  Future<List<dynamic>> getRecordedSessions();

  Future<void> closeUnfinishedSession();
}
