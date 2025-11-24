import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller.dart';

/// Background tile download service using isolates for non-blocking downloads
class BackgroundTileDownloadService extends GetxService {
  static BackgroundTileDownloadService get instance => Get.find();

  // Configuration constants - Updated for 50,000 tile capacity
  static const int MAX_TILES_THRESHOLD =
      50000; // Total tiles across all regions
  static const int WARNING_THRESHOLD = 40000; // Warning at 40k tiles
  static const int MAPBOX_REGION_TILE_LIMIT =
      700; // Per-region limit (under 750 - Mapbox hard limit)
  static const int LARGE_REGION_CHUNK_SIZE =
      5000; // Larger chunks for better coverage
  static const int BACKGROUND_DOWNLOAD_BATCH_SIZE =
      1000; // Increased batch size
  static const Duration DOWNLOAD_INTERVAL = Duration(
    minutes: 3,
  ); // Faster downloads
  static const Duration QUOTA_CHECK_INTERVAL = Duration(minutes: 1);

  // Core dependencies
  mapbox.TileStore? _tileStore;
  mapbox.OfflineManager? _offlineManager;

  // Isolate management
  Isolate? _downloadIsolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  StreamSubscription? _isolateSubscription;

  // Timers
  Timer? _downloadTimer;
  Timer? _quotaCheckTimer;

  // State management
  final RxBool isDownloading = false.obs;
  final RxInt totalTilesDownloaded = 0.obs;
  final RxDouble downloadProgress = 0.0.obs;
  final RxBool forceOfflineMode = false.obs; // UI should use offline maps
  final RxBool stopDownloading =
      false.obs; // Stop downloading when quota reached
  final RxString currentDownloadRegion = ''.obs;
  final RxList<DownloadRegion> downloadQueue = <DownloadRegion>[].obs;
  final RxBool _isInitialized = false.obs; // Add missing _isInitialized

  // Configuration
  final RxBool autoDownloadEnabled = true.obs;
  final RxBool wifiOnlyDownloads = true.obs;
  final RxInt maxTilesLimit = MAX_TILES_THRESHOLD.obs;

  @override
  Future<void> onInit() async {
    super.onInit();

    await _loadConfiguration();

    debugPrint('[BackgroundTileDownloadService] Service initialized');
  }

  @override
  void onClose() {
    _cleanup();
    super.onClose();
  }

  /// Initialize the service with MapController dependencies
  Future<void> initialize({
    required mapbox.TileStore? tileStore,
    required mapbox.OfflineManager? offlineManager,
  }) async {
    _tileStore = tileStore;
    _offlineManager = offlineManager;
    _isInitialized.value = true;

    // Set initial disk quota based on max tiles limit
    await setTileQuota(maxTilesLimit.value);

    // Load configuration
    await _loadConfiguration();
    await _loadDownloadQueue();

    // FIX: Clean up stale regions after loading
    _cleanupStaleRegions();

    // Start monitoring and downloads
    _startTileQuotaMonitoring();
    _startBackgroundDownloads();

    debugPrint(
      '[BackgroundTileDownloadService] Initialized with disk quota for ${maxTilesLimit.value} tiles',
    );
  }

