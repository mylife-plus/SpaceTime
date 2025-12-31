import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'package:spacetime/app/modules/location_picker/services/location_picker_service.dart';
import 'package:spacetime/app/utils/place_categories_utils.dart';
import 'package:spacetime/services/mbtiles_download_service.dart';
import 'package:spacetime/services/mbtiles_server_service.dart';

enum MemoryLocationPickerState {
  loading,
  ready,
  error,
  searchingLocation,
  movingToLocation,
}

class MemoryLocationPickerWidget extends StatefulWidget {
  const MemoryLocationPickerWidget({super.key});

  @override
  State<MemoryLocationPickerWidget> createState() => _MemoryLocationPickerWidgetState();
}

class _MemoryLocationPickerWidgetState extends State<MemoryLocationPickerWidget> {
  final MemoryController memoryController = Get.find<MemoryController>();
  final UiController uiController = Get.find<UiController>();
  final LocationPickerService _locationPickerService = LocationPickerService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final RxBool _showSearchResults = false.obs;
  
  // State management
  final Rx<MemoryLocationPickerState> state = MemoryLocationPickerState.loading.obs;
  final RxString errorMessage = ''.obs;
  final RxBool hasLocationPermission = false.obs;
  final RxBool isOfflineMode = false.obs;
  final Rxn<Position> currentPosition = Rxn<Position>();
  final RxBool isSearching = false.obs;
  final RxList<Map<String, dynamic>> searchResults = <Map<String, dynamic>>[].obs;
  
  // Map components
  mapbox.MapboxMap? mapController;
  mapbox.PointAnnotationManager? annotationManager;
  mapbox.PointAnnotation? selectedLocationMarker;

  // Server state for local tiles
  String? _serverUrl;
  String? _serverErrorMessage;
  bool _isInitializingServer = true;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _searchController.addListener(_onSearchChanged);
    _initializeLocationPicker();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Initialize location picker
  Future<void> _initializeLocationPicker() async {
    try {
      state.value = MemoryLocationPickerState.loading;

      // Initialize local tile server first
      await _initializeLocalTileServer();

      // Check location permission
      await _checkLocationPermission();

      // Get current location if permission is available
      if (hasLocationPermission.value) {
        await _getCurrentLocation();
      }

      state.value = MemoryLocationPickerState.ready;
    } catch (e) {
      debugPrint('Error initializing location picker: $e');
      errorMessage.value = 'Failed to initialize location picker: $e';
      state.value = MemoryLocationPickerState.error;
    }
  }

  /// Initialize local tile server before map creation
  /// Server is started in main.dart, so we just check if it's running
  Future<void> _initializeLocalTileServer() async {
    try {
      debugPrint('[MemoryLocationPicker] 🔍 Checking if local tile server is running...');

      final serverService = MbtilesServerService.instance;

      // Check if server is already running (started in main.dart)
      if (serverService.isRunning && serverService.serverUrl != null) {
        setState(() {
          _serverUrl = serverService.serverUrl;
          _isInitializingServer = false;
        });
        debugPrint('[MemoryLocationPicker] ✅ Using existing tile server at: $_serverUrl');
        debugPrint('[MemoryLocationPicker] 📡 Tiles will be served from: $_serverUrl/{z}/{x}/{y}.pbf');
        return;
      }

      // If server is not running, try to start it (fallback)
      debugPrint('[MemoryLocationPicker] ⚠️ Server not running, attempting to start...');

      final mbtilesService = MbtilesDownloadService.instance;
      final isDownloaded = await mbtilesService.isMbtilesDownloaded();
      final tilesPath = mbtilesService.getLocalMbtilesPath();

      if (!isDownloaded || tilesPath == null) {
        setState(() {
          _serverErrorMessage = 'MBTiles file not downloaded. Please download from Get Started screen first.';
          _isInitializingServer = false;
        });
        debugPrint('[MemoryLocationPicker] ❌ $_serverErrorMessage');
        return;
      }

      final url = await serverService.startServer(tilesPath);

      if (url != null) {
        setState(() {
          _serverUrl = url;
          _isInitializingServer = false;
        });
        debugPrint('[MemoryLocationPicker] ✅ Local tile server started at: $url');
      } else {
        setState(() {
          _serverErrorMessage = 'Failed to start local tile server';
          _isInitializingServer = false;
        });
        debugPrint('[MemoryLocationPicker] ❌ $_serverErrorMessage');
      }
    } catch (e) {
      setState(() {
        _serverErrorMessage = 'Error initializing tile server: $e';
        _isInitializingServer = false;
      });
      debugPrint('[MemoryLocationPicker] ❌ $_serverErrorMessage');
    }
  }

