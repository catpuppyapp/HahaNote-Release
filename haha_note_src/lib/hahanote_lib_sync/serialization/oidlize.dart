import 'package:hahanote_app/hahanote_lib_sync/crypto/key_data.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/versioning/version.dart';

abstract class Oidlize {
  Future<String> toOidStr(KeyData contentKeyData);

}

extension OidlizeExt on Oidlize {
  Future<VersionOid> toOid(KeyData contentKeyData) async {
    return VersionOid(value: await toOidStr(contentKeyData));
  }
}
