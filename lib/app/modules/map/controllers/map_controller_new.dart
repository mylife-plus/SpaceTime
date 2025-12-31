import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/services/offline_map_service.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import '../../../../services/permission_service.dart';
import '../../../../services/connectivity_service.dart';
import '../../../repositories/memory_repository.dart';
import '../../../repositories/cluster_repository.dart';
import '../../../services/map_marker_service.dart';
import '../../../models/memory_cluster.dart' as models;
import '../../../../services/memory_clustering_service.dart' as clustering;
import '../../../../services/memory_geojson_service.dart';
import '../../../services/offline_map_coordinator_service.dart';
import '../../memories/controllers/memory_controller.dart';
import '../../add_memories/controllers/add_memories_controller.dart';
import '../../add_memories/views/add_memories.dart';
import '../../../services/memory_db.dart';
import '../../../routes/app_pages.dart';
import '../views/mini_widgets/bottom_info.dart';

class MapControllerNew extends GetxController {
  // Constructor with logging
  MapControllerNew() {
    debugPrint('[MapControllerNew] 🏗️ Constructor called - Creating new instance: $hashCode');
  }

  // MapBox controller
  mapbox.MapboxMap? mapboxMap;

  // MapBox Native Clustering Constants
  static const String MEMORY_SOURCE_ID = 'memory-source';
  static const String CLUSTER_LAYER_ID = 'cluster-layer';
  static const String CLUSTER_COUNT_LAYER_ID = 'cluster-count-layer';
  static const String UNCLUSTERED_LAYER_ID = 'unclustered-layer';
  static const String INDIVIDUAL_COUNT_LAYER_ID = 'individual-count-layer';
  static const String ARROW_LINES_SOURCE_ID = 'arrow-lines-source';
  static const String ARROW_LINES_LAYER_ID = 'arrow-lines-layer';

  // Zoom level constants - now loaded from MapboxZoomHelper
  // These getters provide access to the centralized zoom configuration
  double get _minZoom => MapboxZoomHelper().minZoom.value;
  double get _maxZoom => MapboxZoomHelper().maxZoom.value;

  // Zoom thresholds for layer visibility - loaded from MapboxZoomHelper
  double get _clusterVisibilityMaxZoom => MapboxZoomHelper().clusterVisibilityMaxZoom.value;
  double get _individualVisibilityMinZoom => MapboxZoomHelper().individualVisibilityMinZoom.value;
  double get _detailVisibilityMinZoom => MapboxZoomHelper().detailVisibilityMinZoom.value;

  // Reactive state variables
  final RxBool isMapReady = false.obs;
  final RxBool isLoadingLocation = false.obs;
  final RxBool hasLocationPermission =
      false.obs; // Start as false until checked
  final RxString locationStatus = 'Checking permissions...'.obs;
  // Internet connectivity checks removed - offline tiles are downloaded during Get Started flow
  PermissionStatus permissionStatus = PermissionStatus.denied;

  // Current zoom level - initialized from MapboxZoomHelper
  var currentZoom = MapboxZoomHelper().currentZoomInitial.value.obs;

  // Current location
  final Rx<Position?> currentLocation = Rx<Position?>(null);

  // Filter state
  final RxBool isFilterOpen = false.obs;
  final RxMap<String, String> filterValues = <String, String>{}.obs;
  final RxString selectedRadius = ''.obs;
  final RxList<String> selectedHashtags = <String>[].obs;
  final RxList<String> selectedContacts = <String>[].obs;
  final RxList<String> selectedCategories = <String>[].obs;
  final RxBool hasActiveFilters = false.obs;

  // Cache for available filter items
  final RxList<String> availableHashtags = <String>[].obs;
  final RxList<String> availableContacts = <String>[].obs;
  final RxList<String> availableCategories = <String>[].obs;

  // Location selection state
  final RxString selectedLocation = ''.obs;

  // Clustering and arrow state
  final RxList<dynamic> currentClusters = <dynamic>[].obs;
  final RxList<dynamic> currentArrows = <dynamic>[].obs;
  final RxList<Map<String, dynamic>> _currentMemories =
      <Map<String, dynamic>>[].obs;

  bool _isBottomPanelOpen = false;

  // Services
  ConnectivityService? _connectivityService;
  MemoryRepository? _memoryRepository;
  ClusterRepository? _clusterRepository;
  MapMarkerService? _mapMarkerService;
  OfflineMapCoordinatorService? _offlineCoordinator;

  // Offline map state getters (delegate to coordinator)
  RxBool get showOfflineDownloadOverlay => _offlineCoordinator?.showOfflineDownloadOverlay ?? false.obs;
  RxBool get isOfflineMode => _offlineCoordinator?.isOfflineMode ?? false.obs;

  // Permission monitoring with listeners
  Worker? _permissionServiceWorker;
  StreamSubscription<AppLifecycleState>? _appLifecycleSubscription;
  _MapLifecycleObserver? _lifecycleObserver;

  // Flag to prevent double initialization
  bool _isInitialized = false;

  @override
  void onInit() {
    super.onInit();

    // Prevent double initialization
    if (_isInitialized) {
      debugPrint('[MapControllerNew] ⚠️ Controller already initialized, skipping onInit()');
      return;
    }

    debugPrint('[MapControllerNew] 🚀 Initializing new map controller (first time)');
    debugPrint('[MapControllerNew] 🆔 Controller instance: ${hashCode}');
    debugPrint(
      '[MapControllerNew] Initial hasLocationPermission: ${hasLocationPermission.value}',
    );

    // Internet connectivity checks removed - offline tiles are downloaded during Get Started flow
   
    _initializeServices();
    _initializeMap();

    // Start periodic permission checking to catch changes from permission service
    _startPermissionMonitoring();

    // Mark as initialized
    _isInitialized = true;
    debugPrint('[MapControllerNew] ✅ Controller initialization complete');
  }

  /// Initialize services
  void _initializeServices() {
    try {
      _connectivityService = Get.find<ConnectivityService>();
      debugPrint('[MapControllerNew] ConnectivityService found');
    } catch (e) {
      debugPrint('[MapControllerNew] ConnectivityService not found: $e');
    }

    // Initialize memory repository
    try {
      _memoryRepository = Get.find<MemoryRepository>();
      debugPrint('[MapControllerNew] MemoryRepository found');
    } catch (e) {
      debugPrint('[MapControllerNew] MemoryRepository not found: $e');
    }

    // Initialize cluster repository
    try {
      _clusterRepository = Get.find<ClusterRepository>();
      debugPrint('[MapControllerNew] ClusterRepository found');
    } catch (e) {
      debugPrint('[MapControllerNew] ClusterRepository not found: $e');
    }

    // Initialize map marker service
    try {
      _mapMarkerService = Get.find<MapMarkerService>();
      debugPrint('[MapControllerNew] MapMarkerService found');
    } catch (e) {
      debugPrint('[MapControllerNew] MapMarkerService not found: $e');
    }

    // Initialize offline map coordinator
    try {
      _offlineCoordinator = Get.find<OfflineMapCoordinatorService>();
      debugPrint('[MapControllerNew] OfflineMapCoordinatorService found');
    } catch (e) {
      debugPrint(
        '[MapControllerNew] OfflineMapCoordinatorService not found, creating: $e',
      );
      Get.put(OfflineMapCoordinatorService());
      _offlineCoordinator = Get.find<OfflineMapCoordinatorService>();
    }

    // Load filter data
    loadFilterData();
  }

  /// Initialize the map with location permissions and current location
  Future<void> _initializeMap() async {
    try {
      debugPrint('[MapControllerNew] 🔍 Starting map initialization');
      locationStatus.value = 'Checking location permissions...';
      isLoadingLocation.value =
          true; // Show loading state during permission check

      // First check internet connectivity
      // Check and request location permissions
      debugPrint('[MapControllerNew] 🔐 Checking location permissions...');
      final hasPermission = await _checkLocationPermissions();

      if (hasPermission) {
        debugPrint('[MapControllerNew] ✅ Location permission granted');
        hasLocationPermission.value = true;
        await _getCurrentLocation();
      } else {
        debugPrint(
          '[MapControllerNew] ❌ Location permission denied or unavailable',
        );
        hasLocationPermission.value = false;
        locationStatus.value = 'Location permission required';
        isLoadingLocation.value =
            false; // Stop loading since we need user action
      }

      // Note: Memory loading will happen after map is created in onMapCreated()
      debugPrint(
        '[MapControllerNew] Map initialization complete, waiting for map creation',
      );
    } catch (e) {
      debugPrint('[MapControllerNew] Error initializing map: $e');
      hasLocationPermission.value = false;
      locationStatus.value = 'Error initializing map';
      await _handleError(e);
    } finally {
      // Ensure loading state is stopped if permission was denied or error occurred
      if (!hasLocationPermission.value) {
        isLoadingLocation.value = false;
      }
      debugPrint(
        '[MapControllerNew] Final state - hasLocationPermission: ${hasLocationPermission.value}, isLoadingLocation: ${isLoadingLocation.value}',
      );
    }
  }

  /// Check and request location permissions
  Future<bool> _checkLocationPermissions() async {
    try {
      debugPrint(
        '[MapControllerNew] 🔍 Checking if location services are enabled...',
      );
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[MapControllerNew] ⏰ Location service check timed out');
          return false;
        },
      );

      if (!serviceEnabled) {
        debugPrint('[MapControllerNew] ❌ Location services are disabled');
        locationStatus.value = 'Location services are disabled';
        return false;
      }
      debugPrint('[MapControllerNew] ✅ Location services are enabled');

      // Check current permission status
      debugPrint('[MapControllerNew] 🔍 Checking current permission status...');
      LocationPermission permission = await Geolocator.checkPermission()
          .timeout(
            Duration(seconds: 5),
            onTimeout: () {
              debugPrint('[MapControllerNew] ⏰ Permission check timed out');
              return LocationPermission.denied;
            },
          );
      debugPrint('[MapControllerNew] Current permission status: $permission');

