import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to download mbtiles file from server
///
/// Storage Location: Application Support directory
/// - Persists across app updates
/// - Deleted on app uninstall (iOS limitation)
/// - Automatically re-downloads if file is missing
///
/// Note: On iOS, ALL app directories (Documents, Application Support, Caches, tmp)
/// are deleted when the app is uninstalled. There is no way to persist files across
/// uninstalls without using iCloud or external storage. For a 4.5GB file, iCloud is
/// not practical, so we use Application Support and auto-detect missing files.
class MbtilesDownloadService extends GetxController {
  static MbtilesDownloadService? _instance;
  static MbtilesDownloadService get instance =>
      _instance ??= MbtilesDownloadService._();

  MbtilesDownloadService._();

  // Direct download URL from server
  static const String MBTILES_DOWNLOAD_URL = 'http://codetivelab.com/spacetime/11_included.mbtiles';
  static const String MBTILES_FILENAME = '11_included.mbtiles';
  static const String PREFS_KEY_MBTILES_DOWNLOADED = 'mbtiles_downloaded';
  static const String PREFS_KEY_MBTILES_PATH = 'mbtiles_path';

  // Reactive state
  final RxBool isDownloading = false.obs;
  final RxBool isCompleted = false.obs;
  final RxBool hasError = false.obs;
  final RxDouble downloadProgress = 0.0.obs;
  final RxString statusText = "Ready to download".obs;
  final RxString errorMessage = "".obs;
  final RxInt downloadedBytes = 0.obs;
  final RxInt totalBytes = 0.obs;

  String? _localMbtilesPath;
  CancelToken? _cancelToken;

  /// Check if mbtiles file is already downloaded
  Future<bool> isMbtilesDownloaded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDownloaded = prefs.getBool(PREFS_KEY_MBTILES_DOWNLOADED) ?? false;
      final savedPath = prefs.getString(PREFS_KEY_MBTILES_PATH);

      debugPrint('[MbtilesDownload] 🔍 Checking download status: isDownloaded=$isDownloaded, savedPath=$savedPath');

      if (isDownloaded && savedPath != null) {
        final file = File(savedPath);
        // file.delete();
                // final file1 = File(savedPath);

        final exists = await file.exists();
        
        debugPrint('[MbtilesDownload] 🔍 File exists check: $exists for path: $savedPath');

        if (exists) {
          _localMbtilesPath = savedPath;
          debugPrint('[MbtilesDownload] ✅ MBTiles already downloaded at: $savedPath');

          // Reset any error states since file exists
          hasError.value = false;
          errorMessage.value = "";
          isCompleted.value = true;

          return true;
        } else {
          debugPrint('[MbtilesDownload] ❌ File does not exist at saved path: $savedPath');
          debugPrint('[MbtilesDownload] 🔄 Clearing saved preferences (file was deleted or app was reinstalled)');
          // Clear the saved preferences since the file doesn't exist
          await prefs.setBool(PREFS_KEY_MBTILES_DOWNLOADED, false);
          await prefs.remove(PREFS_KEY_MBTILES_PATH);
          await prefs.remove('offline_downloaded_tile_count');

          // Reset states for fresh download
          hasError.value = false;
          errorMessage.value = "";
          isCompleted.value = false;
          isDownloading.value = false;
          downloadProgress.value = 0.0;
          statusText.value = "Ready to download";
        }
      } else {
        debugPrint('[MbtilesDownload] ❌ MBTiles not marked as downloaded in preferences');

        // Reset states for fresh download
        hasError.value = false;
        errorMessage.value = "";
        isCompleted.value = false;
        isDownloading.value = false;
        downloadProgress.value = 0.0;
        statusText.value = "Ready to download";
      }

