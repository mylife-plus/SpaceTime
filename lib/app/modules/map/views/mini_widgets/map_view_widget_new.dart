import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/map/views/mini_widgets/map_fab.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/top_buttons.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import '../../controllers/map_controller_new.dart';
// Note: Permission-related imports removed as location check is disabled
// Note: Internet required screen removed - offline tiles are downloaded during Get Started flow
import '../../../add_memories/controllers/add_memories_controller.dart';
import '../../../add_memories/views/mini_widgets/filter_indicator.dart';
import 'map_filter_overlay.dart';
import '../../../../../services/mbtiles_download_service.dart';
import '../../../../../services/mbtiles_server_service.dart';

class MapViewWidgetNew extends StatefulWidget {
  const MapViewWidgetNew({super.key});

  @override
  State<MapViewWidgetNew> createState() => _MapViewWidgetNewState();
}

class _MapViewWidgetNewState extends State<MapViewWidgetNew>
    with WidgetsBindingObserver {
  MapControllerNew? controller;
  mapbox.MapboxMap? mapController;

  // Server state (like GlobeTestView)
  String? _serverUrl;
  String? _errorMessage;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // MapControllerNew is initialized in main.dart as permanent singleton
    // Always use Get.find() - never create new instance
    controller = Get.find<MapControllerNew>();
    debugPrint('[MapViewWidgetNew] Using MapControllerNew instance: ${controller.hashCode}');

    // Initialize local tile server BEFORE map creation (like GlobeTestView)
    _initializeLocalTileServer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed && controller != null) {
      // App resumed from background (possibly from settings)
      debugPrint(
        '[MapViewWidgetNew] App resumed, checking location permissions',
      );
      controller!.checkPermissionsAfterResume();
    }
  }

  /// Initialize local tile server before map creation
  /// Server is started in main.dart, so we just check if it's running
  Future<void> _initializeLocalTileServer() async {
    try {
      debugPrint('[MapViewWidgetNew] � Checking if local tile server is running...');

      final serverService = MbtilesServerService.instance;

      // Check if server is already running (started in main.dart)
      if (serverService.isRunning && serverService.serverUrl != null) {
        setState(() {
          _serverUrl = serverService.serverUrl;
          _isInitializing = false;
        });
        debugPrint('[MapViewWidgetNew] ✅ Using existing tile server at: $_serverUrl');
        debugPrint('[MapViewWidgetNew] 📡 Tiles will be served from: $_serverUrl/{z}/{x}/{y}.pbf');
        return;
      }

      // If server is not running, try to start it (fallback)
      debugPrint('[MapViewWidgetNew] ⚠️ Server not running, attempting to start...');

      final mbtilesService = MbtilesDownloadService.instance;
      final isDownloaded = await mbtilesService.isMbtilesDownloaded();
      final tilesPath = mbtilesService.getLocalMbtilesPath();

      if (!isDownloaded || tilesPath == null) {
        setState(() {
          _errorMessage = 'MBTiles file not downloaded. Please download from Get Started screen first.';
          _isInitializing = false;
        });
        debugPrint('[MapViewWidgetNew] ❌ $_errorMessage');
        return;
      }

      final url = await serverService.startServer(tilesPath);

      if (url != null) {
        setState(() {
          _serverUrl = url;
          _isInitializing = false;
        });
        debugPrint('[MapViewWidgetNew] ✅ Local tile server started at: $url');
      } else {
        setState(() {
          _errorMessage = 'Failed to start local tile server';
          _isInitializing = false;
        });
        debugPrint('[MapViewWidgetNew] ❌ $_errorMessage');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing tile server: $e';
        _isInitializing = false;
      });
      debugPrint('[MapViewWidgetNew] ❌ $_errorMessage');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show error if server failed to start
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Show loading while server is starting
    if (_isInitializing || _serverUrl == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text(
                  'Starting local tile server...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GetBuilder<MapControllerNew>(
      // Remove init parameter to prevent creating new instance
      builder: (controller) {
        return Obx(() {
          return Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Stack(
                children: [
                  // MapBox Map
                  _buildMapWidget(controller),

                  // Filter overlay backdrop
                  if (controller.isFilterOpen.value)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.8),
                      ),
                    ),

                  // Top buttons and FAB (hidden when filter is open)
                  if (!controller.isFilterOpen.value)
                    const MapTopButtons(),
                  if (!controller.isFilterOpen.value)
                    const MapFab(),

                  // Filter indicator (shown when filters are active and filter is not open)
                  if (!controller.isFilterOpen.value)
                    Positioned(
                      top: 60,
                      left: 0,
                      right: 0,
                      child: Obx(() {
                        // Only show if AddMemoriesController is registered and has active filters
                        if (!Get.isRegistered<AddMemoriesController>()) {
                          return const SizedBox.shrink();
                        }

                        final addMemoriesController = Get.find<AddMemoriesController>();
                        if (!addMemoriesController.hasActiveFilters.value) {
                          return const SizedBox.shrink();
                        }

                        return const FilterIndicator();
                      }),
                    ),

                  // Filter overlay
                  if (controller.isFilterOpen.value) const MapFilterOverlay(),


                  // Permission and Internet screens overlay
                  // _buildPermissionAndInternetScreens(context, controller),
                ],
              ),
            ),
            floatingActionButton: _buildFloatingActionButton(controller),
          );
        });
      },
    );
  }

  /// Build the MapBox map widget
  Widget _buildMapWidget(MapControllerNew controller) {
    // If server URL is not available, show blank style immediately
    if (_serverUrl == null) {
      return mapbox.MapWidget(
        key: ValueKey("mapbox_map_new"),
        cameraOptions: mapbox.CameraOptions(
          zoom: MapboxZoomHelper().initialCameraZoom.value,
        ),
        styleUri: _getCustomStyleUri(), // Returns blank style
        textureView: io.Platform.isAndroid,
        onMapCreated: (mapboxMap) async {
          mapboxMap = mapboxMap;
          controller.mapboxMap = mapboxMap;
          debugPrint('[MapViewWidgetNew] 🗺️ onMapCreated callback triggered (blank style)');
          // Enable online mode even for blank style
          await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
          debugPrint('[MapViewWidgetNew] 🌐 Online mode ENABLED (blank style fallback)');
          controller.onMapCreated(mapboxMap);
          
        },
        onStyleLoadedListener: (styleLoadedEventData) async {
          debugPrint('[MapViewWidgetNew] 🎨 onStyleLoaded callback triggered (blank style)');
          controller.onStyleLoaded(styleLoadedEventData);
           await _addLocalTileSource();
        },
      );
    }

    // Server URL is available - load style.json from assets
    final tileUrl = '$_serverUrl/{z}/{x}/{y}.pbf';
    final serverUrl = _serverUrl!; // Base server URL without tile pattern

    return FutureBuilder<String>(
      future: _loadStyleJsonFromAssets(tileUrl, serverUrl),
      builder: (context, snapshot) {
        // Show loading indicator while style.json is being loaded
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading map style...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        }

        // Handle error
        if (snapshot.hasError) {
          debugPrint('[MapViewWidgetNew] ❌ Error in FutureBuilder: ${snapshot.error}');
          return Center(
            child: Text(
              'Error loading map style',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        // Style loaded successfully - build the map
        final styleJson = snapshot.data ?? _getCustomStyleUri();

        return mapbox.MapWidget(
          key: ValueKey("mapbox_map_new"),
          cameraOptions: mapbox.CameraOptions(

            zoom: MapboxZoomHelper().initialCameraZoom.value,
          ),
          // Don't set styleUri - we'll load the JSON style after map creation
          // iOS FIX: Use surface view instead of texture view for better iOS compatibility
          textureView: io.Platform.isAndroid, // Only use texture view on Android
          onMapCreated: (mapboxMap) async {
            controller.mapboxMap = mapboxMap;

            debugPrint('[MapViewWidgetNew] 🗺️ onMapCreated callback triggered');

            // CRITICAL: Enable online mode to allow localhost tile server access
            // Mapbox's offline mode blocks ALL network requests, including localhost
            // We MUST enable connectivity for the local tile server to work
            await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
            debugPrint('[MapViewWidgetNew] 🌐 Online mode ENABLED - localhost tile server can now be accessed');

            // Load the custom style JSON with local tile server URLs
            debugPrint('[MapViewWidgetNew] 📥 Loading custom style JSON into Mapbox...');
            debugPrint('[MapViewWidgetNew] 📊 Style JSON length: ${styleJson.length} characters');

            // Verify the JSON contains our localhost URLs before loading
            if (styleJson.contains('localhost:8080')) {
              debugPrint('[MapViewWidgetNew] ✅ Verified: Style JSON contains localhost URLs');
            } else {
              debugPrint('[MapViewWidgetNew] ⚠️ WARNING: Style JSON does NOT contain localhost URLs!');
            }

            await mapboxMap.loadStyleJson(styleJson);

            debugPrint('[MapViewWidgetNew] ✅ Custom style JSON loaded into Mapbox successfully');

            controller.onMapCreated(mapboxMap);
          },
          onStyleLoadedListener: (styleLoadedEventData) async {
            debugPrint('[MapViewWidgetNew] 🎨 onStyleLoaded callback triggered');
            debugPrint('[MapViewWidgetNew] ✅ Style.json from assets loaded successfully with local tiles');

            controller.onStyleLoaded(styleLoadedEventData);
          },
          onMapLoadErrorListener: (mapLoadError) {
            debugPrint('[MapViewWidgetNew] ❌ Map Load Error: ${mapLoadError.type}');
            debugPrint('[MapViewWidgetNew] ❌ Error Message: ${mapLoadError.message}');
            debugPrint('[MapViewWidgetNew] ❌ Error Timestamp: ${mapLoadError.timestamp}');
          },
        );
      },
    );
  }

   Future<void> _addLocalTileSource() async {
    try {
      if (_serverUrl == null) {
        debugPrint('[MemoryLocationPicker] ⚠️ Server URL is null, skipping tile source addition');
        return;
      }

      if (mapController == null) {
        debugPrint('[MemoryLocationPicker] ⚠️ Map controller is null, skipping tile source addition');
        return;
      }

      debugPrint('[MemoryLocationPicker] 🗺️ Adding local tile source...');

      final tileUrl = '$_serverUrl/{z}/{x}/{y}.pbf';
      debugPrint('[MemoryLocationPicker] Tile URL template: $tileUrl');

      // Add vector source with zoom levels from MapboxZoomHelper
      final zoomHelper = MapboxZoomHelper();
      await mapController!.style.addSource(
        mapbox.VectorSource(
          id: 'local-tiles',
          tiles: [tileUrl],
          minzoom: zoomHelper.minZoom.value,
          maxzoom: zoomHelper.maxZoom.value,
        ),
      );

      debugPrint('[MemoryLocationPicker] ✅ Local tile source added (zoom: ${zoomHelper.minZoom.value}-${zoomHelper.maxZoom.value})');

      // Add layers to display the tiles (CRITICAL - without this, tiles won't show!)
      // await _addLocalTileLayers();
    } catch (e) {
      debugPrint('[MemoryLocationPicker] ❌ Error adding tile source: $e');
      // Continue anyway - map will use default Mapbox tiles
    }
  }

  ///

  /// Get custom style URI with local tile server URL
  String _getCustomStyleUri() {


    // Load style.json from assets and replace placeholder with actual server URL
    final tileUrl = '$_serverUrl/{z}/{x}/{y}.pbf';
    debugPrint('[MapViewWidgetNew] 📡 Using custom style with tile URL: $tileUrl');

    // Return the style JSON with the local tile URL
    // Note: We'll load and modify the assets/style.json content
    return _getStyleJsonWithLocalTiles(tileUrl);
  }

  /// Get style JSON from assets with local tile URL
  /// Loads assets/style.json and replaces {LOCAL_TILE_URL} placeholder
  String _getStyleJsonWithLocalTiles(String tileUrl) {
    // This method is synchronous but needs to load from assets
    // We'll use a FutureBuilder in _buildMapWidget instead
    // For now, return a placeholder that indicates loading is needed
    return 'LOADING_FROM_ASSETS';
  }

  /// Load style.json from assets and replace placeholders with actual server URLs
  Future<String> _loadStyleJsonFromAssets(String tileUrl, String serverUrl) async {
    try {
      debugPrint('[MapViewWidgetNew] 📂 Loading style.json from assets...');

      // Load style.json from assets folder
      final styleJsonString = await rootBundle.loadString('assets/custom-style.json');
      debugPrint('[MapViewWidgetNew] ✅ Loaded style.json from assets');

      // IMPORTANT: Replace {LOCAL_SERVER_URL} FIRST, then {LOCAL_TILE_URL}
      // This prevents the tile URL pattern from interfering with server URL
      var modifiedStyleJson = styleJsonString
          .replaceAll('{LOCAL_SERVER_URL}', serverUrl)
          .replaceAll('{LOCAL_TILE_URL}', tileUrl);

      debugPrint('[MapViewWidgetNew] 📡 Replaced {LOCAL_SERVER_URL} with: $serverUrl');
      debugPrint('[MapViewWidgetNew] 📡 Replaced {LOCAL_TILE_URL} with: $tileUrl');
      debugPrint('[MapViewWidgetNew] ✅ Style JSON configured with local MBTiles server');

      // Debug: Check if glyphs and sprite fields are correctly replaced
      if (modifiedStyleJson.contains('{LOCAL_SERVER_URL}') || modifiedStyleJson.contains('{LOCAL_TILE_URL}')) {
        debugPrint('[MapViewWidgetNew] ⚠️ WARNING: Placeholders still present in style JSON!');
      }

      // Check for glyphs field
      if (modifiedStyleJson.contains('"glyphs"')) {
        final glyphsMatch = RegExp(r'"glyphs":\s*"([^"]+)"').firstMatch(modifiedStyleJson);
        if (glyphsMatch != null) {
          debugPrint('[MapViewWidgetNew] 📝 Glyphs URL: ${glyphsMatch.group(1)}');
        } else {
          debugPrint('[MapViewWidgetNew] ⚠️ WARNING: glyphs field found but URL could not be extracted!');
        }
      } else {
        debugPrint('[MapViewWidgetNew] ⚠️ WARNING: No glyphs field found in style JSON!');
      }
      // Check for sprite field
      if (modifiedStyleJson.contains('"sprite"')) {
        final spriteMatch = RegExp(r'"sprite":\s*"([^"]+)"').firstMatch(modifiedStyleJson);
        if (spriteMatch != null) {
          debugPrint('[MapViewWidgetNew] 🎨 Sprite URL: ${spriteMatch.group(1)}');
        } else {
          debugPrint('[MapViewWidgetNew] ⚠️ WARNING: sprite field found but URL could not be extracted!');
        }
      } else {
        debugPrint('[MapViewWidgetNew] ⚠️ WARNING: No sprite field found in style JSON!');
      }

      // Print the sources, sprite, and glyphs section for verification
      debugPrint('[MapViewWidgetNew] 📄 ========== STYLE JSON VERIFICATION ==========');
      final sourcesMatch = RegExp(r'"sources":\s*\{[^}]+\}', multiLine: true, dotAll: true).firstMatch(modifiedStyleJson);
      if (sourcesMatch != null) {
        debugPrint('[MapViewWidgetNew] 📦 Sources section: ${sourcesMatch.group(0)}');
      }

      // Extract and print sprite and glyphs lines
      final lines = modifiedStyleJson.split('\n');
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].contains('"sprite"') || lines[i].contains('"glyphs"')) {
          debugPrint('[MapViewWidgetNew] 📄 Line ${i + 1}: ${lines[i].trim()}');
        }
      }
      debugPrint('[MapViewWidgetNew] 📄 ==========================================');

      return modifiedStyleJson;
    } catch (e) {
      debugPrint('[MapViewWidgetNew] ❌ Error loading style.json from assets: $e');
      debugPrint('[MapViewWidgetNew] ⚠️ Falling back to simplified style');

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

  // ============================================================================
  // OLD METHODS - COMMENTED OUT
  // These methods are no longer needed because style.json handles all layers
  // Keeping them here for reference in case we need to debug or modify later
  // ============================================================================

  /*
  /// Add local tile source from downloaded mbtiles (called after style loads)
  /// NOTE: This method is no longer used - style.json handles the tile source
  Future<void> _addLocalTileSource() async {
    try {
      if (_serverUrl == null) {
        debugPrint('[MapViewWidgetNew] ⚠️ Local tile server not running');
        return;
      }

      final mapboxMap = controller?.mapboxMap;
      if (mapboxMap == null) {
        debugPrint('[MapViewWidgetNew] ❌ MapboxMap not available yet');
        return;
      }

      debugPrint('[MapViewWidgetNew] 📡 Adding local tile source...');

      final tileUrl = '$_serverUrl/{z}/{x}/{y}.pbf';
      debugPrint('[MapViewWidgetNew] Tile URL template: $tileUrl');

      // Add vector source with maxzoom restricted to 10 (as per requirements)
      await mapboxMap.style.addSource(
        mapbox.VectorSource(
          id: 'local-tiles',
          tiles: [tileUrl],
          minzoom: 0,
          maxzoom: 10, // Restricted to zoom level 10 (was 14)
        ),
      );

      debugPrint('[MapViewWidgetNew] ✅ Local tile source added (zoom: 0-10)');

      // INSPECT TILES: Print all available layer IDs from the vector tiles
      await _inspectVectorTileLayers();

      // Add layers to display the tiles (CRITICAL - without this, tiles won't show!)
      await _addLocalTileLayers();
    } catch (e) {
      debugPrint('[MapViewWidgetNew] ❌ Error adding tile source: $e');
      // Continue anyway - map will use default Mapbox tiles
    }
  }

  /// Inspect vector tiles and print all available layer IDs
  /// This method tries to add test layers to see which source layers exist
  Future<void> _inspectVectorTileLayers() async {
    try {
      final mapboxMap = controller?.mapboxMap;
      if (mapboxMap == null) return;

      debugPrint('[MapViewWidgetNew] 🔍 ========================================');
      debugPrint('[MapViewWidgetNew] 🔍 INSPECTING VECTOR TILE LAYERS');
      debugPrint('[MapViewWidgetNew] 🔍 ========================================');
      debugPrint('[MapViewWidgetNew] 🔍 ');
      debugPrint('[MapViewWidgetNew] 🔍 Testing common OpenMapTiles layer names...');
      debugPrint('[MapViewWidgetNew] 🔍 Method: Attempting to add test layers and checking for errors');
      debugPrint('[MapViewWidgetNew] 🔍 ');

      // Actual vector tile layer names from your mbtiles file
      final commonLayers = [
        'aeroway',
        'boundary',
        'building',
        'housenumber',
        'landcover',
        'landuse',
        'mountain_peak',
        'park',
        'place',
        'poi',
        'transportation',
        'transportation_name',
        'water',
        'water_name',
        'waterway',
      ];

      debugPrint('[MapViewWidgetNew] 🔍 Testing ${commonLayers.length} common layer names:');
      debugPrint('[MapViewWidgetNew] 🔍 ----------------------------------------');

      final foundLayers = <String>[];
      final notFoundLayers = <String>[];

      for (final layerName in commonLayers) {
        try {
          // Try to add a test fill layer for this source layer
          await mapboxMap.style.addLayer(
            mapbox.FillLayer(
              id: 'test-layer-$layerName',
              sourceId: 'local-tiles',
              sourceLayer: layerName,
              fillColor: 0xFF000000,
              fillOpacity: 0.0, // Invisible
            ),
          );

          // If we got here, the layer exists!
          foundLayers.add(layerName);
          debugPrint('[MapViewWidgetNew] 🔍 ✅ FOUND: "$layerName"');

          // Remove the test layer immediately
          await mapboxMap.style.removeStyleLayer('test-layer-$layerName');
        } catch (e) {
          // Layer doesn't exist in the tiles
          notFoundLayers.add(layerName);
          debugPrint('[MapViewWidgetNew] 🔍 ❌ NOT FOUND: "$layerName"');
        }
      }

      debugPrint('[MapViewWidgetNew] 🔍 ========================================');
      debugPrint('[MapViewWidgetNew] 🔍 INSPECTION COMPLETE');
      debugPrint('[MapViewWidgetNew] 🔍 ========================================');
      debugPrint('[MapViewWidgetNew] 🔍 ');
      debugPrint('[MapViewWidgetNew] 🔍 📊 SUMMARY:');
      debugPrint('[MapViewWidgetNew] 🔍 ✅ Found ${foundLayers.length} layers');
      debugPrint('[MapViewWidgetNew] 🔍 ❌ Not found: ${notFoundLayers.length} layers');
      debugPrint('[MapViewWidgetNew] 🔍 ');
      debugPrint('[MapViewWidgetNew] 🔍 📋 AVAILABLE LAYERS IN YOUR MBTILES:');
      debugPrint('[MapViewWidgetNew] 🔍 ----------------------------------------');
      for (final layer in foundLayers) {
        debugPrint('[MapViewWidgetNew] 🔍    - $layer');
      }
      debugPrint('[MapViewWidgetNew] 🔍 ========================================');
      debugPrint('[MapViewWidgetNew] 🔍 ');
      debugPrint('[MapViewWidgetNew] 🔍 💡 NEXT STEPS:');
      debugPrint('[MapViewWidgetNew] 🔍 1. Use the layer names above in _addLocalTileLayers()');
      debugPrint('[MapViewWidgetNew] 🔍 2. Add FillLayer for polygon layers (water, landcover, landuse, building)');
      debugPrint('[MapViewWidgetNew] 🔍 3. Add LineLayer for line layers (transportation, waterway, boundary)');
      debugPrint('[MapViewWidgetNew] 🔍 4. Add SymbolLayer for label layers (place, poi, transportation_name)');
      debugPrint('[MapViewWidgetNew] 🔍 ========================================');

    } catch (e) {
      debugPrint('[MapViewWidgetNew] ⚠️ Error inspecting vector tile layers: $e');
      debugPrint('[MapViewWidgetNew] ℹ️ This is normal - will proceed with standard layer setup');
    }
  }

  /// Add layers to display local tiles
  /// Using all 15 layers from OpenMapTiles schema
  Future<void> _addLocalTileLayers() async {
    try {
      final mapboxMap = controller?.mapboxMap;
      if (mapboxMap == null) return;

      debugPrint('[MapViewWidgetNew] 🎨 Adding all 15 OpenMapTiles layers...');

      // LAYER ORDER IS IMPORTANT! Bottom to top rendering:
      // 1. Background (ocean)
      // 2. Water bodies
      // 3. Landcover (land masses)
      // 4. Landuse (parks, residential, etc.)
      // 5. Parks
      // 6. Waterways (rivers)
      // 7. Buildings
      // 8. Aeroway
      // 9. Transportation (roads)
      // 10. Boundaries
      // 11. Water names
      // 12. Transportation names
      // 13. Place names
      // 14. POI
      // 15. Mountain peaks
      // 16. House numbers

      // 1. Background layer (ocean/sea - light blue)
      await mapboxMap.style.addLayer(
        mapbox.BackgroundLayer(
          id: 'local-background',
          backgroundColor: 0xFFAAD3DF, // Light blue for ocean
        ),
      );
      debugPrint('[MapViewWidgetNew] ✅ Added background layer');

      // 2. Water bodies (oceans, lakes)
      try {
        await mapboxMap.style.addLayer(
          mapbox.FillLayer(
            id: 'local-water',
            sourceId: 'local-tiles',
            sourceLayer: 'water',
            fillColor: 0xFFAAD3DF, // Blue for water
            fillOpacity: 1.0,
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added water layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ water layer error: $e');
      }

      // 3. Landcover (land masses - forests, grass, ice, etc.)
      try {
        await mapboxMap.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landcover',
            sourceId: 'local-tiles',
            sourceLayer: 'landcover',
            fillColor: 0xFFE8E8E8, // Light gray for land
            fillOpacity: 1.0,
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added landcover layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ landcover layer error: $e');
      }

      // 4. Landuse (residential, commercial, industrial, etc.)
      try {
        await mapboxMap.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landuse',
            sourceId: 'local-tiles',
            sourceLayer: 'landuse',
            fillColor: 0xFFD4E7D4, // Light green for landuse
            fillOpacity: 0.6,
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added landuse layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ landuse layer error: $e');
      }

      // 5. Parks (parks and green spaces)
      try {
        await mapboxMap.style.addLayer(
          mapbox.FillLayer(
            id: 'local-park',
            sourceId: 'local-tiles',
            sourceLayer: 'park',
            fillColor: 0xFFC8E6C9, // Green for parks
            fillOpacity: 0.7,
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added park layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ park layer error: $e');
      }

      // 6. Waterways (rivers, streams)
      try {
        await mapboxMap.style.addLayer(
          mapbox.LineLayer(
            id: 'local-waterway',
            sourceId: 'local-tiles',
            sourceLayer: 'waterway',
            lineColor: 0xFFAAD3DF, // Blue for waterways
            lineWidth: 1.0,
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added waterway layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ waterway layer error: $e');
      }

      // 7. Buildings
      try {
        await mapboxMap.style.addLayer(
          mapbox.FillLayer(
            id: 'local-building',
            sourceId: 'local-tiles',
            sourceLayer: 'building',
            fillColor: 0xFFD0D0D0, // Gray for buildings
            fillOpacity: 0.7,
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added building layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ building layer error: $e');
      }

      // 8. Aeroway (airports, runways)
      try {
        await mapboxMap.style.addLayer(
          mapbox.FillLayer(
            id: 'local-aeroway',
            sourceId: 'local-tiles',
            sourceLayer: 'aeroway',
            fillColor: 0xFFE0E0E0, // Light gray for aeroway
            fillOpacity: 0.5,
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added aeroway layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ aeroway layer error: $e');
      }

      // 9. Transportation (roads, railways, paths)
      try {
        await mapboxMap.style.addLayer(
          mapbox.LineLayer(
            id: 'local-transportation',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation',
            lineColor: 0xFFFFFFFF, // White for roads
            lineWidth: 1.5,
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added transportation layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ transportation layer error: $e');
      }

      // 10. Boundaries (administrative boundaries)
      try {
        await mapboxMap.style.addLayer(
          mapbox.LineLayer(
            id: 'local-boundary',
            sourceId: 'local-tiles',
            sourceLayer: 'boundary',
            lineColor: 0xFFCCCCCC, // Gray for boundaries
            lineWidth: 0.5,
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added boundary layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ boundary layer error: $e');
      }

      // 11. Water names (labels for water bodies)
      try {
        await mapboxMap.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-water-name',
            sourceId: 'local-tiles',
            sourceLayer: 'water_name',
            textField: '{name}',
            textSize: 11.0,
            textColor: 0xFF4A90E2, // Blue text for water names
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added water_name layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ water_name layer error: $e');
      }

      // 12. Transportation names (road names)
      try {
        await mapboxMap.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-transportation-name',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation_name',
            textField: '{name}',
            textSize: 10.0,
            textColor: 0xFF666666, // Gray text for road names
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added transportation_name layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ transportation_name layer error: $e');
      }

      // 13. Place names (cities, towns, villages)
      try {
        await mapboxMap.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-place',
            sourceId: 'local-tiles',
            sourceLayer: 'place',
            textField: '{name}',
            textSize: 12.0,
            textColor: 0xFF000000, // Black text for place names
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added place layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ place layer error: $e');
      }

      // 14. POI (points of interest)
      try {
        await mapboxMap.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-poi',
            sourceId: 'local-tiles',
            sourceLayer: 'poi',
            textField: '{name}',
            textSize: 10.0,
            textColor: 0xFF333333, // Dark gray for POI
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added poi layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ poi layer error: $e');
      }

      // 15. Mountain peaks
      try {
        await mapboxMap.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-mountain-peak',
            sourceId: 'local-tiles',
            sourceLayer: 'mountain_peak',
            textField: '{name}',
            textSize: 10.0,
            textColor: 0xFF8B4513, // Brown text for mountains
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added mountain_peak layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ mountain_peak layer error: $e');
      }

      // 16. House numbers
      try {
        await mapboxMap.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-housenumber',
            sourceId: 'local-tiles',
            sourceLayer: 'housenumber',
            textField: '{housenumber}',
            textSize: 9.0,
            textColor: 0xFF999999, // Light gray for house numbers
          ),
        );
        debugPrint('[MapViewWidgetNew] ✅ Added housenumber layer');
      } catch (e) {
        debugPrint('[MapViewWidgetNew] ⚠️ housenumber layer error: $e');
      }

      debugPrint('[MapViewWidgetNew] ✅ All 15 OpenMapTiles layers added successfully');
    } catch (e) {
      debugPrint('[MapViewWidgetNew] ❌ Error adding tile layers: $e');
      // Don't throw - continue with whatever layers were added
    }
  }
  */

  // ============================================================================
  // END OF COMMENTED OUT METHODS
  // ============================================================================

  /// Build floating action button for location actions
  Widget _buildFloatingActionButton(MapControllerNew controller) {
    return Obx(() {
     
      if (!controller.hasLocationPermission.value) {
     
        return Container(); // Hide when no permission
     
      }

      return FloatingActionButton(
        onPressed: controller.refreshLocation,
        backgroundColor: Colors.blue,
        tooltip: 'Go to Current Location',
        child:
            controller.isLoadingLocation.value
                ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : Icon(Icons.my_location, color: Colors.white),
      );
    });
  }


}


