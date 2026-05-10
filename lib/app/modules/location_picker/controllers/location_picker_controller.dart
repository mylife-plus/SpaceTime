import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/data/models/location_data.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import 'package:spacetime/app/modules/location_picker/services/location_picker_service.dart';

enum LocationPickerState {
  loading,
  ready,
  error,
  searchingLocation,
  movingToLocation,
}

class LocationPickerController extends GetxController {
  final LocationPickerService _service = LocationPickerService();

  // Reactive state
  final Rx<LocationPickerState> state = LocationPickerState.loading.obs;
  final RxString errorMessage = ''.obs;
  final RxBool hasLocationPermission = false.obs;
  final RxBool isOfflineMode = false.obs;

  // Location data
  final Rxn<LocationData> selectedLocation = Rxn<LocationData>();
  final RxDouble selectedRadius = 10.0.obs; // Default 10km
  final RxBool isUpdatingRadius = false.obs; // Flag to track radius update process (deprecated - no longer used)
  final RxList<LocationData> recentLocations = <LocationData>[].obs;

  // Map state
  final RxBool isMapReady = false.obs;
  final Rxn<Position> currentPosition = Rxn<Position>();

  // Search state
  final RxBool isSearching = false.obs;
  final RxList<Map<String, dynamic>> searchResults = <Map<String, dynamic>>[].obs;
  final RxString searchQuery = ''.obs;

  // Map components
  mapbox.MapboxMap? mapController;
  mapbox.PointAnnotationManager? annotationManager;

  @override
  void onInit() {
    super.onInit();
    initializeController();
  }

  /// Initialize the controller
  Future<void> initializeController() async {
    try {
      state.value = LocationPickerState.loading;
      
      // Initialize service
      await _service.initialize();
      
      // Check offline tiles availability
      final hasOfflineTiles = await _service.areOfflineTilesAvailable();
      isOfflineMode.value = hasOfflineTiles;
      
      // Check location permissions
      hasLocationPermission.value = await _service.hasLocationPermission();
      
      // Load saved data
      await _loadSavedData();
      
      // Load recent locations
      await _loadRecentLocations();
      
      state.value = LocationPickerState.ready;
      debugPrint('[LocationPickerController] Controller initialized successfully');
    } catch (e) {
      debugPrint('[LocationPickerController] Initialization failed: $e');
      errorMessage.value = 'Failed to initialize: $e';
      state.value = LocationPickerState.error;
    }
  }

  /// Load saved location and radius data
  Future<void> _loadSavedData() async {
    try {
      final savedLocation = await _service.getSavedLocation();
      if (savedLocation != null) {
        selectedLocation.value = savedLocation;
      }

      final savedRadius = await _service.getSavedRadius();
      // Clamp the saved radius to the valid range (1km - 200km)
      selectedRadius.value = savedRadius.clamp(1.0, 200.0);
    } catch (e) {
      debugPrint('[LocationPickerController] Error loading saved data: $e');
    }
  }

  /// Load recent locations
  Future<void> _loadRecentLocations() async {
    try {
      final recent = await _service.getRecentLocations();
      recentLocations.value = recent;
    } catch (e) {
      debugPrint('[LocationPickerController] Error loading recent locations: $e');
    }
  }

  /// Set map controller
  void setMapController(mapbox.MapboxMap controller) {
    mapController = controller;
    _service.setMapController(controller);
    isMapReady.value = true;
    debugPrint('[LocationPickerController] Map controller set');
  }

  /// Set annotation manager
  void setAnnotationManager(mapbox.PointAnnotationManager manager) {
    annotationManager = manager;
    _service.setAnnotationManager(manager);
    debugPrint('[LocationPickerController] Annotation manager set');
  }

  /// Configure offline map
  Future<void> configureOfflineMap(mapbox.MapboxMap controller) async {
    await _service.configureOfflineMap(controller);
  }

  /// Get current location
  Future<void> getCurrentLocation() async {
    try {
      state.value = LocationPickerState.searchingLocation;
      
      if (!hasLocationPermission.value) {
        final granted = await _service.requestLocationPermission();
        if (!granted) {
          errorMessage.value = 'snackbar_body_location_permission_denied'.tr;
          state.value = LocationPickerState.error;
          return;
        }
        hasLocationPermission.value = true;
      }

      final position = await _service.getCurrentLocation();
      if (position != null) {
        currentPosition.value = position;
        
        // Move camera to current location
        await _service.moveCameraToLocation(
          position.latitude,
          position.longitude,
          zoom: MapboxZoomHelper().currentLocationZoom.value,
        );
        
        // Add marker at current location
        await _service.addMarker(
          position.latitude, 
          position.longitude, 
          radius: selectedRadius.value,
        );
        
        // Get location info
        final locationData = await _service.getLocationInfo(
          position.latitude, 
          position.longitude,
        );
        
        if (locationData != null) {
          selectedLocation.value = locationData;
        }
        
        state.value = LocationPickerState.ready;
      } else {
        errorMessage.value = 'Failed to get current location';
        state.value = LocationPickerState.error;
      }
    } catch (e) {
      debugPrint('[LocationPickerController] Error getting current location: $e');
      errorMessage.value = 'Error getting location: $e';
      state.value = LocationPickerState.error;
    }
  }

