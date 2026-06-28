import 'package:cloud_disk_note_app/cloud_disk_note/exception/exception.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/files/file_info.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/msg/msg.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart';

abstract class Mock {
  static bool enable = false;

  static void throwIfDisabled() {
    if(!enable) {
      throw AppException("Mock data disabled");
    }
  }

  static List<VersionNode> historyNodeList() {
    throwIfDisabled();

    return [
      for(var i = 0; i < 100; i++) VersionNode(oid: VersionOid.randomOid())
    ];
  }

  static List<Msg> conflictItemList() {
    throwIfDisabled();

    return [];
  }

  static List<FileInfo> recycleBinList() {
    throwIfDisabled();

    return [];
  }
}
