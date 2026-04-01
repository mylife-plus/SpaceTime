import 'dart:io';
import 'dart:async';
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
      debugPrint('[MbtilesServer] 📥 Request: ${uri.path}');

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

  /// Serve font glyphs from assets
  /// Request format: /fonts/{fontstack}/{range}.pbf
  /// Example: /fonts/Noto Sans Regular/0-255.pbf
  Future<void> _serveFont(HttpRequest request, String fontstack, String rangeFile) async {
    try {
      // Remove .pbf extension from range
      final range = rangeFile.replaceAll('.pbf', '');

      // Construct asset path
      // URL-decode fontstack to handle spaces (e.g., "Noto%20Sans%20Regular" -> "Noto Sans Regular")
      final decodedFontstack = Uri.decodeComponent(fontstack);
      final assetPath = 'assets/fonts/$decodedFontstack/$range.pbf';

      debugPrint('[MbtilesServer] 📝 Loading font: $assetPath');

      // Try to load font from assets
      try {
        final fontData = await rootBundle.load(assetPath);
        final bytes = fontData.buffer.asUint8List();

        // Set appropriate headers
        request.response.headers.contentType = ContentType('application', 'x-protobuf');
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.add(bytes);
        await request.response.close();

        debugPrint('[MbtilesServer] ✅ Served font: $decodedFontstack/$range.pbf (${bytes.length} bytes)');
      } catch (assetError) {
        // Font file doesn't exist (e.g., high Unicode ranges not included in font)
        // Return an empty PBF instead of 404 to prevent map errors
        debugPrint('[MbtilesServer] ⚠️ Font not found: $assetPath (returning empty PBF)');

        // Empty PBF file (valid protobuf with no glyphs)
        // This prevents Mapbox from showing errors for missing glyph ranges
        final emptyPbf = <int>[];

        request.response.headers.contentType = ContentType('application', 'x-protobuf');
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.add(emptyPbf);
        await request.response.close();

        debugPrint('[MbtilesServer] ✅ Served empty PBF for missing font: $decodedFontstack/$range.pbf');
      }
    } catch (e) {
      debugPrint('[MbtilesServer] ❌ Error serving font $fontstack/$rangeFile: $e');

      // Return empty PBF even on error to prevent map load failures
      request.response.headers.contentType = ContentType('application', 'x-protobuf');
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
      // Construct asset path
      final assetPath = 'assets/$spritePath';

      debugPrint('[MbtilesServer] 🎨 Loading sprite: $assetPath');

      try {
        // Load sprite from assets
        final spriteData = await rootBundle.load(assetPath);
        final bytes = spriteData.buffer.asUint8List();

        // Set appropriate headers based on file extension
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

        debugPrint('[MbtilesServer] ✅ Served sprite: $spritePath (${bytes.length} bytes)');
      } catch (assetError) {
        // Sprite file doesn't exist - return empty response
        debugPrint('[MbtilesServer] ⚠️ Sprite not found: $assetPath (returning empty response)');

        // Return appropriate empty content based on file type
        if (spritePath.endsWith('.json')) {
          // Empty JSON object for missing sprite metadata
          request.response.headers.contentType = ContentType.json;
          request.response.headers.add('Access-Control-Allow-Origin', '*');
          request.response.write('{}');
        } else if (spritePath.endsWith('.png')) {
          // Empty PNG (1x1 transparent pixel)
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.headers.add('Access-Control-Allow-Origin', '*');
          // Minimal valid PNG: 1x1 transparent pixel
          final emptyPng = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 dimensions
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, // RGBA, CRC
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, // IDAT chunk
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, // Compressed data
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, // CRC
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, // IEND chunk
            0x42, 0x60, 0x82
          ];
          request.response.add(emptyPng);
        } else {
          request.response.headers.add('Access-Control-Allow-Origin', '*');
          request.response.add(<int>[]);
        }

        await request.response.close();
        debugPrint('[MbtilesServer] ✅ Served empty response for missing sprite: $spritePath');
      }
    } catch (e) {
      debugPrint('[MbtilesServer] ❌ Error serving sprite $spritePath: $e');

      // Return empty response even on error
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
