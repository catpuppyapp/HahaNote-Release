import 'package:cloud_disk_note_app/cloud_disk_note/crypto/key_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart';

abstract class RelatedOids {
  // 获取所有关联的objoid，用来清理仓库数据
  Stream<VersionOid> allRelatedObjectsOids();

  Future<String> selfOidStr(KeyData contentKeyData);
}

extension RelatedOidsExt on RelatedOids {
  // 获取自己的oid，例如 fileinfo的oid，msg的oid
  Future<VersionOid> selfOid(KeyData contentKeyData) async {
    return VersionOid(value: await selfOidStr(contentKeyData));
  }
}
