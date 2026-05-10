import 'dart:math' show min;

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:spacetime/app/utils/place_categories_utils.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';

/// True when [geo] has any human-readable place field from reverse geocode.
bool trackPreviewGeoHasPlace(Map<String, dynamic>? geo) {
  if (geo == null) return false;
  for (final k in ['name', 'city', 'country', 'address']) {
    if ((geo[k] ?? '').toString().trim().isNotEmpty) return true;
  }
  return false;
}

/// Single-line label for preview cards (flag prefix optional).
String trackPreviewComposeLine(Map<String, dynamic> geo) {
  final flag = (geo['flag'] as String? ?? '').trim();
  final name = (geo['name'] as String? ?? '').trim();
  final city = (geo['city'] as String? ?? '').trim();
  final country = (geo['country'] as String? ?? '').trim();
  var primary = name;
  if (primary.isEmpty) primary = city;
  if (primary.isEmpty) primary = country;
  if (primary.isEmpty) primary = (geo['address'] as String? ?? '').trim();
  if (primary.isEmpty) return '';
  return flag.isEmpty ? primary : '$flag $primary';
}

bool trackPreviewIsPlaceholderLine(String text) {
  final t = text.trim();
  return t.isEmpty || t == 'Region';
}

String trackPreviewCoordinateLine(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

String trackPreviewCoordKey(double lat, double lng) =>
    '${lat.toStringAsFixed(4)}_${lng.toStringAsFixed(4)}';

/// One resolved line per coordinate row (shared coords reuse one lookup). Bounded parallelism.
Future<List<String>> resolveTrackPreviewLocationLinesOrdered(
  List<({double lat, double lng})> coordinates, {
  int maxConcurrent = 6,
}) async {
  if (coordinates.isEmpty) return [];
  final unique = <String, ({double lat, double lng})>{};
  for (final c in coordinates) {
    unique.putIfAbsent(trackPreviewCoordKey(c.lat, c.lng), () => c);
  }
  final entries = unique.entries.toList();
  final resolved = <String, String>{};
  for (var start = 0; start < entries.length; start += maxConcurrent) {
    final end = min(start + maxConcurrent, entries.length);
    final slice = entries.sublist(start, end);
    await Future.wait(
      slice.map((e) async {
        resolved[e.key] =
            await resolveTrackPreviewLocationLine(e.value.lat, e.value.lng);
      }),
    );
  }
  return coordinates
      .map((c) => resolved[trackPreviewCoordKey(c.lat, c.lng)]!)
      .toList();
}

/// Retries (offline geocoder can be cold / briefly empty), then coordinates — never `"Region"`.
Future<String> resolveTrackPreviewLocationLine(
  double latitude,
  double longitude,
) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      final geo = await reverseGeocodeTrackPreview(latitude, longitude).timeout(
        Duration(seconds: 12 + attempt * 2),
        onTimeout: () => null,
      );
      if (geo != null && trackPreviewGeoHasPlace(geo)) {
        final line = trackPreviewComposeLine(geo);
        if (!trackPreviewIsPlaceholderLine(line)) return line;
      }
    } catch (e, st) {
      debugPrint('[resolveTrackPreviewLocationLine] attempt $attempt: $e\n$st');
    }
    await Future<void>.delayed(Duration(milliseconds: 250 + attempt * 100));
  }
  return trackPreviewCoordinateLine(latitude, longitude);
}

/// Reverse-geocode for track previews without requiring [MemoryController] /
/// map bootstrap (GPX/KMZ opened from Data/settings).
Future<Map<String, dynamic>?> reverseGeocodeTrackPreview(
  double latitude,
  double longitude,
) async {
  try {
    if (!Get.isRegistered<GeocodingIsolateService>()) {
      Get.put(GeocodingIsolateService(), permanent: true);
    }
    final svc = GeocodingIsolateService.instance;
    final ok = await svc.ensureInitialized();
    if (!ok) {
      debugPrint(
        '[reverseGeocodeTrackPreview] GeocodingIsolateService not initialized',
      );
      return null;
    }
    final raw = await svc.reverseGeocode(latitude, longitude);
    if (raw == null) {
      debugPrint(
        '[reverseGeocodeTrackPreview] null result for $latitude,$longitude',
      );
      return null;
    }
    final country = (raw['country'] ?? '').toString().trim();
    var flag = (raw['flag'] ?? '').toString().trim();
    if (flag.isEmpty && country.isNotEmpty) {
      flag = countryFlags[country.toLowerCase()] ?? '';
    }
    return <String, dynamic>{
      ...raw,
      'country': country,
      'flag': flag,
    };
  } catch (e, st) {
    debugPrint('[reverseGeocodeTrackPreview] $e\n$st');
    return null;
  }
}
