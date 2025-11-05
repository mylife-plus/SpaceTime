import 'dart:math' as math;

/// Model for location data used in location picker
class LocationData {
  final double latitude;
  final double longitude;
  final String address;
  final String city;
  final String state;
  final String country;
  final String? postcode;
  final String timestamp;
  final String? type;
  final String? source;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.city,
    required this.state,
    required this.country,
    this.postcode,
    required this.timestamp,
    this.type,
    this.source,
  });

  /// Create LocationData from JSON
  factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      state: json['state'] as String? ?? '',
      country: json['country'] as String? ?? '',
      postcode: json['postcode'] as String?,
      timestamp: json['timestamp'] as String? ?? DateTime.now().toIso8601String(),
      type: json['type'] as String?,
      source: json['source'] as String?,
    );
  }

  /// Convert LocationData to JSON
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
      'city': city,
      'state': state,
      'country': country,
      'postcode': postcode,
      'timestamp': timestamp,
      'type': type,
      'source': source,
    };
  }

  /// Create LocationData from search result
  factory LocationData.fromSearchResult(Map<String, dynamic> result) {
    return LocationData(
      latitude: (result['latitude'] as num).toDouble(),
      longitude: (result['longitude'] as num).toDouble(),
      address: result['name'] as String? ?? result['address'] as String? ?? 'Unknown Location',
      city: result['city'] as String? ?? '',
      state: result['region'] as String? ?? result['state'] as String? ?? '',
      country: result['country'] as String? ?? '',
      postcode: result['postcode'] as String?,
      timestamp: DateTime.now().toIso8601String(),
      type: result['type'] as String?,
      source: result['source'] as String? ?? 'search',
    );
  }

  /// Get display name for the location
  String get displayName {
    if (address.isNotEmpty) {
      return address;
    }
    
    List<String> parts = [];
    if (city.isNotEmpty) parts.add(city);
    if (state.isNotEmpty) parts.add(state);
    if (country.isNotEmpty) parts.add(country);
    
    return parts.isNotEmpty ? parts.join(', ') : 'Unknown Location';
  }

  /// Get short display name
  String get shortDisplayName {
    List<String> parts = [];
    if (city.isNotEmpty) parts.add(city);
    if (country.isNotEmpty) parts.add(country);
    
    return parts.isNotEmpty ? parts.join(', ') : displayName;
  }

  /// Check if location has valid coordinates
  bool get hasValidCoordinates {
    return latitude >= -90.0 && 
           latitude <= 90.0 && 
           longitude >= -180.0 && 
           longitude <= 180.0 &&
           !(latitude == 0.0 && longitude == 0.0);
  }

  /// Calculate distance to another location in kilometers
  double distanceTo(LocationData other) {
    const double earthRadius = 6371.0; // Earth's radius in kilometers
    
    final double lat1Rad = latitude * (3.14159265359 / 180.0);
    final double lat2Rad = other.latitude * (3.14159265359 / 180.0);
    final double deltaLatRad = (other.latitude - latitude) * (3.14159265359 / 180.0);
    final double deltaLngRad = (other.longitude - longitude) * (3.14159265359 / 180.0);

    final double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLngRad / 2) * math.sin(deltaLngRad / 2);

    final double c = 2 * math.asin(math.sqrt(a));
    
    return earthRadius * c;
  }

  /// Create a copy with updated values
  LocationData copyWith({
    double? latitude,
    double? longitude,
    String? address,
    String? city,
    String? state,
    String? country,
    String? postcode,
    String? timestamp,
    String? type,
    String? source,
  }) {
    return LocationData(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      country: country ?? this.country,
      postcode: postcode ?? this.postcode,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      source: source ?? this.source,
    );
  }

  @override
  String toString() {
    return 'LocationData(lat: $latitude, lng: $longitude, address: $address, city: $city, state: $state, country: $country)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationData &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.address == address &&
        other.city == city &&
        other.state == state &&
        other.country == country;
  }

  @override
  int get hashCode {
    return Object.hash(
      latitude,
      longitude,
      address,
      city,
      state,
      country,
    );
  }
}
