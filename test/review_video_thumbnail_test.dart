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
    expect(tester.takeException(), isNull);
  });

  test('player page accepts a file source', () {
    final page = ReviewVideoPlayerPage(file: File('/a/v.mp4'));
    expect(page.file!.path, '/a/v.mp4');
    expect(page.url, isNull);
  });
}