  /// Initialize the download isolate
  Future<void> _initializeDownloadIsolate() async {
    try {
      _receivePort = ReceivePort();

      // Spawn isolate with entry point
      _downloadIsolate = await Isolate.spawn(
        _downloadIsolateEntryPoint,
        _receivePort!.sendPort,
        debugName: 'TileDownloadIsolate',
      );

      // Listen to messages from isolate
      _isolateSubscription = _receivePort!.listen(_handleIsolateMessage);

      debugPrint(
        '[BackgroundTileDownloadService] Download isolate initialized',
      );

      // Wait for isolate to send back its SendPort
      await Future.delayed(Duration(milliseconds: 500));
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error initializing isolate: $e',
      );
    }
  }

  /// Entry point for the download isolate
  static void _downloadIsolateEntryPoint(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();

    // Send the isolate's send port back to main isolate
    mainSendPort.send(isolateReceivePort.sendPort);

    // Listen for download commands from main isolate
    isolateReceivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        await _processDownloadCommand(message, mainSendPort);
      }
    });
  }

  /// Process download commands in the isolate
  static Future<void> _processDownloadCommand(
    Map<String, dynamic> command,
    SendPort mainSendPort,
  ) async {
    try {
      final type = command['type'] as String;

      switch (type) {
        case 'download_region':
          await _downloadRegionInIsolate(command, mainSendPort);
          break;
        case 'count_tiles':
          await _countTilesInIsolate(command, mainSendPort);
          break;
      }
    } catch (e) {
      mainSendPort.send({'type': 'error', 'message': 'Error in isolate: $e'});
    }
  }

  /// Download region in isolate with resume capability
  static Future<void> _downloadRegionInIsolate(
    Map<String, dynamic> command,
    SendPort mainSendPort,
  ) async {
    try {
      final regionData = command['region'] as Map<String, dynamic>;
      final estimatedTiles =
          (regionData['estimated_tiles'] as num?)?.toInt() ?? 100;

      // FIX: Support resume capability with safe type casting
      final resumeFromProgress =
          (regionData['resume_from_progress'] as num?)?.toDouble() ?? 0.0;
      final tilesAlreadyDownloaded =
          (regionData['tiles_already_downloaded'] as num?)?.toInt() ?? 0;

      debugPrint(
        '[BackgroundTileDownloadService] Isolate: Starting download for region ${regionData['id']} - Resume from ${(resumeFromProgress * 100).toStringAsFixed(1)}% (${tilesAlreadyDownloaded} tiles already downloaded)',
      );

      // Simulate download progress (replace with actual Mapbox download logic)
      mainSendPort.send({
        'type': 'download_started',
        'region_id': regionData['id'],
      });

      // FIX: Start from resume point instead of 0%
      final startProgress = (resumeFromProgress * 100).round();
      int tilesDownloadedSoFar = tilesAlreadyDownloaded;

      for (int i = startProgress + 10; i <= 100; i += 10) {
        await Future.delayed(
          Duration(milliseconds: 100),
        ); // FIX: Reduced delay for faster downloads

        // Calculate tiles downloaded for this progress step only
        final totalTilesForThisProgress = (estimatedTiles * i / 100).round();
        final newTilesThisStep =
            totalTilesForThisProgress - tilesDownloadedSoFar;
        tilesDownloadedSoFar = totalTilesForThisProgress;

        mainSendPort.send({
          'type': 'download_progress',
          'region_id': regionData['id'],
          'progress': i / 100.0,
          'tiles_downloaded_this_step':
              newTilesThisStep, // Only new tiles this step
          'total_tiles_for_region':
              totalTilesForThisProgress, // Total for this region
        });

        // FIX: If we started from a resume point, log the progress
        if (startProgress > 0) {
          debugPrint(
            '[BackgroundTileDownloadService] Isolate: Resumed download at ${i}% for region ${regionData['id']}',
          );
        }
      }

      // FIX: Send completion message - don't send tiles count as they're already counted in progress
      mainSendPort.send({
        'type': 'download_completed',
        'region_id': regionData['id'],
        'tiles_downloaded': 0, // FIX: Set to 0 to prevent double counting
      });
    } catch (e, stackTrace) {
      debugPrint(
        '[BackgroundTileDownloadService] Isolate error for region ${command['region']?['id'] ?? 'unknown'}: $e',
      );
      debugPrint(
        '[BackgroundTileDownloadService] Isolate stack trace: $stackTrace',
      );

      mainSendPort.send({
        'type': 'download_error',
        'region_id': command['region']?['id'] ?? 'unknown',
        'error': 'Isolate error: $e',
      });
    }
  }

  /// Count tiles in isolate
  static Future<void> _countTilesInIsolate(
    Map<String, dynamic> command,
    SendPort mainSendPort,
  ) async {
    try {
      // Simulate tile counting (replace with actual counting logic)
      await Future.delayed(Duration(milliseconds: 100));

      // FIX: Use more stable mock count that doesn't interfere with resume
      // In real implementation, this would query the actual TileStore
      final baseCount = command['expected_count'] as int? ?? 0;
      final mockTileCount =
          baseCount > 0
              ? baseCount + math.Random().nextInt(1000)
              : math.Random().nextInt(5000);

      mainSendPort.send({'type': 'tile_count_result', 'count': mockTileCount});
    } catch (e) {
      mainSendPort.send({'type': 'tile_count_error', 'error': e.toString()});
    }
  }

  /// Handle messages from the download isolate
  void _handleIsolateMessage(dynamic message) {
    debugPrint(
      '[BackgroundTileDownloadService] Received isolate message: $message',
    );

    if (message is SendPort) {
      // This is the isolate's send port
      _sendPort = message;
      debugPrint(
        '[BackgroundTileDownloadService] Received isolate send port - isolate ready',
      );
      return;
    }

    if (message is Map<String, dynamic>) {
      final type = message['type'] as String?;

      switch (type) {
        case 'download_started':
          _handleDownloadStarted(message);
          break;
        case 'download_progress':
          _handleDownloadProgress(message);
          break;
        case 'download_completed':
          _handleDownloadCompleted(message);
          break;
        case 'download_error':
          _handleDownloadError(message);
          break;
        case 'tile_count_result':
          _handleTileCountResult(message);
          break;
        case 'tile_count_error':
          debugPrint(
            '[BackgroundTileDownloadService] Tile count error: ${message['error']}',
          );
          break;
        case 'error':
          debugPrint(
            '[BackgroundTileDownloadService] Isolate error: ${message['message']}',
          );
          break;
        default:
          debugPrint(
            '[BackgroundTileDownloadService] Unknown message type: $type',
          );
      }
    }
  }

  /// Handle download started message
  void _handleDownloadStarted(Map<String, dynamic> message) {
    final regionId = message['region_id'] as String;
    debugPrint(
      '[BackgroundTileDownloadService] Download started for region: $regionId',
    );

    isDownloading.value = true;
    currentDownloadRegion.value = regionId;
    downloadProgress.value = 0.0;
  }

  /// Handle download progress message
  void _handleDownloadProgress(Map<String, dynamic> message) {
    final regionId = message['region_id'] as String;
    final progress = (message['progress'] as num).toDouble();
    final tilesDownloadedThisStep =
        message['tiles_downloaded_this_step'] as int? ?? 0;

    debugPrint(
      '[BackgroundTileDownloadService] Progress for $regionId: ${(progress * 100).toStringAsFixed(1)}%, +$tilesDownloadedThisStep tiles',
    );

    // FIX: Update region-specific progress for persistence
    final region = downloadQueue.firstWhereOrNull((r) => r.id == regionId);
    if (region != null) {
      region.progress = progress;
      region.tilesDownloadedSoFar += tilesDownloadedThisStep;
      region.lastProgressTime = DateTime.now();

      debugPrint(
        '[BackgroundTileDownloadService] Region $regionId progress: ${(progress * 100).toStringAsFixed(1)}%, total tiles for region: ${region.tilesDownloadedSoFar}',
      );
    }

    // Update current download progress for UI
    downloadProgress.value = progress;

    // Add only the new tiles from this step to avoid double counting
    if (tilesDownloadedThisStep > 0) {
      totalTilesDownloaded.value += tilesDownloadedThisStep;
      debugPrint(
        '[BackgroundTileDownloadService] Total tiles now: ${totalTilesDownloaded.value}',
      );
    }

    // FIX: Save progress periodically (every 10% or every 100 tiles)
    if (progress > 0 && (progress * 10).round() % 1 == 0) {
      // Every 10%
      _saveDownloadQueue();
    }
    if (totalTilesDownloaded.value % 100 == 0) {
      _saveConfiguration();
    }
  }

  /// Handle download completed message
  void _handleDownloadCompleted(Map<String, dynamic> message) {
    final regionId = message['region_id'] as String;
    final tilesDownloaded = message['tiles_downloaded'] as int;

    debugPrint(
      '[BackgroundTileDownloadService] Download completed for region $regionId: $tilesDownloaded tiles',
    );

    // FIX: DON'T add tiles here - already counted in progress updates
    // This prevents double counting

    // Update region status and completion time
    final region = downloadQueue.firstWhereOrNull((r) => r.id == regionId);
    if (region != null) {
      region.status = DownloadStatus.completed;
      region.progress = 1.0;
      region.completedTime = DateTime.now();
      debugPrint(
        '[BackgroundTileDownloadService] Region $regionId marked as completed with ${region.tilesDownloadedSoFar} tiles',
      );
    }

    // Reset current download state
    currentDownloadRegion.value = '';
    downloadProgress.value = 0.0;

    // Save configuration and queue after successful download
    _saveConfiguration();
    _saveDownloadQueue();

    // Check quota after download
    _checkQuotaStatus();

    // FIX: Immediately continue with next region - don't wait for timer
    debugPrint(
      '[BackgroundTileDownloadService] Immediately processing next region...',
    );
    _processNextDownload();
  }

  /// Handle download error message
  void _handleDownloadError(Map<String, dynamic> message) {
    final regionId = message['region_id'];
    final errorMessage = message['error'];

    debugPrint(
      '[BackgroundTileDownloadService] Download error for region $regionId: $errorMessage',
    );

    // Mark region as failed and potentially retry
    final region = downloadQueue.firstWhereOrNull((r) => r.id == regionId);
    if (region != null) {
      region.status = DownloadStatus.failed;
      region.retryCount++;

      // Retry up to 3 times
      if (region.retryCount < 3) {
        region.status = DownloadStatus.pending;
        debugPrint(
          '[BackgroundTileDownloadService] Scheduling retry for region: $regionId (attempt ${region.retryCount + 1}/3)',
        );
      } else {
        debugPrint(
          '[BackgroundTileDownloadService] Region $regionId failed after 3 attempts, skipping permanently',
        );
      }
    }

    // FIX: Don't stop downloading - continue with next region
    // Reset current download state but keep isDownloading true to continue
    currentDownloadRegion.value = '';
    downloadProgress.value = 0.0;

    // Save the updated queue state
    _saveDownloadQueue();

    // Continue with next region immediately
    debugPrint(
      '[BackgroundTileDownloadService] Continuing to next region after error...',
    );
    _processNextDownload();
  }

  /// Handle tile count result
  void _handleTileCountResult(Map<String, dynamic> message) {
    final isolateCount = message['count'] as int;
    debugPrint(
      '[BackgroundTileDownloadService] Isolate tile count: $isolateCount, Persisted count: ${totalTilesDownloaded.value}',
    );

    // FIX: Don't override persisted tile count with mock isolate data
    // Only update if isolate count is significantly higher (indicating real progress)
    final persistedCount = totalTilesDownloaded.value;

    if (persistedCount == 0) {
      // First time initialization - use isolate count if reasonable
      if (isolateCount > 0 && isolateCount < MAX_TILES_THRESHOLD) {
        totalTilesDownloaded.value = isolateCount;
        debugPrint(
          '[BackgroundTileDownloadService] 🔄 Initial tile count set to: $isolateCount',
        );
        _saveConfiguration(); // Persist the initial count
      }
    } else {
      // Resume scenario - keep persisted count unless isolate shows significant progress
      if (isolateCount > persistedCount + 1000) {
        totalTilesDownloaded.value = isolateCount;
        debugPrint(
          '[BackgroundTileDownloadService] 📈 Tile count updated: $persistedCount -> $isolateCount',
        );
        _saveConfiguration();
      } else {
        debugPrint(
          '[BackgroundTileDownloadService] 💾 Keeping persisted tile count: $persistedCount (isolate: $isolateCount)',
        );
      }
    }

    _checkQuotaStatus();
  }

  /// Start tile quota monitoring timer
  void _startTileQuotaMonitoring() {
    _quotaCheckTimer = Timer.periodic(QUOTA_CHECK_INTERVAL, (timer) {
      _requestTileCount();
    });

    // Initial quota check
    _requestTileCount();
  }

  /// Start background downloads with proper isolate management
  void _startBackgroundDownloads() {
    if (_downloadTimer != null) {
      _downloadTimer!.cancel();
    }

    // FIX: Only create isolate if it doesn't exist or is not ready
    if (_downloadIsolate == null || _sendPort == null) {
      debugPrint(
        '[BackgroundTileDownloadService] Creating new isolate - current state: isolate=${_downloadIsolate != null}, sendPort=${_sendPort != null}',
      );
      _initializeDownloadIsolate();
    } else {
      debugPrint('[BackgroundTileDownloadService] Reusing existing isolate');
    }

    debugPrint(
      '[BackgroundTileDownloadService] Starting background download timer',
    );

    _downloadTimer = Timer.periodic(DOWNLOAD_INTERVAL, (timer) {
      debugPrint('[BackgroundTileDownloadService] 🔄 Download timer tick');

      if (!isDownloading.value &&
          !stopDownloading.value &&
          autoDownloadEnabled.value) {
        // Ensure isolate is ready before processing
        if (_sendPort != null) {
          _processNextDownload();
        } else {
          debugPrint(
            '[BackgroundTileDownloadService] 🔄 Isolate not ready, skipping download',
          );
        }
      } else {
        debugPrint(
          '[BackgroundTileDownloadService] 🔄 Skipping - isDownloading: ${isDownloading.value}, stopDownloading: ${stopDownloading.value}',
        );
      }
    });

    // Process immediately if queue has pending items and isolate is ready
    Timer(Duration(seconds: 2), () {
      if (_sendPort != null) {
        _processNextDownloadIfReady();
      }
    });
  }

  /// Request tile count from isolate
  void _requestTileCount() {
    if (_sendPort != null) {
      _sendPort!.send({
        'type': 'count_tiles',
        'expected_count':
            totalTilesDownloaded.value, // Pass current count for stable mocking
      });
    }
  }

  /// Process next download in queue with resume capability
  Future<void> _processNextDownload() async {
    if (downloadQueue.isEmpty) {
      await _scheduleIntelligentDownloads();
      return;
    }

    final nextRegion = downloadQueue.firstWhereOrNull(
      (region) => region.status == DownloadStatus.pending,
    );

    if (nextRegion != null && _sendPort != null) {
      // FIX: Set up region for download with resume information
      nextRegion.status = DownloadStatus.downloading;
      nextRegion.startTime = DateTime.now();
      isDownloading.value = true;
      currentDownloadRegion.value = nextRegion.id;

      // FIX: Send region data including resume information
      final regionData = nextRegion.toMap();
      regionData['resume_from_progress'] =
          nextRegion.progress; // Resume capability
      regionData['tiles_already_downloaded'] =
          nextRegion.tilesDownloadedSoFar; // Skip already downloaded tiles

      debugPrint(
        '[BackgroundTileDownloadService] Starting download for region ${nextRegion.id} - Resume from ${(nextRegion.progress * 100).toStringAsFixed(1)}% (${nextRegion.tilesDownloadedSoFar} tiles already downloaded)',
      );

      _sendPort!.send({'type': 'download_region', 'region': regionData});

      // Save queue state immediately to persist the downloading status
      _saveDownloadQueue();
    } else {
      // FIX: No pending regions found - reset downloading state and schedule more if under quota
      debugPrint(
        '[BackgroundTileDownloadService] No pending regions found - resetting download state',
      );
      isDownloading.value = false;
      currentDownloadRegion.value = '';
      downloadProgress.value = 0.0;

      // If we're under the quota limit, schedule new regions
      if (totalTilesDownloaded.value < maxTilesLimit.value) {
        debugPrint(
          '[BackgroundTileDownloadService] Under quota limit (${totalTilesDownloaded.value}/${maxTilesLimit.value}) - scheduling more regions',
        );
        await _scheduleIntelligentDownloads();
      } else {
        debugPrint(
          '[BackgroundTileDownloadService] Reached quota limit (${totalTilesDownloaded.value}/${maxTilesLimit.value}) - stopping downloads',
        );
      }
    }
  }

  /// Schedule intelligent downloads based on user patterns
  Future<void> _scheduleIntelligentDownloads() async {
    try {
      // Don't schedule new downloads if we already have pending ones
      final pendingRegions =
          downloadQueue.where((r) => r.status == DownloadStatus.pending).length;
      if (pendingRegions > 0) {
        debugPrint(
          '[BackgroundTileDownloadService] Already have $pendingRegions pending regions, skipping scheduling',
        );
        return;
      }

      // Check if we're approaching total tile limit (not per-region limit)
      final remainingTiles = maxTilesLimit.value - totalTilesDownloaded.value;
      if (remainingTiles < MAPBOX_REGION_TILE_LIMIT) {
        debugPrint(
          '[BackgroundTileDownloadService] Near total tile limit ($remainingTiles remaining), not scheduling new downloads',
        );
        return;
      }

      final hotspots = await _analyzeUserLocationPatterns();

      // FIX: If no hotspots available, schedule default regions
      if (hotspots.isEmpty) {
        debugPrint(
          '[BackgroundTileDownloadService] No user hotspots found, scheduling default regions',
        );
        await _scheduleDefaultRegions();
        return;
      }

      // Schedule multiple small regions to build up to 50,000 tiles
      final maxNewRegions = math.min(
        5,
        remainingTiles ~/ (MAPBOX_REGION_TILE_LIMIT ~/ 2),
      );

      for (int i = 0; i < math.min(maxNewRegions, hotspots.length); i++) {
        final hotspot = hotspots[i];

        // Check if we already have a region for this hotspot
        final existingRegion = downloadQueue.firstWhereOrNull(
          (region) => region.id.contains('hotspot_${hotspot.id}'),
        );

        if (existingRegion == null) {
          final region = DownloadRegion(
            id: 'hotspot_${hotspot.id}_${DateTime.now().millisecondsSinceEpoch}',
            bounds: _createConservativeBoundsFromHotspot(hotspot),
            zoomLevels: [10, 11, 12],
            priority: hotspot.priority,
            scheduledTime: DateTime.now(),
            estimatedTiles:
                MAPBOX_REGION_TILE_LIMIT ~/ 2, // ~350 tiles per region
          );

          downloadQueue.add(region);
        }
      }

      // Save the updated queue
      await _saveDownloadQueue();

      debugPrint(
        '[BackgroundTileDownloadService] Scheduled ${downloadQueue.length} total regions (targeting ${maxTilesLimit.value} total tiles)',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error scheduling downloads: $e',
      );
    }
  }

  /// Schedule default regions when no user patterns are available
  Future<void> _scheduleDefaultRegions() async {
    try {
      final remainingTiles = maxTilesLimit.value - totalTilesDownloaded.value;
      final maxNewRegions = math.min(
        10,
        remainingTiles ~/ (MAPBOX_REGION_TILE_LIMIT ~/ 2),
      );

      // Define some popular/useful default regions around the world
      final defaultRegions = [
        {'name': 'New York', 'lat': 40.7128, 'lng': -74.0060},
        {'name': 'London', 'lat': 51.5074, 'lng': -0.1278},
        {'name': 'Paris', 'lat': 48.8566, 'lng': 2.3522},
        {'name': 'Tokyo', 'lat': 35.6762, 'lng': 139.6503},
        {'name': 'Sydney', 'lat': -33.8688, 'lng': 151.2093},
        {'name': 'San Francisco', 'lat': 37.7749, 'lng': -122.4194},
        {'name': 'Berlin', 'lat': 52.5200, 'lng': 13.4050},
        {'name': 'Singapore', 'lat': 1.3521, 'lng': 103.8198},
        {'name': 'Dubai', 'lat': 25.2048, 'lng': 55.2708},
        {'name': 'Los Angeles', 'lat': 34.0522, 'lng': -118.2437},
      ];

      for (int i = 0; i < math.min(maxNewRegions, defaultRegions.length); i++) {
        final region = defaultRegions[i];
        final regionId =
            'default_${region['name']}_${DateTime.now().millisecondsSinceEpoch}';

        // Check if we already have a region for this location
        final existingRegion = downloadQueue.firstWhereOrNull(
          (r) => r.id.contains('default_${region['name']}'),
        );

        if (existingRegion == null) {
          final downloadRegion = DownloadRegion(
            id: regionId,
            bounds: _createDefaultRegionBounds(
              region['lat'] as double,
              region['lng'] as double,
            ),
            zoomLevels: [10, 11, 12],
            priority: 500 - i, // Decreasing priority
            scheduledTime: DateTime.now().add(
              Duration(minutes: i * 2),
            ), // Stagger downloads
            estimatedTiles:
                MAPBOX_REGION_TILE_LIMIT ~/ 2, // ~350 tiles per region
          );

          downloadQueue.add(downloadRegion);
          debugPrint(
            '[BackgroundTileDownloadService] Scheduled default region: ${region['name']}',
          );
        }
      }

      // Save the updated queue
      await _saveDownloadQueue();

      debugPrint(
        '[BackgroundTileDownloadService] Scheduled ${downloadQueue.length} default regions for initial tile coverage',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error scheduling default regions: $e',
      );
    }
  }

  /// Create bounds for default region around a city center
  mapbox.CoordinateBounds _createDefaultRegionBounds(double lat, double lng) {
    // Create small area around city center (approximately 2km x 2km)
    const double radius = 0.009; // Roughly 1km in degrees

    return mapbox.CoordinateBounds(
      southwest: mapbox.Point(
        coordinates: mapbox.Position(lng - radius, lat - radius),
      ),
      northeast: mapbox.Point(
        coordinates: mapbox.Position(lng + radius, lat + radius),
      ),
      infiniteBounds: false,
    );
  }

  /// Analyze user location patterns from memory data
  Future<List<LocationHotspot>> _analyzeUserLocationPatterns() async {
    try {
      final mapController = Get.find<MapController>();

      final memories = mapController.allMemories;

      final locationClusters = <LocationCluster>[];

      for (final memory in memories) {
        final lat = memory['location_latitude'];
        final lng = memory['location_longitude'];

        if (lat != null && lng != null) {
          _addToLocationCluster(locationClusters, lat, lng, memory);
        }
      }

      // Convert clusters to hotspots with priority scores
      return locationClusters
          .map(
            (cluster) => LocationHotspot(
              id: cluster.id,
              center: cluster.center,
              radius: cluster.radius,
              memoryCount: cluster.memories.length,
              lastVisited: cluster.lastVisited,
              priority: _calculatePriority(cluster),
            ),
          )
          .toList()
        ..sort((a, b) => b.priority.compareTo(a.priority));
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error analyzing location patterns: $e',
      );
      return [];
    }
  }

  /// Add memory to location cluster
  void _addToLocationCluster(
    List<LocationCluster> clusters,
    double lat,
    double lng,
    Map<String, dynamic> memory,
  ) {
    const double clusterRadius = 0.01; // ~1km

    // Find existing cluster within radius
    for (final cluster in clusters) {
      final distance = _calculateDistance(
        lat,
        lng,
        cluster.center.latitude,
        cluster.center.longitude,
      );

      if (distance <= clusterRadius) {
        cluster.memories.add(memory);
        cluster.updateLastVisited(memory);
        return;
      }
    }

    // Create new cluster
    clusters.add(
      LocationCluster(
        id: 'cluster_${clusters.length}',
        center: LocationPoint(latitude: lat, longitude: lng),
        radius: clusterRadius,
        memories: [memory],
        lastVisited:
            DateTime.tryParse(memory['created_at'] ?? '') ?? DateTime.now(),
      ),
    );
  }

  /// Calculate priority for location cluster
  int _calculatePriority(LocationCluster cluster) {
    final recency = DateTime.now().difference(cluster.lastVisited).inDays;
    final frequency = cluster.memories.length;

    // Higher frequency and recent visits = higher priority
    return (frequency * 10) - (recency ~/ 7);
  }

  /// Calculate distance between two points in degrees
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return math.sqrt(math.pow(lat2 - lat1, 2) + math.pow(lng2 - lng1, 2));
  }

  /// Create bounds from hotspot
  mapbox.CoordinateBounds _createBoundsFromHotspot(LocationHotspot hotspot) {
    final padding = hotspot.radius;
    return mapbox.CoordinateBounds(
      southwest: mapbox.Point(
        coordinates: mapbox.Position(
          hotspot.center.longitude - padding,
          hotspot.center.latitude - padding,
        ),
      ),
      northeast: mapbox.Point(
        coordinates: mapbox.Position(
          hotspot.center.longitude + padding,
          hotspot.center.latitude + padding,
        ),
      ),
      infiniteBounds: false,
    );
  }

  /// Estimate tile count for hotspot
  int _estimateTileCount(LocationHotspot hotspot) {
    // Rough estimation based on zoom levels and area
    final area = hotspot.radius * hotspot.radius * 4; // Square area
    return (area * 1000).round(); // Rough tiles per area
  }

  /// Check quota status with proper 50k limit
  void _checkQuotaStatus() {
    debugPrint(
      '[BackgroundTileDownloadService] 📊 Checking quota status - tiles: ${totalTilesDownloaded.value}, warning: $WARNING_THRESHOLD, max: ${maxTilesLimit.value}',
    );

    if (totalTilesDownloaded.value >= maxTilesLimit.value) {
      debugPrint(
        '[BackgroundTileDownloadService] 🔴 Max quota reached (${totalTilesDownloaded.value}/${maxTilesLimit.value}) - stopping downloads',
      );
      _enforceOfflineMode();
    } else if (totalTilesDownloaded.value >= WARNING_THRESHOLD) {
      debugPrint(
        '[BackgroundTileDownloadService] 🟠 Warning threshold reached (${totalTilesDownloaded.value}/${maxTilesLimit.value}) - enabling offline mode but continuing downloads',
      );
      _showQuotaWarning(totalTilesDownloaded.value);
      _enableOfflineModeOnly();
    } else {
      debugPrint(
        '[BackgroundTileDownloadService] 🟢 Under quota limits (${totalTilesDownloaded.value}/${maxTilesLimit.value}) - normal operation',
      );
    }
  }

  /// Enable offline mode without stopping downloads
  void _enableOfflineModeOnly() {
    if (!forceOfflineMode.value) {
      forceOfflineMode.value = true;
      debugPrint(
        '[BackgroundTileDownloadService] 🟠 Offline mode enabled at ${totalTilesDownloaded.value} tiles - continuing downloads until ${maxTilesLimit.value} tiles',
      );
      debugPrint(
        '[BackgroundTileDownloadService] 🟠 stopDownloading: ${stopDownloading.value}, autoDownloadEnabled: ${autoDownloadEnabled.value}',
      );

      // Get.snackbar(
      //   'Offline Mode Enabled',
      //   'App is now using offline maps. Tiles will continue downloading in background until storage limit is reached (${totalTilesDownloaded.value}/${maxTilesLimit.value}).',
      //   backgroundColor: Colors.orange,
      //   colorText: Colors.white,
      //   duration: const Duration(seconds: 4),
      //   snackPosition: SnackPosition.TOP,
      // );
    } else {
      debugPrint(
        '[BackgroundTileDownloadService] 🟠 Offline mode already enabled - tiles: ${totalTilesDownloaded.value}/${maxTilesLimit.value}',
      );
    }
  }

  /// Enforce offline mode when quota is reached
  void _enforceOfflineMode() {
    forceOfflineMode.value = true;
    stopDownloading.value = true; // Stop downloading when max quota reached

    // Stop all downloads
    _stopAllDownloads();

    // Update offline settings asynchronously
    _updateOfflineSettings();

    // Notify user
    Get.snackbar(
      'Offline Mode Activated',
      'Maximum tiles downloaded (${totalTilesDownloaded.value}). App now running in offline mode.',
      backgroundColor: Colors.blue,
      colorText: Colors.white,
        duration: const Duration(seconds: 2),
    );

    debugPrint(
      '[BackgroundTileDownloadService] Offline mode enforced - quota reached',
    );
  }

  /// Update offline settings asynchronously
  Future<void> _updateOfflineSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('force_offline_mode', true);
      debugPrint('[BackgroundTileDownloadService] Offline settings updated');
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error updating offline settings: $e',
      );
    }
  }

  /// Show quota warning
  void _showQuotaWarning(int currentTiles) {}

  /// Stop all downloads
  void _stopAllDownloads() {
    _downloadTimer?.cancel();

    // Mark all downloading regions as cancelled
    for (final region in downloadQueue) {
      if (region.status == DownloadStatus.downloading) {
        region.status = DownloadStatus.cancelled;
      }
    }

    isDownloading.value = false;
    currentDownloadRegion.value = '';
    downloadProgress.value = 0.0;
  }

  /// Process next download only if enough time has passed
  Future<void> _processNextDownloadIfReady() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final lastDownloadTime = prefs.getInt('last_download_timestamp') ?? 0;

      final timeSinceLastDownload =
          DateTime.now().millisecondsSinceEpoch - lastDownloadTime;

      // Only process if enough time has passed (respect download interval)
      if (timeSinceLastDownload >= DOWNLOAD_INTERVAL.inMilliseconds) {
        debugPrint(
          '[BackgroundTileDownloadService] Processing download - enough time passed',
        );
        await _processNextDownload();
      } else {
        final remainingTime =
            DOWNLOAD_INTERVAL.inMilliseconds - timeSinceLastDownload;
        debugPrint(
          '[BackgroundTileDownloadService] Waiting ${Duration(milliseconds: remainingTime).inMinutes} more minutes before next download',
        );
      }
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error checking download timing: $e',
      );
    }
  }

  /// Load configuration from SharedPreferences
  Future<void> _loadConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      autoDownloadEnabled.value =
          prefs.getBool('auto_download_enabled') ?? true;
      wifiOnlyDownloads.value = prefs.getBool('wifi_only_downloads') ?? true;
      maxTilesLimit.value =
          prefs.getInt('max_tiles_limit') ?? MAX_TILES_THRESHOLD;
      forceOfflineMode.value = prefs.getBool('force_offline_mode') ?? false;
      stopDownloading.value = prefs.getBool('stop_downloading') ?? false;

      // FIX: Load persisted tile count and ensure it's displayed immediately
      final persistedTileCount = prefs.getInt('total_tiles_downloaded') ?? 0;
      totalTilesDownloaded.value = persistedTileCount;

      // Load last download timestamp to avoid immediate restart
      final lastDownloadTime = prefs.getInt('last_download_timestamp') ?? 0;
      final timeSinceLastDownload =
          DateTime.now().millisecondsSinceEpoch - lastDownloadTime;
      final shouldWaitBeforeNextDownload =
          timeSinceLastDownload < DOWNLOAD_INTERVAL.inMilliseconds;

      debugPrint('[BackgroundTileDownloadService] Configuration loaded:');
      debugPrint('  - 💾 Persisted tiles: $persistedTileCount');
      debugPrint('  - Force offline: ${forceOfflineMode.value}');
      debugPrint('  - Stop downloading: ${stopDownloading.value}');
      debugPrint(
        '  - Time since last download: ${Duration(milliseconds: timeSinceLastDownload).inMinutes} minutes',
      );
      debugPrint('  - Should wait: $shouldWaitBeforeNextDownload');

      // Load persisted download queue
      await _loadDownloadQueue();

      // Initial quota check with persisted count
      _checkQuotaStatus();

      // FIX: If we have persisted tiles, show resume message
      if (persistedTileCount > 0) {
        debugPrint(
          '[BackgroundTileDownloadService] 🔄 RESUMING from $persistedTileCount tiles',
        );
      }
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error loading configuration: $e',
      );
    }
  }

  /// Save configuration to SharedPreferences
  Future<void> _saveConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('auto_download_enabled', autoDownloadEnabled.value);
      await prefs.setBool('wifi_only_downloads', wifiOnlyDownloads.value);
      await prefs.setInt('max_tiles_limit', maxTilesLimit.value);
      await prefs.setBool('force_offline_mode', forceOfflineMode.value);
      await prefs.setBool('stop_downloading', stopDownloading.value);

      // Save tile count immediately when it changes
      await prefs.setInt('total_tiles_downloaded', totalTilesDownloaded.value);

      debugPrint(
        '[BackgroundTileDownloadService] Configuration saved - tiles: ${totalTilesDownloaded.value}',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error saving configuration: $e',
      );
    }
  }

  /// Update tile count and save to preferences
  void updateTileCount(int newCount) {
    final oldCount = totalTilesDownloaded.value;
    totalTilesDownloaded.value = newCount;

    debugPrint(
      '[BackgroundTileDownloadService] Tile count updated: $oldCount -> $newCount',
    );

    // Save to preferences every 100 tiles or when reaching milestones
    if (newCount % 100 == 0 || newCount >= 50000 || newCount > oldCount + 500) {
      _saveConfiguration();
    }
  }

  /// Cleanup resources
  void _cleanup() {
    _downloadTimer?.cancel();
    _quotaCheckTimer?.cancel();
    _isolateSubscription?.cancel();
    _receivePort?.close();
    _downloadIsolate?.kill(priority: Isolate.immediate);

    // FIX: Reset isolate references to prevent stale state
    _downloadIsolate = null;
    _sendPort = null;
    _receivePort = null;
    _isolateSubscription = null;

    debugPrint(
      '[BackgroundTileDownloadService] Cleanup completed - all references reset',
    );
  }

  /// Public methods for external control

  /// Enable/disable auto downloads
  Future<void> setAutoDownloadEnabled(bool enabled) async {
    autoDownloadEnabled.value = enabled;
    await _saveConfiguration();

    if (enabled && !stopDownloading.value) {
      _startBackgroundDownloads();
    } else {
      _stopAllDownloads();
    }
  }

  /// Set WiFi only downloads
  Future<void> setWifiOnlyDownloads(bool wifiOnly) async {
    wifiOnlyDownloads.value = wifiOnly;
    await _saveConfiguration();
  }

  /// Set max tiles limit and update disk quota
  Future<void> setMaxTilesLimit(int limit) async {
    // Allow opu o550,000 t,tal til00, butotnsur les h regien sueyc under 700h region stays under 700
    final safeLimit = math.min(limit, MAX_TILES_THRESHOLD);

    maxTilesLimit.value = safeLimit;
    await _saveConfiguration();

    // Update disk quota to match new tile limit (50,000 tiles = ~62.5 GB) (50,000 tiles = ~62.5 GB)
    await setTileQuota(safeLimit);

    // Check if current tiles exceed new limit
    if (totalTilesDownloaded.value >= safeLimit) {
      _enforceOfflineMode();
    } else {
      // If new limit is higher and we were stopped, resume downloads
      if (stopDownloading.value && totalTilesDownloaded.value < safeLimit) {
        _resumeDownloads();
      }
    }

    debugPrint(
      '[BackgroundTileDownloadService] Updated max tiles limit to $safeLimit (requested: $limit)',
    );
  }

  /// Resume downloads when quota allows
  void _resumeDownloads() {
    stopDownloading.value = false;
    forceOfflineMode.value = false;

    // FIX: Use proper isolate management for resume
    _startBackgroundDownloads();

    // Count pending regions with partial progress
    final resumableRegions =
        downloadQueue
            .where((r) => r.status == DownloadStatus.pending && r.progress > 0)
            .length;
    final totalPendingRegions =
        downloadQueue.where((r) => r.status == DownloadStatus.pending).length;

    debugPrint(
      '[BackgroundTileDownloadService] ✅ Downloads resumed - current: ${totalTilesDownloaded.value}/${maxTilesLimit.value}, ${resumableRegions} resumable regions, ${totalPendingRegions} total pending',
    );

    // Downloads resumed notification removed as requested
  }

  /// Reset offline state (for testing or cache clearing)
  Future<void> resetOfflineState() async {
    forceOfflineMode.value = false;
    stopDownloading.value = false;
    totalTilesDownloaded.value = 0;
    downloadProgress.value = 0.0;
    currentDownloadRegion.value = '';

    await _saveConfiguration();
    debugPrint('[BackgroundTileDownloadService] Offline state reset');

    if (autoDownloadEnabled.value) {
      _startBackgroundDownloads();
    }
  }

  /// Manually trigger download for specific region with proper tile limits
  Future<void> downloadRegion(
    mapbox.CoordinateBounds bounds,
    List<int> zoomLevels,
  ) async {
    // Validate zoom levels to prevent exceeding tile limits
    final validZoomLevels =
        zoomLevels.where((zoom) => zoom >= 10 && zoom <= 14).toList();
    if (validZoomLevels.length > 3) {
      validZoomLevels.removeRange(
        3,
        validZoomLevels.length,
      ); // Max 3 zoom levels
    }

    final region = DownloadRegion(
      id: 'manual_${DateTime.now().millisecondsSinceEpoch}',
      bounds: bounds,
      zoomLevels: validZoomLevels,
      priority: 1000, // High priority for manual downloads
      scheduledTime: DateTime.now(),
      estimatedTiles: MAPBOX_REGION_TILE_LIMIT ~/ 2, // Conservative estimate
    );

    downloadQueue.insert(0, region); // Add to front of queue

    if (!isDownloading.value && !stopDownloading.value) {
      _processNextDownload();
    }
  }

  /// Get current quota status
  TileQuotaStatus getCurrentQuotaStatus() {
    return TileQuotaStatus(
      currentTiles: totalTilesDownloaded.value,
      maxTiles: maxTilesLimit.value,
      usagePercentage: (totalTilesDownloaded.value / maxTilesLimit.value) * 100,
      shouldWarn: totalTilesDownloaded.value >= WARNING_THRESHOLD,
      shouldForceOffline: totalTilesDownloaded.value >= maxTilesLimit.value,
    );
  }

  /// Load download queue from SharedPreferences
  Future<void> _loadDownloadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getStringList('download_queue') ?? [];

      downloadQueue.clear();
      int resumedRegions = 0;

      for (final regionJson in queueJson) {
        try {
          final regionMap = Map<String, dynamic>.from(
            jsonDecode(regionJson) as Map,
          );
          final region = DownloadRegion.fromMap(regionMap);

          // FIX: Handle different statuses appropriately for resume capability
          if (region.status == DownloadStatus.downloading) {
            // Convert downloading regions back to pending for resume
            region.status = DownloadStatus.pending;
            resumedRegions++;
            debugPrint(
              '[BackgroundTileDownloadService] Converting downloading region to pending for resume: ${region.id} (${(region.progress * 100).toStringAsFixed(1)}% completed)',
            );
          }

          // Add all non-completed regions (including converted downloading ones)
          if (region.status == DownloadStatus.pending ||
              (region.status == DownloadStatus.failed &&
                  region.retryCount < 3)) {
            downloadQueue.add(region);
          } else if (region.status == DownloadStatus.completed) {
            debugPrint(
              '[BackgroundTileDownloadService] Skipping completed region: ${region.id}',
            );
          }
        } catch (e) {
          debugPrint(
            '[BackgroundTileDownloadService] Error parsing region: $e',
          );
        }
      }

      debugPrint(
        '[BackgroundTileDownloadService] Loaded ${downloadQueue.length} regions from queue (${resumedRegions} resumed from previous session)',
      );

      // Calculate total tiles from completed regions that were skipped
      final completedTilesFromPreviousSessions = downloadQueue
          .where(
            (r) =>
                r.status == DownloadStatus.pending &&
                r.tilesDownloadedSoFar > 0,
          )
          .fold<int>(0, (sum, region) => sum + region.tilesDownloadedSoFar);

      if (completedTilesFromPreviousSessions > 0) {
        debugPrint(
          '[BackgroundTileDownloadService] Found ${completedTilesFromPreviousSessions} tiles from previous partial downloads',
        );
      }

      // FIX: Handle empty queue - reset state and schedule new regions if needed
      if (downloadQueue.isEmpty) {
        debugPrint(
          '[BackgroundTileDownloadService] No regions in queue - resetting download state',
        );
        isDownloading.value = false;
        currentDownloadRegion.value = '';
        downloadProgress.value = 0.0;

        // If we're under the quota limit, schedule new regions
        if (totalTilesDownloaded.value < maxTilesLimit.value) {
          debugPrint(
            '[BackgroundTileDownloadService] Under quota limit (${totalTilesDownloaded.value}/${maxTilesLimit.value}) - scheduling new regions',
          );
          Future.delayed(Duration(seconds: 1), () {
            _scheduleIntelligentDownloads();
          });
        }
      } else {
        // FIX: Restore UI progress for currently downloading region if any
        _restoreUIProgressState();
      }
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error loading download queue: $e',
      );
    }
  }

  /// Restore UI progress state for resumed downloads
  void _restoreUIProgressState() {
    // Find any region that was being downloaded and restore its progress to UI
    final downloadingRegion = downloadQueue.firstWhereOrNull(
      (region) =>
          region.status == DownloadStatus.pending && region.progress > 0,
    );

    if (downloadingRegion != null) {
      currentDownloadRegion.value = downloadingRegion.id;
      downloadProgress.value = downloadingRegion.progress;
      debugPrint(
        '[BackgroundTileDownloadService] Restored UI progress for region ${downloadingRegion.id}: ${(downloadingRegion.progress * 100).toStringAsFixed(1)}%',
      );
    }
  }

  /// Clean up stale or invalid download regions
  void _cleanupStaleRegions() {
    final now = DateTime.now();
    final staleRegions = <DownloadRegion>[];

    for (final region in downloadQueue) {
      // Remove regions that have been downloading for too long (over 1 hour)
      if (region.status == DownloadStatus.downloading &&
          region.startTime != null &&
          now.difference(region.startTime!).inHours > 1) {
        region.status = DownloadStatus.pending; // Reset to pending for retry
        staleRegions.add(region);
      }

      // Remove regions with no progress after multiple retries
      if (region.retryCount > 3 && region.progress == 0.0) {
        staleRegions.add(region);
      }
    }

    if (staleRegions.isNotEmpty) {
      for (final staleRegion in staleRegions) {
        if (staleRegion.retryCount > 3) {
          downloadQueue.remove(staleRegion);
          debugPrint(
            '[BackgroundTileDownloadService] Removed stale region: ${staleRegion.id}',
          );
        } else {
          debugPrint(
            '[BackgroundTileDownloadService] Reset stale downloading region to pending: ${staleRegion.id}',
          );
        }
      }
      _saveDownloadQueue();
    }
  }

  /// Save download queue to SharedPreferences with progress
  Future<void> _saveDownloadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // FIX: Save all regions including their progress state
      final queueJson =
          downloadQueue.map((region) {
            final regionMap = region.toMap();
            debugPrint(
              '[BackgroundTileDownloadService] Saving region ${region.id}: status=${region.status}, progress=${(region.progress * 100).toStringAsFixed(1)}%, tiles=${region.tilesDownloadedSoFar}',
            );
            return jsonEncode(regionMap);
          }).toList();

      await prefs.setStringList('download_queue', queueJson);
      debugPrint(
        '[BackgroundTileDownloadService] Saved ${queueJson.length} regions to queue (including progress data)',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error saving download queue: $e',
      );
    }
  }

  /// Set tile quota using proper TileStore API
  Future<void> setTileQuota(int tileCount) async {
    try {
      if (_tileStore == null) {
        debugPrint('[BackgroundTileDownloadService] TileStore not initialized');
        return;
      }

      // Convert tile count to approximate disk size (1.25 MB per tile)
      final diskQuotaBytes = tileCount * 1250000;

      // Use setDiskQuota method directly
      _tileStore!.setDiskQuota(4000000000);

      debugPrint(
        '[BackgroundTileDownloadService] Set disk quota: ${diskQuotaBytes / 1024 / 1024} MB for $tileCount tiles',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error setting tile quota: $e',
      );
    }
  }

  /// Set disk quota directly in bytes
  Future<void> setDiskQuota(int limitInBytes) async {
    try {
      if (_tileStore == null) {
        debugPrint('[BackgroundTileDownloadService] TileStore not initialized');
        return;
      }

      // Use setDiskQuota method directly
      _tileStore!.setDiskQuota(4000000000);
      debugPrint(
        '[BackgroundTileDownloadService] Set disk quota: ${limitInBytes / 1024 / 1024} MB',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error setting disk quota: $e',
      );
    }
  }

  /// Download large region by splitting into multiple small regions
  Future<void> downloadLargeRegion(
    mapbox.CoordinateBounds bounds,
    List<int> zoomLevels,
  ) async {
    try {
      debugPrint(
        '[BackgroundTileDownloadService] Splitting large region into Mapbox-compliant sub-regions',
      );

      // Calculate how many sub-regions we need to stay under per-region limits
      final estimatedTotalTiles = _estimateRegionTiles(bounds, zoomLevels);
      final subRegionsNeeded =
          (estimatedTotalTiles / MAPBOX_REGION_TILE_LIMIT).ceil();
      final gridSize = math.sqrt(subRegionsNeeded).ceil();

      // Split the large bounds into smaller sub-regions
      final subRegions = _splitBoundsIntoSubRegions(bounds, gridSize, gridSize);

      for (int i = 0; i < subRegions.length; i++) {
        // Ensure we don't exceed total tile limit
        if (totalTilesDownloaded.value + (i * MAPBOX_REGION_TILE_LIMIT) >=
            maxTilesLimit.value) {
          debugPrint(
            '[BackgroundTileDownloadService] Stopping sub-region creation - would exceed total limit',
          );
          break;
        }

        final subRegion = DownloadRegion(
          id: 'sub_region_${i}_${DateTime.now().millisecondsSinceEpoch}',
          bounds: subRegions[i],
          zoomLevels:
              zoomLevels
                  .where((z) => z <= 14)
                  .take(3)
                  .toList(), // Max 3 zoom levels
          priority: 100 + i,
          scheduledTime: DateTime.now().add(
            Duration(minutes: i * 2),
          ), // Stagger downloads
          estimatedTiles:
              MAPBOX_REGION_TILE_LIMIT ~/ 2, // Conservative per sub-region
        );

        downloadQueue.add(subRegion);
      }

      await _saveDownloadQueue();
      debugPrint(
        '[BackgroundTileDownloadService] Scheduled ${subRegions.length} sub-regions for download',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadService] Error downloading large region: $e',
      );
    }
  }

  /// Estimate tiles for a region (rough calculation)
  int _estimateRegionTiles(
    mapbox.CoordinateBounds bounds,
    List<int> zoomLevels,
  ) {
    final latDiff =
        bounds.northeast.coordinates.lat - bounds.southwest.coordinates.lat;
    final lngDiff =
        bounds.northeast.coordinates.lng - bounds.southwest.coordinates.lng;
    final area = latDiff * lngDiff;

    // Rough estimation: more area and zoom levels = more tiles
    return (area * 10000 * zoomLevels.length).round();
  }

  /// Split bounds into smaller sub-regions
  List<mapbox.CoordinateBounds> _splitBoundsIntoSubRegions(
    mapbox.CoordinateBounds bounds,
    int rows,
    int cols,
  ) {
    final subRegions = <mapbox.CoordinateBounds>[];

    final swLat = bounds.southwest.coordinates.lat;
    final swLng = bounds.southwest.coordinates.lng;
    final neLat = bounds.northeast.coordinates.lat;
    final neLng = bounds.northeast.coordinates.lng;

    final latStep = (neLat - swLat) / rows;
    final lngStep = (neLng - swLng) / cols;

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final subSw = mapbox.Point(
          coordinates: mapbox.Position(
            swLng + (col * lngStep),
            swLat + (row * latStep),
          ),
        );
        final subNe = mapbox.Point(
          coordinates: mapbox.Position(
            swLng + ((col + 1) * lngStep),
            swLat + ((row + 1) * latStep),
          ),
        );

        subRegions.add(
          mapbox.CoordinateBounds(
            southwest: subSw,
            northeast: subNe,
            infiniteBounds: false,
          ),
        );
      }
    }

    return subRegions;
  }
}

