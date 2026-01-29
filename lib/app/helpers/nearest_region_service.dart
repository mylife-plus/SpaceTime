import 'dart:math';
import 'package:flutter/services.dart';

import 'package:csv/csv.dart';
// import 'package:flutter/services.dart';
class NearestRegionService {
  NearestRegionService._internal();
  static final NearestRegionService _instance =
      NearestRegionService._internal();
  factory NearestRegionService() => _instance;

  final List<Region> _regions = [];
  bool _isLoaded = false;


Future<void> loadFromAssets({
  String assetPath = 'assets/states.csv',
}) async {
  if (_isLoaded) return;

  final raw = await rootBundle.loadString(assetPath);

  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(raw);

  // Skip header
  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];

    if (row.length < 17) continue;

    _regions.add(
      Region(
        id: int.tryParse(row[0].toString()) ?? 0,
        name: row[1].toString(),
        countryId: int.tryParse(row[2].toString()) ?? 0,
        countryCode: row[3].toString(),
        countryName: row[4].toString(),
        iso2: row[5].toString(),
        iso3166_2: row[6].toString(),
        fipsCode: row[7].toString(),
        type: row[8].toString(),
        level: row[9].toString(),
        parentId: row[10].toString().isEmpty
            ? null
            : int.tryParse(row[10].toString()),
        nativeName: row[11].toString(),
        latitude: double.tryParse(row[12].toString()) ?? 0.0,
        longitude: double.tryParse(row[13].toString()) ?? 0.0,
        timezone: row[14].toString(),
        wikiDataId: row[15].toString(),
        population: row[16].toString().isEmpty
            ? 0
            : int.tryParse(row[16].toString()) ?? 0,
      ),
    );
  }

  _isLoaded = true;
}

  /// Find nearest STATE / PROVINCE
  Region? findNearest(double lat, double lng) {
    if (!_isLoaded || _regions.isEmpty) return null;

    const double step = 0.001;
    const double maxRadius = 5.0;

    double radius = 0.001;

    while (radius <= maxRadius) {
      Region? nearest;
      double minDistance = double.infinity;

      for (final region in _regions) {
        if ((region.latitude - lat).abs() > radius ||
            (region.longitude - lng).abs() > radius) {
          continue;
        }

        final distance = _distance(
          lat,
          lng,
          region.latitude,
          region.longitude,
        );

        if (distance < minDistance) {
          minDistance = distance;
          nearest = region;
        }
      }

      if (nearest != null) return nearest;
      radius += step;
    }

    // 🔁 Fallback: absolute nearest
    Region? fallback;
    double minDistance = double.infinity;

    for (final region in _regions) {
      final d = _distance(lat, lng, region.latitude, region.longitude);
      if (d < minDistance) {
        minDistance = d;
        fallback = region;
      }
    }

    return fallback;
  }

  /// Haversine distance (KM)
  double _distance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371.0;

    final dLat = _deg(lat2 - lat1);
    final dLon = _deg(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg(lat1)) *
            cos(_deg(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _deg(double d) => d * pi / 180;
}


class Region {
  final int id;
  final String name;
  final int countryId;
  final String countryCode;
  final String countryName;
  final String iso2;
  final String iso3166_2;
  final String fipsCode;
  final String type; // province / state
  final String level;
  final int? parentId;
  final String nativeName;
  final double latitude;
  final double longitude;
  final String timezone;
  final String wikiDataId;
  final int population;

  Region({
    required this.id,
    required this.name,
    required this.countryId,
    required this.countryCode,
    required this.countryName,
    required this.iso2,
    required this.iso3166_2,
    required this.fipsCode,
    required this.type,
    required this.level,
    required this.parentId,
    required this.nativeName,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.wikiDataId,
    required this.population,
  });

  /// Print all data (debug / detail screen)
  void printAll() {
    print('printAll ID: $id');
    print('printAll State Name: $name');
    print('printAll Native Name: $nativeName');
    print('printAll Country: $countryName ($countryCode)');
    print('printAll ISO2: $iso2');
    print('printAll ISO 3166-2: $iso3166_2');
    print('printAll FIPS Code: $fipsCode');
    print('printAll Type: $type');
    print('printAll Level: $level');
    print('printAll Parent ID: $parentId');
    print('printAll Latitude: $latitude');
    print('printAll Longitude: $longitude');
    print('printAll Timezone: $timezone');
    print('printAll Wikidata ID: $wikiDataId');
    print('printAll Population: $population');
  }
}
