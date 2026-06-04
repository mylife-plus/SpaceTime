import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';

enum MediaGpsStorageCheckResult {
  ok,
  insufficient,
  unavailable,
}

/// Result of [MediaGpsImportStorageService.validateStorageBeforeImport].
class MediaGpsStorageCheckReport {
  const MediaGpsStorageCheckReport({
    required this.result,
    required this.importBytes,
    this.availableBytes,
  });

  final MediaGpsStorageCheckResult result;
  final int importBytes;
  final int? availableBytes;

  bool get canImport => result == MediaGpsStorageCheckResult.ok;
}

/// Estimates import payload size and compares it to free device storage.
///
/// Gallery items use metadata-only estimates — never [AssetEntity.file].
class MediaGpsImportStorageService {
  MediaGpsImportStorageService._();

  static const _diskQueryTimeout = Duration(seconds: 4);

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// Total bytes for images and videos the user is about to import.
  static int calculateImportMediaBytes(Iterable<MediaGpsPickedAsset> assets) {
    final seen = <String>{};
    var total = 0;
    for (final asset in assets) {
      if (!seen.add(asset.id)) continue;
      if (!asset.isImage && !asset.isVideo) continue;
      total += _byteSizeForAsset(asset);
    }
    return total;
  }

  static int _byteSizeForAsset(MediaGpsPickedAsset asset) {
    if (asset.isFromFile) {
      final path = asset.localPath;
      if (path != null && path.isNotEmpty) {
        try {
          final file = File(path);
          if (file.existsSync()) return file.lengthSync();
        } catch (e, st) {
          debugPrint('[MediaGpsImportStorage] file size $path: $e\n$st');
        }
      }
    }
    return _estimateGalleryBytes(asset);
  }

  /// Typical compressed sizes from width/height/duration on [MediaGpsPickedAsset].
  static int _estimateGalleryBytes(MediaGpsPickedAsset asset) {
    if (asset.isVideo) {
      final sec = asset.videoDuration.inSeconds;
      if (sec > 0) {
        return (sec * 2 * 1024 * 1024).clamp(1024 * 1024, 800 * 1024 * 1024);
      }
      return 15 * 1024 * 1024;
    }
    final w = asset.width > 0 ? asset.width : 3000;
    final h = asset.height > 0 ? asset.height : 2000;
    final estimate = (w * h * 0.2).round();
    return estimate.clamp(300 * 1024, 12 * 1024 * 1024);
  }

  /// Free space on device via [device_info_plus] (bytes).
  static Future<int?> fetchAvailableDeviceBytes() async {
    try {
      if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo.timeout(_diskQueryTimeout);
        final bytes = info.freeDiskSize;
        if (bytes > 0) return bytes;
      } else if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo.timeout(_diskQueryTimeout);
        final bytes = info.freeDiskSize;
        if (bytes > 0) return bytes;
      }
    } catch (e, st) {
      debugPrint('[MediaGpsImportStorage] free disk size: $e\n$st');
    }
    return null;
  }

  /// Blocks when import size exceeds available space, or when free space is unreadable.
  static Future<MediaGpsStorageCheckReport> validateStorageBeforeImport(
    Iterable<MediaGpsPickedAsset> assets,
  ) async {
    final importBytes = calculateImportMediaBytes(assets);
    final available = await fetchAvailableDeviceBytes();
    if (available == null) {
      debugPrint(
        '[MediaGpsImportStorage] import ~${(importBytes / (1024 * 1024)).toStringAsFixed(1)} MB, '
        'free space unavailable — blocking import',
      );
      return MediaGpsStorageCheckReport(
        result: MediaGpsStorageCheckResult.unavailable,
        importBytes: importBytes,
      );
    }
    debugPrint(
      '[MediaGpsImportStorage] import ~${(importBytes / (1024 * 1024)).toStringAsFixed(1)} MB, '
      'free ~${(available / (1024 * 1024)).toStringAsFixed(1)} MB',
    );
    if (importBytes > available) {
      return MediaGpsStorageCheckReport(
        result: MediaGpsStorageCheckResult.insufficient,
        importBytes: importBytes,
        availableBytes: available,
      );
    }
    return MediaGpsStorageCheckReport(
      result: MediaGpsStorageCheckResult.ok,
      importBytes: importBytes,
      availableBytes: available,
    );
  }
}
