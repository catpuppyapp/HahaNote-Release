import 'package:cloud_disk_note_app/cloud_disk_note/crypto/key_data.dart';
import 'package:cloud_disk_note_app/cloud_disk_note/storage/versioning/version.dart';

abstract class Oidlize {
  Future<String> toOidStr(KeyData contentKeyData);

}

extension OidlizeExt on Oidlize {
  Future<VersionOid> toOid(KeyData contentKeyData) async {
    return VersionOid(value: await toOidStr(contentKeyData));
  }
}
