import 'dart:async';
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
import '../../../../services/mbtiles_download_service.dart';
import '../../../../services/mbtiles_server_service.dart';
import '../../../../services/style_json_download_service.dart';

class GetStartedController extends GetxController {
  // Dependencies
  OfflineMapCoordinatorService? _offlineCoordinator;
  OfflineMapService? _offlineMapService;
  MbtilesDownloadService? _mbtilesDownloadService;
  StyleJsonDownloadService? _styleJsonDownloadService;

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

  // State for zoom level 14 download
  final RxBool isDownloadingZoom10 = false.obs;
  final RxBool hasReached150Tiles = false.obs;

  // State for zoom level selection (11 or 12)
  final RxInt selectedZoomLevel = 11.obs; // Default to zoom 11

  // State for language selection
  final RxString selectedLanguage = 'English'.obs; // Default to English

  // State for UI visibility
  final RxBool showDownloadUI = false.obs; // Controls visibility of download button and language dropdown
  final RxBool isCheckingTiles = true.obs; // Shows loading state while checking tiles
  final RxBool tilesAlreadyDownloaded = false.obs; // Tracks if tiles were already downloaded when app started

  @override
  void onInit() {
    super.onInit();
    // Initialize services immediately
    _initializeServices();
    _checkIfShouldShowGetStarted();
  }

  /// Check if get started should be shown or navigate directly to main app
  Future<void> _checkIfShouldShowGetStarted() async {
    debugPrint('[GetStartedController] Checking tiles and starting server if needed...');

    // Services are already initialized in onInit()
    // Ensure they are initialized (defensive check)
    if (_mbtilesDownloadService == null) {
      debugPrint('[GetStartedController] ⚠️ Services not initialized, initializing now...');
      _initializeServices();
    }

    // 1. First, always check and request location permissions
    await _checkAndRequestLocationPermissions();

    // 2. Check if mbtiles are already downloaded AND download was completed
    if (_mbtilesDownloadService != null) {
      final isAlreadyDownloaded = await _mbtilesDownloadService!.isMbtilesDownloaded();
      final tilesPath = _mbtilesDownloadService!.getLocalMbtilesPath();

      // Check if download was completed (not just if file exists)
      final prefs = await SharedPreferences.getInstance();
      var downloadCompleted = prefs.getBool('mbtiles_download_completed') ?? false;

      // Migration: If tiles exist and are valid, but flag is not set, set it now
      if (isAlreadyDownloaded && tilesPath != null && !downloadCompleted) {
        debugPrint('[GetStartedController] 🔄 Migration: Tiles exist but completion flag not set. Setting it now...');
        await prefs.setBool('mbtiles_download_completed', true);
        downloadCompleted = true;
        debugPrint('[GetStartedController] ✅ Migration complete: mbtiles_download_completed flag set to true');
      }

      debugPrint('[GetStartedController] 🔍 Tile check results:');
      debugPrint('[GetStartedController]    - isAlreadyDownloaded: $isAlreadyDownloaded');
      debugPrint('[GetStartedController]    - tilesPath: $tilesPath');
      debugPrint('[GetStartedController]    - downloadCompleted: $downloadCompleted');

      if (isAlreadyDownloaded && tilesPath != null && downloadCompleted) {
        debugPrint('[GetStartedController] ✅ MBTiles already downloaded and completed at: $tilesPath');

        // Mark that tiles were already downloaded
        tilesAlreadyDownloaded.value = true;
        debugPrint('[GetStartedController] 📚 Set tilesAlreadyDownloaded = true (book will be 20% smaller)');

        // Start the tile server
        await _startTileServer(tilesPath);

        // Show Get Started screen for at least 3 seconds before navigating
        debugPrint('[GetStartedController] Showing Get Started screen for 3 seconds...');
        isCheckingTiles.value = false;

        // Show the welcome animation/screen
        showWelcomeAnimation.value = true;

        // Wait for 3 seconds
        await Future.delayed(const Duration(seconds: 4 ));

        // Navigate to map after 3 seconds
        debugPrint('[GetStartedController] 3 seconds elapsed, navigating to MapViewWidgetNew...');
        Get.offAllNamed(Routes.MAP_NEW);
        return;
      } else {
        if (isAlreadyDownloaded && !downloadCompleted) {
          debugPrint('[GetStartedController] ⚠️ MBTiles download was incomplete - showing download UI');
        } else {
          debugPrint('[GetStartedController] ⚠️ MBTiles not downloaded yet - showing download UI');
        }

        // Show download UI (buttons and language dropdown)
        debugPrint('[GetStartedController] 🎯 Setting showDownloadUI = true');
        debugPrint('[GetStartedController] 🎯 Setting isCheckingTiles = false');
        isCheckingTiles.value = false;
        showDownloadUI.value = true;

        debugPrint('[GetStartedController] 🎯 Current state: showDownloadUI=${showDownloadUI.value}, isCheckingTiles=${isCheckingTiles.value}');

        // Reset states for fresh download
        isCompleted.value = false;
        hasError.value = false;
        isDownloading.value = false;
        statusText.value = "Download 5GB of map tiles to use offline";

        // Check internet and show appropriate screen
        debugPrint('[GetStartedController] Showing Get Started screen for tile download');
        await _checkInternetAndShowAppropriateScreen();

        debugPrint('[GetStartedController] 🎯 After internet check: showDownloadUI=${showDownloadUI.value}, isCheckingTiles=${isCheckingTiles.value}');
      }
    }
  }

