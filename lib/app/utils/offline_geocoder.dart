import 'dart:math';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:geocoder_offline_json/geocoder_offline.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/helpers/nearest_region_service.dart';
import 'package:spacetime/app/helpers/offline_water_service.dart';
import 'package:spacetime/app/utils/place_categories_utils.dart';
import 'package:spacetime/services/mbtiles_geocoder_service.dart';

/// Plain, isolate-transferable result of parsing the 151k-row/13MB
/// cities_names_1.csv — see [_parseGeocodingDataInBackground].
class _ParsedGeocodingData {
  _ParsedGeocodingData({required this.cityLookupRows, required this.kdTreeJson});

  /// coordKey -> [name, stateName, countryName, countryCode, lat, lng]
  final Map<String, List<Object?>> cityLookupRows;
  final Map<String, dynamic> kdTreeJson;
}

/// Top-level so it can run via [compute] in a background isolate. Does the
/// SAME work [OfflineGeocoder.init] used to do directly on the main/UI
/// isolate: parse a 151,166-row, 13MB CSV (twice — once for the lookup map,
/// once more inside GeocodeData's own constructor) and build a KD-tree.
/// That was a genuine multi-second synchronous, CPU-bound block on the UI
/// isolate during every app startup — confirmed on a real device via
/// [MapInitTiming] logs showing a ~13s gap with zero other activity, ending
/// exactly when this init logged completion. Only the small serialized
/// results below cross back to the main isolate; GeocodeData supports this
/// via its own toJson()/fromJson(), which wraps a serializable KDTree.
_ParsedGeocodingData _parseGeocodingDataInBackground(String dataString) {
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(dataString);

  final cityLookupRows = <String, List<Object?>>{};
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
      final key = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
      cityLookupRows[key] = [
        row[nameIdx].toString(),
        stateNameIdx >= 0 ? row[stateNameIdx].toString() : '',
        row[countryNameIdx].toString(),
        countryCodeIdx >= 0 ? row[countryCodeIdx].toString() : '',
        lat,
        lng,
      ];
    }
  }

  final geocoder = GeocodeData(
    dataString,
    'name',
    'country_name',
    'latitude',
    'longitude',
    fieldDelimiter: ',',
    eol: '\n',
    numMarkers: 48,
  );

  return _ParsedGeocodingData(
    cityLookupRows: cityLookupRows,
    kdTreeJson: geocoder.toJson(),
  );
}

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

    // CSV parsing (151,166 rows / 13MB, done twice — once here, once more
    // inside GeocodeData's own constructor) + KD-tree construction used to
    // run directly on the main/UI isolate and blocked it for several
    // seconds on every cold start. Runs in a background isolate now; only
    // the small serialized results cross back.
    final parsed = await compute(_parseGeocodingDataInBackground, dataString);

    for (final entry in parsed.cityLookupRows.entries) {
      final row = entry.value;
      _cityLookup[entry.key] = _CityRecord(
        name: row[0] as String,
        stateName: row[1] as String,
        countryName: row[2] as String,
        countryCode: row[3] as String,
        latitude: row[4] as double,
        longitude: row[5] as double,
      );
    }

    geocoder = GeocodeData.fromJson(parsed.kdTreeJson, numMarkers: 48);
    _isInitialized = true;

    try {
      // await MbtilesGeocoderService.instance.init();
    } catch (_) {}
  }

  _CityRecord? _lookupRecord(LocationData loc) {
    if (loc.latitude == null || loc.longitude == null) return null;
    return _cityLookup[_coordKey(loc.latitude!, loc.longitude!)];
  }

  String _resolveRegion(String stateName, String countryCode, double lat, double lng) {
    final region = NearestRegionService().findNearest(lat, lng, countryCode: countryCode);
    if (region != null) return region.name;
    if (stateName.isNotEmpty) return stateName;
    return '';
  }

  Map<String, dynamic> _buildResult(_CityRecord? record, LocationData loc, double lat, double lng, {String? tileSubRegion}) {
    final city = record?.name ?? loc.featureName ?? '';
    final country = record?.countryName ?? loc.state ?? '';
    final stateName = record?.stateName ?? '';
    final countryCode = record?.countryCode ?? '';
    final flag = countryFlags[country.toLowerCase()] ?? '';

    final regionName = _resolveRegion(stateName, countryCode, lat, lng);

    String city1;
    if (tileSubRegion != null && tileSubRegion.isNotEmpty) {
      // Do not append NearestRegionService admin (e.g. "Oslo") to local tile names
      // (e.g. "Røst") — that produced invalid "Røst, Oslo" at sea.
      city1 = tileSubRegion;
    } else {
      city1 = (regionName.isNotEmpty && !city.contains(regionName))
          ? '$city, $regionName'
          : city;
    }

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

  Future<Map<String, dynamic>?> reverseGeocode(double lat, double lng, {String? tileSubRegion}) async {
    final results = geocoder.search(lat, lng);

    if (results.isNotEmpty) {
      LocationResult? best;
      double bestDist = double.infinity;
      for (final r in results) {
        if (r.location.latitude == null || r.location.longitude == null) continue;
        final d = _haversineKm(lat, lng, r.location.latitude!, r.location.longitude!);
        if (d < bestDist) {
          bestDist = d;
          best = r;
        }
      }
      if (best != null && bestDist < 50) {
        final record = _lookupRecord(best.location);
        return _buildResult(record, best.location, lat, lng, tileSubRegion: tileSubRegion);
      }
    }

    if (results.isEmpty) return null;

    LocationResult? fallback;
    double fallbackDist = double.infinity;
    for (final r in results) {
      if (r.location.latitude == null || r.location.longitude == null) continue;
      final d = _haversineKm(lat, lng, r.location.latitude!, r.location.longitude!);
      if (d < fallbackDist) {
        fallbackDist = d;
        fallback = r;
      }
    }
    if (fallback == null) return null;
    final record = _lookupRecord(fallback.location);
    return _buildResult(record, fallback.location, lat, lng, tileSubRegion: tileSubRegion);
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
        sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}
