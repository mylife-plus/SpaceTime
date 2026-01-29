import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geocoder_offline_json/geocoder_offline.dart';
import 'package:spacetime/app/helpers/nearest_region_service.dart';
import 'package:spacetime/app/utils/place_categories_utils.dart';

class OfflineGeocoder {
  static OfflineGeocoder? _instance;
  static OfflineGeocoder get instance => _instance ??= OfflineGeocoder._();

  OfflineGeocoder._();

  late GeocodeData geocoder;
  bool _isInitialized = false;

  /// Initialize geocoder with your CSV file
  Future<void> init() async {
    if (_isInitialized) return;
    final dataString = await rootBundle.loadString('assets/cities_names_1.csv');
    geocoder = GeocodeData(
      dataString,
      'name', // city name column
      'country_name', // ISO code column
      'latitude',
      'longitude',
      fieldDelimiter: ',',
      eol: '\n',
    );
  }

  /// Find the single nearest city for given lat/lng
  /// Returns data structure compatible with existing reverse geocoding implementation
  Future<Map<String, dynamic>?> reverseGeocode(double lat, double lng) async {
    final results = geocoder.search(lat, lng);

    if (results.isEmpty) return null;

    final nearest = results.first; // Get the closest result
    final city = nearest.location.featureName ?? '';
    final country = nearest.location.state ?? '';
    final flag = countryFlags[country.toLowerCase()] ?? '';

 final region = await NearestRegionService()
    .findNearest(lat, lng);
// var city = region.name
region?.printAll();
   var city1 = (city.contains(region!.name) ? '${city}' :'${city}, ${region?.name}');

    // Build address string similar to original implementation
    final addressComponents = <String>[];
    if (city.isNotEmpty) addressComponents.add(city);
    if (country.isNotEmpty) addressComponents.add(country);
    final address = addressComponents.join(', ');

    // Return data structure compatible with existing geocoding implementation
    final locationDetails = {
      'country': country,
      'city': city1,
      'name': city.isNotEmpty ? '$city, $country' : country,
      'address': address,
      'flag': flag,
    };

    debugPrint('🔍 OfflineGeocoder reverse geocoding coordinates: $lat, $lng');
    debugPrint('✅ OfflineGeocoder result: $locationDetails');

    return locationDetails;
  }

  /// Convert ISO code → emoji flag
  // String countryCodeToFlag(String code) {
  //   return code.toUpperCase().runes.map((c) => String.fromCharCode(c + 127397)).join();
  // }
}
