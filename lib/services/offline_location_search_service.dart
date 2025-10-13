import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _useNativeSearch = false;

  /// Initialize the offline search service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🔍 Initializing OfflineLocationSearchService...');

      // Check if native search is available
      await _checkNativeSearchAvailability();

      // Load offline location database
      await _loadOfflineDatabase();

      _isInitialized = true;
      debugPrint('✅ OfflineLocationSearchService initialized successfully');
      debugPrint('   Native search: $_useNativeSearch');
      debugPrint('   Offline locations: ${_locations.length}');
    } catch (e) {
      debugPrint('❌ Error initializing OfflineLocationSearchService: $e');
      _isInitialized = false;
    }
  }

  /// Check if native search capabilities are available
  Future<void> _checkNativeSearchAvailability() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        debugPrint(
          '🔍 Checking native search availability on ${Platform.operatingSystem}...',
        );

        final result = await _channel.invokeMethod('isNativeSearchAvailable');
        _useNativeSearch = result == true;

        debugPrint('🔍 Native search availability: $_useNativeSearch');
        if (_useNativeSearch) {
          debugPrint('✅ Native search is available and will be used');
        } else {
          debugPrint(
            '⚠️ Native search is not available, using offline-only mode',
          );
        }
      } else {
        debugPrint(
          '⚠️ Platform ${Platform.operatingSystem} not supported for native search',
        );
        _useNativeSearch = false;
      }
    } catch (e) {
      debugPrint('❌ Error checking native search availability: $e');
      debugPrint('   Error type: ${e.runtimeType}');
      if (e.toString().contains('MissingPluginException')) {
        debugPrint(
          '   This means the native platform channel is not properly set up',
        );
        debugPrint('   Falling back to offline-only search');
      }
      _useNativeSearch = false;
    }
  }

  /// Load offline location database
  Future<void> _loadOfflineDatabase() async {
    try {
      // Load from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final locationsJson = prefs.getString('offline_locations_db') ?? '[]';
      final List<dynamic> locationsList = json.decode(locationsJson);

      _locations =
          locationsList
              .map((json) => LocationSearchResult.fromJson(json))
              .toList();

      // If no locations exist, create initial database
      if (_locations.isEmpty) {
        await _createInitialDatabase();
      }

      debugPrint('📍 Loaded ${_locations.length} offline locations');
    } catch (e) {
      debugPrint('❌ Error loading offline database: $e');
      await _createInitialDatabase();
    }
  }

  /// Create initial offline location database
  Future<void> _createInitialDatabase() async {
    try {
      debugPrint('🏗️ Creating initial offline location database...');

      // _locations = [
      //   // Major world cities
      //   LocationSearchResult(
      //     name: 'New York City',
      //     displayName: 'New York City, NY, USA',
      //     shortDisplayName: 'New York, USA',
      //     latitude: 40.7128,
      //     longitude: -74.0060,
      //     country: 'United States',
      //     state: 'New York',
      //     city: 'New York City',
      //     type: LocationType.city,
      //     population: 8336817,
      //   ),
      //   LocationSearchResult(
      //     name: 'London',
      //     displayName: 'London, England, UK',
      //     shortDisplayName: 'London, UK',
      //     latitude: 51.5074,
      //     longitude: -0.1278,
      //     country: 'United Kingdom',
      //     state: 'England',
      //     city: 'London',
      //     type: LocationType.city,
      //     population: 9648110,
      //   ),
      //   LocationSearchResult(
      //     name: 'Tokyo',
      //     displayName: 'Tokyo, Japan',
      //     shortDisplayName: 'Tokyo, Japan',
      //     latitude: 35.6762,
      //     longitude: 139.6503,
      //     country: 'Japan',
      //     state: 'Tokyo',
      //     city: 'Tokyo',
      //     type: LocationType.city,
      //     population: 37400068,
      //   ),
      //   LocationSearchResult(
      //     name: 'Paris',
      //     displayName: 'Paris, Île-de-France, France',
      //     shortDisplayName: 'Paris, France',
      //     latitude: 48.8566,
      //     longitude: 2.3522,
      //     country: 'France',
      //     state: 'Île-de-France',
      //     city: 'Paris',
      //     type: LocationType.city,
      //     population: 2161000,
      //   ),
      //   LocationSearchResult(
      //     name: 'Sydney',
      //     displayName: 'Sydney, NSW, Australia',
      //     shortDisplayName: 'Sydney, Australia',
      //     latitude: -33.8688,
      //     longitude: 151.2093,
      //     country: 'Australia',
      //     state: 'New South Wales',
      //     city: 'Sydney',
      //     type: LocationType.city,
      //     population: 5312163,
      //   ),
      //   LocationSearchResult(
      //     name: 'Dubai',
      //     displayName: 'Dubai, UAE',
      //     shortDisplayName: 'Dubai, UAE',
      //     latitude: 25.2048,
      //     longitude: 55.2708,
      //     country: 'United Arab Emirates',
      //     state: 'Dubai',
      //     city: 'Dubai',
      //     type: LocationType.city,
      //     population: 3331420,
      //   ),
      //   LocationSearchResult(
      //     name: 'Singapore',
      //     displayName: 'Singapore',
      //     shortDisplayName: 'Singapore',
      //     latitude: 1.3521,
      //     longitude: 103.8198,
      //     country: 'Singapore',
      //     state: 'Singapore',
      //     city: 'Singapore',
      //     type: LocationType.city,
      //     population: 5850342,
      //   ),
      //   LocationSearchResult(
      //     name: 'Mumbai',
      //     displayName: 'Mumbai, Maharashtra, India',
      //     shortDisplayName: 'Mumbai, India',
      //     latitude: 19.0760,
      //     longitude: 72.8777,
      //     country: 'India',
      //     state: 'Maharashtra',
      //     city: 'Mumbai',
      //     type: LocationType.city,
      //     population: 20411274,
      //   ),
      //   LocationSearchResult(
      //     name: 'São Paulo',
      //     displayName: 'São Paulo, SP, Brazil',
      //     shortDisplayName: 'São Paulo, Brazil',
      //     latitude: -23.5505,
      //     longitude: -46.6333,
      //     country: 'Brazil',
      //     state: 'São Paulo',
      //     city: 'São Paulo',
      //     type: LocationType.city,
      //     population: 12325232,
      //   ),
      //   LocationSearchResult(
      //     name: 'Cairo',
      //     displayName: 'Cairo, Egypt',
      //     shortDisplayName: 'Cairo, Egypt',
      //     latitude: 30.0444,
      //     longitude: 31.2357,
      //     country: 'Egypt',
      //     state: 'Cairo Governorate',
      //     city: 'Cairo',
      //     type: LocationType.city,
      //     population: 10230350,
      //   ),
      // ];

      // // Save to SharedPreferences
      await _saveOfflineDatabase();

      debugPrint(
        '✅ Created initial database with ${_locations.length} locations',
      );
    } catch (e) {
      debugPrint('❌ Error creating initial database: $e');
    }
  }

  /// Save offline database to SharedPreferences
  Future<void> _saveOfflineDatabase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final locationsJson = json.encode(
        _locations.map((l) => l.toJson()).toList(),
      );
      await prefs.setString('offline_locations_db', locationsJson);
    } catch (e) {
      debugPrint('❌ Error saving offline database: $e');
    }
  }

  /// Search locations using hybrid approach (native + offline)
  Future<List<LocationSearchResult>> searchLocations(
    String query, {
    int limit = 10,
    bool forceOffline = false,
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
      if (_useNativeSearch && !forceOffline) {
        try {
          final nativeResults = await _searchNative(query, limit: limit ~/ 2);
          results.addAll(nativeResults);
        } catch (e) {
          debugPrint('⚠️ Native search failed, falling back to offline: $e');
        }
      }

      // Always include offline search results
      final offlineResults = _searchOffline(
        query,
        limit: limit - results.length,
      );
      results.addAll(offlineResults);

      // Remove duplicates and limit results
      results = _removeDuplicates(results);
      if (results.length > limit) {
        results = results.take(limit).toList();
      }

      debugPrint('🔍 Search "$query" returned ${results.length} results');
      return results;
    } catch (e) {
      debugPrint('❌ Error searching locations: $e');
      return _searchOffline(query, limit: limit);
    }
  }

  /// Search using native platform capabilities
  Future<List<LocationSearchResult>> _searchNative(
    String query, {
    int limit = 10,
  }) async {
    try {
      debugPrint('🔍 Attempting native search for: "$query"');

      final result = await _channel.invokeMethod('searchLocations', {
        'query': query,
        'limit': limit,
      });

      debugPrint('🔍 Native search raw result: $result');

      if (result is List) {
        final locations = <LocationSearchResult>[];

        for (final item in result) {
          try {
            if (item is Map) {
              final json = Map<String, dynamic>.from(item);
              final location = LocationSearchResult.fromJson(json);
              locations.add(location);
              debugPrint('✅ Parsed native location: ${location.displayName}');
            }
          } catch (e) {
            debugPrint('⚠️ Error parsing native location item: $e');
            debugPrint('   Item: $item');
          }
        }

        debugPrint(
          '🔍 Native search returned ${locations.length} valid locations',
        );
        return locations;
      } else {
        debugPrint(
          '⚠️ Native search returned unexpected type: ${result.runtimeType}',
        );
      }
    } catch (e) {
      debugPrint('❌ Native search error: $e');
      debugPrint('   Error type: ${e.runtimeType}');
      if (e.toString().contains('MissingPluginException')) {
        debugPrint(
          '   This is likely because the native implementation is not properly registered',
        );
      }
    }
    return [];
  }

  /// Search using offline database
  List<LocationSearchResult> _searchOffline(String query, {int limit = 10}) {
    final lowerQuery = query.toLowerCase().trim();

    final results =
        _locations.where((location) {
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
        await _saveOfflineDatabase();
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
  bool get hasNativeSearch => _useNativeSearch;

  /// Test native search functionality
  Future<void> testNativeSearch() async {
    if (!_isInitialized) {
      await initialize();
    }

    debugPrint('🧪 Testing native search functionality...');

    if (!_useNativeSearch) {
      debugPrint('❌ Native search is not available for testing');
      return;
    }

    try {
      // Test with a simple query
      final testResults = await _searchNative('New York', limit: 3);

      if (testResults.isNotEmpty) {
        debugPrint('✅ Native search test PASSED');
        debugPrint('   Found ${testResults.length} results for "New York"');
        for (final result in testResults) {
          debugPrint(
            '   - ${result.displayName} (${result.latitude}, ${result.longitude})',
          );
        }
      } else {
        debugPrint('⚠️ Native search test returned no results');
        debugPrint('   This might be normal if no results were found');
      }
    } catch (e) {
      debugPrint('❌ Native search test FAILED: $e');
    }
  }
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
