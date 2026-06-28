import 'package:flutter/material.dart';

class NetImg extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit? fit;

  const NetImg({super.key, required this.url, this.width, this.height, this.fit});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        final expectedTotalBytes = loadingProgress.expectedTotalBytes;
        return Center(
          child: CircularProgressIndicator(
            value: expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / expectedTotalBytes
                : null,
          ),
        );
      },
      // 出错时显示的东西，这里实现的是出错时显示个broken image icon，也可替换成别的，例如描述文本，或什么都不显示，都行
      errorBuilder: (context, error, stackTrace) => Icon(Icons.broken_image),
    );
  }

}
