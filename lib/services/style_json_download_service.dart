import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for downloading and managing custom-style.json file
class StyleJsonDownloadService extends GetxService {
  static StyleJsonDownloadService get instance => Get.find<StyleJsonDownloadService>();

  // Cloudflare R2 URL for style.json
  static const String STYLE_JSON_URL = 'https://pub-5c6d5b96bc9b424080c7d9716062e560.r2.dev/custom-style.json';

  // Local filename
  static const String LOCAL_STYLE_JSON_FILENAME = 'custom-style.json';

  // SharedPreferences keys
  static const String PREFS_KEY_STYLE_JSON_DOWNLOADED = 'style_json_downloaded';
  static const String PREFS_KEY_STYLE_JSON_PATH = 'style_json_path';

  // Reactive state
  final RxBool isDownloading = false.obs;
  final RxBool isDownloaded = false.obs;
  final RxString errorMessage = ''.obs;
  final RxDouble downloadProgress = 0.0.obs;

  @override
  void onInit() {
    super.onInit();
    debugPrint('[StyleJsonDownloadService] Service initialized');
  }

  /// Check if style.json is already downloaded
  Future<bool> isStyleJsonDownloaded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDownloaded = prefs.getBool(PREFS_KEY_STYLE_JSON_DOWNLOADED) ?? false;
      final savedPath = prefs.getString(PREFS_KEY_STYLE_JSON_PATH);

      if (isDownloaded && savedPath != null) {
        final file = File(savedPath);
        final exists = await file.exists();
        debugPrint('[StyleJsonDownloadService] Style.json exists: $exists at $savedPath');
        return exists;
      }

      return false;
    } catch (e) {
      debugPrint('[StyleJsonDownloadService] Error checking style.json: $e');
      return false;
    }
  }

  /// Get local style.json file path
  String? getLocalStyleJsonPath() {
    try {
      // This is synchronous, but we need async to get the directory
      // So we'll return null here and use getLocalStyleJsonPathAsync instead
      return null;
    } catch (e) {
      debugPrint('[StyleJsonDownloadService] Error getting path: $e');
      return null;
    }
  }

  /// Get local style.json file path (async version)
  Future<String> getLocalStyleJsonPathAsync() async {
    final appDir = await getApplicationSupportDirectory();
    final styleDir = Directory('${appDir.path}/offline_tiles');
    return '${styleDir.path}/$LOCAL_STYLE_JSON_FILENAME';
  }

  /// Download style.json from Cloudflare R2
  Future<String?> downloadStyleJson() async {
    if (isDownloading.value) {
      debugPrint('[StyleJsonDownloadService] ⚠️ Download already in progress');
      return null;
    }

    try {
      isDownloading.value = true;
      errorMessage.value = '';
      downloadProgress.value = 0.0;

      debugPrint('[StyleJsonDownloadService] 📥 Starting style.json download from: $STYLE_JSON_URL');

      // Get app support directory
      final appDir = await getApplicationSupportDirectory();
      final styleDir = Directory('${appDir.path}/offline_tiles');

      // Create directory if it doesn't exist
      if (!await styleDir.exists()) {
        await styleDir.create(recursive: true);
        debugPrint('[StyleJsonDownloadService] 📁 Created directory: ${styleDir.path}');
      }

      final filePath = '${styleDir.path}/$LOCAL_STYLE_JSON_FILENAME';
      final file = File(filePath);

      // Download the file
      final response = await http.get(Uri.parse(STYLE_JSON_URL));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        debugPrint('[StyleJsonDownloadService] ✅ Style.json downloaded successfully');
        debugPrint('[StyleJsonDownloadService] 📁 Saved to: $filePath');

        // Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(PREFS_KEY_STYLE_JSON_DOWNLOADED, true);
        await prefs.setString(PREFS_KEY_STYLE_JSON_PATH, filePath);

        isDownloaded.value = true;
        downloadProgress.value = 1.0;

        return filePath;
      } else {
        throw Exception('Failed to download style.json: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[StyleJsonDownloadService] ❌ Error downloading style.json: $e');
      errorMessage.value = e.toString();
      return null;
    } finally {
      isDownloading.value = false;
    }
  }

  /// Read style.json content from local file
  Future<String?> readStyleJsonContent() async {
    try {
      final filePath = await getLocalStyleJsonPathAsync();
      final file = File(filePath);

      if (await file.exists()) {
        final content = await file.readAsString();
        debugPrint('[StyleJsonDownloadService] ✅ Read style.json content (${content.length} bytes)');
        return content;
      } else {
        debugPrint('[StyleJsonDownloadService] ⚠️ Style.json file not found at: $filePath');
        return null;
      }
    } catch (e) {
      debugPrint('[StyleJsonDownloadService] ❌ Error reading style.json: $e');
      return null;
    }
  }
}

