import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../../services/offline_map_service.dart';
import '../../../repositories/offline_map_repository.dart';

class OfflineMapController extends GetxController {
  // Services
  late final OfflineMapService offlineMapService;
  late final OfflineMapRepository offlineMapRepository;

  // Map controller
  MapboxMap? offlineMapboxMap;

  // State
  final RxBool isOfflineModeEnabled = false.obs;
  final RxBool showDownloadOverlay = false.obs;

  @override
  void onInit() {
    super.onInit();
    _initializeServices();
  }

  /// Initialize required services
  void _initializeServices() {
    try {
      offlineMapService = Get.find<OfflineMapService>();
      offlineMapRepository = Get.find<OfflineMapRepository>();
      debugPrint('[OfflineMapController] ✅ Services initialized');
    } catch (e) {
      debugPrint('[OfflineMapController] ❌ Failed to initialize services: $e');
      // Initialize services if not found
      Get.put(OfflineMapService());
      Get.put(OfflineMapRepository());
      offlineMapService = Get.find<OfflineMapService>();
      offlineMapRepository = Get.find<OfflineMapRepository>();
    }
  }

  /// Handle offline map creation
  void onOfflineMapCreated(MapboxMap mapboxMap) {
    offlineMapboxMap = mapboxMap;
    debugPrint('[OfflineMapController] 🗺️ Offline map created');
  }

  /// Start downloading offline map for current region
  Future<void> startDownload() async {
    try {
      debugPrint('[OfflineMapController] 🚀 Starting offline map download...');
      showDownloadOverlay.value = true;

      // Define region geometry (example: Islamabad area)
      final regionGeometry = {
        "type": "Polygon",
        "coordinates": [
          [
            [72.8, 33.5], // Southwest
            [73.2, 33.5], // Southeast
            [73.2, 33.8], // Northeast
            [72.8, 33.8], // Northwest
            [72.8, 33.5], // Close polygon
          ],
        ],
      };

      await offlineMapService.downloadOfflineMap(
        regionGeometry: regionGeometry,
        styleUri: MapboxStyles.MAPBOX_STREETS,
      );

      // Save region metadata
      final regionData = OfflineRegionData(
        id: 'islamabad-region',
        name: 'Islamabad Area',
        geometry: regionGeometry,
        styleUri: MapboxStyles.MAPBOX_STREETS,
        minZoom: 0,
        maxZoom: 16,
        createdAt: DateTime.now(),
        tileCount: offlineMapService.downloadedTileCount.value,
        sizeInMB:
            offlineMapService.downloadedTileCount.value *
            0.01, // Rough estimate
        isComplete: offlineMapService.isOfflineReady.value,
      );

      await offlineMapRepository.saveOfflineRegion(regionData);

      // Save download history
      final historyEntry = DownloadHistoryEntry(
        regionId: 'islamabad-region',
        regionName: 'Islamabad Area',
        downloadDate: DateTime.now(),
        tilesDownloaded: offlineMapService.downloadedTileCount.value,
        sizeInMB: offlineMapService.downloadedTileCount.value * 0.01,
        downloadDuration: const Duration(minutes: 5), // Placeholder
        wasSuccessful: offlineMapService.isOfflineReady.value,
      );

      await offlineMapRepository.saveDownloadHistory(historyEntry);

      debugPrint('[OfflineMapController] ✅ Download completed successfully');
    } catch (e) {
      debugPrint('[OfflineMapController] ❌ Download failed: $e');
      Get.snackbar(
        'Download Failed',
        'Failed to download offline maps: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  /// Toggle offline mode on/off
  Future<void> toggleOfflineMode() async {
    try {
      if (isOfflineModeEnabled.value) {
        await offlineMapService.disableOfflineMode();
        isOfflineModeEnabled.value = false;
        Get.snackbar(
          'Online Mode',
          'Map is now using online tiles',
          snackPosition: SnackPosition.BOTTOM,
        );
      } else {
        await offlineMapService.enableOfflineMode();
        isOfflineModeEnabled.value = true;
        Get.snackbar(
          'Offline Mode',
          'Map is now using offline tiles',
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      debugPrint('[OfflineMapController] ❌ Failed to toggle offline mode: $e');
    }
  }

  /// Clear all offline data
  Future<void> clearOfflineData() async {
    try {
      await offlineMapService.clearOfflineData();
      await offlineMapRepository.clearAllOfflineData();

      isOfflineModeEnabled.value = false;
      showDownloadOverlay.value = false;

      Get.snackbar(
        'Data Cleared',
        'All offline map data has been cleared',
        snackPosition: SnackPosition.BOTTOM,
      );

      debugPrint('[OfflineMapController] ✅ Offline data cleared');
    } catch (e) {
      debugPrint('[OfflineMapController] ❌ Failed to clear offline data: $e');
    }
  }

  /// Hide download overlay
  void hideDownloadOverlay() {
    showDownloadOverlay.value = false;
  }

  /// Show download overlay
  void showDownloadOverlayWidget() {
    showDownloadOverlay.value = true;
  }

  /// Check if offline tiles should be used automatically
  Future<void> checkAndUseOfflineTiles() async {
    try {
      if (offlineMapService.isOfflineReady.value &&
          offlineMapService.downloadedTileCount.value >= 40000) {
        final preferences = await offlineMapRepository.getOfflinePreferences();
        if (preferences.enableOfflineModeAutomatically) {
          await offlineMapService.enableOfflineMode();
          isOfflineModeEnabled.value = true;
          debugPrint(
            '[OfflineMapController] ✅ Automatically enabled offline mode',
          );
        }
      }
    } catch (e) {
      debugPrint('[OfflineMapController] ❌ Failed to check offline tiles: $e');
    }
  }

  @override
  void onClose() {
    offlineMapboxMap = null;
    super.onClose();
  }
}
