import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/helpers/offline_water_service.dart';
import 'package:spacetime/app/utils/place_categories_utils.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';

/// Shared pin geocoding: admin hierarchy, reverse geocode with tileSubRegion,
/// water detection / naming, flags — same pipeline as the memory location picker.
class MemoryLocationPinGeocoding {
  MemoryLocationPinGeocoding(this.mapController);

  final mapbox.MapboxMap? mapController;

  Future<Map<String, dynamic>?> buildLocationDataForPin(
    double lat,
    double lng,
  ) async {
    final adminData = await getAdminHierarchy(lat, lng);
    final mapHadNoRenderedFeatures = adminData['assumeLandFromMap'] == 'true';
    final adminMapHasNoWaterLayer = adminData['water'] == null &&
        adminData['waterClass'] == null;

    final bool isTapOnWater;
    if (mapHadNoRenderedFeatures) {
      // No vector hit at pixel — only offline polygons may indicate ocean/lake.
      isTapOnWater = await _isTapOnWater(
        lat,
        lng,
        adminWater: null,
        mapHadNoRenderedFeatures: true,
      );
    } else if (adminMapHasNoWaterLayer) {
      // Map returned features but no water / water_name — land: reverse geocode only.
      isTapOnWater = false;
    } else {
      isTapOnWater = await _isTapOnWater(
        lat,
        lng,
        adminWater: adminData['water'],
        mapHadNoRenderedFeatures: false,
      );
    }

    final tileSubRegion = adminData['subRegion'] ?? adminData['city'];
    final locationData1 = await GeocodingIsolateService.instance.reverseGeocode(
      lat,
      lng,
      tileSubRegion: tileSubRegion,
    );

    if (locationData1 == null && !isTapOnWater) {
      return null;
    }

    Map<String, dynamic> finalData = locationData1 ?? <String, dynamic>{};
    String? waterName;
    if (isTapOnWater) {
      waterName = adminData['water'];
      if (waterName == null ||
          waterName.trim().isEmpty ||
          waterName.trim().toLowerCase() == 'water') {
        final detailedWaterName = await _queryWaterNameFromRenderedTiles(
          lat,
          lng,
          mapWaterClass: adminData['waterClass'],
        );
        if (detailedWaterName != null && detailedWaterName.trim().isNotEmpty) {
          waterName = detailedWaterName;
        }
      }
      if (waterName == null ||
          waterName.trim().isEmpty ||
          waterName.trim().toLowerCase() == 'water') {
        final fallback = _resolveWaterNameFallback(lat, lng);
        if (fallback != null && fallback.trim().isNotEmpty) {
          waterName = fallback;
        }
      }
    }

    final shouldApplyWater = _shouldApplyWaterResult(
      isTapOnWater: isTapOnWater,
      waterName: waterName,
    );
    if (shouldApplyWater && waterName != null) {
      finalData['city'] = waterName;
      finalData['name'] = waterName;
      finalData['address'] = waterName;
      if (finalData['country'] == null ||
          (finalData['country'] as String? ?? '').isEmpty) {
        finalData['country'] = '';
      }
      finalData['flag'] = '🌊';
    } else {
      waterName = null;
    }

    final displayName = finalData['display_name'] as String? ??
        finalData['name'] as String? ??
        'Unknown Location';
    String nameOut = (finalData['name'] as String?)?.trim().isNotEmpty == true
        ? finalData['name'] as String
        : displayName;

    var country = finalData['country'] as String? ?? '';
    var flag = finalData['flag'] as String? ?? '';
    var city = finalData['city'] as String? ?? '';

    if (country.isEmpty && adminData['country'] != null) {
      country = adminData['country']!;
    }
    if (flag.isEmpty && country.isNotEmpty) {
      flag = countryFlags[country.toLowerCase()] ?? '';
    }

    if (city.isEmpty && tileSubRegion != null && tileSubRegion.isNotEmpty) {
      city = tileSubRegion;
    }

    final waterFlag = waterName != null && waterName.toLowerCase().contains('ocean')
        ? '🇺🇳'
        : '🌊';

    if (waterFlag == '🌊') {
      nameOut = '$waterName, $country';
    }

    debugPrint('waterName: $waterName');
    debugPrint('waterFlag: $waterFlag');
    debugPrint('flag: $flag');
    debugPrint('country: $country');
    debugPrint('city: $city');
    debugPrint('nameOut: $nameOut');
    debugPrint('finalData: $finalData');

    if (waterName != null) {
      finalData['name'] = nameOut;
    }

    return <String, dynamic>{
      'latitude': lat,
      'longitude': lng,
      'city': city,
      'country': country,
      'address': finalData['address'] as String? ?? '',
      'flag': waterName != null ? waterFlag : flag,
      'name': nameOut,
    };
  }

