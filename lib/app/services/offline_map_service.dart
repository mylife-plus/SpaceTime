import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing offline map downloads and tile storage
class OfflineMapService extends GetxService {
  static OfflineMapService get to => Get.find();

  // SharedPreferences keys
  static const String _keyDownloadedTileCount = 'offline_downloaded_tile_count';
  static const String _keyIsOfflineReady = 'offline_is_ready';
  static const String _keyLastDownloadDate = 'offline_last_download_date';

  // Stream controllers for progress tracking
  final StreamController<double> _stylePackProgress =
      StreamController.broadcast();
  final StreamController<double> _tileRegionLoadProgress =
      StreamController.broadcast();
  final StreamController<String> _downloadStatus = StreamController.broadcast();

  // Mapbox offline components
  TileStore? _tileStore;
  OfflineManager? _offlineManager;

  // Configuration
  static const String _tileRegionId = "spacetime-tile-region";
  static const int _minZoom = 14;  // Only download zoom level 14
  static const int _maxZoom = 14; // Only download zoom level 14
  static const int _requiredTileThreshold = 700; // Require 700 tiles for offline mode

  // Reactive state
  final RxBool isInitialized = false.obs;
  final RxBool isDownloading = false.obs;
  final RxBool isOfflineReady = false.obs;
  final RxDouble stylePackProgress = 0.0.obs;
  final RxDouble tileRegionProgress = 0.0.obs;
  final RxString downloadStatusText = "Ready to download".obs;
  final RxInt downloadedTileCount = 0.obs;

  // Getters for streams
  Stream<double> get stylePackProgressStream => _stylePackProgress.stream;
  Stream<double> get tileRegionProgressStream => _tileRegionLoadProgress.stream;
  Stream<String> get downloadStatusStream => _downloadStatus.stream;

  @override
  Future<void> onInit() async {
    super.onInit();
    await _initializeOfflineComponents();
  }

  @override
  void onClose() {
    _stylePackProgress.close();
    _tileRegionLoadProgress.close();
    _downloadStatus.close();
    super.onClose();
  }

  /// Initialize offline map components
  Future<void> _initializeOfflineComponents() async {
    try {
      debugPrint('[OfflineMapService] 🔧 Initializing offline components...');

      _offlineManager = await OfflineManager.create();
      _tileStore = await TileStore.createDefault();

      // Reset disk quota to default value
      _tileStore?.setDiskQuota(4000000000);

      isInitialized.value = true;
      debugPrint(
        '[OfflineMapService] ✅ Offline components initialized successfully',
      );

      // Check if we already have sufficient tiles downloaded
      await _checkExistingTiles();
    } catch (e) {
      debugPrint(
        '[OfflineMapService] ❌ Failed to initialize offline components: $e',
      );
      _updateDownloadStatus("Failed to initialize: $e");
    }
  }

  /// Check if we already have sufficient tiles for offline use
  Future<void> _checkExistingTiles() async {
    try {
      // Load tile count from SharedPreferences
      await _loadTileCountFromPrefs();

      if (downloadedTileCount.value >= _requiredTileThreshold) {
        isOfflineReady.value = true;
        _updateDownloadStatus(
          "Offline ready (${downloadedTileCount.value} tiles)",
        );
        debugPrint('[OfflineMapService] ✅ Sufficient tiles already downloaded: ${downloadedTileCount.value}');
      } else {
        _updateDownloadStatus(
          "Need to download tiles (${downloadedTileCount.value}/$_requiredTileThreshold)",
        );
        debugPrint('[OfflineMapService] ⚠️ Insufficient tiles: ${downloadedTileCount.value}/$_requiredTileThreshold');
      }
    } catch (e) {
      debugPrint('[OfflineMapService] ⚠️ Error checking existing tiles: $e');
    }
  }

