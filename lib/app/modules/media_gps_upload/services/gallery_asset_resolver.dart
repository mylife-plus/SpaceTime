import 'dart:io';
import 'dart:math' as math;

import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_gallery_service.dart';
import 'package:video_player/video_player.dart';

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
class GalleryAssetResolver {
  static const int _maxAlbumScan = 4000;
  static const int _batchSize = 400;

  /// Maps absolute/normalized file path → gallery metadata (best effort).
  static Future<Map<String, GalleryResolvedMetadata>> resolveMetadataForPaths(
    List<String> paths, {
    int maxAlbumScan = _maxAlbumScan,
  }) async {
    final out = <String, GalleryResolvedMetadata>{};
    if (paths.isEmpty || kIsWeb) return out;
    if (!await MediaGpsGalleryService.hasAuthorizedGalleryAccess()) {
      return out;
    }

    final pending = <String, _PickedFileProbe>{};
    for (final raw in paths) {
      final path = raw.trim();
      if (path.isEmpty) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      final probe = await _probeFile(path, file);
      if (probe != null) pending[path] = probe;
    }
    if (pending.isEmpty) return out;

    final albums =
        await PhotoManager.getAssetPathList(type: RequestType.common);
    if (albums.isEmpty) {
      for (final entry in pending.entries) {
        out[entry.key] = GalleryResolvedMetadata(
          mediaCreatedAt: entry.value.captureTime,
        );
      }
      return out;
    }

    final album = albums.first;
    final total = await album.assetCountAsync;
    final scanLimit = math.min(total, maxAlbumScan);

    for (var start = 0; start < scanLimit && pending.isNotEmpty; start += _batchSize) {
      final end = math.min(start + _batchSize, scanLimit);
      final entities = await album.getAssetListRange(start: start, end: end);
      for (final entity in entities) {
        if (pending.isEmpty) break;
        final matches = <String>[];
        for (final entry in pending.entries) {
          if (_entityMatchesProbe(entity, entry.value)) {
            matches.add(entry.key);
          }
        }
        for (final path in matches) {
          out[path] = GalleryResolvedMetadata(
            assetId: entity.id,
            mediaCreatedAt: entity.createDateTime.toUtc(),
          );
          pending.remove(path);
        }
      }
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
      if (probe.width > 0 &&
          (entity.width != probe.width || entity.height != probe.height)) {
        return false;
      }
      final dur = entity.videoDuration.inMilliseconds;
      if (dur > 0 && probe.videoDurationMs > 0) {
        if ((dur - probe.videoDurationMs).abs() > 1500) return false;
      }
      return probe.width > 0 || probe.videoDurationMs > 0;
    }

    if (probe.captureTime != null) {
      final delta = entity.createDateTime
          .difference(probe.captureTime!)
          .inSeconds
          .abs();
      if (delta > 5) return false;
    }
    if (probe.width > 0 &&
        (entity.width != probe.width || entity.height != probe.height)) {
      return false;
    }
    return probe.width > 0 || probe.captureTime != null;
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
        int vWidth = 0, vHeight = 0, vDurationMs = 0;
        VideoPlayerController? vc;
        try {
          vc = VideoPlayerController.file(file);
          await vc.initialize();
          final sz = vc.value.size;
          vWidth = sz.width.round();
          vHeight = sz.height.round();
          vDurationMs = vc.value.duration.inMilliseconds;
        } catch (_) {
        } finally {
          await vc?.dispose();
        }
        return _PickedFileProbe(
          fileSize: fileSize,
          width: vWidth,
          height: vHeight,
          isVideo: true,
          videoDurationMs: vDurationMs,
          captureTime: null,
        );
      }

      DateTime? exifDate;
      int exifWidth = 0, exifHeight = 0;
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          final data = await readExifFromBytes(bytes);
          if (data.isNotEmpty) {
            final rawDate = data['EXIF DateTimeOriginal']?.printable ??
                data['Image DateTime']?.printable ??
                data['EXIF DateTimeDigitized']?.printable;
            if (rawDate != null && rawDate.length >= 10) {
              final normalized = rawDate
                  .replaceFirst(':', '-')
                  .replaceFirst(':', '-')
                  .replaceAll(' ', 'T');
              exifDate = DateTime.tryParse(normalized)?.toUtc();
            }
            final wTag = data['EXIF ExifImageWidth'] ?? data['Image ImageWidth'];
            final hTag = data['EXIF ExifImageLength'] ?? data['Image ImageLength'];
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
        captureTime: exifDate,
      );
    } catch (e, st) {
      debugPrint('[GalleryAssetResolver] probe $path: $e\n$st');
      return null;
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