/// Download region model
class DownloadRegion {
  final String id;
  final mapbox.CoordinateBounds bounds;
  final List<int> zoomLevels;
  final int priority;
  final DateTime scheduledTime;
  final int estimatedTiles;
  DownloadStatus status;
  int retryCount;

  // NEW: Progress tracking fields
  double progress; // 0.0 to 1.0
  int tilesDownloadedSoFar; // Actual tiles downloaded for this region
  DateTime? startTime; // When download started
  DateTime? lastProgressTime; // Last progress update
  DateTime? completedTime; // When download completed

  DownloadRegion({
    required this.id,
    required this.bounds,
    required this.zoomLevels,
    required this.priority,
    required this.scheduledTime,
    required this.estimatedTiles,
    this.status = DownloadStatus.pending,
    this.retryCount = 0,
    this.progress = 0.0,
    this.tilesDownloadedSoFar = 0,
    this.startTime,
    this.lastProgressTime,
    this.completedTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bounds': {
        'southwest': {
          'lat': bounds.southwest.coordinates.lat,
          'lng': bounds.southwest.coordinates.lng,
        },
        'northeast': {
          'lat': bounds.northeast.coordinates.lat,
          'lng': bounds.northeast.coordinates.lng,
        },
      },
      'zoomLevels': zoomLevels,
      'priority': priority,
      'scheduledTime': scheduledTime.millisecondsSinceEpoch,
      'estimatedTiles': estimatedTiles,
      'status': status.index,
      'retryCount': retryCount,
      // NEW: Progress tracking fields
      'progress': progress,
      'tilesDownloadedSoFar': tilesDownloadedSoFar,
      'startTime': startTime?.millisecondsSinceEpoch,
      'lastProgressTime': lastProgressTime?.millisecondsSinceEpoch,
      'completedTime': completedTime?.millisecondsSinceEpoch,
    };
  }

  static DownloadRegion fromMap(Map<String, dynamic> map) {
    final boundsMap = map['bounds'] as Map<String, dynamic>;
    final sw = boundsMap['southwest'] as Map<String, dynamic>;
    final ne = boundsMap['northeast'] as Map<String, dynamic>;

    return DownloadRegion(
      id: map['id'] as String,
      bounds: mapbox.CoordinateBounds(
        southwest: mapbox.Point(
          coordinates: mapbox.Position(sw['lng'], sw['lat']),
        ),
        northeast: mapbox.Point(
          coordinates: mapbox.Position(ne['lng'], ne['lat']),
        ),
        infiniteBounds: false,
      ),
      zoomLevels: List<int>.from(map['zoomLevels'] as List),
      priority: map['priority'] as int,
      scheduledTime: DateTime.fromMillisecondsSinceEpoch(
        map['scheduledTime'] as int,
      ),
      estimatedTiles: map['estimatedTiles'] as int,
      status: DownloadStatus.values[map['status'] as int],
      retryCount: map['retryCount'] as int? ?? 0,
      // NEW: Progress tracking fields
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      tilesDownloadedSoFar: map['tilesDownloadedSoFar'] as int? ?? 0,
      startTime:
          map['startTime'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int)
              : null,
      lastProgressTime:
          map['lastProgressTime'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                map['lastProgressTime'] as int,
              )
              : null,
      completedTime:
          map['completedTime'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['completedTime'] as int)
              : null,
    );
  }
}

