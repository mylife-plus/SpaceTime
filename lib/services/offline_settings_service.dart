import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import '../app/modules/map/controllers/map_controller.dart';

class OfflineSettingsService {
  static OfflineSettingsService? _instance;
  static OfflineSettingsService get instance =>
      _instance ??= OfflineSettingsService._();

  OfflineSettingsService._();

  // SharedPreferences keys
  static const String _forceOfflineModeKey = 'force_offline_mode';
  static const String _tilesDownloadedKey = 'tiles_downloaded_regions';
  static const String _lastTileCheckKey = 'last_tile_check';
  static const String _worldTilesDownloadedKey = 'world_tiles_downloaded';
  static const String _offlineCachePathKey = 'offline_cache_path';

  SharedPreferences? _prefs;
  bool _isInitialized = false;

  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
      debugPrint('✅ OfflineSettingsService initialized');
    } catch (e) {
      debugPrint('❌ Error initializing OfflineSettingsService: $e');
    }
  }

  /// Check if user has forced offline mode
  Future<bool> isForceOfflineEnabled() async {
    await _ensureInitialized();
    return _prefs?.getBool(_forceOfflineModeKey) ?? false;
  }

  /// Set force offline mode preference
  Future<void> setForceOfflineMode(bool enabled) async {
    await _ensureInitialized();
    await _prefs?.setBool(_forceOfflineModeKey, enabled);
    debugPrint('🔒 Force offline mode ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Get list of downloaded regions
  Future<List<String>> getDownloadedRegions() async {
    await _ensureInitialized();
    return _prefs?.getStringList(_tilesDownloadedKey) ?? [];
  }

  /// Mark a region as downloaded
  Future<void> markRegionDownloaded(String regionId) async {
    await _ensureInitialized();
    final regions = await getDownloadedRegions();
    if (!regions.contains(regionId)) {
      regions.add(regionId);
      await _prefs?.setStringList(_tilesDownloadedKey, regions);
      debugPrint('📦 Region marked as downloaded: $regionId');
    }
  }

  /// Check if world base tiles are downloaded
  Future<bool> areWorldTilesDownloaded() async {
    await _ensureInitialized();
    return _prefs?.getBool(_worldTilesDownloadedKey) ?? false;
  }

  /// Mark world tiles as downloaded
  Future<void> markWorldTilesDownloaded(bool downloaded) async {
    await _ensureInitialized();
    await _prefs?.setBool(_worldTilesDownloadedKey, downloaded);
    debugPrint(
      '🌍 World tiles marked as ${downloaded ? 'downloaded' : 'not downloaded'}',
    );
  }

  /// Check if basic tiles are available for offline use
  Future<bool> areBasicTilesDownloaded() async {
    await _ensureInitialized();

    // Check if world tiles are downloaded
    if (await areWorldTilesDownloaded()) {
      return true;
    }

    // Check if any regional tiles are downloaded
    final regions = await getDownloadedRegions();
    if (regions.isNotEmpty) {
      return true;
    }

    // Check with MapController if tiles are available
    try {
      if (Get.isRegistered<MapController>()) {
        final mapController = Get.find<MapController>();
        return await mapController.isOfflineDataAvailable();
      }
    } catch (e) {
      debugPrint('⚠️ Could not check MapController tile availability: $e');
    }

    return false;
  }

  /// Get offline cache path
  Future<String?> getOfflineCachePath() async {
    await _ensureInitialized();
    return _prefs?.getString(_offlineCachePathKey);
  }

  /// Set offline cache path
  Future<void> setOfflineCachePath(String path) async {
    await _ensureInitialized();
    await _prefs?.setString(_offlineCachePathKey, path);
  }

  /// Smart offline mode detection
  Future<OfflineMode> determineOfflineMode() async {
    await _ensureInitialized();

    // Priority 1: User forced offline mode
    if (await isForceOfflineEnabled()) {
      return OfflineMode(
        isOffline: true,
        reason: 'User preference',
        priority: OfflineModePriority.userForced,
      );
    }

    // Priority 2: Check if tiles are available
    if (await areBasicTilesDownloaded()) {
      return OfflineMode(
        isOffline: true,
        reason: 'Tiles available',
        priority: OfflineModePriority.tilesAvailable,
      );
    }

    // Priority 3: Network connectivity check (will be handled by caller)
    return OfflineMode(
      isOffline: false,
      reason: 'Network check required',
      priority: OfflineModePriority.networkCheck,
    );
  }

  /// Update last tile check timestamp
  Future<void> updateLastTileCheck() async {
    await _ensureInitialized();
    await _prefs?.setInt(
      _lastTileCheckKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Get last tile check timestamp
  Future<DateTime?> getLastTileCheck() async {
    await _ensureInitialized();
    final timestamp = _prefs?.getInt(_lastTileCheckKey);
    return timestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : null;
  }

  /// Clear all offline settings
  Future<void> clearAllSettings() async {
    await _ensureInitialized();
    await _prefs?.remove(_forceOfflineModeKey);
    await _prefs?.remove(_tilesDownloadedKey);
    await _prefs?.remove(_lastTileCheckKey);
    await _prefs?.remove(_worldTilesDownloadedKey);
    await _prefs?.remove(_offlineCachePathKey);
    debugPrint('🗑️ All offline settings cleared');
  }

  /// Ensure service is initialized
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }
}

/// Offline mode information
class OfflineMode {
  final bool isOffline;
  final String reason;
  final OfflineModePriority priority;

  OfflineMode({
    required this.isOffline,
    required this.reason,
    required this.priority,
  });

  @override
  String toString() =>
      'OfflineMode(isOffline: $isOffline, reason: $reason, priority: $priority)';
}

/// Priority levels for offline mode determination
enum OfflineModePriority {
  userForced, // Highest priority - user explicitly enabled offline mode
  forceOffline, // System forced due to tile quota reached
  tilesAvailable, // Medium priority - tiles are available locally
  networkCheck, // Lowest priority - fallback to network connectivity check
}