  /// Start downloading offline map data for a specific region
  Future<void> downloadOfflineMap({
    required Map<String, dynamic> regionGeometry,
    String styleUri = MapboxStyles.MAPBOX_STREETS,
  }) async {
    if (!isInitialized.value) {
      debugPrint('[OfflineMapService] ❌ Service not initialized');
      return;
    }

    if (isDownloading.value) {
      debugPrint('[OfflineMapService] ⚠️ Download already in progress');
      return;
    }

    try {
      isDownloading.value = true;
      _updateDownloadStatus("Starting download...");

      // Reset progress
      stylePackProgress.value = 0.0;
      tileRegionProgress.value = 0.0;

      // Start downloads concurrently
      await Future.wait([
        _downloadStylePack(styleUri),
        _downloadTileRegion(regionGeometry, styleUri),
      ]);

      debugPrint('[OfflineMapService] ✅ Offline map download completed');
    } catch (e) {
      debugPrint('[OfflineMapService] ❌ Download failed: $e');
      _updateDownloadStatus("Download failed: $e");
    } finally {
      isDownloading.value = false;
    }
  }

  /// Download style pack for offline use
  Future<void> _downloadStylePack(String styleUri) async {
    try {
      debugPrint('[OfflineMapService] 📦 Starting style pack download...');

      final stylePackLoadOptions = StylePackLoadOptions(
        glyphsRasterizationMode:
            GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY,
        metadata: {
          "tag": "spacetime-offline",
          "timestamp": DateTime.now().toIso8601String(),
        },
        acceptExpired: false,
      );

      final completer = Completer<void>();

      _offlineManager
          ?.loadStylePack(styleUri, stylePackLoadOptions, (progress) {
            final percentage =
                progress.completedResourceCount /
                progress.requiredResourceCount;
            stylePackProgress.value = percentage;

            if (!_stylePackProgress.isClosed) {
              _stylePackProgress.sink.add(percentage);
            }

            debugPrint(
              '[OfflineMapService] 📦 Style pack progress: ${(percentage * 100).toStringAsFixed(1)}%',
            );
            _updateDownloadStatus(
              "Downloading style pack: ${(percentage * 100).toStringAsFixed(1)}%",
            );
          })
          .then((value) {
            stylePackProgress.value = 1.0;
            if (!_stylePackProgress.isClosed) {
              _stylePackProgress.sink.add(1.0);
            }
            debugPrint('[OfflineMapService] ✅ Style pack download completed');
            completer.complete();
          })
          .catchError((error) {
            debugPrint(
              '[OfflineMapService] ❌ Style pack download failed: $error',
            );
            completer.completeError(error);
          });

      await completer.future;
    } catch (e) {
      debugPrint('[OfflineMapService] ❌ Style pack download error: $e');
      rethrow;
    }
  }

  /// Download tile region for offline use
  Future<void> _downloadTileRegion(
    Map<String, dynamic> regionGeometry,
    String styleUri,
  ) async {
    try {
      debugPrint('[OfflineMapService] 🗺️ Starting tile region download...');
      debugPrint('[OfflineMapService] Region geometry: $regionGeometry');
      debugPrint('[OfflineMapService] Style URI: $styleUri');
      debugPrint('[OfflineMapService] Zoom range: $_minZoom - $_maxZoom');
      debugPrint('[OfflineMapService] TileStore available: ${_tileStore != null}');

      final tileRegionLoadOptions = TileRegionLoadOptions(
        geometry: regionGeometry,
        descriptorsOptions: [
          TilesetDescriptorOptions(
            styleURI: styleUri,
            minZoom: _minZoom,
            maxZoom: _maxZoom,
          ),
        ],
        acceptExpired: true,
        networkRestriction: NetworkRestriction.NONE,
      );

      debugPrint('[OfflineMapService] TileRegionLoadOptions created successfully');
      final completer = Completer<void>();

      debugPrint('[OfflineMapService] Calling loadTileRegion with ID: $_tileRegionId');
      _tileStore
          ?.loadTileRegion(_tileRegionId, tileRegionLoadOptions, (progress) {
            debugPrint('[OfflineMapService] 📊 Progress callback called: ${progress.completedResourceCount}/${progress.requiredResourceCount}');
            final percentage =
                progress.completedResourceCount /
                progress.requiredResourceCount;
            tileRegionProgress.value = percentage;
            downloadedTileCount.value = progress.completedResourceCount;

            if (!_tileRegionLoadProgress.isClosed) {
              _tileRegionLoadProgress.sink.add(percentage);
            }

            debugPrint(
              '[OfflineMapService] 🗺️ Tile region progress: ${(percentage * 100).toStringAsFixed(1)}% (${progress.completedResourceCount}/${progress.requiredResourceCount} tiles)',
            );
            _updateDownloadStatus(
              "Downloading tiles: ${progress.completedResourceCount}/${progress.requiredResourceCount} (${(percentage * 100).toStringAsFixed(1)}%)",
            );
          })
          .then((value) {
            tileRegionProgress.value = 1.0;
            if (!_tileRegionLoadProgress.isClosed) {
              _tileRegionLoadProgress.sink.add(1.0);
            }

            // Check if we have enough tiles for offline use
            if (downloadedTileCount.value >= _requiredTileThreshold) {
              isOfflineReady.value = true;
              _updateDownloadStatus(
                "Offline ready! Downloaded ${downloadedTileCount.value} tiles",
              );
              debugPrint(
                '[OfflineMapService] ✅ Sufficient tiles downloaded for offline use',
              );
            } else {
              _updateDownloadStatus(
                "Download complete but insufficient tiles: ${downloadedTileCount.value}/$_requiredTileThreshold",
              );
              debugPrint(
                '[OfflineMapService] ⚠️ Downloaded ${downloadedTileCount.value} tiles, need $_requiredTileThreshold for offline use',
              );
            }

            // Save tile count to SharedPreferences
            _saveTileCountToPrefs().then((_) {
              debugPrint('[OfflineMapService] ✅ Tile region download completed');
              completer.complete();
            }).catchError((error) {
              debugPrint('[OfflineMapService] ⚠️ Failed to save tile count, but download completed: $error');
              completer.complete(); // Still complete even if save fails
            });
          })
          .catchError((error) {
            debugPrint(
              '[OfflineMapService] ❌ Tile region download failed: $error',
            );
            completer.completeError(error);
          });

      await completer.future;
    } catch (e) {
      debugPrint('[OfflineMapService] ❌ Tile region download error: $e');
      rethrow;
    }
  }

