import 'dart:math';
import 'package:flutter/services.dart';
import 'package:csv/csv.dart';

class NearestRegionService {
  NearestRegionService._internal();
  static final NearestRegionService _instance =
      NearestRegionService._internal();
  factory NearestRegionService() => _instance;

  final List<Region> _regions = [];
  final List<_CityEntry> _cities = [];
  final Map<String, String> _admin1Names = {};
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

    await _loadCities500();
    await _loadAdmin1Codes();

    _isLoaded = true;
  }

  Future<void> _loadCities500() async {
    try {
      final raw = await rootBundle.loadString('assets/cities500.csv');
      final rows = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(raw);
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 6) continue;
        _cities.add(_CityEntry(
          name: row[0].toString(),
          latitude: double.tryParse(row[1].toString()) ?? 0.0,
          longitude: double.tryParse(row[2].toString()) ?? 0.0,
          countryCode: row[3].toString(),
          admin1: row[4].toString(),
          population: int.tryParse(row[5].toString()) ?? 0,
        ));
      }
      print('[NearestRegion] Loaded ${_cities.length} cities from cities500');
    } catch (e) {
      print('[NearestRegion] Failed to load cities500: $e');
    }
  }

  Future<void> _loadAdmin1Codes() async {
    try {
      final raw = await rootBundle.loadString('assets/admin1codes.csv');
      final rows = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(raw);
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 2) continue;
        _admin1Names[row[0].toString()] = row[1].toString();
      }
      print('[NearestRegion] Loaded ${_admin1Names.length} admin1 codes');
    } catch (e) {
      print('[NearestRegion] Failed to load admin1codes: $e');
    }
  }

  Region? findNearest(double lat, double lng, {String? countryCode}) {
    if (!_isLoaded) return null;

    if (_cities.isNotEmpty) {
      final cityResult = _findNearestCity(lat, lng, countryCode: countryCode);
      if (cityResult != null) return cityResult;
    }

    if (_regions.isEmpty) return null;

    final radii = [50.0, 150.0, 500.0, 1500.0, double.infinity];
    var candidates = <_RankedRegion>[];

    for (final maxDist in radii) {
      candidates.clear();
      for (final r in _regions) {
        if (maxDist != double.infinity) {
          final dLat = (r.latitude - lat).abs();
          final dLng = (r.longitude - lng).abs();
          if (dLat > maxDist / 80 || dLng > maxDist / 80) continue;
        }
        final d = _distance(lat, lng, r.latitude, r.longitude);
        if (d <= maxDist) candidates.add(_RankedRegion(r, d));
      }
      if (candidates.isNotEmpty) break;
    }

    if (candidates.isEmpty) return null;

    for (final c in candidates) {
      c.score = _calcScore(c);
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));

    print('[NearestRegion] Query: $lat, $lng | countryCode: $countryCode | found: ${candidates.length}');
    for (int i = 0; i < candidates.length && i < 10; i++) {
      final c = candidates[i];
      print('[NearestRegion] #${i + 1}: ${c.region.name}, ${c.region.countryName} (${c.region.countryCode}) | dist: ${c.distance.toStringAsFixed(2)} km | score: ${c.score.toStringAsFixed(4)}');
    }

    if (countryCode != null && countryCode.isNotEmpty) {
      final countryMatches = candidates.where((c) => c.region.countryCode == countryCode).toList();
      if (countryMatches.isNotEmpty) {
        print('[NearestRegion] Selected(state): ${countryMatches.first.region.name} | dist: ${countryMatches.first.distance.toStringAsFixed(2)} km');
        return countryMatches.first.region;
      }
    }

    print('[NearestRegion] Selected(state): ${candidates.first.region.name}');
    return candidates.first.region;
  }

  Region? _findNearestCity(double lat, double lng, {String? countryCode}) {
    final radii = [50.0, 150.0, 500.0, 1500.0, double.infinity];
    var candidates = <_RankedCity>[];

    for (final maxDist in radii) {
      candidates.clear();
      for (final c in _cities) {
        if (maxDist != double.infinity) {
          final dLat = (c.latitude - lat).abs();
          final dLng = (c.longitude - lng).abs();
          if (dLat > maxDist / 80 || dLng > maxDist / 80) continue;
        }
        final d = _distance(lat, lng, c.latitude, c.longitude);
        if (d <= maxDist) candidates.add(_RankedCity(c, d));
      }
      if (candidates.isNotEmpty) break;
    }

    if (candidates.isEmpty) return null;

    for (final c in candidates) {
      c.score = 1.0 / (1.0 + c.distance) + (c.city.population > 0 ? log(c.city.population.toDouble()) / 20.0 : 0.0);
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));

    if (countryCode != null && countryCode.isNotEmpty) {
      final countryMatches = candidates.where((c) => c.city.countryCode == countryCode).toList();
      if (countryMatches.isNotEmpty) candidates = countryMatches;
    }

    print('[NearestCity] Query: $lat, $lng | found: ${candidates.length}');
    for (int i = 0; i < candidates.length && i < 10; i++) {
      final c = candidates[i];
      final admin1Key = '${c.city.countryCode}.${c.city.admin1}';
      final stateName = _admin1Names[admin1Key] ?? c.city.admin1;
      print('[NearestCity] #${i + 1}: ${c.city.name} (${c.city.countryCode}) | admin1: $stateName | pop: ${c.city.population} | dist: ${c.distance.toStringAsFixed(2)} km | score: ${c.score.toStringAsFixed(4)}');
    }

    final best = candidates.first;
    final admin1Key = '${best.city.countryCode}.${best.city.admin1}';
    final stateName = _admin1Names[admin1Key] ?? best.city.admin1;

    print('[NearestCity] Selected: ${best.city.name} -> state: $stateName | dist: ${best.distance.toStringAsFixed(2)} km');

    final matchingRegion = _regions.where((r) =>
      r.countryCode == best.city.countryCode &&
      (r.name.toLowerCase() == stateName.toLowerCase() ||
       r.iso2.toLowerCase() == best.city.admin1.toLowerCase())
    ).toList();

    if (matchingRegion.isNotEmpty) return matchingRegion.first;

    return Region(
      id: 0,
      name: stateName,
      countryId: 0,
      countryCode: best.city.countryCode,
      countryName: '',
      iso2: best.city.admin1,
      iso3166_2: '',
      fipsCode: '',
      type: 'city-derived',
      level: '',
      parentId: null,
      nativeName: '',
      latitude: best.city.latitude,
      longitude: best.city.longitude,
      timezone: '',
      wikiDataId: '',
      population: best.city.population,
    );
  }

  double _calcScore(_RankedRegion c) {
    final distPenalty = 1.0 / (1.0 + c.distance);
    final popBonus = c.region.population > 0 ? log(c.region.population.toDouble()) / 20.0 : 0.0;
    return distPenalty + popBonus;
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


class _RankedRegion {
  final Region region;
  final double distance;
  double score;
  _RankedRegion(this.region, this.distance, {this.score = 0.0});
}

class _CityEntry {
  final String name;
  final double latitude;
  final double longitude;
  final String countryCode;
  final String admin1;
  final int population;
  _CityEntry({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.countryCode,
    required this.admin1,
    required this.population,
  });
}

class _RankedCity {
  final _CityEntry city;
  final double distance;
  double score;
  _RankedCity(this.city, this.distance, {this.score = 0.0});
}