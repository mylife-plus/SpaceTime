import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/helpers/nearest_region_service.dart';
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
import 'package:spacetime/app/helpers/offline_water_service.dart';

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


    final lat = selectedLocationMarker!.geometry.coordinates.lat.toDouble();
    final lng = selectedLocationMarker!.geometry.coordinates.lng.toDouble();

    final adminData = await getAdminHierarchy(lat, lng);
    print('Admin Data $adminData');
          String? waterName = adminData['water'];

    final tileSubRegion =adminData['subRegion'] ??  adminData['city'];

    final locationData1 = await GeocodingIsolateService.instance.reverseGeocode(
        lat,
        lng,
        tileSubRegion: tileSubRegion,
      );
   

      

      Map<String, dynamic> finalData;

      if (waterName != null && waterName.isNotEmpty) {

        // if (waterName != null || waterName!.isNotEmpty) {
        final waterHit = OfflineWaterService.instance.detect(lat, lng);
        print('WaterHit $waterHit');
        if (waterHit != null) {
          waterName = waterHit.name?.toLowerCase().capitalize;
        // }
      }
        finalData = locationData1 ?? {};
        finalData['city'] = waterName;
        finalData['name'] = waterName;
        if (finalData['country'] == null || (finalData['country'] as String? ?? '').isEmpty) {
          finalData['country'] = '';
        }
        if (finalData['flag'] == null || (finalData['flag'] as String? ?? '').isEmpty) {
          finalData['flag'] = '🌊';
        }
        finalData['address'] = waterName;
      } else if (locationData1 == null) {
        Get.snackbar(
          'Location Not Found',
          'Could not identify this location. Please try a different spot.',
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.red.withValues(alpha: 0.8),
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
        return;
      } else {
        finalData = locationData1;
      }

      final locationName = finalData['display_name'] as String? ?? finalData['name'] as String? ?? 'Unknown Location';

      var country = finalData['country'] as String? ?? '';
      var flag = finalData['flag'] as String? ?? '';
      var city = finalData['city'] as String? ?? '';

      if (country.isEmpty && adminData['country'] != null) {
        country = adminData['country']!;
        finalData['country'] = country;
      }
      if (flag.isEmpty && country.isNotEmpty) {
        flag = countryFlags[country.toLowerCase()] ?? '';
        finalData['flag'] = flag;
      }
      if (city.isEmpty && tileSubRegion != null && tileSubRegion.isNotEmpty) {
        city = tileSubRegion;
        finalData['city'] = city;
      }

      memoryController.locationCountry.value = country;
      memoryController.locationFlag.value = flag;
      memoryController.locationCity.value = city;
      memoryController.locationAddress.value = finalData['address'] as String? ?? '';

      memoryController.selectedLocation.value = locationName;
      memoryController.locationLatitude.value = selectedLocationMarker!.geometry.coordinates.lat.toDouble();
      memoryController.locationLongitude.value = selectedLocationMarker!.geometry.coordinates.lng.toDouble();

    final locationData = {
      'latitude': selectedLocationMarker!.geometry.coordinates.lat,
      'longitude': selectedLocationMarker!.geometry.coordinates.lng,
      'city': memoryController.locationCity.value,
      'country': memoryController.locationCountry.value,
      'address': memoryController.locationAddress.value,
      'flag': waterName != null ? '🇺🇳' : memoryController.locationFlag.value,
      'name': memoryController.locationName.value,
    };

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
    controller.compass.updateSettings(mapbox.CompassSettings(enabled: false));
               controller.scaleBar.updateSettings(mapbox.ScaleBarSettings(enabled: false));
               controller.attribution.updateSettings(mapbox.AttributionSettings(enabled: false));
               controller.logo.updateSettings(mapbox.LogoSettings(enabled: false));

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
      // await _printAllLayersAndSources();
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

  // await getAdminHierarchy(latitude, longitude);

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
      final featureId = f.queriedFeature.feature['id']?.toString() ?? '';
for (final f in features) {

  if (f == null) continue;
}
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

    for (final f in sourceFeatures!) {
      if (f?.queriedFeature?.feature == null) continue;

      final geojson = Map<String, dynamic>.from(f!.queriedFeature!.feature!);
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
  
//   Future<Map<String, dynamic>?> getWaterPolygonById(
//   String sourceId,
//   String sourceLayer,
//   String featureId,
// ) async {
//   if (mapController == null) {
//     debugPrint('[getWaterPolygonById] mapController is null');
//     return null;
//   }

//   try {
//     debugPrint(
//         '[getWaterPolygonById] Querying sourceId="$sourceId", layer="$sourceLayer", featureId="$featureId"');

//     final sourceFeatures = await mapController!.querySourceFeatures(
//       sourceId,
//       mapbox.SourceQueryOptions(
//         sourceLayerIds: [sourceLayer],
//         filter: 'all', // empty filter to include all features
//       ),
//     );

//     if (sourceFeatures.isEmpty) {
//       debugPrint(
//           '[getWaterPolygonById] No features returned from source layer "$sourceLayer"');
//       return null;
//     }

//     debugPrint(
//         '[getWaterPolygonById] Total features retrieved: ${sourceFeatures.length}');

//     for (int index = 0; index < sourceFeatures.length; index++) {
//       final f = sourceFeatures[index];
//       if (f == null) {
//         debugPrint('[getWaterPolygonById] Feature at index $index is null');
//         continue;
//       }

//       final queriedFeature = f.queriedFeature;
//       if (queriedFeature == null) {
//         debugPrint(
//             '[getWaterPolygonById] queriedFeature at index $index is null');
//         continue;
//       }

//       // Safely cast feature map
//       final geojsonRaw = queriedFeature.feature;
//       if (geojsonRaw == null) {
//         debugPrint('[getWaterPolygonById] geojson at index $index is null');
//         continue;
//       }

//       final geojson = Map<String, dynamic>.from(geojsonRaw);

//       final id = geojson['id']?.toString();
//       if (id == null) {
//         debugPrint('[getWaterPolygonById] feature id at index $index is null');
//         continue;
//       }

//       debugPrint('[getWaterPolygonById] Checking feature id="$id"');

//       if (id == featureId) {
//         debugPrint(
//             '[getWaterPolygonById] Found matching feature! id="$id" at index $index');
//         debugPrint('[getWaterPolygonById] Properties: ${geojson['properties']}');
//         debugPrint('[getWaterPolygonById] Geometry: ${geojson['geometry']}');
//         return geojson;
//       }
//     }

//     debugPrint(
//         '[getWaterPolygonById] Feature with id="$featureId" not found');
//   } catch (e, stack) {
//     debugPrint('[getWaterPolygonById] Exception: $e');
//     debugPrint('[getWaterPolygonById] Stack trace: $stack');
//   }

//   return null; // Not found
// }
// //   Future<Map<String, dynamic>?> getWaterPolygonById(
//   String sourceId,
//   String sourceLayer,
//   String featureId,
// ) async {
//   if (mapController == null) {
//     debugPrint('[getWaterPolygonById] mapController is null');
//     return null;
//   }

//   try {
//     debugPrint(
//         '[getWaterPolygonById] Querying sourceId="$sourceId", layer="$sourceLayer", featureId="$featureId"');

//     final List<mapbox.QueriedSourceFeature?> sourceFeatures =
//         await mapController!.querySourceFeatures(
//       sourceId,
//       mapbox.SourceQueryOptions(
//         sourceLayerIds: [sourceLayer],
//     filter: 'all', // empty filter to include all features
//       ),
//     );

//     if (sourceFeatures.isEmpty) {
//       debugPrint(
//           '[getWaterPolygonById] No features returned from source layer "$sourceLayer"');
//       return null;
//     }

//     debugPrint(
//         '[getWaterPolygonById] Total features retrieved: ${sourceFeatures.length}');

//     for (int index = 0; index < sourceFeatures.length; index++) {
//       final f = sourceFeatures[index];
//       if (f == null) {
//         debugPrint('[getWaterPolygonById] Feature at index $index is null');
//         continue;
//       }

//       final queriedFeature = f.queriedFeature;
//       if (queriedFeature == null) {
//         debugPrint(
//             '[getWaterPolygonById] queriedFeature at index $index is null');
//         continue;
//       }

//       final geojson = queriedFeature.feature as Map<String, dynamic>?;
//       if (geojson == null) {
//         debugPrint('[getWaterPolygonById] geojson at index $index is null');
//         continue;
//       }

//       final id = geojson['id']?.toString();
//       if (id == null) {
//         debugPrint('[getWaterPolygonById] feature id at index $index is null');
//         continue;
//       }

//       debugPrint('[getWaterPolygonById] Checking feature id="$id"');

//       if (id == featureId) {
//         debugPrint(
//             '[getWaterPolygonById] Found matching feature! id="$id" at index $index');
//         debugPrint(
//             '[getWaterPolygonById] Properties: ${geojson['properties']}');
//         debugPrint(
//             '[getWaterPolygonById] Geometry: ${geojson['geometry']}');
//         return geojson; // Full feature map
//       }
//     }

//     debugPrint(
//         '[getWaterPolygonById] Feature with id="$featureId" not found in source layer "$sourceLayer"');
//   } catch (e, stack) {
//     debugPrint('[getWaterPolygonById] Exception: $e');
//     debugPrint('[getWaterPolygonById] Stack trace: $stack');
//   }

//   return null; // Not found
// }
//   /// Clear search
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
