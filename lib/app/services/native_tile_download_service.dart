import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing native tile downloads on Android and iOS
/// Supports downloading up to 6000 tiles using native Mapbox SDKs
class NativeTileDownloadService extends GetxService {
  static NativeTileDownloadService get to => Get.find();

  // Method channel for native communication
  static const MethodChannel _channel = MethodChannel('com.spacetime.tile_download');

  // SharedPreferences keys
  static const String _keyDownloadedTileCount = 'native_offline_downloaded_tile_count';
  static const String _keyIsOfflineReady = 'native_offline_is_ready';
  static const String _keyLastDownloadDate = 'native_offline_last_download_date';

  // Configuration
  static const int _minZoom = 14;
  static const int _maxZoom = 14;
  static const int _requiredTileThreshold = 700;
  static const int _maxTiles = 6000; // Native allows up to 6000 tiles

  // Reactive state
  final RxInt downloadedTileCount = 0.obs;
  final RxInt totalTileCount = 0.obs;
  final RxBool isDownloading = false.obs;
  final RxBool isInitialized = false.obs;
  final RxString downloadStatus = ''.obs;
  final RxDouble downloadProgress = 0.0.obs;

  // Stream controllers
  final StreamController<String> _statusController = StreamController.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  @override
  void onInit() {
    super.onInit();
    _setupMethodCallHandler();
    _loadSavedTileCount();
  }

  @override
  void onClose() {
    _statusController.close();
    super.onClose();
  }

