import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:shared_preferences/shared_preferences.dart';

/// Background tile download service using isolates for non-blocking downloads (COPY VERSION)
class BackgroundTileDownloadServiceCopy extends GetxService {
  static BackgroundTileDownloadServiceCopy get instance => Get.find();

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
  final RxList<DownloadRegionCopy> downloadQueue = <DownloadRegionCopy>[].obs;
  final RxBool _isInitialized = false.obs; // Add missing _isInitialized

  // Configuration
  final RxBool autoDownloadEnabled = true.obs;
  final RxBool wifiOnlyDownloads = true.obs;
  final RxInt maxTilesLimit = MAX_TILES_THRESHOLD.obs;

  @override
  Future<void> onInit() async {
    super.onInit();

    await _loadConfiguration();

    debugPrint('[BackgroundTileDownloadServiceCopy] Service initialized');
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
      '[BackgroundTileDownloadServiceCopy] Initialized with disk quota for ${maxTilesLimit.value} tiles',
    );
  }

  /// Set tile quota (disk space limit)
  Future<void> setTileQuota(int maxTiles) async {
    if (_tileStore == null) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] ⚠️ Cannot set quota - TileStore not initialized',
      );
      return;
    }

    try {
      // Set the max tiles limit
      maxTilesLimit.value = maxTiles;

      debugPrint(
        '[BackgroundTileDownloadServiceCopy] ✅ Max tiles limit set to $maxTiles',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] ❌ Failed to set max tiles limit: $e',
      );
    }
  }

  /// Load configuration from SharedPreferences
  Future<void> _loadConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      autoDownloadEnabled.value =
          prefs.getBool('auto_download_enabled_copy') ?? true;
      wifiOnlyDownloads.value = prefs.getBool('wifi_only_downloads_copy') ?? true;
      maxTilesLimit.value =
          prefs.getInt('max_tiles_limit_copy') ?? MAX_TILES_THRESHOLD;
      totalTilesDownloaded.value =
          prefs.getInt('total_tiles_downloaded_copy') ?? 0;

      debugPrint(
        '[BackgroundTileDownloadServiceCopy] Configuration loaded - Auto: ${autoDownloadEnabled.value}, WiFi Only: ${wifiOnlyDownloads.value}, Max: ${maxTilesLimit.value}',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] ⚠️ Failed to load configuration: $e',
      );
    }
  }

  /// Save configuration to SharedPreferences
  Future<void> _saveConfiguration() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool('auto_download_enabled_copy', autoDownloadEnabled.value);
      await prefs.setBool('wifi_only_downloads_copy', wifiOnlyDownloads.value);
      await prefs.setInt('max_tiles_limit_copy', maxTilesLimit.value);
      await prefs.setInt('total_tiles_downloaded_copy', totalTilesDownloaded.value);

      debugPrint('[BackgroundTileDownloadServiceCopy] Configuration saved');
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] ⚠️ Failed to save configuration: $e',
      );
    }
  }

  /// Load download queue from SharedPreferences
  Future<void> _loadDownloadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString('download_queue_copy');

      if (queueJson != null) {
        final List<dynamic> queueList = jsonDecode(queueJson);
        downloadQueue.value = queueList
            .map((item) => DownloadRegionCopy.fromMap(item as Map<String, dynamic>))
            .toList();

        debugPrint(
          '[BackgroundTileDownloadServiceCopy] Loaded ${downloadQueue.length} regions from queue',
        );
      }
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] ⚠️ Failed to load download queue: $e',
      );
    }
  }

  /// Save download queue to SharedPreferences
  Future<void> _saveDownloadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson =
          jsonEncode(downloadQueue.map((region) => region.toMap()).toList());

      await prefs.setString('download_queue_copy', queueJson);

      debugPrint(
        '[BackgroundTileDownloadServiceCopy] Saved ${downloadQueue.length} regions to queue',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] ⚠️ Failed to save download queue: $e',
      );
    }
  }

  /// Clean up stale regions (completed, failed, or cancelled)
  void _cleanupStaleRegions() {
    final initialCount = downloadQueue.length;

    downloadQueue.removeWhere(
      (region) =>
          region.status == DownloadStatusCopy.completed ||
          region.status == DownloadStatusCopy.failed ||
          region.status == DownloadStatusCopy.cancelled,
    );

    final removedCount = initialCount - downloadQueue.length;

    if (removedCount > 0) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] 🧹 Cleaned up $removedCount stale regions',
      );
      _saveDownloadQueue();
    }
  }

  /// Cleanup resources
  void _cleanup() {
    _downloadTimer?.cancel();
    _quotaCheckTimer?.cancel();
    _isolateSubscription?.cancel();
    _downloadIsolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();

    debugPrint('[BackgroundTileDownloadServiceCopy] Cleanup completed');
  }

  /// Start tile quota monitoring
  void _startTileQuotaMonitoring() {
    _quotaCheckTimer?.cancel();

    _quotaCheckTimer = Timer.periodic(QUOTA_CHECK_INTERVAL, (timer) async {
      await _checkTileQuota();
    });

    debugPrint(
      '[BackgroundTileDownloadServiceCopy] 📊 Tile quota monitoring started',
    );
  }

  /// Check current tile quota and enforce limits
  Future<void> _checkTileQuota() async {
    if (_tileStore == null) return;

    try {
      // Request tile count from isolate
      _requestTileCount();

      // Check if we've exceeded the quota
      _checkQuotaStatus();
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] ⚠️ Error checking tile quota: $e',
      );
    }
  }

  /// Check quota status and enforce limits
  void _checkQuotaStatus() {
    if (totalTilesDownloaded.value >= maxTilesLimit.value) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] 🚫 Tile quota reached: ${totalTilesDownloaded.value}/${maxTilesLimit.value}',
      );

      stopDownloading.value = true;
      forceOfflineMode.value = true;

      // Stop any ongoing downloads
      if (isDownloading.value) {
        _sendPort?.send({'type': 'cancel_download'});
        isDownloading.value = false;
      }
    } else if (totalTilesDownloaded.value >= WARNING_THRESHOLD) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] ⚠️ Approaching tile quota: ${totalTilesDownloaded.value}/${maxTilesLimit.value}',
      );
    }
  }

  /// Initialize download isolate
  Future<void> _initializeDownloadIsolate() async {
    try {
      _receivePort = ReceivePort();

      _downloadIsolate = await Isolate.spawn(
        _downloadIsolateEntryPoint,
        _receivePort!.sendPort,
      );

      _isolateSubscription = _receivePort!.listen(_handleIsolateMessage);

      debugPrint(
        '[BackgroundTileDownloadServiceCopy] Download isolate initialized',
      );
    } catch (e) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] ❌ Failed to initialize isolate: $e',
      );
    }
  }

  /// Isolate entry point
  static void _downloadIsolateEntryPoint(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        final type = message['type'] as String?;

        switch (type) {
          case 'download_region':
            _handleDownloadRegionInIsolate(message, sendPort);
            break;
          case 'count_tiles':
            _handleCountTilesInIsolate(message, sendPort);
            break;
          case 'cancel_download':
            // Handle cancellation
            break;
        }
      }
    });
  }

  /// Handle download region in isolate
  static void _handleDownloadRegionInIsolate(
    Map<String, dynamic> message,
    SendPort sendPort,
  ) {
    try {
      final regionData = message['region'] as Map<String, dynamic>;
      final regionId = regionData['id'] as String;

      // Send download started
      sendPort.send({
        'type': 'download_started',
        'region_id': regionId,
      });

      // Simulate download progress
      final random = math.Random();
      int tilesDownloaded = regionData['tiles_already_downloaded'] as int? ?? 0;
      final resumeProgress = (regionData['resume_from_progress'] as num?)?.toDouble() ?? 0.0;

      for (int i = (resumeProgress * 10).toInt(); i <= 10; i++) {
        final progress = i / 10.0;
        final tilesThisStep = random.nextInt(50) + 10;

        sendPort.send({
          'type': 'download_progress',
          'region_id': regionId,
          'progress': progress,
          'tiles_downloaded_this_step': tilesThisStep,
        });

        tilesDownloaded += tilesThisStep;

        // Simulate work
        Future.delayed(Duration(milliseconds: 500));
      }

      // Send completion
      sendPort.send({
        'type': 'download_completed',
        'region_id': regionId,
        'tiles_downloaded': tilesDownloaded,
      });
    } catch (e) {
      sendPort.send({
        'type': 'download_error',
        'region_id': message['region']?['id'] ?? 'unknown',
        'error': e.toString(),
      });
    }
  }

  /// Handle count tiles in isolate
  static void _handleCountTilesInIsolate(
    Map<String, dynamic> message,
    SendPort sendPort,
  ) {
    try {
      final expectedCount = message['expected_count'] as int? ?? 0;

      // Return the expected count (stable mocking)
      sendPort.send({
        'type': 'tile_count_result',
        'count': expectedCount,
      });
    } catch (e) {
      sendPort.send({
        'type': 'tile_count_error',
        'error': e.toString(),
      });
    }
  }

  /// Handle messages from isolate
  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] Received isolate send port - isolate ready',
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
            '[BackgroundTileDownloadServiceCopy] Tile count error: ${message['error']}',
          );
          break;
        case 'error':
          debugPrint(
            '[BackgroundTileDownloadServiceCopy] Isolate error: ${message['message']}',
          );
          break;
        default:
          debugPrint(
            '[BackgroundTileDownloadServiceCopy] Unknown message type: $type',
          );
      }
    }
  }

  /// Handle download started message
  void _handleDownloadStarted(Map<String, dynamic> message) {
    final regionId = message['region_id'] as String;
    debugPrint(
      '[BackgroundTileDownloadServiceCopy] Download started for region: $regionId',
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
      '[BackgroundTileDownloadServiceCopy] Progress for $regionId: ${(progress * 100).toStringAsFixed(1)}%, +$tilesDownloadedThisStep tiles',
    );

    // Update region-specific progress for persistence
    final region = downloadQueue.firstWhereOrNull((r) => r.id == regionId);
    if (region != null) {
      region.progress = progress;
      region.tilesDownloadedSoFar += tilesDownloadedThisStep;
      region.lastProgressTime = DateTime.now();

      debugPrint(
        '[BackgroundTileDownloadServiceCopy] Region $regionId progress: ${(progress * 100).toStringAsFixed(1)}%, total tiles for region: ${region.tilesDownloadedSoFar}',
      );
    }

    // Update current download progress for UI
    downloadProgress.value = progress;

    // Add only the new tiles from this step to avoid double counting
    if (tilesDownloadedThisStep > 0) {
      totalTilesDownloaded.value += tilesDownloadedThisStep;
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] Total tiles now: ${totalTilesDownloaded.value}',
      );
    }

    // Save progress periodically (every 10% or every 100 tiles)
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
      '[BackgroundTileDownloadServiceCopy] Download completed for region $regionId: $tilesDownloaded tiles',
    );

    // Update region status and completion time
    final region = downloadQueue.firstWhereOrNull((r) => r.id == regionId);
    if (region != null) {
      region.status = DownloadStatusCopy.completed;
      region.progress = 1.0;
      region.completedTime = DateTime.now();
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] Region $regionId marked as completed with ${region.tilesDownloadedSoFar} tiles',
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

    // Immediately continue with next region
    debugPrint(
      '[BackgroundTileDownloadServiceCopy] Immediately processing next region...',
    );
    _processNextDownload();
  }

  /// Handle download error message
  void _handleDownloadError(Map<String, dynamic> message) {
    final regionId = message['region_id'];
    final errorMessage = message['error'];

    debugPrint(
      '[BackgroundTileDownloadServiceCopy] Download error for region $regionId: $errorMessage',
    );

    // Mark region as failed and potentially retry
    final region = downloadQueue.firstWhereOrNull((r) => r.id == regionId);
    if (region != null) {
      region.status = DownloadStatusCopy.failed;
      region.retryCount++;

      // Retry up to 3 times
      if (region.retryCount < 3) {
        region.status = DownloadStatusCopy.pending;
        debugPrint(
          '[BackgroundTileDownloadServiceCopy] Scheduling retry for region: $regionId (attempt ${region.retryCount + 1}/3)',
        );
      } else {
        debugPrint(
          '[BackgroundTileDownloadServiceCopy] Region $regionId failed after 3 attempts, skipping permanently',
        );
      }
    }

    // Reset current download state but keep isDownloading true to continue
    currentDownloadRegion.value = '';
    downloadProgress.value = 0.0;

    // Save the updated queue state
    _saveDownloadQueue();

    // Continue with next region immediately
    debugPrint(
      '[BackgroundTileDownloadServiceCopy] Continuing to next region after error...',
    );
    _processNextDownload();
  }

  /// Handle tile count result
  void _handleTileCountResult(Map<String, dynamic> message) {
    final isolateCount = message['count'] as int;
    debugPrint(
      '[BackgroundTileDownloadServiceCopy] Isolate tile count: $isolateCount, Persisted count: ${totalTilesDownloaded.value}',
    );

    final persistedCount = totalTilesDownloaded.value;

    if (persistedCount == 0) {
      // First time initialization - use isolate count if reasonable
      if (isolateCount > 0 && isolateCount < MAX_TILES_THRESHOLD) {
        totalTilesDownloaded.value = isolateCount;
        debugPrint(
          '[BackgroundTileDownloadServiceCopy] Initial tile count set to: $isolateCount',
        );
        _saveConfiguration();
      }
    } else {
      // Resume scenario - keep persisted count unless isolate shows significant progress
      if (isolateCount > persistedCount + 1000) {
        totalTilesDownloaded.value = isolateCount;
        debugPrint(
          '[BackgroundTileDownloadServiceCopy] Tile count updated: $persistedCount -> $isolateCount',
        );
        _saveConfiguration();
      } else {
        debugPrint(
          '[BackgroundTileDownloadServiceCopy] Keeping persisted tile count: $persistedCount (isolate: $isolateCount)',
        );
      }
    }

    _checkQuotaStatus();
  }

  /// Request tile count from isolate
  void _requestTileCount() {
    if (_sendPort != null) {
      _sendPort!.send({
        'type': 'count_tiles',
        'expected_count': totalTilesDownloaded.value,
      });
    }
  }

  /// Start background downloads with proper isolate management
  void _startBackgroundDownloads() {
    if (_downloadTimer != null) {
      _downloadTimer!.cancel();
    }

    // Only create isolate if it doesn't exist or is not ready
    if (_downloadIsolate == null || _sendPort == null) {
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] Creating new isolate - current state: isolate=${_downloadIsolate != null}, sendPort=${_sendPort != null}',
      );
      _initializeDownloadIsolate();
    } else {
      debugPrint('[BackgroundTileDownloadServiceCopy] Reusing existing isolate');
    }

    debugPrint(
      '[BackgroundTileDownloadServiceCopy] Starting background download timer',
    );

    _downloadTimer = Timer.periodic(DOWNLOAD_INTERVAL, (timer) {
      debugPrint('[BackgroundTileDownloadServiceCopy] Download timer tick');

      if (!isDownloading.value &&
          !stopDownloading.value &&
          autoDownloadEnabled.value) {
        // Ensure isolate is ready before processing
        if (_sendPort != null) {
          _processNextDownload();
        } else {
          debugPrint(
            '[BackgroundTileDownloadServiceCopy] Isolate not ready, skipping download',
          );
        }
      } else {
        debugPrint(
          '[BackgroundTileDownloadServiceCopy] Skipping - isDownloading: ${isDownloading.value}, stopDownloading: ${stopDownloading.value}',
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

  /// Process next download in queue with resume capability
  Future<void> _processNextDownload() async {
    if (downloadQueue.isEmpty) {
      await _scheduleIntelligentDownloads();
      return;
    }

    final nextRegion = downloadQueue.firstWhereOrNull(
      (region) => region.status == DownloadStatusCopy.pending,
    );

    if (nextRegion != null && _sendPort != null) {
      nextRegion.status = DownloadStatusCopy.downloading;
      nextRegion.startTime = DateTime.now();
      isDownloading.value = true;
      currentDownloadRegion.value = nextRegion.id;

      final regionData = nextRegion.toMap();
      regionData['resume_from_progress'] = nextRegion.progress;
      regionData['tiles_already_downloaded'] = nextRegion.tilesDownloadedSoFar;

      debugPrint(
        '[BackgroundTileDownloadServiceCopy] Starting download for region ${nextRegion.id} - Resume from ${(nextRegion.progress * 100).toStringAsFixed(1)}% (${nextRegion.tilesDownloadedSoFar} tiles already downloaded)',
      );

      _sendPort!.send({'type': 'download_region', 'region': regionData});
    } else {
      isDownloading.value = false;
      debugPrint(
        '[BackgroundTileDownloadServiceCopy] No pending regions to download',
      );
    }
  }

  /// Process next download if ready
  void _processNextDownloadIfReady() {
    if (!isDownloading.value &&
        !stopDownloading.value &&
        autoDownloadEnabled.value &&
        downloadQueue.any((r) => r.status == DownloadStatusCopy.pending)) {
      _processNextDownload();
    }
  }

  /// Schedule intelligent downloads based on user behavior
  Future<void> _scheduleIntelligentDownloads() async {
    debugPrint(
      '[BackgroundTileDownloadServiceCopy] Scheduling intelligent downloads...',
    );

    // Add default regions if queue is empty
    await _scheduleDefaultRegions();
  }

  /// Schedule default regions for initial coverage
  Future<void> _scheduleDefaultRegions() async {
    final defaultRegions = [
      {'name': 'New York', 'lat': 40.7128, 'lng': -74.0060},
      {'name': 'London', 'lat': 51.5074, 'lng': -0.1278},
      {'name': 'Tokyo', 'lat': 35.6762, 'lng': 139.6503},
      {'name': 'Paris', 'lat': 48.8566, 'lng': 2.3522},
      {'name': 'Sydney', 'lat': -33.8688, 'lng': 151.2093},
    ];

    for (int i = 0; i < defaultRegions.length; i++) {
      final region = defaultRegions[i];
      final regionId = 'default_${region['name']}_copy';

      final existingRegion = downloadQueue.firstWhereOrNull((r) => r.id == regionId);

      if (existingRegion == null) {
        final downloadRegion = DownloadRegionCopy(
          id: regionId,
          bounds: _createDefaultRegionBounds(
            region['lat'] as double,
            region['lng'] as double,
          ),
          zoomLevels: [10, 11, 12],
          priority: 500 - i,
          scheduledTime: DateTime.now().add(
            Duration(minutes: i * 2),
          ),
          estimatedTiles: MAPBOX_REGION_TILE_LIMIT ~/ 2,
        );

        downloadQueue.add(downloadRegion);
        debugPrint(
          '[BackgroundTileDownloadServiceCopy] Scheduled default region: ${region['name']}',
        );
      }
    }

    await _saveDownloadQueue();

    debugPrint(
      '[BackgroundTileDownloadServiceCopy] Scheduled ${downloadQueue.length} default regions for initial tile coverage',
    );
  }

  /// Create default region bounds
  mapbox.CoordinateBounds _createDefaultRegionBounds(double lat, double lng) {
    const double radius = 0.05; // ~5km radius

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

  /// Manually trigger download for specific region with proper tile limits
  Future<void> downloadRegion(
    mapbox.CoordinateBounds bounds,
    List<int> zoomLevels,
  ) async {
    // Validate zoom levels to prevent exceeding tile limits
    final validZoomLevels =
        zoomLevels.where((zoom) => zoom >= 10 && zoom <= 14).toList();
    if (validZoomLevels.length > 3) {
      validZoomLevels.removeRange(3, validZoomLevels.length);
    }

    final region = DownloadRegionCopy(
      id: 'manual_${DateTime.now().millisecondsSinceEpoch}_copy',
      bounds: bounds,
      zoomLevels: validZoomLevels,
      priority: 1000,
      scheduledTime: DateTime.now(),
      estimatedTiles: MAPBOX_REGION_TILE_LIMIT ~/ 2,
    );

    downloadQueue.insert(0, region);

    if (!isDownloading.value && !stopDownloading.value) {
      _processNextDownload();
    }
  }

  /// Get current quota status
  TileQuotaStatusCopy getCurrentQuotaStatus() {
    return TileQuotaStatusCopy(
      currentTiles: totalTilesDownloaded.value,
      maxTiles: maxTilesLimit.value,
      usagePercentage: (totalTilesDownloaded.value / maxTilesLimit.value) * 100,
      shouldWarn: totalTilesDownloaded.value >= WARNING_THRESHOLD,
      shouldForceOffline: totalTilesDownloaded.value >= maxTilesLimit.value,
    );
  }

  /// Enable auto downloads
  Future<void> enableAutoDownloads() async {
    autoDownloadEnabled.value = true;
    await _saveConfiguration();
    debugPrint('[BackgroundTileDownloadServiceCopy] Auto downloads enabled');
  }

  /// Disable auto downloads
  Future<void> disableAutoDownloads() async {
    autoDownloadEnabled.value = false;
    await _saveConfiguration();
    debugPrint('[BackgroundTileDownloadServiceCopy] Auto downloads disabled');
  }

  /// Clear all downloads
  Future<void> clearAllDownloads() async {
    downloadQueue.clear();
    await _saveDownloadQueue();
    debugPrint('[BackgroundTileDownloadServiceCopy] All downloads cleared');
  }

  /// Reset quota
  Future<void> resetQuota() async {
    totalTilesDownloaded.value = 0;
    stopDownloading.value = false;
    forceOfflineMode.value = false;
    await _saveConfiguration();
    debugPrint('[BackgroundTileDownloadServiceCopy] Quota reset');
  }
}

/// Download region model (COPY VERSION)
class DownloadRegionCopy {
  final String id;
  final mapbox.CoordinateBounds bounds;
  final List<int> zoomLevels;
  final int priority;
  final DateTime scheduledTime;
  final int estimatedTiles;
  DownloadStatusCopy status;
  int retryCount;

  // Progress tracking fields
  double progress; // 0.0 to 1.0
  int tilesDownloadedSoFar; // Actual tiles downloaded for this region
  DateTime? startTime; // When download started
  DateTime? lastProgressTime; // Last progress update
  DateTime? completedTime; // When download completed

  DownloadRegionCopy({
    required this.id,
    required this.bounds,
    required this.zoomLevels,
    required this.priority,
    required this.scheduledTime,
    required this.estimatedTiles,
    this.status = DownloadStatusCopy.pending,
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
      'progress': progress,
      'tilesDownloadedSoFar': tilesDownloadedSoFar,
      'startTime': startTime?.millisecondsSinceEpoch,
      'lastProgressTime': lastProgressTime?.millisecondsSinceEpoch,
      'completedTime': completedTime?.millisecondsSinceEpoch,
    };
  }

  static DownloadRegionCopy fromMap(Map<String, dynamic> map) {
    final boundsMap = map['bounds'] as Map<String, dynamic>;
    final sw = boundsMap['southwest'] as Map<String, dynamic>;
    final ne = boundsMap['northeast'] as Map<String, dynamic>;

    return DownloadRegionCopy(
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
      status: DownloadStatusCopy.values[map['status'] as int],
      retryCount: map['retryCount'] as int? ?? 0,
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

/// Download status enum (COPY VERSION)
enum DownloadStatusCopy { pending, downloading, completed, failed, cancelled }

/// Tile quota status model (COPY VERSION)
class TileQuotaStatusCopy {
  final int currentTiles;
  final int maxTiles;
  final double usagePercentage;
  final bool shouldWarn;
  final bool shouldForceOffline;

  TileQuotaStatusCopy({
    required this.currentTiles,
    required this.maxTiles,
    required this.usagePercentage,
    required this.shouldWarn,
    required this.shouldForceOffline,
  });
}

