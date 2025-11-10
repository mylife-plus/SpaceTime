import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class WorldLocationsService {
  static WorldLocationsService? _instance;
  static WorldLocationsService get instance =>
      _instance ??= WorldLocationsService._();

  WorldLocationsService._();

  List<Country> _countries = [];
  List<LocationResult> _allLocations = [];
  bool _isLoaded = false;

  /// Initialize the service by loading the world locations data from CSV
  Future<bool> initialize() async {
    if (_isLoaded) return true;

    try {
      debugPrint('📂 Loading cities from assets/geonames_cities.csv...');

      final String csvString = await rootBundle.loadString(
        'assets/geonames_cities.csv',
      );

      // Parse CSV
      final lines = csvString.split('\n');
      if (lines.isEmpty) {
        debugPrint('❌ CSV file is empty');
        return false;
      }

      // Skip header line (name,country_code,country_name,latitude,longitude,population)
      _allLocations = [];
      final Map<String, Country> countriesMap = {};

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
          _allLocations.add(
            LocationResult(
              name: name,
              type: LocationType.city,
              latitude: latitude,
              longitude: longitude,
              country: countryName,
              countryCode: countryCode,
              city: name,
              state: null,
              population: population,
            ),
          );

          // Track unique countries
          if (!countriesMap.containsKey(countryCode)) {
            countriesMap[countryCode] = Country(
              name: countryName,
              code: countryCode,
              latitude: latitude,
              longitude: longitude,
              cities: [],
            );
          }
        } catch (e) {
          debugPrint('⚠️ Error parsing line $i: $e');
          continue;
        }
      }

      // Convert countries map to list
      _countries = countriesMap.values.toList();

      // Add countries as searchable locations
      for (final country in _countries) {
        _allLocations.add(
          LocationResult(
            name: country.name,
            type: LocationType.country,
            latitude: country.latitude,
            longitude: country.longitude,
            country: country.name,
            countryCode: country.code,
            city: null,
            state: null,
            population: null,
          ),
        );
      }

      _isLoaded = true;
      debugPrint(
        '✅ World locations loaded: ${_countries.length} countries, ${_allLocations.length} total locations',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error loading world locations: $e');
      return false;
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

  /// Search for locations by query
  List<LocationResult> searchLocations(String query, {int limit = 20}) {
    if (!_isLoaded || query.isEmpty) return [];

    final lowerQuery = query.toLowerCase().trim();
    final results = <LocationResult>[];

    // Exact matches first
    final exactMatches =
        _allLocations
            .where(
              (location) =>
                  location.name.toLowerCase() == lowerQuery ||
                  location.country.toLowerCase() == lowerQuery ||
                  (location.city?.toLowerCase() == lowerQuery) ||
                  (location.state?.toLowerCase() == lowerQuery),
            )
            .toList();

    // Sort exact matches by population (highest first)
    exactMatches.sort((a, b) {
      // Prioritize cities over countries
      if (a.type != b.type) {
        return a.type == LocationType.city ? -1 : 1;
      }
      // Then sort by population
      return (b.population ?? 0).compareTo(a.population ?? 0);
    });

    results.addAll(exactMatches);

    // Starts with matches
    if (results.length < limit) {
      final startsWithMatches =
          _allLocations
              .where(
                (location) =>
                    !exactMatches.contains(location) &&
                    (location.name.toLowerCase().startsWith(lowerQuery) ||
                        location.country.toLowerCase().startsWith(lowerQuery) ||
                        (location.city?.toLowerCase().startsWith(lowerQuery) ??
                            false) ||
                        (location.state?.toLowerCase().startsWith(lowerQuery) ??
                            false)),
              )
              .toList();

      // Sort by population
      startsWithMatches.sort((a, b) {
        if (a.type != b.type) {
          return a.type == LocationType.city ? -1 : 1;
        }
        return (b.population ?? 0).compareTo(a.population ?? 0);
      });

      results.addAll(startsWithMatches.take(limit - results.length));
    }

    // Contains matches
    if (results.length < limit) {
      final containsMatches =
          _allLocations
              .where(
                (location) =>
                    !exactMatches.contains(location) &&
                    !results.contains(location) &&
                    (location.name.toLowerCase().contains(lowerQuery) ||
                        location.country.toLowerCase().contains(lowerQuery) ||
                        (location.city?.toLowerCase().contains(lowerQuery) ??
                            false) ||
                        (location.state?.toLowerCase().contains(lowerQuery) ??
                            false)),
              )
              .toList();

      // Sort by population
      containsMatches.sort((a, b) {
        if (a.type != b.type) {
          return a.type == LocationType.city ? -1 : 1;
        }
        return (b.population ?? 0).compareTo(a.population ?? 0);
      });

      results.addAll(containsMatches.take(limit - results.length));
    }

    return results.take(limit).toList();
  }

  /// Get all countries
  List<Country> get countries => _countries;

  /// Get all locations
  List<LocationResult> get allLocations => _allLocations;

  /// Check if service is loaded
  bool get isLoaded => _isLoaded;
}

class Country {
  final String name;
  final String code;
  final double latitude;
  final double longitude;
  final List<City> cities;

  Country({
    required this.name,
    required this.code,
    required this.latitude,
    required this.longitude,
    required this.cities,
  });

  factory Country.fromJson(Map<String, dynamic> json) {
    return Country(
      name: json['name'],
      code: json['code'],
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      cities:
          (json['cities'] as List)
              .map((cityData) => City.fromJson(cityData))
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'code': code,
      'latitude': latitude,
      'longitude': longitude,
      'cities': cities.map((city) => city.toJson()).toList(),
    };
  }
}

class City {
  final String name;
  final double latitude;
  final double longitude;
  final String state;

  City({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.state,
  });

  factory City.fromJson(Map<String, dynamic> json) {
    return City(
      name: json['name'],
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      state: json['state'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'state': state,
    };
  }
}

class LocationResult {
  final String name;
  final LocationType type;
  final double latitude;
  final double longitude;
  final String country;
  final String countryCode;
  final String? city;
  final String? state;
  final int? population;

  LocationResult({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.country,
    required this.countryCode,
    this.city,
    this.state,
    this.population,
  });

  String get displayName {
    switch (type) {
      case LocationType.country:
        return name;
      case LocationType.city:
        return state != null ? '$name, $state, $country' : '$name, $country';
    }
  }

  String get shortDisplayName {
    switch (type) {
      case LocationType.country:
        return name;
      case LocationType.city:
        return '$name, $country';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.toString(),
      'latitude': latitude,
      'longitude': longitude,
      'country': country,
      'countryCode': countryCode,
      'city': city,
      'state': state,
      'population': population,
    };
  }

  @override
  String toString() {
    return 'LocationResult(name: $name, type: $type, country: $country, lat: $latitude, lng: $longitude, pop: $population)';
  }
}

enum LocationType { country, city }
