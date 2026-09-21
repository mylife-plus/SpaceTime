import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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

  /// IMPORTANT: this must go through [Get.put] (not just a plain
  /// constructor call) — GetX only invokes [onInit] for instances created
  /// through its DI container. Before this fix, `_instance ??=
  /// MbtilesDownloadService._()` bypassed that entirely, so onInit() (and
  /// therefore the global download-status stream listener,
  /// resumeFromBackground(), and _checkForResumedDownloads()) never ran on
  /// Android — the only thing left driving progress/completion was a
  /// one-shot resync on app resume, which is exactly why downloads would
  /// "sometimes" complete (app happened to be backgrounded/foregrounded)
  /// and otherwise sit stuck with no error and no way to retry.
  static MbtilesDownloadService get instance {
    if (_instance == null) {
      _instance = MbtilesDownloadService._();
      if (Get.isRegistered<MbtilesDownloadService>()) {
        Get.delete<MbtilesDownloadService>(force: true);
      }
      Get.put<MbtilesDownloadService>(_instance!, permanent: true);
    }
    return _instance!;
  }

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
  /// 0–1 value for the UI. Progress is **monotonic** — a new/restarted task
  /// reporting 0% must not wipe a higher % already confirmed from disk or
  /// a previous update (that was causing the bar to bounce 0.5 → 0.2 → 0).
  double _displayProgressFrom(double raw) {
    if (raw >= 0.0 && raw <= 1.0) {
      if (raw >= _lastGoodProgress) {
        _lastGoodProgress = raw;
      }
      return _lastGoodProgress;
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

  /// Highest temp-file byte count observed this session (and persisted).
  /// Used to stop the native downloader from truncating a larger partial
  /// when stale resume metadata has a lower [requiredStartByte].
  int _maxBytesSeen = 0;
  static const String _prefsKeyMaxPartialBytes = 'mbtiles_max_partial_bytes';

  void _updateGbStatusFromBytes(int bytes) {
    final expected =
        totalBytes.value > 0 ? totalBytes.value : _approxExpectedBytes;
    // Never let the GB label bounce downward mid-download.
    downloadedBytes.value = math.max(downloadedBytes.value, bytes);
    if (totalBytes.value <= 0) totalBytes.value = expected;
    final receivedGB =
        (downloadedBytes.value / (1024 * 1024 * 1024)).toStringAsFixed(2);
    final totalGB = (expected / (1024 * 1024 * 1024)).toStringAsFixed(2);
    _setStatusText(
      'mbtiles_status_downloading_gb_pair',
      [receivedGB, totalGB],
    );
  }

  void _updateGbStatusFromProgress() {
    final expected =
        totalBytes.value > 0 ? totalBytes.value : _approxExpectedBytes;
    final received = (downloadProgress.value * expected).round();
    _updateGbStatusFromBytes(math.max(downloadedBytes.value, received));
  }

  Future<void> _loadMaxBytesCheckpoint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _maxBytesSeen =
          math.max(_maxBytesSeen, prefs.getInt(_prefsKeyMaxPartialBytes) ?? 0);
    } catch (_) {}
  }

  Future<void> _rememberMaxBytes(int bytes) async {
    if (bytes <= _maxBytesSeen) return;
    _maxBytesSeen = bytes;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKeyMaxPartialBytes, _maxBytesSeen);
    } catch (_) {}
  }

  Future<void> _clearMaxBytesCheckpoint() async {
    _maxBytesSeen = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyMaxPartialBytes);
    } catch (_) {}
  }

  /// Native Android code truncates the temp file DOWN to [requiredStartByte]
  /// when the file is larger. Keep resume JSON aligned with the **actively
  /// growing** temp (most recently modified), not a stale larger leftover.
  Future<void> _protectResumeDataFromTruncation() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final liveTemp = await _bestLiveDownloaderTemp(appDir.path);
      final resumeDir =
          Directory('${appDir.path}/backgroundDownloaderResumeData');
      if (!await resumeDir.exists()) return;

      await for (final entity in resumeDir.list()) {
        if (entity is! File) continue;
        if (await entity.length() < 8) continue;
        try {
          final raw = await entity.readAsString();
          if (raw.isEmpty) continue;
          final map = jsonDecode(raw) as Map<String, dynamic>;
          var path = map['data'] as String?;
          if (path == null || path.isEmpty) continue;

          // Prefer the most recently written live temp over a stale larger one.
          if (liveTemp != null && liveTemp.path != path) {
            debugPrint(
              '[MbtilesDownload] 🛡️ Retargeting resume temp '
              '${path.split('/').last} → '
              '${liveTemp.path.split('/').last} (${liveTemp.length} bytes)',
            );
            path = liveTemp.path;
            map['data'] = path;
          }

          final temp = File(path);
          if (!await temp.exists()) continue;
          final fileLen = await temp.length();
          await _rememberMaxBytes(fileLen);
          if (fileLen <= 0) continue;

          final currentStart = switch (map['requiredStartByte']) {
            final int v => v,
            final num v => v.toInt(),
            _ => 0,
          };
          if (currentStart == fileLen && map['data'] == path) continue;

          map['requiredStartByte'] = fileLen;
          map['data'] = path;
          await entity.writeAsString(jsonEncode(map));
          debugPrint(
            '[MbtilesDownload] 🛡️ Patched resume startByte '
            '$currentStart → $fileLen',
          );
        } catch (e) {
          debugPrint('[MbtilesDownload] ⚠️ Resume protect skip: $e');
        }
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Resume protect failed: $e');
    }
  }

  /// Best live downloader temp: **largest** wins.
  ///
  /// Preferring "newest" previously deleted multi-hundred-MB partials when a
  /// brand-new empty temp appeared during re-enqueue — catastrophic for
  /// resume. Size is the only reliable signal for a multi-GB Range download.
  ///
  /// [minBytes] defaults to 1MB for progress seeding. Cleanup must pass
  /// `minBytes: 0` so a brand-new temp is visible as a keep candidate only
  /// when no larger partial exists.
  Future<({String path, int length})?> _bestLiveDownloaderTemp(
    String appDirPath, {
    int minBytes = 1024 * 1024,
  }) async {
    ({String path, int length, DateTime modified})? best;
    final cutoff =
        DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    try {
      await for (final entity in Directory(appDirPath).list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : '';
        if (!name.startsWith('com.bbflight.background_downloader')) continue;
        final stat = await entity.stat();
        if (stat.modified.millisecondsSinceEpoch < cutoff) continue;
        final len = stat.size;
        if (len < minBytes) continue;
        if (best == null ||
            len > best.length ||
            (len == best.length && stat.modified.isAfter(best.modified))) {
          best = (path: entity.path, length: len, modified: stat.modified);
        }
      }
    } catch (_) {}
    if (best == null) return null;
    return (path: best.path, length: best.length);
  }

  /// Force WorkManager path (priority ≥ 1). Optionally mint a new taskId so
  /// Android JobScheduler cannot revive a prior UIDT job for the same id.
  DownloadTask _asWorkManagerTask(DownloadTask task, {bool newTaskId = false}) {
    final id = newTaskId
        ? 'mbtiles_${DateTime.now().millisecondsSinceEpoch}'
        : task.taskId;
    if (task.priority >= 1 && !newTaskId) return task;
    return task.copyWith(taskId: id, priority: 1);
  }

  /// Cancel + forget every legacy UIDT (priority 0) tiles.mbtiles record.
  /// Keeps on-disk temps and resume JSON so Range can continue via WorkManager.
  Future<void> _purgeUidtMbtilesTaskRecords() async {
    try {
      final records = await FileDownloader().database.allRecords();
      for (final record in records) {
        if (record.task.filename != LOCAL_MBTILES_FILENAME) continue;
        final task = record.task;
        if (task.priority != 0) continue;
        debugPrint(
          '[MbtilesDownload] 🧹 Purging UIDT record ${task.taskId} '
          '(priority 0) before WorkManager start',
        );
        try {
          await FileDownloader().cancelTaskWithId(task.taskId);
        } catch (_) {}
        try {
          await FileDownloader().database.deleteRecordWithId(task.taskId);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ UIDT purge failed: $e');
    }
  }

  /// Bytes already on disk for the *active* download.
  ///
  /// [minLiveTempBytes] is forwarded to [_bestLiveDownloaderTemp]. The
  /// default (1MB) is fine for progress seeding, but the ghost-download
  /// watchdog needs to see a live temp as soon as it exists (down to its own
  /// 64KB threshold) — otherwise a real, slow-but-healthy download under 1MB
  /// looks identical to an orphaned one and gets wiped + reset to 0%.
  Future<int> _activePartialBytesOnDisk({int minLiveTempBytes = 1024 * 1024}) async {
    final appDir = await getApplicationSupportDirectory();
    var best = 0;

    final finalFile =
        File('${appDir.path}/offline_tiles/$LOCAL_MBTILES_FILENAME');
    if (await finalFile.exists()) {
      best = math.max(best, await finalFile.length());
    }

    final resumeDir =
        Directory('${appDir.path}/backgroundDownloaderResumeData');
    if (await resumeDir.exists()) {
      await for (final entity in resumeDir.list()) {
        if (entity is! File) continue;
        try {
          final raw = await entity.readAsString();
          if (raw.isEmpty) continue;
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final path = map['data'] as String?;
          if (path != null) {
            final temp = File(path);
            if (await temp.exists()) {
              best = math.max(best, await temp.length());
            }
          }
        } catch (_) {}
      }
    }

    final live = await _bestLiveDownloaderTemp(
      appDir.path,
      minBytes: minLiveTempBytes,
    );
    if (live != null) {
      best = math.max(best, live.length);
    }

    return best;
  }

  /// Sync UI progress upward from on-disk bytes only — never pull the bar
  /// down (that was the increase/decrease bounce).
  Future<void> _seedProgressFromPartialFileIfNeeded() async {
    try {
      final len = await _activePartialBytesOnDisk();
      await _rememberMaxBytes(len);
      if (len <= 0) return;

      final expected = totalBytes.value > 0
          ? totalBytes.value
          : _approxExpectedBytes;
      final approx = (len / expected).clamp(0.0, 0.99);

      if (approx > _lastGoodProgress) {
        _lastGoodProgress = approx;
        downloadProgress.value = approx;
        _updateGbStatusFromBytes(len);
        debugPrint(
          '[MbtilesDownload] 📐 Seeded progress from on-disk partial: '
          '${(approx * 100).toStringAsFixed(1)}% ($len bytes)',
        );
      } else {
        _updateGbStatusFromBytes(len);
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Could not seed progress from file: $e');
    }
  }

  /// Delete every `com.bbflight.background_downloader*` temp except [keepPath].
  Future<int> _deleteDownloaderTempsExcept(String? keepPath) async {
    var freed = 0;
    try {
      final appDir = await getApplicationSupportDirectory();
      await for (final entity in Directory(appDir.path).list()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.isNotEmpty
            ? entity.uri.pathSegments.last
            : entity.path;
        if (!name.startsWith('com.bbflight.background_downloader')) continue;
        if (keepPath != null && entity.path == keepPath) continue;
        final len = await entity.length();
        try {
          await entity.delete();
          freed += len;
          debugPrint(
            '[MbtilesDownload] 🧹 Deleted leftover temp '
            '($len bytes): $name',
          );
        } catch (e) {
          debugPrint('[MbtilesDownload] ⚠️ Could not delete $name: $e');
        }
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Temp cleanup failed: $e');
    }
    return freed;
  }

  /// Keep at most one active temp (resume target). Delete every other leftover.
  /// Never runs a delete-all while downloading without a keep target, and
  /// never prefers a brand-new tiny temp over a large Range partial.
  Future<void> _cleanupOrphanDownloaderTemps() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      String? keep;
      var keepLen = 0;

      void consider(String path, int len) {
        if (len >= keepLen) {
          keep = path;
          keepLen = len;
        }
      }

      final resumeDir =
          Directory('${appDir.path}/backgroundDownloaderResumeData');
      if (await resumeDir.exists()) {
        await for (final entity in resumeDir.list()) {
          if (entity is! File) continue;
          try {
            final raw = await entity.readAsString();
            if (raw.isEmpty) continue;
            final map = jsonDecode(raw) as Map<String, dynamic>;
            final path = map['data'] as String?;
            if (path == null || path.isEmpty) continue;
            if (!await File(path).exists()) continue;
            final len = await File(path).length();
            consider(path, len);
            debugPrint(
              '[MbtilesDownload] 🧹 Resume keep candidate: '
              '${path.split('/').last} ($len bytes)',
            );
          } catch (_) {}
        }
      }

      final live = await _bestLiveDownloaderTemp(appDir.path, minBytes: 0);
      if (live != null) consider(live.path, live.length);

      // Never delete-all while a download is active: that unlinks the live
      // write target and leaves "ghost" progress with nothing on disk.
      if (keep == null) {
        if (isDownloading.value) {
          debugPrint(
            '[MbtilesDownload] 🧹 Skip orphan cleanup — no keep target '
            'while download is active',
          );
          return;
        }
      }

      // While downloading, only delete temps that are clearly leftover
      // (<10% of keep size) — never touch a near-peer partial.
      if (isDownloading.value && keep != null && keepLen > 1024 * 1024) {
        debugPrint(
          '[MbtilesDownload] 🧹 Active download — keeping largest partial '
          '(${keep!.split('/').last}, $keepLen bytes)',
        );
      }

      final freed = await _deleteDownloaderTempsExcept(keep);
      if (freed > 0) {
        debugPrint(
          '[MbtilesDownload] 🧹 Freed ${(freed / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB leftover temps '
          '(kept ${keep?.split('/').last ?? 'none'})',
        );
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Orphan temp cleanup failed: $e');
    }
  }

  /// Hard reset before starting a brand-new download task: cancel old tasks,
  /// wipe resume/task records for tiles.mbtiles, and delete ALL previous
  /// downloader temp files so they cannot fight the new download.
  ///
  /// When [preservePartials] is true (default), keep the largest temp / resume
  /// metadata / progress so a pause+relaunch continues instead of restarting
  /// a multi-GB download from 0%.
  Future<void> _wipePreviousMbtilesDownloadArtifacts({
    bool preservePartials = true,
  }) async {
    if (preservePartials) {
      await _softPrepareForResumeEnqueue();
      return;
    }

    debugPrint(
      '[MbtilesDownload] 🧹 Wiping previous download artifacts before restart',
    );
    try {
      final records = await FileDownloader().database.allRecords();
      final ids = <String>[];
      for (final record in records) {
        if (record.task.filename != LOCAL_MBTILES_FILENAME) continue;
        ids.add(record.task.taskId);
      }
      if (ids.isNotEmpty) {
        try {
          await FileDownloader().cancelTasksWithIds(ids);
        } catch (_) {}
        for (final id in ids) {
          try {
            await FileDownloader().database.deleteRecordWithId(id);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Could not clear task records: $e');
    }

    try {
      final appDir = await getApplicationSupportDirectory();
      final resumeDir =
          Directory('${appDir.path}/backgroundDownloaderResumeData');
      if (await resumeDir.exists()) {
        await for (final entity in resumeDir.list()) {
          if (entity is! File) continue;
          try {
            await entity.delete();
          } catch (_) {}
        }
      }

      // Incomplete destination file cannot be resumed without resume metadata.
      final partial = File('${appDir.path}/offline_tiles/$LOCAL_MBTILES_FILENAME');
      if (await partial.exists()) {
        final len = await partial.length();
        try {
          await partial.delete();
          debugPrint(
            '[MbtilesDownload] 🧹 Deleted incomplete $LOCAL_MBTILES_FILENAME '
            '($len bytes)',
          );
        } catch (e) {
          debugPrint(
            '[MbtilesDownload] ⚠️ Could not delete incomplete mbtiles: $e',
          );
        }
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Could not clear resume data: $e');
    }

    final freed = await _deleteDownloaderTempsExcept(null);
    _backgroundTask = null;
    _lastGoodProgress = 0.0;
    downloadProgress.value = 0.0;
    downloadedBytes.value = 0;
    await _clearMaxBytesCheckpoint();
    debugPrint(
      '[MbtilesDownload] 🧹 Restart wipe complete '
      '(freed ${(freed / (1024 * 1024)).toStringAsFixed(1)} MB)',
    );
  }

  /// Cancel stale task DB rows only — never delete temps, resume JSON, or
  /// progress checkpoints. Used before re-enqueue so Range resume can continue.
  Future<void> _softPrepareForResumeEnqueue() async {
    debugPrint(
      '[MbtilesDownload] ♻️ Soft prepare — preserving partials for resume',
    );
    await _loadMaxBytesCheckpoint();
    await _seedProgressFromPartialFileIfNeeded();

    try {
      final records = await FileDownloader().database.allRecords();
      final mbtiles = records
          .where((r) => r.task.filename == LOCAL_MBTILES_FILENAME)
          .toList();
      // Keep at most one preferred record for resume; drop the rest.
      final preferred = await _ensureSingleActiveMbtilesTask(mbtiles);
      if (preferred != null) {
        _backgroundTask = preferred.task as DownloadTask;
        if (preferred.progress >= 0 && preferred.progress <= 1) {
          _applyProgress(preferred.progress);
        }
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Soft prepare task scan: $e');
    }

    // Drop orphan temps that are not the live write target — keep the best one.
    await _cleanupOrphanDownloaderTemps();
    await _protectResumeDataFromTruncation();
  }

  /// Plant [ResumeData] for [task] from the largest on-disk partial temp, then
  /// call [FileDownloader.resume] so the native worker continues with Range.
  Future<bool> _resumeFromOnDiskPartial(DownloadTask task) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final live = await _bestLiveDownloaderTemp(
        appDir.path,
        minBytes: 64 * 1024,
      );

      String? tempPath = live?.path;
      var startByte = live?.length ?? 0;
      String? eTag;

      if (tempPath == null || startByte < 64 * 1024) {
        // Fall back to any stored resume entry for tiles.mbtiles.
        final existing = await _readStoredMbtilesResumeEntries(appDir.path);
        for (final entry in existing) {
          final f = File(entry.tempPath);
          if (!await f.exists()) continue;
          final len = await f.length();
          if (len < 64 * 1024) continue;
          tempPath = entry.tempPath;
          startByte = len;
          eTag = entry.eTag;
          break;
        }
      }

      if (tempPath == null || startByte < 64 * 1024) {
        return false;
      }

      await _writeResumeDataFile(
        task,
        tempPath: tempPath,
        startByte: startByte,
        // Preserve ETag when possible. Cloudflare weak ETags (W/…) cannot
        // resume in the plugin — then WorkManager FGS must keep the transfer
        // alive so we never need to resume.
        eTag: eTag,
      );
      await _protectResumeDataFromTruncation();
      final ok = await FileDownloader().resume(task);
      debugPrint(
        '[MbtilesDownload] ▶️ resume from partial '
        '($startByte bytes) => $ok',
      );
      return ok;
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ _resumeFromOnDiskPartial: $e');
      return false;
    }
  }

  static final RegExp _illegalPathCharacters = RegExp(r'[\\/:*?"<>|]');

  Future<void> _writeResumeDataFile(
    DownloadTask task, {
    required String tempPath,
    required int startByte,
    String? eTag,
  }) async {
    final appDir = await getApplicationSupportDirectory();
    final resumeDir =
        Directory('${appDir.path}/backgroundDownloaderResumeData');
    if (!await resumeDir.exists()) {
      await resumeDir.create(recursive: true);
    }
    final safeId = task.taskId.replaceAll(_illegalPathCharacters, '_');
    final payload = ResumeData(task, tempPath, startByte, eTag).toJson();
    final file = File('${resumeDir.path}/$safeId');
    await file.writeAsString(jsonEncode(payload));
    debugPrint(
      '[MbtilesDownload] 💾 Wrote resume data for ${task.taskId} '
      'at byte $startByte',
    );
  }

  Future<List<({String tempPath, int startByte, String? eTag})>>
      _readStoredMbtilesResumeEntries(String appDirPath) async {
    final out = <({String tempPath, int startByte, String? eTag})>[];
    final resumeDir =
        Directory('$appDirPath/backgroundDownloaderResumeData');
    if (!await resumeDir.exists()) return out;
    await for (final entity in resumeDir.list()) {
      if (entity is! File) continue;
      try {
        final raw = await entity.readAsString();
        if (raw.isEmpty) continue;
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final taskMap = map['task'];
        if (taskMap is Map &&
            taskMap['filename'] != LOCAL_MBTILES_FILENAME) {
          continue;
        }
        final path = map['data'] as String?;
        if (path == null || path.isEmpty) continue;
        final start = switch (map['requiredStartByte']) {
          final int v => v,
          final num v => v.toInt(),
          _ => 0,
        };
        out.add((
          tempPath: path,
          startByte: start,
          eTag: map['eTag'] as String?,
        ));
      } catch (_) {}
    }
    // Prefer largest partial first.
    out.sort((a, b) => b.startByte.compareTo(a.startByte));
    return out;
  }

  /// Enqueue [task], preferring Range resume from an existing partial.
  /// Always uses WorkManager (priority ≥ 1). Migrates old UIDT (priority 0)
  /// tasks so Xiaomi does not kill the download when the app is backgrounded.
  Future<bool> _enqueueOrResumeMbtilesTask(DownloadTask task) async {
    // Force WorkManager. If the source was UIDT, mint a new taskId so the
    // old JobScheduler job cannot be revived for the same id hash.
    final fromUidt = task.priority == 0;
    final workTask = _asWorkManagerTask(task, newTaskId: fromUidt);
    _backgroundTask = workTask;
    debugPrint(
      '[MbtilesDownload] 📋 Enqueue/resume WorkManager task '
      '${workTask.taskId} (priority=${workTask.priority}'
      '${fromUidt ? ', migrated from UIDT' : ''})',
    );

    FileDownloader().configureNotificationForTask(
      workTask,
      running: TaskNotification(
        'mbtiles_notif_running_title'.tr,
        'mbtiles_notif_running_body'.tr,
      ),
      complete: TaskNotification(
        'mbtiles_notif_complete_title'.tr,
        'mbtiles_notif_complete_body'.tr,
      ),
      error: TaskNotification(
        'mbtiles_notif_running_title'.tr,
        'mbtiles_status_resuming'.tr,
      ),
      paused: TaskNotification(
        'mbtiles_notif_paused_title'.tr,
        'mbtiles_notif_paused_body'.tr,
      ),
      progressBar: true,
    );

    try {
      final records = await FileDownloader().database.allRecords();
      final preferred = await _ensureSingleActiveMbtilesTask(
        records
            .where((r) => r.task.filename == LOCAL_MBTILES_FILENAME)
            .toList(),
      );
      if (preferred != null) {
        final existing = preferred.task as DownloadTask;
        // Already on WorkManager and running — leave it alone.
        if (existing.priority != 0 &&
            (preferred.status == TaskStatus.running ||
                preferred.status == TaskStatus.enqueued ||
                preferred.status == TaskStatus.waitingToRetry)) {
          _backgroundTask = existing;
          debugPrint(
            '[MbtilesDownload] ▶️ Keeping active WorkManager task '
            '${existing.taskId}',
          );
          return true;
        }

        if (existing.priority != 0) {
          final canResume = await FileDownloader().taskCanResume(existing);
          if (canResume) {
            await _protectResumeDataFromTruncation();
            final ok = await FileDownloader().resume(existing);
            if (ok) {
              _backgroundTask = existing;
              debugPrint(
                '[MbtilesDownload] ▶️ Resumed WorkManager task ${existing.taskId}',
              );
              return true;
            }
          }
        }

        // Cancel stuck UIDT (priority 0) / failed tasks — keep temps.
        try {
          await FileDownloader().cancelTaskWithId(existing.taskId);
        } catch (_) {}
        try {
          await FileDownloader().database.deleteRecordWithId(existing.taskId);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ existing-task resume check: $e');
    }

    if (await _resumeFromOnDiskPartial(workTask)) {
      return true;
    }

    final enqueued = await FileDownloader().enqueue(workTask);
    debugPrint(
      '[MbtilesDownload] 📋 Fresh WorkManager enqueue '
      '(priority=${workTask.priority}) => $enqueued',
    );
    return enqueued;
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

  /// Stall watchdog: if progress hasn't moved for [_stallTimeout] while
  /// `isDownloading` is true, try an auto-resume first, then surface a
  /// retryable error so the user is not stuck forever.
  ///
  /// 15 minutes: a ~4.5GB R2 download routinely goes quiet for several minutes
  /// (radio sleep, CDN pause, MIUI throttling) without being truly dead.
  static const Duration _stallTimeout = Duration(minutes: 15);
  DateTime? _lastProgressAt;
  double _lastWatchedProgress = -1;

  /// Backoff counter for silent auto-retries (no user-facing attempt count).
  int _autoResumeAttempts = 0;
  bool _silentRetryScheduled = false;
  DateTime? _lastResumeAttemptAt;
  static const Duration _resumeCooldown = Duration(seconds: 20);
  bool _dedupingTasks = false;
  /// Consecutive Android polls where a "running" task has zero bytes on disk.
  /// Ghost progress after an unlinked temp FD needs a hard restart.
  int _emptyDiskWhileRunningPolls = 0;
  /// Plugin-reported progress captured when the "empty disk" streak began —
  /// used to tell a genuinely stuck download from one whose progress keeps
  /// climbing (real, just invisible to our file scan) while we watch it.
  double _emptyDiskBaselineProgress = 0.0;
  DateTime? _lastEnqueueAt;

  static const String _downloadGroup = 'mbtiles';
  // Native auto-retries can truncate a large temp when resume metadata lags
  // (see DownloadTaskRunner.determineIfResume). We disable them and resume
  // ourselves after patching requiredStartByte to match the real file size.
  static const int _downloadRetries = 0;

  /// Expected mbtiles size (~4.5 GB for zoom 11) used when Content-Length is unknown.
  static const int _approxExpectedBytes = 4831838208; // 4.5 * 1024^3

  Future<String> _resolveLocalMbtilesPath() async {
    if (_localMbtilesPath != null && _localMbtilesPath!.isNotEmpty) {
      return _localMbtilesPath!;
    }
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}/offline_tiles/$LOCAL_MBTILES_FILENAME';
  }

  void _startProgressPolling() {
    // Fresh watchdog window for this attempt — avoid a stale timestamp from
    // a previous stalled/retried download immediately tripping the watchdog.
    _lastProgressAt = DateTime.now();
    _lastWatchedProgress = downloadProgress.value;
    _androidProgressPollTimer?.cancel();
    _androidProgressPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_syncProgressFromDatabaseAndFile()),
    );
    unawaited(_syncProgressFromDatabaseAndFile());
  }

  /// Back-compat alias used throughout this file.
  void _startAndroidProgressPolling() => _startProgressPolling();

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
      await _protectResumeDataFromTruncation();
      await _seedProgressFromPartialFileIfNeeded();
      // Drop leftover temps that are not the active resume target.
      unawaited(_cleanupOrphanDownloaderTemps());

      final records = await FileDownloader().database.allRecords();
      final mbtiles = records
          .where((r) => r.task.filename == LOCAL_MBTILES_FILENAME)
          .toList();
      if (mbtiles.isEmpty) {
        _checkForStall();
        return;
      }

      // Multiple concurrent tiles.mbtiles tasks fight each other and make
      // progress bounce (0 → 0.5 → 0.2). Keep exactly one survivor.
      final preferred = await _ensureSingleActiveMbtilesTask(mbtiles);
      if (preferred == null) {
        _checkForStall();
        return;
      }

      _backgroundTask = preferred.task as DownloadTask;
      final record = preferred;

      if (record.status == TaskStatus.running ||
          record.status == TaskStatus.enqueued ||
          record.status == TaskStatus.waitingToRetry ||
          record.status == TaskStatus.paused) {
        isDownloading.value = true;

        // Ghost download: plugin reports progress but the temp was deleted
        // (e.g. orphan cleanup unlinked an open FD). Restart cleanly.
        //
        // Use a low minBytes here (matching the 64KB ghost threshold below)
        // — the default 1MB visibility floor made a real, slow-but-healthy
        // temp under 1MB indistinguishable from a truly-orphaned one, which
        // caused false wipe+reset-to-0% on healthy downloads.
        final onDisk =
            await _activePartialBytesOnDisk(minLiveTempBytes: 64 * 1024);
        final enqueueAge = _lastEnqueueAt == null
            ? const Duration(days: 1)
            : DateTime.now().difference(_lastEnqueueAt!);
        // The plugin's own DB record progress is an independent signal from
        // the native downloader — if it has moved past where we started
        // watching, the download is alive even if our file scan missed it.
        final pluginReportsProgress =
            record.progress > 0.0 && record.progress > _emptyDiskBaselineProgress;
        if (onDisk < 64 * 1024 &&
            !pluginReportsProgress &&
            // Never wipe a download that already confirmed multi-MB progress
            // on disk earlier this session / via prefs — that was resetting
            // pause+relaunch to 0% when the live temp was briefly invisible.
            _maxBytesSeen < 1024 * 1024 &&
            enqueueAge > const Duration(seconds: 30) &&
            (record.status == TaskStatus.running ||
                record.status == TaskStatus.enqueued)) {
          if (_emptyDiskWhileRunningPolls == 0) {
            _emptyDiskBaselineProgress = record.progress;
          }
          _emptyDiskWhileRunningPolls++;
          if (_emptyDiskWhileRunningPolls >= 8) {
            // ~16s of empty disk while "running"
            debugPrint(
              '[MbtilesDownload] 🚨 Running task with empty disk '
              '(${_emptyDiskWhileRunningPolls} polls) — soft re-enqueue',
            );
            _emptyDiskWhileRunningPolls = 0;
            _emptyDiskBaselineProgress = 0.0;
            _stopAndroidProgressPolling();
            // Preserve any partials that appear; do not hard-wipe.
            await _wipePreviousMbtilesDownloadArtifacts(preservePartials: true);
            isDownloading.value = false;
            unawaited(downloadMbtiles(zoomLevel: await getSelectedZoomLevel()));
            return;
          }
        } else {
          _emptyDiskWhileRunningPolls = 0;
          _emptyDiskBaselineProgress = 0.0;
        }
      }

      if (record.progress >= 0.0 && record.progress <= 1.0) {
        _applyProgress(record.progress);
      } else if (record.progress == progressWaitingToRetry) {
        await _seedProgressFromPartialFileIfNeeded();
      }

      if (record.expectedFileSize > 0) {
        totalBytes.value = record.expectedFileSize;
        _updateGbStatusFromProgress();
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
        debugPrint(
          '[MbtilesDownload] 📦 Preferred task failed — silent auto-retry',
        );
        if (await _tryAutoResume(reason: 'db_poll_failed')) {
          return;
        }
        unawaited(_scheduleSilentRetry(reason: 'db_poll_failed'));
        return;
      }

      await _seedProgressFromPartialFileIfNeeded();
      _checkForStall();
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Progress sync failed: $e');
    }
  }

  /// Score records so we keep the best single download and cancel the rest.
  double _scoreMbtilesRecord(TaskRecord record) {
    final statusWeight = switch (record.status) {
      TaskStatus.running => 100.0,
      TaskStatus.enqueued => 80.0,
      TaskStatus.waitingToRetry => 70.0,
      TaskStatus.paused => 60.0,
      TaskStatus.failed => 40.0,
      _ => 0.0,
    };
    final p = (record.progress >= 0 && record.progress <= 1)
        ? record.progress
        : 0.0;
    return statusWeight + p;
  }

  TaskRecord? _preferredMbtilesRecord(Iterable<TaskRecord> records) {
    TaskRecord? best;
    var bestScore = -1.0;
    for (final record in records) {
      if (record.task.filename != LOCAL_MBTILES_FILENAME) continue;
      if (record.status == TaskStatus.complete ||
          record.status == TaskStatus.canceled ||
          record.status == TaskStatus.notFound) {
        continue;
      }
      final score = _scoreMbtilesRecord(record);
      if (score > bestScore) {
        bestScore = score;
        best = record;
      }
    }
    return best;
  }

  /// Cancel every tiles.mbtiles task except [keep], and delete stale failed
  /// records so the poll loop stops thrashing them.
  Future<TaskRecord?> _ensureSingleActiveMbtilesTask(
    List<TaskRecord> mbtiles,
  ) async {
    if (_dedupingTasks) {
      return _preferredMbtilesRecord(mbtiles);
    }
    final preferred = _preferredMbtilesRecord(mbtiles);
    if (preferred == null) return null;

    final keepId = preferred.task.taskId;
    final toCancel = <String>[];
    final toDelete = <String>[];

    for (final record in mbtiles) {
      final id = record.task.taskId;
      if (id == keepId) continue;

      final isLive = record.status == TaskStatus.running ||
          record.status == TaskStatus.enqueued ||
          record.status == TaskStatus.waitingToRetry ||
          record.status == TaskStatus.paused;
      if (isLive) {
        toCancel.add(id);
      }
      // Drop dead failed/canceled duplicates from the DB so we never
      // auto-resume the wrong leftover task.
      if (record.status == TaskStatus.failed ||
          record.status == TaskStatus.canceled ||
          record.status == TaskStatus.notFound ||
          isLive) {
        toDelete.add(id);
      }
    }

    if (toCancel.isEmpty && toDelete.isEmpty) return preferred;

    _dedupingTasks = true;
    try {
      if (toCancel.isNotEmpty) {
        debugPrint(
          '[MbtilesDownload] 🧹 Canceling ${toCancel.length} duplicate '
          'download(s); keeping $keepId',
        );
        await FileDownloader().cancelTasksWithIds(toCancel);
      }
      for (final id in toDelete) {
        try {
          await FileDownloader().database.deleteRecordWithId(id);
        } catch (_) {}
      }
      // Do NOT delete temp files here — orphan cleanup during an active
      // download races with resume and can discard a good partial.
    } finally {
      _dedupingTasks = false;
    }
    return preferred;
  }

  /// Called on every poll tick. If progress hasn't moved for [_stallTimeout]
  /// while still marked as downloading, try resume / silent retry — never
  /// show a numbered "retry N of M" message to the user.
  void _checkForStall() {
    if (!isDownloading.value || hasError.value || isCompleted.value) return;

    if (downloadProgress.value != _lastWatchedProgress) {
      _lastWatchedProgress = downloadProgress.value;
      _lastProgressAt = DateTime.now();
      return;
    }

    final lastProgressAt = _lastProgressAt;
    if (lastProgressAt == null) {
      _lastProgressAt = DateTime.now();
      return;
    }

    if (DateTime.now().difference(lastProgressAt) < _stallTimeout) return;

    debugPrint(
      '[MbtilesDownload] ⏱️ Stall detected — no progress for '
      '${_stallTimeout.inMinutes}min',
    );
    unawaited(_recoverFromStallOrFail());
  }

  Future<void> _recoverFromStallOrFail() async {
    if (!isDownloading.value || hasError.value || isCompleted.value) return;

    if (await _tryAutoResume(reason: 'stall')) {
      _lastProgressAt = DateTime.now();
      return;
    }

    debugPrint('[MbtilesDownload] ⏱️ Stall recovery — scheduling silent retry');
    _lastProgressAt = DateTime.now();
    unawaited(_scheduleSilentRetry(reason: 'stall'));
  }

  /// Resume a paused/failed task when the native downloader still has Range data.
  /// Always retries — no user-facing "retry 1 of N" limit or message.
  Future<bool> _tryAutoResume({required String reason}) async {
    final last = _lastResumeAttemptAt;
    if (last != null && DateTime.now().difference(last) < _resumeCooldown) {
      debugPrint(
        '[MbtilesDownload] ⏸️ Resume cooldown active — skip ($reason)',
      );
      return true; // already recently resumed; do not enqueue another task
    }

    DownloadTask? task = _backgroundTask;
    try {
      final records = await FileDownloader().database.allRecords();
      final preferred = await _ensureSingleActiveMbtilesTask(
        records
            .where((r) => r.task.filename == LOCAL_MBTILES_FILENAME)
            .toList(),
      );
      if (preferred != null) {
        final existing = preferred.task as DownloadTask;
        // Active WorkManager task — leave it.
        if (existing.priority != 0 &&
            (preferred.status == TaskStatus.running ||
                preferred.status == TaskStatus.enqueued ||
                preferred.status == TaskStatus.waitingToRetry)) {
          _backgroundTask = existing;
          isDownloading.value = true;
          if (preferred.progress >= 0 && preferred.progress <= 1) {
            _applyProgress(preferred.progress);
          }
          return true;
        }
        task = existing;
      }
    } catch (_) {}

    // Build a WorkManager task (priority 1) — never re-enqueue UIDT (0).
    final template = task ??
        DownloadTask(
          url: getDownloadUrl(await getSelectedZoomLevel()),
          filename: LOCAL_MBTILES_FILENAME,
          directory: 'offline_tiles',
          baseDirectory: BaseDirectory.applicationSupport,
          group: _downloadGroup,
          updates: Updates.statusAndProgress,
          requiresWiFi: false,
          retries: _downloadRetries,
          allowPause: true,
          priority: 1,
          displayName: 'SpaceTime map tiles',
        );
    final workTask = _asWorkManagerTask(
      template,
      newTaskId: template.priority == 0,
    );

    try {
      await _seedProgressFromPartialFileIfNeeded();
      _lastResumeAttemptAt = DateTime.now();
      _autoResumeAttempts++;
      isDownloading.value = true;
      hasError.value = false;
      _setStatusText('mbtiles_status_resuming');

      final ok = await _enqueueOrResumeMbtilesTask(workTask);
      if (ok) {
        _startAndroidProgressPolling();
        debugPrint(
          '[MbtilesDownload] ✅ Auto-resume (WorkManager) after $reason',
        );
        return true;
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Auto-resume error: $e');
    }
    return false;
  }

  /// Keep trying forever after a transient failure — resume only, never
  /// spawn a second competing download (that was resetting progress to 0).
  Future<void> _scheduleSilentRetry({required String reason}) async {
    if (_silentRetryScheduled || isCompleted.value) return;
    _silentRetryScheduled = true;
    isDownloading.value = true;
    hasError.value = false;
    _setStatusText('mbtiles_status_resuming');
    await _seedProgressFromPartialFileIfNeeded();

    final delaySeconds =
        math.min(60, 5 * (1 << math.min(_autoResumeAttempts, 3)));
    debugPrint(
      '[MbtilesDownload] ⏳ Silent retry in ${delaySeconds}s after $reason',
    );
    try {
      await Future<void>.delayed(Duration(seconds: delaySeconds));
      if (isCompleted.value) return;

      if (await _tryAutoResume(reason: '${reason}_silent')) return;

      // Last resort: one carefully-deduped re-enqueue (downloadMbtiles will
      // cancel duplicates and keep monotonic progress).
      debugPrint(
        '[MbtilesDownload] ♻️ Resume unavailable — single re-enqueue after $reason',
      );
      // Allow downloadMbtiles past the isDownloading guard.
      final wasDownloading = isDownloading.value;
      isDownloading.value = false;
      await downloadMbtiles(zoomLevel: await getSelectedZoomLevel());
      if (!isDownloading.value && wasDownloading) {
        isDownloading.value = true;
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Silent retry error: $e');
      isDownloading.value = true;
      hasError.value = false;
      _setStatusText('mbtiles_status_resuming');
      _startAndroidProgressPolling();
      _silentRetryScheduled = false;
      unawaited(_scheduleSilentRetry(reason: '${reason}_again'));
      return;
    } finally {
      _silentRetryScheduled = false;
    }
  }

  /// Pull updates stored while the app/engine was disconnected.
  Future<void> resumeDownloadUpdatesFromBackground() async {
    await FileDownloader().resumeFromBackground();
    await _syncProgressFromDatabaseAndFile();
    // If paused/failed after background, kick resume.
    if (!isCompleted.value &&
        (isDownloading.value ||
            _maxBytesSeen > 1024 * 1024 ||
            downloadProgress.value > 0)) {
      unawaited(_tryAutoResume(reason: 'app_resumed'));
    }
  }

  /// Whether an incomplete download should continue (for Get Started UI).
  Future<bool> hasResumablePartialOrActiveTask() async {
    if (isDownloading.value && !isCompleted.value) return true;
    if (await isMbtilesDownloaded()) return false;
    await _loadMaxBytesCheckpoint();
    if (_maxBytesSeen >= 1024 * 1024) return true;
    final onDisk = await _activePartialBytesOnDisk(minLiveTempBytes: 64 * 1024);
    if (onDisk >= 1024 * 1024) return true;
    try {
      final records = await FileDownloader().database.allRecords();
      return records.any(
        (r) =>
            r.task.filename == LOCAL_MBTILES_FILENAME &&
            (r.status == TaskStatus.running ||
                r.status == TaskStatus.enqueued ||
                r.status == TaskStatus.paused ||
                r.status == TaskStatus.waitingToRetry ||
                r.status == TaskStatus.failed),
      );
    } catch (_) {
      return false;
    }
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
    unawaited(_loadMaxBytesCheckpoint());
    // start() must complete before we inspect the task DB / resume.
    unawaited(() async {
      await _initializeBackgroundDownloader();
      await _checkForResumedDownloads();
    }());
  }

  /// Configure running/paused/complete notifications for the mbtiles group.
  /// Required for Android foreground service + UIDT while the app is backgrounded.
  void _configureMbtilesNotifications() {
    final running = TaskNotification(
      'mbtiles_notif_running_title'.tr,
      'mbtiles_notif_running_body'.tr,
    );
    final complete = TaskNotification(
      'mbtiles_notif_complete_title'.tr,
      'mbtiles_notif_complete_body'.tr,
    );
    final error = TaskNotification(
      'mbtiles_notif_running_title'.tr,
      'mbtiles_status_resuming'.tr,
    );
    final paused = TaskNotification(
      'mbtiles_notif_paused_title'.tr,
      'mbtiles_notif_paused_body'.tr,
    );

    // Default + group — UIDT/FGS looks up the running notification by task.
    FileDownloader().configureNotification(
      running: running,
      complete: complete,
      error: error,
      paused: paused,
      progressBar: true,
    );
    FileDownloader().configureNotificationForGroup(
      _downloadGroup,
      running: running,
      complete: complete,
      error: error,
      paused: paused,
      progressBar: true,
    );
  }

  /// Android 13+ needs POST_NOTIFICATIONS; without it the FGS/UIDT worker
  /// cannot stay alive in the background for multi-GB downloads.
  Future<bool> _ensureNotificationPermissionForBackground() async {
    if (!Platform.isAndroid) return true;
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return true;
      final result = await Permission.notification.request();
      debugPrint(
        '[MbtilesDownload] 🔔 Notification permission => $result',
      );
      return result.isGranted;
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Notification permission check: $e');
      return false;
    }
  }

  /// Check for any downloads that were in progress when app was closed
  Future<void> _checkForResumedDownloads() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadMaxBytesCheckpoint();
      await _seedProgressFromPartialFileIfNeeded();

      final tasks = await FileDownloader().database.allRecords();
      debugPrint(
        '[MbtilesDownload] 🔍 Checking for resumed downloads: ${tasks.length} tasks found',
      );

      final mbtiles = tasks
          .where((r) => r.task.filename == LOCAL_MBTILES_FILENAME)
          .toList();
      final preferred = await _ensureSingleActiveMbtilesTask(mbtiles);

      if (preferred != null) {
        debugPrint(
          '[MbtilesDownload] 🔄 Preferred task: ${preferred.task.taskId} '
          '(${preferred.status}) progress=${preferred.progress}',
        );

        _backgroundTask = preferred.task as DownloadTask;

        if (preferred.status == TaskStatus.running ||
            preferred.status == TaskStatus.enqueued) {
          final existing = preferred.task as DownloadTask;
          // Migrate legacy UIDT (priority 0) → WorkManager FGS (priority 1).
          if (existing.priority == 0) {
            debugPrint(
              '[MbtilesDownload] ♻️ Migrating UIDT task ${existing.taskId} '
              '→ WorkManager (Xiaomi kills UIDT in background)',
            );
            try {
              await FileDownloader().cancelTaskWithId(existing.taskId);
            } catch (_) {}
            try {
              await FileDownloader()
                  .database
                  .deleteRecordWithId(existing.taskId);
            } catch (_) {}
            isDownloading.value = false;
            unawaited(downloadMbtiles(zoomLevel: await getSelectedZoomLevel()));
            return;
          }
          isDownloading.value = true;
          _applyProgress(preferred.progress);
          await _seedProgressFromPartialFileIfNeeded();
          _setStatusText('mbtiles_status_resuming');
          _startAndroidProgressPolling();
          debugPrint(
            '[MbtilesDownload] ▶️ Resuming download from ${(downloadProgress.value * 100).toStringAsFixed(1)}%',
          );
          return;
        }

        if (preferred.status == TaskStatus.paused) {
          final existing = preferred.task as DownloadTask;
          if (existing.priority == 0) {
            debugPrint(
              '[MbtilesDownload] ♻️ Migrating paused UIDT → WorkManager',
            );
            try {
              await FileDownloader().cancelTaskWithId(existing.taskId);
            } catch (_) {}
            try {
              await FileDownloader()
                  .database
                  .deleteRecordWithId(existing.taskId);
            } catch (_) {}
            isDownloading.value = false;
            unawaited(downloadMbtiles(zoomLevel: await getSelectedZoomLevel()));
            return;
          }
          isDownloading.value = true;
          _applyProgress(preferred.progress);
          await _seedProgressFromPartialFileIfNeeded();
          _setStatusText('mbtiles_status_resuming');
          final canResume =
              await FileDownloader().taskCanResume(preferred.task);
          if (canResume) {
            await _protectResumeDataFromTruncation();
            final ok =
                await FileDownloader().resume(preferred.task as DownloadTask);
            debugPrint('[MbtilesDownload] ▶️ startup resume(paused) => $ok');
          } else {
            unawaited(_tryAutoResume(reason: 'startup_paused'));
          }
          _startAndroidProgressPolling();
          return;
        }

        if (preferred.status == TaskStatus.waitingToRetry) {
          isDownloading.value = true;
          _applyProgress(preferred.progress);
          await _seedProgressFromPartialFileIfNeeded();
          _setStatusText('mbtiles_status_resuming');
          _startAndroidProgressPolling();
          return;
        }

        if (preferred.status == TaskStatus.failed) {
          isDownloading.value = true;
          await _seedProgressFromPartialFileIfNeeded();
          unawaited(_tryAutoResume(reason: 'startup_failed'));
          return;
        }
      }

      // No active task record, but bytes on disk → continue automatically.
      final onDisk = await _activePartialBytesOnDisk(minLiveTempBytes: 64 * 1024);
      if (onDisk >= 1024 * 1024 || _maxBytesSeen >= 1024 * 1024) {
        debugPrint(
          '[MbtilesDownload] ♻️ Orphan partial on disk ($onDisk bytes, '
          'maxSeen=$_maxBytesSeen) — auto-continuing download',
        );
        isDownloading.value = false; // allow downloadMbtiles past guard
        unawaited(downloadMbtiles(zoomLevel: await getSelectedZoomLevel()));
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
            // WorkManager + SystemForegroundService (survives app pause).
            // Never use priority 0 / UIDT on Xiaomi — JobService is stopped
            // the moment the app hits AppLifecycleState.paused.
            (Config.runInForeground, Config.always),
            // Never use cache dir for ~4.5GB mbtiles — cache eviction kills resume.
            (Config.useCacheDir, Config.never),
          ],
        );
      }
      _downloaderConfigured = true;
    }

    // Notifications must exist before enqueue so Android can promote the
    // worker to a foreground service / UIDT job while the app is backgrounded.
    _configureMbtilesNotifications();

    // Listener MUST be registered before start() so undelivered background
    // updates (and killed-task reschedule) are not missed.
    FileDownloader().updates.listen((update) async {
      debugPrint('[MbtilesDownload] 🔔 Received update for task: ${update.task.taskId}');
      debugPrint('[MbtilesDownload] 🔔 Task filename: ${update.task.filename}');
      debugPrint('[MbtilesDownload] 🔔 Update type: ${update.runtimeType}');

      // Match by filename instead of taskId since taskId changes between app restarts
      if (update.task.filename == LOCAL_MBTILES_FILENAME) {
        // Ignore progress/status from duplicate tasks we are canceling — they
        // would otherwise yank the UI progress bar backwards.
        final activeId = _backgroundTask?.taskId;
        if (activeId != null &&
            update.task.taskId != activeId &&
            update is TaskProgressUpdate) {
          debugPrint(
            '[MbtilesDownload] 🔇 Ignoring progress from duplicate task '
            '${update.task.taskId} (active=$activeId)',
          );
          return;
        }

        // Adopt this task only when we have none yet, or it is the active one.
        // Never store a priority-0 UIDT task as "active" — that would re-enqueue
        // UIDT on the next resume().
        final incoming = update.task as DownloadTask;
        if (incoming.priority == 0) {
          debugPrint(
            '[MbtilesDownload] ⚠️ Ignoring UIDT update for ${incoming.taskId} '
            '(priority 0) — WorkManager migration owns this download',
          );
          // Cancel the UIDT worker if it somehow got scheduled.
          unawaited(FileDownloader().cancelTaskWithId(incoming.taskId));
          return;
        }

        if (_backgroundTask == null ||
            _backgroundTask!.taskId == incoming.taskId) {
          _backgroundTask = incoming;
        } else if (update is TaskStatusUpdate &&
            (update.status == TaskStatus.running ||
                update.status == TaskStatus.enqueued)) {
          // A newer live task appeared — switch to it and cancel the old one.
          final oldId = _backgroundTask!.taskId;
          _backgroundTask = incoming;
          unawaited(FileDownloader().cancelTaskWithId(oldId));
          debugPrint(
            '[MbtilesDownload] 🔄 Switched active task $oldId → ${incoming.taskId}',
          );
        }

        if (update is TaskProgressUpdate) {
          // Never feed sentinel values (-4 waitingToRetry, etc.) straight to the UI.
          if (update.progress == progressWaitingToRetry) {
            isDownloading.value = true;
            hasError.value = false;
            _applyProgress(update.progress);
            await _seedProgressFromPartialFileIfNeeded();
            _setStatusText('mbtiles_status_resuming');
            // Built-in retries are working — reset stall clock.
            _lastProgressAt = DateTime.now();
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
          _lastProgressAt = DateTime.now();

          debugPrint(
            '[MbtilesDownload] 📊 Progress update: ${(downloadProgress.value * 100).toStringAsFixed(1)}% (raw=${update.progress})',
          );

          if (update.expectedFileSize > 0) {
            totalBytes.value = update.expectedFileSize;
          }
          _updateGbStatusFromProgress();
        } else if (update is TaskStatusUpdate) {
          debugPrint('[MbtilesDownload] 📡 Status update: ${update.status}');

          if (update.status == TaskStatus.running ||
              update.status == TaskStatus.enqueued ||
              update.status == TaskStatus.waitingToRetry) {
            isDownloading.value = true;
            hasError.value = false;
            _lastProgressAt = DateTime.now();
            if (update.status == TaskStatus.waitingToRetry) {
              _setStatusText('mbtiles_status_resuming');
            } else {
              _setStatusText('mbtiles_status_downloading');
            }
          } else if (update.status == TaskStatus.complete) {
            // isDownloading intentionally stays true until finalize actually
            // confirms success below. Clearing it here left a window where
            // downloadMbtiles()'s "already in progress" reentrancy guard
            // would pass for a second call arriving in that window, and its
            // directory-wipe-on-fresh-start logic would delete the
            // just-completed file before finalize ever got to read it —
            // silently stranding the app with isDownloading=false,
            // isCompleted=false and no error, which is exactly the "stuck
            // on Get Started even though tiles finished" symptom.
            _applyProgress(1.0);
            _setStatusText('text_download_completed');
            _stopAndroidProgressPolling();
            _autoResumeAttempts = 0;

            final localPath = await _resolveLocalMbtilesPath();
            await _finalizeSuccessfulDownload(
              localPath,
              await getSelectedZoomLevel(),
            );
            // _finalizeSuccessfulDownload clears isDownloading itself on
            // both its success and validation-failure paths. This is only
            // a safety net for any path that returns without touching it.
            if (!isCompleted.value && !hasError.value) {
              isDownloading.value = false;
            }
          } else if (update.status == TaskStatus.failed) {
            // Ignore failures from duplicate tasks we canceled/replaced.
            if (_backgroundTask != null &&
                update.task.taskId != _backgroundTask!.taskId) {
              debugPrint(
                '[MbtilesDownload] 🔇 Ignoring failure from non-active task '
                '${update.task.taskId}',
              );
              return;
            }
            debugPrint(
              '[MbtilesDownload] ❌ Task failed — silent auto-retry (no retry-count UI)',
            );
            await _protectResumeDataFromTruncation();
            await _seedProgressFromPartialFileIfNeeded();
            if (await _tryAutoResume(reason: 'task_failed')) {
              return;
            }
            unawaited(_scheduleSilentRetry(reason: 'task_failed'));
          } else if (update.status == TaskStatus.paused) {
            _setStatusText('mbtiles_status_download_paused');
            // OS/background pause — keep downloading flag so UI stays in progress
            // and cold start / resume will continue automatically.
            isDownloading.value = true;
          }
        }
      }
    });

    // Purge legacy UIDT records BEFORE start/reschedule so the plugin cannot
    // re-enqueue priority-0 JobScheduler jobs that Xiaomi kills on pause.
    await _purgeUidtMbtilesTaskRecords();

    // trackTasks + resumeFromBackground — required for multi-GB downloads that
    // survive app pause / process death. We intentionally disable the plugin's
    // blind rescheduleKilledTasks (it would re-enqueue purged UIDT tasks);
    // _checkForResumedDownloads owns WorkManager re-enqueue instead.
    await FileDownloader().start(
      doTrackTasks: true,
      markDownloadedComplete: true,
      doRescheduleKilledTasks: false,
      autoCleanDatabase: false,
    );
    debugPrint('[MbtilesDownload] ✅ FileDownloader.start() complete');
  }

  Future<void> _finalizeSuccessfulDownload(
    String localFilePath,
    int selectedZoom,
  ) async {
    if (isCompleted.value) return;
    try {
      final localFile = File(localFilePath);
      if (!await localFile.exists()) {
        // Previously left isDownloading/isCompleted/hasError all false here
        // — a silent dead end with no error shown and no way to retry
        // (retryDownload() is gated on hasError). Surface it instead.
        debugPrint('[MbtilesDownload] ⚠️ Finalize skipped — file missing');
        hasError.value = true;
        errorMessage.value = 'mbtiles_error_file_missing_after_complete'.tr;
        _setStatusText('mbtiles_error_file_missing_after_complete');
        isDownloading.value = false;
        isCompleted.value = false;
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
      await _clearMaxBytesCheckpoint();
      unawaited(_cleanupOrphanDownloaderTemps());
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

    // Defense-in-depth against wiping a real, already-finalized download:
    // the directory-cleanup step below deletes everything in offline_tiles
    // before starting a "fresh" download. If this method is ever re-entered
    // right after a genuine completion (the isDownloading guard above is
    // the primary protection, but should not be the only one), this check
    // stops it from destroying a file that's already valid.
    if (zoomLevel == null || zoomLevel == await getSelectedZoomLevel()) {
      if (await isMbtilesDownloaded()) {
        debugPrint(
          '[MbtilesDownload] ✅ Already downloaded at the requested zoom — skipping re-download',
        );
        return _localMbtilesPath;
      }
    }

    // Prefer resuming an existing incomplete / failed-but-resumable task over
    // wiping offline_tiles and starting from 0% again (common after retry /
    // screen revisit / Xiaomi killing the worker mid-download).
    try {
      final existing = await FileDownloader().database.allRecords();
      final mbtiles = existing
          .where((r) => r.task.filename == LOCAL_MBTILES_FILENAME)
          .toList();
      // Critical: never leave multiple concurrent tile downloads alive.
      final record = await _ensureSingleActiveMbtilesTask(mbtiles);
      if (record != null) {
        final task = record.task as DownloadTask;
        final active = record.status == TaskStatus.running ||
            record.status == TaskStatus.enqueued ||
            record.status == TaskStatus.waitingToRetry ||
            record.status == TaskStatus.paused;
        final failedButMaybeResumable = record.status == TaskStatus.failed;

        if (active || failedButMaybeResumable) {
          // Never keep a priority-0 UIDT task — Xiaomi kills it on pause.
          if (task.priority == 0) {
            debugPrint(
              '[MbtilesDownload] ♻️ Dropping UIDT task ${task.taskId} '
              '— will re-enqueue via WorkManager',
            );
            try {
              await FileDownloader().cancelTaskWithId(task.taskId);
            } catch (_) {}
            try {
              await FileDownloader().database.deleteRecordWithId(task.taskId);
            } catch (_) {}
            // Fall through to soft prepare + WorkManager enqueue.
          } else {
            _backgroundTask = task;
            isDownloading.value = true;
            hasError.value = false;
            isCompleted.value = false;
            _applyProgress(record.progress);
            await _seedProgressFromPartialFileIfNeeded();
            debugPrint(
              '[MbtilesDownload] ▶️ Reusing existing WorkManager task '
              '${task.taskId} (${record.status}) at '
              '${(downloadProgress.value * 100).toStringAsFixed(1)}%',
            );

            if (record.status == TaskStatus.paused || failedButMaybeResumable) {
              final canResume = await FileDownloader().taskCanResume(task);
              if (canResume) {
                await _protectResumeDataFromTruncation();
                _lastResumeAttemptAt = DateTime.now();
                final resumed = await FileDownloader().resume(task);
                debugPrint('[MbtilesDownload] ▶️ resume() => $resumed');
                if (resumed) {
                  _setStatusText('mbtiles_status_resuming');
                  _startAndroidProgressPolling();
                  return null;
                }
              }
              // Resume metadata missing — plant from on-disk partial before wipe.
              if (await _resumeFromOnDiskPartial(task)) {
                _setStatusText('mbtiles_status_resuming');
                _startAndroidProgressPolling();
                return null;
              }
              if (failedButMaybeResumable) {
                debugPrint(
                  '[MbtilesDownload] ⚠️ Failed task not resumable via plugin — '
                  'soft re-enqueue preserving partials',
                );
                // Fall through to soft prepare + enqueue below.
              } else {
                _setStatusText('mbtiles_status_resuming');
                _startAndroidProgressPolling();
                return null;
              }
            } else {
              // Already running on WorkManager — do NOT touch temps.
              _setStatusText('mbtiles_status_downloading');
              _startAndroidProgressPolling();
              return null;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Could not check existing tasks: $e');
    }

    // Soft prepare — keep temps/resume so Range continues from same byte.
    await _wipePreviousMbtilesDownloadArtifacts(preservePartials: true);

    try { 
       final appDir = await getApplicationSupportDirectory();
      final tilesDir = Directory('${appDir.path}/offline_tiles');
              debugPrint('[MbtilesDownload] 📁 fetching tiles directory ${tilesDir.path}');

    }catch(e) {
            debugPrint('[MbtilesDownload] 🗺️ File Creation issue ${e}');

    }

    // Set right before the Android enqueue-success return below so `finally`
    // knows NOT to stop the just-started polling timer. Without this, the
    // finally block ran immediately after that return and canceled the
    // Android DB-polling safety net on every single fresh download attempt.
    var didEnqueueOnAndroid = false;

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
      // Keep last good % when retrying with a partial file already on disk.
      // Never force UI back to 0% — that caused the bouncing progress bar.
      await _seedProgressFromPartialFileIfNeeded();
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

      // Create tiles directory if it doesn't exist. If a partial tiles.mbtiles
      // is already present, KEEP it so Range/resume can continue — wiping here
      // was resetting multi-GB downloads back to 0% on every retry.
      if (!await tilesDir.exists()) {
        await tilesDir.create(recursive: true);
        debugPrint('[MbtilesDownload] 📁 Created tiles directory: ${tilesDir.path}');
      } else {
        final partialFile = File('${tilesDir.path}/$LOCAL_MBTILES_FILENAME');
        final partialBytes =
            await partialFile.exists() ? await partialFile.length() : 0;
        final keepPartial = partialBytes > 1024 * 1024; // >1MB

        if (keepPartial) {
          debugPrint(
            '[MbtilesDownload] ♻️ Keeping partial $LOCAL_MBTILES_FILENAME '
            '($partialBytes bytes) — will resume instead of wiping',
          );
          await _seedProgressFromPartialFileIfNeeded();
        } else {
          debugPrint(
            '[MbtilesDownload] 📁 Tiles directory exists, cleaning up: ${tilesDir.path}',
          );

          try {
            debugPrint('[MbtilesDownload] 🗑️ Attempting to delete directory recursively...');
            await tilesDir.delete(recursive: true);
            debugPrint('[MbtilesDownload] ✅ Successfully deleted tiles directory');
            await tilesDir.create(recursive: true);
            debugPrint('[MbtilesDownload] 📁 Recreated tiles directory');
          } catch (e) {
            debugPrint('[MbtilesDownload] ⚠️ Error deleting directory: $e');

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
            }
          }
        }
      }

      // Define local file path (always use same filename for consistency)
      final localFilePath = '${tilesDir.path}/$LOCAL_MBTILES_FILENAME';
      final localFile = File(localFilePath);
      final existingPartialBytes =
          await localFile.exists() ? await localFile.length() : 0;

      debugPrint('[MbtilesDownload] 📁 Local file path: $localFilePath');

      // Only delete an existing complete-looking leftover when we are not
      // trying to resume a partial download.
      if (existingPartialBytes > 0 && existingPartialBytes < 1024 * 1024) {
        try {
          await localFile.delete();
          debugPrint('[MbtilesDownload] 🗑️ Deleted tiny leftover mbtiles file');
        } catch (e) {
          debugPrint('[MbtilesDownload] ⚠️ Error deleting tiny leftover: $e');
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

      // FGS / UIDT require a granted notification permission + configured
      // running notification, otherwise Android kills the download in background.
      final notifOk = await _ensureNotificationPermissionForBackground();
      if (!notifOk) {
        debugPrint(
          '[MbtilesDownload] ⚠️ Notification permission denied — '
          'background download will be unreliable on Android',
        );
      }
      _configureMbtilesNotifications();

      _backgroundTask = DownloadTask(
        url: downloadUrl,
        filename: LOCAL_MBTILES_FILENAME,
        directory: 'offline_tiles',
        baseDirectory: BaseDirectory.applicationSupport,
        group: _downloadGroup,
        updates: Updates.statusAndProgress,
        requiresWiFi: false,
        retries: _downloadRetries,
        allowPause: true,
        // priority 1 (not 0): WorkManager + FGS. priority 0 = UIDT JobService,
        // which Xiaomi/HyperOS cancels when the app goes to background.
        priority: 1,
        displayName: 'SpaceTime map tiles',
        metaData: 'mbtiles_download_zoom_$selectedZoom',
        headers: headers.isNotEmpty ? headers : null,
      );

      // Bind notification config to this task so FGS always has a running notif.
      FileDownloader().configureNotificationForTask(
        _backgroundTask!,
        running: TaskNotification(
          'mbtiles_notif_running_title'.tr,
          'mbtiles_notif_running_body'.tr,
        ),
        complete: TaskNotification(
          'mbtiles_notif_complete_title'.tr,
          'mbtiles_notif_complete_body'.tr,
        ),
        error: TaskNotification(
          'mbtiles_notif_running_title'.tr,
          'mbtiles_status_resuming'.tr,
        ),
        paused: TaskNotification(
          'mbtiles_notif_paused_title'.tr,
          'mbtiles_notif_paused_body'.tr,
        ),
        progressBar: true,
      );

      debugPrint('[MbtilesDownload] 🎯 Created download task: ${_backgroundTask!.taskId}');
      debugPrint('[MbtilesDownload] 🎯 Task URL: ${_backgroundTask!.url}');
      debugPrint('[MbtilesDownload] 🎯 Task filename: ${_backgroundTask!.filename}');
      debugPrint('[MbtilesDownload] 🎯 Task directory: ${_backgroundTask!.directory}');

      debugPrint('[MbtilesDownload] 🚀 Starting download (enqueue + resume)...');

      // Both platforms use enqueue so the native worker continues in the
      // background and survives Flutter engine restarts. Prefer Range resume
      // from the largest on-disk partial when available.
      final started = await _enqueueOrResumeMbtilesTask(_backgroundTask!);
      if (!started) {
        throw Exception('Failed to enqueue/resume mbtiles download task');
      }
      debugPrint(
        '[MbtilesDownload] 📋 Background task active '
        '(${Platform.isIOS ? 'iOS URLSession' : 'Android FGS/UIDT'})',
      );
      _lastEnqueueAt = DateTime.now();
      _emptyDiskWhileRunningPolls = 0;
      _emptyDiskBaselineProgress = 0.0;
      _startProgressPolling();
      didEnqueueOnAndroid = true; // keep polling in finally for both platforms
      return null;
    } catch (e) {
      debugPrint('[MbtilesDownload] ❌ Error downloading mbtiles: $e');
      hasError.value = true;
      errorMessage.value = e.toString();
      _setStatusText('mbtiles_error_download_with_message', [e.toString()]);
      return null;
    } finally {
      if (!didEnqueueOnAndroid) {
        _stopAndroidProgressPolling();
      }
      // Do not clear isDownloading after enqueue — background worker owns it.
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

