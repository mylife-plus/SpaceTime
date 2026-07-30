import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';
import 'package:spacetime/app/utils/concurrency.dart';

/// Shared option for gallery reads (photos/videos) used by permission checks and requests.
///
/// [mediaLocation] must be true on Android 10+ or [AssetEntity.latlngAsync] returns
/// no coordinates and Upload Files scans the whole library looking for GPS forever.
const PermissionRequestOption kMediaGpsGalleryPermissionRequest =
    PermissionRequestOption(
  androidPermission: AndroidPermission(
    type: RequestType.common,
    mediaLocation: true,
  ),
  iosAccessLevel: IosAccessLevel.readWrite,
);

class MediaGpsGalleryService {
  static const int _firstPageSize = 800;

  /// Upper bound on library positions scanned per album when collecting GPS assets.
  static const int _maxAlbumPositionsScan = 8000;

  /// Parallel EXIF / location reads. Keep modest on mid-range Android to
  /// avoid ExifInterface thrashing / input ANRs while the gallery is open.
  static const int _gpsCheckConcurrency = 4;

  /// If this many assets yield zero GPS, stop (missing ACCESS_MEDIA_LOCATION).
  static const int _earlyAbortAfterNoGps = 400;

  /// Does not prompt — used before localized priming dialogs elsewhere.
  static Future<bool> hasAuthorizedGalleryAccess() async {
    final PermissionState ps = await PhotoManager.getPermissionState(
      requestOption: kMediaGpsGalleryPermissionRequest,
    );
    return ps.hasAccess;
  }

  /// Ensures Photos access **and** media-location on Android (needed after
  /// upgrading an install that previously granted photos without location).
  static Future<bool> ensureMediaLocationAccess() async {
    if (!Platform.isAndroid) {
      return hasAuthorizedGalleryAccess();
    }
    final state = await PhotoManager.requestPermissionExtend(
      requestOption: kMediaGpsGalleryPermissionRequest,
    );
    return state.hasAccess;
  }

  static Future<MediaGpsPickedAsset?> _gpsAssetOrNull(AssetEntity e) async {
    try {
      final t = e.createDateTime;
      // Prefer sync fields when present; fall back to EXIF via latlngAsync.
      double? lat = e.latitude;
      double? lng = e.longitude;
      if (lat == null ||
          lng == null ||
          (lat == 0 && lng == 0) ||
          lat.isNaN ||
          lng.isNaN) {
        final latlng = await e.latlngAsync();
        lat = latlng?.latitude;
        lng = latlng?.longitude;
      }
      final dur = (e.type == AssetType.video || e.type == AssetType.audio)
          ? e.videoDuration
          : Duration.zero;
      final picked = MediaGpsPickedAsset.fromGallery(
        entity: e,
        createTime: t,
        latitude: lat,
        longitude: lng,
        width: e.width,
        height: e.height,
        orientation: e.orientation,
        modifiedTime: e.modifiedDateTime,
        fileTitle: e.title,
        videoDuration: dur,
      );
      if (!picked.hasGps) return null;
      return picked;
    } catch (err, st) {
      debugPrint('[MediaGpsGalleryService] skip asset ${e.id}: $err\n$st');
      return null;
    }
  }

  static Future<void> _collectGpsAssetsFromAlbum({
    required AssetPathEntity album,
    required Map<String, MediaGpsPickedAsset> out,
    required int targetUniqueCount,
    required int maxPositionsToScan,
    void Function(List<MediaGpsPickedAsset> snapshot)? onProgress,
    VoidCallback? onFirstBatchDone,
  }) async {
    final totalAlbum = await album.assetCountAsync;
    final scanLimit = math.min(totalAlbum, maxPositionsToScan);
    if (scanLimit == 0) {
      onFirstBatchDone?.call();
      return;
    }

    const batchSize = 200;
    var scanned = 0;
    var firstBatch = true;

    void emitProgress() {
      if (onProgress == null) return;
      final list = out.values.toList()
        ..sort((a, b) => b.createTime.compareTo(a.createTime));
      onProgress(list);
    }

    for (var start = 0;
        start < scanLimit && out.length < targetUniqueCount;
        start += batchSize) {
      final end = math.min(start + batchSize, scanLimit);
      final entities = await album.getAssetListRange(start: start, end: end);
      scanned += entities.length;

      final found = await mapWithConcurrency<AssetEntity, MediaGpsPickedAsset?>(
        entities,
        _gpsCheckConcurrency,
        (e, _) => _gpsAssetOrNull(e),
      );
      for (final picked in found) {
        if (picked == null) continue;
        if (out.length >= targetUniqueCount) break;
        out[picked.id] = picked;
      }

      emitProgress();
      if (firstBatch) {
        firstBatch = false;
        onFirstBatchDone?.call();
      }

      if (out.isEmpty && scanned >= _earlyAbortAfterNoGps) {
        debugPrint(
          '[MediaGpsGalleryService] aborting GPS scan after $scanned '
          'assets with 0 GPS hits (check ACCESS_MEDIA_LOCATION)',
        );
        return;
      }
    }

    if (firstBatch) onFirstBatchDone?.call();
  }

  /// Recent photos / videos **with GPS in library metadata** only (newest batch first).
  ///
  /// [onProgress] is called as GPS assets are found so the UI can leave the
  /// spinner and allow selection before the full scan finishes.
  /// [onFirstBatchDone] fires after the first EXIF batch so the spinner can clear
  /// even when that batch has no GPS yet (user can use + / empty state).
  static Future<List<MediaGpsPickedAsset>> loadRecentAssets({
    int maxCount = _firstPageSize,
    void Function(List<MediaGpsPickedAsset> snapshot)? onProgress,
    VoidCallback? onFirstBatchDone,
  }) async {
    if (!await hasAuthorizedGalleryAccess()) {
      onFirstBatchDone?.call();
      return [];
    }

    final merged = <String, MediaGpsPickedAsset>{};

    // Photos + videos only (RequestType.common excludes audio); audio is not
    // importable in this flow.
    final commonPaths =
        await PhotoManager.getAssetPathList(type: RequestType.common);
    if (commonPaths.isNotEmpty) {
      await _collectGpsAssetsFromAlbum(
        album: commonPaths.first,
        out: merged,
        targetUniqueCount: maxCount,
        maxPositionsToScan: _maxAlbumPositionsScan,
        onProgress: onProgress,
        onFirstBatchDone: onFirstBatchDone,
      );
    } else {
      onFirstBatchDone?.call();
    }

    if (merged.isEmpty) return [];

    final list = merged.values.toList()
      ..sort((a, b) => b.createTime.compareTo(a.createTime));
    if (list.length > maxCount) {
      return list.take(maxCount).toList();
    }
    return list;
  }

  /// Copies asset to a temp file (image, video, or audio) for import pipeline.
  static Future<String?> exportToTempFile(AssetEntity entity) async {
    try {
      final file = await entity.file;
      return file?.path;
    } catch (e, st) {
      debugPrint('[MediaGpsGalleryService] exportToTempFile: $e\n$st');
      return null;
    }
  }

  /// Resolves an on-disk path for gallery or file-picked items.
  static Future<String?> resolveExportPath(MediaGpsPickedAsset asset) async {
    if (asset.isFromFile) {
      final path = asset.localPath;
      if (path == null || path.isEmpty) return null;
      final f = File(path);
      if (await f.exists()) return path;
      return null;
    }
    final entity = asset.entity;
    if (entity == null) return null;
    return exportToTempFile(entity);
  }
}
