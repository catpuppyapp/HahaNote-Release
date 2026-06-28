import 'package:cloud_disk_note_app/cloud_disk_note/storage/repo/repo.dart';

Future<void> main() async {
  final oid = "8cf061d5cff5aaee5b405b06d0b1ede14944af2fab041a108f4e415e14b2f47a";
  final expectedPath = "base/objects/8c/f0/61d5cff5aaee5b405b06d0b1ede14944af2fab041a108f4e415e14b2f47a/data.enc";
  assert(expectedPath == (Repo.getLocalRemoteObjectPathByOidStr("base", oid)).replaceAll("\\", "/"));
  assert(Repo.getLocalRemoteObjectOidStrByPath(expectedPath) == oid);
}
