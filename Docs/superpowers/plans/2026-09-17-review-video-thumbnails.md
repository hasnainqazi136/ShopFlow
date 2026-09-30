# Review Video Thumbnails Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show first-frame thumbnails for review videos (Add Review tiles and review cards), let users play a picked video before submitting, and upload `.mov`/`.m4v` so iOS can play them.

**Architecture:** One `ReviewVideoThumbnail` widget initializes a `VideoPlayerController` (file or network) without playing and renders its first frame, falling back to the existing dark tile. `ReviewVideoPlayerPage` gains a `File` source. The encoder maps QuickTime-family extensions to `video/mp4` to avoid the server's `.quicktime` storage bug.

**Tech Stack:** Flutter 3.44 / Dart 3.12, `video_player` ^2.14.0 (already added), flutter_test.

Spec: `Docs/superpowers/specs/2026-09-17-review-video-thumbnails-design.md`

## Global Constraints

- Branch `feat/review-attachments`. Do not push or merge.
- Never stage `lib/core/constants/api_constants.dart` (skip-worktree) or `lib/features/category/presentation/widgets/category_banner.dart`, or `CLAUDE.md`. Always `git add` explicit paths.
- Do not run `dart format` on whole existing files (it reformats unrelated code). Hand-indent edits.
- Baseline: `flutter analyze` → `49 issues found.`; `flutter test` → `All tests passed!` (173 tests).
- Commit messages end with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

---

### Task 1: Upload `.mov` / `.m4v` as `video/mp4`

**Files:**
- Modify: `lib/features/account/data/utils/review_attachment_encoder.dart` (`_mimeByExtension`)
- Modify: `test/review_attachment_encoder_test.dart`

**Interfaces:** `ReviewAttachmentEncoder.mimeTypeFor('/a/clip.mov') == 'video/mp4'`; `isVideoPath` unchanged.

- [ ] **Step 1: Update test.** In `mimeTypeFor maps supported image and video extensions`, replace the `.mov` expectation with:

```dart
    // The server stores video/quicktime as ".quicktime", which iOS cannot
    // play. QuickTime-family files are uploaded as MP4 instead.
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a/clip.mov'), 'video/mp4');
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a/clip.M4V'), 'video/mp4');
```

Add test:

```dart
  test('encode sends mov files as video/mp4 data URIs', () async {
    final mov = writeFile('c.mov', [9]);

    final encoded = await ReviewAttachmentEncoder.encode([mov]);

    expect(jsonDecode(encoded), ['data:video/mp4;base64,${base64Encode([9])}']);
  });
```

- [ ] **Step 2:** `flutter test test/review_attachment_encoder_test.dart` → FAIL (`Expected: 'video/mp4' Actual: 'video/quicktime'`).
- [ ] **Step 3: Implement.** In `_mimeByExtension` replace the `mov` and `m4v` lines with:

```dart
    // Stored by the server as ".quicktime"/".x-m4v" (unplayable on iOS);
    // MP4 is the same container family and plays everywhere.
    'mov': 'video/mp4',
    'm4v': 'video/mp4',
```

- [ ] **Step 4:** `flutter test test/review_attachment_encoder_test.dart` → `All tests passed!`
- [ ] **Step 5: Commit** `lib/features/account/data/utils/review_attachment_encoder.dart test/review_attachment_encoder_test.dart` — `fix: upload mov and m4v review videos as mp4`.

---

### Task 2: `ReviewVideoThumbnail`, file playback, strip thumbnails

**Files:**
- Create: `lib/features/account/presentation/widgets/review_video_thumbnail.dart`
- Modify: `lib/features/account/presentation/pages/review_video_player_page.dart`
- Modify: `lib/features/account/presentation/widgets/review_attachments_strip.dart`
- Create: `test/review_video_thumbnail_test.dart`

**Interfaces:**
- `ReviewVideoThumbnail({Key? key, String? url, File? file, double iconSize = 28})` — exactly one of `url`/`file`.
- `ReviewVideoPlayerPage({Key? key, String? url, File? file})`; `static Future<void> navigate(BuildContext, String url)`; `static Future<void> navigateFile(BuildContext, File file)`.

- [ ] **Step 1: Write failing test** `test/review_video_thumbnail_test.dart`:

```dart
import 'dart:io';

import 'package:bagisto_flutter/features/account/presentation/pages/review_video_player_page.dart';
import 'package:bagisto_flutter/features/account/presentation/widgets/review_video_thumbnail.dart';
import 'package:bagisto_flutter/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('falls back to a play tile when the video cannot load', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SizedBox(
          width: 56,
          height: 56,
          child: ReviewVideoThumbnail(url: 'https://x.test/v.mp4'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('file source renders a play tile', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 72,
          height: 72,
          child: ReviewVideoThumbnail(file: File('/nope/v.mp4'), iconSize: 32),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);
  });

  test('player page accepts a file source', () {
    final page = ReviewVideoPlayerPage(file: File('/a/v.mp4'));
    expect(page.file!.path, '/a/v.mp4');
    expect(page.url, isNull);
  });
}
```

- [ ] **Step 2:** `flutter test test/review_video_thumbnail_test.dart` → FAIL (missing `review_video_thumbnail.dart`).

- [ ] **Step 3: Create** `lib/features/account/presentation/widgets/review_video_thumbnail.dart`:

```dart
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
```

- [ ] **Step 4: Player page file source.** In `review_video_player_page.dart`:
  - add `import 'dart:io';` as first import;
  - replace the class fields/constructor/`navigate` with:

```dart
class ReviewVideoPlayerPage extends StatefulWidget {
  final String? url;
  final File? file;

  const ReviewVideoPlayerPage({super.key, this.url, this.file})
    : assert((url == null) != (file == null));

  static Future<void> navigate(BuildContext context, String url) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReviewVideoPlayerPage(url: url)),
    );
  }

  /// Play a picked (not yet uploaded) video.
  static Future<void> navigateFile(BuildContext context, File file) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReviewVideoPlayerPage(file: file)),
    );
  }
```

  - replace `_createController` with:

```dart
  VideoPlayerController _createController() => widget.file != null
      ? VideoPlayerController.file(widget.file!)
      : VideoPlayerController.networkUrl(Uri.parse(widget.url!));
```

- [ ] **Step 5: Strip uses thumbnail.** In `review_attachments_strip.dart` add `import 'review_video_thumbnail.dart';` after the model import, and replace the video branch:

```dart
            child: attachment.isVideo
                ? ReviewVideoThumbnail(url: attachment.url)
                : Image.network(
```

(remove the old `Container(color: AppColors.neutral800, child: const Center(child: Icon(...)))` block).

- [ ] **Step 6:** `flutter test test/review_video_thumbnail_test.dart test/review_attachments_strip_test.dart` → `All tests passed!`
- [ ] **Step 7:** `flutter analyze` on the 3 lib files + test → `No issues found!`
- [ ] **Step 8: Commit** the 4 files — `feat: show first-frame thumbnails for review videos`.

---

### Task 3: Add Review video tile thumbnail + tap to play

**Files:**
- Modify: `lib/features/account/presentation/pages/add_review_page.dart` (`_buildMediaTile`)
- Modify: `test/add_review_page_test.dart`

**Interfaces:** consumes `ReviewVideoThumbnail(file:, iconSize:)`, `ReviewVideoPlayerPage.navigateFile`. Test key `ValueKey('add_review_media_open_$index')`.

- [ ] **Step 1: Failing test.** Add import `package:bagisto_flutter/features/account/presentation/pages/review_video_player_page.dart`. In group `media attachments` add:

```dart
    testWidgets('tapping a video tile opens the player', (tester) async {
      final photo = writeFile('p.png');
      final video = writeFile('v.mp4');

      await tester.pumpWidget(
        _buildTestApp(initialAttachments: [photo, video]),
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('add_review_media_open_1')),
      );
      await tester.tap(find.byKey(const ValueKey('add_review_media_open_1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ReviewVideoPlayerPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('add_review_media_open_0')),
        findsNothing,
      );
    });
```

(Image tiles have no open key; only video tiles are tappable.)

- [ ] **Step 2:** `flutter test test/add_review_page_test.dart` → FAIL (key not found).

- [ ] **Step 3: Implement.** In `add_review_page.dart` add imports after `../bloc/add_review_bloc.dart`:

```dart
import 'review_video_player_page.dart';
import '../widgets/review_video_thumbnail.dart';
```

In `_buildMediaTile`, replace the video branch of `child: isVideo ? const Center(...) : Image.file(...)` with:

```dart
            child: isVideo
                ? GestureDetector(
                    key: ValueKey('add_review_media_open_$index'),
                    onTap: isSubmitting
                        ? null
                        : () => ReviewVideoPlayerPage.navigateFile(
                              context,
                              file,
                            ),
                    child: ReviewVideoThumbnail(file: file, iconSize: 32),
                  )
                : Image.file(
```

- [ ] **Step 4:** `flutter test test/add_review_page_test.dart` → `All tests passed!`
- [ ] **Step 5:** `flutter analyze lib/features/account/presentation/pages/add_review_page.dart test/add_review_page_test.dart` → `No issues found!`
- [ ] **Step 6: Commit** 2 files — `feat: preview and play picked review videos`.

---

### Task 4: Backend bug note

**Files:** Create `Docs/backend-issues/review-attachment-video-extension.md`.

- [ ] **Step 1:** Write note (normal prose, for backend team): summary; repro (upload `data:video/quicktime;base64,...` via `createProductReview`; stored URL `.../storage/review/2/6aabd0314b929.quicktime`; `curl -sI` shows no `content-type`); impact (AVFoundation `Cannot Open`; same bytes `.mov`/`.mp4` playable; affects `video/x-m4v`, `video/x-matroska`); requested fix (derive extension via proper MIME→extension map, serve `Content-Type`); app workaround (uploads `.mov`/`.m4v` as `video/mp4`) and note that existing `.quicktime` files need renaming.
- [ ] **Step 2: Commit** — `docs: report review video extension bug for backend`.

---

### Task 5: Verify

- [ ] `flutter analyze 2>&1 | tail -1` → `49 issues found.`
- [ ] `flutter test 2>&1 | tail -1` → `All tests passed!`
- [ ] `git status --short` → only ` M lib/features/category/presentation/widgets/category_banner.dart` and `?? CLAUDE.md`.
- [ ] Manual on iPhone (user): pick `.mov` → tile shows first frame → tap plays → submit → approve in admin → product page tile shows first frame → tap plays.