  /// True when offline ocean/lake polygons say this point is on land.
  bool _offlineSaysLand(double lat, double lng) {
    try {
      return OfflineWaterService.instance.detect(lat, lng) == null;
    } catch (_) {
      return false;
    }
  }

  /// Drop map-only water when Natural Earth says land + we have place admin,
  /// or when the hit is generic — reduces coast / stacking false "sea" labels.
  void _applyLandVetoForMapWater(double lat, double lng, Map<String, String?> result) {
    if (!_offlineSaysLand(lat, lng)) return;

    final w = result['water'];
    if (w == null) return;

    final wl = w.trim().toLowerCase();
    if (wl.isEmpty || wl == 'water') {
      result['water'] = null;
      result['waterClass'] = null;
      debugPrint('[AdminHierarchy] Land veto: cleared generic map water (offline land)');
      return;
    }

    final hasPlace = result['city'] != null ||
        result['country'] != null ||
        result['region'] != null ||
        result['subRegion'] != null;

    if (hasPlace) {
      result['water'] = null;
      result['waterClass'] = null;
      debugPrint('[AdminHierarchy] Land veto: map water cleared — place labels + offline land');
    }
  }

  Future<Map<String, String?>> getAdminHierarchy(double lat, double lng) async {
    final result = <String, String?>{
      'city': null,
      'region': null,
      'subRegion': null,
      'country': null,
      'water': null,
      'waterClass': null,
      // Set 'true' when queryRenderedFeatures is empty — skip map water heuristics; land unless offline water.
      'assumeLandFromMap': null,
    };
    if (mapController == null) return result;
    try {
      final pixel = await mapController!.pixelForCoordinate(
        mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      );

      final geometry = mapbox.RenderedQueryGeometry.fromScreenCoordinate(pixel);

      final features = await mapController!.queryRenderedFeatures(
        geometry,
        mapbox.RenderedQueryOptions(
          layerIds: null,
          filter: null,
        ),
      );

      if (features.isEmpty) {
        result['assumeLandFromMap'] = 'true';
        debugPrint(
          '[AdminHierarchy] No features found at $lat, $lng — map surface treated as land (offline water only)',
        );
        return result;
      }

      // Pass 1: place labels (land context before water at coasts).
      for (final f in features) {
        if (f == null) continue;
        final props = (f.queriedFeature.feature['properties'] as Map?)?.cast<String, dynamic>();
        final sourceLayer = f.queriedFeature.sourceLayer ?? '';
        final className = props?['class']?.toString() ?? '';
        debugPrint('[AdminHierarchy] sourceLayer=$sourceLayer class=$className props=$props');
        if (sourceLayer != 'place' || props == null) continue;
        final name = (props['name:en'] ?? props['name'])?.toString();
        if (name == null || name.isEmpty) continue;
        if (['country'].contains(className) && result['country'] == null) {
          result['country'] = name;
        } else if (['state', 'province', 'region'].contains(className) && result['region'] == null) {
          result['region'] = name;
        } else if (['county', 'district'].contains(className) && result['subRegion'] == null) {
          result['subRegion'] = name;
        } else if (['city', 'town', 'village', 'suburb', 'hamlet', 'quarter', 'neighbourhood'].contains(className) && result['city'] == null) {
          result['city'] = name;
        }
      }
      // Pass 2: water polygons / labels after place is filled.
      for (final f in features) {
        if (f == null) continue;
        final props = (f.queriedFeature.feature['properties'] as Map?)?.cast<String, dynamic>();
        final sourceLayer = f.queriedFeature.sourceLayer ?? '';
        final className = props?['class']?.toString() ?? '';
        if (sourceLayer != 'water' && sourceLayer != 'water_name') continue;
        debugPrint('[AdminHierarchy] sourceLayer=$sourceLayer class=$className props=$props');
        final name = (props?['name:en'] ?? props?['name'])?.toString();
        if (result['waterClass'] == null && className.isNotEmpty) {
          result['waterClass'] = className;
        }
        if (result['water'] == null) {
          result['water'] = (name != null && name.isNotEmpty) ? name : 'Water';
        }
      }

      _applyLandVetoForMapWater(lat, lng, result);

      debugPrint('[AdminHierarchy] result=$result');
    } catch (e) {
      debugPrint('[AdminHierarchy] Error: $e');
    }
    return result;
  }

