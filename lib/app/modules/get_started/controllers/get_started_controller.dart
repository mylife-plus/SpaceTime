import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../services/connectivity_service.dart';
import '../../../services/offline_map_coordinator_service.dart';
import '../../../services/offline_map_service.dart';
import '../../../routes/app_pages.dart';

class GetStartedController extends GetxController {
  // Dependencies
  OfflineMapCoordinatorService? _offlineCoordinator;
  OfflineMapService? _offlineMapService;

  // UI State
  final RxBool isDownloading = false.obs;
  final RxBool isCompleted = false.obs;
  final RxBool hasError = false.obs;
  final RxBool isNoInternet = false.obs;
  final RxString statusText = "Preparing to download...".obs;
  final RxDouble downloadProgress = 0.0.obs;
  final RxInt downloadedTileCount = 0.obs;
  final RxString errorMessage = "".obs;

  // Animation controllers
  final RxBool showWelcomeAnimation = true.obs;
  final RxBool showDownloadSection = false.obs;

  // New state variables for persistent download status and location permissions
  final RxBool tilesDownloadCompleted = false.obs;
  final RxBool hasLocationPermission = false.obs;
  final RxBool isCheckingPermissions = true.obs;

  @override
  void onInit() {
    super.onInit();
    _checkIfShouldShowGetStarted();
  }

  /// Check if get started should be shown or navigate directly to main app
  Future<void> _checkIfShouldShowGetStarted() async {
    debugPrint('[GetStartedController] Checking get started conditions...');

    // Initialize services first
    _initializeServices();

    // 1. First, always check and request location permissions
    await _checkAndRequestLocationPermissions();

    // 2. Check persistent tile download status
    final isPersistentlyDownloaded = await _getTileDownloadCompletionStatus();
    debugPrint('[GetStartedController] Persistent download status: $isPersistentlyDownloaded');

    if (isPersistentlyDownloaded) {
      // Tiles are already downloaded according to persistent storage - navigate directly
      debugPrint('[GetStartedController] Tiles already downloaded (persistent), navigating to main app');
      tilesDownloadCompleted.value = true;

      // Navigate directly to main app without showing Get Started screen
      navigateToMainApp();
      return;
    }

    // 3. If not persistently downloaded, check actual tile count as fallback
    final tileCount = await _getTileCount();
    debugPrint('[GetStartedController] Current tile count: $tileCount');

    if (tileCount >= 500) {
      // Tiles are downloaded but not marked as complete - mark as complete and navigate
      debugPrint('[GetStartedController] Tiles downloaded but not marked complete, updating status');
      await _saveTileDownloadCompletionStatus(true);
      tilesDownloadCompleted.value = true;

      // Navigate directly to main app without showing Get Started screen
      navigateToMainApp();
    } else {
      // Tiles not downloaded - show Get Started screen with appropriate content
      debugPrint('[GetStartedController] Tiles not downloaded, showing Get Started screen');
      await _checkInternetAndShowAppropriateScreen();
    }
  }

  /// Check internet connectivity and show appropriate screen
  Future<void> _checkInternetAndShowAppropriateScreen() async {
    try {
      // Check internet connectivity
      final connectivityService = Get.find<ConnectivityService>();
      final hasInternet = await connectivityService.hasInternetQuickCheck();

      debugPrint('[GetStartedController] Internet connectivity: $hasInternet');

      if (hasInternet) {
        // Has internet - show normal get started flow
        debugPrint('[GetStartedController] Internet available, showing get started flow');
        _startWelcomeSequence();
      } else {
        // No internet - show no internet message
        debugPrint('[GetStartedController] No internet, showing no internet message');
        _showNoInternetScreen();
      }
    } catch (e) {
      debugPrint('[GetStartedController] Error checking internet: $e');
      // On error, assume no internet and show no internet screen
      _showNoInternetScreen();
    }
  }

