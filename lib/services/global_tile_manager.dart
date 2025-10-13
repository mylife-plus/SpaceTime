import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../app/modules/map/controllers/map_controller.dart';
import 'offline_settings_service.dart';

class GlobalTileManager {
  static GlobalTileManager? _instance;
  static GlobalTileManager get instance => _instance ??= GlobalTileManager._();

  GlobalTileManager._();

  bool _isInitialized = false;
  String? _cachePath;

  /// Initialize the tile manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Get cache directory
      final cacheDir = await getApplicationCacheDirectory();
      _cachePath = '${cacheDir.path}/mapbox_tiles';

      // Ensure cache directory exists
      final tileCacheDir = Directory(_cachePath!);
      if (!await tileCacheDir.exists()) {
        await tileCacheDir.create(recursive: true);
      }

      // Store cache path in settings
      await OfflineSettingsService.instance.setOfflineCachePath(_cachePath!);

      _isInitialized = true;
      debugPrint(
        '✅ GlobalTileManager initialized with cache path: $_cachePath',
      );
    } catch (e) {
      debugPrint('❌ Error initializing GlobalTileManager: $e');
    }
  }

  /// Get the offline cache path
  Future<String> getOfflineCachePath() async {
    await _ensureInitialized();
    return _cachePath ?? '';
  }

  /// Check if tiles are available for specific coordinates and zoom level
  Future<bool> areTilesAvailable(double lat, double lng, int zoom) async {
    await _ensureInitialized();

    try {
      // Check with MapController if available
      if (Get.isRegistered<MapController>()) {
        final mapController = Get.find<MapController>();
        return await mapController.isOfflineDataAvailable();
      }

      // Fallback: check if any tiles are downloaded
      final offlineSettings = OfflineSettingsService.instance;
      return await offlineSettings.areBasicTilesDownloaded();
    } catch (e) {
      debugPrint('❌ Error checking tile availability: $e');
      return false;
    }
  }

  /// Download world base tiles (zoom levels 0-6)
  Future<bool> downloadWorldBaseTiles() async {
    await _ensureInitialized();

    try {
      debugPrint('🌍 Starting world base tiles download...');

      // Check if MapController is available
      if (!Get.isRegistered<MapController>()) {
        debugPrint('❌ MapController not available for tile download');
        return false;
      }

      final mapController = Get.find<MapController>();

      // Initialize offline map components if not already done
      await mapController.initOfflineMap();

      // Download style pack first
      await mapController.downloadStylePack();

      // Download world tiles using MapController's existing functionality
      await mapController.setupOfflineMap();

      // Mark world tiles as downloaded
      await OfflineSettingsService.instance.markWorldTilesDownloaded(true);

      debugPrint('✅ World base tiles download completed');
      return true;
    } catch (e) {
      debugPrint('❌ Error downloading world base tiles: $e');
      return false;
    }
  }

  /// Download regional tiles for specific coordinates
  Future<bool> downloadRegionalTiles(
    double lat,
    double lng, {
    String? regionName,
  }) async {
    await _ensureInitialized();

    try {
      final region =
          regionName ??
          'region_${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';
      debugPrint('📍 Starting regional tiles download for: $region');

      // Check if MapController is available
      if (!Get.isRegistered<MapController>()) {
        debugPrint('❌ MapController not available for regional tile download');
        return false;
      }

      final mapController = Get.find<MapController>();

      // Download tiles for the region
      await mapController.downloadTilesForRegion(region);

      // Mark region as downloaded
      await OfflineSettingsService.instance.markRegionDownloaded(region);

      debugPrint('✅ Regional tiles download completed for: $region');
      return true;
    } catch (e) {
      debugPrint('❌ Error downloading regional tiles: $e');
      return false;
    }
  }

  /// Check if world base tiles are downloaded
  Future<bool> areWorldBaseTilesDownloaded() async {
    await _ensureInitialized();
    return await OfflineSettingsService.instance.areWorldTilesDownloaded();
  }

  /// Get download progress stream (if available from MapController)
  Stream<double>? getDownloadProgress() {
    try {
      if (Get.isRegistered<MapController>()) {
        final mapController = Get.find<MapController>();
        return mapController.tileRegionLoadProgress.stream;
      }
    } catch (e) {
      debugPrint('❌ Error getting download progress: $e');
    }
    return null;
  }

  /// Get cache size in bytes
  Future<int> getCacheSize() async {
    await _ensureInitialized();

    try {
      if (_cachePath == null) return 0;

      final cacheDir = Directory(_cachePath!);
      if (!await cacheDir.exists()) return 0;

      int totalSize = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      return totalSize;
    } catch (e) {
      debugPrint('❌ Error calculating cache size: $e');
      return 0;
    }
  }

  /// Clear tile cache
  Future<bool> clearTileCache() async {
    await _ensureInitialized();

    try {
      debugPrint('🗑️ Clearing tile cache...');

      // Clear MapController cache if available
      if (Get.isRegistered<MapController>()) {
        final mapController = Get.find<MapController>();
        await mapController.removeOfflineResources();
      }

      // Clear local cache directory
      if (_cachePath != null) {
        final cacheDir = Directory(_cachePath!);
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
          await cacheDir.create(recursive: true);
        }
      }

      // Clear settings
      await OfflineSettingsService.instance.markWorldTilesDownloaded(false);
      final regions =
          await OfflineSettingsService.instance.getDownloadedRegions();
      for (final region in regions) {
        // Clear region markers (we'll need to implement this in OfflineSettingsService)
      }

      debugPrint('✅ Tile cache cleared successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Error clearing tile cache: $e');
      return false;
    }
  }

  /// Ensure tiles are available for location picker usage
  Future<bool> ensureTilesForLocationPicker() async {
    await _ensureInitialized();

    try {
      // Check if any tiles are already available
      if (await areTilesAvailable(0, 0, 6)) {
        debugPrint('✅ Tiles already available for location picker');
        return true;
      }

      // Download world base tiles if not available
      debugPrint('📦 Downloading tiles for location picker...');
      return await downloadWorldBaseTiles();
    } catch (e) {
      debugPrint('❌ Error ensuring tiles for location picker: $e');
      return false;
    }
  }

  /// Get formatted cache size string
  Future<String> getFormattedCacheSize() async {
    final sizeBytes = await getCacheSize();

    if (sizeBytes < 1024) {
      return '${sizeBytes} B';
    } else if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    } else if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }
}