  Future<bool> _isTapOnWater(
    double lat,
    double lng, {
    String? adminWater,
    bool mapHadNoRenderedFeatures = false,
  }) async {
    if (mapHadNoRenderedFeatures) {
      try {
        return OfflineWaterService.instance.detect(lat, lng) != null;
      } catch (_) {
        return false;
      }
    }

    final admin = (adminWater ?? '').trim().toLowerCase();
    if (admin.isNotEmpty && admin != 'water') {
      return _confirmNamedMapWaterAgainstOfflineLand(lat, lng);
    }

    try {
      if (OfflineWaterService.instance.detect(lat, lng) != null) {
        return true;
      }
    } catch (_) {
      // fall through to rendered probe
    }

    final rendered = await _queryWaterNameFromRenderedTiles(lat, lng);
    if (rendered != null && rendered.trim().isNotEmpty) {
      return true;
    }
    return false;
  }

  /// Map vector may label a nearby sea; offline polygons say land — require rendered confirmation.
  Future<bool> _confirmNamedMapWaterAgainstOfflineLand(double lat, double lng) async {
    try {
      if (OfflineWaterService.instance.detect(lat, lng) != null) {
        return true;
      }
    } catch (_) {
      return true;
    }
    final rendered = await _queryWaterNameFromRenderedTiles(lat, lng);
    return rendered != null && rendered.trim().isNotEmpty;
  }

  bool _shouldApplyWaterResult({
    required bool isTapOnWater,
    required String? waterName,
  }) {
    if (!isTapOnWater) return false;
    if (waterName == null) return false;
    final w = waterName.trim();
    if (w.isEmpty) return false;
    if (w.toLowerCase() == 'water') return false;
    return _isLikelyWaterName(w);
  }

  bool _isLikelyWaterName(String name) {
    final n = name.toLowerCase();
    return n.contains('ocean') ||
        n.contains('sea') ||
        n.contains('lake') ||
        n.contains('river') ||
        n.contains('stream') ||
        n.contains('brook') ||
        n.contains('creek') ||
        n.contains('canal') ||
        n.contains('dam') ||
        n.contains('reservoir') ||
        n.contains('pond') ||
        n.contains('lagoon') ||
        n.contains('fjord') ||
        n.contains('wetland') ||
        n.contains('marsh') ||
        n.contains('swamp') ||
        n.contains('delta') ||
        n.contains('estuary') ||
        n.contains('inlet') ||
        n.contains('harbor') ||
        n.contains('harbour') ||
        n.contains('dock') ||
        n.contains('basin') ||
        n.contains('bay') ||
        n.contains('gulf') ||
        n.contains('strait') ||
        n.contains('channel') ||
        n.contains('sound');
  }

  bool _isWaterClass(String className) {
    final c = className.toLowerCase();
    return c.contains('water') ||
        c.contains('river') ||
        c.contains('stream') ||
        c.contains('brook') ||
        c.contains('creek') ||
        c.contains('canal') ||
        c.contains('dam') ||
        c.contains('reservoir') ||
        c.contains('pond') ||
        c.contains('lagoon') ||
        c.contains('fjord') ||
        c.contains('wetland') ||
        c.contains('marsh') ||
        c.contains('swamp') ||
        c.contains('delta') ||
        c.contains('estuary') ||
        c.contains('inlet') ||
        c.contains('harbor') ||
        c.contains('harbour') ||
        c.contains('dock') ||
        c.contains('basin') ||
        c.contains('lake') ||
        c.contains('ocean') ||
        c.contains('sea') ||
        c.contains('gulf') ||
        c.contains('bay') ||
        c.contains('strait') ||
        c.contains('channel') ||
        c.contains('sound');
  }