  /// Check location permission
  Future<void> _checkLocationPermission() async {
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
  Future<void> _getCurrentLocation() async {
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
    switch (state.value) {
      case MemoryLocationPickerState.loading:
        return _buildLoadingView();
      case MemoryLocationPickerState.error:
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
            errorMessage.value,
            textAlign: TextAlign.center,
            style: AppFonts.regular(14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initializeLocationPicker,
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
        // Top search bar
        _buildTopSearchBar(),
        // Search results dropdown
        _buildSearchResultsOverlay(),
        // Current location button
        _buildCurrentLocationButton(),
        // Bottom action buttons
        _buildBottomActionButtons(),
      ],
    );
  }

  /// Build map widget
  Widget _buildMap() {
    return mapbox.MapWidget(
      key: const ValueKey('memory_location_picker_map'),
      cameraOptions: _getCameraOptions(),
      // Use a minimal blank style JSON to avoid loading from Mapbox servers
      styleUri: _getBlankStyleJson(),
      textureView: true,
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: (styleLoadedEventData) async {
        debugPrint('[MemoryLocationPicker] 🎨 onStyleLoaded callback triggered');

        // Add mbtiles vector source after style is loaded
        await _addLocalTileSource();
      },
      onTapListener: _onMapTap,
      // onMapLoadErrorListener removed as per requirements
    );
  }

  /// Get a blank style JSON that doesn't reference any Mapbox sources
  /// This prevents the "Failed to load tile for source composite" errors
  String _getBlankStyleJson() {
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

  /// Add local tile source from downloaded mbtiles (called after style loads)
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
      await _addLocalTileLayers();
    } catch (e) {
      debugPrint('[MemoryLocationPicker] ❌ Error adding tile source: $e');
      // Continue anyway - map will use default Mapbox tiles
    }
  }

