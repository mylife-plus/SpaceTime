import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class OfflineLocationService {
  static const MethodChannel _channel = MethodChannel(
    'offline_location_service',
  );

  static OfflineLocationService? _instance;
  static OfflineLocationService get instance =>
      _instance ??= OfflineLocationService._();

  OfflineLocationService._();

  /// Initialize the offline location service
  Future<bool> initialize() async {
    try {
      final result = await _channel.invokeMethod('initialize');
      return result == true;
    } catch (e) {
      debugPrint('Error initializing offline location service: $e');
      return false;
    }
  }

  /// Search for locations using offline Mapbox data
  Future<List<OfflineLocationResult>> searchLocations(
    String query, {
    double? latitude,
    double? longitude,
    double? radius,
    int limit = 10,
  }) async {
    try {
      final Map<String, dynamic> params = {'query': query, 'limit': limit};

      if (latitude != null && longitude != null) {
        params['latitude'] = latitude;
        params['longitude'] = longitude;
      }

      if (radius != null) {
        params['radius'] = radius;
      }

      final result = await _channel.invokeMethod('searchLocations', params);

      if (result is List) {
        return result
            .map(
              (item) => OfflineLocationResult.fromMap(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList();
      }

      return [];
    } catch (e) {
      debugPrint('Error searching offline locations: $e');
      return [];
    }
  }

  /// Reverse geocode coordinates to get location information
  Future<OfflineLocationResult?> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    try {
      final result = await _channel.invokeMethod('reverseGeocode', {
        'latitude': latitude,
        'longitude': longitude,
      });

      if (result != null) {
        return OfflineLocationResult.fromMap(Map<String, dynamic>.from(result));
      }

      return null;
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      return null;
    }
  }

  /// Check if offline data is available for a region
  Future<bool> isOfflineDataAvailable(double latitude, double longitude) async {
    try {
      final result = await _channel.invokeMethod('isOfflineDataAvailable', {
        'latitude': latitude,
        'longitude': longitude,
      });
      return result == true;
    } catch (e) {
      debugPrint('Error checking offline data availability: $e');
      return false;
    }
  }

  /// Download offline region data
  Future<bool> downloadOfflineRegion({
    required String regionId,
    required double northLatitude,
    required double southLatitude,
    required double eastLongitude,
    required double westLongitude,
    required double minZoom,
    required double maxZoom,
  }) async {
    try {
      final result = await _channel.invokeMethod('downloadOfflineRegion', {
        'regionId': regionId,
        'northLatitude': northLatitude,
        'southLatitude': southLatitude,
        'eastLongitude': eastLongitude,
        'westLongitude': westLongitude,
        'minZoom': minZoom,
        'maxZoom': maxZoom,
      });
      return result == true;
    } catch (e) {
      debugPrint('Error downloading offline region: $e');
      return false;
    }
  }

  /// Get list of downloaded offline regions
  Future<List<OfflineRegion>> getOfflineRegions() async {
    try {
      final result = await _channel.invokeMethod('getOfflineRegions');

      if (result is List) {
        return result
            .map(
              (item) => OfflineRegion.fromMap(Map<String, dynamic>.from(item)),
            )
            .toList();
      }

      return [];
    } catch (e) {
      debugPrint('Error getting offline regions: $e');
      return [];
    }
  }
}

class OfflineLocationResult {
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final String? country;
  final String? region;
  final String? city;
  final String? postcode;
  final double? relevance;

  OfflineLocationResult({
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    this.country,
    this.region,
    this.city,
    this.postcode,
    this.relevance,
  });

  factory OfflineLocationResult.fromMap(Map<String, dynamic> map) {
    return OfflineLocationResult(
      name: map['name'] ?? '',
      address: map['address'],
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      country: map['country'],
      region: map['region'],
      city: map['city'],
      postcode: map['postcode'],
      relevance: map['relevance']?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'country': country,
      'region': region,
      'city': city,
      'postcode': postcode,
      'relevance': relevance,
    };
  }

  @override
  String toString() {
    return 'OfflineLocationResult(name: $name, city: $city, country: $country, lat: $latitude, lng: $longitude)';
  }
}

class OfflineRegion {
  final String id;
  final String name;
  final double northLatitude;
  final double southLatitude;
  final double eastLongitude;
  final double westLongitude;
  final double minZoom;
  final double maxZoom;
  final int downloadState;
  final double downloadProgress;

  OfflineRegion({
    required this.id,
    required this.name,
    required this.northLatitude,
    required this.southLatitude,
    required this.eastLongitude,
    required this.westLongitude,
    required this.minZoom,
    required this.maxZoom,
    required this.downloadState,
    required this.downloadProgress,
  });

  factory OfflineRegion.fromMap(Map<String, dynamic> map) {
    return OfflineRegion(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      northLatitude: (map['northLatitude'] ?? 0.0).toDouble(),
      southLatitude: (map['southLatitude'] ?? 0.0).toDouble(),
      eastLongitude: (map['eastLongitude'] ?? 0.0).toDouble(),
      westLongitude: (map['westLongitude'] ?? 0.0).toDouble(),
      minZoom: (map['minZoom'] ?? 0.0).toDouble(),
      maxZoom: (map['maxZoom'] ?? 0.0).toDouble(),
      downloadState: map['downloadState'] ?? 0,
      downloadProgress: (map['downloadProgress'] ?? 0.0).toDouble(),
    );
  }

  bool get isDownloaded => downloadState == 2; // STATE_COMPLETE
  bool get isDownloading => downloadState == 1; // STATE_ACTIVE
}
