import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Uint8List;
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Position;
import 'package:spacetime/app/modules/map/views/mini_widgets/click_listener.dart';
import 'package:spacetime/app/routes/app_pages.dart';

import '../views/mini_widgets/bottom_info.dart';
import '../../add_memories/controllers/add_memories_controller.dart';

import '../../../../services/memory_clustering_service.dart';
import '../../../../services/background_tile_download_service.dart';
import '../../../../services/connectivity_service.dart';
import '../../../../services/permission_service.dart';
import '../../../services/memory_db.dart';

/// Map initialization states for sequential flow
enum MapInitializationState {
  initial, // Starting state
  checkingPermission, // Checking/requesting location permission
  permissionDenied, // Permission denied, show permission screen
  checkingInternet, // Checking internet connectivity
  internetRequired, // No internet and no offline tiles, show internet screen
  downloadingTiles, // Downloading map tiles
  loadingMap, // Loading map with tiles
  ready, // Map is ready and functional
  error, // Error state
}

class MapController extends GetxController with WidgetsBindingObserver {
  mapbox.MapboxMap? mapController;
  mapbox.PointAnnotationManager? currentAnnotationManager;

  final annotations = <mapbox.PointAnnotation>[].obs;
  var isFilterOpen = false.obs;
  var hasInitialized = false.obs;
  var isShowingNewLocations = false.obs;
  var currentZoom = 0.3.obs;
  var isMapReady = false.obs;
  var isRefreshing = false.obs;
  var isOfflineMode = false.obs;

  // Sequential state management
  var currentInitializationState = MapInitializationState.initial.obs;
  var isProcessingStateChange = false.obs;
  var stateChangeMessage = ''.obs;

  // Legacy variables (keeping for compatibility)
  var needsInternetConnection = false.obs;
  var isFirstTimeLoad = true.obs;
  var hasOfflineTiles = false.obs;
  var isConnectivityChecking = false.obs;
  var shouldShowInternetScreen = false.obs;

  // User's current location for initial map center
  var userCurrentLocation = mapbox.Position(0, 0).obs;

  // Predefined colors for memory markers (20 colors)
  final List<Color> markerColors = [
    const Color(0xFF2196F3), // Blue
    const Color(0xFF4CAF50), // Green
    const Color(0xFFFF9800), // Orange
    const Color(0xFF9C27B0), // Purple
    const Color(0xFFF44336), // Red
    const Color(0xFF00BCD4), // Cyan
    const Color(0xFFFFEB3B), // Yellow
    const Color(0xFF795548), // Brown
    const Color(0xFF607D8B), // Blue Grey
    const Color(0xFFE91E63), // Pink
    const Color(0xFF3F51B5), // Indigo
    const Color(0xFF009688), // Teal
    const Color(0xFFFF5722), // Deep Orange
    const Color(0xFF8BC34A), // Light Green
    const Color(0xFFCDDC39), // Lime
    const Color(0xFFFFC107), // Amber
    const Color(0xFF673AB7), // Deep Purple
    const Color(0xFF00E676), // Green Accent
    const Color(0xFFFF1744), // Red Accent
    const Color(0xFF2979FF), // Blue Accent
  ];

  // Base year for color mapping (current year)
  final int baseYear = DateTime.now().year;

  /// Get color for a specific year
  /// Maps years to colors in a repeating cycle of 20 colors
  /// Covers past 50 years and next 50 years from current year
  Color getColorForYear(int year) {
    // Calculate the difference from base year
    final yearDifference = year - baseYear;

    // Map to a positive index within our 20-color range
    // This ensures consistent color mapping for the same year
    final colorIndex = (yearDifference % markerColors.length).abs();

    return markerColors[colorIndex];
  }

  /// Get all year-color mappings for a range of years
  /// Useful for displaying color legends or year filters
  Map<int, Color> getYearColorMappings({
    int startYear = -50,
    int endYear = 50,
  }) {
    final Map<int, Color> yearColorMap = {};

    for (int i = startYear; i <= endYear; i++) {
      final year = baseYear + i;
      yearColorMap[year] = getColorForYear(year);
    }

    return yearColorMap;
  }

  /// Get years that use a specific color
  /// Useful for filtering memories by color
  List<int> getYearsForColor(
    Color color, {
    int startYear = -50,
    int endYear = 50,
  }) {
    final List<int> years = [];

    for (int i = startYear; i <= endYear; i++) {
      final year = baseYear + i;
      if (getColorForYear(year) == color) {
        years.add(year);
      }
    }

    return years;
  }

  /// Get color index for a year (0-19)
  /// Useful for consistent indexing
  int getColorIndexForYear(int year) {
    final yearDifference = year - baseYear;
    return (yearDifference % markerColors.length).abs();
  }
  // COMMENTED OUT: Hardcoded visit counts
  // final List<int> visitCounts = [32, 12, 9, 4, 17];

  // Memory clustering variables
  final RxList<Map<String, dynamic>> allMemories = <Map<String, dynamic>>[].obs;
  final RxList<MemoryCluster> currentClusters = <MemoryCluster>[].obs;
  final RxList<ChronologicalArrow> currentArrows = <ChronologicalArrow>[].obs;
  final Rx<ClusterLevel> currentClusterLevel = ClusterLevel.initial.obs;
  final Rxn<MemoryCluster> selectedCluster = Rxn<MemoryCluster>();
  final RxBool isLoadingMemories = false.obs;
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  final fromDate = ''.obs;
  final toDate = ''.obs;
  final locationRadius = ''.obs;
  final placeSearch = ''.obs;
  final hashtagSearch = ''.obs;
  final contactSearch = ''.obs;
  final selectedLocation = ''.obs;

  final RxMap<String, String> filterValues = <String, String>{}.obs;

  final StreamController<double> stylePackProgress =
      StreamController.broadcast();
  final StreamController<double> tileRegionLoadProgress =
      StreamController.broadcast();

  TileStore? tileStore;
  OfflineManager? offlineManager;
  final tileRegionId = "my-tile-region";

  void setFilterDate(String hint, String date) {
    filterValues[hint] = date;
  }

  Future<void> initOfflineMap() async {
    try {
      print(
        '[MapController][initOfflineMap]: Initializing offline map components',
      );
      offlineManager = await OfflineManager.create();
      tileStore = await TileStore.createDefault();
      tileStore?.setDiskQuota(
        null,
      ); // Reset to default (setDiskQuota returns void)
      print(
        '[MapController][initOfflineMap]: Offline map components initialized successfully',
      );
    } catch (e) {
      print(
        '[MapController][initOfflineMap]: Error initializing offline map: $e',
      );
    }
  }

  Future<void> downloadStylePack() async {
    try {
      print('[MapController][downloadStylePack]: Starting style pack download');

      final stylePackLoadOptions = StylePackLoadOptions(
        glyphsRasterizationMode:
            GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
        metadata: {"tag": "offline"},
        acceptExpired: false,
      );

      await offlineManager
          ?.loadStylePack(
            MapboxStyles.MAPBOX_STREETS, // Change style if needed
            stylePackLoadOptions,
            (progress) {
              final percentage =
                  progress.completedResourceCount /
                  progress.requiredResourceCount;
              print(
                '[MapController][downloadStylePack]: Style pack progress: ${(percentage * 100).toStringAsFixed(1)}%',
              );
              if (!stylePackProgress.isClosed) {
                stylePackProgress.sink.add(percentage);
              }
            },
          )
          .then((_) {
            print(
              '[MapController][downloadStylePack]: Style pack download completed',
            );
            if (!stylePackProgress.isClosed) {
              stylePackProgress.sink.add(1.0);
              stylePackProgress.close();
            }
          });
    } catch (e) {
      print(
        '[MapController][downloadStylePack]: Error downloading style pack: $e',
      );
      if (!stylePackProgress.isClosed) {
        stylePackProgress.sink.addError(e);
        stylePackProgress.close();
      }
    }
  }

  Future<void> downloadTileRegion() async {
    try {
      print(
        '[MapController][downloadTileRegion]: Starting tile region download with 50,000 tile capacity',
      );

      // Get user's current location for a larger, more useful region
      final userPosition = await _getUserCurrentPosition();

      if (userPosition == null) {
        print(
          '[MapController][downloadTileRegion]: No user position available, using default region',
        );
        await _downloadLargeDefaultRegion();
        return;
      }

      print(
        '[MapController][downloadTileRegion]: User position: ${userPosition.latitude}, ${userPosition.longitude}',
      );

      // Create a larger region around user - we can now handle up to 50,000 tiles
      // Each degree is ~111km, so 0.1 degrees ≈ 11km radius (much more useful coverage)
      final regionSize = 0.1; // ~11km radius - good coverage for daily use

      final bounds = mapbox.CoordinateBounds(
        southwest: mapbox.Point(
          coordinates: mapbox.Position(
            userPosition.longitude - regionSize,
            userPosition.latitude - regionSize,
          ),
        ),
        northeast: mapbox.Point(
          coordinates: mapbox.Position(
            userPosition.longitude + regionSize,
            userPosition.latitude + regionSize,
          ),
        ),
        infiniteBounds: false,
      );

      // Use more zoom levels for better detail - we have 50,000 tile capacity
      final zoomLevels = [10, 11, 12, 13, 14];

      print(
        '[MapController][downloadTileRegion]: Downloading region with zoom levels: $zoomLevels',
      );

      // Estimate tiles before downloading
      final estimatedTiles = _estimateTileCount(bounds, zoomLevels);
      print(
        '[MapController][downloadTileRegion]: Estimated tiles: $estimatedTiles',
      );

      // Check if we need to chunk the region
      if (estimatedTiles > 45000) {
        // Leave some buffer below 50,000
        print(
          '[MapController][downloadTileRegion]: Large region ($estimatedTiles tiles), using chunked download',
        );
        await _downloadLargeRegionInChunks(bounds, zoomLevels, estimatedTiles);
      } else if (estimatedTiles > 700) {
        // Larger than single region limit but under total limit
        print(
          '[MapController][downloadTileRegion]: Medium region ($estimatedTiles tiles), splitting into sub-regions',
        );
        final downloadService = Get.find<BackgroundTileDownloadService>();
        await downloadService.downloadLargeRegion(bounds, zoomLevels);
      } else {
        print(
          '[MapController][downloadTileRegion]: Small region ($estimatedTiles tiles), single download',
        );
        final downloadService = Get.find<BackgroundTileDownloadService>();
        await downloadService.downloadRegion(bounds, zoomLevels);
      }

      print(
        '[MapController][downloadTileRegion]: Tile region download completed',
      );
    } catch (e) {
      print(
        '[MapController][downloadTileRegion]: Error downloading tile region: $e',
      );
      // Fallback to a smaller region
      await _downloadMediumFallbackRegion();
    }
  }

  /// Get user's current position with error handling
  Future<geolocator.Position?> _getUserCurrentPosition() async {
    try {
      print(
        '[MapController][_getUserCurrentPosition]: Getting user current position',
      );

      // Check if location services are enabled
      bool serviceEnabled =
          await geolocator.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print(
          '[MapController][_getUserCurrentPosition]: Location services are disabled',
        );
        return null;
      }

      // Check permissions
      geolocator.LocationPermission permission =
          await geolocator.Geolocator.checkPermission();
      if (permission == geolocator.LocationPermission.denied) {
        permission = await geolocator.Geolocator.requestPermission();
        if (permission == geolocator.LocationPermission.denied) {
          print(
            '[MapController][_getUserCurrentPosition]: Location permissions are denied',
          );
          return null;
        }
      }

      if (permission == geolocator.LocationPermission.deniedForever) {
        print(
          '[MapController][_getUserCurrentPosition]: Location permissions are permanently denied',
        );
        return null;
      }

      // Get current position with timeout
      final position = await geolocator.Geolocator.getCurrentPosition(
        locationSettings: geolocator.LocationSettings(
          accuracy: geolocator.LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );

      print(
        '[MapController][_getUserCurrentPosition]: Got position: ${position.latitude}, ${position.longitude}',
      );
      return position;
    } catch (e) {
      print(
        '[MapController][_getUserCurrentPosition]: Error getting position: $e',
      );
      return null;
    }
  }

  /// Download a larger default region (San Francisco Bay Area) when user location is unavailable
  Future<void> _downloadLargeDefaultRegion() async {
    try {
      print(
        '[MapController][_downloadLargeDefaultRegion]: Downloading large default region (San Francisco Bay Area)',
      );

      // San Francisco Bay Area - larger region for better coverage
      final bounds = mapbox.CoordinateBounds(
        southwest: mapbox.Point(
          coordinates: mapbox.Position(-122.6, 37.6), // SW corner
        ),
        northeast: mapbox.Point(
          coordinates: mapbox.Position(-122.2, 37.9), // NE corner
        ),
        infiniteBounds: false,
      );

      // More zoom levels for better detail
      final zoomLevels = [10, 11, 12, 13];

      // Estimate tiles and decide on download strategy
      final estimatedTiles = _estimateTileCount(bounds, zoomLevels);
      print(
        '[MapController][_downloadLargeDefaultRegion]: Estimated tiles: $estimatedTiles',
      );

      final downloadService = Get.find<BackgroundTileDownloadService>();

      if (estimatedTiles > 700) {
        // Use chunked download for large regions
        await downloadService.downloadLargeRegion(bounds, zoomLevels);
      } else {
        // Single region download
        await downloadService.downloadRegion(bounds, zoomLevels);
      }

      print(
        '[MapController][_downloadLargeDefaultRegion]: Large default region download completed',
      );
    } catch (e) {
      print(
        '[MapController][_downloadLargeDefaultRegion]: Error downloading large default region: $e',
      );
      // Fallback to smaller region
      await _downloadDefaultSmallRegion();
    }
  }

  /// Download a default small region (San Francisco area) when user location is unavailable
  Future<void> _downloadDefaultSmallRegion() async {
    try {
      print(
        '[MapController][_downloadDefaultSmallRegion]: Downloading default small region (San Francisco)',
      );

      // San Francisco downtown - small region
      final bounds = mapbox.CoordinateBounds(
        southwest: mapbox.Point(
          coordinates: mapbox.Position(-122.45, 37.75), // SW corner
        ),
        northeast: mapbox.Point(
          coordinates: mapbox.Position(-122.35, 37.85), // NE corner
        ),
        infiniteBounds: false,
      );

      // Limited zoom levels
      final zoomLevels = [10, 11, 12];

      final downloadService = Get.find<BackgroundTileDownloadService>();
      await downloadService.downloadRegion(bounds, zoomLevels);

      print(
        '[MapController][_downloadDefaultSmallRegion]: Default region download completed',
      );
    } catch (e) {
      print(
        '[MapController][_downloadDefaultSmallRegion]: Error downloading default region: $e',
      );
    }
  }

  /// Download large region in chunks to stay within 50,000 tile limit
  Future<void> _downloadLargeRegionInChunks(
    mapbox.CoordinateBounds bounds,
    List<int> zoomLevels,
    int estimatedTiles,
  ) async {
    try {
      print(
        '[MapController][_downloadLargeRegionInChunks]: Downloading large region in chunks (estimated: $estimatedTiles tiles)',
      );

      // Calculate how many chunks we need to stay under 45,000 tiles per chunk
      final maxTilesPerChunk = 45000;
      final chunksNeeded = (estimatedTiles / maxTilesPerChunk).ceil();
      final gridSize = math.sqrt(chunksNeeded).ceil();

      print(
        '[MapController][_downloadLargeRegionInChunks]: Splitting into ${gridSize}x${gridSize} grid ($chunksNeeded chunks)',
      );

      // Split the bounds into smaller chunks
      final chunks = _splitBoundsIntoChunks(bounds, gridSize, gridSize);

      final downloadService = Get.find<BackgroundTileDownloadService>();

      // Download each chunk separately
      for (int i = 0; i < chunks.length && i < chunksNeeded; i++) {
        final chunkBounds = chunks[i];
        final chunkTiles = _estimateTileCount(chunkBounds, zoomLevels);

        print(
          '[MapController][_downloadLargeRegionInChunks]: Downloading chunk ${i + 1}/${chunksNeeded} (estimated: $chunkTiles tiles)',
        );

        if (chunkTiles > 700) {
          // Use large region download for chunks that need sub-division
          await downloadService.downloadLargeRegion(chunkBounds, zoomLevels);
        } else {
          // Direct download for smaller chunks
          await downloadService.downloadRegion(chunkBounds, zoomLevels);
        }

        // Small delay between chunks to avoid overwhelming the system
        await Future.delayed(Duration(seconds: 2));
      }

      print(
        '[MapController][_downloadLargeRegionInChunks]: Large region chunked download completed',
      );
    } catch (e) {
      print(
        '[MapController][_downloadLargeRegionInChunks]: Error downloading large region in chunks: $e',
      );
    }
  }

  /// Download a medium-sized fallback region
  Future<void> _downloadMediumFallbackRegion() async {
    try {
      print(
        '[MapController][_downloadMediumFallbackRegion]: Downloading medium fallback region',
      );

      // Medium region around San Francisco
      final bounds = mapbox.CoordinateBounds(
        southwest: mapbox.Point(
          coordinates: mapbox.Position(-122.5, 37.7), // SW corner
        ),
        northeast: mapbox.Point(
          coordinates: mapbox.Position(-122.3, 37.8), // NE corner
        ),
        infiniteBounds: false,
      );

      // Moderate zoom levels
      final zoomLevels = [10, 11, 12];

      final downloadService = Get.find<BackgroundTileDownloadService>();
      await downloadService.downloadLargeRegion(bounds, zoomLevels);

      print(
        '[MapController][_downloadMediumFallbackRegion]: Medium fallback region download completed',
      );
    } catch (e) {
      print(
        '[MapController][_downloadMediumFallbackRegion]: Error downloading medium fallback region: $e',
      );
      // Final fallback to tiny region
      await _downloadFallbackTinyRegion();
    }
  }

  /// Download a very tiny region as last resort fallback
  Future<void> _downloadFallbackTinyRegion() async {
    try {
      print(
        '[MapController][_downloadFallbackTinyRegion]: Downloading tiny fallback region',
      );

      // Extremely small region around San Francisco downtown
      final bounds = mapbox.CoordinateBounds(
        southwest: mapbox.Point(
          coordinates: mapbox.Position(-122.415, 37.775), // SW corner
        ),
        northeast: mapbox.Point(
          coordinates: mapbox.Position(-122.405, 37.785), // NE corner
        ),
        infiniteBounds: false,
      );

      // Minimal zoom levels for maximum safety
      final zoomLevels = [10];

      final downloadService = Get.find<BackgroundTileDownloadService>();
      await downloadService.downloadRegion(bounds, zoomLevels);

      print(
        '[MapController][_downloadFallbackTinyRegion]: Tiny fallback region download completed',
      );
    } catch (e) {
      print(
        '[MapController][_downloadFallbackTinyRegion]: Error downloading tiny fallback region: $e',
      );
    }
  }

  /// Split coordinate bounds into smaller chunks for large region downloads
  List<mapbox.CoordinateBounds> _splitBoundsIntoChunks(
    mapbox.CoordinateBounds bounds,
    int gridWidth,
    int gridHeight,
  ) {
    try {
      print(
        '[MapController][_splitBoundsIntoChunks]: Splitting bounds into ${gridWidth}x${gridHeight} chunks',
      );

      final chunks = <mapbox.CoordinateBounds>[];

      // Get the original bounds
      final sw = bounds.southwest.coordinates;
      final ne = bounds.northeast.coordinates;

      // Calculate the size of each chunk
      final latStep = (ne.lat - sw.lat) / gridHeight;
      final lngStep = (ne.lng - sw.lng) / gridWidth;

      print(
        '[MapController][_splitBoundsIntoChunks]: Original bounds: SW(${sw.lng}, ${sw.lat}) NE(${ne.lng}, ${ne.lat})',
      );
      print(
        '[MapController][_splitBoundsIntoChunks]: Chunk size: lat=$latStep, lng=$lngStep',
      );

      // Create chunks
      for (int row = 0; row < gridHeight; row++) {
        for (int col = 0; col < gridWidth; col++) {
          final chunkSW = mapbox.Position(
            sw.lng + (col * lngStep),
            sw.lat + (row * latStep),
          );

          final chunkNE = mapbox.Position(
            sw.lng + ((col + 1) * lngStep),
            sw.lat + ((row + 1) * latStep),
          );

          final chunkBounds = mapbox.CoordinateBounds(
            southwest: mapbox.Point(coordinates: chunkSW),
            northeast: mapbox.Point(coordinates: chunkNE),
            infiniteBounds: false,
          );

          chunks.add(chunkBounds);

          print(
            '[MapController][_splitBoundsIntoChunks]: Chunk ${chunks.length}: SW(${chunkSW.lng}, ${chunkSW.lat}) NE(${chunkNE.lng}, ${chunkNE.lat})',
          );
        }
      }

      print(
        '[MapController][_splitBoundsIntoChunks]: Created ${chunks.length} chunks',
      );
      return chunks;
    } catch (e) {
      print(
        '[MapController][_splitBoundsIntoChunks]: Error splitting bounds: $e',
      );
      // Return original bounds as single chunk if splitting fails
      return [bounds];
    }
  }

  /// Estimate tile count for a region to prevent exceeding Mapbox limits
  int _estimateTileCount(mapbox.CoordinateBounds bounds, List<int> zoomLevels) {
    try {
      print(
        '[MapController][_estimateTileCount]: Estimating tiles for bounds and zoom levels: $zoomLevels',
      );

      // Get the coordinate bounds
      final sw = bounds.southwest.coordinates;
      final ne = bounds.northeast.coordinates;

      // Calculate the area in degrees
      final latDiff = (ne.lat - sw.lat).abs();
      final lngDiff = (ne.lng - sw.lng).abs();

      print(
        '[MapController][_estimateTileCount]: Area - lat: $latDiff, lng: $lngDiff',
      );

      int totalTiles = 0;

      for (final zoom in zoomLevels) {
        // More accurate tile calculation for Mapbox
        // At zoom level z, there are 2^z tiles per side of the world
        final tilesPerSide = math.pow(2, zoom);

        // Calculate tile coordinates for the bounds
        final minTileX = ((sw.lng + 180.0) / 360.0 * tilesPerSide).floor();
        final maxTileX = ((ne.lng + 180.0) / 360.0 * tilesPerSide).floor();
        final minTileY =
            ((1.0 -
                        math.log(
                              math.tan(sw.lat * math.pi / 180.0) +
                                  1.0 / math.cos(sw.lat * math.pi / 180.0),
                            ) /
                            math.pi) /
                    2.0 *
                    tilesPerSide)
                .floor();
        final maxTileY =
            ((1.0 -
                        math.log(
                              math.tan(ne.lat * math.pi / 180.0) +
                                  1.0 / math.cos(ne.lat * math.pi / 180.0),
                            ) /
                            math.pi) /
                    2.0 *
                    tilesPerSide)
                .floor();

        final tilesInX = (maxTileX - minTileX + 1).abs();
        final tilesInY = (maxTileY - minTileY + 1).abs();
        final tilesAtZoom = tilesInX * tilesInY;

        totalTiles += tilesAtZoom;
        print(
          '[MapController][_estimateTileCount]: Zoom $zoom: ${tilesInX}x${tilesInY} = $tilesAtZoom tiles',
        );
      }

      print(
        '[MapController][_estimateTileCount]: Total estimated tiles: $totalTiles',
      );

      // Add 10% buffer for safety
      final bufferedTiles = (totalTiles * 1.1).round();
      print(
        '[MapController][_estimateTileCount]: With 10% buffer: $bufferedTiles tiles',
      );

      return bufferedTiles;
    } catch (e) {
      print('[MapController][_estimateTileCount]: Error estimating tiles: $e');
      // Return a conservative estimate
      return 5000;
    }
  }

  Future<void> removeOfflineResources() async {
    try {
      print(
        '[MapController][removeOfflineResources]: Removing offline resources',
      );
      await tileStore?.removeRegion(tileRegionId);
      tileStore?.setDiskQuota(0); // setDiskQuota returns void, no await needed
      await offlineManager?.removeStylePack(MapboxStyles.MAPBOX_STREETS);
      print(
        '[MapController][removeOfflineResources]: Offline resources removed successfully',
      );
    } catch (e) {
      print(
        '[MapController][removeOfflineResources]: Error removing offline resources: $e',
      );
    }
  }

  // Comprehensive method to set up offline functionality
  Future<void> setupOfflineMap() async {
    try {
      print(
        '[MapController][setupOfflineMap]: Setting up complete offline functionality',
      );

      // Step 1: Initialize offline components
      await initOfflineMap();

      // Step 2: Download style pack
      await downloadStylePack();

      // Step 3: Download tile region based on user location
      await downloadTileRegion();

      print(
        '[MapController][setupOfflineMap]: Complete offline setup finished successfully',
      );
    } catch (e) {
      print(
        '[MapController][setupOfflineMap]: Error in complete offline setup: $e',
      );
    }
  }

  // Download tiles for a specific region manually
  Future<void> downloadTilesForRegion(String regionName) async {
    try {
      print(
        '[MapController][downloadTilesForRegion]: Downloading tiles for specific region: $regionName',
      );

      Map<String, dynamic> regionData;

      switch (regionName.toLowerCase()) {
        case 'asia':
          regionData = {
            'name': 'Asia',
            'geometry': {
              "type": "Polygon",
              "coordinates": [
                [
                  [60, -10],
                  [150, -10],
                  [150, 55],
                  [60, 55],
                  [60, -10],
                ],
              ],
            },
          };
          break;
        case 'europe':
          regionData = {
            'name': 'Europe',
            'geometry': {
              "type": "Polygon",
              "coordinates": [
                [
                  [-25, 35],
                  [45, 35],
                  [45, 75],
                  [-25, 75],
                  [-25, 35],
                ],
              ],
            },
          };
          break;
        case 'north america':
          regionData = {
            'name': 'North America',
            'geometry': {
              "type": "Polygon",
              "coordinates": [
                [
                  [-170, 15],
                  [-50, 15],
                  [-50, 75],
                  [-170, 75],
                  [-170, 15],
                ],
              ],
            },
          };
          break;
        case 'south america':
          regionData = {
            'name': 'South America',
            'geometry': {
              "type": "Polygon",
              "coordinates": [
                [
                  [-85, -60],
                  [-30, -60],
                  [-30, 15],
                  [-85, 15],
                  [-85, -60],
                ],
              ],
            },
          };
          break;
        case 'africa':
          regionData = {
            'name': 'Africa',
            'geometry': {
              "type": "Polygon",
              "coordinates": [
                [
                  [-20, -40],
                  [55, -40],
                  [55, 40],
                  [-20, 40],
                  [-20, -40],
                ],
              ],
            },
          };
          break;
        case 'oceania':
          regionData = {
            'name': 'Oceania',
            'geometry': {
              "type": "Polygon",
              "coordinates": [
                [
                  [110, -50],
                  [180, -50],
                  [180, -5],
                  [110, -5],
                  [110, -50],
                ],
              ],
            },
          };
          break;
        default:
          throw Exception('Unknown region: $regionName');
      }

      final tileOptions = TileRegionLoadOptions(
        geometry: regionData['geometry'],
        descriptorsOptions: [
          TilesetDescriptorOptions(
            styleURI: MapboxStyles.MAPBOX_STREETS,
            minZoom: 6,
            maxZoom: 14,
          ),
        ],
        acceptExpired: true,
        networkRestriction: NetworkRestriction.NONE,
      );

      await tileStore?.loadTileRegion(
        "${tileRegionId}_${regionName.toLowerCase().replaceAll(' ', '_')}",
        tileOptions,
        (progress) {
          final percentage =
              progress.completedResourceCount / progress.requiredResourceCount;
          debugPrint(
            '🗺 OFFLINE - $regionName tiles progress: ${(percentage * 100).toStringAsFixed(1)}%',
          );
          if (!tileRegionLoadProgress.isClosed) {
            tileRegionLoadProgress.sink.add(percentage);
          }
        },
      );

      debugPrint('🗺 OFFLINE - $regionName tiles download completed');
    } catch (e) {
      debugPrint('❌ OFFLINE - Error downloading tiles for $regionName: $e');
    }
  }

  // Get user's region bounds for downloading appropriate tiles
  Future<Map<String, dynamic>> _getUserRegionBounds() async {
    try {
      // Try to get user's current location
      geolocator.Position? userPosition;

      try {
        userPosition = await geolocator.Geolocator.getCurrentPosition(
          locationSettings: geolocator.LocationSettings(
            accuracy: geolocator.LocationAccuracy.low,
            timeLimit: Duration(seconds: 10),
          ),
        );
        debugPrint(
          '🗺 OFFLINE - Got user location: ${userPosition.latitude}, ${userPosition.longitude}',
        );
      } catch (e) {
        debugPrint('🗺 OFFLINE - Could not get user location: $e');
        // Fallback to a default region (you can customize this)
        userPosition = null;
      }

      // Determine region based on user's location
      if (userPosition != null) {
        return _getRegionForCoordinates(
          userPosition.latitude,
          userPosition.longitude,
        );
      } else {
        // Fallback to a default region (Global/World coverage)
        debugPrint('🗺 OFFLINE - Using default global region');
        return {
          'name': 'Global',
          'geometry': {
            "type": "Polygon",
            "coordinates": [
              [
                [-180, -85], // Southwest
                [180, -85], // Southeast
                [180, 85], // Northeast
                [-180, 85], // Northwest
                [-180, -85], // Close polygon
              ],
            ],
          },
        };
      }
    } catch (e) {
      debugPrint('❌ OFFLINE - Error getting user region bounds: $e');
      // Return a safe default
      return {
        'name': 'Default',
        'geometry': {
          "type": "Point",
          "coordinates": [0, 0],
        },
      };
    }
  }

