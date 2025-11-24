import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Uint8List;
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/click_listener.dart';
import 'package:spacetime/app/routes/app_pages.dart';

import '../views/mini_widgets/bottom_info.dart';
import '../../add_memories/controllers/add_memories_controller.dart';
import '../../add_memories/views/add_memories.dart';
import '../../../../services/memory_clustering_service.dart';
import '../../../services/memory_db.dart';

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

  // User's current location for initial map center
  var userCurrentLocation = mapbox.Position(0, 0).obs;

  // Predefined colors for memory markers (10 colors)
  final List<Color> markerColors = [
    const Color(0xFF2196F3), // Blue
    const Color(0xFF4CAF50), // Green
    const Color(0xFFFF9800), // Orange
    const Color(0xFF9C27B0), // Purple
    const Color(0xFFF44336), // Red
  ];
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
      debugPrint('🗺 OFFLINE - Initializing offline map components');
      offlineManager = await OfflineManager.create();
      tileStore = await TileStore.createDefault();
      tileStore?.setDiskQuota(
        null,
      ); // Reset to default (setDiskQuota returns void)
      debugPrint(
        '🗺 OFFLINE - Offline map components initialized successfully',
      );
    } catch (e) {
      debugPrint('❌ OFFLINE - Error initializing offline map: $e');
    }
  }

  Future<void> downloadStylePack() async {
    try {
      debugPrint('🗺 OFFLINE - Starting style pack download');

      final stylePackLoadOptions = StylePackLoadOptions(
        glyphsRasterizationMode:
            GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
        metadata: {"tag": "offline"},
        acceptExpired: false,
      );

      await offlineManager
          ?.loadStylePack(
           mapbox.MapboxStyles.MAPBOX_STREETS, // Change style if needed
            stylePackLoadOptions,
            (progress) {
              final percentage =
                  progress.completedResourceCount /
                  progress.requiredResourceCount;
              debugPrint(
                '🗺 OFFLINE - Style pack progress: ${(percentage * 100).toStringAsFixed(1)}%',
              );
              if (!stylePackProgress.isClosed) {
                stylePackProgress.sink.add(percentage);
              }
            },
          )
          .then((_) {
            debugPrint('🗺 OFFLINE - Style pack download completed');
            if (!stylePackProgress.isClosed) {
              stylePackProgress.sink.add(1.0);
              stylePackProgress.close();
            }
          });
    } catch (e) {
      debugPrint('❌ OFFLINE - Error downloading style pack: $e');
      if (!stylePackProgress.isClosed) {
        stylePackProgress.sink.addError(e);
        stylePackProgress.close();
      }
    }
  }

  Future<void> downloadTileRegion() async {
    try {
      debugPrint('🗺 OFFLINE - Starting tile region download');

      // Get user's current location to determine region
      final userRegion = await _getUserRegionBounds();

      debugPrint(
        '🗺 OFFLINE - Downloading tiles for region: ${userRegion['name']}',
      );

      final tileOptions = TileRegionLoadOptions(
        geometry: userRegion['geometry'],
        descriptorsOptions: [
          TilesetDescriptorOptions(
            styleURI: MapboxStyles.MAPBOX_STREETS,
            minZoom: 6, // Lower zoom for larger areas
            maxZoom: 14, // Reasonable max zoom for regional coverage
          ),
        ],
        acceptExpired: true,
        networkRestriction: NetworkRestriction.NONE,
      );

      await tileStore
          ?.loadTileRegion(tileRegionId, tileOptions, (progress) {
            final percentage =
                progress.completedResourceCount /
                progress.requiredResourceCount;
            debugPrint(
              '🗺 OFFLINE - Tile region progress: ${(percentage * 100).toStringAsFixed(1)}%',
            );
            if (!tileRegionLoadProgress.isClosed) {
              tileRegionLoadProgress.sink.add(percentage);
            }
          })
          .then((_) {
            debugPrint('🗺 OFFLINE - Tile region download completed');
            if (!tileRegionLoadProgress.isClosed) {
              tileRegionLoadProgress.sink.add(1.0);
              tileRegionLoadProgress.close();
            }
          });
    } catch (e) {
      debugPrint('❌ OFFLINE - Error downloading tile region: $e');
      if (!tileRegionLoadProgress.isClosed) {
        tileRegionLoadProgress.sink.addError(e);
        tileRegionLoadProgress.close();
      }
    }
  }

  Future<void> removeOfflineResources() async {
    try {
      debugPrint('🗺 OFFLINE - Removing offline resources');
      await tileStore?.removeRegion(tileRegionId);
      tileStore?.setDiskQuota(0); // setDiskQuota returns void, no await needed
      await offlineManager?.removeStylePack(MapboxStyles.MAPBOX_STREETS);
      debugPrint('🗺 OFFLINE - Offline resources removed successfully');
    } catch (e) {
      debugPrint('❌ OFFLINE - Error removing offline resources: $e');
    }
  }

  // Comprehensive method to set up offline functionality
  Future<void> setupOfflineMap() async {
    try {
      debugPrint('🗺 OFFLINE - Setting up complete offline functionality');

      // Step 1: Initialize offline components
      await initOfflineMap();

      // Step 2: Download style pack
      await downloadStylePack();

      // Step 3: Download tile region based on user location
      await downloadTileRegion();

      debugPrint('🗺 OFFLINE - Complete offline setup finished successfully');
    } catch (e) {
      debugPrint('❌ OFFLINE - Error in complete offline setup: $e');
    }
  }

  // Download tiles for a specific region manually
  Future<void> downloadTilesForRegion(String regionName) async {
    try {
      debugPrint(
        '🗺 OFFLINE - Downloading tiles for specific region: $regionName',
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
            minZoom: 8,
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
        return false;
      }

      // For now, we'll assume offline data is available if the components are initialized
      // You can enhance this by checking specific resources if the API provides methods
      debugPrint('🗺 OFFLINE - Offline components are initialized and ready');
      return true;
    } catch (e) {
      debugPrint('❌ OFFLINE - Error checking offline data availability: $e');
      return false;
    }
  }

  void onTextChanged(String hint, String value) {
    if (value.contains('@')) {
      // open mention bottom sheet
      debugPrint("Mention trigger from [$hint]: $value");
    } else if (value.contains('#')) {
      // open tag bottom sheet
      debugPrint("Tag trigger from [$hint]: $value");
    }
    filterValues[hint] = value;
  }

  void setLocation(String location) {
    selectedLocation.value = location;
    debugPrint("Location set to: $location");
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
    super.onInit();
    debugPrint('[MapController][onInit] Starting initialization');
    debugPrint(
      '[MapController][onInit] currentZoom.value: ${currentZoom.value}',
    );
    debugPrint(
      '[MapController][onInit] isShowingNewLocations.value: ${isShowingNewLocations.value}',
    );
    debugPrint('[MapController][onInit] locations count: ${locations.length}');
    debugPrint(
      '[MapController][onInit] hasInitialized: ${hasInitialized.value}',
    );
    debugPrint('[MapController][onInit] isMapReady: ${isMapReady.value}');
    debugPrint(
      '[MapController][onInit] mapController null: ${mapController == null}',
    );
    debugPrint(
      '[MapController][onInit] currentAnnotationManager null: ${currentAnnotationManager == null}',
    );

    WidgetsBinding.instance.addObserver(this);
    debugPrint('[MapController][onInit] WidgetsBindingObserver added');

    // Initialize offline functionality in background
    debugPrint(
      '[MapController][onInit] Starting offline initialization in background',
    );
    setupApp();

    debugPrint('[MapController][onInit] Initialization complete');
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
    try {
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Starting memory loading from database',
      );
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] isLoadingMemories before: ${isLoadingMemories.value}',
      );
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] allMemories count before: ${allMemories.length}',
      );

      isLoadingMemories.value = true;
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Set isLoadingMemories to true',
      );

      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Calling _databaseHelper.getAllMemoriesWithDetails()',
      );
      final memories = await _databaseHelper.getAllMemoriesWithDetails();
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Database query completed, got ${memories.length} memories',
      );

      allMemories.assignAll(memories);
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Assigned memories to allMemories, count: ${allMemories.length}',
      );

      if (memories.isEmpty) {
        debugPrint(
          '[MapController][loadMemoriesFromDatabase] No memories found in database, returning early',
        );
        return;
      }

      // Debug memory location data
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Debugging memory locations...',
      );
      MemoryClusteringService.debugMemoryLocations(memories);

      // Initialize clustering with loaded memories
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Starting clustering initialization...',
      );
      await _initializeMemoryClustering();
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Clustering initialization completed',
      );
    } catch (e) {
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Error loading memories from database: $e',
      );
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Error type: ${e.runtimeType}',
      );
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Stack trace: ${StackTrace.current}',
      );
    } finally {
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] Setting isLoadingMemories to false',
      );
      isLoadingMemories.value = false;
      debugPrint(
        '[MapController][loadMemoriesFromDatabase] loadMemoriesFromDatabase completed',
      );
    }
  }

  Future<void> _initializeMemoryClustering() async {
    try {
      debugPrint(
        '🔄 MEMORY CLUSTERING - Starting clustering initialization...',
      );

      // Convert memories to MemoryLocation objects, filtering out those without valid locations
      final memoriesWithCoordinates =
          allMemories.where((memory) => _hasValidCoordinates(memory)).toList();

      debugPrint(
        '🔄 MEMORY CLUSTERING - Filtered memories: ${memoriesWithCoordinates.length} out of ${allMemories.length} have valid coordinates',
      );

      // Log some examples of filtered memories
      for (
        int i = 0;
        i <
            (memoriesWithCoordinates.length > 2
                ? 2
                : memoriesWithCoordinates.length);
        i++
      ) {
        final memory = memoriesWithCoordinates[i];
        debugPrint(
          '🔄 MEMORY CLUSTERING - Valid memory ${i + 1}: Location=${memory['location']}',
        );
      }

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
        '🔄 MEMORY CLUSTERING - Final memory locations for clustering: ${memoryLocations.length}',
      );

      // Log some examples of memory locations
      for (
        int i = 0;
        i < (memoryLocations.length > 2 ? 2 : memoryLocations.length);
        i++
      ) {
        final location = memoryLocations[i];
        debugPrint(
          '🔄 MEMORY CLUSTERING - Memory location ${i + 1}: ${location.latitude}, ${location.longitude}',
        );
      }

      if (memoryLocations.isEmpty) {
        debugPrint(
          '🔄 MEMORY CLUSTERING - No memories with valid coordinates found for clustering',
        );
        debugPrint(
          '🔄 MEMORY CLUSTERING - Falling back to dummy data for testing',
        );
        // await _showDummyMarkersForTesting();
        return;
      }

      // Use fixed 50km clustering radius as requested
      double clusterRadius =
          MemoryClusteringService.cityClusterRadiusKm; // 50km
      debugPrint(
        '🔄 MEMORY CLUSTERING - Using fixed cluster radius: ${clusterRadius}km for ${memoryLocations.length} memories',
      );

      // Initial clustering with adaptive radius
      debugPrint('🔄 MEMORY CLUSTERING - Starting clustering process...');
      final clusters = MemoryClusteringService.clusterMemories(
        memoryLocations,
        clusterRadius,
      );

      debugPrint(
        '🔄 MEMORY CLUSTERING - Clustering completed, got ${clusters.length} clusters',
      );

      // Log cluster details
      for (int i = 0; i < clusters.length; i++) {
        final cluster = clusters[i];
        debugPrint(
          '🔄 MEMORY CLUSTERING - Cluster ${i + 1}: ${cluster.memoryCount} memories at ${cluster.centerLatitude}, ${cluster.centerLongitude}',
        );
      }

      currentClusters.assignAll(clusters);

      // Generate chronological arrows with performance limits
      debugPrint('🔄 MEMORY CLUSTERING - Generating arrows...');
      final arrows = _generateOptimizedArrows(clusters);
      currentArrows.assignAll(arrows);

      currentClusterLevel.value = ClusterLevel.initial;

      debugPrint(
        '🔄 MEMORY CLUSTERING - Initialized ${clusters.length} clusters with ${arrows.length} arrows from ${memoryLocations.length} memories',
      );

      // Display clusters on map
      debugPrint('🔄 MEMORY CLUSTERING - Starting map display...');
      await _displayMemoryClusters();
      debugPrint('🔄 MEMORY CLUSTERING - Map display completed');
    } catch (e) {
      debugPrint('Error initializing memory clustering: $e');
    }
  }

  List<ChronologicalArrow> _generateOptimizedArrows(
    List<MemoryCluster> clusters,
  ) {
    // For performance, limit arrow generation for large datasets
    // if (clusters.length > 50) {
    //   // Only generate arrows for the most significant clusters (by memory count)
    //   final sortedClusters = List<MemoryCluster>.from(clusters);
    //   sortedClusters.sort((a, b) => b.memoryCount.compareTo(a.memoryCount));
    //   final topClusters = sortedClusters.take(30).toList();

    //   debugPrint('Performance optimization: Using top 30 clusters for arrow generation');
    //   // return MemoryClusteringService.generateChronologicalArrows(topClusters);
    // } else {
    return MemoryClusteringService.generateChronologicalArrows(clusters);
    // }
  }

  bool _hasValidCoordinates(Map<String, dynamic> memory) {
    final locationStr = memory['location'] as String? ?? '';

    // Skip if location is empty or null
    if (locationStr.isEmpty) {
      return false;
    }

    // Skip if location doesn't contain coordinates (comma-separated values)
    if (!locationStr.contains(',')) {
      return false;
    }

    final parts = locationStr.split(',');
    if (parts.length < 2) {
      return false;
    }

    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());

    // Skip if coordinates are invalid or zero
    if (lat == null || lng == null) {
      return false;
    }

    // Skip if coordinates are exactly 0,0 (likely default/invalid)
    if (lat == 0.0 && lng == 0.0) {
      return false;
    }

    // Skip if coordinates are outside valid ranges
    if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) {
      return false;
    }

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
          '🔄 DISPLAY CLUSTERS - Creating marker ${i + 1} for cluster at ${cluster.centerLatitude}, ${cluster.centerLongitude}',
        );

        try {
          // Create marker image based on cluster
          final imageBytes = await _createClusterMarkerImage(cluster, i);

          debugPrint(
            '🔄 DISPLAY CLUSTERS - Adding style image: $imageName (${imageBytes.length} bytes)',
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
            '🔄 DISPLAY CLUSTERS - Successfully added style image: $imageName',
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

          debugPrint('🔄 DISPLAY CLUSTERS - Added marker option ${i + 1}');
        } catch (e) {
          debugPrint('❌ DISPLAY CLUSTERS - Error creating marker ${i + 1}: $e');
          // Skip this marker and continue with the next one
          continue;
        }
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
        id: 'subcluster_${clusters.length}',
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
    try {
      isRefreshing.value = true;
      debugPrint('🔄 REFRESH MAP - Starting map view refresh...');

      // Reset to initial clustering state
      currentClusterLevel.value = ClusterLevel.initial;
      selectedCluster.value = null;

      // Clear existing annotations and arrows
      if (currentAnnotationManager != null) {
        await currentAnnotationManager!.deleteAll();
        currentAnnotationManager = null;
      }
      annotations.clear();
      currentClusters.clear();
      currentArrows.clear();

      // Clear all marker images and lines
      await _clearAllMarkerImages();
      await _clearAllLines();

      // Reload memories from database and reinitialize clustering
      await loadMemoriesFromDatabase();

      debugPrint('🔄 REFRESH MAP - Map view refresh completed');
    } catch (e) {
      debugPrint('❌ ERROR refreshing map view: $e');
      rethrow; // Re-throw to let the UI handle the error
    } finally {
      isRefreshing.value = false;
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
            colorText: Colors.white,        duration: const Duration(seconds: 2),

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

  Future<Uint8List> _createClusterMarkerImage(
    MemoryCluster cluster,
    int id,
  ) async {
    try {
      // Use fixed size to avoid issues with Mapbox
      const double size = 60.0;
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final radius = size / 2;

      debugPrint(
        '🔄 Creating marker image for cluster with ${cluster.memoryCount} memories',
      );
      debugPrint(
        '🔄 Cluster details: ID=${cluster.id}, isSingleMemory=${cluster.isSingleMemory}, memories.length=${cluster.memories.length}',
      );

      // Choose color based on cluster type and memory count
      Color markerColor;
      Color borderColor = Colors.white;
      double borderWidth = 3.0;

      if (cluster.isSingleMemory) {
        markerColor = getRandomMarkerColor(4);
        ; // Blue for single memories
      } else {
        // Group markers have distinct styling
        borderWidth = 4.0;
        borderColor = const Color(0xFFFFD700); // Gold border for groups

        if (cluster.memoryCount <= 5) {
          markerColor = const Color(0xFF4CAF50); // Green for small clusters
        } else if (cluster.memoryCount <= 15) {
          markerColor = const Color(0xFFFF9800); // Orange for medium clusters
        } else if (cluster.memoryCount <= 50) {
          markerColor = const Color(0xFFF44336); // Red for large clusters
        } else {
          markerColor = const Color(
            0xFF9C27B0,
          ); // Purple for very large clusters
        }
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
              (cluster.singleMemory != null)
                  ? (id + 1).toString()
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
        text: count.toString(),
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
      final lineColor = getRandomMarkerColor(4);
      final decimalValue = lineColor.value;

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
        await lineManager.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: points),
            lineColor: 0xFF000000,
            lineWidth: width + 2,
            lineOpacity: 0.20,
          ),
        );

        debugPrint(
          '🎨 Line color for arrow: ${lineColor.toString()} (decimal: $decimalValue)',
        );

        // Main line
        await lineManager.create(
          mapbox.PolylineAnnotationOptions(
            geometry: mapbox.LineString(coordinates: points),
            lineColor: decimalValue,
            lineWidth: 5,
            lineOpacity: 1,
          ),
        );

        await _addArrowHeadOnCurve(
          points,
          lineColor.value,
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
    int arrowColor,
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

      final imageBytes = await _createArrowImage(getRandomMarkerColor(4));
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
          zoom: zoom,
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
      debugPrint('🗺 MAP CREATED - Starting initialization');
      debugPrint('🗺 MAP CREATED - currentZoom.value: ${currentZoom.value}');
      debugPrint(
        '🗺 MAP CREATED - isShowingNewLocations.value: ${isShowingNewLocations.value}',
      );

      // Clean up any existing resources first
      if (currentAnnotationManager != null) {
        debugPrint('🗺 MAP CREATED - Cleaning up existing annotation manager');
        currentAnnotationManager = null;
      }
      annotations.clear();

      mapController = controller;
      hasInitialized.value = true;

      debugPrint('🗺 MAP CREATED - Setting isMapReady to true');
      isMapReady.value = true;

      // Wait a tiny bit for map to be ready, then smoothly set the camera
      await Future.delayed(const Duration(milliseconds: 50));

      debugPrint(
        '🗺 MAP CREATED - Setting camera smoothly to zoom: ${currentZoom.value}',
      );
      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates:
                locations.isNotEmpty ? locations[0] : mapbox.Position(0, 0),
          ),
          zoom: currentZoom.value,
          bearing: 0,
          pitch: 0,
        ),
        mapbox.MapAnimationOptions(
          duration: 800, // Smooth animation for initial setup
          startDelay: 0,
        ),
      );

      // Get initial camera state to see what Mapbox actually set
      final initialCamera = await mapController!.getCameraState();
      debugPrint(
        '🗺 MAP CREATED - Camera zoom after immediate flyTo: ${initialCamera.zoom}',
      );
      debugPrint(
        '🗺 MAP CREATED - Expected zoom from controller: ${currentZoom.value}',
      );

      // If the zoom is still not correct, try another flyTo as backup with longer animation
      if ((initialCamera.zoom - currentZoom.value).abs() > 0.1) {
        debugPrint(
          '🗺 MAP CREATED - First flyTo failed, trying second flyTo with longer animation',
        );
        await mapController!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(
              coordinates:
                  locations.isNotEmpty ? locations[0] : mapbox.Position(0, 0),
            ),
            zoom: currentZoom.value,
            bearing: 0,
            pitch: 0,
          ),
          mapbox.MapAnimationOptions(
            duration: 1000, // Longer animation for backup
            startDelay: 100,
          ),
        );

        final backupCamera = await mapController!.getCameraState();
        debugPrint(
          '🗺 MAP CREATED - Camera zoom after backup flyTo: ${backupCamera.zoom}',
        );
      }

      // Initialize map display reactively
      debugPrint(
        '🗺 MAP CREATED - Initializing display. isShowingNewLocations: ${isShowingNewLocations.value}',
      );

      // Wait for map to be fully loaded, then set camera multiple times to ensure it sticks
      debugPrint('🗺 MAP CREATED - Calling _ensureCorrectZoomWithRetries()');
      await _ensureCorrectZoomWithRetries();

      // Set up reactive initialization
      debugPrint('🗺 MAP CREATED - Calling _initializeMapReactively()');
      _initializeMapReactively();

      // Load memories from database and initialize clustering
      debugPrint('🗺 MAP CREATED - Loading memories for clustering');

      // Add a small delay to ensure map is fully ready
      await Future.delayed(Duration(milliseconds: 100));

      await loadMemoriesFromDatabase();

      // Check location permissions in background (don't block map display)
      _checkLocationPermissionInBackground();

      debugPrint('🗺 MAP CREATED - Initialization complete');
    } catch (e) {
      debugPrint('❌ ERROR in onMapCreated: $e');
      // Reset state on error to prevent future crashes
      isShowingNewLocations.value = false;
      // Clean up on error
      mapController = null;
      currentAnnotationManager = null;
      annotations.clear();
      hasInitialized.value = false;
      isMapReady.value = false;
    }
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
  Color getRandomMarkerColor(int? seed) {
    // final random = seed != null ? math.Random(seed) : math.Random();
    return markerColors[Random().nextInt(markerColors.length)];
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
      onMapLoadErrorListener: (mapLoadingErrorEventData) {},
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
    await _initializeOfflineInBackground();

    // Set up reactive workers for proper state management
    debugPrint('[MapController][onInit] Setting up reactive workers');
    await _setupReactiveWorkers();

    // Check permissions and schedule one-time recreation
    debugPrint(
      '[MapController][onInit] Checking permissions and scheduling recreation',
    );
    await _checkPermissionsAndScheduleOneTimeRecreation();

    // Schedule clustering check after a delay to handle race conditions
    debugPrint(
      '[MapController][onInit] Scheduling clustering check in 2 seconds',
    );
    Future.delayed(Duration(seconds: 2), () {
      debugPrint('[MapController][onInit] Delayed clustering check triggered');
      ensureClusteringInitialized();
    });
  }
}