  /// Show no internet screen
  void _showNoInternetScreen() {
    showWelcomeAnimation.value = false;
    isNoInternet.value = true;
    statusText.value = "Internet is required to download the tiles. Please connect to the internet and then try again.";
  }

  /// Get current tile count from SharedPreferences
  Future<int> _getTileCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('offline_downloaded_tile_count') ?? 0;
    } catch (e) {
      debugPrint('[GetStartedController] Error getting tile count: $e');
      return 0;
    }
  }



  /// Initialize required services
  void _initializeServices() {
    try {
      _offlineCoordinator = Get.find<OfflineMapCoordinatorService>();
      _offlineMapService = Get.find<OfflineMapService>();
      debugPrint('[GetStartedController] Services initialized successfully');
    } catch (e) {
      debugPrint('[GetStartedController] Error initializing services: $e');
      hasError.value = true;
      errorMessage.value = "Failed to initialize services";
    }
  }

  /// Start the welcome animation sequence
  void _startWelcomeSequence() {
    // Show welcome animation for 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      showWelcomeAnimation.value = false;
      showDownloadSection.value = true;

      // Wait for user to manually tap the button to start download
      // No auto-start - user must explicitly confirm
    });
  }

  /// Start the tile download process
  Future<void> startDownload() async {
    if (isDownloading.value) return;

    try {
      debugPrint('[GetStartedController] Starting tile download...');
      
      isDownloading.value = true;
      hasError.value = false;
      statusText.value = "Starting download...";
      downloadProgress.value = 0.0;

      // Setup listeners for download progress
      _setupDownloadListeners();

      // Start the download using the coordinator service
      await _offlineCoordinator?.startOfflineDownload();

      debugPrint('[GetStartedController] Download initiated successfully');
      
    } catch (e) {
      debugPrint('[GetStartedController] Error starting download: $e');
      hasError.value = true;
      errorMessage.value = "Failed to start download: ${e.toString()}";
      isDownloading.value = false;
    }
  }

  /// Setup listeners for download progress updates
  void _setupDownloadListeners() {
    if (_offlineMapService == null) return;

    // Listen to download progress
    ever(_offlineMapService!.tileRegionProgress, (double progress) {
      downloadProgress.value = progress;
      if (progress > 0) {
        statusText.value = "Downloading maps... ${(progress * 100).toStringAsFixed(1)}%";
      }
    });

    // Listen to tile count updates
    ever(_offlineMapService!.downloadedTileCount, (int tileCount) {
      downloadedTileCount.value = tileCount;
      if (tileCount > 0) {
        statusText.value = "Downloaded $tileCount tiles";
      }
    });

    // Listen to status text updates
    ever(_offlineMapService!.downloadStatusText, (String status) {
      if (status.isNotEmpty && status != "Ready to download") {
        statusText.value = status;
      }
    });

    // Listen to download completion
    ever(_offlineMapService!.isOfflineReady, (bool isReady) {
      if (isReady) {
        _onDownloadCompleted();
      }
    });

    // Listen to download state changes
    ever(_offlineMapService!.isDownloading, (bool downloading) {
      isDownloading.value = downloading;
      if (!downloading && downloadedTileCount.value >= 500) {
        _onDownloadCompleted();
      }
    });
  }

  /// Handle download completion
  void _onDownloadCompleted() async {
    debugPrint('[GetStartedController] Download completed!');

    isCompleted.value = true;
    isDownloading.value = false;
    tilesDownloadCompleted.value = true;
    statusText.value = "Download completed! ${downloadedTileCount.value} tiles ready";

    // Save persistent download completion status
    await _saveTileDownloadCompletionStatus(true);

    // Auto-navigate to main app after download completion
    debugPrint('[GetStartedController] Download completed, auto-navigating to main app');

    // Add a small delay to show completion message briefly
    await Future.delayed(const Duration(seconds: 1));

    navigateToMainApp();
  }

  /// Mark get started as completed in SharedPreferences
  Future<void> _markGetStartedCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('get_started_completed', true);
      debugPrint('[GetStartedController] Get started marked as completed');
    } catch (e) {
      debugPrint('[GetStartedController] Error saving get started completion: $e');
    }
  }

  /// Navigate to the main app
  void navigateToMainApp() {
    debugPrint('[GetStartedController] Navigating to main app...');
    // Don't mark as completed - always show get started screen on app start
    Get.offAllNamed(Routes.MAP_NEW);
  }

  /// Close the app
  void closeApp() {
    debugPrint('[GetStartedController] Closing app...');
    // Close the app using SystemNavigator
    SystemNavigator.pop();
  }

  /// Skip download and go to main app
  void skipDownload() {
    debugPrint('[GetStartedController] User chose to skip download');
    _markGetStartedCompleted();
    navigateToMainApp();
  }

  /// Retry download if there was an error
  void retryDownload() {
    debugPrint('[GetStartedController] Retrying download...');
    hasError.value = false;
    errorMessage.value = "";
    startDownload();
  }

  /// Check if get started should be shown based on tile download status
  static Future<bool> shouldShowGetStarted() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if tiles are completely downloaded
      final tilesDownloaded = prefs.getBool('tiles_download_completed') ?? false;

      if (tilesDownloaded) {
        debugPrint('[GetStartedController] Tiles already downloaded, skipping Get Started');
        return false; // Don't show Get Started screen
      }

      // If not marked as downloaded, check tile count as fallback
      final tileCount = prefs.getInt('offline_downloaded_tile_count') ?? 0;
      debugPrint('[GetStartedController] Tile count fallback check: $tileCount');

      if (tileCount >= 500) {
        // Mark as downloaded and don't show Get Started
        await prefs.setBool('tiles_download_completed', true);
        debugPrint('[GetStartedController] Marked tiles as downloaded based on count');
        return false;
      }

      // Tiles not downloaded - show Get Started screen
      debugPrint('[GetStartedController] Tiles not downloaded, showing Get Started');
      return true;
    } catch (e) {
      debugPrint('[GetStartedController] Error checking get started status: $e');
      return true; // Show by default if there's an error
    }
  }

  /// Get persistent tile download completion status
  Future<bool> _getTileDownloadCompletionStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('tiles_download_completed') ?? false;
    } catch (e) {
      debugPrint('[GetStartedController] Error getting tile download status: $e');
      return false;
    }
  }

  /// Save persistent tile download completion status
  Future<void> _saveTileDownloadCompletionStatus(bool completed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tiles_download_completed', completed);
      debugPrint('[GetStartedController] Tile download status saved: $completed');
    } catch (e) {
      debugPrint('[GetStartedController] Error saving tile download status: $e');
    }
  }

  /// Check and request location permissions
  Future<void> _checkAndRequestLocationPermissions() async {
    try {
      debugPrint('[GetStartedController] Checking location permissions...');
      isCheckingPermissions.value = true;

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[GetStartedController] Location services are disabled');
        hasLocationPermission.value = false;
        isCheckingPermissions.value = false;
        return;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('[GetStartedController] Current location permission: $permission');

      if (permission == LocationPermission.denied) {
        // Request permission
        debugPrint('[GetStartedController] Requesting location permission...');
        permission = await Geolocator.requestPermission();
        debugPrint('[GetStartedController] Permission after request: $permission');
      }

      // Update permission status
      hasLocationPermission.value = permission == LocationPermission.whileInUse ||
                                   permission == LocationPermission.always;

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[GetStartedController] Location permission denied forever');
        // Could show a dialog to open app settings, but for now just log it
      }

      debugPrint('[GetStartedController] Final location permission status: ${hasLocationPermission.value}');
      isCheckingPermissions.value = false;
    } catch (e) {
      debugPrint('[GetStartedController] Error checking location permissions: $e');
      hasLocationPermission.value = false;
      isCheckingPermissions.value = false;
    }
  }
}
