import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:spacetime/app/utils/memory_sort.dart';
import 'package:spacetime/services/memory_geojson_service.dart';

/// Prebuilt Mapbox GeoJSON strings for clustering + timeline arrows.
class MemoryMapLayerPayload {
  const MemoryMapLayerPayload({
    required this.clusteringGeoJson,
    required this.arrowLinesGeoJson,
    required this.arrowPointsGeoJson,
  });

  final String clusteringGeoJson;
  final String arrowLinesGeoJson;
  final String arrowPointsGeoJson;
}

/// Builds heavy map payloads off the UI isolate when the library is large.
class MemoryMapIsolate {
  MemoryMapIsolate._();

  /// Below this count, isolate spawn + copy cost outweighs the win.
  static const int isolateThreshold = 80;

  /// Spread identical coordinates slightly so stacked pins are tappable.
  /// Runs in a background isolate for large libraries.
  static Future<List<Map<String, dynamic>>> spreadOverlappingMemories(
    List<Map<String, dynamic>> memories,
  ) async {
    if (memories.length < isolateThreshold) {
      return spreadOverlappingMemoriesSync(memories);
    }
    // Copy maps so the isolate can mutate lat/lng without touching UI objects.
    final copies = [for (final m in memories) Map<String, dynamic>.from(m)];
    return Isolate.run(() => spreadOverlappingMemoriesSync(copies));
  }

  static List<Map<String, dynamic>> spreadOverlappingMemoriesSync(
    List<Map<String, dynamic>> memories,
  ) {
    if (memories.isEmpty) return memories;

    final locationGroups = <String, List<Map<String, dynamic>>>{};
    final memoriesWithoutLocation = <Map<String, dynamic>>[];

    for (final memory in memories) {
      final lat = _toDouble(memory['location_latitude']);
      final lng = _toDouble(memory['location_longitude']);
      if (lat == null || lng == null) {
        memoriesWithoutLocation.add(memory);
        continue;
      }
      final locationKey = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
      locationGroups.putIfAbsent(locationKey, () => []).add(memory);
    }

    final spreadMemories = <Map<String, dynamic>>[];
    final random = math.Random();

    for (final group in locationGroups.values) {
      if (group.length == 1) {
        spreadMemories.add(group.first);
        continue;
      }
      for (var i = 0; i < group.length; i++) {
        final memory = Map<String, dynamic>.from(group[i]);
        final originalLat = _toDouble(memory['location_latitude']);
        final originalLng = _toDouble(memory['location_longitude']);
        if (originalLat == null || originalLng == null) {
          spreadMemories.add(memory);
          continue;
        }
        const offsetMeters = 2.0;
        const metersPerDegreeLat = 111320.0;
        final angle = random.nextDouble() * 2 * math.pi;
        final distance = random.nextDouble() * offsetMeters;
        final latOffset = (distance * math.cos(angle)) / metersPerDegreeLat;
        final lngOffset =
            (distance * math.sin(angle)) /
            (metersPerDegreeLat * math.cos(originalLat * math.pi / 180));
        memory['location_latitude'] = originalLat + latOffset;
        memory['location_longitude'] = originalLng + lngOffset;
        spreadMemories.add(memory);
      }
    }

    spreadMemories.addAll(memoriesWithoutLocation);
    return spreadMemories;
  }

  static Future<MemoryMapLayerPayload> buildLayers({
    required List<Map<String, dynamic>> memories,
    required List<Map<String, dynamic>> allMemoriesForColors,
  }) async {
    final slimMemories = memories
        .map(_slimMemoryForMap)
        .toList(growable: false);
    final slimAll = allMemoriesForColors
        .map(_slimYearOnly)
        .toList(growable: false);

    if (slimMemories.length < isolateThreshold) {
      return buildLayersSync(slimMemories, slimAll);
    }

    return Isolate.run(() => buildLayersSync(slimMemories, slimAll));
  }

  /// Pure CPU work — safe for [Isolate.run] / [compute].
  static MemoryMapLayerPayload buildLayersSync(
    List<Map<String, dynamic>> memories,
    List<Map<String, dynamic>> allMemoriesForColors,
  ) {
    final clusteringGeoJson = MemoryGeoJsonService.createGeoJsonFromMemories(
      memories,
      allMemoriesForColors,
    );
    final arrows = _buildArrowFeatureCollections(
      memories,
      allMemoriesForColors,
    );
    return MemoryMapLayerPayload(
      clusteringGeoJson: clusteringGeoJson,
      arrowLinesGeoJson: arrows.linesJson,
      arrowPointsGeoJson: arrows.pointsJson,
    );
  }

  static Map<String, dynamic> _slimYearOnly(Map<String, dynamic> memory) {
    return {'year': memory['year']};
  }

  static Map<String, dynamic> _slimMemoryForMap(Map<String, dynamic> memory) {
    final images = memory['images'];
    final audios = memory['audios'];
    return {
      'id': memory['id'],
      'year': memory['year'],
      'date': memory['date'],
      'time': memory['time'],
      'category': memory['category'],
      'text': memory['text'],
      'description': memory['description'],
      'memory_date': memory['memory_date'] ?? memory['date'],
      'location_latitude': _toDouble(memory['location_latitude']),
      'location_longitude': _toDouble(memory['location_longitude']),
      'location_name': memory['location_name'] ?? '',
      'location_address': memory['location_address'] ?? '',
      'location_city': memory['location_city'] ?? '',
      'location_country': memory['location_country'] ?? '',
      // Length only — avoids copying media path lists into the isolate.
      'images':
          images is List ? List.filled(images.length, '') : const <String>[],
      'audios':
          audios is List ? List.filled(audios.length, '') : const <String>[],
      'created_at': memory['created_at'],
      'updated_at': memory['updated_at'],
    };
  }

