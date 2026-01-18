import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/services/offline_map_service.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import 'package:spacetime/utils/cluster_icon_generator.dart';
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
    debugPrint(
      '[MapControllerNew] 🏗️ Constructor called - Creating new instance: $hashCode',
    );
  }

  // MapBox controller
  mapbox.MapboxMap? mapboxMap;

  // MapBox Native Clustering Constants
  static const String MEMORY_SOURCE_ID = 'memory-source';
  static const String CLUSTER_LAYER_ID = 'cluster-layer';
  static const String CLUSTER_COUNT_LAYER_ID = 'cluster-count-layer';
  static const String UNCLUSTERED_LAYER_ID = 'unclustered-layer';
  static const String INDIVIDUAL_COUNT_LAYER_ID = 'individual-count-layer';
  static const String CLUSTERS_CIRCLE_LAYER_ID = 'memory-clusters-circle';
  static const String CLUSTERS_COUNT_LAYER_ID = 'memory-clusters-count';
  // Cluster size tiers - used for both icon generation and layer creation
  final List<int> CLUSTER_SIZE_TIERS = List<int>.generate(
    200,
    (index) => index + 1,
  );

  // Zoom level constants - now loaded from MapboxZoomHelper
  // These getters provide access to the centralized zoom configuration
  double get _minZoom => MapboxZoomHelper().minZoom.value;
  double get _maxZoom => MapboxZoomHelper().maxZoom.value;

  // Zoom thresholds for layer visibility - loaded from MapboxZoomHelper
  double get _clusterVisibilityMaxZoom =>
      MapboxZoomHelper().clusterVisibilityMaxZoom.value;
  double get _individualVisibilityMinZoom =>
      MapboxZoomHelper().individualVisibilityMinZoom.value;
  double get _detailVisibilityMinZoom =>
      MapboxZoomHelper().detailVisibilityMinZoom.value;

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
  final RxList<String> selectedMemoryIds = <String>[].obs; // Filter by specific memory IDs (from map/filter)
  final RxList<String> searchedMemoryIds = <String>[].obs; // Filter by specific memory IDs (from search)
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
  MemoryRepository? _memoryRepository;
  ClusterRepository? _clusterRepository;
  MapMarkerService? _mapMarkerService;
  OfflineMapCoordinatorService? _offlineCoordinator;

  // Offline map state getters (delegate to coordinator)
  RxBool get showOfflineDownloadOverlay =>
      _offlineCoordinator?.showOfflineDownloadOverlay ?? false.obs;
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

    _initializeServices();

    loadFilterData();

    _initializeMap();

    // Start periodic permission checking to catch changes from permission service
    _startPermissionMonitoring();

    // Mark as initialized
    _isInitialized = true;
  }

  /// Initialize services
  void _initializeServices() {
    _memoryRepository = Get.find<MemoryRepository>();
    _clusterRepository = Get.find<ClusterRepository>();
    _mapMarkerService = Get.find<MapMarkerService>();
  }

  /// Initialize the map with location permissions and current location
  Future<void> _initializeMap() async {
    try {
      locationStatus.value = 'Checking location permissions...';
      isLoadingLocation.value =
          true; // Show loading state during permission check

      final hasPermission = await _checkLocationPermissions();

      if (hasPermission) {
        hasLocationPermission.value = true;

        await _getCurrentLocation();
      } else {
        hasLocationPermission.value = false;
        locationStatus.value = 'Location permission required';
        isLoadingLocation.value =
            false; // Stop loading since we need user action
      }
    } catch (e) {
      hasLocationPermission.value = false;
      locationStatus.value = 'Error initializing map';
    } finally {
      // Ensure loading state is stopped if permission was denied or error occurred
      if (!hasLocationPermission.value) {
        isLoadingLocation.value = false;
      }
    }
  }

  /// Check and request location permissions
  Future<bool> _checkLocationPermissions() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
        Duration(seconds: 5),
        onTimeout: () {
          return false;
        },
      );

      if (!serviceEnabled) {
        locationStatus.value = 'Location services are disabled';
        return false;
      }
      // Check current permission status

      LocationPermission permission = await Geolocator.checkPermission()
          .timeout(
            Duration(seconds: 5),
            onTimeout: () {
              return LocationPermission.denied;
            },
          );

      if (permission == LocationPermission.denied) {
        // Request permission with timeout
        permission = await Geolocator.requestPermission().timeout(
          Duration(seconds: 10),
          onTimeout: () {
            return LocationPermission.denied;
          },
        );

        if (permission == LocationPermission.denied) {
          locationStatus.value = 'Location permission denied';
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        locationStatus.value =
            'Location permission permanently denied. Please enable in Settings.';
        return false;
      }

      locationStatus.value = 'Permission granted';
      return true;
    } catch (e) {
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

      // Move camera to current location if map is ready
      if (isMapReady.value && mapboxMap != null) {
        await _moveCameraToCurrentLocation();
      } else {}
    } catch (e) {
    } finally {
      isLoadingLocation.value = false;
    }
  }

  /// Move camera to current location
  Future<void> _moveCameraToCurrentLocation() async {
    if (currentLocation.value == null || mapboxMap == null) {
      return;
    }

    try {
      final position = currentLocation.value!;
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
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error moving camera: $e');
    }
  }

  /// Ensure camera animates to user location with retry mechanism
  Future<void> _ensureCameraAnimationToUserLocation() async {
    // If we already have location, try immediate animation
    if (currentLocation.value != null &&
        isMapReady.value &&
        mapboxMap != null) {
      await _moveCameraToCurrentLocation();

      return;
    }

    // If we don't have location yet but have permission, wait and retry
    if (currentLocation.value == null && hasLocationPermission.value) {
      // Wait up to 5 seconds for location to be obtained
      for (int i = 0; i < 10; i++) {
        await Future.delayed(Duration(milliseconds: 500));

        if (currentLocation.value != null &&
            isMapReady.value &&
            mapboxMap != null) {
          await _moveCameraToCurrentLocation();

          return;
        }
      }
    }
  }

  /// Handle map creation callback
  void onMapCreated(mapbox.MapboxMap mapboxMapInstance) {
    mapboxMap = mapboxMapInstance;
    isMapReady.value = true;
  }

  /// Initialize map components after creation (iOS-safe)
  void _initializeMapAfterCreation() {
    _proceedWithMapInitialization();
  }

  void _proceedWithMapInitialization() {
    _setupCameraChangeListener();

    initializeMapData();

    // iOS FIX: If we have permission and location already, animate to it
    if (hasLocationPermission.value && currentLocation.value != null) {
      // Use platform-specific delays
      final delay = io.Platform.isIOS ? 2000 : 500;
      Future.delayed(Duration(milliseconds: delay), () async {
        await _moveCameraToCurrentLocation();
      });
    }
  }

  /// Handle style loaded callback
  void onStyleLoaded(mapbox.StyleLoadedEventData data) {
    loadMemoriesFromDB();

    Future.delayed(Duration(milliseconds: 1), () {
      _initializeMapAfterCreation();
      showLoadedDataOnMap();
    });
  }

  Future<void> showLoadedDataOnMap() async {
    await clearAllLines();
    await _setupMapboxClustering(_currentMemories);
    await generateAndDisplayArrowsAsSymbols(_currentMemories, mapboxMap!);
    handleMapTap();
  }

  /// Retry getting location permissions
  Future<void> retryLocationPermission() async {
    try {
      locationStatus.value = 'Checking permissions...';
      isLoadingLocation.value = true;

      await _initializeMap();

      // Force an immediate check to ensure UI updates right away
      await forcePermissionStateCheck();

      // If permission was granted, animate to user location
      if (hasLocationPermission.value) {
        await _ensureCameraAnimationToUserLocation();
      }
    } catch (e) {
      hasLocationPermission.value = false;
      isLoadingLocation.value = false;
      locationStatus.value = 'Error checking permissions';
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
    }
  }

  Future<void> loadMemoriesFromDB([
    List<Map<String, dynamic>>? filteredMemoriesData,
  ]) async {
    _memoryRepository ??= MemoryRepository();

    var memories =
        filteredMemoriesData ?? await _memoryRepository!.loadAllMemories();
    _currentMemories.clear();
    if (memories != null && memories.isNotEmpty) {
      // Store memories for tap handling
      _currentMemories.assignAll(memories);

      // Calculate and set appropriate zoom level based on memory spread
      await _setOptimalZoomForMemories(memories);
    } else {
      // Clear memories list
      _currentMemories.clear();
    }
  }

  /// Load a specific memory from database by ID
  /// Returns the memory as a single-item list, or empty list if not found
  Future<List<Map<String, dynamic>>> loadMemoryById(String memoryId) async {
    try {
      debugPrint('[MapControllerNew] 🔍 Loading memory by ID: $memoryId');

      _memoryRepository ??= MemoryRepository();

      // Load all memories from database
      var allMemories = await _memoryRepository!.loadAllMemories();

      if (allMemories == null || allMemories.isEmpty) {
        debugPrint('[MapControllerNew] ⚠️ No memories found in database');
        return [];
      }

      debugPrint('[MapControllerNew] 📊 Total memories in database: ${allMemories.length}');

      // Convert memoryId to int for comparison (database stores ID as int)
      final searchId = int.tryParse(memoryId);
      if (searchId == null) {
        debugPrint('[MapControllerNew] ⚠️ Invalid memory ID format: $memoryId');
        return [];
      }

      debugPrint('[MapControllerNew] 🔍 Searching for memory with ID: $searchId (int)');

      // Find the memory with matching ID (compare as int)
      final memory = allMemories.firstWhere(
        (m) {
          final dbId = m['id'];
          debugPrint('[MapControllerNew] 🔍 Comparing: $dbId (${dbId.runtimeType}) == $searchId (${searchId.runtimeType})');
          return dbId == searchId;
        },
        orElse: () => <String, dynamic>{},
      );

      if (memory.isEmpty) {
        debugPrint('[MapControllerNew] ⚠️ Memory not found with ID: $searchId');
        debugPrint('[MapControllerNew] 📋 Available IDs: ${allMemories.map((m) => m['id']).take(10).join(", ")}');
        return [];
      }

      debugPrint('[MapControllerNew] ✅ Found memory: ${memory['category'] ?? memory['description'] ?? 'Untitled'}');
      debugPrint('[MapControllerNew] 📝 Memory data: $memory');
      return [memory];
    } catch (e, stackTrace) {
      debugPrint('[MapControllerNew] ❌ Error loading memory by ID: $e');
      debugPrint('[MapControllerNew] Stack trace: $stackTrace');
      return [];
    }
  }

  /// Load filtered memories from database based on current filter settings
  /// Returns the filtered list without performing any other actions
  Future<List<Map<String, dynamic>>> loadFilteredMemoriesFromDB() async {
    try {
      debugPrint('[MapControllerNew] 🔍 Loading filtered memories from DB...');

      _memoryRepository ??= MemoryRepository();

      // If memory IDs filter is active, load only those specific memories
      if (selectedMemoryIds.isNotEmpty) {
        debugPrint('[MapControllerNew] 🎯 Memory IDs filter active: ${selectedMemoryIds.join(", ")}');

        var allMemories = await _memoryRepository!.loadAllMemories();
        if (allMemories == null || allMemories.isEmpty) {
          return [];
        }

        // Filter to only include memories with IDs in selectedMemoryIds
        final filteredMemories = allMemories.where((m) {
          final memoryId = m['id']?.toString();
          return selectedMemoryIds.contains(memoryId);
        }).toList();

        debugPrint('[MapControllerNew] ✅ Found ${filteredMemories.length} memories with IDs: ${selectedMemoryIds.join(", ")}');
        return filteredMemories;
      }

      // Load all memories from database
      var allMemories = await _memoryRepository!.loadAllMemories();

      if (allMemories == null || allMemories.isEmpty) {
        debugPrint('[MapControllerNew] ⚠️ No memories found in database');
        return [];
      }

      debugPrint(
        '[MapControllerNew] 📊 Total memories loaded: ${allMemories.length}',
      );

      // Check if any filters are active
      final hasFilters =
          filterValues.isNotEmpty ||
          selectedLocation.value.isNotEmpty ||
          selectedRadius.value.isNotEmpty ||
          selectedHashtags.isNotEmpty ||
          selectedContacts.isNotEmpty ||
          selectedCategories.isNotEmpty;

      if (!hasFilters) {
        debugPrint(
          '[MapControllerNew] ℹ️ No filters active, returning all memories',
        );
        return allMemories;
      }

      // Apply filters
      final filteredMemories = allMemories.where(_matchesFilters).toList();

      debugPrint(
        '[MapControllerNew] ✅ Filtered memories: ${filteredMemories.length}/${allMemories.length}',
      );
      debugPrint('[MapControllerNew] 📋 Active filters:');
      if (filterValues.isNotEmpty) {
        debugPrint('  - Text filters: ${filterValues.values.join(", ")}');
      }
      if (selectedHashtags.isNotEmpty) {
        debugPrint('  - Hashtags: ${selectedHashtags.join(", ")}');
      }
      if (selectedContacts.isNotEmpty) {
        debugPrint('  - Contacts: ${selectedContacts.join(", ")}');
      }
      if (selectedCategories.isNotEmpty) {
        debugPrint('  - Categories: ${selectedCategories.join(", ")}');
      }
      if (selectedLocation.value.isNotEmpty &&
          selectedRadius.value.isNotEmpty) {
        debugPrint(
          '  - Location: ${selectedLocation.value} (radius: ${selectedRadius.value}km)',
        );
      }

      return filteredMemories;
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error loading filtered memories: $e');
      return [];
    }
  }

  /// Calculate and set optimal zoom level based on memory locations (matching old controller)
  Future<void> _setOptimalZoomForMemories(
    List<Map<String, dynamic>> memories,
  ) async {
    if (memories.isEmpty || mapboxMap == null) {
      return;
    }

    try {
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
        final defaultZoom = MapboxZoomHelper().defaultZoom.value;
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

  Timer? _tapDelayTimer;
  String? _pendingTapType; // "cluster" or "memory"
  dynamic _pendingTapData;

  /// Called when cluster is tapped
  void onClusterTap(cluster) {
    debugPrint(
      '[MapControllerNew] Cluster tapped: ${cluster.id} (${cluster.count} memories)',
    );

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
            colorText: Colors.white,
            duration: const Duration(seconds: 2),
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
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
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
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
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
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
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
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
        return;
      }

      // Extract memory IDs from the cluster memories
      final memoryIds =
          clusterMemories
              .map((m) => m['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toList();

      debugPrint(
        '[MapControllerNew] 🔍 DRILL DOWN - Extracted ${memoryIds.length} memory IDs',
      );

      // Show bottom panel with memory IDs
      showLocationBottomPanel(Get.context!, memoryIds);

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
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// Show location bottom panel with memory IDs
  void showLocationBottomPanel(BuildContext context, List<String> memoryIds) {
    if (_isBottomPanelOpen) {
      debugPrint('[MapControllerNew] ⚠️ Bottom panel already open');
      return;
    }

    _isBottomPanelOpen = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BottomPanel(memoryIds: memoryIds),
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
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
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
      // AddMemoriesController is initialized in main.dart as permanent singleton
      final controller = Get.find<AddMemoriesController>();

      final memoryLocation = clustering.MemoryLocation.fromMap(
        normalizedMemory,
      );
      controller.isOpenedFromMap = true;
      controller.showSpecificMemories([memoryLocation]);

      final result = await Get.to(
        () => AddMemoriesView(),
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
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
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
      try {
        final memoryController = Get.find<MemoryController>();

        // Use the same data as memory view popups
        availableHashtags.value = List.from(memoryController.existingTags);
        availableContacts.value = List.from(memoryController.existingMentions);
        availableCategories.value = List.from(
          memoryController.existingCategories,
        );
      } catch (e) {
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
      }
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
        selectedCategories.isNotEmpty ||
        selectedMemoryIds.isNotEmpty;

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
    addMemoriesController.selectedMemoryIds
      ..clear()
      ..addAll(selectedMemoryIds);
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
    selectedMemoryIds
      ..clear()
      ..addAll(controller.selectedMemoryIds);
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
  Future<void> handleFilterApplyFromMap({List<int>? memoryIds}) async {
    // AddMemoriesController is initialized in main.dart as permanent singleton
    final addMemoriesController = Get.find<AddMemoriesController>();

    addMemoriesController.isOpenedFromMap = true;
    if(memoryIds == null) {
        addMemoriesController.applyFilters();
    }
    addMemoriesController.applyFilters(memoryIds: memoryIds);
    _syncFiltersFromAddMemoriesController(addMemoriesController);

    closeFilter();

    _updateFilterStatus();

    await _applyFiltersAndReloadMap();

    var memories = await addMemoriesController.syncFiltersAndLoadMemories();

    await loadMemoriesFromDB(memories);

    showLoadedDataOnMap();
  }

  /// Reset all filters
  void resetFilters() {
    final addMemoriesController = _getAddMemoriesControllerOrNull();
    addMemoriesController?.isOpenedFromMap = true;
    addMemoriesController?.resetFilters();

    filterValues.clear();
    selectedLocation.value = '';
    selectedRadius.value = '';
    addMemoriesController?.selectedLocationDisplayName.value = '';
    // selectedLocationDisplayName.value = '';

    selectedRadius.value = '';
    selectedHashtags.clear();
    selectedContacts.clear();
    selectedCategories.clear();
    selectedMemoryIds.clear();
    _updateFilterStatus();
    closeFilter();
    hasActiveFilters.value = false;
    _applyFiltersAndReloadMap();
  }

  /// Apply filters and reload map with filtered memories
  Future<void> _applyFiltersAndReloadMap() async {
    // try {
    //   debugPrint('[MapControllerNew] Applying filters and reloading map...');

    //   final addMemoriesController = _getAddMemoriesControllerOrNull();
    //   final bool filtersActive = hasActiveFilters.value;
    //   List<Map<String, dynamic>> memoriesToDisplay = [];

    //   if (addMemoriesController != null) {
    //     if (addMemoriesController.hasActiveFilters.value) {
    //       memoriesToDisplay = List<Map<String, dynamic>>.from(
    //         addMemoriesController.filteredMemories,
    //       );
    //     } else if (addMemoriesController.filteredMemories.isNotEmpty) {
    //       memoriesToDisplay = List<Map<String, dynamic>>.from(
    //         addMemoriesController.filteredMemories,
    //       );
    //     }
    //   }

    //   if (memoriesToDisplay.isEmpty) {
    //     if (addMemoriesController != null &&
    //         addMemoriesController.hasActiveFilters.value) {
    //       debugPrint(
    //         '[MapControllerNew] No memories matched active filters; clearing map markers',
    //       );
    //       await _setupMapboxClustering(memoriesToDisplay);
    //       return;
    //     }

    //     final allMemories = await _memoryRepository?.loadAllMemories();
    //     if (allMemories == null) {
    //       debugPrint('[MapControllerNew] No memories available for filtering');
    //       await _setupMapboxClustering([]);
    //       return;
    //     }

    //     if (filtersActive) {
    //       memoriesToDisplay = allMemories.where(_matchesFilters).toList();
    //     } else {
    //       memoriesToDisplay = List<Map<String, dynamic>>.from(allMemories);
    //     }
    //   }

    //   debugPrint(
    //     '[MapControllerNew] Preparing ${memoriesToDisplay.length} memories for clustering (filtersActive=$filtersActive)',
    //   );

    //   await _setupMapboxClustering(memoriesToDisplay);
    // } catch (e) {
    //   debugPrint('[MapControllerNew] Error applying filters: $e');
    //   // Fallback to loading all memories
    //   // loadMemoriesFromDB();
    // }
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
      debugPrint(
        '[MapControllerNew] ⚠️ Cannot calculate zoom - no map or memories',
      );
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
      if (validLocationCount == 0 ||
          minLat == null ||
          maxLat == null ||
          minLng == null ||
          maxLng == null) {
        debugPrint(
          '[MapControllerNew] ⚠️ No valid memory locations found for zoom calculation',
        );
        // Fallback to current location or default zoom
        await _fallbackToDefaultZoom();
        return;
      }

      // Calculate the spread (matching old controller logic)
      final double latDiff = maxLat - minLat;
      final double lngDiff = maxLng - minLng;
      final double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

      // Validate calculated differences
      if (latDiff.isNaN ||
          lngDiff.isNaN ||
          maxDiff.isNaN ||
          maxDiff.isInfinite) {
        debugPrint(
          '[MapControllerNew] ⚠️ Invalid bounds calculation, using fallback',
        );
        await _fallbackToDefaultZoom();
        return;
      }

      // Get zoom level based on geographical spread from MapboxZoomHelper
      double zoom = MapboxZoomHelper().getZoomForSpread(maxDiff);

      // Calculate center coordinates
      final centerLat = (minLat + maxLat) / 2;
      final centerLng = (minLng + maxLng) / 2;

      // Validate center coordinates before using them
      if (centerLat.isNaN ||
          centerLng.isNaN ||
          centerLat.isInfinite ||
          centerLng.isInfinite) {
        debugPrint(
          '[MapControllerNew] ⚠️ Invalid center coordinates, using fallback',
        );
        await _fallbackToDefaultZoom();
        return;
      }

      // Update current zoom variable
      currentZoom.value = zoom;

      debugPrint('[MapControllerNew] 📊 Memory spread analysis:');
      debugPrint(
        '[MapControllerNew] - Valid locations: $validLocationCount/${_currentMemories.length}',
      );
      debugPrint(
        '[MapControllerNew] - Lat range: $minLat to $maxLat (diff: $latDiff)',
      );
      debugPrint(
        '[MapControllerNew] - Lng range: $minLng to $maxLng (diff: $lngDiff)',
      );
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
        debugPrint(
          '[MapControllerNew] ✅ Fallback: Used current location with zoom ${currentZoom.value}',
        );
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
        debugPrint(
          '[MapControllerNew] ✅ Fallback: Used world center with zoom ${currentZoom.value}',
        );
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
    // Clear MapMarkerService annotations (old approach)
    if (_mapMarkerService != null) {
      await _mapMarkerService!.clearAll();
      debugPrint(
        '[MapControllerNew] MapMarkerService lines and markers cleared',
      );
    }

    // Clear native arrow layers (new approach)
    if (mapboxMap != null) {
      await removeLayerSafely(CLUSTERS_CIRCLE_LAYER_ID);
      await removeLayerSafely(ARROW_SYMBOLS_LAYER_ID);
      await removeLayerSafely(CLUSTERS_COUNT_LAYER_ID);
      await removeLayerSafely(UNCLUSTERED_LAYER_ID);
      await removeLayerSafely(CLUSTER_LAYER_ID);
      await removeLayerSafely(CLUSTER_COUNT_LAYER_ID);
      await removeLayerSafely(ARROW_LINES_LAYER_ID);
    }

    debugPrint('[MapControllerNew] ✅ All lines and arrows cleared');
  }

  Future<void> removeLayerSafely(String layerId) async {
    try {
      await mapboxMap!.style.removeStyleLayer(layerId);
      debugPrint('[MapControllerNew] Removed layer: $layerId');
    } catch (e) {
      debugPrint('[MapControllerNew] No layer to remove: $layerId');
    }
  }

  /// Refresh map view by reloading memories and updating markers
  Future<void> refreshMapView() async {
    debugPrint('[MapControllerNew] Refreshing map view');

    // Clear existing lines/arrows first
    await clearAllLines();

    // Reload memories from database
    // await loadMemoriesFromDB();

    // Refresh AddMemoriesController if it exists
    try {
      final addMemoriesController = Get.find<AddMemoriesController>();
      addMemoriesController.onAgainInit();
      debugPrint('[MapControllerNew] AddMemoriesController refreshed');
    } catch (e) {
      debugPrint('[MapControllerNew] AddMemoriesController not found: $e');
    }
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
      if (isMapReady.value &&
          mapboxMap != null &&
          currentLocation.value != null) {
        debugPrint(
          '[MapControllerNew] 🎯 iOS: Permission granted after map ready - forcing animation',
        );
        await Future.delayed(Duration(milliseconds: 500));
        await _moveCameraToCurrentLocation();
      }
    } catch (e) {
      debugPrint(
        '[MapControllerNew] Error getting location after permission granted: $e',
      );
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
    debugPrint(
      '[MapControllerNew] Error message: ${mapLoadingErrorEventData.message}',
    );
    debugPrint(
      '[MapControllerNew] Error type: ${mapLoadingErrorEventData.type}',
    );

    // Map errors are expected when using local tile server
    // The local tile server serves tiles via HTTP, so Mapbox style loads normally
    // No need to check for offline tiles or enable offline mode
    debugPrint(
      '[MapControllerNew] ℹ️ Map error logged - continuing with local tile server if available',
    );
  }

  /// Manually trigger layer visibility update (useful for testing or manual refresh)
  Future<void> updateLayerVisibility() async {
    if (mapboxMap == null) return;

    try {
      final cameraState = await mapboxMap!.getCameraState();
      final currentZoomLevel = cameraState.zoom;
      await _updateLayerVisibilityForZoom(currentZoomLevel);
      debugPrint(
        '[MapControllerNew] 🔄 Manual layer visibility update completed for zoom: $currentZoomLevel',
      );
    } catch (e) {
      debugPrint(
        '[MapControllerNew] ❌ Error in manual layer visibility update: $e',
      );
    }
  }

  /// Set up camera change listener to handle zoom-based layer visibility
  void _setupCameraChangeListener() {
    if (mapboxMap == null) return;

    try {
      debugPrint(
        '[MapControllerNew] 📹 Setting up zoom monitoring for layer visibility',
      );

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

        // SAFETY CHECK: Only update layer visibility if we're in the main map view
        // Check if the current route is the map view to avoid updating layers in other map instances
        // (e.g., location picker, memory location picker)
        if (Get.currentRoute == '/map-new' ||
            Get.currentRoute == '/map' ||
            Get.currentRoute == '/') {
          // Update layer visibility based on zoom level
          await _updateLayerVisibilityForZoom(currentZoomLevel);
        }
      }
    } catch (e) {
      // Silently ignore errors to avoid spam
    }
  }

  /// Update layer visibility based on current zoom level
  Future<void> _updateLayerVisibilityForZoom(double zoomLevel) async {
    // if (mapboxMap == null) return;

    // try {
    //   // Determine which layers should be visible at current zoom
    //   // Clusters: visible when zoomed out (below half zoom ~9.0)
    //   final showClusters = zoomLevel < _clusterVisibilityMaxZoom;
    //   // Individual memories: visible when zoomed in (above half zoom ~9.0)
    //   final showIndividual = zoomLevel >= _individualVisibilityMinZoom;
    //   // Details: visible at high zoom levels
    //   final showDetails = zoomLevel >= 0;

    //   // Update cluster layers visibility (show when zoomed out)
    //   await _setLayerVisibility(CLUSTER_LAYER_ID, showClusters);
    //   await _setLayerVisibility(CLUSTER_COUNT_LAYER_ID, showClusters);

    //   // Update individual memory layers visibility (show when zoomed in)
    //   // await _setLayerVisibility(UNCLUSTERED_LAYER_ID, showIndividual);
    //   await _setLayerVisibility(
    //     INDIVIDUAL_COUNT_LAYER_ID,
    //     showIndividual && showDetails,
    //   );
    // } catch (e) {
    //   debugPrint('[MapControllerNew] ❌ Error updating layer visibility: $e');
    // }
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
      debugPrint(
        '[MapControllerNew] 🎨 Set layer $layerId visibility to: $visibility',
      );
    } catch (e) {
      // Layer might not exist - this is normal when in other map views (location picker, etc.)
      // Silently ignore to avoid log spam
    }
  }

  void initializeMapData() {
    if (currentLocation.value != null) {
      _moveCameraToCurrentLocation();
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
      debugPrint(
        '[MapControllerNew] 📱 Screen coordinates: x=${tapPoint.coordinates.lng}, y=${tapPoint.coordinates.lat}',
      );
      debugPrint(
        '[MapControllerNew] 🎯 Target layers: [$CLUSTER_LAYER_ID, $UNCLUSTERED_LAYER_ID]',
      );

      // Get current zoom level for context
      try {
        final cameraState = await mapboxMap!.getCameraState();
        debugPrint(
          '[MapControllerNew] 🔍 Current zoom level: ${cameraState.zoom}',
        );
        debugPrint(
          '[MapControllerNew] 🗺️ Current center: ${cameraState.center.coordinates.lat}, ${cameraState.center.coordinates.lng}',
        );
      } catch (e) {
        debugPrint('[MapControllerNew] ⚠️ Could not get camera state: $e');
      }

      // Query features in cluster layer first (clusters have priority)
      // Query all cluster layer variants (small, medium, large, etc.)
      final clusterLayerIds = [CLUSTERS_CIRCLE_LAYER_ID, CLUSTER_LAYER_ID];

      debugPrint(
        '[MapControllerNew] 🔍 Querying cluster layers: $clusterLayerIds',
      );
      final clusterFeatures = await mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(
          mapbox.ScreenCoordinate(
            x: tapPoint.coordinates.lng.toDouble(),
            y: tapPoint.coordinates.lat.toDouble(),
          ),
        ),
        mapbox.RenderedQueryOptions(layerIds: clusterLayerIds),
      );

      debugPrint(
        '[MapControllerNew] 🌐 Cluster features found: ${clusterFeatures.length}',
      );

      // Log detailed cluster feature data
      for (int i = 0; i < clusterFeatures.length; i++) {
        final feature = clusterFeatures[i];
        if (feature != null) {
          debugPrint('[MapControllerNew] 📊 Cluster feature $i:');
          debugPrint(
            '[MapControllerNew]   - Feature type: ${feature.runtimeType}',
          );

          try {
            final queriedFeature = feature.queriedFeature;
            debugPrint(
              '[MapControllerNew]   - Queried feature type: ${queriedFeature.runtimeType}',
            );
            debugPrint(
              '[MapControllerNew]   - Feature data: ${queriedFeature.toString()}',
            );
          } catch (e) {
            debugPrint(
              '[MapControllerNew]   - Error accessing queried feature: $e',
            );
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
      debugPrint(
        '[MapControllerNew] 🔍 Querying individual memory layer: $UNCLUSTERED_LAYER_ID',
      );
      final individualFeatures = await mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(
          mapbox.ScreenCoordinate(
            x: tapPoint.coordinates.lng.toDouble(),
            y: tapPoint.coordinates.lat.toDouble(),
          ),
        ),
        mapbox.RenderedQueryOptions(layerIds: [UNCLUSTERED_LAYER_ID]),
      );

      debugPrint(
        '[MapControllerNew] 👤 Individual features found: ${individualFeatures.length}',
      );

      // Log detailed individual feature data
      for (int i = 0; i < individualFeatures.length; i++) {
        final feature = individualFeatures[i];
        if (feature != null) {
          debugPrint('[MapControllerNew] 📊 Individual feature $i:');
          debugPrint(
            '[MapControllerNew]   - Feature type: ${feature.runtimeType}',
          );

          try {
            final queriedFeature = feature.queriedFeature;
            debugPrint(
              '[MapControllerNew]   - Queried feature type: ${queriedFeature.runtimeType}',
            );
            debugPrint(
              '[MapControllerNew]   - Feature data: ${queriedFeature.toString()}',
            );
          } catch (e) {
            debugPrint(
              '[MapControllerNew]   - Error accessing queried feature: $e',
            );
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
      debugPrint(
        '[MapControllerNew] 🔍 Querying ALL features at tap point for debugging',
      );
      final allFeatures = await mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(
          mapbox.ScreenCoordinate(
            x: tapPoint.coordinates.lng.toDouble(),
            y: tapPoint.coordinates.lat.toDouble(),
          ),
        ),
        mapbox.RenderedQueryOptions(),
      );

      debugPrint(
        '[MapControllerNew] 🌍 Total features found: ${allFeatures.length}',
      );
      for (int i = 0; i < allFeatures.length && i < 10; i++) {
        // Limit to first 10 to avoid spam
        final feature = allFeatures[i];
        if (feature != null) {
          try {
            final queriedFeature = feature.queriedFeature;
            debugPrint(
              '[MapControllerNew] 📊 All feature $i: ${queriedFeature.toString()}',
            );
          } catch (e) {
            debugPrint(
              '[MapControllerNew] 📊 All feature $i: Error accessing - $e',
            );
          }
        }
      }

      // No features found, show location info
      debugPrint(
        '[MapControllerNew] 📍 No target features found at tap point, showing location info',
      );
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
  /// Implements smooth zoom-in behavior from CircleLayerClusteringPage
  Future<void> _handleClusterFeatureTap(
    mapbox.QueriedRenderedFeature clusterFeature,
    double lat,
    double lng,
  ) async {
    try {
      debugPrint(
        '[MapControllerNew] 🎯 Handling cluster feature tap at ($lat, $lng)',
      );

      // Extract cluster properties to get cluster_id and point_count
      final featureData = clusterFeature.queriedFeature.feature;
      final properties = featureData['properties'] as Map<String, dynamic>?;

      if (properties != null) {
        debugPrint('[MapControllerNew] 📊 Cluster Properties:');

        final clusterId = properties['cluster_id'];
        final pointCount = properties['point_count'];

        debugPrint('[MapControllerNew] - cluster_id: $clusterId');
        debugPrint('[MapControllerNew] - point_count: $pointCount');

        // Fetch all memory leaves (individual memories) in this cluster
        if (clusterId != null) {
          await _fetchAndLogClusterMemories(clusterId, pointCount ?? 0);
        } else {
          debugPrint('[MapControllerNew] ⚠️ No cluster_id found in properties');
        }
      } else {
        debugPrint(
          '[MapControllerNew] ⚠️ No properties found in cluster feature',
        );
      }

      // Get current zoom level
      final cameraState = await mapboxMap!.getCameraState();
      final currentZoomLevel = cameraState.zoom;

      debugPrint('[MapControllerNew] 📊 Current zoom: $currentZoomLevel');

      // Check if we're at high zoom level (close to clusterMaxZoom of 14)
      // If zoom >= 13, show cluster details instead of zooming further
      if (currentZoomLevel >= 13.0) {
        debugPrint(
          '[MapControllerNew] 🔍 High zoom level detected, showing cluster details',
        );

        // Fetch and show cluster memories in a bottom sheet
        if (properties != null && properties['cluster_id'] != null) {
          await _showClusterMemoriesBottomSheet(
            properties['cluster_id'],
            properties['point_count'] ?? 0,
            lat,
            lng,
          );
        } else {
          debugPrint(
            '[MapControllerNew] ⚠️ No cluster_id found, showing location info',
          );
          _showLocationInfo(lat, lng);
        }
      } else {
        // Zoom in smoothly (CircleLayerClusteringPage behavior)
        final newZoom = (currentZoomLevel + 2.0).clamp(0.0, 22.0);

        debugPrint(
          '[MapControllerNew] 🔍 Zooming into cluster: $currentZoomLevel → $newZoom',
        );

        await mapboxMap!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
            zoom: newZoom,
          ),
          mapbox.MapAnimationOptions(
            duration:
                800, // Smooth 800ms animation like CircleLayerClusteringPage
            startDelay: 0,
          ),
        );

        // Update reactive zoom variable
        currentZoom.value = newZoom;

        debugPrint('[MapControllerNew] ✅ Zoomed into cluster (zoom: $newZoom)');
      }
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error handling cluster feature tap: $e');
      _showLocationInfo(lat, lng);
    }
  }

  /// Fetch and log all memory IDs in a cluster using getGeoJsonClusterLeaves
  Future<void> _fetchAndLogClusterMemories(
    dynamic clusterId,
    int pointCount,
  ) async {
    try {
      debugPrint(
        '[MapControllerNew] 🔍 Fetching cluster leaves for cluster_id: $clusterId',
      );
      debugPrint('[MapControllerNew] 📊 Expected point count: $pointCount');

      // Create cluster feature map for querying
      final clusterFeature = {'cluster_id': clusterId};

      // Fetch all leaves (individual memories) in this cluster
      final result = await mapboxMap!.getGeoJsonClusterLeaves(
        MEMORY_SOURCE_ID,
        clusterFeature,
        0, // offset - start from first memory
        1000, // limit - fetch up to 1000 memories (should be enough)
      );

      final leavesData = result.value;

      if (leavesData == null) {
        debugPrint(
          '[MapControllerNew] ⚠️ No leaves data returned from cluster',
        );
        return;
      }

      debugPrint(
        '[MapControllerNew] 📦 Raw leaves data type: ${leavesData.runtimeType}',
      );
      debugPrint('[MapControllerNew] 📦 Raw leaves data: $leavesData');

      // Parse the GeoJSON FeatureCollection
      try {
        final leavesJson = jsonDecode(leavesData.toString());

        if (leavesJson is Map && leavesJson['type'] == 'FeatureCollection') {
          final features = leavesJson['features'] as List<dynamic>?;

          if (features != null && features.isNotEmpty) {
            debugPrint(
              '[MapControllerNew] ✅ Found ${features.length} memories in cluster',
            );
            debugPrint('[MapControllerNew] 🎯 Memory IDs in cluster:');

            final memoryIds = <String>[];
            for (int i = 0; i < features.length; i++) {
              final feature = features[i] as Map<String, dynamic>;
              final properties = feature['properties'] as Map<String, dynamic>?;

              if (properties != null) {
                final memoryId = properties['id'];
                final memoryTitle = properties['title'] ?? 'Untitled';
                final memoryDate = properties['memory_date'] ?? '';

                memoryIds.add(memoryId.toString());

                debugPrint('[MapControllerNew]   [$i] ID: $memoryId');
                debugPrint('[MapControllerNew]       Title: $memoryTitle');
                debugPrint('[MapControllerNew]       Date: $memoryDate');
              }
            }

            debugPrint(
              '[MapControllerNew] 📋 All Memory IDs: ${memoryIds.join(', ')}',
            );
          } else {
            debugPrint(
              '[MapControllerNew] ⚠️ No features found in FeatureCollection',
            );
          }
        } else {
          debugPrint(
            '[MapControllerNew] ⚠️ Unexpected leaves data format: ${leavesJson.runtimeType}',
          );
        }
      } catch (parseError) {
        debugPrint(
          '[MapControllerNew] ❌ Error parsing leaves JSON: $parseError',
        );
        debugPrint('[MapControllerNew] Raw data: $leavesData');
      }
    } catch (e, stackTrace) {
      debugPrint('[MapControllerNew] ❌ Error fetching cluster memories: $e');
      debugPrint('[MapControllerNew] Stack trace: $stackTrace');
    }
  }

  /// Show cluster memories in a bottom sheet
  ///
  /// This method supports TWO approaches to get cluster memories:
  ///
  /// **Approach 1: Using pre-aggregated memory IDs (FASTER)**
  /// - Memory IDs are stored in cluster properties during GeoJSON creation
  /// - Uses `clusterProperties` with reduce expressions to aggregate IDs
  /// - Avoids additional API calls to fetch cluster leaves
  /// - Best for performance when you need to fetch from database
  ///
  /// **Approach 2: Using getGeoJsonClusterLeaves (MORE FLEXIBLE)**
  /// - Fetches individual features from the cluster dynamically
  /// - Returns full GeoJSON features with all properties
  /// - No need to query database separately
  /// - Best when you need all feature properties
  ///
  /// Parameters:
  /// - [clusterId]: The cluster ID from Mapbox
  /// - [pointCount]: Number of points in the cluster
  /// - [lat], [lng]: Cluster center coordinates
  /// - [memoryIdsString]: Optional comma-separated memory IDs from cluster properties
  Future<void> _showClusterMemoriesBottomSheet(
    dynamic clusterId,
    int pointCount,
    double lat,
    double lng, {
    String?
    memoryIdsString, // Optional: pre-aggregated memory IDs from cluster properties
  }) async {
    try {
      debugPrint('[MapControllerNew] 📋 Showing cluster memories bottom sheet');

      // APPROACH 1: If memory IDs are provided in cluster properties, use them (FAST)
      if (memoryIdsString != null && memoryIdsString.isNotEmpty) {
        final memoryIds =
            memoryIdsString
                .split(',')
                .where((id) => id.trim().isNotEmpty)
                .map((id) => id.trim())
                .toList();

        debugPrint(
          '[MapControllerNew] 💾 Using pre-aggregated memory IDs (${memoryIds.length}): ${memoryIds.join(', ')}',
        );

        // Show BottomPanel with memory IDs
        if (_isBottomPanelOpen) {
          debugPrint('[MapControllerNew] ⚠️ Bottom panel already open');
          return;
        }

        _isBottomPanelOpen = true;

        await showModalBottomSheet(
          context: Get.context!,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => BottomPanel(memoryIds: memoryIds),
        ).whenComplete(() {
          _isBottomPanelOpen = false;
          debugPrint('[MapControllerNew] Bottom panel closed');
        });

        return;
      }

      // APPROACH 2: Use getGeoJsonClusterLeaves to fetch full GeoJSON features (FALLBACK)
      debugPrint(
        '[MapControllerNew] 🔍 Fetching cluster leaves using getGeoJsonClusterLeaves...',
      );

      // Create cluster feature map for querying
      final clusterFeature = {'cluster_id': clusterId};

      // Fetch all leaves (individual memories) in this cluster
      final result = await mapboxMap!.getGeoJsonClusterLeaves(
        MEMORY_SOURCE_ID,
        clusterFeature,
        0, // offset
        1000, // limit
      );

      final leavesData = result.value;

      if (leavesData == null) {
        debugPrint(
          '[MapControllerNew] ⚠️ No leaves data returned from cluster',
        );
        Get.snackbar(
          'Error',
          'Could not load cluster memories',
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 2),
        );
        return;
      }

      // Parse the GeoJSON FeatureCollection
      final leavesJson = jsonDecode(leavesData.toString());

      if (leavesJson is! Map || leavesJson['type'] != 'FeatureCollection') {
        debugPrint('[MapControllerNew] ⚠️ Unexpected leaves data format');
        return;
      }

      final features = leavesJson['features'] as List<dynamic>?;

      if (features == null || features.isEmpty) {
        debugPrint('[MapControllerNew] ⚠️ No features found in cluster');
        return;
      }

      // Extract memory data from features
      final memories = <Map<String, dynamic>>[];
      for (final feature in features) {
        final properties =
            (feature as Map<String, dynamic>)['properties']
                as Map<String, dynamic>?;
        if (properties != null) {
          memories.add(properties);
        }
      }

      debugPrint(
        '[MapControllerNew] ✅ Showing ${memories.length} memories in bottom sheet',
      );

      // Show bottom sheet with cluster memories
      Get.bottomSheet(
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cluster Memories (${memories.length})',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Get.back(),
                    ),
                  ],
                ),
              ),
              // Memory list
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: memories.length,
                  itemBuilder: (context, index) {
                    final memory = memories[index];
                    final memoryId = memory['id'];
                    final title = memory['title'] ?? 'Untitled';
                    final date = memory['memory_date'] ?? '';
                    final description = memory['description'] ?? '';
                    final hasImages = memory['has_images'] == true;
                    final hasAudios = memory['has_audios'] == true;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: Icon(
                          hasImages ? Icons.image : Icons.location_on,
                          color: Colors.blue,
                        ),
                      ),
                      title: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (date.isNotEmpty)
                            Text(
                              date,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          if (description.isNotEmpty)
                            Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasImages)
                            const Icon(
                              Icons.image,
                              size: 16,
                              color: Colors.blue,
                            ),
                          if (hasAudios)
                            const Icon(
                              Icons.audiotrack,
                              size: 16,
                              color: Colors.orange,
                            ),
                        ],
                      ),
                      onTap: () {
                        debugPrint(
                          '[MapControllerNew] 📝 Memory tapped: $memoryId',
                        );
                        Get.back(); // Close bottom sheet
                        // TODO: Navigate to memory detail page
                        Get.snackbar(
                          'Memory Selected',
                          title,
                          snackPosition: SnackPosition.BOTTOM,
                          duration: const Duration(seconds: 2),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        isScrollControlled: true,
        enableDrag: true,
      );
    } catch (e, stackTrace) {
      debugPrint('[MapControllerNew] ❌ Error showing cluster memories: $e');
      debugPrint('[MapControllerNew] Stack trace: $stackTrace');
      Get.snackbar(
        'Error',
        'Could not load cluster memories',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// Find the nearest cluster to the given coordinates
  models.MemoryCluster? _findNearestCluster(double lat, double lng) {
    if (currentClusters.isEmpty) return null;

    models.MemoryCluster? nearestCluster;
    double minDistance = double.infinity;
    const double maxDistance = 0.001; // ~100m tolerance

    for (final cluster in currentClusters) {
      final distance = _calculateDistance(
        lat,
        lng,
        cluster.latitude,
        cluster.longitude,
      );
      if (distance < minDistance && distance < maxDistance) {
        minDistance = distance;
        nearestCluster = cluster;
      }
    }

    return nearestCluster;
  }

  /// Calculate distance between two coordinates (simple Euclidean distance)
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = lat1 - lat2;
    final dLng = lng1 - lng2;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  /// Show all memories in a cluster
  Future<void> _showClusterMemories(models.MemoryCluster cluster) async {
    try {
      debugPrint(
        '[MapControllerNew] 📋 Showing ${cluster.memories.length} memories from cluster ${cluster.id}',
      );

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
      debugPrint(
        '[MapControllerNew] 🎯 Handling individual memory feature tap at ($lat, $lng)',
      );

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
      debugPrint(
        '[MapControllerNew] ❌ Error handling individual feature tap: $e',
      );
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
    debugPrint(
      '[MapControllerNew] 🔄 Using fallback location-based tap handling',
    );

    if (_mapMarkerService != null &&
        (currentClusters.isNotEmpty || _currentMemories.isNotEmpty)) {
      // Get current zoom level for dynamic tap radius
      double? currentZoom;
      if (mapboxMap != null) {
        try {
          final cameraState = await mapboxMap!.getCameraState();
          currentZoom = cameraState.zoom;
        } catch (e) {
          debugPrint(
            '[MapControllerNew] Could not get zoom level for fallback tap: $e',
          );
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

  /// Load custom cluster icons into the map style
  Future<void> _loadClusterIcons() async {
    if (mapboxMap == null) return;

    try {
      debugPrint('[MapControllerNew] 🎨 Loading custom cluster icons...');

      // Generate cluster icon set using defined size tiers
      final icons = await ClusterIconGenerator.generateClusterIconSet(
        counts: CLUSTER_SIZE_TIERS,
        size: 30.0,
      );

      // Add each icon to the map style
      for (final entry in icons.entries) {
        final iconName = entry.key;
        final iconData = entry.value;

        try {
          await mapboxMap!.style.addStyleImage(
            iconName,
            1.0, // scale
            mapbox.MbxImage(width: 30, height: 30, data: iconData),
            false, // sdf (signed distance field)
            [], // stretchX
            [], // stretchY
            null, // content
          );
          debugPrint('[MapControllerNew] ✅ Added cluster icon: $iconName');
        } catch (e) {
          debugPrint('[MapControllerNew] ❌ Failed to add icon $iconName: $e');
        }
      }

      // Generate and add individual point icon
      debugPrint('[MapControllerNew] 🎨 Generating individual point icon...');

      debugPrint('[MapControllerNew] ✅ All cluster icons loaded successfully');
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error loading cluster icons: $e');
    }
  }

  /// Add MapBox cluster layers with enhanced styling and proper layer ordering
  /// Uses custom circular icons instead of text labels
  Future<void> _addClusterLayers(List<Map<String, dynamic>> memories) async {
    if (mapboxMap == null) return;

    try {
      debugPrint(
        '[MapControllerNew] 🎨 Adding enhanced cluster layers with custom icons...',
      );

      // Load custom cluster icons first
      // await _loadClusterIcons();

      // Get all style layers to find proper insertion point
      final layers = await mapboxMap!.style.getStyleLayers();
      debugPrint('[MapControllerNew] Total layers found: ${layers.length}');

      // Find the first symbol layer for proper ordering
      String? labelLayerId = layers.last!.id;

      try {
        await mapboxMap!.style.addLayer(
          mapbox.CircleLayer(
            id: CLUSTERS_CIRCLE_LAYER_ID,
            sourceId: MEMORY_SOURCE_ID,
            filter: ['has', 'point_count'],

            // Initial simple paint; will refine via setStyleLayerProperty below if needed
            circleColor: 0xFF11B4DA, // default (will be overridden)
            circleRadius: 12.0,
            circleStrokeWidth: 5.0,
            circleStrokeColor: 0xFFFFFFFF,
            circleOpacity: 1.0,
          ),
        );
        await mapboxMap!.style.setStyleLayerProperty(
          CLUSTERS_CIRCLE_LAYER_ID,
          'circle-color',
          [
            'step',
            ['get', 'point_count'],
            '#51bbd6', // <= first threshold
            100, '#f1f075',
            750, '#f28cb1',
          ],
        );
      } catch (_) {}

      // Optional: use expressions for circle-color / circle-radius by point_count

      // await mapboxMap!.style.setStyleLayerProperty(
      //   CLUSTERS_CIRCLE_LAYER_ID,
      //   'circle-radius',
      //   [
      //     'step',
      //     ['get', 'point_count'],
      //     10.0,
      //     100,
      //     10.0,
      //     750,
      //     10.0,
      //   ],
      // );
    try {

    }catch(_) {


    }

    try {
 await mapboxMap!.style.addLayer(
        mapbox.SymbolLayer(
          id: CLUSTERS_COUNT_LAYER_ID,
          sourceId: MEMORY_SOURCE_ID,
          filter: ['has', 'point_count'],
          textField: '', // or null; gets overridden
          textSize: 14.0,
          textColor: 0xFFFFFFFF,
          textIgnorePlacement: true,
          textAllowOverlap: true,
        ),
      );

      await mapboxMap!.style.setStyleLayerProperty(
        CLUSTERS_COUNT_LAYER_ID,
        'text-field',
        ['get', 'point_count_abbreviated'],
      );
    }catch(_) {

      
    }
      // 2) Cluster count text (symbol layer)
     

      debugPrint(
        '[MapControllerNew] ✅ All ${CLUSTER_SIZE_TIERS.length} cluster icon layers added',
      );

      // Layer 2: Individual memory points using custom icon
      debugPrint(
        '[MapControllerNew] 🎨          Adding individual point layer...',
      );
      try {
        await mapboxMap!.style.addLayer(
          mapbox.CircleLayer(
            id: UNCLUSTERED_LAYER_ID,
            sourceId: MEMORY_SOURCE_ID,
            filter: [
              '!',
              ['has', 'point_count'],
            ],
            circleColor: 0xFF11B4DA, // default (will be overridden)
            circleRadius: 12.0,
            circleStrokeWidth: 5.0,
            circleStrokeColor: 0xFFFFFFFF,
            circleOpacity: 1.0,
          ),
        );

        try {
          await mapboxMap!.style.setStyleLayerProperty(
            UNCLUSTERED_LAYER_ID,
            'circle-color',
            [
              'match',
              ['get', 'toMemoryYear'],
              2020.0, Colors.red.value.toRGBA(),
              2021.0, Colors.green.value.toRGBA(),
              2022.0, Colors.purple.value.toRGBA(),
              2023.0, Colors.purple.value.toRGBA(),
              2024.0, Colors.deepOrange.value.toRGBA(),
              2025.0, Colors.orange.value.toRGBA(),
              2026.0, Colors.pink.value.toRGBA(),
              Colors.blue.value.toRGBA(), // Default
            ],
          );
        } catch (e) {
          print('MapControllerNew toMemoryYear circle-color erro $e');
        }
        debugPrint('[MapControllerNew] ✅ Fallback circle layer added');

        debugPrint('[MapControllerNew] ✅ Individual point icon layer added');
      } catch (e) {
        debugPrint(
          '[MapControllerNew] ❌ Failed to add individual icon layer: $e',
        );
        // Fallback: use circle layer if icon fails
        debugPrint(
          '[MapControllerNew] 🔄 Adding fallback circle layer for individual points...',
        );

            // );
    try {
 await mapboxMap!.style.addLayer(
          mapbox.CircleLayer(
            id: UNCLUSTERED_LAYER_ID,
            sourceId: MEMORY_SOURCE_ID,
            filter: [
              '!',
              ['has', 'point_count'],
            ],
            circleColor: 0xFF11B4DA,
            circleRadius: 12.0,
            circleStrokeWidth: .0,
            circleStrokeColor: 0xFFFFFFFF,
            circleOpacity: 1.0,
          ),
        );
    }catch(_) {


    }
       

        try {
          await mapboxMap!.style.setStyleLayerProperty(
            UNCLUSTERED_LAYER_ID,
            'circle-color',
            [
              'match',
              ['get', 'toMemoryYear'],
              2020.0, Colors.red.value.toRGBA(),
              2021.0, Colors.green.value.toRGBA(),
              2022.0, Colors.purple.value.toRGBA(),
              2023.0, Colors.purple.value.toRGBA(),
              2024.0, Colors.deepOrange.value.toRGBA(),
              2025.0, Colors.orange.value.toRGBA(),
              2026.0, Colors.pink.value.toRGBA(),
              Colors.blue.value.toRGBA(), // Default
            ],
          );
        } catch (e) {
          print('MapControllerNew toMemoryYear circle-color erro $e');
        }
        debugPrint('[MapControllerNew] ✅ Fallback circle layer added');
      }

      // Note: Individual points now use icon with embedded "1" text
      // No separate text layer needed since the icon includes the number
      debugPrint(
        '[MapControllerNew] ✅ Individual point icon includes embedded "1" text',
      );
      // Move all cluster layers above the symbol/label layer for proper ordering
      if (labelLayerId != null) {
        // Move all cluster size tiers
        final clusterLayerIds = [];

        for (final layerId in clusterLayerIds) {
          await mapboxMap!.style.moveStyleLayer(
            layerId,
            mapbox.LayerPosition(above: labelLayerId),
          );
        }

        // Move individual points icon layer (includes embedded "1" text)
        await mapboxMap!.style.moveStyleLayer(
          UNCLUSTERED_LAYER_ID,
          mapbox.LayerPosition(above: labelLayerId),
        );

        debugPrint(
          '[MapControllerNew] ✅ Moved all cluster icon layers above symbol layer: $labelLayerId',
        );
      } else {
        debugPrint(
          '[MapControllerNew] ⚠️ No symbol layer found, layers added on top',
        );
      }

      // Verify individual layer was added
      final layerExists = await mapboxMap!.style.styleLayerExists(
        UNCLUSTERED_LAYER_ID,
      );
      debugPrint('[MapControllerNew] 🔍 Individual layer exists: $layerExists');

      if (layerExists) {
        // Check current zoom level
        final cameraState = await mapboxMap!.getCameraState();
        final currentZoom = cameraState.zoom;
        debugPrint(
          '[MapControllerNew] 🔍 Current zoom: $currentZoom (individual points show at zoom >= 14)',
        );

        if (currentZoom < 14) {
          debugPrint(
            '[MapControllerNew] ⚠️ Zoom in to level 14+ to see individual points',
          );
        }
      }

      debugPrint(
        '[MapControllerNew] ✅ Successfully added all enhanced cluster layers',
      );
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error adding cluster layers: $e');
      // rethrow;
    }
  }

  /// Call this on map tap - Add interactions for individual markers AND clusters
  Future<void> handleMapTap() async {
    if (mapboxMap == null) {
      debugPrint('[MapControllerNew] ⚠️ Map not ready for adding interactions');
      return;
    }

    try {
      final clusterLayerIds = [
        CLUSTERS_CIRCLE_LAYER_ID,
        CLUSTERS_COUNT_LAYER_ID,
        CLUSTER_LAYER_ID,
        CLUSTER_COUNT_LAYER_ID,
      ];

      for (final layerId in clusterLayerIds) {
        try {
          debugPrint(
            '[MapControllerNew] 🎯 Adding tap interaction for cluster layer: $layerId',
          );

          mapboxMap!.addInteraction(
            mapbox.TapInteraction(
              mapbox.FeaturesetDescriptor(layerId: layerId),
              (feature, context) async {
                await _handleClusterMarkerTap(feature, layerId, context);
              },
            ),
            interactionID: "clusterTapInteraction_$layerId",
          );
        } catch (e) {
          debugPrint(
            '[MapControllerNew] ⚠️ Could not add interaction for $layerId: $e',
          );
        }
      }

      // ========== INDIVIDUAL MARKER INTERACTIONS ==========
      // Add tap interaction for individual memory markers (icon layer)
      debugPrint(
        '[MapControllerNew] 🎯 Adding tap interaction for $UNCLUSTERED_LAYER_ID',
      );

      mapboxMap!.addInteraction(
        mapbox.TapInteraction(
          mapbox.FeaturesetDescriptor(layerId: UNCLUSTERED_LAYER_ID),
          (feature, context) async {
            await _handleIndividualMarkerTap(feature, 'UNCLUSTERED_LAYER');
          },
        ),
        interactionID: "individualMarkerTapInteraction",
      );

      // Add tap interaction for individual memory count labels
      debugPrint(
        '[MapControllerNew] 🎯 Adding tap interaction for $INDIVIDUAL_COUNT_LAYER_ID',
      );

      mapboxMap!.addInteraction(
        mapbox.TapInteraction(
          mapbox.FeaturesetDescriptor(layerId: INDIVIDUAL_COUNT_LAYER_ID),
          (feature, context) async {
            await _handleIndividualMarkerTap(feature, 'INDIVIDUAL_COUNT_LAYER');
          },
        ),
        interactionID: "individualCountTapInteraction",
      );

      debugPrint(
        '[MapControllerNew] ✅ All tap interactions (clusters + individual markers) added successfully',
      );
    } catch (e, stackTrace) {
      debugPrint('[MapControllerNew] ❌ Error adding tap interactions: $e');
      debugPrint('[MapControllerNew] Stack trace: $stackTrace');
    }
  }

  /// Handle tap on cluster marker
  /// This is called when user taps on any cluster layer
  Future<void> _handleClusterMarkerTap(
    mapbox.TypedFeaturesetFeature<mapbox.FeaturesetDescriptor> feature,
    String layerName,
    mapbox.MapContentGestureContext context,
  ) async {
    try {
      debugPrint(
        '[MapControllerNew] 🎯 Cluster marker tapped on layer: $layerName',
      );
      debugPrint('[MapControllerNew] Feature: $feature');

      final properties = feature.properties;

      // Debug: Print ALL properties to see what's available
      debugPrint('[MapControllerNew] 📋 ALL Feature properties:');

      properties.forEach((key, value) {
        debugPrint(
          '[MapControllerNew]   - $key: $value (${value.runtimeType})',
        );
      });

      if (properties.isEmpty) {
        debugPrint(
          '[MapControllerNew] ⚠️ No properties found in cluster feature',
        );

        return;
      }

      // Extract cluster information
      final clusterId = properties['cluster_id'];
      final pointCountRaw = properties['point_count'];
      final pointCount =
          (pointCountRaw is int)
              ? pointCountRaw
              : (pointCountRaw is double)
              ? pointCountRaw.toInt()
              : 0;

      // Extract aggregated memory IDs from cluster properties
      final memoryIdsString = properties['memory_ids'].toString() ?? '';
      final memoryCount = properties['memory_count'];

      // Get coordinates from context
      final coordinates = context.point.coordinates;
      final lat = coordinates.lat.toDouble();
      final lng = coordinates.lng.toDouble();

      debugPrint('[MapControllerNew] 📊 Cluster Details:');
      debugPrint('[MapControllerNew] - cluster_id: $clusterId');
      debugPrint('[MapControllerNew] - point_count: $pointCount');
      debugPrint('[MapControllerNew] - memory_count: $memoryCount');
      debugPrint('[MapControllerNew] - memory_ids (raw): $memoryIdsString');
      debugPrint('[MapControllerNew] - Location: ($lat, $lng)');

      // Parse memory IDs from the aggregated string
      if (memoryIdsString.isNotEmpty) {
        final memoryIds =
            memoryIdsString
                .split(',')
                .where((id) => id.trim().isNotEmpty)
                .map((id) => id.trim())
                .toList();

        debugPrint(
          '[MapControllerNew] 📋 Showing BottomPanel with ${memoryIds.length} memory IDs',
        );

        // Show BottomPanel with memory IDs
        showLocationBottomPanel(Get.context!, memoryIds);
        //  BottomPanel
      }

      // Get current zoom level
      final cameraState = await mapboxMap!.getCameraState();
      final currentZoomLevel = cameraState.zoom;

      debugPrint('[MapControllerNew] 📊 Current zoom: $currentZoomLevel');

      if (currentZoomLevel >= 13.0) {
        debugPrint(
          '[MapControllerNew] 🔍 High zoom level detected, showing cluster details',
        );

        // Parse memory IDs and show BottomPanel
        if (memoryIdsString.isNotEmpty) {
          final memoryIds =
              memoryIdsString
                  .split(',')
                  .where((id) => id.trim().isNotEmpty)
                  .map((id) => id.trim())
                  .toList();

          debugPrint(
            '[MapControllerNew] 📋 Showing BottomPanel with ${memoryIds.length} memory IDs',
          );

          // Show BottomPanel with memory IDs
          showLocationBottomPanel(Get.context!, memoryIds);
        } else {
          debugPrint(
            '[MapControllerNew] ⚠️ No memory IDs found, showing snackbar',
          );
          Get.snackbar(
            'Cluster',
            '$pointCount memories at this location',
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 2),
          );
        }
      } else {
        // Zoom in smoothly
        final newZoom = (currentZoomLevel + 2.0).clamp(0.0, 22.0);

        debugPrint(
          '[MapControllerNew] 🔍 Zooming into cluster: $currentZoomLevel → $newZoom',
        );

        await mapboxMap!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
            zoom: newZoom,
          ),
          mapbox.MapAnimationOptions(
            duration: 800, // Smooth 800ms animation
            startDelay: 0,
          ),
        );

        // Update reactive zoom variable
        currentZoom.value = newZoom;

        debugPrint('[MapControllerNew] ✅ Zoomed into cluster (zoom: $newZoom)');
      }
    } catch (e, stackTrace) {
      debugPrint('[MapControllerNew] ❌ Error handling cluster marker tap: $e');
      debugPrint('[MapControllerNew] Stack trace: $stackTrace');
    }
  }

  /// Handle tap on individual memory marker
  /// This is called when user taps on UNCLUSTERED_LAYER_ID or INDIVIDUAL_COUNT_LAYER_ID
  Future<void> _handleIndividualMarkerTap(
    mapbox.TypedFeaturesetFeature<mapbox.FeaturesetDescriptor> feature,
    String layerName,
  ) async {
    try {
      debugPrint(
        '[MapControllerNew] 🎯 Individual marker tapped on layer: $layerName',
      );
      debugPrint('[MapControllerNew] Feature: $feature');
      debugPrint(
        '[MapControllerNew] Feature properties: ${feature.properties}',
      );

      final properties = feature.properties;

      if (properties == null || properties.isEmpty) {
        debugPrint('[MapControllerNew] ⚠️ No properties found in feature');
        return;
      }

      // Extract memory ID from properties
      final rawMemoryId = properties['id'].toString();
      if (rawMemoryId.isEmpty) {
        debugPrint('[MapControllerNew] ⚠️ No memory ID found in properties');
        return;
      }

      // Clean the memory ID - remove any non-numeric characters (like trailing commas)
      final memoryId = rawMemoryId.replaceAll(RegExp(r'[^0-9]'), '').trim();

      debugPrint('[MapControllerNew] 🔍 Raw memory ID: "$rawMemoryId" -> Cleaned: "$memoryId"');
      debugPrint('[MapControllerNew] 📊 Total memories in _currentMemories: ${_currentMemories.length}');

      // Find the memory from _currentMemories using the ID
      // Database stores ID as int, so we need to compare properly
      Map<String, dynamic>? foundMemory;

      for (var data in _currentMemories) {
        final dbId = data['id']?.toString().trim();
        debugPrint('[MapControllerNew] 🔍 Comparing: DB ID="$dbId" vs Search ID="$memoryId"');

        if (dbId == memoryId) {
          debugPrint('[MapControllerNew] ✅ Memory found with ID: $memoryId');
          foundMemory = data;
          break;
        }
      }

      if (foundMemory == null) {
        debugPrint('[MapControllerNew] ⚠️ Memory not found in _currentMemories with ID: $memoryId');
        debugPrint('[MapControllerNew] 📋 Available IDs: ${_currentMemories.map((m) => m['id']).take(10).join(", ")}');
        Get.snackbar(
          '⚠️ Error',
          'Memory not found',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      // Convert to MemoryLocation object
      clustering.MemoryLocation? memoryLocation;
      try {
        memoryLocation = clustering.MemoryLocation.fromMap(foundMemory);
      } catch (e) {
        debugPrint('[MapControllerNew] ❌ Failed to create MemoryLocation: $e');
        Get.snackbar(
          '⚠️ Error',
          'Failed to load memory details',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
        return;
      }

      // Get AddMemoriesController
      final controller = Get.find<AddMemoriesController>();

      // Show the specific memory in AddMemories view
      // controller.showSpecificMemories([memoryLocation]);

      // Apply filter with the memory ID
      final memoryIdInt = int.tryParse(memoryId);
      if (memoryIdInt != null) {
      controller.applyFilters(memoryIds: [memoryIdInt]);
        await loadFilteredMemoriesFromDB();
        handleFilterApplyFromMap();
        debugPrint('[MapControllerNew] 🎯 Applied memory IDs filter: [$memoryIdInt]');
      }

      debugPrint('[MapControllerNew] 🎯 Navigating to AddMemories view with memory: ${foundMemory['category'] ?? foundMemory['description']}');

      final result = await Get.toNamed(Routes.ADD_MEMORIES);

      // If memories were edited/deleted, refresh the map
      // if (result == true) {
      //   await refreshMapView();
      //   debugPrint('[MapControllerNew] ✅ Map refreshed after memory editing');
      // }
    } catch (e, stackTrace) {
      debugPrint(
        '[MapControllerNew] ❌ Error handling individual marker tap: $e',
      );
      debugPrint('[MapControllerNew] Stack trace: $stackTrace');
    }
  }

  void _getClusterLeaves(int clusterId) async {}

  Future<void> _updateInitialLayerVisibility() async {
    if (mapboxMap == null) return;

    // try {
    //   final cameraState = await mapboxMap!.getCameraState();
    //   final currentZoomLevel = cameraState.zoom;

    //   _lastKnownZoom = currentZoomLevel;
    //   currentZoom.value = currentZoomLevel;

    //   debugPrint(
    //     '[MapControllerNew] 🎯 Setting initial layer visibility for zoom: $currentZoomLevel',
    //   );

    //   await _updateLayerVisibilityForZoom(currentZoomLevel);
    // } catch (e) {
    //   debugPrint(
    //     '[MapControllerNew] ❌ Error setting initial layer visibility: $e',
    //   );
    // }
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

  List<List<double>> _createMinorCurvedLine({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    double curvature = 0.001, // 0.1% curve for nearly straight lines
  }) {
    final midLat = (startLat + endLat) / 2;
    final midLng = (startLng + endLng) / 2;

    final dx = endLng - startLng;
    final dy = endLat - startLat;
    final length = math.sqrt(dx * dx + dy * dy);

    if (length == 0) {
      return [
        [startLng, startLat],
        [endLng, endLat],
      ];
    }

    final offsetLat = midLat + (-dx / length) * curvature;
    final offsetLng = midLng + (dy / length) * curvature;

    return [
      [startLng, startLat],
      [offsetLng, offsetLat],
      [endLng, endLat],
    ];
  }

  Future<void> _addHardcodedArrow(mapbox.MapboxMap mapboxMap) async {
    const String ARROW_LINES_SOURCE_ID = 'arrow_lines_source';
    const String ARROW_LINES_LAYER_ID = 'arrow_lines_layer';

    try {
      // 1️⃣ Remove old layer if exists
      try {
        await mapboxMap.style.removeStyleLayer(ARROW_LINES_LAYER_ID);
        debugPrint('[Arrow] Removed existing layer');
      } catch (_) {
        debugPrint('[Arrow] No existing layer to remove');
      }

      // 2️⃣ Remove old source if exists
      try {
        await mapboxMap.style.removeStyleSource(ARROW_LINES_SOURCE_ID);
        debugPrint('[Arrow] Removed existing source');
      } catch (_) {
        debugPrint('[Arrow] No existing source to remove');
      }

      // 3️⃣ Add GeoJSON source with hardcoded coordinates (Islamabad → Karachi)
      await mapboxMap.style.addSource(
        mapbox.GeoJsonSource(
          id: ARROW_LINES_SOURCE_ID, // e.g. "arrow_lines"
          data: '''
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "geometry": {
        "type": "LineString",
        "coordinates": [
          [73.0479, 33.6844],
          [67.0011, 24.8607]
        ]
      },
      "properties": {
        "from": "Islamabad",
        "to": "Karachi"
      }
    }
  ]
}
''',
        ),
      );

      debugPrint('[Arrow] Source added');

      // 4️⃣ Add LineLayer on top of all layers to ensure visibility
      await mapboxMap.style.addLayer(
        mapbox.LineLayer(
          minZoom: 0,
          id: 'arrow_line_layer',
          sourceId: ARROW_LINES_SOURCE_ID,
          lineJoin: mapbox.LineJoin.ROUND,
          lineCap: mapbox.LineCap.ROUND,
          lineColor: Colors.red.value,
          lineWidth: 4.0,
        ),
      );

      var layers = await mapboxMap.style.getStyleLayers();
      var layerID = getLayerID(layers);
      // 5️⃣ Move layer to top to ensure it’s visible over custom tiles
      await mapboxMap.style.moveStyleLayer(
        ARROW_LINES_LAYER_ID,
        mapbox.LayerPosition(below: layerID),
      );

      debugPrint('[Arrow] Layer positioned at top ✅');
    } catch (e, s) {
      debugPrint('[Arrow] ERROR: $e');
      debugPrintStack(stackTrace: s);
    }
  }

  final String ARROW_LINES_SOURCE_ID = 'arrow_lines_source';
  final String ARROW_LINES_LAYER_ID = 'arrow_lines_layer';
  final String ARROW_POINTS_SOURCE_ID = 'arrow_points_source';
  final String ARROW_SYMBOLS_LAYER_ID = 'arrow_symbols_layer';

  final double ARROW_ICON_SIZE = 2.0; // adjust for bigger arrows

  Future<Uint8List> createChevronArrowPng({
    double size = 64,
    Color fillColor = Colors.blue,
    Color strokeColor = Colors.white,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    final w = size;
    final h = size;

    // 🔄 Move origin to center
    canvas.translate(w / 2, h / 2);

    // 🔄 Rotate 90 degrees clockwise
    canvas.rotate(math.pi / 2);

    // 🔄 Move origin back
    canvas.translate(-w / 2, -h / 2);

    final path = Path();

    // Chevron "<" shape (base shape)
    path.moveTo(w * 0.7, h * 0.2);
    path.lineTo(w * 0.3, h * 0.5);
    path.lineTo(w * 0.7, h * 0.8);

    final strokePaint =
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * 0.12
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, strokePaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  Future<void> generateAndDisplayArrowsAsSymbols(
    List<Map<String, dynamic>> memories,
    mapbox.MapboxMap mapboxMap,
  ) async {
    if (memories.length < 2) return;

    const double ARROW_ICON_SIZE = 4.0;
    const double ARROW_POSITION_FACTOR = 0.65; // 🔥 65% toward end

    try {
      // 1️⃣ Sort memories by date
      final sorted = List<Map<String, dynamic>>.from(memories)..sort((a, b) {
        final ad = DateTime.tryParse(a['memory_date'] ?? '') ?? DateTime.now();
        final bd = DateTime.tryParse(b['memory_date'] ?? '') ?? DateTime.now();
        return ad.compareTo(bd);
      });

      final List<mapbox.Feature> lineFeatures = [];
      final List<mapbox.Feature> arrowPointFeatures = [];

      for (int i = 0; i < sorted.length - 1; i++) {
        final a = sorted[i];
        final b = sorted[i + 1];

        final double? startLat = a['location_latitude'];
        final double? startLng = a['location_longitude'];
        final double? endLat = b['location_latitude'];
        final double? endLng = b['location_longitude'];

        if ([startLat, startLng, endLat, endLng].contains(null)) continue;

        // 2️⃣ Densify line
        final coords = _densifyLine(
          start: [startLng!, startLat!],
          end: [endLng!, endLat!],
          segments: 120,
        );
        if (coords.length < 5) continue;

        // 3️⃣ Add main line
        lineFeatures.add(
          mapbox.Feature(
            id: 'line_$i',
            geometry: mapbox.LineString(
              coordinates:
                  coords.map((c) => mapbox.Position(c[0], c[1])).toList(),
            ),
            properties: {'type': 'line'},
          ),
        );

        // 4️⃣ Arrow placement (~65% toward end)
        final int arrowIndex = (coords.length * ARROW_POSITION_FACTOR)
            .round()
            .clamp(1, coords.length - 1);

        final base = coords[arrowIndex - 1];
        final tip = coords[arrowIndex];

        final rotation = _bearingBetween(base, tip);

        arrowPointFeatures.add(
          mapbox.Feature(
            id: 'arrow_$i',
            geometry: mapbox.Point(
              coordinates: mapbox.Position(tip[0], tip[1]),
            ),
            properties: {'rotation': rotation},
          ),
        );
      }

      // 5️⃣ Cleanup old layers/sources
      for (final id in [ARROW_SYMBOLS_LAYER_ID, ARROW_LINES_LAYER_ID]) {
        try {
          await mapboxMap.style.removeStyleLayer(id);
        } catch (_) {}
      }
      for (final id in [ARROW_POINTS_SOURCE_ID, ARROW_LINES_SOURCE_ID]) {
        try {
          await mapboxMap.style.removeStyleSource(id);
        } catch (_) {}
      }

      // 6️⃣ Line source + layer
      await mapboxMap.style.addSource(
        mapbox.GeoJsonSource(
          id: ARROW_LINES_SOURCE_ID,
          data: json.encode(
            mapbox.FeatureCollection(features: lineFeatures).toJson(),
          ),
        ),
      );

      await mapboxMap.style.addLayer(
        mapbox.LineLayer(
          id: ARROW_LINES_LAYER_ID,
          sourceId: ARROW_LINES_SOURCE_ID,
          lineColor: Colors.blue.value,
          lineWidth: 5.0,
          lineOpacity: 0.9,
          lineCap: mapbox.LineCap.ROUND,
          lineJoin: mapbox.LineJoin.ROUND,
          minZoom: 0,
        ),
      );

      // 7️⃣ Arrow point source
      await mapboxMap.style.addSource(
        mapbox.GeoJsonSource(
          id: ARROW_POINTS_SOURCE_ID,
          data: json.encode(
            mapbox.FeatureCollection(features: arrowPointFeatures).toJson(),
          ),
        ),
      );

      // 8️⃣ Add arrow image (once)
      if (!await mapboxMap.style.hasStyleImage('arrow-icon')) {
        final Uint8List arrowBytes = await createChevronArrowPng(size: 64);
        await mapboxMap.style.addStyleImage(
          'arrow-icon',
          8,
          mapbox.MbxImage(width: 64, height: 64, data: arrowBytes),
          false,
          const [],
          const [],
          null,
        );
      }

      // 9️⃣ Symbol layer for arrows
      await mapboxMap.style.addLayer(
        mapbox.SymbolLayer(
          id: ARROW_SYMBOLS_LAYER_ID,
          sourceId: ARROW_POINTS_SOURCE_ID,
          iconImage: 'arrow-icon',
          iconSize: ARROW_ICON_SIZE,
          iconAllowOverlap: true,
          iconRotationAlignment: mapbox.IconRotationAlignment.MAP,
          iconRotateExpression: ['get', 'rotation'],
          minZoom: 0,
        ),
      );

      var layers = await mapboxMap.style.getStyleLayers();
      var layerID = getLayerID(layers);
      // 5️⃣ Move layer to top to ensure it’s visible over custom tiles
      await mapboxMap.style.moveStyleLayer(
        ARROW_LINES_LAYER_ID,
        mapbox.LayerPosition(below: layerID),
      );

      try {
        await mapboxMap.style.moveStyleLayer(
          ARROW_LINES_LAYER_ID,
          mapbox.LayerPosition(below: layerID),
        );
      } catch (_) {}
      // 🔝 Keep arrows above lines
      try {
        await mapboxMap.style.moveStyleLayer(
          ARROW_SYMBOLS_LAYER_ID,
          mapbox.LayerPosition(above: ARROW_LINES_LAYER_ID),
        );
      } catch (_) {}

      debugPrint('✅ Arrows positioned at 65% and oriented correctly');
    } catch (e, st) {
      // debugPrint('❌ ERROR: $e');
      debugPrint(st.toString());
    }
  }

  // Helper: calculate bearing from base → tip in degrees
  double _bearingBetween(List<double> start, List<double> end) {
    final lat1 = start[1] * math.pi / 180;
    final lon1 = start[0] * math.pi / 180;
    final lat2 = end[1] * math.pi / 180;
    final lon2 = end[0] * math.pi / 180;

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    var brng = math.atan2(y, x) * 180 / math.pi;
    if (brng < 0) brng += 360;
    return brng;
  }

  // Densify line
  List<List<double>> _densifyLine({
    required List<double> start,
    required List<double> end,
    int segments = 100,
  }) {
    final List<List<double>> result = [];
    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      result.add([
        start[0] + (end[0] - start[0]) * t,
        start[1] + (end[1] - start[1]) * t,
      ]);
    }
    return result;
  }

  /// Creates arrowhead lines as small LineStrings
  /// Returns list of segments [[ [lng, lat], [lng, lat] ], ...]
  List<List<List<double>>> _createArrowHead({
    required double endLat,
    required double endLng,
    required double bearingDeg,
    double length = 0.0005,
    double angleDeg = 25,
  }) {
    final angleRad = angleDeg * (pi / 180);
    final bearingRad = bearingDeg * (pi / 180);

    final left = [
      endLng - length * cos(bearingRad - angleRad),
      endLat - length * sin(bearingRad - angleRad),
    ];

    final right = [
      endLng - length * cos(bearingRad + angleRad),
      endLat - length * sin(bearingRad + angleRad),
    ];

    // Each segment is a mini LineString from tip to wing
    return [
      [
        [endLng, endLat],
        left,
      ],
      [
        [endLng, endLat],
        right,
      ],
    ];
  }

  final String ARROW_DEBUG = 'ARROW_DEBUG';

  // const String ARROW_LINES_SOURCE_ID = 'arrow_lines_source';
  // const String ARROW_LINES_LAYER_ID = 'arrow_lines_layer';
  final ARROW_BACK_DISTANCE =
      10000; // ~150m in degrees (adjust for your map scale)
  final ARROW_SIZE = 100.00; // arrowhead size

  // const String ARROW_LINES_SOURCE_ID = 'arrow_lines_source';
  // const String ARROW_LINES_LAYER_ID = 'arrow_lines_layer';
  // const String ARROW_POINTS_SOURCE_ID = 'arrow_points_source';
  // const String ARROW_SYMBOLS_LAYER_ID = 'arrow_symbols_layer';
  // const double ARROW_ICON_SIZE = 2.0; // adjust for bigger arrows

  /// Arrowhead V geometry (tip + wings)
  List<List<double>> _createArrowHeadGeometry({
    required List<double> base,
    required List<double> tip,
    double size = 0.00015,
  }) {
    final dx = tip[0] - base[0];
    final dy = tip[1] - base[1];
    final length = math.sqrt(dx * dx + dy * dy);
    if (length == 0) return [];

    final ux = dx / length;
    final uy = dy / length;
    final px = -uy;
    final py = ux;

    final left = [
      tip[0] - ux * size + px * size * 0.6,
      tip[1] - uy * size + py * size * 0.6,
    ];
    final right = [
      tip[0] - ux * size - px * size * 0.6,
      tip[1] - uy * size - py * size * 0.6,
    ];

    return [left, tip, right];
  }

  Future<void> _setupMapboxClustering(
    List<Map<String, dynamic>> memories,
  ) async {
    try {
      // Add a small delay to ensure cleanup is complete
      await Future.delayed(const Duration(milliseconds: 100));
      // Convert memories to GeoJSON
      final geoJsonString = MemoryGeoJsonService.createGeoJsonFromMemories(
        memories,
      );

      try {
        await mapboxMap!.style.addSource(
          mapbox.GeoJsonSource(
            id: MEMORY_SOURCE_ID,
            data: geoJsonString,
            cluster: true,

            // clusterMinZoom: 4, // 👈 IMPORTANT
            clusterRadius:
                10, // Radius of each cluster (pixels) - optimized for smooth clustering
            clusterMaxZoom:
                13.5, // Max zoom to cluster points - stops clustering at zoom 15+
            clusterMinPoints: 2, // Minimum points to form a cluster
            clusterProperties: {
              // Aggregate memory IDs into a comma-separated string
              // Format: [operator, mapExpression, reduceExpression]
              // The operator is applied in the reduce step
              'memory_ids': [
                'concat',
                [
                  'to-string',
                  ['get', 'id'],
                ],
              ],
            },
          ),
        );
      } catch (e) {
        if (e.toString().contains('already exists')) {
          try {
            // Try to update the existing source data instead of adding a new one

            await mapboxMap!.style.setStyleSourceProperty(
              MEMORY_SOURCE_ID,
              'data',
              geoJsonString,
            );
          } catch (updateError) {
            // If update fails, force remove and re-add
            await _forceRemoveAndReaddSource(geoJsonString);
          }
        } else {
          throw e; // Re-throw to be caught by outer try-catch
        }
      }

      // Add cluster layers
      await _addClusterLayers(memories);

      // Initialize MapMarkerService with MapBox map before arrow generation

      if (_mapMarkerService != null) {
        _mapMarkerService!.initialize(mapboxMap!);
      }

      // Generate and display chronological arrows
    } catch (e) {
      debugPrint('[MapControllerNew] Error setting up MapBox clustering: $e');
    }
  }

  /// Handle map tap to query rendered features and get memories from clusters
  Future<void> handleMapTap1(mapbox.MapContentGestureContext c) async {
    if (mapboxMap == null) {
      debugPrint('[MapControllerNew] ⚠️ Map not ready for tap handling');
      return;
    }

    try {
      final coordinates = c.point.coordinates; // Position (lng, lat)
      final touchPosition = c.touchPosition; // ScreenCoordinate (x, y)

      debugPrint(
        '[MapControllerNew] 🎯 Map tapped at: (${coordinates.lng}, ${coordinates.lat})',
      );
      debugPrint(
        '[MapControllerNew] 📍 Screen position: (${touchPosition.x}, ${touchPosition.y})',
      );

      // Query rendered features at the tap point
      // Check clusters first, then individual markers

      // 1. Check if a cluster was tapped
      // Query all cluster layer variants (small, medium, large, etc.)
      final clusterLayerIds = [
        CLUSTERS_CIRCLE_LAYER_ID,
        CLUSTER_LAYER_ID,
        CLUSTERS_COUNT_LAYER_ID,
        CLUSTER_LAYER_ID,
      ];

      final clusterFeatures = await mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(touchPosition),
        mapbox.RenderedQueryOptions(
          layerIds: clusterLayerIds, // Query all cluster layer variants
        ),
      );

      if (clusterFeatures.isNotEmpty && clusterFeatures.first != null) {
        debugPrint(
          '[MapControllerNew] 🎯 Cluster tapped - ${clusterFeatures.length} cluster features found',
        );
        // Use existing _handleClusterFeatureTap method
        await _handleClusterFeatureTap(
          clusterFeatures.first!,
          coordinates.lat.toDouble(),
          coordinates.lng.toDouble(),
        );
        return;
      }

      // 2. Check if an individual memory was tapped
      final individualFeatures = await mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(touchPosition),
        mapbox.RenderedQueryOptions(
          layerIds: [UNCLUSTERED_LAYER_ID], // Query individual marker layer
        ),
      );

      if (individualFeatures.isNotEmpty && individualFeatures.first != null) {
        debugPrint(
          '[MapControllerNew] 🎯 Individual memory tapped - ${individualFeatures.length} features found',
        );
        await _handleIndividualMemoryTapFromQuery(individualFeatures.first!);
        return;
      }

      debugPrint('[MapControllerNew] ℹ️ No features found at tap location');
    } catch (e, stackTrace) {
      debugPrint('[MapControllerNew] ❌ Error handling map tap: $e');
      debugPrint('[MapControllerNew] Stack trace: $stackTrace');
    }
  }

  /// Handle individual memory tap from query - show memory details
  Future<void> _handleIndividualMemoryTapFromQuery(
    mapbox.QueriedRenderedFeature memoryFeature,
  ) async {
    try {
      final properties =
          memoryFeature.queriedFeature.feature['properties']
              as Map<String, dynamic>?;

      if (properties == null) {
        debugPrint(
          '[MapControllerNew] ⚠️ No properties found in memory feature',
        );
        return;
      }

      final memoryId = '${properties['id']}';
      final memoryTitle = properties['title'] ?? 'Untitled';
      final memoryDate = properties['memory_date'] ?? '';

      debugPrint('[MapControllerNew] 📝 Memory tapped:');
      debugPrint('[MapControllerNew] - ID: $memoryId');
      debugPrint('[MapControllerNew] - Title: $memoryTitle');
      debugPrint('[MapControllerNew] - Date: $memoryDate');

      // TODO: Show memory details in a bottom sheet or navigate to memory detail page
      // TODO: You can use Get.bottomSheet() or Get.toNamed() here

      // Example: Show a simple snackbar for now
      Get.snackbar(
        'Memory Tapped',
        memoryTitle,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[MapControllerNew] ❌ Error handling individual memory tap: $e',
      );
      debugPrint('[MapControllerNew] Stack trace: $stackTrace');
    }
  }

  getLayerID(List<mapbox.StyleObjectInfo?> layers) {
    for (var l in layers) {
      if (l!.id.toLowerCase().contains('cluster')) {
        return l.id;
      }
    }
    return layers.last!.id;
  }

  void initializeMapAfterCreation() {
    _initializeMapAfterCreation();
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
