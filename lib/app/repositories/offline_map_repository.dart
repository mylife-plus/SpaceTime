import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repository for managing offline map metadata and preferences
class  OfflineMapRepository extends GetxService {
  static OfflineMapRepository get to => Get.find();

  SharedPreferences? _prefs;

  // Storage keys
  static const String _keyOfflineRegions = 'offline_regions';
  static const String _keyOfflinePreferences = 'offline_preferences';
  static const String _keyDownloadHistory = 'download_history';

  @override
  Future<void> onInit() async {
    super.onInit();
    await _initializeStorage();
  }

  /// Initialize shared preferences storage
  Future<void> _initializeStorage() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      debugPrint('[OfflineMapRepository] ✅ Storage initialized');
    } catch (e) {
      debugPrint('[OfflineMapRepository] ❌ Failed to initialize storage: $e');
    }
  }

  /// Save offline region metadata
  Future<void> saveOfflineRegion(OfflineRegionData regionData) async {
    try {
      final regions = await getOfflineRegions();

      // Remove existing region with same ID if it exists
      regions.removeWhere((region) => region.id == regionData.id);

      // Add the new/updated region
      regions.add(regionData);

      final regionsJson = regions.map((region) => region.toJson()).toList();
      await _prefs?.setString(_keyOfflineRegions, jsonEncode(regionsJson));

      debugPrint(
        '[OfflineMapRepository] ✅ Saved offline region: ${regionData.id}',
      );
    } catch (e) {
      debugPrint('[OfflineMapRepository] ❌ Failed to save offline region: $e');
    }
  }

  /// Get all saved offline regions
  Future<List<OfflineRegionData>> getOfflineRegions() async {
    try {
      final regionsString = _prefs?.getString(_keyOfflineRegions);
      if (regionsString == null) return [];

      final regionsJson = jsonDecode(regionsString) as List;
      return regionsJson
          .map((json) => OfflineRegionData.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('[OfflineMapRepository] ❌ Failed to get offline regions: $e');
      return [];
    }
  }

  /// Remove offline region metadata
  Future<void> removeOfflineRegion(String regionId) async {
    try {
      final regions = await getOfflineRegions();
      regions.removeWhere((region) => region.id == regionId);

      final regionsJson = regions.map((region) => region.toJson()).toList();
      await _prefs?.setString(_keyOfflineRegions, jsonEncode(regionsJson));

      debugPrint('[OfflineMapRepository] ✅ Removed offline region: $regionId');
    } catch (e) {
      debugPrint(
        '[OfflineMapRepository] ❌ Failed to remove offline region: $e',
      );
    }
  }

  /// Save offline preferences
  Future<void> saveOfflinePreferences(OfflinePreferences preferences) async {
    try {
      await _prefs?.setString(
        _keyOfflinePreferences,
        jsonEncode(preferences.toJson()),
      );
      debugPrint('[OfflineMapRepository] ✅ Saved offline preferences');
    } catch (e) {
      debugPrint(
        '[OfflineMapRepository] ❌ Failed to save offline preferences: $e',
      );
    }
  }

  /// Get offline preferences
  Future<OfflinePreferences> getOfflinePreferences() async {
    try {
      final prefsString = _prefs?.getString(_keyOfflinePreferences);
      if (prefsString == null) return OfflinePreferences.defaultPreferences();

      final prefsJson = jsonDecode(prefsString);
      return OfflinePreferences.fromJson(prefsJson);
    } catch (e) {
      debugPrint(
        '[OfflineMapRepository] ❌ Failed to get offline preferences: $e',
      );
      return OfflinePreferences.defaultPreferences();
    }
  }

  /// Save download history entry
  Future<void> saveDownloadHistory(DownloadHistoryEntry entry) async {
    try {
      final history = await getDownloadHistory();

      // Add new entry at the beginning
      history.insert(0, entry);

      // Keep only last 50 entries
      if (history.length > 50) {
        history.removeRange(50, history.length);
      }

      final historyJson = history.map((entry) => entry.toJson()).toList();
      await _prefs?.setString(_keyDownloadHistory, jsonEncode(historyJson));

      debugPrint('[OfflineMapRepository] ✅ Saved download history entry');
    } catch (e) {
      debugPrint(
        '[OfflineMapRepository] ❌ Failed to save download history: $e',
      );
    }
  }

  /// Get download history
  Future<List<DownloadHistoryEntry>> getDownloadHistory() async {
    try {
      final historyString = _prefs?.getString(_keyDownloadHistory);
      if (historyString == null) return [];

      final historyJson = jsonDecode(historyString) as List;
      return historyJson
          .map((json) => DownloadHistoryEntry.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('[OfflineMapRepository] ❌ Failed to get download history: $e');
      return [];
    }
  }

  /// Clear all offline data from storage
  Future<void> clearAllOfflineData() async {
    try {
      await _prefs?.remove(_keyOfflineRegions);
      await _prefs?.remove(_keyDownloadHistory);
      debugPrint(
        '[OfflineMapRepository] ✅ Cleared all offline data from storage',
      );
    } catch (e) {
      debugPrint('[OfflineMapRepository] ❌ Failed to clear offline data: $e');
    }
  }
}

/// Data model for offline region metadata
class OfflineRegionData {
  final String id;
  final String name;
  final Map<String, dynamic> geometry;
  final String styleUri;
  final int minZoom;
  final int maxZoom;
  final DateTime createdAt;
  final DateTime? lastUpdated;
  final int tileCount;
  final double sizeInMB;
  final bool isComplete;

  OfflineRegionData({
    required this.id,
    required this.name,
    required this.geometry,
    required this.styleUri,
    required this.minZoom,
    required this.maxZoom,
    required this.createdAt,
    this.lastUpdated,
    required this.tileCount,
    required this.sizeInMB,
    required this.isComplete,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'geometry': geometry,
      'styleUri': styleUri,
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated?.toIso8601String(),
      'tileCount': tileCount,
      'sizeInMB': sizeInMB,
      'isComplete': isComplete,
    };
  }

  factory OfflineRegionData.fromJson(Map<String, dynamic> json) {
    return OfflineRegionData(
      id: json['id'],
      name: json['name'],
      geometry: json['geometry'],
      styleUri: json['styleUri'],
      minZoom: json['minZoom'],
      maxZoom: json['maxZoom'],
      createdAt: DateTime.parse(json['createdAt']),
      lastUpdated:
          json['lastUpdated'] != null
              ? DateTime.parse(json['lastUpdated'])
              : null,
      tileCount: json['tileCount'],
      sizeInMB: json['sizeInMB'].toDouble(),
      isComplete: json['isComplete'],
    );
  }
}

/// Data model for offline preferences
class OfflinePreferences {
  final bool autoDownloadOnWifi;
  final bool enableOfflineModeAutomatically;
  final int maxZoomLevel;
  final int minZoomLevel;
  final double maxDownloadSizeMB;
  final bool downloadOnlyOnWifi;

  OfflinePreferences({
    required this.autoDownloadOnWifi,
    required this.enableOfflineModeAutomatically,
    required this.maxZoomLevel,
    required this.minZoomLevel,
    required this.maxDownloadSizeMB,
    required this.downloadOnlyOnWifi,
  });

  static OfflinePreferences defaultPreferences() {
    return OfflinePreferences(
      autoDownloadOnWifi: true,
      enableOfflineModeAutomatically: false,
      maxZoomLevel: 16,
      minZoomLevel: 0,
      maxDownloadSizeMB: 500.0,
      downloadOnlyOnWifi: true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'autoDownloadOnWifi': autoDownloadOnWifi,
      'enableOfflineModeAutomatically': enableOfflineModeAutomatically,
      'maxZoomLevel': maxZoomLevel,
      'minZoomLevel': minZoomLevel,
      'maxDownloadSizeMB': maxDownloadSizeMB,
      'downloadOnlyOnWifi': downloadOnlyOnWifi,
    };
  }

  factory OfflinePreferences.fromJson(Map<String, dynamic> json) {
    return OfflinePreferences(
      autoDownloadOnWifi: json['autoDownloadOnWifi'] ?? true,
      enableOfflineModeAutomatically:
          json['enableOfflineModeAutomatically'] ?? false,
      maxZoomLevel: json['maxZoomLevel'] ?? 16,
      minZoomLevel: json['minZoomLevel'] ?? 0,
      maxDownloadSizeMB: json['maxDownloadSizeMB']?.toDouble() ?? 500.0,
      downloadOnlyOnWifi: json['downloadOnlyOnWifi'] ?? true,
    );
  }
}

/// Data model for download history entries
class DownloadHistoryEntry {
  final String regionId;
  final String regionName;
  final DateTime downloadDate;
  final int tilesDownloaded;
  final double sizeInMB;
  final Duration downloadDuration;
  final bool wasSuccessful;
  final String? errorMessage;

  DownloadHistoryEntry({
    required this.regionId,
    required this.regionName,
    required this.downloadDate,
    required this.tilesDownloaded,
    required this.sizeInMB,
    required this.downloadDuration,
    required this.wasSuccessful,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() {
    return {
      'regionId': regionId,
      'regionName': regionName,
      'downloadDate': downloadDate.toIso8601String(),
      'tilesDownloaded': tilesDownloaded,
      'sizeInMB': sizeInMB,
      'downloadDurationMs': downloadDuration.inMilliseconds,
      'wasSuccessful': wasSuccessful,
      'errorMessage': errorMessage,
    };
  }

  factory DownloadHistoryEntry.fromJson(Map<String, dynamic> json) {
    return DownloadHistoryEntry(
      regionId: json['regionId'],
      regionName: json['regionName'],
      downloadDate: DateTime.parse(json['downloadDate']),
      tilesDownloaded: json['tilesDownloaded'],
      sizeInMB: json['sizeInMB'].toDouble(),
      downloadDuration: Duration(milliseconds: json['downloadDurationMs']),
      wasSuccessful: json['wasSuccessful'],
      errorMessage: json['errorMessage'],
    );
  }
}
