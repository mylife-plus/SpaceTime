import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/utils/offline_geocoder.dart';

/// Service that handles reverse geocoding operations using non-blocking approach
class GeocodingIsolateService extends GetxService {
  static GeocodingIsolateService get instance => Get.find();

  // State management
  final RxBool isInitialized = false.obs;
  final RxInt activeRequests = 0.obs;

  @override
  Future<void> onInit() async {
    super.onInit();
    // Initialize OfflineGeocoder on main thread
    try {
      final geocoder = OfflineGeocoder.instance;
      await geocoder.init();

      isInitialized.value = true;
      debugPrint(
        '[GeocodingIsolateService] Service initialized with OfflineGeocoder',
      );
    } catch (e) {
      debugPrint(
        '[GeocodingIsolateService] Failed to initialize OfflineGeocoder: $e',
      );
      isInitialized.value = false;
    }
  }

  /// Reverse geocode coordinates using non-blocking approach
  Future<Map<String, dynamic>?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    try {
      debugPrint(
        '[GeocodingIsolateService] Non-blocking geocoding: $latitude, $longitude',
      );

      activeRequests.value++;

      // Use a simple async approach to avoid blocking the UI
      final result = await _performGeocodingAsync(latitude, longitude);

      activeRequests.value--;

      debugPrint('[GeocodingIsolateService] Geocoding completed: $result');
      return result;
    } catch (e) {
      activeRequests.value--;
      debugPrint('[GeocodingIsolateService] Geocoding error: $e');
      return null;
    }
  }

  /// Perform geocoding asynchronously without blocking UI
  Future<Map<String, dynamic>?> _performGeocodingAsync(
    double latitude,
    double longitude,
  ) async {
    try {
      // Add a small delay to yield control back to the UI thread
      await Future.delayed(const Duration(milliseconds: 1));

      final geocoder = OfflineGeocoder.instance;
      final result = await geocoder.reverseGeocode(latitude, longitude);

      return result;
    } catch (e) {
      debugPrint('[GeocodingIsolateService] Async geocoding error: $e');
      return null;
    }
  }

  /// Ensure service is initialized and ready
  Future<bool> ensureInitialized() async {
    if (isInitialized.value) {
      return true;
    }

    debugPrint(
      '[GeocodingIsolateService] Service not initialized, attempting to initialize...',
    );

    try {
      final geocoder = OfflineGeocoder.instance;
      await geocoder.init();
      isInitialized.value = true;
      return true;
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
