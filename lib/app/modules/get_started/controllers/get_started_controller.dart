import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../services/permission_service.dart';
import '../../../services/offline_map_coordinator_service.dart';
import '../../../services/offline_map_service.dart';
import '../../../routes/app_pages.dart';
import '../../../../services/mbtiles_download_service.dart';
import '../../../../services/mbtiles_server_service.dart';
import '../../../../services/style_json_download_service.dart';
import '../../../services/memory_db.dart';
import '../../../services/path_migration_helper.dart';
import '../../../helpers/mapbox_zoom_helper.dart';
import '../../../../services/memory_geojson_service.dart';
import '../../ui/controllers/ui_controller.dart';

const String PREFS_KEY_MBTILES_DOWNLOADED = 'mbtiles_downloaded';
const String PREFS_KEY_MBTILES_PATH = 'mbtiles_path';

class GetStartedController extends GetxController with WidgetsBindingObserver {
  // Dependencies
  OfflineMapCoordinatorService? _offlineCoordinator;
  OfflineMapService? _offlineMapService;
  MbtilesDownloadService? _mbtilesDownloadService;
  StyleJsonDownloadService? _styleJsonDownloadService;
  Future<String?>? _styleDownloadFuture;
  bool _isFinalizingDownload = false;

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
  final RxBool hideStartButtonDuringTileCheck = false.obs;

  final RxBool isInitializing = true.obs;

  bool _startupInitializationStarted = false;

  // iOS Background App Refresh gating
  Completer<bool>? _waitingForBackgroundRefreshCompleter;
  bool _backgroundRefreshPopupShowing = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // 1) Resolve any pending "wait for background refresh enabled" request
    final completer = _waitingForBackgroundRefreshCompleter;
    if (completer != null) {
      _waitingForBackgroundRefreshCompleter = null;
      unawaited(() async {
        final status = await _getBackgroundRefreshStatus();
        final enabled = status == 'available';
        if (!completer.isCompleted) completer.complete(enabled);
      }());
      return;
    }

