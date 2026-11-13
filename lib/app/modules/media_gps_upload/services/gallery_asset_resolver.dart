import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_capture_time.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_gallery_service.dart';

/// Resolved phone/library metadata for a picked file path.
class GalleryResolvedMetadata {
  const GalleryResolvedMetadata({
    this.assetId,
    this.mediaCreatedAt,
  });

  final String? assetId;
  final DateTime? mediaCreatedAt;
}

/// Links image_picker / file_picker outputs to [AssetEntity.id] for cross-flow dedupe.
///
/// Fast path only — never calls [AssetEntity.originFile] (that blocked Memory
/// View on large libraries). Videos match on duration + capture time; images
/// on EXIF time + dimensions. Content-id dedupe covers the rest.
class GalleryAssetResolver {
  static const int _maxAlbumScan = 4000;
  static const int _batchSize = 400;
  static const int _exifHeadBytes = 256 * 1024;

  /// iOS PhotoManager album walks can hang indefinitely — never block UI
  /// staging on them. Memory View uses [probeMetadataForPaths] first.
  static const Duration albumLinkTimeout = Duration(seconds: 4);

  /// Fast EXIF/mtime only — no PhotoManager. Safe to await on the staging path.
  static Future<Map<String, GalleryResolvedMetadata>> probeMetadataForPaths(
    List<String> paths,
  ) async {
    final out = <String, GalleryResolvedMetadata>{};
    if (paths.isEmpty || kIsWeb) return out;

    for (final raw in paths) {
      final path = raw.trim();
      if (path.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final probe = await _probeFile(path, file);
      if (probe == null) continue;
      out[path] = GalleryResolvedMetadata(
        mediaCreatedAt: probe.captureTime,
      );
      await Future<void>.delayed(Duration.zero);
    }
    return out;
  }

  /// Maps absolute/normalized file path → gallery metadata (best effort).
  ///
  /// Set [linkGalleryAssetIds] false to skip the album walk (use
  /// [probeMetadataForPaths] instead for UI-critical paths).
  static Future<Map<String, GalleryResolvedMetadata>> resolveMetadataForPaths(
    List<String> paths, {
    int maxAlbumScan = _maxAlbumScan,
    bool linkGalleryAssetIds = true,
    Duration? timeout,
  }) async {
    if (!linkGalleryAssetIds) {
      return probeMetadataForPaths(paths);
    }

    final effectiveTimeout = timeout ?? albumLinkTimeout;
    try {
      return await _resolveWithAlbumLink(
        paths,
        maxAlbumScan: maxAlbumScan,
      ).timeout(effectiveTimeout);
    } on TimeoutException {
      debugPrint(
        '[GalleryAssetResolver] album link timed out after '
        '${effectiveTimeout.inMilliseconds}ms — falling back to EXIF/mtime',
      );
      return probeMetadataForPaths(paths);
    } catch (e, st) {
      debugPrint('[GalleryAssetResolver] album link failed: $e\n$st');
      return probeMetadataForPaths(paths);
    }
  }

  static Future<Map<String, GalleryResolvedMetadata>> _resolveWithAlbumLink(
    List<String> paths, {
    required int maxAlbumScan,
  }) async {
    final out = <String, GalleryResolvedMetadata>{};
    if (paths.isEmpty || kIsWeb) return out;
    if (!await MediaGpsGalleryService.hasAuthorizedGalleryAccess()) {
      return probeMetadataForPaths(paths);
    }

    final pending = <String, _PickedFileProbe>{};
    for (final raw in paths) {
      final path = raw.trim();
      if (path.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final probe = await _probeFile(path, file);
      if (probe != null) pending[path] = probe;
      await Future<void>.delayed(Duration.zero);
    }
    if (pending.isEmpty) return out;

    final albums = await PhotoManager.getAssetPathList(type: RequestType.common)
        .timeout(const Duration(seconds: 2));
    if (albums.isEmpty) {
      for (final entry in pending.entries) {
        out[entry.key] = GalleryResolvedMetadata(
          mediaCreatedAt: entry.value.captureTime,
        );
      }
      return out;
    }

    final album = albums.first;
    final total = await album.assetCountAsync
        .timeout(const Duration(seconds: 2));
    final scanLimit = math.min(total, maxAlbumScan);

    for (var start = 0;
        start < scanLimit && pending.isNotEmpty;
        start += _batchSize) {
      final end = math.min(start + _batchSize, scanLimit);
      final entities = await album
          .getAssetListRange(start: start, end: end)
          .timeout(const Duration(seconds: 2));
      for (final entity in entities) {
        if (pending.isEmpty) break;
        final matches = <String>[];
        for (final entry in pending.entries) {
          if (_entityMatchesProbe(entity, entry.value)) {
            matches.add(entry.key);
          }
        }
        // Ambiguous: same entity matched multiple pending files — skip.
        if (matches.length != 1) continue;
        final path = matches.first;
        out[path] = GalleryResolvedMetadata(
          assetId: entity.id,
          mediaCreatedAt:
              MediaCaptureTime.wallClock(entity.createDateTime),
        );
        pending.remove(path);
      }
      await Future<void>.delayed(Duration.zero);
    }

    for (final entry in pending.entries) {
      out[entry.key] = GalleryResolvedMetadata(
        mediaCreatedAt: entry.value.captureTime,
      );
    }

    return out;
  }

  /// Back-compat: asset id only.
  static Future<Map<String, String>> resolveAssetIdsForPaths(
    List<String> paths, {
    int maxAlbumScan = _maxAlbumScan,
  }) async {
    final meta = await resolveMetadataForPaths(
      paths,
      maxAlbumScan: maxAlbumScan,
    );
    final out = <String, String>{};
    for (final e in meta.entries) {
      final id = e.value.assetId;
      if (id != null && id.isNotEmpty) out[e.key] = id;
    }
    return out;
  }

  static bool _entityMatchesProbe(AssetEntity entity, _PickedFileProbe probe) {
    final entityIsVideo = entity.type == AssetType.video;
    if (probe.isVideo != entityIsVideo) return false;

    if (probe.isVideo) {
      final dur = entity.videoDuration.inMilliseconds;
      if (dur <= 0) return false;
      if (probe.videoDurationMs > 0 &&
          (dur - probe.videoDurationMs).abs() > 500) {
        return false;
      }
      if (probe.width > 0 &&
          (entity.width != probe.width || entity.height != probe.height)) {
        return false;
      }
      final capture = probe.captureTime;
      if (capture != null) {
        final ageFromNow = DateTime.now().difference(capture).abs();
        final looksLikeCacheCopy = ageFromNow < const Duration(minutes: 3);
        if (!looksLikeCacheCopy) {
          final delta =
              entity.createDateTime.difference(capture).inSeconds.abs();
          return delta <= 3;
        }
      }
      // Android FilePicker cache copy: duration(+dims) is the best signal.
      return probe.videoDurationMs > 0;
    }

    // Images: EXIF time + dims (picker may re-encode — never require byte size).
    if (probe.captureTime == null) return false;
    if (probe.width > 0 &&
        (entity.width != probe.width || entity.height != probe.height)) {
      return false;
    }
    final delta = entity.createDateTime
        .difference(probe.captureTime!)
        .inSeconds
        .abs();
    return delta <= 5;
  }

  static Future<_PickedFileProbe?> _probeFile(
    String path,
    File file,
  ) async {
    try {
      final stat = await file.stat();
      final fileSize = stat.size;
      final lower = path.toLowerCase();
      final isVideo = const [
        '.mp4',
        '.mov',
        '.avi',
        '.mkv',
        '.m4v',
        '.3gp',
      ].any(lower.endsWith);

      if (isVideo) {
        // Never use FilePicker cache mtime as capture — on Android that is the
        // copy time (see logs: video dedupeKey used 04:21 while MediaStore was
        // 02:32). Prefer MP4/MOV mvhd creation time + duration.
        DateTime? mvhdTime;
        var durationMs = 0;
        try {
          final bytes = await MediaCaptureTime.readVideoProbeBytes(file)
              .timeout(const Duration(seconds: 2));
          final mvhd = MediaCaptureTime.parseMp4Mvhd(bytes);
          mvhdTime = mvhd.createdAt;
          durationMs = mvhd.durationMs;
        } catch (_) {}
        return _PickedFileProbe(
          fileSize: fileSize,
          width: 0,
          height: 0,
          isVideo: true,
          videoDurationMs: durationMs,
          captureTime:
              mvhdTime ?? MediaCaptureTime.wallClock(stat.modified),
        );
      }

      // Only the file head — full readAsBytes was freezing Memory View on
      // large camera JPEGs/HEICs.
      DateTime? exifDate;
      int exifWidth = 0, exifHeight = 0;
      try {
        final bytes = await _readFileHead(file, _exifHeadBytes)
            .timeout(const Duration(seconds: 2));
        if (bytes.isNotEmpty) {
          final data = await readExifFromBytes(bytes)
              .timeout(const Duration(seconds: 2));
          if (data.isNotEmpty) {
            final rawDate = data['EXIF DateTimeOriginal']?.printable ??
                data['Image DateTime']?.printable ??
                data['EXIF DateTimeDigitized']?.printable;
            // Local wall-clock — do NOT .toUtc() (Android TZ shift vs MediaStore).
            exifDate = MediaCaptureTime.parseExif(rawDate);
            final wTag = data['EXIF ExifImageWidth'] ?? data['Image ImageWidth'];
            final hTag =
                data['EXIF ExifImageLength'] ?? data['Image ImageLength'];
            exifWidth = int.tryParse(wTag?.printable ?? '') ?? 0;
            exifHeight = int.tryParse(hTag?.printable ?? '') ?? 0;
          }
        }
      } catch (_) {}

      return _PickedFileProbe(
        fileSize: fileSize,
        width: exifWidth,
        height: exifHeight,
        isVideo: false,
        videoDurationMs: 0,
        captureTime:
            exifDate ?? MediaCaptureTime.wallClock(stat.modified),
      );
    } catch (e, st) {
      debugPrint('[GalleryAssetResolver] probe $path: $e\n$st');
      return null;
    }
  }

  static Future<Uint8List> _readFileHead(File file, int maxBytes) async {
    final raf = await file.open();
    try {
      final len = await raf.length();
      final n = math.min(len, maxBytes);
      if (n <= 0) return Uint8List(0);
      return await raf.read(n);
    } finally {
      await raf.close();
    }
  }
}

class _PickedFileProbe {
  _PickedFileProbe({
    required this.fileSize,
    required this.width,
    required this.height,
    required this.isVideo,
    required this.videoDurationMs,
    this.captureTime,
  });

  final int fileSize;
  final int width;
  final int height;
  final bool isVideo;
  final int videoDurationMs;
  final DateTime? captureTime;
}