  /// Start the tile server with downloaded tiles
  Future<void> _startTileServer(String tilesPath) async {
    try {
      debugPrint('[GetStartedController] 🗺️ Starting tile server...');

      final serverService = MbtilesServerService.instance;
      final serverUrl = await serverService.startServer(tilesPath);

      if (serverUrl != null) {
        debugPrint('[GetStartedController] ✅ Tile server started successfully at: $serverUrl');
        debugPrint('[GetStartedController] 📡 Tiles will be served from: $serverUrl/{z}/{x}/{y}.pbf');
      } else {
        debugPrint('[GetStartedController] ❌ Failed to start tile server');
      }
    } catch (e) {
      debugPrint('[GetStartedController] ❌ Error starting tile server: $e');
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
    isCheckingTiles.value = false; // Stop checking tiles indicator
    showWelcomeAnimation.value = false;
    isNoInternet.value = true;
    showDownloadUI.value = false; // Hide download UI when no internet
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
      debugPrint('[GetStartedController] 🔧 Initializing services...');

      // Initialize OfflineMapCoordinatorService if not already initialized
      if (!Get.isRegistered<OfflineMapCoordinatorService>()) {
        debugPrint('[GetStartedController] 🔧 Putting OfflineMapCoordinatorService...');
        Get.put(OfflineMapCoordinatorService(), permanent: true);
      }
      _offlineCoordinator = Get.find<OfflineMapCoordinatorService>();

      // Initialize OfflineMapService if not already initialized
      if (!Get.isRegistered<OfflineMapService>()) {
        debugPrint('[GetStartedController] 🔧 Putting OfflineMapService...');
        Get.put(OfflineMapService(), permanent: true);
      }
      _offlineMapService = Get.find<OfflineMapService>();

      // Get MbtilesDownloadService instance (singleton)
      _mbtilesDownloadService = MbtilesDownloadService.instance;

      // Initialize StyleJsonDownloadService if not already initialized
      if (!Get.isRegistered<StyleJsonDownloadService>()) {
        debugPrint('[GetStartedController] 🔧 Putting StyleJsonDownloadService...');
        Get.put(StyleJsonDownloadService(), permanent: true);
      }
      _styleJsonDownloadService = StyleJsonDownloadService.instance;

      debugPrint('[GetStartedController] ✅ Services initialized successfully');
    } catch (e) {
      debugPrint('[GetStartedController] ❌ Error initializing services: $e');
      hasError.value = true;
      errorMessage.value = "Failed to initialize services";
    }
  }

