
import 'dart:io' show File;
import 'dart:typed_data';

abstract class ByteStream {
  Stream<List<int>> toByteStream();

}

extension ByteStreamExt on ByteStream {
  Future<List<int>> toBytes() async {
    return toUint8List();
  }

  Future<Uint8List> toUint8List() async {
    final bb = BytesBuilder(copy: false);
    await for(final b in toByteStream()) {
      bb.add(b);
    }

    return bb.takeBytes();
  }
}


abstract class WriteToFile {
  Future<void> writeToFile(File file);
}

abstract class JsonByteStream {
  Stream<List<int>> toJsonByteStream();
}
