import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../repositories/offline_map_repository.dart';
import 'offline_map_service.dart';

/// Service that coordinates offline map downloading, UI state, and user interactions
/// This service acts as a bridge between the MapController and the core OfflineMapService
class OfflineMapCoordinatorService extends GetxService {
  static OfflineMapCoordinatorService get to => Get.find();

  // Dependencies
  OfflineMapService? _offlineMapService;
  OfflineMapRepository? _offlineMapRepository;

  // UI State
  final RxBool showOfflineDownloadOverlay = false.obs;
  final RxBool isOfflineMode = false.obs;
  final RxBool isInitialized = false.obs;

  // Streams for UI updates
  final StreamController<String> _statusUpdates = StreamController.broadcast();
  Stream<String> get statusUpdates => _statusUpdates.stream;

  @override
  Future<void> onInit() async {
    super.onInit();
    await _initializeServices();
    await _checkInitialOfflineStatus();
    _setupListeners();
  }

  @override
  void onClose() {
    _statusUpdates.close();
    super.onClose();
  }

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  Future<void> _initializeServices() async {
    try {
      // Initialize offline map service
      try {
        _offlineMapService = Get.find<OfflineMapService>();
        debugPrint('[OfflineMapCoordinator] OfflineMapService found');
      } catch (e) {
        debugPrint('[OfflineMapCoordinator] Creating OfflineMapService: $e');
        Get.put(OfflineMapService());
        _offlineMapService = Get.find<OfflineMapService>();
      }

      // Wait for the service to initialize
      if (_offlineMapService != null) {
        // Give the service time to initialize
        await Future.delayed(const Duration(milliseconds: 500));
        debugPrint('[OfflineMapCoordinator] Service initialized: ${_offlineMapService!.isInitialized.value}');
      }

      // Initialize offline map repository
      try {
        _offlineMapRepository = Get.find<OfflineMapRepository>();
        debugPrint('[OfflineMapCoordinator] OfflineMapRepository found');
      } catch (e) {
        debugPrint('[OfflineMapCoordinator] Creating OfflineMapRepository: $e');
        Get.put(OfflineMapRepository());
        _offlineMapRepository = Get.find<OfflineMapRepository>();
      }

      isInitialized.value = true;
      debugPrint('[OfflineMapCoordinator] ✅ Services initialized');
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Failed to initialize services: $e');
    }
  }

  void _setupListeners() {
    if (_offlineMapService == null) return;

    // Listen to download completion
    ever(_offlineMapService!.isOfflineReady, (bool isReady) {
      if (isReady) {
        debugPrint('[OfflineMapCoordinator] 🎉 Offline download completed');
        _statusUpdates.add('Offline download completed');
        _configureOfflineMode();
      }
    });

    // Listen to download state changes (when download actually finishes)
    ever(_offlineMapService!.isDownloading, (bool isDownloading) {
      if (!isDownloading && _offlineMapService!.downloadedTileCount.value >= 500) {
        debugPrint('[OfflineMapCoordinator] 🎉 Tile download completed with ${_offlineMapService!.downloadedTileCount.value} tiles');
        _hideDownloadOverlayAfterCompletion();
      }
    });

    // Listen to tile count changes for real-time updates
    ever(_offlineMapService!.downloadedTileCount, (int tileCount) {
      if (tileCount > 0 && !isOfflineMode.value) {
        debugPrint('[OfflineMapCoordinator] 🎯 New tiles available ($tileCount)');
        _statusUpdates.add('Downloaded $tileCount tiles');
        _configureOfflineMode();
      }
    });

    // Listen to download progress
    ever(_offlineMapService!.downloadStatusText, (String status) {
      _statusUpdates.add(status);
    });
  }

  // ============================================================================
  // OFFLINE STATUS MANAGEMENT
  // ============================================================================

  Future<void> _checkInitialOfflineStatus() async {
    try {
      if (_offlineMapService == null) return;

      final tileCount = _offlineMapService!.downloadedTileCount.value;

      if (tileCount > 0) {
        debugPrint('[OfflineMapCoordinator] ✅ Found $tileCount offline tiles');
        await _enableOfflineModeIfAllowed();
        // // // showOfflineDownloadOverlay.value = false;
      } else {
        debugPrint('[OfflineMapCoordinator] 📥 No offline tiles found');
        showOfflineDownloadOverlay.value = true;
      }
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Error checking offline status: $e');
    }
  }

