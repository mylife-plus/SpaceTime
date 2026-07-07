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
import '../../../../services/app_lock_controller.dart';
import '../../../../services/mbtiles_download_service.dart';
import '../../../../services/mbtiles_server_service.dart';
import '../../../../services/style_json_download_service.dart';
import '../../../services/memory_db.dart';
import '../../../services/path_migration_helper.dart';
import '../../../helpers/mapbox_zoom_helper.dart';
import '../../../../services/memory_geojson_service.dart';
import '../../ui/controllers/ui_controller.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';

const String PREFS_KEY_MBTILES_DOWNLOADED = 'mbtiles_downloaded';
const String PREFS_KEY_MBTILES_PATH = 'mbtiles_path';
const String PREFS_KEY_IOS_BAR_EDUCATION_POPUP_SHOWN =
    'ios_bar_education_popup_shown';

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
  final RxString statusText = ''.obs;
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

  // State for UI visibility
  final RxBool showDownloadUI = false.obs; // Controls visibility of download button and language dropdown
  final RxBool isCheckingTiles = true.obs; // Shows loading state while checking tiles
  final RxBool tilesAlreadyDownloaded = false.obs; // Tracks if tiles were already downloaded when app started
  final RxBool hideStartButtonDuringTileCheck = false.obs;

  final RxBool isInitializing = true.obs;

  bool _startupInitializationStarted = false;

  /// Prevents overlapping [Get.offAllNamed] to MAP_NEW (causes half map / half get-started glitches).
  bool _navigateToMapRequested = false;

  // iOS Background App Refresh gating
  Completer<bool>? _waitingForBackgroundRefreshCompleter;
  bool _backgroundRefreshPopupShowing = false;

  /// Shown below Start after the one-time B.A.R. dialog was seen and refresh is still off.
  final RxBool iosBackgroundRefreshBannerVisible = false.obs;

  String _statusL10nKey = '';
  List<Object?> _statusL10nArgs = const [];
  static const int _kStatusLocal = 0;
  static const int _kStatusMbtiles = 1;
  static const int _kStatusOffline = 2;
  int _statusBinding = _kStatusLocal;

  void _setStatusText(String key, [List<Object?> args = const []]) {
    _statusBinding = _kStatusLocal;
    _statusL10nKey = key;
    _statusL10nArgs = args.isEmpty ? const [] : List<Object?>.from(args);
    statusText.value =
        args.isEmpty ? key.tr : trKey(key, _statusL10nArgs);
  }

  void _setStatusFromMbtilesService() {
    final svc = _mbtilesDownloadService;
    if (svc == null) return;
    final s = svc.statusText.value;
    if (s.isEmpty) return;
    _statusBinding = _kStatusMbtiles;
    _statusL10nKey = '';
    statusText.value = s;
  }

  void _setStatusFromOfflineService(String s) {
    if (s.isEmpty) return;
    _statusBinding = _kStatusOffline;
    _statusL10nKey = '';
    statusText.value = s;
  }

  void _refreshStatusTextForLocale() {
    switch (_statusBinding) {
      case _kStatusMbtiles:
        _setStatusFromMbtilesService();
        break;
      case _kStatusOffline:
        final o = _offlineMapService;
        if (o != null && o.downloadStatusText.value.isNotEmpty) {
          statusText.value = o.downloadStatusText.value;
        }
        break;
      default:
        if (_statusL10nKey.isNotEmpty) {
          statusText.value = _statusL10nArgs.isEmpty
              ? _statusL10nKey.tr
              : trKey(_statusL10nKey, List<Object?>.from(_statusL10nArgs));
        }
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    if (Get.isRegistered<UiController>()) {
      ever(Get.find<UiController>().selectedLanguage, (_) {
        _refreshStatusTextForLocale();
      });
    }
    _setStatusText('get_started_status_preparing');
  }

  @override
  void onReady() {
    super.onReady();
    // [main] bootstrap may finish before this controller exists (e.g. app lock on launch).
    runStartupInitialization();
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
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final status = await _getBackgroundRefreshStatusStable(
          attempts: 5,
          step: const Duration(milliseconds: 280),
        );
        final enabled = status == 'available';
        if (!completer.isCompleted) completer.complete(enabled);
        await refreshIosBackgroundRefreshBanner();
      }());
      return;
    }

    unawaited(refreshIosBackgroundRefreshBanner());
  }

  /// Called from [main] after core services register (native splash already removed).
  void runStartupInitialization() {
    if (_startupInitializationStarted) return;
    _startupInitializationStarted = true;
    _initializeEverything();
  }

  Future<void> _initializeEverything() async {
    try {
      isInitializing.value = true;
      await _initializeBackgroundServices();
      _initializeServices();
      // Render Get Started UI first, then begin tile checks.
      isInitializing.value = false;
      await _waitForUiFrame();
      await _checkIfShouldShowGetStarted();
    } catch (e, st) {
      debugPrint('[GetStartedController] Startup initialization failed: $e\n$st');
      hideStartButtonDuringTileCheck.value = false;
      isCheckingTiles.value = false;
      showDownloadUI.value = true;
    } finally {
      isInitializing.value = false;
    }
  }

  /// Do not mount Mapbox / route to the map until Face ID or PIN completes.
  Future<void> _waitUntilAppUnlocked() async {
    if (!Get.isRegistered<AppLockController>()) return;
    final lock = Get.find<AppLockController>();
    if (!lock.isLocked.value) return;

    debugPrint('[GetStartedController] Waiting for app unlock before map routing...');
    final completer = Completer<void>();
    late Worker subscription;
    subscription = ever(lock.isLocked, (locked) {
      if (!locked) {
        subscription.dispose();
        if (!completer.isCompleted) completer.complete();
      }
    });
    await completer.future;
  }

  Future<void> _waitForUiFrame() async {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    // Small buffer so book/loader paints before heavy checks start.
    await Future<void>.delayed(const Duration(milliseconds: 120));
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
    await _waitUntilAppUnlocked();

    if (_mbtilesDownloadService != null) {
      final serviceDownloaded =
          await _mbtilesDownloadService!.isMbtilesDownloaded();
      final servicePath = _mbtilesDownloadService!.getLocalMbtilesPath();
      if (serviceDownloaded &&
          servicePath != null &&
          servicePath.isNotEmpty) {
        debugPrint(
          '[GetStartedController] ✅ Tiles already on device — routing to map',
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('mbtiles_download_completed', true);
        await prefs.setBool(PREFS_KEY_MBTILES_DOWNLOADED, true);
        await prefs.setString(PREFS_KEY_MBTILES_PATH, servicePath);
        final styleJsonExists =
            await (_styleJsonDownloadService?.isStyleJsonDownloaded() ??
                Future<bool>.value(false));
        tilesAlreadyDownloaded.value = true;
        _prepareLoaderOnlyState();
        final serverStarted = await _startTileServer(servicePath);
        if (!serverStarted) {
          hideStartButtonDuringTileCheck.value = false;
          isCheckingTiles.value = false;
          showDownloadUI.value = true;
          hasError.value = true;
          errorMessage.value = 'get_started_error_tile_server_failed'.tr;
          _setStatusText('get_started_status_tile_server_unavailable');
          return;
        }
        unawaited(
          _recoverStyleJsonInBackground(servicePath, styleJsonExists, prefs),
        );
        await _navigateToMainFromStartup();
        return;
      }

      final prefs = await SharedPreferences.getInstance();

      var downloadCompleted =
          prefs.getBool('mbtiles_download_completed') ?? false;
      if (!downloadCompleted) {
        downloadCompleted =
            prefs.getBool(PREFS_KEY_MBTILES_DOWNLOADED) ?? false;
      }
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
          errorMessage.value = 'get_started_error_tile_server_failed'.tr;
          _setStatusText('get_started_status_tile_server_unavailable');
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
        _setStatusText('get_started_status_download_mbtiles_offline');

        _startWelcomeSequence();
        unawaited(refreshIosBackgroundRefreshBanner());
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
      _setStatusText('get_started_status_download_mbtiles_offline');
      _startWelcomeSequence();
      unawaited(refreshIosBackgroundRefreshBanner());
    }
  }

  void _prepareLoaderOnlyState() {
    // Keep Get Started visuals and hide only Start while we route to the map.
    hideStartButtonDuringTileCheck.value = true;
    isCheckingTiles.value = true;
    showDownloadUI.value = true;
  }

  Future<void> _navigateToMainFromStartup() async {
    await Future.delayed(const Duration(seconds: 2));
    await navigateToMainApp();
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

  void _showNoInternetSnackbar() {
    showTrSnackbar('snackbar_no_internet', 
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      backgroundColor: Colors.black87,
      colorText: Colors.white,
      duration: const Duration(seconds: 4),);
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
      errorMessage.value = 'get_started_error_init_services'.tr;
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
      unawaited(refreshIosBackgroundRefreshBanner());
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

  /// Applies app locale (same as Settings → Language).
  void selectLanguage(String languageCode) {
    Get.find<UiController>().setLanguage(languageCode);
    _refreshStatusTextForLocale();
    debugPrint('[GetStartedController] Selected language: $languageCode');
  }

  /// Start the mbtiles download process from Cloudflare R2
  /// Downloads mbtiles file based on selected zoom level and saves to app-specific folder
  static const _backgroundRefreshChannel = MethodChannel('com.spacetime.app/settings');

  static String _normalizeBackgroundRefreshPayload(dynamic raw) {
    if (raw == null) return 'unknown';
    final s = raw.toString().trim().toLowerCase();
    switch (s) {
      case 'available':
      case 'denied':
      case 'restricted':
      case 'unknown':
        return s;
      default:
        return 'unknown';
    }
  }

  Future<String> _getBackgroundRefreshStatus() async {
    if (!Platform.isIOS) return 'available';
    try {
      final raw = await _backgroundRefreshChannel.invokeMethod(
        'getBackgroundRefreshStatus',
      );
      return _normalizeBackgroundRefreshPayload(raw);
    } catch (e) {
      debugPrint('[GetStartedController] Error checking background refresh: $e');
      return 'unknown';
    }
  }

  /// iOS often reports a stale non-available [UIBackgroundRefreshStatus] for a short
  /// time after launch or resume even when Background App Refresh is enabled.
  Future<String> _getBackgroundRefreshStatusStable({
    int attempts = 6,
    Duration step = const Duration(milliseconds: 220),
  }) async {
    if (!Platform.isIOS) return 'available';
    var last = 'unknown';
    for (var i = 0; i < attempts; i++) {
      last = await _getBackgroundRefreshStatus();
      if (last == 'available') return 'available';
      if (i < attempts - 1) await Future<void>.delayed(step);
    }
    return last;
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
          actionsAlignment: MainAxisAlignment.center,
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          title: SizedBox(
            width: double.infinity,
            child: Text(
              'text_background_refresh_deactivated'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'KumbhSans',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: titleColor,
              ),
            ),
          ),
          content: SizedBox(
            width: double.infinity,
            child: Text(
              'text_activate_background_refresh_in_settings_general_bac'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'KumbhSans',
                fontSize: 14,
                height: 1.35,
                color: contentColor,
              ),
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
                'text_not_now'.tr,
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
                if (Get.isRegistered<AppLockController>()) {
                  Get.find<AppLockController>().scheduleRestartOnNextResume();
                }
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
                'text_activate'.tr,
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

    final statusNow = await _getBackgroundRefreshStatusStable();
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

  Future<bool> _readIosBarPopupShownPref() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(PREFS_KEY_IOS_BAR_EDUCATION_POPUP_SHOWN) ?? false;
  }

  Future<void> _writeIosBarPopupShownPref() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(PREFS_KEY_IOS_BAR_EDUCATION_POPUP_SHOWN, true);
  }

  /// Updates red banner under Start: visible only after one-time dialog was shown, B.A.R. still off, download not finished/active.
  Future<void> refreshIosBackgroundRefreshBanner() async {
    if (!Platform.isIOS) {
      iosBackgroundRefreshBannerVisible.value = false;
      return;
    }
    if (!await _readIosBarPopupShownPref()) {
      iosBackgroundRefreshBannerVisible.value = false;
      return;
    }
    final status = await _getBackgroundRefreshStatusStable(
      attempts: 5,
      step: const Duration(milliseconds: 180),
    );
    final barOff = status != 'available';
    final show = barOff && !isCompleted.value && !isDownloading.value;
    iosBackgroundRefreshBannerVisible.value = show;
  }

  Future<void> startDownload() async {
    if (isDownloading.value) {
      debugPrint('[GetStartedController] Download already in progress, ignoring tap');
      return;
    }

    try {
      final tilesOk =
          _mbtilesDownloadService != null &&
          await _mbtilesDownloadService!.isMbtilesDownloaded();
      final styleOk =
          _styleJsonDownloadService != null &&
          await _styleJsonDownloadService!.isStyleJsonDownloaded();
      if (!tilesOk || !styleOk) {
        final hasInternet =
            await Get.find<ConnectivityService>().hasInternetQuickCheck();
        if (!hasInternet) {
          debugPrint(
            '[GetStartedController] Start blocked: offline and tiles/style not ready',
          );
          _showNoInternetSnackbar();
          return;
        }
      }

      if (Platform.isIOS) {
        var bgStatus = await _getBackgroundRefreshStatusStable();
        debugPrint('[GetStartedController] Background refresh status (stable): $bgStatus');
        if (bgStatus != 'available') {
          final alreadyShown = await _readIosBarPopupShownPref();
          var userOpenedSettings = false;
          if (!alreadyShown) {
            userOpenedSettings = await _showBackgroundRefreshPopup();
            await _writeIosBarPopupShownPref();
          }
          if (userOpenedSettings) {
            await _waitForBackgroundRefreshToBecomeAvailable();
          }
          // Extra passes after returning from Settings — OS can update BAR flag late.
          for (var i = 0; i < 4 && bgStatus != 'available'; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
            bgStatus = await _getBackgroundRefreshStatusStable(
              attempts: 3,
              step: const Duration(milliseconds: 200),
            );
            debugPrint('[GetStartedController] Background refresh re-check ($i): $bgStatus');
          }
        }
        await refreshIosBackgroundRefreshBanner();
      } else {
        iosBackgroundRefreshBannerVisible.value = false;
      }

      debugPrint('[GetStartedController] 🔔 Checking notification permission...');
      _setStatusText('get_started_status_checking_permissions');

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
          errorMessage.value = 'get_started_error_init_download_service'.tr;
          _setStatusText('get_started_status_init_failed');
          return;
        }
        debugPrint('[GetStartedController] ✅ MbtilesDownloadService initialized successfully');
      }

      // Reset state before starting download
      isDownloading.value = true;
      hasError.value = false;
      isCompleted.value = false;
      errorMessage.value = "";
      _setStatusText(
        'get_started_status_preparing_zoom',
        [selectedZoomLevel.value],
      );
      downloadProgress.value = 0.0;
      unawaited(refreshIosBackgroundRefreshBanner());

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
      errorMessage.value = trKey('get_started_error_start_download', [e.toString()]);
      _setStatusText('text_download_failed');
      isDownloading.value = false;
      unawaited(refreshIosBackgroundRefreshBanner());
    }
  }

  /// Handle mbtiles download completion
  void _onMbtilesDownloadCompleted(String downloadedPath) async {
    if (_isFinalizingDownload) return;
    _isFinalizingDownload = true;

    debugPrint('[GetStartedController] 🎉 MBTiles download completed!');
    debugPrint('[GetStartedController] 📁 Saved to: $downloadedPath');

    // Ensure style.json is also complete before marking download state as done.
    _setStatusText('get_started_status_finishing_style');
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
      _setStatusText('get_started_status_style_failed');
      errorMessage.value = 'get_started_error_style_failed'.tr;
      _isFinalizingDownload = false;
      return;
    }

    isCompleted.value = true;
    isDownloading.value = false;
    tilesDownloadCompleted.value = true;
    _setStatusText('get_started_status_map_tiles_ready');
    downloadProgress.value = 1.0;
    unawaited(refreshIosBackgroundRefreshBanner());

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

      // Update status text (service owns l10n; mirror here for binding)
      final status = _mbtilesDownloadService!.statusText.value;
      if (status.isNotEmpty && statusText.value != status) {
        _setStatusFromMbtilesService();
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
        unawaited(refreshIosBackgroundRefreshBanner());
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
        _setStatusText(
          'get_started_status_downloading_maps_pct',
          [(progress * 100).toStringAsFixed(1)],
        );
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
        _setStatusText('get_started_status_downloaded_n_tiles', [tileCount]);
      }
    });

    // Listen to status text updates
    ever(_offlineMapService!.downloadStatusText, (String status) {
      if (status.isNotEmpty && !isDownloadingZoom10.value) {
        _setStatusFromOfflineService(status);
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
      _setStatusText('get_started_status_downloading_zoom14');

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
          _setStatusText(
            'get_started_status_zoom14_progress',
            [downloaded],
          );
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
    _setStatusText(
      'get_started_status_download_complete_n_tiles',
      [downloadedTileCount.value],
    );
    unawaited(refreshIosBackgroundRefreshBanner());

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
    if (_navigateToMapRequested) {
      debugPrint(
        '[GetStartedController] navigateToMainApp ignored — already navigating to map',
      );
      return;
    }
    _navigateToMapRequested = true;

    try {
      await _waitUntilAppUnlocked();
      debugPrint('[GetStartedController] Navigating to MapViewWidgetNew...');

      // Start tile server if tiles are downloaded
      if (_mbtilesDownloadService != null) {
        final isDownloaded = await _mbtilesDownloadService!.isMbtilesDownloaded();
        final tilesPath = _mbtilesDownloadService!.getLocalMbtilesPath();

        if (isDownloaded && tilesPath != null) {
          await _startTileServer(tilesPath);
        }
      }

      // Instant route swap (Transition.noTransition on MAP_NEW) — no extra frame wait.
      Get.offAllNamed(Routes.MAP_NEW);
    } catch (e) {
      debugPrint('[GetStartedController] navigateToMainApp failed: $e');
      _navigateToMapRequested = false;
    }
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