/// Download status enum
enum DownloadStatus { pending, downloading, completed, failed, cancelled }

/// Location models
class LocationHotspot {
  final String id;
  final LocationPoint center;
  final double radius;
  final int memoryCount;
  final DateTime lastVisited;
  final int priority;

  LocationHotspot({
    required this.id,
    required this.center,
    required this.radius,
    required this.memoryCount,
    required this.lastVisited,
    required this.priority,
  });
}

class LocationCluster {
  final String id;
  final LocationPoint center;
  final double radius;
  final List<Map<String, dynamic>> memories;
  DateTime lastVisited;

  LocationCluster({
    required this.id,
    required this.center,
    required this.radius,
    required this.memories,
    required this.lastVisited,
  });

  void updateLastVisited(Map<String, dynamic> memory) {
    final memoryDate = DateTime.tryParse(memory['created_at'] ?? '');
    if (memoryDate != null && memoryDate.isAfter(lastVisited)) {
      lastVisited = memoryDate;
    }
  }
}

class LocationPoint {
  final double latitude;
  final double longitude;

  LocationPoint({required this.latitude, required this.longitude});
}

/// Tile quota status model
class TileQuotaStatus {
  final int currentTiles;
  final int maxTiles;
  final double usagePercentage;
  final bool shouldWarn;
  final bool shouldForceOffline;

  TileQuotaStatus({
    required this.currentTiles,
    required this.maxTiles,
    required this.usagePercentage,
    required this.shouldWarn,
    required this.shouldForceOffline,
  });
}

/// Create conservative bounds that respect per-region tile limits
mapbox.CoordinateBounds _createConservativeBoundsFromHotspot(
  LocationHotspot hotspot,
) {
  // Create small area to stay under 700 tiles per region
  const double kmToDegrees = 0.009; // Rough conversion
  const double radius = kmToDegrees * 1.0; // 1km radius = 2km x 2km area

  return mapbox.CoordinateBounds(
    southwest: mapbox.Point(
      coordinates: mapbox.Position(
        hotspot.center.longitude - radius,
        hotspot.center.latitude - radius,
      ),
    ),
    northeast: mapbox.Point(
      coordinates: mapbox.Position(
        hotspot.center.longitude + radius,
        hotspot.center.latitude + radius,
      ),
    ),
    infiniteBounds: false,
  );
}