  /// Add layers to display local tiles
  /// Matches layers from assets/style.json
  Future<void> _addLocalTileLayers() async {
    try {
      if (mapController == null) return;

      debugPrint('[MemoryLocationPicker] 🎨 Adding local tile layers...');

      // 1. Background layer (LAND - beige/tan color, NOT ocean!)
      // In OpenMapTiles, background = land, water is drawn on top
      await mapController!.style.addLayer(
        mapbox.BackgroundLayer(
          id: 'local-background',
          backgroundColor: 0xFFE8E4DC, // Beige/tan for land (matches style.json: hsl(47, 26%, 88%))
        ),
      );

      // 2. Landuse - Residential areas
      try {
        await mapController!.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landuse-residential',
            sourceId: 'local-tiles',
            sourceLayer: 'landuse',
            fillColor: 0xFFE8E4E0, // Light beige for residential
            fillOpacity: 0.7,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added landuse-residential layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ landuse-residential layer error: $e');
      }

      // 3. Landcover - Grass
      try {
        await mapController!.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landcover-grass',
            sourceId: 'local-tiles',
            sourceLayer: 'landcover',
            fillColor: 0xFFD4E7D4, // Light green for grass
            fillOpacity: 0.5,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added landcover-grass layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ landcover-grass layer error: $e');
      }

      // 4. Landcover - Wood/Forest
      try {
        await mapController!.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landcover-wood',
            sourceId: 'local-tiles',
            sourceLayer: 'landcover',
            fillColor: 0xFFC8E6C8, // Green for forests
            fillOpacity: 0.6,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added landcover-wood layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ landcover-wood layer error: $e');
      }

      // 5. Water bodies (rivers, lakes)
      try {
        await mapController!.style.addLayer(
          mapbox.FillLayer(
            id: 'local-water',
            sourceId: 'local-tiles',
            sourceLayer: 'water',
            fillColor: 0xFFAAD3DF, // Blue for water
            fillOpacity: 1.0,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added water layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ water layer error: $e');
      }

      // 6. Landcover - Ice shelf
      try {
        await mapController!.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landcover-ice-shelf',
            sourceId: 'local-tiles',
            sourceLayer: 'landcover',
            fillColor: 0xFFFFFFFF, // White for ice
            fillOpacity: 0.8,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added landcover-ice-shelf layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ landcover-ice-shelf layer error: $e');
      }

      // 7. Landcover - Glacier
      try {
        await mapController!.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landcover-glacier',
            sourceId: 'local-tiles',
            sourceLayer: 'landcover',
            fillColor: 0xFFE8F4F8, // Light blue for glaciers
            fillOpacity: 0.8,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added landcover-glacier layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ landcover-glacier layer error: $e');
      }

      // 8. Landcover - Sand
      try {
        await mapController!.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landcover-sand',
            sourceId: 'local-tiles',
            sourceLayer: 'landcover',
            fillColor: 0xFFF5E9D3, // Sandy color
            fillOpacity: 0.7,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added landcover-sand layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ landcover-sand layer error: $e');
      }

      // 9. Landuse - General (parks, etc.)
      try {
        await mapController!.style.addLayer(
          mapbox.FillLayer(
            id: 'local-landuse',
            sourceId: 'local-tiles',
            sourceLayer: 'landuse',
            fillColor: 0xFFD4E7D4, // Light green for parks
            fillOpacity: 0.6,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added landuse layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ landuse layer error: $e');
      }

      // 10. Waterway - Tunnel
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-waterway-tunnel',
            sourceId: 'local-tiles',
            sourceLayer: 'waterway',
            lineColor: 0xFFAAD3DF, // Blue for waterways
            lineWidth: 1.0,
            lineDasharray: [2.0, 1.0], // Dashed for tunnels
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added waterway-tunnel layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ waterway-tunnel layer error: $e');
      }

      // 11. Waterway - Regular
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-waterway',
            sourceId: 'local-tiles',
            sourceLayer: 'waterway',
            lineColor: 0xFFAAD3DF, // Blue for waterways
            lineWidth: 1.5,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added waterway layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ waterway layer error: $e');
      }

      // 12. Buildings
      try {
        await mapController!.style.addLayer(
          mapbox.FillLayer(
            id: 'local-buildings',
            sourceId: 'local-tiles',
            sourceLayer: 'building',
            fillColor: 0xFFD0D0D0, // Gray for buildings
            fillOpacity: 0.7,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added building layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ building layer error: $e');
      }

      // 13. Aeroway - Area (airports)
      try {
        await mapController!.style.addLayer(
          mapbox.FillLayer(
            id: 'local-aeroway-area',
            sourceId: 'local-tiles',
            sourceLayer: 'aeroway',
            fillColor: 0xFFE0E0E0, // Light gray for airport areas
            fillOpacity: 0.5,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added aeroway-area layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ aeroway-area layer error: $e');
      }

      // 14. Aeroway - Taxiway
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-aeroway-taxiway',
            sourceId: 'local-tiles',
            sourceLayer: 'aeroway',
            lineColor: 0xFFCCCCCC, // Gray for taxiways
            lineWidth: 1.0,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added aeroway-taxiway layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ aeroway-taxiway layer error: $e');
      }

      // 15. Aeroway - Runway
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-aeroway-runway',
            sourceId: 'local-tiles',
            sourceLayer: 'aeroway',
            lineColor: 0xFFBBBBBB, // Darker gray for runways
            lineWidth: 3.0,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added aeroway-runway layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ aeroway-runway layer error: $e');
      }

      // 16. Transportation - Path
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-road-path',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation',
            lineColor: 0xFFDDDDDD, // Light gray for paths
            lineWidth: 0.5,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added road-path layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ road-path layer error: $e');
      }

      // 17. Transportation - Minor roads
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-road-minor',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation',
            lineColor: 0xFFFFFFFF, // White for minor roads
            lineWidth: 1.0,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added road-minor layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ road-minor layer error: $e');
      }

      // 18. Transportation - Trunk/Primary roads
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-road-trunk-primary',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation',
            lineColor: 0xFFFFC966, // Orange for major roads
            lineWidth: 2.0,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added road-trunk-primary layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ road-trunk-primary layer error: $e');
      }

      // 19. Transportation - Secondary/Tertiary roads
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-road-secondary-tertiary',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation',
            lineColor: 0xFFFEFEFE, // White for secondary roads
            lineWidth: 1.5,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added road-secondary-tertiary layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ road-secondary-tertiary layer error: $e');
      }

      // 20. Transportation - Motorway
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-road-motorway',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation',
            lineColor: 0xFFFC8, // Red/orange for motorways
            lineWidth: 2.5,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added road-motorway layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ road-motorway layer error: $e');
      }

      // 21. Transportation - Railway
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-railway',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation',
            lineColor: 0xFF888888, // Dark gray for railways
            lineWidth: 1.0,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added railway layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ railway layer error: $e');
      }