  /// Start the welcome animation sequence
  void _startWelcomeSequence() {
    debugPrint('[GetStartedController] 🎬 Starting welcome sequence');
    debugPrint('[GetStartedController] 🎬 Before: showDownloadUI=${showDownloadUI.value}, isCheckingTiles=${isCheckingTiles.value}');

    // Stop checking tiles indicator since we're showing the welcome sequence
    isCheckingTiles.value = false;

    // Ensure download UI is visible (if it was set to true earlier, keep it true)
    // This is important for cases where tiles are not downloaded or download was incomplete
    if (!showDownloadUI.value) {
      debugPrint('[GetStartedController] 🎬 Setting showDownloadUI to true in welcome sequence');
      showDownloadUI.value = true;
    }

    debugPrint('[GetStartedController] 🎬 After: showDownloadUI=${showDownloadUI.value}, isCheckingTiles=${isCheckingTiles.value}');

    // Show welcome animation for 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      debugPrint('[GetStartedController] 🎬 Welcome animation complete, showing download section');
      showWelcomeAnimation.value = false;
      showDownloadSection.value = true;
      debugPrint('[GetStartedController] 🎬 Final state: showDownloadUI=${showDownloadUI.value}, showDownloadSection=${showDownloadSection.value}');

      // Wait for user to manually tap the button to start download
      // No auto-start - user must explicitly confirm
    });
  }

  /// Select zoom level for download
  void selectZoomLevel(int zoomLevel) {
    if (isDownloading.value) {
      debugPrint('[GetStartedController] Cannot change zoom level during download');
      return;
    }
    selectedZoomLevel.value = zoomLevel;
    debugPrint('[GetStartedController] Selected zoom level: $zoomLevel');
  }

  /// Select language
  void selectLanguage(String language) {
    selectedLanguage.value = language;
    debugPrint('[GetStartedController] Selected language: $language');
    // TODO: Implement language change logic here
  }

  /// Start the mbtiles download process from Cloudflare R2
  /// Downloads mbtiles file based on selected zoom level and saves to app-specific folder
  Future<void> startDownload() async {
    if (isDownloading.value) {
      debugPrint('[GetStartedController] Download already in progress, ignoring tap');
      return;
    }

    try {
      debugPrint('[GetStartedController] 🚀 Starting mbtiles download from Cloudflare R2...');
      debugPrint('[GetStartedController] 🔢 Selected zoom level: ${selectedZoomLevel.value}');

      // Ensure service is initialized
      if (_mbtilesDownloadService == null) {
        debugPrint('[GetStartedController] ⚠️ MbtilesDownloadService not initialized, initializing now...');
        _mbtilesDownloadService = MbtilesDownloadService.instance;

        if (_mbtilesDownloadService == null) {
          debugPrint('[GetStartedController] ❌ Failed to initialize MbtilesDownloadService');
          hasError.value = true;
          errorMessage.value = "Failed to initialize download service";
          statusText.value = "Initialization failed";
          return;
        }
        debugPrint('[GetStartedController] ✅ MbtilesDownloadService initialized successfully');
      }

      // Reset state before starting download
      isDownloading.value = true;
      hasError.value = false;
      isCompleted.value = false;
      errorMessage.value = "";
      statusText.value = "Preparing download for zoom level ${selectedZoomLevel.value}...";
      downloadProgress.value = 0.0;

      // Setup listeners for download progress updates
      _setupMbtilesDownloadListeners();

      // Start the download from Cloudflare R2 with selected zoom level
      // This will download the file to: {appSupportDir}/offline_tiles/tiles.mbtiles
      debugPrint('[GetStartedController] 📥 Calling MbtilesDownloadService.downloadMbtiles(zoomLevel: ${selectedZoomLevel.value})...');
      final downloadedPath = await _mbtilesDownloadService!.downloadMbtiles(
        zoomLevel: selectedZoomLevel.value,
      );

      if (downloadedPath != null && downloadedPath.isNotEmpty) {
        debugPrint('[GetStartedController] ✅ MBTiles download completed successfully');
        debugPrint('[GetStartedController] 📁 File saved at: $downloadedPath');

        // Mark as completed and navigate to main app
        _onMbtilesDownloadCompleted(downloadedPath);
      } else {
        debugPrint('[GetStartedController] ❌ MBTiles download failed - no path returned');
        hasError.value = true;
        errorMessage.value = _mbtilesDownloadService?.errorMessage.value ?? "Download failed - please try again";
        statusText.value = "Download failed";
        isDownloading.value = false;
      }

    } catch (e) {
      debugPrint('[GetStartedController] ❌ Error starting download: $e');
      hasError.value = true;
      errorMessage.value = "Failed to start download: ${e.toString()}";
      statusText.value = "Download error";
      isDownloading.value = false;
    }
  }

  /// Handle mbtiles download completion
  void _onMbtilesDownloadCompleted(String downloadedPath) async {
    debugPrint('[GetStartedController] 🎉 MBTiles download completed!');
    debugPrint('[GetStartedController] 📁 Saved to: $downloadedPath');

    // Download style.json file
    statusText.value = "Downloading map style...";
    debugPrint('[GetStartedController] 📥 Starting style.json download...');

    try {
      final styleJsonPath = await _styleJsonDownloadService?.downloadStyleJson();
      if (styleJsonPath != null) {
        debugPrint('[GetStartedController] ✅ Style.json downloaded successfully to: $styleJsonPath');
      } else {
        debugPrint('[GetStartedController] ⚠️ Style.json download failed, will use fallback');
      }
    } catch (e) {
      debugPrint('[GetStartedController] ❌ Error downloading style.json: $e');
      // Continue anyway - the app can use a fallback style
    }

    isCompleted.value = true;
    isDownloading.value = false;
    tilesDownloadCompleted.value = true;
    statusText.value = "Map tiles ready!";
    downloadProgress.value = 1.0;

    // Save download completed flag to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('mbtiles_download_completed', true);
      debugPrint('[GetStartedController] ✅ Saved mbtiles_download_completed flag to SharedPreferences');
    } catch (e) {
      debugPrint('[GetStartedController] ❌ Error saving download completed flag: $e');
    }

    // Auto-navigate to main app after brief delay
    debugPrint('[GetStartedController] ⏱️ Auto-navigating to main app in 2 seconds...');
    await Future.delayed(const Duration(seconds: 2));

    navigateToMainApp();
  }

  /// Setup listeners for mbtiles download progress updates
  void _setupMbtilesDownloadListeners() {
    if (_mbtilesDownloadService == null) {
      debugPrint('[GetStartedController] ⚠️ Cannot setup listeners - service is null');
      return;
    }

    debugPrint('[GetStartedController] 📡 Setting up download progress listeners...');

    // Use interval to poll progress instead of ever() to avoid listener issues
    // This ensures we always get the latest values
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_mbtilesDownloadService == null) {
        timer.cancel();
        return;
      }

      // Update progress
      final progress = _mbtilesDownloadService!.downloadProgress.value;
      if (downloadProgress.value != progress) {
        downloadProgress.value = progress;
        debugPrint('[GetStartedController] 📊 Download progress: ${(progress * 100).toStringAsFixed(1)}%');
      }

      // Update status text
      final status = _mbtilesDownloadService!.statusText.value;
      if (status.isNotEmpty && statusText.value != status) {
        statusText.value = status;
        debugPrint('[GetStartedController] 📝 Status: $status');
      }

      // Update downloading state
      final downloading = _mbtilesDownloadService!.isDownloading.value;
      if (isDownloading.value != downloading) {
        isDownloading.value = downloading;
        debugPrint('[GetStartedController] 🔄 Downloading: $downloading');
      }

      // Check for errors
      final hasErr = _mbtilesDownloadService!.hasError.value;
      if (hasErr && !hasError.value) {
        hasError.value = true;
        errorMessage.value = _mbtilesDownloadService!.errorMessage.value;
        debugPrint('[GetStartedController] ❌ Error detected: ${errorMessage.value}');
        timer.cancel();
      }

      // Check for completion
      final completed = _mbtilesDownloadService!.isCompleted.value;
      if (completed && !isCompleted.value) {
        isCompleted.value = true;
        debugPrint('[GetStartedController] ✅ Download completed!');
        timer.cancel();
      }

      // Cancel timer if download is no longer in progress and not completed
      if (!downloading && !completed && !hasErr) {
        debugPrint('[GetStartedController] ⏹️ Download stopped, canceling listener timer');
        timer.cancel();
      }
    });

    debugPrint('[GetStartedController] ✅ Download listeners setup complete');
  }

  /// Setup listeners for download progress updates (old method - kept for compatibility)
  void _setupDownloadListeners() {
    if (_offlineMapService == null) return;

    // Listen to download progress
    ever(_offlineMapService!.tileRegionProgress, (double progress) {
      downloadProgress.value = progress;
      if (progress > 0 && !isDownloadingZoom10.value) {
        statusText.value = "Downloading maps... ${(progress * 100).toStringAsFixed(1)}%";
      }
    });

    // Listen to tile count updates
    ever(_offlineMapService!.downloadedTileCount, (int tileCount) {
      downloadedTileCount.value = tileCount;

      // Check if we've reached 150 tiles and haven't started zoom 14 download yet
      if (tileCount >= 150 && !hasReached150Tiles.value && !isDownloadingZoom10.value) {
        hasReached150Tiles.value = true;
        debugPrint('[GetStartedController] Reached 150 tiles, starting zoom level 14 download...');
        _startZoom10Download();
      }

      if (tileCount > 0 && !isDownloadingZoom10.value) {
        statusText.value = "Downloaded $tileCount tiles";
      }
    });

    // Listen to status text updates
    ever(_offlineMapService!.downloadStatusText, (String status) {
      if (status.isNotEmpty && status != "Ready to download" && !isDownloadingZoom10.value) {
        statusText.value = status;
      }
    });

    // Listen to download completion
    ever(_offlineMapService!.isOfflineReady, (bool isReady) {
      if (isReady && !isDownloadingZoom10.value) {
        // Initial download completed, but we'll wait for zoom 12 download
        debugPrint('[GetStartedController] Initial download completed, waiting for zoom 12...');
      }
    });

    // Listen to download state changes
    ever(_offlineMapService!.isDownloading, (bool downloading) {
      if (!isDownloadingZoom10.value) {
        isDownloading.value = downloading;
      }
    });
  }

  /// Start downloading zoom level 14 tiles
  Future<void> _startZoom10Download() async {
    try {
      isDownloadingZoom10.value = true;
      statusText.value = "Downloading zoom level 14 tiles...";

      debugPrint('[GetStartedController] Starting zoom level 14 download...');

      // Get the region geometry from the coordinator service
      final regionGeometry = await _offlineCoordinator?.getRegionGeometry();

      if (regionGeometry == null) {
        debugPrint('[GetStartedController] Failed to get region geometry for zoom 14');
        _onZoom10DownloadCompleted(false);
        return;
      }

      // Download zoom level 14 tiles specifically
      await _downloadZoom10Tiles(regionGeometry);

    } catch (e) {
      debugPrint('[GetStartedController] Zoom 14 download failed: $e');
      // Even if it fails, we save what we have and move on
      _onZoom10DownloadCompleted(false);
    }
  }

  /// Download zoom level 14 tiles with error handling
  Future<void> _downloadZoom10Tiles(Map<String, dynamic> regionGeometry) async {
    try {
      // This will attempt to download zoom 14 tiles until it fails
      // The Mapbox SDK will handle the download and save whatever it can
      await _offlineMapService?.downloadZoom10Tiles(
        regionGeometry: regionGeometry,
        onProgress: (int downloaded, int total) {
          statusText.value = "Downloading zoom 14: $downloaded tiles";
          debugPrint('[GetStartedController] Zoom 14 progress: $downloaded tiles');
        },
        onComplete: () {
          debugPrint('[GetStartedController] Zoom 14 download completed successfully');
          _onZoom10DownloadCompleted(true);
        },
        onError: (error) {
          debugPrint('[GetStartedController] Zoom 14 download error: $error');
          // Save whatever was downloaded and move on
          _onZoom10DownloadCompleted(false);
        },
      );

    } catch (e) {
      debugPrint('[GetStartedController] Error in zoom 14 download: $e');
      _onZoom10DownloadCompleted(false);
    }
  }

  /// Handle zoom 14 download completion (success or failure)
  void _onZoom10DownloadCompleted(bool success) async {
    debugPrint('[GetStartedController] Zoom 14 download completed. Success: $success');

    isDownloadingZoom10.value = false;

    // Save the current tile count (includes whatever zoom 14 tiles were downloaded)
    await _offlineMapService?.saveTileCount();

    // Mark overall download as completed
    _onDownloadCompleted();
  }

  /// Handle download completion
  void _onDownloadCompleted() async {
    debugPrint('[GetStartedController] Download completed!');

    isCompleted.value = true;
    isDownloading.value = false;
    tilesDownloadCompleted.value = true;
    statusText.value = "Download completed! ${downloadedTileCount.value} tiles ready";

    // Don't save persistent download completion status - always download on app start
    // await _saveTileDownloadCompletionStatus(true);

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
  Future<void> navigateToMainApp() async {
    debugPrint('[GetStartedController] Navigating to MapViewWidgetNew...');

    // Start tile server if tiles are downloaded
    if (_mbtilesDownloadService != null) {
      final isDownloaded = await _mbtilesDownloadService!.isMbtilesDownloaded();
      final tilesPath = _mbtilesDownloadService!.getLocalMbtilesPath();

      if (isDownloaded && tilesPath != null) {
        await _startTileServer(tilesPath);
      }
    }

    // Navigate to MapViewWidgetNew (main map screen)
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
      // Check if mbtiles are downloaded
      final mbtilesService = MbtilesDownloadService.instance;
      final isDownloaded = await mbtilesService.isMbtilesDownloaded();

      if (isDownloaded) {
        debugPrint('[GetStartedController] ✅ Tiles already downloaded - skipping Get Started');
        return false; // Don't show Get Started, go directly to map
      } else {
        debugPrint('[GetStartedController] ⚠️ Tiles not downloaded - showing Get Started');
        return true; // Show Get Started to download tiles
      }
    } catch (e) {
      debugPrint('[GetStartedController] Error checking get started status: $e');
      // On error, show Get Started screen to be safe
      return true;
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

      // Add timeout to prevent hanging on Android
      await Future.any([
        _performLocationPermissionCheck(),
        Future.delayed(const Duration(seconds: 10), () {
          debugPrint('[GetStartedController] ⚠️ Location permission check timed out after 10 seconds');
          throw TimeoutException('Location permission check timed out');
        }),
      ]);

      isCheckingPermissions.value = false;
    } catch (e) {
      debugPrint('[GetStartedController] Error checking location permissions: $e');
      hasLocationPermission.value = false;
      isCheckingPermissions.value = false;
    }
  }

  /// Perform the actual location permission check
  Future<void> _performLocationPermissionCheck() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('[GetStartedController] Location services are disabled');
        hasLocationPermission.value = false;
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
    } catch (e) {
      debugPrint('[GetStartedController] Error in permission check: $e');
      hasLocationPermission.value = false;
      rethrow;
    }
  }
}