  Future<void> _configureOfflineMode() async {
    try {
      if (_offlineMapService == null) return;

      final tileCount = _offlineMapService!.downloadedTileCount.value;
      final isDownloading = _offlineMapService!.isDownloading.value;

      if (tileCount > 0) {
        debugPrint('[OfflineMapCoordinator] 🗺️ Configuring offline mode with $tileCount tiles');

        // Only enable offline mode if we have enough tiles AND download is complete
        if (tileCount >= 500 && !isDownloading) {
          debugPrint('[OfflineMapCoordinator] ✅ Sufficient tiles downloaded - enabling offline mode');
          await _enableOfflineModeIfAllowed();
          // Note: Banner hiding is handled by _hideDownloadOverlayAfterCompletion()

          // Success notification removed as requested
        } else if (isDownloading) {
          debugPrint('[OfflineMapCoordinator] 📥 Download in progress - keeping overlay visible');
          // Keep overlay visible during download - don't hide it
        } else {
          debugPrint('[OfflineMapCoordinator] ⏳ Need more tiles for offline mode ($tileCount/500)');
        }
      }
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Error configuring offline mode: $e');
    }
  }

  /// Hide download overlay after successful completion
  void _hideDownloadOverlayAfterCompletion() {
    try {
      final tileCount = _offlineMapService?.downloadedTileCount.value ?? 0;
      debugPrint('[OfflineMapCoordinator] 🎯 Hiding download overlay after completion ($tileCount tiles)');

      showOfflineDownloadOverlay.value = false;

      // Download completion notification removed as requested
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Error hiding overlay: $e');
    }
  }

  Future<void> _enableOfflineModeIfAllowed() async {
    try {
      final preferences = await _offlineMapRepository?.getOfflinePreferences();
      if (preferences?.enableOfflineModeAutomatically != false) {
        await _offlineMapService!.enableOfflineMode();
        isOfflineMode.value = true;
        debugPrint('[OfflineMapCoordinator] 🔌 Offline mode enabled automatically');
      } else {
        debugPrint('[OfflineMapCoordinator] 📱 Auto-enable disabled in preferences');
      }
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Error enabling offline mode: $e');
    }
  }

  /// Check if offline tiles are available and enable offline mode if possible
  /// Returns true if offline mode was successfully enabled
  Future<bool> checkAndEnableOfflineMode() async {
    try {
      if (_offlineMapService == null) {
        debugPrint('[OfflineMapCoordinator] ❌ OfflineMapService not available');
        return false;
      }

      final tileCount = _offlineMapService!.downloadedTileCount.value;
      debugPrint('[OfflineMapCoordinator] 📊 Checking offline tiles: $tileCount tiles available');

      if (tileCount >= 500) { // Minimum threshold for offline mode
        debugPrint('[OfflineMapCoordinator] 🔌 Enabling offline mode with $tileCount tiles');

        // Enable offline mode directly (bypass user preferences for error recovery)
        await _offlineMapService!.enableOfflineMode();
        isOfflineMode.value = true;

        debugPrint('[OfflineMapCoordinator] ✅ Offline mode enabled for error recovery');
        return true;
      } else {
        debugPrint('[OfflineMapCoordinator] ⚠️ Insufficient tiles for offline mode: $tileCount < 500');
        return false;
      }
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Error checking/enabling offline mode: $e');
      return false;
    }
  }

  // ============================================================================
  // PUBLIC API
  // ============================================================================

