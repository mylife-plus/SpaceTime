import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spacetime/services/app_lock_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:background_downloader/background_downloader.dart';

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

  MbtilesDownloadService._() {
    if (Get.isRegistered<UiController>()) {
      ever(Get.find<UiController>().selectedLanguage, (_) {
        _refreshLocalizedStatus();
      });
    }
  }

  String _statusL10nKey = '';
  List<Object?> _statusL10nArgs = const [];

  /// Last real download fraction in \[0, 1\]. Used so special downloader
  /// sentinel values (retry=-4, paused=-5, …) do not flash as -400% in the UI
  /// or reset the bar to 0 on every retry.
  double _lastGoodProgress = 0.0;

  /// Maps [background_downloader] progress (including sentinels) to a stable
  /// 0–1 value for the UI.
  double _displayProgressFrom(double raw) {
    if (raw >= 0.0 && raw <= 1.0) {
      _lastGoodProgress = raw;
      return raw;
    }
    // Special values from background_downloader models.dart:
    // progressFailed=-1, canceled=-2, notFound=-3, waitingToRetry=-4, paused=-5
    if (raw == progressWaitingToRetry ||
        raw == progressPaused ||
        raw == progressFailed ||
        raw == progressCanceled ||
        raw == progressNotFound) {
      return _lastGoodProgress;
    }
    return _lastGoodProgress;
  }

  void _applyProgress(double raw) {
    downloadProgress.value = _displayProgressFrom(raw);
  }

  /// Best-effort progress from a partial tiles.mbtiles when the downloader
  /// only reports a sentinel (e.g. waitingToRetry = -4).
  Future<void> _seedProgressFromPartialFileIfNeeded() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final partial =
          File('${appDir.path}/offline_tiles/$LOCAL_MBTILES_FILENAME');
      if (!await partial.exists()) return;
      final len = await partial.length();
      if (len <= 0) return;
      const expectedBytes = _approxExpectedBytes;
      final approx = (len / expectedBytes).clamp(0.0, 0.99);
      if (approx > _lastGoodProgress) {
        _lastGoodProgress = approx;
        downloadProgress.value = approx;
        debugPrint(
          '[MbtilesDownload] 📐 Seeded progress from partial file: '
          '${(approx * 100).toStringAsFixed(1)}% ($len bytes)',
        );
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Could not seed progress from file: $e');
    }
  }

  void _setStatusText(String key, [List<Object?> args = const []]) {
    _statusL10nKey = key;
    _statusL10nArgs = args.isEmpty ? const [] : List<Object?>.from(args);
    statusText.value =
        args.isEmpty ? key.tr : trKey(key, _statusL10nArgs);
  }

  void _refreshLocalizedStatus() {
    if (_statusL10nKey.isEmpty) return;
    statusText.value = _statusL10nArgs.isEmpty
        ? _statusL10nKey.tr
        : trKey(_statusL10nKey, List<Object?>.from(_statusL10nArgs));
  }

  /// Always returns status in the current app locale (safe after language switch).
  String get displayStatusText {
    if (_statusL10nKey.isEmpty) return statusText.value;
    return _statusL10nArgs.isEmpty
        ? _statusL10nKey.tr
        : trKey(_statusL10nKey, List<Object?>.from(_statusL10nArgs));
  }

  /// Re-apply current locale to cached status key/args.
  void refreshStatusForLocale() => _refreshLocalizedStatus();

  // Cloudflare R2 storage configuration
  // TODO: Replace with your public R2 URL (e.g., https://pub-xxxxx.r2.dev)
  // or custom domain (e.g., https://tiles.yourdomain.com)
  static const String CLOUDFLARE_BASE_URL = 'https://pub-5c6d5b96bc9b424080c7d9716062e560.r2.dev';

  // Optional: Add authentication token if bucket is private
  // Leave empty if using public R2 URL
  static const String CLOUDFLARE_AUTH_TOKEN = ''; // Add your token here if needed

  // Available zoom levels
  static const List<int> AVAILABLE_ZOOM_LEVELS = [11, 12];

  // File naming pattern: {zoom}_included.mbtiles
  static String getMbtilesFilename(int zoomLevel) => '${zoomLevel}_included.mbtiles';

  // Get download URL for specific zoom level
  static String getDownloadUrl(int zoomLevel) => '$CLOUDFLARE_BASE_URL/${getMbtilesFilename(zoomLevel)}';

  // SharedPreferences keys
  static const String PREFS_KEY_MBTILES_DOWNLOADED = 'mbtiles_downloaded';
  static const String PREFS_KEY_MBTILES_PATH = 'mbtiles_path';
  static const String PREFS_KEY_SELECTED_ZOOM_LEVEL = 'selected_zoom_level';

  // Default zoom level
  static const int DEFAULT_ZOOM_LEVEL = 11;

  // Local filename (always use same name for consistency)
  static const String LOCAL_MBTILES_FILENAME = 'tiles.mbtiles';

  // Reactive state
  final RxBool isDownloading = false.obs;
  final RxBool isCompleted = false.obs;
  final RxBool hasError = false.obs;
  final RxDouble downloadProgress = 0.0.obs;
  final RxString statusText = ''.obs;
  final RxString errorMessage = "".obs;
  final RxInt downloadedBytes = 0.obs;
  final RxInt totalBytes = 0.obs;

  String? _localMbtilesPath;
  DownloadTask? _backgroundTask;
  Timer? _androidProgressPollTimer;
  bool _downloaderConfigured = false;

  /// Expected mbtiles size (~4.5 GB for zoom 11) used when Content-Length is unknown.
  static const int _approxExpectedBytes = 4831838208; // 4.5 * 1024^3

  Future<String> _resolveLocalMbtilesPath() async {
    if (_localMbtilesPath != null && _localMbtilesPath!.isNotEmpty) {
      return _localMbtilesPath!;
    }
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}/offline_tiles/$LOCAL_MBTILES_FILENAME';
  }

  void _startAndroidProgressPolling() {
    if (!Platform.isAndroid) return;
    _androidProgressPollTimer?.cancel();
    _androidProgressPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_syncProgressFromDatabaseAndFile()),
    );
    unawaited(_syncProgressFromDatabaseAndFile());
  }

  void _stopAndroidProgressPolling() {
    _androidProgressPollTimer?.cancel();
    _androidProgressPollTimer = null;
  }

  /// When the native worker cannot post to the Flutter background channel
  /// (common on Android / MIUI), progress is stored locally — poll DB + file.
  Future<void> _syncProgressFromDatabaseAndFile() async {
    if (!isDownloading.value && !isCompleted.value) return;
    try {
      unawaited(FileDownloader().resumeFromBackground());

      final records = await FileDownloader().database.allRecords();
      for (final record in records) {
        if (record.task.filename != LOCAL_MBTILES_FILENAME) continue;

        if (record.status == TaskStatus.running ||
            record.status == TaskStatus.enqueued ||
            record.status == TaskStatus.waitingToRetry ||
            record.status == TaskStatus.paused) {
          isDownloading.value = true;
        }

        if (record.progress >= 0.0 && record.progress <= 1.0) {
          _applyProgress(record.progress);
        } else if (record.progress == progressWaitingToRetry) {
          await _seedProgressFromPartialFileIfNeeded();
        }

        if (record.expectedFileSize > 0) {
          totalBytes.value = record.expectedFileSize;
          downloadedBytes.value =
              (downloadProgress.value * record.expectedFileSize).round();
        }

        if (record.status == TaskStatus.complete && !isCompleted.value) {
          debugPrint('[MbtilesDownload] 📦 DB reports complete — finalizing');
          await _finalizeSuccessfulDownload(
            await _resolveLocalMbtilesPath(),
            await getSelectedZoomLevel(),
          );
          return;
        }

        if (record.status == TaskStatus.failed && !hasError.value) {
          isDownloading.value = false;
          hasError.value = true;
          _setStatusText('text_download_failed');
          _stopAndroidProgressPolling();
          return;
        }
      }

      await _seedProgressFromPartialFileIfNeeded();
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Progress sync failed: $e');
    }
  }

  /// Pull updates stored while the app/engine was disconnected (Android).
  Future<void> resumeDownloadUpdatesFromBackground() async {
    if (!Platform.isAndroid) return;
    await FileDownloader().resumeFromBackground();
    await _syncProgressFromDatabaseAndFile();
  }

  @override
  void onClose() {
    _stopAndroidProgressPolling();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    _setStatusText('mbtiles_status_ready_to_download');
    _initializeBackgroundDownloader();
    _checkForResumedDownloads();
  }

  /// Check for any downloads that were in progress when app was closed
  Future<void> _checkForResumedDownloads() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));

      final tasks = await FileDownloader().database.allRecords();
      debugPrint('[MbtilesDownload] 🔍 Checking for resumed downloads: ${tasks.length} tasks found');

      for (final record in tasks) {
        if (record.task.filename == LOCAL_MBTILES_FILENAME) {
          debugPrint('[MbtilesDownload] 🔄 Found existing download task: ${record.task.taskId}');
          debugPrint('[MbtilesDownload] 🔄 Task status: ${record.status}');
          debugPrint('[MbtilesDownload] 🔄 Task progress: ${record.progress}');

          _backgroundTask = record.task as DownloadTask;

          if (record.status == TaskStatus.running || record.status == TaskStatus.enqueued) {
            isDownloading.value = true;
            _applyProgress(record.progress);
            _setStatusText('mbtiles_status_resuming');
            debugPrint('[MbtilesDownload] ▶️ Resuming download from ${(downloadProgress.value * 100).toStringAsFixed(1)}%');
          } else if (record.status == TaskStatus.paused) {
            _applyProgress(record.progress);
            _setStatusText(
              'mbtiles_status_paused_at_pct',
              [(downloadProgress.value * 100).toStringAsFixed(1)],
            );
          } else if (record.status == TaskStatus.waitingToRetry) {
            isDownloading.value = true;
            _applyProgress(record.progress);
            await _seedProgressFromPartialFileIfNeeded();
            _setStatusText('mbtiles_status_resuming');
            debugPrint(
              '[MbtilesDownload] ⏳ Waiting to retry — holding UI at ${(downloadProgress.value * 100).toStringAsFixed(1)}%',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Error checking for resumed downloads: $e');
    }
  }

  Future<void> _initializeBackgroundDownloader() async {
    if (!_downloaderConfigured) {
      if (Platform.isAndroid) {
        await FileDownloader().configure(
          globalConfig: [
            (Config.runInForeground, true),
          ],
        );
      }
      _downloaderConfigured = true;
    }

    await FileDownloader().resumeFromBackground();

    // Listen to ALL updates and filter by metadata or filename
    FileDownloader().updates.listen((update) async {
      debugPrint('[MbtilesDownload] 🔔 Received update for task: ${update.task.taskId}');
      debugPrint('[MbtilesDownload] 🔔 Task filename: ${update.task.filename}');
      debugPrint('[MbtilesDownload] 🔔 Update type: ${update.runtimeType}');

      // Match by filename instead of taskId since taskId changes between app restarts
      if (update.task.filename == LOCAL_MBTILES_FILENAME) {
        // Store the task reference if we don't have it
        if (_backgroundTask == null || _backgroundTask!.taskId != update.task.taskId) {
          _backgroundTask = update.task as DownloadTask;
          debugPrint('[MbtilesDownload] 🔄 Updated background task reference: ${_backgroundTask!.taskId}');
        }

        if (update is TaskProgressUpdate) {
          // Never feed sentinel values (-4 waitingToRetry, etc.) straight to the UI.
          if (update.progress == progressWaitingToRetry) {
            isDownloading.value = true;
            _applyProgress(update.progress);
            await _seedProgressFromPartialFileIfNeeded();
            _setStatusText('mbtiles_status_resuming');
            debugPrint(
              '[MbtilesDownload] ⏳ Retrying — UI stays at ${(downloadProgress.value * 100).toStringAsFixed(1)}%',
            );
            return;
          }
          if (update.progress == progressPaused) {
            _applyProgress(update.progress);
            _setStatusText('mbtiles_status_download_paused');
            return;
          }
          if (update.progress < 0) {
            // failed / canceled / notFound — keep last good % until status update
            _applyProgress(update.progress);
            debugPrint(
              '[MbtilesDownload] ⚠️ Non-display progress sentinel: ${update.progress}',
            );
            return;
          }

          _applyProgress(update.progress);

          debugPrint('[MbtilesDownload] 📊 Progress update: ${(downloadProgress.value * 100).toStringAsFixed(1)}%');
          debugPrint('[MbtilesDownload] 📊 Expected file size: ${update.expectedFileSize}');
          debugPrint('[MbtilesDownload] 📊 Network speed: ${update.networkSpeed}');
          debugPrint('[MbtilesDownload] 📊 Time remaining: ${update.timeRemaining}');

          if (update.expectedFileSize > 0) {
            final received = (downloadProgress.value * update.expectedFileSize).toInt();
            downloadedBytes.value = received;
            totalBytes.value = update.expectedFileSize;

            final receivedGB = (received / (1024 * 1024 * 1024)).toStringAsFixed(2);
            final totalGB = (update.expectedFileSize / (1024 * 1024 * 1024)).toStringAsFixed(2);

            _setStatusText(
              'mbtiles_status_downloading_gb_pair',
              [receivedGB, totalGB],
            );
            debugPrint('[MbtilesDownload] 📊 Downloaded: $receivedGB GB / $totalGB GB');
          } else {
            final received = (downloadProgress.value * 1024 * 1024 * 1024).toInt();
            final receivedGB = (received / (1024 * 1024 * 1024)).toStringAsFixed(2);
            _setStatusText('mbtiles_status_downloading_gb_only', [receivedGB]);
            debugPrint('[MbtilesDownload] 📊 Downloaded: $receivedGB GB (size unknown)');
          }
        } else if (update is TaskStatusUpdate) {
          debugPrint('[MbtilesDownload] 📡 Status update: ${update.status}');

          if (update.status == TaskStatus.running ||
              update.status == TaskStatus.enqueued ||
              update.status == TaskStatus.waitingToRetry) {
            isDownloading.value = true;
            if (update.status == TaskStatus.waitingToRetry) {
              _setStatusText('mbtiles_status_resuming');
            } else {
              _setStatusText('mbtiles_status_downloading');
            }
          } else if (update.status == TaskStatus.complete) {
            isDownloading.value = false;
            isCompleted.value = true;
            _applyProgress(1.0);
            _setStatusText('text_download_completed');
            _stopAndroidProgressPolling();

            final localPath = await _resolveLocalMbtilesPath();
            await _finalizeSuccessfulDownload(
              localPath,
              await getSelectedZoomLevel(),
            );
          } else if (update.status == TaskStatus.failed) {
            isDownloading.value = false;
            _setStatusText('text_download_failed');
            hasError.value = true;
            _stopAndroidProgressPolling();
          } else if (update.status == TaskStatus.paused) {
            _setStatusText('mbtiles_status_download_paused');
          }
        }
      }
    });
  }

  Future<void> _finalizeSuccessfulDownload(
    String localFilePath,
    int selectedZoom,
  ) async {
    if (isCompleted.value) return;
    try {
      final localFile = File(localFilePath);
      if (!await localFile.exists()) {
        debugPrint('[MbtilesDownload] ⚠️ Finalize skipped — file missing');
        return;
      }

      final fileSize = await localFile.length();
      final fileSizeGB = (fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2);

      final bytes = await localFile.openRead(0, 200).first;
      final header = String.fromCharCodes(bytes.take(100).toList());
      if (header.contains('<!DOCTYPE') ||
          header.contains('<html') ||
          header.contains('<HTML')) {
        debugPrint('[MbtilesDownload] ❌ Downloaded file is HTML, not mbtiles!');
        await localFile.delete();
        hasError.value = true;
        errorMessage.value = trKey(
          'dialog_content_mbtiles_server_returned_html',
          [getDownloadUrl(selectedZoom), selectedZoom],
        );
        _setStatusText('mbtiles_status_download_failed_server_error');
        isCompleted.value = false;
        isDownloading.value = false;
        return;
      }

      const minExpectedSize = 4 * 1024 * 1024 * 1024;
      if (fileSize < minExpectedSize) {
        debugPrint('[MbtilesDownload] ❌ File size too small: $fileSizeGB GB');
        hasError.value = true;
        errorMessage.value = trKey('mbtiles_error_file_too_small', [fileSizeGB]);
        _setStatusText('mbtiles_status_download_failed_file_small');
        isCompleted.value = false;
        isDownloading.value = false;
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PREFS_KEY_MBTILES_DOWNLOADED, true);
      await prefs.setBool('mbtiles_download_completed', true);
      await prefs.setString(PREFS_KEY_MBTILES_PATH, localFilePath);

      final estimatedTileCount = (fileSize / 20000).round();
      await prefs.setInt('offline_downloaded_tile_count', estimatedTileCount);

      _localMbtilesPath = localFilePath;
      isCompleted.value = true;
      isDownloading.value = false;
      hasError.value = false;
      _applyProgress(1.0);
      _setStatusText('mbtiles_status_download_completed_gb', [fileSizeGB]);
      _stopAndroidProgressPolling();
      _backgroundTask = null;
      debugPrint('[MbtilesDownload] ✅ Download finalized: $fileSizeGB GB');
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Error finalizing download: $e');
    }
  }

  /// @deprecated Use [_finalizeSuccessfulDownload] instead.
  Future<void> _markDownloadAsCompleted() async {
    await _finalizeSuccessfulDownload(
      await _resolveLocalMbtilesPath(),
      await getSelectedZoomLevel(),
    );
  }

  /// Get selected zoom level from preferences
  Future<int> getSelectedZoomLevel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(PREFS_KEY_SELECTED_ZOOM_LEVEL) ?? DEFAULT_ZOOM_LEVEL;
    } catch (e) {
      debugPrint('[MbtilesDownload] Error getting zoom level: $e');
      return DEFAULT_ZOOM_LEVEL;
    }
  }

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

          // Do not wipe live download UI state — a check during an in-flight
          // download was resetting progress to 0% (and briefly showing -400%).
          if (!isDownloading.value) {
            hasError.value = false;
            errorMessage.value = "";
            isCompleted.value = false;
            downloadProgress.value = 0.0;
            _lastGoodProgress = 0.0;
            _setStatusText('mbtiles_status_ready_to_download');
          }
        }
      } else {
        debugPrint('[MbtilesDownload] ❌ MBTiles not marked as downloaded in preferences');

        if (!isDownloading.value) {
          hasError.value = false;
          errorMessage.value = "";
          isCompleted.value = false;
          downloadProgress.value = 0.0;
          _lastGoodProgress = 0.0;
          _setStatusText('mbtiles_status_ready_to_download');
        }
      }

      return false;
    } catch (e) {
      debugPrint('[MbtilesDownload] ❌ Error checking mbtiles: $e');

      if (!isDownloading.value) {
        hasError.value = false;
        errorMessage.value = "";
        isCompleted.value = false;
      }

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
        _setStatusText('mbtiles_status_requesting_storage_permission');

        status = await Permission.storage.request();
        debugPrint('[MbtilesDownload] 🔐 Storage permission after request: $status');

        if (!status.isGranted) {
          if (status.isPermanentlyDenied) {
            debugPrint('[MbtilesDownload] ❌ Storage permission permanently denied');
            hasError.value = true;
            errorMessage.value = 'dialog_content_storage_permission_is_required_to_downloa'.tr;
            _setStatusText('mbtiles_status_permission_denied');

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
        title: Text(
          'title_text_storage_permission_required'.tr,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'dialog_content_storage_permission_is_required_to_downloa'.tr,
          style: TextStyle(
            color: Colors.white70,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              'text_cancel_10'.tr,
              style: TextStyle(
                color: Colors.grey[400],
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              if (Get.isRegistered<AppLockController>()) {
                Get.find<AppLockController>().openExternalSettings(openAppSettings);
              } else {
                openAppSettings();
              }
              Get.back();
            },
            child: Text(
              'text_open_settings_6'.tr,
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

  /// Download mbtiles file from Cloudflare R2 storage
  /// [zoomLevel] - The zoom level to download (11 or 12)
  /// [enableBackgroundDownload] - If false, download will only work in foreground (iOS without background refresh)
  Future<String?> downloadMbtiles({int? zoomLevel, bool enableBackgroundDownload = true}) async {
    if (isDownloading.value) {
      debugPrint(
        '[MbtilesDownload] ⚠️ Download already in progress at ${(downloadProgress.value * 100).toStringAsFixed(1)}% — not restarting',
      );
      return null;
    }

    // Prefer resuming an existing incomplete task over wiping offline_tiles
    // and starting from 0% again (common after retry / screen revisit).
    try {
      final existing = await FileDownloader().database.allRecords();
      for (final record in existing) {
        if (record.task.filename != LOCAL_MBTILES_FILENAME) continue;
        final active = record.status == TaskStatus.running ||
            record.status == TaskStatus.enqueued ||
            record.status == TaskStatus.waitingToRetry ||
            record.status == TaskStatus.paused;
        if (!active) continue;

        _backgroundTask = record.task as DownloadTask;
        isDownloading.value = true;
        hasError.value = false;
        isCompleted.value = false;
        _applyProgress(record.progress);
        debugPrint(
          '[MbtilesDownload] ▶️ Reusing existing task ${record.task.taskId} '
          '(${record.status}) at ${(downloadProgress.value * 100).toStringAsFixed(1)}%',
        );

        if (record.status == TaskStatus.paused) {
          final task = record.task as DownloadTask;
          final resumed = await FileDownloader().resume(task);
          debugPrint('[MbtilesDownload] ▶️ resume() => $resumed');
          _setStatusText('mbtiles_status_resuming');
        } else {
          _setStatusText('mbtiles_status_downloading');
        }
        _startAndroidProgressPolling();
        // Completion is handled by the global updates listener + DB polling.
        return null;
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Could not check existing tasks: $e');
    }

    try { 
       final appDir = await getApplicationSupportDirectory();
      final tilesDir = Directory('${appDir.path}/offline_tiles');
              debugPrint('[MbtilesDownload] 📁 fetching tiles directory ${tilesDir.path}');

    }catch(e) {
            debugPrint('[MbtilesDownload] 🗺️ File Creation issue ${e}');

    }

    try {
      // Get or use default zoom level
      final selectedZoom = zoomLevel ?? DEFAULT_ZOOM_LEVEL;

      // Validate zoom level
      if (!AVAILABLE_ZOOM_LEVELS.contains(selectedZoom)) {
        debugPrint('[MbtilesDownload] ❌ Invalid zoom level: $selectedZoom');
        errorMessage.value = 'mbtiles_error_invalid_zoom'.tr;
        hasError.value = true;
        return null;
      }

      debugPrint('[MbtilesDownload] 🗺️ Starting mbtiles download for zoom level $selectedZoom...');

      isDownloading.value = true;
      hasError.value = false;
      isCompleted.value = false;
      _lastGoodProgress = 0.0;
      downloadProgress.value = 0.0;
      _setStatusText('mbtiles_status_preparing_download');

      // Save selected zoom level to preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(PREFS_KEY_SELECTED_ZOOM_LEVEL, selectedZoom);
      debugPrint('[MbtilesDownload] 💾 Saved selected zoom level: $selectedZoom');

      // Note: We use getApplicationSupportDirectory() which doesn't require storage permissions
      debugPrint('[MbtilesDownload] ℹ️ Using app-specific storage - no permissions required');

      // Get app support directory (more persistent than documents directory)
      // Note: On iOS, this directory persists across app updates but NOT across uninstalls
      // For truly persistent storage across uninstalls, we would need iCloud or external storage
      final appDir = await getApplicationSupportDirectory();
      final tilesDir = Directory('${appDir.path}/offline_tiles');
      debugPrint('[MbtilesDownload] 📁 Tiles directory: ${tilesDir.path}');

      // Create tiles directory if it doesn't exist
      if (!await tilesDir.exists()) {
        await tilesDir.create(recursive: true);
        debugPrint('[MbtilesDownload] 📁 Created tiles directory: ${tilesDir.path}');
      } else {
        debugPrint('[MbtilesDownload] 📁 Tiles directory exists, cleaning up: ${tilesDir.path}');

        try {
          // iOS/Android: Delete directory recursively (including all files inside)
          // This requires recursive: true to delete non-empty directories
          debugPrint('[MbtilesDownload] 🗑️ Attempting to delete directory recursively...');
          await tilesDir.delete(recursive: true);
          debugPrint('[MbtilesDownload] ✅ Successfully deleted tiles directory');

          // Recreate the directory immediately after deletion
          await tilesDir.create(recursive: true);
          debugPrint('[MbtilesDownload] 📁 Recreated tiles directory');
        } catch (e) {
          debugPrint('[MbtilesDownload] ⚠️ Error deleting directory: $e');

          // Fallback: Try to delete individual files if directory deletion fails
          // This can happen on iOS if the directory is locked or in use
          try {
            debugPrint('[MbtilesDownload] 🔄 Attempting fallback: deleting individual files...');
            final files = await tilesDir.list(recursive: true).toList();
            debugPrint('[MbtilesDownload] 📋 Found ${files.length} items to delete');

            for (var entity in files) {
              try {
                if (entity is File) {
                  await entity.delete();
                  debugPrint('[MbtilesDownload] 🗑️ Deleted file: ${entity.path}');
                } else if (entity is Directory) {
                  await entity.delete(recursive: true);
                  debugPrint('[MbtilesDownload] 🗑️ Deleted subdirectory: ${entity.path}');
                }
              } catch (e3) {
                debugPrint('[MbtilesDownload] ⚠️ Error deleting ${entity.path}: $e3');
              }
            }
            debugPrint('[MbtilesDownload] ✅ Fallback deletion completed');
          } catch (e2) {
            debugPrint('[MbtilesDownload] ❌ Fallback deletion also failed: $e2');
            // If all deletion attempts fail, we'll just overwrite the file later
          }
        }
      }

      // Define local file path (always use same filename for consistency)
      final localFilePath = '${tilesDir.path}/$LOCAL_MBTILES_FILENAME';
      final localFile = File(localFilePath);

      debugPrint('[MbtilesDownload] 📁 Local file path: $localFilePath');

      // If file already exists, delete it first
      if (await localFile.exists()) {
        try {
          await localFile.delete();
          debugPrint('[MbtilesDownload] 🗑️ Deleted existing mbtiles file: $localFilePath');
        } catch (e) {
          debugPrint('[MbtilesDownload] ⚠️ Error deleting existing file: $e');
          // On iOS, if file is locked, try to overwrite it instead
          debugPrint('[MbtilesDownload] 🔄 Will attempt to overwrite the file during download');
        }
      }

      debugPrint('[MbtilesDownload] 📡 Preparing to download mbtiles from Cloudflare R2...');
      _setStatusText('mbtiles_status_connecting_cloudflare');

      final downloadUrl = getDownloadUrl(selectedZoom);

      final headers = <String, String>{};
      if (CLOUDFLARE_AUTH_TOKEN.isNotEmpty) {
        headers['Authorization'] = 'Bearer $CLOUDFLARE_AUTH_TOKEN';
        debugPrint('[MbtilesDownload] 🔐 Using authentication token');
      }

      debugPrint('[MbtilesDownload] 📥 Download URL: $downloadUrl');
      debugPrint('[MbtilesDownload] 🔢 Zoom level: $selectedZoom');
      debugPrint('[MbtilesDownload] 💾 Saving to: $localFilePath');
      debugPrint('[MbtilesDownload] 📁 Directory: ${tilesDir.path}');
      _setStatusText('mbtiles_status_starting_download');

      // Check and request notification permission first
      debugPrint('[MbtilesDownload] 🔔 Checking notification permission...');
     
      _backgroundTask = DownloadTask(
        url: downloadUrl,
        filename: LOCAL_MBTILES_FILENAME,
        directory: 'offline_tiles',
        baseDirectory: BaseDirectory.applicationSupport,
        updates: Updates.statusAndProgress,
        requiresWiFi: false,
        retries: 3,
        allowPause: true,
        metaData: 'mbtiles_download_zoom_$selectedZoom',
        headers: headers.isNotEmpty ? headers : null,
      );

      debugPrint('[MbtilesDownload] 🎯 Created download task: ${_backgroundTask!.taskId}');
      debugPrint('[MbtilesDownload] 🎯 Task URL: ${_backgroundTask!.url}');
      debugPrint('[MbtilesDownload] 🎯 Task filename: ${_backgroundTask!.filename}');
      debugPrint('[MbtilesDownload] 🎯 Task directory: ${_backgroundTask!.directory}');

      // Configure notifications with more visible settings
      FileDownloader().configureNotificationForGroup(
        FileDownloader.defaultGroup,
        running: TaskNotification(
          'mbtiles_notif_running_title'.tr,
          'mbtiles_notif_running_body'.tr,
        ),
        complete: TaskNotification(
          'mbtiles_notif_complete_title'.tr,
          'mbtiles_notif_complete_body'.tr,
        ),
        error: TaskNotification(
          'mbtiles_notif_error_title'.tr,
          'mbtiles_notif_error_body'.tr,
        ),
        paused: TaskNotification(
          'mbtiles_notif_paused_title'.tr,
          'mbtiles_notif_paused_body'.tr,
        ),
        progressBar: true,
      );
      final downloader = FileDownloader();
      debugPrint('[MbtilesDownload] 🔔 Notifications configured');

      debugPrint('[MbtilesDownload] 🚀 Starting download...');

      if (Platform.isAndroid) {
        final enqueued = await downloader.enqueue(_backgroundTask!);
        if (!enqueued) {
          throw Exception('Failed to enqueue mbtiles download task');
        }
        debugPrint('[MbtilesDownload] 📋 Enqueued on Android (background worker)');
        _startAndroidProgressPolling();
        return null;
      }

      final result = await downloader.download(
        _backgroundTask!,
        onProgress: (progress) {
          _applyProgress(progress);
          debugPrint(
            '[MbtilesDownload] 📊 Progress: ${(downloadProgress.value * 100).toStringAsFixed(1)}% (raw=$progress)',
          );
        },
        onStatus: (status) {
          debugPrint('[MbtilesDownload] 📡 Status: $status');

          if (status == TaskStatus.complete) {
            debugPrint('[MbtilesDownload] ✅ Download completed successfully');
            _setStatusText('text_download_completed');
          } else if (status == TaskStatus.failed) {
            debugPrint('[MbtilesDownload] ❌ Download failed');
            hasError.value = true;
            errorMessage.value = 'text_download_failed'.tr;
            _setStatusText('text_download_failed');
          } else if (status == TaskStatus.waitingToRetry) {
            debugPrint('[MbtilesDownload] ⏳ Waiting to retry (keeping last progress)');
            _setStatusText('mbtiles_status_resuming');
          } else if (status == TaskStatus.running) {
            debugPrint('[MbtilesDownload] 🏃 Download running');
            _setStatusText('mbtiles_status_downloading');
          } else if (status == TaskStatus.enqueued) {
            debugPrint('[MbtilesDownload] 📋 Download enqueued');
            _setStatusText('mbtiles_status_preparing');
          }
        },
      );

      debugPrint('[MbtilesDownload] 🏁 Download result status: ${result.status}');

      if (result.status != TaskStatus.complete) {
        throw Exception('Download failed with status: ${result.status}');
      }

      debugPrint('[MbtilesDownload] ✅ Download completed: $localFilePath');
      await _finalizeSuccessfulDownload(localFilePath, selectedZoom);
      return localFilePath;
    } catch (e) {
      debugPrint('[MbtilesDownload] ❌ Error downloading mbtiles: $e');
      hasError.value = true;
      errorMessage.value = e.toString();
      _setStatusText('mbtiles_error_download_with_message', [e.toString()]);
      return null;
    } finally {
      _stopAndroidProgressPolling();
      if (!Platform.isAndroid) {
        isDownloading.value = false;
        _backgroundTask = null;
      }
    }
  }

  

  Future<void> cancelDownload() async {
    if (_backgroundTask != null) {
      await FileDownloader().cancelTaskWithId(_backgroundTask!.taskId);
      debugPrint('[MbtilesDownload] ❌ Download cancelled');
      _setStatusText('mbtiles_status_download_cancelled');
      isDownloading.value = false;
      _backgroundTask = null;
      _stopAndroidProgressPolling();
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

