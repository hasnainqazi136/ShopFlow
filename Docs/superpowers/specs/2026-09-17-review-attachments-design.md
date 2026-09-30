# Review Attachments (Images & Videos) — Design

Date: 2026-09-17
Status: Approved

## Goal

Let customers attach photos and videos when writing a product review, and show
those attachments wherever reviews are listed.

API reference:
https://api-docs.bagisto.com/api/graphql-api/shop/mutations/create-product-review.html

## API contract

`createProductReview(input: createProductReviewInput!)` accepts an optional
`attachments: String`.

- Input: a **JSON-encoded string** of an array of Base64 data URIs,
  `data:{MIME};base64,{DATA}`. MIME must be `image/*` or `video/*`.
- Limit: 5 MB per decoded file. Any oversized, malformed, or undecodable item
  rejects the whole mutation.
- Output (`productReview.attachments`): JSON string of
  `[{"type":"image"|"video","url":"https://..."}]`, or `null`.
- New reviews are always `pending`, so a just-submitted review's attachments
  appear in lists only after admin approval.

## Scope

In scope:

1. Pick, preview, remove, and submit attachments on the Add Review page.
2. Show attachment thumbnails on review cards in:
   - product detail reviews (`lib/features/product/presentation/widgets/product_reviews_section.dart`)
   - account dashboard reviews (`lib/features/account/presentation/widgets/product_reviews_section.dart`)
   - My Reviews page (`lib/features/account/presentation/pages/reviews_page.dart`)
3. Full-screen image viewer and in-app video player.

Out of scope: recording video from the camera, compressing or transcoding media,
editing attachments on existing reviews.

## Decisions

| Topic | Decision |
|---|---|
| Encoding location | Repository. UI and bloc pass `File`s. |
| Max files | 5 per review |
| Max size | 5 MB per file, checked client-side before encoding |
| Sources | Gallery (`ImagePicker.pickMultipleMedia`, images + videos) and camera photo (`ImagePicker.pickImage(source: camera)`) |
| Video playback | In-app, new dependency `video_player` |
| Image viewing | Existing `FullscreenImageViewer.open` (`lib/features/product/presentation/widgets/fullscreen_image_viewer.dart`) |

## Architecture

### 1. Data layer

**`ReviewAttachment` model** — new file
`lib/features/account/data/models/review_attachment.dart`:

```dart
enum ReviewAttachmentType { image, video }

class ReviewAttachment extends Equatable {
  final ReviewAttachmentType type;
  final String url;

  /// Accepts a JSON string, a decoded List, or null.
  /// Skips entries without a non-empty url. Unknown/missing type:
  /// infer from url extension (video extensions -> video), else image.
  /// Invalid JSON -> empty list. Never throws.
  static List<ReviewAttachment> parseList(dynamic raw);
}
```

Shared by both review models (the category model imports it from the account
feature, same as the product feature already imports account widgets).

**Models**

- `account_models.dart` `ProductReview`: add
  `final List<ReviewAttachment> attachments` (default `const []`), parsed with
  `ReviewAttachment.parseList(json['attachments'])`.
- `product_model.dart` `ProductReview`: same field and parsing.

**Queries** — add `attachments` to review node selections:

- `AccountQueries.createProductReview`
- `AccountQueries.getProductReviews`
- `AccountQueries.getCustomerReviews`
- `ProductQueries` in `lib/core/graphql/queries.dart`: the `reviews` block in
  `_productDetailedCommonFragment` and the other product-detail `reviews` block
  (around line 886). Listing fragments `_productCoreFragment` and
  `_productSectionFragment` stay unchanged (ratings only, no cards).

**Encoding helper** — new file
`lib/features/account/data/utils/review_attachment_encoder.dart`:

```dart
class ReviewAttachmentEncoder {
  static const int maxFileBytes = 5 * 1024 * 1024;
  static const int maxFiles = 5;

  /// MIME from file extension. Returns null for unsupported types.
  /// Images: jpg, jpeg, png, webp, gif, heic, heif.
  /// Videos: mp4, mov, m4v, 3gp, webm, mkv.
  static String? mimeTypeFor(String path);

  /// Reads each file and returns jsonEncode([...data URIs]).
  /// Throws AccountException for unsupported type or oversized file.
  static Future<String> encode(List<File> files);
}
```

**Repository** — `AccountRepository.createProductReview` gains
`List<File> attachments = const []`. When non-empty, adds
`'attachments': await ReviewAttachmentEncoder.encode(attachments)` to the input.
When empty, the key is omitted.

### 2. Bloc

