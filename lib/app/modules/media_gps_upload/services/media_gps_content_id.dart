import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Stable content id shared by Memory View and GPS Files upload.
///
/// Capture time for content hashes uses UTC milliseconds.
/// Cross-flow gallery dedupe (Add Memories ↔ GPS) uses second+kind keys in
/// [DatabaseHelper.mediaTimeKindDedupeKey] so EXIF and PhotoManager align.
class MediaGpsContentId {
  /// UTC epoch millis for file content hashes.
  static int captureTimeMs(DateTime dt) =>
      dt.toUtc().millisecondsSinceEpoch;

  /// `file:<sha256>` — safe to store in [imported_gallery_assets].
  static String fileKey({
    required int size,
    required DateTime createTime,
    required String mediaKind,
    int videoDurationMs = 0,
  }) {
    final tMs = captureTimeMs(createTime);
    final digest = sha256.convert(
      utf8.encode('v4|$size|$tMs|$mediaKind|$videoDurationMs'),
    );
    return 'file:${digest.toString()}';
  }
}
