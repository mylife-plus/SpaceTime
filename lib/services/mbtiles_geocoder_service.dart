// import 'dart:io';
// import 'dart:math';
// import 'package:flutter/foundation.dart';
// import 'package:sqflite/sqflite.dart';
// import 'package:vector_tile/vector_tile.dart';
// import 'package:spacetime/services/mbtiles_server_service.dart';

// class MbtilesPlaceResult {
//   final String name;
//   final String? className;
//   final double lat;
//   final double lng;
//   final double distanceKm;
//   final bool isWater;
//   final String? countryName;
//   final String? stateName;

//   MbtilesPlaceResult({
//     required this.name,
//     required this.className,
//     required this.lat,
//     required this.lng,
//     required this.distanceKm,
//     this.isWater = false,
//     this.countryName,
//     this.stateName,
//   });
// }

// class MbtilesGeocoderService {
//   static MbtilesGeocoderService? _instance;
//   static MbtilesGeocoderService get instance =>
//       _instance ??= MbtilesGeocoderService._();

//   MbtilesGeocoderService._();

//   Database? _database;
//   bool _isInitialized = false;
//   int _maxZoom = 14;

//   Future<void> init() async {
//     if (_isInitialized) return;
//     final server = MbtilesServerService.instance;
//     if (!server.isRunning) {
//       debugPrint('[MbtilesGeocoder] Server not running, skipping init');
//       return;
//     }

//     _database = server.database;
//     if (_database == null) {
//       debugPrint('[MbtilesGeocoder] No database available');
//       return;
//     }

//     try {
//       final result = await _database!.rawQuery(
//         "SELECT value FROM metadata WHERE name = 'maxzoom'",
//       );
//       if (result.isNotEmpty) {
//         _maxZoom = int.tryParse(result.first['value'].toString()) ?? 14;
//       }
//     } catch (_) {}

//     _isInitialized = true;
//     debugPrint('[MbtilesGeocoder] Initialized, maxZoom=$_maxZoom');
//   }

//   Future<MbtilesPlaceResult?> reverseGeocode(double lat, double lng) async {
//     if (!_isInitialized) await init();
//     if (!_isInitialized || _database == null) return null;

//     final z = _maxZoom;
//     final tileX = _lngToTileX(lng, z);
//     final tileY = _latToTileY(lat, z);

//     final places = await _extractPlacesFromTile(z, tileX, tileY, lat, lng);

//     for (int dz = z - 1; dz >= max(z - 3, 0) && places.isEmpty; dz--) {
//       final tx = _lngToTileX(lng, dz);
//       final ty = _latToTileY(lat, dz);
//       places.addAll(await _extractPlacesFromTile(dz, tx, ty, lat, lng));
//     }

//     if (places.isEmpty) return null;

//     final nonWater = places.where((p) => !p.isWater).toList();
//     final water = places.where((p) => p.isWater).toList();

//     if (nonWater.isNotEmpty) {
//       nonWater.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
//       if (nonWater.first.distanceKm < 10) return nonWater.first;
//     }

//     if (water.isNotEmpty) {
//       final named = water.where((w) => w.name != 'Water').toList();
//       if (named.isNotEmpty) {
//         named.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
//         return named.first;
//       }
//       return water.first;
//     }

//     if (nonWater.isNotEmpty) return nonWater.first;

//     return null;
//   }

//   Future<List<MbtilesPlaceResult>> _extractPlacesFromTile(
//       int z, int x, int y, double queryLat, double queryLng) async {
//     final tmsY = (1 << z) - 1 - y;
//     final result = await _database!.rawQuery(
//       'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
//       [z, x, tmsY],
//     );

//     if (result.isEmpty || result.first['tile_data'] == null) return [];

//     final tileData = result.first['tile_data'] as Uint8List;

//     Uint8List decompressed;
//     try {
//       decompressed = Uint8List.fromList(gzip.decode(tileData));
//     } catch (_) {
//       decompressed = tileData;
//     }

//     final tile = VectorTile.fromBytes(bytes: decompressed);
//     final places = <MbtilesPlaceResult>[];
//     bool insideWaterPolygon = false;
//     String? nearestCountry;
//     String? nearestState;
//     double countryDist = double.infinity;
//     double stateDist = double.infinity;

//     for (final layer in tile.layers) {
//       final ln = layer.name.toLowerCase();

//       final isPlace = ln == 'place' || ln == 'place_label';
//       final isWaterName = ln == 'water_name' || ln == 'waterway' || ln == 'waterway_label';
//       final isWaterGeom = ln == 'water';

//       if (!isPlace && !isWaterName && !isWaterGeom) continue;

//       for (final feature in layer.features) {
//         feature.decodeGeometry();

