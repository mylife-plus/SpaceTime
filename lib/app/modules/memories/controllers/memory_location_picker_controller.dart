import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import 'package:spacetime/app/modules/location_picker/services/location_picker_service.dart';
import 'package:spacetime/services/mbtiles_download_service.dart';
import 'package:spacetime/services/mbtiles_server_service.dart';
import 'package:spacetime/services/style_json_download_service.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/memory_location_admin_edit_widget.dart';
import 'package:spacetime/app/modules/memories/services/memory_location_pin_geocoding.dart';

enum MemoryLocationPickerState {
  loading,
  ready,
  error,
  searchingLocation,
  movingToLocation,
}

class MemoryLocationPickerController extends GetxController {
  static const double _fallbackLat = 51.1657;
  static const double _fallbackLng = 10.4515;

  // Controllers
  final MemoryController memoryController = Get.find<MemoryController>();
  final UiController uiController = Get.find<UiController>();
  final LocationPickerService locationPickerService = LocationPickerService();
  
  // Text and focus controllers
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  
  // State management
  final Rx<MemoryLocationPickerState> state = MemoryLocationPickerState.loading.obs;
  final RxString errorMessage = ''.obs;
  final RxBool hasLocationPermission = false.obs;
  final RxBool isOfflineMode = false.obs;
  final Rxn<Position> currentPosition = Rxn<Position>();
  final RxBool isSearching = false.obs;
  final RxList<Map<String, dynamic>> searchResults = <Map<String, dynamic>>[].obs;
  final RxBool showSearchResults = false.obs;
  
  // Map components
  mapbox.MapboxMap? mapController;
  mapbox.PointAnnotationManager? annotationManager;
  mapbox.PointAnnotation? selectedLocationMarker;
  bool _mapBootstrapped = false;
  int _labelGeocodeGeneration = 0;

  void _invalidatePendingLabelGeocode() {
    _labelGeocodeGeneration++;
  }

  // Server state for local tiles
  final Rxn<String> serverUrl = Rxn<String>();
  final Rxn<String> serverErrorMessage = Rxn<String>();
  final RxBool isInitializingServer = true.obs;

  @override
  void onInit() {
    super.onInit();
    MapboxZoomHelper().currentLocationZoom.value = 6;
    searchFocusNode.addListener(onSearchFocusChanged);
    searchController.addListener(onSearchChanged);
    initializeLocationPicker();
  }

  @override
  void onClose() {
    searchController.dispose();
    searchFocusNode.dispose();
    super.onClose();
  }

  /// Initialize location picker
  Future<void> initializeLocationPicker() async {
    try {
      state.value = MemoryLocationPickerState.loading;

      // Initialize local tile server first
      await initializeLocalTileServer();

      // Check location permission
      await checkLocationPermission();

      // Get current location if permission is available
      if (hasLocationPermission.value) {
        await getCurrentLocation();
      }

      state.value = MemoryLocationPickerState.ready;
    } catch (e) {
      debugPrint('Error initializing location picker: $e');
      errorMessage.value = 'Failed to initialize location picker: $e';
      state.value = MemoryLocationPickerState.error;
    }
  }

  /// Initialize local tile server before map creation
  Future<void> initializeLocalTileServer() async {
    try {
      debugPrint('[MemoryLocationPicker] 🔍 Checking if local tile server is running...');

      final serverService = MbtilesServerService.instance;

      // Check if server is already running (started in main.dart)
      if (serverService.isRunning && serverService.serverUrl != null) {
        serverUrl.value = serverService.serverUrl;
        isInitializingServer.value = false;
        debugPrint('[MemoryLocationPicker] ✅ Using existing tile server at: ${serverUrl.value}');
        debugPrint('[MemoryLocationPicker] 📡 Tiles will be served from: ${serverUrl.value}/{z}/{x}/{y}.pbf');
        return;
      }

      // If server is not running, try to start it (fallback)
      debugPrint('[MemoryLocationPicker] ⚠️ Server not running, attempting to start...');

      final mbtilesService = MbtilesDownloadService.instance;
      final isDownloaded = await mbtilesService.isMbtilesDownloaded();
      final tilesPath = mbtilesService.getLocalMbtilesPath();

      // Debug logging to understand the issue
      debugPrint('[MemoryLocationPicker] 🔍 Tile check: isDownloaded=$isDownloaded, tilesPath=$tilesPath');

      if (!isDownloaded || tilesPath == null) {
        serverErrorMessage.value = 'MBTiles file not downloaded. Please download from Get Started screen first.';
        isInitializingServer.value = false;
        debugPrint('[MemoryLocationPicker] ❌ ${serverErrorMessage.value}');
        debugPrint('[MemoryLocationPicker] 🔍 Debug: isDownloaded=$isDownloaded, tilesPath=$tilesPath');
        return;
      }

      final url = await serverService.startServer(tilesPath);

      if (url != null) {
        serverUrl.value = url;
        isInitializingServer.value = false;
        debugPrint('[MemoryLocationPicker] ✅ Local tile server started at: $url');
      } else {
        serverErrorMessage.value = 'Failed to start local tile server';
        isInitializingServer.value = false;
        debugPrint('[MemoryLocationPicker] ❌ ${serverErrorMessage.value}');
      }
    } catch (e) {
      serverErrorMessage.value = 'Error initializing tile server: $e';
      isInitializingServer.value = false;
      debugPrint('[MemoryLocationPicker] ❌ ${serverErrorMessage.value}');
    }
  }

