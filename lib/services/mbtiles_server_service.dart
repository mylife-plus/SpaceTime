import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';

/// Service to run a local HTTP server that serves tiles from mbtiles file
/// This allows Mapbox to load tiles via HTTP instead of direct file access
class MbtilesServerService {
  static final MbtilesServerService _instance = MbtilesServerService._();
  static MbtilesServerService get instance => _instance;

  MbtilesServerService._();

  HttpServer? _server;
  Database? _database;
  int _port = 8080;
  bool _isRunning = false;

  /// Immutable asset bytes (glyphs/sprites) reused across style settle requests.
  final Map<String, Uint8List> _assetByteCache = {};

  Database? get database => _database;

  bool get isRunning => _isRunning;

  /// Get the server URL
  String? get serverUrl => _isRunning ? 'http://localhost:$_port' : null;

  /// Start the local tile server
  Future<String?> startServer(String mbtilesPath) async {
    if (_isRunning) {
      debugPrint('[MbtilesServer] Server already running at http://localhost:$_port');
      return serverUrl;
    }

    try {
      debugPrint('[MbtilesServer] 🚀 Starting local tile server...');
      debugPrint('[MbtilesServer] 📁 MBTiles path: $mbtilesPath');

      // Open the mbtiles database
      _database = await openDatabase(
        mbtilesPath,
        readOnly: true,
      );

      debugPrint('[MbtilesServer] ✅ MBTiles database opened successfully');

      // Start HTTP server using direct bind to avoid check-then-bind port races.
      _server = await _bindServerOnAvailablePort();
      _port = _server!.port;
      _isRunning = true;

      debugPrint('[MbtilesServer] ✅ Server started at http://localhost:$_port');

      // Handle requests
      _server!.listen(_handleRequest, onError: (error) {
        debugPrint('[MbtilesServer] ❌ Server error: $error');
      });

      return serverUrl;
    } catch (e) {
      debugPrint('[MbtilesServer] ❌ Failed to start server: $e');
      _isRunning = false;
      return null;
    }
  }

  /// Bind server directly on the first available port in range.
  /// This avoids races between "port check" and actual bind.
  Future<HttpServer> _bindServerOnAvailablePort() async {
    for (int port = 8080; port <= 8090; port++) {
      try {
        return await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      } catch (e) {
        // Port is in use, try next one
        continue;
      }
    }
    // Last resort: ask OS for any available ephemeral port.
    return await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  }

  /// Handle HTTP requests
  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final uri = request.uri;
      final pathSegments = uri.pathSegments;

      // Handle sprite requests: /sprites/{name}.json or /sprites/{name}.png or /sprites/{name}@2x.png
      if (pathSegments.length >= 2 && pathSegments[0] == 'sprites') {
        await _serveSprite(request, pathSegments.sublist(1).join('/'));
        return;
      }

      // Handle font requests: /fonts/{fontstack}/{range}.pbf
      if (pathSegments.length == 3 && pathSegments[0] == 'fonts') {
        await _serveFont(request, pathSegments[1], pathSegments[2]);
        return;
      }

      // Parse tile request: /{z}/{x}/{y}.pbf or /{z}/{x}/{y}.png
      if (pathSegments.length == 3) {
        final z = int.tryParse(pathSegments[0]);
        final x = int.tryParse(pathSegments[1]);
        final yWithExt = pathSegments[2];
        final y = int.tryParse(yWithExt.split('.')[0]);

        if (z != null && x != null && y != null) {
          await _serveTile(request, z, x, y);
          return;
        }
      }

      // Serve metadata for root path
      if (uri.path == '/' || uri.path == '/metadata') {
        await _serveMetadata(request);
        return;
      }

