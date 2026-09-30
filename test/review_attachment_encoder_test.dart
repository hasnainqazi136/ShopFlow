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
    // The server stores video/quicktime as ".quicktime", which iOS cannot
    // play. QuickTime-family files are uploaded as MP4 instead.
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a/clip.mov'), 'video/mp4');
    expect(ReviewAttachmentEncoder.mimeTypeFor('/a/clip.M4V'), 'video/mp4');
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

    expect(jsonDecode(encoded), [
      'data:image/png;base64,${base64Encode([1, 2, 3])}',
      'data:video/mp4;base64,${base64Encode([4, 5])}',
    ]);
  });

  test('encode sends mov files as video/mp4 data URIs', () async {
    final mov = writeFile('c.mov', [9]);

    final encoded = await ReviewAttachmentEncoder.encode([mov]);

    expect(jsonDecode(encoded), [
      'data:video/mp4;base64,${base64Encode([9])}',
    ]);
  });

  test('encode rejects unsupported files', () async {
    final pdf = writeFile('d.pdf', [1]);

    await expectLater(
      ReviewAttachmentEncoder.encode([pdf]),
      throwsA(isA<AccountException>()),
    );
  });

  test('encode rejects files larger than 5 MB', () async {
    final big = writeFile(
      'big.jpg',
      List<int>.filled(ReviewAttachmentEncoder.maxFileBytes + 1, 0),
    );

    await expectLater(
      ReviewAttachmentEncoder.encode([big]),
      throwsA(isA<AccountException>()),
    );
  });

  test('encode rejects more than 5 files', () async {
    final files = List.generate(6, (i) => writeFile('p$i.png', [i]));

    await expectLater(
      ReviewAttachmentEncoder.encode(files),
      throwsA(isA<AccountException>()),
    );
  });
}
