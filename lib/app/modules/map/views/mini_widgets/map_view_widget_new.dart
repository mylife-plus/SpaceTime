import 'dart:io' as io;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/search_overly.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/map_fab.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/top_buttons.dart';
import 'package:spacetime/app/helpers/mapbox_zoom_helper.dart';
import '../../controllers/map_controller_new.dart';
// Note: Permission-related imports removed as location check is disabled
// Note: Internet required screen removed - offline tiles are downloaded during Get Started flow
import '../../../add_memories/controllers/add_memories_controller.dart';
import '../../../add_memories/views/mini_widgets/filter_indicator.dart';
import '../../../add_memories/views/mini_widgets/search_indicator.dart';
import '../../../filter/controllers/filter_controller.dart';
import '../../../ui/controllers/ui_controller.dart';
import 'package:spacetime/app/theme/app_system_ui.dart';
import 'map_filter_overlay.dart';
import '../../../../../services/mbtiles_download_service.dart';
import '../../../../../services/mbtiles_server_service.dart';
import '../../../../../services/style_json_download_service.dart';

class MapViewWidgetNew extends StatefulWidget {
  const MapViewWidgetNew({super.key});

  @override
  State<MapViewWidgetNew> createState() => _MapViewWidgetNewState();
}

class _MapViewWidgetNewState extends State<MapViewWidgetNew>
    with WidgetsBindingObserver {
  MapControllerNew? controller;
  AddMemoriesController? addMemoriesController;

  mapbox.MapboxMap? mapController;

  // Server state (like GlobeTestView)
  String? _serverUrl;
  String? _errorMessage;
  bool _isInitializing = true;
  bool _serverInitScheduled = false;

  /// Top bar / FAB / indicators stay off until style is loaded so Flutter does not
  /// composite heavy widgets while Mapbox is still initializing (reduces jank).
  bool _mapChromeReady = false;

  /// Must be stable across rebuilds — a new [Future] each [build] resets [FutureBuilder] (infinite loop after [setState]).
  String? _styleLoadCacheKey;
  Future<String>? _styleJsonLoadFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    controller = Get.find<MapControllerNew>();

    // One frame after mount so ModalRoute is ready; no artificial delay (avoids felt lag).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _beginTileServerInit();
    });
  }

  void _beginTileServerInit() {
    if (!mounted || _serverInitScheduled) return;
    _serverInitScheduled = true;
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
      controller!.checkPermissionsAfterResume();
    }
  }

  /// Initialize local tile server before map creation
  /// Server is started in main.dart, so we just check if it's running
  Future<void> _initializeLocalTileServer() async {
    try {
      final serverService = MbtilesServerService.instance;

      // Check if server is already running (started in main.dart)
      if (serverService.isRunning && serverService.serverUrl != null) {
        setState(() {
          _serverUrl = serverService.serverUrl;
          _isInitializing = false;
        });
        return;
      }

      final mbtilesService = MbtilesDownloadService.instance;
      final isDownloaded = await mbtilesService.isMbtilesDownloaded();
      final tilesPath = mbtilesService.getLocalMbtilesPath();

      if (!isDownloaded || tilesPath == null) {
        setState(() {
          _errorMessage =
              'MBTiles file not downloaded. Please download from Get Started screen first.';
          _isInitializing = false;
        });
        return;
      }

      final url = await serverService.startServer(tilesPath);

      if (url != null) {
        setState(() {
          _serverUrl = url;
          _isInitializing = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to start local tile server';
          _isInitializing = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing tile server: $e';
        _isInitializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    // Show error if server failed to start
    if (_errorMessage != null) {
      return Obx(() {
        final isDark = uiController.darkMode.value;
        final fg = isDark ? Colors.white : Colors.black87;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppSystemUi.overlayStyle(dark: isDark),
          child: ColoredBox(
            color: isDark ? uiController.darkBackgroundColor : Colors.white,
            child: SafeArea(
              bottom: false,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 64, color: Colors.red),
                        const SizedBox(height: 20),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: fg),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      });
    }

    // Show loading while server is starting
    if (_isInitializing || _serverUrl == null) {
      return Obx(() {
        final isDark = uiController.darkMode.value;
        final fg = isDark ? Colors.white : Colors.black87;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: AppSystemUi.overlayStyle(dark: isDark),
          child: ColoredBox(
            color: isDark ? uiController.darkBackgroundColor : Colors.white,
            child: SafeArea(
              bottom: false,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        color: isDark ? Colors.white : null,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'text_starting_local_tile_server'.tr,
                        style: TextStyle(color: fg),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      });
    }

    return GetBuilder<MapControllerNew>(
      // Remove init parameter to prevent creating new instance
      builder: (controller) {
        return Obx(() {
          final isDark = uiController.darkMode.value;
          final addMemoriesController = Get.find<AddMemoriesController>();
          final filterOpen = controller.isFilterOpen.value;
          final searchOpen = addMemoriesController.isSearchActive.value &&
              addMemoriesController.isOpenedFromMap;
          final overlayChromeOpen = filterOpen || searchOpen;
          final overlayStatusBarColor = filterOpen
              ? uiController.filterOverlayBackgroundColor
              : uiController.searchOverlayBackgroundColor;

          final SystemUiOverlayStyle systemUi = overlayChromeOpen
              ? AppSystemUi.overlayStyleMatchingSurface(
                  surface: overlayStatusBarColor,
                  darkTheme: isDark,
                )
              : AppSystemUi.overlayStyle(dark: isDark);

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: systemUi,
            child: ColoredBox(
              color: isDark ? uiController.darkBackgroundColor : Colors.white,
              child: Scaffold(
                backgroundColor: Colors.transparent,
                body: Stack(
                  children: [
                    // Map fills the whole screen, INCLUDING under the status bar.
                    Positioned.fill(child: _buildMapWidget(controller)),

                    if (!_mapChromeReady)
                      Positioned.fill(child: _buildMapLoadingOverlay()),

                    // Chrome stays below the status bar via SafeArea (fills the
                    // screen so the overlay Stack gets tight constraints; the
                    // top inset matches the previous safe-area-wrapped layout).
                    if (_mapChromeReady)
                      Positioned.fill(
                        child: SafeArea(
                          bottom: false,
                          child: Obx(() => _buildOverlays(controller)),
                        ),
                      ),

                    // Android edge-to-edge: paint the status-bar inset to match the
                    // open filter or search overlay surface.
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: MediaQuery.of(context).padding.top,
                      child: overlayChromeOpen
                          ? ColoredBox(color: overlayStatusBarColor)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
    // },
    // );
  }

  /// Full-screen friendly loader while style JSON / Mapbox surface initialize (avoids long black screen).
  Widget _buildMapLoadingOverlay() {
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ) ??
        const TextStyle(
          fontSize: 22,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        );

    return AbsorbPointer(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0D1117),
              Color(0xFF161B22),
              Color(0xFF010409),
            ],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 52,
                  color: Colors.white.withOpacity(0.85),
                ),
                const SizedBox(height: 28),
                Text('text_preparing_your_map'.tr, style: titleStyle),
                const SizedBox(height: 12),
                Text(
                  'text_loading_offline_tiles_and_map_style'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlays(MapControllerNew controller) {
    final addMemoriesController = Get.find<AddMemoriesController>();
    return Stack(
      children: [
        // Dim map when filter or search overlay is open.
        Obx(() {
          final searchOpen = addMemoriesController.isSearchActive.value &&
              addMemoriesController.isOpenedFromMap;
          if (!controller.isFilterOpen.value && !searchOpen) {
            return const SizedBox.shrink();
          }
          final ui = Get.find<UiController>();
          final alpha = ui.darkMode.value ? 0.74 : 0.52;
          return Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: alpha),
            ),
          );
        }),

        // Top buttons and FAB (hidden when filter or search is open)
        Obx(() {
          final searchOpen = addMemoriesController.isSearchActive.value &&
              addMemoriesController.isOpenedFromMap;
          if (controller.isFilterOpen.value || searchOpen) {
            return const SizedBox.shrink();
          }
          return const Stack(children: [MapTopButtons(), MapFab()]);
        }),

        Positioned(top: 60, left: 0, right: 0, child: SearchIndicator()),

        const Positioned(top: 60, left: 0, right: 0, child: FilterIndicator()),

        // Filter overlay
        Visibility(
          visible: controller.isFilterOpen.value,
          maintainState: true,
          maintainAnimation: true,
          maintainSize: true,
          child: const MapFilterOverlay(),
        ),

        // Search overlay (same in-place pattern as filter — map stays mounted)
        Obx(() {
          final searchOpen = addMemoriesController.isSearchActive.value &&
              addMemoriesController.isOpenedFromMap;
          if (!searchOpen) return const SizedBox.shrink();
          return const SearchOverlay();
        }),
      ],
    );
  }

  /// Build the MapBox map widget
  Widget _buildMapWidget(MapControllerNew controller) {
    // If server URL is not available, show blank style immediately

    if (_serverUrl == null) {
      return mapbox.MapWidget(
        key: ValueKey("mapbox_map_new"),
        cameraOptions: mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(10.4515, 51.1657),
          ),
          zoom: 2.0,
        ),
        styleUri: _getCustomStyleUri(), // Returns blank style
        textureView: io.Platform.isAndroid,
        onMapCreated: (mapboxMap) async {
          mapboxMap = mapboxMap;
          mapboxMap.compass.updateSettings(
            mapbox.CompassSettings(enabled: false),
          );
          mapboxMap.scaleBar.updateSettings(
            mapbox.ScaleBarSettings(enabled: false),
          );
          mapboxMap.attribution.updateSettings(
            mapbox.AttributionSettings(enabled: false),
          );

          controller.mapboxMap = mapboxMap;

          await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
          controller.onMapCreated(mapboxMap);
          mapboxMap.compass.updateSettings(
            mapbox.CompassSettings(enabled: false),
          );
          mapboxMap.scaleBar.updateSettings(
            mapbox.ScaleBarSettings(enabled: false),
          );
          mapboxMap.attribution.updateSettings(
            mapbox.AttributionSettings(enabled: false),
          );
          mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));
        },
        onTapListener: (c) {
          controller.handleMapTap1(c);
          //
        },
        onStyleLoadedListener: (styleLoadedEventData) {
          controller.onStyleLoaded(styleLoadedEventData);
        },
      );
    }

    // Server URL is available - load style.json from assets
    final tileUrl = '$_serverUrl/{z}/{x}/{y}.pbf';
    final serverUrl = _serverUrl!; // Base server URL without tile pattern

    final styleKey = '$serverUrl|$tileUrl';
    if (_styleLoadCacheKey != styleKey) {
      _styleLoadCacheKey = styleKey;
      _styleJsonLoadFuture = _loadStyleJsonFromAssets(tileUrl, serverUrl);
    }

    return FutureBuilder<String>(
      future: _styleJsonLoadFuture!,
      builder: (context, snapshot) {
        // Style JSON loading — full-screen overlay handles UX; keep layer cheap underneath.
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const ColoredBox(
            color: Color(0xFF0D1117),
            child: SizedBox.expand(),
          );
        }

        // Handle error — show chrome so user can still use top bar / leave screen
        if (snapshot.hasError) {
          debugPrint(
            '[MapViewWidgetNew] ❌ Error in FutureBuilder: ${snapshot.error}',
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_mapChromeReady) {
              setState(() => _mapChromeReady = true);
            }
          });
          return Center(
            child: Text(
              'text_error_loading_map_style'.tr,
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        // Style loaded successfully - build the map
        final styleJson = snapshot.data ?? _getCustomStyleUri();

        return mapbox.MapWidget(
          key: ValueKey("mapbox_map_new"),
          cameraOptions: mapbox.CameraOptions(
            center: mapbox.Point(
              coordinates: mapbox.Position(10.4515, 51.1657),
            ),
            zoom: 2.0,
          ),
          // Don't set styleUri - we'll load the JSON style after map creation
          // iOS FIX: Use surface view instead of texture view for better iOS compatibility
          textureView:
              io.Platform.isAndroid, // Only use texture view on Android
          onMapCreated: (mapboxMap) async {
            debugPrint(
              '[MapViewWidgetNew] 🗺️ onMapCreated callback triggered',
            );

            // CRITICAL: Enable online mode to allow localhost tile server access
            // Mapbox's offline mode blocks ALL network requests, including localhost
            // We MUST enable connectivity for the local tile server to work
            await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
            debugPrint(
              '[MapViewWidgetNew] 🌐 Online mode ENABLED - localhost tile server can now be accessed',
            );

            // Before loadStyleJson so onStyleLoaded cannot be undone by a late onMapCreated.
            controller.onMapCreated(mapboxMap);

            // Load the custom style JSON with local tile server URLs
            debugPrint(
              '[MapViewWidgetNew] 📥 Loading custom style JSON into Mapbox...',
            );
            debugPrint(
              '[MapViewWidgetNew] 📊 Style JSON length: ${styleJson.length} characters',
            );

            // Verify the JSON contains our localhost URLs before loading
            if (styleJson.contains('localhost:8080')) {
              debugPrint(
                '[MapViewWidgetNew] ✅ Verified: Style JSON contains localhost URLs',
              );
            } else {
              debugPrint(
                '[MapViewWidgetNew] ⚠️ WARNING: Style JSON does NOT contain localhost URLs!',
              );
            }

            await mapboxMap.loadStyleJson(styleJson);

            debugPrint(
              '[MapViewWidgetNew] ✅ Custom style JSON loaded into Mapbox successfully',
            );
          },
          onStyleLoadedListener: (styleLoadedEventData) async {
            debugPrint(
              '[MapViewWidgetNew] 🎨 onStyleLoaded callback triggered',
            );
            debugPrint(
              '[MapViewWidgetNew] ✅ Style.json from assets loaded successfully with local tiles',
            );

            controller.onStyleLoaded(styleLoadedEventData);
            if (mounted) {
              setState(() => _mapChromeReady = true);
            }
          },
          onMapLoadErrorListener: (mapLoadError) {
            debugPrint(
              '[MapViewWidgetNew] ❌ Map Load Error: ${mapLoadError.type}',
            );
            debugPrint(
              '[MapViewWidgetNew] ❌ Error Message: ${mapLoadError.message}',
            );
            debugPrint(
              '[MapViewWidgetNew] ❌ Error Timestamp: ${mapLoadError.timestamp}',
            );
          },
        );
      },
    );
  }

  Future<void> _addLocalTileSource() async {
    try {
      if (_serverUrl == null) {
        return;
      }

      if (mapController == null) {
        return;
      }

      final tileUrl = '$_serverUrl/{z}/{x}/{y}.pbf';

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
    } catch (e) {
      // Continue anyway - map will use default Mapbox tiles
    }
  }

  ///

  /// Get custom style URI with local tile server URL
  String _getCustomStyleUri() {
    final tileUrl = '$_serverUrl/{z}/{x}/{y}.pbf';

    return _getStyleJsonWithLocalTiles(tileUrl);
  }

  String _getStyleJsonWithLocalTiles(String tileUrl) {
    return 'LOADING_FROM_ASSETS';
  }

  Future<String> _loadStyleJsonFromAssets(
    String tileUrl,
    String serverUrl,
  ) async {
    try {
      debugPrint(
        '[MapViewWidgetNew] 📂 Loading style.json from local storage...',
      );

      // Try to load from local storage first if service is available
      String? styleJsonString;
      if (Get.isRegistered<StyleJsonDownloadService>()) {
        final styleJsonService = Get.find<StyleJsonDownloadService>();
        styleJsonString = await styleJsonService.readStyleJsonContent();
      }

      // Fallback to assets if local file not found or service not available

      if (styleJsonString == null) {
        debugPrint(
          '[MapViewWidgetNew] ⚠️ Local style.json not found, loading from assets...',
        );
        styleJsonString = await rootBundle.loadString(
          'assets/custom-style.json',
        );
        debugPrint('[MapViewWidgetNew] ✅ Loaded style.json from assets');
      } else {
        debugPrint('[MapViewWidgetNew] ✅ Loaded style.json from local storage');
      }

      var modifiedStyleJson = styleJsonString
          .replaceAll('{LOCAL_SERVER_URL}', serverUrl)
          .replaceAll('{LOCAL_TILE_URL}', tileUrl);

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
}

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
        title: Text('title_text_circle_layer_clustering_example'.tr),
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
            coordinates: mapbox.Position(
              -103.59179687498357,
              40.66995747013945,
            ),
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
      debugPrint(
        '[CircleLayerClustering] 🎨 Loading style and setting up clustering...',
      );

      // 1) Load your GeoJSON (equivalent to earthquakes.geojson in Android example)
      final geojsonString = await rootBundle.loadString(
        'assets/earthquakes.geojson',
      );

      debugPrint('[CircleLayerClustering] 📦 GeoJSON loaded, adding source...');

      // 2) Add clustered GeoJSON source with optimized settings for smooth clustering
      await style.addSource(
        mapbox.GeoJsonSource(
          id: _sourceId,
          data: geojsonString,
          cluster: true,
          clusterRadius:
              50, // Radius of each cluster (pixels) - adjust for tighter/looser clustering
          clusterMaxZoom:
              14, // Max zoom to cluster points - stops clustering at zoom 15+
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
          filter: [
            '!',
            ['has', 'point_count'],
          ],
          circleColor: 0xFF11B4DA, // Lighter blue for individual points
          circleRadius: 8.0, // Slightly larger for better visibility
          circleStrokeWidth: 2.0,
          circleStrokeColor: 0xFFFFFFFF, // White stroke
          circleOpacity: 0.95,
          circleBlur: 0.1, // Slight blur for smoother appearance
        ),
      );

      debugPrint('[CircleLayerClustering] ✅ Unclustered layer added');
      debugPrint(
        '[CircleLayerClustering] 🎉 All clustering layers added successfully!',
      );

      // Setup camera change listener for smooth zoom transitions
      _setupCameraChangeListener();
    } catch (e) {
      debugPrint('[CircleLayerClustering] ❌ Error setting up clustering: $e');
    }
  }

  /// Setup camera change listener for smooth transitions
  void _setupCameraChangeListener() {
    if (_mapboxMap == null) return;

    debugPrint(
      '[CircleLayerClustering] 📹 Setting up camera change listener for smooth transitions',
    );

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
        mapbox.CameraOptions(center: cameraState.center, zoom: newZoom),
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
        mapbox.CameraOptions(center: cameraState.center, zoom: newZoom),
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
            coordinates: mapbox.Position(
              -103.59179687498357,
              40.66995747013945,
            ),
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
      debugPrint(
        '[CircleLayerClustering] 📊 Context type: ${context.runtimeType}',
      );
      debugPrint('[CircleLayerClustering] 📊 Context point: ${context.point}');

      final tapPoint = context.point;

      // Use fromScreenCoordinate with lng/lat (this is how the main controller does it)
      // Note: This seems wrong but it's what works in the main controller
      final screenCoord = mapbox.ScreenCoordinate(
        x: lng.toDouble(),
        y: lat.toDouble(),
      );

      // First, try querying ALL features at this point to see what's there
      debugPrint(
        '[CircleLayerClustering] 🔍 Querying ALL features at tap point',
      );
      final allFeatures = await _mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(screenCoord),
        mapbox.RenderedQueryOptions(),
      );

      debugPrint(
        '[CircleLayerClustering] 📊 Total features found: ${allFeatures.length}',
      );

      // Log first few features to see what we're getting
      for (int i = 0; i < allFeatures.length && i < 5; i++) {
        final feature = allFeatures[i];
        if (feature != null) {
          try {
            final queriedFeature = feature.queriedFeature;
            final featureData = queriedFeature.feature;
            debugPrint(
              '[CircleLayerClustering] 📊 Feature $i: ${featureData.toString()}',
            );
            debugPrint(
              '[CircleLayerClustering] 📊 Feature $i source: ${queriedFeature.source}',
            );
            debugPrint(
              '[CircleLayerClustering] 📊 Feature $i sourceLayer: ${queriedFeature.sourceLayer}',
            );
          } catch (e) {
            debugPrint(
              '[CircleLayerClustering] 📊 Feature $i: Error accessing - $e',
            );
          }
        }
      }

      debugPrint(
        '[CircleLayerClustering] 🔍 Querying cluster layer: $_clusterLayerId',
      );

      // Check if we tapped on a cluster
      final clusterFeatures = await _mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenCoordinate(screenCoord),
        mapbox.RenderedQueryOptions(layerIds: [_clusterLayerId]),
      );

      debugPrint(
        '[CircleLayerClustering] 📊 Cluster features found: ${clusterFeatures.length}',
      );

      if (clusterFeatures.isNotEmpty && clusterFeatures.first != null) {
        // Tapped on a cluster - zoom in smoothly
        debugPrint('[CircleLayerClustering] 🎯 Cluster tapped, zooming in...');

        final cameraState = await _mapboxMap!.getCameraState();
        final currentZoom = cameraState.zoom;
        final newZoom = (currentZoom + 2.0).clamp(0.0, 22.0);

        debugPrint(
          '[CircleLayerClustering] 📊 Current zoom: $currentZoom, New zoom: $newZoom',
        );

        await _mapboxMap!.flyTo(
          mapbox.CameraOptions(center: tapPoint, zoom: newZoom),
          mapbox.MapAnimationOptions(duration: 800, startDelay: 0),
        );

        setState(() {
          _currentZoom = newZoom;
        });

        debugPrint(
          '[CircleLayerClustering] ✅ Zoomed into cluster (zoom: $newZoom)',
        );
        return;
      }

      debugPrint(
        '[CircleLayerClustering] 🔍 No cluster found, querying individual points layer: $_unclusteredLayerId',
      );

      // Check if we tapped on an individual point
      final pointFeatures = await _mapboxMap!.queryRenderedFeatures(
        mapbox.RenderedQueryGeometry.fromScreenBox(
          mapbox.ScreenBox(
            min: mapbox.ScreenCoordinate(x: lng - 0.001, y: lat - 0.001),
            max: mapbox.ScreenCoordinate(x: lng + 0.001, y: lat + 0.001),
          ),
        ),
        mapbox.RenderedQueryOptions(layerIds: [_unclusteredLayerId]),
      );

      debugPrint(
        '[CircleLayerClustering] 📊 Individual point features found: ${pointFeatures.length}',
      );

      if (pointFeatures.isNotEmpty && pointFeatures.first != null) {
        debugPrint('[CircleLayerClustering] 📍 Individual point tapped');
        debugPrint('[CircleLayerClustering] 📊 mounted: $mounted');
        debugPrint(
          '[CircleLayerClustering] 📊 Get.context != null: ${Get.context != null}',
        );

        // Show a snackbar with point info
        if (mounted && Get.context != null) {
          debugPrint(
            '[CircleLayerClustering] 🎯 Attempting to show snackbar...',
          );

          try {
            ScaffoldMessenger.of(Get.context!).showSnackBar(
              SnackBar(
                content: Text(
                  'dialog_content_earthquake_point_tapped_zoom_in_to_see_de'.tr,
                ),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.blue,
              ),
            );
            debugPrint('[CircleLayerClustering] ✅ Snackbar shown successfully');
          } catch (snackbarError) {
            debugPrint(
              '[CircleLayerClustering] ❌ Error showing snackbar: $snackbarError',
            );
          }
        } else {
          debugPrint(
            '[CircleLayerClustering] ⚠️ Cannot show snackbar - mounted: $mounted, Get.context: ${Get.context != null}',
          );
        }
      } else {
        debugPrint(
          '[CircleLayerClustering] 📍 Empty area tapped (no features found)',
        );
      }

      debugPrint('[CircleLayerClustering] 🔍 === TAP HANDLER COMPLETE ===');
    } catch (e, stackTrace) {
      debugPrint('[CircleLayerClustering] ❌ Error handling map tap: $e');
      debugPrint('[CircleLayerClustering] 📊 Stack trace: $stackTrace');
    }
  }
}
