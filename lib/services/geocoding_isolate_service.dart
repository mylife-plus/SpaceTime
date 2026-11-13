import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/helpers/nearest_region_service.dart';
import 'package:spacetime/app/utils/offline_geocoder.dart';

/// Service that handles reverse geocoding operations using non-blocking approach
class GeocodingIsolateService extends GetxService {
  static GeocodingIsolateService get instance => Get.find();

  // State management
  final RxBool isInitialized = false.obs;
  final RxInt activeRequests = 0.obs;
  Future<void>? _warmFuture;

  @override
  Future<void> onInit() async {
    super.onInit();
    // Kick warm-up without blocking GetX registration — callers await via
    // [ensureInitialized] / [warmUp] / [reverseGeocode].
    unawaited(warmUp());
  }

  /// Prefetch OfflineGeocoder + NearestRegion CSVs so the first Add Memories
  /// location pin is not stuck waiting on a multi-second cold parse.
  Future<void> warmUp() async {
    if (isInitialized.value && OfflineGeocoder.instance.isInitialized) {
      return;
    }
    _warmFuture ??= _warmUpImpl();
    await _warmFuture;
  }

  Future<void> _warmUpImpl() async {
    try {
      final geocoder = OfflineGeocoder.instance;
      await geocoder.init().timeout(const Duration(seconds: 12));
      // Region names (FCT, etc.) — load in parallel with nothing else once
      // cities CSV is ready; first findNearest() used to return null.
      await NearestRegionService()
          .loadFromAssets()
          .timeout(const Duration(seconds: 8));
      isInitialized.value = true;
      debugPrint(
        '[GeocodingIsolateService] Warm-up complete (OfflineGeocoder + NearestRegion)',
      );
    } catch (e) {
      debugPrint(
        '[GeocodingIsolateService] Failed to warm geocoding: $e',
      );
      isInitialized.value = false;
      // Allow a later retry after a failed/timed-out warm-up.
      _warmFuture = null;
    }
  }

  /// Reverse geocode coordinates using non-blocking approach
  Future<Map<String, dynamic>?> reverseGeocode(
    double latitude,
    double longitude, {
    String? tileSubRegion,
  }) async {
    try {
      debugPrint(
        '[GeocodingIsolateService] Non-blocking geocoding: $latitude, $longitude',
      );

      // Always wait for CSV/KD-tree — calling search() before init threw
      // LateInitializationError and left memory location names empty.
      final ready = await ensureInitialized();
      if (!ready) {
        debugPrint('[GeocodingIsolateService] Not ready — geocode skipped');
        return null;
      }

      activeRequests.value++;

      final result = await _performGeocodingAsync(
        latitude,
        longitude,
        tileSubRegion: tileSubRegion,
      );

      activeRequests.value--;

      debugPrint('[GeocodingIsolateService] Geocoding completed: $result');
      return result;
    } catch (e) {
      activeRequests.value--;
      debugPrint('[GeocodingIsolateService] Geocoding error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _performGeocodingAsync(
    double latitude,
    double longitude, {
    String? tileSubRegion,
  }) async {
    try {
      final geocoder = OfflineGeocoder.instance;
      return await geocoder.reverseGeocode(
        latitude,
        longitude,
        tileSubRegion: tileSubRegion,
      );
    } catch (e) {
      debugPrint('[GeocodingIsolateService] Async geocoding error: $e');
      return null;
    }
  }

  /// Ensure service is initialized and ready.
  /// Hard-capped so Media GPS upload cannot hang forever on CSV load.
  Future<bool> ensureInitialized({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (isInitialized.value && OfflineGeocoder.instance.isInitialized) {
      return true;
    }

    debugPrint(
      '[GeocodingIsolateService] Service not initialized, attempting to initialize...',
    );

    try {
      await warmUp().timeout(timeout);
      return isInitialized.value && OfflineGeocoder.instance.isInitialized;
    } catch (e) {
      debugPrint('[GeocodingIsolateService] Failed to initialize service: $e');
      isInitialized.value = false;
      return false;
    }
  }

  /// Get current service status
  Map<String, dynamic> getStatus() {
    return {
      'isInitialized': isInitialized.value,
      'activeRequests': activeRequests.value,
    };
  }
}