  /// Enable offline mode (disconnect from network for map tiles)
  Future<void> enableOfflineMode() async {
    if (!isOfflineReady.value) {
      debugPrint(
        '[OfflineMapService] ⚠️ Cannot enable offline mode - insufficient tiles downloaded',
      );
      return;
    }

    try {
      await OfflineSwitch.shared.setMapboxStackConnected(false);
      debugPrint('[OfflineMapService] 🔌 Offline mode enabled');
      _updateDownloadStatus("Offline mode enabled");
    } catch (e) {
      debugPrint('[OfflineMapService] ❌ Failed to enable offline mode: $e');
    }
  }

  /// Disable offline mode (reconnect to network)
  Future<void> disableOfflineMode() async {
    try {
      await OfflineSwitch.shared.setMapboxStackConnected(true);
      debugPrint('[OfflineMapService] 🌐 Online mode enabled');
      _updateDownloadStatus("Online mode enabled");
    } catch (e) {
      debugPrint('[OfflineMapService] ❌ Failed to disable offline mode: $e');
    }
  }

  /// Clean up downloaded tiles and style packs
  Future<void> clearOfflineData() async {
    try {
      debugPrint('[OfflineMapService] 🧹 Clearing offline data...');

      // Remove the tile region
      await _tileStore?.removeRegion(_tileRegionId);

      // Set disk quota to zero to fully evict tiles
      _tileStore?.setDiskQuota(0);

      // Remove style pack
      await _offlineManager?.removeStylePack(MapboxStyles.MAPBOX_STREETS);

      // Reset state
      isOfflineReady.value = false;
      downloadedTileCount.value = 0;
      stylePackProgress.value = 0.0;
      tileRegionProgress.value = 0.0;

      // Reset disk quota to default
      _tileStore?.setDiskQuota(null);

      // Save cleared state to SharedPreferences
      await _saveTileCountToPrefs();

      _updateDownloadStatus("Offline data cleared");
      debugPrint('[OfflineMapService] ✅ Offline data cleared successfully');
    } catch (e) {
      debugPrint('[OfflineMapService] ❌ Failed to clear offline data: $e');
      _updateDownloadStatus("Failed to clear data: $e");
    }
  }

  /// Update download status and broadcast to listeners
  void _updateDownloadStatus(String status) {
    downloadStatusText.value = status;
    if (!_downloadStatus.isClosed) {
      _downloadStatus.sink.add(status);
    }
  }