  /// Auto-start offline download if needed
  Future<void> autoStartDownloadIfNeeded() async {
    if (_offlineMapService == null) {
      debugPrint('[OfflineMapCoordinator] ⚠️ Service not available for auto-download');
      return;
    }

    // Wait a bit more for service to initialize if needed
    if (!_offlineMapService!.isInitialized.value) {
      debugPrint('[OfflineMapCoordinator] ⏳ Waiting for service to initialize...');
      await Future.delayed(const Duration(seconds: 2));

      if (!_offlineMapService!.isInitialized.value) {
        debugPrint('[OfflineMapCoordinator] ❌ Service failed to initialize, showing overlay');
        showOfflineDownloadOverlay.value = true;
        return;
      }
    }

    final tileCount = _offlineMapService!.downloadedTileCount.value;
    debugPrint('[OfflineMapCoordinator] Current tile count: $tileCount');

    // If we have tiles, use them
    if (tileCount > 0) {
      debugPrint('[OfflineMapCoordinator] ✅ Already have $tileCount tiles');
      // // // showOfflineDownloadOverlay.value = false;
      return;
    }

    // Check if download is already in progress
    if (_offlineMapService!.isDownloading.value) {
      debugPrint('[OfflineMapCoordinator] ⏳ Download already in progress');
      return;
    }

    debugPrint('[OfflineMapCoordinator] 🚀 Auto-starting offline download...');

    try {
      await startOfflineDownload();
      debugPrint('[OfflineMapCoordinator] ✅ Auto-download initiated');
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Auto-download failed: $e');
      showOfflineDownloadOverlay.value = true;
    }
  }

  /// Start downloading offline map tiles
  Future<void> startOfflineDownload({mapbox.MapboxMap? mapboxMap}) async {
    try {
      if (_offlineMapService == null) {
        debugPrint('[OfflineMapCoordinator] ❌ OfflineMapService not available');
        return;
      }

      debugPrint('[OfflineMapCoordinator] 🚀 Starting offline download...');
      debugPrint('[OfflineMapCoordinator] Service initialized: ${_offlineMapService!.isInitialized.value}');
      debugPrint('[OfflineMapCoordinator] Already downloading: ${_offlineMapService!.isDownloading.value}');

      // Show download overlay when starting download
      showOfflineDownloadOverlay.value = true;
      debugPrint('[OfflineMapCoordinator] 📱 Showing download progress overlay');

      // Get region geometry based on current map bounds or default
      final regionGeometry = await _getDownloadRegionGeometry(mapboxMap);
      debugPrint('[OfflineMapCoordinator] Region geometry: $regionGeometry');

      await _offlineMapService!.downloadOfflineMap(
        regionGeometry: regionGeometry,
        styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
      );

      // Save region metadata
      await _saveRegionMetadata(regionGeometry);

      debugPrint('[OfflineMapCoordinator] ✅ Download initiated');
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Download failed: $e');
      Get.snackbar(
        'Download Failed',
        'Failed to download offline maps: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
      );
    }
  }

  /// Toggle offline mode on/off
  Future<void> toggleOfflineMode() async {
    try {
      if (_offlineMapService == null) return;

      if (isOfflineMode.value) {
        await _offlineMapService!.disableOfflineMode();
        isOfflineMode.value = false;
        debugPrint('[OfflineMapCoordinator] 🌐 Disabled offline mode');

        Get.snackbar(
          'Online Mode',
          'Map is now using online tiles',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green.withValues(alpha: 0.8),
          colorText: Colors.white,
        );
      } else {
        final tileCount = _offlineMapService!.downloadedTileCount.value;
        if (tileCount > 0) {
          await _offlineMapService!.enableOfflineMode();
          isOfflineMode.value = true;
          debugPrint('[OfflineMapCoordinator] 🔌 Enabled offline mode');

          Get.snackbar(
            'Offline Mode',
            'Map is now using offline tiles ($tileCount tiles)',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.blue.withValues(alpha: 0.8),
            colorText: Colors.white,
          );
        } else {
          Get.snackbar(
            'No Offline Tiles',
            'No offline tiles available. Please download tiles first.',
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.orange.withValues(alpha: 0.8),
            colorText: Colors.white,
          );
        }
      }
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Failed to toggle offline mode: $e');
    }
  }

  /// Clear all offline data
  Future<void> clearOfflineData() async {
    try {
      await _offlineMapService?.clearOfflineData();
      await _offlineMapRepository?.clearAllOfflineData();

      isOfflineMode.value = false;
      // // // showOfflineDownloadOverlay.value = false;

      Get.snackbar(
        'Data Cleared',
        'All offline map data has been cleared',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
      );

      debugPrint('[OfflineMapCoordinator] ✅ Offline data cleared');
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Failed to clear offline data: $e');
    }
  }

