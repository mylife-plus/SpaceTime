import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../../../services/connectivity_service.dart';
import '../../../../services/permission_service.dart';
import '../../../../services/background_tile_download_service.dart';

/// Map initialization states for sequential flow
enum MapInitializationState {
  initial, // Starting state
  checkingPermission, // Checking/requesting location permission
  permissionDenied, // Permission denied, show permission screen
  checkingInternet, // Checking internet connectivity
  internetRequired, // No internet and no offline tiles, show internet screen
  downloadingTiles, // Downloading map tiles
  loadingMap, // Loading map with tiles
  ready, // Map is ready and functional
  error, // Error state
}

/// Service responsible for managing map initialization sequence
class MapInitializationService extends GetxService {
  // Sequential state management
  final currentInitializationState = MapInitializationState.initial.obs;
  final isProcessingStateChange = false.obs;
  final stateChangeMessage = ''.obs;

  // Legacy variables (keeping for compatibility)
  final needsInternetConnection = false.obs;
  final isFirstTimeLoad = true.obs;
  final hasOfflineTiles = false.obs;
  final isConnectivityChecking = false.obs;
  final shouldShowInternetScreen = false.obs;

  @override
  void onInit() {
    super.onInit();
    _setupServiceListeners();
  }

  /// Initialize connectivity and permission services
  void initializeServices() {
    try {
      // Initialize connectivity service if not already registered
      if (!Get.isRegistered<ConnectivityService>()) {
        Get.put(ConnectivityService());
      }

      // Initialize permission service if not already registered
      if (!Get.isRegistered<PermissionService>()) {
        Get.put(PermissionService());
      }

      debugPrint(
        '[MapInitializationService] Services initialized successfully',
      );
    } catch (e) {
      debugPrint('[MapInitializationService] Error initializing services: $e');
    }
  }

  /// Set up reactive listeners for sequential state management
  void _setupServiceListeners() {
    try {
      final connectivityService = Get.find<ConnectivityService>();
      final permissionService = Get.find<PermissionService>();

      // Listen to permission changes and advance state
      ever(permissionService.hasLocationPermission, (bool hasPermission) {
        _handlePermissionStateChange(hasPermission);
      });

      // Listen to connectivity changes and advance state
      ever(connectivityService.isConnected, (bool isConnected) {
        _handleConnectivityStateChange(isConnected);
      });

      // Listen to permission just granted for immediate progression
      ever(permissionService.permissionJustGranted, (bool justGranted) {
        if (justGranted) {
          _handlePermissionJustGranted();
        }
      });

      // Listen to state changes and process them sequentially
      ever(currentInitializationState, (MapInitializationState state) {
        _processStateChange(state);
      });

      debugPrint(
        '[MapInitializationService] Sequential service listeners set up successfully',
      );
    } catch (e) {
      debugPrint(
        '[MapInitializationService] Error setting up service listeners: $e',
      );
    }
  }

  /// Handle permission state changes in sequential flow
  void _handlePermissionStateChange(bool hasPermission) {
    debugPrint(
      '[MapInitializationService] Permission state changed: $hasPermission',
    );

    // Process permission changes for any permission-related state
    if (currentInitializationState.value ==
            MapInitializationState.checkingPermission ||
        currentInitializationState.value ==
            MapInitializationState.permissionDenied) {
      if (hasPermission) {
        // Permission granted, automatically advance to internet checking
        debugPrint(
          '[MapInitializationService] Permission granted from ${currentInitializationState.value}, advancing to internet check',
        );
        setState(MapInitializationState.checkingInternet);
      } else {
        // Permission denied, stay in denied state
        if (currentInitializationState.value !=
            MapInitializationState.permissionDenied) {
          setState(MapInitializationState.permissionDenied);
        }
      }
    }
  }

