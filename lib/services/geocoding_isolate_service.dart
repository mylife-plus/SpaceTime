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

  /// Prefetch OfflineGeocoder (+ best-effort NearestRegion) so the first Add
  /// Memories location pin is not stuck waiting on a multi-second cold parse.
  Future<void> warmUp() async {
    if (OfflineGeocoder.instance.isInitialized) {
      isInitialized.value = true;
      return;
    }
    _warmFuture ??= _warmUpImpl();
    await _warmFuture;
  }

  Future<void> _warmUpImpl() async {
    try {
      final geocoder = OfflineGeocoder.instance;
      // Cities CSV + KD-tree can take ~13s on device — must succeed for reverse
      // geocode. Keep this as the only hard requirement.
      await geocoder.init().timeout(const Duration(seconds: 20));

      // Region names (FCT, etc.) are nice-to-have. OfflineGeocoder falls back
      // to state_name when NearestRegion is not ready — do not fail warm-up.
      try {
        await NearestRegionService()
            .loadFromAssets()
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint(
          '[GeocodingIsolateService] NearestRegion warm-up deferred: $e',
        );
      }

      isInitialized.value = OfflineGeocoder.instance.isInitialized;
      debugPrint(
        '[GeocodingIsolateService] Warm-up complete '
        '(OfflineGeocoder ready=${isInitialized.value})',
      );
    } catch (e) {
      debugPrint(
        '[GeocodingIsolateService] Failed to warm geocoding: $e',
      );
      // Recover if OfflineGeocoder finished despite a timeout on this waiter.
      isInitialized.value = OfflineGeocoder.instance.isInitialized;
      // Allow a later retry only when cities geocoder is still not ready.
      if (!isInitialized.value) {
        _warmFuture = null;
      }
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

  /// Ensure OfflineGeocoder is ready (NearestRegion is best-effort).
  /// Hard-capped so Media GPS upload cannot hang forever on CSV load.
  Future<bool> ensureInitialized({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (OfflineGeocoder.instance.isInitialized) {
      isInitialized.value = true;
      return true;
    }

    debugPrint(
      '[GeocodingIsolateService] Service not initialized, attempting to initialize...',
    );

    try {
      await warmUp().timeout(timeout);
    } catch (e) {
      debugPrint('[GeocodingIsolateService] Failed to initialize service: $e');
    }

    // Gate on OfflineGeocoder only — region CSV may still be loading lazily
    // inside OfflineGeocoder.reverseGeocode.
    final ready = OfflineGeocoder.instance.isInitialized;
    isInitialized.value = ready;
    return ready;
  }

  /// Get current service status
  Map<String, dynamic> getStatus() {
    return {
      'isInitialized': isInitialized.value,
      'activeRequests': activeRequests.value,
    };
  }
}
