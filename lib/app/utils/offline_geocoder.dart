import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:geocoder_offline_json/geocoder_offline.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/helpers/nearest_region_service.dart';
import 'package:spacetime/app/helpers/offline_water_service.dart';
import 'package:spacetime/app/utils/place_categories_utils.dart';

class _CityRecord {
  final String name;
  final String stateName;
  final String countryName;
  final String countryCode;
  final double latitude;
  final double longitude;

  _CityRecord({
    required this.name,
    required this.stateName,
    required this.countryName,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
  });
}

class OfflineGeocoder {
  static OfflineGeocoder? _instance;
  static OfflineGeocoder get instance => _instance ??= OfflineGeocoder._();

  OfflineGeocoder._();

  late GeocodeData geocoder;
  bool _isInitialized = false;
  final Map<String, _CityRecord> _cityLookup = {};

  String _coordKey(double lat, double lng) =>
      '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  Future<void> init() async {
    if (_isInitialized) return;
    final dataString = await rootBundle.loadString('assets/cities_names_1.csv');

    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(dataString);

    if (rows.isNotEmpty) {
      final header = rows[0].map((e) => e.toString()).toList();
      final nameIdx = header.indexOf('name');
      final stateNameIdx = header.indexOf('state_name');
      final countryNameIdx = header.indexOf('country_name');
      final countryCodeIdx = header.indexOf('country_code');
      final latIdx = header.indexOf('latitude');
      final lngIdx = header.indexOf('longitude');

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length <= lngIdx) continue;
        final lat = double.tryParse(row[latIdx].toString()) ?? 0;
        final lng = double.tryParse(row[lngIdx].toString()) ?? 0;
        _cityLookup[_coordKey(lat, lng)] = _CityRecord(
          name: row[nameIdx].toString(),
          stateName: stateNameIdx >= 0 ? row[stateNameIdx].toString() : '',
          countryName: row[countryNameIdx].toString(),
          countryCode: countryCodeIdx >= 0 ? row[countryCodeIdx].toString() : '',
          latitude: lat,
          longitude: lng,
        );
      }
    }

    geocoder = GeocodeData(
      dataString,
      'name',
      'country_name',
      'latitude',
      'longitude',
      fieldDelimiter: ',',
      eol: '\n',
      numMarkers: 5,
    );
    _isInitialized = true;
  }

  _CityRecord? _lookupRecord(LocationData loc) {
    if (loc.latitude == null || loc.longitude == null) return null;
    return _cityLookup[_coordKey(loc.latitude!, loc.longitude!)];
  }

  String _resolveRegion(String stateName, String countryCode, double lat, double lng) {
    final region = NearestRegionService().findNearest(lat, lng);
    if (region != null && countryCode.isNotEmpty && region.countryCode == countryCode) {
      return region.name;
    }
    if (stateName.isNotEmpty) return stateName;
    if (region != null) return region.name;
    return '';
  }

  Map<String, dynamic> _buildResult(_CityRecord? record, LocationData loc, double lat, double lng) {
    final city = record?.name ?? loc.featureName ?? '';
    final country = record?.countryName ?? loc.state ?? '';
    final stateName = record?.stateName ?? '';
    final countryCode = record?.countryCode ?? '';
    final flag = countryFlags[country.toLowerCase()] ?? '';

    final regionName = _resolveRegion(stateName, countryCode, lat, lng);

    var city1 = (regionName.isNotEmpty && !city.contains(regionName))
        ? '$city, $regionName'
        : city;

    final addressComponents = <String>[];
    if (city.isNotEmpty) addressComponents.add(city);
    if (country.isNotEmpty) addressComponents.add(country);
    final address = addressComponents.join(', ');

    return {
      'country': country,
      'city': city1,
      'name': city.isNotEmpty ? '$city, $country' : country,
      'address': address,
      'flag': flag,
    };
  }

  Future<Map<String, dynamic>?> reverseGeocode(double lat, double lng) async {
    final results = geocoder.search(lat, lng);
    final hit = OfflineWaterService.instance.detect(lat, lng);

    if (results.isNotEmpty && results.first.distance < 50) {
      final nearest = results.first;
      final record = _lookupRecord(nearest.location);
      return _buildResult(record, nearest.location, lat, lng);
    }

    if (hit != null) {
      return {
        'country': '',
        'city': hit.name?.toLowerCase().capitalize ?? '',
        'name': hit.name?.toLowerCase().capitalize ?? '',
        'address': '',
        'flag': '🇺🇳',
      };
    }

    if (results.isEmpty) return null;

    final nearest = results.first;
    final record = _lookupRecord(nearest.location);
    return _buildResult(record, nearest.location, lat, lng);
  }
}
