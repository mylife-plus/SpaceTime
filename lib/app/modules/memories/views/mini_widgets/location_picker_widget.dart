import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../../../../../services/world_locations_service.dart';
import '../../../../../services/offline_location_search_service.dart'
    as offline;
import '../../../../../services/offline_settings_service.dart';
import '../../../../../services/global_tile_manager.dart';

import '../../../../../services/geocoding_isolate_service.dart';
import '../../../../../services/connectivity_service.dart';
import '../../../../../services/background_tile_download_service.dart';
import '../../../../services/offline_map_service.dart';
import '../../../../../services/permission_service.dart';
import 'internet_required_screen_location_picker.dart';

import '../../../../config/app_colors.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/widgets/location_picker_system_ui_shell.dart';

enum LocationPickerState {
  initial,
  checkingInternet,
  internetRequired,
  loadingMap,
  ready,
  error,
}

class LocationPickerWidget extends StatefulWidget {
  const LocationPickerWidget({super.key});

  @override
  State<LocationPickerWidget> createState() => _LocationPickerWidgetState();
}

class _LocationPickerWidgetState extends State<LocationPickerWidget> {
  mapbox.MapboxMap? mapController;
  final memoryController = Get.find<MemoryController>();
  final uiController = Get.find<UiController>();

  Position? currentPosition;

  bool hasLocationPermission = false;
  mapbox.PointAnnotation? currentLocationMarker;
  mapbox.PointAnnotationManager? annotationManager;
  bool isLoading = true;
  bool isOfflineMode = false;
  String offlineModeReason = '';
  OfflineModePriority offlineModePriority = OfflineModePriority.networkCheck;
  Map<String, dynamic> offlineLocationData = {};
  List<Map<String, dynamic>> savedLocations = [];
  Map<String, dynamic>? selectedLocationData;

  // Internet required screen state
  LocationPickerState currentState = LocationPickerState.initial;
  bool showInternetScreen = false;

  PermissionService? _permissionService;
  StreamSubscription<bool>? _permissionSubscription;
  BackgroundTileDownloadService? _backgroundTileService;
  OfflineMapService? _offlineMapService;
  bool _offlineModeEnabledByPicker = false;
  Worker? _offlineTileCountWorker;
  Worker? _legacyTileCountWorker;
  Worker? _offlineReadyWorker;

  static const int _offlineTileThreshold = 40000;
  static const int _legacyTileThreshold = 30000;

  /// Set the current state and log the change
  void _setCurrentState(
    LocationPickerState newState,
    String functionName, [
    String? reason,
  ]) {
    final oldState = currentState;
    debugPrint(
      '[LocationPickerWidget][StateChanges][$functionName]: $oldState → $newState${reason != null ? ' (Reason: $reason)' : ''}',
    );

    setState(() {
      currentState = newState;
    });
  }

  @override
  void initState() {
    super.initState();

    // Location permission is now optional - check status but don't block initialization
    if (Get.isRegistered<PermissionService>()) {
      try {
        _permissionService = PermissionService.instance;
        hasLocationPermission = _permissionService!.hasLocationPermission.value;
        _permissionSubscription = _permissionService!.permissionChanges.listen((
          granted,
        ) {
          if (!mounted) return;

          setState(() {
            hasLocationPermission = granted;
          });

          // If permission was granted, try to get current location again
          if (granted) {
            hasAskedLocationPermissionOnce = false;
            _getCurrentLocation();
          }
        });
      } catch (e) {
        debugPrint('LocationPickerWidget: PermissionService unavailable - $e');
      }
    }

    // Initialize offline services similar to map controller
    if (Get.isRegistered<BackgroundTileDownloadService>()) {
      try {
        _backgroundTileService = Get.find<BackgroundTileDownloadService>();
        _legacyTileCountWorker = ever<int>(
          _backgroundTileService!.totalTilesDownloaded,
          (_) {
            if (!mounted) return;
            _updateOfflineAvailability();
          },
        );
      } catch (e) {
        debugPrint(
          'LocationPickerWidget: BackgroundTileDownloadService unavailable - $e',
        );
      }
    }

    if (Get.isRegistered<OfflineMapService>()) {
      try {
        _offlineMapService = Get.find<OfflineMapService>();
        _offlineTileCountWorker = ever<int>(
          _offlineMapService!.downloadedTileCount,
          (_) {
            if (!mounted) return;
            _updateOfflineAvailability();
          },
        );
        _offlineReadyWorker = ever<bool>(_offlineMapService!.isOfflineReady, (
          _,
        ) {
          if (!mounted) return;
          _updateOfflineAvailability();
        });
      } catch (e) {
        debugPrint(
          'LocationPickerWidget: OfflineMapService lookup failed - $e',
        );
      }
    } else {
      try {
        _offlineMapService = Get.put(OfflineMapService(), permanent: true);
        _offlineTileCountWorker = ever<int>(
          _offlineMapService!.downloadedTileCount,
          (_) {
            if (!mounted) return;
            _updateOfflineAvailability();
          },
        );
        _offlineReadyWorker = ever<bool>(_offlineMapService!.isOfflineReady, (
          _,
        ) {
          if (!mounted) return;
          _updateOfflineAvailability();
        });
      } catch (e) {
        debugPrint(
          'LocationPickerWidget: Unable to create OfflineMapService - $e',
        );
      }
    }

    _syncOfflineStateFromServices();

    _initializeLocationPicker();
  }

  Future<void> _initializeLocationPicker() async {
    try {
      _setCurrentState(
        LocationPickerState.loadingMap,
        '_initializeLocationPicker',
        'Loading map for location picking',
      );

      // Simply check if map is ready and allow offline operation
      await _initializeOfflineData();

      // Set to ready state to allow location picking
      _setCurrentState(
        LocationPickerState.ready,
        '_initializeLocationPicker',
        'Map ready for location picking',
      );

      setState(() {
        showInternetScreen = false;
      });

      await _getCurrentLocation();
    } catch (e) {
      debugPrint('❌ Error initializing location picker: $e');
      _setCurrentState(
        LocationPickerState.error,
        '_initializeLocationPicker',
        'Initialization error: $e',
      );
    }
  }

  bool hasAskedLocationPermissionOnce = false;

  /// Handle map load errors
  void _handleMapLoadError(String errorMessage) async {
    debugPrint('🗺️ LocationPicker - Map load error: $errorMessage');

 final hasSufficientTiles = await _checkOfflineTileCount();

      if (!hasSufficientTiles) {
        debugPrint('[MapControllerNew] ❌ Insufficient offline tiles available, showing Internet Required Screen');
        // Skip offline mode attempt and show internet required screen
      try {
      final connectivityService = Get.find<ConnectivityService>();

      // Check if it's a connectivity error
      if (connectivityService.isMapboxConnectivityError(errorMessage)) {
        debugPrint('🌐 LocationPicker - Connectivity error detected');

        final hasInternet = await connectivityService.hasInternetForMapbox();
        if (!hasInternet) {
          _setCurrentState(
            LocationPickerState.internetRequired,
            '_handleMapLoadError',
            'Connectivity error detected',
          );
          setState(() {
            showInternetScreen = true;
          });
        }
      } else {
        _setCurrentState(
          LocationPickerState.error,
          '_handleMapLoadError',
          'Map load error: $errorMessage',
        );
      }
    } catch (e) {
      debugPrint('❌ Error handling map load error: $e');
      _setCurrentState(
        LocationPickerState.internetRequired,
        '_handleMapLoadError',
        'Error handling map load error: $e',
      );
      setState(() {
        showInternetScreen = true;
      });
    }
        return;
      }

    
  }


Future<bool> _checkOfflineTileCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tileCount = prefs.getInt('offline_downloaded_tile_count') ?? 0;

      debugPrint('[MapControllerNew] 📊 Fetched offline tile count from SharedPreferences: $tileCount tiles');

