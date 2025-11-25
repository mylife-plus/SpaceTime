import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

class ConnectivityService extends GetxController {
  static ConnectivityService get instance => Get.find<ConnectivityService>();

  final Connectivity _connectivity = Connectivity();
  final RxBool isConnected = false.obs;
  final RxBool isInitialized = false.obs;
  final RxString connectionType = 'none'.obs;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _internetCheckTimer;

  @override
  void onInit() {
    super.onInit();
    _initializeConnectivity();
  }

  @override
  void onClose() {
    _connectivitySubscription?.cancel();
    _internetCheckTimer?.cancel();
    super.onClose();
  }

  /// Initialize connectivity monitoring
  Future<void> _initializeConnectivity() async {
    try {
      // Check initial connectivity
      await _checkConnectivity();

      // Listen to connectivity changes
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
        List<ConnectivityResult> results,
      ) {
        _handleConnectivityChange(results);
      });

      // Start periodic internet checks
      _startPeriodicInternetCheck();

      isInitialized.value = true;
      debugPrint('🌐 ConnectivityService initialized');
    } catch (e) {
      debugPrint('❌ Error initializing ConnectivityService: $e');
      isInitialized.value =
          true; // Set to true even on error to prevent blocking
    }
  }

  /// Handle connectivity changes
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    // debugPrint('🌐 Connectivity changed: $results');

    // Store previous connectivity state
    final wasConnected = isConnected.value;
    final previousConnectionType = connectionType.value;

    if (results.isEmpty || results.contains(ConnectivityResult.none)) {
      connectionType.value = 'none';
      isConnected.value = false;
    } else {
      // Update connection type
      if (results.contains(ConnectivityResult.wifi)) {
        connectionType.value = 'wifi';
      } else if (results.contains(ConnectivityResult.mobile)) {
        connectionType.value = 'mobile';
      } else if (results.contains(ConnectivityResult.ethernet)) {
        connectionType.value = 'ethernet';
      } else {
        connectionType.value = 'other';
      }

      // Verify actual internet connectivity
      _verifyInternetConnectivity();
    }

    // Check if connectivity was restored (after a brief delay to ensure _verifyInternetConnectivity completes)
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!wasConnected &&
          isConnected.value &&
          connectionType.value != 'none') {
       
        _notifyConnectivityRestored();
      } else if (wasConnected && !isConnected.value) {
        
      }
    });
  }

  /// Notify that connectivity has been restored
  void _notifyConnectivityRestored() {
    debugPrint('🌐 Notifying connectivity restoration...');

    // Force update the reactive values to trigger UI updates
    final currentConnected = isConnected.value;
    final currentType = connectionType.value;

    // Trigger reactive updates by setting values again
    isConnected.value = currentConnected;
    connectionType.value = currentType;

    // Add a small delay to ensure the connectivity is stable
    Future.delayed(const Duration(milliseconds: 300), () {
      debugPrint(
        '🌐 Connectivity restoration notification - reactive listeners will handle map reload',
      );
      // Force another update to ensure UI refreshes
      isConnected.refresh();
      connectionType.refresh();
    });
  }

  /// Check current connectivity status
  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _handleConnectivityChange(results);
    } catch (e) {
      debugPrint('❌ Error checking connectivity: $e');
      isConnected.value = false;
      connectionType.value = 'none';
    }
  }

  Future<void> _verifyInternetConnectivity() async {
    try {
      // debugPrint('🌐 Verifying internet connectivity...');

      // Must be a hostname, not URL
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 5));

      final hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      // debugPrint(
      //   '🌐 Internet lookup result: hasInternet=$hasInternet, resultCount=${result.length}',
      // );

      if (hasInternet) {
        // If internet is available but connectionType is 'none', refresh from system
        if (connectionType.value == 'none') {
          // debugPrint(
          //   '🌐 Internet restored but connectionType is none - refreshing from system',
          // );
          await _updateConnectionTypeFromSystem();
        }

        // Ensure we have a valid connection type
        if (connectionType.value == 'none' || connectionType.value.isEmpty) {
        
          connectionType.value = 'other';
        }

        isConnected.value = true;
        
      } else {
        isConnected.value = false;
        connectionType.value = 'none';
       
      }
    } catch (e) {
      isConnected.value = false;
      connectionType.value = 'none';
    }
  }

  /// Verify actual internet connectivity by attempting to reach a server
  // te connection type from system connectivity state
  Future<void> _updateConnectionTypeFromSystem() async {
    try {
      final results = await _connectivity.checkConnectivity();

      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        connectionType.value = 'none';
      } else {
        // Update connection type based on current system state
        if (results.contains(ConnectivityResult.wifi)) {
          connectionType.value = 'wifi';
        } else if (results.contains(ConnectivityResult.mobile)) {
          connectionType.value = 'mobile';
        } else if (results.contains(ConnectivityResult.ethernet)) {
          connectionType.value = 'ethernet';
        } else {
          connectionType.value = 'other';
        }
      }

      debugPrint(
        '🌐 Updated connectionType from system: ${connectionType.value}',
      );
    } catch (e) {
      debugPrint('❌ Error updating connectionType from system: $e');
      connectionType.value = 'none';
    }
  }

  /// Start periodic internet connectivity checks
  void _startPeriodicInternetCheck() {
    _internetCheckTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      // First check the actual connectivity state to update connectionType
      await _checkConnectivity();
      // Then verify internet connectivity
      await _verifyInternetConnectivity();
    });
  }

  /// Force refresh connectivity status
  Future<void> refreshConnectivity() async {
    debugPrint('🌐 Force refreshing connectivity status');

    try {
      // Store previous values for comparison
      final previousConnected = isConnected.value;
      final previousConnectionType = connectionType.value;

      // First update connection type from system
      await _updateConnectionTypeFromSystem();

      // Then verify actual internet connectivity
      await _verifyInternetConnectivity();

      // Log the changes
      debugPrint('🌐 Connectivity refresh complete:');
      debugPrint(
        '🌐 - Previous: isConnected=$previousConnected, type=$previousConnectionType',
      );
      debugPrint(
        '🌐 - Current: isConnected=${isConnected.value}, type=${connectionType.value}',
      );

      // If connectivity status changed, trigger additional verification
      if (previousConnected != isConnected.value) {
        debugPrint(
          '🌐 Connectivity status changed - triggering additional verification',
        );

        // Wait a moment and verify again to ensure stability
        await Future.delayed(const Duration(milliseconds: 200));
        await _verifyInternetConnectivity();

        debugPrint(
          '🌐 Final verification: isConnected=${isConnected.value}, type=${connectionType.value}',
        );
      }
    } catch (e) {
      debugPrint('❌ Error during connectivity refresh: $e');
      // On error, assume no connectivity to be safe
      isConnected.value = false;
      connectionType.value = 'none';
    }
  }

  /// Check if internet is available for map tiles
  Future<bool> hasInternetForMaps() async {
    try {
      // Quick connectivity check first
      final results = await _connectivity.checkConnectivity();
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return false;
      }

      // Verify with actual internet check
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(seconds: 3));

      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      debugPrint('🌐 Internet check for maps failed: $e');
      return false;
    }
  }

  /// Quick single ping internet check for fast state transitions
  Future<bool> hasInternetQuickCheck() async {
    try {
      // Quick connectivity check first
      final results = await _connectivity.checkConnectivity();
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        debugPrint('🌐 Quick check: No connectivity detected');
        return false;
      }

      // Single quick ping with short timeout
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(const Duration(milliseconds: 800));

      final hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      debugPrint('🌐 Quick internet check result: $hasInternet');
      return hasInternet;
    } catch (e) {
      debugPrint('🌐 Quick internet check failed: $e');
      return false;
    }
  }

  /// Enhanced internet check specifically for Mapbox services

  Future<bool> hasInternetForMapbox() async {
    try {
      final connectivityResult = await _connectivity.checkConnectivity();
      if (connectivityResult.isEmpty || connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint('🗺 No connectivity detected');
        return false;
      }

      final response = await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        debugPrint('🗺 Internet access confirmed via HTTP ping');
        return true;
      } else {
        debugPrint('🗺 Unexpected status code: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('🗺 Internet check failed: $e');
      return false;
    }
  }

  /// Handle Mapbox-specific connectivity errors reported in logs
  void handleMapboxConnectivityError(String errorMessage) {
    debugPrint('🗺 Mapbox connectivity error detected: $errorMessage');

    // Force update connectivity status
    isConnected.value = false;
    connectionType.value = 'none';

    // Trigger immediate connectivity recheck
    refreshConnectivity();

    // Notify listeners about the connectivity issue
    debugPrint('🗺 Forcing connectivity recheck due to Mapbox error');
  }

  /// Check if an error message indicates a Mapbox connectivity issue
  bool isMapboxConnectivityError(String errorMessage) {
    final lowerError = errorMessage.toLowerCase();
    final mapboxConnectivityKeywords = [
      'failed to load style',
      'failed to load tile',
      'internet connection appears to be offline',
      'network connection was lost',
      'unable to fetch configuration',
      'connectionerror',
      'mapbox',
      'timeout',
      'network error',
      'couldn\'t connect to server',
      'net::err_internet_disconnected',
      'online connectivity disabled',
      'connection failed',
      'no internet',
      'offline',
    ];

    return mapboxConnectivityKeywords.any(
      (keyword) => lowerError.contains(keyword),
    );
  }

  /// Get connectivity status as a readable string
  String get connectivityStatus {
    if (!isConnected.value) return 'No Internet';

    switch (connectionType.value) {
      case 'wifi':
        return 'WiFi Connected';
      case 'mobile':
        return 'Mobile Data';
      case 'ethernet':
        return 'Ethernet';
      case 'other':
        return 'Connected';
      default:
        return 'No Internet';
    }
  }

  /// Show connectivity status snackbar
  void showConnectivityStatus() {
    final status = connectivityStatus;
    final color = isConnected.value ? Colors.green : Colors.red;

    if (isConnected.value) return;
    Get.snackbar(
      'Connection Status',
      status,
      backgroundColor: color.withValues(alpha: 0.8),
      colorText: Colors.white,
        duration: const Duration(seconds: 2),
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
    );
  }
}
