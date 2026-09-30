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
    // Stored by the server as ".quicktime"/".x-m4v" (unplayable on iOS);
    // MP4 is the same container family and plays everywhere.
    'mov': 'video/mp4',
    'm4v': 'video/mp4',
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