      // 22. Boundary - Administrative subdivisions
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-boundary-admin-sub',
            sourceId: 'local-tiles',
            sourceLayer: 'boundary',
            lineColor: 0xFFDDDDDD, // Light gray for subdivisions
            lineWidth: 0.5,
            lineDasharray: [3.0, 2.0], // Dashed line
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added boundary-admin-sub layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ boundary-admin-sub layer error: $e');
      }

      // 23. Boundary - Country borders
      try {
        await mapController!.style.addLayer(
          mapbox.LineLayer(
            id: 'local-boundary-country',
            sourceId: 'local-tiles',
            sourceLayer: 'boundary',
            lineColor: 0xFF999999, // Gray for country borders
            lineWidth: 1.0,
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added boundary-country layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ boundary-country layer error: $e');
      }

      // 24. POI Labels (Points of Interest)
      try {
        await mapController!.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-poi-label',
            sourceId: 'local-tiles',
            sourceLayer: 'poi',
            textField: '{name}',
            textSize: 10.0,
            textColor: 0xFF666666, // Dark gray text
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added poi-label layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ poi-label layer error: $e');
      }

      // 25. Airport Labels
      try {
        await mapController!.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-airport-label',
            sourceId: 'local-tiles',
            sourceLayer: 'aerodrome_label',
            textField: '{name}',
            textSize: 11.0,
            textColor: 0xFF555555, // Dark gray text
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added airport-label layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ airport-label layer error: $e');
      }

      // 26. Road Labels (transportation_name)
      try {
        await mapController!.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-road-label',
            sourceId: 'local-tiles',
            sourceLayer: 'transportation_name',
            textField: '{name}',
            textSize: 10.0,
            textColor: 0xFF444444, // Dark gray text
            symbolPlacement: mapbox.SymbolPlacement.LINE, // Place text along the road
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added road-label layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ road-label layer error: $e');
      }

      // 27. Place Labels - Other (towns, villages)
      try {
        await mapController!.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-place-label-other',
            sourceId: 'local-tiles',
            sourceLayer: 'place',
            textField: '{name}',
            textSize: 11.0,
            textColor: 0xFF333333, // Dark text
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added place-label-other layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ place-label-other layer error: $e');
      }

      // 28. Place Labels - Cities
      try {
        await mapController!.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-place-label-city',
            sourceId: 'local-tiles',
            sourceLayer: 'place',
            textField: '{name}',
            textSize: 14.0,
            textColor: 0xFF000000, // Black text for cities
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added place-label-city layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ place-label-city layer error: $e');
      }

      // 29. Country Labels
      try {
        await mapController!.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-country-label',
            sourceId: 'local-tiles',
            sourceLayer: 'place',
            textField: '{name}',
            textSize: 16.0,
            textColor: 0xFF000000, // Black text for countries
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added country-label layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ country-label layer error: $e');
      }

      // 30. House Numbers
      try {
        await mapController!.style.addLayer(
          mapbox.SymbolLayer(
            id: 'local-housenumber',
            sourceId: 'local-tiles',
            sourceLayer: 'housenumber',
            textField: '{housenumber}',
            textSize: 8.0,
            textColor: 0xFF888888, // Gray text for house numbers
          ),
        );
        debugPrint('[MemoryLocationPicker] ✅ Added housenumber layer');
      } catch (e) {
        debugPrint('[MemoryLocationPicker] ⚠️ housenumber layer error: $e');
      }

      debugPrint('[MemoryLocationPicker] ✅ Local tile layers setup complete (30 layers added)');
    } catch (e) {
      debugPrint('[MemoryLocationPicker] ❌ Error adding tile layers: $e');
      // Don't throw - continue with whatever layers were added
    }
  }

  /// Get camera options
  mapbox.CameraOptions? _getCameraOptions() {
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

  /// Build top search bar - matching new location picker design
  Widget _buildTopSearchBar() {
    return Positioned(
      top: 50,
      left: 4,
      right: hasLocationPermission.value && currentPosition.value != null ? 60 : 4,
      child: Container(
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
                  searchResults.clear();
                  _showSearchResults.value = false;
                  _searchFocusNode.unfocus();
                },
                child: Icon(
                  Icons.clear,
                  size: 20,
                  color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600],
                ),
              ),
          ],
        )),
      ),
    );
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

  /// Build search results overlay - matching new location picker design
  Widget _buildSearchResultsOverlay() {
    return Obx(() {
      if (!_showSearchResults.value ||
          (_searchController.text.isEmpty && searchResults.isEmpty && !isSearching.value)) {
        return const SizedBox.shrink();
      }

      return Positioned(
        top: 98, // Below search bar
        left: 4,
        right: hasLocationPermission.value && currentPosition.value != null ? 60 : 4,
        child: Container(
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
          child: _buildSearchResultsContent(),
        ),
      );
    });
  }

  /// Build search results content - matching new location picker design
  Widget _buildSearchResultsContent() {
    if (isSearching.value) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: CircularProgressIndicator(
            color: uiController.primaryColor,
          ),
        ),
      );
    }

    if (searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No locations found',
          style: AppFonts.medium(
            14,
            color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: searchResults.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: uiController.darkMode.value
            ? Colors.grey[700]!
            : Colors.grey[300]!,
      ),
      itemBuilder: (context, index) {
        final result = searchResults[index];
        return _buildSearchResultItem(result);
      },
    );
  }

  /// Build individual search result item - matching new location picker design
  Widget _buildSearchResultItem(Map<String, dynamic> result) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _selectSearchResult(result);
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

  /// Build current location button - matching new location picker design
  Widget _buildCurrentLocationButton() {
    if (!hasLocationPermission.value || currentPosition.value == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 50,
      right: 4,
      child: GestureDetector(
        onTap: _moveToCurrentLocation,
        child: Container(
          padding: const EdgeInsets.all(6),
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
      ),
    );
  }

  /// Build bottom action buttons - matching new location picker design
  Widget _buildBottomActionButtons() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      bottom: _searchFocusNode.hasFocus ? -100 : 30, // Hide when search is focused
      left: 20,
      right: 20,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _searchFocusNode.hasFocus ? 0.0 : 1.0, // Fade out when search is focused
        child: Row(
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
        ),
      ),
    );
  }

  /// Build individual bottom button - matching new location picker design
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
    // Trigger rebuild for button animation
    setState(() {});
  }

  /// Handle search text changes
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _performLocationSearch(query);
    } else {
      _showSearchResults.value = false;
      searchResults.clear();
    }
  }

  /// Handle map creation
  Future<void> _onMapCreated(mapbox.MapboxMap controller) async {
    try {
      mapController = controller;

      // ENABLE online mode to allow localhost tile server access
      // Mapbox's offline mode blocks ALL network requests, including localhost
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

        await _moveToLocation(lat, lng);
        await _selectLocation(lat, lng);
        debugPrint('📍 Showing previously selected location on map load: $lat, $lng');
      } else if (hasLocationPermission.value && currentPosition.value != null) {
        // Otherwise, show current location if available
        await _moveToLocation(
          currentPosition.value!.latitude,
          currentPosition.value!.longitude,
        );
        // Automatically select current location with red marker
        await _selectLocation(
          currentPosition.value!.latitude,
          currentPosition.value!.longitude,
        );
        debugPrint('📍 Auto-selected current location on map load');
      }
    } catch (e) {
      debugPrint('Error in onMapCreated: $e');
    }
  }

  /// Handle map tap - show red marker without radius
  Future<void> _onMapTap(mapbox.MapContentGestureContext context) async {
    // Dismiss keyboard when tapping on map
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      _showSearchResults.value = false;
    }

    final point = context.point;
    await _selectLocation(
      point.coordinates.lat.toDouble(),
      point.coordinates.lng.toDouble(),
    );
  }

  /// Move to current location
  Future<void> _moveToCurrentLocation() async {
    if (currentPosition.value == null) {
      await _getCurrentLocation();
    }

    if (currentPosition.value != null) {
      await _moveToLocation(
        currentPosition.value!.latitude,
        currentPosition.value!.longitude,
      );
      await _selectLocation(
        currentPosition.value!.latitude,
        currentPosition.value!.longitude,
      );
    }
  }

  /// Move camera to location
  Future<void> _moveToLocation(double lat, double lng) async {
    if (mapController == null) return;

    await mapController!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(lng, lat),
        ),
        zoom: MapboxZoomHelper().currentLocationZoom.value,
      ),
      mapbox.MapAnimationOptions(duration: 1000),
    );
  }

  /// Select location and add red marker without radius
  Future<void> _selectLocation(double lat, double lng) async {
    if (annotationManager == null) return;

    try {
      // Clear existing markers first
      await _clearExistingMarkers();

      // Create red marker image
      await _createRedMarkerImage();

      // Create new red marker
      final pointAnnotationOptions = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        iconImage: 'red-marker-icon',
        iconSize: 0.1, // Reduced size to make it smaller
      );

      selectedLocationMarker = await annotationManager!.create(pointAnnotationOptions);

      // Update memory controller with selected location
      memoryController.setLocation('$lat,$lng');

      // Get location details using geocoding service
      await _getLocationDetails(lat, lng);

    } catch (e) {
      debugPrint('Error selecting location: $e');
    }
  }

  Future<void> _clearExistingMarkers() async {
    if (annotationManager == null) return;

    try {
      // Clear all existing annotations
      await annotationManager!.deleteAll();

      // Reset the selected marker reference
      selectedLocationMarker = null;

      debugPrint('🧹 Cleared all existing location markers');
    } catch (e) {
      debugPrint('Error clearing existing markers: $e');
    }
  }

  /// Create red marker image for selected location
  Future<void> _createRedMarkerImage() async {
    if (mapController == null) return;

    try {
      // Remove existing image if it exists
      try {
        await mapController!.style.removeStyleImage('red-marker-icon');
      } catch (e) {
        // Image doesn't exist yet, which is fine
      }

      // Create proper circular red marker using Canvas
      final imageBytes = await _createRedMarkerImageBytes();

      await mapController!.style.addStyleImage(
        'red-marker-icon',
        1.0,
        mapbox.MbxImage(
          data: imageBytes,
          width: 500,
          height: 500,
        ),
        false,
        [],
        [],
        null,
      );

      debugPrint('✅ Red marker image created and added to map style');
    } catch (e) {
      debugPrint('Error creating red marker image: $e');
    }
  }

  /// Create red marker image bytes using Canvas
  Future<Uint8List> _createRedMarkerImageBytes() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Create a high-quality circular marker with higher resolution
    const size = 500.0; // Doubled size for better quality
    const center = Offset(size / 2, size / 2);
    const innerRadius = size / 3.5; // Larger inner radius

    // Draw inner red circle with solid color
    final innerPaint = Paint()
      ..color = const Color(0xFFE53E3E) // Better red color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, innerRadius, innerPaint);

    // Draw white border around inner circle with better thickness
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0 // Thicker border for better visibility
      ..isAntiAlias = true;
    canvas.drawCircle(center, innerRadius, borderPaint);

    // Add a subtle shadow effect
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2.0);
    canvas.drawCircle(center.translate(2, 2), innerRadius, shadowPaint);

    // Convert to high-quality image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Get location details using geocoding service
  Future<void> _getLocationDetails(double lat, double lng) async {
    try {
      // Use the geocoding isolate service for reverse geocoding
      final geocodingService = GeocodingIsolateService.instance;
      final result = await geocodingService.reverseGeocode(lat, lng);

      if (result != null) {
        final country = result['country'] ?? '';
        final city = result['city'] ?? '';
        final address = result['address'] ?? '';
        final flag = result['flag'] ?? countryFlags[country.toLowerCase()] ?? '📍';

        memoryController.setEnhancedLocationData({
          'latitude': lat,
          'longitude': lng,
          'city': city,
          'country': country,
          'address': address,
          'flag': flag,
          'name': city.isNotEmpty ? '$city, $country' : country,
        });

        debugPrint('📍 Location details: $city, $country $flag');
      } else {
        // Fallback to basic location data
        memoryController.setEnhancedLocationData({
          'latitude': lat,
          'longitude': lng,
          'city': 'Selected Location',
          'country': 'Unknown',
          'flag': '📍',
        });
      }
    } catch (e) {
      debugPrint('Error getting location details: $e');
      // Fallback to basic location data
      memoryController.setEnhancedLocationData({
        'latitude': lat,
        'longitude': lng,
        'city': 'Selected Location',
        'country': 'Unknown',
        'flag': '📍',
      });
    }
  }



  /// Perform location search using LocationPickerService (same as new_location_picker_widget)
  Future<void> _performLocationSearch(String query) async {

    
    if (query.trim().isEmpty) {
                _showSearchResults.value = false;

      return;
      }

                _showSearchResults.value = true;


    isSearching.value = true;
    searchResults.clear();


    try {
      // Use LocationPickerService for searching (same database as new_location_picker_widget)
      final results = await _locationPickerService.searchLocations(
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

  /// Select search result
  Future<void> _selectSearchResult(Map<String, dynamic> result) async {
    final lat = double.tryParse(result['latitude']?.toString() ?? '0') ?? 0.0;
    final lng = double.tryParse(result['longitude']?.toString() ?? '0') ?? 0.0;

    _showSearchResults.value = false;
    _searchController.clear();
    FocusScope.of(context).unfocus();

    // Clear existing markers before selecting new location
    await _clearExistingMarkers();

    await _moveToLocation(lat, lng);
    await _selectLocation(lat, lng);
  }

  /// Handle done button press - return complete location data with flag
  void _onDonePressed() {
    if (selectedLocationMarker == null) {
      Get.back();
      return;
    }

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
}
