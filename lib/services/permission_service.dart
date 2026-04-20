import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

class PermissionService extends GetxController {
  static PermissionService get instance => Get.find<PermissionService>();

  final RxBool hasLocationPermission = false.obs;
  final RxBool isLocationServiceEnabled = false.obs;
  final RxBool isCheckingPermissions = false.obs;
  final RxBool permissionJustGranted = false.obs;

  // Stream controller for permission changes
  final StreamController<bool> _permissionChangeController =
      StreamController<bool>.broadcast();
  Stream<bool> get permissionChanges => _permissionChangeController.stream;

  @override
  void onInit() {
    super.onInit();
    _initializePermissionMonitoring();
  }

  @override
  void onClose() {
    _permissionChangeController.close();
    super.onClose();
  }

  /// Initialize permission monitoring
  Future<void> _initializePermissionMonitoring() async {
    await checkLocationPermission();
    _startPermissionMonitoring();
  }

  /// Start monitoring permission changes
  void _startPermissionMonitoring() {
    // Check permissions more frequently to catch settings changes quickly
    Timer.periodic(const Duration(seconds: 1), (timer) {
      _checkPermissionStatus();
    });
  }

  /// Check permission status without requesting
  Future<void> _checkPermissionStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();

      final wasEnabled = hasLocationPermission.value;
      final hasPermission = _isPermissionGranted(permission) && serviceEnabled;

      isLocationServiceEnabled.value = serviceEnabled;
      hasLocationPermission.value = hasPermission;

      // Notify if permission status changed
      if (wasEnabled != hasPermission) {
        debugPrint(
          '🔐 Permission status changed: $wasEnabled -> $hasPermission',
        );
        _permissionChangeController.add(hasPermission);

        if (hasPermission && !wasEnabled) {
          permissionJustGranted.value = true;
          // Reset the flag after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            permissionJustGranted.value = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking permission status: $e');
    }
  }

  /// Check and request location permission if needed
  Future<bool> checkLocationPermission({bool requestIfDenied = false}) async {
    if (isCheckingPermissions.value) return hasLocationPermission.value;

    isCheckingPermissions.value = true;

    try {
      debugPrint('🔐 Checking location service enabled');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      isLocationServiceEnabled.value = serviceEnabled;

      if (!serviceEnabled) {
        debugPrint('🔐 Location service disabled');
        if (requestIfDenied) {
          await _showLocationServiceDialog();
        }
        hasLocationPermission.value = false;
        return false;
      }

      debugPrint('🔐 Checking location permission');
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('🔐 Current permission: $permission');

      if (permission == LocationPermission.denied && requestIfDenied) {
        debugPrint('🔐 Requesting location permission');
        permission = await Geolocator.requestPermission();
        debugPrint('🔐 Permission after request: $permission');

        if (_isPermissionGranted(permission)) {
          permissionJustGranted.value = true;
          Future.delayed(const Duration(seconds: 2), () {
            permissionJustGranted.value = false;
          });
        }
      }

      if (permission == LocationPermission.deniedForever && requestIfDenied) {
        debugPrint('🔐 Permission denied forever');
        await _showPermissionDeniedDialog();
        hasLocationPermission.value = false;
        return false;
      }

      final granted = _isPermissionGranted(permission);
      hasLocationPermission.value = granted;
      debugPrint('🔐 Location permission granted: $granted');

      return granted;
    } catch (e) {
      debugPrint('❌ Error checking location permission: $e');
      hasLocationPermission.value = false;
      return false;
    } finally {
      isCheckingPermissions.value = false;
    }
  }

  /// Check if permission is granted
  bool _isPermissionGranted(LocationPermission permission) {
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Show location service disabled dialog
  Future<void> _showLocationServiceDialog() async {
    final uiController = Get.find<UiController>();

    return Get.dialog(
      AlertDialog(
        backgroundColor:
            uiController.darkMode.value ? Colors.grey[900] : Colors.white,
        title: Text(
          'title_text_location_service_disabled'.tr,
          style: TextStyle(
            color: uiController.darkMode.value ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'dialog_content_location_services_are_disabled_please_ena'.tr,
          style: TextStyle(
            color:
                uiController.darkMode.value
                    ? Colors.grey[300]
                    : Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              'text_cancel_11'.tr,
              style: TextStyle(
                color:
                    uiController.darkMode.value
                        ? Colors.grey[400]
                        : Colors.grey[600],
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Geolocator.openLocationSettings();
              Get.back();
            },
            child: Text(
              'text_open_settings_7'.tr,
              style: TextStyle(
                color: uiController.currentMainColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  /// Show permission denied forever dialog
  Future<void> _showPermissionDeniedDialog() async {
    final uiController = Get.find<UiController>();

    return Get.dialog(
      AlertDialog(
        backgroundColor:
            uiController.darkMode.value ? Colors.grey[900] : Colors.white,
        title: Text(
          'title_text_location_permission_required'.tr,
          style: TextStyle(
            color: uiController.darkMode.value ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'dialog_content_location_permission_is_permanently_denied_2'.tr,
          style: TextStyle(
            color:
                uiController.darkMode.value
                    ? Colors.grey[300]
                    : Colors.grey[700],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              'text_cancel_12'.tr,
              style: TextStyle(
                color:
                    uiController.darkMode.value
                        ? Colors.grey[400]
                        : Colors.grey[600],
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Geolocator.openAppSettings();
              Get.back();
            },
            child: Text(
              'text_open_settings_8'.tr,
              style: TextStyle(
                color: uiController.currentMainColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  /// Request location permission with user-friendly flow
  Future<bool> requestLocationPermission() async {
    return await checkLocationPermission(requestIfDenied: true);
  }

  /// Get current location if permission is granted
  Future<Position?> getCurrentLocation() async {
    try {
      // 1) Ensure location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("❌ Location services are disabled.");
        return null;
      }

      // 2) Check permissions (use your existing observable too)
      if (!hasLocationPermission.value) {
        final granted = await requestLocationPermission();
        if (!granted) {
          debugPrint("❌ Location permission not granted.");
          return null;
        }
      }

      // 3) Try to get current position
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, // more reliable than medium
            timeLimit: Duration(seconds: 10),
          ),
        );
        debugPrint(
          '🌍 Current location: ${position.latitude}, ${position.longitude}',
        );
        return position;
      } catch (e) {
        debugPrint("⚠️ Error getting current position: $e");
      }

      // 4) Fallback: last known position
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        debugPrint(
          '📍 Using last known location: ${lastKnown.latitude}, ${lastKnown.longitude}',
        );
        return lastKnown;
      }

      // 5) If still null
      debugPrint("❌ No location available.");
      return null;
    } catch (e) {
      debugPrint("❌ Unexpected error in getCurrentLocation: $e");
      return null;
    }
  }

  /// Show permission status
  void showPermissionStatus() {
    String message;
    Color color;

    if (hasLocationPermission.value) {
      message = 'Location permission granted';
      color = Colors.green;
    } else if (!isLocationServiceEnabled.value) {
      message = 'Location service disabled';
      color = Colors.orange;
    } else {
      message = 'Location permission denied';
      color = Colors.red;
    }

    Get.snackbar(
      'snackbar_location_permission'.tr,
      message,
      backgroundColor: color.withValues(alpha: 0.8),
      colorText: Colors.white,
        duration: const Duration(seconds: 2),
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
    );
  }
}
