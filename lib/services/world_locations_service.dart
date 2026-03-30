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

      // Parse heavy CSV in background isolate to avoid UI jank on iOS.
      final parsed = await compute(_parseWorldLocationsCsv, csvString);
      final countriesData = (parsed['countries'] as List).cast<Map>();
      final locationsData = (parsed['locations'] as List).cast<Map>();

      _countries =
          countriesData
              .map(
                (c) => Country(
                  name: c['name'] as String,
                  code: c['code'] as String,
                  latitude: (c['latitude'] as num).toDouble(),
                  longitude: (c['longitude'] as num).toDouble(),
                  cities: const [],
                ),
              )
              .toList();

      _allLocations =
          locationsData
              .map(
                (l) => LocationResult(
                  name: l['name'] as String,
                  type:
                      (l['type'] as String) == 'country'
                          ? LocationType.country
                          : LocationType.city,
                  latitude: (l['latitude'] as num).toDouble(),
                  longitude: (l['longitude'] as num).toDouble(),
                  country: l['country'] as String,
                  countryCode: l['countryCode'] as String,
                  city: l['city'] as String?,
                  state: l['state'] as String?,
                  population: l['population'] as int?,
                ),
              )
              .toList();

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

Map<String, List<Map<String, dynamic>>> _parseWorldLocationsCsv(
  String csvString,
) {
  final lines = csvString.split('\n');
  if (lines.isEmpty) {
    return <String, List<Map<String, dynamic>>>{
      'countries': <Map<String, dynamic>>[],
      'locations': <Map<String, dynamic>>[],
    };
  }

  final locations = <Map<String, dynamic>>[];
  final countriesByCode = <String, Map<String, dynamic>>{};

  for (int i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;

    final parts = _parseCsvLineInIsolate(line);
    if (parts.length < 6) continue;

    final name = parts[0];
    final countryCode = parts[1];
    final countryName = parts[2];
    final latitude = double.tryParse(parts[3]) ?? 0.0;
    final longitude = double.tryParse(parts[4]) ?? 0.0;
    final population = int.tryParse(parts[5]) ?? 0;

    locations.add(<String, dynamic>{
      'name': name,
      'type': 'city',
      'latitude': latitude,
      'longitude': longitude,
      'country': countryName,
      'countryCode': countryCode,
      'city': name,
      'state': null,
      'population': population,
    });

    countriesByCode.putIfAbsent(countryCode, () {
      return <String, dynamic>{
        'name': countryName,
        'code': countryCode,
        'latitude': latitude,
        'longitude': longitude,
      };
    });
  }

  final countries = countriesByCode.values.toList(growable: false);
  for (final c in countries) {
    locations.add(<String, dynamic>{
      'name': c['name'],
      'type': 'country',
      'latitude': c['latitude'],
      'longitude': c['longitude'],
      'country': c['name'],
      'countryCode': c['code'],
      'city': null,
      'state': null,
      'population': null,
    });
  }

  return <String, List<Map<String, dynamic>>>{
    'countries': countries,
    'locations': locations,
  };
}

List<String> _parseCsvLineInIsolate(String line) {
  final result = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

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
  result.add(buffer.toString().trim());
  return result;
}
