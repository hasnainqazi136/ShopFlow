# Review Video Thumbnails & Playable Uploads — Design

Date: 2026-09-17
Status: Approved
Builds on: `2026-09-17-review-attachments-design.md`

## Goal

1. Video attachments show a real first-frame thumbnail on the Add Review page
   and on review cards (product page, ReviewsPage).
2. A picked video can be played from the Add Review page before submitting.
3. Newly uploaded `.mov` / `.m4v` videos play on iOS.

## Root cause for (3)

The server names stored files from the MIME subtype and serves no
`Content-Type` for unknown extensions:

- Upload `data:video/quicktime;base64,...` is stored as `review/2/<hash>.quicktime`.
- `curl -sI <url>` returns `200`, `accept-ranges: bytes`, no `content-type`.
- AVFoundation check on the same bytes: `.quicktime` fails with `Cannot Open`;
  `.mov` and `.mp4` both report `playable: true`.

The same applies to `video/x-m4v` (`.x-m4v`). The backend should map MIME
types to real extensions; until then the app uploads QuickTime-family videos
as `video/mp4` (same ISO base media container family, confirmed playable).

## Decisions

| Topic | Decision |
|---|---|
| Thumbnail source | First frame via `video_player` (no new dependency) |
| Thumbnail failure | Existing dark tile with play icon |
| Local playback | `ReviewVideoPlayerPage` accepts a `File` |
| Upload MIME | `.mov` and `.m4v` encoded as `video/mp4` |
| Existing `.quicktime` uploads | Not fixable in app; need backend fix or re-upload |

## Components

### `ReviewVideoThumbnail`

New file `lib/features/account/presentation/widgets/review_video_thumbnail.dart`.

```dart
class ReviewVideoThumbnail extends StatefulWidget {
  final String? url;
  final File? file;
  final double iconSize;
  const ReviewVideoThumbnail({super.key, this.url, this.file, this.iconSize = 28})
      : assert((url == null) != (file == null));
}
```

- `initState`: create `VideoPlayerController.networkUrl` or `.file`, call
  `initialize()`, never `play()`. Any exception → error state.
- Loading: neutral800 fill + small `CircularProgressIndicator`.
- Ready: `FittedBox(fit: BoxFit.cover)` of `SizedBox(size: value.size)` with
  `VideoPlayer(controller)`, clipped by the parent tile.
- Error: neutral800 fill.
- All states overlay a centered `Icons.play_circle_fill` (white).
- `dispose` disposes the controller. Rebuilding with a different url/file
  (`didUpdateWidget`) disposes the old controller and loads the new one.

### `ReviewVideoPlayerPage`

- Constructor becomes `ReviewVideoPlayerPage({super.key, this.url, this.file})`
  with the same one-of assert.
- `navigate(BuildContext, String url)` stays; add
  `navigateFile(BuildContext, File file)`.
- `_createController` uses `.file(file)` when `file != null`.

### Add Review page

- Video tile content becomes `ReviewVideoThumbnail(file: file, iconSize: 32)`.
- Tapping a video tile (not the ×) opens `ReviewVideoPlayerPage.navigateFile`.
  Disabled while submitting. Image tiles unchanged (no tap action).
- Tile key for tap target: `ValueKey('add_review_media_open_$index')`.

### `ReviewAttachmentsStrip`

- Video tile content becomes `ReviewVideoThumbnail(url: attachment.url)`.

### `ReviewAttachmentEncoder`

- `mov` → `video/mp4`, `m4v` → `video/mp4`. `isVideoPath` unchanged in result.

## Testing

- Encoder: `mimeTypeFor('/a/clip.mov')` and `('/a/clip.m4v')` return `video/mp4`;
  encode of a `.mov` yields `data:video/mp4;base64,...`.
- `ReviewVideoThumbnail`: in widget tests the video platform is unavailable, so
  `initialize()` fails; assert the play icon still renders and no exception
  escapes.
- Add Review: tapping `add_review_media_open_1` (video) pushes
  `ReviewVideoPlayerPage`.
- Existing strip and page tests keep passing.
- Manual: pick a `.mov` on iPhone → thumbnail shows → tap plays → submit →
  approve → product page tile shows thumbnail and plays.

## Backend bug note

`Docs/backend-issues/review-attachment-video-extension.md`: repro curl,
observed extension and headers, AVFoundation result, requested fix
(map MIME → extension: `video/quicktime` → `.mov`, `video/x-m4v` → `.m4v`,
and serve correct `Content-Type`).