      if (permission == LocationPermission.denied) {
        debugPrint(
          '[MapControllerNew] 🔐 Permission denied, requesting permission...',
        );
        // Request permission with timeout
        permission = await Geolocator.requestPermission().timeout(
          Duration(seconds: 10),
          onTimeout: () {
            debugPrint('[MapControllerNew] ⏰ Permission request timed out');
            return LocationPermission.denied;
          },
        );
        debugPrint('[MapControllerNew] Permission request result: $permission');
        if (permission == LocationPermission.denied) {
          debugPrint('[MapControllerNew] ❌ Permission request denied by user');
          locationStatus.value = 'Location permission denied';
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[MapControllerNew] ❌ Permission permanently denied');
        locationStatus.value =
            'Location permission permanently denied. Please enable in Settings.';
        return false;
      }

      debugPrint(
        '[MapControllerNew] ✅ Location permission granted: $permission',
      );
      locationStatus.value = 'Permission granted';
      return true;
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error checking permissions: $e');
      locationStatus.value = 'Error checking permissions';
      return false;
    }
  }

  /// Get current location
  Future<void> _getCurrentLocation() async {
    try {
      isLoadingLocation.value = true;
      locationStatus.value = 'Getting current location...';

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: LocationAccuracy.high),
      );

      currentLocation.value = position;
      locationStatus.value = 'Location found';

      debugPrint(
        '[MapControllerNew] 📍 Location found: ${position.latitude}, ${position.longitude}',
      );
      debugPrint(
        '[MapControllerNew] 🗺️ Map ready: ${isMapReady.value}, MapboxMap: ${mapboxMap != null}',
      );

      // Move camera to current location if map is ready
      if (isMapReady.value && mapboxMap != null) {
        debugPrint(
          '[MapControllerNew] 🎬 Calling _moveCameraToCurrentLocation()',
        );
        await _moveCameraToCurrentLocation();
      } else {
        debugPrint(
          '[MapControllerNew] ⚠️ Cannot animate to location - Map not ready or mapboxMap is null',
        );
      }
    } catch (e) {
      debugPrint('[MapControllerNew] Error getting location: $e');
      await _handleError(e);
    } finally {
      isLoadingLocation.value = false;
    }
  }

  /// Move camera to current location
  Future<void> _moveCameraToCurrentLocation() async {
    debugPrint('[MapControllerNew] 🎬 _moveCameraToCurrentLocation() called');

    if (currentLocation.value == null || mapboxMap == null) {
      debugPrint(
        '[MapControllerNew] ❌ Cannot move camera - location: ${currentLocation.value != null}, map: ${mapboxMap != null}',
      );
      return;
    }

    try {
      final position = currentLocation.value!;
      debugPrint(
        '[MapControllerNew] 🚀 Starting flyTo animation to ${position.latitude}, ${position.longitude}',
      );

      // Update current zoom level from MapboxZoomHelper
      currentZoom.value = MapboxZoomHelper().currentZoomAfterLocation.value;

      await mapboxMap!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(position.longitude, position.latitude),
          ),
          zoom: currentZoom.value,
          bearing: 0,
          pitch: 0,
        ),
        mapbox.MapAnimationOptions(duration: 1500),
      );

      debugPrint(
        '[MapControllerNew] ✅ Camera animation completed successfully',
      );
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error moving camera: $e');
    }

    loadMemoriesFromDB();
  }

  /// Ensure camera animates to user location with retry mechanism
  Future<void> _ensureCameraAnimationToUserLocation() async {
    debugPrint(
      '[MapControllerNew] 🎯 Ensuring camera animation to user location',
    );

    // If we already have location, try immediate animation
    if (currentLocation.value != null &&
        isMapReady.value &&
        mapboxMap != null) {
      debugPrint(
        '[MapControllerNew] 🎬 Immediate animation - all conditions met',
      );
      await _moveCameraToCurrentLocation();
      return;
    }

    // If we don't have location yet but have permission, wait and retry
    if (currentLocation.value == null && hasLocationPermission.value) {
      debugPrint('[MapControllerNew] ⏳ Waiting for location to be obtained...');

      // Wait up to 5 seconds for location to be obtained
      for (int i = 0; i < 10; i++) {
        await Future.delayed(Duration(milliseconds: 500));

        if (currentLocation.value != null &&
            isMapReady.value &&
            mapboxMap != null) {
          debugPrint(
            '[MapControllerNew] 🎬 Retry animation - conditions met after ${(i + 1) * 500}ms',
          );
          await _moveCameraToCurrentLocation();
          return;
        }
      }

      debugPrint(
        '[MapControllerNew] ⏰ Timeout waiting for location/map readiness',
      );
    }

    debugPrint(
      '[MapControllerNew] ❌ Cannot animate - conditions not met: hasLocation: ${currentLocation.value != null}, mapReady: ${isMapReady.value}, mapboxMap: ${mapboxMap != null}',
    );
  }

  /// Force animate to user location with aggressive retry
  Future<void> _forceAnimateToUserLocation() async {
    debugPrint('[MapControllerNew] 🚀 Force animating to user location');

    // Wait for up to 10 seconds for all conditions to be met
    for (int attempt = 0; attempt < 20; attempt++) {
      debugPrint('[MapControllerNew] 🔄 Animation attempt ${attempt + 1}/20');
      debugPrint(
        '[MapControllerNew] - hasLocation: ${currentLocation.value != null}',
      );
      debugPrint('[MapControllerNew] - mapReady: ${isMapReady.value}');
      debugPrint('[MapControllerNew] - mapboxMap: ${mapboxMap != null}');

      if (currentLocation.value != null &&
          isMapReady.value &&
          mapboxMap != null) {
        try {
          debugPrint(
            '[MapControllerNew] 🎯 All conditions met - executing flyTo animation',
          );
          final position = currentLocation.value!;

          // Use target zoom level from MapboxZoomHelper
          final targetZoom = MapboxZoomHelper().currentZoomAfterLocation.value;
          currentZoom.value = targetZoom;

          await mapboxMap!.flyTo(
            mapbox.CameraOptions(
              center: mapbox.Point(
                coordinates: mapbox.Position(
                  position.longitude,
                  position.latitude,
                ),
              ),
              zoom: targetZoom,
              bearing: 0,
              pitch: 0,
            ),
            mapbox.MapAnimationOptions(duration: 1500),
          );

          debugPrint(
            '[MapControllerNew] ✅ Force animation completed successfully!',
          );
          return;
        } catch (e) {
          debugPrint('[MapControllerNew] ❌ Force animation error: $e');
        }
      }

      await Future.delayed(Duration(milliseconds: 500));
    }

    debugPrint(
      '[MapControllerNew] ⏰ Force animation timeout - giving up after 10 seconds',
    );
  }

  /// Handle map creation callback
  void onMapCreated(mapbox.MapboxMap mapboxMapInstance) {
    debugPrint('[MapControllerNew] 🗺️ === MAP CREATED ===');
    debugPrint('[MapControllerNew] 🗺️ MapboxMap instance received $mapboxMapInstance');
    debugPrint('[MapControllerNew] 🗺️ Platform: ${io.Platform.isIOS ? "iOS" : "Android"}');

 
    mapboxMap = mapboxMapInstance;
    isMapReady.value = true;

    debugPrint('[MapControllerNew] ✅ Map ready state set to: ${isMapReady.value}');
    debugPrint('[MapControllerNew] ✅ MapboxMap instance stored: ${mapboxMap != null}');

    // iOS FIX: Add additional delay for iOS map initialization
    if (io.Platform.isIOS) {
      debugPrint('[MapControllerNew] 🍎 iOS detected - using iOS-specific initialization');
      Future.delayed(Duration(milliseconds: 500), () {
        _initializeMapAfterCreation();
      });
    } else {
      debugPrint('[MapControllerNew] 🤖 Android detected - using standard initialization');
      _initializeMapAfterCreation();
    }
  }

  /// Initialize map components after creation (iOS-safe)
  void _initializeMapAfterCreation() {
    debugPrint('[MapControllerNew] 🚀 Starting post-creation initialization...');

    // Verify map is still available
    if (mapboxMap == null) {
      debugPrint('[MapControllerNew] ❌ MapboxMap became null during initialization');

      // iOS FIX: Retry map initialization if it failed
      if (io.Platform.isIOS) {
        debugPrint('[MapControllerNew] 🍎 iOS: Retrying map initialization in 1 second...');
        Future.delayed(Duration(seconds: 1), () {
          if (mapboxMap != null) {
            debugPrint('[MapControllerNew] 🍎 iOS: Map became available, retrying initialization');
            _initializeMapAfterCreation();
          } else {
            debugPrint('[MapControllerNew] 🍎 iOS: Map still null after retry');
          }
        });
      }
      return;
    }

    // iOS FIX: Test map functionality before proceeding
    if (io.Platform.isIOS) {
      _testMapFunctionality().then((isWorking) {
        if (isWorking) {
          debugPrint('[MapControllerNew] 🍎 iOS: Map functionality test passed');
          _proceedWithMapInitialization();
        } else {
          debugPrint('[MapControllerNew] 🍎 iOS: Map functionality test failed, retrying...');
          Future.delayed(Duration(milliseconds: 500), () {
            _initializeMapAfterCreation();
          });
        }
      });
    } else {
      _proceedWithMapInitialization();
      
    }
  }

  /// Test map functionality (iOS-specific)
  Future<bool> _testMapFunctionality() async {
    try {
      if (mapboxMap == null) return false;

      // Try to get camera state to test if map is responsive
      final cameraState = await mapboxMap!.getCameraState();
      debugPrint('[MapControllerNew] 🍎 iOS: Map test - camera state: ${cameraState.zoom}');
      return true;
    } catch (e) {
      debugPrint('[MapControllerNew] 🍎 iOS: Map test failed: $e');
      return false;
    }
  }

  /// Proceed with map initialization after verification
  void _proceedWithMapInitialization() {
    debugPrint('[MapControllerNew] 🚀 Proceeding with map initialization...');

    // Set up camera change listener for zoom-based visibility
    debugPrint('[MapControllerNew] 📹 Setting up camera change listener...');
    _setupCameraChangeListener();

    // Initialize map data (load memories and move camera)
    debugPrint('[MapControllerNew] 🚀 Calling initializeMapData()...');
    initializeMapData();

    // iOS FIX: If we have permission and location already, animate to it
    if (hasLocationPermission.value && currentLocation.value != null) {
      debugPrint('[MapControllerNew] 🎯 Map ready - animating to existing location');
      debugPrint('[MapControllerNew] 📍 Location: ${currentLocation.value!.latitude}, ${currentLocation.value!.longitude}');

      // Use platform-specific delays
      final delay = io.Platform.isIOS ? 2000 : 500;
      Future.delayed(Duration(milliseconds: delay), () async {
        debugPrint('[MapControllerNew] 🎬 Executing delayed animation (${delay}ms delay)');
        await _moveCameraToCurrentLocation();
      });
    } else if (hasLocationPermission.value && currentLocation.value == null) {
      debugPrint('[MapControllerNew] 🔄 Map ready but no location yet - will animate when location arrives');
    } else {
      debugPrint('[MapControllerNew] ℹ️ No location permission or location available');
      debugPrint('[MapControllerNew] ℹ️ Permission: ${hasLocationPermission.value}, Location: ${currentLocation.value != null}');
    }

    debugPrint('[MapControllerNew] 🗺️ === MAP CREATION COMPLETE ===');
  }

  /// Handle style loaded callback
  void onStyleLoaded(mapbox.StyleLoadedEventData data) {
    debugPrint('[MapControllerNew] Map style loaded');
  }

  /// Retry getting location permissions
  Future<void> retryLocationPermission() async {
    try {
      debugPrint('[MapControllerNew] 🔄 Retrying location permission');
      locationStatus.value = 'Checking permissions...';
      isLoadingLocation.value = true;

      await _initializeMap();

      // Force an immediate check to ensure UI updates right away
      await forcePermissionStateCheck();

      // If permission was granted, animate to user location
      if (hasLocationPermission.value) {
        await _ensureCameraAnimationToUserLocation();
      }

      debugPrint('[MapControllerNew] ✅ Permission retry completed');
      debugPrint(
        '[MapControllerNew] - hasLocationPermission: ${hasLocationPermission.value}',
      );
      debugPrint(
        '[MapControllerNew] - isLoadingLocation: ${isLoadingLocation.value}',
      );
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error retrying location permission: $e');
      hasLocationPermission.value = false;
      isLoadingLocation.value = false;
      locationStatus.value = 'Error checking permissions';
      await _handleError(e);
    }
  }

  /// Open app settings for location permission
  Future<void> openLocationSettings() async {
    try {
      await openAppSettings();
    } catch (e) {
      debugPrint('[MapControllerNew] Error opening settings: $e');
    }
  }

  /// Refresh current location
  Future<void> refreshLocation() async {
    try {
      debugPrint('[MapControllerNew] 🔄 Refresh location called');
      if (hasLocationPermission.value) {
        await animateToUserLocation();
      } else {
        await retryLocationPermission();
      }
    } catch (e) {
      debugPrint('[MapControllerNew] Error refreshing location: $e');
      await _handleError(e);
    }
  }

  /// Animate to current user location (used by FAB and permission grants)
  Future<void> animateToUserLocation() async {
    debugPrint('[MapControllerNew] 🎯 Public animateToUserLocation() called');

    if (hasLocationPermission.value) {
      if (currentLocation.value != null) {
        // If we already have location, animate immediately
        await _moveCameraToCurrentLocation();
      } else {
        // Get fresh location and animate
        await _getCurrentLocation();
      }
    } else {
      debugPrint(
        '[MapControllerNew] ❌ Cannot animate - no location permission',
      );
    }
  }

  /// Check permissions after app resumes (e.g., from settings)
  Future<void> checkPermissionsAfterResume() async {
    try {
      debugPrint('[MapControllerNew] 🔄 Checking permissions after app resume');

      // Use the force check method to ensure immediate state updates
      await forcePermissionStateCheck();
    } catch (e) {
      debugPrint(
        '[MapControllerNew] Error checking permissions after resume: $e',
      );
      await _handleError(e);
    }
  }

  /// Handle errors by checking internet connectivity
  Future<void> _handleError(dynamic error) async {}

  // Internet connectivity checks removed - offline tiles are downloaded during Get Started flow
  // No need to check internet connectivity or monitor for restoration

  /// Load all memories from database using MemoryRepository
  Future<void> loadMemoriesFromDB() async {
    debugPrint(
      '[MapControllerNew] ========== LOADING MEMORIES FROM DATABASE ==========',
    );

    if (_memoryRepository == null) {
      debugPrint('[MapControllerNew] MemoryRepository not initialized');
      return;
    }

    debugPrint(
      '[MapControllerNew] Delegating memory loading to MemoryRepository',
    );
    var memories = await _memoryRepository!.loadAllMemories();

    if (memories != null && memories.isNotEmpty) {
      debugPrint(
        '[MapControllerNew] ${memories.length} memories loaded, setting up native clustering...',
      );
      // Store memories for tap handling
      _currentMemories.assignAll(memories);

      // Calculate and set appropriate zoom level based on memory spread
      await _setOptimalZoomForMemories(memories);

      await _setupMapboxClustering(memories);
    } else {
      debugPrint(
        '[MapControllerNew] No memories loaded - creating test arrows anyway',
      );
      // Clear memories list
      _currentMemories.clear();
      // Even with no memories, let's test the arrow system
      await _generateAndDisplayArrowsFromMemories([]);
    }

    // Auto-start offline download after memories are loaded
    await _offlineCoordinator?.autoStartDownloadIfNeeded();
  }

  /// Setup MapBox native clustering with memories
  Future<void> _setupMapboxClustering(
    List<Map<String, dynamic>> memories,
  ) async {
    if (mapboxMap == null) {
      debugPrint(
        '[MapControllerNew] ⚠️  MapBox map not initialized for clustering - this should not happen after map creation',
      );
      debugPrint(
        '[MapControllerNew] ⚠️  Clustering setup will be skipped. Make sure loadMemoriesFromDB() is only called after onMapCreated()',
      );
      return;
    }

    try {
      debugPrint(
        '[MapControllerNew] ========== SETTING UP MAPBOX NATIVE CLUSTERING ==========',
      );
      debugPrint(
        '[MapControllerNew] Setting up native clustering for ${memories.length} memories',
      );

      // First, create our own clusters for tap detection
      await _createClustersAndUpdateMarkers(memories);

      // Clear existing sources and layers
      await _clearMapboxClusteringLayers();

      // Add a small delay to ensure cleanup is complete
      await Future.delayed(const Duration(milliseconds: 100));
      debugPrint('[MapControllerNew] Cleanup complete, proceeding with setup');

      // Convert memories to GeoJSON
      final geoJsonString = MemoryGeoJsonService.createGeoJsonFromMemories(
        memories,
      );
      debugPrint(
        '[MapControllerNew] Created GeoJSON with ${memories.length} memory features',
      );

      // Add GeoJSON source with clustering enabled
      debugPrint('[MapControllerNew] Adding GeoJSON source: $MEMORY_SOURCE_ID');
      try {
        await mapboxMap!.style.addSource(
          mapbox.GeoJsonSource(
            id: MEMORY_SOURCE_ID,
            data: geoJsonString,
            cluster: true,
            clusterMaxZoom: MapboxZoomHelper().clusterMaxZoom.value, // Max zoom to cluster points on
            clusterRadius:
                50, // Radius of each cluster when clustering points (pixels)
            clusterMinPoints: 2, // Minimum points to form a cluster
          ),
        );
        debugPrint(
          '[MapControllerNew] ✅ Successfully added GeoJSON source with clustering enabled',
        );
      } catch (e) {
        if (e.toString().contains('already exists')) {
          debugPrint(
            '[MapControllerNew] ⚠️  Source already exists, attempting to update data instead',
          );
          try {
            // Try to update the existing source data instead of adding a new one
            await mapboxMap!.style.setStyleSourceProperty(
              MEMORY_SOURCE_ID,
              'data',
              geoJsonString,
            );
            debugPrint(
              '[MapControllerNew] ✅ Successfully updated existing GeoJSON source data',
            );
          } catch (updateError) {
            debugPrint(
              '[MapControllerNew] ❌ Failed to update source data: $updateError',
            );
            // If update fails, force remove and re-add
            await _forceRemoveAndReaddSource(geoJsonString);
          }
        } else {
          debugPrint('[MapControllerNew] ❌ Failed to add GeoJSON source: $e');
          throw e; // Re-throw to be caught by outer try-catch
        }
      }

      // Add cluster layers
      await _addClusterLayers();
      debugPrint('[MapControllerNew] Added cluster layers');

      // Setup click handlers
      await _setupNativeClusterClickHandlers();
      debugPrint('[MapControllerNew] Setup cluster click handlers');

      // Initialize MapMarkerService with MapBox map before arrow generation
      if (_mapMarkerService != null) {
        _mapMarkerService!.initialize(mapboxMap!);
        debugPrint(
          '[MapControllerNew] MapMarkerService initialized for native clustering',
        );
      }

      // Generate and display chronological arrows
      await _generateAndDisplayArrowsFromMemories(memories);
      debugPrint(
        '[MapControllerNew] Generated and displayed chronological arrows',
      );

      debugPrint(
        '[MapControllerNew] ========== MAPBOX NATIVE CLUSTERING SETUP COMPLETE ==========',
      );
    } catch (e) {
      debugPrint('[MapControllerNew] Error setting up MapBox clustering: $e');
    }
  }

  /// Calculate and set optimal zoom level based on memory locations (matching old controller)
  Future<void> _setOptimalZoomForMemories(
    List<Map<String, dynamic>> memories,
  ) async {
    if (memories.isEmpty || mapboxMap == null) {
      debugPrint(
        '[MapControllerNew] Cannot set zoom - no memories or map not ready',
      );
      return;
    }

    try {
      // Extract coordinates from memories
      double minLat = double.infinity;
      double maxLat = double.negativeInfinity;
      double minLng = double.infinity;
      double maxLng = double.negativeInfinity;
      int validLocationCount = 0;

      for (final memory in memories) {
        final lat = memory['latitude'] as double?;
        final lng = memory['longitude'] as double?;

        if (lat != null && lng != null && lat.isFinite && lng.isFinite) {
          minLat = lat < minLat ? lat : minLat;
          maxLat = lat > maxLat ? lat : maxLat;
          minLng = lng < minLng ? lng : minLng;
          maxLng = lng > maxLng ? lng : maxLng;
          validLocationCount++;
        }
      }

      // Check if we have any valid locations
      if (validLocationCount == 0) {
        debugPrint('[MapControllerNew] ⚠️ No memories with valid location data found');
        final defaultZoom = MapboxZoomHelper().defaultZoom.value;
        debugPrint('[MapControllerNew] 📊 Using default zoom level: $defaultZoom');
        currentZoom.value = defaultZoom;
        return;
      }

      // Calculate the spread (matching old controller logic)
      final double latDiff = maxLat - minLat;
      final double lngDiff = maxLng - minLng;
      final double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

      // Get zoom level based on geographical spread from MapboxZoomHelper
      double zoom = MapboxZoomHelper().getZoomForSpread(maxDiff);

      // Update current zoom variable
      currentZoom.value = zoom;

      debugPrint('[MapControllerNew] 📊 Memory spread analysis:');
      debugPrint('[MapControllerNew] - Total memories: ${memories.length}');
      debugPrint('[MapControllerNew] - Valid locations: $validLocationCount');
      debugPrint(
        '[MapControllerNew] - Lat range: $minLat to $maxLat (diff: $latDiff)',
      );
      debugPrint(
        '[MapControllerNew] - Lng range: $minLng to $maxLng (diff: $lngDiff)',
      );
      debugPrint('[MapControllerNew] - Max diff: $maxDiff');
      debugPrint('[MapControllerNew] - Calculated zoom: $zoom');

      // Set camera to fit bounds with calculated zoom
      await mapboxMap!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              (minLng + maxLng) / 2,
              (minLat + maxLat) / 2,
            ),
          ),
          zoom: zoom,
          bearing: 0,
          pitch: 0,
        ),
        mapbox.MapAnimationOptions(duration: 1500),
      );

      debugPrint('[MapControllerNew] ✅ Optimal zoom level set to: $zoom');
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error calculating optimal zoom: $e');
    }
  }

  /// Create clusters from memories and update map markers
  Future<void> _createClustersAndUpdateMarkers(
    List<Map<String, dynamic>> memories,
  ) async {
    if (_clusterRepository == null || _mapMarkerService == null) {
      debugPrint('[MapControllerNew] Clustering services not initialized');
      return;
    }

    try {
      // Get current zoom level for dynamic clustering
      double? zoomLevel;
      if (mapboxMap != null) {
        try {
          final cameraState = await mapboxMap!.getCameraState();
          zoomLevel = cameraState.zoom;
        } catch (e) {
          debugPrint('[MapControllerNew] Could not get zoom level: $e');
        }
      }

      // Create clusters
      final clusteringResult = await _clusterRepository!.createClusters(
        memories,
        zoomLevel: zoomLevel,
      );

      debugPrint(
        '[MapControllerNew] Clustering complete: ${clusteringResult.clusters.length} clusters, ${clusteringResult.individualMemories.length} individual',
      );

      // Store clusters for arrow generation and tap detection
      currentClusters.assignAll(clusteringResult.clusters);
      debugPrint(
        '[MapControllerNew] 📊 Stored ${currentClusters.length} clusters for tap detection',
      );

      // Initialize map marker service with MapBox map BEFORE arrow generation
      if (mapboxMap != null) {
        _mapMarkerService!.initialize(mapboxMap!);
        debugPrint(
          '[MapControllerNew] MapMarkerService initialized with MapBox map',
        );
      }

      // Generate and display chronological arrows
      await _generateAndDisplayArrows(
        clusteringResult.clusters,
        clusteringResult.individualMemories,
      );

      // Debug clustering results
      debugPrint('[MapControllerNew] Clustering results:');
      debugPrint('  - Clusters: ${clusteringResult.clusters.length}');
      debugPrint(
        '  - Individual memories: ${clusteringResult.individualMemories.length}',
      );

      // Log some individual memories for debugging
      for (
        int i = 0;
        i < math.min(3, clusteringResult.individualMemories.length);
        i++
      ) {
        final memory = clusteringResult.individualMemories[i];
        debugPrint(
          '  - Individual memory ${i + 1}: ID=${memory['id']}, lat=${memory['location_latitude']}, lng=${memory['location_longitude']}',
        );
      }

      // Update markers on the map
      await _mapMarkerService!.updateMarkers(
        clusters: clusteringResult.clusters,
        individualMemories: clusteringResult.individualMemories,
      );

      // Set up marker tap callbacks
      _setupMarkerCallbacks();

      debugPrint('[MapControllerNew] Map markers updated successfully');
    } catch (e) {
      debugPrint(
        '[MapControllerNew] Error creating clusters and updating markers: $e',
      );
      Get.snackbar(
        'Clustering Error',
        'Failed to create memory clusters: $e',
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
    }
  }

  /// Setup marker tap callbacks
  void _setupMarkerCallbacks() {
    if (_mapMarkerService == null) return;

    _mapMarkerService!.setCallbacks(
      
      onClusterTap: (cluster) {
        debugPrint(
          '[MapControllerNew] Cluster tapped: ${cluster.id} (${cluster.count} memories)',
        );
        _handleClusterTap(cluster);
      },
      onMemoryTap: (memory) {
        debugPrint('[MapControllerNew] Memory tapped: ${memory['id']}');
        _handleMemoryTap(memory);
      },
    );
  }

Timer? _tapDelayTimer;
String? _pendingTapType; // "cluster" or "memory"
dynamic _pendingTapData;

/// Called when cluster is tapped
void onClusterTap(cluster) {
  debugPrint('[MapControllerNew] Cluster tapped: ${cluster.id} (${cluster.count} memories)');

  // If memory tap is pending -> override it
  if (_pendingTapType == 'memory') {
    debugPrint('[MapControllerNew] Cluster tap overrides pending memory tap');
    _tapDelayTimer?.cancel();
    _handleClusterTap(cluster);
    _resetTapState();
    return;
  }

  // Otherwise, schedule cluster tap
  _scheduleTap('cluster', cluster);
}

/// Called when memory is tapped
void onMemoryTap(memory) {
  debugPrint('[MapControllerNew] Memory tapped: ${memory['id']}');

  // If cluster tap is pending -> override it
  if (_pendingTapType == 'cluster') {
    debugPrint('[MapControllerNew] Memory tap overrides pending cluster tap');
    _tapDelayTimer?.cancel();
    _handleMemoryTap(memory);
    _resetTapState();
    return;
  }

  // Otherwise, schedule memory tap
  _scheduleTap('memory', memory);
}

/// Helper to schedule a delayed tap
void _scheduleTap(String type, dynamic data) {
  _pendingTapType = type;
  _pendingTapData = data;

  _tapDelayTimer?.cancel();
  _tapDelayTimer = Timer(const Duration(seconds: 1), () {
    if (_pendingTapType == 'cluster') {
      _handleClusterTap(_pendingTapData);
    } else if (_pendingTapType == 'memory') {
      _handleMemoryTap(_pendingTapData);
    }
    _resetTapState();
  });
}

/// Reset the tap state after execution
void _resetTapState() {
  _pendingTapType = null;
  _pendingTapData = null;
  _tapDelayTimer?.cancel();
  _tapDelayTimer = null;
}

  /// Handle cluster tap - similar to _onClusterMarkerTapped in old controller
  Future<void> _handleClusterTap(models.MemoryCluster cluster) async {
    debugPrint(
      '[MapControllerNew] Handling cluster tap: ${cluster.id}, count: ${cluster.count}',
    );
    debugPrint(
      '[MapControllerNew] Cluster memories length: ${cluster.memories.length}',
    );
    debugPrint(
      '[MapControllerNew] Cluster location: ${cluster.latitude}, ${cluster.longitude}',
    );

    try {
      // Validate cluster has memories
      if (cluster.memories.isEmpty) {
        debugPrint(
          '[MapControllerNew] ⚠️ Cluster has no memories, count: ${cluster.count}',
        );

        // For MapBox native clustering, we might have a count but empty memories list
        // In this case, try to show a fallback error or handle it differently
        Get.snackbar(
          'Error',
          'No memory data available for this location. This might be a clustering issue.',
          backgroundColor: Colors.orange.withValues(alpha: 0.8),
          colorText: Colors.white,
        duration: const Duration(seconds: 2),

        );
        return;
      }

      if (cluster.count == 1 && cluster.memories.isNotEmpty) {
        // Single memory marker - navigate to ADD_MEMORIES route
        debugPrint(
          '[MapControllerNew] Single memory tap - navigating to ADD_MEMORIES',
        );
        debugPrint('[MapControllerNew] Memory data: ${cluster.memories.first}');

        try {
          // AddMemoriesController is initialized in main.dart as permanent singleton
          final controller = Get.find<AddMemoriesController>();

          final normalizedMemory = _normalizeMemoryForNavigation(
            cluster.memories.first,
          );
          final memoryLocation = clustering.MemoryLocation.fromMap(
            normalizedMemory,
          );
          controller.showSpecificMemories([memoryLocation]);

          var result = await Get.toNamed(Routes.ADD_MEMORIES);
          debugPrint('[MapControllerNew] Navigation result: $result');

          if (result == true) {
            debugPrint('[MapControllerNew] Result = true');
            await clearAllLines();
            controller.onAgainInit();
          }
        } catch (memoryError) {
          debugPrint(
            '[MapControllerNew] Error processing single memory: $memoryError',
          );
          debugPrint(
            '[MapControllerNew] Memory data that failed: ${cluster.memories.first}',
          );
          Get.snackbar(
            'Error',
            'Failed to load memory data: ${memoryError.toString()}',
            backgroundColor: Colors.red.withValues(alpha: 0.8),
            colorText: Colors.white,        duration: const Duration(seconds: 2),

          );
        }
      } else if (cluster.count > 1) {
        // Cluster marker with multiple memories - drill down
        debugPrint(
          '[MapControllerNew] Multi-memory cluster (${cluster.count} memories) - showing details panel',
        );
        await _drillDownToCluster(cluster.memories);
      } else {
        // Edge case: count is 1 but no memories, or other unexpected state
        debugPrint(
          '[MapControllerNew] ⚠️ Unexpected cluster state - count: ${cluster.count}, memories: ${cluster.memories.length}',
        );
        Get.snackbar(
          'Info',
          'This location doesn\'t have accessible memory data (count: ${cluster.count})',
          backgroundColor: Colors.blue.withValues(alpha: 0.8),
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
      }
    } catch (e) {
      debugPrint('[MapControllerNew] Error handling cluster tap: $e');
      debugPrint('[MapControllerNew] Stack trace: ${StackTrace.current}');
      debugPrint(
        '[MapControllerNew] Cluster details - count: ${cluster.count}, memories length: ${cluster.memories.length}',
      );

      // Show user-friendly error
      Get.snackbar(
        'Error',
        'Failed to open memory details. Please try again.',
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// Drill down to cluster memories - show bottom panel with cluster details
  Future<void> _drillDownToCluster(
    List<Map<String, dynamic>> clusterMemories,
  ) async {
    try {
      debugPrint(
        '[MapControllerNew] 🔍 DRILL DOWN - Starting drill down for ${clusterMemories.length} memories',
      );

      // Validate we have memories to process
      if (clusterMemories.isEmpty) {
        debugPrint('[MapControllerNew] ⚠️ No memories to drill down into');
        Get.snackbar(
          'Error',
          'No memories found in this cluster',
          backgroundColor: Colors.red.withValues(alpha: 0.8),
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
        return;
      }

      if (_isBottomPanelOpen) {
        debugPrint(
          '[MapControllerNew] 🔁 Bottom panel already open, skipping new presentation',
        );
        return;
      }

      final normalizedMemories =
          clusterMemories.map(_normalizeMemoryForNavigation).toList();

      // Calculate center for the cluster
      double totalLat = 0;
      double totalLng = 0;
      int validCoordinates = 0;

      for (final memory in normalizedMemories) {
        final lat = _extractLatitude(memory);
        final lng = _extractLongitude(memory);
        if (lat != null && lng != null) {
          totalLat += lat;
          totalLng += lng;
          validCoordinates++;
        }
      }

      if (validCoordinates == 0) {
        debugPrint(
          '[MapControllerNew] ⚠️ No valid coordinates found in cluster memories',
        );
        Get.snackbar(
          'Error',
          'No valid location data found for these memories',
          backgroundColor: Colors.red.withValues(alpha: 0.8),
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
        return;
      }

      final centerLat = totalLat / validCoordinates;
      final centerLng = totalLng / validCoordinates;

      // Create a MemoryCluster object for the bottom panel (using clustering service MemoryCluster)
      final memoryLocations = <clustering.MemoryLocation>[];
      for (final memory in normalizedMemories) {
        try {
          final memoryLocation = clustering.MemoryLocation.fromMap(memory);
          memoryLocations.add(memoryLocation);
        } catch (e) {
          debugPrint(
            '[MapControllerNew] ⚠️ Failed to create MemoryLocation from: ${memory['id']} - $e',
          );
          // Continue with other memories
        }
      }

      if (memoryLocations.isEmpty) {
        debugPrint(
          '[MapControllerNew] ⚠️ No valid MemoryLocation objects created',
        );
        Get.snackbar(
          'Error',
          'Failed to process memory data',
          backgroundColor: Colors.red.withValues(alpha: 0.8),
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
        return;
      }

      final memoryCluster = clustering.MemoryCluster(
        id: 'cluster_${DateTime.now().millisecondsSinceEpoch}',
        memories: memoryLocations,
        centerLatitude: centerLat,
        centerLongitude: centerLng,
        radiusKm: 0.5, // Default radius for cluster
      );

      // Show bottom panel with cluster memories (like the old controller)
      showLocationBottomPanel(
        Get.context!,
        memoryCluster,
        specificMemories: normalizedMemories,
      );

      debugPrint(
        '[MapControllerNew] 🔍 DRILL DOWN - Showing bottom panel with cluster details',
      );
    } catch (e) {
      debugPrint(
        '[MapControllerNew] ❌ DRILL DOWN - Error during drill down: $e',
      );

      // Show user-friendly error
      Get.snackbar(
        'Error',
        'Failed to show cluster details: ${e.toString()}',
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
    }
  }

  /// Show location bottom panel - similar to showLocationBottomPanel in old controller
  void showLocationBottomPanel(
    BuildContext context,
    clustering.MemoryCluster cluster, {
    List<Map<String, dynamic>>? specificMemories,
  }) {
    if (_isBottomPanelOpen) {
      debugPrint(
        '[MapControllerNew] 🔁 Bottom panel already open, ignoring subsequent request',
      );
      return;
    }

    _isBottomPanelOpen = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BottomPanel(cluster, specificMemories: specificMemories),
    ).whenComplete(() {
      _isBottomPanelOpen = false;
      debugPrint('[MapControllerNew] Bottom panel closed');
    });
  }

  /// Handle memory tap - similar to _onDrillDownMarkerTapped in old controller
  Future<void> _handleMemoryTap(Map<String, dynamic> memory) async {
    debugPrint('[MapControllerNew] Handling memory tap: ${memory['id']}');

    try {
      // Validate memory data
      if (memory.isEmpty) {
        debugPrint('[MapControllerNew] ⚠️ Empty memory data received');
        Get.snackbar(
          'Error',
          'Invalid memory data',
          backgroundColor: Colors.red.withValues(alpha: 0.8),
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
        return;
      }

      final normalizedMemory = _normalizeMemoryForNavigation(memory);
      final lat = _extractLatitude(normalizedMemory);
      final lng = _extractLongitude(normalizedMemory);

      // Detailed memory information logging (matching old controller style)
      debugPrint(
        '[MapControllerNew] 🎯 SINGLE MARKER TAPPED - Detailed Information:',
      );
      debugPrint('  📍 Location: ${lat ?? 'Unknown'}, ${lng ?? 'Unknown'}');
      debugPrint('  🆔 Memory ID: ${normalizedMemory['id']}');
      debugPrint('  📅 Date: ${normalizedMemory['memory_date']}');
      debugPrint('  📝 Title: ${normalizedMemory['title'] ?? 'No title'}');
      debugPrint(
        '  📄 Description: ${normalizedMemory['description'] ?? 'No description'}',
      );
      debugPrint(
        '  📂 Category: ${normalizedMemory['category'] ?? 'No category'}',
      );
      debugPrint('  🏷️ Tags: ${normalizedMemory['tags'] ?? 'No tags'}');
      debugPrint(
        '  📱 Created At: ${normalizedMemory['created_at'] ?? 'Unknown'}',
      );
      debugPrint(
        '  🔄 Updated At: ${normalizedMemory['updated_at'] ?? 'Unknown'}',
      );
      debugPrint(
        '  🗺️ Location String: ${normalizedMemory['location'] ?? 'No location string'}',
      );
      debugPrint(
        '  📸 Has Images: ${normalizedMemory['images']?.isNotEmpty ?? false}',
      );
      debugPrint(
        '  🎵 Has Audio: ${normalizedMemory['audio_path']?.isNotEmpty ?? false}',
      );

      // AddMemoriesController is initialized in main.dart as permanent singleton
      final controller = Get.find<AddMemoriesController>();

      final memoryLocation = clustering.MemoryLocation.fromMap(
        normalizedMemory,
      );
      controller.isOpenedFromMap = true;
      controller.showSpecificMemories([memoryLocation]);

      final result = await Get.to(
        () =>  AddMemoriesView(),
        transition: Transition.rightToLeft,
      );
      debugPrint('[MapControllerNew] Navigation result: $result');

      if (result == true) {
        debugPrint('[MapControllerNew] Result = true');
        await clearAllLines();
        // Clear all markers and re-initialize memory clustering (matching old controller pattern)
        await refreshMapView();
      }
    } catch (e) {
      debugPrint('[MapControllerNew] Error navigating to ADD_MEMORIES: $e');
      debugPrint('[MapControllerNew] Memory data: ${memory.toString()}');

      // Show user-friendly error
      Get.snackbar(
        'Error',
        'Failed to open memory: ${e.toString()}',
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
    }
  }

  /// Toggle filter overlay
  void toggleFilter() {
    isFilterOpen.value = !isFilterOpen.value;
    debugPrint('[MapControllerNew] Filter toggled: ${isFilterOpen.value}');
  }

  /// Open filter overlay
  void openFilter() {
    isFilterOpen.value = true;
    debugPrint('[MapControllerNew] Filter opened');
  }

  /// Close filter overlay
  void closeFilter() {
    isFilterOpen.value = false;
    debugPrint('[MapControllerNew] Filter closed');
  }

  /// Load filter data for dropdowns
  Future<void> loadFilterData() async {
    try {
      // Try to use MemoryController's data if available
      try {
        final memoryController = Get.find<MemoryController>();

        // Use the same data as memory view popups
        availableHashtags.value = List.from(memoryController.existingTags);
        availableContacts.value = List.from(memoryController.existingMentions);
        availableCategories.value = List.from(
          memoryController.existingCategories,
        );

        debugPrint(
          '[MapControllerNew] Using MemoryController data - ${availableHashtags.length} hashtags, ${availableContacts.length} contacts, ${availableCategories.length} categories',
        );
      } catch (e) {
        debugPrint(
          '[MapControllerNew] MemoryController not available, loading from database: $e',
        );

        // Fallback to direct database access
        final databaseHelper = DatabaseHelper.instance;
        final hashtags = await databaseHelper.getPopularTags(limit: 100);
        availableHashtags.value = hashtags;

        final contacts = await databaseHelper.getPopularMentions(limit: 100);
        availableContacts.value = contacts;

        final categories = await databaseHelper.getPopularCategories(
          limit: 100,
        );
        availableCategories.value = categories;

        debugPrint(
          '[MapControllerNew] Loaded from database - ${hashtags.length} hashtags, ${contacts.length} contacts, ${categories.length} categories',
        );
      }

      debugPrint('[MapControllerNew] Filter data loaded successfully');
    } catch (e) {
      debugPrint('[MapControllerNew] Error loading filter data: $e');
    }
  }

  /// Handle text changes for filters
  void onTextChanged(String hint, String value) {
    if (value.contains('@')) {
      debugPrint("[MapControllerNew] Mention trigger from [$hint]: $value");
    } else if (value.contains('#')) {
      debugPrint("[MapControllerNew] Tag trigger from [$hint]: $value");
    }
    _setFilterValue(hint, value);
  }

  /// Set filter date
  void setFilterDate(String hint, String date) {
    _setFilterValue(hint, date);
    debugPrint("[MapControllerNew] Filter date set: $hint = $date");
  }

  String _normalizeFilterKey(String hint) => hint.trim().toLowerCase();

  void _setFilterValue(String hint, String? value) {
    final key = _normalizeFilterKey(hint);

    if (value == null || value.isEmpty) {
      filterValues.remove(key);
    } else {
      filterValues[key] = value;
    }

    _updateFilterStatus();
  }

  /// Set location for filtering
  void setLocation(String location) {
    selectedLocation.value = location;
    _updateFilterStatus();
    debugPrint("[MapControllerNew] Location set to: $location");

    // Show hint if location is set but radius is empty
    if (location.isNotEmpty && selectedRadius.value.isEmpty) {
      Get.snackbar(
        'Hint',
        'Don\'t forget to set the radius for location-based filtering',
        backgroundColor: Colors.orange.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// Set enhanced location data
  void setEnhancedLocationData(Map<String, dynamic> locationData) {
    // Check if latitude and longitude are provided
    var locationLatitude = locationData['latitude']?.toDouble();
    var locationLongitude = locationData['longitude']?.toDouble();

    if (locationLatitude != null && locationLongitude != null) {
      // Format to 4 decimal places
      final formattedLat = locationLatitude.toStringAsFixed(4);
      final formattedLng = locationLongitude.toStringAsFixed(4);
      selectedLocation.value = '$formattedLat,$formattedLng';
      _updateFilterStatus();
      debugPrint(
        "[MapControllerNew] Enhanced location set: $formattedLat,$formattedLng",
      );
    } else if (locationData.containsKey('address')) {
      selectedLocation.value = locationData['address'];
      _updateFilterStatus();
      debugPrint(
        "[MapControllerNew] Enhanced location set: ${locationData['address']}",
      );
    }
  }

  /// Update filter status
  void _updateFilterStatus() {
    hasActiveFilters.value =
        filterValues.isNotEmpty ||
        selectedLocation.value.isNotEmpty ||
        selectedRadius.value.isNotEmpty ||
        selectedHashtags.isNotEmpty ||
        selectedContacts.isNotEmpty ||
        selectedCategories.isNotEmpty;

    debugPrint(
      '[MapControllerNew] Filter status updated: hasActiveFilters=${hasActiveFilters.value}',
    );
  }

  AddMemoriesController? _getAddMemoriesControllerOrNull() {
    if (!Get.isRegistered<AddMemoriesController>()) {
      return null;
    }
    try {
      return Get.find<AddMemoriesController>();
    } catch (_) {
      return null;
    }
  }

  void _syncFiltersToAddMemoriesController({bool applyFilters = false}) {
    final addMemoriesController = _getAddMemoriesControllerOrNull();
    if (addMemoriesController == null) {
      return;
    }

    addMemoriesController.isOpenedFromMap = true;
    addMemoriesController.filterValues
      ..clear()
      ..addAll(filterValues);
    addMemoriesController.selectedLocation.value = selectedLocation.value;
    addMemoriesController.selectedRadius.value = selectedRadius.value;
    addMemoriesController.selectedHashtags
      ..clear()
      ..addAll(selectedHashtags);
    addMemoriesController.selectedContacts
      ..clear()
      ..addAll(selectedContacts);
    addMemoriesController.selectedCategories
      ..clear()
      ..addAll(selectedCategories);
    addMemoriesController.updateFilterStatus();

    if (applyFilters) {
      addMemoriesController.applyFilters();
    }
  }

  void _syncFiltersFromAddMemoriesController(AddMemoriesController controller) {
    filterValues
      ..clear()
      ..addAll(controller.filterValues);
    selectedLocation.value = controller.selectedLocation.value;
    selectedRadius.value = controller.selectedRadius.value;
    selectedHashtags
      ..clear()
      ..addAll(controller.selectedHashtags);
    selectedContacts
      ..clear()
      ..addAll(controller.selectedContacts);
    selectedCategories
      ..clear()
      ..addAll(controller.selectedCategories);
    _updateFilterStatus();
  }

  /// Apply filters and refresh the map view
  Future<void> applyFilters() async {
    // Validate location and radius dependency
    final hasLocation = selectedLocation.value.isNotEmpty;
    final hasRadius = selectedRadius.value.isNotEmpty;

    if (hasLocation && !hasRadius) {
      Get.snackbar(
        'Validation Error',
        'Radius is required when location is selected',
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    if (hasRadius && !hasLocation) {
      Get.snackbar(
        'Validation Error',
        'Location is required when radius is specified',
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    // Check if any filters are active
    final hasFilters =
        filterValues.isNotEmpty ||
        selectedLocation.value.isNotEmpty ||
        selectedRadius.value.isNotEmpty ||
        selectedHashtags.isNotEmpty ||
        selectedContacts.isNotEmpty ||
        selectedCategories.isNotEmpty;

    debugPrint('[MapControllerNew] === APPLYING FILTERS - REFRESHING MAP ===');
    debugPrint('[MapControllerNew] Filter values: ${filterValues.toString()}');
    debugPrint(
      '[MapControllerNew] Selected location: "${selectedLocation.value}"',
    );
    debugPrint('[MapControllerNew] Selected radius: "${selectedRadius.value}"');
    debugPrint(
      '[MapControllerNew] Selected hashtags: ${selectedHashtags.toString()}',
    );
    debugPrint(
      '[MapControllerNew] Selected contacts: ${selectedContacts.toString()}',
    );
    debugPrint(
      '[MapControllerNew] Selected categories: ${selectedCategories.toString()}',
    );
    debugPrint('[MapControllerNew] Has filters: $hasFilters');

    // Sync filter selections to AddMemoriesController so list view stays in sync
    _syncFiltersToAddMemoriesController(applyFilters: true);

    // Close filter overlay and refresh filter status
    closeFilter();
    _updateFilterStatus();

    await _applyFiltersAndReloadMap();
  }

  /// Sync filter values from AddMemoriesController and apply them
  Future<void> applyFiltersFromAddMemoriesController() async {
    try {
      final addMemoriesController = _getAddMemoriesControllerOrNull();
      if (addMemoriesController == null) {
        debugPrint(
          '[MapControllerNew] AddMemoriesController not registered; cannot apply shared filters',
        );
        await _applyFiltersAndReloadMap();
        return;
      }

      _syncFiltersFromAddMemoriesController(addMemoriesController);
      closeFilter();

      await _applyFiltersAndReloadMap();
    } catch (e) {
      debugPrint(
        '[MapControllerNew] Failed to apply filters from AddMemoriesController: $e',
      );
    }
  }

  /// Handle filter apply action when overlay is launched from the map
  Future<void> handleFilterApplyFromMap() async {
    // AddMemoriesController is initialized in main.dart as permanent singleton
    final addMemoriesController = Get.find<AddMemoriesController>();

    addMemoriesController.isOpenedFromMap = true;
    addMemoriesController.applyFilters();
    _syncFiltersFromAddMemoriesController(addMemoriesController);

    closeFilter();
    _updateFilterStatus();

    await _applyFiltersAndReloadMap();

    final result = await Get.to(() => AddMemoriesView());
    if (result == true) {
      await refreshMapView();
    }
  }

  /// Reset all filters
  void resetFilters() {
    final addMemoriesController = _getAddMemoriesControllerOrNull();
    addMemoriesController?.isOpenedFromMap = true;
    addMemoriesController?.resetFilters();

    filterValues.clear();
    selectedLocation.value = '';
    selectedRadius.value = '';
    selectedHashtags.clear();
    selectedContacts.clear();
    selectedCategories.clear();
    _updateFilterStatus();
    closeFilter();
    hasActiveFilters.value = false;
    _applyFiltersAndReloadMap();
  }

  /// Apply filters and reload map with filtered memories
  Future<void> _applyFiltersAndReloadMap() async {
    try {
      debugPrint('[MapControllerNew] Applying filters and reloading map...');

      final addMemoriesController = _getAddMemoriesControllerOrNull();
      final bool filtersActive = hasActiveFilters.value;
      List<Map<String, dynamic>> memoriesToDisplay = [];

      if (addMemoriesController != null) {
        if (addMemoriesController.hasActiveFilters.value) {
          memoriesToDisplay = List<Map<String, dynamic>>.from(
            addMemoriesController.filteredMemories,
          );
        } else if (addMemoriesController.filteredMemories.isNotEmpty) {
          memoriesToDisplay = List<Map<String, dynamic>>.from(
            addMemoriesController.filteredMemories,
          );
        }
      }

      if (memoriesToDisplay.isEmpty) {
        if (addMemoriesController != null &&
            addMemoriesController.hasActiveFilters.value) {
          debugPrint(
            '[MapControllerNew] No memories matched active filters; clearing map markers',
          );
          await _setupMapboxClustering([]);
          return;
        }

        final allMemories = await _memoryRepository?.loadAllMemories();
        if (allMemories == null) {
          debugPrint('[MapControllerNew] No memories available for filtering');
          await _setupMapboxClustering([]);
          return;
        }

        if (filtersActive) {
          memoriesToDisplay = allMemories.where(_matchesFilters).toList();
        } else {
          memoriesToDisplay = List<Map<String, dynamic>>.from(allMemories);
        }
      }

      debugPrint(
        '[MapControllerNew] Preparing ${memoriesToDisplay.length} memories for clustering (filtersActive=$filtersActive)',
      );

      await _setupMapboxClustering(memoriesToDisplay);
    } catch (e) {
      debugPrint('[MapControllerNew] Error applying filters: $e');
      // Fallback to loading all memories
      loadMemoriesFromDB();
    }
  }

  bool _matchesFilters(Map<String, dynamic> memory) {
    // Text filters
    if (filterValues.isNotEmpty) {
      final searchableText =
          StringBuffer()
            ..write((memory['text'] ?? '').toString().toLowerCase())
            ..write(' ')
            ..write((memory['description'] ?? '').toString().toLowerCase())
            ..write(' ')
            ..write((memory['title'] ?? '').toString().toLowerCase());

      final combinedText = searchableText.toString();
      for (final value in filterValues.values) {
        final query = value.toLowerCase();
        if (query.isEmpty) continue;
        if (!combinedText.contains(query)) {
          return false;
        }
      }
    }

    // Hashtag filters
    if (selectedHashtags.isNotEmpty) {
      final rawHashtags = (memory['hashtags'] ?? memory['tags']) ?? [];
      final hashtagsList = _extractStringList(rawHashtags);
      final normalizedHashtags =
          hashtagsList
              .map((tag) => tag.replaceFirst('#', '').toLowerCase().trim())
              .toSet();

      for (final tag in selectedHashtags) {
        final cleaned = tag.replaceFirst('#', '').toLowerCase().trim();
        if (!normalizedHashtags.contains(cleaned)) {
          return false;
        }
      }
    }

    // Contact filters
    if (selectedContacts.isNotEmpty) {
      final rawContacts = memory['contacts'] ?? memory['tagged_contacts'] ?? [];
      final contactsList = _extractStringList(rawContacts);
      final normalizedContacts =
          contactsList
              .map(
                (contact) => contact.replaceFirst('@', '').toLowerCase().trim(),
              )
              .toSet();

      for (final contact in selectedContacts) {
        final cleaned = contact.replaceFirst('@', '').toLowerCase().trim();
        if (!normalizedContacts.contains(cleaned)) {
          return false;
        }
      }
    }

    // Category filters
    if (selectedCategories.isNotEmpty) {
      final rawCategories = memory['categories'] ?? [];
      final categoriesList = _extractStringList(rawCategories);
      final normalizedCategories =
          categoriesList
              .map((category) => category.toLowerCase().trim())
              .toSet();

      for (final category in selectedCategories) {
        if (!normalizedCategories.contains(category.toLowerCase().trim())) {
          return false;
        }
      }
    }

    // Location + radius filter
    if (selectedLocation.value.isNotEmpty && selectedRadius.value.isNotEmpty) {
      final radius = double.tryParse(selectedRadius.value);
      if (radius != null) {
        final locationParts = selectedLocation.value.split(',');
        if (locationParts.length == 2) {
          final filterLat = double.tryParse(locationParts[0].trim());
          final filterLng = double.tryParse(locationParts[1].trim());

          if (filterLat != null && filterLng != null) {
            final memoryLat = _toDouble(memory['location_latitude']);
            final memoryLng = _toDouble(memory['location_longitude']);

            if (memoryLat != null && memoryLng != null) {
              final distance = _calculateDistance(
                filterLat,
                filterLng,
                memoryLat,
                memoryLng,
              );
              if (distance > radius) {
                return false;
              }
            }
          }
        }
      }
    }

    return true;
  }

  double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  double? _extractLatitude(Map<String, dynamic> memory) {
    return _toDouble(memory['location_latitude']) ??
        _toDouble(memory['latitude']);
  }

  double? _extractLongitude(Map<String, dynamic> memory) {
    return _toDouble(memory['location_longitude']) ??
        _toDouble(memory['longitude']);
  }

  Map<String, dynamic> _normalizeMemoryForNavigation(
    Map<String, dynamic> memory,
  ) {
    final normalized = Map<String, dynamic>.from(memory);

    final lat = _extractLatitude(normalized);
    final lng = _extractLongitude(normalized);

    final locationString = normalized['location']?.toString().trim() ?? '';
    if ((locationString.isEmpty) && lat != null && lng != null) {
      normalized['location'] = '$lat,$lng';
    }

    // Ensure both date formats are populated for consumers expecting either key
    final memoryDate = normalized['memory_date'];
    final date = normalized['date'];
    if (memoryDate == null && date != null) {
      normalized['memory_date'] = date;
    } else if (date == null && memoryDate != null) {
      normalized['date'] = memoryDate;
    }

    return normalized;
  }

  List<String> _extractStringList(dynamic source, {String separator = ','}) {
    if (source is Iterable) {
      return source
          .map((item) => item == null ? '' : item.toString())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (source is String && source.isNotEmpty) {
      return source
          .split(separator)
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  /// Get available hashtags for filtering
  List<String> get getAvailableHashtags => availableHashtags.toList();

  /// Get available contacts for filtering
  List<String> get getAvailableContacts => availableContacts.toList();

  /// Get available categories for filtering
  List<String> get getAvailableCategories => availableCategories.toList();

  /// Set radius for location filtering (used by MemoriesFilterTextFieldRow)
  void setRadius(String radius) {
    selectedRadius.value = radius;
    _updateFilterStatus();
    debugPrint("[MapControllerNew] Radius set to: $radius");
  }

  /// Request focus on radius field (used by MemoriesFilterTextFieldRow)
  void requestRadiusFieldFocus() {
    // This is used by the filter field to request focus after location is set
    // For now, we'll just log it since we don't have a focus node in this controller
    debugPrint("[MapControllerNew] Radius field focus requested");
  }

  /// Check if opened from map (used by filter widgets)
  bool isOpenedFromMap = false;

  /// Focus request for radius field (used by MemoriesFilterTextFieldRow)
  final RxBool shouldFocusRadiusField = false.obs;

  /// Calculate optimal zoom level based on memory distribution
  Future<void> _calculateOptimalZoom() async {
    if (mapboxMap == null || _currentMemories.isEmpty) {
      debugPrint('[MapControllerNew] ⚠️ Cannot calculate zoom - no map or memories');
      return;
    }

    try {
      // Initialize bounds with first valid memory location
      double? minLat, maxLat, minLng, maxLng;
      int validLocationCount = 0;

      for (final memory in _currentMemories) {
        final lat = _extractLatitude(memory);
        final lng = _extractLongitude(memory);

        // Skip memories without valid coordinates
        if (lat == null || lng == null || lat.isNaN || lng.isNaN) {
          continue;
        }

        validLocationCount++;

        // Initialize bounds with first valid location
        if (minLat == null) {
          minLat = maxLat = lat;
          minLng = maxLng = lng;
        } else {
          // Update bounds
          if (lat < minLat) minLat = lat;
          if (lat > maxLat!) maxLat = lat;
          if (lng < minLng!) minLng = lng;
          if (lng > maxLng!) maxLng = lng;
        }
      }

      // Check if we have valid bounds
      if (validLocationCount == 0 || minLat == null || maxLat == null || 
          minLng == null || maxLng == null) {
        debugPrint('[MapControllerNew] ⚠️ No valid memory locations found for zoom calculation');
        // Fallback to current location or default zoom
        await _fallbackToDefaultZoom();
        return;
      }

      // Calculate the spread (matching old controller logic)
      final double latDiff = maxLat - minLat;
      final double lngDiff = maxLng - minLng;
      final double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

      // Validate calculated differences
      if (latDiff.isNaN || lngDiff.isNaN || maxDiff.isNaN || maxDiff.isInfinite) {
        debugPrint('[MapControllerNew] ⚠️ Invalid bounds calculation, using fallback');
        await _fallbackToDefaultZoom();
        return;
      }

      // Get zoom level based on geographical spread from MapboxZoomHelper
      double zoom = MapboxZoomHelper().getZoomForSpread(maxDiff);

      // Calculate center coordinates
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;

      // Validate center coordinates before using them
      if (centerLat.isNaN || centerLng.isNaN || 
          centerLat.isInfinite || centerLng.isInfinite) {
        debugPrint('[MapControllerNew] ⚠️ Invalid center coordinates, using fallback');
        await _fallbackToDefaultZoom();
        return;
      }

      // Update current zoom variable
      currentZoom.value = zoom;

      debugPrint('[MapControllerNew] 📊 Memory spread analysis:');
      debugPrint('[MapControllerNew] - Valid locations: $validLocationCount/${_currentMemories.length}');
      debugPrint('[MapControllerNew] - Lat range: $minLat to $maxLat (diff: $latDiff)');
      debugPrint('[MapControllerNew] - Lng range: $minLng to $maxLng (diff: $lngDiff)');
      debugPrint('[MapControllerNew] - Max diff: $maxDiff');
      debugPrint('[MapControllerNew] - Calculated zoom: $zoom');
      debugPrint('[MapControllerNew] - Center: $centerLat, $centerLng');

      // Set camera to fit bounds with calculated zoom
      await mapboxMap!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(centerLng, centerLat),
          ),
          zoom: zoom,
          bearing: 0,
          pitch: 0,
        ),
        mapbox.MapAnimationOptions(duration: 1500),
      );

      debugPrint('[MapControllerNew] ✅ Optimal zoom level set to: $zoom');
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error calculating optimal zoom: $e');
      await _fallbackToDefaultZoom();
    }
  }

  /// Fallback to default zoom when calculation fails
  Future<void> _fallbackToDefaultZoom() async {
    try {
      debugPrint('[MapControllerNew] 🔄 Using fallback zoom strategy');
      
      // Use current location if available
      if (currentLocation.value != null) {
        currentZoom.value = _minZoom.toDouble();
        await mapboxMap!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(
              coordinates: mapbox.Position(
                currentLocation.value!.longitude,
                currentLocation.value!.latitude,
              ),
            ),
            zoom: currentZoom.value,
            bearing: 0,
            pitch: 0,
          ),
          mapbox.MapAnimationOptions(duration: 1500),
        );
        debugPrint('[MapControllerNew] ✅ Fallback: Used current location with zoom ${currentZoom.value}');
      } else {
        // Default world view
        currentZoom.value = _minZoom.toDouble();
        await mapboxMap!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(0, 0)),
            zoom: currentZoom.value,
            bearing: 0,
            pitch: 0,
          ),
          mapbox.MapAnimationOptions(duration: 1500),
        );
        debugPrint('[MapControllerNew] ✅ Fallback: Used world center with zoom ${currentZoom.value}');
      }
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error in fallback zoom: $e');
    }
  }
  /// Add hashtag to selected hashtags (used by FilterDropdown)
  void addHashtag(String hashtag) {
    if (!selectedHashtags.contains(hashtag)) {
      selectedHashtags.add(hashtag);
      _updateFilterStatus();
      debugPrint("[MapControllerNew] Added hashtag: $hashtag");
    }
  }

  /// Remove hashtag from selected hashtags (used by FilterDropdown)
  void removeHashtag(String hashtag) {
    selectedHashtags.remove(hashtag);
    _updateFilterStatus();
    debugPrint("[MapControllerNew] Removed hashtag: $hashtag");
  }

  /// Add contact to selected contacts (used by FilterDropdown)
  void addContact(String contact) {
    if (!selectedContacts.contains(contact)) {
      selectedContacts.add(contact);
      _updateFilterStatus();
      debugPrint("[MapControllerNew] Added contact: $contact");
    }
  }

  /// Remove contact from selected contacts (used by FilterDropdown)
  void removeContact(String contact) {
    selectedContacts.remove(contact);
    _updateFilterStatus();
    debugPrint("[MapControllerNew] Removed contact: $contact");
  }

  /// Add category to selected categories (used by FilterDropdown)
  void addCategory(String category) {
    if (!selectedCategories.contains(category)) {
      selectedCategories.add(category);
      _updateFilterStatus();
      debugPrint("[MapControllerNew] Added category: $category");
    }
  }

  /// Remove category from selected categories (used by FilterDropdown)
  void removeCategory(String category) {
    selectedCategories.remove(category);
    _updateFilterStatus();
    debugPrint("[MapControllerNew] Removed category: $category");
  }

  /// Clear all lines/arrows from the map
  Future<void> clearAllLines() async {
    if (_mapMarkerService != null) {
      await _mapMarkerService!.clearAll();
      debugPrint('[MapControllerNew] All lines and markers cleared');
    }
  }

  /// Refresh map view by reloading memories and updating markers
  Future<void> refreshMapView() async {
    debugPrint('[MapControllerNew] Refreshing map view');

    // Clear existing lines/arrows first
    await clearAllLines();

    // Reload memories from database
    await loadMemoriesFromDB();

    // Refresh AddMemoriesController if it exists
    try {
      final addMemoriesController = Get.find<AddMemoriesController>();
      addMemoriesController.onAgainInit();
      debugPrint('[MapControllerNew] AddMemoriesController refreshed');
    } catch (e) {
      debugPrint('[MapControllerNew] AddMemoriesController not found: $e');
    }
  }

  /// Generate and display chronological arrows between clusters and individual memories
  Future<void> _generateAndDisplayArrows(
    List<models.MemoryCluster> clusters,
    List<Map<String, dynamic>> individualMemories,
  ) async {
    try {
      debugPrint(
        '[MapControllerNew] Generating chronological arrows for ${clusters.length} clusters',
      );

      debugPrint(
        '[MapControllerNew] Found ${individualMemories.length} individual memories for arrow generation',
      );

      // Log some individual memories for debugging
      for (int i = 0; i < math.min(2, individualMemories.length); i++) {
        final memory = individualMemories[i];
        debugPrint(
          '[MapControllerNew] Individual memory ${i + 1}: ID=${memory['id']}, date=${memory['memory_date']}, lat=${memory['location_latitude']}, lng=${memory['location_longitude']}',
        );
      }

      // Create unified memory list for arrow generation
      final allMemoriesWithClusters = <clustering.MemoryWithCluster>[];

      // Add clustered memories
      for (final cluster in clusters) {
        final clusteringCluster = clustering.MemoryCluster(
          id: cluster.id,
          memories:
              cluster.memories
                  .map(
                    (memory) => clustering.MemoryLocation(
                      id: (memory['id'] ?? 0).toString(),
                      latitude: memory['location_latitude'] ?? 0.0,
                      longitude: memory['location_longitude'] ?? 0.0,
                      memoryDate:
                          DateTime.tryParse(memory['memory_date'] ?? '') ??
                          DateTime.now(),
                      title: memory['text'] ?? memory['description'] ?? '',
                      description:
                          memory['text'] ?? memory['description'] ?? '',
                      memoryData: Map<String, dynamic>.from(memory),
                    ),
                  )
                  .toList(),
          centerLatitude: cluster.latitude,
          centerLongitude: cluster.longitude,
          radiusKm: cluster.radiusKm,
        );

        // Add each memory in the cluster to the unified list
        for (final memory in clusteringCluster.memories) {
          allMemoriesWithClusters.add(
            clustering.MemoryWithCluster(memory, clusteringCluster),
          );
        }
      }

      // Add individual memories as single-memory clusters
      for (final individualMemory in individualMemories) {
        final memoryLocation = clustering.MemoryLocation(
          id: (individualMemory['id'] ?? 0).toString(),
          latitude: individualMemory['location_latitude'] ?? 0.0,
          longitude: individualMemory['location_longitude'] ?? 0.0,
          memoryDate:
              DateTime.tryParse(individualMemory['memory_date'] ?? '') ??
              DateTime.now(),
          title:
              individualMemory['text'] ?? individualMemory['description'] ?? '',
          description:
              individualMemory['text'] ?? individualMemory['description'] ?? '',
          memoryData: Map<String, dynamic>.from(individualMemory),
        );

        // Create virtual cluster for individual memory
        final virtualCluster = clustering.MemoryCluster(
          id: 'individual_${individualMemory['id']}',
          memories: [memoryLocation],
          centerLatitude: memoryLocation.latitude,
          centerLongitude: memoryLocation.longitude,
          radiusKm: 0.0,
        );

        allMemoriesWithClusters.add(
          clustering.MemoryWithCluster(memoryLocation, virtualCluster),
        );
      }

      debugPrint(
        '[MapControllerNew] Created unified memory list with ${allMemoriesWithClusters.length} memories',
      );

      if (allMemoriesWithClusters.length < 2) {
        debugPrint('[MapControllerNew] Not enough memories for arrows');
        return;
      }

      // Generate arrows using the unified approach
      final arrows = _generateChronologicalArrowsFromMemories(
        allMemoriesWithClusters,
      );
      debugPrint(
        '[MapControllerNew] Generated ${arrows.length} chronological arrows',
      );

      // Store arrows
      currentArrows.assignAll(arrows);

      // Display arrows using MapMarkerService
      if (_mapMarkerService != null) {
        if (arrows.isNotEmpty) {
          debugPrint(
            '[MapControllerNew] Calling MapMarkerService.displayChronologicalArrows with ${arrows.length} arrows',
          );

          // Log arrow details for debugging
          for (int i = 0; i < arrows.length; i++) {
            final arrow = arrows[i];
            debugPrint(
              '[MapControllerNew] Arrow $i: ${arrow.fromClusterId} → ${arrow.toClusterId} (${arrow.fromLatitude}, ${arrow.fromLongitude}) → (${arrow.toLatitude}, ${arrow.toLongitude})',
            );
          }

          await _mapMarkerService!.displayChronologicalArrows(arrows);
          debugPrint(
            '[MapControllerNew] ✅ Successfully displayed chronological arrows on map',
          );
        } else {
          debugPrint('[MapControllerNew] ⚠️  No arrows to display');
        }
      } else {
        debugPrint(
          '[MapControllerNew] ❌ MapMarkerService not available for arrow display',
        );
      }
    } catch (e) {
      debugPrint('[MapControllerNew] Error generating/displaying arrows: $e');
    }
  }

  /// Generate chronological arrows from unified memory list (clusters + individuals)
  List<clustering.ChronologicalArrow> _generateChronologicalArrowsFromMemories(
    List<clustering.MemoryWithCluster> memoriesWithClusters,
  ) {
    if (memoriesWithClusters.length < 2) return [];

    final List<clustering.ChronologicalArrow> arrows = [];

    // Sort all memories by date
    memoriesWithClusters.sort(
      (a, b) => a.memory.memoryDate.compareTo(b.memory.memoryDate),
    );

    debugPrint(
      '[MapControllerNew] Sorted ${memoriesWithClusters.length} memories chronologically',
    );

    // Generate arrows between consecutive memories
    for (int i = 0; i < memoriesWithClusters.length - 1; i++) {
      final currentMemory = memoriesWithClusters[i];
      final nextMemory = memoriesWithClusters[i + 1];

      debugPrint(
        '[MapControllerNew] Checking arrow between ${currentMemory.cluster.id} and ${nextMemory.cluster.id}',
      );

      // Create arrow if memories are in different clusters OR if they are far apart
      final shouldCreateArrow =
          currentMemory.cluster.id != nextMemory.cluster.id ||
          _calculateDistance(
                currentMemory.cluster.centerLatitude,
                currentMemory.cluster.centerLongitude,
                nextMemory.cluster.centerLatitude,
                nextMemory.cluster.centerLongitude,
              ) >
              0.1; // Create arrow if distance > 100m

      if (shouldCreateArrow) {
        final arrow = clustering.ChronologicalArrow(
          fromLatitude: currentMemory.cluster.centerLatitude,
          fromLongitude: currentMemory.cluster.centerLongitude,
          toLatitude: nextMemory.cluster.centerLatitude,
          toLongitude: nextMemory.cluster.centerLongitude,
          fromDate: currentMemory.memory.memoryDate,
          toDate: nextMemory.memory.memoryDate,
          fromClusterId: currentMemory.cluster.id,
          toClusterId: nextMemory.cluster.id,
        );

        arrows.add(arrow);

        debugPrint(
          '[MapControllerNew] ✅ Created arrow: ${currentMemory.cluster.id} → ${nextMemory.cluster.id} (${currentMemory.memory.memoryDate} → ${nextMemory.memory.memoryDate})',
        );
      } else {
        debugPrint(
          '[MapControllerNew] ⚠️  Skipped arrow: same cluster and close distance',
        );
      }
    }

    // Remove duplicate arrows between same cluster pairs
    final uniqueArrows = <clustering.ChronologicalArrow>[];
    final seenConnections = <String>{};

    for (final arrow in arrows) {
      final connectionKey = '${arrow.fromClusterId}_${arrow.toClusterId}';
      if (!seenConnections.contains(connectionKey)) {
        uniqueArrows.add(arrow);
        seenConnections.add(connectionKey);
      }
    }

    debugPrint(
      '[MapControllerNew] Generated ${uniqueArrows.length} unique arrows from ${arrows.length} total connections',
    );

    return uniqueArrows;
  }

  /// Get memory statistics (delegates to MemoryRepository)
  Map<String, dynamic> getMemoryStatistics() {
    if (_memoryRepository == null) {
      return {'total_memories': 0};
    }

    return _memoryRepository!.getMemoryStatistics();
  }

  /// Print memory statistics (delegates to MemoryRepository)
  void printMemoryStatistics() {
    if (_memoryRepository == null) {
      debugPrint('[MapControllerNew] MemoryRepository not available');
      return;
    }

    _memoryRepository!.printMemoryStatistics();
  }

  /// Get memories near current location (delegates to MemoryRepository)
  List<Map<String, dynamic>> getMemoriesNearCurrentLocation({
    double radiusKm = 1.0,
  }) {
    if (_memoryRepository == null || currentLocation.value == null) {
      return [];
    }

    return _memoryRepository!.getMemoriesNearLocation(
      currentLocation.value!.latitude,
      currentLocation.value!.longitude,
      radiusKm: radiusKm,
    );
  }

  /// Test method removed - internet required screen no longer used
  // Internet connectivity checks removed - offline tiles are downloaded during Get Started flow

  /// Reset loading states - useful for debugging stuck states
  void resetLoadingStates() {
    debugPrint('[MapControllerNew] 🔄 Resetting loading states');
    isLoadingLocation.value = false;
    locationStatus.value = 'Ready';
    debugPrint('[MapControllerNew] States after reset:');
    debugPrint(
      '[MapControllerNew] - hasLocationPermission: ${hasLocationPermission.value}',
    );
    debugPrint(
      '[MapControllerNew] - isLoadingLocation: ${isLoadingLocation.value}',
    );
    debugPrint('[MapControllerNew] - locationStatus: ${locationStatus.value}');
  }

  /// Force immediate permission state check - ensures UI updates immediately after permission grant
  Future<void> forcePermissionStateCheck() async {
    try {
      debugPrint(
        '[MapControllerNew] 🔍 Force checking current permission state...',
      );

      // Check current permission without requesting
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('[MapControllerNew] Current permission: $permission');

      bool hasPermission =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;

      if (hasPermission && !hasLocationPermission.value) {
        debugPrint(
          '[MapControllerNew] 🎉 Permission was granted! Updating state...',
        );
        hasLocationPermission.value = true;
        locationStatus.value = 'Permission granted, getting location...';
        isLoadingLocation.value = true;

        // Get location immediately
        await _getCurrentLocation();
      } else if (!hasPermission && hasLocationPermission.value) {
        debugPrint(
          '[MapControllerNew] ❌ Permission was revoked! Updating state...',
        );
        hasLocationPermission.value = false;
        locationStatus.value = 'Location permission required';
        isLoadingLocation.value = false;
      }

      debugPrint('[MapControllerNew] Final state after force check:');
      debugPrint(
        '[MapControllerNew] - hasLocationPermission: ${hasLocationPermission.value}',
      );
      debugPrint(
        '[MapControllerNew] - isLoadingLocation: ${isLoadingLocation.value}',
      );
      debugPrint(
        '[MapControllerNew] - locationStatus: ${locationStatus.value}',
      );
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error in force permission check: $e');
    }
  }

  /// Start monitoring permission changes using efficient listeners
  void _startPermissionMonitoring() {
    debugPrint(
      '[MapControllerNew] 🔍 Starting permission monitoring with listeners',
    );

    // Clean up existing listeners
    _permissionServiceWorker?.dispose();
    _appLifecycleSubscription?.cancel();

    try {
      // Listen to PermissionService changes
      final permissionService = Get.find<PermissionService>();

      _permissionServiceWorker = ever(permissionService.hasLocationPermission, (
        bool hasPermission,
      ) {
        debugPrint(
          '[MapControllerNew] 📡 PermissionService state changed: $hasPermission',
        );

        if (hasPermission && !hasLocationPermission.value) {
          debugPrint(
            '[MapControllerNew] 🎉 Permission granted detected via PermissionService listener!',
          );
          // Permission was just granted, update our state immediately
          _handlePermissionGranted();
        } else if (!hasPermission && hasLocationPermission.value) {
          debugPrint(
            '[MapControllerNew] ❌ Permission revoked detected via PermissionService listener!',
          );
          // Permission was revoked
          _handlePermissionRevoked();
        }
      });

      // Also setup app lifecycle listener for additional permission detection
      _setupAppLifecycleListener();

      debugPrint('[MapControllerNew] ✅ Permission listeners setup complete');
    } catch (e) {
      debugPrint(
        '[MapControllerNew] ⚠️ Could not find PermissionService, using fallback monitoring: $e',
      );
      // Fallback to less frequent periodic checks if PermissionService is not available
      _startFallbackMonitoring();
    }
  }

  /// Setup app lifecycle listener for permission changes
  void _setupAppLifecycleListener() {
    try {
      // Create reactive app lifecycle state observer
      final appLifecycleState = AppLifecycleState.resumed.obs;

      // Add a WidgetsBindingObserver to track app lifecycle
      _lifecycleObserver = _MapLifecycleObserver(
        onStateChanged: (state) {
          appLifecycleState.value = state;
        },
      );
      WidgetsBinding.instance.addObserver(_lifecycleObserver!);

      // Listen to app lifecycle changes
      ever(appLifecycleState, (AppLifecycleState state) {
        if (state == AppLifecycleState.resumed) {
          debugPrint(
            '[MapControllerNew] 📱 App resumed, checking permission state',
          );

          // Only check if we currently think permission is denied
          if (!hasLocationPermission.value) {
            forcePermissionStateCheck().then((_) {
              if (hasLocationPermission.value) {
                debugPrint(
                  '[MapControllerNew] 🎉 Permission granted detected via app lifecycle!',
                );
              }
            });
          }
        }
      });

      debugPrint('[MapControllerNew] 📱 App lifecycle listener setup complete');
    } catch (e) {
      debugPrint(
        '[MapControllerNew] ⚠️ Could not setup app lifecycle listener: $e',
      );
    }
  }

  /// Handle when permission is granted (iOS-specific timing fix)
  void _handlePermissionGranted() async {
    hasLocationPermission.value = true;
    locationStatus.value = 'Permission granted, getting location...';
    isLoadingLocation.value = true;

    try {
      await _getCurrentLocation();

      // iOS FIX: If map is already ready but we just got location, animate now
      if (isMapReady.value && mapboxMap != null && currentLocation.value != null) {
        debugPrint('[MapControllerNew] 🎯 iOS: Permission granted after map ready - forcing animation');
        await Future.delayed(Duration(milliseconds: 500));
        await _moveCameraToCurrentLocation();
      }
    } catch (e) {
      debugPrint('[MapControllerNew] Error getting location after permission granted: $e');
    }
  }

  /// Handle when permission is revoked
  void _handlePermissionRevoked() {
    hasLocationPermission.value = false;
    locationStatus.value = 'Location permission required';
    isLoadingLocation.value = false;
    currentLocation.value = null;
  }

  /// Fallback monitoring with less frequent checks
  void _startFallbackMonitoring() {
    debugPrint('[MapControllerNew] 🔄 Starting fallback permission monitoring');

    // Use a much less frequent check as fallback (every 5 seconds, only when needed)
    Timer.periodic(Duration(seconds: 5), (timer) {
      if (!hasLocationPermission.value) {
        forcePermissionStateCheck().then((_) {
          if (hasLocationPermission.value) {
            debugPrint(
              '[MapControllerNew] 🎉 Permission granted detected via fallback monitoring!',
            );
            timer.cancel();
          }
        });
      } else {
        timer.cancel(); // Stop once permission is granted
      }
    });
  }

  @override
  void onClose() {
    debugPrint('[MapControllerNew] Cleaning up map controller');

    // Clean up permission listeners
    _permissionServiceWorker?.dispose();
    _appLifecycleSubscription?.cancel();

    // Clean up zoom monitoring timer
    _zoomMonitorTimer?.cancel();
    _zoomMonitorTimer = null;

    // Remove lifecycle observer
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }

    super.onClose();
  }

  Future<void> onMapError(
    mapbox.MapLoadingErrorEventData mapLoadingErrorEventData,
  ) async {
    debugPrint('[MapControllerNew] 🗺️ Map load error occurred');
    debugPrint('[MapControllerNew] Error message: ${mapLoadingErrorEventData.message}');
    debugPrint('[MapControllerNew] Error type: ${mapLoadingErrorEventData.type}');

    // Map errors are expected when using local tile server
    // The local tile server serves tiles via HTTP, so Mapbox style loads normally
    // No need to check for offline tiles or enable offline mode
    debugPrint('[MapControllerNew] ℹ️ Map error logged - continuing with local tile server if available');
  }

  /// Check for offline tiles and enable offline mode if available
  Future<bool> _checkAndEnableOfflineMode() async {
    try {
      // Check if offline coordinator is available
      if (_offlineCoordinator == null) {
        debugPrint('[MapControllerNew] ❌ Offline coordinator not available');
        return false;
      }

      // Use the coordinator's method to check and enable offline mode
      final offlineModeEnabled = await _offlineCoordinator!.checkAndEnableOfflineMode();

      if (offlineModeEnabled) {
        debugPrint('[MapControllerNew] ✅ Offline mode successfully enabled');

        // Internet connectivity checks removed - offline tiles are downloaded during Get Started flow
        // No need to update UI state for internet connection

        return true;
      } else {
        debugPrint('[MapControllerNew] ❌ Could not enable offline mode');
        return false;
      }
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error checking offline mode: $e');
      return false;
    }
  }

  // COMMENTED OUT: Tile count check not needed when using downloaded mbtiles
  // /// Check if we have sufficient offline tiles (500+) by fetching from SharedPreferences
  // Future<bool> _checkOfflineTileCount() async {
  //   try {
  //     final prefs = await SharedPreferences.getInstance();
  //     final tileCount = prefs.getInt('offline_downloaded_tile_count') ?? 0;
  //
  //     debugPrint('[MapControllerNew] 📊 Fetched offline tile count from SharedPreferences: $tileCount tiles');
  //
  //     if (tileCount >= 500) {
  //       debugPrint('[MapControllerNew] ✅ Sufficient tiles available: $tileCount >= 500');
  //       return true;
  //     } else {
  //       debugPrint('[MapControllerNew] ❌ Insufficient tiles: $tileCount < 500');
  //       return false;
  //     }
  //   } catch (e) {
  //     debugPrint('[MapControllerNew] ❌ Error fetching tile count from SharedPreferences: $e');
  //     return false;
  //   }
  // }

  /// Manually trigger layer visibility update (useful for testing or manual refresh)
  Future<void> updateLayerVisibility() async {
    if (mapboxMap == null) return;

    try {
      final cameraState = await mapboxMap!.getCameraState();
      final currentZoomLevel = cameraState.zoom;
      await _updateLayerVisibilityForZoom(currentZoomLevel);
      debugPrint('[MapControllerNew] 🔄 Manual layer visibility update completed for zoom: $currentZoomLevel');
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error in manual layer visibility update: $e');
    }
  }

  /// Set up camera change listener to handle zoom-based layer visibility
  void _setupCameraChangeListener() {
    if (mapboxMap == null) return;

    try {
      debugPrint('[MapControllerNew] 📹 Setting up zoom monitoring for layer visibility');

      // Since Mapbox Flutter doesn't have direct camera listeners,
      // we'll use a periodic check combined with manual updates
      _startZoomMonitoring();

      debugPrint('[MapControllerNew] ✅ Zoom monitoring setup complete');
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error setting up zoom monitoring: $e');
    }
  }

  Timer? _zoomMonitorTimer;
  double _lastKnownZoom = 0.0;

  /// Start periodic zoom monitoring
  void _startZoomMonitoring() {
    // Check zoom level every 500ms
    _zoomMonitorTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      _checkZoomChange();
    });
  }

  /// Check if zoom level has changed and update layers accordingly
  void _checkZoomChange() async {
    if (mapboxMap == null) return;

    try {
      final cameraState = await mapboxMap!.getCameraState();
      final currentZoomLevel = cameraState.zoom;

      // Only update if zoom has changed significantly (avoid excessive updates)
      if ((currentZoomLevel - _lastKnownZoom).abs() > 0.1) {
        _lastKnownZoom = currentZoomLevel;
        currentZoom.value = currentZoomLevel;

        debugPrint('[MapControllerNew] 🔍 Zoom changed to: $currentZoomLevel');

        // Update layer visibility based on zoom level
        await _updateLayerVisibilityForZoom(currentZoomLevel);
      }
    } catch (e) {
      // Silently ignore errors to avoid spam
    }
  }



  /// Update layer visibility based on current zoom level
  Future<void> _updateLayerVisibilityForZoom(double zoomLevel) async {
    if (mapboxMap == null) return;

    try {
      // Determine which layers should be visible at current zoom
      // Clusters: visible when zoomed out (below half zoom ~9.0)
      final showClusters = zoomLevel < _clusterVisibilityMaxZoom;
      // Individual memories: visible when zoomed in (above half zoom ~9.0)
      final showIndividual = zoomLevel >= _individualVisibilityMinZoom;
      // Details: visible at high zoom levels
      final showDetails = zoomLevel >= _detailVisibilityMinZoom;

      debugPrint('[MapControllerNew] 👁️ Updating layer visibility for zoom $zoomLevel:');
      debugPrint('[MapControllerNew] - Clusters: $showClusters (max: $_clusterVisibilityMaxZoom)');
      debugPrint('[MapControllerNew] - Individual: $showIndividual (min: $_individualVisibilityMinZoom)');
      debugPrint('[MapControllerNew] - Details: $showDetails (min: $_detailVisibilityMinZoom)');

      // Update cluster layers visibility (show when zoomed out)
      await _setLayerVisibility(CLUSTER_LAYER_ID, showClusters);
      await _setLayerVisibility(CLUSTER_COUNT_LAYER_ID, showClusters);

      // Update individual memory layers visibility (show when zoomed in)
      await _setLayerVisibility(UNCLUSTERED_LAYER_ID, showIndividual);
      await _setLayerVisibility(INDIVIDUAL_COUNT_LAYER_ID, showIndividual && showDetails);

    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error updating layer visibility: $e');
    }
  }

  /// Set visibility for a specific layer
  Future<void> _setLayerVisibility(String layerId, bool visible) async {
    if (mapboxMap == null) return;

    try {
      final visibility = visible ? 'visible' : 'none';
      await mapboxMap!.style.setStyleLayerProperty(
        layerId,
        'visibility',
        visibility,
      );
      debugPrint('[MapControllerNew] 🎨 Set layer $layerId visibility to: $visibility');
    } catch (e) {
      // Layer might not exist yet, which is fine
      debugPrint('[MapControllerNew] ⚠️ Could not set visibility for layer $layerId: $e');
    }
  }

  void initializeMapData() {
    if (currentLocation.value != null) {
      _moveCameraToCurrentLocation();
    } else {
      loadMemoriesFromDB();
    }
  }

  /// Force remove and re-add source when update fails
  Future<void> _forceRemoveAndReaddSource(String geoJsonString) async {
    if (mapboxMap == null) return;

    try {
      debugPrint(
        '[MapControllerNew] 🔄 Force removing and re-adding source...',
      );

      // Force remove the source
      try {
        await mapboxMap!.style.removeStyleSource(MEMORY_SOURCE_ID);
        debugPrint(
          '[MapControllerNew] ✅ Force removed source: $MEMORY_SOURCE_ID',
        );
      } catch (e) {
        debugPrint(
          '[MapControllerNew] ⚠️  Source removal failed (may not exist): $e',
        );
      }

      // Wait a moment for cleanup
      await Future.delayed(const Duration(milliseconds: 200));

      // Re-add the source
      await mapboxMap!.style.addSource(
        mapbox.GeoJsonSource(
          id: MEMORY_SOURCE_ID,
          data: geoJsonString,
          cluster: true,
          clusterMaxZoom: 14,
          clusterRadius: 50,
          clusterMinPoints: 2,
        ),
      );
      debugPrint('[MapControllerNew] ✅ Successfully re-added GeoJSON source');
    } catch (e) {
      debugPrint(
        '[MapControllerNew] ❌ Failed to force remove and re-add source: $e',
      );
      rethrow;
    }
  }

  /// Handle map tap with feature querying to detect clusters or individual memories
  Future<void> _handleMapTapWithFeatureQuery(
    mapbox.Point tapPoint,
    double lat,
    double lng,
  ) async {
    try {
      debugPrint(
        '[MapControllerNew] 🔍 Querying features at tap point: ($lat, $lng)',
      );

      // Query features at the tap point to detect clusters or individual markers
      await _queryFeaturesAtTapPoint(tapPoint, lat, lng);

    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error in tap handling: $e');
      // Fallback to location info
      // _showLocationInfo(lat, lng);
    }
  }

  /// Query map features at tap point to distinguish between clusters and individual markers
  Future<void> _queryFeaturesAtTapPoint(
    mapbox.Point tapPoint,
    double lat,
    double lng,
  ) async {
    if (mapboxMap == null) return;

    try {
      debugPrint('[MapControllerNew] 🔍 === DETAILED TAP QUERY DEBUG ===');
      debugPrint('[MapControllerNew] 📍 Tap coordinates: lat=$lat, lng=$lng');
      debugPrint('[MapControllerNew] 📱 Screen coordinates: x=${tapPoint.coordinates.lng}, y=${tapPoint.coordinates.lat}');
      debugPrint('[MapControllerNew] 🎯 Target layers: [$CLUSTER_LAYER_ID, $UNCLUSTERED_LAYER_ID]');

      // Get current zoom level for context
      try {
        final cameraState = await mapboxMap!.getCameraState();
        debugPrint('[MapControllerNew] 🔍 Current zoom level: ${cameraState.zoom}');
        debugPrint('[MapControllerNew] 🗺️ Current center: ${cameraState.center.coordinates.lat}, ${cameraState.center.coordinates.lng}');
      } catch (e) {
        debugPrint('[MapControllerNew] ⚠️ Could not get camera state: $e');
      }

      // Query features in cluster layer first (clusters have priority)
      debugPrint('[MapControllerNew] 🔍 Querying cluster layer: $CLUSTER_LAYER_ID');
      final clusterFeatures = await mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(
          mapbox.ScreenCoordinate(x: tapPoint.coordinates.lng.toDouble(), y: tapPoint.coordinates.lat.toDouble())
        ),
        mapbox.RenderedQueryOptions(
          layerIds: [CLUSTER_LAYER_ID],
        ),
      );

      debugPrint('[MapControllerNew] 🌐 Cluster features found: ${clusterFeatures.length}');

      // Log detailed cluster feature data
      for (int i = 0; i < clusterFeatures.length; i++) {
        final feature = clusterFeatures[i];
        if (feature != null) {
          debugPrint('[MapControllerNew] 📊 Cluster feature $i:');
          debugPrint('[MapControllerNew]   - Feature type: ${feature.runtimeType}');

          try {
            final queriedFeature = feature.queriedFeature;
            debugPrint('[MapControllerNew]   - Queried feature type: ${queriedFeature.runtimeType}');
            debugPrint('[MapControllerNew]   - Feature data: ${queriedFeature.toString()}');
          } catch (e) {
            debugPrint('[MapControllerNew]   - Error accessing queried feature: $e');
          }
        } else {
          debugPrint('[MapControllerNew] 📊 Cluster feature $i: null');
        }
      }

      if (clusterFeatures.isNotEmpty && clusterFeatures.first != null) {
        debugPrint('[MapControllerNew] ✅ Processing cluster tap');
        await _handleClusterFeatureTap(clusterFeatures.first!, lat, lng);
        return;
      }

      // Query features in individual memory layer
      debugPrint('[MapControllerNew] 🔍 Querying individual memory layer: $UNCLUSTERED_LAYER_ID');
      final individualFeatures = await mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(
          mapbox.ScreenCoordinate(x: tapPoint.coordinates.lng.toDouble(), y: tapPoint.coordinates.lat.toDouble())
        ),
        mapbox.RenderedQueryOptions(
          layerIds: [UNCLUSTERED_LAYER_ID],
        ),
      );

      debugPrint('[MapControllerNew] 👤 Individual features found: ${individualFeatures.length}');

      // Log detailed individual feature data
      for (int i = 0; i < individualFeatures.length; i++) {
        final feature = individualFeatures[i];
        if (feature != null) {
          debugPrint('[MapControllerNew] 📊 Individual feature $i:');
          debugPrint('[MapControllerNew]   - Feature type: ${feature.runtimeType}');

          try {
            final queriedFeature = feature.queriedFeature;
            debugPrint('[MapControllerNew]   - Queried feature type: ${queriedFeature.runtimeType}');
            debugPrint('[MapControllerNew]   - Feature data: ${queriedFeature.toString()}');
          } catch (e) {
            debugPrint('[MapControllerNew]   - Error accessing queried feature: $e');
          }
        } else {
          debugPrint('[MapControllerNew] 📊 Individual feature $i: null');
        }
      }

      if (individualFeatures.isNotEmpty && individualFeatures.first != null) {
        debugPrint('[MapControllerNew] ✅ Processing individual memory tap');
        await _handleIndividualFeatureTap(individualFeatures.first!, lat, lng);
        return;
      }

      // Query all features at this point for debugging
      debugPrint('[MapControllerNew] 🔍 Querying ALL features at tap point for debugging');
      final allFeatures = await mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(
          mapbox.ScreenCoordinate(x: tapPoint.coordinates.lng.toDouble(), y: tapPoint.coordinates.lat.toDouble())
        ),
        mapbox.RenderedQueryOptions(),
      );

      debugPrint('[MapControllerNew] 🌍 Total features found: ${allFeatures.length}');
      for (int i = 0; i < allFeatures.length && i < 10; i++) { // Limit to first 10 to avoid spam
        final feature = allFeatures[i];
        if (feature != null) {
          try {
            final queriedFeature = feature.queriedFeature;
            debugPrint('[MapControllerNew] 📊 All feature $i: ${queriedFeature.toString()}');
          } catch (e) {
            debugPrint('[MapControllerNew] 📊 All feature $i: Error accessing - $e');
          }
        }
      }

      // No features found, show location info
      debugPrint('[MapControllerNew] 📍 No target features found at tap point, showing location info');
      debugPrint('[MapControllerNew] 🔍 === END TAP QUERY DEBUG ===');
      _showLocationInfo(lat, lng);

    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error querying features: $e');
      debugPrint('[MapControllerNew] 📊 Error details: ${e.toString()}');
      debugPrint('[MapControllerNew] 📊 Error type: ${e.runtimeType}');
      debugPrint('[MapControllerNew] 🔍 === END TAP QUERY DEBUG (ERROR) ===');
      // Fallback to old method
      _fallbackToLocationBasedTap(lat, lng);
    }
  }

  /// Handle tap on a cluster feature
  Future<void> _handleClusterFeatureTap(
    mapbox.QueriedRenderedFeature clusterFeature,
    double lat,
    double lng,
  ) async {
    try {
      debugPrint('[MapControllerNew] 🎯 Handling cluster feature tap at ($lat, $lng)');

      // For now, find the cluster by location proximity since feature property access is complex
      // This is a temporary solution until we can properly access Mapbox feature properties
      final nearbyCluster = _findNearestCluster(lat, lng);

      if (nearbyCluster != null) {
        debugPrint('[MapControllerNew] 📊 Found cluster with ${nearbyCluster.memories.length} memories');
        await _showClusterMemories(nearbyCluster);
      } else {
        debugPrint('[MapControllerNew] ⚠️ No cluster found near tap location');
        _showLocationInfo(lat, lng);
      }
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error handling cluster feature tap: $e');
      _showLocationInfo(lat, lng);
    }
  }

  /// Find the nearest cluster to the given coordinates
  models.MemoryCluster? _findNearestCluster(double lat, double lng) {
    if (currentClusters.isEmpty) return null;

    models.MemoryCluster? nearestCluster;
    double minDistance = double.infinity;
    const double maxDistance = 0.001; // ~100m tolerance

    for (final cluster in currentClusters) {
      final distance = _calculateDistance(lat, lng, cluster.latitude, cluster.longitude);
      if (distance < minDistance && distance < maxDistance) {
        minDistance = distance;
        nearestCluster = cluster;
      }
    }

    return nearestCluster;
  }

  /// Calculate distance between two coordinates (simple Euclidean distance)
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    final dLat = lat1 - lat2;
    final dLng = lng1 - lng2;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  /// Show all memories in a cluster
  Future<void> _showClusterMemories(models.MemoryCluster cluster) async {
    try {
      debugPrint('[MapControllerNew] 📋 Showing ${cluster.memories.length} memories from cluster ${cluster.id}');

      if (cluster.memories.length == 1) {
        // Single memory, show directly
        await _handleMemoryTap(cluster.memories.first);
      } else {
        // Multiple memories, show cluster details
        await _handleClusterTap(cluster);
      }
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error showing cluster memories: $e');
    }
  }

  /// Handle tap on an individual memory feature
  Future<void> _handleIndividualFeatureTap(
    mapbox.QueriedRenderedFeature individualFeature,
    double lat,
    double lng,
  ) async {
    try {
      debugPrint('[MapControllerNew] 🎯 Handling individual memory feature tap at ($lat, $lng)');

      // Find the nearest individual memory by location proximity
      final nearbyMemory = _findNearestMemory(lat, lng);

      if (nearbyMemory != null) {
        debugPrint('[MapControllerNew] 📝 Found memory: ${nearbyMemory['id']}');
        await _handleMemoryTap(nearbyMemory);
      } else {
        debugPrint('[MapControllerNew] ⚠️ No memory found near tap location');
        _showLocationInfo(lat, lng);
      }
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error handling individual feature tap: $e');
      _showLocationInfo(lat, lng);
    }
  }

  /// Find the nearest memory to the given coordinates
  Map<String, dynamic>? _findNearestMemory(double lat, double lng) {
    if (_currentMemories.isEmpty) return null;

    Map<String, dynamic>? nearestMemory;
    double minDistance = double.infinity;
    const double maxDistance = 0.001; // ~100m tolerance

    for (final memory in _currentMemories) {
      final memoryLat = memory['location_latitude'] as double?;
      final memoryLng = memory['location_longitude'] as double?;

      if (memoryLat != null && memoryLng != null) {
        final distance = _calculateDistance(lat, lng, memoryLat, memoryLng);
        if (distance < minDistance && distance < maxDistance) {
          minDistance = distance;
          nearestMemory = memory;
        }
      }
    }

    return nearestMemory;
  }



  /// Fallback to location-based tap handling when feature querying fails
  Future<void> _fallbackToLocationBasedTap(double lat, double lng) async {
    debugPrint('[MapControllerNew] 🔄 Using fallback location-based tap handling');

    if (_mapMarkerService != null && (currentClusters.isNotEmpty || _currentMemories.isNotEmpty)) {
      // Get current zoom level for dynamic tap radius
      double? currentZoom;
      if (mapboxMap != null) {
        try {
          final cameraState = await mapboxMap!.getCameraState();
          currentZoom = cameraState.zoom;
        } catch (e) {
          debugPrint('[MapControllerNew] Could not get zoom level for fallback tap: $e');
        }
      }

      _mapMarkerService!.handleLocationTap(
        lat,
        lng,
        currentClusters.cast<models.MemoryCluster>(),
        _currentMemories,
        zoomLevel: currentZoom,
      );
    } else {
      _showLocationInfo(lat, lng);
    }
  }

  /// Show basic location information for map taps
  void _showLocationInfo(double lat, double lng) {
    debugPrint('[MapControllerNew] 📍 Showing location info for: ($lat, $lng)');
  }

  /// Clear MapBox clustering layers and sources
  Future<void> _clearMapboxClusteringLayers() async {
    if (mapboxMap == null) return;

    try {
      // Remove layers first (order matters)
      final layersToRemove = [
        ARROW_LINES_LAYER_ID,
        CLUSTER_COUNT_LAYER_ID,
        CLUSTER_LAYER_ID,
        UNCLUSTERED_LAYER_ID,
        INDIVIDUAL_COUNT_LAYER_ID,
      ];

      for (final layerId in layersToRemove) {
        try {
          await mapboxMap!.style.removeStyleLayer(layerId);
          debugPrint('[MapControllerNew] Removed layer: $layerId');
        } catch (e) {
          // Layer doesn't exist, which is fine
          debugPrint(
            '[MapControllerNew] Layer $layerId not found (expected): $e',
          );
        }
      }

      // Remove sources
      final sourcesToRemove = [ARROW_LINES_SOURCE_ID, MEMORY_SOURCE_ID];

      for (final sourceId in sourcesToRemove) {
        try {
          await mapboxMap!.style.removeStyleSource(sourceId);
          debugPrint('[MapControllerNew] Removed source: $sourceId');
        } catch (e) {
          // Source doesn't exist, which is fine
          debugPrint(
            '[MapControllerNew] Source $sourceId not found (expected): $e',
          );
        }
      }
    } catch (e) {
      debugPrint('[MapControllerNew] Error clearing clustering layers: $e');
    }
  }

  /// Add MapBox cluster layers with enhanced styling and year-based colors
  Future<void> _addClusterLayers() async {
    if (mapboxMap == null) return;

    try {
      debugPrint(
        '[MapControllerNew] 🎨 Adding enhanced cluster layers with year-based colors...',
      );

      // Layer 1: Cluster circles (background) with enhanced styling (visibility controlled dynamically)
      debugPrint('[MapControllerNew] 🔵 Adding cluster circle layer...');
      await mapboxMap!.style.addLayer(
        mapbox.CircleLayer(
          id: CLUSTER_LAYER_ID,
          sourceId: MEMORY_SOURCE_ID,
          filter: ['has', 'point_count'],
          circleColor: 0xFF4CAF50, // Green for clusters
          circleRadius:
              25.0, // Fixed size for now - can enhance with expressions later
          circleStrokeWidth: 3,
          circleStrokeColor: 0xFFFFFFFF, // White stroke
          circleOpacity: 1,
          // No static zoom constraints - visibility controlled dynamically
        ),
      );
      debugPrint('[MapControllerNew] ✅ Added cluster circle layer');

      // Layer 2: Cluster count text (visibility controlled dynamically)
      debugPrint('[MapControllerNew] 🔤 Adding cluster count text layer...');
      await mapboxMap!.style.addLayer(
        mapbox.SymbolLayer(
          id: CLUSTER_COUNT_LAYER_ID,
          sourceId: MEMORY_SOURCE_ID,
          filter: ['has', 'point_count'],
          textField: '{point_count}',
          textSize: 12.0, // Fixed size for now
          textAllowOverlap: true,
          textColor: 0xFFFFFFFF, // White text
          textHaloColor: 0xFF000000, // Black halo
          textHaloWidth: 1.5,
          // No static zoom constraints - visibility controlled dynamically
        ),
      );
      debugPrint('[MapControllerNew] ✅ Added cluster count text layer');

      // Layer 3: Individual memory points (unclustered) with year-based colors (visibility controlled dynamically)
      debugPrint(
        '[MapControllerNew] 🔴 Adding individual memory circle layer...',
      );
      await mapboxMap!.style.addLayer(
        mapbox.CircleLayer(
          id: UNCLUSTERED_LAYER_ID,
          sourceId: MEMORY_SOURCE_ID,
          filter: [
            '!',
            ['has', 'point_count'],
          ],
          circleColor:
              0xFF2196F3, // Blue for individual memories - will enhance with year colors later
          circleRadius: 20.0,
          circleStrokeWidth: 2,
          circleStrokeColor: 0xFFFFFFFF, // White stroke
          circleOpacity: 0.9,
          // No static zoom constraints - visibility controlled dynamically
        ),
      );
      debugPrint('[MapControllerNew] ✅ Added individual memory circle layer');

      // Layer 4: Individual memory count text (show "1" for individual memories) (visibility controlled dynamically)
      debugPrint(
        '[MapControllerNew] 🔤 Adding individual memory count text layer...',
      );
      await mapboxMap!.style.addLayer(
        mapbox.SymbolLayer(
          id: INDIVIDUAL_COUNT_LAYER_ID,
          sourceId: MEMORY_SOURCE_ID,
          filter: [
            '!',
            ['has', 'point_count'],
          ],
          textField: '1', // Always show "1" for individual memories
          textSize: 10.0,
          textAllowOverlap: true,
          textColor: 0xFFFFFFFF, // White text
          textHaloColor: 0xFF000000, // Black halo
          textHaloWidth: 1.0,
          textFont: ['Open Sans Bold', 'Arial Unicode MS Bold'],
          // No static zoom constraints - visibility controlled dynamically
        ),
      );
      debugPrint(
        '[MapControllerNew] ✅ Added individual memory count text layer',
      );

      debugPrint(
        '[MapControllerNew] ✅ Successfully added all enhanced cluster layers',
      );

      // Verify layers were added
      await _verifyLayersAdded();

      // Set initial layer visibility based on current zoom
      await _updateInitialLayerVisibility();
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error adding cluster layers: $e');
      rethrow;
    }
  }

  /// Set initial layer visibility based on current zoom level
  Future<void> _updateInitialLayerVisibility() async {
    if (mapboxMap == null) return;

    try {
      final cameraState = await mapboxMap!.getCameraState();
      final currentZoomLevel = cameraState.zoom;
      _lastKnownZoom = currentZoomLevel;
      currentZoom.value = currentZoomLevel;

      debugPrint('[MapControllerNew] 🎯 Setting initial layer visibility for zoom: $currentZoomLevel');
      await _updateLayerVisibilityForZoom(currentZoomLevel);
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error setting initial layer visibility: $e');
    }
  }

  /// Verify that layers were successfully added to the map
  Future<void> _verifyLayersAdded() async {
    if (mapboxMap == null) return;

    try {
      final layers = await mapboxMap!.style.getStyleLayers();
      debugPrint(
        '[MapControllerNew] 📋 Total layers in style: ${layers.length}',
      );

      final layerIds = layers.map((l) => l!.id).whereType<String>().toList();
      debugPrint(
        '[MapControllerNew] 🔍 Looking for our layers in: ${layerIds.take(10).join(", ")}...',
      );

      // Check if our layers exist
      final ourLayers = [
        CLUSTER_LAYER_ID,
        CLUSTER_COUNT_LAYER_ID,
        UNCLUSTERED_LAYER_ID,
        INDIVIDUAL_COUNT_LAYER_ID,
      ];
      for (final layerId in ourLayers) {
        if (layerIds.contains(layerId)) {
          debugPrint('[MapControllerNew] ✅ Layer found: $layerId');
        } else {
          debugPrint('[MapControllerNew] ❌ Layer missing: $layerId');
        }
      }
    } catch (e) {
      debugPrint('[MapControllerNew] ⚠️  Could not verify layers: $e');
    }
  }

  /// Setup enhanced click handlers for native clustering
  Future<void> _setupNativeClusterClickHandlers() async {
    if (mapboxMap == null) return;

    try {
      debugPrint(
        '[MapControllerNew] 👆 Setting up enhanced cluster click handlers...',
      );

      // Setup map tap listener with feature querying
      mapboxMap!.setOnMapTapListener((context) async {
        final lat = context.point.coordinates.lat;
        final lng = context.point.coordinates.lng;
        debugPrint('[MapControllerNew] 🎯 Map tapped at: ($lat, $lng)');

        try {
          // Query features at the tap point to detect clusters or individual memories
          await _handleMapTapWithFeatureQuery(
            context.point,
            lat.toDouble(),
            lng.toDouble(),
          );
        } catch (e) {
          debugPrint('[MapControllerNew] ❌ Error handling map tap: $e');
          // Fallback to simple location display
          Get.snackbar(
            'Map Tapped',
            'Location: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
            backgroundColor: Colors.blue.withValues(alpha: 0.8),
            colorText: Colors.white,
        duration: const Duration(seconds: 2),
          );
        }
      });

      debugPrint(
        '[MapControllerNew] ✅ Enhanced cluster click handlers setup complete',
      );
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error setting up click handlers: $e');
    }
  }

  /// Generate and display arrows from memories (simplified version)
  Future<void> _generateAndDisplayArrowsFromMemories(
    List<Map<String, dynamic>> memories,
  ) async {
    try {
      debugPrint(
        '[MapControllerNew] Generating arrows from ${memories.length} memories',
      );

      if (memories.length < 2) {
        debugPrint('[MapControllerNew] Not enough memories for arrows');
        return;
      }

      // Sort memories by date
      final sortedMemories = List<Map<String, dynamic>>.from(memories);
      sortedMemories.sort((a, b) {
        final dateA =
            DateTime.tryParse(a['memory_date'] ?? '') ?? DateTime.now();
        final dateB =
            DateTime.tryParse(b['memory_date'] ?? '') ?? DateTime.now();
        return dateA.compareTo(dateB);
      });

      // Create simple arrows between consecutive memories
      final arrows = <clustering.ChronologicalArrow>[];
      for (int i = 0; i < sortedMemories.length - 1; i++) {
        final currentMemory = sortedMemories[i];
        final nextMemory = sortedMemories[i + 1];

        final currentLat = currentMemory['location_latitude'] as double?;
        final currentLng = currentMemory['location_longitude'] as double?;
        final nextLat = nextMemory['location_latitude'] as double?;
        final nextLng = nextMemory['location_longitude'] as double?;

        if (currentLat != null &&
            currentLng != null &&
            nextLat != null &&
            nextLng != null) {
          final arrow = clustering.ChronologicalArrow(
            fromLatitude: currentLat,
            fromLongitude: currentLng,
            toLatitude: nextLat,
            toLongitude: nextLng,
            fromDate:
                DateTime.tryParse(currentMemory['memory_date'] ?? '') ??
                DateTime.now(),
            toDate:
                DateTime.tryParse(nextMemory['memory_date'] ?? '') ??
                DateTime.now(),
            fromClusterId: 'memory_${currentMemory['id']}',
            toClusterId: 'memory_${nextMemory['id']}',
          );
          arrows.add(arrow);
        }
      }

      debugPrint('[MapControllerNew] Generated ${arrows.length} arrows');

      // Log arrow details for debugging
      for (int i = 0; i < arrows.length; i++) {
        final arrow = arrows[i];
        debugPrint(
          '[MapControllerNew] Arrow $i: (${arrow.fromLatitude}, ${arrow.fromLongitude}) → (${arrow.toLatitude}, ${arrow.toLongitude})',
        );
      }

      // Store arrows
      currentArrows.assignAll(arrows);

      // Display arrows using MapMarkerService (if available)
      if (_mapMarkerService != null) {
        if (arrows.isNotEmpty) {
          debugPrint(
            '[MapControllerNew] Calling MapMarkerService.displayChronologicalArrows with ${arrows.length} arrows',
          );
          await _mapMarkerService!.displayChronologicalArrows(arrows);
          debugPrint(
            '[MapControllerNew] ✅ Successfully displayed arrows using MapMarkerService',
          );
        } else {
          debugPrint('[MapControllerNew] ⚠️  No arrows generated to display');
        }
      } else {
        debugPrint(
          '[MapControllerNew] ❌ MapMarkerService is null - cannot display arrows',
        );
      }
    } catch (e) {
      debugPrint(
        '[MapControllerNew] Error generating arrows from memories: $e',
      );
    }
  }



  // ============================================================================
  // OFFLINE MAP FUNCTIONALITY (Delegated to OfflineMapCoordinatorService)
  // ============================================================================

  /// Start downloading offline map tiles (delegated to coordinator)
  Future<void> startOfflineDownload() async {
    await _offlineCoordinator?.startOfflineDownload(mapboxMap: mapboxMap);
  }

  /// Toggle offline mode on/off (delegated to coordinator)
  Future<void> toggleOfflineMode() async {
    await _offlineCoordinator?.toggleOfflineMode();
  }

  /// Hide the offline download overlay (delegated to coordinator)
  void hideOfflineDownloadOverlay() {
    _offlineCoordinator?.hideOfflineDownloadOverlay();
  }

  /// Show the offline download overlay (delegated to coordinator)
  void showOfflineDownloadOverlayWidget() {
    _offlineCoordinator?.showOfflineDownloadOverlayWidget();
  }

  /// Clear all offline data (delegated to coordinator)
  Future<void> clearOfflineData() async {
    await _offlineCoordinator?.clearOfflineData();
  }






}

/// Helper class for tracking app lifecycle changes
class _MapLifecycleObserver with WidgetsBindingObserver {
  final Function(AppLifecycleState) onStateChanged;

  _MapLifecycleObserver({required this.onStateChanged});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    onStateChanged(state);
  }
}
