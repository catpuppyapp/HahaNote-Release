import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:hahanote_app/hahanote_lib_sync/utils.dart';
import 'package:hahanote_app/widget/media_bar.dart';

import '../hahanote_lib_sync/storage/files/file_path.dart';

/// [MyHtmlVideoAudioExtension] adds support for the <video> and <audio> tag to the flutter_html
/// library.
class MyHtmlVideoAudioExtension extends HtmlExtension {
  final bool isVideo;
  final String basePath;
  final void Function(String)? showMsg;
  final void Function(String)? showMsgLong;

  const MyHtmlVideoAudioExtension({
    required this.isVideo,
    required this.basePath,
    required this.showMsg,
    required this.showMsgLong,
  });

  @override
  Set<String> get supportedTags => isVideo ? {"video"} : {"audio"};

  @override
  InlineSpan build(ExtensionContext context) {
    return WidgetSpan(
      child: VideoAudioWidget(
        context: context,
        isVideo: isVideo,
        basePath: basePath,
        showMsg: showMsg,
        showMsgLong: showMsgLong,
      ));
  }
}

/// A widget used for rendering an audio player in the HTML tree
class VideoAudioWidget extends StatefulWidget {
  final ExtensionContext context;
  final bool isVideo;
  final String basePath;
  final void Function(String)? showMsg;
  final void Function(String)? showMsgLong;

  const VideoAudioWidget({
    super.key,
    required this.context,
    required this.isVideo,
    required this.basePath,
    required this.showMsg,
    required this.showMsgLong,
  });

  @override
  State<StatefulWidget> createState() => _VideoAudioWidgetState();
}

class _VideoAudioWidgetState extends State<VideoAudioWidget> {
  late final List<String?> sources;

  @override
  void initState() {
    super.initState();
    sources = <String?>[
      if (widget.context.attributes['src'] != null)
        widget.context.attributes['src'],
      ...ReplacedElement.parseMediaSources(widget.context.node.children),
    ];

  }

  @override
  Widget build(BuildContext bContext) {
    if (sources.isEmpty) {
      return const SizedBox.shrink();
    }

    return CssBoxWidget(
      style: widget.context.styledElement!.style,
      // 设为true代表组件可能有自己的宽度
      childIsReplaced: true,
      child: Column(
        children: [
          for(final src in sources) src == null
            ? const SizedBox.shrink()
            : MediaBar(
              path: isHttpUrl(src) ? src : FilePath.fromString(widget.basePath+"/"+src).toString(),
              headingIcon: widget.isVideo ? Icons.movie_creation_outlined : Icons.music_note_outlined,
              showMsg: widget.showMsg,
              showMsgLong: widget.showMsgLong
          ),
        ],
      ),
    );
  }
}
