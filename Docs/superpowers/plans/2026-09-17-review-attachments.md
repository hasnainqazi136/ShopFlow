# Review Attachments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let customers attach up to 5 photos/videos when writing a product review, and show review attachments (tap to zoom image / play video) on every review card.

**Architecture:** A pure `ReviewAttachment` model parses the server's JSON-string `attachments` field for both `ProductReview` models. A `ReviewAttachmentEncoder` turns picked `File`s into the JSON-string array of Base64 data URIs the `createProductReview` mutation expects; the repository calls it, the bloc and page only pass `File`s. A shared `ReviewAttachmentsStrip` widget renders thumbnails on three review cards and routes to the existing `FullscreenImageViewer` or a new `ReviewVideoPlayerPage`.

**Tech Stack:** Flutter 3.44 / Dart ^3.10.8, flutter_bloc + equatable, graphql_flutter, image_picker 1.2.1, photo_view (via existing viewer), new `video_player`, gen_l10n.

Spec: `Docs/superpowers/specs/2026-09-17-review-attachments-design.md`

## Global Constraints

- Server: `https://test-delivery.bagisto.com/api/graphql` (set locally in `lib/core/constants/api_constants.dart`). **Never stage or commit `lib/core/constants/api_constants.dart`** or `lib/features/category/presentation/widgets/category_banner.dart` (pre-existing local changes). Always `git add` explicit paths.
- Server schema verified: `ProductReview.attachments: String`, `createProductReviewInput.attachments: String`. `CustomerReview` (used by `getCustomerReviews`) has **no** `attachments` field: do not request it there, and do not add the strip to the account dashboard reviews section (it only shows customer reviews).
- Attachments input: JSON **string** of an array of `data:{MIME};base64,{DATA}`; MIME `image/*` or `video/*`.
- Max 5 files per review; max 5 MB (`5 * 1024 * 1024` bytes) per file.
- Omit the `attachments` key entirely when no files are attached.
- House style: events+state+bloc in one file; hand-written defensive `fromJson`; imperative `Navigator.push(MaterialPageRoute)`; every widget branches on `Theme.of(context).brightness`; Roboto inline `TextStyle`s; colors from `AppColors`.
- l10n: every new user-facing string in all 10 `lib/l10n/app_*.arb` (ar, de, en, es, fr, it, nl, ru, tr, uk); placeholder metadata only in `app_en.arb`; run `flutter gen-l10n`; commit generated `lib/l10n/app_localizations*.dart`.
- Baseline (2026-09-17, with the test server config): `flutter analyze` → `49 issues found`, 0 errors. `flutter test` → `All tests passed!` (147 tests). Neither number may get worse.
- Commit messages end with: `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`

## File Map

| File | Action | Responsibility |
|---|---|---|
| `lib/features/account/data/models/review_attachment.dart` | Create | `ReviewAttachment` model + `parseList` |
| `lib/features/account/data/utils/review_attachment_encoder.dart` | Create | MIME lookup, size/count limits, Base64 JSON encoding |
| `lib/features/account/data/models/account_models.dart` | Modify | `ProductReview.attachments` |
| `lib/features/category/data/models/product_model.dart` | Modify | `ProductReview.attachments` |
| `lib/core/graphql/account_queries.dart` | Modify | request `attachments` |
| `lib/core/graphql/queries.dart` | Modify | request `attachments` in product-detail reviews |
| `lib/features/account/data/repository/account_repository.dart` | Modify | send encoded attachments |
| `lib/features/account/presentation/bloc/add_review_bloc.dart` | Modify | `SubmitReview.attachments` |
| `lib/l10n/app_*.arb` + generated | Modify | 9 new strings |
| `pubspec.yaml`, `pubspec.lock` | Modify | `video_player` |
| `lib/features/account/presentation/pages/review_video_player_page.dart` | Create | in-app video playback |
| `lib/features/account/presentation/widgets/review_attachments_strip.dart` | Create | thumbnail strip on review cards |
| `lib/features/product/presentation/widgets/product_reviews_section.dart` | Modify | show strip |
| `lib/features/account/presentation/widgets/product_reviews_section.dart` | Modify | show strip |
| `lib/features/account/presentation/pages/reviews_page.dart` | Modify | show strip |
| `lib/features/account/presentation/pages/add_review_page.dart` | Modify | pick / preview / remove / submit media |
| `test/review_attachment_test.dart` | Create | model parsing tests |
| `test/review_attachment_encoder_test.dart` | Create | encoder tests |
| `test/review_models_attachments_test.dart` | Create | both `ProductReview.fromJson` |
| `test/create_product_review_repository_test.dart` | Create | mutation payload tests |
| `test/review_attachments_strip_test.dart` | Create | strip rendering tests |
| `test/add_review_page_test.dart` | Modify | fake signature + media section tests |

---

### Task 1: `ReviewAttachment` model

**Files:**
- Create: `lib/features/account/data/models/review_attachment.dart`
- Test: `test/review_attachment_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum ReviewAttachmentType { image, video }`
  - `class ReviewAttachment extends Equatable { final ReviewAttachmentType type; final String url; const ReviewAttachment({required this.type, required this.url}); bool get isVideo; static List<ReviewAttachment> parseList(dynamic raw); }`

- [ ] **Step 1: Write the failing test**

Create `test/review_attachment_test.dart`:

```dart
import 'package:bagisto_flutter/features/account/data/models/review_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReviewAttachment.parseList', () {
    test('parses the JSON string returned by the API', () {
      const raw =
          '[{"type":"image","url":"https://x.test/storage/review/94/photo1.webp"},'
          '{"type":"video","url":"https://x.test/storage/review/94/demo.mp4"}]';

      expect(ReviewAttachment.parseList(raw), const [
        ReviewAttachment(
          type: ReviewAttachmentType.image,
          url: 'https://x.test/storage/review/94/photo1.webp',
        ),
        ReviewAttachment(
          type: ReviewAttachmentType.video,
          url: 'https://x.test/storage/review/94/demo.mp4',
        ),
      ]);
    });

    test('parses an already decoded list', () {
      final result = ReviewAttachment.parseList([
        {'type': 'video', 'url': 'https://x.test/a.mov'},
      ]);

      expect(result.single.isVideo, isTrue);
      expect(result.single.url, 'https://x.test/a.mov');
    });

    test('returns empty for null, blank, invalid JSON and non-list JSON', () {
      expect(ReviewAttachment.parseList(null), isEmpty);
      expect(ReviewAttachment.parseList(''), isEmpty);
      expect(ReviewAttachment.parseList('not json'), isEmpty);
      expect(ReviewAttachment.parseList('{"url":"https://x.test/a.png"}'), isEmpty);
    });

    test('skips entries without a url or that are not objects', () {
      final result = ReviewAttachment.parseList([
        {'type': 'image'},
        {'type': 'image', 'url': '  '},
        'https://x.test/a.png',
        {'type': 'image', 'url': 'https://x.test/b.png'},
      ]);

      expect(result.map((a) => a.url), ['https://x.test/b.png']);
    });

    test('infers type from url extension when type is missing or unknown', () {
      final result = ReviewAttachment.parseList([
        {'url': 'https://x.test/clip.MP4?v=1'},
        {'type': 'other', 'url': 'https://x.test/photo.jpg'},
        {'type': 'video/mp4', 'url': 'https://x.test/no-extension'},
      ]);

      expect(result.map((a) => a.type), [
        ReviewAttachmentType.video,
        ReviewAttachmentType.image,
        ReviewAttachmentType.video,
      ]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/review_attachment_test.dart`