  /// Hide the offline download overlay
  void hideOfflineDownloadOverlay() {
    // // // showOfflineDownloadOverlay.value = false;
  }

  /// Show the offline download overlay
  void showOfflineDownloadOverlayWidget() {
    showOfflineDownloadOverlay.value = true;
  }

  // ============================================================================
  // GETTERS
  // ============================================================================

  /// Get current tile count
  int get currentTileCount => _offlineMapService?.downloadedTileCount.value ?? 0;

  /// Check if downloading
  bool get isDownloading => _offlineMapService?.isDownloading.value ?? false;

  /// Check if offline ready
  bool get isOfflineReady => _offlineMapService?.isOfflineReady.value ?? false;

  /// Get download progress
  double get downloadProgress => _offlineMapService?.tileRegionProgress.value ?? 0.0;

  /// Get current status
  String get currentStatus => _offlineMapService?.downloadStatusText.value ?? 'Unknown';

  // ============================================================================
  // PRIVATE HELPERS
  // ============================================================================

  /// Get the region geometry for downloading
  Future<Map<String, dynamic>> _getDownloadRegionGeometry(mapbox.MapboxMap? mapboxMap) async {
    try {
      // Try to get current map bounds if map is available
      if (mapboxMap != null) {
        try {
          final cameraState = await mapboxMap.getCameraState();
          final center = cameraState.center;

          // Create a region around the current center (approximately 100km radius to stay within 750 tile limit)
          final lat = center.coordinates.lat;
          final lng = center.coordinates.lng;
          final offset = 0.9; // Approximately 100km at equator (to stay within 750 tile limit)

          debugPrint('[OfflineMapCoordinator] Using current map center for download region');
          return {
            'type': 'Polygon',
            'coordinates': [
              [
                [lng - offset, lat - offset], // Southwest
                [lng + offset, lat - offset], // Southeast
                [lng + offset, lat + offset], // Northeast
                [lng - offset, lat + offset], // Northwest
                [lng - offset, lat - offset], // Close polygon
              ]
            ]
          };
        } catch (e) {
          debugPrint('[OfflineMapCoordinator] ⚠️ Could not get map center: $e');
        }
      }

      // Fallback to a smaller region (Islamabad-Lahore area to stay within 750 tile limit)
      debugPrint('[OfflineMapCoordinator] Using default smaller region for download');
      return {
        'type': 'Polygon',
        'coordinates': [
          [
            [72.5, 31.0], // Southwest (Lahore area)
            [74.5, 31.0], // Southeast
            [74.5, 34.0], // Northeast (Islamabad area)
            [72.5, 34.0], // Northwest
            [72.5, 31.0], // Close polygon
          ]
        ]
      };
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ❌ Error getting region geometry: $e');
      // Return minimal fallback region
      return {
        'type': 'Polygon',
        'coordinates': [
          [
            [-1.0, -1.0],
            [1.0, -1.0],
            [1.0, 1.0],
            [-1.0, 1.0],
            [-1.0, -1.0],
          ]
        ]
      };
    }
  }

  /// Save region metadata to repository
  Future<void> _saveRegionMetadata(Map<String, dynamic> regionGeometry) async {
    try {
      if (_offlineMapRepository != null && _offlineMapService != null) {
        final regionData = OfflineRegionData(
          id: 'spacetime-main-region',
          name: 'SpaceTime Main Region',
          geometry: regionGeometry,
          styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
          minZoom: 5,
          maxZoom: 15,
          createdAt: DateTime.now(),
          tileCount: _offlineMapService!.downloadedTileCount.value,
          sizeInMB: _offlineMapService!.downloadedTileCount.value * 0.01, // Rough estimate
          isComplete: _offlineMapService!.isOfflineReady.value,
        );

        await _offlineMapRepository!.saveOfflineRegion(regionData);
        debugPrint('[OfflineMapCoordinator] ✅ Saved region metadata');
      }
    } catch (e) {
      debugPrint('[OfflineMapCoordinator] ⚠️ Failed to save region metadata: $e');
    }
  }
}