  /// Load tile count from SharedPreferences
  Future<void> _loadTileCountFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTileCount = prefs.getInt(_keyDownloadedTileCount) ?? 0;
      final savedIsOfflineReady = prefs.getBool(_keyIsOfflineReady) ?? false;

      downloadedTileCount.value = savedTileCount;
      isOfflineReady.value = savedIsOfflineReady;

      debugPrint('[OfflineMapService] 📱 Loaded from SharedPreferences: $savedTileCount tiles, offline ready: $savedIsOfflineReady');
    } catch (e) {
      debugPrint('[OfflineMapService] ❌ Failed to load tile count from SharedPreferences: $e');
      // Fallback to default values
      downloadedTileCount.value = 0;
      isOfflineReady.value = false;
    }
  }

  /// Save tile count to SharedPreferences
  Future<void> _saveTileCountToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyDownloadedTileCount, downloadedTileCount.value);
      await prefs.setBool(_keyIsOfflineReady, isOfflineReady.value);
      await prefs.setString(_keyLastDownloadDate, DateTime.now().toIso8601String());

      debugPrint('[OfflineMapService] 💾 Saved to SharedPreferences: ${downloadedTileCount.value} tiles, offline ready: ${isOfflineReady.value}');
    } catch (e) {
      debugPrint('[OfflineMapService] ❌ Failed to save tile count to SharedPreferences: $e');
    }
  }

  /// Public method to save tile count
  Future<void> saveTileCount() async {
    await _saveTileCountToPrefs();
  }

  /// Get TileStore instance
  TileStore? getTileStore() {
    return _tileStore;
  }

  /// Get OfflineManager instance
  OfflineManager? getOfflineManager() {
    return _offlineManager;
  }

  /// Download zoom level 14 tiles specifically
  Future<void> downloadZoom10Tiles({
    required Map<String, dynamic> regionGeometry,
    required Function(int downloaded, int total) onProgress,
    required Function() onComplete,
    required Function(dynamic error) onError,
  }) async {
    try {
      debugPrint('[OfflineMapService] 🗺️ Starting zoom level 14 tile download...');

      final tileRegionId = "spacetime-zoom14-tiles";

      final tileRegionLoadOptions = TileRegionLoadOptions(
        geometry: regionGeometry,
        descriptorsOptions: [
          TilesetDescriptorOptions(
            styleURI: MapboxStyles.MAPBOX_STREETS,
            minZoom: 14,
            maxZoom: 14,
          ),
        ],
        acceptExpired: false,
        networkRestriction: NetworkRestriction.NONE,
      );

      final completer = Completer<void>();

      _tileStore
          ?.loadTileRegion(tileRegionId, tileRegionLoadOptions, (progress) {
            final downloaded = progress.completedResourceCount;
            final total = progress.requiredResourceCount;

            debugPrint('[OfflineMapService] 🗺️ Zoom 14 progress: $downloaded/$total tiles');

            // Update the main tile count
            downloadedTileCount.value += downloaded;

            onProgress(downloaded, total);
          })
          .then((value) {
            debugPrint('[OfflineMapService] ✅ Zoom 14 tile download completed');
            onComplete();
            completer.complete();
          })
          .catchError((error) {
            debugPrint('[OfflineMapService] ❌ Zoom 14 tile download failed: $error');
            // Even on error, save what we have
            _saveTileCountToPrefs();
            onError(error);
            completer.complete(); // Complete anyway to move forward
          });

      await completer.future;
    } catch (e) {
      debugPrint('[OfflineMapService] ❌ Zoom 14 download error: $e');
      // Save whatever was downloaded
      await _saveTileCountToPrefs();
      onError(e);
    }
  }

  /// Get current offline status summary
  Map<String, dynamic> getOfflineStatus() {
    return {
      'isInitialized': isInitialized.value,
      'isDownloading': isDownloading.value,
      'isOfflineReady': isOfflineReady.value,
      'downloadedTileCount': downloadedTileCount.value,
      'requiredTileThreshold': _requiredTileThreshold,
      'stylePackProgress': stylePackProgress.value,
      'tileRegionProgress': tileRegionProgress.value,
      'statusText': downloadStatusText.value,
    };
  }
}