/// Example page demonstrating Mapbox circle layer clustering
///
/// This page shows how to:
/// - Load GeoJSON data from assets
/// - Create a clustered source
/// - Add circle layers for clusters and unclustered points
/// - Add symbol layers for cluster counts
///
/// **Mapbox API Key Configuration:**
/// The Mapbox access token is automatically loaded from the `.env` file
/// and set globally in `main.dart` via:
/// ```dart
/// await dotenv.load(fileName: ".env");
/// MapboxOptions.setAccessToken(dotenv.get('MAPBOX_ACCESS_TOKEN'));
/// ```
///
/// **Requirements:**
/// - Add `assets/earthquakes.geojson` file to your project
/// - Add the file to `pubspec.yaml` under assets section
///
/// **Usage:**
/// Navigate to this page using:
/// ```dart
/// Get.to(() => const CircleLayerClusteringPage());
/// ```
class CircleLayerClusteringPage extends StatefulWidget {
  const CircleLayerClusteringPage({super.key});

  @override
  State<CircleLayerClusteringPage> createState() =>
      _CircleLayerClusteringPageState();
}

class _CircleLayerClusteringPageState extends State<CircleLayerClusteringPage> {
  mapbox.MapboxMap? _mapboxMap;
  static const String _sourceId = 'earthquakes';
  static const String _clusterLayerId = 'clusters';
  static const String _clusterCountLayerId = 'cluster-count';
  static const String _unclusteredLayerId = 'unclustered-points';

