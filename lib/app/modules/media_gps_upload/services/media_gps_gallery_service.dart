import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_capture_time.dart';
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

/// Cursor for oldest-first GPS paging (PhotoManager index 0 = newest).
class MediaGpsGalleryScanState {
  MediaGpsGalleryScanState({
    required this.commonAlbum,
    required this.commonTotal,
    required this.commonCursorEnd,
    this.videoAlbum,
    this.videoTotal = 0,
    this.videoCursorEnd = 0,
  });

  final AssetPathEntity? commonAlbum;
  final int commonTotal;
  /// Next exclusive end index while scanning toward 0 (oldest → newer).
  int commonCursorEnd;

  final AssetPathEntity? videoAlbum;
  final int videoTotal;
  int videoCursorEnd;

  bool get hasMore {
    final commonMore =
        commonAlbum != null && commonCursorEnd > 0;
    final videoMore = Platform.isAndroid &&
        videoAlbum != null &&
        videoCursorEnd > 0;
    return commonMore || videoMore;
  }
}

class MediaGpsGalleryService {
  /// GPS assets loaded per page (initial + each scroll page).
  static const int pageSize = 50;

  /// Max library positions scanned while filling one page (avoids hanging).
  static const int _maxPositionsPerPage = 4000;

  /// Parallel EXIF / location reads. Keep modest on mid-range Android to
  /// avoid ExifInterface thrashing / input ANRs while the gallery is open.
  static int get _gpsCheckConcurrency => Platform.isIOS ? 6 : 4;

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

  static bool _coordsOk(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (lat.isNaN || lng.isNaN) return false;
    if (lat == 0 && lng == 0) return false;
    return true;
  }