  /// Check location permission
  Future<void> checkLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      hasLocationPermission.value = permission == LocationPermission.whileInUse ||
                                   permission == LocationPermission.always;
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      hasLocationPermission.value = false;
    }
  }

  /// Get current location
  Future<void> getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      currentPosition.value = position;
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  /// Load style.json from local storage or assets and replace placeholders with actual server URLs
  Future<String> loadStyleJsonFromAssets(String tileUrl, String serverUrlValue) async {
    try {
      debugPrint('[MemoryLocationPicker] 📂 Loading style.json from local storage...');

      // Try to load from local storage first
      final styleJsonService = Get.find<StyleJsonDownloadService>();
      String? styleJsonString = await styleJsonService.readStyleJsonContent();

      // Fallback to assets if local file not found
      if (styleJsonString == null) {
        debugPrint('[MemoryLocationPicker] ⚠️ Local style.json not found, loading from assets...');
        styleJsonString = await rootBundle.loadString('assets/custom-style.json');
        debugPrint('[MemoryLocationPicker] ✅ Loaded style.json from assets');
      } else {
        debugPrint('[MemoryLocationPicker] ✅ Loaded style.json from local storage');
      }

      // IMPORTANT: Replace {LOCAL_SERVER_URL} FIRST, then {LOCAL_TILE_URL}
      var modifiedStyleJson = styleJsonString
          .replaceAll('{LOCAL_SERVER_URL}', serverUrlValue)
          .replaceAll('{LOCAL_TILE_URL}', tileUrl);

      debugPrint('[MemoryLocationPicker] 📡 Replaced {LOCAL_SERVER_URL} with: $serverUrlValue');
      debugPrint('[MemoryLocationPicker] 📡 Replaced {LOCAL_TILE_URL} with: $tileUrl');
      debugPrint('[MemoryLocationPicker] ✅ Style JSON configured with local MBTiles server');

      return modifiedStyleJson;
    } catch (e) {
      debugPrint('[MemoryLocationPicker] ❌ Error loading style.json: $e');
      debugPrint('[MemoryLocationPicker] ⚠️ Falling back to simplified style');

      // Fallback to a simplified style
      return '''
{
  "version": 8,
  "name": "Local Tiles Fallback",
  "metadata": {"mapbox:autocomposite": false},
  "sources": {
    "openmaptiles": {
      "type": "vector",
      "tiles": ["$tileUrl"],
      "minzoom": 0,
      "maxzoom": 14
    }
  },
  "projection": { "type": "globe" },
  "sprite": "",
  "glyphs": "",
  "layers": [
    {"id": "background", "type": "background", "paint": {"background-color": "hsl(47, 26%, 88%)"}},
    {"id": "water", "type": "fill", "source": "openmaptiles", "source-layer": "water", "filter": ["==", "\$type", "Polygon"], "paint": {"fill-color": "hsl(205, 56%, 73%)"}},
    {"id": "road", "type": "line", "source": "openmaptiles", "source-layer": "transportation", "paint": {"line-color": "#fff", "line-width": 1.5}}
  ]
}
''';
    }
  }

  /// Get camera options
  mapbox.CameraOptions? getCameraOptions() {
    // Prioritize selected location over current location
    final hasSelectedLocation = memoryController.selectedLocation.value.isNotEmpty &&
                                 memoryController.locationLatitude.value != null &&
                                 memoryController.locationLongitude.value != null;

    if (hasSelectedLocation) {
      return mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            memoryController.locationLongitude.value!,
            memoryController.locationLatitude.value!,
          ),
        ),
        zoom: 6,
      );
    } else if (currentPosition.value != null) {
      return mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            currentPosition.value!.longitude,
            currentPosition.value!.latitude,
          ),
        ),
        zoom: 6,
      );
    }
    return null;
  }

  /// Handle search focus changes
  void onSearchFocusChanged() {
    if (searchFocusNode.hasFocus) {
      showSearchResults.value = true;
    } else {
      // Only hide if search is empty
      if (searchController.text.isEmpty) {
        showSearchResults.value = false;
      } else {
        // Force a refresh so listeners (e.g. bottom buttons) rebuild on focus change
        showSearchResults.refresh();
      }
    }
  }

  /// Handle search text changes
  void onSearchChanged() {
    final query = searchController.text.trim();
    if (query.isNotEmpty) {
      performLocationSearch(query);
    } else {
      showSearchResults.value = false;
      searchResults.clear();
    }
  }

  /// Perform location search using LocationPickerService
  Future<void> performLocationSearch(String query) async {
    if (query.trim().isEmpty) {
      showSearchResults.value = false;
      return;
    }

    showSearchResults.value = true;
    isSearching.value = true;
    searchResults.clear();

    try {
      // Use LocationPickerService for searching
      final results = await locationPickerService.searchLocations(
        query,
        isOfflineMode: isOfflineMode.value,
      );

      // Results are already in the correct format from LocationPickerService
      searchResults.addAll(results);
    } catch (e) {
      debugPrint('Error performing location search: $e');
    } finally {
      isSearching.value = false;
    }
  }

    String getBlankStyleJson() {
    return '''
{
  "version": 8,
  "name": "Blank",
   "projection": {
  "name": "globe"
  },
  "metadata": {
    "mapbox:autocomposite": false
  },
  "sources": {},
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": {"background-color": "hsl(47, 26%, 88%)"}
    },
  ]
}
''';
  }

  Future<Map<String, dynamic>?> _buildLocationDataForPin(
    double lat,
    double lng,
  ) async {
    return MemoryLocationPinGeocoding(mapController).buildLocationDataForPin(
      lat,
      lng,
    );
  }

  Future<void> onDonePressed() async {
    _invalidatePendingLabelGeocode();

    // Always prefer the currently visible marker coordinates.
    final hasExistingMemoryCoords =
        memoryController.locationLatitude.value != null &&
        memoryController.locationLongitude.value != null;

    if (selectedLocationMarker == null && !hasExistingMemoryCoords) {
      print('Selected Location Marker Is Null');
      Get.back();
      return;
    }

    final lat = selectedLocationMarker != null
        ? selectedLocationMarker!.geometry.coordinates.lat.toDouble()
        : memoryController.locationLatitude.value!;
    final lng = selectedLocationMarker != null
        ? selectedLocationMarker!.geometry.coordinates.lng.toDouble()
        : memoryController.locationLongitude.value!;
    print(
      '[WaterNameSearch] onDonePressed usingMarker=${selectedLocationMarker != null} lat=$lat lng=$lng',
    );

    // Use label fields already shown in the picker (no re-fetch).
    final locationData = <String, dynamic>{
      'latitude': lat,
      'longitude': lng,
      'country': memoryController.locationCountry.value,
      'city': memoryController.locationCity.value,
      'address': memoryController.locationAddress.value,
      'flag': memoryController.locationFlag.value,
      'name': memoryController.locationName.value,
    };

    memoryController.setEnhancedLocationData(locationData);
    Get.back(result: locationData);
  }

  /// Call when leaving the picker route so the next open does not retain native map state.
  Future<void> disposePickerMapSession() async {
    _invalidatePendingLabelGeocode();
    try {
      await clearExistingMarkers();
    } catch (e) {
      debugPrint('[MemoryLocationPicker] disposePickerMapSession clear markers: $e');
    }
    annotationManager = null;
    selectedLocationMarker = null;
    mapController = null;
    _mapBootstrapped = false;
  }

  Future<void> onEditLocationTextPressed() async {
    _invalidatePendingLabelGeocode();
    final lat = selectedLocationMarker != null
        ? selectedLocationMarker!.geometry.coordinates.lat.toDouble()
        : memoryController.locationLatitude.value;
    final lng = selectedLocationMarker != null
        ? selectedLocationMarker!.geometry.coordinates.lng.toDouble()
        : memoryController.locationLongitude.value;
    if (lat == null || lng == null) return;

    final data = await Get.to(() => const MemoryLocationAdminEditWidget());
    _invalidatePendingLabelGeocode();
    if (data == null) return;

    final patch = Map<String, dynamic>.from(data as Map);
    memoryController.setEnhancedLocationData(<String, dynamic>{
      'latitude': lat,
      'longitude': lng,
      'country': patch['country'] ?? memoryController.locationCountry.value,
      'city': patch['city'] ?? memoryController.locationCity.value,
      'address': patch['address'] ?? memoryController.locationAddress.value,
      'flag': patch['flag'] ?? memoryController.locationFlag.value,
      'name': patch['name'] ?? memoryController.locationName.value,
    });
  }

  /// Select search result
  Future<void> selectSearchResult(Map<String, dynamic> result) async {
    final lat = double.tryParse(result['latitude']?.toString() ?? '0') ?? 0.0;
    final lng = double.tryParse(result['longitude']?.toString() ?? '0') ?? 0.0;

    showSearchResults.value = false;
    searchController.clear();
    searchFocusNode.unfocus();

    // Clear existing markers before selecting new location
    await clearExistingMarkers();

    await moveToLocation(lat, lng);
    await selectLocation(lat, lng);
  }

  /// Handle map creation
  Future<void> onMapCreated(mapbox.MapboxMap controller) async {
    if (_mapBootstrapped && mapController == controller && annotationManager != null) {
      return;
    }

    controller.compass.updateSettings(mapbox.CompassSettings(enabled: false));
               controller.scaleBar.updateSettings(mapbox.ScaleBarSettings(enabled: false));
               controller.attribution.updateSettings(mapbox.AttributionSettings(enabled: false));
               controller.logo.updateSettings(mapbox.LogoSettings(enabled: false));

    try {
      mapController = controller;

      // ENABLE online mode to allow localhost tile server access
      await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
      debugPrint('[MemoryLocationPicker] 🌐 Online mode ENABLED - localhost tile server can now be accessed');

      // Create annotation manager only once per live map instance
      annotationManager ??= await controller.annotations.createPointAnnotationManager();
      _mapBootstrapped = true;

      // Check if there's already a selected location
      final hasSelectedLocation = memoryController.locationLatitude.value != null &&
          memoryController.locationLongitude.value != null;

      if (hasSelectedLocation) {
        // If location is already selected, show that location
        final lat = memoryController.locationLatitude.value!;
        final lng = memoryController.locationLongitude.value!;

        await moveToLocation(lat, lng);
        await _createOrMoveMarker(lat, lng);
        debugPrint('📍 Showing previously selected location on map load: $lat, $lng');
      } else if (hasLocationPermission.value && currentPosition.value != null) {
        // Otherwise, show current location if available
        await moveToLocation(
          currentPosition.value!.latitude,
          currentPosition.value!.longitude,
        );
        // Automatically select current location with red marker
        await selectLocation(
          currentPosition.value!.latitude,
          currentPosition.value!.longitude,
          userAction: false,
        );
        debugPrint('📍 Auto-selected current location on map load');
      } else {
        await moveToLocation(_fallbackLat, _fallbackLng);
        await selectLocation(_fallbackLat, _fallbackLng, userAction: false);
        debugPrint('📍 Using Germany fallback on map load');
      }
      // await _printAllLayersAndSources();
    } catch (e) {
      debugPrint('Error in onMapCreated: $e');
    }
  }

 
  /// Move camera to location
  Future<void> moveToLocation(double latitude, double longitude) async {
    if (mapController == null) return;

    try {
      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(longitude, latitude),
          ),
          zoom: 6,
        ),
        mapbox.MapAnimationOptions(duration: 1000),
      );

      // state.value = MemoryLocationPickerState.ready;
    } catch (e) {
      debugPrint('Error moving to location: $e');
      // state.value = MemoryLocationPickerState.ready;
    }
  }

  /// Select location and add marker
  Future<void> selectLocation(
    double latitude,
    double longitude, {
    bool userAction = true,
  }) async {
    if (annotationManager == null) return;
    final myGeneration = ++_labelGeocodeGeneration;

    await _createOrMoveMarker(latitude, longitude);

    try {
      final data = await _buildLocationDataForPin(latitude, longitude);
      if (myGeneration != _labelGeocodeGeneration) return;
      if (data != null) {
        memoryController.setEnhancedLocationData(data);
      } else {
        memoryController.locationLatitude.value = latitude;
        memoryController.locationLongitude.value = longitude;
        memoryController.selectedLocation.value = '$latitude,$longitude';
      }
      debugPrint('Selected location ($latitude, $longitude)');
    } catch (e) {
      if (myGeneration != _labelGeocodeGeneration) return;
      debugPrint('Error Reverse geocoding $e');
      memoryController.locationLatitude.value = latitude;
      memoryController.locationLongitude.value = longitude;
      memoryController.selectedLocation.value = '$latitude,$longitude';
    }
  }

  Future<void> _createOrMoveMarker(double latitude, double longitude) async {
    try {
      await clearExistingMarkers();
      final Uint8List imageData = await _createCircularMarker();
      final pointAnnotationOptions = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(longitude, latitude),
        ),
        image: imageData,
        iconSize: 1.0,
      );
      selectedLocationMarker = await annotationManager!.create(pointAnnotationOptions);
      debugPrint('Selected Address $latitude $longitude');
    } catch (e) {
      debugPrint('Error selecting location: $e');
    }
  }

  /// Create a circular marker image with app primary color
  Future<Uint8List> _createCircularMarker() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = 100.0;
    final center = Offset(size / 2, size / 2);
    final radius = size / 2;

    // Draw outer white circle (border)
    final outerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, outerPaint);

    // Draw inner circle with primary color
    final innerPaint = Paint()
      ..color = uiController.currentMainColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 8, innerPaint);

    // Draw center white dot
    final centerDotPaint = Paint()
      ..color = uiController.currentMainColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8, centerDotPaint);

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Clear existing markers (all annotations on this manager).
  Future<void> clearExistingMarkers() async {
    if (annotationManager == null) return;
    try {
      await annotationManager!.deleteAll();
      selectedLocationMarker = null;
    } catch (e) {
      debugPrint('Error clearing existing markers: $e');
    }
  }

  /// Handle map tap
  Future<void> onMapTap(mapbox.MapContentGestureContext context) async {
    clearSearch();

    final point = context.point;

    final latitude = point.coordinates.lat.toDouble();
    final longitude = point.coordinates.lng.toDouble();

    await selectLocation(latitude, longitude);
  }

  Future<Map<String, String?>> getAdminHierarchy(double lat, double lng) async {
    return MemoryLocationPinGeocoding(mapController).getAdminHierarchy(lat, lng);
  }

  Future<Map<String, dynamic>?> getWaterPolygonById(
    String sourceId,
    String sourceLayer,
    String featureId,
  ) async {
    return MemoryLocationPinGeocoding(mapController).getWaterPolygonById(
      sourceId,
      sourceLayer,
      featureId,
    );
  }

  Future<String?> getWaterLabel(
    Map<String, dynamic> polygonFeature,
    List<String> labelLayers,
  ) async {
    return MemoryLocationPinGeocoding(mapController).getWaterLabel(
      polygonFeature,
      labelLayers,
    );
  }

  
  void clearSearch() {
    searchController.clear();
    showSearchResults.value = false;
    searchResults.clear();
    searchFocusNode.unfocus();
  }