    // 2) If a download is still running and background refresh is off,
    // show the popup again so user can re-enable (prevents silent pauses).
    if (Platform.isIOS && isDownloading.value && !tilesDownloadCompleted.value) {
      unawaited(_maybeShowBackgroundRefreshPopupOnResume());
    }
  }

  /// Called from [main] after core services register (native splash already removed).
  void runStartupInitialization() {
    if (_startupInitializationStarted) return;
    _startupInitializationStarted = true;
    _initializeEverything();
  }

  Future<void> _initializeEverything() async {
    isInitializing.value = true;

    await _initializeBackgroundServices();

    _initializeServices();
    await _checkIfShouldShowGetStarted();

    isInitializing.value = false;
  }

  Future<void> _initializeBackgroundServices() async {
    // All the heavy initialization from main.dart
    try {
      await Future.wait([
        _initDatabase(),
        // _initA/ssets(),
        _initMapboxHelpers(),
      ]);
      // Do not block initial UI on tile-server warmup.
      unawaited(_initTileServer());
    } catch (e) {
      debugPrint('[GetStartedController] Background init error: $e');
    }
  }

  Future<void> _initDatabase() async {
    try {
      await DatabaseHelper.instance.database;
      final isHealthy = await DatabaseHelper.instance.isDatabaseHealthy();
      if (!isHealthy) {
        await DatabaseHelper.instance.resetDatabaseConnection();
      }
      await DatabaseHelper.instance.initializePlaceCategoriesIfNeeded();
      await DatabaseHelper.instance.initializeHashtagGroupsIfNeeded();
      await PathMigrationHelper.instance.migrateAllPathsToRelative();
    } catch (e) {
      debugPrint('[GetStartedController] Database init error: $e');
    }
  }

  Future<void> _initMapboxHelpers() async {
    try {
      await MapboxZoomHelper.initialize();
      MemoryGeoJsonService.initializeYearColorIndexCache();
    } catch (e) {
      debugPrint('[GetStartedController] Mapbox helper error: $e');
    }
  }

  Future<void> _initTileServer() async {
    try {
      final mbtilesService = MbtilesDownloadService.instance;
      final isDownloaded = await mbtilesService.isMbtilesDownloaded();
      final tilesPath = mbtilesService.getLocalMbtilesPath();

      if (isDownloaded && tilesPath != null) {
        final serverService = MbtilesServerService.instance;
        await serverService
            .startServer(tilesPath)
            .timeout(const Duration(seconds: 6));
      }
    } catch (e) {
      debugPrint('[GetStartedController] Tile server error: $e');
    }
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

    await _checkAndRequestLocationPermissions();

    if (_mbtilesDownloadService != null) {
      final prefs = await SharedPreferences.getInstance();

      var downloadCompleted = prefs.getBool('mbtiles_download_completed') ?? false;
      final savedPath = prefs.getString(PREFS_KEY_MBTILES_PATH);

      debugPrint('[GetStartedController] 🔍 Initial preference check:');
      debugPrint('[GetStartedController]    - downloadCompleted: $downloadCompleted');
      debugPrint('[GetStartedController]    - savedPath: $savedPath');

      const minExpectedSize = 4 * 1024 * 1024 * 1024;
      final appSupportDir = await getApplicationSupportDirectory();
      final tileCheckFuture = Isolate.run(() {
        return _checkTilesFileInIsolate(
          savedPath: savedPath,
          downloadCompleted: downloadCompleted,
          fallbackPath: '${appSupportDir.path}/offline_tiles/tiles.mbtiles',
          minExpectedSize: minExpectedSize,
        );
      });
      final styleCheckFuture = _styleJsonDownloadService?.isStyleJsonDownloaded() ?? Future<bool>.value(false);
      final tileCheck = await tileCheckFuture;
      bool fileExistsAndValid = tileCheck['fileExistsAndValid'] as bool;
      String? tilesPath = tileCheck['tilesPath'] as String?;
      bool recoveredFromFallback = tileCheck['recoveredFromFallback'] as bool;
      bool styleJsonExists = await styleCheckFuture;
      debugPrint('[GetStartedController] 🎨 Style.json exists: $styleJsonExists');

      if (recoveredFromFallback && tilesPath != null) {
        await prefs.setString(PREFS_KEY_MBTILES_PATH, tilesPath);
        await prefs.setBool(PREFS_KEY_MBTILES_DOWNLOADED, true);
        debugPrint('[GetStartedController] ✅ Recovered tiles path from fallback location');
      }

      if (fileExistsAndValid && styleJsonExists && !downloadCompleted && tilesPath != null) {
        debugPrint('[GetStartedController] 🔄 Tiles + style exist but not marked complete - updating preferences...');
        await prefs.setBool('mbtiles_download_completed', true);
        await prefs.setBool(PREFS_KEY_MBTILES_DOWNLOADED, true);
        await prefs.setString(PREFS_KEY_MBTILES_PATH, tilesPath);
        downloadCompleted = true;
        debugPrint('[GetStartedController] ✅ Preferences updated');
      }

      debugPrint('[GetStartedController] 🔍 Final check results:');
      debugPrint('[GetStartedController]    - fileExistsAndValid: $fileExistsAndValid');
      debugPrint('[GetStartedController]    - styleJsonExists: $styleJsonExists');
      debugPrint('[GetStartedController]    - downloadCompleted: $downloadCompleted');

      if (fileExistsAndValid && downloadCompleted && tilesPath != null) {
        debugPrint('[GetStartedController] ✅ Tiles verified, proceeding to map');

        tilesAlreadyDownloaded.value = true;
        _prepareLoaderOnlyState();
        // Gate navigation on server startup to ensure map has a live tile endpoint.
        final serverStarted = await _startTileServer(tilesPath);
        if (!serverStarted) {
          debugPrint('[GetStartedController] ❌ Tile server not ready, staying on Get Started');
          hideStartButtonDuringTileCheck.value = false;
          isCheckingTiles.value = false;
          showDownloadUI.value = true;
          hasError.value = true;
          errorMessage.value = 'Tile server failed to start. Please retry.';
          statusText.value = 'Unable to start tile server.';
          return;
        }
        // Keep style recovery in background.
        unawaited(_recoverStyleJsonInBackground(tilesPath, styleJsonExists, prefs));
        await _navigateToMainFromStartup();
        return;
      } else if (!fileExistsAndValid) {
        debugPrint('[GetStartedController] ⚠️ Files not ready - showing download UI');

        hideStartButtonDuringTileCheck.value = false;
        isCheckingTiles.value = false;
        showDownloadUI.value = true;

        isCompleted.value = false;
        hasError.value = false;
        isDownloading.value = false;
        statusText.value = "Download 4.5GB of map tiles to use offline";

        await _checkInternetAndShowAppropriateScreen();
      } else {
        debugPrint('[GetStartedController] ⚠️ Files exist but preferences not set - hiding start button');

        _prepareLoaderOnlyState();
        await _navigateToMainFromStartup();
      }
    } else {
      // Never leave UI in endless "checking" state.
      debugPrint('[GetStartedController] ❌ MbtilesDownloadService unavailable, showing download UI fallback');
      hideStartButtonDuringTileCheck.value = false;
      isCheckingTiles.value = false;
      showDownloadUI.value = true;
      hasError.value = false;
      isDownloading.value = false;
      statusText.value = "Download 4.5GB of map tiles to use offline";
      await _checkInternetAndShowAppropriateScreen();
    }
  }

  void _prepareLoaderOnlyState() {
    // Keep Get Started visuals and hide only Start while we route to the map.
    hideStartButtonDuringTileCheck.value = true;
    isCheckingTiles.value = true;
    showDownloadUI.value = true;
    isNoInternet.value = false;
  }

  Future<void> _navigateToMainFromStartup() async {
    await Future.delayed(const Duration(seconds: 1));
    Get.offAllNamed(Routes.MAP_NEW);
  }

  Future<void> _recoverStyleJsonInBackground(
    String tilesPath,
    bool styleJsonExists,
    SharedPreferences prefs,
  ) async {
    // Recover style.json in background when missing.
    if (!styleJsonExists && _styleJsonDownloadService != null) {
      debugPrint('[GetStartedController] 🎨 style.json missing, attempting background recovery...');
      try {
        await _styleJsonDownloadService!.downloadStyleJson(
          enableBackgroundDownload: false,
        );
        final recovered = await _styleJsonDownloadService!.isStyleJsonDownloaded();
        if (recovered) {
          await prefs.setBool('mbtiles_download_completed', true);
          await prefs.setBool(PREFS_KEY_MBTILES_DOWNLOADED, true);
          await prefs.setString(PREFS_KEY_MBTILES_PATH, tilesPath);
          debugPrint('[GetStartedController] ✅ style.json recovered in background');
        }
      } catch (e) {
        debugPrint('[GetStartedController] ⚠️ style.json background recovery failed: $e');
      }
    }
  }

  /// Start the tile server with downloaded tiles
  Future<bool> _startTileServer(String tilesPath) async {
    try {
      debugPrint('[GetStartedController] 🗺️ Starting tile server...');

      final serverService = MbtilesServerService.instance;
      final serverUrl = await serverService
          .startServer(tilesPath)
          .timeout(const Duration(seconds: 8));

      if (serverUrl != null) {
        debugPrint('[GetStartedController] ✅ Tile server started successfully at: $serverUrl');
        debugPrint('[GetStartedController] 📡 Tiles will be served from: $serverUrl/{z}/{x}/{y}.pbf');
        return true;
      } else {
        debugPrint('[GetStartedController] ❌ Failed to start tile server');
        return false;
      }
    } catch (e) {
      debugPrint('[GetStartedController] ❌ Error starting tile server: $e');
      return false;
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
    hideStartButtonDuringTileCheck.value = false;

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
  static const _backgroundRefreshChannel = MethodChannel('com.spacetime.app/settings');

  Future<String> _getBackgroundRefreshStatus() async {
    if (!Platform.isIOS) return 'available';
    try {
      final status = await _backgroundRefreshChannel.invokeMethod<String>('getBackgroundRefreshStatus');
      return status ?? 'unknown';
    } catch (e) {
      debugPrint('[GetStartedController] Error checking background refresh: $e');
      return 'unknown';
    }
  }

  Future<bool> _showBackgroundRefreshPopup() async {
    if (!Platform.isIOS) return true;
    if (_backgroundRefreshPopupShowing) return false;

    _backgroundRefreshPopupShowing = true;
    final uiController = Get.find<UiController>();
    final isDark = uiController.darkMode.value;
    final bgColor = isDark ? uiController.darkSurfaceColor : uiController.getLightModeBackgroundColor(uiController.mainColor.value);
    final titleColor = isDark ? Colors.white : Colors.black87;
    final contentColor = isDark ? Colors.white70 : Colors.black54;
    final ignoreColor = isDark ? Colors.white70 : Colors.grey.shade600;
    final accentColor = uiController.currentMainColor;

    try {
      final completer = Completer<bool>();
      Get.dialog(
        AlertDialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          title: Text(
            'Background refresh deactivated',
            style: TextStyle(
              fontFamily: 'KumbhSans',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: titleColor,
            ),
          ),
          content: Text(
            'Activate background refresh in Settings → General → Background App Refresh\n\n'
            'Otherwise the tile download may cancel after ~3 minutes in background.',
            style: TextStyle(
              fontFamily: 'KumbhSans',
              fontSize: 14,
              height: 1.35,
              color: contentColor,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (Get.isDialogOpen != true) return;
                Get.back();
                if (!completer.isCompleted) completer.complete(false);
              },
              child: Text(
                'Not now',
                style: TextStyle(
                  fontFamily: 'KumbhSans',
                  color: ignoreColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Get.back();
                openAppSettings();
                if (!completer.isCompleted) completer.complete(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              child: Text(
                'Activate',
                style: TextStyle(
                  fontFamily: 'KumbhSans',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        barrierDismissible: false,
      );

      return await completer.future;
    } finally {
      _backgroundRefreshPopupShowing = false;
    }
  }

  Future<bool> _waitForBackgroundRefreshToBecomeAvailable({Duration timeout = const Duration(seconds: 90)}) async {
    if (!Platform.isIOS) return true;

    final statusNow = await _getBackgroundRefreshStatus();
    if (statusNow == 'available') return true;

    final completer = Completer<bool>();
    _waitingForBackgroundRefreshCompleter = completer;
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      return false;
    } finally {
      if (_waitingForBackgroundRefreshCompleter == completer) {
        _waitingForBackgroundRefreshCompleter = null;
      }
    }
  }

  Future<void> _maybeShowBackgroundRefreshPopupOnResume() async {
    final status = await _getBackgroundRefreshStatus();
    if (status == 'available') return;
    await _showBackgroundRefreshPopup();
  }

  Future<void> startDownload() async {
    if (isDownloading.value) {
      debugPrint('[GetStartedController] Download already in progress, ignoring tap');
      return;
    }

    try {
      final bgStatus = await _getBackgroundRefreshStatus();
      debugPrint('[GetStartedController] Background refresh status: $bgStatus');
      if (bgStatus != 'available') {
        final userActivated = await _showBackgroundRefreshPopup();
        if (userActivated) {
          // Wait until user returns to app and background refresh is actually enabled.
          await _waitForBackgroundRefreshToBecomeAvailable();
        }
      }

      debugPrint('[GetStartedController] 🔔 Checking notification permission...');
      statusText.value = "Checking permissions...";

      final notificationStatus = await Permission.notification.status;
      debugPrint('[GetStartedController] 🔔 Notification status: $notificationStatus');

      if (!notificationStatus.isGranted) {
        debugPrint('[GetStartedController] 🔔 Requesting notification permission...');
        final result = await Permission.notification.request();
        debugPrint('[GetStartedController] 🔔 Notification permission result: $result');

        if (!result.isGranted) {
          debugPrint('[GetStartedController] ⚠️ Notification permission denied');
        }
      }

      const bool canDownloadInBackground = true;

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

      _setupMbtilesDownloadListeners();

      debugPrint('[GetStartedController] 📥 Starting downloads in parallel...');
      debugPrint('[GetStartedController] 📱 Background download enabled: $canDownloadInBackground');

      // Start tiles download
      _mbtilesDownloadService!.downloadMbtiles(
        zoomLevel: selectedZoomLevel.value,
        enableBackgroundDownload: canDownloadInBackground,
      );

      // Start style.json download in parallel and keep a reference so completion
      // can be finalized only when BOTH tiles + style are ready.
      if (_styleJsonDownloadService != null) {
        _styleDownloadFuture = _styleJsonDownloadService!.downloadStyleJson(
          enableBackgroundDownload: canDownloadInBackground,
        );
        _styleDownloadFuture!
            .then((path) {
              if (path != null) {
                debugPrint(
                  '[GetStartedController] ✅ Style.json download completed: $path',
                );
              } else {
                debugPrint('[GetStartedController] ⚠️ Style.json download failed');
              }
            })
            .catchError((e) {
              debugPrint('[GetStartedController] ❌ Style.json download error: $e');
            });
      } else {
        debugPrint('[GetStartedController] ⚠️ StyleJsonDownloadService not initialized');
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
    if (_isFinalizingDownload) return;
    _isFinalizingDownload = true;

    debugPrint('[GetStartedController] 🎉 MBTiles download completed!');
    debugPrint('[GetStartedController] 📁 Saved to: $downloadedPath');

    // Ensure style.json is also complete before marking download state as done.
    statusText.value = "Finishing map style...";
    debugPrint('[GetStartedController] 📥 Ensuring style.json is downloaded...');

    String? styleJsonPath;
    try {
      styleJsonPath =
          await (_styleDownloadFuture ??
              _styleJsonDownloadService?.downloadStyleJson());
      if (styleJsonPath != null) {
        debugPrint('[GetStartedController] ✅ Style.json downloaded successfully to: $styleJsonPath');
      } else {
        debugPrint('[GetStartedController] ❌ Style.json download failed');
      }
    } catch (e) {
      debugPrint('[GetStartedController] ❌ Error downloading style.json: $e');
    } finally {
      _styleDownloadFuture = null;
    }

    if (styleJsonPath == null) {
      hasError.value = true;
      isDownloading.value = false;
      isCompleted.value = false;
      tilesDownloadCompleted.value = false;
      statusText.value = "Style download failed. Please retry.";
      errorMessage.value = "Map style download failed";
      _isFinalizingDownload = false;
      return;
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
    _isFinalizingDownload = false;
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
        debugPrint('[GetStartedController] ✅ Download completed!');
        timer.cancel();

        final downloadedPath = _mbtilesDownloadService!.getLocalMbtilesPath();
        if (downloadedPath != null) {
          _onMbtilesDownloadCompleted(downloadedPath);
        }
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
  Future<void> closeApp() async {
    debugPrint('[GetStartedController] Closing app...');
    if (GetPlatform.isAndroid) {
      await SystemNavigator.pop();
      return;
    }

    if (GetPlatform.isIOS) {
      // User-requested force close on iOS.
      exit(0);
    }

    await SystemNavigator.pop();
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

      if (!Get.isRegistered<PermissionService>()) {
        hasLocationPermission.value = false;
        return;
      }
      final ps = Get.find<PermissionService>();
      final granted = await ps.checkLocationPermission(requestIfDenied: false).timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('[GetStartedController] Permission check timed out, using cached state');
          return ps.hasLocationPermission.value;
        },
      );
      hasLocationPermission.value = granted;
    } catch (e) {
      debugPrint('[GetStartedController] Error checking location permissions: $e');
      hasLocationPermission.value = Get.isRegistered<PermissionService>()
          ? Get.find<PermissionService>().hasLocationPermission.value
          : false;
    } finally {
      isCheckingPermissions.value = false;
    }
  }
}

Map<String, Object?> _checkTilesFileInIsolate({
  required String? savedPath,
  required bool downloadCompleted,
  required String fallbackPath,
  required int minExpectedSize,
}) {
  bool fileExistsAndValid = false;
  String? tilesPath;
  bool recoveredFromFallback = false;

  if (savedPath != null) {
    final file = File(savedPath);
    if (file.existsSync()) {
      if (downloadCompleted) {
        fileExistsAndValid = true;
        tilesPath = savedPath;
      } else {
        final fileSize = file.lengthSync();
        if (fileSize >= minExpectedSize) {
          fileExistsAndValid = true;
          tilesPath = savedPath;
        }
      }
    }
  }

  if (!fileExistsAndValid) {
    final fallbackFile = File(fallbackPath);
    if (fallbackFile.existsSync()) {
      final fileSize = fallbackFile.lengthSync();
      if (fileSize >= minExpectedSize) {
        fileExistsAndValid = true;
        tilesPath = fallbackPath;
        recoveredFromFallback = true;
      }
    }
  }

  return {
    'fileExistsAndValid': fileExistsAndValid,
    'tilesPath': tilesPath,
    'recoveredFromFallback': recoveredFromFallback,
  };
}