  static Future<MediaGpsPickedAsset?> _gpsAssetOrNull(AssetEntity e) async {
    try {
      // Prefer sync fields when present; fall back to EXIF via latlngAsync.
      // Retry once — concurrent MediaStore/Photos reads often return null first.
      double? lat = e.latitude;
      double? lng = e.longitude;
      if (!_coordsOk(lat, lng)) {
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            final latlng = await e
                .latlngAsync()
                .timeout(const Duration(seconds: 3));
            lat = latlng?.latitude;
            lng = latlng?.longitude;
            if (_coordsOk(lat, lng)) break;
          } catch (_) {
            // retry
          }
          if (attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 60));
          }
        }
      }
      // No GPS → skip before the slower on-device check (keeps iOS scan moving).
      if (!_coordsOk(lat, lng)) return null;

      // On-device only — hide confirmed iCloud-only. Short timeout + optimistic
      // so large libraries don't block the spinner / first grid paint.
      if (!await isOnDevice(e, optimisticOnTimeout: true)) {
        return null;
      }

      // Wall-clock local components — matches EXIF DateTimeOriginal on Android
      // where DATE_TAKEN is a UTC instant and naive EXIF .toUtc() used to drift.
      final t = MediaCaptureTime.wallClock(e.createDateTime);
      // Do NOT probe video file containers here — readMetadata can scan up to
      // 48MB + VideoPlayer init per asset and blocked galleryLoading forever.
      // GPS for gallery items comes from MediaStore / latlngAsync only; file
      // picker (+) still uses MediaGpsFileMetadataService for filesystem GPS.
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

  static List<MediaGpsPickedAsset> sortOldestFirst(
    Iterable<MediaGpsPickedAsset> items,
  ) {
    final list = items.toList()
      ..sort((a, b) => a.createTime.compareTo(b.createTime));
    return list;
  }

  /// Open albums and place cursors at the oldest end (index = total).
  static Future<MediaGpsGalleryScanState?> beginOldestFirstScan() async {
    if (!await hasAuthorizedGalleryAccess()) return null;

    final commonPaths =
        await PhotoManager.getAssetPathList(type: RequestType.common);
    final commonAlbum = commonPaths.isEmpty ? null : commonPaths.first;
    final commonTotal =
        commonAlbum == null ? 0 : await commonAlbum.assetCountAsync;

    AssetPathEntity? videoAlbum;
    var videoTotal = 0;
    if (Platform.isAndroid) {
      final videoPaths =
          await PhotoManager.getAssetPathList(type: RequestType.video);
      if (videoPaths.isNotEmpty) {
        videoAlbum = videoPaths.first;
        videoTotal = await videoAlbum.assetCountAsync;
      }
    }

    return MediaGpsGalleryScanState(
      commonAlbum: commonAlbum,
      commonTotal: commonTotal,
      commonCursorEnd: commonTotal,
      videoAlbum: videoAlbum,
      videoTotal: videoTotal,
      videoCursorEnd: videoTotal,
    );
  }

  /// Fill up to [pageSize] new GPS assets by scanning oldest → newer.
  /// Skips ids already in [excludeIds]. Advances [state] cursors.
  static Future<List<MediaGpsPickedAsset>> loadNextGpsPage({
    required MediaGpsGalleryScanState state,
    Set<String> excludeIds = const {},
    int pageSize = MediaGpsGalleryService.pageSize,
  }) async {
    final out = <String, MediaGpsPickedAsset>{};
    var positionsScanned = 0;

    Future<void> scanAlbum({
      required AssetPathEntity? album,
      required int Function() getCursorEnd,
      required void Function(int) setCursorEnd,
    }) async {
      if (album == null) return;
      while (out.length < pageSize &&
          getCursorEnd() > 0 &&
          positionsScanned < _maxPositionsPerPage) {
        final end = getCursorEnd();
        final start = math.max(0, end - 120);
        final entities = await album.getAssetListRange(start: start, end: end);
        setCursorEnd(start);
        positionsScanned += entities.length;
        if (entities.isEmpty) continue;

        // Range is newest→oldest within the window; check oldest first.
        final ordered = entities.reversed.toList(growable: false);
        final found =
            await mapWithConcurrency<AssetEntity, MediaGpsPickedAsset?>(
          ordered,
          _gpsCheckConcurrency,
          (e, _) => _gpsAssetOrNull(e),
        );
        for (final picked in found) {
          if (picked == null) continue;
          if (excludeIds.contains(picked.id) || out.containsKey(picked.id)) {
            continue;
          }
          out[picked.id] = picked;
          if (out.length >= pageSize) break;
        }
      }
    }

    await scanAlbum(
      album: state.commonAlbum,
      getCursorEnd: () => state.commonCursorEnd,
      setCursorEnd: (v) => state.commonCursorEnd = v,
    );

    if (out.length < pageSize && Platform.isAndroid) {
      await scanAlbum(
        album: state.videoAlbum,
        getCursorEnd: () => state.videoCursorEnd,
        setCursorEnd: (v) => state.videoCursorEnd = v,
      );
    }

    debugPrint(
      '[MediaGpsGalleryService] page +${out.length} GPS '
      '(scanned~$positionsScanned positions, hasMore=${state.hasMore})',
    );
    return sortOldestFirst(out.values);
  }

  /// True when the asset is already on-device (Android always; iOS skips iCloud-only).
  ///
  /// [optimisticOnTimeout]: for gallery listing, a slow Photos reply should not
  /// hide on-phone items. Export still uses `false` so iCloud is never fetched.
  static Future<bool> isOnDevice(
    AssetEntity entity, {
    bool optimisticOnTimeout = false,
  }) async {
    if (Platform.isAndroid) return true;
    try {
      return await entity.isLocallyAvailable(isOrigin: false).timeout(
            Duration(milliseconds: optimisticOnTimeout ? 900 : 3000),
            onTimeout: () => optimisticOnTimeout,
          );
    } catch (_) {
      return optimisticOnTimeout;
    }
  }

  /// Local file only — never triggers an iCloud download.
  static Future<String?> exportToTempFile(AssetEntity entity) async {
    try {
      if (!await isOnDevice(entity, optimisticOnTimeout: false)) {
        debugPrint(
          '[MediaGpsGalleryService] skip iCloud-only asset id=${entity.id}',
        );
        return null;
      }
      // Prefer compressed local file; never call originFile (iCloud fetch).
      final file = await entity.file.timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          debugPrint(
            '[MediaGpsGalleryService] exportToTempFile timeout id=${entity.id}',
          );
          return null;
        },
      );
      return file?.path;
    } catch (e, st) {
      debugPrint('[MediaGpsGalleryService] exportToTempFile: $e\n$st');
      return null;
    }
  }

  /// Resolves an on-disk path for gallery or file-picked items.
  /// Gallery items must already be on the phone — no iCloud export.
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
