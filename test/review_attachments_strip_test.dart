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
