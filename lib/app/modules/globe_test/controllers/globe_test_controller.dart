import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../../../../services/mbtiles_server_service.dart';
import '../../../../services/mbtiles_download_service.dart';

class GlobeTestController extends GetxController {
  // Map instance
  mapbox.MapboxMap? mapboxMap;
  
  // Reactive state
  final isMapReady = false.obs;
  final serverUrl = Rx<String?>(null);
  final errorMessage = Rx<String?>(null);
  
  @override
  void onInit() {
    super.onInit();
    debugPrint('[GlobeTestController] Initializing...');
    _initializeLocalTileServer();
  }
  
  /// Initialize local tile server before map creation
  Future<void> _initializeLocalTileServer() async {
    try {
      debugPrint('[GlobeTestController] 🚀 Starting local tile server...');
      
      // Check if mbtiles file is downloaded
      final mbtilesService = MbtilesDownloadService.instance;
      final isDownloaded = await mbtilesService.isMbtilesDownloaded();
      final tilesPath = mbtilesService.getLocalMbtilesPath();
      
      debugPrint('[GlobeTestController] 🔍 MBTiles check: isDownloaded=$isDownloaded, tilesPath=$tilesPath');
      
      if (!isDownloaded || tilesPath == null) {
        errorMessage.value = 'MBTiles file not downloaded. Please download from Get Started screen first.';
        debugPrint('[GlobeTestController] ❌ ${errorMessage.value}');
        return;
      }
      
      // Start local tile server
      final serverService = MbtilesServerService.instance;
      final url = await serverService.startServer(tilesPath);
      
      if (url != null) {
        serverUrl.value = url;
        debugPrint('[GlobeTestController] ✅ Local tile server started at: $url');
        debugPrint('[GlobeTestController] 📡 Tiles will be served from: $url/{z}/{x}/{y}.pbf');
      } else {
        errorMessage.value = 'Failed to start local tile server';
        debugPrint('[GlobeTestController] ❌ ${errorMessage.value}');
      }
    } catch (e) {
      errorMessage.value = 'Error initializing tile server: $e';
      debugPrint('[GlobeTestController] ❌ ${errorMessage.value}');
    }
  }
  
  /// Called when map is created
  Future<void> onMapCreated(mapbox.MapboxMap map) async {
    try {
      debugPrint('[GlobeTestController] 🗺️ Map created');
      mapboxMap = map;

      // Enable online mode to allow localhost tile server access
      await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
      debugPrint('[GlobeTestController] 🌐 Online mode enabled - localhost tile server can be accessed');

      // Load custom style JSON with local tile server URLs
      await _loadCustomStyleJson();

      isMapReady.value = true;
    } catch (e) {
      debugPrint('[GlobeTestController] ❌ Error in onMapCreated: $e');
      errorMessage.value = 'Error creating map: $e';
    }
  }

  /// Load style.json from assets and replace placeholders with actual server URLs
  Future<void> _loadCustomStyleJson() async {
    try {
      debugPrint('[GlobeTestController] 📂 Loading style.json from assets...');

      // Load style.json from assets folder
      final styleJsonString = await rootBundle.loadString('assets/style.json');
      debugPrint('[GlobeTestController] ✅ Loaded style.json from assets');

      // Prepare URLs
      final tileUrl = '${serverUrl.value}/{z}/{x}/{y}.pbf';
      final baseServerUrl = serverUrl.value!;

      // Replace placeholders with actual URLs
      var modifiedStyleJson = styleJsonString
          .replaceAll('{LOCAL_SERVER_URL}', baseServerUrl)
          .replaceAll('{LOCAL_TILE_URL}', tileUrl);

      debugPrint('[GlobeTestController] 📡 Replaced {LOCAL_SERVER_URL} with: $baseServerUrl');
      debugPrint('[GlobeTestController] 📡 Replaced {LOCAL_TILE_URL} with: $tileUrl');

      // Debug: Check if glyphs and sprite fields are correctly replaced
      if (modifiedStyleJson.contains('{LOCAL_SERVER_URL}') || modifiedStyleJson.contains('{LOCAL_TILE_URL}')) {
        debugPrint('[GlobeTestController] ⚠️ WARNING: Placeholders still present in style JSON!');
      }
      if (modifiedStyleJson.contains('"glyphs"')) {
        final glyphsMatch = RegExp(r'"glyphs":\s*"([^"]+)"').firstMatch(modifiedStyleJson);
        if (glyphsMatch != null) {
          debugPrint('[GlobeTestController] 📝 Glyphs URL: ${glyphsMatch.group(1)}');
        }
      }
      if (modifiedStyleJson.contains('"sprite"')) {
        final spriteMatch = RegExp(r'"sprite":\s*"([^"]+)"').firstMatch(modifiedStyleJson);
        if (spriteMatch != null) {
          debugPrint('[GlobeTestController] 🎨 Sprite URL: ${spriteMatch.group(1)}');
        }
      }

      // Verify and load the custom style JSON
      debugPrint('[GlobeTestController] 📥 Loading custom style JSON into Mapbox...');
      debugPrint('[GlobeTestController] 📊 Style JSON length: ${modifiedStyleJson.length} characters');

      // Verify the JSON contains our localhost URLs before loading
      if (modifiedStyleJson.contains('localhost:8080')) {
        debugPrint('[GlobeTestController] ✅ Verified: Style JSON contains localhost URLs');
      } else {
        debugPrint('[GlobeTestController] ⚠️ WARNING: Style JSON does NOT contain localhost URLs!');
      }

      await mapboxMap!.loadStyleJson(modifiedStyleJson);
      debugPrint('[GlobeTestController] ✅ Custom style JSON loaded into Mapbox successfully');

    } catch (e) {
      debugPrint('[GlobeTestController] ❌ Error loading style.json: $e');
      errorMessage.value = 'Error loading map style: $e';
      rethrow;
    }
  }
  
  /// Called when style is loaded
  Future<void> onStyleLoaded(mapbox.StyleLoadedEventData data) async {
    try {
      debugPrint('[GlobeTestController] 🎨 Style loaded from assets/style.json');
      debugPrint('[GlobeTestController] ✅ Local tile map setup complete');
      debugPrint('[GlobeTestController] 📡 Map is now serving tiles from: ${serverUrl.value}');
    } catch (e) {
      debugPrint('[GlobeTestController] ❌ Error in onStyleLoaded: $e');
      errorMessage.value = 'Error loading style: $e';
    }
  }
  
  @override
  void onClose() {
    debugPrint('[GlobeTestController] Closing...');
    super.onClose();
  }
}

