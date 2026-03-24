import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import 'package:spacetime/app/modules/memories/services/memory_location_pin_geocoding.dart';
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

class MemoryLocationPickerControllerWithRadius extends GetxController {
  // Controllers
  // final MemoryController memoryController = Get.find<MemoryController>();
  final UiController uiController = Get.find<UiController>();
  final LocationPickerService locationPickerService = LocationPickerService();

  // Text and focus controllers
  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();

  // Radius control
  RxDouble radiusSliderValue = 0.0.obs; // 0-100 slider value (default 10 = 2km)
  RxDouble radiusInKm = 4.0.obs; // Actual radius in kilometers (default 2km)
  RxDouble radiusInMeters =
      2000.0.obs; // Actual radius in meters (default 2000m)
  // State management
  final Rx<MemoryLocationPickerState> state =
      MemoryLocationPickerState.loading.obs;
  final RxString errorMessage = ''.obs;
  final RxBool hasLocationPermission = false.obs;
  final Rxn<Position> currentPosition = Rxn<Position>();
  final RxBool isSearching = false.obs;
  final RxList<Map<String, dynamic>> searchResults =
      <Map<String, dynamic>>[].obs;
  final RxBool showSearchResults = false.obs;
  double lat = 0.0;
  double lng = 0.0;
  String city = '';

  String country = '';
  String address = '';
  String flag = '';
  String name = '';
  String address_state = '';

  // Map components
  mapbox.MapboxMap? mapController;
  mapbox.PointAnnotationManager? annotationManager;
  mapbox.PointAnnotation? selectedLocationMarker;

  bool _radiusPickerAnnotationsInitialized = false;

  // Server state for local tiles
  final Rxn<String> serverUrl = Rxn<String>();
  final Rxn<String> serverErrorMessage = Rxn<String>();
  final RxBool isInitializingServer = true.obs;

  @override
  void onInit() {
    super.onInit();
       lat = 0.0;
 lng = 0.0;
   city = '';

   country = '';
   address = '';
   flag = '';
   name = '';
   address_state = '';
    debugPrint('[MemoryLocationPicker] 🎬 Controller onInit() called');
    radiusInKm.value = 4;
    radiusSliderValue.value = 0;
    MapboxZoomHelper().currentLocationZoom.value = 1;
    searchFocusNode.addListener(onSearchFocusChanged);
    searchController.addListener(onSearchChanged);
    radiusSliderValue.listen(_onRadiusSliderChanged);
    debugPrint('[MemoryLocationPicker] 🚀 About to call initializeLocationPicker()');

   initializeLocationPicker();
    debugPrint('[MemoryLocationPicker] ✅ onInit() completed');
  }

  /// Convert slider value (0-100) to radius in kilometers
  /// 0-10: 0-2 km (linear)
  /// 10-50: 2-100 km (linear)
  /// 50-100: 100-500 km (linear)

  /// Calculate appropriate zoom level for given radius

  /// Handle radius slider changes
  void _onRadiusSliderChanged(double value) {
    debugPrint('🎚️ Slider changed: $value');
    // radiusInKm.value = _sliderValueToKm(value);
    // radiusInMeters.value = radiusInKm.value * 1000;
    debugPrint(
      '📏 Radius updated: ${radiusInKm.value} km (${radiusInMeters.value} m)',
    );

    // Update circle if location is selected
    if (lat != 0.0 && lng != 0.0 && mapController != null) {
      debugPrint(
        '🔄 Updating circle at ($lat, $lng) with radius ${radiusInMeters.value}m',
      );
    } else {
      debugPrint(
        '⚠️ Cannot update circle - lat: $lat, lng: $lng, mapController: ${mapController != null}',
      );
    }
  }

