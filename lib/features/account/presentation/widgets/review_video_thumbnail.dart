import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/app_theme.dart';

/// First-frame preview of a review video (network URL or picked file).
/// The video is prepared but never played. Falls back to a dark tile
/// when the video cannot be opened. Always shows a play icon on top.
class ReviewVideoThumbnail extends StatefulWidget {
  final String? url;
  final File? file;
  final double iconSize;

  const ReviewVideoThumbnail({
    super.key,
    this.url,
    this.file,
    this.iconSize = 28,
  }) : assert((url == null) != (file == null));

  @override
  State<ReviewVideoThumbnail> createState() => _ReviewVideoThumbnailState();
}

class _ReviewVideoThumbnailState extends State<ReviewVideoThumbnail> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ReviewVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.file?.path != widget.file?.path) {
      _controller?.dispose();
      _controller = null;
      _ready = false;
      _load();
    }
  }

  Future<void> _load() async {
    final VideoPlayerController controller;
    try {
      controller = widget.file != null
          ? VideoPlayerController.file(widget.file!)
          : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
    } catch (e) {
      debugPrint('🎬 ReviewVideoThumbnail create error: $e');
      return;
    }
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || controller != _controller) return;
      setState(() => _ready = true);
    } catch (e) {
      debugPrint('🎬 ReviewVideoThumbnail load error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final size = controller?.value.size ?? Size.zero;
    final showFrame = _ready && controller != null && !size.isEmpty;

    return Container(
      color: AppColors.neutral800,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showFrame)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: VideoPlayer(controller),
              ),
            ),
          Center(
            child: Icon(
              Icons.play_circle_fill,
              size: widget.iconSize,
              color: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}