  /// Setup method call handler for native callbacks
  void _setupMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onProgress':
          final downloaded = call.arguments['downloaded'] as int;
          final total = call.arguments['total'] as int;
          _handleProgress(downloaded, total);
          break;
        case 'onZoomProgress':
          final downloaded = call.arguments['downloaded'] as int;
          final total = call.arguments['total'] as int;
          _handleZoomProgress(downloaded, total);
          break;
      }
    });
  }

  /// Handle download progress updates
  void _handleProgress(int downloaded, int total) {
    downloadedTileCount.value = downloaded;
    totalTileCount.value = total;
    
    if (total > 0) {
      downloadProgress.value = downloaded / total;
    }
    
    debugPrint('[NativeTileDownloadService] Progress: $downloaded/$total tiles');
    _statusController.add('Downloaded $downloaded/$total tiles');
  }

  /// Handle zoom level download progress updates
  void _handleZoomProgress(int downloaded, int total) {
    debugPrint('[NativeTileDownloadService] Zoom progress: $downloaded/$total tiles');
    _statusController.add('Downloading zoom tiles: $downloaded/$total');
  }

  /// Initialize the native tile store
  Future<bool> initialize() async {
    try {
      debugPrint('[NativeTileDownloadService] 🔧 Initializing native tile store...');
      debugPrint('[NativeTileDownloadService] 🔧 Calling native method: initializeTileStore');

      final result = await _channel.invokeMethod('initializeTileStore');

      debugPrint('[NativeTileDownloadService] 🔧 Native method returned: $result (type: ${result.runtimeType})');

      // Handle different result types
      bool success = false;
      if (result is Map) {
        debugPrint('[NativeTileDownloadService] 🔧 Result is a Map: $result');
        // Check if the map contains a 'success' key
        if (result.containsKey('success')) {
          success = result['success'] == true;
          debugPrint('[NativeTileDownloadService] 🔧 Map contains success key: $success');
        } else {
          debugPrint('[NativeTileDownloadService] ⚠️ Map does not contain success key');
        }
      } else if (result is bool) {
        debugPrint('[NativeTileDownloadService] 🔧 Result is a bool: $result');
        success = result;
      } else {
        debugPrint('[NativeTileDownloadService] ⚠️ Unexpected result type: ${result.runtimeType}');
      }

      isInitialized.value = success;

      if (isInitialized.value) {
        debugPrint('[NativeTileDownloadService] ✅ Native tile store initialized successfully');
      } else {
        debugPrint('[NativeTileDownloadService] ❌ Failed to initialize native tile store - result was: $result');
      }

      return isInitialized.value;
    } catch (e, stackTrace) {
      debugPrint('[NativeTileDownloadService] ❌ Error initializing native tile store');
      debugPrint('[NativeTileDownloadService] ❌ Error: $e');
      debugPrint('[NativeTileDownloadService] ❌ Stack trace: $stackTrace');
      isInitialized.value = false;
      return false;
    }
  }

  /// Download offline map tiles
  Future<Map<String, dynamic>?> downloadOfflineMap({
    required Map<String, dynamic> regionGeometry,
    int? minZoom,
    int? maxZoom,
  }) async {
    if (!isInitialized.value) {
      debugPrint('[NativeTileDownloadService] ❌ Not initialized, initializing now...');
      final initialized = await initialize();
      if (!initialized) {
        throw Exception('Failed to initialize native tile store');
      }
    }

    try {
      isDownloading.value = true;
      downloadStatus.value = 'Starting download...';
      
      debugPrint('[NativeTileDownloadService] 🗺️ Starting native tile download...');
      debugPrint('[NativeTileDownloadService] Zoom levels: ${minZoom ?? _minZoom}-${maxZoom ?? _maxZoom}');
      
      final result = await _channel.invokeMethod('downloadTiles', {
        'regionGeometry': regionGeometry,
        'minZoom': minZoom ?? _minZoom,
        'maxZoom': maxZoom ?? _maxZoom,
      });

      isDownloading.value = false;
      
      if (result is Map) {
        final resultMap = Map<String, dynamic>.from(result);
        final tilesDownloaded = resultMap['tilesDownloaded'] as int? ?? 0;
        
        debugPrint('[NativeTileDownloadService] ✅ Download completed: $tilesDownloaded tiles');
        
        // Save tile count
        await _saveTileCount(tilesDownloaded);
        
        downloadStatus.value = 'Download completed';
        return resultMap;
      }
      
      return null;
    } catch (e) {
      isDownloading.value = false;
      downloadStatus.value = 'Download failed';
      debugPrint('[NativeTileDownloadService] ❌ Download error: $e');
      rethrow;
    }
  }

  /// Download additional zoom level tiles
  Future<bool> downloadZoomTiles({
    required Map<String, dynamic> regionGeometry,
    required int zoomLevel,
  }) async {
    if (!isInitialized.value) {
      debugPrint('[NativeTileDownloadService] ❌ Not initialized');
      return false;
    }

    try {
      debugPrint('[NativeTileDownloadService] 🗺️ Starting zoom level $zoomLevel download...');
      
      final result = await _channel.invokeMethod('downloadZoomTiles', {
        'regionGeometry': regionGeometry,
        'zoomLevel': zoomLevel,
      });

      if (result is Map && result['success'] == true) {
        debugPrint('[NativeTileDownloadService] ✅ Zoom level $zoomLevel download completed');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('[NativeTileDownloadService] ❌ Zoom download error: $e');
      return false;
    }
  }

  /// Get current download progress
  Future<Map<String, int>> getDownloadProgress() async {
    try {
      final result = await _channel.invokeMethod('getDownloadProgress');
      if (result is Map) {
        return Map<String, int>.from(result);
      }
      return {'downloaded': 0, 'total': 0};
    } catch (e) {
      debugPrint('[NativeTileDownloadService] Error getting progress: $e');
      return {'downloaded': 0, 'total': 0};
    }
  }

  /// Cancel ongoing download
  Future<bool> cancelDownload() async {
    try {
      final result = await _channel.invokeMethod('cancelDownload');
      isDownloading.value = false;
      downloadStatus.value = 'Download cancelled';
      return result == true;
    } catch (e) {
      debugPrint('[NativeTileDownloadService] Error cancelling download: $e');
      return false;
    }
  }

  /// Check if download is in progress
  Future<bool> isDownloadInProgress() async {
    try {
      final result = await _channel.invokeMethod('isDownloadInProgress');
      return result == true;
    } catch (e) {
      debugPrint('[NativeTileDownloadService] Error checking download status: $e');
      return false;
    }
  }

  /// Save tile count to SharedPreferences
  Future<void> _saveTileCount(int count) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyDownloadedTileCount, count);
      await prefs.setString(_keyLastDownloadDate, DateTime.now().toIso8601String());
      downloadedTileCount.value = count;
      debugPrint('[NativeTileDownloadService] Saved tile count: $count');
    } catch (e) {
      debugPrint('[NativeTileDownloadService] Error saving tile count: $e');
    }
  }

  /// Load saved tile count from SharedPreferences
  Future<void> _loadSavedTileCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(_keyDownloadedTileCount) ?? 0;
      downloadedTileCount.value = count;
      debugPrint('[NativeTileDownloadService] Loaded tile count: $count');
    } catch (e) {
      debugPrint('[NativeTileDownloadService] Error loading tile count: $e');
    }
  }

  /// Check if offline tiles are available
  Future<bool> hasOfflineTiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = prefs.getInt(_keyDownloadedTileCount) ?? 0;
      return count >= _requiredTileThreshold;
    } catch (e) {
      debugPrint('[NativeTileDownloadService] Error checking offline tiles: $e');
      return false;
    }
  }

  /// Get saved tile count
  Future<int> getSavedTileCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_keyDownloadedTileCount) ?? 0;
    } catch (e) {
      debugPrint('[NativeTileDownloadService] Error getting saved tile count: $e');
      return 0;
    }
  }
}