//         if (isWaterGeom) {
//           if (feature.type == VectorTileGeomType.POLYGON) {
//             final geojson = feature.toGeoJson<GeoJsonPolygon>(x: x, y: y, z: z);
//             if (geojson?.geometry != null) {
//               for (final ring in geojson!.geometry!.coordinates) {
//                 if (_pointInPolygon(queryLat, queryLng, ring)) {
//                   insideWaterPolygon = true;
//                   break;
//                 }
//               }
//             }
//           }
//           continue;
//         }

//         final props = feature.decodeProperties();
//         final name = _extractStringProp(props, ['name', 'name:en', 'name_en']);
//         final className = _extractStringProp(props, ['class', 'type', 'place', 'subclass']);

//         if (isPlace && feature.type == VectorTileGeomType.POINT) {
//           final geojson = feature.toGeoJson<GeoJsonPoint>(x: x, y: y, z: z);
//           if (geojson?.geometry == null) continue;
//           final coords = geojson!.geometry!.coordinates;
//           if (coords.length < 2) continue;
//           final fLng = coords[0];
//           final fLat = coords[1];
//           final dist = _haversineKm(queryLat, queryLng, fLat, fLng);

//           if (className == 'country') {
//             if (name != null && name.isNotEmpty && dist < countryDist) {
//               nearestCountry = name;
//               countryDist = dist;
//             }
//             continue;
//           }
//           if (className == 'state') {
//             if (name != null && name.isNotEmpty && dist < stateDist) {
//               nearestState = name;
//               stateDist = dist;
//             }
//             continue;
//           }

//           if (name == null || name.isEmpty) continue;

//           places.add(MbtilesPlaceResult(
//             name: name,
//             className: className,
//             lat: fLat,
//             lng: fLng,
//             distanceKm: dist,
//             isWater: false,
//           ));
//           continue;
//         }

//         if (isWaterName) {
//           if (name == null || name.isEmpty) continue;

//           if (feature.type == VectorTileGeomType.POINT) {
//             final geojson = feature.toGeoJson<GeoJsonPoint>(x: x, y: y, z: z);
//             if (geojson?.geometry == null) continue;
//             final coords = geojson!.geometry!.coordinates;
//             if (coords.length < 2) continue;
//             final dist = _haversineKm(queryLat, queryLng, coords[1], coords[0]);
//             places.add(MbtilesPlaceResult(
//               name: name,
//               className: className ?? 'water',
//               lat: coords[1],
//               lng: coords[0],
//               distanceKm: dist,
//               isWater: true,
//             ));
//           } else if (feature.type == VectorTileGeomType.LINESTRING) {
//             final geojson = feature.toGeoJson<GeoJsonLineString>(x: x, y: y, z: z);
//             if (geojson?.geometry == null) continue;
//             final coords = geojson!.geometry!.coordinates;
//             if (coords.isEmpty) continue;
//             double minDist = double.infinity;
//             double closestLat = queryLat, closestLng = queryLng;
//             for (final c in coords) {
//               if (c.length < 2) continue;
//               final d = _haversineKm(queryLat, queryLng, c[1], c[0]);
//               if (d < minDist) {
//                 minDist = d;
//                 closestLat = c[1];
//                 closestLng = c[0];
//               }
//             }
//             places.add(MbtilesPlaceResult(
//               name: name,
//               className: className ?? 'water',
//               lat: closestLat,
//               lng: closestLng,
//               distanceKm: minDist,
//               isWater: true,
//             ));
//           }
//         }
//       }
//     }

//     if (insideWaterPolygon && places.where((p) => p.isWater).isEmpty) {
//       places.add(MbtilesPlaceResult(
//         name: 'Water',
//         className: 'water',
//         lat: queryLat,
//         lng: queryLng,
//         distanceKm: 0.0,
//         isWater: true,
//       ));
//     }

//     for (int i = 0; i < places.length; i++) {
//       if (!places[i].isWater && (places[i].countryName == null || places[i].stateName == null)) {
//         places[i] = MbtilesPlaceResult(
//           name: places[i].name,
//           className: places[i].className,
//           lat: places[i].lat,
//           lng: places[i].lng,
//           distanceKm: places[i].distanceKm,
//           isWater: places[i].isWater,
//           countryName: nearestCountry,
//           stateName: nearestState,
//         );
//       }
//     }

//     return places;
//   }

//   bool _pointInPolygon(double lat, double lng, List<List<double>> ring) {
//     bool inside = false;
//     for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
//       final xi = ring[i].length >= 2 ? ring[i][1] : 0.0;
//       final yi = ring[i].length >= 2 ? ring[i][0] : 0.0;
//       final xj = ring[j].length >= 2 ? ring[j][1] : 0.0;
//       final yj = ring[j].length >= 2 ? ring[j][0] : 0.0;
//       if (((yi > lng) != (yj > lng)) &&
//           (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi)) {
//         inside = !inside;
//       }
//     }
//     return inside;
//   }

//   String? _extractStringProp(
//       Map<String, VectorTileValue> props, List<String> keys) {
//     for (final key in keys) {
//       final val = props[key];
//       if (val != null && val.dartStringValue != null) {
//         return val.dartStringValue;
//       }
//     }
//     return null;
//   }