      return false;
    } catch (e) {
      debugPrint('[MbtilesDownload] ❌ Error checking mbtiles: $e');

      // Reset states on error
      hasError.value = false;
      errorMessage.value = "";
      isCompleted.value = false;
      isDownloading.value = false;

      return false;
    }
  }

  /// Get the local path of downloaded mbtiles file
  String? getLocalMbtilesPath() {
    return _localMbtilesPath;
  }

  /// Check and request storage permissions
  Future<bool> _checkStoragePermissions() async {
    try {
      debugPrint('[MbtilesDownload] 🔐 Checking storage permissions...');

      // Note: We're using getApplicationSupportDirectory() which is app-specific storage
      // On Android 10+ (API 29+), app-specific directories don't require storage permissions
      // On Android 9 and below, we still need to request storage permission

      if (Platform.isAndroid) {
        // Try to check storage permission status
        // On Android 13+ (API 33+), Permission.storage is deprecated but still works for compatibility
        var status = await Permission.storage.status;
        debugPrint('[MbtilesDownload] � Storage permission status: $status');

        // If permission is already granted, we're good
        if (status.isGranted) {
          debugPrint('[MbtilesDownload] ✅ Storage permission already granted');
          return true;
        }

        // If permission is not granted, request it
        // Note: On Android 13+, this might not be needed, but it won't hurt to ask
        debugPrint('[MbtilesDownload] 🔐 Requesting storage permission...');
        statusText.value = "Requesting storage permission...";

        status = await Permission.storage.request();
        debugPrint('[MbtilesDownload] 🔐 Storage permission after request: $status');

        if (!status.isGranted) {
          if (status.isPermanentlyDenied) {
            debugPrint('[MbtilesDownload] ❌ Storage permission permanently denied');
            hasError.value = true;
            errorMessage.value = "Storage permission is required to download offline maps. Please enable it in app settings.";
            statusText.value = "Permission denied";

            // Show dialog to open settings
            await _showPermissionDeniedDialog();
            return false;
          } else if (status.isDenied) {
            debugPrint('[MbtilesDownload] ⚠️ Storage permission denied');
            // On newer Android versions, this might be expected for app-specific storage
            // Let's try to proceed anyway since we're using app-specific directory
            debugPrint('[MbtilesDownload] ℹ️ Proceeding with app-specific storage (no permission needed on Android 10+)');
            return true;
          }
        }

        debugPrint('[MbtilesDownload] ✅ Storage permission granted');
        return true;
      } else if (Platform.isIOS) {
        // iOS doesn't need storage permissions for app-specific directories
        debugPrint('[MbtilesDownload] ✅ iOS: No storage permission needed for app directory');
        return true;
      }

      return true;
    } catch (e) {
      debugPrint('[MbtilesDownload] ❌ Error checking storage permissions: $e');
      debugPrint('[MbtilesDownload] ℹ️ Proceeding anyway - app-specific storage should work without permissions');
      // Don't fail the download - app-specific storage should work without permissions
      return true;
    }
  }

  /// Show permission denied dialog
  Future<void> _showPermissionDeniedDialog() async {
    return Get.dialog(
      AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Storage Permission Required',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          'Storage permission is required to download offline maps. Please enable it in app settings.',
          style: TextStyle(
            color: Colors.white70,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey[400],
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Get.back();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  /// Download mbtiles file from Google Drive
  Future<String?> downloadMbtiles() async {
    // if (isDownloading.value) {
    //   debugPrint('[MbtilesDownload] ⚠️ Download already in progress');
    //   return null;
    // }

    try { 
       final appDir = await getApplicationSupportDirectory();
      final tilesDir = Directory('${appDir.path}/offline_tiles');
              debugPrint('[MbtilesDownload] 📁 fetching tiles directory ${tilesDir.path}');

    }catch(e) {
            debugPrint('[MbtilesDownload] 🗺️ File Creation issue ${e}');

    }

    try {
      debugPrint('[MbtilesDownload] 🗺️ Starting mbtiles download...');

      isDownloading.value = true;
      hasError.value = false;
      isCompleted.value = false;
      downloadProgress.value = 0.0;
      statusText.value = "Preparing download...";

      // Note: We use getApplicationSupportDirectory() which doesn't require storage permissions
      debugPrint('[MbtilesDownload] ℹ️ Using app-specific storage - no permissions required');

      // Get app support directory (more persistent than documents directory)
      // Note: On iOS, this directory persists across app updates but NOT across uninstalls
      // For truly persistent storage across uninstalls, we would need iCloud or external storage
      final appDir = await getApplicationSupportDirectory();
      final tilesDir = Directory('${appDir.path}/offline_tiles');
              debugPrint('[MbtilesDownload] 📁 fetching tiles directory ${tilesDir.path}');

      // Create tiles directory if it doesn't exist
      if (!await tilesDir.exists()) {
        await tilesDir.create(recursive: true);
        debugPrint('[MbtilesDownload] 📁 Created tiles directory: ${tilesDir.path}');
      } else {
        debugPrint('[MbtilesDownload] 📁 Deleting Folder: ${tilesDir.path}');

        
        await tilesDir.delete(); 
           await tilesDir.create(recursive: true);
      }

      // Define local file path
      final localFilePath = '${tilesDir.path}/$MBTILES_FILENAME';
      final localFile = File(localFilePath);

      // If file already exists, delete it first
      if (await localFile.exists()) {
        await localFile.delete();
        debugPrint('[MbtilesDownload] 🗑️ Deleted existing mbtiles file');
      }

      // Create Dio instance with custom configuration
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(hours: 2), // Large file needs more time
        sendTimeout: const Duration(minutes: 5),
        followRedirects: true,
        maxRedirects: 10,
        validateStatus: (status) => status! < 500,
      ));

      _cancelToken = CancelToken();

      // Download from direct HTTP server
      debugPrint('[MbtilesDownload] � Preparing to download mbtiles from server...');
      statusText.value = "Connecting to server...";

      // Use the direct download URL
      final downloadUrl = MBTILES_DOWNLOAD_URL;

      debugPrint('[MbtilesDownload] 📥 Download URL: $downloadUrl');
      debugPrint('[MbtilesDownload] � Saving to: $localFilePath');
      statusText.value = "Starting download...";

      // Download the file with progress tracking
      await dio.download(
        downloadUrl,
        localFilePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            downloadedBytes.value = received;
            totalBytes.value = total;
            downloadProgress.value = received / total;

            final receivedMB = (received / (1024 * 1024)).toStringAsFixed(1);
            final totalMB = (total / (1024 * 1024)).toStringAsFixed(1);
            final receivedGB = (received / (1024 * 1024 * 1024)).toStringAsFixed(2);
            final totalGB = (total / (1024 * 1024 * 1024)).toStringAsFixed(2);

            statusText.value = "Downloading: $receivedGB GB / $totalGB GB";

            // Log progress every 5%
            final progressPercent = (downloadProgress.value * 100);
            if (progressPercent % 5 < 0.1) {
              debugPrint('[MbtilesDownload] 📊 Progress: ${progressPercent.toStringAsFixed(1)}% - $receivedGB GB / $totalGB GB');
            }
          } else {
            // Total size unknown, just show received
            final receivedMB = (received / (1024 * 1024)).toStringAsFixed(1);
            final receivedGB = (received / (1024 * 1024 * 1024)).toStringAsFixed(2);
            statusText.value = "Downloading: $receivedGB GB";

            // Log every 100MB when total is unknown
            if (received % (100 * 1024 * 1024) < 1024 * 1024) {
              debugPrint('[MbtilesDownload] 📊 Downloaded: $receivedGB GB ($receivedMB MB)');
            }
          }
        },
        options: Options(
          followRedirects: true,
          maxRedirects: 10,
          receiveTimeout: const Duration(hours: 2),
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': '*/*',
            'Accept-Encoding': 'gzip, deflate, br',
            'Connection': 'keep-alive',
          },
        ),
      );

      debugPrint('[MbtilesDownload] ✅ Download completed: $localFilePath');

      // Verify file was written correctly
      if (await localFile.exists()) {
        final fileSize = await localFile.length();
        final fileSizeMB = (fileSize / (1024 * 1024)).toStringAsFixed(1);
        final fileSizeGB = (fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2);

        debugPrint('[MbtilesDownload] 📊 Verifying downloaded file...');
        debugPrint('[MbtilesDownload] 📁 File size: $fileSizeGB GB ($fileSizeMB MB) = $fileSize bytes');

        // Read first few bytes to check file type
        final bytes = await localFile.openRead(0, 200).first;
        final header = String.fromCharCodes(bytes.take(100).toList());

        debugPrint('[MbtilesDownload] 🔍 File header (first 100 chars): ${header.substring(0, header.length > 100 ? 100 : header.length)}');

        // Check if it's HTML (error page)
        if (header.contains('<!DOCTYPE') || header.contains('<html') || header.contains('<HTML')) {
          debugPrint('[MbtilesDownload] ❌ Downloaded file is HTML, not mbtiles!');
          debugPrint('[MbtilesDownload] 📄 Full header: $header');
          await localFile.delete();
          hasError.value = true;
          errorMessage.value = """
Download Error

The server returned an HTML error page instead of the mbtiles file.

Possible reasons:
1. File not found on server
2. Server access denied
3. Incorrect download URL

Download URL: $MBTILES_DOWNLOAD_URL
""";
          statusText.value = "Download failed - server error";
          return null;
        }

        // Validate file size - should be at least 4GB for the mbtiles file
        const minExpectedSize = 4 * 1024 * 1024 * 1024; // 4GB in bytes

        if (fileSize < minExpectedSize) {
          debugPrint('[MbtilesDownload] ❌ File size too small! Expected at least 4GB, got $fileSizeGB GB');
          debugPrint('[MbtilesDownload] ⚠️ This might be an error response from Google Drive');

          hasError.value = true;
          errorMessage.value = "Downloaded file is too small ($fileSizeGB GB). Expected at least 4GB. Please ensure the Google Drive file is publicly accessible.";
          statusText.value = "Download failed - file too small";
          return null;
        }

        debugPrint('[MbtilesDownload] ✅ File size validation passed');

        // Save to preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(PREFS_KEY_MBTILES_DOWNLOADED, true);
        await prefs.setString(PREFS_KEY_MBTILES_PATH, localFilePath);

        // Update estimated tile count (approximate based on file size)
        final estimatedTileCount = (fileSize / 20000).round();
        await prefs.setInt('offline_downloaded_tile_count', estimatedTileCount);
        debugPrint('[MbtilesDownload] 📊 Estimated tile count: $estimatedTileCount');

        _localMbtilesPath = localFilePath;
        isCompleted.value = true;
        statusText.value = "Download completed! $fileSizeGB GB";

        return localFilePath;
      } else {
        debugPrint('[MbtilesDownload] ❌ Failed to verify downloaded file - file does not exist');
        hasError.value = true;
        errorMessage.value = "Failed to verify downloaded file";
        statusText.value = "Download failed";
        return null;
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ❌ Error downloading mbtiles: $e');
      hasError.value = true;
      errorMessage.value = e.toString();
      statusText.value = "Download failed: ${e.toString()}";
      return null;
    } finally {
      isDownloading.value = false;
      _cancelToken = null;
    }
  }

  /// Cancel ongoing download
  Future<void> cancelDownload() async {
    if (_cancelToken != null && !_cancelToken!.isCancelled) {
      _cancelToken!.cancel('Download cancelled by user');
      debugPrint('[MbtilesDownload] ❌ Download cancelled');
      statusText.value = "Download cancelled";
      isDownloading.value = false;
    }
  }

  /// Clear downloaded mbtiles file
  Future<void> clearMbtiles() async {
    try {
      if (_localMbtilesPath != null) {
        final file = File(_localMbtilesPath!);
        if (await file.exists()) {
          await file.delete();
          debugPrint('[MbtilesDownload] 🗑️ Deleted mbtiles file');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(PREFS_KEY_MBTILES_DOWNLOADED);
      await prefs.remove(PREFS_KEY_MBTILES_PATH);

      _localMbtilesPath = null;
      isCompleted.value = false;

      debugPrint('[MbtilesDownload] ✅ MBTiles cleared');
    } catch (e) {
      debugPrint('[MbtilesDownload] ❌ Error clearing mbtiles: $e');
    }
  }
}