  /// Handle connectivity state changes in sequential flow
  void _handleConnectivityStateChange(bool isConnected) {
    debugPrint(
      '[MapInitializationService] Connectivity state changed: $isConnected',
    );
    debugPrint(
      '[MapInitializationService] Current state: ${currentInitializationState.value}',
    );

    if (!isConnected) {
      // Lost connectivity logic
      debugPrint(
        '[MapInitializationService] No connectivity detected - checking current state and offline tiles',
      );

      if (currentInitializationState.value == MapInitializationState.ready ||
          currentInitializationState.value ==
              MapInitializationState.loadingMap ||
          currentInitializationState.value ==
              MapInitializationState.downloadingTiles ||
          currentInitializationState.value ==
              MapInitializationState.checkingInternet) {
        debugPrint(
          '🌐 Lost connectivity in active state - checking if internet screen needed',
        );
        _checkIfInternetScreenNeeded();
      } else if (currentInitializationState.value ==
              MapInitializationState.initial ||
          currentInitializationState.value ==
              MapInitializationState.checkingPermission) {
        debugPrint(
          '🌐 No connectivity during initialization - checking offline tiles immediately',
        );
        Future.microtask(() async {
          await _checkOfflineTilesAndSetState();
        });
      }
    } else {
      // ENHANCED: Connectivity restored - immediate response
      debugPrint(
        '🌐 Connectivity restored - current state: ${currentInitializationState.value}',
      );

      // IMMEDIATE response for internet-related states
      if (currentInitializationState.value ==
              MapInitializationState.checkingInternet ||
          currentInitializationState.value ==
              MapInitializationState.internetRequired) {
        debugPrint(
          '🌐 Internet restored - IMMEDIATELY hiding internet screen and advancing state',
        );

        // Immediately advance to loading state (this hides InternetRequiredScreen instantly)
        setState(MapInitializationState.loadingMap);

        // Then reload map in background
        Future.microtask(() async {
          // Trigger map reload callback if available
          Get.find<MapInitializationService>().onConnectivityRestored?.call();
        });
      } else if (currentInitializationState.value ==
          MapInitializationState.ready) {
        // If already ready, just refresh the map
        debugPrint('🌐 Internet restored in ready state - refreshing map view');
        Future.microtask(() async {
          Get.find<MapInitializationService>().onConnectivityRestored?.call();
        });
      }
    }
  }

  /// Handle permission just granted for immediate state progression
  void _handlePermissionJustGranted() {
    onPermissionGranted?.call();
  }

  /// Set the current initialization state
  void setState(MapInitializationState newState) {
    debugPrint(
      '[MapInitializationService] Entered setState with newState=$newState',
    );
    debugPrint(
      '[MapInitializationService] Current state before check: ${currentInitializationState.value}',
    );

    if (currentInitializationState.value != newState) {
      debugPrint(
        '🔄 State transition: ${currentInitializationState.value} → $newState',
      );
      currentInitializationState.value = newState;
    }
  }

  /// Advance to the next state in the sequence
  Future<void> advanceToNextState() async {
    if (isProcessingStateChange.value) {
      debugPrint('⏳ State change already in progress, skipping');
      return;
    }

    isProcessingStateChange.value = true;

    try {
      switch (currentInitializationState.value) {
        case MapInitializationState.initial:
          setState(MapInitializationState.checkingPermission);
          break;

        case MapInitializationState.checkingPermission:
          final permissionService = Get.find<PermissionService>();
          if (permissionService.hasLocationPermission.value) {
            setState(MapInitializationState.checkingInternet);
          } else {
            setState(MapInitializationState.permissionDenied);
          }
          break;

        case MapInitializationState.permissionDenied:
          // Stay in this state until permission is granted
          break;

        case MapInitializationState.checkingInternet:
          await _checkInternetAndAdvance();
          break;

        case MapInitializationState.internetRequired:
          // Stay in this state until internet is available
          break;

        case MapInitializationState.downloadingTiles:
          setState(MapInitializationState.loadingMap);
          break;

        case MapInitializationState.loadingMap:
          setState(MapInitializationState.ready);
          onMapReady?.call();
          break;

        case MapInitializationState.ready:
          onMapReady?.call();
          // Final state, nothing to advance to
          break;

        case MapInitializationState.error:
          // Error state, manual intervention needed
          break;
      }
    } catch (e) {
      debugPrint('❌ Error advancing state: $e');
      setState(MapInitializationState.error);
    } finally {
      isProcessingStateChange.value = false;
    }
  }