  bool _isWaterSourceLayer(String sourceLayer) {
    final s = sourceLayer.toLowerCase();
    return s.contains('water') ||
        s.contains('waterway') ||
        s.contains('marine') ||
        s.contains('ocean') ||
        s.contains('sea') ||
        s.contains('river') ||
        s.contains('lake') ||
        s.contains('canal') ||
        s.contains('dam') ||
        s.contains('reservoir') ||
        s.contains('wetland') ||
        s.contains('marsh') ||
        s.contains('stream') ||
        s.contains('basin');
  }

  double _maxWaterCandidateScoreKm(String? mapWaterClass) {
    final c = mapWaterClass?.toLowerCase() ?? '';
    if (c == 'ocean' || c == 'sea') return 2000.0;
    if (c.isNotEmpty) return 600.0;
    return 400.0;
  }

  Future<String?> _queryWaterNameFromRenderedTiles(
    double lat,
    double lng, {
    String? mapWaterClass,
  }) async {
    if (mapController == null) {
      debugPrint('[WaterNameSearch] mapController is null, skipping');
      return null;
    }
    final maxCandidateKm = _maxWaterCandidateScoreKm(mapWaterClass);
    try {
      debugPrint(
        '[WaterNameSearch] Start lookup at lat=$lat lng=$lng maxCandidateKm=$maxCandidateKm mapWaterClass=$mapWaterClass',
      );
      final centerPixel = await mapController!.pixelForCoordinate(
        mapbox.Point(coordinates: mapbox.Position(lng, lat)),
      );

      const offsets = <List<double>>[
        [0, 0],
        [20, 0], [-20, 0], [0, 20], [0, -20],
        [40, 0], [-40, 0], [0, 40], [0, -40],
        [20, 20], [20, -20], [-20, 20], [-20, -20],
        [60, 0], [-60, 0], [0, 60], [0, -60],
      ];

      bool sawWaterFeature = false;
      final Map<String, double> namedCandidates = <String, double>{};
      int probeIndex = 0;

      for (final off in offsets) {
        probeIndex++;
        final probe = mapbox.ScreenCoordinate(
          x: centerPixel.x + off[0],
          y: centerPixel.y + off[1],
        );
        final geometry = mapbox.RenderedQueryGeometry.fromScreenCoordinate(probe);
        final features = await mapController!.queryRenderedFeatures(
          geometry,
          mapbox.RenderedQueryOptions(
            layerIds: null,
            filter: null,
          ),
        );
        if (features.isNotEmpty) {
          debugPrint(
            '[WaterNameSearch] Probe#$probeIndex offset=(${off[0]},${off[1]}) features=${features.length}',
          );
        }

        for (final f in features) {
          if (f == null) continue;
          final featureMap = Map<String, dynamic>.from(f.queriedFeature.feature);
          final sourceLayer = (f.queriedFeature.sourceLayer ?? '').toLowerCase();
          final props =
              (featureMap['properties'] as Map?)?.cast<String, dynamic>();
          final className =
              (props?['class'] ?? props?['subclass'] ?? props?['type'] ?? '')
                  .toString();
          final name =
              (props?['name:en'] ?? props?['name'] ?? props?['name_en'])
                  ?.toString()
                  .trim();

          if (_isWaterSourceLayer(sourceLayer) || _isWaterClass(className)) {
            sawWaterFeature = true;
          }

          if (name != null &&
              name.isNotEmpty &&
              (_isWaterClass(className) ||
                  _isWaterSourceLayer(sourceLayer) ||
                  _isLikelyWaterName(name))) {
            final contained = _isPointInsideFeaturePolygon(featureMap, lat, lng);
            double scoreKm = _featureDistanceKm(featureMap, lat, lng);
            if (scoreKm.isInfinite) {
              scoreKm = math.sqrt(off[0] * off[0] + off[1] * off[1]) / 40.0;
            }
            scoreKm += _waterClassPenaltyKm(className, name);
            if (contained) {
              scoreKm -= 120.0;
            }
            final prev = namedCandidates[name];
            if (prev == null || scoreKm < prev) {
              namedCandidates[name] = scoreKm;
            }
            debugPrint(
              '[WaterNameSearch] Candidate name="$name" sourceLayer="$sourceLayer" class="$className" contained=$contained scoreKm=${scoreKm.toStringAsFixed(3)}',
            );
          }
        }
      }

      if (namedCandidates.isNotEmpty) {
        final sorted = namedCandidates.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        final best = sorted.first;
        if (best.value > maxCandidateKm) {
          debugPrint(
            '[WaterNameSearch] Rejecting rendered candidate "${best.key}" due to far score=${best.value.toStringAsFixed(3)} (max=$maxCandidateKm)',
          );
        } else {
          debugPrint(
            '[WaterNameSearch] Selected nearest water="${best.key}" scoreKm=${best.value.toStringAsFixed(3)} candidates=${sorted.length}',
          );
          return best.key;
        }
      }

      final sourceName = await _queryWaterNameFromSourceFeatures(
        lat,
        lng,
        mapWaterClass: mapWaterClass,
      );
      if (sourceName != null && sourceName.trim().isNotEmpty) {
        debugPrint('[WaterNameSearch] Source-feature fallback selected "$sourceName"');
        return sourceName;
      }

      if (sawWaterFeature) {
        final offlineHit = OfflineWaterService.instance.detect(lat, lng);
        if (offlineHit != null) {
          final n = (offlineHit.name ?? '').trim();
          if (n.isNotEmpty) {
            debugPrint('[WaterNameSearch] Unnamed rendered water confirmed by offline="$n"');
            return n;
          }
          debugPrint('[WaterNameSearch] Unnamed rendered water confirmed by offline (generic)');
          return 'Water';
        }
        debugPrint(
          '[WaterNameSearch] Rendered water; offline land mask ignored — generic Water',
        );
        return 'Water';
      }
      debugPrint('[WaterNameSearch] No water feature/name found');
    } catch (e) {
      debugPrint('[WaterNameSearch] Error querying rendered water features: $e');
    }
    return null;
  }