  // Determine region/subcontinent based on coordinates
  Map<String, dynamic> _getRegionForCoordinates(double lat, double lng) {
    debugPrint('🗺 OFFLINE - Determining region for coordinates: $lat, $lng');

    // Asia regions
    if (lat >= -10 && lat <= 55 && lng >= 60 && lng <= 150) {
      if (lat >= 8 && lat <= 37 && lng >= 68 && lng <= 97) {
        // South Asia (India, Pakistan, Bangladesh, etc.)
        return {
          'name': 'South Asia',
          'geometry': {
            "type": "Polygon",
            "coordinates": [
              [
                [68, 8], // Southwest
                [97, 8], // Southeast
                [97, 37], // Northeast
                [68, 37], // Northwest
                [68, 8], // Close polygon
              ],
            ],
          },
        };
      } else if (lat >= 15 && lat <= 50 && lng >= 100 && lng <= 145) {
        // East Asia (China, Japan, Korea, etc.)
        return {
          'name': 'East Asia',
          'geometry': {
            "type": "Polygon",
            "coordinates": [
              [
                [100, 15], // Southwest
                [145, 15], // Southeast
                [145, 50], // Northeast
                [100, 50], // Northwest
                [100, 15], // Close polygon
              ],
            ],
          },
        };
      } else if (lat >= -10 && lat <= 25 && lng >= 95 && lng <= 140) {
        // Southeast Asia
        return {
          'name': 'Southeast Asia',
          'geometry': {
            "type": "Polygon",
            "coordinates": [
              [
                [95, -10], // Southwest
                [140, -10], // Southeast
                [140, 25], // Northeast
                [95, 25], // Northwest
                [95, -10], // Close polygon
              ],
            ],
          },
        };
      } else {
        // General Asia
        return {
          'name': 'Asia',
          'geometry': {
            "type": "Polygon",
            "coordinates": [
              [
                [60, -10], // Southwest
                [150, -10], // Southeast
                [150, 55], // Northeast
                [60, 55], // Northwest
                [60, -10], // Close polygon
              ],
            ],
          },
        };
      }
    }
    // Europe
    else if (lat >= 35 && lat <= 75 && lng >= -25 && lng <= 45) {
      return {
        'name': 'Europe',
        'geometry': {
          "type": "Polygon",
          "coordinates": [
            [
              [-25, 35], // Southwest
              [45, 35], // Southeast
              [45, 75], // Northeast
              [-25, 75], // Northwest
              [-25, 35], // Close polygon
            ],
          ],
        },
      };
    }
    // North America
    else if (lat >= 15 && lat <= 75 && lng >= -170 && lng <= -50) {
      return {
        'name': 'North America',
        'geometry': {
          "type": "Polygon",
          "coordinates": [
            [
              [-170, 15], // Southwest
              [-50, 15], // Southeast
              [-50, 75], // Northeast
              [-170, 75], // Northwest
              [-170, 15], // Close polygon
            ],
          ],
        },
      };
    }
    // South America
    else if (lat >= -60 && lat <= 15 && lng >= -85 && lng <= -30) {
      return {
        'name': 'South America',
        'geometry': {
          "type": "Polygon",
          "coordinates": [
            [
              [-85, -60], // Southwest
              [-30, -60], // Southeast
              [-30, 15], // Northeast
              [-85, 15], // Northwest
              [-85, -60], // Close polygon
            ],
          ],
        },
      };
    }
    // Africa
    else if (lat >= -40 && lat <= 40 && lng >= -20 && lng <= 55) {
      return {
        'name': 'Africa',
        'geometry': {
          "type": "Polygon",
          "coordinates": [
            [
              [-20, -40], // Southwest
              [55, -40], // Southeast
              [55, 40], // Northeast
              [-20, 40], // Northwest
              [-20, -40], // Close polygon
            ],
          ],
        },
      };
    }
    // Oceania
    else if (lat >= -50 && lat <= -5 && lng >= 110 && lng <= 180) {
      return {
        'name': 'Oceania',
        'geometry': {
          "type": "Polygon",
          "coordinates": [
            [
              [110, -50], // Southwest
              [180, -50], // Southeast
              [180, -5], // Northeast
              [110, -5], // Northwest
              [110, -50], // Close polygon
            ],
          ],
        },
      };
    }
    // Default fallback - create a country-sized region around the point
    else {
      debugPrint(
        '🗺 OFFLINE - Using country-sized region around user location',
      );
      return {
        'name': 'Local Region',
        'geometry': {
          "type": "Polygon",
          "coordinates": [
            [
              [lng - 5, lat - 5], // Southwest (roughly 500km radius)
              [lng + 5, lat - 5], // Southeast
              [lng + 5, lat + 5], // Northeast
              [lng - 5, lat + 5], // Northwest
              [lng - 5, lat - 5], // Close polygon
            ],
          ],
        },
      };
    }
  }

  // Check if offline resources are available
  Future<bool> isOfflineDataAvailable() async {
    try {
      if (tileStore == null || offlineManager == null) {
        debugPrint('🗺 OFFLINE - Offline components not initialized');
        return false;
      }

      // Check if we actually have downloaded tiles
      final hasDownloadedTiles = await _hasDownloadedTiles();
      debugPrint(
        '🗺 OFFLINE - Components initialized: true, Downloaded tiles: $hasDownloadedTiles',
      );

      return hasDownloadedTiles;
    } catch (e) {
      debugPrint('❌ OFFLINE - Error checking offline data availability: $e');
      return false;
    }
  }

  /// Check if maps are currently in offline mode
  /// This checks both downloaded tiles and network connectivity
  Future<bool> isMapInOfflineMode() async {
    try {
      debugPrint('🗺 OFFLINE - Checking if maps are in offline mode');

      // Check 1: Are offline components initialized?
      if (tileStore == null || offlineManager == null) {
        debugPrint(
          '🗺 OFFLINE - Offline components not initialized, not in offline mode',
        );
        return false;
      }

      // Check 2: Do we have downloaded tiles?
      final hasDownloadedTiles = await _hasDownloadedTiles();
      if (!hasDownloadedTiles) {
        debugPrint(
          '🗺 OFFLINE - No downloaded tiles found, not in offline mode',
        );
        return false;
      }

      // Check 3: Is the background service forcing offline mode?
      final backgroundService = Get.find<BackgroundTileDownloadService>();
      if (backgroundService.forceOfflineMode.value) {
        debugPrint('🗺 OFFLINE - Background service is forcing offline mode');
        return true;
      }

      // Check 4: Network connectivity (optional - maps can work offline even with network)
      // This is more about whether we're actively using offline resources
      final isUsingOfflineResources = await _isUsingOfflineResources();

      debugPrint(
        '🗺 OFFLINE - Maps offline mode status: $isUsingOfflineResources',
      );
      return isUsingOfflineResources;
    } catch (e) {
      debugPrint('❌ OFFLINE - Error checking offline mode: $e');
      return false;
    }
  }

  /// Check if we have downloaded tiles available (50,000+ tiles threshold)
  Future<bool> _hasDownloadedTiles() async {
    try {
      if (tileStore == null) return false;

      // Check if the background service has downloaded sufficient tiles (50,000+ threshold)
      final backgroundService = Get.find<BackgroundTileDownloadService>();
      final tileCount = backgroundService.totalTilesDownloaded.value;

      debugPrint(
        '🗺 OFFLINE - Total tiles downloaded: $tileCount (threshold: 50,000)',
      );

      // Return true only if we have 50,000+ tiles for reliable offline mode
      return tileCount >= 30000;
    } catch (e) {
      debugPrint('❌ OFFLINE - Error checking downloaded tiles: $e');
      return false;
    }
  }

  /// Check if we're actively using offline resources
  Future<bool> _isUsingOfflineResources() async {
    try {
      // Check if we have offline data and it's being used
      final hasOfflineData = await isOfflineDataAvailable();
      final hasDownloadedTiles = await _hasDownloadedTiles();

      // If we have both offline components and downloaded tiles, we can use offline mode
      final canUseOffline = hasOfflineData && hasDownloadedTiles;

      debugPrint('🗺 OFFLINE - Can use offline resources: $canUseOffline');
      debugPrint('🗺 OFFLINE - Has offline data: $hasOfflineData');
      debugPrint('🗺 OFFLINE - Has downloaded tiles: $hasDownloadedTiles');

      return canUseOffline;
    } catch (e) {
      debugPrint('❌ OFFLINE - Error checking offline resource usage: $e');
      return false;
    }
  }

  /// Get detailed offline status information
  Future<Map<String, dynamic>> getOfflineStatus() async {
    try {
      final isOffline = await isMapInOfflineMode();
      final hasOfflineData = await isOfflineDataAvailable();
      final hasDownloadedTiles = await _hasDownloadedTiles();

      // Get background service status
      final backgroundService = Get.find<BackgroundTileDownloadService>();
      final tileCount = backgroundService.totalTilesDownloaded.value;
      final maxTiles = backgroundService.maxTilesLimit.value;
      final forceOffline = backgroundService.forceOfflineMode.value;
      final isDownloading = backgroundService.isDownloading.value;

      final status = {
        'isOfflineMode': isOffline,
        'hasOfflineComponents': hasOfflineData,
        'hasDownloadedTiles': hasDownloadedTiles,
        'totalTilesDownloaded': tileCount,
        'maxTilesLimit': maxTiles,
        'usagePercentage':
            tileCount > 0 ? (tileCount / maxTiles * 100).round() : 0,
        'forceOfflineMode': forceOffline,
        'isCurrentlyDownloading': isDownloading,
        'offlineComponentsInitialized':
            tileStore != null && offlineManager != null,
      };

      debugPrint('🗺 OFFLINE - Complete offline status: $status');
      return status;
    } catch (e) {
      debugPrint('❌ OFFLINE - Error getting offline status: $e');
      return {
        'isOfflineMode': false,
        'hasOfflineComponents': false,
        'hasDownloadedTiles': false,
        'error': e.toString(),
      };
    }
  }

  /// Update offline mode status and notify observers
  Future<void> updateOfflineStatus() async {
    try {
      final wasOffline = isOfflineMode.value;
      final nowOffline = await isMapInOfflineMode();

      if (wasOffline != nowOffline) {
        isOfflineMode.value = nowOffline;
        debugPrint(
          '🗺 OFFLINE - Offline mode status changed: $wasOffline -> $nowOffline',
        );

        // Notify about the change
        if (nowOffline) {
          debugPrint('🗺 OFFLINE - Maps are now running in offline mode');
        } else {
          debugPrint('🗺 OFFLINE - Maps are now running in online mode');
        }
      }
    } catch (e) {
      debugPrint('❌ OFFLINE - Error updating offline status: $e');
    }
  }

  /// Start monitoring offline mode status
  Timer? _offlineStatusTimer;