  /// Check internet connectivity and advance state accordingly
  Future<void> _checkInternetAndAdvance() async {
    try {
      debugPrint('🌐 Starting internet check for Mapbox...');
      final connectivityService = Get.find<ConnectivityService>();

      // Use Mapbox-specific internet check for better reliability
      final hasInternetForMapbox =
          await connectivityService.hasInternetQuickCheck();

      debugPrint('🌐 Mapbox internet check result: $hasInternetForMapbox');

      if (hasInternetForMapbox) {
        // Internet available for Mapbox, check if we need to download tiles
        final hasOfflineTiles = await _isOfflineDataAvailable();

        if (hasOfflineTiles) {
          // We have tiles, go straight to loading map
          debugPrint('🗺 Offline tiles available, loading map directly');
          setState(MapInitializationState.loadingMap);
        } else {
          // Need to download tiles
          debugPrint('🗺 No offline tiles, need to download');
          setState(MapInitializationState.downloadingTiles);
        }
      } else {
        setState(MapInitializationState.internetRequired);
        // No internet for Mapbox, check if we have offline tiles
        debugPrint(
          '🌐 No internet for Mapbox detected, checking offline tiles',
        );
        await _checkOfflineTilesAndSetState();
      }
    } catch (e) {
      setState(MapInitializationState.internetRequired);
      debugPrint('❌ Error checking internet: $e');

      // Check if the error itself indicates connectivity issues
      final connectivityService = Get.find<ConnectivityService>();
      if (connectivityService.isMapboxConnectivityError(e.toString())) {
        debugPrint(
          '🌐 Internet check failed with connectivity error - setting internetRequired state',
        );
        setState(MapInitializationState.internetRequired);
      } else {
        setState(MapInitializationState.internetRequired);
      }
    }
  }

  /// Check offline tiles and set appropriate state
  Future<void> _checkOfflineTilesAndSetState() async {
    try {
      debugPrint('🗺 Checking offline tiles and setting state');

      final backgroundService = Get.find<BackgroundTileDownloadService>();
      final tileCount = backgroundService.totalTilesDownloaded.value;
      final hasOfflineTiles = await _isOfflineDataAvailable();

      debugPrint(
        '🗺 Tile count: $tileCount, hasOfflineTiles: $hasOfflineTiles',
      );

      if (hasOfflineTiles && tileCount >= 25000) {
        // Sufficient offline tiles available
        debugPrint('🗺 Sufficient offline tiles - proceeding to load map');
        setState(MapInitializationState.loadingMap);
      } else {
        // Insufficient tiles - need internet
        debugPrint(
          '🌐 Insufficient offline tiles ($tileCount < 25,000) - requiring internet',
        );
        setState(MapInitializationState.internetRequired);
      }
    } catch (e) {
      debugPrint('❌ Error checking offline tiles: $e');
      setState(MapInitializationState.internetRequired);
    }
  }

  /// Check if internet screen should be shown due to connectivity loss
  Future<void> _checkIfInternetScreenNeeded() async {
    try {
      final connectivityService = Get.find<ConnectivityService>();
      final hasInternetForMapbox =
          await connectivityService.hasInternetForMapbox();

      if (!hasInternetForMapbox) {
        // Check tile count - show internet widget if < 25,000 tiles
        final backgroundService = Get.find<BackgroundTileDownloadService>();
        final tileCount = backgroundService.totalTilesDownloaded.value;
        final hasSufficientTiles = tileCount >= 25000;

        debugPrint(
          '🌐 No internet access - tile count: $tileCount, sufficient: $hasSufficientTiles',
        );

        if (!hasSufficientTiles) {
          debugPrint(
            '🌐 No internet and insufficient tiles (< 25,000) - setting internetRequired state',
          );
          setState(MapInitializationState.internetRequired);
        } else {
          debugPrint(
            '🌐 No internet but sufficient tiles (≥ 25,000) - staying in ready state',
          );
        }
      } else {
        debugPrint(
          '🌐 Internet access available - no need for internet screen',
        );
      }
    } catch (e) {
      debugPrint('❌ Error checking if internet screen needed: $e');
    }
  }