Expected: FAIL, compile error `Target of URI doesn't exist: 'package:bagisto_flutter/features/account/data/models/review_attachment.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/features/account/data/models/review_attachment.dart`:

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';

enum ReviewAttachmentType { image, video }

/// A photo or video attached to a product review.
///
/// The Bagisto API returns `attachments` as a JSON string:
/// `[{"type":"image","url":"https://..."}, {"type":"video","url":"..."}]`.
class ReviewAttachment extends Equatable {
  final ReviewAttachmentType type;
  final String url;

  const ReviewAttachment({required this.type, required this.url});

  bool get isVideo => type == ReviewAttachmentType.video;

  static const Set<String> _videoExtensions = {
    'mp4',
    'mov',
    'm4v',
    '3gp',
    'webm',
    'mkv',
  };

  /// Accepts a JSON string, an already decoded list, or null.
  /// Never throws: invalid data yields an empty list.
  static List<ReviewAttachment> parseList(dynamic raw) {
    dynamic decoded = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return const [];
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! List) return const [];

    final attachments = <ReviewAttachment>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final url = item['url']?.toString().trim() ?? '';
      if (url.isEmpty) continue;
      attachments.add(
        ReviewAttachment(
          type: _typeFor(item['type']?.toString(), url),
          url: url,
        ),
      );
    }
    return attachments;
  }

  static ReviewAttachmentType _typeFor(String? type, String url) {
    final normalized = type?.toLowerCase().trim() ?? '';
    if (normalized == 'video' || normalized.startsWith('video/')) {
      return ReviewAttachmentType.video;
    }
    if (normalized == 'image' || normalized.startsWith('image/')) {
      return ReviewAttachmentType.image;
    }
    final path = Uri.tryParse(url)?.path ?? url;
    final dot = path.lastIndexOf('.');
    final extension = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
    return _videoExtensions.contains(extension)
        ? ReviewAttachmentType.video
        : ReviewAttachmentType.image;
  }

  @override
  List<Object?> get props => [type, url];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/review_attachment_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/account/data/models/review_attachment.dart test/review_attachment_test.dart
git commit -m "feat: add ReviewAttachment model

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Review models and queries carry attachments

**Files:**
- Modify: `lib/features/account/data/models/account_models.dart` (class `ProductReview`, ~line 579)
- Modify: `lib/features/category/data/models/product_model.dart` (class `ProductReview`, ~line 1413)
- Modify: `lib/core/graphql/account_queries.dart` (`getProductReviews` ~line 72, `getCustomerReviews` ~line 101, `createProductReview` ~line 667)
- Modify: `lib/core/graphql/queries.dart` (`reviews` in `_productDetailedCommonFragment` ~line 237 and in `_productDetailedFragment` ~line 886)
- Test: `test/review_models_attachments_test.dart`

**Interfaces:**
- Consumes: `ReviewAttachment.parseList` (Task 1).
- Produces: `List<ReviewAttachment> attachments` (default `const []`) on both `ProductReview` classes.

- [ ] **Step 1: Write the failing test**

Create `test/review_models_attachments_test.dart`:

```dart
import 'package:bagisto_flutter/core/graphql/account_queries.dart';
import 'package:bagisto_flutter/core/graphql/queries.dart';
import 'package:bagisto_flutter/features/account/data/models/account_models.dart'
    as account;
import 'package:bagisto_flutter/features/account/data/models/review_attachment.dart';
import 'package:bagisto_flutter/features/category/data/models/product_model.dart'
    as category;
import 'package:flutter_test/flutter_test.dart';

const _raw =
    '[{"type":"image","url":"https://x.test/p.webp"},{"type":"video","url":"https://x.test/v.mp4"}]';

void main() {
  test('account ProductReview parses attachments', () {
    final review = account.ProductReview.fromJson({
      'id': '/api/shop/reviews/1',
      'name': 'Ann',
      'title': 'Nice',
      'rating': 5,
      'comment': 'Good',
      'attachments': _raw,
    });

    expect(review.attachments, hasLength(2));
    expect(review.attachments.last.type, ReviewAttachmentType.video);
  });

  test('account ProductReview defaults to no attachments', () {
    final review = account.ProductReview.fromJson({
      'name': 'Ann',
      'title': 'Nice',
      'rating': 5,
      'comment': 'Good',
    });

    expect(review.attachments, isEmpty);
    expect(
      const account.ProductReview(
        name: 'a',
        title: 'b',
        rating: 1,
        comment: 'c',
      ).attachments,
      isEmpty,
    );
  });

  test('category ProductReview parses attachments', () {
    final review = category.ProductReview.fromJson({
      'id': '1',
      'rating': 4,
      'attachments': _raw,
    });

    expect(review.attachments.map((a) => a.url), [
      'https://x.test/p.webp',
      'https://x.test/v.mp4',
    ]);
  });

  test('review queries request attachments', () {
    expect(AccountQueries.createProductReview, contains('attachments'));
    expect(AccountQueries.getProductReviews, contains('attachments'));
    expect(AccountQueries.getCustomerReviews, contains('attachments'));
    expect(ProductQueries.getProductByUrlKeyByType(null), contains('attachments'));
    expect(ProductQueries.getProductByUrlKey, contains('attachments'));
    expect(ProductQueries.getProductById, contains('attachments'));
  });
}
```

`getProductByUrlKeyByType` (queries.dart ~line 564) interpolates `_productDetailedCommonFragment`, so it covers the product detail page. The second `reviews` block (~line 886) lives in `_productDetailedFragment`, used by `getProductByUrlKey` and `getProductById`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/review_models_attachments_test.dart`
Expected: FAIL, compile error `The getter 'attachments' isn't defined for the type 'ProductReview'`.

- [ ] **Step 3: Implement account model**

In `lib/features/account/data/models/account_models.dart`, add import after `import 'package:equatable/equatable.dart';`:

```dart
import 'review_attachment.dart';
```

In class `ProductReview`, add the field after `final String? productImageUrl;`:

```dart
  final List<ReviewAttachment> attachments;
```

Add the constructor parameter after `this.productImageUrl,`:

```dart
    this.attachments = const [],
```

In `ProductReview.fromJson`'s `return ProductReview(` call, add after `productImageUrl: pImage,`:

```dart
      attachments: ReviewAttachment.parseList(json['attachments']),
```

- [ ] **Step 4: Implement category model**

In `lib/features/category/data/models/product_model.dart`, add after `import 'dart:developer' as developer;`:

```dart
import '../../../account/data/models/review_attachment.dart';
```

Replace the category `ProductReview` fields, constructor, and factory (keep `ratingLabel` unchanged) with:

