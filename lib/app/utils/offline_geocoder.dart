import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:geocoder_offline_json/geocoder_offline.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spacetime/app/helpers/nearest_region_service.dart';
import 'package:spacetime/app/utils/place_categories_utils.dart';

const _kGeocoderAsset = 'assets/cities_names_1.csv';
const _kCacheVersion = 1;
const _kCacheFileName = 'offline_geocoder_cache_v1.json';

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

/// Decode disk cache JSON off the UI isolate.
/// [args] = { 'raw': String, 'srcLen': int }
_ParsedGeocodingData? _decodeGeocoderCache(Map<String, Object?> args) {
  final raw = args['raw'];
  final srcLen = args['srcLen'];
  if (raw is! String || srcLen is! int) return null;
  final decoded = jsonDecode(raw);
  if (decoded is! Map) return null;
  final map = Map<String, dynamic>.from(decoded);
  if (map['v'] != _kCacheVersion) return null;
  if (map['srcLen'] != srcLen) return null;
  final lookupRaw = map['lookup'];
  final kd = map['kd'];
  if (lookupRaw is! Map || kd is! Map) return null;

  final cityLookupRows = <String, List<Object?>>{};
  lookupRaw.forEach((key, value) {
    if (value is! List) return;
    cityLookupRows[key.toString()] = List<Object?>.from(value);
  });
  return _ParsedGeocodingData(
    cityLookupRows: cityLookupRows,
    kdTreeJson: Map<String, dynamic>.from(kd),
  );
}

/// Encode cache payload off the UI isolate.
String _encodeGeocoderCache(Map<String, dynamic> payload) =>
    jsonEncode(payload);

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
  Future<void>? _initFuture;
  final Map<String, _CityRecord> _cityLookup = {};

  bool get isInitialized => _isInitialized;

  String _coordKey(double lat, double lng) =>
      '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

  Future<void> init() async {
    if (_isInitialized) return;
    // Deduplicate concurrent callers (Add Memories + location picker +
    // GeocodingIsolateService.onInit used to race and each parse the 13MB CSV).
    if (_initFuture != null) return _initFuture!;
    _initFuture = _initImpl();
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  /// True when a valid on-disk KD-tree cache already exists for the bundled CSV.
  Future<bool> hasValidDiskCache() async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return false;
      final assetLen = await _assetByteLength();
      final raf = await file.open();
      try {
        final headerBytes = await raf.read(512);
        final header = utf8.decode(headerBytes, allowMalformed: true);
        return header.contains('"v":$_kCacheVersion') &&
            header.contains('"srcLen":$assetLen');
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Parse + write disk cache if missing (safe to call during tiles download).
  Future<void> prefetchAndCacheIfNeeded() async {
    if (_isInitialized) return;
    if (await hasValidDiskCache()) {
      await init();
      return;
    }
    await init();
  }

  Future<File> _cacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_kCacheFileName');
  }

  Future<int> _assetByteLength() async {
    final data = await rootBundle.load(_kGeocoderAsset);
    return data.lengthInBytes;
  }

  Future<_ParsedGeocodingData?> _tryLoadDiskCache(int assetLen) async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final parsed = await compute(_decodeGeocoderCache, <String, Object?>{
        'raw': raw,
        'srcLen': assetLen,
      });
      if (parsed == null) {
        debugPrint('[OfflineGeocoder] Disk cache invalid/stale — rebuilding');
        return null;
      }
      debugPrint(
        '[OfflineGeocoder] Loaded disk cache '
        '(${parsed.cityLookupRows.length} cities)',
      );
      return parsed;
    } catch (e) {
      debugPrint('[OfflineGeocoder] Disk cache read failed: $e');
      return null;
    }
  }

  Future<void> _writeDiskCache(
    _ParsedGeocodingData parsed,
    int assetLen,
  ) async {
    try {
      final payload = <String, dynamic>{
        'v': _kCacheVersion,
        'srcLen': assetLen,
        'lookup': parsed.cityLookupRows,
        'kd': parsed.kdTreeJson,
      };
      final encoded = await compute(_encodeGeocoderCache, payload);
      final file = await _cacheFile();
      await file.writeAsString(encoded, flush: true);
      debugPrint(
        '[OfflineGeocoder] Disk cache written '
        '(${(encoded.length / (1024 * 1024)).toStringAsFixed(1)} MB)',
      );
    } catch (e) {
      debugPrint('[OfflineGeocoder] Disk cache write failed: $e');
    }
  }

  void _applyParsed(_ParsedGeocodingData parsed) {
    _cityLookup.clear();
    for (final entry in parsed.cityLookupRows.entries) {
      final row = entry.value;
      _cityLookup[entry.key] = _CityRecord(
        name: row[0] as String,
        stateName: row[1] as String,
        countryName: row[2] as String,
        countryCode: row[3] as String,
        latitude: (row[4] as num).toDouble(),
        longitude: (row[5] as num).toDouble(),
      );
    }
    geocoder = GeocodeData.fromJson(parsed.kdTreeJson, numMarkers: 48);
    _isInitialized = true;
  }

  Future<void> _initImpl() async {
    if (_isInitialized) return;
    final sw = Stopwatch()..start();
    final assetLen = await _assetByteLength();

    // Fast path: previously parsed KD-tree + city lookup on disk.
    final cached = await _tryLoadDiskCache(assetLen);
    if (cached != null) {
      _applyParsed(cached);
      debugPrint(
        '[OfflineGeocoder] Ready from cache in ${sw.elapsedMilliseconds}ms '
        '(${_cityLookup.length} cities)',
      );
      return;
    }

    // Cold path: parse CSV once, then persist for next launches.
    final dataString = await rootBundle.loadString(_kGeocoderAsset);
    final parsed = await compute(_parseGeocodingDataInBackground, dataString);
    _applyParsed(parsed);
    debugPrint(
      '[OfflineGeocoder] Ready in ${sw.elapsedMilliseconds}ms '
      '(${_cityLookup.length} cities, cold parse)',
    );
    // Await write so Get Started / warm-up know the cache is on disk.
    await _writeDiskCache(parsed, assetLen);
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
    await init();
    // Region suffix (e.g. "Islamabad, FCT") needs NearestRegionService. Its
    // findNearest() used to fire-and-forget load and return null on first
    // call — so the first memory after Get Started often had an empty /
    // incomplete name until a later lookup.
    await NearestRegionService().loadFromAssets();

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
