import 'package:hahanote_app/hahanote_lib_sync/utils.dart';
import 'package:cryptography/helpers.dart';

// generate random bytes
Future<void> main() async {
  final sb = StringBuffer("[");
  final bytes = randomBytes(32);
  final lastIdx = bytes.length - 1;
  for(final (i, b) in bytes.indexed) {
    sb.write("0x${bytesToHex([b])}");
    if(i != lastIdx) {
      sb.write(", ");
    }
  }
  sb.write("]");

  print(sb.toString());
}
