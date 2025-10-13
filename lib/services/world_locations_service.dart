import 'dart:convert';
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

  /// Initialize the service by loading the world locations data
  Future<bool> initialize() async {
    if (_isLoaded) return true;

    try {
      final String jsonString = await rootBundle.loadString(
        'assets/data/world_locations.json',
      );
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      _countries =
          (jsonData['countries'] as List)
              .map((countryData) => Country.fromJson(countryData))
              .toList();

      // Create a flat list of all locations for easier searching
      _allLocations = [];

      for (final country in _countries) {
        // Add country as a location
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
          ),
        );

        // Add all cities
        for (final city in country.cities) {
          _allLocations.add(
            LocationResult(
              name: city.name,
              type: LocationType.city,
              latitude: city.latitude,
              longitude: city.longitude,
              country: country.name,
              countryCode: country.code,
              city: city.name,
              state: city.state,
            ),
          );
        }
      }

      _isLoaded = true;
      debugPrint(
        'World locations loaded: ${_countries.length} countries, ${_allLocations.length} total locations',
      );
      return true;
    } catch (e) {
      debugPrint('Error loading world locations: $e');
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

  LocationResult({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.country,
    required this.countryCode,
    this.city,
    this.state,
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
    };
  }

  @override
  String toString() {
    return 'LocationResult(name: $name, type: $type, country: $country, lat: $latitude, lng: $longitude)';
  }
}

enum LocationType { country, city }
