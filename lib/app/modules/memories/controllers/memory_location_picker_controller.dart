import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'package:spacetime/app/modules/location_picker/services/location_picker_service.dart';
import 'package:spacetime/services/mbtiles_download_service.dart';
import 'package:spacetime/services/mbtiles_server_service.dart';
import 'package:spacetime/services/style_json_download_service.dart';

enum MemoryLocationPickerState {
  loading,
  ready,
  error,
  searchingLocation,
  movingToLocation,
}

class MemoryLocationPickerController extends GetxController {
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

  // Server state for local tiles
  final Rxn<String> serverUrl = Rxn<String>();
  final Rxn<String> serverErrorMessage = Rxn<String>();
  final RxBool isInitializingServer = true.obs;

  @override
  void onInit() {
    super.onInit();
    MapboxZoomHelper().currentLocationZoom.value = 1;
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

      if (!isDownloaded || tilesPath == null) {
        serverErrorMessage.value = 'MBTiles file not downloaded. Please download from Get Started screen first.';
        isInitializingServer.value = false;
        debugPrint('[MemoryLocationPicker] ❌ ${serverErrorMessage.value}');
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
        zoom: MapboxZoomHelper().currentLocationZoom.value,
      );
    } else if (currentPosition.value != null) {
      return mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            currentPosition.value!.longitude,
            currentPosition.value!.latitude,
          ),
        ),
        zoom: MapboxZoomHelper().currentLocationZoom.value,
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

  Future<void> onDonePressed() async {
    if (selectedLocationMarker == null) {
      print('Selected Location Marker Is Null');
      Get.back();
      return;
    }

final locationData1 = await GeocodingIsolateService.instance.reverseGeocode(
        selectedLocationMarker!.geometry.coordinates.lat.toDouble(),
        selectedLocationMarker!.geometry.coordinates.lng.toDouble(),
      );

      // Extract location name from the result
      final locationName = locationData1?['display_name'] as String? ?? 'Unknown Location';

      print('Selected Address $locationName');

      memoryController.locationCountry.value = locationData1?['country'] as String? ?? 'country';
      memoryController.locationFlag.value = locationData1?['flag'] as String? ?? 'flag';
      memoryController.locationCity.value = locationData1?['city'] as String? ?? 'city';
            memoryController.locationAddress.value = locationData1?['address'] as String? ?? 'address';

       memoryController.selectedLocation.value = locationName;
      memoryController.locationLatitude.value = selectedLocationMarker!.geometry.coordinates.lat.toDouble();
      memoryController.locationLongitude.value = selectedLocationMarker!.geometry.coordinates.lat.toDouble();
    // Return the complete location data including flag
    final locationData = {
      'latitude': selectedLocationMarker!.geometry.coordinates.lat,
      'longitude': selectedLocationMarker!.geometry.coordinates.lng,
      'city': memoryController.locationCity.value,
      'country': memoryController.locationCountry.value,
      'address': memoryController.locationAddress.value,
      'flag': memoryController.locationFlag.value,
      'name': memoryController.locationName.value,
    };

    debugPrint('🎯 Returning location data: $locationData');
    Get.back(result: locationData);
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
    
    try {
      mapController = controller;

      // ENABLE online mode to allow localhost tile server access
      await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
      debugPrint('[MemoryLocationPicker] 🌐 Online mode ENABLED - localhost tile server can now be accessed');

      // Create annotation manager
      annotationManager = await controller.annotations.createPointAnnotationManager();

      // Check if there's already a selected location
      final hasSelectedLocation = memoryController.selectedLocation.value.isNotEmpty &&
                                   memoryController.locationLatitude.value != null &&
                                   memoryController.locationLongitude.value != null;

      if (hasSelectedLocation) {
        // If location is already selected, show that location
        final lat = memoryController.locationLatitude.value!;
        final lng = memoryController.locationLongitude.value!;

        await moveToLocation(lat, lng);
        await selectLocation(lat, lng);
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
        );
        debugPrint('📍 Auto-selected current location on map load');
      }
    } catch (e) {
      debugPrint('Error in onMapCreated: $e');
    }
  }

  /// Move camera to location
  Future<void> moveToLocation(double latitude, double longitude) async {
    if (mapController == null) return;

    try {
      state.value = MemoryLocationPickerState.movingToLocation;

      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(longitude, latitude),
          ),
          zoom: MapboxZoomHelper().currentLocationZoom.value,
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
  Future<void> selectLocation(double latitude, double longitude) async {
    if (annotationManager == null) return;

  
    // await Future.delayed(Duration(seconds: 01));
    try {
      // Clear existing markers first
      await clearExistingMarkers();

      // Create custom circular marker with app primary color
      final Uint8List imageData = await _createCircularMarker();

      // Create point annotation options
      final pointAnnotationOptions = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(longitude, latitude),
        ),
        image: imageData,
        iconSize: 1.0,
      );
      
       selectedLocationMarker = await annotationManager!.create(pointAnnotationOptions);
      print('Selected Address $latitude $longitude');
      // Add marker
    } catch (e) {
      debugPrint('Error selecting location: $e');
    }

    try {

      // Reverse geocode to get location name
      final locationData = await GeocodingIsolateService.instance.reverseGeocode(
        latitude,
        longitude,
      );

      // Extract location name from the result
      final locationName = locationData?['display_name'] as String? ?? 'Unknown Location';

      print('Selected Address $locationName');

      // Update memory controller with selected location
       memoryController.selectedLocation.value = locationName;
      memoryController.locationLatitude.value = latitude;
      memoryController.locationLongitude.value = longitude;
      
      debugPrint('Selected location: $locationName ($latitude, $longitude)');

    }catch(e) {

      print('Error Reverse geocoding $e');

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

  /// Clear existing markers
  Future<void> clearExistingMarkers() async {
    if (annotationManager != null && selectedLocationMarker != null) {
      try {
        await annotationManager!.delete(selectedLocationMarker!);
        selectedLocationMarker = null;
      } catch (e) {
        debugPrint('Error clearing existing markers: $e');
      }
    }
  }

  /// Handle map tap
  Future<void> onMapTap(mapbox.MapContentGestureContext context) async {
    final point = context.point;
    final latitude = point.coordinates.lat.toDouble();
    final longitude = point.coordinates.lng.toDouble();

    await selectLocation(latitude, longitude);
  }

  /// Clear search
  void clearSearch() {
    searchController.clear();
    showSearchResults.value = false;
    searchResults.clear();
    searchFocusNode.unfocus();
  }

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
