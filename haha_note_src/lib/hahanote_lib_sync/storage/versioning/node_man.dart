import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';

abstract class NodeManage {
  // 如果添加时超过总数限制，返回被移除的节点
  VersionNode? addNode(VersionNode node);

  VersionNode curNode();
  VersionNode? lastNode();

}
