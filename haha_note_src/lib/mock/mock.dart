import 'package:hahanote_app/hahanote_lib_sync/exception/exception.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_info.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/msg/msg.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';

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