`add_review_bloc.dart`: `SubmitReview` gains `final List<File> attachments`
(default `const []`, included in `props`) and forwards it to the repository.
No other state changes; submitting already shows a spinner.

### 3. Add Review page

New section after the Review field: label "Photos & Videos" (optional) and a
horizontal row of 72×72 tiles (radius 10, border neutral200/neutral700):

- One tile per selected file, in pick order.
  - Image: `Image.file`, `BoxFit.cover`.
  - Video: neutral800 fill with centered `Icons.play_circle_fill`.
  - Top-right × button removes the file.
- Trailing "Add" tile (`Icons.add_a_photo_outlined`) while fewer than 5 files.
  Tap opens a bottom sheet with "Gallery" and "Camera".
- Page state holds `List<File> _attachments`.
- Validation on pick, per file, in order:
  1. Unsupported type → skip, snackbar `accountReviewUnsupportedFile`.
  2. Size > 5 MB → skip, snackbar `accountReviewFileTooLarge`.
  3. Would exceed 5 → keep first allowed, snackbar `accountReviewMaxFiles`.
- Picker cancel → no change. Picker platform error → snackbar
  `accountReviewPickFailed`.
- Tiles and Add tile are disabled while submitting.
- `_onSubmit` passes `_attachments` in `SubmitReview`.

### 4. Display

**`ReviewAttachmentsStrip`** — new file
`lib/features/account/presentation/widgets/review_attachments_strip.dart`.
Input: `List<ReviewAttachment>`. Renders nothing when empty. Otherwise a
wrap of 56×56 tiles (radius 8, spacing 8):

- Image: `Image.network` cover, error → broken-image icon.
- Video: dark tile with play icon.
- Tap image → `FullscreenImageViewer.open(context, imageUrls: <image urls only>,
  initialIndex: <index among images>)`.
- Tap video → `ReviewVideoPlayerPage.navigate(context, url)`.

Added below the comment text in each of the three review cards listed in Scope.

**`ReviewVideoPlayerPage`** — new file
`lib/features/account/presentation/pages/review_video_player_page.dart`.
Black scaffold, close button, `VideoPlayerController.networkUrl`.
States: loading spinner; error text `accountReviewVideoLoadFailed` with existing `commonRetry` button;
ready → `AspectRatio` video, tap toggles play/pause, bottom
`VideoProgressIndicator(allowScrubbing: true)`. Autoplay on ready. Controller
disposed on exit.

### 5. Dependencies and platform

- Add `video_player` to `pubspec.yaml`.
- iOS: camera and photo-library usage strings already exist in `Info.plist`.
- Android: `INTERNET` and `CAMERA` already declared. Gallery picking uses the
  system photo picker and needs no new permission.

### 6. Localization

New keys in all 10 `lib/l10n/app_*.arb` files, then `flutter gen-l10n`:

| Key | English |
|---|---|
| `accountReviewPhotosVideos` | Photos & Videos |
| `accountReviewAddMedia` | Add |
| `accountReviewGallery` | Gallery |
| `accountReviewCamera` | Camera |
| `accountReviewMaxFiles` | You can attach up to {count} files |
| `accountReviewFileTooLarge` | Each file must be 5 MB or smaller |
| `accountReviewUnsupportedFile` | Only images and videos are supported |
| `accountReviewPickFailed` | Could not add media. Please try again |
| `accountReviewVideoLoadFailed` | Unable to play this video |

`{count}` placeholder metadata only in `app_en.arb`.

## Error handling

- Client-side checks prevent the known server rejections (type, size, count).
- `ReviewAttachmentEncoder.encode` still re-checks and throws
  `AccountException`, so the bloc's existing error path shows a snackbar.
- Server errors (reviews disabled, invalid attachment) go through the existing
  `_extractErrorMessage` / `ErrorMapper` path. Selected files stay in the page
  so the user can retry.
- Display parsing never throws; bad attachment data renders no strip.

## Testing

- `test/review_attachment_test.dart`: `parseList` with JSON string, decoded
  list, null, invalid JSON, missing url, missing type (infer from extension).
- `test/review_attachment_encoder_test.dart`: MIME mapping; encode of temp
  files yields JSON string array of `data:image/png;base64,...`; oversized file
  and unsupported extension throw `AccountException`.
- `test/add_review_page_test.dart`: update the fake repository signature; assert
  attachments are forwarded; widget test that attachment tiles render and the
  × removes one. Test seam: `AddReviewPage` takes optional
  `@visibleForTesting List<File> initialAttachments` used to seed `_attachments`,
  so tests never call the real picker.
- Model tests: both `ProductReview.fromJson` parse `attachments`.
- Run `flutter analyze` (compare against the known ~49 baseline) and
  `flutter test`.
