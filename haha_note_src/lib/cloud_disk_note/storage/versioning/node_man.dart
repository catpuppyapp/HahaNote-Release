import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart';

abstract class NodeManage {
  // 如果添加时超过总数限制，返回被移除的节点
  VersionNode? addNode(VersionNode node);

  VersionNode curNode();
  VersionNode? lastNode();

}