//   int _lngToTileX(double lng, int z) =>
//       ((lng + 180.0) / 360.0 * (1 << z)).floor();

//   int _latToTileY(double lat, int z) {
//     final latRad = lat * pi / 180.0;
//     return ((1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / pi) /
//             2.0 *
//             (1 << z))
//         .floor();
//   }

//   double _haversineKm(double lat1, double lng1, double lat2, double lng2) {
//     const r = 6371.0;
//     final dLat = (lat2 - lat1) * pi / 180.0;
//     final dLng = (lng2 - lng1) * pi / 180.0;
//     final a = sin(dLat / 2) * sin(dLat / 2) +
//         cos(lat1 * pi / 180.0) *
//             cos(lat2 * pi / 180.0) *
//             sin(dLng / 2) *
//             sin(dLng / 2);
//     return r * 2 * atan2(sqrt(a), sqrt(1 - a));
//   }

//   Future<void> debugDumpTile(double lat, double lng) async {
//     if (!_isInitialized) await init();
//     if (!_isInitialized || _database == null) {
//       debugPrint('[DEBUG] Not initialized');
//       return;
//     }

//     final z = _maxZoom;
//     final x = _lngToTileX(lng, z);
//     final y = _latToTileY(lat, z);
//     final tmsY = (1 << z) - 1 - y;

//     debugPrint('═══════════════════════════════════════');
//     debugPrint('[DEBUG] Coords: $lat, $lng');
//     debugPrint('[DEBUG] Tile: z=$z x=$x y=$y tmsY=$tmsY');

//     final result = await _database!.rawQuery(
//       'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
//       [z, x, tmsY],
//     );

//     if (result.isEmpty || result.first['tile_data'] == null) {
//       debugPrint('[DEBUG] NO TILE DATA FOUND');
//       for (int dz = z - 1; dz >= max(z - 3, 0); dz--) {
//         final tx = _lngToTileX(lng, dz);
//         final ty = _latToTileY(lat, dz);
//         final tmsYd = (1 << dz) - 1 - ty;
//         final r2 = await _database!.rawQuery(
//           'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
//           [dz, tx, tmsYd],
//         );
//         if (r2.isNotEmpty && r2.first['tile_data'] != null) {
//           debugPrint('[DEBUG] Found tile at fallback z=$dz');
//           await _dumpTileContents(r2.first['tile_data'] as Uint8List, dz, tx, ty, lat, lng);
//           return;
//         }
//       }
//       debugPrint('[DEBUG] No tiles found at any zoom level');
//       return;
//     }

//     await _dumpTileContents(result.first['tile_data'] as Uint8List, z, x, y, lat, lng);
//   }

//   Future<void> _dumpTileContents(Uint8List tileData, int z, int x, int y, double queryLat, double queryLng) async {
//     Uint8List decompressed;
//     try {
//       decompressed = Uint8List.fromList(gzip.decode(tileData));
//     } catch (_) {
//       decompressed = tileData;
//     }

//     final tile = VectorTile.fromBytes(bytes: decompressed);
//     debugPrint('[DEBUG] Total layers: ${tile.layers.length}');

//     for (final layer in tile.layers) {
//       debugPrint('───────────────────────────────────');
//       debugPrint('[LAYER] "${layer.name}" features=${layer.features.length}');

//       int shown = 0;
//       for (final feature in layer.features) {
//         if (shown >= 5) {
//           debugPrint('  ... and ${layer.features.length - shown} more features');
//           break;
//         }

//         feature.decodeGeometry();
//         final props = feature.decodeProperties();
//         final propsMap = <String, String>{};
//         for (final entry in props.entries) {
//           final v = entry.value;
//           final val = v.dartStringValue ?? v.dartIntValue?.toString() ?? v.dartDoubleValue?.toString() ?? v.dartBoolValue?.toString() ?? '?';
//           propsMap[entry.key] = val;
//         }

//         String coordInfo = 'type=${feature.type}';
//         try {
//           if (feature.type == VectorTileGeomType.POINT) {
//             final gj = feature.toGeoJson<GeoJsonPoint>(x: x, y: y, z: z);
//             if (gj?.geometry != null) {
//               final c = gj!.geometry!.coordinates;
//               coordInfo = 'POINT(${c[1].toStringAsFixed(4)}, ${c[0].toStringAsFixed(4)}) dist=${_haversineKm(queryLat, queryLng, c[1], c[0]).toStringAsFixed(2)}km';
//             }
//           } else if (feature.type == VectorTileGeomType.POLYGON) {
//             coordInfo = 'POLYGON';
//           } else if (feature.type == VectorTileGeomType.LINESTRING) {
//             coordInfo = 'LINESTRING';
//           }
//         } catch (_) {}

//         debugPrint('  [$coordInfo] $propsMap');
//         shown++;
//       }
//     }
//     debugPrint('═══════════════════════════════════════');
//   }
// }