  /// Process state changes and update UI accordingly
  void _processStateChange(MapInitializationState state) {
    debugPrint('🔄 Processing state change: $state');

    switch (state) {
      case MapInitializationState.initial:
        stateChangeMessage.value = 'Initializing...';
        break;

      case MapInitializationState.checkingPermission:
        stateChangeMessage.value = 'Checking location permission...';
        _checkLocationPermissionInState();
        break;

      case MapInitializationState.permissionDenied:
        stateChangeMessage.value = 'Location permission required';
        // UI will show permission request screen
        break;

      case MapInitializationState.checkingInternet:
        stateChangeMessage.value = 'Checking internet connection...';
        // Immediately trigger the quick internet check
        Future.microtask(() async {
          await _checkInternetAndAdvance();
        });
        break;

      case MapInitializationState.internetRequired:
        stateChangeMessage.value = 'Internet connection required';
        shouldShowInternetScreen.value = true;
        break;

      case MapInitializationState.downloadingTiles:
        stateChangeMessage.value = 'Map ready';
        shouldShowInternetScreen.value = false;
        isFirstTimeLoad.value = false;
        _startTileDownload();
        break;

      case MapInitializationState.loadingMap:
        stateChangeMessage.value = 'Map ready';
        shouldShowInternetScreen.value = false;
        isFirstTimeLoad.value = false;
        _startMapLoading();
        break;

      case MapInitializationState.ready:
        stateChangeMessage.value = 'Map ready';
        shouldShowInternetScreen.value = false;
        isFirstTimeLoad.value = false;
        break;

      case MapInitializationState.error:
        stateChangeMessage.value = 'Error occurred';
        break;
    }
  }

  /// Check location permission within state management
  Future<void> _checkLocationPermissionInState() async {
    try {
      final permissionService = Get.find<PermissionService>();
      final hasPermission = await permissionService.checkLocationPermission(
        requestIfDenied: true,
      );

      if (hasPermission) {
        advanceToNextState();
      } else {
        setState(MapInitializationState.permissionDenied);
      }
    } catch (e) {
      debugPrint('❌ Error checking permission in state: $e');
      setState(MapInitializationState.error);
    }
  }

  /// Start tile download process
  Future<void> _startTileDownload() async {
    try {
      debugPrint('🗺 Starting tile download...');

      // Get the background download service
      final downloadService = Get.find<BackgroundTileDownloadService>();

      // Start the offline map setup
      await onOfflineMapSetup?.call();

      // Trigger a manual download for a default region
      try {
        // Create a default region around user's location or a global area
        final bounds = mapbox.CoordinateBounds(
          southwest: mapbox.Point(
            coordinates: mapbox.Position(-180.0, -85.0), // Global southwest
          ),
          northeast: mapbox.Point(
            coordinates: mapbox.Position(180.0, 85.0), // Global northeast
          ),
          infiniteBounds: false,
        );
        await downloadService.downloadRegion(bounds, [10, 11, 12, 13, 14]);
        debugPrint('🗺 Triggered manual download for global region');
      } catch (e) {
        debugPrint('⚠️ Could not trigger manual download: $e');
      }

      // Wait a moment to show the download banner
      await Future.delayed(const Duration(seconds: 2));

      // Advance to loading map
      advanceToNextState();
    } catch (e) {
      debugPrint('❌ Error downloading tiles: $e');
      setState(MapInitializationState.error);
    }
  }

