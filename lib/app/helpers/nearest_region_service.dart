import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NearestRegionService {
  NearestRegionService._internal();
  static final NearestRegionService _instance =
      NearestRegionService._internal();
  factory NearestRegionService() => _instance;

  final List<Region> _regions = [];
  final List<_CityEntry> _cities = [];
  final Map<String, String> _admin1Names = {};
  final List<_AdminPolygon> _adminPolygons = [];
  bool _isLoaded = false;
  Future<void>? _loading;

  bool get isLoaded => _isLoaded;

  Future<void> loadFromAssets({
    String assetPath = 'assets/states.csv',
  }) async {
    if (_isLoaded) return;
    // Deduplicate concurrent callers (map + deferred startup).
    if (_loading != null) return _loading!;
    _loading = _loadFromAssetsImpl(assetPath);
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _loadFromAssetsImpl(String assetPath) async {
    if (_isLoaded) return;

    // Load bytes on UI isolate (fast), decode+parse on workers so cold-start
    // map taps are not blocked for 10s+ (Xiaomi ANR / input timeout).
    final statesBytes = await _assetBytes(assetPath);
    final citiesBytes = await _assetBytes('assets/cities500.csv');
    final admin1Bytes = await _assetBytes('assets/admin1codes.csv');
    final polygonsBytes = await _assetBytes('assets/geo/ne_10m_admin1.json');

    await Future<void>.delayed(Duration.zero);

    final regions = await Isolate.run(() => _parseStatesCsvBytes(statesBytes));
    await Future<void>.delayed(Duration.zero);
    final cities = await Isolate.run(() => _parseCities500CsvBytes(citiesBytes));
    await Future<void>.delayed(Duration.zero);
    final admin1 =
        await Isolate.run(() => _parseAdmin1CsvBytes(admin1Bytes));
    await Future<void>.delayed(Duration.zero);
    final polygons =
        await Isolate.run(() => _parseAdminPolygonsJsonBytes(polygonsBytes));

    _regions
      ..clear()
      ..addAll(regions);
    await _appendInChunks(_cities..clear(), cities);
    _admin1Names
      ..clear()
      ..addAll(admin1);
    await _appendInChunks(_adminPolygons..clear(), polygons);

    _isLoaded = true;
    debugPrint(
      '[NearestRegion] Loaded ${_cities.length} cities, '
      '${_admin1Names.length} admin1, ${_adminPolygons.length} polygons '
      '(off main isolate)',
    );
  }

  static Future<void> _appendInChunks<T>(List<T> target, List<T> source) async {
    const chunk = 8000;
    for (var i = 0; i < source.length; i += chunk) {
      final end = i + chunk > source.length ? source.length : i + chunk;
      target.addAll(source.sublist(i, end));
      await Future<void>.delayed(Duration.zero);
    }
  }

  static Future<Uint8List> _assetBytes(String path) async {
    final data = await rootBundle.load(path);
    // Copy so Isolate.run can transfer a standalone buffer (not a view).
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  String? findStateByPolygon(double lat, double lng, {String? countryCode}) {
    for (final poly in _adminPolygons) {
      if (lat < poly.minLat || lat > poly.maxLat) continue;
      if (lng < poly.minLng || lng > poly.maxLng) continue;
      if (countryCode != null &&
          countryCode.isNotEmpty &&
          poly.countryCode != countryCode) {
        continue;
      }
      for (final ring in poly.rings) {
        if (_pointInRing(lat, lng, ring)) {
          return poly.name;
        }
      }
    }
    return null;
  }

  bool _pointInRing(double lat, double lng, List<List<double>> ring) {
    bool inside = false;
    int j = ring.length - 1;
    for (int i = 0; i < ring.length; i++) {
      final xi = ring[i][0], yi = ring[i][1];
      final xj = ring[j][0], yj = ring[j][1];
      if (((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  Region? findNearest(double lat, double lng, {String? countryCode}) {
    if (!_isLoaded) return null;

    final polyState = findStateByPolygon(lat, lng, countryCode: countryCode);
    if (polyState != null) {
      final match = _regions
          .where(
            (r) =>
                r.name.toLowerCase() == polyState.toLowerCase() &&
                (countryCode == null ||
                    countryCode.isEmpty ||
                    r.countryCode == countryCode),
          )
          .toList();
      if (match.isNotEmpty) {
        return match.first;
      }
      return Region(
        id: 0,
        name: polyState,
        countryId: 0,
        countryCode: countryCode ?? '',
        countryName: '',
        iso2: '',
        iso3166_2: '',
        fipsCode: '',
        type: 'polygon-derived',
        level: '',
        parentId: null,
        nativeName: '',
        latitude: lat,
        longitude: lng,
        timezone: '',
        wikiDataId: '',
        population: 0,
      );
    }

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

    if (countryCode != null && countryCode.isNotEmpty) {
      final countryMatches = candidates
          .where((c) => c.region.countryCode == countryCode)
          .toList();
      if (countryMatches.isNotEmpty) {
        return countryMatches.first.region;
      }
    }

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
      c.score = 1.0 / (1.0 + c.distance) +
          (c.city.population > 0
              ? log(c.city.population.toDouble()) / 20.0
              : 0.0);
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));

    if (countryCode != null && countryCode.isNotEmpty) {
      final countryMatches = candidates
          .where((c) => c.city.countryCode == countryCode)
          .toList();
      if (countryMatches.isNotEmpty) candidates = countryMatches;
    }

    final best = candidates.first;
    final admin1Key = '${best.city.countryCode}.${best.city.admin1}';
    final stateName = _admin1Names[admin1Key] ?? best.city.admin1;

    final matchingRegion = _regions
        .where(
          (r) =>
              r.countryCode == best.city.countryCode &&
              (r.name.toLowerCase() == stateName.toLowerCase() ||
                  r.iso2.toLowerCase() == best.city.admin1.toLowerCase()),
        )
        .toList();

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
    final popBonus = c.region.population > 0
        ? log(c.region.population.toDouble()) / 20.0
        : 0.0;
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

List<Region> _parseStatesCsvBytes(Uint8List bytes) =>
    _parseStatesCsv(utf8.decode(bytes));

List<_CityEntry> _parseCities500CsvBytes(Uint8List bytes) =>
    _parseCities500Csv(utf8.decode(bytes));

Map<String, String> _parseAdmin1CsvBytes(Uint8List bytes) =>
    _parseAdmin1Csv(utf8.decode(bytes));

List<_AdminPolygon> _parseAdminPolygonsJsonBytes(Uint8List bytes) =>
    _parseAdminPolygonsJson(utf8.decode(bytes));

List<Region> _parseStatesCsv(String raw) {
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(raw);
  final out = <Region>[];
  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length < 17) continue;
    out.add(
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
  return out;
}

List<_CityEntry> _parseCities500Csv(String raw) {
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(raw);
  final out = <_CityEntry>[];
  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length < 7) continue;
    out.add(
      _CityEntry(
        name: row[0].toString(),
        latitude: double.tryParse(row[1].toString()) ?? 0.0,
        longitude: double.tryParse(row[2].toString()) ?? 0.0,
        countryCode: row[3].toString(),
        admin1: row[4].toString(),
        admin2: row[5].toString(),
        population: int.tryParse(row[6].toString()) ?? 0,
      ),
    );
  }
  return out;
}

Map<String, String> _parseAdmin1Csv(String raw) {
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(raw);
  final out = <String, String>{};
  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length < 2) continue;
    out[row[0].toString()] = row[1].toString();
  }
  return out;
}

List<_AdminPolygon> _parseAdminPolygonsJson(String raw) {
  final geojson = jsonDecode(raw) as Map<String, dynamic>;
  final features = geojson['features'] as List;
  final out = <_AdminPolygon>[];
  for (final f in features) {
    final props = f['properties'] as Map<String, dynamic>;
    final geom = f['geometry'] as Map<String, dynamic>;
    final name = props['n']?.toString() ?? '';
    final cc = props['c']?.toString() ?? '';
    final type = geom['type']?.toString() ?? '';

    final polygons = <List<List<double>>>[];
    if (type == 'Polygon') {
      final coords = geom['coordinates'] as List;
      for (final ring in coords) {
        polygons.add(
          (ring as List)
              .map(
                (p) => [
                  (p[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ],
              )
              .toList(),
        );
      }
    } else if (type == 'MultiPolygon') {
      final multiCoords = geom['coordinates'] as List;
      for (final poly in multiCoords) {
        for (final ring in (poly as List)) {
          polygons.add(
            (ring as List)
                .map(
                  (p) => [
                    (p[0] as num).toDouble(),
                    (p[1] as num).toDouble(),
                  ],
                )
                .toList(),
          );
        }
      }
    }

    if (polygons.isEmpty) continue;

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final ring in polygons) {
      for (final pt in ring) {
        if (pt[1] < minLat) minLat = pt[1];
        if (pt[1] > maxLat) maxLat = pt[1];
        if (pt[0] < minLng) minLng = pt[0];
        if (pt[0] > maxLng) maxLng = pt[0];
      }
    }
    out.add(
      _AdminPolygon(
        name: name,
        countryCode: cc,
        rings: polygons,
        minLat: minLat,
        maxLat: maxLat,
        minLng: minLng,
        maxLng: maxLng,
      ),
    );
  }
  return out;
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
  final String admin2;
  final int population;
  _CityEntry({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.countryCode,
    required this.admin1,
    required this.admin2,
    required this.population,
  });
}

class _RankedCity {
  final _CityEntry city;
  final double distance;
  double score;
  _RankedCity(this.city, this.distance, {this.score = 0.0});
}

class _AdminPolygon {
  final String name;
  final String countryCode;
  final List<List<List<double>>> rings;
  final double minLat, maxLat, minLng, maxLng;
  _AdminPolygon({
    required this.name,
    required this.countryCode,
    required this.rings,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });
}