void debugPrintFull(String text) {
  const int chunkSize = 800;
  for (var i = 0; i < text.length; i += chunkSize) {
    debugPrint(text.substring(i, i + chunkSize > text.length ? text.length : i + chunkSize));
  }
}

// Usage

  /// Request location permission
  Future<void> requestLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      hasLocationPermission.value = permission == LocationPermission.whileInUse ||
                                   permission == LocationPermission.always;

      if (hasLocationPermission.value) {
        await getCurrentLocation();
        if (currentPosition.value != null) {
          await moveToLocation(
            currentPosition.value!.latitude,
            currentPosition.value!.longitude,
          );
        }
      }
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
    }
  }

  /// Move to current location
  Future<void> moveToCurrentLocation() async {
    clearSearch();

    if (!hasLocationPermission.value) {
      await requestLocationPermission();
      return;
    }

    await getCurrentLocation();
    if (currentPosition.value != null) {
      await moveToLocation(
        currentPosition.value!.latitude,
        currentPosition.value!.longitude,
      );
      // Automatically select current location
      await selectLocation(
        currentPosition.value!.latitude,
        currentPosition.value!.longitude,
      );
    }
  }

  /// Clear selected location
  Future<void> clearSelectedLocation() async {
    await clearExistingMarkers();
    memoryController.selectedLocation.value = '';
    memoryController.locationLatitude.value = null;
    memoryController.locationLongitude.value = null;
  }
}
