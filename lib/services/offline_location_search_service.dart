import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:spacetime/services/world_locations_service.dart' as world;

/// Comprehensive offline location search service with native integrations
class OfflineLocationSearchService {
  static const MethodChannel _channel = MethodChannel(
    'com.spacetime.location_search',
  );
  static OfflineLocationSearchService? _instance;

  static OfflineLocationSearchService get instance {
    _instance ??= OfflineLocationSearchService._internal();
    return _instance!;
  }

  OfflineLocationSearchService._internal();

  // Local database of locations
  List<LocationSearchResult> _locations = [];
  bool _isInitialized = false;

  /// Initialize the offline search service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🔍 Initializing OfflineLocationSearchService...');

      // Prefer shared WorldLocationsService (single CSV parse in isolate) when available.
      final worldSvc = world.WorldLocationsService.instance;
      await worldSvc.initialize();
      if (worldSvc.isLoaded) {
        _locations = [];
        _isInitialized = true;
        debugPrint(
          '✅ OfflineLocationSearchService ready (WorldLocationsService, no duplicate CSV)',
        );
        return;
      }

      await _loadOfflineDatabase();
      _isInitialized = true;
      debugPrint('✅ OfflineLocationSearchService initialized successfully');
      debugPrint('   Offline locations: ${_locations.length}');
    } catch (e) {
      debugPrint('❌ Error initializing OfflineLocationSearchService: $e');
      _isInitialized = false;
    }
  }
/// Load offline location database
  Future<void> _loadOfflineDatabase() async {
    try {
      // First try to load from CSV assets
      try {
        debugPrint('📂 Loading offline locations from CSV...');
        final String csvString = await rootBundle.loadString(
          'assets/geonames_cities.csv',
        );

        // Parse CSV
        final lines = csvString.split('\n');
        if (lines.isEmpty) {
          debugPrint('❌ CSV file is empty');
          throw Exception('CSV file is empty');
        }

        // Skip header line (name,country_code,country_name,latitude,longitude,population)
        _locations = [];

        for (int i = 1; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;

          try {
            final parts = _parseCsvLine(line);
            if (parts.length < 6) continue;

            final name = parts[0];
            final countryCode = parts[1];
            final countryName = parts[2];
            final latitude = double.tryParse(parts[3]) ?? 0.0;
            final longitude = double.tryParse(parts[4]) ?? 0.0;
            final population = int.tryParse(parts[5]) ?? 0;

            // Add city to locations
            _locations.add(
              LocationSearchResult(
                name: name,
                displayName: '$name, $countryName',
                shortDisplayName: '$name, $countryCode',
                latitude: latitude,
                longitude: longitude,
                country: countryName,
                state: null,
                city: name,
                type: LocationType.city,
                population: population,
              ),
            );
          } catch (e) {
            debugPrint('⚠️ Error parsing CSV line $i: $e');
            continue;
          }
        }

        debugPrint('✅ Loaded ${_locations.length} offline locations from CSV');
        return;
      } catch (assetError) {
        debugPrint('⚠️ Could not load from CSV assets: $assetError');
      }

      // If CSV loading failed, initialize with empty list
      _locations = [];
      debugPrint('⚠️ No locations loaded');
    } catch (e) {
      debugPrint('❌ Error loading offline database: $e');
      _locations = [];
    }
  }

  /// Parse a CSV line handling quoted fields
  List<String> _parseCsvLine(String line) {
    final List<String> result = [];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    // Add the last field
    result.add(buffer.toString().trim());

    return result;
  }



  /// Search locations using hybrid approach (native + offline)
  Future<List<LocationSearchResult>> searchLocations(
    String query, {
    int limit = 50,
    bool forceOffline = true,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (query.trim().isEmpty) {
      return _locations.take(limit).toList();
    }

    try {
      List<LocationSearchResult> results = [];

      // Try native search first if available and not forced offline

      // Always include offline search results
      final offlineResults = _searchOffline(
        query,
        limit: limit - results.length,
      );
      results.addAll(offlineResults);
      debugPrint('🔍 Offline search returned ${offlineResults.length} results');

      // Remove duplicates and limit results
      results = _removeDuplicates(results);
      if (results.length > limit) {
        results = results.take(limit).toList();
      }

      debugPrint('🔍 Search "$query" returned ${results.length} total results');
      return results;
    } catch (e) {
      debugPrint('❌ Error searching locations: $e');
      return _searchOffline(query, limit: limit);
    }
  }
  /// Search using offline database
  List<LocationSearchResult> _searchOffline(String query, {int limit = 50}) {
    // Use WorldLocationsService for offline search
    final worldLocationsService = world.WorldLocationsService.instance;

    if (!worldLocationsService.isLoaded) {
      debugPrint('⚠️ WorldLocationsService not loaded, using fallback search');
      // Fallback to local database search
      final lowerQuery = query.toLowerCase().trim();
      final results = _locations.where((location) {
        return location.name.toLowerCase().contains(lowerQuery) ||
            location.city.toLowerCase().contains(lowerQuery) ||
            location.country.toLowerCase().contains(lowerQuery) ||
            (location.state?.toLowerCase().contains(lowerQuery) ?? false) ||
            location.displayName.toLowerCase().contains(lowerQuery);
      }).toList();

      // Sort by relevance (exact matches first, then by population)
      results.sort((a, b) {
        final aExact = a.name.toLowerCase() == lowerQuery ? 1 : 0;
        final bExact = b.name.toLowerCase() == lowerQuery ? 1 : 0;
        if (aExact != bExact) return bExact - aExact;
        return (b.population ?? 0).compareTo(a.population ?? 0);
      });

      return results.take(limit).toList();
    }

    // Use WorldLocationsService search method
    final worldResults = worldLocationsService.searchLocations(query, limit: limit);

    // Convert WorldLocationsService results to LocationSearchResult
    final convertedResults = worldResults.map((result) {
      return LocationSearchResult(
        name: result.name,
        displayName: _buildDisplayName(result),
        shortDisplayName: _buildShortDisplayName(result),
        latitude: result.latitude,
        longitude: result.longitude,
        country: result.country,
        state: result.state,
        city: result.city ?? result.name,
        type: result.type == world.LocationType.city ? LocationType.city : LocationType.country,
        population: result.population,
      );
    }).toList();

    debugPrint('🌍 WorldLocationsService returned ${convertedResults.length} results');
    return convertedResults;
  }

  /// Build display name from location result
  String _buildDisplayName(world.LocationResult result) {
    if (result.type == world.LocationType.city) {
      if (result.state != null && result.state!.isNotEmpty) {
        return '${result.name}, ${result.state}, ${result.country}';
      }
      return '${result.name}, ${result.country}';
    }
    return result.name;
  }

  /// Build short display name from location result
  String _buildShortDisplayName(world.LocationResult result) {
    if (result.type == world.LocationType.city) {
      return '${result.name}, ${result.countryCode}';
    }
    return result.name;
  }

  /// Remove duplicate locations from results
  List<LocationSearchResult> _removeDuplicates(
    List<LocationSearchResult> results,
  ) {
    final seen = <String>{};
    return results.where((location) {
      final key =
          '${location.latitude.toStringAsFixed(3)},${location.longitude.toStringAsFixed(3)}';
      return seen.add(key);
    }).toList();
  }

  /// Add a new location to the offline database
  Future<void> addLocation(LocationSearchResult location) async {
    try {
      // Check if location already exists
      final exists = _locations.any(
        (l) =>
            (l.latitude - location.latitude).abs() < 0.001 &&
            (l.longitude - location.longitude).abs() < 0.001,
      );

      if (!exists) {
        _locations.add(location);
        debugPrint('📍 Added new location: ${location.displayName}');
      }
    } catch (e) {
      debugPrint('❌ Error adding location: $e');
    }
  }

  /// Get all locations in the offline database
  List<LocationSearchResult> get allLocations => List.unmodifiable(_locations);

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if native search is available
  }