  static double? _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static ({String linesJson, String pointsJson}) _buildArrowFeatureCollections(
    List<Map<String, dynamic>> memories,
    List<Map<String, dynamic>> allMemoriesForColors,
  ) {
    if (memories.length < 2) {
      return (
        linesJson: jsonEncode({
          'type': 'FeatureCollection',
          'features': <Map<String, dynamic>>[],
        }),
        pointsJson: jsonEncode({
          'type': 'FeatureCollection',
          'features': <Map<String, dynamic>>[],
        }),
      );
    }

    const arrowPositionFactor = 0.65;
    const densifySegments = 120;

    final parsedDates = <int, DateTime?>{};
    final fallbackKeys = <int, String>{};
    for (var i = 0; i < memories.length; i++) {
      parsedDates[i] = MemorySort.parseMemoryDateTime(memories[i]);
      fallbackKeys[i] = MemorySort.memorySortKey(memories[i]);
    }

    final indices = List<int>.generate(memories.length, (i) => i);
    indices.sort((a, b) {
      final aDate = parsedDates[a];
      final bDate = parsedDates[b];
      if (aDate != null && bDate != null) return aDate.compareTo(bDate);
      if (aDate != null) return -1;
      if (bDate != null) return 1;
      return fallbackKeys[a]!.compareTo(fallbackKeys[b]!);
    });

    final sorted = [for (final i in indices) memories[i]];
    final colorIndexes = MemoryGeoJsonService.buildColorIndexLookup(
      allMemoriesForColors,
    );
    final colors = MemoryGeoJsonService.colors;

    final locationPairs = <String, int>{};
    final bidirectionalIndices = <int>{};

    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      final startLat = _toDouble(a['location_latitude']);
      final startLng = _toDouble(a['location_longitude']);
      final endLat = _toDouble(b['location_latitude']);
      final endLng = _toDouble(b['location_longitude']);
      if (startLat == null ||
          startLng == null ||
          endLat == null ||
          endLng == null) {
        continue;
      }

      final loc1 =
          '${startLat.toStringAsFixed(6)},${startLng.toStringAsFixed(6)}';
      final loc2 = '${endLat.toStringAsFixed(6)},${endLng.toStringAsFixed(6)}';
      if (loc1 == loc2) continue;

      final pairKey =
          loc1.compareTo(loc2) < 0 ? '$loc1->$loc2' : '$loc2->$loc1';
      if (locationPairs.containsKey(pairKey)) {
        bidirectionalIndices.add(i);
        bidirectionalIndices.add(locationPairs[pairKey]!);
      } else {
        locationPairs[pairKey] = i;
      }
    }

    final lineFeatures = <Map<String, dynamic>>[];
    final arrowPointFeatures = <Map<String, dynamic>>[];

    for (var i = 0; i < sorted.length - 1; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      final memoryDate =
          DateTime.tryParse('${b['date'] ?? ''}') ?? DateTime.now();
      final yearForColor =
          int.tryParse('${b['year'] ?? ''}') ?? memoryDate.year;
      final index =
          colorIndexes[yearForColor] ?? yearForColor.abs() % colors.length;

      final startLat = _toDouble(a['location_latitude']);
      final startLng = _toDouble(a['location_longitude']);
      final endLat = _toDouble(b['location_latitude']);
      final endLng = _toDouble(b['location_longitude']);
      if (startLat == null ||
          startLng == null ||
          endLat == null ||
          endLng == null) {
        continue;
      }

      final coords = _densifyLine(
        start: [startLng, startLat],
        end: [endLng, endLat],
        segments: densifySegments,
      );
      if (coords.length < 5) continue;

      lineFeatures.add({
        'type': 'Feature',
        'id': 'line_$i',
        'geometry': {'type': 'LineString', 'coordinates': coords},
        'properties': {'type': 'line', 'color': colors[index]},
      });

      if (!bidirectionalIndices.contains(i)) {
        final arrowIndex = (coords.length * arrowPositionFactor).round().clamp(
          1,
          coords.length - 1,
        );
        final base = coords[arrowIndex - 1];
        final tip = coords[arrowIndex];
        arrowPointFeatures.add({
          'type': 'Feature',
          'id': 'arrow_$i',
          'geometry': {'type': 'Point', 'coordinates': tip},
          'properties': {
            'rotation': _bearingBetween(base, tip),
            'color': colors[index],
          },
        });
      }
    }

    return (
      linesJson: jsonEncode({
        'type': 'FeatureCollection',
        'features': lineFeatures,
      }),
      pointsJson: jsonEncode({
        'type': 'FeatureCollection',
        'features': arrowPointFeatures,
      }),
    );
  }

  static List<List<double>> _densifyLine({
    required List<double> start,
    required List<double> end,
    int segments = 100,
  }) {
    final result = <List<double>>[];
    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      result.add([
        start[0] + (end[0] - start[0]) * t,
        start[1] + (end[1] - start[1]) * t,
      ]);
    }
    return result;
  }

  static double _bearingBetween(List<double> start, List<double> end) {
    final lat1 = start[1] * math.pi / 180;
    final lon1 = start[0] * math.pi / 180;
    final lat2 = end[1] * math.pi / 180;
    final lon2 = end[0] * math.pi / 180;

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    var brng = math.atan2(y, x) * 180 / math.pi;
    if (brng < 0) brng += 360;
    return brng;
  }
}
