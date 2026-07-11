import 'package:chewie_audio/chewie_audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:hahanote_app/hahanote_lib_sync/storage/files/file_path.dart';
import 'package:html/dom.dart' as dom;
import 'package:video_player/video_player.dart';

/// [MyAudioHtmlExtension] adds support for the <audio> tag to the flutter_html
/// library.
class MyAudioHtmlExtension extends HtmlExtension {
  final AudioControllerCallback? audioControllerCallback;
  final String basePath;

  const MyAudioHtmlExtension({
    required this.basePath,
    this.audioControllerCallback,
  });

  @override
  Set<String> get supportedTags => {"audio"};

  @override
  InlineSpan build(ExtensionContext context) {
    return WidgetSpan(
        child: AudioWidget(
          context: context,
          callback: audioControllerCallback,
          basePath: basePath,
        ));
  }
}

typedef AudioControllerCallback = void Function(
    dom.Element?, ChewieAudioController, VideoPlayerController);

/// A widget used for rendering an audio player in the HTML tree
class AudioWidget extends StatefulWidget {
  final ExtensionContext context;
  final AudioControllerCallback? callback;
  final String basePath;

  const AudioWidget({
    super.key,
    required this.context,
    this.callback,
    required this.basePath,
  });

  @override
  State<StatefulWidget> createState() => _AudioWidgetState();
}

class _AudioWidgetState extends State<AudioWidget> {
  ChewieAudioController? chewieAudioController;
  VideoPlayerController? audioController;
  late final List<String?> sources;

  @override
  void initState() {
    sources = <String?>[
      if (widget.context.attributes['src'] != null)
        widget.context.attributes['src'],
      ...ReplacedElement.parseMediaSources(widget.context.node.children),
    ];

    if (sources.isNotEmpty && sources.first != null) {
      final srcPath = sources.first!;
      audioController = srcPath.startsWith("https://") || srcPath.startsWith("http://")
        ? VideoPlayerController.networkUrl(Uri.tryParse(srcPath) ?? Uri())
        : VideoPlayerController.file(FilePath.fromString(widget.basePath+"/"+srcPath).toFile());

      chewieAudioController = ChewieAudioController(
        videoPlayerController: audioController!,
        autoPlay: widget.context.attributes['autoplay'] != null,
        looping: widget.context.attributes['loop'] != null,
        showControls: widget.context.attributes['controls'] != null,
        autoInitialize: true,
      );
      widget.callback?.call(
        widget.context.element,
        chewieAudioController!,
        audioController!,
      );
    }
    super.initState();
  }

  @override
  void dispose() {
    chewieAudioController?.dispose();
    audioController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext bContext) {
    if (sources.isEmpty || sources.first == null) {
      return const SizedBox(height: 0, width: 0);
    }

    return CssBoxWidget(
      style: widget.context.styledElement!.style,
      childIsReplaced: true,
      child: ChewieAudio(
        controller: chewieAudioController!,
      ),
    );
  }
}