```dart
class ProductReview {
  final String id;
  final double rating;
  final String? name;
  final String? title;
  final String? comment;
  final String? createdAt;
  final List<ReviewAttachment> attachments;

  const ProductReview({
    required this.id,
    required this.rating,
    this.name,
    this.title,
    this.comment,
    this.createdAt,
    this.attachments = const [],
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    return ProductReview(
      id: json['id']?.toString() ?? '',
      rating: (json['rating'] is int)
          ? (json['rating'] as int).toDouble()
          : (json['rating'] as double? ?? 0),
      name: json['name'] as String?,
      title: json['title'] as String?,
      comment: json['comment'] as String?,
      createdAt: json['createdAt'] as String?,
      attachments: ReviewAttachment.parseList(json['attachments']),
    );
  }
```

- [ ] **Step 5: Add `attachments` to queries**

In `lib/core/graphql/account_queries.dart`:
- `getProductReviews`: in the `node { ... }` selection, add a line `attachments` directly after `comment`.
- `getCustomerReviews`: in the review `node { ... }` selection, add `attachments` directly after `comment`.
- `createProductReview`: in `productReview { ... }`, add `attachments` directly after `comment`.

In `lib/core/graphql/queries.dart`, in both product-detail `reviews { edges { node { ... } } }` blocks (the one inside `_productDetailedCommonFragment` ~line 237 and the one ~line 886), add `attachments` directly after `comment`. Do **not** change the `reviews` blocks in `_productCoreFragment` (~line 147) or `_productSectionFragment` (~line 180).

Each edited node selection must read:

```graphql
          node {
            rating
            id
            name
            title
            comment
            attachments
            createdAt
          }
```

(For account queries keep their other existing fields; only insert the `attachments` line.)

- [ ] **Step 6: Run tests**

Run: `flutter test test/review_models_attachments_test.dart test/account_models_test.dart`
Expected: `All tests passed!`

- [ ] **Step 7: Verify against the live server**

Run (from repo root):

```bash
curl -s https://test-delivery.bagisto.com/api/graphql \
  -H 'Content-Type: application/json' \
  -H 'X-STOREFRONT-KEY: pk_storefront_SnkqmqiLsKhia28OQROyGiWH6N0puqGy' \
  -d '{"query":"{ productReviews(first: 2) { edges { node { _id title attachments } } } }"}'
```

Expected: JSON with `"data":{"productReviews":{"edges":[...]}}` and no `"errors"` key.

- [ ] **Step 8: Commit**

