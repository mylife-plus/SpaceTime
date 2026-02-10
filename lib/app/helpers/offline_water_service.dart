import 'dart:math';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:geojson_vi/geojson_vi.dart';

/// ===============================================================
/// OFFLINE WATER DETECTION SERVICE
/// ===============================================================
/// Detects if a lat/lng lies in:
/// - Ocean
/// - Lake
/// - Otherwise → land (null)
///
/// Uses Natural Earth GeoJSON (offline)
/// ===============================================================
class OfflineWaterService {
  /// ================= SINGLETON =================
  OfflineWaterService._internal();
  static final OfflineWaterService instance =
      OfflineWaterService._internal();

  /// ================= STORAGE =================
  final List<_PolyFeature> _oceans = [];
  final List<_PolyFeature> _lakes = [];

  bool _initialized = false;

  /// ================= INIT (CALL ONCE IN main) =================
  Future<void> init({
    required String oceanGeoJson,
    required String lakeGeoJson,
  }) async {
    if (_initialized) return;

    await _loadPolygons(oceanGeoJson, _oceans);
    await _loadPolygons(lakeGeoJson, _lakes);

    _initialized = true;
  }

  /// ================= PUBLIC API =================
  /// Returns:
  /// - WaterHit(type: ocean/lake, name)
  /// - null → land
  WaterHit? detect(double lat, double lng) {
    if (!_initialized) {
      throw StateError('OfflineWaterService.init() was not called');
    }

    final point = LatLng(lat, lng);

    // 🌊 Check oceans first (priority)
    for (final ocean in _oceans) {
      if (!ocean.bbox.contains(point)) continue;
      if (_pointInPolygon(point, ocean.points)) {
        return WaterHit(
          type: WaterType.ocean,
          name: ocean.name,
        );
      }
    }

    // 🟦 Check lakes
    for (final lake in _lakes) {
      if (!lake.bbox.contains(point)) continue;
      if (_pointInPolygon(point, lake.points)) {
        return WaterHit(
          type: WaterType.lake,
          name: lake.name,
        );
      }
    }

    return null; // 🌍 Land
  }

  /// ================= GEOJSON LOADER =================
  Future<void> _loadPolygons(
    String assetPath,
    List<_PolyFeature> target,
  ) async {
    final json = await rootBundle.loadString(assetPath);
    final collection = GeoJSONFeatureCollection.fromJSON(json);

    for (final feature in collection.features) {
      final geometry = feature?.geometry;
      if (geometry == null) continue;

      final rawName = feature?.properties?['name']?.toString();
      if (rawName == null || rawName.isEmpty) continue;

      final name = _clean(rawName);

      // ✅ Polygon
      if (geometry is GeoJSONPolygon) {
        for (final ring in geometry.coordinates) {
          _addPolygon(ring, name, target);
        }
      }

      // ✅ MultiPolygon (MOST oceans)
      else if (geometry is GeoJSONMultiPolygon) {
        for (final polygon in geometry.coordinates) {
          for (final ring in polygon) {
            _addPolygon(ring, name, target);
          }
        }
      }
    }
  }

  void _addPolygon(
    List<List<double>> ring,
    String name,
    List<_PolyFeature> target,
  ) {
    final points = ring.map((c) => LatLng(c[1], c[0])).toList();

    if (points.length < 3) return;

    target.add(
      _PolyFeature(
        name: name,
        points: points,
        bbox: _BBox.fromPoints(points),
      ),
    );
  }

  /// ================= POINT IN POLYGON =================
  /// Ray-casting algorithm
  bool _pointInPolygon(LatLng p, List<LatLng> poly) {
    bool inside = false;

    for (int i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final xi = poly[i].longitude;
      final yi = poly[i].latitude;
      final xj = poly[j].longitude;
      final yj = poly[j].latitude;

      final intersect =
          ((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude <
              (xj - xi) *
                      (p.latitude - yi) /
                      (yj - yi) +
                  xi);

      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// ================= HELPERS =================
  String _clean(String s) =>
      s.replaceAll('\r', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// ===============================================================
/// INTERNAL MODELS
/// ===============================================================
class _PolyFeature {
  final String name;
  final List<LatLng> points;
  final _BBox bbox;

  _PolyFeature({
    required this.name,
    required this.points,
    required this.bbox,
  });
}

class _BBox {
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  _BBox(this.minLat, this.maxLat, this.minLng, this.maxLng);

  bool contains(LatLng p) =>
      p.latitude >= minLat &&
      p.latitude <= maxLat &&
      p.longitude >= minLng &&
      p.longitude <= maxLng;

  static _BBox fromPoints(List<LatLng> pts) {
    double minLat = pts.first.latitude;
    double maxLat = pts.first.latitude;
    double minLng = pts.first.longitude;
    double maxLng = pts.first.longitude;

    for (final p in pts) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }

    return _BBox(minLat, maxLat, minLng, maxLng);
  }
}

/// ===============================================================
/// PUBLIC RESULT TYPES
/// ===============================================================
enum WaterType { ocean, lake }

class WaterHit {
  final WaterType type;
  final String? name;

  const WaterHit({
    required this.type,
    this.name,
  });
}
