import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

class RadiusPolygonHelper {
  static const String sourceId = 'radius-polygon-source';
  static const String fillLayerId = 'radius-fill-layer';
  static const String outlineLayerId = 'radius-outline-layer';

  /// Generate geodesic circle polygon (meters)
  static Map<String, dynamic> generateCirclePolygon({
    required double lat,
    required double lng,
    required double radiusMeters,
    int points = 64,
  }) {
    const earthRadius = 6378137.0;
    final List<List<double>> coords = [];

    for (int i = 0; i <= points; i++) {
      final angle = (i * 360 / points) * pi / 180;
      final dx = radiusMeters * cos(angle);
      final dy = radiusMeters * sin(angle);

      final newLat = lat + (dy / earthRadius) * (180 / pi);
      final newLng =
          lng + (dx / earthRadius) * (180 / pi) /
              cos(lat * pi / 180);

      coords.add([newLng, newLat]);
    }

    return {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "geometry": {
            "type": "Polygon",
            "coordinates": [coords]
          }
        }
      ]
    };
  }

  /// Add radius polygon (MapTiler-safe)
  static Future<void> addRadiusPolygon({
    required mapbox.MapboxMap map,
    required double lat,
    required double lng,
    required double radiusMeters,
  }) async {
    final geoJson = generateCirclePolygon(
      lat: lat,
      lng: lng,
      radiusMeters: radiusMeters,
    );

    await clearRadiusPolygon(map);

    // Add source
    await map.style.addSource(
      mapbox.GeoJsonSource(
        id: sourceId,
        data: geoJson.toString(),
      ),
    );

    // Add fill layer
    await map.style.addLayer(
      mapbox.FillLayer(
        id: fillLayerId,
        sourceId: sourceId,
        fillColor: Colors.blue.withOpacity(0.25).value,
        fillOutlineColor: Colors.blue.value,
      ),
    );

    // Add outline layer
    await map.style.addLayer(
      mapbox.LineLayer(
        id: outlineLayerId,
        sourceId: sourceId,
        lineColor: Colors.blue.value,
        lineWidth: 2.0,
      ),
    );

    // 🔑 Move layers BELOW label layers (best for MapTiler OSM)
    await _moveBelowLabels(map);
  }

  /// Move polygon below label layers
  static Future<void> _moveBelowLabels(mapbox.MapboxMap map) async {
    final style = map.style;
    final layers = await style.getStyleLayers();

    // Try to find label layers dynamically
    final labelLayer = layers.firstWhere(
      (l) =>
          l!.id.contains('label') ||
          l!.id.contains('place') ||
          l!.id.contains('name'),
      orElse: () => layers.last,
    );

    await style.moveStyleLayer(fillLayerId,  mapbox.LayerPosition(below: labelLayer!.id),
);
    await style.moveStyleLayer(outlineLayerId, mapbox.LayerPosition(below: labelLayer!.id),);
  }

  /// Clear polygon (tap-safe)
  static Future<void> clearRadiusPolygon(mapbox.MapboxMap map) async {
    try {
      await map.style.removeStyleLayer(fillLayerId);
    } catch (_) {}

    try {
      await map.style.removeStyleLayer(outlineLayerId);
    } catch (_) {}

    try {
      await map.style.removeStyleSource(sourceId);
    } catch (_) {}
  }
}
