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
      expect(
        ReviewAttachment.parseList('{"url":"https://x.test/a.png"}'),
        isEmpty,
      );
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
