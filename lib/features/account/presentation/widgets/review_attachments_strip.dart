import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../product/presentation/widgets/fullscreen_image_viewer.dart';
import '../../data/models/review_attachment.dart';
import '../pages/review_video_player_page.dart';
import 'review_video_thumbnail.dart';

/// Thumbnails of a review's photos and videos.
/// Tap an image to zoom (all review images are swipeable),
/// tap a video to play it in-app. Renders nothing when empty.
class ReviewAttachmentsStrip extends StatelessWidget {
  final List<ReviewAttachment> attachments;

  const ReviewAttachmentsStrip({super.key, required this.attachments});

  static const double _tileSize = 56;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageUrls = [
      for (final attachment in attachments)
        if (!attachment.isVideo) attachment.url,
    ];

    var imageIndex = 0;
    final tiles = <Widget>[];
    for (var i = 0; i < attachments.length; i++) {
      final attachment = attachments[i];
      final initialIndex = attachment.isVideo ? -1 : imageIndex++;
      tiles.add(
        GestureDetector(
          key: ValueKey('review_attachment_$i'),
          onTap: () {
            if (attachment.isVideo) {
              ReviewVideoPlayerPage.navigate(context, attachment.url);
            } else {
              FullscreenImageViewer.open(
                context,
                imageUrls: imageUrls,
                initialIndex: initialIndex,
              );
            }
          },
          child: Container(
            width: _tileSize,
            height: _tileSize,
            decoration: BoxDecoration(
              color: isDark ? AppColors.neutral700 : AppColors.neutral200,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: attachment.isVideo
                ? ReviewVideoThumbnail(url: attachment.url)
                : Image.network(
                    attachment.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 22,
                        color: AppColors.neutral400,
                      ),
                    ),
                  ),
          ),
        ),
      );
    }

    return Wrap(spacing: 8, runSpacing: 8, children: tiles);
  }
}