```bash
git add lib/features/account/data/models/account_models.dart lib/features/category/data/models/product_model.dart lib/core/graphql/account_queries.dart lib/core/graphql/queries.dart test/review_models_attachments_test.dart
git commit -m "feat: fetch and parse review attachments

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `ReviewAttachmentEncoder`

**Files:**
- Create: `lib/features/account/data/utils/review_attachment_encoder.dart`
- Test: `test/review_attachment_encoder_test.dart`

**Interfaces:**
- Consumes: `AccountException` from `lib/features/account/data/repository/account_repository.dart` (`const AccountException(String message)`).
- Produces:
  - `ReviewAttachmentEncoder.maxFileBytes` (`int`, `5 * 1024 * 1024`)
  - `ReviewAttachmentEncoder.maxFiles` (`int`, `5`)
  - `static String? mimeTypeFor(String path)`
  - `static bool isVideoPath(String path)`
  - `static Future<String> encode(List<File> files)` — throws `AccountException`

- [ ] **Step 1: Write the failing test**

Create `test/review_attachment_encoder_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:bagisto_flutter/features/account/data/repository/account_repository.dart';
import 'package:bagisto_flutter/features/account/data/utils/review_attachment_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('review_encoder'));
  tearDown(() => dir.deleteSync(recursive: true));

  File writeFile(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  test('mimeTypeFor maps supported image and video extensions', () {
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a/photo.JPG'), 'image/jpeg');
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a/photo.png'), 'image/png');
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a/photo.heic'), 'image/heic');
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a/clip.mov'), 'video/quicktime');
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a/clip.mp4'), 'video/mp4');
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a/doc.pdf'), isNull);
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a.dir/noext'), isNull);
    expect(ReviewAttachmentEncoder.isVideoPath('/a/clip.webm'), isTrue);
    expect(ReviewAttachmentEncoder.isVideoPath('/a/photo.webp'), isFalse);
  });

  test('encode returns a JSON string array of data URIs', () async {
    final png = writeFile('p.png', [1, 2, 3]);
    final mp4 = writeFile('v.mp4', [4, 5]);

    final encoded = await ReviewAttachmentEncoder.encode([png, mp4]);

    expect(encoded, isA<String>());
    expect(jsonDecode(encoded), [
      'data:image/png;base64,${base64Encode([1, 2, 3])}',
      'data:video/mp4;base64,${base64Encode([4, 5])}',
    ]);
  });

  test('encode rejects unsupported files', () async {
    final pdf = writeFile('d.pdf', [1]);

    expect(
      () => ReviewAttachmentEncoder.encode([pdf]),
      throwsA(isA<AccountException>()),
    );
  });

  test('encode rejects files larger than 5 MB', () async {
    final big = writeFile(
      'big.jpg',
      List<int>.filled(ReviewAttachmentEncoder.maxFileBytes + 1, 0),
    );

    expect(
      () => ReviewAttachmentEncoder.encode([big]),
      throwsA(isA<AccountException>()),
    );
  });

  test('encode rejects more than 5 files', () async {
    final files = List.generate(6, (i) => writeFile('p$i.png', [i]));

    expect(
      () => ReviewAttachmentEncoder.encode(files),
      throwsA(isA<AccountException>()),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/review_attachment_encoder_test.dart`
Expected: FAIL, compile error `Target of URI doesn't exist: ...review_attachment_encoder.dart`.

- [ ] **Step 3: Write the implementation**

Create `lib/features/account/data/utils/review_attachment_encoder.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import '../repository/account_repository.dart' show AccountException;

/// Builds the `attachments` value for `createProductReview`:
/// a JSON string of an array of `data:{MIME};base64,{DATA}` URIs.
class ReviewAttachmentEncoder {
  ReviewAttachmentEncoder._();

  /// Bagisto rejects any decoded file above 5 MB.
  static const int maxFileBytes = 5 * 1024 * 1024;
  static const int maxFiles = 5;

  static const Map<String, String> _mimeByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'm4v': 'video/x-m4v',
    '3gp': 'video/3gpp',
    'webm': 'video/webm',
    'mkv': 'video/x-matroska',
  };

  /// MIME type from the file extension, or null when unsupported.
  static String? mimeTypeFor(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return null;
    return _mimeByExtension[path.substring(dot + 1).toLowerCase()];
  }

  static bool isVideoPath(String path) =>
      mimeTypeFor(path)?.startsWith('video/') ?? false;

  static Future<String> encode(List<File> files) async {
    if (files.length > maxFiles) {
      throw AccountException('You can attach up to $maxFiles files');
    }

    final dataUris = <String>[];
    for (final file in files) {
      final mimeType = mimeTypeFor(file.path);
      if (mimeType == null) {
        throw const AccountException('Only images and videos are supported');
      }
      if (await file.length() > maxFileBytes) {
        throw const AccountException('Each file must be 5 MB or smaller');
      }
      final bytes = await file.readAsBytes();
      dataUris.add('data:$mimeType;base64,${base64Encode(bytes)}');
    }
    return jsonEncode(dataUris);
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/review_attachment_encoder_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/account/data/utils/review_attachment_encoder.dart test/review_attachment_encoder_test.dart
git commit -m "feat: encode review attachments as base64 data URIs

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Repository and bloc send attachments

**Files:**
- Modify: `lib/features/account/data/repository/account_repository.dart` (`createProductReview`, ~line 1001)
- Modify: `lib/features/account/presentation/bloc/add_review_bloc.dart`
- Modify: `test/add_review_page_test.dart` (fake repository override)
- Test: `test/create_product_review_repository_test.dart`

**Interfaces:**
- Consumes: `ReviewAttachmentEncoder.encode` (Task 3); `ProductReview.attachments` (Task 2).
- Produces:
  - `Future<ProductReview> AccountRepository.createProductReview({required int productId, required String title, required String comment, required int rating, required String name, List<File> attachments = const []})`
  - `SubmitReview({required int productId, required String title, required String comment, required int rating, required String name, List<File> attachments = const []})` with `final List<File> attachments`

- [ ] **Step 1: Write the failing repository test**

Create `test/create_product_review_repository_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:bagisto_flutter/features/account/data/repository/account_repository.dart';
import 'package:bagisto_flutter/features/account/presentation/bloc/add_review_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('review_repo'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('omits attachments when none are given', () async {
    Map<String, dynamic>? sent;
    final repository = _repository((body) => sent = body);

    await repository.createProductReview(
      productId: 10,
      title: 'Nice',
      comment: 'Good',
      rating: 5,
      name: 'Ann',
    );

    final input = sent!['variables']['input'] as Map<String, dynamic>;
    expect(input.containsKey('attachments'), isFalse);
    expect(sent!['query'], contains('attachments'));
  });

  test('sends attachments as a JSON string of data URIs', () async {
    Map<String, dynamic>? sent;
    final repository = _repository((body) => sent = body);
    final photo = File('${dir.path}/p.png')..writeAsBytesSync([7, 8, 9]);

    final review = await repository.createProductReview(
      productId: 10,
      title: 'Nice',
      comment: 'Good',
      rating: 5,
      name: 'Ann',
      attachments: [photo],
    );

    final attachments = sent!['variables']['input']['attachments'];
    expect(attachments, isA<String>());
    expect(jsonDecode(attachments as String), [
      'data:image/png;base64,${base64Encode([7, 8, 9])}',
    ]);
    expect(review.attachments.single.url, 'https://x.test/p.png');
  });

  test('SubmitReview includes attachments in props', () {
    final a = SubmitReview(
      productId: 1,
      title: 't',
      comment: 'c',
      rating: 5,
      name: 'n',
      attachments: [File('/a.png')],
    );
    const b = SubmitReview(
      productId: 1,
      title: 't',
      comment: 'c',
      rating: 5,
      name: 'n',
    );

    expect(a.attachments.single.path, '/a.png');
    expect(b.attachments, isEmpty);
    expect(a == b, isFalse);
  });
}

AccountRepository _repository(void Function(Map<String, dynamic>) capture) {
  final httpClient = MockClient((request) async {
    capture(jsonDecode(request.body) as Map<String, dynamic>);
    return http.Response(
      jsonEncode({
        'data': {
          '__typename': 'Mutation',
          'createProductReview': {
            '__typename': 'createProductReviewPayload',
            'productReview': {
              '__typename': 'ProductReview',
              'id': '/api/shop/reviews/5',
              '_id': 5,
              'name': 'Ann',
              'title': 'Nice',
              'rating': 5,
              'comment': 'Good',
              'status': 'pending',
              'attachments':
                  '[{"type":"image","url":"https://x.test/p.png"}]',
              'createdAt': '2026-09-17T10:00:00+00:00',
              'updatedAt': '2026-09-17T10:00:00+00:00',
            },
          },
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  return AccountRepository(
    client: GraphQLClient(
      link: HttpLink('https://example.com/graphql', httpClient: httpClient),
      cache: GraphQLCache(store: InMemoryStore()),
    ),
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/create_product_review_repository_test.dart`
Expected: FAIL, compile error `No named parameter with the name 'attachments'`.

- [ ] **Step 3: Implement repository**

In `lib/features/account/data/repository/account_repository.dart`, add as the first import line:

```dart
import 'dart:io';
```

and after `import '../models/returns_models.dart';`:

```dart
import '../utils/review_attachment_encoder.dart';
```

Replace the whole `createProductReview` method (doc comment through closing brace) with:

```dart
  /// Create a product review.
  /// [productId] — numeric product _id (Int).
  /// [title] — review headline.
  /// [comment] — full review text.
  /// [rating] — 1 to 5 star rating.
  /// [name] — reviewer's display name.
  /// [attachments] — optional images/videos, sent as a JSON string of
  /// Base64 data URIs. The key is omitted when the list is empty.
  /// Returns the created ProductReview.
  Future<ProductReview> createProductReview({
    required int productId,
    required String title,
    required String comment,
    required int rating,
    required String name,
    List<File> attachments = const [],
  }) async {
    debugPrint(
      '📝 AccountRepo.createProductReview '
      '(product=$productId, attachments=${attachments.length})',
    );

    final input = <String, dynamic>{
      'productId': productId,
      'title': title,
      'comment': comment,
      'rating': rating,
      'name': name,
    };
    if (attachments.isNotEmpty) {
      input['attachments'] = await ReviewAttachmentEncoder.encode(attachments);
    }

    final result = await client.mutate(
      MutationOptions(
        document: gql(AccountQueries.createProductReview),
        variables: {'input': input},
      ),
    );

    if (result.hasException) {
      final message = _extractErrorMessage(result.exception!);
      debugPrint('📝 AccountRepo.createProductReview — error: $message');
      throw AccountException(message);
    }

    final data = result.data?['createProductReview']?['productReview'];
    if (data == null) {
      throw AccountException('Failed to create review');
    }

    debugPrint('📝 AccountRepo.createProductReview — success');
    return ProductReview.fromJson(data as Map<String, dynamic>);
  }
```

- [ ] **Step 4: Implement bloc**

In `lib/features/account/presentation/bloc/add_review_bloc.dart`, add as the first import:

```dart
import 'dart:io';

```

Replace class `SubmitReview` with:

```dart
/// Submit a new product review
class SubmitReview extends AddReviewEvent {
  final int productId;
  final String title;
  final String comment;
  final int rating;
  final String name;
  final List<File> attachments;

  const SubmitReview({
    required this.productId,
    required this.title,
    required this.comment,
    required this.rating,
    required this.name,
    this.attachments = const [],
  });

  @override
  List<Object?> get props => [
    productId,
    title,
    comment,
    rating,
    name,
    attachments.map((file) => file.path).toList(),
  ];
}
```

In `_onSubmit`, change the repository call to:

```dart
      final review = await repository.createProductReview(
        productId: event.productId,
        title: event.title,
        comment: event.comment,
        rating: event.rating,
        name: event.name,
        attachments: event.attachments,
      );
```

- [ ] **Step 5: Update the existing fake repository**

In `test/add_review_page_test.dart`, add `import 'dart:io';` as the first import, and change the fake override signature to:

```dart
  @override
  Future<ProductReview> createProductReview({
    required int productId,
    required String title,
    required String comment,
    required int rating,
    required String name,
    List<File> attachments = const [],
  }) async {
```

- [ ] **Step 6: Run tests**

Run: `flutter test test/create_product_review_repository_test.dart test/add_review_page_test.dart`
Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/account/data/repository/account_repository.dart lib/features/account/presentation/bloc/add_review_bloc.dart test/add_review_page_test.dart test/create_product_review_repository_test.dart
git commit -m "feat: send review attachments in createProductReview

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Localized strings

**Files:**
- Modify: `lib/l10n/app_ar.arb`, `app_de.arb`, `app_en.arb`, `app_es.arb`, `app_fr.arb`, `app_it.arb`, `app_nl.arb`, `app_ru.arb`, `app_tr.arb`, `app_uk.arb`
- Regenerate: `lib/l10n/app_localizations*.dart`

**Interfaces:**
- Produces (on `AppLocalizations`): `accountReviewPhotosVideos`, `accountReviewAddMedia`, `accountReviewGallery`, `accountReviewCamera`, `String accountReviewMaxFiles(int count)`, `accountReviewFileTooLarge`, `accountReviewUnsupportedFile`, `accountReviewPickFailed`, `accountReviewVideoLoadFailed`. Existing `commonRetry` is reused.

- [ ] **Step 1: Confirm keys are new**

Run: `grep -c "accountReviewPhotosVideos\|accountReviewMaxFiles" lib/l10n/app_en.arb`
Expected: `0`

- [ ] **Step 2: Append keys to all arb files**

Save as `/private/tmp/claude-506/add_review_media_l10n.py` (scratch, not committed) and run `python3 /private/tmp/claude-506/add_review_media_l10n.py` from repo root:

```python
import json

KEYS = [
    "accountReviewPhotosVideos", "accountReviewAddMedia", "accountReviewGallery",
    "accountReviewCamera", "accountReviewMaxFiles", "accountReviewFileTooLarge",
    "accountReviewUnsupportedFile", "accountReviewPickFailed",
    "accountReviewVideoLoadFailed",
]

T = {
    "en": ["Photos & Videos", "Add", "Gallery", "Camera",
           "You can attach up to {count} files", "Each file must be 5 MB or smaller",
           "Only images and videos are supported", "Could not add media. Please try again",
           "Unable to play this video"],
    "ar": ["الصور ومقاطع الفيديو", "إضافة", "المعرض", "الكاميرا",
           "يمكنك إرفاق {count} ملفات كحد أقصى", "يجب ألا يتجاوز حجم كل ملف 5 ميغابايت",
           "يتم دعم الصور ومقاطع الفيديو فقط", "تعذرت إضافة الوسائط. يرجى المحاولة مرة أخرى",
           "تعذر تشغيل هذا الفيديو"],
    "de": ["Fotos & Videos", "Hinzufügen", "Galerie", "Kamera",
           "Sie können bis zu {count} Dateien anhängen", "Jede Datei darf höchstens 5 MB groß sein",
           "Nur Bilder und Videos werden unterstützt",
           "Medien konnten nicht hinzugefügt werden. Bitte versuchen Sie es erneut",
           "Dieses Video kann nicht abgespielt werden"],
    "es": ["Fotos y videos", "Añadir", "Galería", "Cámara",
           "Puedes adjuntar hasta {count} archivos", "Cada archivo debe pesar 5 MB o menos",
           "Solo se admiten imágenes y videos", "No se pudo añadir el contenido. Inténtalo de nuevo",
           "No se puede reproducir este video"],
    "fr": ["Photos et vidéos", "Ajouter", "Galerie", "Appareil photo",
           "Vous pouvez joindre jusqu'à {count} fichiers", "Chaque fichier doit faire 5 Mo maximum",
           "Seules les images et les vidéos sont prises en charge",
           "Impossible d'ajouter le média. Veuillez réessayer", "Impossible de lire cette vidéo"],
    "it": ["Foto e video", "Aggiungi", "Galleria", "Fotocamera",
           "Puoi allegare fino a {count} file", "Ogni file deve essere di 5 MB o meno",
           "Sono supportati solo immagini e video", "Impossibile aggiungere il contenuto. Riprova",
           "Impossibile riprodurre questo video"],
    "nl": ["Foto's en video's", "Toevoegen", "Galerij", "Camera",
           "Je kunt maximaal {count} bestanden toevoegen", "Elk bestand mag maximaal 5 MB zijn",
           "Alleen afbeeldingen en video's worden ondersteund",
           "Media kon niet worden toegevoegd. Probeer het opnieuw",
           "Deze video kan niet worden afgespeeld"],
    "ru": ["Фото и видео", "Добавить", "Галерея", "Камера",
           "Можно прикрепить не более {count} файлов",
           "Размер каждого файла не должен превышать 5 МБ",
           "Поддерживаются только изображения и видео",
           "Не удалось добавить медиафайл. Повторите попытку",
           "Не удалось воспроизвести это видео"],
    "tr": ["Fotoğraflar ve Videolar", "Ekle", "Galeri", "Kamera",
           "En fazla {count} dosya ekleyebilirsiniz", "Her dosya en fazla 5 MB olmalıdır",
           "Yalnızca görseller ve videolar desteklenir", "Medya eklenemedi. Lütfen tekrar deneyin",
           "Bu video oynatılamıyor"],
    "uk": ["Фото та відео", "Додати", "Галерея", "Камера",
           "Можна прикріпити не більше {count} файлів",
           "Розмір кожного файлу не повинен перевищувати 5 МБ",
           "Підтримуються лише зображення та відео",
           "Не вдалося додати медіафайл. Спробуйте ще раз",
           "Не вдалося відтворити це відео"],
}

for lang, values in T.items():
    path = f"lib/l10n/app_{lang}.arb"
    with open(path, encoding="utf-8") as f:
        text = f.read()
    json.loads(text)  # must be valid before editing
    lines = []
    for key, value in zip(KEYS, values):
        lines.append(f'  {json.dumps(key)}: {json.dumps(value, ensure_ascii=False)}')
        if lang == "en" and key == "accountReviewMaxFiles":
            lines.append('  "@accountReviewMaxFiles": {\n    "placeholders": {\n      "count": {\n        "type": "int"\n      }\n    }\n  }')
    body = text.rstrip()
    assert body.endswith("}"), path
    text = body[:-1].rstrip() + ",\n" + ",\n".join(lines) + "\n}\n"
    json.loads(text)  # must still be valid
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print("updated", path)
```

Expected: 10 lines `updated lib/l10n/app_xx.arb`.

- [ ] **Step 3: Generate localizations**

Run: `flutter gen-l10n`
Expected: exits 0, no `untranslated` warnings for the new keys.

Run: `grep -n "accountReviewMaxFiles(int count)" lib/l10n/app_localizations.dart`
Expected: one match.

- [ ] **Step 4: Verify nothing broke**

Run: `flutter analyze 2>&1 | tail -1`
Expected: `49 issues found.` (or fewer).

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/
git commit -m "feat: add review media strings in all locales

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Video player page and attachments strip

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock`
- Create: `lib/features/account/presentation/pages/review_video_player_page.dart`
- Create: `lib/features/account/presentation/widgets/review_attachments_strip.dart`
- Test: `test/review_attachments_strip_test.dart`

**Interfaces:**
- Consumes: `ReviewAttachment` (Task 1); l10n keys (Task 5); `FullscreenImageViewer.open(BuildContext context, {required List<String> imageUrls, int initialIndex = 0})` from `lib/features/product/presentation/widgets/fullscreen_image_viewer.dart`.
- Produces:
  - `ReviewVideoPlayerPage({Key? key, required String url})`, `static Future<void> navigate(BuildContext context, String url)`
  - `ReviewAttachmentsStrip({Key? key, required List<ReviewAttachment> attachments})`; tile keys `ValueKey('review_attachment_$index')`

- [ ] **Step 1: Add dependency**

Run: `flutter pub add video_player`
Expected: `pubspec.yaml` gains `video_player: ^<version>` under `dependencies`; command exits 0.

Run: `git diff --stat pubspec.yaml pubspec.lock`
Expected: both files changed.

- [ ] **Step 2: Write the failing test**

Create `test/review_attachments_strip_test.dart`:

```dart
import 'package:bagisto_flutter/features/account/data/models/review_attachment.dart';
import 'package:bagisto_flutter/features/account/presentation/widgets/review_attachments_strip.dart';
import 'package:bagisto_flutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('renders nothing when there are no attachments', (tester) async {
    await tester.pumpWidget(
      _wrap(const ReviewAttachmentsStrip(attachments: [])),
    );

    expect(find.byKey(const ValueKey('review_attachment_0')), findsNothing);
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('renders an image tile and a video tile with play icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const ReviewAttachmentsStrip(
          attachments: [
            ReviewAttachment(
              type: ReviewAttachmentType.image,
              url: 'https://x.test/p.png',
            ),
            ReviewAttachment(
              type: ReviewAttachmentType.video,
              url: 'https://x.test/v.mp4',
            ),
          ],
        ),
      ),
    );

    expect(find.byKey(const ValueKey('review_attachment_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('review_attachment_1')), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/review_attachments_strip_test.dart`
Expected: FAIL, compile error `Target of URI doesn't exist: ...review_attachments_strip.dart`.

- [ ] **Step 4: Create the video player page**

Create `lib/features/account/presentation/pages/review_video_player_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';

/// Full-screen in-app player for a review video attachment.
class ReviewVideoPlayerPage extends StatefulWidget {
  final String url;

  const ReviewVideoPlayerPage({super.key, required this.url});

  static Future<void> navigate(BuildContext context, String url) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReviewVideoPlayerPage(url: url)),
    );
  }

  @override
  State<ReviewVideoPlayerPage> createState() => _ReviewVideoPlayerPageState();
}

class _ReviewVideoPlayerPageState extends State<ReviewVideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    _load(_controller);
  }

  VideoPlayerController _createController() =>
      VideoPlayerController.networkUrl(Uri.parse(widget.url));

  Future<void> _load(VideoPlayerController controller) async {
    try {
      await controller.initialize();
      if (!mounted || controller != _controller) return;
      await controller.play();
      setState(() {});
    } catch (e) {
      debugPrint('🎬 ReviewVideoPlayerPage load error: $e');
      if (!mounted || controller != _controller) return;
      setState(() => _hasError = true);
    }
  }

  void _retry() {
    final previous = _controller;
    setState(() {
      _controller = _createController();
      _hasError = false;
    });
    previous.dispose();
    _load(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(child: _buildContent(context)),
            Positioned(
              top: 8,
              right: 12,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  shape: const CircleBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_hasError) return _buildError(context);
    if (!_controller.value.isInitialized) {
      return const CircularProgressIndicator(
        color: AppColors.primary500,
        strokeWidth: 2,
      );
    }

    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        if (value.hasError) return _buildError(context);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () =>
                  value.isPlaying ? _controller.pause() : _controller.play(),
              child: AspectRatio(
                aspectRatio: value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    if (!value.isPlaying)
                      const Icon(
                        Icons.play_circle_fill,
                        size: 64,
                        color: Colors.white70,
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: VideoProgressIndicator(
                _controller,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: AppColors.primary500,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildError(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.white70),
          const SizedBox(height: 12),
          Text(
            l10n.accountReviewVideoLoadFailed,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _retry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary500,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(54),
                ),
              ),
              child: Text(
                l10n.commonRetry,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Create the strip widget**

Create `lib/features/account/presentation/widgets/review_attachments_strip.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../product/presentation/widgets/fullscreen_image_viewer.dart';
import '../../data/models/review_attachment.dart';
import '../pages/review_video_player_page.dart';

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
                ? Container(
                    color: AppColors.neutral800,
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        size: 28,
                        color: AppColors.white,
                      ),
                    ),
                  )
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
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/review_attachments_strip_test.dart`
Expected: `All tests passed!`

- [ ] **Step 7: Analyze new files**

Run: `flutter analyze lib/features/account/presentation/pages/review_video_player_page.dart lib/features/account/presentation/widgets/review_attachments_strip.dart`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/account/presentation/pages/review_video_player_page.dart lib/features/account/presentation/widgets/review_attachments_strip.dart test/review_attachments_strip_test.dart
git commit -m "feat: add review attachments strip and video player

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Show attachments on review cards

**Files:**
- Modify: `lib/features/product/presentation/widgets/product_reviews_section.dart` (`_buildReviewCard`, comment block ~line 431)
- Modify: `lib/features/account/presentation/widgets/product_reviews_section.dart` (`_buildReviewCard`, comment `Text` ~line 245)
- Modify: `lib/features/account/presentation/pages/reviews_page.dart` (`_ReviewCard.build`, comment `Text` ~line 497)

**Interfaces:**
- Consumes: `ReviewAttachmentsStrip` (Task 6); `ProductReview.attachments` (Task 2).
- Produces: nothing new.

- [ ] **Step 1: Product detail card**

In `lib/features/product/presentation/widgets/product_reviews_section.dart`, add import after `import '../../../account/presentation/pages/reviews_page.dart';`:

```dart
import '../../../account/presentation/widgets/review_attachments_strip.dart';
```

In `_buildReviewCard`, find the `// ── Comment ──` block (the `if (review.comment != null && review.comment!.isNotEmpty) Text(...)` ending with `),`). Directly after that block and before `const SizedBox(height: 12),` / `// ── Author ──`, insert:

```dart
          if (review.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            ReviewAttachmentsStrip(attachments: review.attachments),
          ],
```

- [ ] **Step 2: Account dashboard card**

In `lib/features/account/presentation/widgets/product_reviews_section.dart`, add import after `import 'section_header.dart';`:

```dart
import 'review_attachments_strip.dart';
```

In `_buildReviewCard`, after the `// Review comment` `Text(...)` (the one with `maxLines: 4`) and before the closing `],` of the `Column` children, insert:

```dart
          if (review.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            ReviewAttachmentsStrip(attachments: review.attachments),
          ],
```

- [ ] **Step 3: My Reviews page card**

In `lib/features/account/presentation/pages/reviews_page.dart`, add import after `import '../bloc/review_bloc.dart';`:

```dart
import '../widgets/review_attachments_strip.dart';
```

In `_ReviewCard.build`, after the `// ── Review comment ──` `Text(...)` and before the closing `],` of the `Column` children, insert:

```dart
          if (review.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            ReviewAttachmentsStrip(attachments: review.attachments),
          ],
```

- [ ] **Step 4: Analyze and test**

Run: `flutter analyze 2>&1 | tail -1`
Expected: `49 issues found.` (or fewer).

Run: `flutter test`
Expected: `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/product/presentation/widgets/product_reviews_section.dart lib/features/account/presentation/widgets/product_reviews_section.dart lib/features/account/presentation/pages/reviews_page.dart
git commit -m "feat: show review attachments on review cards

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Add Review page media picker

**Files:**
- Modify: `lib/features/account/presentation/pages/add_review_page.dart`
- Modify: `test/add_review_page_test.dart`

**Interfaces:**
- Consumes: `ReviewAttachmentEncoder.maxFiles`, `.maxFileBytes`, `.mimeTypeFor`, `.isVideoPath` (Task 3); `SubmitReview.attachments` (Task 4); l10n keys (Task 5).
- Produces: `AddReviewPage({..., @visibleForTesting List<File> initialAttachments = const []})`. Test keys: `ValueKey('add_review_media_tile_$index')`, `ValueKey('add_review_media_remove_$index')`, `ValueKey('add_review_media_add')`.

- [ ] **Step 1: Write the failing tests**

In `test/add_review_page_test.dart`:

1. Add `import 'dart:async';` next to `import 'dart:io';`.
2. Replace `_buildTestApp` with:

```dart
Widget _buildTestApp({
  AccountRepository? repository,
  List<File> initialAttachments = const [],
}) {
  final accountRepository = repository ?? _FakeAccountRepository();

  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider(
      create: (_) => AddReviewBloc(repository: accountRepository),
      child: AddReviewPage(
        productId: 10,
        productName: 'Arctic Frost Winter Accessories Bundle',
        initialAttachments: initialAttachments,
      ),
    ),
  );
}
```

3. In `_FakeAccountRepository`, add a field `List<File>? lastAttachments;` and a field `bool neverComplete = false;`, and change the override body to:

```dart
  }) async {
    createReviewCalls += 1;
    lastAttachments = attachments;
    if (neverComplete) {
      return Completer<ProductReview>().future;
    }
    return ProductReview(
      id: '1',
      name: name,
      title: title,
      comment: comment,
      rating: rating,
      createdAt: '2026-05-22T10:00:00.000Z',
    );
  }
```

4. Add these tests inside `main()` after the existing two:

```dart
  group('media attachments', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('add_review_media'));
    tearDown(() => dir.deleteSync(recursive: true));

    File writeFile(String name) =>
        File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);

    testWidgets('shows the section with an add tile when empty', (
      tester,
    ) async {
      await tester.pumpWidget(_buildTestApp());

      expect(find.text('Photos & Videos'), findsOneWidget);
      expect(find.byKey(const ValueKey('add_review_media_add')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('add_review_media_tile_0')),
        findsNothing,
      );
    });

    testWidgets('renders image and video tiles and removes one', (
      tester,
    ) async {
      final photo = writeFile('p.png');
      final video = writeFile('v.mp4');

      await tester.pumpWidget(
        _buildTestApp(initialAttachments: [photo, video]),
      );

      expect(find.byKey(const ValueKey('add_review_media_tile_0')), findsOneWidget);
      expect(find.byKey(const ValueKey('add_review_media_tile_1')), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const ValueKey('add_review_media_remove_0')),
      );
      await tester.tap(find.byKey(const ValueKey('add_review_media_remove_0')));
      await tester.pump();

      expect(find.byKey(const ValueKey('add_review_media_tile_1')), findsNothing);
      expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    });

    testWidgets('hides the add tile at 5 attachments', (tester) async {
      final files = List.generate(5, (i) => writeFile('p$i.png'));

      await tester.pumpWidget(_buildTestApp(initialAttachments: files));

      expect(find.byKey(const ValueKey('add_review_media_tile_4')), findsOneWidget);
      expect(find.byKey(const ValueKey('add_review_media_add')), findsNothing);
    });

    testWidgets('submits selected attachments', (tester) async {
      final repository = _FakeAccountRepository()..neverComplete = true;
      final photo = writeFile('p.png');

      await tester.pumpWidget(
        _buildTestApp(repository: repository, initialAttachments: [photo]),
      );

      await tester.tap(find.byIcon(Icons.star_outline_rounded).at(4));
      await tester.enterText(find.byType(TextFormField).at(0), 'Ann');
      await tester.enterText(find.byType(TextFormField).at(1), 'Nice');
      await tester.enterText(find.byType(TextFormField).at(2), 'Good');
      await tester.tap(find.text('Submit Review'));
      await tester.pump();

      expect(repository.createReviewCalls, 1);
      expect(repository.lastAttachments!.single.path, photo.path);
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/add_review_page_test.dart`
Expected: FAIL, compile error `No named parameter with the name 'initialAttachments'`.

- [ ] **Step 3: Implement the page changes**

In `lib/features/account/presentation/pages/add_review_page.dart`:

3a. Replace the imports with:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/graphql/graphql_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../data/repository/account_repository.dart';
import '../../data/utils/review_attachment_encoder.dart';
import '../bloc/add_review_bloc.dart';
```

3b. In the class doc comment, after `///   - Review multi-line text field`, add `///   - Photos & Videos picker (up to 5 files, 5 MB each)`.

3c. In `AddReviewPage`, add the field after `final String? productImageUrl;`:

```dart
  /// Pre-selected attachments. Test seam; production callers omit it.
  @visibleForTesting
  final List<File> initialAttachments;
```

and in the constructor after `this.productImageUrl,`:

```dart
    this.initialAttachments = const [],
```

3d. In `_AddReviewPageState`, add fields after `String? _ratingErrorText;`:

```dart
  final ImagePicker _imagePicker = ImagePicker();
  late final List<File> _attachments = List.of(widget.initialAttachments);
```

3e. In `_onSubmit`, change the `SubmitReview(` call to add after `name: _nickNameController.text.trim(),`:

```dart
          attachments: List.unmodifiable(_attachments),
```

3f. In `build`, after the `// ── Review Field ──` `_buildTextField(...)` and its following `const SizedBox(height: 20),`… specifically replace:

```dart
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
```

with:

```dart
                        const SizedBox(height: 20),

                        // ── Photos & Videos ──
                        _buildMediaSection(context, isSubmitting),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
```

3g. Add these methods to `_AddReviewPageState`, directly before the `// Submit Button` section comment:

```dart
  // ──────────────────────────────────────────────
  // Photos & Videos — pick, preview, remove
  // ──────────────────────────────────────────────

  Future<void> _showMediaSourceSheet() async {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppColors.neutral800 : AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final textStyle = TextStyle(
          fontFamily: 'Roboto',
          fontWeight: FontWeight.w400,
          fontSize: 16,
          color: isDark ? AppColors.neutral200 : AppColors.neutral900,
        );
        final iconColor = isDark ? AppColors.neutral200 : AppColors.neutral900;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_library_outlined, color: iconColor),
                title: Text(l10n.accountReviewGallery, style: textStyle),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: Icon(Icons.photo_camera_outlined, color: iconColor),
                title: Text(l10n.accountReviewCamera, style: textStyle),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
            ],
          ),
        );
      },
    );

    if (source != null) await _pickMedia(source);
  }

  Future<void> _pickMedia(ImageSource source) async {
    final l10n = AppLocalizations.of(context)!;
    final remaining = ReviewAttachmentEncoder.maxFiles - _attachments.length;
    if (remaining <= 0) {
      _showMediaMessage(
        l10n.accountReviewMaxFiles(ReviewAttachmentEncoder.maxFiles),
      );
      return;
    }

    List<XFile> picked;
    try {
      if (source == ImageSource.camera) {
        final photo = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        picked = photo == null ? const [] : [photo];
      } else {
        picked = await _imagePicker.pickMultipleMedia(
          imageQuality: 85,
          limit: remaining > 1 ? remaining : null,
        );
      }
    } catch (e) {
      debugPrint('❌ AddReviewPage._pickMedia error: $e');
      if (mounted) _showMediaMessage(l10n.accountReviewPickFailed);
      return;
    }
    if (picked.isEmpty || !mounted) return;

    final accepted = <File>[];
    final messages = <String>{};
    for (final xFile in picked) {
      if (ReviewAttachmentEncoder.mimeTypeFor(xFile.path) == null) {
        messages.add(l10n.accountReviewUnsupportedFile);
        continue;
      }
      if (await xFile.length() > ReviewAttachmentEncoder.maxFileBytes) {
        messages.add(l10n.accountReviewFileTooLarge);
        continue;
      }
      if (_attachments.length + accepted.length >=
          ReviewAttachmentEncoder.maxFiles) {
        messages.add(
          l10n.accountReviewMaxFiles(ReviewAttachmentEncoder.maxFiles),
        );
        break;
      }
      accepted.add(File(xFile.path));
    }

    if (!mounted) return;
    if (accepted.isNotEmpty) {
      setState(() => _attachments.addAll(accepted));
    }
    if (messages.isNotEmpty) _showMediaMessage(messages.join('\n'));
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  void _showMediaMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Widget _buildMediaSection(BuildContext context, bool isSubmitting) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final canAdd = _attachments.length < ReviewAttachmentEncoder.maxFiles;
    final borderColor = isDark ? AppColors.neutral700 : AppColors.neutral200;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(context, label: l10n.accountReviewPhotosVideos),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(top: 8, right: 8),
            itemCount: _attachments.length + (canAdd ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              if (index == _attachments.length) {
                return GestureDetector(
                  key: const ValueKey('add_review_media_add'),
                  onTap: isSubmitting ? null : _showMediaSourceSheet,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          size: 24,
                          color: isDark
                              ? AppColors.neutral300
                              : AppColors.neutral700,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.accountReviewAddMedia,
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                            color: isDark
                                ? AppColors.neutral300
                                : AppColors.neutral700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return _buildMediaTile(
                context,
                index: index,
                file: _attachments[index],
                borderColor: borderColor,
                isSubmitting: isSubmitting,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMediaTile(
    BuildContext context, {
    required int index,
    required File file,
    required Color borderColor,
    required bool isSubmitting,
  }) {
    final isVideo = ReviewAttachmentEncoder.isVideoPath(file.path);

    return SizedBox(
      key: ValueKey('add_review_media_tile_$index'),
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
              color: AppColors.neutral800,
            ),
            clipBehavior: Clip.antiAlias,
            child: isVideo
                ? const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      size: 32,
                      color: AppColors.white,
                    ),
                  )
                : Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 24,
                        color: AppColors.neutral400,
                      ),
                    ),
                  ),
          ),
          Positioned(
            top: -8,
            right: -8,
            child: GestureDetector(
              key: ValueKey('add_review_media_remove_$index'),
              onTap: isSubmitting ? null : () => _removeAttachment(index),
              child: Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  color: AppColors.neutral900,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: AppColors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
```

Note: the remove button sits at `top: -8, right: -8` with `Clip.none`. The `ListView` has `padding: EdgeInsets.only(top: 8)` so the button is not clipped at the top. Use `const EdgeInsets.only(top: 8, right: 8)` so the last tile's button is not clipped on the right either.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/add_review_page_test.dart`
Expected: `All tests passed!`

Note: image_picker 1.2.1 `pickMultipleMedia({int? limit})` throws when `limit < 2`; `null` means no limit. The code passes `null` when only 1 slot remains and relies on the post-pick count check.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/features/account/presentation/pages/add_review_page.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/account/presentation/pages/add_review_page.dart test/add_review_page_test.dart
git commit -m "feat: pick photos and videos when adding a review

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Full verification

**Files:** none changed unless a check fails.

- [ ] **Step 1: Analyze**

Run: `flutter analyze 2>&1 | tail -1`
Expected: `49 issues found.` or fewer, and `flutter analyze 2>&1 | grep -c " error "` prints `0`.

- [ ] **Step 2: All tests**

Run: `flutter test 2>&1 | tail -1`
Expected: `All tests passed!` (147 baseline + new tests).

- [ ] **Step 3: Manual end-to-end check on the test server**

Pick a product id:

```bash
curl -s https://test-delivery.bagisto.com/api/graphql \
  -H 'Content-Type: application/json' \
  -H 'X-STOREFRONT-KEY: pk_storefront_SnkqmqiLsKhia28OQROyGiWH6N0puqGy' \
  -d '{"query":"{ products(first: 1) { edges { node { _id name } } } }"}'
```

Then run the app on a device/simulator (`flutter run`), log in, open that product, tap "Write a Review", attach one photo from the gallery and one short video (< 5 MB), fill the form, and submit.
Expected: green "Review submitted" snackbar, page closes. In Bagisto admin, the pending review shows both attachments. After approving it, the product page review card shows an image thumbnail (tap → zoomable viewer) and a video tile (tap → in-app player plays).

- [ ] **Step 4: Confirm local-only files are not committed**

Run: `git status --short`
Expected: only ` M lib/features/category/presentation/widgets/category_banner.dart` and `?? CLAUDE.md` remain. (`api_constants.dart` has the skip-worktree flag, so git hides its local server config; `git ls-files -v lib/core/constants/api_constants.dart` must still print `S ...`.)
