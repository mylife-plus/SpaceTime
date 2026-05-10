import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';

/// Shared option for gallery reads (photos/videos/audio) used by permission checks and requests.
const PermissionRequestOption kMediaGpsGalleryPermissionRequest =
    PermissionRequestOption(
  androidPermission: AndroidPermission(
    type: RequestType.common,
    mediaLocation: false,
  ),
  iosAccessLevel: IosAccessLevel.readWrite,
);

class MediaGpsGalleryService {
  static const int _firstPageSize = 800;

  /// Upper bound on library positions scanned per album when collecting GPS assets.
  static const int _maxAlbumPositionsScan = 25000;

  /// Does not prompt — used before localized priming dialogs elsewhere.
  static Future<bool> hasAuthorizedGalleryAccess() async {
    final PermissionState ps = await PhotoManager.getPermissionState(
      requestOption: kMediaGpsGalleryPermissionRequest,
    );
    return ps.hasAccess;
  }

  static Future<void> _collectGpsAssetsFromAlbum({
    required AssetPathEntity album,
    required Map<String, MediaGpsPickedAsset> out,
    required int targetUniqueCount,
    required int maxPositionsToScan,
  }) async {
    final totalAlbum = await album.assetCountAsync;
    final scanLimit = math.min(totalAlbum, maxPositionsToScan);
    if (scanLimit == 0) return;

    const batchSize = 400;

    for (var start = 0;
        start < scanLimit && out.length < targetUniqueCount;
        start += batchSize) {
      final end = math.min(start + batchSize, scanLimit);
      final entities = await album.getAssetListRange(start: start, end: end);
      for (final e in entities) {
        if (out.length >= targetUniqueCount) return;
        try {
          final t = e.createDateTime;
          final latlng = await e.latlngAsync();
          final lat = latlng?.latitude;
          final lng = latlng?.longitude;
          final dur = (e.type == AssetType.video || e.type == AssetType.audio)
              ? e.videoDuration
              : Duration.zero;
          final picked = MediaGpsPickedAsset(
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
          if (!picked.hasGps) continue;
          out[e.id] = picked;
        } catch (err, st) {
          debugPrint('[MediaGpsGalleryService] skip asset ${e.id}: $err\n$st');
        }
      }
    }
  }

  /// Recent photos / videos / audio **with GPS in library metadata** only (newest batch first).
  static Future<List<MediaGpsPickedAsset>> loadRecentAssets({
    int maxCount = _firstPageSize,
  }) async {
    if (!await hasAuthorizedGalleryAccess()) return [];

    final merged = <String, MediaGpsPickedAsset>{};

    final commonPaths =
        await PhotoManager.getAssetPathList(type: RequestType.common);
    if (commonPaths.isNotEmpty) {
      await _collectGpsAssetsFromAlbum(
        album: commonPaths.first,
        out: merged,
        targetUniqueCount: maxCount,
        maxPositionsToScan: _maxAlbumPositionsScan,
      );
    }

    final audioPaths =
        await PhotoManager.getAssetPathList(type: RequestType.audio);
    if (audioPaths.isNotEmpty && merged.length < maxCount) {
      await _collectGpsAssetsFromAlbum(
        album: audioPaths.first,
        out: merged,
        targetUniqueCount: maxCount,
        maxPositionsToScan: _maxAlbumPositionsScan,
      );
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
}
