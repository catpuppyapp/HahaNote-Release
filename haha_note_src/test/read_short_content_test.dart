import 'dart:convert';

Future<void> main() async {
  final l1 = utf8.encoder.convert("abcdef我不知道");
  final l2 = utf8.encoder.convert("爱与和平");
  final str = await readShortContent(Stream.fromIterable([l1, l2]));
  print(str);
}

Future<String> readShortContent(
  Stream<List<int>> stream, {
  String? charsetName,
  int contentCharsLimit = 3,
}) async {
  try {
    final sb = StringBuffer();
    out: await for (final chunk in stream.transform(utf8.decoder)) {
      for(final line in (const LineSplitter()).convert(chunk)) {
        final trimmedLine = line.trim();
        if(trimmedLine.isEmpty) {
          continue;
        }

        sb.write('$trimmedLine\n');

        if(sb.length >= contentCharsLimit) {
          break out;
        }
      }
    }

    return sb.toString().trim();

  } catch (e) {
    print(e);
    return "";
  }
}