  /// Handle map tap
  Future<void> onMapTap(double latitude, double longitude) async {
    try {
      state.value = LocationPickerState.movingToLocation;

      // Add marker at tapped location (this also adjusts camera zoom based on radius)
      await _service.addMarker(latitude, longitude, radius: selectedRadius.value);

      // Get location info
      final locationData = await _service.getLocationInfo(latitude, longitude);
      if (locationData != null) {
        selectedLocation.value = locationData;
      }

      state.value = LocationPickerState.ready;
    } catch (e) {
      debugPrint('[LocationPickerController] Error handling map tap: $e');
      errorMessage.value = 'Error selecting location: $e';
      state.value = LocationPickerState.error;
    }
  }

  /// Update radius
  Future<void> updateRadius(double radius) async {
    try {
      // Round to nearest 0.1 to avoid floating point precision issues
      final roundedRadius = (radius * 10).round() / 10.0;
      // Clamp to valid range (1km - 200km)
      final clampedRadius = roundedRadius.clamp(1.0, 200.0);
      selectedRadius.value = clampedRadius;

      debugPrint('[LocationPickerController] Radius updated: original=$radius, rounded=$roundedRadius, clamped=$clampedRadius');

      // Update marker size if location is selected
      if (selectedLocation.value != null) {
        await _service.addMarker(
          selectedLocation.value!.latitude,
          selectedLocation.value!.longitude,
          radius: clampedRadius,
        );
      }

      // Save radius
      await _service.saveRadius(clampedRadius);
    } catch (e) {
      debugPrint('[LocationPickerController] Error updating radius: $e');
    }
  }

  /// Update zoom level for marker scaling
  Future<void> updateZoom(double zoom) async {
    try {
      await _service.updateZoom(zoom);
    } catch (e) {
      debugPrint('[LocationPickerController] Error updating zoom: $e');
    }
  }

  /// Search locations
  Future<void> searchLocations(String query) async {
    try {
      searchQuery.value = query;

      if (query.isEmpty) {
        searchResults.clear();
        isSearching.value = false;
        return;
      }

      isSearching.value = true;

      final results = await _service.searchLocations(
        query,
        isOfflineMode: isOfflineMode.value,
      );

      searchResults.value = results;
      isSearching.value = false;
    } catch (e) {
      debugPrint('[LocationPickerController] Error searching locations: $e');
      // Clear results on error to show "No locations found" message
      searchResults.clear();
      isSearching.value = false;
    }
  }

  /// Select location from search results
  Future<void> selectSearchResult(Map<String, dynamic> result) async {
    try {
      state.value = LocationPickerState.movingToLocation;
      
      final latitude = result['latitude'] as double;
      final longitude = result['longitude'] as double;

      // Move camera to selected location
      await _service.moveCameraToLocation(latitude, longitude, zoom: MapboxZoomHelper().currentLocationZoom.value);
      
      // Add marker
      await _service.addMarker(latitude, longitude, radius: selectedRadius.value);
      
      // Create location data
      final locationData = LocationData(
        latitude: latitude,
        longitude: longitude,
        address: result['name'] ?? 'Selected Location',
        city: result['city'] ?? '',
        state: result['region'] ?? '',
        country: result['country'] ?? '',
        timestamp: DateTime.now().toIso8601String(),
      );
      
      selectedLocation.value = locationData;
      
      // Clear search
      searchResults.clear();
      searchQuery.value = '';
      
      state.value = LocationPickerState.ready;
    } catch (e) {
      debugPrint('[LocationPickerController] Error selecting search result: $e');
      errorMessage.value = 'Error selecting location: $e';
      state.value = LocationPickerState.error;
    }
  }

  /// Save current selection
  Future<void> saveSelection() async {
    try {
      if (selectedLocation.value != null) {
        await _service.saveLocation(selectedLocation.value!);
        await _service.saveRadius(selectedRadius.value);
        
        // Refresh recent locations
        await _loadRecentLocations();
        
        debugPrint('[LocationPickerController] Selection saved successfully');
      }
    } catch (e) {
      debugPrint('[LocationPickerController] Error saving selection: $e');
      errorMessage.value = 'Failed to save selection: $e';
    }
  }

  /// Get result data for returning to parent
  Map<String, dynamic>? getResultData() {
    if (selectedLocation.value == null) return null;
    
    return {
      'location': selectedLocation.value!.toJson(),
      'radius': selectedRadius.value,
    };
  }

  @override
  void onClose() {
    // Clean up service resources
    _service.dispose().catchError((e) {
      debugPrint('[LocationPickerController] Error during service disposal: $e');
    });
    super.onClose();
  }
}
