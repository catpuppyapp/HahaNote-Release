import 'package:cloud_disk_note_app/bean/bean.dart' show FileItem, Canceler;
import 'package:cloud_disk_note_app/util/fs.dart' show Fs;
import 'package:flutter/material.dart';

import '../i18n/strings.g.dart';

class FileInfoDialog extends StatefulWidget {
  final FileItem fileItem;
  const FileInfoDialog({super.key, required this.fileItem});

  @override
  State<FileInfoDialog> createState() => _FileInfoDialogState();

}

class _FileInfoDialogState extends State<FileInfoDialog> {
  String name = '';
  String path = '';
  int size = 0;
  String modified = '';
  Canceler? canceler;

  @override
  void initState() {
    super.initState();

    name = widget.fileItem.name;
    path = widget.fileItem.path.toString();
    size = widget.fileItem.size;

    () async {
      canceler = await widget.fileItem.setLastModifiedAndStartCountSize((s) {
        if(!mounted) return;

        setState(() => size = s);
      });

      if(!mounted) return;

      setState(() {
        modified = widget.fileItem.lastModified;
      });
    }();
  }

  @override
  void dispose() {
    canceler?.call();
    super.dispose();
  }


  Widget _fileInfoLine(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: SelectableText(value),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.info),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fileInfoLine(t.name, name),
          const SizedBox(height: 8),
          _fileInfoLine(t.path, path),
          const SizedBox(height: 8),
          _fileInfoLine(t.size, Fs.readableSize(size)),
          const SizedBox(height: 8),
          _fileInfoLine(t.modifiedTime, modified),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t.close))],
    );
  }
}