  /// Start map loading process
  Future<void> _startMapLoading() async {
    try {
      debugPrint('🗺 Starting map loading...');

      // Use the direct initialization method for the actual map setup
      await onDirectMapInitialization?.call();

      // Mark as ready
      advanceToNextState();
    } catch (e) {
      debugPrint('❌ Error loading map: $e');
      setState(MapInitializationState.error);
    }
  }

  /// Start the sequential initialization process
  Future<void> startSequentialInitialization() async {
    debugPrint('🚀 Starting sequential initialization process');

    // Reset state
    currentInitializationState.value = MapInitializationState.initial;
    isProcessingStateChange.value = false;

    // Start the sequence
    await advanceToNextState();
  }

  /// Retry from current state (for user-triggered retries)
  Future<void> retryCurrentState() async {
    debugPrint(
      '[MapInitializationService] Retrying current state: ${currentInitializationState.value}',
    );

    try {
      switch (currentInitializationState.value) {
        case MapInitializationState.permissionDenied:
          debugPrint('🔄 Retrying from permission denied state');
          setState(MapInitializationState.checkingPermission);
          break;

        case MapInitializationState.internetRequired:
          debugPrint('🔄 Retrying from internet required state');

          // Force refresh connectivity before retrying
          final connectivityService = Get.find<ConnectivityService>();
          await connectivityService.refreshConnectivity();

          setState(MapInitializationState.checkingInternet);
          break;

        case MapInitializationState.error:
          debugPrint('🔄 Retrying from error state');
          setState(MapInitializationState.initial);
          await advanceToNextState();
          break;

        default:
          debugPrint(
            '🔄 Retrying from state: ${currentInitializationState.value}',
          );
          // For other states, just advance
          await advanceToNextState();
          break;
      }
    } catch (e) {
      debugPrint('❌ Error during state retry: $e');
      setState(MapInitializationState.error);
    }
  }

  /// Check initial connectivity and set appropriate state
  Future<void> checkInitialConnectivityAndSetState() async {
    try {
      debugPrint('🌐 Checking initial connectivity and setting state');

      // First check location permissions
      final permissionService = Get.find<PermissionService>();
      if (!permissionService.hasLocationPermission.value) {
        debugPrint(
          '🔐 No location permission - setting checkingPermission state',
        );
        setState(MapInitializationState.checkingPermission);
        return;
      }

      // Check internet connectivity
      final connectivityService = Get.find<ConnectivityService>();
      final hasInternetForMapbox =
          await connectivityService.hasInternetForMapbox();

      if (hasInternetForMapbox) {
        // Internet available, proceed normally
        debugPrint('🌐 Internet available - proceeding to check offline tiles');
        final hasOfflineTiles = await _isOfflineDataAvailable();

        if (hasOfflineTiles) {
          setState(MapInitializationState.loadingMap);
        } else {
          setState(MapInitializationState.downloadingTiles);
        }
      } else {
        // No internet - check if we have sufficient offline tiles
        debugPrint('🌐 No internet - checking offline tiles');
        await _checkOfflineTilesAndSetState();
      }
    } catch (e) {
      debugPrint('❌ Error in initial connectivity check: $e');
      setState(MapInitializationState.error);
    }
  }

  /// Check if offline data is available
  Future<bool> _isOfflineDataAvailable() async {
    try {
      // Check if the background service has downloaded sufficient tiles
      final backgroundService = Get.find<BackgroundTileDownloadService>();
      final tileCount = backgroundService.totalTilesDownloaded.value;

      debugPrint(
        '🗺 OFFLINE - Total tiles downloaded: $tileCount (threshold: 30,000)',
      );

      // Return true only if we have 30,000+ tiles for reliable offline mode
      return tileCount >= 30000;
    } catch (e) {
      debugPrint('❌ OFFLINE - Error checking downloaded tiles: $e');
      return false;
    }
  }

  // Callback functions that can be set by the MapController
  Function()? onPermissionGranted;
  Function()? onConnectivityRestored;
  Function()? onMapReady;
  Future<void> Function()? onOfflineMapSetup;
  Future<void> Function()? onDirectMapInitialization;
}
