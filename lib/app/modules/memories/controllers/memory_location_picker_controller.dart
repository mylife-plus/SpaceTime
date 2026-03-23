import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/helpers/offline_water_service.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'package:spacetime/app/modules/location_picker/services/location_picker_service.dart';
import 'package:spacetime/services/mbtiles_download_service.dart';
import 'package:spacetime/services/mbtiles_server_service.dart';
import 'package:spacetime/services/style_json_download_service.dart';
import 'package:spacetime/app/utils/place_categories_utils.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/memory_location_admin_edit_widget.dart';

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
    final adminData = await getAdminHierarchy(lat, lng);
    final adminWater = adminData['water'];
    final isTapOnWater = await _isTapOnWater(lat, lng, adminWater: adminWater);

    final tileSubRegion = adminData['subRegion'] ?? adminData['city'];
    final locationData1 = await GeocodingIsolateService.instance.reverseGeocode(
      lat,
      lng,
      tileSubRegion: tileSubRegion,
    );

    if (locationData1 == null && !isTapOnWater) {
      return null;
    }

    Map<String, dynamic> finalData = locationData1 ?? <String, dynamic>{};
    String? waterName;
    if (isTapOnWater) {
      waterName = adminWater;
      if (waterName == null ||
          waterName.trim().isEmpty ||
          waterName.trim().toLowerCase() == 'water') {
        final detailedWaterName = await _queryWaterNameFromRenderedTiles(lat, lng);
        if (detailedWaterName != null && detailedWaterName.trim().isNotEmpty) {
          waterName = detailedWaterName;
        }
      }
      if (waterName == null ||
          waterName.trim().isEmpty ||
          waterName.trim().toLowerCase() == 'water') {
        final fallback = _resolveWaterNameFallback(lat, lng);
        if (fallback != null && fallback.trim().isNotEmpty) {
          waterName = fallback;
        }
      }
    }

    final shouldApplyWater = _shouldApplyWaterResult(
      isTapOnWater: isTapOnWater,
      waterName: waterName,
    );
    if (shouldApplyWater && waterName != null) {
      finalData['city'] = waterName;
      finalData['name'] = waterName;
      finalData['address'] = waterName;
      if (finalData['country'] == null ||
          (finalData['country'] as String? ?? '').isEmpty) {
        finalData['country'] = '';
      }
      finalData['flag'] = '🌊';
    } else {
      waterName = null;
    }

    final displayName = finalData['display_name'] as String? ??
        finalData['name'] as String? ??
        'Unknown Location';
    final nameOut = (finalData['name'] as String?)?.trim().isNotEmpty == true
        ? finalData['name'] as String
        : displayName;

    var country = finalData['country'] as String? ?? '';
    var flag = finalData['flag'] as String? ?? '';
    var city = finalData['city'] as String? ?? '';

    if (country.isEmpty && adminData['country'] != null) {
      country = adminData['country']!;
    }
    if (flag.isEmpty && country.isNotEmpty) {
      flag = countryFlags[country.toLowerCase()] ?? '';
    }
    if (city.isEmpty && tileSubRegion != null && tileSubRegion.isNotEmpty) {
      city = tileSubRegion;
    }

    final waterFlag = waterName != null && waterName.toLowerCase().contains('ocean')
        ? '🇺🇳'
        : '🌊';

    return <String, dynamic>{
      'latitude': lat,
      'longitude': lng,
      'city': city,
      'country': country,
      'address': finalData['address'] as String? ?? '',
      'flag': waterName != null ? waterFlag : flag,
      'name': nameOut,
    };
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

  Future<bool> _isTapOnWater(
    double lat,
    double lng, {
    String? adminWater,
  }) async {
    final admin = (adminWater ?? '').trim().toLowerCase();
    if (admin.isNotEmpty && admin != 'water') {
      return true;
    }

    final offline = OfflineWaterService.instance.detect(lat, lng);
    if (offline != null) {
      return true;
    }

    final rendered = await _queryWaterNameFromRenderedTiles(lat, lng);
    if (rendered != null && rendered.trim().isNotEmpty) {
      return true;
    }
    return false;
  }

  bool _shouldApplyWaterResult({
    required bool isTapOnWater,
    required String? waterName,
  }) {
    if (!isTapOnWater) return false;
    if (waterName == null) return false;
    final w = waterName.trim();
    if (w.isEmpty) return false;
    if (w.toLowerCase() == 'water') return false;
    return _isLikelyWaterName(w);
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
    clearSearch();

    final point = context.point;

    final latitude = point.coordinates.lat.toDouble();
    final longitude = point.coordinates.lng.toDouble();

    await selectLocation(latitude, longitude);
  }

  Future<Map<String, String?>> getAdminHierarchy(double lat, double lng) async {
    final result = <String, String?>{
      'city': null,
      'region': null,
      'subRegion': null,
      'country': null,
      'water': null,
    };
    if (mapController == null) return result;
    try {
      final pixel = await mapController!.pixelForCoordinate(
        mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      );

      final geometry = mapbox.RenderedQueryGeometry.fromScreenCoordinate(pixel);

      final features = await mapController!.queryRenderedFeatures(
        geometry,
        mapbox.RenderedQueryOptions(
          layerIds: null,
          filter: null,
        ),
      );

      if (features.isEmpty) {
        debugPrint('[AdminHierarchy] No features found at $lat, $lng');
        return result;
      }

      for (final f in features) {
        if (f == null) continue;
        final props = (f.queriedFeature.feature['properties'] as Map?)?.cast<String, dynamic>();
        final sourceLayer = f.queriedFeature.sourceLayer ?? '';
        final className = props?['class']?.toString() ?? '';

        // final sourceLayer = f.queriedFeature.sourceLayer ?? '';
        debugPrint('[AdminHierarchy] sourceLayer=$sourceLayer class=$className props=$props');

        if (sourceLayer == 'water' || sourceLayer == 'water_name') {
          final name = (props?['name:en'] ?? props?['name'])?.toString();
          if (result['water'] == null) {
            result['water'] = (name != null && name.isNotEmpty) ? name : 'Water';
          // }
          // if(result['water'] == 'Water') {
            
// final polygonFeature =
//     await getWaterPolygonById('openmaptiles', sourceLayer, featureId);

// if (polygonFeature != null) {
//   // final name = polygonFeature['properties']?['name:en'] ??
//   //     polygonFeature['properties']?['name'] ??
//   //     'Water';
//   // final classType =
//   //     polygonFeature['properties']?['class'] ?? 'water';
// // final waterName = await getWaterLabel(
// //       polygonFeature,
// //   ['Water labels', 'Lakeline labels'], // style layer IDs
// //   );

//   result['water'] = waterName ?? 'Water';
//   result['waterType'] = polygonFeature['properties']?['class'] ?? 'water';
//   print('Water name from polygon is $waterName type ${result['waterType']}');
//   // print('Water name: $name');
//   // print('Class: $classType');
//   // print('Geometry: ${polygonFeature['geometry']}');
// }
          }
          continue;
        }

        if (props == null) continue;

        final name = (props['name:en'] ?? props['name'])?.toString();
        if (name == null || name.isEmpty) continue;

        if (sourceLayer == 'place') {
          if (['country'].contains(className) && result['country'] == null) {
            result['country'] = name;
          } else if (['state', 'province', 'region'].contains(className) && result['region'] == null) {
            result['region'] = name;
          } else if (['county', 'district'].contains(className) && result['subRegion'] == null) {
            result['subRegion'] = name;
          } else if (['city', 'town', 'village', 'suburb', 'hamlet', 'quarter', 'neighbourhood'].contains(className) && result['city'] == null) {
            result['city'] = name;
          }
        }
      }

      debugPrint('[AdminHierarchy] result=$result');
    } catch (e) {
      debugPrint('[AdminHierarchy] Error: $e');
    }
    return result;
  }

  bool _isLikelyWaterName(String name) {
    final n = name.toLowerCase();
    return n.contains('ocean') ||
        n.contains('sea') ||
        n.contains('lake') ||
        n.contains('river') ||
        n.contains('stream') ||
        n.contains('brook') ||
        n.contains('creek') ||
        n.contains('canal') ||
        n.contains('dam') ||
        n.contains('reservoir') ||
        n.contains('pond') ||
        n.contains('lagoon') ||
        n.contains('fjord') ||
        n.contains('wetland') ||
        n.contains('marsh') ||
        n.contains('swamp') ||
        n.contains('delta') ||
        n.contains('estuary') ||
        n.contains('inlet') ||
        n.contains('harbor') ||
        n.contains('harbour') ||
        n.contains('dock') ||
        n.contains('basin') ||
        n.contains('bay') ||
        n.contains('gulf') ||
        n.contains('strait') ||
        n.contains('channel') ||
        n.contains('sound');
  }

  bool _isWaterClass(String className) {
    final c = className.toLowerCase();
    return c.contains('water') ||
        c.contains('river') ||
        c.contains('stream') ||
        c.contains('brook') ||
        c.contains('creek') ||
        c.contains('canal') ||
        c.contains('dam') ||
        c.contains('reservoir') ||
        c.contains('pond') ||
        c.contains('lagoon') ||
        c.contains('fjord') ||
        c.contains('wetland') ||
        c.contains('marsh') ||
        c.contains('swamp') ||
        c.contains('delta') ||
        c.contains('estuary') ||
        c.contains('inlet') ||
        c.contains('harbor') ||
        c.contains('harbour') ||
        c.contains('dock') ||
        c.contains('basin') ||
        c.contains('lake') ||
        c.contains('ocean') ||
        c.contains('sea') ||
        c.contains('gulf') ||
        c.contains('bay') ||
        c.contains('strait') ||
        c.contains('channel') ||
        c.contains('sound');
  }

  bool _isWaterSourceLayer(String sourceLayer) {
    final s = sourceLayer.toLowerCase();
    return s.contains('water') ||
        s.contains('waterway') ||
        s.contains('marine') ||
        s.contains('ocean') ||
        s.contains('sea') ||
        s.contains('river') ||
        s.contains('lake') ||
        s.contains('canal') ||
        s.contains('dam') ||
        s.contains('reservoir') ||
        s.contains('wetland') ||
        s.contains('marsh') ||
        s.contains('stream') ||
        s.contains('basin');
  }

  Future<String?> _queryWaterNameFromRenderedTiles(double lat, double lng) async {
    if (mapController == null) {
      print('[WaterNameSearch] mapController is null, skipping');
      return null;
    }
    try {
      print('[WaterNameSearch] Start lookup at lat=$lat lng=$lng');
      final centerPixel = await mapController!.pixelForCoordinate(
        mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      );

      // Query around tap point (screen-space) to catch nearby water labels/features.
      const offsets = <List<double>>[
        [0, 0],
        [20, 0], [-20, 0], [0, 20], [0, -20],
        [40, 0], [-40, 0], [0, 40], [0, -40],
        [20, 20], [20, -20], [-20, 20], [-20, -20],
        [60, 0], [-60, 0], [0, 60], [0, -60],
      ];

      bool sawWaterFeature = false;
      final Map<String, double> namedCandidates = <String, double>{};
      int probeIndex = 0;

      for (final off in offsets) {
        probeIndex++;
        final probe = mapbox.ScreenCoordinate(
          x: centerPixel.x + off[0],
          y: centerPixel.y + off[1],
        );
        final geometry = mapbox.RenderedQueryGeometry.fromScreenCoordinate(probe);
        final features = await mapController!.queryRenderedFeatures(
          geometry,
          mapbox.RenderedQueryOptions(
            // Query all rendered style layers; then filter by sourceLayer/class.
            // Passing source-layer names here can return zero matches.
            layerIds: null,
            filter: null,
          ),
        );
        if (features.isNotEmpty) {
          print(
            '[WaterNameSearch] Probe#$probeIndex offset=(${off[0]},${off[1]}) features=${features.length}',
          );
        }

        for (final f in features) {
          if (f == null) continue;
          final featureMap = Map<String, dynamic>.from(f.queriedFeature.feature);
          final sourceLayer = (f.queriedFeature.sourceLayer ?? '').toLowerCase();
          final props =
              (featureMap['properties'] as Map?)?.cast<String, dynamic>();
          final className =
              (props?['class'] ?? props?['subclass'] ?? props?['type'] ?? '')
                  .toString();
          final name =
              (props?['name:en'] ?? props?['name'] ?? props?['name_en'])
                  ?.toString()
                  .trim();

          if (_isWaterSourceLayer(sourceLayer) || _isWaterClass(className)) {
            sawWaterFeature = true;
          }

          if (name != null &&
              name.isNotEmpty &&
              (_isWaterClass(className) ||
                  _isWaterSourceLayer(sourceLayer) ||
                  _isLikelyWaterName(name))) {
            final contained = _isPointInsideFeaturePolygon(featureMap, lat, lng);
            double scoreKm = _featureDistanceKm(featureMap, lat, lng);
            if (scoreKm.isInfinite) {
              // Fallback score from probe offset when geometry is missing.
              scoreKm = math.sqrt(off[0] * off[0] + off[1] * off[1]) / 40.0;
            }
            scoreKm += _waterClassPenaltyKm(className, name);
            if (contained) {
              scoreKm -= 120.0; // Strongly prefer containing polygon.
            }
            final prev = namedCandidates[name];
            if (prev == null || scoreKm < prev) {
              namedCandidates[name] = scoreKm;
            }
            print(
              '[WaterNameSearch] Candidate name="$name" sourceLayer="$sourceLayer" class="$className" contained=$contained scoreKm=${scoreKm.toStringAsFixed(3)}',
            );
          }
        }
      }

      if (namedCandidates.isNotEmpty) {
        final sorted = namedCandidates.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        final best = sorted.first;
        if (best.value > 250.0) {
          print(
            '[WaterNameSearch] Rejecting rendered candidate "${best.key}" due to far score=${best.value.toStringAsFixed(3)}',
          );
        } else {
        print(
          '[WaterNameSearch] Selected nearest water="${best.key}" scoreKm=${best.value.toStringAsFixed(3)} candidates=${sorted.length}',
        );
        return best.key;
        }
      }

      // Rendered labels can be unavailable at some zooms/styles (e.g., oceans).
      // Query source features directly from loaded vector tiles as fallback.
      final sourceName = await _queryWaterNameFromSourceFeatures(lat, lng);
      if (sourceName != null && sourceName.trim().isNotEmpty) {
        print('[WaterNameSearch] Source-feature fallback selected "$sourceName"');
        return sourceName;
      }

      // Water geometry found but unnamed: only trust if offline water detection
      // also confirms current tap is on water.
      if (sawWaterFeature) {
        final offlineHit = OfflineWaterService.instance.detect(lat, lng);
        if (offlineHit != null) {
          final n = (offlineHit.name ?? '').trim();
          if (n.isNotEmpty) {
            print('[WaterNameSearch] Unnamed rendered water confirmed by offline="$n"');
            return n;
          }
          print('[WaterNameSearch] Unnamed rendered water confirmed by offline (generic)');
          return 'Water';
        }
        print(
          '[WaterNameSearch] Rendered water seen but offline check is land; treating as non-water',
        );
        return null;
      }
      print('[WaterNameSearch] No water feature/name found');
    } catch (e) {
      print('[WaterNameSearch] Error querying rendered water features: $e');
    }
    return null;
  }

  Future<String?> _queryWaterNameFromSourceFeatures(double lat, double lng) async {
    if (mapController == null) return null;
    try {
      final sourceCandidates = <String, double>{};
      const sourceLayers = <String>[
        'water_name',
        'waterway',
        'water',
        'marine',
        'marine_label',
        'waterway_label',
      ];

      for (final layer in sourceLayers) {
        final features = await mapController!.querySourceFeatures(
          'openmaptiles',
          mapbox.SourceQueryOptions(
            sourceLayerIds: [layer],
            filter: 'all',
          ),
        );
        if (features.isEmpty) continue;

        print('[WaterNameSearch] Source layer="$layer" features=${features.length}');

        for (final f in features) {
          if (f == null) continue;
          final featureMap = Map<String, dynamic>.from(f.queriedFeature.feature);
          final props =
              (featureMap['properties'] as Map?)?.cast<String, dynamic>();
          if (props == null) continue;

          final className =
              (props['class'] ?? props['subclass'] ?? props['type'] ?? '')
                  .toString();
          final name =
              (props['name:en'] ?? props['name'] ?? props['name_en'])
                  ?.toString()
                  .trim();

          if (name == null || name.isEmpty) continue;
          if (!(_isWaterClass(className) || _isLikelyWaterName(name))) continue;

          final contained = _isPointInsideFeaturePolygon(featureMap, lat, lng);
          if ((className.toLowerCase().contains('ocean') ||
                  name.toLowerCase().contains('ocean')) &&
              !contained) {
            // Avoid far ocean false positives when tap is inland.
            continue;
          }
          double scoreKm = _featureDistanceKm(featureMap, lat, lng);
          if (scoreKm.isInfinite) continue;
          scoreKm += _waterClassPenaltyKm(className, name);
          if (contained) {
            scoreKm -= 120.0;
          }
          final prev = sourceCandidates[name];
          if (prev == null || scoreKm < prev) {
            sourceCandidates[name] = scoreKm;
          }
        }
      }

      if (sourceCandidates.isEmpty) return null;
      final sorted = sourceCandidates.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final best = sorted.first;
      if (best.value > 250.0) {
        print(
          '[WaterNameSearch] Rejecting source candidate "${best.key}" due to far score=${best.value.toStringAsFixed(3)}',
        );
        return null;
      }
      print(
        '[WaterNameSearch] Source nearest water="${best.key}" scoreKm=${best.value.toStringAsFixed(3)} candidates=${sorted.length}',
      );
      return best.key;
    } catch (e) {
      print('[WaterNameSearch] Source-feature fallback error: $e');
      return null;
    }
  }

  (double, double)? _featureRepresentativePoint(Map<String, dynamic> featureMap) {
    try {
      final geometry = featureMap['geometry'];
      if (geometry is! Map) return null;
      final coordinates = geometry['coordinates'];
      if (coordinates == null) return null;
      final points = <(double, double)>[];
      _collectLngLatPairs(coordinates, points);
      if (points.isEmpty) return null;
      double latSum = 0;
      double lngSum = 0;
      for (final p in points) {
        latSum += p.$1;
        lngSum += p.$2;
      }
      return (latSum / points.length, lngSum / points.length);
    } catch (_) {
      return null;
    }
  }

  bool _isPointInsideFeaturePolygon(
    Map<String, dynamic> featureMap,
    double lat,
    double lng,
  ) {
    try {
      final geometry = featureMap['geometry'];
      if (geometry is! Map) return false;
      final type = (geometry['type'] ?? '').toString();
      final coords = geometry['coordinates'];
      if (coords == null) return false;

      if (type == 'Polygon' && coords is List) {
        for (final ring in coords) {
          if (ring is List && _pointInRing(lat, lng, ring)) return true;
        }
      } else if (type == 'MultiPolygon' && coords is List) {
        for (final poly in coords) {
          if (poly is! List) continue;
          for (final ring in poly) {
            if (ring is List && _pointInRing(lat, lng, ring)) return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  bool _pointInRing(double lat, double lng, List ring) {
    bool inside = false;
    int j = ring.length - 1;
    for (int i = 0; i < ring.length; i++) {
      final pi = ring[i];
      final pj = ring[j];
      if (pi is! List || pj is! List || pi.length < 2 || pj.length < 2) {
        j = i;
        continue;
      }
      final xi = (pi[0] as num).toDouble();
      final yi = (pi[1] as num).toDouble();
      final xj = (pj[0] as num).toDouble();
      final yj = (pj[1] as num).toDouble();
      final intersect =
          ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
      if (intersect) inside = !inside;
      j = i;
    }
    return inside;
  }

  double _waterClassPenaltyKm(String className, String name) {
    final c = className.toLowerCase();
    final n = name.toLowerCase();
    if (c.contains('dam') || n.contains('dam')) return -30.0;
    if (c.contains('canal') || n.contains('canal')) return -28.0;
    if (c.contains('lake') || n.contains('lake')) return -22.0;
    if (c.contains('gulf') || c.contains('strait') || c.contains('bay') || n.contains('gulf') || n.contains('strait') || n.contains('bay')) {
      return -35.0;
    }
    if (c.contains('sea') || n.contains('sea')) return -25.0;
    if (c.contains('river') || n.contains('river')) return -8.0;
    if (c.contains('ocean') || n.contains('ocean')) return 220.0;
    return 0.0;
  }

  double _featureDistanceKm(
    Map<String, dynamic> featureMap,
    double lat,
    double lng,
  ) {
    try {
      // Best signal for polygonal water bodies.
      if (_isPointInsideFeaturePolygon(featureMap, lat, lng)) {
        return 0.0;
      }
      final geometry = featureMap['geometry'];
      if (geometry is! Map) return double.infinity;
      final coordinates = geometry['coordinates'];
      if (coordinates == null) return double.infinity;

      // Use nearest vertex distance (better for long canals/river lines than centroid).
      final points = <(double, double)>[];
      _collectLngLatPairs(coordinates, points);
      if (points.isEmpty) return double.infinity;

      double minKm = double.infinity;
      for (final p in points) {
        final d = _haversineKm(lat, lng, p.$1, p.$2);
        if (d < minKm) minKm = d;
      }
      return minKm;
    } catch (_) {
      return double.infinity;
    }
  }

  void _collectLngLatPairs(dynamic coords, List<(double, double)> out) {
    if (coords is List) {
      if (coords.length >= 2 && coords[0] is num && coords[1] is num) {
        out.add(((coords[1] as num).toDouble(), (coords[0] as num).toDouble()));
        return;
      }
      for (final c in coords) {
        _collectLngLatPairs(c, out);
      }
    }
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String? _resolveWaterNameFallback(double lat, double lng) {
    try {
      // First, exact tap point.
      final exact = OfflineWaterService.instance.detect(lat, lng);
      if (exact != null && (exact.name?.trim().isNotEmpty ?? false)) {
        final n = exact.name!.trim();
        print('[WaterNameSearch] Offline fallback exact hit="$n"');
        return n;
      }

      // Then sample nearby points so unnamed "water" taps can still resolve
      // to known seas/oceans from offline marine polygons.
      const radiiKm = <double>[10, 25, 50, 100, 180];
      const bearings = <double>[0, 45, 90, 135, 180, 225, 270, 315];

      for (final rKm in radiiKm) {
        final dLat = rKm / 111.0;
        final dLngBase =
            rKm / (111.0 * math.max(0.2, math.cos(lat * math.pi / 180.0)));
        for (final b in bearings) {
          final rad = b * math.pi / 180.0;
          final sampleLat = lat + dLat * math.sin(rad);
          final sampleLng = lng + dLngBase * math.cos(rad);
          final hit = OfflineWaterService.instance.detect(sampleLat, sampleLng);
          if (hit != null && (hit.name?.trim().isNotEmpty ?? false)) {
            final n = hit.name!.trim();
            print(
              '[WaterNameSearch] Offline fallback nearby hit="$n" '
              'radiusKm=$rKm bearing=$b',
            );
            return n;
          }
        }
      }

      print('[WaterNameSearch] Offline fallback no named water found');
    } catch (e) {
      print('[WaterNameSearch] Offline fallback error: $e');
    }
    return null;
  }

// ------------------- HELPER: Get water polygon by featureId -------------------
Future<Map<String, dynamic>?> getWaterPolygonById(
  String sourceId,
  String sourceLayer,
  String featureId,
  // mapbox.MapboxMapController? mapController,
) async {
  // if (mapController == null) return null;

  try {
    debugPrint(
        '[getWaterPolygonById] Querying sourceId="$sourceId", layer="$sourceLayer", featureId="$featureId"');

    final sourceFeatures = await mapController?.querySourceFeatures(
      sourceId,
      mapbox.SourceQueryOptions(
        sourceLayerIds: [sourceLayer],
        filter: 'all', // include all
      ),
    );

    debugPrint(
        '[getWaterPolygonById] Total features retrieved: ${sourceFeatures?.length}');

    if (sourceFeatures == null) return null;
    for (final f in sourceFeatures) {
      if (f == null) continue;
      final geojson = Map<String, dynamic>.from(f.queriedFeature.feature);
      final id = geojson['id']?.toString();
      if (id == featureId) {
        debugPrint(
            '[getWaterPolygonById] Found feature! id="$id", properties=${geojson['properties']}');
        return geojson;
      }
    }
  } catch (e, stack) {
    debugPrint('[getWaterPolygonById] Exception: $e');
    debugPrint('[getWaterPolygonById] Stack: $stack');
  }

  return null;
}

// ------------------- HELPER: Query label for water polygon -------------------
Future<String?> getWaterLabel(
  Map<String, dynamic> polygonFeature,
  // mapbox.MapboxMapController?? mapController,
  List<String> labelLayers,
) async {
  // if (mapController == null) return null;

  try {
    // Compute polygon centroid
    final coords = polygonFeature['geometry']['coordinates'][0] as List;
    double sumLat = 0, sumLng = 0;
    for (final c in coords) {
      sumLng += (c[0] as num).toDouble();
      sumLat += (c[1] as num).toDouble();
    }
    final n = coords.length;
    final centroid = LatLng(sumLat / n, sumLng / n);

    final pixel = await mapController?.pixelForCoordinate(
      mapbox.Point(coordinates: mapbox.Position(centroid.longitude, centroid.latitude)),
    );
    final geometry = mapbox.RenderedQueryGeometry.fromScreenCoordinate(pixel!);

    final labelFeatures = await mapController?.queryRenderedFeatures(
      geometry,
      mapbox.RenderedQueryOptions(
        layerIds: labelLayers,
        filter: 'all',
      ),
    );

   for (final f in labelFeatures!) {
  if (f == null) continue;

  // Safely get properties
  final props = (f.queriedFeature.feature['properties'] as Map?)?.cast<String, dynamic>();
  debugPrint('[getWaterLabel] Feature properties: $props');

  // Optional: print the full feature GeoJSON
  final featureJson = const JsonEncoder.withIndent('  ').convert(f.queriedFeature.feature);
  debugPrint('[getWaterLabel] Full feature GeoJSON:\n$featureJson');

  // Extract name if available
  final name = (props?['name:en'] ?? props?['name'])?.toString();
  if (name != null && name.isNotEmpty) {
    debugPrint('[getWaterLabel] Found label: $name');
    return name; // first valid name
  }
}
  } catch (e, stack) {
    debugPrint('[getWaterLabel] Exception: $e');
    debugPrint('[getWaterLabel] Stack: $stack');
  }

  return null;
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
