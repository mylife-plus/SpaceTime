import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/location_picker/controllers/location_picker_controller.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/config/app_colors.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import 'package:spacetime/services/mbtiles_download_service.dart';
import 'package:spacetime/services/mbtiles_server_service.dart';

class NewLocationPickerWidget extends StatefulWidget {
  const NewLocationPickerWidget({super.key});

  @override
  State<NewLocationPickerWidget> createState() => _NewLocationPickerWidgetState();
}

class _NewLocationPickerWidgetState extends State<NewLocationPickerWidget> {
  final LocationPickerController controller = Get.put(LocationPickerController());
  final UiController uiController = Get.find<UiController>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final RxBool _showSearchResults = false.obs;

  // Server state for local tiles
  String? _serverUrl;
  String? _serverErrorMessage;
  bool _isInitializingServer = true;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _searchController.addListener(_onSearchChanged);
    _initializeLocalTileServer();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    Get.delete<LocationPickerController>();
    super.dispose();
  }

  /// Initialize local tile server before map creation
  /// Server is started in main.dart, so we just check if it's running
  Future<void> _initializeLocalTileServer() async {
    try {
      debugPrint('[NewLocationPicker] 🔍 Checking if local tile server is running...');

      final serverService = MbtilesServerService.instance;

      // Check if server is already running (started in main.dart)
      if (serverService.isRunning && serverService.serverUrl != null) {
        setState(() {
          _serverUrl = serverService.serverUrl;
          _isInitializingServer = false;
        });
        debugPrint('[NewLocationPicker] ✅ Using existing tile server at: $_serverUrl');
        debugPrint('[NewLocationPicker] 📡 Tiles will be served from: $_serverUrl/{z}/{x}/{y}.pbf');
        return;
      }

      // If server is not running, try to start it (fallback)
      debugPrint('[NewLocationPicker] ⚠️ Server not running, attempting to start...');

      final mbtilesService = MbtilesDownloadService.instance;
      final isDownloaded = await mbtilesService.isMbtilesDownloaded();
      final tilesPath = mbtilesService.getLocalMbtilesPath();

      if (!isDownloaded || tilesPath == null) {
        setState(() {
          _serverErrorMessage = 'MBTiles file not downloaded. Please download from Get Started screen first.';
          _isInitializingServer = false;
        });
        debugPrint('[NewLocationPicker] ❌ $_serverErrorMessage');
        return;
      }

      final url = await serverService.startServer(tilesPath);

      if (url != null) {
        setState(() {
          _serverUrl = url;
          _isInitializingServer = false;
        });
        debugPrint('[NewLocationPicker] ✅ Local tile server started at: $url');
      } else {
        setState(() {
          _serverErrorMessage = 'Failed to start local tile server';
          _isInitializingServer = false;
        });
        debugPrint('[NewLocationPicker] ❌ $_serverErrorMessage');
      }
    } catch (e) {
      setState(() {
        _serverErrorMessage = 'Error initializing tile server: $e';
        _isInitializingServer = false;
      });
      debugPrint('[NewLocationPicker] ❌ $_serverErrorMessage');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while server is initializing
    if (_isInitializingServer) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text(
                  'Initializing map...',
                  style: AppFonts.regular(14, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Show error if server failed to start
    if (_serverErrorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'Error',
                  style: AppFonts.medium(18, color: Colors.red),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _serverErrorMessage!,
                    textAlign: TextAlign.center,
                    style: AppFonts.regular(14, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Get.back(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Obx(() => _buildBody()),
      ),
    );
  }



  /// Build main body
  Widget _buildBody() {
    switch (controller.state.value) {
      case LocationPickerState.loading:
        return _buildLoadingView();
      case LocationPickerState.error:
        return _buildErrorView();
      default:
        return _buildMapView();
    }
  }

  /// Build loading view
  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading map...'),
        ],
      ),
    );
  }

  /// Build error view
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            'Error',
            style: AppFonts.medium(18, color: Colors.red),
          ),
          const SizedBox(height: 8),
          Text(
            controller.errorMessage.value,
            textAlign: TextAlign.center,
            style: AppFonts.regular(14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => controller.initializeController(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Build map view
  Widget _buildMapView() {
    return Stack(
      children: [
        // Map
        _buildMap(),

        // Floating action buttons
        _buildFloatingButtons(),

        // Radius control
      //  Positioned(
      //     top: 100,
      //     left: 16,
      //     right: 16,
      //     child: _buildRadiusControl(),
      //   ), 

      ],
    );
  }

  /// Build map widget
  Widget _buildMap() {
    // If server URL is not available yet, show loading
    if (_serverUrl == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Initializing map...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
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
          debugPrint('[NewLocationPicker] ❌ Error in FutureBuilder: ${snapshot.error}');
          return Center(
            child: Text(
              'Error loading map style',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        // Style loaded successfully - build the map
        final styleJson = snapshot.data ?? _getBlankStyleJson();

        return mapbox.MapWidget(
          key: const ValueKey("mapbox_map_new"),
          cameraOptions: _getCameraOptions(),
          onMapCreated: (mapboxMap) async {
            controller.mapController = mapboxMap;
            debugPrint('[NewLocationPicker] 🗺️ onMapCreated callback triggered');

            // CRITICAL: Enable online mode to allow localhost tile server access
            await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
            debugPrint('[NewLocationPicker] 🌐 Online mode ENABLED - localhost tile server can now be accessed');

            // Load the custom style JSON with local tile server URLs
            debugPrint('[NewLocationPicker] 📥 Loading custom style JSON into Mapbox...');
            debugPrint('[NewLocationPicker] 📊 Style JSON length: ${styleJson.length} characters');

            // Verify the JSON contains our localhost URLs before loading
            if (styleJson.contains('localhost:8080')) {
              debugPrint('[NewLocationPicker] ✅ Verified: Style JSON contains localhost URLs');
            } else {
              debugPrint('[NewLocationPicker] ⚠️ WARNING: Style JSON does NOT contain localhost URLs!');
            }

            await mapboxMap.loadStyleJson(styleJson);
            debugPrint('[NewLocationPicker] ✅ Custom style JSON loaded into Mapbox successfully');

            _onMapCreated(mapboxMap);
          },
          onStyleLoadedListener: (styleLoadedEventData) async {
            debugPrint('[NewLocationPicker] 🎨 onStyleLoaded callback triggered');
            debugPrint('[NewLocationPicker] ✅ Style.json from assets loaded successfully with local tiles');
          },
          onTapListener: _onMapTap,
          onCameraChangeListener: _onCameraChange,
        );
      },
    );
  }

  /// Get a blank style JSON that doesn't reference any Mapbox sources
  /// This prevents the "Failed to load tile for source composite" errors
  String _getBlankStyleJson() {
    return '''
{
  "version": 8,
  "name": "Blank",
  "metadata": {
    "mapbox:autocomposite": false
  },
  "sources": {},
  "layers": [
    {
      "id": "background",
      "type": "background",
      "paint": {
        "background-color": "#f0f0f0"
      }
    }
  ]
}
''';
  }

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
      "maxzoom": 14
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

  /// Add local tile source from downloaded mbtiles (called after style loads)
  Future<void> _addLocalTileSource() async {
    try {
      if (_serverUrl == null) {
        debugPrint('[NewLocationPicker] ⚠️ Server URL is null, skipping tile source addition');
        return;
      }

      final mapController = controller.mapController;
      if (mapController == null) {
        debugPrint('[NewLocationPicker] ⚠️ Map controller is null, skipping tile source addition');
        return;
      }

      debugPrint('[NewLocationPicker] 🗺️ Adding local tile source...');

      final tileUrl = '$_serverUrl/{z}/{x}/{y}.pbf';
      debugPrint('[NewLocationPicker] Tile URL template: $tileUrl');

      // Add vector source with zoom levels from MapboxZoomHelper
      final zoomHelper = MapboxZoomHelper();
      await mapController.style.addSource(
        mapbox.VectorSource(
          id: 'local-tiles',
          tiles: [tileUrl],
          minzoom: zoomHelper.minZoom.value,
          maxzoom: zoomHelper.maxZoom.value,
        ),
      );

      debugPrint('[NewLocationPicker] ✅ Local tile source added (zoom: ${zoomHelper.minZoom.value}-${zoomHelper.maxZoom.value})');

      // Add layers to display the tiles (CRITICAL - without this, tiles won't show!)
      await _addLocalTileLayers();
    } catch (e) {
      debugPrint('[NewLocationPicker] ❌ Error adding tile source: $e');
      // Continue anyway - map will use default Mapbox tiles
    }
  }

  /// Add layers to display local tiles
  /// Using all 15 layers from OpenMapTiles schema
  Future<void> _addLocalTileLayers() async {
    try {
      final mapController = controller.mapController;
      if (mapController == null) return;

      debugPrint('[NewLocationPicker] 🎨 Adding all 15 OpenMapTiles layers...');

      // 1. Background layer (ocean/sea)
      await mapController.style.addLayer(
        mapbox.BackgroundLayer(
          id: 'local-background',
          backgroundColor: 0xFFAAD3DF,
        ),
      );

      // 2. Water bodies
      try {
        await mapController.style.addLayer(
          mapbox.FillLayer(
            id: 'local-water',
            sourceId: 'local-tiles',
            sourceLayer: 'water',
            fillColor: 0xFFAAD3DF,
            fillOpacity: 1.0,
          ),
        );
      } catch (e) {}

      // 3. Landcover
      try {
        await mapController.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landcover',
            sourceId: 'local-tiles',
            sourceLayer: 'landcover',
            fillColor: 0xFFE8E8E8,
            fillOpacity: 1.0,
          ),
        );
      } catch (e) {}

      // 4. Landuse
      try {
        await mapController.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landuse',
            sourceId: 'local-tiles',
            sourceLayer: 'landuse',
            fillColor: 0xFFD4E7D4,
            fillOpacity: 0.6,
          ),
        );
      } catch (e) {}

      // 5. Parks
      try {
        await mapController.style.addLayer(
          mapbox.FillLayer(
            id: 'local-park',
            sourceId: 'local-tiles',
            sourceLayer: 'park',
            fillColor: 0xFFC8E6C9,
            fillOpacity: 0.7,
          ),
        );
      } catch (e) {}

      // 6. Waterways
      try {
        await mapController.style.addLayer(
          mapbox.LineLayer(
            id: 'local-waterway',
            sourceId: 'local-tiles',
            sourceLayer: 'waterway',
            lineColor: 0xFFAAD3DF,
            lineWidth: 1.0,
          ),
        );
      } catch (e) {}

      // 7. Buildings
      try {
        await mapController.style.addLayer(
          mapbox.FillLayer(
            id: 'local-building',
            sourceId: 'local-tiles',
            sourceLayer: 'building',
            fillColor: 0xFFD0D0D0,
            fillOpacity: 0.7,
          ),
        );
      } catch (e) {}

      // 8. Aeroway
      try {
        await mapController.style.addLayer(
          mapbox.FillLayer(
            id: 'local-aeroway',
            sourceId: 'local-tiles',
            sourceLayer: 'aeroway',
            fillColor: 0xFFE0E0E0,
            fillOpacity: 0.5,
          ),
        );
      } catch (e) {}

      // 9. Transportation
      try {
        await mapController.style.addLayer(
          mapbox.LineLayer(
            id: 'local-transportation',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation',
            lineColor: 0xFFFFFFFF,
            lineWidth: 1.5,
          ),
        );
      } catch (e) {}

      // 10. Boundaries
      try {
        await mapController.style.addLayer(
          mapbox.LineLayer(
            id: 'local-boundary',
            sourceId: 'local-tiles',
            sourceLayer: 'boundary',
            lineColor: 0xFFCCCCCC,
            lineWidth: 0.5,
          ),
        );
      } catch (e) {}

      // 11. Water names
      try {
        await mapController.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-water-name',
            sourceId: 'local-tiles',
            sourceLayer: 'water_name',
            textField: '{name}',
            textSize: 11.0,
            textColor: 0xFF4A90E2,
          ),
        );
      } catch (e) {}

      // 12. Transportation names
      try {
        await mapController.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-transportation-name',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation_name',
            textField: '{name}',
            textSize: 10.0,
            textColor: 0xFF666666,
          ),
        );
      } catch (e) {}

      // 13. Place names
      try {
        await mapController.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-place',
            sourceId: 'local-tiles',
            sourceLayer: 'place',
            textField: '{name}',
            textSize: 12.0,
            textColor: 0xFF000000,
          ),
        );
      } catch (e) {}

      // 14. POI
      try {
        await mapController.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-poi',
            sourceId: 'local-tiles',
            sourceLayer: 'poi',
            textField: '{name}',
            textSize: 10.0,
            textColor: 0xFF333333,
          ),
        );
      } catch (e) {}

      // 15. Mountain peaks
      try {
        await mapController.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-mountain-peak',
            sourceId: 'local-tiles',
            sourceLayer: 'mountain_peak',
            textField: '{name}',
            textSize: 10.0,
            textColor: 0xFF8B4513,
          ),
        );
      } catch (e) {}

      // 16. House numbers
      try {
        await mapController.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-housenumber',
            sourceId: 'local-tiles',
            sourceLayer: 'housenumber',
            textField: '{housenumber}',
            textSize: 9.0,
            textColor: 0xFF999999,
          ),
        );
      } catch (e) {}

      debugPrint('[NewLocationPicker] ✅ All 15 OpenMapTiles layers added');
    } catch (e) {
      debugPrint('[NewLocationPicker] ❌ Error adding tile layers: $e');
    }
  }

  /// Build floating action buttons
  Widget _buildFloatingButtons() {
    return Stack(
      children: [
 Positioned(
          top: 100,
          left: 4,
          right: 4,
          child: _buildRadiusControl(),
        ), 

        // Current location button (top right - moved from done button position)
        if (controller.hasLocationPermission.value && controller.currentPosition.value != null)
          Positioned(
            top: 50,
            right: 4,
            child: _buildCurrentLocationButton(),
          ),

        // Search bar (top center area)
        Positioned(
          top: 50,
          left: 4,
          right: controller.hasLocationPermission.value && controller.currentPosition.value != null ? 60 : 4,
          child: Column(
            children: [
              _buildLocationSearchBar(),
              // Search results dropdown
              Obx(() {
                if (_showSearchResults.value && (_searchController.text.isNotEmpty || controller.searchResults.isNotEmpty || controller.isSearching.value)) {
                  return _buildSearchResultsDropdown();
                }
                return const SizedBox.shrink();
              }),
            ],
          ),
        ),

        // Bottom buttons (done and close)
        Positioned(
          bottom: 30,
          left: 20,
          right: 20,
          child: _buildBottomButtons(),
        ),
      ],
    );
  }

  /// Build back button
  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Get.back(),
      child: Container(
        padding: EdgeInsets.all(6),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(AppImages.rectangle),
            fit: BoxFit.cover,
            colorFilter: uiController.rectangleColorFilter,
          ),
        ),
        child: Image.asset(
          AppImages.arrowBack,
          fit: BoxFit.contain,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Build bottom buttons (done and close)
  Widget _buildBottomButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Close button
        _buildBottomButton(
          iconPath: 'assets/images/ic_cross.png',
          onTap: () => Get.back(),
        ),
        // Done button
        _buildBottomButton(
          iconPath: 'assets/images/ic_tick.png',
          onTap: _onDonePressed,
        ),
      ],
    );
  }

  /// Build individual bottom button
  Widget _buildBottomButton({
    required String iconPath,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Image.asset(
            iconPath,
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  /// Build current location button
  Widget _buildCurrentLocationButton() {
    return GestureDetector(
      onTap: controller.getCurrentLocation,
      child: Container(
        padding: EdgeInsets.all(6),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(AppImages.rectangle),
            fit: BoxFit.cover,
            colorFilter: uiController.rectangleColorFilter,
          ),
        ),
        child: Image.asset(
          AppImages.location,
          fit: BoxFit.contain,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Build location search bar
  Widget _buildLocationSearchBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: uiController.darkMode.value
            ? Colors.black.withValues(alpha: 0.8)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Obx(() => Row(
        children: [
          Image.asset(
            AppImages.searchNormal,
            width: 20,
            height: 20,
            color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildSearchField(),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                controller.searchResults.clear();
                controller.searchQuery.value = '';
                _searchFocusNode.unfocus();
                _showSearchResults.value = false;
              },
              child: Icon(
                Icons.clear,
                size: 20,
                color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600],
              ),
            ),
        ],
      )),
    );
  }

  /// Handle search focus changes
  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus) {
      _showSearchResults.value = true;
    } else {
      // Only hide if search is empty
      if (_searchController.text.isEmpty) {
        _showSearchResults.value = false;
      }
    }
  }

  /// Handle search input changes
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      controller.searchLocations(query);
    } else {
      controller.searchResults.clear();
      controller.searchQuery.value = '';
    }
  }

  /// Build search text field
  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: false,
      textInputAction: TextInputAction.search,
      style: AppFonts.medium(
        16,
        color: uiController.darkMode.value ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        hintText: 'Search locations...',
        hintStyle: AppFonts.regular(
          16,
          color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 2),
      ),
      onTap: () {
        if (!_showSearchResults.value) {
          _showSearchResults.value = true;
        }
      },
    );
  }

  /// Get camera options
  mapbox.CameraOptions? _getCameraOptions() {
    if (controller.currentPosition.value != null) {
      return mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            controller.currentPosition.value!.longitude,
            controller.currentPosition.value!.latitude,
          ),
        ),
        zoom: MapboxZoomHelper().currentLocationZoom.value,
      );
    }
    return null;
  }

  /// Handle map creation
  Future<void> _onMapCreated(mapbox.MapboxMap mapController) async {
    try {
      controller.setMapController(mapController);

      // ENABLE online mode to allow localhost tile server access
      // Mapbox's offline mode blocks ALL network requests, including localhost
      await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
      debugPrint('[NewLocationPicker] 🌐 Online mode ENABLED - localhost tile server can now be accessed');

      // Create annotation manager
      final annotationManager = await mapController.annotations.createPointAnnotationManager();
      controller.setAnnotationManager(annotationManager);

      // Get current location if permission is available
      if (controller.hasLocationPermission.value) {
        await controller.getCurrentLocation();
      }
    } catch (e) {
      debugPrint('Error in onMapCreated: $e');
    }
  }



  /// Handle map tap
  void _onMapTap(mapbox.MapContentGestureContext context) {
    final point = context.point;
    controller.onMapTap(
      point.coordinates.lat.toDouble(),
      point.coordinates.lng.toDouble(),
    );
  }

  /// Handle camera change (zoom level changes)
  void _onCameraChange(mapbox.CameraChangedEventData eventData) {
    // Update zoom level in service for marker scaling
    controller.updateZoom(eventData.cameraState.zoom);
  }

  /// Create a GeoJSON polygon circle in meters for accurate radius display
  Map<String, dynamic> _buildCircleGeoJson(double lat, double lon, double radiusMeters, {int points = 64}) {
    final List<List<double>> coords = [];
    const earthRadius = 6371000.0; // meters

    final double latRad = lat * pi / 180;
    final double lonRad = lon * pi / 180;

    for (int i = 0; i < points; i++) {
      final double bearing = 2 * pi * (i / points);
      final double angularDistance = radiusMeters / earthRadius;

      final double lat2 = asin(
        sin(latRad) * cos(angularDistance) + cos(latRad) * sin(angularDistance) * cos(bearing),
      );
      final double lon2 = lonRad +
          atan2(
            sin(bearing) * sin(angularDistance) * cos(latRad),
            cos(angularDistance) - sin(latRad) * sin(lat2),
          );

      coords.add([lon2 * 180 / pi, lat2 * 180 / pi]);
    }

    // Close the polygon by adding the first coordinate at the end
    coords.add(coords.first);

    return {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "properties": {"radius_m": radiusMeters},
          "geometry": {
            "type": "Polygon",
            "coordinates": [coords],
          }
        }
      ]
    };
  }



  /// Build radius control
  Widget _buildRadiusControl() {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 5, top: 10),
      decoration: BoxDecoration(
        color: uiController.darkMode.value
            ? Colors.black.withOpacity(0.8)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              text: 'Radius: ',
              style: AppFonts.medium(
                16,
                color: uiController.darkMode.value ? Colors.white : Colors.black,
              ),
              children: [
                TextSpan(
                  text: '${_formatRadius(controller.selectedRadius.value)} km',
                  style: AppFonts.medium(
                    16,
                    color: uiController.currentMainColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Obx(() {
            // Convert radius to slider value (0-100 scale)
            final sliderValue = _radiusToSliderValue(controller.selectedRadius.value);

            return Slider(
              value: sliderValue,
              min: 0.0,
              max: 100.0,
              padding: EdgeInsets.only(bottom: 5),
              divisions: 1000,
              activeColor: uiController.currentMainColor,
              inactiveColor: Colors.grey.withOpacity(0.3),
              onChanged: (value) {
                // Convert slider value to radius and update immediately for smooth movement
                final radius = _sliderValueToRadius(value);
                controller.selectedRadius.value = radius;
              },
              onChangeEnd: (value) {
                // Save when user releases the slider
                final radius = _sliderValueToRadius(value);
                controller.updateRadius(radius);
              },
            );
          }),
        ],
      ),
    );
  }

  /// Convert radius (km) to slider value (0-100 scale)
  /// 0-50: 1km to 25km (linear)
  /// 50-100: 25km to 200km (linear)
  double _radiusToSliderValue(double radius) {
    if (radius <= 25.0) {
      // 0-50% of slider: 1km to 25km
      return ((radius - 1.0) / 24.0) * 50.0;
    } else {
      // 50-100% of slider: 25km to 200km
      return 50.0 + ((radius - 25.0) / 175.0) * 50.0;
    }
  }

  /// Convert slider value (0-100 scale) to radius (km)
  /// 0-50: 1km to 25km (linear)
  /// 50-100: 25km to 200km (linear)
  double _sliderValueToRadius(double sliderValue) {
    if (sliderValue <= 50.0) {
      // 0-50% of slider: 1km to 25km
      final radius = 1.0 + (sliderValue / 50.0) * 24.0;
      return (radius * 10).round() / 10.0; // Round to 0.1km
    } else {
      // 50-100% of slider: 25km to 200km
      final radius = 25.0 + ((sliderValue - 50.0) / 50.0) * 175.0;
      return (radius * 10).round() / 10.0; // Round to 0.1km
    }
  }

  /// Build location info
  Widget _buildLocationInfo() {
    final location = controller.selectedLocation.value!;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: uiController.darkMode.value 
            ? Colors.black.withOpacity(0.8)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Selected Location',
            style: AppFonts.medium(
              14,
              color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600]!,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            location.address,
            style: AppFonts.medium(
              16,
              color: uiController.darkMode.value ? Colors.white : Colors.black,
            ),
          ),
          if (location.city.isNotEmpty || location.state.isNotEmpty)
            Text(
              '${location.city}${location.city.isNotEmpty && location.state.isNotEmpty ? ', ' : ''}${location.state}',
              style: AppFonts.regular(
                14,
                color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600]!,
              ),
            ),
        ],
      ),
    );
  }

  /// Build search results dropdown
  Widget _buildSearchResultsDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: uiController.darkMode.value
            ? Colors.black.withValues(alpha: 0.9)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Obx(() {
        if (controller.isSearching.value) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: CircularProgressIndicator(
                color: uiController.primaryColor,
              ),
            ),
          );
        }

        if (controller.searchResults.isEmpty && _searchController.text.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off,
                  size: 32,
                  color: uiController.darkMode.value ? Colors.white38 : Colors.grey[400]!,
                ),
                const SizedBox(height: 8),
                Text(
                  'No locations found',
                  style: AppFonts.medium(
                    14,
                    color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
                  ),
                ),
              
              ],
            ),
          );
        }

        if (controller.searchResults.isEmpty) {
          return const SizedBox.shrink();
        }

        return ListView.separated(
          shrinkWrap: true,
          itemCount: controller.searchResults.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: 1,
            color: uiController.darkMode.value
                ? Colors.grey[700]!
                : Colors.grey[300]!,
          ),
          itemBuilder: (context, index) {
            final result = controller.searchResults[index];
            return _buildSearchResultItem(result);
          },
        );
      }),
    );
  }

  /// Build individual search result item
  Widget _buildSearchResultItem(Map<String, dynamic> result) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          controller.selectSearchResult(result);
          _searchController.clear();
          _showSearchResults.value = false;
          _searchFocusNode.unfocus();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result['name'] ?? 'Unknown Location',
                style: AppFonts.medium(
                  16,
                  color: uiController.darkMode.value ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (result['address'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  result['address'],
                  style: AppFonts.regular(
                    14,
                    color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600]!,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Handle done button press
  void _onDonePressed() {
    controller.saveSelection();
    final result = controller.getResultData();
    Get.back(result: result);
  }

  /// Format radius value for display
  String _formatRadius(double radius) {
    // Show integer values for whole numbers, decimal for fractional values
    if (radius == radius.toInt()) {
      return radius.toInt().toString();
    } else {
      // Show up to 1 decimal place for precision
      return radius.toStringAsFixed(1);
    }
  }
}