/// Location search result model
class LocationSearchResult {
  final String name;
  final String displayName;
  final String shortDisplayName;
  final double latitude;
  final double longitude;
  final String country;
  final String? state;
  final String city;
  final LocationType type;
  final int? population;

  LocationSearchResult({
    required this.name,
    required this.displayName,
    required this.shortDisplayName,
    required this.latitude,
    required this.longitude,
    required this.country,
    this.state,
    required this.city,
    required this.type,
    this.population,
  });

  factory LocationSearchResult.fromJson(Map<String, dynamic> json) {
    return LocationSearchResult(
      name: json['name'] ?? '',
      displayName: json['displayName'] ?? '',
      shortDisplayName: json['shortDisplayName'] ?? '',
      latitude: (json['latitude'] ?? 0.0).toDouble(),
      longitude: (json['longitude'] ?? 0.0).toDouble(),
      country: json['country'] ?? '',
      state: json['state'],
      city: json['city'] ?? '',
      type: LocationType.values.firstWhere(
        (t) => t.toString() == json['type'],
        orElse: () => LocationType.city,
      ),
      population: json['population'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'displayName': displayName,
      'shortDisplayName': shortDisplayName,
      'latitude': latitude,
      'longitude': longitude,
      'country': country,
      'state': state,
      'city': city,
      'type': type.toString(),
      'population': population,
    };
  }
}

/// Location type enumeration
enum LocationType {
  city,
  town,
  village,
  country,
  state,
  region,
  landmark,
  airport,
  university,
}
