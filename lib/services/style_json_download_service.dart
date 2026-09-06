import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for downloading and managing custom-style.json file.
///
/// Uses Dio (not [FileDownloader]) so the small style download does not
/// trigger Android download / foreground-service notifications that would
/// otherwise compete with the large MBTiles tile download.
class StyleJsonDownloadService extends GetxService {
  static StyleJsonDownloadService get instance =>
      Get.find<StyleJsonDownloadService>();

  // Cloudflare R2 URL for style.json
  static const String STYLE_JSON_URL =
      'https://pub-5c6d5b96bc9b424080c7d9716062e560.r2.dev/custom-style.json';

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

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.bytes,
    ),
  );

  @override
  void onInit() {
    super.onInit();
    debugPrint('[StyleJsonDownloadService] Service initialized');
  }

  /// Check if style.json is already downloaded
  Future<bool> isStyleJsonDownloaded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDownloaded =
          prefs.getBool(PREFS_KEY_STYLE_JSON_DOWNLOADED) ?? false;
      final savedPath = prefs.getString(PREFS_KEY_STYLE_JSON_PATH);

      if (isDownloaded && savedPath != null) {
        final file = File(savedPath);
        final exists = await file.exists();
        debugPrint(
          '[StyleJsonDownloadService] Style.json exists: $exists at $savedPath',
        );
        return exists;
      }

      // Also accept a file present on disk even if prefs were cleared.
      final fallbackPath = await getLocalStyleJsonPathAsync();
      if (await File(fallbackPath).exists()) {
        await prefs.setBool(PREFS_KEY_STYLE_JSON_DOWNLOADED, true);
        await prefs.setString(PREFS_KEY_STYLE_JSON_PATH, fallbackPath);
        return true;
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

  /// Download style.json from Cloudflare R2.
  /// [enableBackgroundDownload] kept for API compatibility with callers;
  /// style is small enough that Dio foreground download is preferred so it
  /// never posts a system download notification on Android.
  Future<String?> downloadStyleJson({
    bool enableBackgroundDownload = true,
  }) async {
    if (isDownloading.value) {
      debugPrint('[StyleJsonDownloadService] ⚠️ Download already in progress');
      return null;
    }

    try {
      // Skip network if we already have a valid local copy.
      if (await isStyleJsonDownloaded()) {
        final existing = await getLocalStyleJsonPathAsync();
        debugPrint(
          '[StyleJsonDownloadService] ✅ Style.json already present at $existing',
        );
        isDownloaded.value = true;
        downloadProgress.value = 1.0;
        return existing;
      }

      isDownloading.value = true;
      errorMessage.value = '';
      downloadProgress.value = 0.0;

      debugPrint(
        '[StyleJsonDownloadService] 📥 Starting style.json download from: $STYLE_JSON_URL',
      );

      final appDir = await getApplicationSupportDirectory();
      final styleDir = Directory('${appDir.path}/offline_tiles');

      if (!await styleDir.exists()) {
        await styleDir.create(recursive: true);
        debugPrint(
          '[StyleJsonDownloadService] 📁 Created directory: ${styleDir.path}',
        );
      }

      final filePath = '${styleDir.path}/$LOCAL_STYLE_JSON_FILENAME';
      final tempPath = '$filePath.tmp';

      // Up to 3 attempts — mirrors previous FileDownloader retries: 3
      Object? lastError;
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          await _dio.download(
            STYLE_JSON_URL,
            tempPath,
            onReceiveProgress: (received, total) {
              if (total > 0) {
                downloadProgress.value = received / total;
              }
            },
          );

          final tempFile = File(tempPath);
          if (!await tempFile.exists() || await tempFile.length() < 10) {
            throw Exception('Downloaded style.json is empty or missing');
          }

          // Atomic replace so a partial download never becomes the live file.
          final target = File(filePath);
          if (await target.exists()) {
            await target.delete();
          }
          await tempFile.rename(filePath);

          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(PREFS_KEY_STYLE_JSON_DOWNLOADED, true);
          await prefs.setString(PREFS_KEY_STYLE_JSON_PATH, filePath);

          isDownloaded.value = true;
          downloadProgress.value = 1.0;

          debugPrint(
            '[StyleJsonDownloadService] ✅ Style.json downloaded successfully',
          );
          debugPrint('[StyleJsonDownloadService] 📁 Saved to: $filePath');
          return filePath;
        } catch (e) {
          lastError = e;
          debugPrint(
            '[StyleJsonDownloadService] ⚠️ Attempt $attempt failed: $e',
          );
          try {
            final tmp = File(tempPath);
            if (await tmp.exists()) await tmp.delete();
          } catch (_) {}
          if (attempt < 3) {
            await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
          }
        }
      }

      throw Exception('Failed to download style.json: $lastError');
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
        debugPrint(
          '[StyleJsonDownloadService] ✅ Read style.json content (${content.length} bytes)',
        );
        return content;
      } else {
        debugPrint(
          '[StyleJsonDownloadService] ⚠️ Style.json file not found at: $filePath',
        );
        return null;
      }
    } catch (e) {
      debugPrint('[StyleJsonDownloadService] ❌ Error reading style.json: $e');
      return null;
    }
  }
}