  void _startOfflineStatusMonitoring() {
    // Check offline status every 30 seconds
    _offlineStatusTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      updateOfflineStatus();
    });

    // Initial check
    updateOfflineStatus();

    debugPrint('🗺 OFFLINE - Started offline status monitoring');
  }

  /// Stop monitoring offline mode status
  void _stopOfflineStatusMonitoring() {
    _offlineStatusTimer?.cancel();
    _offlineStatusTimer = null;
    debugPrint('🗺 OFFLINE - Stopped offline status monitoring');
  }

  void onTextChanged(String hint, String value) {
    if (value.contains('@')) {
      // open mention bottom sheet
      print(
        "[MapController][onTextChanged]: Mention trigger from [$hint]: $value",
      );
    } else if (value.contains('#')) {
      // open tag bottom sheet
      print("[MapController][onTextChanged]: Tag trigger from [$hint]: $value");
    }
    filterValues[hint] = value;
  }

  void setLocation(String location) {
    selectedLocation.value = location;
    print("[MapController][setLocation]: Location set to: $location");
  }

  final RxList<mapbox.Position> locations = <mapbox.Position>[].obs;
  final List<mapbox.Position> newLocations = [];

  final List<Map<String, dynamic>> locationData = [];

  var isDetailView = false.obs;

  // Add timer for one-time recreation after controller initialization
  Timer? _oneTimeRecreationTimer;
  var _hasTriggeredRecreation = false;

  // Add flag to trigger MapWidget recreation (simulates restart)
  var shouldRecreateMap = false.obs;
  var _mapRecreationCount = 0;

  // Add flag to prevent reactive zoom during location transitions
  var _isTransitioningLocations = false;

  @override
  void onInit() {
    print('[MapController][onInit]: Entered method');
    super.onInit();
    print('[MapController][onInit]: super.onInit() completed');
    debugPrint('[MapController][onInit] Starting initialization');
    print('[MapController][onInit]: Starting initialization log printed');
    debugPrint(
      '[MapController][onInit] currentZoom.value: ${currentZoom.value}',
    );
    print(
      '[MapController][onInit]: currentZoom.value logged: ${currentZoom.value}',
    );
    debugPrint(
      '[MapController][onInit] isShowingNewLocations.value: ${isShowingNewLocations.value}',
    );
    print(
      '[MapController][onInit]: isShowingNewLocations.value logged: ${isShowingNewLocations.value}',
    );
    debugPrint('[MapController][onInit] locations count: ${locations.length}');
    print(
      '[MapController][onInit]: locations count logged: ${locations.length}',
    );
    debugPrint(
      '[MapController][onInit] hasInitialized: ${hasInitialized.value}',
    );
    print(
      '[MapController][onInit]: hasInitialized logged: ${hasInitialized.value}',
    );
    debugPrint('[MapController][onInit] isMapReady: ${isMapReady.value}');
    print('[MapController][onInit]: isMapReady logged: ${isMapReady.value}');
    debugPrint(
      '[MapController][onInit] mapController null: ${mapController == null}',
    );
    print(
      '[MapController][onInit]: mapController null status logged: ${mapController == null}',
    );
    debugPrint(
      '[MapController][onInit] currentAnnotationManager null: ${currentAnnotationManager == null}',
    );
    print(
      '[MapController][onInit]: currentAnnotationManager null status logged: ${currentAnnotationManager == null}',
    );

    WidgetsBinding.instance.addObserver(this);
    print('[MapController][onInit]: WidgetsBindingObserver added');
    debugPrint('[MapController][onInit] WidgetsBindingObserver added');
    print('[MapController][onInit]: WidgetsBindingObserver added log printed');

    // Initialize services
    print('[MapController][onInit]: About to call _initializeServices()');
    _initializeServices();
    print('[MapController][onInit]: _initializeServices() completed');

    // Check initial connectivity state and set appropriate UI state
    print(
      '[MapController][onInit]: About to call _checkInitialConnectivityAndSetState()',
    );
    _checkInitialConnectivityAndSetState();
    print(
      '[MapController][onInit]: _checkInitialConnectivityAndSetState() completed',
    );

    // Initialize offline functionality in background
    debugPrint(
      '[MapController][onInit] Starting offline initialization in background',
    );
    print('[MapController][onInit]: Offline initialization log printed');
    print('[MapController][onInit]: About to call setupApp()');
    setupApp();
    print('[MapController][onInit]: setupApp() completed');

    // Initialize background tile download service
    print(
      '[MapController][onInit]: About to call _initializeBackgroundTileService()',
    );
    _initializeBackgroundTileService();
    print(
      '[MapController][onInit]: _initializeBackgroundTileService() completed',
    );

    // Start offline status monitoring
    print(
      '[MapController][onInit]: About to call _startOfflineStatusMonitoring()',
    );
    _startOfflineStatusMonitoring();
    print('[MapController][onInit]: _startOfflineStatusMonitoring() completed');

    debugPrint('[MapController][onInit] Initialization complete');
    print('[MapController][onInit]: Initialization complete log printed');
    print('[MapController][onInit]: Method completed successfully');
  }

  // Initialize offline functionality in background without blocking UI
  Future<void> _initializeOfflineInBackground() async {
    try {
      debugPrint(
        '[MapController][_initializeOfflineInBackground] Starting background offline initialization',
      );
      debugPrint(
        '[MapController][_initializeOfflineInBackground] offlineManager null: ${offlineManager == null}',
      );
      debugPrint(
        '[MapController][_initializeOfflineInBackground] tileStore null: ${tileStore == null}',
      );
      await initOfflineMap();
      debugPrint(
        '[MapController][_initializeOfflineInBackground] Background offline initialization completed',
      );
      debugPrint(
        '[MapController][_initializeOfflineInBackground] offlineManager null after init: ${offlineManager == null}',
      );
      debugPrint(
        '[MapController][_initializeOfflineInBackground] tileStore null after init: ${tileStore == null}',
      );
    } catch (e) {
      debugPrint(
        '[MapController][_initializeOfflineInBackground] Background offline initialization failed: $e',
      );
      debugPrint(
        '[MapController][_initializeOfflineInBackground] Error type: ${e.runtimeType}',
      );
      debugPrint(
        '[MapController][_initializeOfflineInBackground] Stack trace: ${StackTrace.current}',
      );
    }
  }

  /// Initialize background tile download service
  Future<void> _initializeBackgroundTileService() async {
    try {
      // Wait for map initialization to complete
      await Future.delayed(Duration(seconds: 3));

      if (tileStore != null && offlineManager != null) {
        // Import and initialize the background download service
        try {
          final downloadService = Get.put(BackgroundTileDownloadService());
          await downloadService.initialize(
            tileStore: tileStore,
            offlineManager: offlineManager,
          );

          debugPrint(
            '[MapController] Background tile download service initialized successfully',
          );
        } catch (importError) {
          debugPrint(
            '[MapController] Error importing background service: $importError',
          );
        }
      } else {
        debugPrint(
          '[MapController] TileStore or OfflineManager not available for background service',
        );
      }
    } catch (e) {
      debugPrint(
        '[MapController] Error initializing background tile service: $e',
      );
    }
  }

  /// Initialize connectivity and permission services
  void _initializeServices() {
    try {
      // Initialize connectivity service if not already registered
      if (!Get.isRegistered<ConnectivityService>()) {
        Get.put(ConnectivityService());
      }

      // Initialize permission service if not already registered
      if (!Get.isRegistered<PermissionService>()) {
        Get.put(PermissionService());
      }

      // Set up reactive listeners
      _setupServiceListeners();

      print(
        '[MapController][_initializeServices]: Services initialized successfully',
      );
    } catch (e) {
      print(
        '[MapController][_initializeServices]: Error initializing services: $e',
      );
    }
  }

  /// Set up reactive listeners for sequential state management
  void _setupServiceListeners() {
    try {
      final connectivityService = Get.find<ConnectivityService>();
      final permissionService = Get.find<PermissionService>();

      // Listen to permission changes and advance state
      ever(permissionService.hasLocationPermission, (bool hasPermission) {
        _handlePermissionStateChange(hasPermission);
      });

      // Listen to connectivity changes and advance state
      ever(connectivityService.isConnected, (bool isConnected) {
        _handleConnectivityStateChange(isConnected);
      });

      // Listen to permission just granted for immediate progression
      ever(permissionService.permissionJustGranted, (bool justGranted) {
        if (justGranted) {
          _handlePermissionJustGranted();
        }
      });

      // Listen to state changes and process them sequentially
      ever(currentInitializationState, (MapInitializationState state) {
        _processStateChange(state);
      });

      print(
        '[MapController][_setupServiceListeners]: Sequential service listeners set up successfully',
      );
    } catch (e) {
      print(
        '[MapController][_setupServiceListeners]: Error setting up service listeners: $e',
      );
    }
  }

  /// Handle permission state changes in sequential flow
  void _handlePermissionStateChange(bool hasPermission) {
    print(
      '[MapController][_handlePermissionStateChange]: Permission state changed: $hasPermission',
    );

    // Process permission changes for any permission-related state
    if (currentInitializationState.value ==
            MapInitializationState.checkingPermission ||
        currentInitializationState.value ==
            MapInitializationState.permissionDenied) {
      if (hasPermission) {
        // Permission granted, automatically advance to internet checking
        print(
          '[MapController][_handlePermissionStateChange]: Permission granted from ${currentInitializationState.value}, advancing to internet check',
        );

        // Add a small delay to ensure UI updates smoothly
        // Future.delayed(const Duration(milliseconds: 500), () {
        _setState(MapInitializationState.checkingInternet);
        // });
      } else {
        // Permission denied, stay in denied state
        if (currentInitializationState.value !=
            MapInitializationState.permissionDenied) {
          _setState(MapInitializationState.permissionDenied);
        }
      }
    }
  }

  /// Handle connectivity state changes in sequential flow
  void _handleConnectivityStateChange(bool isConnected) {
    print(
      '[MapController][_handleConnectivityStateChange]: Connectivity state changed: $isConnected',
    );
    print(
      '[MapController][_handleConnectivityStateChange]: Current state: ${currentInitializationState.value}',
    );

    if (!isConnected) {
      // Lost connectivity logic remains the same
      print(
        '[MapController][_handleConnectivityStateChange]: No connectivity detected - checking current state and offline tiles',
      );

      if (currentInitializationState.value == MapInitializationState.ready ||
          currentInitializationState.value ==
              MapInitializationState.loadingMap ||
          currentInitializationState.value ==
              MapInitializationState.downloadingTiles ||
          currentInitializationState.value ==
              MapInitializationState.checkingInternet) {
        debugPrint(
          '🌐 Lost connectivity in active state - checking if internet screen needed',
        );
        _checkIfInternetScreenNeeded();
      } else if (currentInitializationState.value ==
              MapInitializationState.initial ||
          currentInitializationState.value ==
              MapInitializationState.checkingPermission) {
        debugPrint(
          '🌐 No connectivity during initialization - checking offline tiles immediately',
        );
        Future.microtask(() async {
          await _checkOfflineTilesAndSetState();
        });
      }
    } else {
      // ENHANCED: Connectivity restored - immediate response
      debugPrint(
        '🌐 Connectivity restored - current state: ${currentInitializationState.value}',
      );

      // IMMEDIATE response for internet-related states
      if (currentInitializationState.value ==
              MapInitializationState.checkingInternet ||
          currentInitializationState.value ==
              MapInitializationState.internetRequired) {
        debugPrint(
          '🌐 Internet restored - IMMEDIATELY hiding internet screen and advancing state',
        );

        // Immediately advance to loading state (this hides InternetRequiredScreen instantly)
        _setState(MapInitializationState.loadingMap);

        // Then reload map in background
        Future.microtask(() async {
          await automaticMapReloadAfterConnectivityRestore();
        });
      } else if (currentInitializationState.value ==
          MapInitializationState.ready) {
        // If already ready, just refresh the map
        debugPrint('🌐 Internet restored in ready state - refreshing map view');
        Future.microtask(() async {
          await automaticMapReloadAfterConnectivityRestore();
        });
      }
    }
  }

  /// Check if internet screen should be shown due to connectivity loss
  Future<void> _checkIfInternetScreenNeeded() async {
    try {
      final connectivityService = Get.find<ConnectivityService>();
      final hasInternetForMapbox =
          await connectivityService.hasInternetForMapbox();

      if (!hasInternetForMapbox) {
        // Check tile count - show internet widget if < 25,000 tiles
        final backgroundService = Get.find<BackgroundTileDownloadService>();
        final tileCount = backgroundService.totalTilesDownloaded.value;
        final hasSufficientTiles = tileCount >= 25000;

        debugPrint(
          '🌐 No internet access - tile count: $tileCount, sufficient: $hasSufficientTiles',
        );

        if (!hasSufficientTiles) {
          debugPrint(
            '🌐 No internet and insufficient tiles (< 25,000) - setting internetRequired state',
          );
          _setState(MapInitializationState.internetRequired);
        } else {
          debugPrint(
            '🌐 No internet but sufficient tiles (≥ 25,000) - staying in ready state',
          );
        }
      } else {
        debugPrint(
          '🌐 Internet access available - no need for internet screen',
        );
      }
    } catch (e) {
      debugPrint('❌ Error checking if internet screen needed: $e');
    }
  }

  /// Handle Mapbox connectivity errors detected in logs
  void handleMapboxConnectivityError(String errorMessage) {
    debugPrint('🗺 Mapbox connectivity error reported: $errorMessage');

    final connectivityService = Get.find<ConnectivityService>();

    // Check if this is a known connectivity error
    if (connectivityService.isMapboxConnectivityError(errorMessage)) {
      debugPrint(
        '🗺 Confirmed Mapbox connectivity error - checking current state',
      );

      // If we're in ready state, we might need to show internet screen
      if (currentInitializationState.value == MapInitializationState.ready) {
        debugPrint(
          '🗺 Map was ready but Mapbox reports connectivity issues - checking internet',
        );
        _checkIfInternetScreenNeeded();
      } else if (currentInitializationState.value ==
              MapInitializationState.loadingMap ||
          currentInitializationState.value ==
              MapInitializationState.downloadingTiles) {
        debugPrint(
          '🗺 Mapbox connectivity error during loading - setting internetRequired state',
        );
        _setState(MapInitializationState.internetRequired);
      }

      // Notify connectivity service
      connectivityService.handleMapboxConnectivityError(errorMessage);
    }
  }

  /// Handle permission just granted for immediate state progression
  void _handlePermissionJustGranted() {
    onInit();
    refreshMapView();
    return;
  }

  void setState(MapInitializationState newState) {
    _setState(newState);
  }

  /// Set the current initialization state
  void _setState(MapInitializationState newState) {
    print('[MapController][_setState]: Entered method with newState=$newState');
    print(
      '[MapController][_setState]: Current state before check: ${currentInitializationState.value}',
    );
    print(
      '[MapController][_setState]: Checking if states are different: ${currentInitializationState.value != newState}',
    );
    if (currentInitializationState.value != newState) {
      print(
        '[MapController][_setState]: States are different, proceeding with transition',
      );
      debugPrint(
        '🔄 State transition: ${currentInitializationState.value} → $newState',
      );
      print('[MapController][_setState]: State transition log printed');
      print(
        '[MapController][_setState]: About to set currentInitializationState.value to $newState',
      );
      currentInitializationState.value = newState;
      print(
        '[MapController][_setState]: currentInitializationState.value set to: ${currentInitializationState.value}',
      );
    } else {
      print(
        '[MapController][_setState]: States are the same, no transition needed',
      );
    }
    print('[MapController][_setState]: Method completed');
  }

  /// Advance to the next state in the sequence
  Future<void> _advanceToNextState() async {
    if (isProcessingStateChange.value) {
      debugPrint('⏳ State change already in progress, skipping');
      return;
    }

    isProcessingStateChange.value = true;

    try {
      switch (currentInitializationState.value) {
        case MapInitializationState.initial:
          _setState(MapInitializationState.checkingPermission);
          break;

        case MapInitializationState.checkingPermission:
          final permissionService = Get.find<PermissionService>();
          if (permissionService.hasLocationPermission.value) {
            _setState(MapInitializationState.checkingInternet);
          } else {
            _setState(MapInitializationState.permissionDenied);
          }
          break;

        case MapInitializationState.permissionDenied:
          // Stay in this state until permission is granted
          break;

        case MapInitializationState.checkingInternet:
          await _checkInternetAndAdvance();
          break;

        case MapInitializationState.internetRequired:
          // Stay in this state until internet is available
          break;

        case MapInitializationState.downloadingTiles:
          _setState(MapInitializationState.loadingMap);
          break;

        case MapInitializationState.loadingMap:
          _setState(MapInitializationState.ready);
          refreshMapView();
          break;

        case MapInitializationState.ready:
          refreshMapView();
          // Final state, nothing to advance to
          break;

        case MapInitializationState.error:
          // Error state, manual intervention needed
          break;
      }
    } catch (e) {
      debugPrint('❌ Error advancing state: $e');
      _setState(MapInitializationState.error);
    } finally {
      isProcessingStateChange.value = false;
    }
  }

  /// Check internet connectivity and advance state accordingly
  Future<void> _checkInternetAndAdvance() async {
    try {
      debugPrint('🌐 Starting internet check for Mapbox...');
      final connectivityService = Get.find<ConnectivityService>();

      // Use Mapbox-specific internet check for better reliability
      final hasInternetForMapbox =
          await connectivityService.hasInternetQuickCheck();

      debugPrint('🌐 Mapbox internet check result: $hasInternetForMapbox');

      if (hasInternetForMapbox) {
        // Internet available for Mapbox, check if we need to download tiles
        final hasOfflineTiles = await isOfflineDataAvailable();

        if (hasOfflineTiles) {
          // We have tiles, go straight to loading map
          debugPrint('🗺 Offline tiles available, loading map directly');
          _setState(MapInitializationState.loadingMap);
        } else {
          // Need to download tiles
          debugPrint('🗺 No offline tiles, need to download');
          _setState(MapInitializationState.downloadingTiles);
        }
      } else {
        _setState(MapInitializationState.internetRequired);
        // No internet for Mapbox, check if we have offline tiles
        debugPrint(
          '🌐 No internet for Mapbox detected, checking offline tiles',
        );
        await _checkOfflineTilesAndSetState();
      }
    } catch (e) {
      _setState(MapInitializationState.internetRequired);

      debugPrint('❌ Error checking internet: $e');

      // Check if the error itself indicates connectivity issues
      final connectivityService = Get.find<ConnectivityService>();
      if (connectivityService.isMapboxConnectivityError(e.toString())) {
        debugPrint(
          '🌐 Internet check failed with connectivity error - setting internetRequired state',
        );
        _setState(MapInitializationState.internetRequired);
      } else {
        _setState(MapInitializationState.internetRequired);
      }
    }
  }

  /// Check offline tiles and set appropriate state
  Future<void> _checkOfflineTilesAndSetState() async {
    try {
      debugPrint('🗺 Checking offline tiles and setting state');

      final backgroundService = Get.find<BackgroundTileDownloadService>();
      final tileCount = backgroundService.totalTilesDownloaded.value;
      final hasOfflineTiles = await isOfflineDataAvailable();

      debugPrint(
        '🗺 Tile count: $tileCount, hasOfflineTiles: $hasOfflineTiles',
      );

      if (hasOfflineTiles && tileCount >= 25000) {
        // Sufficient offline tiles available
        debugPrint('🗺 Sufficient offline tiles - proceeding to load map');
        _setState(MapInitializationState.loadingMap);
      } else {
        // Insufficient tiles - need internet
        debugPrint(
          '🌐 Insufficient offline tiles ($tileCount < 25,000) - requiring internet',
        );
        _setState(MapInitializationState.internetRequired);
      }
    } catch (e) {
      debugPrint('❌ Error checking offline tiles: $e');
      _setState(MapInitializationState.internetRequired);
    }
  }

  /// Process state changes and update UI accordingly
  void _processStateChange(MapInitializationState state) {
    debugPrint('🔄 Processing state change: $state');

    switch (state) {
      case MapInitializationState.initial:
        stateChangeMessage.value = 'Initializing...';
        break;

      case MapInitializationState.checkingPermission:
        stateChangeMessage.value = 'Checking location permission...';
        _checkLocationPermissionInState();
        break;

      case MapInitializationState.permissionDenied:
        stateChangeMessage.value = 'Location permission required';
        // UI will show permission request screen
        break;

      case MapInitializationState.checkingInternet:
        stateChangeMessage.value = 'Checking internet connection...';
        // Immediately trigger the quick internet check
        Future.microtask(() async {
          await _checkInternetAndAdvance();
        });
        break;

      case MapInitializationState.internetRequired:
        stateChangeMessage.value = 'Internet connection required';
        shouldShowInternetScreen.value = true;
        break;

      case MapInitializationState.downloadingTiles:
        stateChangeMessage.value = 'Map ready';
        shouldShowInternetScreen.value = false;
        isFirstTimeLoad.value = false;
        _startTileDownload();
        break;

      case MapInitializationState.loadingMap:
        stateChangeMessage.value = 'Map ready';
        shouldShowInternetScreen.value = false;
        isFirstTimeLoad.value = false;
        _startMapLoading();
        break;

      case MapInitializationState.ready:
        stateChangeMessage.value = 'Map ready';
        shouldShowInternetScreen.value = false;
        isFirstTimeLoad.value = false;
        break;

      case MapInitializationState.error:
        stateChangeMessage.value = 'Error occurred';
        break;
    }
  }

  /// Check location permission within state management
  Future<void> _checkLocationPermissionInState() async {
    try {
      final permissionService = Get.find<PermissionService>();
      final hasPermission = await permissionService.checkLocationPermission(
        requestIfDenied: true,
      );

      if (hasPermission) {
        _advanceToNextState();
      } else {
        _setState(MapInitializationState.permissionDenied);
      }
    } catch (e) {
      debugPrint('❌ Error checking permission in state: $e');
      _setState(MapInitializationState.error);
    }
  }

  /// Start tile download process
  Future<void> _startTileDownload() async {
    try {
      debugPrint('🗺 Starting tile download...');

      // Get the background download service
      final downloadService = Get.find<BackgroundTileDownloadService>();

      // Start the offline map setup
      await setupOfflineMap();

      // Trigger a manual download for a default region
      try {
        // Create a default region around user's location or a global area
        final bounds = mapbox.CoordinateBounds(
          southwest: mapbox.Point(
            coordinates: mapbox.Position(-180.0, -85.0), // Global southwest
          ),
          northeast: mapbox.Point(
            coordinates: mapbox.Position(180.0, 85.0), // Global northeast
          ),
          infiniteBounds: false,
        );
        await downloadService.downloadRegion(bounds, [10, 11, 12, 13, 14]);
        debugPrint('🗺 Triggered manual download for global region');
      } catch (e) {
        debugPrint('⚠️ Could not trigger manual download: $e');
      }

      // Wait a moment to show the download banner

      await Future.delayed(const Duration(seconds: 2));

      // Advance to loading map

      _advanceToNextState();
    } catch (e) {
      debugPrint('❌ Error downloading tiles: $e');
      _setState(MapInitializationState.error);
    }
  }

  /// Start map loading process
  Future<void> _startMapLoading() async {
    try {
      debugPrint('🗺 Starting map loading...');

      // Use the direct initialization method for the actual map setup
      await _performDirectMapInitialization();

      // Mark as ready
      _advanceToNextState();
    } catch (e) {
      debugPrint('❌ Error loading map: $e');
      _setState(MapInitializationState.error);
    }
  }

  /// Start the sequential initialization process
  Future<void> startSequentialInitialization() async {
    debugPrint('🚀 Starting sequential initialization process');

    // Reset state
    currentInitializationState.value = MapInitializationState.initial;
    isProcessingStateChange.value = false;

    // Start the sequence
    await _advanceToNextState();
  }

  /// Retry from current state (for user-triggered retries)
  Future<void> retryCurrentState() async {
    print('[MapController][retryCurrentState]: Entered method');
    debugPrint(
      '🔄 Retrying current state: ${currentInitializationState.value}',
    );
    print(
      '[MapController][retryCurrentState]: Current state logged: ${currentInitializationState.value}',
    );

    try {
      print('[MapController][retryCurrentState]: Entered try block');
      print(
        '[MapController][retryCurrentState]: About to enter switch statement with state: ${currentInitializationState.value}',
      );
      switch (currentInitializationState.value) {
        case MapInitializationState.permissionDenied:
          print(
            '[MapController][retryCurrentState]: Entered permissionDenied case',
          );
          debugPrint('🔄 Retrying from permission denied state');
          print(
            '[MapController][retryCurrentState]: Permission denied retry log printed',
          );
          print(
            '[MapController][retryCurrentState]: About to call _setState(MapInitializationState.checkingPermission)',
          );
          _setState(MapInitializationState.checkingPermission);
          print(
            '[MapController][retryCurrentState]: _setState completed, new state: ${currentInitializationState.value}',
          );
          break;

        case MapInitializationState.internetRequired:
          print(
            '[MapController][retryCurrentState]: Entered internetRequired case',
          );
          debugPrint('🔄 Retrying from internet required state');
          print(
            '[MapController][retryCurrentState]: Internet required retry log printed',
          );

          // Force refresh connectivity before retrying
          print(
            '[MapController][retryCurrentState]: About to get ConnectivityService',
          );
          final connectivityService = Get.find<ConnectivityService>();
          print(
            '[MapController][retryCurrentState]: ConnectivityService obtained: ${connectivityService != null}',
          );
          print(
            '[MapController][retryCurrentState]: About to call refreshConnectivity()',
          );
          await connectivityService.refreshConnectivity();
          print(
            '[MapController][retryCurrentState]: refreshConnectivity() completed',
          );

          // Wait a moment for reactive updates to propagate
          // await Future.delayed(const Duration(milliseconds: 300));

          print(
            '[MapController][retryCurrentState]: About to call _setState(MapInitializationState.checkingInternet)',
          );
          _setState(MapInitializationState.checkingInternet);
          print(
            '[MapController][retryCurrentState]: _setState completed, new state: ${currentInitializationState.value}',
          );
          break;

        case MapInitializationState.error:
          print('[MapController][retryCurrentState]: Entered error case');
          debugPrint('🔄 Retrying from error state');
          print('[MapController][retryCurrentState]: Error retry log printed');
          print(
            '[MapController][retryCurrentState]: About to call _setState(MapInitializationState.initial)',
          );
          _setState(MapInitializationState.initial);
          print(
            '[MapController][retryCurrentState]: _setState completed, new state: ${currentInitializationState.value}',
          );
          print(
            '[MapController][retryCurrentState]: About to call _advanceToNextState()',
          );
          await _advanceToNextState();
          print(
            '[MapController][retryCurrentState]: _advanceToNextState() completed',
          );
          break;

        default:
          print('[MapController][retryCurrentState]: Entered default case');
          debugPrint(
            '🔄 Retrying from state: ${currentInitializationState.value}',
          );
          print(
            '[MapController][retryCurrentState]: Default retry log printed for state: ${currentInitializationState.value}',
          );
          // For other states, just advance
          print(
            '[MapController][retryCurrentState]: About to call _advanceToNextState()',
          );
          await _advanceToNextState();
          print(
            '[MapController][retryCurrentState]: _advanceToNextState() completed',
          );
          break;
      }
      print('[MapController][retryCurrentState]: Switch statement completed');
    } catch (e) {
      print('[MapController][retryCurrentState]: Caught exception: $e');
      debugPrint('❌ Error during state retry: $e');
      print('[MapController][retryCurrentState]: Error log printed');
      print(
        '[MapController][retryCurrentState]: About to call _setState(MapInitializationState.error)',
      );
      _setState(MapInitializationState.error);
      print(
        '[MapController][retryCurrentState]: _setState completed, new state: ${currentInitializationState.value}',
      );
    }
    print('[MapController][retryCurrentState]: Method completed');
  }

  /// Force refresh connectivity and update UI state
  Future<void> forceConnectivityRefresh() async {
    debugPrint('🌐 Force refreshing connectivity and UI state');

    try {
      final connectivityService = Get.find<ConnectivityService>();

      // Refresh connectivity service
      await connectivityService.refreshConnectivity();

      // Wait for reactive updates
      await Future.delayed(const Duration(milliseconds: 500));

      // Check current connectivity state and update UI accordingly
      final isConnected = connectivityService.isConnected.value;
      final connectionType = connectivityService.connectionType.value;

      debugPrint(
        '🌐 Force refresh results: isConnected=$isConnected, type=$connectionType',
      );

      // If we're in internetRequired state and now have internet, advance
      if (currentInitializationState.value ==
              MapInitializationState.internetRequired &&
          isConnected) {
        debugPrint(
          '🌐 Internet restored during force refresh - advancing state',
        );
        _setState(MapInitializationState.checkingInternet);
      }

      // Refresh map view to update UI
      refreshMapView();
    } catch (e) {
      debugPrint('❌ Error during force connectivity refresh: $e');
    }
  }

  /// Automatically reload/refresh map after connectivity is restored
  Future<void> automaticMapReloadAfterConnectivityRestore() async {
    debugPrint('🌐 Starting automatic map reload after connectivity restore');

    setupOfflineMap();
    try {
      // Ensure we're in loading state to hide internet screen
      if (currentInitializationState.value !=
          MapInitializationState.loadingMap) {
        _setState(MapInitializationState.loadingMap);
      }

      // Small delay to ensure UI updates
      await Future.delayed(const Duration(milliseconds: 100));

      // Check if map controller exists
      if (mapController == null) {
        debugPrint('🌐 No map controller - reinitializing map');
        await startMapInitializationSequence();
      } else {
        debugPrint('🌐 Map controller available - refreshing existing map');

        // Refresh the existing map view
        await refreshMapView();

        // Ensure map is properly loaded with latest data
        await _reloadMapWithLatestData();

        // Set to ready state
        _setState(MapInitializationState.ready);
      }

      debugPrint('🌐 Automatic map reload completed successfully');
    } catch (e) {
      debugPrint('❌ Error during automatic map reload: $e');

      // On error, try to reset to a clean state
      try {
        _setState(MapInitializationState.checkingInternet);
      } catch (resetError) {
        debugPrint('❌ Error during map reload reset: $resetError');
      }
    }
  }

  /// Reload map with latest data after connectivity restore
  Future<void> _reloadMapWithLatestData() async {
    debugPrint('🌐 Reloading map with latest data');

    try {
      // Reload memories from database
      await loadMemoriesFromDatabase();

      // Reinitialize clustering
      await _initializeMemoryClustering();

      // Refresh the map display
      await refreshMapView();

      debugPrint('🌐 Map data reload completed');
    } catch (e) {
      debugPrint('❌ Error reloading map data: $e');
    }
  }

  /// Refresh user location after permission grant
  Future<void> _refreshUserLocation() async {
    try {
      debugPrint('🌍 Refreshing user location');
      _initializeUserLocation();
    } catch (e) {
      debugPrint('❌ Error refreshing user location: $e');
    }
  }

  /// Refresh map after permission grant
  Future<void> _refreshMapAfterPermissionGrant() async {
    try {
      debugPrint('🗺 Refreshing map after permission grant');

      // Refresh user location
      await _refreshUserLocation();

      // If map is ready, update camera to user location
      if (isMapReady.value && mapController != null) {
        final permissionService = Get.find<PermissionService>();
        final position = await permissionService.getCurrentLocation();

        if (position != null) {
          await mapController!.flyTo(
            CameraOptions(
              center: Point(
                coordinates: mapbox.Position(
                  position.longitude,
                  position.latitude,
                ),
              ),
              zoom: 12.0,
            ),
            MapAnimationOptions(duration: 1000),
          );
        }
      }

      debugPrint('🗺 Map refreshed after permission grant');
    } catch (e) {
      debugPrint('❌ Error refreshing map after permission grant: $e');
    }
  }

  /// Refresh map after connectivity is restored
  Future<void> refreshMapAfterConnectivity() async {
    try {
      debugPrint('🌐 Refreshing map after connectivity restored');

      isConnectivityChecking.value = true;

      // Check if we have offline tiles
      hasOfflineTiles.value = await isOfflineDataAvailable();

      // If no offline tiles, try to download them
      if (!hasOfflineTiles.value) {
        debugPrint('🌐 No offline tiles, attempting to download');
        await setupOfflineMap();
      }

      // Refresh the map display
      await _refreshMapDisplay();

      isConnectivityChecking.value = false;

      debugPrint('🌐 Map refreshed after connectivity restored');
    } catch (e) {
      debugPrint('❌ Error refreshing map after connectivity: $e');
      isConnectivityChecking.value = false;
    }
  }

  /// Refresh map display
  Future<void> _refreshMapDisplay() async {
    try {
      debugPrint('🗺 Refreshing map display');

      // Trigger map refresh by updating reactive variables
      isRefreshing.value = true;

      // Small delay to ensure UI updates
      await Future.delayed(const Duration(milliseconds: 100));

      // Load memories and refresh clustering
      await loadMemoriesFromDatabase();
      await _initializeMemoryClustering();

      isRefreshing.value = false;

      debugPrint('🗺 Map display refreshed');
    } catch (e) {
      debugPrint('❌ Error refreshing map display: $e');
      isRefreshing.value = false;
    }
  }

  Future<void> _checkPermissionsAndScheduleOneTimeRecreation() async {
    debugPrint(
      '[MapController][_checkPermissionsAndScheduleOneTimeRecreation] Starting permission check',
    );
    debugPrint(
      '[MapController][_checkPermissionsAndScheduleOneTimeRecreation] Current thread: ${DateTime.now().millisecondsSinceEpoch}',
    );

    // Check location permissions
    debugPrint(
      '[MapController][_checkPermissionsAndScheduleOneTimeRecreation] Checking location permission...',
    );
    final hasLocationPermission = await _checkLocationPermission();
    debugPrint(
      '[MapController][_checkPermissionsAndScheduleOneTimeRecreation] Location permission result: $hasLocationPermission',
    );

    debugPrint(
      '[MapController][_checkPermissionsAndScheduleOneTimeRecreation] Scheduling one-time recreation',
    );
    _scheduleOneTimeRecreation();
    debugPrint(
      '[MapController][_checkPermissionsAndScheduleOneTimeRecreation] Permission check completed',
    );
  }

  void _scheduleOneTimeRecreation() {
    debugPrint(
      '[MapController][_scheduleOneTimeRecreation] Starting recreation scheduling',
    );
    debugPrint(
      '[MapController][_scheduleOneTimeRecreation] _hasTriggeredRecreation: $_hasTriggeredRecreation',
    );
    debugPrint(
      '[MapController][_scheduleOneTimeRecreation] _oneTimeRecreationTimer null: ${_oneTimeRecreationTimer == null}',
    );

    if (_hasTriggeredRecreation) {
      debugPrint(
        '[MapController][_scheduleOneTimeRecreation] Already triggered, skipping',
      );
      return;
    }

    debugPrint(
      '[MapController][_scheduleOneTimeRecreation] Scheduling recreation in 100ms',
    );
    debugPrint(
      '[MapController][_scheduleOneTimeRecreation] Current time: ${DateTime.now().millisecondsSinceEpoch}',
    );

    //   _oneTimeRecreationTimer = Timer(const Duration(milliseconds: 100), () {
    //     debugPrint('[MapController][_scheduleOneTimeRecreation] Timer callback triggered');
    //     debugPrint('[MapController][_scheduleOneTimeRecreation] _hasTriggeredRecreation in callback: $_hasTriggeredRecreation');

    //     if (!_hasTriggeredRecreation) {
    //       debugPrint('[MapController][_scheduleOneTimeRecreation] Executing recreation');
    //       _hasTriggeredRecreation = true;
    //       debugPrint('[MapController][_scheduleOneTimeRecreation] Set _hasTriggeredRecreation to true');
    //       // _triggerMapRecreation();
    //     } else {
    //       debugPrint('[MapController][_scheduleOneTimeRecreation] Recreation already triggered in callback');
    //     }
    //   });

    //   debugPrint('[MapController][_scheduleOneTimeRecreation] Timer scheduled successfully');
  }

  // Trigger map recreation to simulate restart behavior
  void _triggerMapRecreation() {
    _mapRecreationCount++;
    debugPrint(
      '[MapController][_triggerMapRecreation] Starting recreation #$_mapRecreationCount',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation] Current state before recreation:',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation]   - mapController null: ${mapController == null}',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation]   - currentAnnotationManager null: ${currentAnnotationManager == null}',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation]   - annotations count: ${annotations.length}',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation]   - hasInitialized: ${hasInitialized.value}',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation]   - isMapReady: ${isMapReady.value}',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation]   - shouldRecreateMap: ${shouldRecreateMap.value}',
    );

    // Toggle the recreation flag to force MapWidget rebuild
    final previousValue = shouldRecreateMap.value;
    shouldRecreateMap.value = !shouldRecreateMap.value;
    debugPrint(
      '[MapController][_triggerMapRecreation] shouldRecreateMap toggled from $previousValue to ${shouldRecreateMap.value}',
    );

    // Reset map state
    debugPrint('[MapController][_triggerMapRecreation] Resetting map state...');
    mapController = null;
    currentAnnotationManager = null;
    annotations.clear();
    hasInitialized.value = false;
    isMapReady.value = false;

    debugPrint('[MapController][_triggerMapRecreation] State after reset:');
    debugPrint(
      '[MapController][_triggerMapRecreation]   - mapController null: ${mapController == null}',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation]   - currentAnnotationManager null: ${currentAnnotationManager == null}',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation]   - annotations count: ${annotations.length}',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation]   - hasInitialized: ${hasInitialized.value}',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation]   - isMapReady: ${isMapReady.value}',
    );
    debugPrint(
      '[MapController][_triggerMapRecreation] Map state reset complete, MapWidget will rebuild',
    );
  }

  Future<void> _setupReactiveWorkers() async {
    debugPrint(
      '[MapController][_setupReactiveWorkers] Starting reactive workers setup',
    );
    debugPrint('[MapController][_setupReactiveWorkers] Current state:');
    debugPrint(
      '[MapController][_setupReactiveWorkers]   - currentZoom: ${currentZoom.value}',
    );
    debugPrint(
      '[MapController][_setupReactiveWorkers]   - isMapReady: ${isMapReady.value}',
    );
    debugPrint(
      '[MapController][_setupReactiveWorkers]   - isShowingNewLocations: ${isShowingNewLocations.value}',
    );
    debugPrint(
      '[MapController][_setupReactiveWorkers]   - locations count: ${locations.length}',
    );

    // Worker to handle zoom changes
    debugPrint(
      '[MapController][_setupReactiveWorkers] Setting up zoom change worker',
    );
    ever(currentZoom, (double zoom) {
      debugPrint(
        '[MapController][_setupReactiveWorkers][zoomWorker] Zoom change triggered: $zoom',
      );
      debugPrint(
        '[MapController][_setupReactiveWorkers][zoomWorker] isMapReady: ${isMapReady.value}',
      );
      debugPrint(
        '[MapController][_setupReactiveWorkers][zoomWorker] mapController null: ${mapController == null}',
      );
      debugPrint(
        '[MapController][_setupReactiveWorkers][zoomWorker] _isTransitioningLocations: $_isTransitioningLocations',
      );

      if (isMapReady.value &&
          mapController != null &&
          !_isTransitioningLocations) {
        debugPrint(
          '[MapController][_setupReactiveWorkers][zoomWorker] Calling _ensureCameraZoom()',
        );
        _ensureCameraZoom();
      } else {
        debugPrint(
          '[MapController][_setupReactiveWorkers][zoomWorker] Skipping zoom change - conditions not met',
        );
      }
    });

    // Worker to handle location state changes
    debugPrint(
      '[MapController][_setupReactiveWorkers] Setting up location state worker',
    );
    ever(isShowingNewLocations, (bool showingNew) {
      debugPrint(
        '[MapController][_setupReactiveWorkers][locationStateWorker] Location state change: $showingNew',
      );
      debugPrint(
        '[MapController][_setupReactiveWorkers][locationStateWorker] This should trigger MapWidget rebuild via Obx',
      );
    });

    // Worker to handle map ready state changes
    debugPrint(
      '[MapController][_setupReactiveWorkers] Setting up map ready state worker',
    );
    ever(isMapReady, (bool ready) {
      debugPrint(
        '[MapController][_setupReactiveWorkers][mapReadyWorker] Map ready state change: $ready',
      );
      debugPrint(
        '[MapController][_setupReactiveWorkers][mapReadyWorker] mapController null: ${mapController == null}',
      );
      debugPrint(
        '[MapController][_setupReactiveWorkers][mapReadyWorker] _isTransitioningLocations: $_isTransitioningLocations',
      );

      if (ready && mapController != null && !_isTransitioningLocations) {
        debugPrint(
          '[MapController][_setupReactiveWorkers][mapReadyWorker] Calling _ensureCameraZoom()',
        );
        _ensureCameraZoom();
      } else {
        debugPrint(
          '[MapController][_setupReactiveWorkers][mapReadyWorker] Skipping - transitioning locations or controller null',
        );
      }
    });

    // Worker to handle locations changes
    debugPrint(
      '[MapController][_setupReactiveWorkers] Setting up locations change worker',
    );
    ever(locations, (List<mapbox.Position> newLocations) {
      debugPrint(
        '[MapController][_setupReactiveWorkers][locationsWorker] Locations change: ${newLocations.length} locations',
      );
      debugPrint(
        '[MapController][_setupReactiveWorkers][locationsWorker] _isTransitioningLocations: $_isTransitioningLocations',
      );
      debugPrint(
        '[MapController][_setupReactiveWorkers][locationsWorker] This should trigger MapWidget rebuild via Obx',
      );
    });

    debugPrint(
      '[MapController][_setupReactiveWorkers] All reactive workers setup completed',
    );
  }

  @override
  void onClose() {
    // Clean up resources properly
    _oneTimeRecreationTimer?.cancel();

    // Stop offline status monitoring
    _stopOfflineStatusMonitoring();

    // Clean up offline resources
    _cleanupOfflineResources();

    // Clean up map resources
    mapController = null;
    currentAnnotationManager = null;
    annotations.clear();
    hasInitialized.value = false;
    isShowingNewLocations.value = false;
    isMapReady.value = false;

    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  // Clean up offline resources
  void _cleanupOfflineResources() {
    try {
      // Close progress streams
      if (!stylePackProgress.isClosed) {
        stylePackProgress.close();
      }
      if (!tileRegionLoadProgress.isClosed) {
        tileRegionLoadProgress.close();
      }

      // Reset offline managers
      /// Check initial connectivity and set appropriate state
      Future<void> _checkInitialConnectivityAndSetState() async {
        try {
          debugPrint('🌐 Checking initial connectivity and setting state');

          // First check location permissions
          final permissionService = Get.find<PermissionService>();
          if (!permissionService.hasLocationPermission.value) {
            debugPrint(
              '🔐 No location permission - setting checkingPermission state',
            );
            _setState(MapInitializationState.checkingPermission);
            return;
          }

          // Check internet connectivity
          final connectivityService = Get.find<ConnectivityService>();
          final hasInternetForMapbox =
              await connectivityService.hasInternetForMapbox();

          if (hasInternetForMapbox) {
            // Internet available, proceed normally
            debugPrint(
              '🌐 Internet available - proceeding to check offline tiles',
            );
            final hasOfflineTiles = await isOfflineDataAvailable();

            if (hasOfflineTiles) {
              _setState(MapInitializationState.loadingMap);
            } else {
              _setState(MapInitializationState.downloadingTiles);
            }
          } else {
            // No internet - check if we have sufficient offline tiles
            debugPrint('🌐 No internet - checking offline tiles');
            await _checkOfflineTilesAndSetState();
          }
        } catch (e) {
          debugPrint('❌ Error in initial connectivity check: $e');
          _setState(MapInitializationState.error);
        }
      }

      offlineManager = null;
      tileStore = null;

      debugPrint('🗺 OFFLINE - Resources cleaned up successfully');
    } catch (e) {
      debugPrint('❌ OFFLINE - Error cleaning up resources: $e');
    }
  }

  // Method to reset to original locations
  Future<void> resetToOriginalLocations() async {
    debugPrint(
      '[MapController][resetToOriginalLocations] Starting reset to original locations',
    );
    debugPrint(
      '[MapController][resetToOriginalLocations] Current state before reset:',
    );
    debugPrint(
      '[MapController][resetToOriginalLocations]   - _isTransitioningLocations: $_isTransitioningLocations',
    );
    debugPrint(
      '[MapController][resetToOriginalLocations]   - currentAnnotationManager null: ${currentAnnotationManager == null}',
    );
    debugPrint(
      '[MapController][resetToOriginalLocations]   - annotations count: ${annotations.length}',
    );
    debugPrint(
      '[MapController][resetToOriginalLocations]   - locations count: ${locations.length}',
    );
    debugPrint(
      '[MapController][resetToOriginalLocations]   - currentZoom: ${currentZoom.value}',
    );
    debugPrint(
      '[MapController][resetToOriginalLocations]   - isMapReady: ${isMapReady.value}',
    );
    debugPrint(
      '[MapController][resetToOriginalLocations]   - mapController null: ${mapController == null}',
    );

    // Set transition flag to prevent reactive zoom conflicts
    debugPrint(
      '[MapController][resetToOriginalLocations] Setting transition flag to true',
    );
    _isTransitioningLocations = true;
    debugPrint(
      '[MapController][resetToOriginalLocations] _isTransitioningLocations set to: $_isTransitioningLocations',
    );

    try {
      // Clear existing annotations and lines first
      debugPrint(
        '[MapController][resetToOriginalLocations] Starting cleanup of existing annotations and lines',
      );

      if (currentAnnotationManager != null) {
        debugPrint(
          '[MapController][resetToOriginalLocations] Deleting all annotations from manager',
        );
        await currentAnnotationManager!.deleteAll();
        debugPrint(
          '[MapController][resetToOriginalLocations] All annotations deleted, setting manager to null',
        );
        currentAnnotationManager = null;
      } else {
        debugPrint(
          '[MapController][resetToOriginalLocations] No annotation manager to clean up',
        );
      }

      debugPrint(
        '[MapController][resetToOriginalLocations] Clearing annotations list',
      );
      annotations.clear();
      debugPrint(
        '[MapController][resetToOriginalLocations] Clearing marker images',
      );
      await _clearAllMarkerImages();
      debugPrint('[MapController][resetToOriginalLocations] Clearing lines');
      await _clearAllLines();
      debugPrint('[MapController][resetToOriginalLocations] Cleanup completed');

      // Reset to original 5 locations
      locations.clear();
      locations.addAll([]);

      // Reset state flags
      isShowingNewLocations.value = false;
      final newZoomLevel = 1.6 - 0.8; // Calculate the zoomed out level
      currentZoom.value = newZoomLevel;

      debugPrint('🔄 RESET - Updated currentZoom to: ${currentZoom.value}');

      debugPrint('🔄 RESET - Original locations and zoom restored');

      // If map is ready, update the display
      debugPrint(
        '[MapController][resetToOriginalLocations] Checking if map is ready for camera update',
      );
      debugPrint(
        '[MapController][resetToOriginalLocations] isMapReady: ${isMapReady.value}',
      );
      debugPrint(
        '[MapController][resetToOriginalLocations] mapController null: ${mapController == null}',
      );

      if (isMapReady.value && mapController != null) {
        // Use the updated currentZoom value
        final targetZoom = 1.6;
        debugPrint(
          '[MapController][resetToOriginalLocations] Map is ready, starting camera operations',
        );
        debugPrint(
          '[MapController][resetToOriginalLocations] Target zoom: $targetZoom',
        );
        debugPrint(
          '[MapController][resetToOriginalLocations] Target location: ${locations.isNotEmpty ? locations[0] : "NO LOCATIONS"}',
        );

        if (locations.isEmpty) {
          debugPrint(
            '[MapController][resetToOriginalLocations] ERROR: No locations available for camera positioning',
          );
          return;
        }

        // First ensure camera is at correct zoom and position with iOS-specific handling
        debugPrint(
          '[MapController][resetToOriginalLocations] Starting flyTo animation...',
        );
        debugPrint(
          '[MapController][resetToOriginalLocations] Animation duration: 1500ms',
        );

        await mapController!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: locations[0]),
            zoom: targetZoom,
            bearing: 0,
            pitch: 0,
          ),
          mapbox.MapAnimationOptions(duration: 1500), // Longer duration for iOS
        );
        debugPrint(
          '[MapController][resetToOriginalLocations] flyTo animation completed',
        );

        // Wait for the camera animation to complete
        debugPrint(
          '[MapController][resetToOriginalLocations] Waiting 1600ms for animation to settle',
        );
        await Future.delayed(const Duration(milliseconds: 1600));
        debugPrint(
          '[MapController][resetToOriginalLocations] Animation settle delay completed',
        );

        // Force another camera update for iOS reliability
        debugPrint(
          '[MapController][resetToOriginalLocations] Applying iOS reliability camera update',
        );
        await mapController!.setCamera(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: locations[0]),
            zoom: targetZoom,
            bearing: 0,
            pitch: 0,
          ),
        );
        debugPrint(
          '[MapController][resetToOriginalLocations] iOS reliability camera update completed',
        );

        // Additional iOS-specific fix: Force viewport refresh
        await Future.delayed(const Duration(milliseconds: 200));

        // Trigger a small camera movement to force iOS to refresh
        await mapController!.setCamera(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: locations[0]),
            zoom: targetZoom + 0.01, // Tiny zoom change
            bearing: 0,
            pitch: 0,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 100));

        // Set back to the exact target zoom
        await mapController!.setCamera(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: locations[0]),
            zoom: targetZoom,
            bearing: 0,
            pitch: 0,
          ),
        );

        // Then recreate annotations and paths
        await _setAnnotations();
        await _setTravelPath();

        debugPrint('🔄 RESET - Camera and annotations updated');
      }
    } catch (e) {
      debugPrint('Error resetting to original locations: $e');
    } finally {
      _isTransitioningLocations = false;
      debugPrint('🔄 RESET - Reset complete, reactive zoom enabled');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mapController != null) {
      _retryLocationFlowIfPossible();
    }
  }

  void _retryLocationFlowIfPossible() async {
    if (!hasInitialized.value) {
      final hasPermission = await _checkLocationPermission();
      if (hasPermission) {
        hasInitialized.value = true;
        _setAnnotations();
        _setTravelPath();
        _fitCameraToBounds();
      }
    }
  }

  void toggleFilter() => isFilterOpen.toggle();
  void openFilter() => isFilterOpen.value = true;
  void closeFilter() => isFilterOpen.value = false;

  // Public method to manually trigger map recreation (for testing)
  void recreateMap() {
    debugPrint('🔄 PUBLIC - Manual map recreation triggered');
    _triggerMapRecreation();
  }

  // Memory clustering methods
  Future<void> loadMemoriesFromDatabase() async {
    print('[MapController][loadMemoriesFromDatabase]: Entered method');
    try {
      print('[MapController][loadMemoriesFromDatabase]: Entered try block');
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Starting memory loading from database',
      );
      print('[MapController][loadMemoriesFromDatabase]: Starting log printed');
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] isLoadingMemories before: ${isLoadingMemories.value}',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: isLoadingMemories before logged: ${isLoadingMemories.value}',
      );
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] allMemories count before: ${allMemories.length}',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: allMemories count before logged: ${allMemories.length}',
      );

      isLoadingMemories.value = true;
      print(
        '[MapController][loadMemoriesFromDatabase]: isLoadingMemories set to true: ${isLoadingMemories.value}',
      );
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Set isLoadingMemories to true',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: isLoadingMemories true log printed',
      );

      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Calling _databaseHelper.getAllMemoriesWithDetails()',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: About to call database query',
      );
      final memories = await _databaseHelper.getAllMemoriesWithDetails();
      print(
        '[MapController][loadMemoriesFromDatabase]: Database query returned ${memories.length} memories',
      );
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Database query completed, got ${memories.length} memories',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: Database query completion log printed',
      );

      allMemories.assignAll(memories);
      print(
        '[MapController][loadMemoriesFromDatabase]: allMemories.assignAll() completed, new count: ${allMemories.length}',
      );
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Assigned memories to allMemories, count: ${allMemories.length}',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: Assignment log printed',
      );

      print(
        '[MapController][loadMemoriesFromDatabase]: Checking if memories is empty: ${memories.isEmpty}',
      );
      if (memories.isEmpty) {
        print(
          '[MapController][loadMemoriesFromDatabase]: Entered empty memories branch',
        );
        debugPrint(
          '[MapController][loadMemoriesFromDatabase] No memories found in database, returning early',
        );
        print(
          '[MapController][loadMemoriesFromDatabase]: Empty memories log printed',
        );

        // Move to user's current location
        try {
          print(
            '[MapController][loadMemoriesFromDatabase]: Entered location try block',
          );

          print(
            '[MapController][loadMemoriesFromDatabase]: About to get PermissionService',
          );
          final permissionService = Get.find<PermissionService>();
          print(
            '[MapController][loadMemoriesFromDatabase]: PermissionService obtained: ${permissionService != null}',
          );
          print(
            '[MapController][loadMemoriesFromDatabase]: About to call getCurrentLocation()',
          );
          final currentPosition = await permissionService.getCurrentLocation();
          print(
            '[MapController][loadMemoriesFromDatabase]: getCurrentLocation() returned: ${currentPosition != null}',
          );

          print(
            '[MapController][loadMemoriesFromDatabase]: About to call mapController.flyTo()',
          );
          await mapController!.flyTo(
            mapbox.CameraOptions(
              center: mapbox.Point(
                coordinates: mapbox.Position(
                  currentPosition?.longitude ?? 33.3,
                  currentPosition?.latitude ?? 73.03,
                ),
              ),
              zoom: 8.0,
            ),
            mapbox.MapAnimationOptions(duration: 1000),
          );
          print(
            '[MapController][loadMemoriesFromDatabase]: mapController.flyTo() completed',
          );
        } catch (e) {
          print(
            '[MapController][loadMemoriesFromDatabase]: Caught location exception: $e',
          );
          debugPrint(
            '[MapController][loadMemoriesFromDatabase] Error getting current location: $e',
          );
          print(
            '[MapController][loadMemoriesFromDatabase]: Location error log printed',
          );
          // Fallback to world view
          print(
            '[MapController][loadMemoriesFromDatabase]: About to call fallback flyTo()',
          );
          // await mapController!.flyTo(
          //   mapbox.CameraOptions(
          //     center: mapbox.Point(coordinates: mapbox.Position(0, 0)),
          //     zoom: 2.0,
          //   ),
          //   mapbox.MapAnimationOptions(duration: 1000),
          // );
          print(
            '[MapController][loadMemoriesFromDatabase]: Fallback flyTo() completed',
          );
        }

        print(
          '[MapController][loadMemoriesFromDatabase]: About to return from empty memories branch',
        );
        return;
      } else {
        print(
          '[MapController][loadMemoriesFromDatabase]: Memories not empty, continuing with ${memories.length} memories',
        );
      }

      // Debug memory location data
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Debugging memory locations...',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: About to call debugMemoryLocations()',
      );
      MemoryClusteringService.debugMemoryLocations(memories);
      print(
        '[MapController][loadMemoriesFromDatabase]: debugMemoryLocations() completed',
      );

      // Initialize clustering with loaded memories
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Starting clustering initialization...',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: About to call _initializeMemoryClustering()',
      );
      await _initializeMemoryClustering();
      print(
        '[MapController][loadMemoriesFromDatabase]: _initializeMemoryClustering() completed',
      );
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Clustering initialization completed',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: Clustering completion log printed',
      );
    } catch (e) {
      print('[MapController][loadMemoriesFromDatabase]: Caught exception: $e');
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Error loading memories from database: $e',
      );
      print('[MapController][loadMemoriesFromDatabase]: Error log printed');
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Error type: ${e.runtimeType}',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: Error type logged: ${e.runtimeType}',
      );
      // debugPrint('[MapController][loadMemoriesFromDatabase] Stack trace: ${StackTrace.current}');
      print('[MapController][loadMemoriesFromDatabase]: Stack trace logged');
    } finally {
      print('[MapController][loadMemoriesFromDatabase]: Entered finally block');
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Setting isLoadingMemories to false',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: About to set isLoadingMemories to false',
      );
      isLoadingMemories.value = false;
      print(
        '[MapController][loadMemoriesFromDatabase]: isLoadingMemories set to false: ${isLoadingMemories.value}',
      );
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] loadMemoriesFromDatabase completed',
      );
      print(
        '[MapController][loadMemoriesFromDatabase]: Completion log printed',
      );
    }
    print('[MapController][loadMemoriesFromDatabase]: Method completed');
  }

  Future<Position?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("Location services are disabled.");
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("Location permission denied.");
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("Location permission permanently denied.");
        return null;
      }

      // Try current position
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (e) {
        debugPrint("Error getting current position: $e");
        // Fallback to last known location
        return await Geolocator.getLastKnownPosition();
      }
    } catch (e) {
      debugPrint("Error in getCurrentLocation(): $e");
      return null;
    }
  }

  Future<void> _initializeMemoryClustering() async {
    try {
      debugPrint(
        '[MapController][_initializeMemoryClustering] ========== STARTING CLUSTERING INITIALIZATION ==========',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Total memories in allMemories: ${allMemories.length}',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Current clusters count: ${currentClusters.length}',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Current arrows count: ${currentArrows.length}',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Map controller ready: ${mapController != null}',
      );

      // Reset cluster ID tracking to ensure fresh unique IDs
      debugPrint(
        '[MapController][_initializeMemoryClustering] Resetting cluster ID tracking for fresh start',
      );
      MemoryClusteringService.resetClusterIdTracking();

      // Log all memories before filtering
      debugPrint(
        '[MapController][_initializeMemoryClustering] === ALL MEMORIES DATA ===',
      );
      for (int i = 0; i < allMemories.length; i++) {
        final memory = allMemories[i];
        debugPrint('[MapController][_initializeMemoryClustering] Memory $i:');
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - ID: ${memory['id']}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Title: ${memory['title'] ?? 'No title'}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Location: ${memory['location']}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Latitude: ${memory['latitude']}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Longitude: ${memory['longitude']}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Memory Date: ${memory['memory_date']}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Has valid coords: ${_hasValidCoordinates(memory)}',
        );
      }

      // Convert memories to MemoryLocation objects, filtering out those without valid locations
      debugPrint(
        '[MapController][_initializeMemoryClustering] === FILTERING MEMORIES WITH VALID COORDINATES ===',
      );
      final memoriesWithCoordinates =
          allMemories.where((memory) => _hasValidCoordinates(memory)).toList();

      debugPrint(
        '[MapController][_initializeMemoryClustering] Filtered memories: ${memoriesWithCoordinates.length} out of ${allMemories.length} have valid coordinates',
      );

      // Log filtered memories
      debugPrint(
        '[MapController][_initializeMemoryClustering] === FILTERED MEMORIES DATA ===',
      );
      for (int i = 0; i < memoriesWithCoordinates.length; i++) {
        final memory = memoriesWithCoordinates[i];
        debugPrint(
          '[MapController][_initializeMemoryClustering] Filtered Memory $i:',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - ID: ${memory['id']}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Location: ${memory['location']}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Lat/Lng: ${memory['latitude']}, ${memory['longitude']}',
        );
      }

      debugPrint(
        '[MapController][_initializeMemoryClustering] === CONVERTING TO MEMORY LOCATION OBJECTS ===',
      );
      final memoryLocations =
          memoriesWithCoordinates
              .map((memory) => MemoryLocation.fromMap(memory))
              .where(
                (memoryLocation) =>
                    memoryLocation.latitude != 0.0 &&
                    memoryLocation.longitude != 0.0,
              )
              .toList();

      debugPrint(
        '[MapController][_initializeMemoryClustering] MemoryLocation objects created: ${memoryLocations.length}',
      );

      // Log MemoryLocation objects
      debugPrint(
        '[MapController][_initializeMemoryClustering] === MEMORY LOCATION OBJECTS ===',
      );
      for (int i = 0; i < memoryLocations.length; i++) {
        final memLoc = memoryLocations[i];
        debugPrint(
          '[MapController][_initializeMemoryClustering] MemoryLocation $i:',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - ID: ${memLoc.id}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Title: ${memLoc.title}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Coordinates: ${memLoc.latitude}, ${memLoc.longitude}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Date: ${memLoc.memoryDate}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Metadata: ${memLoc.metadata}',
        );
      }

      debugPrint(
        '[MapController][_initializeMemoryClustering] === FINAL MEMORY LOCATIONS FOR CLUSTERING ===',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Final memory locations count: ${memoryLocations.length}',
      );

      if (memoryLocations.isEmpty) {
        debugPrint(
          '[MapController][_initializeMemoryClustering] ❌ NO VALID MEMORIES FOR CLUSTERING',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering] No memories with valid coordinates found for clustering',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering] Clustering process aborted',
        );
        return;
      }

      // Use fixed 50km clustering radius as requested
      double clusterRadius =
          MemoryClusteringService.cityClusterRadiusKm; // 50km
      debugPrint(
        '[MapController][_initializeMemoryClustering] === CLUSTERING CONFIGURATION ===',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Cluster radius: ${clusterRadius}km',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Memory locations to cluster: ${memoryLocations.length}',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Clustering algorithm: MemoryClusteringService.clusterMemories',
      );

      // Initial clustering with adaptive radius
      debugPrint(
        '[MapController][_initializeMemoryClustering] === STARTING CLUSTERING PROCESS ===',
      );
      final stopwatch = Stopwatch()..start();

      final clusters = MemoryClusteringService.clusterMemories(
        memoryLocations,
        clusterRadius,
      );

      stopwatch.stop();
      debugPrint(
        '[MapController][_initializeMemoryClustering] === CLUSTERING COMPLETED ===',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Clustering duration: ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Generated clusters: ${clusters.length}',
      );

      // Log detailed cluster information and verify ID uniqueness
      debugPrint(
        '[MapController][_initializeMemoryClustering] === CLUSTER DETAILS & ID VERIFICATION ===',
      );
      final Set<String> clusterIds = <String>{};
      final List<String> duplicateIds = <String>[];

      for (int i = 0; i < clusters.length; i++) {
        final cluster = clusters[i];
        debugPrint(
          '[MapController][_initializeMemoryClustering] Cluster ${i + 1}:',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - ID: ${cluster.id}',
        );

        // Check for duplicate IDs
        if (clusterIds.contains(cluster.id)) {
          duplicateIds.add(cluster.id);
          debugPrint(
            '[MapController][_initializeMemoryClustering]   - ❌ DUPLICATE ID DETECTED: ${cluster.id}',
          );
        } else {
          clusterIds.add(cluster.id);
          debugPrint(
            '[MapController][_initializeMemoryClustering]   - ✅ UNIQUE ID: ${cluster.id}',
          );
        }

        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Memory count: ${cluster.memoryCount}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Center: ${cluster.centerLatitude.toStringAsFixed(6)}, ${cluster.centerLongitude.toStringAsFixed(6)}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Radius: ${cluster.radiusKm}km',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Earliest date: ${cluster.earliestDate}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Latest date: ${cluster.latestDate}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Is single memory: ${cluster.memoryCount == 1}',
        );

        // Log memories in this cluster
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Memories in cluster:',
        );
        for (int j = 0; j < cluster.memories.length; j++) {
          final memory = cluster.memories[j];
          debugPrint(
            '[MapController][_initializeMemoryClustering]     Memory ${j + 1}: ${memory.id} - "${memory.title}" at ${memory.latitude}, ${memory.longitude}',
          );
        }
      }

      // Report ID uniqueness results
      debugPrint(
        '[MapController][_initializeMemoryClustering] === CLUSTER ID UNIQUENESS REPORT ===',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Total clusters: ${clusters.length}',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Unique cluster IDs: ${clusterIds.length}',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Duplicate IDs found: ${duplicateIds.length}',
      );

      if (duplicateIds.isNotEmpty) {
        debugPrint(
          '[MapController][_initializeMemoryClustering] ❌ CRITICAL: Duplicate cluster IDs detected: $duplicateIds',
        );
      } else {
        debugPrint(
          '[MapController][_initializeMemoryClustering] ✅ SUCCESS: All cluster IDs are unique',
        );
      }

      debugPrint(
        '[MapController][_initializeMemoryClustering] === ASSIGNING CLUSTERS TO CONTROLLER ===',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Previous currentClusters count: ${currentClusters.length}',
      );
      currentClusters.assignAll(clusters);
      debugPrint(
        '[MapController][_initializeMemoryClustering] New currentClusters count: ${currentClusters.length}',
      );

      // Generate chronological arrows with performance limits
      debugPrint(
        '[MapController][_initializeMemoryClustering] === GENERATING CHRONOLOGICAL ARROWS ===',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Starting arrow generation for ${clusters.length} clusters',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Previous currentArrows count: ${currentArrows.length}',
      );

      final arrowStopwatch = Stopwatch()..start();
      final arrows = _generateOptimizedArrows(clusters);
      arrowStopwatch.stop();

      debugPrint(
        '[MapController][_initializeMemoryClustering] Arrow generation completed in ${arrowStopwatch.elapsedMilliseconds}ms',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Generated arrows count: ${arrows.length}',
      );

      currentArrows.assignAll(arrows);
      debugPrint(
        '[MapController][_initializeMemoryClustering] New currentArrows count: ${currentArrows.length}',
      );

      // Log arrow details
      debugPrint(
        '[MapController][_initializeMemoryClustering] === ARROW DETAILS ===',
      );
      for (int i = 0; i < arrows.length; i++) {
        final arrow = arrows[i];
        debugPrint(
          '[MapController][_initializeMemoryClustering] Arrow ${i + 1}:',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - From: ${arrow.fromLatitude.toStringAsFixed(6)}, ${arrow.fromLongitude.toStringAsFixed(6)}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - To: ${arrow.toLatitude.toStringAsFixed(6)}, ${arrow.toLongitude.toStringAsFixed(6)}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - From Date: ${arrow.fromDate}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - To Date: ${arrow.toDate}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - From Cluster ID: ${arrow.fromClusterId}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - To Cluster ID: ${arrow.toClusterId}',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Distance: ${arrow.distance.toStringAsFixed(2)}km',
        );
        debugPrint(
          '[MapController][_initializeMemoryClustering]   - Bearing: ${arrow.bearing.toStringAsFixed(2)}°',
        );
      }

      debugPrint(
        '[MapController][_initializeMemoryClustering] === SETTING CLUSTER LEVEL ===',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Previous cluster level: ${currentClusterLevel.value}',
      );
      currentClusterLevel.value = ClusterLevel.initial;
      debugPrint(
        '[MapController][_initializeMemoryClustering] New cluster level: ${currentClusterLevel.value}',
      );

      debugPrint(
        '[MapController][_initializeMemoryClustering] === CLUSTERING SUMMARY ===',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Total memories processed: ${memoryLocations.length}',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Clusters created: ${clusters.length}',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Arrows generated: ${arrows.length}',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Cluster level: ${currentClusterLevel.value}',
      );

      // Display clusters on map
      debugPrint(
        '[MapController][_initializeMemoryClustering] === STARTING MAP DISPLAY ===',
      );
      debugPrint(
        '[MapController][_initializeMemoryClustering] Calling _displayMemoryClusters()',
      );
      await _displayMemoryClusters();
      debugPrint(
        '[MapController][_initializeMemoryClustering] Map display completed successfully',
      );

      debugPrint(
        '[MapController][_initializeMemoryClustering] ========== CLUSTERING INITIALIZATION COMPLETED ==========',
      );
    } catch (e) {
      debugPrint('Error initializing memory clustering: $e');
    }
  }

  List<ChronologicalArrow> _generateOptimizedArrows(
    List<MemoryCluster> clusters,
  ) {
    debugPrint(
      '[MapController][_generateOptimizedArrows] === STARTING ARROW GENERATION ===',
    );
    debugPrint(
      '[MapController][_generateOptimizedArrows] Input clusters count: ${clusters.length}',
    );

    // Log cluster information for arrow generation
    debugPrint(
      '[MapController][_generateOptimizedArrows] === CLUSTERS FOR ARROW GENERATION ===',
    );
    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      debugPrint(
        '[MapController][_generateOptimizedArrows] Cluster ${i + 1} for arrows:',
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows]   - ID: ${cluster.id}',
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows]   - Memory count: ${cluster.memoryCount}',
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows]   - Center: ${cluster.centerLatitude}, ${cluster.centerLongitude}',
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows]   - Earliest date: ${cluster.earliestDate}',
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows]   - Latest date: ${cluster.latestDate}',
      );
    }

    // For performance, limit arrow generation for large datasets
    if (clusters.length > 50) {
      debugPrint(
        '[MapController][_generateOptimizedArrows] === PERFORMANCE OPTIMIZATION ===',
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows] Large dataset detected (${clusters.length} clusters)',
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows] Applying performance optimization - using top 30 clusters',
      );

      // Only generate arrows for the most significant clusters (by memory count)
      final sortedClusters = List<MemoryCluster>.from(clusters);
      sortedClusters.sort((a, b) => b.memoryCount.compareTo(a.memoryCount));
      final topClusters = sortedClusters.take(30).toList();

      debugPrint(
        '[MapController][_generateOptimizedArrows] Top clusters selected for arrow generation:',
      );
      for (int i = 0; i < topClusters.length; i++) {
        final cluster = topClusters[i];
        debugPrint(
          '[MapController][_generateOptimizedArrows] Top cluster ${i + 1}: ${cluster.memoryCount} memories',
        );
      }

      debugPrint(
        '[MapController][_generateOptimizedArrows] Calling MemoryClusteringService.generateChronologicalArrows with ${topClusters.length} clusters',
      );
      final arrows = MemoryClusteringService.generateChronologicalArrows(
        topClusters,
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows] Generated ${arrows.length} arrows from optimized clusters',
      );
      return arrows;
    } else {
      debugPrint(
        '[MapController][_generateOptimizedArrows] === STANDARD ARROW GENERATION ===',
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows] Normal dataset size (${clusters.length} clusters)',
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows] Calling MemoryClusteringService.generateChronologicalArrows with all clusters',
      );

      final arrows = MemoryClusteringService.generateChronologicalArrows(
        clusters,
      );
      debugPrint(
        '[MapController][_generateOptimizedArrows] Generated ${arrows.length} arrows from all clusters',
      );
      return arrows;
    }
  }

  bool _hasValidCoordinates(Map<String, dynamic> memory) {
    debugPrint(
      '[MapController][_hasValidCoordinates] === VALIDATING COORDINATES ===',
    );
    debugPrint(
      '[MapController][_hasValidCoordinates] Memory ID: ${memory['id']}',
    );

    final locationStr = memory['location'] as String? ?? '';
    debugPrint(
      '[MapController][_hasValidCoordinates] Location string: "$locationStr"',
    );

    // Skip if location is empty or null
    if (locationStr.isEmpty) {
      debugPrint(
        '[MapController][_hasValidCoordinates] ❌ INVALID: Location string is empty',
      );
      return false;
    }

    // Skip if location doesn't contain coordinates (comma-separated values)
    if (!locationStr.contains(',')) {
      debugPrint(
        '[MapController][_hasValidCoordinates] ❌ INVALID: Location string does not contain comma separator',
      );
      return false;
    }

    final parts = locationStr.split(',');
    debugPrint(
      '[MapController][_hasValidCoordinates] Location parts: ${parts.length} parts - $parts',
    );

    if (parts.length < 2) {
      debugPrint(
        '[MapController][_hasValidCoordinates] ❌ INVALID: Less than 2 coordinate parts',
      );
      return false;
    }

    final latStr = parts[0].trim();
    final lngStr = parts[1].trim();
    debugPrint(
      '[MapController][_hasValidCoordinates] Latitude string: "$latStr"',
    );
    debugPrint(
      '[MapController][_hasValidCoordinates] Longitude string: "$lngStr"',
    );

    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);
    debugPrint('[MapController][_hasValidCoordinates] Parsed latitude: $lat');
    debugPrint('[MapController][_hasValidCoordinates] Parsed longitude: $lng');

    // Skip if coordinates are invalid or zero
    if (lat == null || lng == null) {
      debugPrint(
        '[MapController][_hasValidCoordinates] ❌ INVALID: Failed to parse coordinates as numbers',
      );
      return false;
    }

    // Skip if coordinates are exactly 0,0 (likely default/invalid)
    if (lat == 0.0 && lng == 0.0) {
      debugPrint(
        '[MapController][_hasValidCoordinates] ❌ INVALID: Coordinates are 0,0 (likely default/invalid)',
      );
      return false;
    }

    // Skip if coordinates are outside valid ranges
    if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) {
      debugPrint(
        '[MapController][_hasValidCoordinates] ❌ INVALID: Coordinates outside valid ranges',
      );
      debugPrint(
        '[MapController][_hasValidCoordinates] Latitude range: -90 to 90, got: $lat',
      );
      debugPrint(
        '[MapController][_hasValidCoordinates] Longitude range: -180 to 180, got: $lng',
      );
      return false;
    }

    debugPrint(
      '[MapController][_hasValidCoordinates] ✅ VALID: Coordinates are valid ($lat, $lng)',
    );
    return true;
  }

  Future<void> _displayMemoryClusters({bool clearExisting = true}) async {
    debugPrint(
      '[MapController][_displayMemoryClusters] Starting display process...',
    );
    debugPrint(
      '[MapController][_displayMemoryClusters] clearExisting: $clearExisting',
    );
    debugPrint(
      '[MapController][_displayMemoryClusters] mapController null: ${mapController == null}',
    );
    debugPrint(
      '[MapController][_displayMemoryClusters] currentClusters count: ${currentClusters.length}',
    );
    debugPrint(
      '[MapController][_displayMemoryClusters] currentAnnotationManager null: ${currentAnnotationManager == null}',
    );
    debugPrint(
      '[MapController][_displayMemoryClusters] annotations count: ${annotations.length}',
    );

    // Add retry logic for race condition issues
    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(milliseconds: 500);

    debugPrint(
      '[MapController][_displayMemoryClusters] Starting retry loop with max $maxRetries retries',
    );

    while (retryCount < maxRetries) {
      debugPrint(
        '[MapController][_displayMemoryClusters] Retry attempt ${retryCount + 1}/$maxRetries',
      );

      if (mapController == null) {
        debugPrint(
          '[MapController][_displayMemoryClusters] Map controller is null, retry ${retryCount + 1}/$maxRetries',
        );
        retryCount++;
        if (retryCount < maxRetries) {
          debugPrint(
            '[MapController][_displayMemoryClusters] Waiting ${retryDelay.inMilliseconds}ms before retry',
          );
          await Future.delayed(retryDelay);
          continue;
        } else {
          debugPrint(
            '[MapController][_displayMemoryClusters] CRITICAL: Map controller still null after $maxRetries retries, exiting',
          );
          return;
        }
      }

      if (currentClusters.isEmpty) {
        debugPrint(
          '[MapController][_displayMemoryClusters] Current clusters empty, retry ${retryCount + 1}/$maxRetries',
        );
        retryCount++;
        if (retryCount < maxRetries) {
          debugPrint(
            '[MapController][_displayMemoryClusters] Waiting ${retryDelay.inMilliseconds}ms before retry',
          );
          await Future.delayed(retryDelay);
          continue;
        } else {
          debugPrint(
            '[MapController][_displayMemoryClusters] CRITICAL: Clusters still empty after $maxRetries retries, exiting',
          );
          return;
        }
      }

      // Both conditions satisfied, break out of retry loop
      debugPrint(
        '[MapController][_displayMemoryClusters] Retry conditions satisfied, proceeding with display',
      );
      break;
    }

    try {
      debugPrint(
        '[MapController][_displayMemoryClusters] Starting try block for cluster display',
      );

      // Only clear existing annotations if requested (for initial load or reset)
      if (clearExisting) {
        debugPrint(
          '[MapController][_displayMemoryClusters] Clearing existing annotations...',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] currentAnnotationManager null before clear: ${currentAnnotationManager == null}',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] annotations count before clear: ${annotations.length}',
        );

        if (currentAnnotationManager != null) {
          debugPrint(
            '[MapController][_displayMemoryClusters] Calling deleteAll() on annotation manager',
          );
          await currentAnnotationManager!.deleteAll();
          debugPrint(
            '[MapController][_displayMemoryClusters] deleteAll() completed, setting manager to null',
          );
          currentAnnotationManager = null;
        }

        debugPrint(
          '[MapController][_displayMemoryClusters] Clearing annotations list',
        );
        annotations.clear();
        debugPrint(
          '[MapController][_displayMemoryClusters] Clearing marker images',
        );
        await _clearAllMarkerImages();
        debugPrint('[MapController][_displayMemoryClusters] Clearing lines');
        await _clearAllLines();
        debugPrint(
          '[MapController][_displayMemoryClusters] All clearing operations completed',
        );
      } else {
        debugPrint(
          '[MapController][_displayMemoryClusters] Preserving existing annotations, adding new ones...',
        );
      }

      // Create or reuse annotation manager
      debugPrint(
        '[MapController][_displayMemoryClusters] Checking annotation manager state',
      );
      if (currentAnnotationManager == null) {
        debugPrint(
          '[MapController][_displayMemoryClusters] Creating new annotation manager...',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] mapController available: ${mapController != null}',
        );
        currentAnnotationManager =
            await mapController!.annotations.createPointAnnotationManager();
        debugPrint(
          '[MapController][_displayMemoryClusters] New annotation manager created: ${currentAnnotationManager != null}',
        );
      } else {
        debugPrint(
          '[MapController][_displayMemoryClusters] Reusing existing annotation manager',
        );
      }

      debugPrint(
        '[MapController][_displayMemoryClusters] Initializing marker options list',
      );
      final List<mapbox.PointAnnotationOptions> markerOptions = [];
      debugPrint(
        '[MapController][_displayMemoryClusters] Marker options list initialized, length: ${markerOptions.length}',
      );

      debugPrint(
        '🔄 DISPLAY CLUSTERS - Creating ${currentClusters.length} cluster markers...',
      );

      // Create cluster markers
      for (int i = 0; i < currentClusters.length; i++) {
        final cluster = currentClusters[i];
        final imageName = 'cluster_marker_${cluster.id}';

        debugPrint(
          '[MapController][_displayMemoryClusters] === CREATING UNIQUE IMAGE FOR CLUSTER ===',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] Image name: $imageName',
        );
        debugPrint('[MapController][_displayMemoryClusters] Cluster index: $i');

        // Print all cluster data and its memories
        debugPrint(
          '[MapController][_displayMemoryClusters] === CLUSTER ${i + 1} COMPLETE DATA ===',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] Cluster ID: ${cluster.id}',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] Memory Count: ${cluster.memoryCount}',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] Center Coordinates: ${cluster.centerLatitude.toStringAsFixed(6)}, ${cluster.centerLongitude.toStringAsFixed(6)}',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] Radius: ${cluster.radiusKm}km',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] Earliest Date: ${cluster.earliestDate}',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] Latest Date: ${cluster.latestDate}',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] Is Single Memory: ${cluster.memoryCount == 1}',
        );

        // Print all memories in this cluster
        debugPrint(
          '[MapController][_displayMemoryClusters] === MEMORIES IN CLUSTER ${i + 1} ===',
        );
        for (int memIndex = 0; memIndex < cluster.memories.length; memIndex++) {
          final memory = cluster.memories[memIndex];
          debugPrint(
            '[MapController][_displayMemoryClusters] Memory ${memIndex + 1}:',
          );
          debugPrint(
            '[MapController][_displayMemoryClusters]   - ID: ${memory.id}',
          );
          debugPrint(
            '[MapController][_displayMemoryClusters]   - Title: "${memory.title}"',
          );
          debugPrint(
            '[MapController][_displayMemoryClusters]   - Description: "${memory.description}"',
          );
          debugPrint(
            '[MapController][_displayMemoryClusters]   - Coordinates: ${memory.latitude.toStringAsFixed(6)}, ${memory.longitude.toStringAsFixed(6)}',
          );
          debugPrint(
            '[MapController][_displayMemoryClusters]   - Memory Date: ${memory.memoryDate}',
          );
          debugPrint(
            '[MapController][_displayMemoryClusters]   - Metadata Keys: ${memory.metadata.keys.toList()}',
          );

          // Print specific metadata fields if they exist
          if (memory.metadata.containsKey('location')) {
            debugPrint(
              '[MapController][_displayMemoryClusters]   - Original Location: "${memory.metadata['location']}"',
            );
          }
          if (memory.metadata.containsKey('place_category')) {
            debugPrint(
              '[MapController][_displayMemoryClusters]   - Place Category: "${memory.metadata['place_category']}"',
            );
          }
          if (memory.metadata.containsKey('hashtags')) {
            debugPrint(
              '[MapController][_displayMemoryClusters]   - Hashtags: "${memory.metadata['hashtags']}"',
            );
          }
          if (memory.metadata.containsKey('images')) {
            final images = memory.metadata['images'];
            debugPrint(
              '[MapController][_displayMemoryClusters]   - Has Images: ${images != null && images.toString().isNotEmpty}',
            );
          }
          if (memory.metadata.containsKey('voice_notes')) {
            final voiceNotes = memory.metadata['voice_notes'];
            debugPrint(
              '[MapController][_displayMemoryClusters]   - Has Voice Notes: ${voiceNotes != null && voiceNotes.toString().isNotEmpty}',
            );
          }
          if (memory.metadata.containsKey('created_at')) {
            debugPrint(
              '[MapController][_displayMemoryClusters]   - Created At: "${memory.metadata['created_at']}"',
            );
          }
          if (memory.metadata.containsKey('updated_at')) {
            debugPrint(
              '[MapController][_displayMemoryClusters]   - Updated At: "${memory.metadata['updated_at']}"',
            );
          }

          // Print all metadata for complete visibility
          debugPrint(
            '[MapController][_displayMemoryClusters]   - Complete Metadata: ${memory.metadata}',
          );
        }

        debugPrint(
          '[MapController][_displayMemoryClusters] === END CLUSTER ${i + 1} DATA ===',
        );
        debugPrint(
          '[MapController][_displayMemoryClusters] Creating marker ${i + 1} for cluster at ${cluster.centerLatitude}, ${cluster.centerLongitude}',
        );

        // try {
        // Clear any existing image with this name first
        try {
          await mapController!.style.removeStyleImage(imageName);
          debugPrint(
            '[MapController][_displayMemoryClusters] Removed existing image: $imageName',
          );
        } catch (e) {
          debugPrint(
            '[MapController][_displayMemoryClusters] No existing image to remove: $imageName',
          );
        }

        // Create marker image based on cluster
        debugPrint(
          '[MapController][_displayMemoryClusters] Creating unique image for cluster ${cluster.id}',
        );
        final imageBytes = await _createClusterMarkerImage(cluster, i);

        debugPrint(
          '[MapController][_displayMemoryClusters] Created image bytes: ${imageBytes.length} bytes for $imageName',
        );

        // Use the actual image size instead of hardcoded 60x60
        const int imageSize = 60;

        await mapController!.style.addStyleImage(
          imageName,
          1.0,
          mapbox.MbxImage(
            data: imageBytes,
            width: imageSize,
            height: imageSize,
          ),
          false,
          [],
          [],
          null,
        );

        debugPrint(
          '🔄 [MapController][_displayMemoryClusters] DISPLAY CLUSTERS - Successfully added style image: $imageName',
        );

        // Add marker option only if image creation succeeded
        markerOptions.add(
          mapbox.PointAnnotationOptions(
            geometry: mapbox.Point(
              coordinates: mapbox.Position(
                cluster.centerLongitude,
                cluster.centerLatitude,
              ),
            ),
            iconImage: imageName,
            iconSize: cluster.isSingleMemory ? 0.6 : 0.8,
          ),
        );

        debugPrint(
          '🔄 [MapController][_displayMemoryClusters] DISPLAY CLUSTERS - Added marker option ${i + 1}',
        );

        // } catch (e) {
        //   debugPrint('❌ DISPLAY CLUSTERS - Error creating marker ${i + 1}: $e');
        //   // Skip this marker and continue with the next one
        //   continue;
        // }
      }

      // Create markers

      // Display chronological arrows
      debugPrint('🔄 DISPLAY CLUSTERS - Displaying chronological arrows...');
      await _displayChronologicalArrows();

      // Fit camera to show all clusters
      debugPrint('🔄 DISPLAY CLUSTERS - Fitting camera to clusters...');

      debugPrint(
        '🔄 DISPLAY CLUSTERS - Creating ${markerOptions.length} markers...',
      );
      final created = await currentAnnotationManager!.createMulti(
        markerOptions,
      );
      final validAnnotations =
          created
              .where((a) => a != null)
              .cast<mapbox.PointAnnotation>()
              .toList();
      annotations.assignAll(validAnnotations);

      debugPrint(
        '🔄 DISPLAY CLUSTERS - Created ${validAnnotations.length} valid annotations',
      );

      // Set up click listeners for clusters
      debugPrint('🔄 DISPLAY CLUSTERS - Setting up click listeners...');
      currentAnnotationManager!.addOnPointAnnotationClickListener(
        AnnotationClickListener((annotation) async {
          debugPrint('🔄 DISPLAY CLUSTERS - Cluster marker clicked');
          await _onClusterMarkerTapped(annotation);
        }),
      );

      await _fitCameraToMemoryClusters();

      debugPrint(
        '🔄 DISPLAY CLUSTERS - Display process completed successfully',
      );
    } catch (e) {
      debugPrint('❌ DISPLAY CLUSTERS - Error displaying memory clusters: $e');
      debugPrint('❌ DISPLAY CLUSTERS - Stack trace: ${StackTrace.current}');
    }
  }

  Future<void> _onClusterMarkerTapped(mapbox.PointAnnotation annotation) async {
    try {
      // Find which cluster was tapped
      final tappedCluster = currentClusters.firstWhereOrNull(
        (cluster) =>
            (annotation.geometry.coordinates.lng - cluster.centerLongitude)
                    .abs() <
                0.0001 &&
            (annotation.geometry.coordinates.lat - cluster.centerLatitude)
                    .abs() <
                0.0001,
      );

      if (tappedCluster == null) {
        debugPrint('Could not find tapped cluster');
        return;
      }

      debugPrint('Cluster tapped: ${tappedCluster.memoryCount} memories');

      // Handle cluster tap based on cluster type
      if (tappedCluster.isSingleMemory) {
        // Single memory marker - show snackbar

        var controller = Get.find<AddMemoriesController>();

        controller.showSpecificMemories([tappedCluster.memories.first]);
        var result = await Get.toNamed(Routes.ADD_MEMORIES);

        if (result == true) {
          debugPrint('Result = true');

          await _clearAllLines();
          controller.onAgainInit();
        }

        debugPrint('Showing snackbar for individual memory');
      } else {
        // Cluster marker with multiple memories - drill down
        debugPrint(
          'Drilling down to show individual markers for cluster with ${tappedCluster.memoryCount} memories',
        );
        await _drillDownToCluster(tappedCluster.memories);
      }
    } catch (e) {
      debugPrint('Error handling cluster tap: $e');
    }
  }

  Future<void> _drillDownToSubgroup(MemoryCluster selectedCluster) async {
    try {
      debugPrint(
        'Drilling down to subgroup for cluster with ${selectedCluster.memoryCount} memories',
      );

      this.selectedCluster.value = selectedCluster;
      currentClusterLevel.value = ClusterLevel.subgroup;

      // Re-cluster memories in selected cluster with 100m radius
      final subclusters = MemoryClusteringService.clusterMemories(
        selectedCluster.memories,
        MemoryClusteringService.subgroupClusterRadiusM / 1000, // Convert to km
      );

      currentClusters.assignAll(subclusters);

      // Generate new arrows for subgroup with enhanced logic
      final arrows = _generateDrillDownArrows(subclusters, selectedCluster);
      currentArrows.assignAll(arrows);

      // Update display with smooth transition
      await _displayMemoryClusters();

      debugPrint(
        'Drilled down to ${subclusters.length} subclusters with ${arrows.length} arrows',
      );
    } catch (e) {
      debugPrint('Error drilling down to subgroup: $e');
    }
  }

  List<ChronologicalArrow> _generateDrillDownArrows(
    List<MemoryCluster> subclusters,
    MemoryCluster parentCluster,
  ) {
    // Generate arrows within the subgroup
    final internalArrows = MemoryClusteringService.generateChronologicalArrows(
      subclusters,
    );

    // Also preserve connections to external clusters if they exist
    final externalArrows = <ChronologicalArrow>[];

    // Find connections from this subgroup to other main clusters
    for (final subcluster in subclusters) {
      // Check if any memories in this subcluster connect to memories outside the parent cluster
      for (final memory in subcluster.memories) {
        // This would require access to all memories and their temporal relationships
        // For now, we'll focus on internal arrows within the drill-down view
      }
    }

    return [...internalArrows, ...externalArrows];
  }

  Future<void> _showMemoryListPopup(MemoryCluster cluster) async {
    final memories = cluster.memories.map((m) => m.metadata).toList();

    // Sort by date descending
    memories.sort((a, b) {
      final dateA = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime.now();
      final dateB = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime.now();
      return dateB.compareTo(dateA);
    });

    debugPrint('Showing popup for ${memories.length} memories in cluster');

    // Drill down to show individual markers from this cluster
    _drillDownToCluster(cluster.memories);
  }

  mapbox.PolylineAnnotationManager? _polylineAnnotationManager;

  Future<void> _drillDownToCluster(List<MemoryLocation> clusterMemories) async {
    try {
      debugPrint(
        '🔍 DRILL DOWN - Starting drill down for ${clusterMemories.length} memories',
      );

      // Clear all existing markers and clusters
      await _clearAllMarkersAndClusters();

      // Create sub-clusters from the selected cluster's memories using 100m radius
      final subClusters = await _createSubClusters(
        clusterMemories,
        radiusKm: 0.5,
      ); // 100 meters

      debugPrint('🔍 DRILL DOWN - Created ${subClusters.length} sub-clusters');

      // Update current clusters with sub-clusters
      currentClusters.clear();
      currentClusters.addAll(subClusters);

      // Generate arrows between sub-clusters
      debugPrint(
        '🔍 DRILL DOWN - Generating arrows between ${subClusters.length} sub-clusters',
      );
      final subClusterArrows = _generateOptimizedArrows(subClusters);
      currentArrows.clear();
      currentArrows.addAll(subClusterArrows);
      debugPrint(
        '🔍 DRILL DOWN - Generated ${subClusterArrows.length} arrows between sub-clusters',
      );

      // Log arrow details for debugging
      for (int i = 0; i < subClusterArrows.length; i++) {
        final arrow = subClusterArrows[i];
        debugPrint(
          '🔍 DRILL DOWN - Arrow ${i + 1}: ${arrow.fromLatitude}, ${arrow.fromLongitude} → ${arrow.toLatitude}, ${arrow.toLongitude}',
        );
      }

      // Display arrows first (bottom layer)
      debugPrint('🔍 DRILL DOWN - Displaying arrows as bottom layer');
      await _displayChronologicalArrows();

      // Then display the sub-clusters on top (skip arrows since we already displayed them)
      debugPrint('🔍 DRILL DOWN - Displaying sub-clusters on top of arrows');
      await _displayMemoryMarkersOnly(); // Custom method that only displays markers, not arrows

      debugPrint('🔍 DRILL DOWN - Drill down completed');
    } catch (e) {
      debugPrint('❌ DRILL DOWN - Error during drill down: $e');
    }
  }

  int index = 1;

  Future<void> _displayMemoryMarkersOnly() async {
    index = 0;
    if (mapController == null || currentClusters.isEmpty) {
      debugPrint(
        '🔄 DISPLAY MARKERS ONLY - Exiting early due to null controller or empty clusters',
      );
      return;
    }

    try {
      debugPrint(
        '🔄 DISPLAY MARKERS ONLY - Starting marker display process...',
      );

      // Create annotation manager if needed
      if (currentAnnotationManager == null) {
        debugPrint(
          '🔄 DISPLAY MARKERS ONLY - Creating new annotation manager...',
        );
        currentAnnotationManager =
            await mapController!.annotations.createPointAnnotationManager();
      } else {
        debugPrint(
          '🔄 DISPLAY MARKERS ONLY - Reusing existing annotation manager...',
        );
      }
      final List<mapbox.PointAnnotationOptions> markerOptions = [];

      debugPrint(
        '🔄 DISPLAY MARKERS ONLY - Creating ${currentClusters.length} cluster markers...',
      );

      // Create cluster markers
      for (int i = 0; i < currentClusters.length; i++) {
        index = index++;
        final cluster = currentClusters[i];
        final imageName = 'cluster_marker_${cluster.id}';

        debugPrint(
          '🔄 DISPLAY MARKERS ONLY - Creating marker ${i + 1} for cluster at ${cluster.centerLatitude}, ${cluster.centerLongitude}',
        );

        try {
          // Create marker image based on cluster
          final imageBytes = await _createClusterMarkerImage(cluster, index);

          debugPrint(
            '🔄 DISPLAY MARKERS ONLY - Adding style image: $imageName (${imageBytes.length} bytes)',
          );

          // Use the actual image size instead of hardcoded 60x60
          const int imageSize = 60;

          await mapController!.style.addStyleImage(
            imageName,
            1.0,
            mapbox.MbxImage(
              data: imageBytes,
              width: imageSize,
              height: imageSize,
            ),
            false,
            [],
            [],
            null,
          );

          debugPrint(
            '🔄 DISPLAY MARKERS ONLY - Successfully added style image: $imageName',
          );

          // Add marker option only if image creation succeeded
          markerOptions.add(
            mapbox.PointAnnotationOptions(
              geometry: mapbox.Point(
                coordinates: mapbox.Position(
                  cluster.centerLongitude,
                  cluster.centerLatitude,
                ),
              ),
              iconImage: imageName,
              iconSize: cluster.isSingleMemory ? 0.6 : 0.8,
            ),
          );

          debugPrint('🔄 DISPLAY MARKERS ONLY - Added marker option ${i + 1}');
        } catch (e) {
          debugPrint(
            '❌ DISPLAY MARKERS ONLY - Error creating marker ${i + 1}: $e',
          );
          // Skip this marker and continue with the next one
          continue;
        }
      }

      // Create markers
      debugPrint(
        '🔄 DISPLAY MARKERS ONLY - Creating ${markerOptions.length} markers...',
      );
      final created = await currentAnnotationManager!.createMulti(
        markerOptions,
      );
      final validAnnotations =
          created
              .where((a) => a != null)
              .cast<mapbox.PointAnnotation>()
              .toList();
      annotations.assignAll(validAnnotations);

      debugPrint(
        '🔄 DISPLAY MARKERS ONLY - Created ${validAnnotations.length} valid annotations',
      );

      // Set up click listeners for drill-down clusters (different behavior)
      debugPrint(
        '🔄 DISPLAY MARKERS ONLY - Setting up drill-down click listeners...',
      );
      currentAnnotationManager!.addOnPointAnnotationClickListener(
        AnnotationClickListener((annotation) async {
          debugPrint('🔄 DISPLAY MARKERS ONLY - Drill-down marker clicked');
          await _onDrillDownMarkerTapped(annotation);
        }),
      );

      // Fit camera to show all clusters
      debugPrint('🔄 DISPLAY MARKERS ONLY - Fitting camera to clusters...');
      await _fitCameraToMemoryClusters();

      debugPrint(
        '🔄 DISPLAY MARKERS ONLY - Marker display process completed successfully',
      );
    } catch (e) {
      debugPrint(
        '❌ DISPLAY MARKERS ONLY - Error displaying memory markers: $e',
      );
      debugPrint('❌ DISPLAY MARKERS ONLY - Stack trace: ${StackTrace.current}');
    }
  }

  Future<void> _onDrillDownMarkerTapped(
    mapbox.PointAnnotation annotation,
  ) async {
    try {
      // Find which cluster was tapped
      final tappedCluster = currentClusters.firstWhereOrNull(
        (cluster) =>
            (annotation.geometry.coordinates.lng - cluster.centerLongitude)
                    .abs() <
                0.0001 &&
            (annotation.geometry.coordinates.lat - cluster.centerLatitude)
                    .abs() <
                0.0001,
      );

      if (tappedCluster == null) {
        debugPrint('❌ DRILL-DOWN TAP - Could not find tapped cluster');
        return;
      }

      debugPrint(
        '🎯 DRILL-DOWN TAP - Cluster found with ${tappedCluster.memoryCount} memories',
      );

      // Handle tap based on cluster type with detailed logging
      if (tappedCluster.isSingleMemory) {
        // Single memory marker - show detailed information
        final memory = tappedCluster.memories.first;

        var controller = Get.find<AddMemoriesController>();

        controller.showSpecificMemories([tappedCluster.memories.first]);
        var result = await Get.toNamed(Routes.ADD_MEMORIES);

        if (result == true) {
          debugPrint('Result = true');

          await _clearAllLines();

          await _clearAllMarkersAndClusters();
          await _initializeMemoryClustering();
        }

        debugPrint('🎯 SINGLE MARKER TAPPED - Detailed Information:');
        debugPrint('  📍 Location: ${memory.latitude}, ${memory.longitude}');
        debugPrint('  🆔 Memory ID: ${memory.id}');
        debugPrint('  📅 Date: ${memory.memoryDate}');
        debugPrint('  📝 Title: ${memory.metadata['title'] ?? 'No title'}');
        debugPrint(
          '  📄 Description: ${memory.metadata['description'] ?? 'No description'}',
        );
        debugPrint(
          '  📂 Category: ${memory.metadata['category'] ?? 'No category'}',
        );
        debugPrint('  🏷️ Tags: ${memory.metadata['tags'] ?? 'No tags'}');
        debugPrint(
          '  📱 Created At: ${memory.metadata['created_at'] ?? 'Unknown'}',
        );
        debugPrint(
          '  🔄 Updated At: ${memory.metadata['updated_at'] ?? 'Unknown'}',
        );
        debugPrint(
          '  🗺️ Location String: ${memory.metadata['location'] ?? 'No location string'}',
        );
        debugPrint(
          '  📸 Has Images: ${memory.metadata['images']?.isNotEmpty ?? false}',
        );
        debugPrint(
          '  🎵 Has Audio: ${memory.metadata['audio_path']?.isNotEmpty ?? false}',
        );
      } else {
        // Cluster marker with multiple memories - show detailed cluster information
        debugPrint('🎯 CLUSTER TAPPED - Detailed Information:');
        debugPrint('  🔢 Memory Count: ${tappedCluster.memoryCount}');
        debugPrint(
          '  📍 Center Location: ${tappedCluster.centerLatitude}, ${tappedCluster.centerLongitude}',
        );
        debugPrint('  🆔 Cluster ID: ${tappedCluster.id}');
        debugPrint('  📏 Radius: ${tappedCluster.radiusKm}km');
        debugPrint(
          '  📅 Date Range: ${tappedCluster.earliestDate} to ${tappedCluster.latestDate}',
        );

        debugPrint('  📋 Individual Memories in Cluster:');

        // Convert cluster memories to the format expected by AddMemoriesController
        final specificMemories =
            tappedCluster.memories
                .map((memoryLocation) => memoryLocation.metadata)
                .toList();

        // Show bottom panel with cluster memories
        showLocationBottomPanel(
          Get.context!,
          tappedCluster,
          specificMemories: specificMemories,
        );
      }
    } catch (e) {
      debugPrint('❌ DRILL-DOWN TAP - Error handling marker tap: $e');
    }
  }

  void _showClusterMemoriesBottomPanel(MemoryCluster cluster) {
    Get.bottomSheet(BottomPanel(cluster));
  }

  Widget _buildMemoryDetailsGrid(MemoryLocation memory) {
    final metadata = memory.metadata;

    return Column(
      children: [
        // Location and date row
        Row(
          children: [
            Expanded(
              child: _buildDetailItem(
                icon: Icons.location_on,
                label: 'Location',
                value:
                    '${memory.latitude.toStringAsFixed(6)}, ${memory.longitude.toStringAsFixed(6)}',
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDetailItem(
                icon: Icons.calendar_today,
                label: 'Date',
                value: _formatDate(memory.memoryDate),
                color: Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Category and ID row
        Row(
          children: [
            Expanded(
              child: _buildDetailItem(
                icon: Icons.category,
                label: 'Category',
                value: metadata['category']?.toString() ?? 'None',
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDetailItem(
                icon: Icons.tag,
                label: 'ID',
                value: memory.id.toString(),
                color: Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Media indicators
        Row(
          children: [
            if (metadata['images']?.isNotEmpty == true)
              _buildMediaIndicator(Icons.image, 'Images', Colors.green),
            if (metadata['audio_path']?.isNotEmpty == true)
              _buildMediaIndicator(Icons.audiotrack, 'Audio', Colors.blue),
            if (metadata['video_path']?.isNotEmpty == true)
              _buildMediaIndicator(Icons.videocam, 'Video', Colors.red),
            if (metadata['tags']?.isNotEmpty == true)
              _buildMediaIndicator(Icons.local_offer, 'Tags', Colors.orange),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMediaIndicator(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  // Keep ONE (or a list, if you prefer) polyline manager you can clear later
  final _polylineManagers = <mapbox.PolylineAnnotationManager>[];

  RxBool mapLoadedSuccessfully = false.obs;

  Future<mapbox.PolylineAnnotationManager> _getPolylineManager() async {
    if (_polylineAnnotationManager == null && mapController != null) {
      _polylineAnnotationManager =
          await mapController!.annotations.createPolylineAnnotationManager();
      _polylineManagers.add(_polylineAnnotationManager!);
    }
    return _polylineAnnotationManager!;
  }

  Future<void> _clearPolylineAnnotations() async {
    // Clear current single manager
    if (_polylineAnnotationManager != null) {
      try {
        await _polylineAnnotationManager!.deleteAll();
      } catch (_) {}
      _polylineAnnotationManager = null;
    }
    // Belt-and-suspenders: if any others were ever created, wipe them too
    for (final m in _polylineManagers) {
      try {
        await m.deleteAll();
      } catch (_) {}
    }
    _polylineManagers.clear();
  }

  Future<void> _clearAllMarkersAndClusters() async {
    try {
      debugPrint(
        '🧹 CLEAR - Clearing all markers, clusters, lines, and arrows',
      );

      // Point annotations (markers + arrow heads)
      if (currentAnnotationManager != null) {
        await currentAnnotationManager!.deleteAll();
        currentAnnotationManager = null;
      }
      annotations.clear();

      // Polyline annotations (chronological arrows)
      await _clearPolylineAnnotations();

      // In-memory state
      currentClusters.clear();
      currentArrows.clear();

      // Style images & style-based layers
      await _clearAllMarkerImages();
      await _clearAllLines(); // (style layers/sources only)

      debugPrint('🧹 CLEAR - All markers, clusters, lines, and arrows cleared');
    } catch (e) {
      debugPrint('❌ CLEAR - Error clearing everything: $e');
    }
  }

  Future<void> _clearMarkersAndClustersOnly() async {
    try {
      debugPrint(
        '🧹 CLEAR - Clearing markers and clusters (preserving arrows)',
      );

      // Clear annotation manager
      if (currentAnnotationManager != null) {
        await currentAnnotationManager!.deleteAll();
        currentAnnotationManager = null;
      }

      // Clear only markers and clusters, preserve arrows
      annotations.clear();
      currentClusters.clear();
      // Note: NOT clearing currentArrows to preserve them for drill-down

      // Clear marker images
      await _clearAllMarkerImages();

      debugPrint('🧹 CLEAR - Markers and clusters cleared (arrows preserved)');
    } catch (e) {
      debugPrint('❌ CLEAR - Error clearing markers: $e');
    }
  }

  Future<List<MemoryCluster>> _createSubClusters(
    List<MemoryLocation> memories, {
    required double radiusKm,
  }) async {
    debugPrint(
      '🔄 SUB-CLUSTERING - Creating sub-clusters with ${radiusKm * 1000}m radius for ${memories.length} memories',
    );

    final clusters = <MemoryCluster>[];
    final processed = <bool>[];

    // Initialize processed array
    for (int i = 0; i < memories.length; i++) {
      processed.add(false);
    }

    for (int i = 0; i < memories.length; i++) {
      if (processed[i]) continue;

      final currentMemory = memories[i];
      final clusterMemories = <MemoryLocation>[currentMemory];
      processed[i] = true;

      // Find all memories within radius
      for (int j = i + 1; j < memories.length; j++) {
        if (processed[j]) continue;

        final otherMemory = memories[j];
        final distance = MemoryClusteringService.calculateDistance(
          currentMemory.latitude,
          currentMemory.longitude,
          otherMemory.latitude,
          otherMemory.longitude,
        );

        if (distance <= radiusKm) {
          clusterMemories.add(otherMemory);
          processed[j] = true;
          debugPrint(
            '🔄 SUB-CLUSTERING - Added memory to cluster (distance: ${(distance * 1000).toStringAsFixed(0)}m)',
          );
        }
      }

      // Calculate cluster center
      double totalLat = 0;
      double totalLng = 0;
      for (final memory in clusterMemories) {
        totalLat += memory.latitude;
        totalLng += memory.longitude;
      }

      final centerLat = totalLat / clusterMemories.length;
      final centerLng = totalLng / clusterMemories.length;

      final cluster = MemoryCluster(
        id: MemoryClusteringService.generateUniqueClusterId(),
        centerLatitude: centerLat,
        centerLongitude: centerLng,
        memories: clusterMemories,
        radiusKm: radiusKm,
      );

      clusters.add(cluster);
      debugPrint(
        '🔄 SUB-CLUSTERING - Created sub-cluster ${clusters.length} with ${clusterMemories.length} memories at $centerLat, $centerLng',
      );
    }

    debugPrint(
      '🔄 SUB-CLUSTERING - Sub-clustering completed: ${clusters.length} clusters created',
    );
    return clusters;
  }

  Future<void> resetToInitialClustering() async {
    try {
      debugPrint('Resetting to initial clustering view');

      currentClusterLevel.value = ClusterLevel.initial;
      selectedCluster.value = null;

      // Re-initialize clustering with all memories
      await _initializeMemoryClustering();
    } catch (e) {
      debugPrint('Error resetting to initial clustering: $e');
    }
  }

  // Public method to handle back navigation with proper arrow updates
  Future<void> navigateBack() async {
    if (currentClusterLevel.value == ClusterLevel.subgroup) {
      await resetToInitialClustering();
    } else {
      // Already at initial level, navigate back to previous screen
      Get.back();
    }
  }

  // Method to refresh clustering when new memories are added
  Future<void> refreshMemoryClustering() async {
    debugPrint('Refreshing memory clustering...');
    await loadMemoriesFromDatabase();
  }

  // Method to ensure clustering is properly initialized (handles race conditions)
  Future<void> ensureClusteringInitialized() async {
    debugPrint('🔄 ENSURING CLUSTERING - Checking clustering state...');

    // If we have memories but no clusters, try to initialize clustering
    if (allMemories.isNotEmpty &&
        currentClusters.isEmpty &&
        mapController != null) {
      //   debugPrint('🔄 ENSURING CLUSTERING - Found memories but no clusters, reinitializing...');
      await _initializeMemoryClustering();
    } else if (currentClusters.isNotEmpty && mapController != null) {
      //   debugPrint('🔄 ENSURING CLUSTERING - Clusters exist, ensuring they are displayed...');
      await _displayMemoryClusters(clearExisting: false);
    } else {
      //   debugPrint('🔄 ENSURING CLUSTERING - State: memories=${allMemories.length}, clusters=${currentClusters.length}, mapReady=${mapController != null}');
    }
  }

  // Method to get clustering statistics for debugging
  Map<String, dynamic> getClusteringStats() {
    return {
      'totalMemories': allMemories.length,
      'currentClusters': currentClusters.length,
      'currentArrows': currentArrows.length,
      'clusterLevel': currentClusterLevel.value.toString(),
      'selectedCluster': selectedCluster.value?.id,
      'isLoading': isLoadingMemories.value,
      'mapReady': mapController != null,
    };
  }

  // Public method to manually trigger clustering (useful for debugging race conditions)
  Future<void> manuallyTriggerClustering() async {
    debugPrint('🔄 MANUAL CLUSTERING - Manually triggering clustering...');
    await ensureClusteringInitialized();
  }

  // Public method to refresh the entire map view and display initial clusters
  Future<void> refreshMapView() async {
    print('[MapController][refreshMapView]: Entered method');
    try {
      print('[MapController][refreshMapView]: Entered try block');

      // Log current tile count before refresh to verify it's preserved
      final downloadService = Get.find<BackgroundTileDownloadService>();
      final currentTiles = downloadService.totalTilesDownloaded.value;
      print(
        '[MapController][refreshMapView]: Current tiles before refresh: $currentTiles',
      );

      isRefreshing.value = true;
      print(
        '[MapController][refreshMapView]: isRefreshing set to true: ${isRefreshing.value}',
      );
      debugPrint('🔄 REFRESH MAP - Starting map view refresh...');
      print('[MapController][refreshMapView]: Starting refresh log printed');

      // Reset to initial clustering state
      print('[MapController][refreshMapView]: About to reset clustering state');
      currentClusterLevel.value = ClusterLevel.initial;
      print(
        '[MapController][refreshMapView]: currentClusterLevel set to: ${currentClusterLevel.value}',
      );
      selectedCluster.value = null;
      print(
        '[MapController][refreshMapView]: selectedCluster set to null: ${selectedCluster.value}',
      );

      // Clear existing annotations and arrows
      print(
        '[MapController][refreshMapView]: Checking currentAnnotationManager: ${currentAnnotationManager != null}',
      );
      if (currentAnnotationManager != null) {
        print(
          '[MapController][refreshMapView]: currentAnnotationManager is not null, deleting all annotations',
        );
        await currentAnnotationManager!.deleteAll();
        print('[MapController][refreshMapView]: All annotations deleted');
        currentAnnotationManager = null;
        print(
          '[MapController][refreshMapView]: currentAnnotationManager set to null',
        );
      } else {
        print(
          '[MapController][refreshMapView]: currentAnnotationManager is null, skipping deletion',
        );
      }
      annotations.clear();
      print(
        '[MapController][refreshMapView]: annotations cleared, count: ${annotations.length}',
      );
      currentClusters.clear();
      print(
        '[MapController][refreshMapView]: currentClusters cleared, count: ${currentClusters.length}',
      );
      currentArrows.clear();
      print(
        '[MapController][refreshMapView]: currentArrows cleared, count: ${currentArrows.length}',
      );

      // Clear all marker images and lines
      print(
        '[MapController][refreshMapView]: About to call _clearAllMarkerImages()',
      );
      await _clearAllMarkerImages();
      print(
        '[MapController][refreshMapView]: _clearAllMarkerImages() completed',
      );
      print('[MapController][refreshMapView]: About to call _clearAllLines()');
      await _clearAllLines();
      print('[MapController][refreshMapView]: _clearAllLines() completed');

      // Check connectivity and setup tile downloading if internet is available
      print(
        '[MapController][refreshMapView]: About to check connectivity and setup tile downloading',
      );
      await _checkConnectivityAndSetupTileDownloading();
      print(
        '[MapController][refreshMapView]: Connectivity check and tile setup completed',
      );

      // Reload memories from database and reinitialize clustering
      print(
        '[MapController][refreshMapView]: About to call loadMemoriesFromDatabase()',
      );
      await loadMemoriesFromDatabase();
      print(
        '[MapController][refreshMapView]: loadMemoriesFromDatabase() completed',
      );

      // Verify tile count is preserved after refresh
      final tilesAfterRefresh = downloadService.totalTilesDownloaded.value;
      print(
        '[MapController][refreshMapView]: Tiles after refresh: $tilesAfterRefresh (preserved: ${currentTiles == tilesAfterRefresh})',
      );

      debugPrint('🔄 REFRESH MAP - Map view refresh completed');
      print('[MapController][refreshMapView]: Refresh completed log printed');
    } catch (e) {
      print('[MapController][refreshMapView]: Caught exception: $e');
      debugPrint('❌ ERROR refreshing map view: $e');
      print('[MapController][refreshMapView]: Error log printed');
      print('[MapController][refreshMapView]: About to rethrow exception');
      rethrow; // Re-throw to let the UI handle the error
    } finally {
      print('[MapController][refreshMapView]: Entered finally block');
      isRefreshing.value = false;
      print(
        '[MapController][refreshMapView]: isRefreshing set to false: ${isRefreshing.value}',
      );
      print('[MapController][refreshMapView]: Finally block completed');
    }
    print('[MapController][refreshMapView]: Method completed');
  }

  /// Check connectivity and setup tile downloading if internet is available
  Future<void> _checkConnectivityAndSetupTileDownloading() async {
    try {
      print(
        '[MapController][_checkConnectivityAndSetupTileDownloading]: Checking connectivity and tile download status',
      );

      // Get connectivity service
      final connectivityService = Get.find<ConnectivityService>();
      print(
        '[MapController][_checkConnectivityAndSetupTileDownloading]: ConnectivityService obtained',
      );

      // Force refresh connectivity status
      await connectivityService.refreshConnectivity();
      print(
        '[MapController][_checkConnectivityAndSetupTileDownloading]: Connectivity refreshed',
      );

      // Check if we have internet
      // final hasIntadernet = connectivityService.isConnected.value;
      // print('[MapController][_checkConnectivityAndSetupTileDownloading]: Has internet: $hasInternet');

      bool hasInternet = await connectivityService.hasInternetForMapbox();

      // If Mapbox check fails, try quick check as fallback
      if (!hasInternet) {
        hasInternet = await connectivityService.hasInternetQuickCheck();
        debugPrint(
          '🌐 [InternetRequiredScreen] Fallback quick check result: $hasInternet',
        );
      }

      if (hasInternet) {
        print(
          '[MapController][_checkConnectivityAndSetupTileDownloading]: Internet available, setting up tile downloading',
        );

        // Check if background tile service is available
        try {
          final downloadService = Get.find<BackgroundTileDownloadService>();
          print(
            '[MapController][_checkConnectivityAndSetupTileDownloading]: BackgroundTileDownloadService found',
          );

          // Check if downloading is already in progress
          final isCurrentlyDownloading = downloadService.isDownloading.value;
          print(
            '[MapController][_checkConnectivityAndSetupTileDownloading]: Currently downloading: $isCurrentlyDownloading',
          );

          if (!isCurrentlyDownloading) {
            print(
              '[MapController][_checkConnectivityAndSetupTileDownloading]: Not currently downloading, starting tile download setup',
            );

            // Check current tile count
            final currentTiles = downloadService.totalTilesDownloaded.value;
            final maxTiles = downloadService.maxTilesLimit.value;
            print(
              '[MapController][_checkConnectivityAndSetupTileDownloading]: Current tiles: $currentTiles, Max tiles: $maxTiles',
            );

            if (currentTiles < maxTiles) {
              print(
                '[MapController][_checkConnectivityAndSetupTileDownloading]: Space available for more tiles, starting offline map setup',
              );

              // Start offline map setup in background (non-blocking)
              setupOfflineMap().catchError((error) {
                print(
                  '[MapController][_checkConnectivityAndSetupTileDownloading]: Error in setupOfflineMap: $error',
                );
              });

              // Also restart background downloads if they were stopped
              if (downloadService.stopDownloading.value) {
                print(
                  '[MapController][_checkConnectivityAndSetupTileDownloading]: Downloads were stopped, restarting',
                );
                downloadService.stopDownloading.value = false;
                await downloadService.setAutoDownloadEnabled(true);
                print(
                  '[MapController][_checkConnectivityAndSetupTileDownloading]: Background downloads restarted',
                );
              }
            } else {
              print(
                '[MapController][_checkConnectivityAndSetupTileDownloading]: Tile limit reached, skipping download setup',
              );
            }
          } else {
            print(
              '[MapController][_checkConnectivityAndSetupTileDownloading]: Already downloading, skipping setup',
            );
          }
        } catch (e) {
          print(
            '[MapController][_checkConnectivityAndSetupTileDownloading]: BackgroundTileDownloadService not available: $e',
          );

          // Initialize the service if it's not available

          print(
            '[MapController][_checkConnectivityAndSetupTileDownloading]: Attempting to initialize background tile service',
          );

          await _initializeBackgroundTileService();
        }
      } else {
        print(
          '[MapController][_checkConnectivityAndSetupTileDownloading]: No internet available, skipping tile download setup',
        );
      }

      print(
        '[MapController][_checkConnectivityAndSetupTileDownloading]: Connectivity check and setup completed',
      );
    } catch (e) {
      print(
        '[MapController][_checkConnectivityAndSetupTileDownloading]: Error during connectivity check and setup: $e',
      );
    }
  }

  // Debug method to check database contents without map initialization
  Future<void> debugDatabaseContents() async {
    try {
      debugPrint('🔍 DATABASE DEBUG - Checking database contents...');

      final memories = await _databaseHelper.getAllMemoriesWithDetails();
      debugPrint(
        '🔍 DATABASE DEBUG - Found ${memories.length} memories in database',
      );

      if (memories.isEmpty) {
        debugPrint(
          '🔍 DATABASE DEBUG - Database is empty. No memories to display.',
        );
        return;
      }

      // Analyze location data
      MemoryClusteringService.debugMemoryLocations(memories);

      // Check if any memories have valid coordinates
      int validLocationCount = 0;
      for (final memory in memories) {
        if (_hasValidCoordinates(memory)) {
          validLocationCount++;
        }
      }

      debugPrint(
        '🔍 DATABASE DEBUG - $validLocationCount out of ${memories.length} memories have valid coordinates',
      );

      if (validLocationCount == 0) {
        debugPrint(
          '🔍 DATABASE DEBUG - No memories have valid location coordinates!',
        );
        debugPrint(
          '🔍 DATABASE DEBUG - To see markers on the map, add memories with location data.',
        );
        debugPrint(
          '🔍 DATABASE DEBUG - Location format should be: "latitude,longitude" (e.g., "37.7749,-122.4194")',
        );
      }
    } catch (e) {
      debugPrint('❌ DATABASE DEBUG - Error checking database: $e');
    }
  }

  // Fallback method to show dummy markers for testing when no real memories have coordinates
  Future<void> _showDummyMarkersForTesting() async {
    if (mapController == null) return;

    try {
      debugPrint('🔄 DUMMY MARKERS - Creating test markers at user location');

      // Clear existing annotations
      if (currentAnnotationManager != null) {
        await currentAnnotationManager!.deleteAll();
        currentAnnotationManager = null;
      }
      annotations.clear();
      await _clearAllMarkerImages();

      // Create annotation manager
      currentAnnotationManager =
          await mapController!.annotations.createPointAnnotationManager();

      // Get user's current location or use a default
      double userLat = 37.7749; // Default to San Francisco
      double userLng = -122.4194;

      try {
        final position = await geolocator.Geolocator.getCurrentPosition();
        userLat = position.latitude;
        userLng = position.longitude;
        debugPrint(
          '🔄 DUMMY MARKERS - Using user location: $userLat, $userLng',
        );
      } catch (e) {
        debugPrint(
          '🔄 DUMMY MARKERS - Could not get user location, using default: $e',
        );
      }

      // Create a few test markers around user location
      final testLocations = [];

      final List<mapbox.PointAnnotationOptions> markerOptions = [];

      for (int i = 0; i < testLocations.length; i++) {
        final location = testLocations[i];

        // Create test marker image
        final imageBytes = await _createTestMarkerImage(
          location['count'] as int,
          i == 0,
        );
        final imageName = 'test_marker_$i';

        await mapController!.style.addStyleImage(
          imageName,
          1.0,
          mapbox.MbxImage(data: imageBytes, width: 50, height: 50),
          false,
          [],
          [],
          null,
        );

        markerOptions.add(
          mapbox.PointAnnotationOptions(
            geometry: mapbox.Point(
              coordinates: mapbox.Position(
                location['lng'] as double,
                location['lat'] as double,
              ),
            ),
            iconImage: imageName,
            iconSize: 0.8,
          ),
        );
      }

      // Create markers
      final created = await currentAnnotationManager!.createMulti(
        markerOptions,
      );
      annotations.assignAll(
        created.where((a) => a != null).cast<mapbox.PointAnnotation>(),
      );

      // Set up click listeners
      currentAnnotationManager!.addOnPointAnnotationClickListener(
        AnnotationClickListener((annotation) async {
          debugPrint('🔄 DUMMY MARKERS - Test marker clicked');
          Get.snackbar(
            'Test Marker',
            'This is a test marker. Add memories with location data to see real clustering.',
            backgroundColor: Colors.blue.withValues(alpha: 0.8),
            colorText: Colors.white,
          );
        }),
      );

      // Fit camera to show test markers
      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: mapbox.Position(userLng, userLat)),
          zoom: 12.0,
        ),
        mapbox.MapAnimationOptions(duration: 1000),
      );

      debugPrint(
        '🔄 DUMMY MARKERS - Created ${testLocations.length} test markers',
      );
    } catch (e) {
      debugPrint('❌ DUMMY MARKERS - Error creating test markers: $e');
    }
  }

  Future<Uint8List> _createTestMarkerImage(
    int count,
    bool isUserLocation,
  ) async {
    const double size = 50.0;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final radius = size / 2;

    // Choose color
    final Color markerColor =
        isUserLocation
            ? const Color(0xFF2196F3) // Blue for user location
            : const Color(0xFFFF9800); // Orange for test clusters

    // Draw circle
    final paint = Paint()..color = markerColor;
    canvas.drawCircle(Offset(radius, radius), radius - 3, paint);

    // Add white border
    final border =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
    canvas.drawCircle(Offset(radius, radius), radius - 3, border);

    // Draw count or icon
    if (isUserLocation) {
      // Draw a person icon or dot
      final iconPaint = Paint()..color = Colors.white;
      canvas.drawCircle(Offset(radius, radius), 8, iconPaint);
    } else {
      // Draw count text
      final textPainter = TextPainter(
        text: TextSpan(
          text: count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(radius - textPainter.width / 2, radius - textPainter.height / 2),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _createSingleMemoryMarker(
    MemoryCluster cluster,
    int clusterIndex,
    double size,
  ) async {
    final radius = size / 2;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    final markerColor = _getUniqueColorForCluster(
      cluster.id,
      cluster.memories[0].id,
    );
    const borderColor = Colors.white;
    const borderWidth = 3.0;

    // Transparent background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size),
      Paint()..color = Colors.transparent,
    );

    // Draw circle
    canvas.drawCircle(
      Offset(radius, radius),
      radius - 6,
      Paint()..color = markerColor,
    );

    // Border
    canvas.drawCircle(
      Offset(radius, radius),
      radius - 6,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    // Index text
    final textPainter = TextPainter(
      text: TextSpan(
        text: (clusterIndex + 1).toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              offset: Offset(0.5, 0.5),
              blurRadius: 1,
              color: Colors.black87,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(radius - textPainter.width / 2, radius - textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _createMultiMemoryMarker(
    MemoryCluster cluster,
    double size,
  ) async {
    final radius = size / 2;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    Color markerColor;
    if (cluster.memoryCount <= 5) {
      markerColor = const Color(0xFF4CAF50); // Green
    } else if (cluster.memoryCount <= 15) {
      markerColor = const Color(0xFFFF9800); // Orange
    } else if (cluster.memoryCount <= 50) {
      markerColor = const Color(0xFFF44336); // Red
    } else {
      markerColor = const Color(0xFF9C27B0); // Purple
    }

    const borderColor = Color(0xFFFFD700); // Gold
    const borderWidth = 4.0;

    // Transparent background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size),
      Paint()..color = Colors.transparent,
    );

    // Outer ring
    canvas.drawCircle(
      Offset(radius, radius),
      radius - 3,
      Paint()
        ..color = borderColor.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0,
    );

    // Main circle
    canvas.drawCircle(
      Offset(radius, radius),
      radius - 6,
      Paint()..color = markerColor,
    );

    // Border
    canvas.drawCircle(
      Offset(radius, radius),
      radius - 6,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = borderWidth,
    );

    // Count text
    final fontSize =
        cluster.memoryCount > 99
            ? 10.0
            : cluster.memoryCount > 9
            ? 12.0
            : 14.0;
    final textPainter = TextPainter(
      text: TextSpan(
        text: cluster.memoryCount.toString(),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(
              offset: Offset(0.5, 0.5),
              blurRadius: 1,
              color: Colors.black87,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(radius - textPainter.width / 2, radius - textPainter.height / 2),
    );

    // Indicator dots
    if (cluster.memoryCount > 1) {
      final indicatorPaint =
          Paint()
            ..color = Colors.white.withOpacity(0.8)
            ..style = PaintingStyle.fill;

      const dotRadius = 1.5;
      final dotDistance = radius - 10;
      final dotCount = cluster.memoryCount > 10 ? 8 : 6;

      for (int i = 0; i < dotCount; i++) {
        final angle = (i * (360 / dotCount)) * (pi / 180);
        final x = radius + cos(angle) * dotDistance;
        final y = radius + sin(angle) * dotDistance;
        canvas.drawCircle(Offset(x, y), dotRadius, indicatorPaint);
      }
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _createClusterMarkerImage(
    MemoryCluster cluster,
    int clusterIndex,
  ) async {
    try {
      // Use fixed size to avoid issues with Mapbox
      const double size = 60.0;
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final radius = size / 2;

      debugPrint(
        '[MapController][_createClusterMarkerImage] === CREATING UNIQUE CLUSTER IMAGE ===',
      );
      debugPrint(
        '[MapController][_createClusterMarkerImage] Cluster ID: ${cluster.id}',
      );
      debugPrint(
        '[MapController][_createClusterMarkerImage] Cluster Index: $clusterIndex',
      );
      debugPrint(
        '[MapController][_createClusterMarkerImage] Memory Count: ${cluster.memoryCount}',
      );
      debugPrint(
        '[MapController][_createClusterMarkerImage] Is Single Memory: ${cluster.isSingleMemory}',
      );
      debugPrint(
        '[MapController][_createClusterMarkerImage] Memories Length: ${cluster.memories.length}',
      );

      // Choose color based on cluster ID and type for UNIQUE identification
      Color markerColor;
      Color borderColor = Colors.white;
      double borderWidth = 3.0;

      if (cluster.isSingleMemory) {
        // For single memories, use cluster ID to generate consistent unique color
        markerColor = getColorForMemoryYear(cluster.memories[0].memoryDate);

        debugPrint(
          '[MapController][_createClusterMarkerImage] Single memory color: ${markerColor.toString()}',
        );
      } else {
        // Group markers have distinct styling based on memory count
        borderWidth = 1.0;
        borderColor = const Color.fromARGB(255, 255, 255, 255); // Gold border for groups

        markerColor = getColorForMemoryYear(cluster.memories.last.memoryDate);

        // if (cluster.memoryCount <= 5) {
        //   markerColor = const Color(0xFF4CAF50); // Green for small clusters
        // } else if (cluster.memoryCount <= 15) {
        //   markerColor = const Color(0xFFFF9800); // Orange for medium clusters
        // } else if (cluster.memoryCount <= 50) {
        //   markerColor = const Color(0xFFF44336); // Red for large clusters
        // } else {
        //   markerColor = const Color(0xFF9C27B0); // Purple for very large clusters
        // }
        debugPrint(
          '[MapController][_createClusterMarkerImage] Multi-memory color: ${markerColor.toString()}',
        );
      }

      // Fill the entire canvas with transparent background first
      final backgroundPaint = Paint()..color = Colors.transparent;
      canvas.drawRect(Rect.fromLTWH(0, 0, size, size), backgroundPaint);

      // Draw outer ring for group markers
      if (!cluster.isSingleMemory) {
        final outerPaint =
            Paint()
              ..color = borderColor.withValues(alpha: 0.3)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6.0;
        canvas.drawCircle(Offset(radius, radius), radius - 3, outerPaint);
      }

      // Draw main circle
      final paint =
          Paint()
            ..color = markerColor
            ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(radius, radius), radius - 6, paint);

      // Add border
      final border =
          Paint()
            ..color = borderColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = borderWidth;
      canvas.drawCircle(Offset(radius, radius), radius - 6, border);

      print('Meta Data Cluster${cluster.memories[0].metadata}');

      // Draw count text - make it more prominent
      final fontSize =
          cluster.memoryCount > 99
              ? 10.0
              : cluster.memoryCount > 9
              ? 12.0
              : 14.0;

      final textPainter = TextPainter(
        text: TextSpan(
          text:
              cluster.isSingleMemory
                  ? (1).toString()
                  : cluster.memoryCount.toString(),
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            shadows: [
              const Shadow(
                offset: Offset(0.5, 0.5),
                blurRadius: 1,
                color: Colors.black87,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      textPainter.layout();

      // Center the text in the circle
      final textOffset = Offset(
        radius - textPainter.width / 2,
        radius - textPainter.height / 2,
      );

      textPainter.paint(canvas, textOffset);

      // Add cluster indicator dots for groups
      if (!cluster.isSingleMemory && cluster.memoryCount > 1) {
        final indicatorPaint =
            Paint()
              ..color = Colors.white.withValues(alpha: 0.8)
              ..style = PaintingStyle.fill;

        // Draw small dots around the marker to indicate it's a cluster
        const dotRadius = 1.5;
        final dotDistance = radius - 10;
        final dotCount = cluster.memoryCount > 10 ? 8 : 6;

        for (int i = 0; i < dotCount; i++) {
          final angle = (i * (360 / dotCount)) * (pi / 180);
          final x = radius + cos(angle) * dotDistance;
          final y = radius + sin(angle) * dotDistance;
          canvas.drawCircle(Offset(x, y), dotRadius, indicatorPaint);
        }
      }

      final picture = recorder.endRecording();

      // Ensure size is valid and not zero
      final imageSize = size.toInt();
      if (imageSize <= 0) {
        debugPrint('❌ Invalid image size: $imageSize');
        throw Exception('Invalid image size: $imageSize');
      }

      final image = await picture.toImage(imageSize, imageSize);
      final byteData = await image.toByteData(format: ImageByteFormat.png);

      if (byteData == null) {
        debugPrint('❌ Failed to create image byte data');
        throw Exception('Failed to create image byte data');
      }

      final imageBytes = byteData.buffer.asUint8List();
      debugPrint(
        '✅ Created cluster marker image: ${imageBytes.length} bytes, ${imageSize}x${imageSize}px',
      );

      return imageBytes;
    } catch (e) {
      debugPrint('❌ Error creating cluster marker image: $e');
      // Return a simple fallback image
      return _createSimpleFallbackMarkerImage(cluster.memoryCount);
    }
  }

  // Simple fallback marker image creation
  Future<Uint8List> _createSimpleFallbackMarkerImage(int count) async {
    const double size = 60.0;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final radius = size / 2;

    // Draw simple circle
    final paint =
        Paint()
          ..color = const Color(0xFF2196F3)
          ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(radius, radius), radius - 5, paint);

    // Draw border
    final border =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
    canvas.drawCircle(Offset(radius, radius), radius - 5, border);

    // Draw count text
    final textPainter = TextPainter(
      text: TextSpan(
        text: (count == 1 ? '' : count.toString()),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(radius - textPainter.width / 2, radius - textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    return byteData?.buffer.asUint8List() ?? Uint8List(0);
  }

  //  Future<void> _displayChronologicalArrows() async {
  //   if (mapController == null || currentArrows.isEmpty) return;

  //   try {
  //     final arrowsToDisplay = currentArrows.length > MemoryClusteringService.maxArrowsToDisplay
  //         ? currentArrows.take(MemoryClusteringService.maxArrowsToDisplay).toList()
  //         : currentArrows;

  //     final lineManager = await mapController!.annotations.createPolylineAnnotationManager();

  //     for (final arrow in arrowsToDisplay) {
  //       // Build a gentle curved path strictly between markers
  //       final points = _createCurvedArrowLine(
  //         arrow.fromLatitude, arrow.fromLongitude,
  //         arrow.toLatitude, arrow.toLongitude,
  //       );
  //       print('arrows 1 todate ${arrow.toDate}');
  //       print('arrows  todate ${arrow.fromDate}');
  //       final timeDiff = arrow.toDate.difference(arrow.fromDate).inMilliseconds;
  //       final color = _getArrowColor(timeDiff);
  //       final width = _getArrowWidth(timeDiff);

  //       // Shadow first (under)
  //       await lineManager.create(
  //         mapbox.PolylineAnnotationOptions(
  //           geometry: mapbox.LineString(coordinates: points),
  //           lineColor: 0xFF000000,
  //           lineWidth: width + 2,
  //           lineOpacity: 0.20,
  //         ),
  //       );

  //       // Main line
  //       await lineManager.create(
  //         mapbox.PolylineAnnotationOptions(
  //           geometry: mapbox.LineString(coordinates: points),
  //           lineColor: color,
  //           lineWidth: width,
  //           lineOpacity: 0.85,
  //         ),
  //       );

  //       // Place the arrow head at t=0.8 on the curve, rotated to the curve tangent
  //       await _addArrowHeadOnCurve(points, color);
  //     }

  //   } catch (e) {
  //     debugPrint('Error displaying chronological arrows: $e');
  //   }
  // }

  Future<void> _displayChronologicalArrows() async {
    if (mapController == null || currentArrows.isEmpty) return;

    try {
      final arrowsToDisplay =
          currentArrows.length > MemoryClusteringService.maxArrowsToDisplay
              ? currentArrows
                  .take(MemoryClusteringService.maxArrowsToDisplay)
                  .toList()
              : currentArrows;

      final lineManager = await _getPolylineManager();

      // Start from a clean slate when redrawing arrows
      await lineManager.deleteAll();

      // Get line color based on connection type and clusters
      // final lineColor = getRandomMarkerColor(4);
      // final decimalValue = lineColor.value;

      for (final arrow in arrowsToDisplay) {
        final points = _createCurvedArrowLine(
          arrow.fromLatitude,
          arrow.fromLongitude,
          arrow.toLatitude,
          arrow.toLongitude,
        );

        final timeDiffMs =
            arrow.toDate.difference(arrow.fromDate).inMilliseconds;
        // final color = _getArrowColor(timeDiffMs);
        final width = _getArrowWidth(timeDiffMs);

        // Shadow

        final currentColor = getColorForYear(arrow.toDate.year);
        final currentColorName = getColorNameForYear(arrow.toDate.year);
        final currentColorIndex = getColorIndexForYear(arrow.toDate.year);
        await lineManager.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: points),
            lineColor: 0xFF000000,
            lineWidth: width + 2,
            lineOpacity: 0.20,
          ),
        );

        // debugPrint('🎨 Line color for arrow: ${lineColor.toString()} (decimal: $decimalValue)');

        // Main line
        await lineManager.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: points),
            lineColor: currentColor.value,
            lineWidth: 5,
            lineOpacity: 1,
          ),
        );

        await _addArrowHeadOnCurve(
          points,
          currentColor,
        ); // heads are point annotations
      }
    } catch (e) {
      debugPrint('Error displaying chronological arrows: $e');
    }
  }

  Future<void> _addArrowToSegment(
    mapbox.Position start,
    mapbox.Position end,
    Color color,
    int index,
  ) async {
    if (mapController == null) return;

    final imageBytes = await _createArrowImage(color);
    final image = mapbox.MbxImage(data: imageBytes, height: 30, width: 30);

    await mapController!.style.addStyleImage(
      'arrow_$index',
      1.0,
      image,
      false,
      [],
      [],
      null,
    );

    final midLng = (start.lng + end.lng) / 2;
    final midLat = (start.lat + end.lat) / 2;
    final bearing = _calculateBearing(start, end);

    final geoJson = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [midLng, midLat],
          },
          'properties': {'bearing': bearing},
        },
      ],
    };

    // Check if arrow source already exists and remove it first
    try {
      await mapController!.style.removeStyleSource('arrow_source_$index');
    } catch (e) {
      // Source doesn't exist, which is fine
    }

    await mapController!.style.addSource(
      mapbox.GeoJsonSource(
        id: 'arrow_source_$index',
        data: jsonEncode(geoJson),
      ),
    );

    await mapController!.style.addLayer(
      mapbox.SymbolLayer(
        id: 'arrow_layer_$index',
        sourceId: 'arrow_source_$index',
        iconImage: 'arrow_$index',
        iconSize: 0.8,
        iconRotate: bearing,
        iconAllowOverlap: true,
      ),
    );
  }

  Future<void> _addArrowHeadOnCurve(
    List<mapbox.Position> curvePoints,
    Color arrowColor,
  ) async {
    if (mapController == null || currentAnnotationManager == null) return;
    if (curvePoints.length < 3) return;

    try {
      // Build (or cache) an arrow head image for this color
      final imgKey = 'arrow_head_color_$arrowColor';
      try {
        await mapController!.style.removeStyleImage(
          imgKey,
        ); // refresh if same color used before
      } catch (_) {}

      final imageBytes = await _createArrowImage(arrowColor);
      final image = mapbox.MbxImage(data: imageBytes, height: 30, width: 30);

      // await mapController!.style.addStyleImage(
      //   'arrow_$index',
      //   1.0,
      //   image,
      //   false,
      //   [],
      //   [],
      //   null,
      // );

      if (imageBytes.isEmpty) {
        debugPrint('❌ Skipping arrow head due to empty image data');
        return;
      }

      await mapController!.style.addStyleImage(
        imgKey,
        1.0,
        image,
        false,
        [],
        [],
        null,
      );

      // Position ~80% along the curve
      final idx =
          ((curvePoints.length - 1) * 0.8)
              .clamp(1, curvePoints.length - 1)
              .toInt();
      final pPrev = curvePoints[idx - 1];
      final pNow = curvePoints[idx];

      // Bearing from pPrev -> pNow (planar approx fine for short segments)
      final bearing = _bearingDegrees(
        pPrev.lat.toDouble(),
        pPrev.lng.toDouble(),
        pNow.lat.toDouble(),
        pNow.lng.toDouble(),
      );

      await currentAnnotationManager!.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(pNow.lng, pNow.lat),
          ),
          iconImage: imgKey,
          iconSize: 0.8,
          iconRotate: bearing,
          // iconAllowOverlap: true,
        ),
      );
    } catch (e) {
      debugPrint('Error adding arrow head on curve: $e');
    }
  }

  /// Bearing from point A -> B in degrees clockwise from north
  double _bearingDegrees(double lat1, double lng1, double lat2, double lng2) {
    final radLat1 = lat1 * math.pi / 180.0;
    final radLat2 = lat2 * math.pi / 180.0;
    final deltaLon = (lng2 - lng1) * math.pi / 180.0;

    final y = math.sin(deltaLon) * math.cos(radLat2);
    final x =
        math.cos(radLat1) * math.sin(radLat2) -
        math.sin(radLat1) * math.cos(radLat2) * math.cos(deltaLon);

    final theta = math.atan2(y, x); // radians
    final deg = (theta * 180.0 / math.pi + 360.0) % 360.0;
    return deg;
  }

  int _getArrowColor(int timeDiffDays) {
    if (timeDiffDays <= 1) {
      return 0xFF4CAF50; // Green for same day/next day
    } else if (timeDiffDays <= 7) {
      return 0xFF2196F3; // Blue for within a week
    } else if (timeDiffDays <= 30) {
      return 0xFFFF9800; // Orange for within a month
    } else {
      return 0xFFF44336; // Red for longer periods
    }
  }

  double _getArrowWidth(int timeDiffDays) {
    // if (timeDiffDays <= 1) {
    return 3.0; // Thicker for recent connections
    // } else if (timeDiffDays <= 7) {
    //   return 2.5;
    // } else if (timeDiffDays <= 30) {
    //   return 2.0;
    // } else {
    //   return 1.5; // Thinner for older connections
    // }
  }

  List<mapbox.Position> _createCurvedArrowLine(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const int segments = 32;

    // Direction in degrees
    final dx = lng2 - lng1;
    final dy = lat2 - lat1;
    final len = math.sqrt(dx * dx + dy * dy);

    // Handle zero-length gracefully (repeat a point)
    if (len == 0) {
      return [mapbox.Position(lng1, lat1), mapbox.Position(lng2, lat2)];
    }

    // Perpendicular unit (lng, lat)
    final ux = -dy / len;
    final uy = dx / len;

    // Estimate segment length in km for sensible offset scaling
    final avgLatRad = ((lat1 + lat2) * 0.5) * (math.pi / 180.0);
    const kmPerDegLat = 110.574; // approx constant
    final kmPerDegLng = 111.320 * math.cos(avgLatRad);

    final segKm =
        (dy.abs() * kmPerDegLat + dx.abs() * kmPerDegLng) * 0.5; // rough avg

    // Max lateral offset ≈ 8% of segment length, capped (subtle arc)
    final maxOffsetKm = (segKm * 0.08).clamp(0.0, 20.0);
    final offDegLat = maxOffsetKm / kmPerDegLat;
    final offDegLng = kmPerDegLng == 0 ? 0.0 : (maxOffsetKm / kmPerDegLng);

    // Control point (midpoint + perpendicular offset)
    final cLng = (lng1 + lng2) * 0.5 + ux * offDegLng;
    final cLat = (lat1 + lat2) * 0.5 + uy * offDegLat;

    // Quadratic Bézier sampling
    final points = <mapbox.Position>[];
    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final omt = 1 - t;

      final lng = omt * omt * lng1 + 2 * omt * t * cLng + t * t * lng2;
      final lat = omt * omt * lat1 + 2 * omt * t * cLat + t * t * lat2;

      points.add(mapbox.Position(lng, lat)); // (lng, lat)
    }

    return points;
  }

  Future<void> _addArrowHead(
    ChronologicalArrow arrow, [
    int? arrowColor,
  ]) async {
    if (mapController == null || currentAnnotationManager == null) return;

    try {
      // Create arrow head image with specified color
      final imageBytes = await _createArrowHeadImage(arrowColor ?? 0xFF4CAF50);
      final imageName =
          'arrow_head_${arrow.fromClusterId}_${arrow.toClusterId}';

      await mapController!.style.addStyleImage(
        imageName,
        1.0,
        mapbox.MbxImage(data: imageBytes, width: 20, height: 20),
        false,
        [],
        [],
        null,
      );

      // Place arrow head at 80% of the way to target
      const t = 0.8;

      final arrowLat =
          arrow.fromLatitude + (arrow.toLatitude - arrow.fromLatitude) * t;
      final arrowLng =
          arrow.fromLongitude + (arrow.toLongitude - arrow.fromLongitude) * t;

      await currentAnnotationManager!.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(arrowLng, arrowLat),
          ),
          iconImage: imageName,
          iconSize: 0.5,
          iconRotate: arrow.bearing,
        ),
      );
    } catch (e) {
      debugPrint('Error adding arrow head: $e');
    }
  }

  Future<Uint8List> _createArrowHeadImage([int colorValue = 0xFF2E7D32]) async {
    const int size = 24; // Use consistent integer size
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    // Fill background with transparent
    final backgroundPaint = Paint()..color = Colors.transparent;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      backgroundPaint,
    );

    final paint =
        Paint()
          ..color = Color(colorValue)
          ..style = PaintingStyle.fill;

    // Draw arrow head triangle with proper proportions
    final path = Path();
    path.moveTo(size * 0.8, size * 0.5); // Point
    path.lineTo(size * 0.2, size * 0.2); // Top
    path.lineTo(size * 0.2, size * 0.8); // Bottom
    path.close();

    canvas.drawPath(path, paint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size, size);
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    if (byteData == null) {
      debugPrint('❌ Failed to create arrow head image data');
      return Uint8List(0);
    }

    final imageBytes = byteData.buffer.asUint8List();
    debugPrint(
      '✅ Created arrow head image: ${imageBytes.length} bytes, ${size}x${size}px',
    );
    return imageBytes;
  }

  Future<void> _fitCameraToMemoryClusters() async {
    if (mapController == null || currentClusters.isEmpty) return;

    try {
      // Calculate bounds of all clusters
      double minLat = currentClusters.first.centerLatitude;
      double maxLat = currentClusters.first.centerLatitude;
      double minLng = currentClusters.first.centerLongitude;
      double maxLng = currentClusters.first.centerLongitude;

      for (final cluster in currentClusters) {
        minLat =
            minLat < cluster.centerLatitude ? minLat : cluster.centerLatitude;
        maxLat =
            maxLat > cluster.centerLatitude ? maxLat : cluster.centerLatitude;
        minLng =
            minLng < cluster.centerLongitude ? minLng : cluster.centerLongitude;
        maxLng =
            maxLng > cluster.centerLongitude ? maxLng : cluster.centerLongitude;
      }

      // Add padding
      const double padding = 0.1;
      minLat -= padding;
      maxLat += padding;
      minLng -= padding;
      maxLng += padding;

      // Calculate zoom level
      final double latDiff = maxLat - minLat;
      final double lngDiff = maxLng - minLng;
      final double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

      double zoom = 10.0;
      if (maxDiff > 10)
        zoom = 2.0;
      else if (maxDiff > 5)
        zoom = 4.0;
      else if (maxDiff > 1)
        zoom = 6.0;
      else if (maxDiff > 0.1)
        zoom = 8.0;

      // Set camera to fit bounds
      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              (minLng + maxLng) / 2,
              (minLat + maxLat) / 2,
            ),
          ),
          zoom: 2,
        ),
        mapbox.MapAnimationOptions(duration: 1000),
      );
    } catch (e) {
      debugPrint('Error fitting camera to memory clusters: $e');
    }
  }

  void showLocationBottomPanel(
    BuildContext context,
    MemoryCluster cluster, {
    List<Map<String, dynamic>>? specificMemories,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BottomPanel(cluster, specificMemories: specificMemories),
    );
  }

  Future<bool> _checkLocationPermission() async {
    debugPrint('🔍 PERMISSIONS - Checking location service enabled');
    bool serviceEnabled =
        await geolocator.Geolocator.isLocationServiceEnabled();
    debugPrint('🔍 PERMISSIONS - Location service enabled: $serviceEnabled');

    if (!serviceEnabled) {
      debugPrint('🔍 PERMISSIONS - Location service disabled, showing dialog');
      Get.dialog(
        AlertDialog(
          title: const Text('Location is Off'),
          content: const Text('Please enable location services to continue.'),
          actions: [
            TextButton(
              onPressed: () {
                geolocator.Geolocator.openLocationSettings();
                Get.back();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      return false;
    }

    debugPrint('🔍 PERMISSIONS - Checking location permission');
    geolocator.LocationPermission permission =
        await geolocator.Geolocator.checkPermission();
    debugPrint('🔍 PERMISSIONS - Current permission: $permission');

    if (permission == geolocator.LocationPermission.denied) {
      debugPrint('🔍 PERMISSIONS - Permission denied, requesting permission');
      permission = await geolocator.Geolocator.requestPermission();
      debugPrint('🔍 PERMISSIONS - Permission after request: $permission');
      if (permission == geolocator.LocationPermission.denied) {
        debugPrint('🔍 PERMISSIONS - Permission still denied after request');
        return false;
      }
    }

    if (permission == geolocator.LocationPermission.deniedForever) {
      debugPrint('🔍 PERMISSIONS - Permission denied forever, showing dialog');
      Get.dialog(
        AlertDialog(
          title: const Text('Permission Denied'),
          content: const Text(
            'Location permission is permanently denied. Open app settings to enable.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                geolocator.Geolocator.openAppSettings();
                Get.back();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      return false;
    }

    debugPrint('🔍 PERMISSIONS - Location permission granted: $permission');
    return true;
  }

  Future<void> _setAnnotations() async {
    if (mapController == null) return;

    currentAnnotationManager =
        await mapController!.annotations.createPointAnnotationManager();
    final List<mapbox.PointAnnotationOptions> options = [];

    for (int i = 0; i < locations.length; i++) {
      Color color =
          (i == 0)
              ? Color(0xFF0071FF)
              : (i == locations.length - 1)
              ? Color(0xFFFF0000)
              : Color(0xFF8800FF);

      // final imageBytes = await _createCircleWithNumberImage(
      //   color,
      //   '${visitCounts[i]}',
      // );
      final imageName = 'marker_$i';

      // await mapController!.style.addStyleImage(
      //   imageName,
      //   1.0,
      //   mapbox.MbxImage(data: imageBytes, width: 50, height: 50),
      //   false,
      //   [],
      //   [],
      //   null,
      // );

      // options.add(
      //   mapbox.PointAnnotationOptions(
      //     geometry: mapbox.Point(coordinates: locations[i]),
      //     iconImage: imageName,
      //     iconSize: 0.7,
      //   ),
      // );
    }

    final created = await currentAnnotationManager!.createMulti(options);
    annotations.assignAll(
      created.where((a) => a != null).cast<mapbox.PointAnnotation>(),
    );

    // currentAnnotationManager!.addOnPointAnnotationClickListener(
    // AnnotationClickListener((annotation) async {
    //   final index = annotations.indexWhere((a) => a.id == annotation.id);
    //   if (index != -1 && visitCounts[index] == 9) {
    //     // Only trigger for marker with number 9
    //     await _showNew8Locations();
    //   }
    // }),
    // );
  }

  // Public method to show new locations (can be called from outside)
  Future<void> showNew8Locations() async {
    // await _showNew8Locations();
  }

  //   Future<void> _showNew8Locations() async {
  //     if (mapController == null) return;

  //     try {
  //       // Set transition flag to prevent reactive zoom operations
  //       _isTransitioningLocations = true;
  //       debugPrint(
  //         '🔄 TRANSITION - Starting location transition, blocking reactive zoom',
  //       );

  //       // Step 1: Clear existing annotations safely
  //       if (currentAnnotationManager != null) {
  //         try {
  //           await currentAnnotationManager!.deleteAll();
  //         } catch (e) {
  //           debugPrint('Error deleting annotations: $e');
  //           // Continue anyway, we'll create a new manager
  //         }
  //         currentAnnotationManager = null;
  //         annotations.clear();
  //       }

  //       // Step 1.5: Clear all existing marker style images
  //       await _clearAllMarkerImages();

  //       // Step 2: Clear all existing lines
  //       await _clearAllLines();

  //       // Step 2.5: Wait a moment for cleanup to complete
  //       await Future.delayed(Duration(milliseconds: 100));

  //       // Step 3: Replace locations with the 8 new European cities
  //       locations.clear();
  //       locations.addAll(newLocations);

  //       // Step 4: Set the state to show new locations
  //       isShowingNewLocations.value = true;

  //       // Step 5: First animate to zoom, then show points
  //       // Calculate center point of all new locations
  //       double centerLat = 0;
  //       double centerLng = 0;
  //       for (var location in locations) {
  //         centerLat += location.lat;
  //         centerLng += location.lng;
  //       }
  //       centerLat /= locations.length;
  //       centerLng /= locations.length;

  //       final currentCamera = await mapController!.getCameraState();
  //       final currentZoom = currentCamera.zoom;
  //       final newZoom = currentZoom < 2.0 ? 4.5 : currentZoom * 2.5;

  //       // Animate to zoom first with smooth transition
  //       await mapController!.flyTo(
  //         mapbox.CameraOptions(
  //           center: mapbox.Point(
  //             coordinates: mapbox.Position(centerLng, centerLat),
  //           ),
  //           zoom: newZoom,
  //         ),
  //         mapbox.MapAnimationOptions(
  //           duration: 1200, // Smooth animation duration
  //           startDelay: 0,
  //         ),
  //       );

  //       // Wait for zoom animation to complete
  //       await Future.delayed(
  //         Duration(milliseconds: 100),
  //       ); // Animation duration + buffer

  //       // Step 6: Now create markers after zoom animation
  //       currentAnnotationManager =
  //           await mapController!.annotations.createPointAnnotationManager();
  //       final List<mapbox.PointAnnotationOptions> options = [];

  //       for (int i = 0; i < locations.length; i++) {
  //         // Use different colors like the original locations
  //         Color color =
  //             (i == 0)
  //                 ? Color(0xFF0071FF)
  //                 : (i == locations.length - 1)
  //                 ? Colors.lightBlue.withValues(alpha: 0.8)
  //                 : Color(0xFF8800FF);

  //         String numberText = (i == 5) ? '2' : '';

  //         final imageBytes = await _createCircleWithNumberImage(
  //           color,
  //           numberText,
  //         );
  //         final imageName = 'new_marker_$i';

  //         await mapController!.style.addStyleImage(
  //           imageName,
  //           1.0,
  //           mapbox.MbxImage(data: imageBytes, width: 50, height: 50),
  //           false,
  //           [],
  //           [],
  //           null,
  //         );

  //         options.add(
  //           mapbox.PointAnnotationOptions(
  //             geometry: mapbox.Point(coordinates: locations[i]),
  //             iconImage: imageName,
  //             iconSize: 0.7,
  //           ),
  //         );
  //       }

  //       final created = await currentAnnotationManager!.createMulti(options);
  //       annotations.assignAll(
  //         created.where((a) => a != null).cast<mapbox.PointAnnotation>(),
  //       );

  //       currentAnnotationManager!.addOnPointAnnotationClickListener(
  //         AnnotationClickListener((annotation) async {
  //           final index = annotations.indexWhere((a) => a.id == annotation.id);
  //           if (index == 5) {
  //             // showLocationBottomPanel(Get.context!);
  //           } else if (index != -1) {
  //             // Any other marker - navigate to add memories
  // Get.find<AddMemoriesController>();
  //             Get.to(() => AddMemoriesView());
  //           }
  //         }),
  //       );

  //       // Step 7: Draw lines between the 8 locations after markers are shown
  //       await _drawLinesForNewLocations();

  //       // Reset transition flag to allow reactive zoom operations again
  //       _isTransitioningLocations = false;
  //       debugPrint(
  //         '🔄 TRANSITION - Location transition complete, reactive zoom enabled',
  //       );
  //     } catch (e) {
  //       debugPrint('Error showing new locations: $e');
  //       // Reset state on error
  //       isShowingNewLocations.value = false;
  //       // Also reset transition flag on error
  //       _isTransitioningLocations = false;
  //       debugPrint(
  //         '🔄 TRANSITION - Location transition failed, reactive zoom enabled',
  //       );
  //     }
  //   }
  //
  Future<void> _drawLinesForNewLocations() async {
    if (mapController == null) return;

    // Draw lines connecting all 8 locations in sequence (1->2->3->...->8)
    for (int i = 0; i < locations.length - 1; i++) {
      final start = locations[i];
      final end = locations[i + 1];
      // Use the same color scheme as the original locations
      final color = (i == 0) ? Color(0xFF0071FF) : Color(0xFF8800FF);

      final geoJson = {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [start.lng, start.lat],
            [end.lng, end.lat],
          ],
        },
      };

      // Check if source already exists and remove it first
      try {
        await mapController!.style.removeStyleSource('new_line_$i');
      } catch (e) {
        // Source doesn't exist, which is fine
      }

      await mapController!.style.addSource(
        mapbox.GeoJsonSource(id: 'new_line_$i', data: jsonEncode(geoJson)),
      );

      await mapController!.style.addLayer(
        mapbox.LineLayer(
          id: 'new_line_layer_$i',
          sourceId: 'new_line_$i',
          lineJoin: mapbox.LineJoin.ROUND,
          lineCap: mapbox.LineCap.ROUND,
          lineOpacity: 0.8,
          lineColor: color.value,
          lineWidth: 3.0,
        ),
      );

      await _addArrowToSegment(start, end, color, i);
    }
  }

  Future<void> _setTravelPath() async {
    if (mapController == null) return;

    for (int i = 0; i < locations.length - 1; i++) {
      final start = locations[i];
      final end = locations[i + 1];
      final color = (i == 0) ? Color(0xFF0071FF) : Color(0xFF8800FF);

      final geoJson = {
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [start.lng, start.lat],
            [end.lng, end.lat],
          ],
        },
      };

      // Check if source already exists and remove it first
      try {
        await mapController!.style.removeStyleSource('line_$i');
      } catch (e) {
        // Source doesn't exist, which is fine
      }

      await mapController!.style.addSource(
        mapbox.GeoJsonSource(id: 'line_$i', data: jsonEncode(geoJson)),
      );

      await mapController!.style.addLayer(
        mapbox.LineLayer(
          id: 'line_layer_$i',
          sourceId: 'line_$i',
          lineJoin: mapbox.LineJoin.ROUND,
          lineCap: mapbox.LineCap.ROUND,
          lineOpacity: 0.7,
          lineColor: color.value,
          lineWidth: 4.0, // thinner
        ),
      );

      await _addArrowToSegment(start, end, color, i);
    }
  }

  // Future<void> _addArrowToSegment(
  //   mapbox.Position start,
  //   mapbox.Position end,
  //   Color color,
  //   int index,
  // ) async {
  //   if (mapController == null) return;

  //   final imageBytes = await _createArrowImage(color);
  //   final image = mapbox.MbxImage(data: imageBytes, height: 30, width: 30);

  //   await mapController!.style.addStyleImage(
  //     'arrow_$index',
  //     1.0,
  //     image,
  //     false,
  //     [],
  //     [],
  //     null,
  //   );

  //   final midLng = (start.lng + end.lng) / 2;
  //   final midLat = (start.lat + end.lat) / 2;
  //   final bearing = _calculateBearing(start, end);

  //   final geoJson = {
  //     'type': 'FeatureCollection',
  //     'features': [
  //       {
  //         'type': 'Feature',
  //         'geometry': {
  //           'type': 'Point',
  //           'coordinates': [midLng, midLat],
  //         },
  //         'properties': {'bearing': bearing},
  //       },
  //     ],
  //   };

  //   // Check if arrow source already exists and remove it first
  //   try {
  //     await mapController!.style.removeStyleSource('arrow_source_$index');
  //   } catch (e) {
  //     // Source doesn't exist, which is fine
  //   }

  //   await mapController!.style.addSource(
  //     mapbox.GeoJsonSource(
  //       id: 'arrow_source_$index',
  //       data: jsonEncode(geoJson),
  //     ),
  //   );

  //   await mapController!.style.addLayer(
  //     mapbox.SymbolLayer(
  //       id: 'arrow_layer_$index',
  //       sourceId: 'arrow_source_$index',
  //       iconImage: 'arrow_$index',
  //       iconSize: 0.8,
  //       iconRotate: bearing,
  //       iconAllowOverlap: true,
  //     ),
  //   );
  // }

  double _calculateBearing(mapbox.Position start, mapbox.Position end) {
    final lat1 = start.lat * pi / 180;
    final lng1 = start.lng * pi / 180;
    final lat2 = end.lat * pi / 180;
    final lng2 = end.lng * pi / 180;

    final dLng = lng2 - lng1;
    final y = sin(dLng) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  Future<Uint8List> _createCircleWithNumberImage(
    Color color,
    String number,
  ) async {
    const double size = 50.0;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final radius = size / 2;

    // Draw circle
    final paint = Paint()..color = color;
    canvas.drawCircle(Offset(radius, radius), radius - 2, paint);

    // Add white border
    final border =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
    canvas.drawCircle(Offset(radius, radius), radius - 2, border);

    // Draw the number in the center
    final textPainter = TextPainter(
      text: TextSpan(
        text: number,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(radius - textPainter.width / 2, radius - textPainter.height / 2),
    );

    // Convert to image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<Uint8List> _createArrowImage(Color color) async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..color = color;
    const size = 30.0;
    const arrowWidth = 20.0;
    const arrowHeight = 15.0;

    final path = Path();
    path.moveTo(size / 2, 5);
    path.lineTo(size / 2 + arrowWidth / 2, 5 + arrowHeight);
    path.lineTo(size / 2 + 5, 5 + arrowHeight);
    path.lineTo(size / 2 + 5, size - 5);
    path.lineTo(size / 2 - 5, size - 5);
    path.lineTo(size / 2 - 5, 5 + arrowHeight);
    path.lineTo(size / 2 - arrowWidth / 2, 5 + arrowHeight);
    path.close();

    canvas.drawPath(path, paint);

    final border =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
    canvas.drawPath(path, border);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _fitCameraToBounds() async {
    if (mapController == null || locations.isEmpty) {
      debugPrint(
        'Cannot fit camera: mapController is null or locations is empty',
      );
      return;
    }

    try {
      double minLat = double.maxFinite;
      double maxLat = -double.maxFinite;
      double minLng = double.maxFinite;
      double maxLng = -double.maxFinite;

      for (var pos in locations) {
        minLat = min(minLat, pos.lat.toDouble());
        maxLat = max(maxLat, pos.lat.toDouble());
        minLng = min(minLng, pos.lng.toDouble());
        maxLng = max(maxLng, pos.lng.toDouble());
      }

      final bounds = mapbox.CoordinateBounds(
        southwest: mapbox.Point(coordinates: mapbox.Position(minLng, minLat)),
        northeast: mapbox.Point(coordinates: mapbox.Position(maxLng, maxLat)),
        infiniteBounds: true,
      );

      // Set bounds first
      await mapController!.setBounds(
        mapbox.CameraBoundsOptions(bounds: bounds, maxZoom: 5.0, minZoom: 1.5),
      );

      // Then smoothly animate to the reactive zoom level
      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: locations[0]),
          zoom: currentZoom.value, // Use reactive zoom value
          bearing: 0,
          pitch: 0,
        ),
        mapbox.MapAnimationOptions(
          duration: 1200, // Smooth animation duration
          startDelay: 150, // Small delay to ensure bounds are set
        ),
      );

      debugPrint(
        'Camera smoothly animated to zoom ${currentZoom.value} successfully',
      );
    } catch (e) {
      debugPrint('Error fitting camera bounds: $e');
      // Fallback: smooth zoom to exact level
      try {
        await mapController!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(
              coordinates:
                  locations.isNotEmpty ? locations[0] : mapbox.Position(0, 0),
            ),
            zoom: currentZoom.value, // Use reactive zoom value
            bearing: 0,
            pitch: 0,
          ),
          mapbox.MapAnimationOptions(duration: 800, startDelay: 0),
        );
        debugPrint('Fallback smooth camera zoom ${currentZoom.value} applied');
      } catch (fallbackError) {
        debugPrint('Fallback camera zoom also failed: $fallbackError');
      }
    }
  }

  // Reactive map initialization that responds to state changes
  void _initializeMapReactively() {
    // Use ever to react to state changes
    ever(isShowingNewLocations, (bool showingNew) async {
      if (isMapReady.value && mapController != null) {
        debugPrint(
          'Reactive state change: isShowingNewLocations = $showingNew',
        );
        await _handleMapStateChange(showingNew);
      }
    });

    // Initialize based on current state
    _handleMapStateChange(isShowingNewLocations.value);
  }

  // Handle map state changes reactively - Updated for memory clustering
  Future<void> _handleMapStateChange(bool showingNew) async {
    if (!isMapReady.value ||
        mapController == null ||
        _isTransitioningLocations) {
      debugPrint(
        '🔄 _handleMapStateChange - Skipping (transitioning: $_isTransitioningLocations)',
      );
      return;
    }

    try {
      debugPrint('Using memory clustering system instead of dummy data');

      // Don't override the memory clustering system
      // The memory clustering is already initialized in onMapCreated
      // Just ensure the camera is set properly if needed
      if (currentClusters.isNotEmpty) {
        debugPrint(
          'Memory clusters already loaded, fitting camera to clusters',
        );
        await _fitCameraToMemoryClusters();
      } else {
        debugPrint('No memory clusters found, falling back to default view');
        // Set a default world view
        currentZoom.value = 1.6;
        await _setImmediateCamera();
      }
    } catch (e) {
      debugPrint('Error in reactive map state change: $e');
    }
  }

  // Set camera with smooth animation instead of immediate
  Future<void> _setImmediateCamera() async {
    if (mapController == null) return;

    try {
      debugPrint('Setting smooth camera to zoom: ${currentZoom.value}');

      // Use a default center point if no locations are available
      final centerPoint =
          locations.isNotEmpty
              ? locations[0]
              : mapbox.Position(0, 0); // World center

      // Use flyTo with short animation for smooth transition
      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(coordinates: centerPoint),
          zoom: currentZoom.value,
          bearing: 0,
          pitch: 0,
        ),
        mapbox.MapAnimationOptions(
          duration: 600, // Smooth but quick animation
          startDelay: 0,
        ),
      );

      debugPrint('Smooth camera set successfully');
    } catch (e) {
      debugPrint('Error setting smooth camera: $e');
    }
  }

  // Ensure correct zoom with multiple retries to overcome MapBox SDK overrides
  Future<void> _ensureCorrectZoomWithRetries() async {
    if (mapController == null) return;

    const maxRetries = 3; // Reduced retries for smoother experience
    const delayBetweenRetries =
        300; // Slightly longer delay for smooth animation

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        debugPrint('Zoom setting attempt $attempt/$maxRetries');

        // Set camera with the desired zoom using flyTo with smooth animation
        final centerPoint =
            locations.isNotEmpty
                ? locations[0]
                : mapbox.Position(0, 0); // World center

        await mapController!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: centerPoint),
            zoom: currentZoom.value, // Use reactive zoom value
            bearing: 0,
            pitch: 0,
          ),
          mapbox.MapAnimationOptions(
            duration: 400, // Smooth animation duration
            startDelay: 0,
          ),
        );

        // Wait for animation to complete
        await Future.delayed(Duration(milliseconds: delayBetweenRetries));

        // Check if the zoom was actually applied
        final currentCamera = await mapController!.getCameraState();
        debugPrint(
          'After attempt $attempt: camera zoom = ${currentCamera.zoom}',
        );

        // If zoom is correct (within tolerance), we're done
        if ((currentCamera.zoom - currentZoom.value).abs() < 0.1) {
          debugPrint(
            'Zoom successfully set to ${currentZoom.value} after $attempt attempts',
          );
          return;
        }

        // If not the last attempt, wait before retrying
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: delayBetweenRetries));
        }
      } catch (e) {
        debugPrint('Error in zoom attempt $attempt: $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: delayBetweenRetries));
        }
      }
    }

    debugPrint(
      'Warning: Could not set zoom to ${currentZoom.value} after $maxRetries attempts',
    );
  }

  // Ensure camera zoom matches the reactive state
  Future<void> _ensureCameraZoom() async {
    if (mapController == null) {
      debugPrint('🔄 _ensureCameraZoom - Skipping: mapController null');
      return;
    }

    try {
      final currentCamera = await mapController!.getCameraState();
      final targetZoom = currentZoom.value;

      debugPrint(
        '🔄 _ensureCameraZoom - Current camera zoom: ${currentCamera.zoom}, target: $targetZoom',
      );

      // Only adjust if zoom is significantly different
      if ((currentCamera.zoom - targetZoom).abs() > 0.1) {
        debugPrint(
          '🔄 _ensureCameraZoom - Adjusting camera zoom to $targetZoom',
        );

        final centerPoint =
            locations.isNotEmpty
                ? locations[0]
                : mapbox.Position(0, 0); // World center

        await mapController!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(coordinates: centerPoint),
            zoom: targetZoom,
            bearing: 0,
            pitch: 0,
          ),
          mapbox.MapAnimationOptions(
            duration: 500, // Smooth animation duration
            startDelay: 0,
          ),
        );

        debugPrint(
          '🔄 _ensureCameraZoom - Camera zoom set to $targetZoom reactively',
        );
      } else {
        debugPrint(
          '🔄 _ensureCameraZoom - Zoom already correct, no adjustment needed',
        );
      }
    } catch (e) {
      debugPrint('❌ Error in _ensureCameraZoom: $e');
    }
  }

  void onMapCreated(mapbox.MapboxMap controller) async {
    try {
      print('Checking StateForMapCreated: $controller');
      debugPrint(
        '[MapController][onMapCreated] Map created - starting new initialization sequence',
      );
      debugPrint(
        '[MapController][onMapCreated] currentZoom.value: ${currentZoom.value}',
      );
      debugPrint(
        '[MapController][onMapCreated] isShowingNewLocations.value: ${isShowingNewLocations.value}',
      );

      // Clean up any existing resources first
      if (currentAnnotationManager != null) {
        debugPrint(
          '[MapController][onMapCreated] Cleaning up existing annotation manager',
        );
        currentAnnotationManager = null;
      }
      annotations.clear();

      mapController = controller;
      hasInitialized.value = true;

      debugPrint('[MapController][onMapCreated] Setting isMapReady to true');
      isMapReady.value = true;

      // Start the new initialization sequence with Mapbox error handling
      debugPrint(
        '[MapController][onMapCreated] Starting new initialization sequence',
      );
      await _startMapInitializationWithErrorHandling();

      debugPrint(
        '[MapController][onMapCreated] New initialization sequence completed',
      );
    } catch (e) {
      debugPrint('❌ ERROR in onMapCreated: $e');
      await _handleMapboxInitializationError(e);
    }
  }

  /// Start map initialization with enhanced Mapbox error handling
  Future<void> _startMapInitializationWithErrorHandling() async {
    try {
      await startMapInitializationSequence();
    } catch (e) {
      debugPrint('❌ Error in map initialization sequence: $e');
      await _handleMapboxInitializationError(e);
    }
  }

  /// Handle Mapbox-specific initialization errors
  Future<void> _handleMapboxInitializationError(dynamic error) async {
    final errorString = error.toString();

    debugPrint('🔍 Analyzing Mapbox error: $errorString');

    // Use enhanced connectivity service to check for Mapbox errors
    final connectivityService = Get.find<ConnectivityService>();

    // Check if this is a known Mapbox connectivity error
    if (connectivityService.isMapboxConnectivityError(errorString)) {
      debugPrint(
        '🗺 Detected Mapbox connectivity error - notifying connectivity service',
      );

      // Notify connectivity service about the Mapbox error
      connectivityService.handleMapboxConnectivityError(errorString);

      // Use enhanced Mapbox-specific internet check
      final hasInternetForMapbox =
          await connectivityService.hasInternetForMapbox();

      if (!hasInternetForMapbox) {
        debugPrint(
          '🌐 No internet for Mapbox services - setting internetRequired state',
        );
        _setState(MapInitializationState.internetRequired);
        return;
      } else {
        debugPrint(
          '🌐 Internet available but Mapbox failed - retrying in 3 seconds',
        );
        // Internet is available but Mapbox failed, retry after delay
        await Future.delayed(const Duration(seconds: 3));
        try {
          await startMapInitializationSequence();
          return;
        } catch (retryError) {
          debugPrint('❌ Mapbox retry failed: $retryError');
          // If retry also fails, check if it's still a connectivity issue
          if (connectivityService.isMapboxConnectivityError(
            retryError.toString(),
          )) {
            debugPrint(
              '🌐 Retry failed with connectivity error - setting internetRequired state',
            );
            _setState(MapInitializationState.internetRequired);
            return;
          }
        }
      }
    }

    // For other errors or if retry failed with non-connectivity error, go to error state
    debugPrint('❌ Setting error state due to unrecoverable Mapbox error');
    _setState(MapInitializationState.error);

    // Reset state on error to prevent future crashes
    isShowingNewLocations.value = false;
    // Clean up on error
    mapController = null;
    currentAnnotationManager = null;
    annotations.clear();
    hasInitialized.value = false;
    isMapReady.value = false;
  }

  // Check permissions in background without blocking map display
  void _checkLocationPermissionInBackground() async {
    try {
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        debugPrint('Location permission not granted, but map will still work');
      }
    } catch (e) {
      debugPrint('Error checking location permission: $e');
    }
  }

  // Get a random color for memory markers
  // Color getRandomMarkerColor(int? seed) {
  //   // final random = seed != null ? math.Random(seed) : math.Random();
  //   return markerColors[Random().nextInt(markerColors.length)];
  // }

  // Get color for memory based on its year
  Color getColorForMemoryYear(DateTime memoryDate) {
    return getColorForYear(memoryDate.year);
  }

  // Get color name for a year (for debugging/display)
  String getColorNameForYear(int year) {
    final colorNames = [
      'Blue',
      'Green',
      'Orange',
      'Purple',
      'Red',
      'Cyan',
      'Yellow',
      'Brown',
      'Blue Grey',
      'Pink',
      'Indigo',
      'Teal',
      'Deep Orange',
      'Light Green',
      'Lime',
      'Amber',
      'Deep Purple',
      'Green Accent',
      'Red Accent',
      'Blue Accent',
    ];

    final colorIndex = getColorIndexForYear(year);
    return colorNames[colorIndex];
  }

  /// Print year-color mapping for debugging and demonstration
  /// Shows the complete mapping for past 50 years and next 50 years
  void printYearColorMapping() {
    debugPrint(
      '🎨 YEAR COLOR MAPPING - Complete List (Past 50 + Next 50 years)',
    );
    debugPrint('📅 Base Year: $baseYear (Current Year)');
    debugPrint('🌈 Total Colors: ${markerColors.length}');
    debugPrint('');

    // Print color palette
    debugPrint('🎨 COLOR PALETTE:');
    for (int i = 0; i < markerColors.length; i++) {
      final colorName =
          [
            'Blue',
            'Green',
            'Orange',
            'Purple',
            'Red',
            'Cyan',
            'Yellow',
            'Brown',
            'Blue Grey',
            'Pink',
            'Indigo',
            'Teal',
            'Deep Orange',
            'Light Green',
            'Lime',
            'Amber',
            'Deep Purple',
            'Green Accent',
            'Red Accent',
            'Blue Accent',
          ][i];
      debugPrint('  $i: $colorName (${markerColors[i].toString()})');
    }
    debugPrint('');

    // Print year mappings
    debugPrint('📅 YEAR-COLOR MAPPINGS:');

    // Past years
    debugPrint('📜 PAST YEARS (${baseYear - 50} to ${baseYear - 1}):');
    for (int year = baseYear - 50; year < baseYear; year++) {
      final color = getColorForYear(year);
      final colorName = getColorNameForYear(year);
      final colorIndex = getColorIndexForYear(year);
      debugPrint(
        '  $year: $colorName (Index: $colorIndex, Color: ${color.toString()})',
      );
    }

    // Current year
    debugPrint('');
    debugPrint('🎯 CURRENT YEAR:');
    final currentColor = getColorForYear(baseYear);
    final currentColorName = getColorNameForYear(baseYear);
    final currentColorIndex = getColorIndexForYear(baseYear);
    debugPrint(
      '  $baseYear: $currentColorName (Index: $currentColorIndex, Color: ${currentColor.toString()}) ⭐',
    );

    // Future years
    debugPrint('');
    debugPrint('🔮 FUTURE YEARS (${baseYear + 1} to ${baseYear + 50}):');
    for (int year = baseYear + 1; year <= baseYear + 50; year++) {
      final color = getColorForYear(year);
      final colorName = getColorNameForYear(year);
      final colorIndex = getColorIndexForYear(year);
      debugPrint(
        '  $year: $colorName (Index: $colorIndex, Color: ${color.toString()})',
      );
    }

    debugPrint('');
    debugPrint('🔄 PATTERN REPEATS EVERY ${markerColors.length} YEARS');
    debugPrint('✅ Year-Color Mapping Complete!');
  }

  // Initialize user's current location for map center
  void _initializeUserLocation() async {
    try {
      debugPrint('🌍 LOCATION - Getting user current location for map center');

      // Check if location services are enabled and permissions are granted
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        debugPrint(
          '🌍 LOCATION - No location permission, using default center',
        );
        userCurrentLocation.value = mapbox.Position(0, 0); // World center
        return;
      }

      // Get current position
      final position = await geolocator.Geolocator.getCurrentPosition(
        locationSettings: geolocator.LocationSettings(
          accuracy: geolocator.LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      userCurrentLocation.value = mapbox.Position(
        position.longitude,
        position.latitude,
      );

      debugPrint(
        '🌍 LOCATION - User location set to: ${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      debugPrint('🌍 LOCATION - Error getting user location: $e');
      // Fallback to world center
      userCurrentLocation.value = mapbox.Position(0, 0);
    }
  }

  // Build the MapWidget with proper initial state - can be recreated to simulate restart
  Widget buildMapWidget(BuildContext context) {
    debugPrint('🏗 BUILDING MapWidget with zoom: ${currentZoom.value}');
    debugPrint(
      '🏗 BUILDING MapWidget with locations count: ${locations.length}',
    );
    debugPrint(
      '🏗 BUILDING MapWidget with isShowingNewLocations: ${isShowingNewLocations.value}',
    );
    debugPrint(
      '🏗 BUILDING MapWidget with recreation flag: ${shouldRecreateMap.value}',
    );

    return mapbox.MapWidget(
      key: ValueKey(
        "mainMap_${shouldRecreateMap.value}_$_mapRecreationCount",
      ), // Use recreation flag in key to force rebuilds when needed
      mapOptions: mapbox.MapOptions(
        contextMode: mapbox.ContextMode.UNIQUE,
        constrainMode: mapbox.ConstrainMode.HEIGHT_ONLY,
        viewportMode: mapbox.ViewportMode.DEFAULT,
        orientation: mapbox.NorthOrientation.UPWARDS,
        crossSourceCollisions: true,
        size: mapbox.Size(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
        ),
        pixelRatio: MediaQuery.of(context).devicePixelRatio,
        glyphsRasterizationOptions: mapbox.GlyphsRasterizationOptions(
          rasterizationMode:
              mapbox.GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
        ),
      ),
      cameraOptions: mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates:
              locations.isNotEmpty ? locations[0] : mapbox.Position(0, 0),
        ),
        zoom: currentZoom.value, // Use reactive zoom state
        bearing: 0,
        pitch: 0,
      ),
      styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
      textureView: true,

      onMapCreated: onMapCreated,
      onTapListener: _onMapTapped,
  
      onMapLoadErrorListener: (mapLoadingErrorEventData) async {
        print('Checking StateForMapErrorLoading: $mapLoadingErrorEventData');

        try {
          final connectivityService = Get.find<ConnectivityService>();
          _setState(MapInitializationState.internetRequired);

          // Perform enhanced internet check for Mapbox services
          final hasInternetForMapbox =
              await connectivityService.hasInternetForMapbox();

          if (hasInternetForMapbox) {
            _setState(MapInitializationState.ready);
            refreshMapView();
          }

          // } else {
          //   debugPrint('❌ Map load error is not connectivity-related - showing error screen');
          //   debugPrint('❌ Error details: $errorMessage');
          //   _setState(MapInitializationState.error);
          // }
        } catch (e) {
          debugPrint('❌ Error handling map load error: $e');
          _setState(MapInitializationState.error);
        }
      },
    );
  }

  Future<void> _clearAllMarkerImages() async {
    if (mapController == null) return;

    // Remove all existing marker style images
    for (int i = 0; i < 20; i++) {
      // Clear original marker images
      try {
        await mapController!.style.removeStyleImage('marker_$i');
      } catch (e) {
        // Ignore if image doesn't exist
      }

      // Clear new marker images
      try {
        await mapController!.style.removeStyleImage('new_marker_$i');
      } catch (e) {
        // Ignore if image doesn't exist
      }

      // Clear arrow images
      try {
        await mapController!.style.removeStyleImage('arrow_$i');
      } catch (e) {
        // Ignore if image doesn't exist
      }
    }
  }

  Future<void> _clearAllLines() async {
    if (mapController == null) return;

    // Remove all existing lines and arrows
    for (int i = 0; i < 20; i++) {
      // Clear original lines and arrows
      try {
        await mapController!.style.removeStyleLayer('line_layer_$i');
      } catch (e) {
        // Ignore if layer doesn't exist
      }
      try {
        await mapController!.style.removeStyleSource('line_$i');
      } catch (e) {
        // Ignore if source doesn't exist
      }
      try {
        await mapController!.style.removeStyleLayer('arrow_layer_$i');
      } catch (e) {
        // Ignore if layer doesn't exist
      }
      try {
        await mapController!.style.removeStyleSource('arrow_source_$i');
      } catch (e) {
        // Ignore if source doesn't exist
      }

      // Clear new lines and arrows
      try {
        await mapController!.style.removeStyleLayer('new_line_layer_$i');
      } catch (e) {
        // Ignore if layer doesn't exist
      }
      try {
        await mapController!.style.removeStyleSource('new_line_$i');
      } catch (e) {
        // Ignore if source doesn't exist
      }

      // Clear detail lines and arrows
      try {
        await mapController!.style.removeStyleLayer('detail_line_layer_$i');
      } catch (e) {
        // Ignore if source doesn't exist
      }
      try {
        await mapController!.style.removeStyleSource('detail_line_$i');
      } catch (e) {
        // Ignore if source doesn't exist
      }
      try {
        await mapController!.style.removeStyleLayer('detail_arrow_layer_$i');
      } catch (e) {
        // Ignore if layer doesn't exist
      }
      try {
        await mapController!.style.removeStyleSource('detail_arrow_source_$i');
      } catch (e) {
        // Ignore if source doesn't exist
      }
    }
  }

  Future<void> clearAllLines() async {
    _clearAllLines();
    print('Controller: Lines cleared');
  }

  Future<void> clearAllMarkersAndClusters() async {
    clearAllMarkersAndClusters();

    print('Controller: clearAllMarkersAndClusters cleared');
  }

  Future<void> initializeMemoryClustering() async {
    print('Controller: _initializeMemoryClustering cleared');
    _initializeMemoryClustering();
  }

  Future<void> setupApp() async {
    debugPrint(
      '[MapController][setupApp] Starting sequential initialization logic',
    );

    // Initialize offline functionality in background
    await _initializeOfflineInBackground();

    // Set up reactive workers for proper state management
    debugPrint('[MapController][setupApp] Setting up reactive workers');
    _setupReactiveWorkers();

    // Start the sequential initialization process
    await startSequentialInitialization();

    debugPrint('[MapController][setupApp] Sequential setup complete');
  }

  /// Check initial connectivity state and set appropriate UI state on app launch
  void _checkInitialConnectivityAndSetState() {
    // Run asynchronously to avoid blocking onInit
    Future.delayed(const Duration(milliseconds: 100), () async {
      try {
        debugPrint('🌐 Checking initial connectivity state for UI');

        final connectivityService = Get.find<ConnectivityService>();

        // Wait for connectivity service to initialize
        int attempts = 0;
        while (!connectivityService.isInitialized.value && attempts < 20) {
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }

        if (!connectivityService.isInitialized.value) {
          debugPrint(
            '⚠️ ConnectivityService not initialized after waiting, checking manually',
          );
          // Force a connectivity check
          await connectivityService.refreshConnectivity();
        }

        // Check current connectivity state
        final hasInternet = connectivityService.isConnected.value;
        final connectionType = connectivityService.connectionType.value;
        debugPrint(
          '🌐 Initial connectivity: hasInternet = $hasInternet, type = $connectionType',
        );

        // ALWAYS start with permission checking first, regardless of internet status
        // Internet screen will only be shown after permissions are granted
        debugPrint(
          '🔐 Starting with permission check - internet status will be checked after permissions are granted',
        );
        _setState(MapInitializationState.checkingPermission);
      } catch (e) {
        debugPrint('❌ Error in initial connectivity check: $e');
        // On error, still start with permission check - don't bypass to internet screen
        debugPrint(
          '🔐 Error occurred but still starting with permission check',
        );
        _setState(MapInitializationState.checkingPermission);
      }
    });
  }

  /// Check initial connectivity state to determine if internet screen should be shown
  Future<void> _checkInitialConnectivityState() async {
    try {
      debugPrint('🌐 Checking initial connectivity state');

      final connectivityService = Get.find<ConnectivityService>();

      // Wait for connectivity service to initialize
      int attempts = 0;
      while (!connectivityService.isInitialized.value && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 100));
        attempts++;
      }

      // Check if we have offline tiles
      hasOfflineTiles.value = await isOfflineDataAvailable();

      // Check internet connectivity
      final hasInternet = await connectivityService.hasInternetForMaps();

      // Determine if we should show internet screen
      if (isFirstTimeLoad.value && !hasInternet && !hasOfflineTiles.value) {
        shouldShowInternetScreen.value = true;
        needsInternetConnection.value = true;
        debugPrint(
          '🌐 First time load without internet and no offline tiles - showing internet screen',
        );
      } else {
        shouldShowInternetScreen.value = false;
        needsInternetConnection.value = false;
        isFirstTimeLoad.value = false;
        debugPrint(
          '🌐 Internet available or offline tiles present - proceeding normally',
        );
      }
    } catch (e) {
      debugPrint('❌ Error checking initial connectivity state: $e');
      // Default to showing internet screen on error for first time load
      if (isFirstTimeLoad.value) {
        shouldShowInternetScreen.value = true;
        needsInternetConnection.value = true;
      }
    }
  }

  /// New loading sequence: Use state-based flow for proper connectivity and permission checking
  Future<void> startMapInitializationSequence() async {
    debugPrint(
      '[MapController][startMapInitializationSequence] Starting state-based map initialization sequence',
    );

    try {
      // Instead of bypassing the state machine, use the proper state-based flow
      // This ensures connectivity and permissions are checked properly

      // Check current state and determine where to start
      if (currentInitializationState.value == MapInitializationState.initial ||
          currentInitializationState.value ==
              MapInitializationState.checkingPermission) {
        debugPrint(
          '[MapController][startMapInitializationSequence] Starting from permission check',
        );
        _setState(MapInitializationState.checkingPermission);
      } else if (currentInitializationState.value ==
          MapInitializationState.internetRequired) {
        debugPrint(
          '[MapController][startMapInitializationSequence] Internet required - staying in current state',
        );
        // Stay in internetRequired state - user needs to resolve connectivity
        return;
      } else {
        debugPrint(
          '[MapController][startMapInitializationSequence] Continuing from current state: ${currentInitializationState.value}',
        );
      }

      debugPrint(
        '[MapController][startMapInitializationSequence] State-based initialization sequence started',
      );
    } catch (e) {
      debugPrint(
        '[MapController][startMapInitializationSequence] Error in initialization sequence: $e',
      );
      debugPrint(
        '[MapController][startMapInitializationSequence] Error type: ${e.runtimeType}',
      );
      debugPrint(
        '[MapController][startMapInitializationSequence] Stack trace: ${StackTrace.current}',
      );

      // On error, set error state
      _setState(MapInitializationState.error);
    }
  }

  /// Legacy direct initialization method - now moved to state-based handlers
  Future<void> _performDirectMapInitialization() async {
    debugPrint(
      '[MapController][_performDirectMapInitialization] Performing direct map initialization',
    );

    try {
      // Step 1: Set initial map location (permission should already be checked by state machine)
      debugPrint(
        '[MapController][_performDirectMapInitialization] Step 1: Setting initial map location',
      );
      final permissionService = Get.find<PermissionService>();
      final hasLocationPermission =
          permissionService.hasLocationPermission.value;
      await _setInitialMapLocation(hasLocationPermission);

      // Step 2: Wait for map to be ready and positioned
      debugPrint(
        '[MapController][_performDirectMapInitialization] Step 2: Waiting for map to be ready',
      );
      await _waitForMapReady();

      // Step 3: Load data from database
      debugPrint(
        '[MapController][_performDirectMapInitialization] Step 3: Loading data from database',
      );
      await loadMemoriesFromDatabase();

      // Step 4: Create clusters and draw lines
      debugPrint(
        '[MapController][_performDirectMapInitialization] Step 4: Creating clusters and drawing lines',
      );
      await _initializeMemoryClustering();

      // Step 5: Add click to zoom functionality
      debugPrint(
        '[MapController][_performDirectMapInitialization] Step 5: Setting up click to zoom',
      );
      _setupClickToZoom();

      debugPrint(
        '[MapController][_performDirectMapInitialization] Direct map initialization completed successfully',
      );
    } catch (e) {
      debugPrint(
        '[MapController][_performDirectMapInitialization] Error in direct initialization: $e',
      );
      throw e; // Re-throw to be handled by caller
    }
  }

  /// Set initial map location based on permission status
  Future<void> _setInitialMapLocation(bool hasLocationPermission) async {
    debugPrint(
      '[MapController][_setInitialMapLocation] Setting initial location, permission: $hasLocationPermission',
    );

    if (hasLocationPermission) {
      debugPrint(
        '[MapController][_setInitialMapLocation] Permission granted, getting current location',
      );
      try {
        final position = await geolocator.Geolocator.getCurrentPosition();

        debugPrint(
          '[MapController][_setInitialMapLocation] Got current position: ${position.latitude}, ${position.longitude}',
        );

        // Set current location
        final currentLocation = mapbox.Position(
          position.longitude,
          position.latitude,
        );
        locations.clear();
        locations.add(currentLocation);

        debugPrint(
          '[MapController][_setInitialMapLocation] Set current location in locations list',
        );
      } catch (e) {
        debugPrint(
          '[MapController][_setInitialMapLocation] Error getting current location: $e',
        );
        debugPrint(
          '[MapController][_setInitialMapLocation] Falling back to hardcoded location',
        );
        _setHardcodedLocation();
      }
    } else {
      debugPrint(
        '[MapController][_setInitialMapLocation] Permission denied, using hardcoded location',
      );
      _setHardcodedLocation();
    }
  }

  /// Set hardcoded location (fallback when no permission)
  void _setHardcodedLocation() {
    debugPrint(
      '[MapController][_setHardcodedLocation] Setting hardcoded location',
    );

    // Use a default location (San Francisco)
    const defaultLat = 37.7749;
    const defaultLng = -122.4194;

    final hardcodedLocation = mapbox.Position(defaultLng, defaultLat);
    locations.clear();
    locations.add(hardcodedLocation);

    debugPrint(
      '[MapController][_setHardcodedLocation] Set hardcoded location: $defaultLat, $defaultLng',
    );
  }

  /// Wait for map to be ready and positioned
  Future<void> _waitForMapReady() async {
    debugPrint('[MapController][_waitForMapReady] Waiting for map to be ready');

    int attempts = 0;
    const maxAttempts = 30; // 15 seconds max wait
    const checkInterval = Duration(milliseconds: 500);

    while (attempts < maxAttempts) {
      debugPrint(
        '[MapController][_waitForMapReady] Check attempt ${attempts + 1}/$maxAttempts',
      );
      debugPrint(
        '[MapController][_waitForMapReady] isMapReady: ${isMapReady.value}',
      );
      debugPrint(
        '[MapController][_waitForMapReady] mapController null: ${mapController == null}',
      );

      if (isMapReady.value && mapController != null) {
        debugPrint('[MapController][_waitForMapReady] Map is ready!');

        // Move camera to the set location
        if (locations.isNotEmpty) {
          debugPrint(
            '[MapController][_waitForMapReady] Moving camera to initial location',
          );
          await mapController!.flyTo(
            mapbox.CameraOptions(
              center: mapbox.Point(coordinates: locations[0]),
              zoom: 5.0,
              bearing: 0,
              pitch: 0,
            ),
            mapbox.MapAnimationOptions(duration: 1500),
          );
          debugPrint(
            '[MapController][_waitForMapReady] Camera moved to initial location',
          );
        }

        return;
      }

      attempts++;
      await Future.delayed(checkInterval);
    }

    debugPrint(
      '[MapController][_waitForMapReady] WARNING: Map not ready after ${maxAttempts * checkInterval.inMilliseconds}ms',
    );
  }

  /// Setup click to zoom functionality
  void _setupClickToZoom() {
    debugPrint(
      '[MapController][_setupClickToZoom] Setting up click to zoom functionality',
    );

    // Click to zoom is now handled by the _onMapTapped method
    debugPrint(
      '[MapController][_setupClickToZoom] Click to zoom setup completed',
    );
  }

  /// Handle map tap events for click to zoom functionality
  void _onMapTapped(mapbox.MapContentGestureContext context) {
    debugPrint(
      '[MapController][_onMapTapped] Map tapped at coordinates: ${context.point.coordinates}',
    );

    if (mapController == null) {
      debugPrint(
        '[MapController][_onMapTapped] Map controller is null, ignoring tap',
      );
      return;
    }

    try {
      // Get current zoom level
      final currentZoomLevel = currentZoom.value;
      debugPrint(
        '[MapController][_onMapTapped] Current zoom level: $currentZoomLevel',
      );

      // Calculate new zoom level (zoom in by 1 level, max zoom 18)
      final newZoomLevel = math.min(currentZoomLevel + 1.0, 18.0);
      debugPrint('[MapController][_onMapTapped] New zoom level: $newZoomLevel');

      if (newZoomLevel == currentZoomLevel) {
        debugPrint(
          '[MapController][_onMapTapped] Already at maximum zoom, ignoring tap',
        );
        return;
      }

      // Update the zoom level
      currentZoom.value = newZoomLevel;

      // Animate to the tapped location with new zoom
      debugPrint(
        '[MapController][_onMapTapped] Animating to tapped location with zoom: $newZoomLevel',
      );
      mapController!.flyTo(
        mapbox.CameraOptions(
          center: context.point,
          zoom: newZoomLevel,
          bearing: 0,
          pitch: 0,
        ),
        mapbox.MapAnimationOptions(
          duration: 800, // Smooth zoom animation
          startDelay: 0,
        ),
      );

      debugPrint(
        '[MapController][_onMapTapped] Click to zoom animation started',
      );
    } catch (e) {
      debugPrint('[MapController][_onMapTapped] Error in click to zoom: $e');
      debugPrint('[MapController][_onMapTapped] Error type: ${e.runtimeType}');
    }
  }

  /// Print all current cluster data and memories - can be called anytime for debugging
  void printAllClusterData() {
    debugPrint(
      '[MapController][printAllClusterData] ========== ALL CLUSTER DATA DUMP ==========',
    );
    debugPrint(
      '[MapController][printAllClusterData] Total Clusters: ${currentClusters.length}',
    );
    debugPrint(
      '[MapController][printAllClusterData] Total Arrows: ${currentArrows.length}',
    );
    debugPrint(
      '[MapController][printAllClusterData] Cluster Level: ${currentClusterLevel.value}',
    );
    debugPrint(
      '[MapController][printAllClusterData] Selected Cluster: ${selectedCluster.value?.id ?? 'None'}',
    );

    if (currentClusters.isEmpty) {
      debugPrint(
        '[MapController][printAllClusterData] ❌ NO CLUSTERS AVAILABLE',
      );
      return;
    }

    for (int i = 0; i < currentClusters.length; i++) {
      final cluster = currentClusters[i];

      debugPrint(
        '[MapController][printAllClusterData] === CLUSTER ${i + 1} OF ${currentClusters.length} ===',
      );
      debugPrint(
        '[MapController][printAllClusterData] Cluster ID: ${cluster.id}',
      );
      debugPrint(
        '[MapController][printAllClusterData] Memory Count: ${cluster.memoryCount}',
      );
      debugPrint(
        '[MapController][printAllClusterData] Center: ${cluster.centerLatitude.toStringAsFixed(6)}, ${cluster.centerLongitude.toStringAsFixed(6)}',
      );
      debugPrint(
        '[MapController][printAllClusterData] Radius: ${cluster.radiusKm}km',
      );
      debugPrint(
        '[MapController][printAllClusterData] Date Range: ${cluster.earliestDate} to ${cluster.latestDate}',
      );
      debugPrint(
        '[MapController][printAllClusterData] Is Single Memory: ${cluster.memoryCount == 1}',
      );

      // Print all memories in this cluster
      debugPrint(
        '[MapController][printAllClusterData] --- MEMORIES IN CLUSTER ${i + 1} ---',
      );
      for (int memIndex = 0; memIndex < cluster.memories.length; memIndex++) {
        final memory = cluster.memories[memIndex];
        debugPrint(
          '[MapController][printAllClusterData] Memory ${memIndex + 1}/${cluster.memories.length}:',
        );
        debugPrint('[MapController][printAllClusterData]   ID: ${memory.id}');
        debugPrint(
          '[MapController][printAllClusterData]   Title: "${memory.title}"',
        );
        debugPrint(
          '[MapController][printAllClusterData]   Description: "${memory.description}"',
        );
        debugPrint(
          '[MapController][printAllClusterData]   Location: ${memory.latitude.toStringAsFixed(6)}, ${memory.longitude.toStringAsFixed(6)}',
        );
        debugPrint(
          '[MapController][printAllClusterData]   Date: ${memory.memoryDate}',
        );

        // Print key metadata
        final metadata = memory.metadata;
        if (metadata.containsKey('location')) {
          debugPrint(
            '[MapController][printAllClusterData]   Original Location: "${metadata['location']}"',
          );
        }
        if (metadata.containsKey('place_category')) {
          debugPrint(
            '[MapController][printAllClusterData]   Category: "${metadata['place_category']}"',
          );
        }
        if (metadata.containsKey('hashtags')) {
          debugPrint(
            '[MapController][printAllClusterData]   Hashtags: "${metadata['hashtags']}"',
          );
        }

        // Check for media
        final hasImages =
            metadata.containsKey('images') &&
            metadata['images'] != null &&
            metadata['images'].toString().isNotEmpty;
        final hasVoice =
            metadata.containsKey('voice_notes') &&
            metadata['voice_notes'] != null &&
            metadata['voice_notes'].toString().isNotEmpty;
        debugPrint(
          '[MapController][printAllClusterData]   Media: Images=${hasImages}, Voice=${hasVoice}',
        );

        // Print timestamps
        if (metadata.containsKey('created_at')) {
          debugPrint(
            '[MapController][printAllClusterData]   Created: ${metadata['created_at']}',
          );
        }
        if (metadata.containsKey('updated_at')) {
          debugPrint(
            '[MapController][printAllClusterData]   Updated: ${metadata['updated_at']}',
          );
        }
      }
    }

    // Print arrow information
    debugPrint(
      '[MapController][printAllClusterData] === CHRONOLOGICAL ARROWS ===',
    );
    debugPrint(
      '[MapController][printAllClusterData] Total Arrows: ${currentArrows.length}',
    );

    for (int i = 0; i < currentArrows.length; i++) {
      final arrow = currentArrows[i];
      debugPrint('[MapController][printAllClusterData] Arrow ${i + 1}:');
      debugPrint(
        '[MapController][printAllClusterData]   From: ${arrow.fromLatitude.toStringAsFixed(6)}, ${arrow.fromLongitude.toStringAsFixed(6)} (${arrow.fromClusterId})',
      );
      debugPrint(
        '[MapController][printAllClusterData]   To: ${arrow.toLatitude.toStringAsFixed(6)}, ${arrow.toLongitude.toStringAsFixed(6)} (${arrow.toClusterId})',
      );
      debugPrint(
        '[MapController][printAllClusterData]   Time: ${arrow.fromDate} → ${arrow.toDate}',
      );
      debugPrint(
        '[MapController][printAllClusterData]   Distance: ${arrow.distance.toStringAsFixed(2)}km, Bearing: ${arrow.bearing.toStringAsFixed(1)}°',
      );
    }

    debugPrint(
      '[MapController][printAllClusterData] ========== END CLUSTER DATA DUMP ==========',
    );
  }

  /// Print cluster statistics summary
  void printClusterStats() {
    debugPrint('[MapController][printClusterStats] === CLUSTER STATISTICS ===');
    debugPrint(
      '[MapController][printClusterStats] Total Memories: ${allMemories.length}',
    );
    debugPrint(
      '[MapController][printClusterStats] Total Clusters: ${currentClusters.length}',
    );
    debugPrint(
      '[MapController][printClusterStats] Total Arrows: ${currentArrows.length}',
    );
    debugPrint(
      '[MapController][printClusterStats] Cluster Level: ${currentClusterLevel.value}',
    );

    if (currentClusters.isNotEmpty) {
      final memoryCounts = currentClusters.map((c) => c.memoryCount).toList();
      final totalMemoriesInClusters = memoryCounts.reduce((a, b) => a + b);
      final avgMemoriesPerCluster =
          totalMemoriesInClusters / currentClusters.length;
      final maxMemoriesInCluster = memoryCounts.reduce((a, b) => a > b ? a : b);
      final minMemoriesInCluster = memoryCounts.reduce((a, b) => a < b ? a : b);

      debugPrint(
        '[MapController][printClusterStats] Memories in Clusters: $totalMemoriesInClusters',
      );
      debugPrint(
        '[MapController][printClusterStats] Avg Memories/Cluster: ${avgMemoriesPerCluster.toStringAsFixed(1)}',
      );
      debugPrint(
        '[MapController][printClusterStats] Max Memories in Single Cluster: $maxMemoriesInCluster',
      );
      debugPrint(
        '[MapController][printClusterStats] Min Memories in Single Cluster: $minMemoriesInCluster',
      );

      final singleMemoryClusters =
          currentClusters.where((c) => c.memoryCount == 1).length;
      debugPrint(
        '[MapController][printClusterStats] Single Memory Clusters: $singleMemoryClusters',
      );
      debugPrint(
        '[MapController][printClusterStats] Multi Memory Clusters: ${currentClusters.length - singleMemoryClusters}',
      );
    }

    debugPrint('[MapController][printClusterStats] === END STATISTICS ===');
  }

  /// Generate a unique, consistent color for each cluster based on cluster ID and memory ID
  Color _getUniqueColorForCluster(String clusterId, String memoryId) {
    debugPrint(
      '[MapController][_getUniqueColorForCluster] Generating unique color for cluster: $clusterId, memory: $memoryId',
    );

    // Combine cluster ID and memory ID for uniqueness
    final combinedId = '$clusterId-$memoryId';

    // Create a hash from the combined ID
    int hash = combinedId.hashCode;

    // Ensure positive hash
    hash = hash.abs();

    debugPrint(
      '[MapController][_getUniqueColorForCluster] Combined ID: $combinedId, Hash: $hash',
    );

    // Define a set of distinct, visually appealing colors for single memories
    final List<Color> singleMemoryColors = [
      const Color(0xFF2196F3), // Blue
      const Color(0xFF4CAF50), // Green
      const Color(0xFFFF9800), // Orange
      const Color(0xFF9C27B0), // Purple
      const Color(0xFFF44336), // Red
      const Color(0xFF00BCD4), // Cyan
      const Color(0xFFFFEB3B), // Yellow
      const Color(0xFF795548), // Brown
      const Color(0xFF607D8B), // Blue Grey
      const Color(0xFFE91E63), // Pink
      const Color(0xFF3F51B5), // Indigo
      const Color(0xFF8BC34A), // Light Green
      const Color(0xFFFF5722), // Deep Orange
      const Color(0xFF673AB7), // Deep Purple
      const Color(0xFF009688), // Teal
      const Color(0xFFFFC107), // Amber
      const Color(0xFF9E9E9E), // Grey
      const Color(0xFF5D4037), // Brown
      const Color(0xFF37474F), // Blue Grey Dark
      const Color(0xFFAD1457), // Pink Dark
    ];

    // Use hash to select color consistently
    final colorIndex = hash % singleMemoryColors.length;
    final selectedColor = singleMemoryColors[colorIndex];

    debugPrint(
      '[MapController][_getUniqueColorForCluster] Selected color index: $colorIndex, Color: ${selectedColor.toString()}',
    );

    return selectedColor;
  }

  /// Verify that all current cluster IDs are unique
  bool verifyClusterIdUniqueness() {
    debugPrint(
      '[MapController][verifyClusterIdUniqueness] === VERIFYING CLUSTER ID UNIQUENESS ===',
    );

    final Set<String> clusterIds = <String>{};
    final List<String> duplicateIds = <String>[];

    for (int i = 0; i < currentClusters.length; i++) {
      final cluster = currentClusters[i];

      if (clusterIds.contains(cluster.id)) {
        duplicateIds.add(cluster.id);
        debugPrint(
          '[MapController][verifyClusterIdUniqueness] ❌ DUPLICATE: Cluster ${i + 1} has duplicate ID: ${cluster.id}',
        );
      } else {
        clusterIds.add(cluster.id);
        debugPrint(
          '[MapController][verifyClusterIdUniqueness] ✅ UNIQUE: Cluster ${i + 1} has unique ID: ${cluster.id}',
        );
      }
    }

    debugPrint(
      '[MapController][verifyClusterIdUniqueness] === UNIQUENESS VERIFICATION RESULTS ===',
    );
    debugPrint(
      '[MapController][verifyClusterIdUniqueness] Total clusters: ${currentClusters.length}',
    );
    debugPrint(
      '[MapController][verifyClusterIdUniqueness] Unique IDs: ${clusterIds.length}',
    );
    debugPrint(
      '[MapController][verifyClusterIdUniqueness] Duplicate IDs: ${duplicateIds.length}',
    );

    if (duplicateIds.isNotEmpty) {
      debugPrint(
        '[MapController][verifyClusterIdUniqueness] ❌ CRITICAL: Found ${duplicateIds.length} duplicate IDs: $duplicateIds',
      );
      return false;
    } else {
      debugPrint(
        '[MapController][verifyClusterIdUniqueness] ✅ SUCCESS: All ${currentClusters.length} cluster IDs are unique',
      );
      return true;
    }
  }

  /// Get cluster ID statistics
  void printClusterIdStats() {
    debugPrint(
      '[MapController][printClusterIdStats] === CLUSTER ID STATISTICS ===',
    );

    final Map<String, int> idCounts = <String, int>{};

    for (final cluster in currentClusters) {
      idCounts[cluster.id] = (idCounts[cluster.id] ?? 0) + 1;
    }

    debugPrint(
      '[MapController][printClusterIdStats] Total clusters: ${currentClusters.length}',
    );
    debugPrint(
      '[MapController][printClusterIdStats] Unique IDs: ${idCounts.length}',
    );

    // Show any IDs that appear more than once
    final duplicates =
        idCounts.entries.where((entry) => entry.value > 1).toList();

    if (duplicates.isNotEmpty) {
      debugPrint('[MapController][printClusterIdStats] ❌ DUPLICATES FOUND:');
      for (final duplicate in duplicates) {
        debugPrint(
          '[MapController][printClusterIdStats]   ID "${duplicate.key}" appears ${duplicate.value} times',
        );
      }
    } else {
      debugPrint(
        '[MapController][printClusterIdStats] ✅ All cluster IDs are unique',
      );
    }

    // Show sample of cluster IDs
    debugPrint('[MapController][printClusterIdStats] Sample cluster IDs:');
    for (int i = 0; i < math.min(5, currentClusters.length); i++) {
      debugPrint(
        '[MapController][printClusterIdStats]   Cluster ${i + 1}: ${currentClusters[i].id}',
      );
    }

    debugPrint(
      '[MapController][printClusterIdStats] === END ID STATISTICS ===',
    );
  }

  void setEnhancedLocationData(locationData) {
    if (locationData != null) {
      print('locationData $locationData');

      // Set enhanced location fields first

      var locationLatitude = locationData['latitude']?.toDouble();
      var locationLongitude = locationData['longitude']?.toDouble();

      // Always set selectedLocation as lat,lng coordinates
      if (locationLatitude != null && locationLongitude != null) {
        selectedLocation.value = '${locationLatitude},${locationLongitude}';
      } else {
        selectedLocation.value = '';
      }
    }
  }
}