  /// Update circle radius and zoom
  Future<void> updateCircleRadius() async {
    if (mapController == null || lat == 0.0 || lng == 0.0) {
      debugPrint(
        '⚠️ Cannot update circle - mapController: ${mapController != null}, lat: $lat, lng: $lng',
      );
      return;
    }

    try {
      debugPrint(
        '🔵 Adding circle layer at ($lat, $lng) with radius ${radiusInMeters.value}m',
      );

      // Remove and recreate circle with new radius
      await addCircleLayer(mapController!, lat, lng, radiusInMeters.value);

      debugPrint('✅ Circle layer added successfully');

      // Adjust zoom to fit circle
      // debugPrint(
      //   '📹 Setting camera zoom to $zoom for radius ${radiusInKm.value}km',
      // );

      debugPrint('✅ Camera updated successfully');
    } catch (e) {
      debugPrint('❌ Error updating circle radius: $e');
    }
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
      debugPrint('[MemoryLocationPicker] 🎯 initializeLocationPicker() started');

      state.value = MemoryLocationPickerState.loading;
      debugPrint('[MemoryLocationPicker] 📊 State set to: loading');

      _radiusPickerAnnotationsInitialized = false;
      mapController = null;
      annotationManager = null;
      selectedLocationMarker = null;

      // Initialize local tile server first
      await initializeLocalTileServer();

      // Check location permission
    
      state.value = MemoryLocationPickerState.ready;
    } catch (e) {
      debugPrint('🟢🟢🟢🟢🟢 Error initializing location picker: $e');
      errorMessage.value = ' 🟢🟢🟢🟢🟢Failed to initialize location picker: $e';
      // state.value = MemoryLocationPickerState.error;
    }
  }

  /// Initialize local tile server before map creation
  Future<void> initializeLocalTileServer() async {
    try {
      debugPrint(
        '[MemoryLocationPicker] 🔍 Checking if local tile server is running...',
      );

      final serverService = MbtilesServerService.instance;

// serverService.
      print('[MemoryLocationPicker] 🟢🟢🟢🟢🟢Server Service started');

      // If server is not running, try to start it (fallback)
      debugPrint(
        '[MemoryLocationPicker] 🟢🟢🟢🟢🟢⚠️ Server not running, attempting to start...',
      );

      final mbtilesService = MbtilesDownloadService.instance;
      final isDownloaded = await mbtilesService.isMbtilesDownloaded();
      final tilesPath = mbtilesService.getLocalMbtilesPath();

      // Debug logging to understand the issue
      debugPrint('[MemoryLocationPicker] 🟢🟢🟢🟢🟢🔍 Tile check: isDownloaded=$isDownloaded, tilesPath=$tilesPath');

      if (tilesPath == null) {
        serverErrorMessage.value =
            'MBTiles file not downloaded. Please download from Get Started screen first.';
        isInitializingServer.value = false;
        debugPrint('[MemoryLocationPicker] 🟢🟢🟢🟢🟢❌ ${serverErrorMessage.value}');
        debugPrint('[MemoryLocationPicker] 🟢🟢🟢🟢🟢🔍 Debug: isDownloaded=$isDownloaded, tilesPath=$tilesPath');
        return;
      }

      final url = await serverService.startServer(tilesPath);

      if (url != null) {
        serverUrl.value = url;
        isInitializingServer.value = false;
        debugPrint(
          '[MemoryLocationPicker] 🟢🟢🟢🟢🟢✅ Local tile server started at: $url',
        );
      } else {
        serverErrorMessage.value = 'Failed to start local tile server';
        isInitializingServer.value = false;
        debugPrint('[MemoryLocationPicker] ❌ 🟢🟢🟢🟢🟢 ${serverErrorMessage.value}');
      }
    } catch (e) {
      serverErrorMessage.value = 'Error initializing tile server: $e';
      isInitializingServer.value = false;
      debugPrint('[MemoryLocationPicker] ❌ 🟢🟢🟢🟢🟢 ${serverErrorMessage.value}');
    }
  }

  /// Check location permission
  Future<void> checkLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      hasLocationPermission.value =
          permission == LocationPermission.whileInUse ||
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
  Future<String> loadStyleJsonFromAssets(
    String tileUrl,
    String serverUrlValue,
  ) async {
       try {
      debugPrint('[loadStyleJsonFromAssets] 📂 Loading style.json from local storage...');

      // Try to load from local storage first if service is available
      String? styleJsonString;
      if (Get.isRegistered<StyleJsonDownloadService>()) {
        final styleJsonService = Get.find<StyleJsonDownloadService>();
        styleJsonString = await styleJsonService.readStyleJsonContent();
      // debugPrint('[loadStyleJsonFromAssets] Style Json $styleJsonString');
      }

      // Fallback to assets if local file not found or service not available

      if (styleJsonString == null) {
        debugPrint('[loadStyleJsonFromAssets] ⚠️ Local style.json not found, loading from assets...');
        styleJsonString = await rootBundle.loadString('assets/custom-style.json');
        debugPrint('[loadStyleJsonFromAssets] ✅ Loaded style.json from assets');
      } else {
        debugPrint('[loadStyleJsonFromAssets] ✅ Loaded style.json from local storage');
      }

      var modifiedStyleJson = styleJsonString
          .replaceAll('{LOCAL_SERVER_URL}', serverUrlValue)
          .replaceAll('{LOCAL_TILE_URL}', tileUrl);
        debugPrint('[loadStyleJsonFromAssets] Returning Tiles Json...');

      return modifiedStyleJson;
    } catch (e) {
      // Fallback to a simplified style if assets/style.json is not found
      return '''
{
  "version": 8,
  "name": "Local Tiles Fallback",
  "metadata": {
    "mapbox:autocomposite": false
  },
  "sources": {
    "openmaptiles": {
      "type": "vector",
      "tiles": ["$tileUrl"],
      "minzoom": 0,
      "maxzoom": 10
    }
  },
  "projection": { "type": "globe" },
  "sprite": "",
  "glyphs": "",
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": {"background-color": "hsl(47, 26%, 88%)"}
    },
    {
      "id": "water",
      "type": "fill",
      "source": "openmaptiles",
      "source-layer": "water",
      "filter": ["==", "\$type", "Polygon"],
      "paint": {"fill-color": "hsl(205, 56%, 73%)"}
    },
    {
      "id": "road",
      "type": "line",
      "source": "openmaptiles",
      "source-layer": "transportation",
      "paint": {"line-color": "#fff", "line-width": 1.5}
    }
  ]
}
''';
    }
  
  }

  /// Get camera options
  mapbox.CameraOptions? getCameraOptions() {
    // Prioritize selected location over current location
    final hasSelectedLocation = lat != 0.0 && lng != 0.0;

    if (hasSelectedLocation) {
      return mapbox.CameraOptions(
        center: mapbox.Point(coordinates: mapbox.Position(lat, lng)),
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
        isOfflineMode: true,
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
    

    // Build location data in the same format as new location picker
    final locationData = {
      'latitude': lat,
      'longitude': lng,
      'address': name.isNotEmpty ? name : address,
      'city': city,
      'state': '', // Memory picker doesn't have state field
      'country': country,
      'postcode': null,
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'selected',
      'source': 'memory_location_picker',
    };

    final result = {
      'location': locationData,
      'radius': radiusInKm.value,
    };

    debugPrint('🎯 Returning location data (new format): $result');

    Get.back(result: result);
    
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

  /// Call after [loadStyleJson] + delay — not from first [onStyleLoaded] (wrong style / EGL teardown).
  Future<void> onMapStyleReady(mapbox.MapboxMap controller) async {
    if (_radiusPickerAnnotationsInitialized) return;
    if (mapController != controller) {
      debugPrint('[MemoryLocationPicker] onMapStyleReady (radius): stale map, skip');
      return;
    }

    try {

controller.compass.updateSettings(mapbox.CompassSettings(enabled: false));
               controller.scaleBar.updateSettings(mapbox.ScaleBarSettings(enabled: false));
               controller.attribution.updateSettings(mapbox.AttributionSettings(enabled: false));
               controller.logo.updateSettings(mapbox.LogoSettings(enabled: false));

        await checkLocationPermission();
      // await Future.delayed(Duration(seconds: 2));
      // Get current location if permission is available
      // if (hasLocationPermission.value) {
        await getCurrentLocation();
      // }

      // await controller.setBounds(
      //   CameraBoundsOptions(
      //     // optional geographic bounds:
      //     // bounds: LatLngBounds(...),
      //     minZoom: 0,
      //     maxZoom: 20,
      //   ),
      // );

      lat = currentPosition.value!.latitude.toDouble();
      lng = currentPosition.value!.longitude.toDouble();

      // await getCurrentLocation();
      mapController = controller;

      // ENABLE online mode to allow localhost tile server access
      await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
      debugPrint(
        '[MemoryLocationPicker] 🌐 Online mode ENABLED - localhost tile server can now be accessed',
      );

      // Create annotation manager
      annotationManager =
          await controller.annotations.createPointAnnotationManager();

      // Check if there's already a selected location
      final hasSelectedLocation = lat != 0.0 && lng != 0.0;

      if (hasSelectedLocation) {
        // If location is already selected, show that location
        final lat = this.lat;
        final lng = this.lng;

        updateRadius(0.8);

        await moveToLocation(lat, lng);
        await selectLocation(lat, lng);
        debugPrint(
          '📍 Showing previously selected location on map load: $lat, $lng',
        );
      } else if (hasLocationPermission.value && currentPosition.value != null) {
        updateRadius(0.8);
        // Otherwise, show current location if available
        await moveToLocation(
          currentPosition.value!.latitude,
          currentPosition.value!.longitude,
        );
        // Automatically select current location with polygon
        await selectLocation(
          currentPosition.value!.latitude,
          currentPosition.value!.longitude,
        );
        debugPrint('📍 Auto-selected current location on map load');
      }
      _radiusPickerAnnotationsInitialized = true;
    } catch (e) {
      debugPrint('Error in onMapStyleReady: $e');
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
          zoom: radiusToZoom(radiusInKm.value) - 2,
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

    // Add circle with current radius (or default if not set)
    final currentRadius = radiusInKm.value * 1000;
    print('current Radius $currentRadius');
    await addCircleLayer(mapController!, latitude, longitude, currentRadius);

    try {
      final locationData =
          await MemoryLocationPinGeocoding(mapController).buildLocationDataForPin(
        latitude,
        longitude,
      );

      lat = latitude;
      lng = longitude;
      if (locationData != null) {
        name = locationData['name'] as String? ?? 'Unknown Location';
        city = locationData['city'] as String? ?? '';
        country = locationData['country'] as String? ?? '';
        address = locationData['address'] as String? ?? '';
        flag = locationData['flag'] as String? ?? '';
        debugPrint(
          'Selected location: $name ($latitude, $longitude)',
        );
      } else {
        name = 'Unknown Location';
        debugPrint('Selected location (no geocode): ($latitude, $longitude)');
      }
    } catch (e) {
      debugPrint('Error Reverse geocoding $e');
    }
  }

  Future<void> addCircleLayer(
    mapbox.MapboxMap map,
    double lat,
    double lng,
    double radiusMeters,
  ) async {
    final style = map.style;

    double width = getWidth(radiusInKm.value);
    // Ensure coordinates are [lng, lat]!
    try {
      final geoJsonString = jsonEncode(
        generateCirclePolygon(lat: lat, lng: lng, radiusMeters: radiusMeters),
      );

      // Remove existing layers and source if they exist
      if (await style.styleLayerExists('circle-fill-layer')) {
        await style.removeStyleLayer('circle-fill-layer');
      }
      if (await style.styleLayerExists('circle-outline-layer')) {
        await style.removeStyleLayer('circle-outline-layer');
      }
      if (await style.styleSourceExists('circle-source')) {
        await style.removeStyleSource('circle-source');
      }

      // Add the source
      await style.addSource(
        mapbox.GeoJsonSource(id: 'circle-source', data: geoJsonString),
      );

      // Add fill layer
      await style.addLayer(
        mapbox.FillLayer(
          id: 'circle-fill-layer',
          sourceId: 'circle-source',
          fillColor: uiController.currentMainColor.toARGB32(),
          fillOpacity: 0.8,
        ),
      );

      // Add outline layer
      await style.addLayer(
        mapbox.LineLayer(
          id: 'circle-outline-layer',
          sourceId: 'circle-source',
          lineColor: Colors.white.toARGB32(),
          lineWidth: width,
        ),
      );

      // Move layers below a known label layer (check actual layer IDs!)
      // final allLayers = await style.styleAllLayerIds();
          final layers = await mapController!.style.getStyleLayers();

      String? labelLayerId = layers[80]!.id;
      for (var id in layers) {
        print('Layer IDS: ${id.toString()}');
        if (id!.type.toLowerCase().contains('symbol')) {
          labelLayerId = id.id;
          break;
        }
      }

      if (labelLayerId != null) {
        await style.moveStyleLayer(
          'circle-fill-layer',
          mapbox.LayerPosition(above: labelLayerId),
        );
        await style.moveStyleLayer(
          'circle-fill-layer',
          mapbox.LayerPosition(below: labelLayerId),
        );
      }

      // Optional: zoom to circle if needed
      // await map.setCamera(
      //   mapbox.CameraOptions(
      //     center: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      //     zoom: 14,
      //   ),
      // );
    } catch (_) {}
  }

  /// Generates a GeoJSON polygon representing a circle (radius in meters)
  /// Uses Haversine formula for accurate geodesic circle calculation
  Map<String, dynamic> generateCirclePolygon({
    required double lat, // center latitude in degrees
    required double lng, // center longitude in degrees
    required double radiusMeters,
    int points = 360, // Increased from 256 for smoother circle
  }) {
    // WGS84 ellipsoid parameters for more accurate Earth model
    const double earthRadiusEquator = 6378137.0; // meters at equator
    const double earthRadiusPolar = 6356752.314245; // meters at poles

    // Calculate Earth radius at given latitude using ellipsoid model
    final double latRad = lat * pi / 180;
    final double lngRad = lng * pi / 180;

    // More accurate Earth radius at this latitude
    final double cosLat = cos(latRad);
    final double sinLat = sin(latRad);
    final double earthRadius = sqrt(
      (pow(earthRadiusEquator * earthRadiusEquator * cosLat, 2) +
              pow(earthRadiusPolar * earthRadiusPolar * sinLat, 2)) /
          (pow(earthRadiusEquator * cosLat, 2) +
              pow(earthRadiusPolar * sinLat, 2)),
    );

    final List<List<double>> coordinates = [];

    // Generate points around the circle using Haversine formula
    for (int i = 0; i <= points; i++) {
      final double bearing = 2 * pi * i / points; // 0 to 2π radians

      // Angular distance in radians
      final double angularDistance = radiusMeters / earthRadius;

      // Calculate new latitude using Haversine formula
      final double newLatRad = asin(
        sin(latRad) * cos(angularDistance) +
            cos(latRad) * sin(angularDistance) * cos(bearing),
      );

      // Calculate new longitude using Haversine formula
      final double newLngRad =
          lngRad +
          atan2(
            sin(bearing) * sin(angularDistance) * cos(latRad),
            cos(angularDistance) - sin(latRad) * sin(newLatRad),
          );

      // Convert back to degrees
      final double newLat = newLatRad * 180 / pi;
      final double newLng = newLngRad * 180 / pi;

      // Normalize longitude to -180 to 180 range
      double normalizedLng = newLng;
      while (normalizedLng > 180) {
        normalizedLng -= 360;
      }
      while (normalizedLng < -180) {
        normalizedLng += 360;
      }

      coordinates.add([normalizedLng, newLat]);
    }

    return {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "geometry": {
            "type": "Polygon",
            "coordinates": [coordinates],
          },
          "properties": {
            "radius_meters": radiusMeters,
            "center_lat": lat,
            "center_lng": lng,
          },
        },
      ],
    };
  }

  /// Create a circular marker image with app primary color
  Future<Uint8List> _createCircularMarker() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = 100.0;
    final center = Offset(size / 2, size / 2);
    final radius = size / 2;

    // Draw outer white circle (border)
    final outerPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, outerPaint);

    // Draw inner circle with primary color
    final innerPaint =
        Paint()
          ..color = uiController.currentMainColor
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 8, innerPaint);

    // Draw center white dot
    final centerDotPaint =
        Paint()
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
    lat = point.coordinates.lat.toDouble();
    lng = point.coordinates.lng.toDouble();

    updateCircleRadius();

    moveToLocation(lat, lng);
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
      hasLocationPermission.value =
          permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;

      if (hasLocationPermission.value) {
        await getCurrentLocation();
        if (currentPosition.value != null) {
          updateCircleRadius();

          moveToLocation(lat, lng);
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
    lat = 0.0;
    lng = 0.0;
    city = '';

    country = '';
    address = '';
    flag = '';
    name = '';
    address_state = '';
  }

  void updateRadius(double value) {
    radiusInKm.value = getRadiusKm(value);
    radiusInMeters.value = getRadiusKm(value).toDouble() * 1000;

    updateCircleRadius();

    moveToLocation(lat, lng);
    // selectLocation(lat, lng);
  }

  double getRadiusKm(double seekValue) {
    if (seekValue <= 0) {
      return 4.0;
    }

    // 1 → 50  => 10 → 100 km
    if (seekValue <= 50) {
      const minSeek = 1.0;
      const maxSeek = 50.0;
      const minRadius = 10.0;
      const maxRadius = 100.0;

      return minRadius +
          ((seekValue - minSeek) *
              (maxRadius - minRadius) /
              (maxSeek - minSeek));
    }

    // 51 → 100 => 100 → 500 km
    const minSeek = 51.0;
    const maxSeek = 100.0;
    const minRadius = 100.0;
    const maxRadius = 500.0;

    return minRadius +
        ((seekValue - minSeek) * (maxRadius - minRadius) / (maxSeek - minSeek));
  }

  double radiusToZoom(double radiusKm) {
    if (radiusKm < 5) {
      return 12;
    }
    if (radiusKm <= 10) {
      return 12;
    }

    if (radiusKm <= 20) {
      return 10.5;
    }

    if (radiusKm < 30) {
      return 10;
    }

    if (radiusKm <= 60) {
      return 9.5;
    }

    if (radiusKm <= 100) {
      return 8.7;
    }

    if (radiusKm <= 150) {
      return 8.2;
    }

    if (radiusKm <= 200) {
      return 7.7;
    }

    if (radiusKm <= 250) {
      return 7.2;
    }

    if (radiusKm <= 300) {
      return 6.7;
    }

    if (radiusKm <= 350) {
      return 6.4;
    }

    if (radiusKm <= 400) {
      return 6.2;
    }

    if (radiusKm <= 450) {
      return 5.8;
    }
    if (radiusKm <= 500) {
      return 5.5;
    }

    return 5.5;
    // const double worldKm = 40075.0;

    // Prevent invalid values
    // radiusKm = radiusKm.clamp(1.0, worldKm);

    // double zoom = log(worldKm / radiusKm) / ln2;

    //   print('Setting Camera Zoom $zoom');

    //   if(radiusKm < 100) {

    //     if(this.radiusInKm.value < 10) {
    // print('Setting Camera Zoom Returning 18 $zoom');
    //       return 13;
    //     }

    //
    // }
    //  if(this.radiusInKm.value > 450) {
    //   print('Setting Camera Zoom Returning 7 $zoom');
    //         return 5;
    //       }
    //     // Optional clamp to Mapbox zoom limits
    //     return zoom.clamp(0.0, 22.0);
  }

  double getWidth(double value) {
    if (value < 10) {
      return 4;
    }

    if (value < 50) {
      return 4;
    }

    if (value < 100) {
      return 4;
    }

    if (value < 200) {
      return 4;
    }

    if (value < 350) {
      return 4;
    }
    if (value < 500) {
      return 4;
    }
    return 4;
  }

Future<void> _getLocationDetails(double lat, double lng) async {
    try {
      final result =
          await MemoryLocationPinGeocoding(mapController).buildLocationDataForPin(
        lat,
        lng,
      );

      if (result != null) {
         country = result['country'] as String? ?? '';
         city = result['city'] as String? ?? '';
         address = result['address'] as String? ?? '';
         flag = result['flag'] as String? ?? '';
         name = result['name'] as String? ?? '';

      //   memoryController.setEnhancedLocationData({
      //     'latitude': lat,
      //     'longitude': lng,
      //     'city': city,
      //     'country': country,
      //     'address': address,
      //     'flag': flag,
      //     'name': city.isNotEmpty ? '$city, $country' : country,
      //   });

      //   debugPrint('📍 Location details: $city, $country $flag');
      // } else {
      //   // Fallback to basic location data
      //   memoryController.setEnhancedLocationData({
      //     'latitude': lat,
      //     'longitude': lng,
      //     'city': 'Selected Location',
      //     'country': 'Unknown',
      //     'flag': '📍',
      //   });
      }

       final locationData = {
      'latitude': lat,
      'longitude': lng,
      'address': '$flag $city, $country',
      'city': city,
      'state': '', // Memory picker doesn't have state field
      'country': country,
      'location_flag': flag, // Add location flag
      'postcode': null,
      'timestamp': DateTime.now().toIso8601String(),
      'type': 'selected',
      'source': 'memory_location_picker',
    };

    final result1 = {
      'location': locationData,
      'radius': radiusInKm.value,
    };

    debugPrint('🎯 Returning location data (new format): $result');
    debugPrint('🎯 Location flag: $flag');

    Get.back(result: result1);
    } catch (e) {
     
    }
  }


  Future<void> onDonePressed1() async {

    await _getLocationDetails(lat,lng);   
    
  }
}