  Future<String?> _queryWaterNameFromSourceFeatures(
    double lat,
    double lng, {
    String? mapWaterClass,
  }) async {
    if (mapController == null) return null;
    final maxCandidateKm = _maxWaterCandidateScoreKm(mapWaterClass);
    try {
      final sourceCandidates = <String, double>{};
      const sourceLayers = <String>[
        'water_name',
        'waterway',
        'water',
        'marine',
        'marine_label',
        'waterway_label',
      ];

      for (final layer in sourceLayers) {
        final features = await mapController!.querySourceFeatures(
          'openmaptiles',
          mapbox.SourceQueryOptions(
            sourceLayerIds: [layer],
            filter: 'all',
          ),
        );
        if (features.isEmpty) continue;

        debugPrint('[WaterNameSearch] Source layer="$layer" features=${features.length}');

        for (final f in features) {
          if (f == null) continue;
          final featureMap = Map<String, dynamic>.from(f.queriedFeature.feature);
          final props =
              (featureMap['properties'] as Map?)?.cast<String, dynamic>();
          if (props == null) continue;

          final className =
              (props['class'] ?? props['subclass'] ?? props['type'] ?? '')
                  .toString();
          final name =
              (props['name:en'] ?? props['name'] ?? props['name_en'])
                  ?.toString()
                  .trim();

          if (name == null || name.isEmpty) continue;
          if (!(_isWaterClass(className) || _isLikelyWaterName(name))) continue;

          final contained = _isPointInsideFeaturePolygon(featureMap, lat, lng);
          if ((className.toLowerCase().contains('ocean') ||
                  name.toLowerCase().contains('ocean')) &&
              !contained) {
            continue;
          }
          double scoreKm = _featureDistanceKm(featureMap, lat, lng);
          if (scoreKm.isInfinite) continue;
          scoreKm += _waterClassPenaltyKm(className, name);
          if (contained) {
            scoreKm -= 120.0;
          }
          final prev = sourceCandidates[name];
          if (prev == null || scoreKm < prev) {
            sourceCandidates[name] = scoreKm;
          }
        }
      }

      if (sourceCandidates.isEmpty) return null;
      final sorted = sourceCandidates.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final best = sorted.first;
      if (best.value > maxCandidateKm) {
        debugPrint(
          '[WaterNameSearch] Rejecting source candidate "${best.key}" due to far score=${best.value.toStringAsFixed(3)} (max=$maxCandidateKm)',
        );
        return null;
      }
      debugPrint(
        '[WaterNameSearch] Source nearest water="${best.key}" scoreKm=${best.value.toStringAsFixed(3)} candidates=${sorted.length}',
      );
      return best.key;
    } catch (e) {
      debugPrint('[WaterNameSearch] Source-feature fallback error: $e');
      return null;
    }
  }

