import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'background_tile_download_service_copy.dart';

/// Helper class to use the BackgroundTileDownloadServiceCopy
/// 
/// This provides a simple interface to initialize and use the copy version
/// of the downloading service without affecting the original service.
class DownloadServiceCopyHelper {
  /// Initialize the copy service
  /// 
  /// This should be called once at app startup or when you want to start
  /// using the copy service.
  /// 
  /// Example:
  /// ```dart
  /// await DownloadServiceCopyHelper.initialize(
  ///   tileStore: myTileStore,
  ///   offlineManager: myOfflineManager,
  /// );
  /// ```
  static Future<void> initialize({
    required mapbox.TileStore? tileStore,
    required mapbox.OfflineManager? offlineManager,
  }) async {
    // Register the service if not already registered
    if (!Get.isRegistered<BackgroundTileDownloadServiceCopy>()) {
      Get.put(BackgroundTileDownloadServiceCopy(), permanent: true);
    }

    // Get the service instance
    final service = Get.find<BackgroundTileDownloadServiceCopy>();

    // Initialize with dependencies
    await service.initialize(
      tileStore: tileStore,
      offlineManager: offlineManager,
    );

    print('[DownloadServiceCopyHelper] Copy service initialized successfully');
  }

  /// Get the copy service instance
  /// 
  /// Returns the BackgroundTileDownloadServiceCopy instance.
  /// Make sure to call initialize() first.
  /// 
  /// Example:
  /// ```dart
  /// final service = DownloadServiceCopyHelper.getService();
  /// final status = service.getCurrentQuotaStatus();
  /// ```
  static BackgroundTileDownloadServiceCopy getService() {
    if (!Get.isRegistered<BackgroundTileDownloadServiceCopy>()) {
      throw Exception(
        'BackgroundTileDownloadServiceCopy not initialized. Call DownloadServiceCopyHelper.initialize() first.',
      );
    }
    return Get.find<BackgroundTileDownloadServiceCopy>();
  }

  /// Check if the copy service is initialized
  /// 
  /// Returns true if the service has been registered and initialized.
  static bool isInitialized() {
    return Get.isRegistered<BackgroundTileDownloadServiceCopy>();
  }

  /// Start downloading a specific region
  /// 
  /// Downloads map tiles for the specified region with the given zoom levels.
  /// 
  /// Parameters:
  /// - [bounds]: The geographic bounds of the region to download
  /// - [zoomLevels]: List of zoom levels to download (e.g., [10, 11, 12])
  /// 
  /// Example:
  /// ```dart
  /// await DownloadServiceCopyHelper.downloadRegion(
  ///   bounds: mapbox.CoordinateBounds(
  ///     southwest: mapbox.Point(coordinates: mapbox.Position(-74.0, 40.7)),
  ///     northeast: mapbox.Point(coordinates: mapbox.Position(-73.9, 40.8)),
  ///     infiniteBounds: false,
  ///   ),
  ///   zoomLevels: [10, 11, 12],
  /// );
  /// ```
  static Future<void> downloadRegion({
    required mapbox.CoordinateBounds bounds,
    required List<int> zoomLevels,
  }) async {
    final service = getService();
    await service.downloadRegion(bounds, zoomLevels);
    print('[DownloadServiceCopyHelper] Region download started');
  }

  /// Get current download quota status
  /// 
  /// Returns information about current tile usage, limits, and warnings.
  /// 
  /// Example:
  /// ```dart
  /// final status = DownloadServiceCopyHelper.getQuotaStatus();
  /// print('Downloaded: ${status.currentTiles}/${status.maxTiles}');
  /// print('Usage: ${status.usagePercentage.toStringAsFixed(1)}%');
  /// ```
  static TileQuotaStatusCopy getQuotaStatus() {
    final service = getService();
    return service.getCurrentQuotaStatus();
  }

  /// Enable automatic downloads
  /// 
  /// Enables background downloading of map tiles based on user behavior.
  /// 
  /// Example:
  /// ```dart
  /// await DownloadServiceCopyHelper.enableAutoDownloads();
  /// ```
  static Future<void> enableAutoDownloads() async {
    final service = getService();
    await service.enableAutoDownloads();
    print('[DownloadServiceCopyHelper] Auto downloads enabled');
  }

