import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to load mbtiles from assets and make them available for offline use
class AssetTileLoaderService {
  static AssetTileLoaderService? _instance;
  static AssetTileLoaderService get instance =>
      _instance ??= AssetTileLoaderService._();

  AssetTileLoaderService._();

  static const String ASSET_MBTILES_PATH = 'assets/11_included.mbtiles';
  static const String LOCAL_MBTILES_FILENAME = '11_included.mbtiles';
  static const String PREFS_KEY_ASSET_TILES_LOADED = 'asset_tiles_loaded';
  static const String PREFS_KEY_ASSET_TILES_PATH = 'asset_tiles_path';

  bool _isLoaded = false;
  String? _localTilesPath;

  /// Check if asset tiles are already loaded
  Future<bool> isAssetTilesLoaded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoaded = prefs.getBool(PREFS_KEY_ASSET_TILES_LOADED) ?? false;
      final savedPath = prefs.getString(PREFS_KEY_ASSET_TILES_PATH);

      if (isLoaded && savedPath != null) {
        final file = File(savedPath);
        if (await file.exists()) {
          _isLoaded = true;
          _localTilesPath = savedPath;
          debugPrint('[AssetTileLoader] ✅ Asset tiles already loaded at: $savedPath');
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('[AssetTileLoader] ❌ Error checking asset tiles: $e');
      return false;
    }
  }

  /// Load mbtiles from assets to local storage
  Future<String?> loadAssetTilesToLocal() async {
    try {
      debugPrint('[AssetTileLoader] 🗺️ Starting to load asset tiles...');

      // Check if already loaded
      if (await isAssetTilesLoaded()) {
        debugPrint('[AssetTileLoader] ✅ Asset tiles already loaded, skipping');
        return _localTilesPath;
      }

      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final tilesDir = Directory('${appDir.path}/offline_tiles');

      // Create tiles directory if it doesn't exist
      if (!await tilesDir.exists()) {
        await tilesDir.create(recursive: true);
        debugPrint('[AssetTileLoader] 📁 Created tiles directory: ${tilesDir.path}');
      }

      // Define local file path
      final localFilePath = '${tilesDir.path}/$LOCAL_MBTILES_FILENAME';
      final localFile = File(localFilePath);

      // If file already exists, delete it first
      if (await localFile.exists()) {
        await localFile.delete();
        debugPrint('[AssetTileLoader] 🗑️ Deleted existing tiles file');
      }

      // Load asset as bytes
      debugPrint('[AssetTileLoader] 📥 Loading asset from: $ASSET_MBTILES_PATH');
      final ByteData data = await rootBundle.load(ASSET_MBTILES_PATH);
      final List<int> bytes = data.buffer.asUint8List();

      debugPrint('[AssetTileLoader] 💾 Writing ${bytes.length} bytes to local storage...');

      // Write to local file
      await localFile.writeAsBytes(bytes, flush: true);

      debugPrint('[AssetTileLoader] ✅ Asset tiles copied to: $localFilePath');

      // Verify file was written correctly
      if (await localFile.exists()) {
        final fileSize = await localFile.length();
        debugPrint('[AssetTileLoader] ✅ Verified file size: $fileSize bytes');

        // Save to preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(PREFS_KEY_ASSET_TILES_LOADED, true);
        await prefs.setString(PREFS_KEY_ASSET_TILES_PATH, localFilePath);

        // Update estimated tile count (approximate based on file size)
        // Typical mbtile is ~20KB per tile, so rough estimate
        final estimatedTileCount = (fileSize / 20000).round();
        await prefs.setInt('offline_downloaded_tile_count', estimatedTileCount);
        debugPrint('[AssetTileLoader] 📊 Estimated tile count: $estimatedTileCount');

        _isLoaded = true;
        _localTilesPath = localFilePath;

        return localFilePath;
      } else {
        debugPrint('[AssetTileLoader] ❌ Failed to verify written file');
        return null;
      }
    } catch (e) {
      debugPrint('[AssetTileLoader] ❌ Error loading asset tiles: $e');
      return null;
    }
  }

  /// Get the local path of loaded asset tiles
  String? getLocalTilesPath() {
    return _localTilesPath;
  }

  /// Clear loaded asset tiles
  Future<void> clearAssetTiles() async {
    try {
      if (_localTilesPath != null) {
        final file = File(_localTilesPath!);
        if (await file.exists()) {
          await file.delete();
          debugPrint('[AssetTileLoader] 🗑️ Deleted asset tiles file');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PREFS_KEY_ASSET_TILES_LOADED);
      await prefs.remove(PREFS_KEY_ASSET_TILES_PATH);

      _isLoaded = false;
      _localTilesPath = null;

      debugPrint('[AssetTileLoader] ✅ Asset tiles cleared');
    } catch (e) {
      debugPrint('[AssetTileLoader] ❌ Error clearing asset tiles: $e');
    }
  }
}