  bool _isPointInsideFeaturePolygon(
    Map<String, dynamic> featureMap,
    double lat,
    double lng,
  ) {
    try {
      final geometry = featureMap['geometry'];
      if (geometry is! Map) return false;
      final type = (geometry['type'] ?? '').toString();
      final coords = geometry['coordinates'];
      if (coords == null) return false;

      if (type == 'Polygon' && coords is List) {
        for (final ring in coords) {
          if (ring is List && _pointInRing(lat, lng, ring)) return true;
        }
      } else if (type == 'MultiPolygon' && coords is List) {
        for (final poly in coords) {
          if (poly is! List) continue;
          for (final ring in poly) {
            if (ring is List && _pointInRing(lat, lng, ring)) return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  bool _pointInRing(double lat, double lng, List ring) {
    bool inside = false;
    int j = ring.length - 1;
    for (int i = 0; i < ring.length; i++) {
      final pi = ring[i];
      final pj = ring[j];
      if (pi is! List || pj is! List || pi.length < 2 || pj.length < 2) {
        j = i;
        continue;
      }
      final xi = (pi[0] as num).toDouble();
      final yi = (pi[1] as num).toDouble();
      final xj = (pj[0] as num).toDouble();
      final yj = (pj[1] as num).toDouble();
      final intersect =
          ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
      if (intersect) inside = !inside;
      j = i;
    }
    return inside;
  }

  double _waterClassPenaltyKm(String className, String name) {
    final c = className.toLowerCase();
    final n = name.toLowerCase();
    if (c.contains('dam') || n.contains('dam')) return -30.0;
    if (c.contains('canal') || n.contains('canal')) return -28.0;
    if (c.contains('lake') || n.contains('lake')) return -22.0;
    if (c.contains('gulf') || c.contains('strait') || c.contains('bay') || n.contains('gulf') || n.contains('strait') || n.contains('bay')) {
      return -35.0;
    }
    if (c.contains('sea') || n.contains('sea')) return -25.0;
    if (c.contains('river') || n.contains('river')) return -8.0;
    if (c.contains('ocean') || n.contains('ocean')) return 220.0;
    return 0.0;
  }

  double _featureDistanceKm(
    Map<String, dynamic> featureMap,
    double lat,
    double lng,
  ) {
    try {
      if (_isPointInsideFeaturePolygon(featureMap, lat, lng)) {
        return 0.0;
      }
      final geometry = featureMap['geometry'];
      if (geometry is! Map) return double.infinity;
      final coordinates = geometry['coordinates'];
      if (coordinates == null) return double.infinity;

      final points = <(double, double)>[];
      _collectLngLatPairs(coordinates, points);
      if (points.isEmpty) return double.infinity;

      double minKm = double.infinity;
      for (final p in points) {
        final d = _haversineKm(lat, lng, p.$1, p.$2);
        if (d < minKm) minKm = d;
      }
      return minKm;
    } catch (_) {
      return double.infinity;
    }
  }

  void _collectLngLatPairs(dynamic coords, List<(double, double)> out) {
    if (coords is List) {
      if (coords.length >= 2 && coords[0] is num && coords[1] is num) {
        out.add(((coords[1] as num).toDouble(), (coords[0] as num).toDouble()));
        return;
      }
      for (final c in coords) {
        _collectLngLatPairs(c, out);
      }
    }
  }

  double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String? _resolveWaterNameFallback(double lat, double lng) {
    try {
      final exact = OfflineWaterService.instance.detect(lat, lng);
      if (exact != null && (exact.name?.trim().isNotEmpty ?? false)) {
        final n = exact.name!.trim();
        debugPrint('[WaterNameSearch] Offline fallback exact hit="$n"');
        return n;
      }

      const radiiKm = <double>[10, 25, 50, 100, 180];
      const bearings = <double>[0, 45, 90, 135, 180, 225, 270, 315];

      for (final rKm in radiiKm) {
        final dLat = rKm / 111.0;
        final dLngBase =
            rKm / (111.0 * math.max(0.2, math.cos(lat * math.pi / 180.0)));
        for (final b in bearings) {
          final rad = b * math.pi / 180.0;
          final sampleLat = lat + dLat * math.sin(rad);
          final sampleLng = lng + dLngBase * math.cos(rad);
          final hit = OfflineWaterService.instance.detect(sampleLat, sampleLng);
          if (hit != null && (hit.name?.trim().isNotEmpty ?? false)) {
            final n = hit.name!.trim();
            debugPrint(
              '[WaterNameSearch] Offline fallback nearby hit="$n" '
              'radiusKm=$rKm bearing=$b',
            );
            return n;
          }
        }
      }

      debugPrint('[WaterNameSearch] Offline fallback no named water found');
    } catch (e) {
      debugPrint('[WaterNameSearch] Offline fallback error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getWaterPolygonById(
    String sourceId,
    String sourceLayer,
    String featureId,
  ) async {
    try {
      debugPrint(
        '[getWaterPolygonById] Querying sourceId="$sourceId", layer="$sourceLayer", featureId="$featureId"',
      );

      final sourceFeatures = await mapController?.querySourceFeatures(
        sourceId,
        mapbox.SourceQueryOptions(
          sourceLayerIds: [sourceLayer],
          filter: 'all',
        ),
      );

      debugPrint(
        '[getWaterPolygonById] Total features retrieved: ${sourceFeatures?.length}',
      );

      if (sourceFeatures == null) return null;
      for (final f in sourceFeatures) {
        if (f == null) continue;
        final geojson = Map<String, dynamic>.from(f.queriedFeature.feature);
        final id = geojson['id']?.toString();
        if (id == featureId) {
          debugPrint(
            '[getWaterPolygonById] Found feature! id="$id", properties=${geojson['properties']}',
          );
          return geojson;
        }
      }
    } catch (e, stack) {
      debugPrint('[getWaterPolygonById] Exception: $e');
      debugPrint('[getWaterPolygonById] Stack: $stack');
    }

    return null;
  }

  Future<String?> getWaterLabel(
    Map<String, dynamic> polygonFeature,
    List<String> labelLayers,
  ) async {
    try {
      final coords = polygonFeature['geometry']['coordinates'][0] as List;
      double sumLat = 0, sumLng = 0;
      for (final c in coords) {
        sumLng += (c[0] as num).toDouble();
        sumLat += (c[1] as num).toDouble();
      }
      final n = coords.length;
      final centroid = LatLng(sumLat / n, sumLng / n);

      final pixel = await mapController?.pixelForCoordinate(
        mapbox.Point(coordinates: mapbox.Position(centroid.longitude, centroid.latitude)),
      );
      if (pixel == null) return null;
      final geometry = mapbox.RenderedQueryGeometry.fromScreenCoordinate(pixel);

      final labelFeatures = await mapController?.queryRenderedFeatures(
        geometry,
        mapbox.RenderedQueryOptions(
          layerIds: labelLayers,
          filter: 'all',
        ),
      );

      if (labelFeatures == null) return null;
      for (final f in labelFeatures) {
        if (f == null) continue;

        final props = (f.queriedFeature.feature['properties'] as Map?)?.cast<String, dynamic>();
        debugPrint('[getWaterLabel] Feature properties: $props');

        final featureJson = const JsonEncoder.withIndent('  ').convert(f.queriedFeature.feature);
        debugPrint('[getWaterLabel] Full feature GeoJSON:\n$featureJson');

        final name = (props?['name:en'] ?? props?['name'])?.toString();
        if (name != null && name.isNotEmpty) {
          debugPrint('[getWaterLabel] Found label: $name');
          return name;
        }
      }
    } catch (e, stack) {
      debugPrint('[getWaterLabel] Exception: $e');
      debugPrint('[getWaterLabel] Stack: $stack');
    }

    return null;
  }
}