      // 404 for unknown paths
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not found: ${uri.path}');
      await request.response.close();
    } catch (e) {
      debugPrint('[MbtilesServer] ❌ Error handling request: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Internal server error');
      await request.response.close();
    }
  }

  /// Serve a tile from the mbtiles database
  Future<void> _serveTile(HttpRequest request, int z, int x, int y) async {
    try {
      if (_database == null) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Database not initialized');
        await request.response.close();
        return;
      }

      // Convert TMS y to XYZ y (mbtiles uses TMS scheme)
      final tmsY = (1 << z) - 1 - y;

      // Query tile from database
      final result = await _database!.rawQuery(
        'SELECT tile_data FROM tiles WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
        [z, x, tmsY],
      );

      if (result.isNotEmpty && result.first['tile_data'] != null) {
        final tileData = result.first['tile_data'] as Uint8List;

        // Set appropriate headers
        request.response.headers.contentType = ContentType('application', 'x-protobuf');
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Content-Encoding', 'gzip');
        request.response.add(tileData);
        await request.response.close();

        debugPrint('[MbtilesServer] ✅ Served tile: $z/$x/$y (${tileData.length} bytes)');
      } else {
        // Tile not found
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        debugPrint('[MbtilesServer] ⚠️ Tile not found: $z/$x/$y');
      }
    } catch (e) {
      debugPrint('[MbtilesServer] ❌ Error serving tile: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  /// Serve metadata about the mbtiles file
  Future<void> _serveMetadata(HttpRequest request) async {
    try {
      if (_database == null) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Database not initialized');
        await request.response.close();
        return;
      }

      // Query metadata
      final result = await _database!.rawQuery('SELECT name, value FROM metadata');
      final metadata = <String, String>{};
      for (final row in result) {
        metadata[row['name'] as String] = row['value'] as String;
      }

      request.response.headers.contentType = ContentType.json;
      request.response.write(metadata.toString());
      await request.response.close();
    } catch (e) {
      debugPrint('[MbtilesServer] ❌ Error serving metadata: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  /// Load an asset once and reuse bytes for subsequent HTTP serves.
  Future<Uint8List?> _loadAssetBytesCached(String assetPath) async {
    final cached = _assetByteCache[assetPath];
    if (cached != null) return cached;
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      _assetByteCache[assetPath] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  /// Serve font glyphs from assets
  /// Request format: /fonts/{fontstack}/{range}.pbf
  /// Example: /fonts/Noto Sans Regular/0-255.pbf
  ///
  /// Offline styles often request Mapbox defaults (e.g. Open Sans) that we do
  /// not ship. Fall back to Noto Sans Regular so labels/cluster counts still
  /// render instead of blank glyphs from an empty PBF.
  Future<void> _serveFont(HttpRequest request, String fontstack, String rangeFile) async {
    const fallbackFont = 'Noto Sans Regular';
    try {
      final range = rangeFile.replaceAll('.pbf', '');
      final decodedFontstack = Uri.decodeComponent(fontstack);

      // Fontstack can be comma-separated ("Open Sans Regular,Arial Unicode MS Regular").
      final candidates = <String>[
        ...decodedFontstack
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty),
        if (!decodedFontstack.contains(fallbackFont)) fallbackFont,
      ];

      for (final candidate in candidates) {
        final assetPath = 'assets/fonts/$candidate/$range.pbf';
        final fromCache = _assetByteCache.containsKey(assetPath);
        final bytes = await _loadAssetBytesCached(assetPath);
        if (bytes == null) continue;

        request.response.headers.contentType =
            ContentType('application', 'x-protobuf');
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.add(bytes);
        await request.response.close();

        if (!fromCache) {
          if (candidate != decodedFontstack &&
              candidate != decodedFontstack.split(',').first.trim()) {
            debugPrint(
              '[MbtilesServer] ⚠️ Font "$decodedFontstack" missing → '
              'served fallback $candidate/$range.pbf (${bytes.length} bytes)',
            );
          } else {
            debugPrint(
              '[MbtilesServer] ✅ Served font: $candidate/$range.pbf '
              '(${bytes.length} bytes)',
            );
          }
        }
        return;
      }

      debugPrint(
        '[MbtilesServer] ❌ No glyphs for "$decodedFontstack" range $range '
        '(tried $candidates) — returning empty PBF (text will be blank)',
      );
      request.response.headers.contentType =
          ContentType('application', 'x-protobuf');
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.add(<int>[]);
      await request.response.close();
    } catch (e) {
      debugPrint('[MbtilesServer] ❌ Error serving font $fontstack/$rangeFile: $e');
      request.response.headers.contentType =
          ContentType('application', 'x-protobuf');
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.add(<int>[]);
      await request.response.close();
    }
  }

  /// Serve sprite files from assets
  /// Request format: /sprites/{name}.json or /sprites/{name}.png or /sprites/{name}@2x.png
  /// Example: /sprites/osm-liberty.json, /sprites/osm-liberty.png
  Future<void> _serveSprite(HttpRequest request, String spritePath) async {
    try {
      final assetPath = 'assets/$spritePath';
      final fromCache = _assetByteCache.containsKey(assetPath);
      final bytes = await _loadAssetBytesCached(assetPath);

      if (bytes != null) {
        if (spritePath.endsWith('.json')) {
          request.response.headers.contentType = ContentType.json;
        } else if (spritePath.endsWith('.png')) {
          request.response.headers.contentType = ContentType('image', 'png');
        } else {
          request.response.headers.contentType = ContentType.binary;
        }

        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.add(bytes);
        await request.response.close();

        if (!fromCache) {
          debugPrint(
            '[MbtilesServer] ✅ Served sprite: $spritePath (${bytes.length} bytes)',
          );
        }
        return;
      }

      debugPrint(
        '[MbtilesServer] ⚠️ Sprite not found: $assetPath (returning empty response)',
      );

      if (spritePath.endsWith('.json')) {
        request.response.headers.contentType = ContentType.json;
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.write('{}');
      } else if (spritePath.endsWith('.png')) {
        request.response.headers.contentType = ContentType('image', 'png');
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        final emptyPng = [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
          0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
          0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
          0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
          0x42, 0x60, 0x82
        ];
        request.response.add(emptyPng);
      } else {
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.add(<int>[]);
      }

      await request.response.close();
    } catch (e) {
      debugPrint('[MbtilesServer] ❌ Error serving sprite $spritePath: $e');
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.add(<int>[]);
      await request.response.close();
    }
  }

  /// Stop the server
  Future<void> stopServer() async {
    if (!_isRunning) {
      debugPrint('[MbtilesServer] Server not running');
      return;
    }

    try {
      debugPrint('[MbtilesServer] 🛑 Stopping server...');

      await _server?.close(force: true);
      await _database?.close();

      _server = null;
      _database = null;
      _isRunning = false;

      debugPrint('[MbtilesServer] ✅ Server stopped');
    } catch (e) {
      debugPrint('[MbtilesServer] ❌ Error stopping server: $e');
    }
  }
}