      if (tileCount >= 500) {
        debugPrint('[MapControllerNew] ✅ Sufficient tiles available: $tileCount >= 500');
        return true;
      } else {
        debugPrint('[MapControllerNew] ❌ Insufficient tiles: $tileCount < 500');
        return false;
      }
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error fetching tile count from SharedPreferences: $e');
      return false;
    }
  }

  Future<void> _initializeOfflineData() async {
    try {
      await _determineOfflineMode();
    } catch (e) {
      debugPrint('Error initializing offline data: $e');
    }
  }

  Future<void> _loadSavedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationsJson = prefs.getString('saved_locations') ?? '[]';
      final List<dynamic> locationsList = json.decode(locationsJson);

      savedLocations =
          locationsList
              .map((location) => Map<String, dynamic>.from(location))
              .toList();

      // Sort by timestamp (most recent first)
      savedLocations.sort((a, b) {
        final aTimestamp = a['timestamp'] as String? ?? '';
        final bTimestamp = b['timestamp'] as String? ?? '';
        return bTimestamp.compareTo(aTimestamp);
      });

      debugPrint(
        '📍 Loaded ${savedLocations.length} saved locations (sorted by recency)',
      );
    } catch (e) {
      debugPrint('❌ Error loading saved locations: $e');
      savedLocations = [];
    }
  }

  /// Comprehensive offline mode detection with priority system
  Future<void> _determineOfflineMode() async {
    try {
      debugPrint('🔍 Determining offline mode...');

      // Initialize services if needed
      await OfflineSettingsService.instance.initialize();
      await GlobalTileManager.instance.initialize();

      // Get offline mode determination from settings service
      final offlineMode =
          await OfflineSettingsService.instance.determineOfflineMode();

      if (offlineMode.priority != OfflineModePriority.networkCheck) {
        // Use settings service determination
        isOfflineMode = offlineMode.isOffline;
        offlineModeReason = offlineMode.reason;
        offlineModePriority = offlineMode.priority;

        debugPrint(
          '🔒 Offline mode determined by ${offlineMode.priority}: ${offlineMode.reason}',
        );
        return;
      }

      // Fallback: Network connectivity check
      isOfflineMode = !(await _hasInternetConnectivity());
      offlineModeReason = isOfflineMode ? 'No internet' : 'Online';
      offlineModePriority = OfflineModePriority.networkCheck;

      debugPrint(
        '🌐 Network-based offline mode: $isOfflineMode ($offlineModeReason)',
      );
    } catch (e) {
      // Default to offline mode on error
      isOfflineMode = true;
      offlineModeReason = 'Error detection';
      offlineModePriority = OfflineModePriority.networkCheck;
      debugPrint('❌ Error determining offline mode, defaulting to offline: $e');
    }

    if (isOfflineMode) {
      debugPrint('📱 Running in offline mode - Reason: $offlineModeReason');

      // Ensure tiles are available for offline use
      await _ensureOfflineTilesAvailable();
      await _enableOfflineModeForPicker(force: true);
    } else {
      await _disableOfflineModeForPicker();
    }
  }

  void _syncOfflineStateFromServices() {
    if (_offlineMapService != null) {
      final tileCount = _offlineMapService!.downloadedTileCount.value;
      if (_offlineMapService!.isOfflineReady.value ||
          tileCount >= _offlineTileThreshold) {
        isOfflineMode = true;
        offlineModeReason = 'Offline tiles ready';
        offlineModePriority = OfflineModePriority.tilesAvailable;
      }
    } else if (_backgroundTileService != null &&
        _backgroundTileService!.totalTilesDownloaded.value >=
            _legacyTileThreshold) {
      isOfflineMode = true;
      offlineModeReason = 'Cached tiles available';
      offlineModePriority = OfflineModePriority.tilesAvailable;
    }

    _markOfflineServiceReadyIfNeeded();
    _updateOfflineAvailability();
  }

  int _getOfflineTileCount() {
    final offlineServiceCount =
        _offlineMapService?.downloadedTileCount.value ?? 0;
    if (offlineServiceCount > 0) {
      return offlineServiceCount;
    }
    return _backgroundTileService?.totalTilesDownloaded.value ?? 0;
  }

  bool _hasSufficientOfflineTiles() {
    final offlineServiceCount =
        _offlineMapService?.downloadedTileCount.value ?? 0;
    if ((_offlineMapService?.isOfflineReady.value ?? false) ||
        offlineServiceCount >= _offlineTileThreshold) {
      return true;
    }

    final legacyCount = _backgroundTileService?.totalTilesDownloaded.value ?? 0;
    return legacyCount >= _legacyTileThreshold;
  }

  void _updateOfflineAvailability() {
    final hasTiles = _hasSufficientOfflineTiles();
    final tileCount = _getOfflineTileCount();
    if (hasTiles) {
      _markOfflineServiceReadyIfNeeded();
      final reason =
          tileCount > 0
              ? 'Offline tiles ready ($tileCount cached)'
              : 'Offline tiles ready';

      final shouldUpdateReason =
          offlineModeReason != reason ||
          offlineModePriority != OfflineModePriority.tilesAvailable;

      if (!isOfflineMode || shouldUpdateReason) {
        setState(() {
          isOfflineMode = true;
          offlineModeReason = reason;
          offlineModePriority = OfflineModePriority.tilesAvailable;
          showInternetScreen = false;
        });
      }

      _enableOfflineModeForPicker(force: true);
      if (mapController != null) {
        _configureOfflineMap(mapController!);
      }
    }
  }

  void _markOfflineServiceReadyIfNeeded() {
    if (_offlineMapService == null) return;

    final offlineService = _offlineMapService!;
    final serviceCount = offlineService.downloadedTileCount.value;
    final legacyCount = _backgroundTileService?.totalTilesDownloaded.value ?? 0;

    if (!offlineService.isOfflineReady.value &&
        (serviceCount >= _offlineTileThreshold ||
            legacyCount >= _legacyTileThreshold)) {
      offlineService.isOfflineReady.value = true;
    }
  }

  Future<void> _enableOfflineModeForPicker({bool force = false}) async {
    if (_offlineMapService == null || _offlineModeEnabledByPicker) {
      return;
    }

    _markOfflineServiceReadyIfNeeded();

    if (!force &&
        offlineModePriority != OfflineModePriority.userForced &&
        offlineModePriority != OfflineModePriority.forceOffline) {
      try {
        final hasInternet = await _hasInternetConnectivity();
        if (hasInternet) {
          return;
        }
      } catch (e) {
        debugPrint(
          'LocationPickerWidget: Internet check failed before enabling offline mode: $e',
        );
      }
    }

    try {
      await _offlineMapService!.enableOfflineMode();
      _offlineModeEnabledByPicker = true;
      debugPrint('LocationPickerWidget: Offline mode enabled for picker');
    } catch (e) {
      debugPrint('LocationPickerWidget: Error enabling offline mode: $e');
    }
  }

  Future<void> _disableOfflineModeForPicker({bool force = false}) async {
    if (_offlineMapService == null || !_offlineModeEnabledByPicker) {
      return;
    }

    if (!force) {
      try {
        final hasInternet = await _hasInternetConnectivity();
        if (!hasInternet) {
          return;
        }
      } catch (e) {
        debugPrint(
          'LocationPickerWidget: Internet check failed before disabling offline mode: $e',
        );
        return;
      }
    }

    try {
      await _offlineMapService!.disableOfflineMode();
      _offlineModeEnabledByPicker = false;
      debugPrint('LocationPickerWidget: Offline mode disabled for picker');
    } catch (e) {
      debugPrint('LocationPickerWidget: Error disabling offline mode: $e');
    }
  }

  /// Check internet connectivity
  Future<bool> _hasInternetConnectivity() async {
    try {
      final result = await InternetAddress.lookup('mapbox.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      debugPrint('🌐 No internet connectivity: $e');
      return false;
    }
  }

  /// Ensure offline tiles are available
  Future<void> _ensureOfflineTilesAvailable() async {
    try {
      final tileManager = GlobalTileManager.instance;
      final tilesAvailable = await tileManager.areTilesAvailable(0, 0, 6);

      if (!tilesAvailable) {
        debugPrint(
          '⚠️ No offline tiles available - location picker may have limited functionality',
        );
        // Could show a dialog here to offer tile download
      } else {
        debugPrint('✅ Offline tiles are available');
      }
    } catch (e) {
      debugPrint('❌ Error checking offline tiles: $e');
    }
  }

  Future<void> _moveToCurrentLocation() async {
    debugPrint('🎯 Moving to current location...');

    if (!_validateMapState()) {
      debugPrint('❌ Map state validation failed');
      return;
    }

    try {
      // Check if we have location permission first
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        // Show message that user needs to grant permission or manually select location
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'dialog_content_location_permission_needed_to_get_current'.tr,
              ),
              backgroundColor: Colors.orange,
        duration: const Duration(seconds: 2),
              action: SnackBarAction(
                label: 'title_text_grant_permission'.tr,
                textColor: Colors.white,
                onPressed: () async {
                  final newPermission = await Geolocator.requestPermission();
                  if (newPermission == LocationPermission.whileInUse ||
                      newPermission == LocationPermission.always) {
                    hasLocationPermission = true;
                    _moveToCurrentLocation(); // Retry after permission granted
                  }
                },
              ),
            ),
          );
        }
        return;
      }

      debugPrint('📍 Getting current position...');

      // Get fresh current location
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      debugPrint(
        '✅ Got current position: ${position.latitude}, ${position.longitude}',
      );

      // Try to get location details for the current position
      debugPrint('🔍 Getting location details for current position...');

      selectedLocationData = {
        'latitude': position.latitude,
        'longitude': position.longitude,
      };
      debugPrint(
        '✅ Reverse geocoding successful for current location: ${selectedLocationData.toString()}',
      );

      // Update current position
      setState(() {
        currentPosition = position;
      });

      // Move camera to current location with smooth animation
      debugPrint('🎥 Moving camera to current location...');
      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(position.longitude, position.latitude),
          ),
          zoom: 2.0, // Good zoom level for current location
        ),
        mapbox.MapAnimationOptions(duration: 1500),
      );

      // Ensure annotation manager is available
      await _ensureAnnotationManager();

      // Clear any existing location marker and create new one at current location
      await _clearAllMarkers();
      await _createLocationMarker(
        position.latitude,
        position.longitude,
        'current location',
      );

      // Update the memory controller with the current location
      memoryController.setLocation(
        '${position.latitude},${position.longitude}',
      );

      debugPrint(
        '✅ Successfully moved camera and marker to current location: ${position.latitude}, ${position.longitude}',
      );

      // Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('dialog_content_moved_to_current_location'.tr),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error getting current location: $e');
      debugPrint('   Error type: ${e.runtimeType}');

      // Show a snackbar to inform user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('dialog_content_unable_to_get_your_current_location_pleas'.tr),
            backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Ensure annotation manager is available and properly initialized
  Future<void> _ensureAnnotationManager() async {
    try {
      if (mapController == null) {
        debugPrint(
          '❌ Cannot create annotation manager - map controller is null',
        );
        return;
      }

      // Only create if it doesn't exist - NEVER recreate an existing one
      if (annotationManager == null) {
        debugPrint('🔄 Creating new annotation manager (first time only)...');

        // Wait a moment to ensure map is ready
        await Future.delayed(Duration(milliseconds: 50));

        annotationManager =
            await mapController!.annotations.createPointAnnotationManager();
        debugPrint(
          '✅ Created new annotation manager with ID: ${annotationManager!.id}',
        );
      } else {
        debugPrint(
          '✅ Annotation manager already exists with ID: ${annotationManager!.id}',
        );
      }
    } catch (e) {
      debugPrint('❌ Error ensuring annotation manager: $e');

      // Only try to recreate if we don't have one
      if (annotationManager == null) {
        try {
          await Future.delayed(Duration(milliseconds: 200));
          if (mapController != null) {
            debugPrint(
              '🔄 Attempting to create annotation manager after error...',
            );
            annotationManager =
                await mapController!.annotations.createPointAnnotationManager();
            debugPrint(
              '✅ Successfully created annotation manager with ID: ${annotationManager!.id}',
            );
          }
        } catch (recreateError) {
          debugPrint('❌ Failed to create annotation manager: $recreateError');
        }
      }
    }
  }

  /// Reinitialize annotation manager (useful after dialog interactions)
  Future<void> _reinitializeAnnotationManager() async {
    try {
      debugPrint('🔄 Reinitializing annotation manager...');

      // Clear existing manager
      annotationManager = null;
      currentLocationMarker = null;

      // Create new manager
      await _ensureAnnotationManager();

      debugPrint('✅ Annotation manager reinitialized');
    } catch (e) {
      debugPrint('❌ Error reinitializing annotation manager: $e');
    }
  }

  /// Clear existing location marker safely with forced map refresh
  Future<void> _clearAllMarkers() async {
    try {
      debugPrint('🗑️ Starting aggressive marker clearing...');

      // Step 1: Clear individual tracked markers
      if (activeMarkers.isNotEmpty) {
        debugPrint('🗑️ Clearing ${activeMarkers.length} tracked markers...');
        for (final marker in List.from(activeMarkers)) {
          try {
            if (annotationManager != null && marker != null) {
              await annotationManager!.delete(marker);
            }
          } catch (e) {
            debugPrint('⚠️ Error deleting individual marker: $e');
          }
        }
        activeMarkers.clear();
      }

      // Step 2: Clear all annotations from manager
      if (annotationManager != null) {
        try {
          await annotationManager!.deleteAll();
          debugPrint('🗑️ Called deleteAll() on annotation manager');
        } catch (e) {
          debugPrint('⚠️ Error calling deleteAll(): $e');
        }
      }

      // Step 3: Remove marker images from map style
      if (mapController != null) {
        try {
          await mapController!.style.removeStyleImage(
            'current_location_marker',
          );
          debugPrint('🗑️ Removed marker image from map style');
        } catch (e) {
          debugPrint('⚠️ Error removing marker image: $e');
        }
      }

      // Step 4: Completely reset annotation manager
      annotationManager = null;
      currentLocationMarker = null;

      // Step 5: Force map refresh by triggering a small camera movement
      if (mapController != null) {
        try {
          final currentCamera = await mapController!.getCameraState();
          await mapController!.setCamera(
            mapbox.CameraOptions(
              center: currentCamera.center,
              zoom: currentCamera.zoom,
              bearing: currentCamera.bearing,
              pitch: currentCamera.pitch,
            ),
          );
          debugPrint('🔄 Forced map refresh with camera update');
        } catch (e) {
          debugPrint('⚠️ Error forcing map refresh: $e');
        }
      }

      // Step 6: Wait a moment for map to process changes
      await Future.delayed(Duration(milliseconds: 100));

      // Step 7: Recreate annotation manager
      await _ensureAnnotationManager();

      debugPrint('✅ Aggressive marker clearing completed');
    } catch (e) {
      debugPrint('❌ Error in aggressive marker clearing: $e');

      // Nuclear option: reset everything
      try {
        annotationManager = null;
        currentLocationMarker = null;
        activeMarkers.clear();

        if (mapController != null) {
          // Try to remove any lingering style images
          try {
            await mapController!.style.removeStyleImage(
              'current_location_marker',
            );
          } catch (_) {}

          // Force a style reload
          try {
            await mapController!.loadStyleURI(_getOptimalStyleUri());
            debugPrint('🔄 Reloaded map style as nuclear option');
          } catch (_) {}
        }

        await _ensureAnnotationManager();
        debugPrint('☢️ Nuclear reset completed');
      } catch (nuclearError) {
        debugPrint('❌ Nuclear reset failed: $nuclearError');
      }
    }
  }

  /// Ensure the marker image is loaded into the map style
  Future<void> _ensureMarkerImageLoaded() async {
    if (mapController == null) return;

    const imageName = 'current_location_marker';

    try {
      // Check if image already exists by trying to remove it first
      // If it doesn't exist, this will throw an exception which we can ignore
      try {
        await mapController!.style.removeStyleImage(imageName);
        debugPrint('🔄 Removed existing marker image to refresh it');
      } catch (e) {
        // Image doesn't exist yet, which is fine
        debugPrint('📍 Marker image doesn\'t exist yet, will create new one');
      }

      // Create and add the marker image
      final imageBytes = await _createRedMarkerImage();
      await mapController!.style.addStyleImage(
        imageName,
        1.0,
        mapbox.MbxImage(data: imageBytes, width: 100, height: 100),
        false,
        [],
        [],
        null,
      );

      debugPrint('✅ Marker image loaded into map style: $imageName');
    } catch (e) {
      debugPrint('❌ Error loading marker image: $e');
    }
  }

  List<mapbox.PointAnnotation> activeMarkers = [];

  Future<void> _createLocationMarker(
    double latitude,
    double longitude,
    String description,
  ) async {
    debugPrint('[_createLocationMarker] === START CREATING MARKER ===');
    debugPrint('[_createLocationMarker] Description: $description');
    debugPrint('[_createLocationMarker] Coordinates: $latitude, $longitude');

    try {
      // Ensure we have a SINGLE, persistent annotation manager
      debugPrint('[_createLocationMarker] Checking annotation manager...');
      if (annotationManager == null) {
        debugPrint(
          '[_createLocationMarker] Creating new annotation manager (first time only)...',
        );
        annotationManager =
            await mapController!.annotations.createPointAnnotationManager();
        debugPrint(
          '[_createLocationMarker] ✅ Created new annotation manager with ID: ${annotationManager!.id}',
        );
      } else {
        debugPrint(
          '[_createLocationMarker] ✅ Using existing annotation manager with ID: ${annotationManager!.id}',
        );
      }

      debugPrint(
        '[_createLocationMarker] Current activeMarkers count before creation: ${activeMarkers.length}',
      );
      for (int i = 0; i < activeMarkers.length; i++) {
        debugPrint(
          '[_createLocationMarker] Existing marker $i: ${activeMarkers[i].id}',
        );
      }

      debugPrint('[_createLocationMarker] Ensuring marker image is loaded...');
      await _ensureMarkerImageLoaded();

      final isDarkMode = uiController.darkMode.value;
      final markerColorInt = isDarkMode ? 0xFFFF6B6B : 0xFFFF4444;
      debugPrint(
        '[_createLocationMarker] Dark mode: $isDarkMode, Color: ${markerColorInt.toRadixString(16)}',
      );

      debugPrint('[_createLocationMarker] Creating marker options...');
      final markerOptions = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(longitude, latitude),
        ),
        iconImage: 'current_location_marker',
        iconSize: isDarkMode ? 0.6 : 0.5,
        iconColor: markerColorInt,
      );

      // Use create() instead of createMulti() for single annotation
      debugPrint(
        '[_createLocationMarker] Calling create() with single marker...',
      );
      final createdMarker = await annotationManager!.create(markerOptions);
      debugPrint(
        '[_createLocationMarker] create() returned marker with ID: ${createdMarker.id}',
      );

      debugPrint(
        '[_createLocationMarker] ✅ Successfully created marker with ID: ${createdMarker.id}',
      );

      currentLocationMarker = createdMarker;
      activeMarkers.add(createdMarker);
      debugPrint('[_createLocationMarker] Added marker to activeMarkers list');
      debugPrint(
        '[_createLocationMarker] Updated currentLocationMarker reference',
      );
      debugPrint(
        '[_createLocationMarker] Total activeMarkers count after creation: ${activeMarkers.length}',
      );

      debugPrint('[_createLocationMarker] === END CREATING MARKER ===');
    } catch (e) {
      debugPrint(
        '[_createLocationMarker] ❌ Error creating $description marker: $e',
      );
      debugPrint('[_createLocationMarker] Error type: ${e.runtimeType}');
      debugPrint('[_createLocationMarker] === END CREATING MARKER (ERROR) ===');
    }
  }

  // /// Validate map state and components
  bool _validateMapState() {
    if (mapController == null) {
      debugPrint('❌ Map controller is null');
      return false;
    }

    if (!mounted) {
      debugPrint('❌ Widget is not mounted');
      return false;
    }

    debugPrint('✅ Map state is valid');
    return true;
  }

  void _showLocationSearch() async {
    debugPrint('🔍 Opening location search dialog...');

    // Load saved locations only when the popup is opened
    await _loadSavedLocations();

    // Check if widget is still mounted before showing dialog
    if (!mounted) {
      debugPrint('❌ Widget not mounted, cannot show location search dialog');
      return;
    }

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder:
            (context) => LocationSearchDialog(
              savedLocations: savedLocations,
              isOfflineMode: isOfflineMode,
              onLocationSelected: _moveToSearchedLocation,
              onLocationSaved: _refreshSavedLocations,
            ),
      );

      debugPrint('🔍 Location search dialog closed with result: $result');

      // Reinitialize annotation manager after dialog is closed
      // This helps prevent issues with the current location button
      debugPrint(
        '🔄 Search dialog closed, reinitializing annotation manager...',
      );
      await _reinitializeAnnotationManager();

      debugPrint('✅ Location search dialog handling completed');
    } catch (e) {
      debugPrint('❌ Error handling location search dialog: $e');
    }
  }

  Future<void> _moveToSearchedLocation(Map<String, dynamic> location) async {
    debugPrint('🔍 === MOVE TO SEARCHED LOCATION START ===');
    debugPrint('🔍 Location: $location');

    if (mapController == null) {
      debugPrint('❌ Map controller is null, cannot move to searched location');
      return;
    }

    final lat = location['latitude'] as double;
    final lng = location['longitude'] as double;

    try {
      debugPrint('📍 Moving to searched location: $lat, $lng');

      // STEP 1: Clear existing markers FIRST
      debugPrint('🔄 STEP 1: Clearing existing markers...');
      await _clearLocationPickerMarkersOnly();

      // STEP 2: Update current position
      debugPrint('🔄 STEP 2: Updating current position...');
      currentPosition = Position(
        latitude: lat.toDouble(),
        longitude: lng.toDouble(),
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      // STEP 3: Move camera
      debugPrint('🔄 STEP 3: Moving camera...');
      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
          zoom: 2.0,
        ),
        mapbox.MapAnimationOptions(duration: 1500),
      );

      // STEP 4: Ensure annotation manager
      debugPrint('🔄 STEP 4: Ensuring annotation manager...');
      await _ensureAnnotationManager();

      // STEP 5: Create new marker
      debugPrint('🔄 STEP 5: Creating new marker...');
      await _createLocationMarker(lat, lng, 'searched location');

      // STEP 6: Update controller
      debugPrint('🔄 STEP 6: Updating memory controller...');
      selectedLocationData = null;
      memoryController.setLocation('$lat,$lng');

      // STEP 7: Save to databases
      debugPrint('🔄 STEP 7: Saving to databases...');
      await _addLocationToOfflineDatabase(location);
      await _saveSelectedLocationToCache(location);

      debugPrint('✅ Successfully moved to searched location: $lat, $lng');
      debugPrint('🔍 === MOVE TO SEARCHED LOCATION END ===');

      // Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              trKey('dialog_content_moved_to_location', [
                location['name'] ??
                    location['city'] ??
                    'l10n_selected_location'.tr,
              ]),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error moving to searched location: $e');
      debugPrint('🔍 === MOVE TO SEARCHED LOCATION ERROR END ===');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('dialog_content_unable_to_move_to_the_selected_location_p'.tr),
            backgroundColor: Colors.red,
        duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Clear only location picker markers, not memory markers from map controller
  Future<void> _clearLocationPickerMarkersOnly() async {
    try {
      debugPrint('🗑️ === CLEARING LOCATION PICKER MARKERS ===');
      debugPrint('🗑️ Current activeMarkers count: ${activeMarkers.length}');
      debugPrint(
        '🗑️ Current annotationManager: ${annotationManager != null ? 'exists' : 'null'}',
      );
      debugPrint(
        '🗑️ Current currentLocationMarker: ${currentLocationMarker != null ? 'exists' : 'null'}',
      );

      // Clear only our tracked markers using the SAME annotation manager
      if (activeMarkers.isNotEmpty && annotationManager != null) {
        debugPrint(
          '🗑️ Attempting to clear ${activeMarkers.length} location picker markers...',
        );

        // Try to delete each marker individually
        final markersToDelete = List.from(activeMarkers);
        for (int i = 0; i < markersToDelete.length; i++) {
          final marker = markersToDelete[i];
          try {
            if (marker != null) {
              await annotationManager!.delete(marker);
              debugPrint('🗑️ Successfully deleted marker $i: ${marker.id}');
            }
          } catch (e) {
            debugPrint('⚠️ Error deleting location picker marker $i: $e');
          }
        }

        // Clear the list
        activeMarkers.clear();
        debugPrint(
          '🗑️ Cleared activeMarkers list, count now: ${activeMarkers.length}',
        );
      } else {
        debugPrint('🗑️ No markers to clear or annotation manager is null');
      }

      // Clear current location marker reference
      if (currentLocationMarker != null) {
        debugPrint('🗑️ Clearing currentLocationMarker reference');
        currentLocationMarker = null;
      }

      // Remove marker image from style
      if (mapController != null) {
        try {
          await mapController!.style.removeStyleImage(
            'current_location_marker',
          );
          debugPrint('🗑️ Removed location picker marker image from map style');
        } catch (e) {
          debugPrint(
            '⚠️ Error removing location picker marker image (might not exist): $e',
          );
        }
      }

      debugPrint('✅ Location picker markers clearing completed');
      debugPrint('🗑️ === END CLEARING LOCATION PICKER MARKERS ===');
    } catch (e) {
      debugPrint('❌ Error in _clearLocationPickerMarkersOnly: $e');
    }
  }

  /// Save selected location to cache/preferences for future use
  Future<void> _saveSelectedLocationToCache(
    Map<String, dynamic> location,
  ) async {
    try {
      // Load saved locations if not already loaded
      if (savedLocations.isEmpty) {
        await _loadSavedLocations();
      }

      final lat = location['latitude'] as double;
      final lng = location['longitude'] as double;

      // Create standardized location data
      final locationData = {
        'name':
            location['name'] ?? location['displayName'] ?? 'Unknown Location',
        'address': location['address'] ?? location['shortDisplayName'] ?? '',
        'latitude': lat,
        'longitude': lng,
        'country': location['country'] ?? '',
        'region': location['region'] ?? location['state'] ?? '',
        'city': location['city'] ?? '',
        'postcode': location['postcode'] ?? '',
        'timestamp': DateTime.now().toIso8601String(),
        'type': location['type'] ?? 'city',
        'source': location['source'] ?? 'search_selection',
      };

      // Check if location already exists in saved locations
      final exists = savedLocations.any(
        (savedLocation) =>
            (savedLocation['latitude'] - lat).abs() < 0.001 &&
            (savedLocation['longitude'] - lng).abs() < 0.001,
      );

      if (!exists) {
        // Add to the beginning of the list (most recent first)
        savedLocations.insert(0, locationData);

        // Limit the number of saved locations to prevent unlimited growth
        const maxSavedLocations = 100;
        if (savedLocations.length > maxSavedLocations) {
          savedLocations = savedLocations.take(maxSavedLocations).toList();
        }

        // Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_locations', json.encode(savedLocations));

        debugPrint(
          '💾 Saved selected location to cache: ${locationData['name']}',
        );
        debugPrint('   Total saved locations: ${savedLocations.length}');
      } else {
        // Move existing location to the front (update timestamp)
        final existingIndex = savedLocations.indexWhere(
          (savedLocation) =>
              (savedLocation['latitude'] - lat).abs() < 0.001 &&
              (savedLocation['longitude'] - lng).abs() < 0.001,
        );

        if (existingIndex != -1) {
          final existingLocation = savedLocations.removeAt(existingIndex);
          existingLocation['timestamp'] = DateTime.now().toIso8601String();
          savedLocations.insert(0, existingLocation);

          // Save updated order to SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_locations', json.encode(savedLocations));

          debugPrint(
            '💾 Updated existing location timestamp and moved to top: ${existingLocation['name']}',
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error saving selected location to cache: $e');
    }
  }

  /// Refresh saved locations from cache
  Future<void> _refreshSavedLocations() async {
    await _loadSavedLocations();
    setState(() {
      // Trigger UI refresh
    });
  }

  /// Add selected location to offline database for future searches
  Future<void> _addLocationToOfflineDatabase(
    Map<String, dynamic> location,
  ) async {
    try {
      final offlineSearchService =
          offline.OfflineLocationSearchService.instance;

      // Print all location data
      print('🔍 === LOCATION DATA DEBUG ===');
      print('📍 Raw location data: $location');
      print('📍 location[\'city\']: ${location['city']}');
      print('📍 location[\'name\']: ${location['name']}');
      print('📍 location[\'country\']: ${location['country']}');
      print('📍 location[\'region\']: ${location['region']}');
      print('📍 location[\'address\']: ${location['address']}');
      print('📍 location[\'latitude\']: ${location['latitude']}');
      print('📍 location[\'longitude\']: ${location['longitude']}');
      print('📍 location[\'type\']: ${location['type']}');
      print('🔍 === END LOCATION DATA DEBUG ===');

      final locationResult = offline.LocationSearchResult(
        name: location['city'] ?? location['name'] ?? 'Unknown',
        displayName:
            location['name'] ?? '${location['city']}, ${location['country']}',
        shortDisplayName:
            location['address'] ??
            '${location['city']}, ${location['country']}',
        latitude: location['latitude'] as double,
        longitude: location['longitude'] as double,
        country: location['country'] ?? '',
        state: location['region'],
        city: location['city'] ?? '',
        type: _parseLocationType(location['type']),
        population: null,
      );

      print('🔍 === LOCATION RESULT DEBUG ===');
      print('📍 LocationResult name: ${locationResult.name}');
      print('📍 LocationResult displayName: ${locationResult.displayName}');
      print(
        '📍 LocationResult shortDisplayName: ${locationResult.shortDisplayName}',
      );
      print('📍 LocationResult country: ${locationResult.country}');
      print('📍 LocationResult state: ${locationResult.state}');
      print('📍 LocationResult city: ${locationResult.city}');
      print(
        '📍 LocationResult coordinates: ${locationResult.latitude}, ${locationResult.longitude}',
      );
      print('📍 LocationResult type: ${locationResult.type}');
      print('🔍 === END LOCATION RESULT DEBUG ===');

      await offlineSearchService.addLocation(locationResult);
      debugPrint(
        '📍 Added location to offline database: ${locationResult.displayName}',
      );
    } catch (e) {
      debugPrint('❌ Error adding location to offline database: $e');
    }
  }

  /// Parse location type from string
  offline.LocationType _parseLocationType(String? typeString) {
    if (typeString == null) return offline.LocationType.city;

    try {
      return offline.LocationType.values.firstWhere(
        (type) => type.toString().split('.').last == typeString.split('.').last,
        orElse: () => offline.LocationType.city,
      );
    } catch (e) {
      return offline.LocationType.city;
    }
  }

  Future<void> _getCurrentLocation() async {
    // Location permission is optional - silently try to get location but don't block the UI
    if (hasAskedLocationPermissionOnce) {
      setState(() => isLoading = false);
      return;
    }

    hasAskedLocationPermissionOnce = true;

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint(
          '📍 Location services disabled - user can manually select location',
        );
        setState(() => isLoading = false);
        return;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();

      // If permission is denied, silently continue without requesting
      // Users can manually select location on the map
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint(
          '📍 Location permission not granted - user can manually select location',
        );
        hasLocationPermission = false;
        setState(() => isLoading = false);
        return;
      }

      // If we have permission, try to get current location
      hasLocationPermission = true;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5), // Add timeout to prevent hanging
        ),
      );

      setState(() {
        currentPosition = position;
        isLoading = false;
      });

      // If map is already created, add marker
      if (mapController != null) {
        await _addCurrentLocationMarker();
      }

      debugPrint(
        '✅ Got current location: ${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      debugPrint(
        '📍 Could not get current location: $e - user can manually select location',
      );
      setState(() => isLoading = false);
    }
  }

  Future<void> _addCurrentLocationMarker() async {
    if (mapController == null || currentPosition == null) return;

    try {
      // Create red marker image
      final imageBytes = await _createRedMarkerImage();
      const imageName = 'current_location_marker';

      await mapController!.style.addStyleImage(
        imageName,
        1.0,
        mapbox.MbxImage(
          data: imageBytes,
          width: 100,
          height: 100,
        ), // Updated dimensions
        false,
        [],
        [],
        null,
      );

      debugPrint('✅ Added marker image to map style: $imageName');

      // Create point annotation manager
      annotationManager =
          await mapController!.annotations.createPointAnnotationManager();

      // Create marker at current location
      final markerOptions = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(
            currentPosition!.longitude,
            currentPosition!.latitude,
          ),
        ),
        iconImage: imageName,
        iconSize: 0.5, // Reduced from 1.0 to compensate for larger image
      );

      final markers = await annotationManager!.createMulti([markerOptions]);
      if (markers.isNotEmpty && markers.first != null) {
        currentLocationMarker = markers.first!;
      }

      // Map tap listener is handled by the MapWidget's onTapListener property

      // Move camera to current location with better zoom level
      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              currentPosition!.longitude,
              currentPosition!.latitude,
            ),
          ),
          zoom: 1.0,
        ),
        mapbox.MapAnimationOptions(duration: 1000),
      );
    } catch (e) {
      debugPrint('Error adding marker: $e');
    }
  }

  void _onMapTap(mapbox.MapContentGestureContext context) async {
    if (mapController == null || annotationManager == null) return;

    try {
      // Get the point from the gesture context
      final point = context.point;

      // Ensure the marker image is loaded
      await _ensureMarkerImageLoaded();

      // Delete existing marker
      if (currentLocationMarker != null) {
        await annotationManager!.delete(currentLocationMarker!);
      }

      // Create new marker at tapped location
      final markerOptions = mapbox.PointAnnotationOptions(
        geometry: point,
        iconImage: 'current_location_marker',
        iconSize: 0.5, // Changed from 1.0 to match initial marker size
      );

      final markers = await annotationManager!.createMulti([markerOptions]);
      if (markers.isNotEmpty && markers.first != null) {
        currentLocationMarker = markers.first!;
      }

      // Update current position for the Done button
      currentPosition = Position(
        latitude: point.coordinates.lat.toDouble(),
        longitude: point.coordinates.lng.toDouble(),
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      selectedLocationData = {
        'latitude': point.coordinates.lat.toDouble(),
        'longitude': point.coordinates.lng.toDouble(),
      };
      debugPrint(
        '✅ ${isOfflineMode ? 'Offline' : 'Online'} geocoding successful: ${selectedLocationData!['name']}',
      );

      // Update the memory controller with the tapped location
      memoryController.setLocation(
        '${point.coordinates.lat},${point.coordinates.lng}',
      );

      // Get current zoom level and maintain it
      final currentCamera = await mapController!.getCameraState();
      await mapController!.flyTo(
        mapbox.CameraOptions(center: point, zoom: currentCamera.zoom),
        mapbox.MapAnimationOptions(duration: 500),
      );

      debugPrint(
        'Map tapped at: ${point.coordinates.lat}, ${point.coordinates.lng}',
      );
    } catch (e) {
      debugPrint('Error handling map tap: $e');
    }
  }

  Future<Uint8List> _createRedMarkerImage() async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    // Increase size for better resolution
    const size = 100.0; // Doubled from 50.0
    const center = Offset(size / 2, size / 2);
    const outerRadius = size / 3;
    const innerRadius = size / 4;

    // Draw outer red circle with better alpha
    final outerPaint =
        Paint()
          ..color = Colors.red.withValues(alpha: 0.4) // Better opacity
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius, outerPaint);

    // Draw inner red circle with solid color
    final innerPaint =
        Paint()
          ..color =
              Colors
                  .red // Use Colors.red instead of hex
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius, innerPaint);

    // Draw white border with better stroke width
    final borderPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;
    canvas.drawCircle(center, innerRadius, borderPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  void _onDonePressed() async {
    if (currentPosition == null) return;

    // Show loading indicator
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    try {
      // Prepare initial location data with coordinates
      final locationData = <String, dynamic>{
        'latitude': currentPosition!.latitude,
        'longitude': currentPosition!.longitude,
        'locationString':
            '${currentPosition!.latitude.toStringAsFixed(6)}, ${currentPosition!.longitude.toStringAsFixed(6)}',
      };

      // Perform reverse geocoding to get location details
      final reverseGeocodedData = await _getLocationDetailsFromCoordinates(
        currentPosition!.latitude,
        currentPosition!.longitude,
      );

      if (reverseGeocodedData != null) {
        // Store the reverse geocoded data
        selectedLocationData = {
          'latitude': currentPosition!.latitude,
          'longitude': currentPosition!.longitude,
          'country': reverseGeocodedData['country'],
          'city': reverseGeocodedData['city'],
          'name': reverseGeocodedData['name'],
          'address': reverseGeocodedData['address'],
          'flag': _getCountryFlag(reverseGeocodedData['country']),
        };

        // Add the reverse geocoded data to location data
        locationData.addAll({
          'country': reverseGeocodedData['country'],
          'city': reverseGeocodedData['city'],
          'name': reverseGeocodedData['name'],
          'address': reverseGeocodedData['address'],
          'flag': _getCountryFlag(reverseGeocodedData['country']),
        });
      } else {
        // Fallback if reverse geocoding fails
        locationData.addAll({
          'country': 'Unknown',
          'city': 'Unknown',
          'name': 'Unknown Location',
          'address': 'Unknown Address',
          'flag': '🌍',
        });
      }

      // Set the location coordinates in the memory controller (always lat,lng format)
      if (locationData.containsKey('latitude') &&
          locationData.containsKey('longitude')) {
        memoryController.setLocation(
          '${locationData['latitude']},${locationData['longitude']}',
        );
      }

      // Close loading dialog
      Get.back();

      // Pass the enhanced location data back to the previous screen
      debugPrint('🔍 === FINAL LOCATION DATA BEING PASSED BACK ===');
      debugPrint('📍 Complete locationData: $locationData');
      debugPrint('📍 locationData[\'country\']: ${locationData['country']}');
      debugPrint('📍 locationData[\'city\']: ${locationData['city']}');
      debugPrint('📍 locationData[\'name\']: ${locationData['name']}');
      debugPrint('📍 locationData[\'address\']: ${locationData['address']}');
      debugPrint('📍 locationData[\'flag\']: ${locationData['flag']}');
      debugPrint('📍 locationData[\'latitude\']: ${locationData['latitude']}');
      debugPrint(
        '📍 locationData[\'longitude\']: ${locationData['longitude']}',
      );
      debugPrint('🔍 === END FINAL LOCATION DATA ===');

      debugPrint('📍 Passing location data back: ${locationData.toString()}');

      // Navigate back with the location data
      Get.back(result: locationData);
    } catch (e) {
      // Close loading dialog on error
      Get.back();

      debugPrint('❌ Error in _onDonePressed: $e');

      // Show error message
      showTrSnackbar('snackbar_unable_to_get_location', 
        backgroundColor: Colors.red,
        colorText: Colors.white,        duration: const Duration(seconds: 2),);
    }
  }

  /// Get country flag emoji based on country name
  String _getCountryFlag(String? countryName) {
    if (countryName == null || countryName.isEmpty) return '🌍';

    final country = countryName.toLowerCase().trim();

    // Comprehensive country to flag emoji mapping
    final countryFlags = {
      // Major countries
      'united states': '🇺🇸', 'usa': '🇺🇸', 'us': '🇺🇸', 'america': '🇺🇸',
      'united kingdom': '🇬🇧', 'uk': '🇬🇧', 'britain': '🇬🇧',
      'canada': '🇨🇦', 'australia': '🇦🇺', 'new zealand': '🇳🇿',
      'germany': '🇩🇪', 'france': '🇫🇷', 'italy': '🇮🇹', 'spain': '🇪🇸',
      'portugal': '🇵🇹', 'netherlands': '🇳🇱', 'belgium': '🇧🇪',
      'switzerland': '🇨🇭', 'austria': '🇦🇹', 'sweden': '🇸🇪',
      'norway': '🇳🇴', 'denmark': '🇩🇰', 'finland': '🇫🇮',
      'iceland': '🇮🇸', 'ireland': '🇮🇪', 'poland': '🇵🇱',
      'czech republic': '🇨🇿', 'slovakia': '🇸🇰', 'hungary': '🇭🇺',
      'romania': '🇷🇴', 'bulgaria': '🇧🇬', 'greece': '🇬🇷',
      'turkey': '🇹🇷', 'russia': '🇷🇺', 'ukraine': '🇺🇦',

      // Asian countries
      'china': '🇨🇳', 'japan': '🇯🇵', 'south korea': '🇰🇷', 'korea': '🇰🇷',
      'india': '🇮🇳', 'pakistan': '🇵🇰', 'bangladesh': '🇧🇩',
      'thailand': '🇹🇭', 'vietnam': '🇻🇳', 'malaysia': '🇲🇾',
      'singapore': '🇸🇬', 'indonesia': '🇮🇩', 'philippines': '🇵🇭',
      'taiwan': '🇹🇼', 'hong kong': '🇭🇰', 'iran': '🇮🇷',
      'saudi arabia': '🇸🇦', 'uae': '🇦🇪', 'united arab emirates': '🇦🇪',

      // African countries
      'south africa': '🇿🇦', 'egypt': '🇪🇬', 'morocco': '🇲🇦',
      'nigeria': '🇳🇬', 'kenya': '🇰🇪', 'ethiopia': '🇪🇹',

      // South American countries
      'brazil': '🇧🇷', 'argentina': '🇦🇷', 'chile': '🇨🇱',
      'peru': '🇵🇪', 'colombia': '🇨🇴', 'venezuela': '🇻🇪',

      // Central American countries
      'mexico': '🇲🇽', 'guatemala': '🇬🇹', 'costa rica': '🇨🇷',
      'panama': '🇵🇦', 'cuba': '🇨🇺', 'jamaica': '🇯🇲',

      // European countries
      'albania': '🇦🇱', 'andorra': '🇦🇩', 'armenia': '🇦🇲',
      'azerbaijan': '🇦🇿', 'belarus': '🇧🇾', 'bosnia and herzegovina': '🇧🇦',
      'croatia': '🇭🇷', 'cyprus': '🇨🇾', 'estonia': '🇪🇪',
      'georgia': '🇬🇪', 'latvia': '🇱🇻', 'lithuania': '🇱🇹',
      'luxembourg': '🇱🇺', 'malta': '🇲🇹', 'moldova': '🇲🇩',
      'monaco': '🇲🇨', 'montenegro': '🇲🇪', 'north macedonia': '🇲🇰',
      'san marino': '🇸🇲', 'serbia': '🇷🇸', 'slovenia': '🇸🇮',
      'vatican city': '🇻🇦',
    };

    return countryFlags[country] ?? '🌍';
  }

  /// Get optimal style URI based on offline mode
  String _getOptimalStyleUri() {
    if (isOfflineMode) {
      // Use the same style but it will prioritize cached tiles
      debugPrint('🗺️ Using offline-optimized style URI');
      return mapbox.MapboxStyles.MAPBOX_STREETS;
    }
    return mapbox.MapboxStyles.MAPBOX_STREETS;
  }

  /// Configure map for offline use
  Future<void> _configureOfflineMap(mapbox.MapboxMap controller) async {
    try {
      if (isOfflineMode) {
        debugPrint('🔧 Configuring map for offline mode');

        // Map already uses MAPBOX_STREETS style which matches downloaded tiles
        // No need to change style URI - tiles will be used automatically

        debugPrint('✅ Map configured for offline mode - using downloaded tiles');
      } else {
        debugPrint('🌐 Map configured for online mode');
      }
    } catch (e) {
      debugPrint('❌ Error configuring offline map: $e');
    }
  }

  /// Build offline mode indicator widget
  Widget _buildOfflineModeIndicator() {
    return Positioned(
      top: 100,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _getOfflineModeColor().withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_getOfflineModeIcon(), size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'text_offline_mode_enabled'.tr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (offlineModePriority == OfflineModePriority.userForced)
              GestureDetector(
                onTap: _showOfflineSettingsDialog,
                child: const Icon(
                  Icons.settings,
                  size: 16,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Get offline mode indicator color based on priority
  Color _getOfflineModeColor() {
    switch (offlineModePriority) {
      case OfflineModePriority.userForced:
        return Colors.blue;
      case OfflineModePriority.forceOffline:
        return Colors.red;
      case OfflineModePriority.tilesAvailable:
        return Colors.green;
      case OfflineModePriority.networkCheck:
        return Colors.orange;
    }
  }

  /// Get offline mode indicator icon based on priority
  IconData _getOfflineModeIcon() {
    switch (offlineModePriority) {
      case OfflineModePriority.userForced:
        return Icons.settings;
      case OfflineModePriority.forceOffline:
        return Icons.storage;
      case OfflineModePriority.tilesAvailable:
        return Icons.offline_bolt;
      case OfflineModePriority.networkCheck:
        return Icons.wifi_off;
    }
  }

  /// Show offline settings dialog
  void _showOfflineSettingsDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('title_text_offline_mode'.tr),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trKey('text_offline_current_mode_reason', [offlineModeReason]),
                ),
                const SizedBox(height: 16),
                Text('text_available_offline_features'.tr),
                const SizedBox(height: 8),
                _buildFeatureList([
                  'text_offline_feature_cached_map_tiles'.tr,
                  'text_offline_feature_offline_location_search'.tr,
                  'text_offline_feature_saved_locations'.tr,
                  'text_offline_feature_no_realtime_updates'.tr,
                  'text_offline_feature_no_place_discovery'.tr,
                ]),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('text_got_it'.tr),
              ),
            ],
          ),
    );
  }

  /// Build feature list widget
  Widget _buildFeatureList(List<String> features) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          features
              .map(
                (feature) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(feature, style: const TextStyle(fontSize: 12)),
                ),
              )
              .toList(),
    );
  }

  /// Get location details from coordinates using isolate-based reverse geocoding
  Future<Map<String, dynamic>?> _getLocationDetailsFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      debugPrint(
        '🔍 Isolate-based reverse geocoding coordinates: $latitude, $longitude',
      );

      // Use GeocodingIsolateService for non-blocking reverse geocoding
      final geocodingService = GeocodingIsolateService.instance;

      // Ensure service is initialized
      final isReady = await geocodingService.ensureInitialized();
      debugPrint('🔍 GeocodingIsolateService ready: $isReady');

      debugPrint('🔍 === ISOLATE REVERSE GEOCODING DEBUG ===');
      debugPrint('📍 Input coordinates: $latitude, $longitude');

      final result = await geocodingService.reverseGeocode(latitude, longitude);

      debugPrint('📍 GeocodingIsolateService raw result: $result');

      if (result != null) {
        final country = result['country'] ?? '';
        final city = result['city'] ?? '';
        final address = result['address'] ?? '';
        final flag = _getCountryFlag(country);

        debugPrint('📍 Extracted country: "$country"');
        debugPrint('📍 Extracted city: "$city"');
        debugPrint('📍 Extracted address: "$address"');
        debugPrint('📍 Generated flag: "$flag"');

        final locationDetails = {
          'country': country,
          'city': city,
          'name': city.isNotEmpty ? '$city, $country' : country,
          'address': address,
          'flag': flag,
        };

        print('📍 Final locationDetails: $locationDetails');
        print('🔍 === END REVERSE GEOCODING DEBUG ===');

        debugPrint('✅ Reverse geocoding successful: $locationDetails');
        return locationDetails;
      } else {
        print('⚠️ OfflineGeocoder returned null result');
        print('🔍 === END REVERSE GEOCODING DEBUG ===');
        debugPrint('⚠️ No placemarks found for coordinates');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Reverse geocoding failed: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return LocationPickerSystemUiShell(
      child: Obx(
        () => Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
            // Map fills the whole screen, including under the status bar.
            mapbox.MapWidget(
              key: const ValueKey("mapbox_map_new"),
              cameraOptions:
                  (currentPosition != null)
                      ? mapbox.CameraOptions(
                        center: mapbox.Point(
                          coordinates: mapbox.Position(
                            currentPosition!.longitude,
                            currentPosition!.latitude,
                          ),
                        ),
                        zoom: 1.0,
                      )
                      : null,
              styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
              textureView: true,
              onMapCreated: (mapbox.MapboxMap controller) async {
                mapController = controller;
                await _configureOfflineMap(controller);
                await _addCurrentLocationMarker();
              },
              onMapLoadErrorListener: (mapLoadingErrorEventData) {
                _handleMapLoadError(mapLoadingErrorEventData.message);
              },
              onTapListener: _onMapTap,
            ),

            // Controls stay below the status bar; the map renders edge-to-edge.
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Stack(
                  children: [
            // Top right Done button
            if (!isLoading)
              Positioned(
                top: 50,
                right: 20,
                child: TextButton(
                  onPressed: _onDonePressed,

                  style: TextButton.styleFrom(
                    backgroundColor:
                        controller.primaryColor ??
                        (controller.darkMode.value
                            ? Colors.black.withValues(alpha: 0.6)
                            : AppColors.blue),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    'text_done_3'.tr,
                    style: TextStyle(
                      color:
                          controller.darkMode.value
                              ? Colors.white
                              : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

            // Current Location Button - only show if location permission is granted
            if (!isLoading && hasLocationPermission && currentPosition != null)
              Positioned(
                top: 50,
                left: 20,
                child: GestureDetector(
                  onTap: _moveToCurrentLocation,
                  child: Container(
                    padding: EdgeInsets.all(6),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage(AppImages.rectangle),
                        fit: BoxFit.cover,
                        colorFilter: controller.rectangleColorFilter,
                      ),
                    ),
                    child: Image.asset(
                      AppImages.location,
                      fit: BoxFit.contain,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            // Search Button
            if (!isLoading)
              Positioned(
                top: 50,
                left:
                    (!isLoading &&
                            hasLocationPermission &&
                            currentPosition != null)
                        ? 75
                        : 20,
                child: GestureDetector(
                  onTap: _showLocationSearch,
                  child: Container(
                    padding: EdgeInsets.all(6),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage(AppImages.rectangle),
                        fit: BoxFit.cover,
                        colorFilter: controller.rectangleColorFilter,
                      ),
                    ),
                    child: Image.asset(
                      AppImages.searchNormal,
                      fit: BoxFit.contain,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

            // Offline mode indicator
            if (isOfflineMode && !isLoading) _buildOfflineModeIndicator(),

            _buildPermissionAndInternetScreens(),

            // Error overlay
            // if (currentState  == LocationPickerState.error)
            // _buildErrorScreen(),
                  ],
                ),
              ),
            ),
            ],
            ),
          ),
        ),
      );
  }

  @override
  void dispose() {
    _permissionSubscription?.cancel();
    _offlineTileCountWorker?.dispose();
    _legacyTileCountWorker?.dispose();
    _offlineReadyWorker?.dispose();
    if (_offlineModeEnabledByPicker) {
      _disableOfflineModeForPicker();
    }
    super.dispose();
  }

  Widget _buildPermissionAndInternetScreens() {
    Widget? overlayContent;

    // Location permission is now optional - users can manually select location
    // Skip permission overlay and allow map usage without location access

    if (showInternetScreen ||
        currentState == LocationPickerState.internetRequired) {
      overlayContent = _buildInternetRequiredScreen();
    }

    final bool shouldShowLoadingOverlay =
        overlayContent == null &&
        (currentState == LocationPickerState.checkingInternet ||
            currentState == LocationPickerState.loadingMap ||
            isLoading);

    if (overlayContent == null && shouldShowLoadingOverlay) {
      overlayContent = _buildLoadingScreen();
    }

    if (overlayContent == null) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(color: Colors.transparent, dismissible: false),
          overlayContent,
        ],
      ),
    );
  }

  Widget _buildInternetRequiredScreen() {
    return InternetRequiredScreenLocationPicker(
      onRetryCallback: _retryAfterInternetRestore,
    );
  }

  /// Retry connection after internet is restored
  Future<void> _retryAfterInternetRestore() async {
    try {
      debugPrint('🔄 LocationPicker - Retrying after internet restore');

      // Immediately hide the internet screen
      setState(() {
        showInternetScreen = false;
      });

      _setCurrentState(
        LocationPickerState.checkingInternet,
        '_retryAfterInternetRestore',
        'Retrying after internet restore',
      );

      // Reinitialize the location picker completely
      await _initializeLocationPicker();
    } catch (e) {
      debugPrint('❌ Error retrying after internet restore: $e');
      _setCurrentState(
        LocationPickerState.error,
        '_retryAfterInternetRestore',
        'Error during retry: $e',
      );
    }
  }

  Widget _buildLoadingScreen([String? message]) {
    final displayMessage = message ?? _getLoadingMessage();
    final isDark = uiController.darkMode.value;
    final themeColor = uiController.currentMainColor;

    return Container(
      alignment: Alignment.center,
      width: double.infinity,
      height: double.infinity,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color:
                isDark
                    ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: themeColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        themeColor.withValues(alpha: 0.8),
                        themeColor.withValues(alpha: 0.4),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: themeColor.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: themeColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  displayMessage,
                  style: TextStyle(
                    fontSize: 18,
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.87)
                            : Colors.black.withValues(alpha: 0.87),
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'text_please_wait_2'.tr,
                  style: TextStyle(
                    fontSize: 14,
                    color:
                        isDark
                            ? Colors.white.withValues(alpha: 0.54)
                            : Colors.black.withValues(alpha: 0.54),
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getLoadingMessage() {
    switch (currentState) {
      case LocationPickerState.checkingInternet:
        return 'Checking internet connection...';
      case LocationPickerState.loadingMap:
        return 'Loading map...';
      default:
        return 'text_getting_your_location'.tr;
    }
  }
}

class LocationSearchDialog extends StatefulWidget {
  final List<Map<String, dynamic>> savedLocations;
  final bool isOfflineMode;
  final Future<void> Function(Map<String, dynamic>) onLocationSelected;
  final VoidCallback? onLocationSaved;

  const LocationSearchDialog({
    super.key,
    required this.savedLocations,
    required this.isOfflineMode,
    required this.onLocationSelected,
    this.onLocationSaved,
  });

  @override
  State<LocationSearchDialog> createState() => _LocationSearchDialogState();
}

class _LocationSearchDialogState extends State<LocationSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredLocations = [];
  List<offline.LocationSearchResult> _searchResults = [];
  bool _isSearching = false;
  bool _isSelectingLocation = false; // Add loading state for location selection
  final WorldLocationsService _worldLocationsService =
      WorldLocationsService.instance;
  final offline.OfflineLocationSearchService _offlineSearchService =
      offline.OfflineLocationSearchService.instance;

  @override
  void initState() {
    super.initState();
    _filteredLocations = widget.savedLocations;
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    await Future.wait([
      _worldLocationsService.initialize(),
      _offlineSearchService.initialize(),
    ]);

    // Load initial results from offline service
    if (_searchResults.isEmpty) {
      final initialResults = await _offlineSearchService.searchLocations(
        '',
        limit: 20,
      );
      setState(() {
        _searchResults = initialResults;
      });
    }
  }

  Future<void> _filterLocations(String query) async {
    if (query.isEmpty) {
      setState(() {
        _filteredLocations = widget.savedLocations;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    // Simulate search delay for better UX
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      List<Map<String, dynamic>> results = [];

      // Use enhanced offline search service (includes native search)
      if (_offlineSearchService.isInitialized) {
        final offlineResults = await _offlineSearchService.searchLocations(
          query,
          limit: 15,
          forceOffline: widget.isOfflineMode,
        );

        results =
            offlineResults
                .map(
                  (result) => {
                    'name': result.displayName,
                    'address': result.shortDisplayName,
                    'latitude': result.latitude,
                    'longitude': result.longitude,
                    'country': result.country,
                    'region': result.state ?? '',
                    'city': result.city,
                    'postcode': '',
                    'timestamp': DateTime.now().toIso8601String(),
                    'type': result.type.toString(),
                    'source': 'offline_search',
                  },
                )
                .toList();

        // Store search results for potential map centering
        setState(() {
          _searchResults = offlineResults;
        });
      }

      // Fallback to world locations service if offline search fails
      if (results.isEmpty && _worldLocationsService.isLoaded) {
        final worldResults = _worldLocationsService.searchLocations(
          query,
          limit: 10,
        );

        final worldMapped =
            worldResults
                .map(
                  (result) => {
                    'name': result.displayName,
                    'address': result.shortDisplayName,
                    'latitude': result.latitude,
                    'longitude': result.longitude,
                    'country': result.country,
                    'region': result.state ?? '',
                    'city': result.city ?? result.name,
                    'postcode': '',
                    'timestamp': DateTime.now().toIso8601String(),
                    'type': result.type.toString(),
                    'source': 'world_locations',
                  },
                )
                .toList();

        results.addAll(worldMapped);
      }

      // Also search in saved locations
      final lowerQuery = query.toLowerCase();
      final savedResults =
          widget.savedLocations.where((location) {
            final country =
                (location['country'] as String? ?? '').toLowerCase();
            final city = (location['city'] as String? ?? '').toLowerCase();
            final region = (location['region'] as String? ?? '').toLowerCase();
            final name = (location['name'] as String? ?? '').toLowerCase();
            final address =
                (location['address'] as String? ?? '').toLowerCase();

            return country.contains(lowerQuery) ||
                city.contains(lowerQuery) ||
                region.contains(lowerQuery) ||
                name.contains(lowerQuery) ||
                address.contains(lowerQuery);
          }).toList();

      // Combine results, avoiding duplicates
      for (final savedResult in savedResults) {
        final isDuplicate = results.any(
          (result) =>
              (result['latitude'] - savedResult['latitude']).abs() < 0.01 &&
              (result['longitude'] - savedResult['longitude']).abs() < 0.01,
        );

        if (!isDuplicate) {
          results.add(savedResult);
        }
      }

      // Limit total results
      if (results.length > 20) {
        results = results.take(20).toList();
      }

      setState(() {
        _filteredLocations = results;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('Error searching locations: $e');
      setState(() {
        _filteredLocations = [];
        _isSearching = false;
      });
    }
  }

  /// Get display name for location source
  String _getSourceDisplayName(String source) {
    switch (source) {
      case 'saved':
        return 'SAVED';
      case 'offline_search':
        return 'text_offline'.tr;
      case 'world_locations':
        return 'GLOBAL';
      case 'search_selection':
        return 'RECENT';
      default:
        return 'LOCAL';
    }
  }

  /// Get country flag emoji based on country name
  String _getCountryFlag(String? countryName) {
    if (countryName == null || countryName.isEmpty) return '🌍';

    final country = countryName.toLowerCase().trim();

    // Comprehensive country to flag emoji mapping
    final countryFlags = {
      // Major countries
      'united states': '🇺🇸', 'usa': '🇺🇸', 'us': '🇺🇸', 'america': '🇺🇸',
      'united kingdom': '🇬🇧', 'uk': '🇬🇧', 'britain': '🇬🇧',
      'england': '🏴󠁧󠁢󠁥󠁮󠁧󠁿',
      'scotland': '🏴󠁧󠁢󠁳󠁣󠁴󠁿',
      'wales': '🏴󠁧󠁢󠁷󠁬󠁳󠁿',
      'canada': '🇨🇦', 'australia': '🇦🇺', 'new zealand': '🇳🇿',
      'germany': '🇩🇪', 'france': '🇫🇷', 'italy': '🇮🇹', 'spain': '🇪🇸',
      'portugal': '🇵🇹', 'netherlands': '🇳🇱', 'belgium': '🇧🇪',
      'switzerland': '🇨🇭', 'austria': '🇦🇹', 'sweden': '🇸🇪',
      'norway': '🇳🇴', 'denmark': '🇩🇰', 'finland': '🇫🇮',
      'iceland': '🇮🇸', 'ireland': '🇮🇪', 'poland': '🇵🇱',
      'czech republic': '🇨🇿', 'slovakia': '🇸🇰', 'hungary': '🇭🇺',
      'romania': '🇷🇴', 'bulgaria': '🇧🇬', 'greece': '🇬🇷',
      'turkey': '🇹🇷', 'russia': '🇷🇺', 'ukraine': '🇺🇦',

      // Asian countries
      'china': '🇨🇳', 'japan': '🇯🇵', 'south korea': '🇰🇷', 'korea': '🇰🇷',
      'india': '🇮🇳', 'pakistan': '🇵🇰', 'bangladesh': '🇧🇩',
      'thailand': '🇹🇭', 'vietnam': '🇻🇳', 'malaysia': '🇲🇾',
      'singapore': '🇸🇬', 'indonesia': '🇮🇩', 'philippines': '🇵🇭',
      'taiwan': '🇹🇼', 'hong kong': '🇭🇰', 'iran': '🇮🇷',
      'saudi arabia': '🇸🇦', 'uae': '🇦🇪', 'united arab emirates': '🇦🇪',

      // African countries
      'south africa': '🇿🇦', 'egypt': '🇪🇬', 'morocco': '🇲🇦',
      'nigeria': '🇳🇬', 'kenya': '🇰🇪', 'ethiopia': '🇪🇹',

      // South American countries
      'brazil': '🇧🇷', 'argentina': '🇦🇷', 'chile': '🇨🇱',
      'peru': '🇵🇪', 'colombia': '🇨🇴', 'venezuela': '🇻🇪',

      // Central American countries
      'mexico': '🇲🇽', 'guatemala': '🇬🇹', 'costa rica': '🇨🇷',
      'panama': '🇵🇦', 'cuba': '🇨🇺', 'jamaica': '🇯🇲',

      // European countries
      'albania': '🇦🇱', 'andorra': '🇦🇩', 'armenia': '🇦🇲',
      'azerbaijan': '🇦🇿', 'belarus': '🇧🇾', 'bosnia and herzegovina': '🇧🇦',
      'croatia': '🇭🇷', 'cyprus': '🇨🇾', 'estonia': '🇪🇪',
      'georgia': '🇬🇪', 'latvia': '🇱🇻', 'lithuania': '🇱🇹',
      'luxembourg': '🇱🇺', 'malta': '🇲🇹', 'moldova': '🇲🇩',
      'monaco': '🇲🇨', 'montenegro': '🇲🇪', 'north macedonia': '🇲🇰',
      'san marino': '🇸🇲', 'serbia': '🇷🇸', 'slovenia': '🇸🇮',
      'vatican city': '🇻🇦',
    };

    return countryFlags[country] ?? '🌍';
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Obx(
      () => Dialog(
        backgroundColor:
            uiController.darkMode.value ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          children: [
            Container(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        widget.isOfflineMode ? Icons.wifi_off : Icons.search,
                        color:
                            uiController.darkMode.value
                                ? Colors.white
                                : Colors.black,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'text_search_locations_2'.tr,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color:
                                    uiController.darkMode.value
                                        ? Colors.white
                                        : Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.close,
                          color:
                              uiController.darkMode.value
                                  ? Colors.white
                                  : Colors.black,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Search field
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'hinttext_search_by_city_or_country'.tr,
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor:
                          uiController.darkMode.value
                              ? Colors.grey[800]
                              : Colors.grey[100],
                    ),
                    onChanged: (query) {
                      // Debounce search to avoid too many API calls
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (_searchController.text == query) {
                          _filterLocations(query);
                        }
                      });
                    },
                  ),

                  const SizedBox(height: 16),

                  // Results
                  Expanded(
                    child:
                        _isSearching
                            ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  Text(
                                    'text_searching_locations'.tr,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                            : _filteredLocations.isEmpty
                            ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    widget.isOfflineMode
                                        ? Icons.location_off
                                        : Icons.search_off,
                                    size: 64,
                                    color:
                                        uiController.darkMode.value
                                            ? Colors.white
                                            : Colors.black,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    widget.isOfflineMode
                                        ? 'No offline locations found'
                                        : 'No locations found',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  if (widget.isOfflineMode)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'text_try_downloading_offline_maps_for_this_area'.tr,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                ],
                              ),
                            )
                            : ListView.builder(
                              itemCount: _filteredLocations.length,
                              itemBuilder: (context, index) {
                                final location = _filteredLocations[index];
                                // Determine color based on location source
                                final source =
                                    location['source'] as String? ?? 'unknown';
                                final iconColor = uiController.currentMainColor;

                                return ListTile(
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: uiController.secondaryColorDark,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _getCountryFlag(location['country']),
                                        style: const TextStyle(fontSize: 20),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    // countryFlags
                                    location['name'] ??
                                        '${location['city']}, ${location['country']}',
                                    style: TextStyle(
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.white
                                              : Colors.black,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (location['address'] != null &&
                                          location['address']
                                              .toString()
                                              .isNotEmpty)
                                        Text(
                                          location['address'],
                                          style: TextStyle(
                                            color:
                                                uiController.darkMode.value
                                                    ? Colors.grey[400]
                                                    : Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      Row(
                                        children: [
                                          Text(
                                            '${location['latitude'].toStringAsFixed(4)}, ${location['longitude'].toStringAsFixed(4)}',
                                            style: TextStyle(
                                              color:
                                                  uiController.darkMode.value
                                                      ? Colors.grey[500]
                                                      : Colors.grey[500],
                                              fontSize: 11,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: iconColor.withValues(
                                                alpha: 0.2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              _getSourceDisplayName(source),
                                              style: TextStyle(
                                                color: iconColor,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  onTap: () async {
                                    // Prevent multiple selections
                                    if (_isSelectingLocation) {
                                      debugPrint(
                                        '⚠️ Location selection already in progress, ignoring tap',
                                      );
                                      return;
                                    }

                                    setState(() {
                                      _isSelectingLocation = true;
                                    });

                                    debugPrint(
                                      '🔍 Location selected in dialog: ${location['name']}',
                                    );

                                    try {
                                      // Close dialog first
                                      Navigator.of(context).pop();

                                      // Add a small delay to ensure dialog is fully closed
                                      await Future.delayed(
                                        const Duration(milliseconds: 100),
                                      );

                                      // Then call the location selection callback
                                      await widget.onLocationSelected(location);

                                      // Notify parent that a location was selected and will be saved
                                      widget.onLocationSaved?.call();

                                      debugPrint(
                                        '✅ Location selection completed successfully',
                                      );
                                    } catch (e) {
                                      debugPrint(
                                        '❌ Error in location selection callback: $e',
                                      );
                                    } finally {
                                      // Reset loading state (though dialog is closed, this is for safety)
                                      if (mounted) {
                                        setState(() {
                                          _isSelectingLocation = false;
                                        });
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                  ),
                ],
              ),
            ),
            // Loading overlay when selecting location
            if (_isSelectingLocation)
              Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.7,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        'text_moving_to_location'.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