  /// Disable automatic downloads
  /// 
  /// Stops background downloading of map tiles.
  /// 
  /// Example:
  /// ```dart
  /// await DownloadServiceCopyHelper.disableAutoDownloads();
  /// ```
  static Future<void> disableAutoDownloads() async {
    final service = getService();
    await service.disableAutoDownloads();
    print('[DownloadServiceCopyHelper] Auto downloads disabled');
  }

  /// Clear all pending downloads
  /// 
  /// Removes all regions from the download queue.
  /// 
  /// Example:
  /// ```dart
  /// await DownloadServiceCopyHelper.clearAllDownloads();
  /// ```
  static Future<void> clearAllDownloads() async {
    final service = getService();
    await service.clearAllDownloads();
    print('[DownloadServiceCopyHelper] All downloads cleared');
  }

  /// Reset download quota
  /// 
  /// Resets the tile count and quota limits. Use with caution.
  /// 
  /// Example:
  /// ```dart
  /// await DownloadServiceCopyHelper.resetQuota();
  /// ```
  static Future<void> resetQuota() async {
    final service = getService();
    await service.resetQuota();
    print('[DownloadServiceCopyHelper] Quota reset');
  }

  /// Set maximum tile limit
  /// 
  /// Sets the maximum number of tiles that can be downloaded.
  /// 
  /// Parameters:
  /// - [maxTiles]: Maximum number of tiles (default: 50,000)
  /// 
  /// Example:
  /// ```dart
  /// await DownloadServiceCopyHelper.setMaxTileLimit(100000);
  /// ```
  static Future<void> setMaxTileLimit(int maxTiles) async {
    final service = getService();
    await service.setTileQuota(maxTiles);
    print('[DownloadServiceCopyHelper] Max tile limit set to $maxTiles');
  }

  /// Get download progress
  /// 
  /// Returns the current download progress as a value between 0.0 and 1.0.
  /// 
  /// Example:
  /// ```dart
  /// final progress = DownloadServiceCopyHelper.getDownloadProgress();
  /// print('Progress: ${(progress * 100).toStringAsFixed(1)}%');
  /// ```
  static double getDownloadProgress() {
    final service = getService();
    return service.downloadProgress.value;
  }

  /// Check if currently downloading
  /// 
  /// Returns true if a download is currently in progress.
  /// 
  /// Example:
  /// ```dart
  /// if (DownloadServiceCopyHelper.isDownloading()) {
  ///   print('Download in progress...');
  /// }
  /// ```
  static bool isDownloading() {
    final service = getService();
    return service.isDownloading.value;
  }

  /// Get total tiles downloaded
  /// 
  /// Returns the total number of tiles downloaded so far.
  /// 
  /// Example:
  /// ```dart
  /// final totalTiles = DownloadServiceCopyHelper.getTotalTilesDownloaded();
  /// print('Total tiles: $totalTiles');
  /// ```
  static int getTotalTilesDownloaded() {
    final service = getService();
    return service.totalTilesDownloaded.value;
  }

  /// Get download queue length
  /// 
  /// Returns the number of regions waiting to be downloaded.
  /// 
  /// Example:
  /// ```dart
  /// final queueLength = DownloadServiceCopyHelper.getQueueLength();
  /// print('Regions in queue: $queueLength');
  /// ```
  static int getQueueLength() {
    final service = getService();
    return service.downloadQueue.length;
  }

  /// Get current download region ID
  /// 
  /// Returns the ID of the region currently being downloaded, or empty string if none.
  /// 
  /// Example:
  /// ```dart
  /// final regionId = DownloadServiceCopyHelper.getCurrentDownloadRegion();
  /// if (regionId.isNotEmpty) {
  ///   print('Downloading region: $regionId');
  /// }
  /// ```
  static String getCurrentDownloadRegion() {
    final service = getService();
    return service.currentDownloadRegion.value;
  }

  /// Check if in forced offline mode
  /// 
  /// Returns true if the quota has been reached and offline mode is forced.
  /// 
  /// Example:
  /// ```dart
  /// if (DownloadServiceCopyHelper.isForceOfflineMode()) {
  ///   print('Quota reached - using offline maps only');
  /// }
  /// ```
  static bool isForceOfflineMode() {
    final service = getService();
    return service.forceOfflineMode.value;
  }
}