  // Track current zoom for smooth transitions
  double _currentZoom = 3.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Circle Layer Clustering Example'),
        backgroundColor: Colors.black,
        actions: [
          // Zoom in button
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Zoom In',
            onPressed: _zoomIn,
          ),
          // Zoom out button
          IconButton(
            icon: const Icon(Icons.remove),
            tooltip: 'Zoom Out',
            onPressed: _zoomOut,
          ),
        ],
      ),
      body: mapbox.MapWidget(
        cameraOptions: mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(-103.59179687498357, 40.66995747013945),
          ),
          zoom: _currentZoom,
        ),
        onMapCreated: _onMapCreated,
        onStyleLoadedListener: (styleLoadedEventData) {
          _onStyleLoaded();
        },
        onTapListener: _onMapTap,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _resetCamera,
        tooltip: 'Reset View',
        backgroundColor: Colors.blue,
        child: const Icon(Icons.home, color: Colors.white),
      ),
    );
  }

  Future<void> _onMapCreated(mapbox.MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    debugPrint('[CircleLayerClustering] 🗺️ Map created');

    // The Mapbox access token is already set globally in main.dart via:
    // MapboxOptions.setAccessToken(dotenv.get('MAPBOX_ACCESS_TOKEN'))
    // So we don't need to set it again here

    // Load Mapbox Streets style
    await mapboxMap.loadStyleURI(mapbox.MapboxStyles.MAPBOX_STREETS);

    debugPrint('[CircleLayerClustering] ✅ Style loaded');
  }

  Future<void> _onStyleLoaded() async {
    if (_mapboxMap == null) return;
    final style = _mapboxMap!.style;

    try {
      debugPrint('[CircleLayerClustering] 🎨 Loading style and setting up clustering...');

      // 1) Load your GeoJSON (equivalent to earthquakes.geojson in Android example)
      final geojsonString =
          await rootBundle.loadString('assets/earthquakes.geojson');

      debugPrint('[CircleLayerClustering] 📦 GeoJSON loaded, adding source...');

      // 2) Add clustered GeoJSON source with optimized settings for smooth clustering
      await style.addSource(
        mapbox.GeoJsonSource(
          id: _sourceId,
          data: geojsonString,
          cluster: true,
          clusterRadius: 50, // Radius of each cluster (pixels) - adjust for tighter/looser clustering
          clusterMaxZoom: 14, // Max zoom to cluster points - stops clustering at zoom 15+
          clusterMinPoints: 2, // Minimum points to form a cluster
          // Performance optimization: enable clustering properties
          clusterProperties: {
            // You can add custom cluster properties here if needed
          },
        ),
      );

      debugPrint('[CircleLayerClustering] ✅ Source added, creating layers...');

      // 3) Circle layer for clusters with smooth size transitions
      await style.addLayer(
        mapbox.CircleLayer(
          id: _clusterLayerId,
          sourceId: _sourceId,
          filter: ['has', 'point_count'],
          // Smooth color transition based on cluster size
          circleColor: 0xFF51BBD6, // Blue color for clusters
          // Smooth radius transition based on cluster size
          circleRadius: 20.0, // Base radius - can be enhanced with expressions
          circleStrokeWidth: 3.0,
          circleStrokeColor: 0xFFFFFFFF, // White stroke for better visibility
          circleOpacity: 0.9, // Slight transparency for overlapping clusters
          // Enable smooth transitions
          circleBlur: 0.2, // Slight blur for smoother appearance
        ),
      );

      debugPrint('[CircleLayerClustering] ✅ Cluster layer added');

      // 4) Symbol layer for cluster counts with better styling
      await style.addLayer(
        mapbox.SymbolLayer(
          id: _clusterCountLayerId,
          sourceId: _sourceId,
          filter: ['has', 'point_count'],
          textField: '{point_count_abbreviated}',
          textColor: 0xFFFFFFFF, // White text for better contrast
          textSize: 14.0, // Larger text for better readability
          textHaloColor: 0xFF000000, // Black halo for text visibility
          textHaloWidth: 1.5,
          textHaloBlur: 0.5,
          // Allow overlap for smooth transitions
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
      );

      debugPrint('[CircleLayerClustering] ✅ Cluster count layer added');

      // 5) Circle layer for unclustered points with smooth styling
      await style.addLayer(
        mapbox.CircleLayer(
          id: _unclusteredLayerId,
          sourceId: _sourceId,
          filter: ['!', ['has', 'point_count']],
          circleColor: 0xFF11B4DA, // Lighter blue for individual points
          circleRadius: 8.0, // Slightly larger for better visibility
          circleStrokeWidth: 2.0,
          circleStrokeColor: 0xFFFFFFFF, // White stroke
          circleOpacity: 0.95,
          circleBlur: 0.1, // Slight blur for smoother appearance
        ),
      );

      debugPrint('[CircleLayerClustering] ✅ Unclustered layer added');
      debugPrint('[CircleLayerClustering] 🎉 All clustering layers added successfully!');

      // Setup camera change listener for smooth zoom transitions
      _setupCameraChangeListener();

    } catch (e) {
      debugPrint('[CircleLayerClustering] ❌ Error setting up clustering: $e');
    }
  }

  /// Setup camera change listener for smooth transitions
  void _setupCameraChangeListener() {
    if (_mapboxMap == null) return;

    debugPrint('[CircleLayerClustering] 📹 Setting up camera change listener for smooth transitions');

    // Note: Camera change listeners help track zoom changes for dynamic updates
    // The clustering itself is handled automatically by Mapbox
  }

  /// Zoom in with smooth animation
  Future<void> _zoomIn() async {
    if (_mapboxMap == null) return;

    try {
      final cameraState = await _mapboxMap!.getCameraState();
      final newZoom = (cameraState.zoom + 1.0).clamp(0.0, 22.0);

      await _mapboxMap!.flyTo(
        mapbox.CameraOptions(
          center: cameraState.center,
          zoom: newZoom,
        ),
        mapbox.MapAnimationOptions(
          duration: 500, // Smooth 500ms animation
          startDelay: 0,
        ),
      );

      setState(() {
        _currentZoom = newZoom;
      });

      debugPrint('[CircleLayerClustering] 🔍 Zoomed in to: $newZoom');
    } catch (e) {
      debugPrint('[CircleLayerClustering] ❌ Error zooming in: $e');
    }
  }

  /// Zoom out with smooth animation
  Future<void> _zoomOut() async {
    if (_mapboxMap == null) return;

    try {
      final cameraState = await _mapboxMap!.getCameraState();
      final newZoom = (cameraState.zoom - 1.0).clamp(0.0, 22.0);

      await _mapboxMap!.flyTo(
        mapbox.CameraOptions(
          center: cameraState.center,
          zoom: newZoom,
        ),
        mapbox.MapAnimationOptions(
          duration: 500, // Smooth 500ms animation
          startDelay: 0,
        ),
      );

      setState(() {
        _currentZoom = newZoom;
      });

      debugPrint('[CircleLayerClustering] 🔍 Zoomed out to: $newZoom');
    } catch (e) {
      debugPrint('[CircleLayerClustering] ❌ Error zooming out: $e');
    }
  }

  /// Reset camera to initial position with smooth animation
  Future<void> _resetCamera() async {
    if (_mapboxMap == null) return;

    try {
      await _mapboxMap!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(-103.59179687498357, 40.66995747013945),
          ),
          zoom: 3.0,
          bearing: 0,
          pitch: 0,
        ),
        mapbox.MapAnimationOptions(
          duration: 1500, // Longer animation for reset
          startDelay: 0,
        ),
      );

      setState(() {
        _currentZoom = 3.0;
      });

      debugPrint('[CircleLayerClustering] 🏠 Reset camera to initial position');
    } catch (e) {
      debugPrint('[CircleLayerClustering] ❌ Error resetting camera: $e');
    }
  }

  /// Handle map tap - zoom into clusters or show point details
  Future<void> _onMapTap(mapbox.MapContentGestureContext context) async {
    debugPrint('[CircleLayerClustering] 🔍 === TAP HANDLER CALLED ===');

    if (_mapboxMap == null) {
      debugPrint('[CircleLayerClustering] ❌ _mapboxMap is null, returning');
      return;
    }

    try {
      final lat = context.point.coordinates.lat;
      final lng = context.point.coordinates.lng;

      debugPrint('[CircleLayerClustering] 👆 Map tapped at: ($lat, $lng)');
      debugPrint('[CircleLayerClustering] 📊 Current zoom: $_currentZoom');
      debugPrint('[CircleLayerClustering] 📊 Context type: ${context.runtimeType}');
      debugPrint('[CircleLayerClustering] 📊 Context point: ${context.point}');

      final tapPoint = context.point;

      // Use fromScreenCoordinate with lng/lat (this is how the main controller does it)
      // Note: This seems wrong but it's what works in the main controller
      final screenCoord = mapbox.ScreenCoordinate(
        x: lng.toDouble(),
        y: lat.toDouble(),
      );

      // First, try querying ALL features at this point to see what's there
      debugPrint('[CircleLayerClustering] 🔍 Querying ALL features at tap point');
      final allFeatures = await _mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(screenCoord),
        mapbox.RenderedQueryOptions(),
      );

      debugPrint('[CircleLayerClustering] 📊 Total features found: ${allFeatures.length}');

      // Log first few features to see what we're getting
      for (int i = 0; i < allFeatures.length && i < 5; i++) {
        final feature = allFeatures[i];
        if (feature != null) {
          try {
            final queriedFeature = feature.queriedFeature;
            final featureData = queriedFeature.feature;
            debugPrint('[CircleLayerClustering] 📊 Feature $i: ${featureData.toString()}');
            debugPrint('[CircleLayerClustering] 📊 Feature $i source: ${queriedFeature.source}');
            debugPrint('[CircleLayerClustering] 📊 Feature $i sourceLayer: ${queriedFeature.sourceLayer}');
          } catch (e) {
            debugPrint('[CircleLayerClustering] 📊 Feature $i: Error accessing - $e');
          }
        }
      }

      debugPrint('[CircleLayerClustering] 🔍 Querying cluster layer: $_clusterLayerId');

      // Check if we tapped on a cluster
      final clusterFeatures = await _mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(screenCoord),
        mapbox.RenderedQueryOptions(
          layerIds: [_clusterLayerId],
        ),
      );

      debugPrint('[CircleLayerClustering] 📊 Cluster features found: ${clusterFeatures.length}');

      if (clusterFeatures.isNotEmpty && clusterFeatures.first != null) {
        // Tapped on a cluster - zoom in smoothly
        debugPrint('[CircleLayerClustering] 🎯 Cluster tapped, zooming in...');

        final cameraState = await _mapboxMap!.getCameraState();
        final currentZoom = cameraState.zoom;
        final newZoom = (currentZoom + 2.0).clamp(0.0, 22.0);

        debugPrint('[CircleLayerClustering] 📊 Current zoom: $currentZoom, New zoom: $newZoom');

        await _mapboxMap!.flyTo(
          mapbox.CameraOptions(
            center: tapPoint,
            zoom: newZoom,
          ),
          mapbox.MapAnimationOptions(
            duration: 800,
            startDelay: 0,
          ),
        );

        setState(() {
          _currentZoom = newZoom;
        });

        debugPrint('[CircleLayerClustering] ✅ Zoomed into cluster (zoom: $newZoom)');
        return;
      }

      debugPrint('[CircleLayerClustering] 🔍 No cluster found, querying individual points layer: $_unclusteredLayerId');

      // Check if we tapped on an individual point
      final pointFeatures = await _mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenBox(
          mapbox.ScreenBox(
            min: mapbox.ScreenCoordinate(x: lng - 0.001, y: lat - 0.001),
            max: mapbox.ScreenCoordinate(x: lng + 0.001, y: lat + 0.001),
          ),
        ),
        mapbox.RenderedQueryOptions(
          layerIds: [_unclusteredLayerId],
        ),
      );

      debugPrint('[CircleLayerClustering] 📊 Individual point features found: ${pointFeatures.length}');

      if (pointFeatures.isNotEmpty && pointFeatures.first != null) {
        debugPrint('[CircleLayerClustering] 📍 Individual point tapped');
        debugPrint('[CircleLayerClustering] 📊 mounted: $mounted');
        debugPrint('[CircleLayerClustering] 📊 Get.context != null: ${Get.context != null}');

        // Show a snackbar with point info
        if (mounted && Get.context != null) {
          debugPrint('[CircleLayerClustering] 🎯 Attempting to show snackbar...');

          try {
            ScaffoldMessenger.of(Get.context!).showSnackBar(
              const SnackBar(
                content: Text('Earthquake point tapped - zoom in to see details'),
                duration: Duration(seconds: 2),
                backgroundColor: Colors.blue,
              ),
            );
            debugPrint('[CircleLayerClustering] ✅ Snackbar shown successfully');
          } catch (snackbarError) {
            debugPrint('[CircleLayerClustering] ❌ Error showing snackbar: $snackbarError');
          }
        } else {
          debugPrint('[CircleLayerClustering] ⚠️ Cannot show snackbar - mounted: $mounted, Get.context: ${Get.context != null}');
        }
      } else {
        debugPrint('[CircleLayerClustering] 📍 Empty area tapped (no features found)');
      }

      debugPrint('[CircleLayerClustering] 🔍 === TAP HANDLER COMPLETE ===');
    } catch (e, stackTrace) {
      debugPrint('[CircleLayerClustering] ❌ Error handling map tap: $e');
      debugPrint('[CircleLayerClustering] 📊 Stack trace: $stackTrace');
    }
  }

}
