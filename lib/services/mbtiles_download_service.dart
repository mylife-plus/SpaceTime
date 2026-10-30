import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
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
class MbtilesDownloadService extends GetxController
    with WidgetsBindingObserver {
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

  /// Bypass [isDownloading] guard for a single re-enqueue without clearing the
  /// flag (clearing it let status checks reset % to 0 while GB stayed).
  bool _allowReenqueueWhileDownloading = false;

  /// Stable expected size for % and GB labels. Always anchors on the known
  /// ~4.5 GB package size — Content-Length blips must not show as 5.0 GB.
  int _expectedTotalBytes() {
    final reported = totalBytes.value;
    // Accept a server size only when it is close to the real package
    // (±15%). Otherwise keep the 4.5 GB constant so the UI stays honest.
    if (reported >= (_approxExpectedBytes * 0.85).round() &&
        reported <= (_approxExpectedBytes * 1.15).round()) {
      return reported;
    }
    return _approxExpectedBytes;
  }

  /// Accept plugin Content-Length only when it looks like the real multi-GB file.
  void _maybeAcceptExpectedFileSize(int size) {
    if (size <= 0) return;
    if (size < (_approxExpectedBytes * 0.85).round() ||
        size > (_approxExpectedBytes * 1.15).round()) {
      debugPrint(
        '[MbtilesDownload] ⚠️ Ignoring expectedFileSize=$size '
        '(using ${_approxExpectedBytes} ≈ 4.5 GB)',
      );
      if (totalBytes.value <= 0 ||
          totalBytes.value < (_approxExpectedBytes * 0.85).round() ||
          totalBytes.value > (_approxExpectedBytes * 1.15).round()) {
        totalBytes.value = _approxExpectedBytes;
      }
      return;
    }
    totalBytes.value = size;
  }

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

  /// Lift % to match on-disk / downloaded bytes so the bar cannot sit at 0.1%
  /// while the GB label already shows 0.02 GB.
  void _liftProgressFromBytes() {
    final bytes = math.max(downloadedBytes.value, _maxBytesSeen);
    if (bytes < 64 * 1024) return;
    final approx =
        (bytes / _expectedTotalBytes()).clamp(0.0, 0.99);
    if (approx > _lastGoodProgress) {
      _lastGoodProgress = approx;
      downloadProgress.value = approx;
    } else if (downloadProgress.value < _lastGoodProgress) {
      downloadProgress.value = _lastGoodProgress;
    }
  }

  /// iOS only: URLSession's partial file is not visible to us, so there are no
  /// on-disk bytes to read — derive downloaded bytes from the plugin's
  /// progress fraction so the GB label matches the % (never 0.00 GB while the
  /// bar moves). Monotonic. Android keeps its real on-disk byte counting.
  void _deriveBytesFromProgressNonAndroid() {
    if (Platform.isAndroid) return;
    final p = _lastGoodProgress;
    if (p <= 0) return;
    final expected = _expectedTotalBytes();
    final derived = (p.clamp(0.0, 1.0) * expected).round();
    if (derived > downloadedBytes.value) {
      downloadedBytes.value = derived;
    }
    if (totalBytes.value < expected) totalBytes.value = expected;
  }

  void _applyProgress(double raw) {
    // Ghost-floor escape: after a fresh enqueue the plugin reports raw≈0
    // while `_lastGoodProgress` still holds the old % (e.g. 16.1%). When
    // there is no live partial, follow raw so Get Started shows real %.
    if (raw >= 0.0 &&
        raw <= 1.0 &&
        _lastGoodProgress >= 0.05 &&
        raw + 0.03 < _lastGoodProgress &&
        _lastLiveTempBytes < 1024 * 1024 &&
        _maxBytesSeen < 1024 * 1024) {
      debugPrint(
        '[MbtilesDownload] 📉 Dropping ghost floor '
        '${(_lastGoodProgress * 100).toStringAsFixed(1)}% → '
        '${(raw * 100).toStringAsFixed(1)}% (real progress)',
      );
      _lastGoodProgress = raw;
      downloadProgress.value = raw;
      if (!Platform.isAndroid) {
        downloadedBytes.value =
            (raw * _expectedTotalBytes()).round().clamp(0, _expectedTotalBytes());
      }
    }

    final before = _lastGoodProgress;
    downloadProgress.value = _displayProgressFrom(raw);
    _deriveBytesFromProgressNonAndroid();
    _liftProgressFromBytes();
    // Once real progress resumes after a network blip, drop the reconnecting label.
    if (downloadProgress.value > before &&
        (_statusL10nKey == 'mbtiles_status_reconnecting' ||
            _statusL10nKey == 'mbtiles_status_resuming')) {
      _setStatusText('mbtiles_status_downloading');
      _ensureNormalProgressPolling();
      _cancelStaleRunningWatchdog();
    }
  }

  /// Highest temp-file byte count observed this session (and persisted).
  /// Used to stop the native downloader from truncating a larger partial
  /// when stale resume metadata has a lower [requiredStartByte].
  int _maxBytesSeen = 0;
  static const String _prefsKeyMaxPartialBytes = 'mbtiles_max_partial_bytes';

  void _updateGbStatusFromBytes(int bytes) {
    final expected = _expectedTotalBytes();
    // Never let the GB label bounce downward mid-download.
    downloadedBytes.value = math.max(downloadedBytes.value, bytes);
    _deriveBytesFromProgressNonAndroid();
    if (totalBytes.value < expected) totalBytes.value = expected;
    _liftProgressFromBytes();
    final receivedGB =
        (downloadedBytes.value / (1024 * 1024 * 1024)).toStringAsFixed(2);
    // One decimal so the package shows as 4.5 GB (not a hacked 5.0).
    final totalGB = (expected / (1024 * 1024 * 1024)).toStringAsFixed(1);
    _setStatusText(
      'mbtiles_status_downloading_gb_pair',
      [receivedGB, totalGB],
    );
  }

  void _updateGbStatusFromProgress() {
    // Prefer real bytes — deriving GB from a wrong high % inflated the label.
    _updateGbStatusFromBytes(downloadedBytes.value);
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

  /// Zero every in-memory and persisted progress signal so the UI never shows
  /// a percentage that has nothing behind it.
  Future<void> _resetStaleProgress(String reason) async {
    debugPrint('[MbtilesDownload] 🧼 Resetting stale progress ($reason)');
    await _clearMaxBytesCheckpoint();
    _lastGoodProgress = 0.0;
    _lastLiveTempBytes = 0;
    downloadProgress.value = 0.0;
    downloadedBytes.value = 0;
    _setStatusText('mbtiles_status_ready_to_download');
  }

  /// After airplane→online / force re-enqueue, iOS often starts a new task at
  /// raw≈0 with no URLSession partial left. Do **not** keep a ghost high %
  /// (`_lastGoodProgress`); show the real download position instead.
  ///
  /// If a real partial still exists on disk (Android Range), seed from that.
  Future<void> _alignUiToRealDownloadProgress(String reason) async {
    final onDisk =
        await _activePartialBytesOnDisk(minLiveTempBytes: 64 * 1024);
    if (onDisk >= 1024 * 1024) {
      debugPrint(
        '[MbtilesDownload] 📊 Align UI to on-disk partial '
        '($onDisk bytes) after $reason',
      );
      await _seedProgressFromPartialFileIfNeeded();
      _updateGbStatusFromBytes(
        math.max(_lastLiveTempBytes, onDisk),
      );
      return;
    }

    debugPrint(
      '[MbtilesDownload] 📉 Align UI to real progress ($reason) — '
      'no partial; was ${(downloadProgress.value * 100).toStringAsFixed(1)}%',
    );
    await _clearMaxBytesCheckpoint();
    _lastGoodProgress = 0.0;
    _lastLiveTempBytes = 0;
    _lastWatchedProgress = 0.0;
    _lastWatchedBytes = 0;
    downloadProgress.value = 0.0;
    downloadedBytes.value = 0;
    final expected = _expectedTotalBytes();
    if (totalBytes.value < expected) totalBytes.value = expected;
    final totalGB = (expected / (1024 * 1024 * 1024)).toStringAsFixed(1);
    _setStatusText('mbtiles_status_downloading_gb_pair', ['0.00', totalGB]);
  }

  /// Delete leftover failed/orphan downloader temps + incomplete destination
  /// files before a new enqueue. When [keepActivePartial] is true, keep the
  /// largest live temp / stable snapshot for Range resume.
  Future<void> _clearOrphanFailedDownloadFiles({
    bool keepActivePartial = false,
  }) async {
    if (keepActivePartial) {
      await _cleanupOrphanDownloaderTemps();
      // Tiny incomplete destination is never resumable — drop it.
      try {
        final appDir = await getApplicationSupportDirectory();
        final dest =
            File('${appDir.path}/offline_tiles/$LOCAL_MBTILES_FILENAME');
        if (await dest.exists()) {
          final len = await dest.length();
          if (len > 0 && len < 1024 * 1024) {
            await dest.delete();
            debugPrint(
              '[MbtilesDownload] 🧹 Deleted tiny incomplete '
              '$LOCAL_MBTILES_FILENAME ($len bytes)',
            );
          }
        }
      } catch (_) {}
      return;
    }
    await _wipePreviousMbtilesDownloadArtifacts(preservePartials: false);
  }

  /// True when a relaunch can genuinely continue: a live task record, or real
  /// bytes on disk (Android temp / stable snapshot). iOS keeps its partial
  /// inside URLSession, so there the task record is the only evidence.
  Future<bool> _hasRealResumableState() async {
    try {
      final records = await FileDownloader().database.allRecords();
      for (final r in records) {
        if (r.task.filename != LOCAL_MBTILES_FILENAME) continue;
        if (r.status == TaskStatus.running ||
            r.status == TaskStatus.enqueued ||
            r.status == TaskStatus.waitingToRetry ||
            r.status == TaskStatus.paused) {
          return true;
        }
        if (r.status == TaskStatus.failed &&
            await FileDownloader().taskCanResume(r.task)) {
          return true;
        }
      }
    } catch (_) {}
    if (Platform.isAndroid) {
      final onDisk =
          await _activePartialBytesOnDisk(minLiveTempBytes: 64 * 1024);
      return onDisk >= 1024 * 1024;
    }
    return false;
  }

  /// The persisted max-bytes checkpoint outlives the download it described
  /// (cancel, OS kill, temp purged). Drop it when nothing can resume, so the
  /// screen shows 0% instead of a ghost percentage over a from-scratch start.
  Future<void> _reconcileStaleCheckpoint() async {
    if (isDownloading.value && !isCompleted.value) return;
    await _loadMaxBytesCheckpoint();
    final hasGhost = _maxBytesSeen > 0 ||
        _lastGoodProgress > 0 ||
        downloadedBytes.value > 0;
    if (!hasGhost) return;
    if (await _hasRealResumableState()) return;
    await _resetStaleProgress('checkpoint without resumable state');
  }

  /// Native Android code truncates the temp file DOWN to [requiredStartByte]
  /// when the file is larger. Align resume JSON to the **largest** live temp
  /// and never point requiredStartByte at a smaller file (that wiped 50MB+).
  Future<void> _protectResumeDataFromTruncation() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final largestTemp =
          await _bestLiveDownloaderTemp(appDir.path, minBytes: 0);
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

          // Only retarget to a LARGER temp — never shrink the resume target.
          if (largestTemp != null && largestTemp.path != path) {
            final currentFile = File(path);
            final currentLen =
                await currentFile.exists() ? await currentFile.length() : 0;
            if (largestTemp.length > currentLen) {
              debugPrint(
                '[MbtilesDownload] 🛡️ Retargeting resume temp '
                '${path.split('/').last} ($currentLen) → '
                '${largestTemp.path.split('/').last} (${largestTemp.length})',
              );
              path = largestTemp.path;
              map['data'] = path;
            }
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
          // Never lower requiredStartByte — native truncates the file to it.
          final nextStart = math.max(currentStart, fileLen);
          if (currentStart == nextStart && map['data'] == path) continue;

          map['requiredStartByte'] = nextStart;
          map['data'] = path;
          await entity.writeAsString(jsonEncode(map));
          debugPrint(
            '[MbtilesDownload] 🛡️ Patched resume startByte '
            '$currentStart → $nextStart',
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
    final stablePartial =
        File('${appDir.path}/offline_tiles/$_stablePartialName');
    if (await stablePartial.exists()) {
      best = math.max(best, await stablePartial.length());
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
      _lastLiveTempBytes = len;
      await _rememberMaxBytes(len);
      if (len <= 0) return;

      final approx =
          (len / _expectedTotalBytes()).clamp(0.0, 0.99);

      if (approx > _lastGoodProgress) {
        _lastGoodProgress = approx;
        downloadProgress.value = approx;
        _updateGbStatusFromBytes(len);
        if (_statusL10nKey == 'mbtiles_status_reconnecting' ||
            _statusL10nKey == 'mbtiles_status_resuming') {
          _setStatusText('mbtiles_status_downloading');
          _ensureNormalProgressPolling();
        }
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
      // iOS URLSession temps are invisible here — skip quietly (was spamming
      // every poll tick and looked like a stuck loop in device logs).
      if (keep == null) {
        if (isDownloading.value) return;
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

      final tilesDir = Directory('${appDir.path}/offline_tiles');
      // Incomplete destination + stable snapshot cannot be kept when restarting.
      for (final name in [LOCAL_MBTILES_FILENAME, _stablePartialName]) {
        final partial = File('${tilesDir.path}/$name');
        if (!await partial.exists()) continue;
        final len = await partial.length();
        try {
          await partial.delete();
          debugPrint(
            '[MbtilesDownload] 🧹 Deleted incomplete $name ($len bytes)',
          );
        } catch (e) {
          debugPrint(
            '[MbtilesDownload] ⚠️ Could not delete $name: $e',
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

  /// Copy the largest downloader temp to a stable path the plugin cannot
  /// delete on task failure (failed Range resume was wiping the partial).
  Future<({String path, int length})?> _snapshotLargestPartial() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final live = await _bestLiveDownloaderTemp(appDir.path, minBytes: 64 * 1024);
      final tilesDir = Directory('${appDir.path}/offline_tiles');
      if (!await tilesDir.exists()) {
        await tilesDir.create(recursive: true);
      }
      final stable = File('${tilesDir.path}/$_stablePartialName');
      var bestPath = live?.path;
      var bestLen = live?.length ?? 0;

      if (await stable.exists()) {
        final stableLen = await stable.length();
        if (stableLen > bestLen) {
          bestPath = stable.path;
          bestLen = stableLen;
        }
      }

      if (bestPath == null || bestLen < 64 * 1024) return null;

      if (bestPath != stable.path) {
        try {
          await File(bestPath).copy(stable.path);
          bestPath = stable.path;
          bestLen = await stable.length();
          debugPrint(
            '[MbtilesDownload] 💾 Snapshotted partial → $_stablePartialName '
            '($bestLen bytes)',
          );
        } catch (e) {
          debugPrint('[MbtilesDownload] ⚠️ Snapshot copy failed: $e');
        }
      }
      await _rememberMaxBytes(bestLen);
      return (path: bestPath!, length: bestLen);
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ Snapshot failed: $e');
      return null;
    }
  }

  /// Plant [ResumeData] for [task] from the largest on-disk partial temp, then
  /// call [FileDownloader.resume] so the native worker continues with Range.
  Future<bool> _resumeFromOnDiskPartial(DownloadTask task) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      // Prefer our stable snapshot (survives plugin deleting its temp on fail).
      final snap = await _snapshotLargestPartial();
      String? tempPath = snap?.path;
      var startByte = snap?.length ?? 0;
      String? eTag;

      // Also consider resume-dir temps; keep the largest overall.
      final existing = await _readStoredMbtilesResumeEntries(appDir.path);
      for (final entry in existing) {
        final f = File(entry.tempPath);
        if (!await f.exists()) continue;
        final len = await f.length();
        if (len < 64 * 1024) continue;
        if (len > startByte) {
          tempPath = entry.tempPath;
          startByte = len;
          eTag = entry.eTag;
        }
      }

      if (tempPath == null || startByte < 64 * 1024) {
        return false;
      }

      // Native check: eTagHeader != storedETag → fail. Null stored ETag ALWAYS
      // fails because R2 returns an ETag on every Range response. Plant the
      // live server ETag (HEAD) so they match.
      final serverEtag = await _fetchServerEtag(task.url);
      await _writeResumeDataFile(
        task,
        tempPath: tempPath,
        startByte: startByte,
        eTag: serverEtag,
      );
      await _protectResumeDataFromTruncation();
      final ok = await FileDownloader().resume(task);
      debugPrint(
        '[MbtilesDownload] ▶️ resume from partial '
        '($startByte bytes, etag=$serverEtag) => $ok',
      );
      return ok;
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ _resumeFromOnDiskPartial: $e');
      return false;
    }
  }

  static final RegExp _illegalPathCharacters = RegExp(r'[\\/:*?"<>|]');

  /// Live ETag from the object store. Required for background_downloader resume:
  /// Android fails with "ETag is not identical, or is weak" when stored eTag
  /// is null/mismatched (R2 always sends ETag on Range responses).
  Future<String?> _fetchServerEtag(String url) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.headUrl(Uri.parse(url));
      final response = await request.close();
      await response.drain<void>();
      final etag = response.headers.value(HttpHeaders.etagHeader);
      debugPrint('[MbtilesDownload] 🏷️ Server ETag => $etag');
      // Plugin rejects weak validators (W/…).
      if (etag != null && etag.toUpperCase().startsWith('W/')) {
        return null;
      }
      return etag;
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ HEAD ETag failed: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

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
  Future<bool> _enqueueOrResumeMbtilesTask(
    DownloadTask task, {
    bool forceRestart = false,
  }) async {
    // Serialize enqueues — parallel connectivity/silent-retry was spawning
    // two FGS workers → two "Downloading Map Tiles" notifications.
    final previous = _enqueueGate;
    final gate = Completer<void>();
    _enqueueGate = gate.future;
    await previous;
    try {
      return await _enqueueOrResumeMbtilesTaskUnlocked(
        task,
        forceRestart: forceRestart,
      );
    } finally {
      gate.complete();
    }
  }

  Future<bool> _enqueueOrResumeMbtilesTaskUnlocked(
    DownloadTask task, {
    bool forceRestart = false,
  }) async {
    if (_wasOffline) {
      debugPrint(
        '[MbtilesDownload] ⏸️ Skip enqueue while offline — wait for network',
      );
      return false;
    }

    // Always clear orphan/failed leftovers before (re)enqueue. Soft resume
    // keeps the active partial; forceRestart wipes everything for a clean 0%.
    await _clearOrphanFailedDownloadFiles(
      keepActivePartial: !forceRestart,
    );

    // Force WorkManager. If the source was UIDT, mint a new taskId so the
    // old JobScheduler job cannot be revived for the same id hash.
    final fromUidt = task.priority == 0;
    final workTask = _asWorkManagerTask(
      task,
      newTaskId: fromUidt || forceRestart,
    );
    _backgroundTask = workTask;
    debugPrint(
      '[MbtilesDownload] 📋 Enqueue/resume WorkManager task '
      '${workTask.taskId} (priority=${workTask.priority}'
      '${fromUidt ? ', migrated from UIDT' : ''}'
      '${forceRestart ? ', forceRestart' : ''})',
    );

    _configureMbtilesNotifications();

    try {
      final records = await FileDownloader().database.allRecords();
      final mbtiles = records
          .where((r) => r.task.filename == LOCAL_MBTILES_FILENAME)
          .toList();

      if (forceRestart) {
        // Kill every prior worker first — otherwise Android keeps two FGS
        // notifications (client screenshot in airplane mode).
        await _cancelAllMbtilesTasks();
      } else {
        final preferred = await _ensureSingleActiveMbtilesTask(mbtiles);
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

          // Cancel stuck / zombie / failed tasks — keep temps.
          await _cancelAllMbtilesTasks();
        }
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ existing-task resume check: $e');
    }

    if (await _resumeFromOnDiskPartial(workTask)) {
      return true;
    }

    // Never start a brand-new temp from byte 0 when a real partial exists —
    // that was deleting multi-MB progress and looping Resuming↔Reconnecting.
    try {
      final appDir = await getApplicationSupportDirectory();
      final partial = await _bestLiveDownloaderTemp(
        appDir.path,
        minBytes: 64 * 1024,
      );
      if (partial != null && partial.length >= 1024 * 1024) {
        debugPrint(
          '[MbtilesDownload] ⚠️ Resume failed but partial exists '
          '(${partial.length} bytes) — retry plant+resume, no fresh 0% enqueue',
        );
        await Future<void>.delayed(const Duration(seconds: 1));
        if (await _resumeFromOnDiskPartial(workTask)) {
          return true;
        }
        // Last resort on Android: enqueue with planted resume data already
        // written — native should Range from startByte.
        if (Platform.isAndroid) {
          final enqueued = await FileDownloader().enqueue(workTask);
          _lastEnqueueAt = DateTime.now();
          return enqueued;
        }
        return false;
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ partial guard: $e');
    }

    final enqueued = await FileDownloader().enqueue(workTask);
    _lastEnqueueAt = DateTime.now();
    debugPrint(
      '[MbtilesDownload] 📋 Fresh WorkManager enqueue '
      '(priority=${workTask.priority}) => $enqueued',
    );
    // Fresh enqueue after forceRestart / lost resume data → show real %
    // (not the previous monotonic floor). Airplane→online hits this path.
    if (enqueued && forceRestart) {
      await _alignUiToRealDownloadProgress('fresh enqueue forceRestart');
    }
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
  /// User started an mbtiles download that is not finished. Survives force-kill
  /// so we can auto-restart after swipe-away / airplane mode on both platforms.
  static const String PREFS_KEY_DOWNLOAD_IN_PROGRESS = 'mbtiles_download_in_progress';

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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _wasOffline = false;
  /// One-shot watchdog after cold start / resume attaches to a "running" task
  /// that may already be dead (iOS force-quit kills URLSession).
  Timer? _staleRunningWatchdog;
  bool _fastProgressPolling = false;
  // Quiet UI hint — keep short so airplane / OEM stalls surface quickly.
  static const Duration _quietProgressHint = Duration(seconds: 20);

  /// Stall watchdog: if progress hasn't moved for [_stallTimeout] while
  /// `isDownloading` is true, force Range-resume so users are not stuck
  /// for 10+ minutes with working internet (client report).
  static const Duration _stallTimeout = Duration(minutes: 4);
  /// After a network blip the native task often stays `running` but transfers
  /// nothing. Kick resume quickly — duplicate FGS workers make this worse.
  static const Duration _zombieRunningTimeout = Duration(seconds: 25);

  /// Product rule: after reopen, only hard-restart if nothing moved for this
  /// long. Shorter windows (15–30s) false-fired while iOS was inactive /
  /// URLSession was quiet but still healthy.
  static const Duration _reopenHardRestartGrace = Duration(seconds: 70);

  /// False while inactive/paused/hidden — progress events often pause then,
  /// which must not count as a stall.
  bool _appInForeground = true;

  /// True when DB says running but the download looks dead (startup / reuse).
  bool _looksLikeZombieRunning({
    required TaskStatus status,
    required double pluginProgress,
  }) {
    if (status != TaskStatus.running && status != TaskStatus.enqueued) {
      return false;
    }
    if (Platform.isAndroid) {
      // Near-zero plugin progress with a small/frozen temp = hung Range worker.
      final live = _lastLiveTempBytes;
      if (live <= 0) return true;
      if (pluginProgress >= 0 &&
          pluginProgress < 0.001 &&
          live < 5 * 1024 * 1024) {
        return true;
      }
      return false;
    }
    // iOS: URLSession temp is invisible. After force-quit the DB often still
    // says "running" with no progress events — only after reopen grace.
    final last = _lastProgressAt;
    if (last == null) return false;
    return DateTime.now().difference(last) >= _reopenHardRestartGrace;
  }

  Future<void> _markDownloadInProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PREFS_KEY_DOWNLOAD_IN_PROGRESS, true);
    } catch (_) {}
  }

  Future<void> _clearDownloadInProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(PREFS_KEY_DOWNLOAD_IN_PROGRESS, false);
    } catch (_) {}
  }

  Future<bool> _isDownloadInProgressFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(PREFS_KEY_DOWNLOAD_IN_PROGRESS) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// After attaching to a DB "running" task, verify real progress arrives.
  /// iOS force-quit leaves stale running rows with a dead URLSession.
  /// Default grace is [_reopenHardRestartGrace] (~70s) — shorter windows
  /// pause+resumed healthy downloads (device: 25–30s false hard restart).
  void _armStaleRunningWatchdog({
    required String reason,
    Duration grace = _reopenHardRestartGrace,
  }) {
    _staleRunningWatchdog?.cancel();
    final armedAt = DateTime.now();
    // Bump liveness so a just-attached running task is not treated as dead
    // for [grace] even if the previous _lastProgressAt was cleared.
    _lastProgressAt = armedAt;
    _staleRunningWatchdog = Timer(grace, () {
      if (!isDownloading.value || isCompleted.value || hasError.value) return;
      if (!_appInForeground) {
        _armStaleRunningWatchdog(reason: '${reason}_bg_wait', grace: grace);
        return;
      }
      if (_wasOffline) {
        // Wait for connectivity listener — don't pause while offline.
        _armStaleRunningWatchdog(reason: '${reason}_offline_wait', grace: grace);
        return;
      }
      final last = _lastProgressAt;
      final moved = last != null && last.isAfter(armedAt);
      if (moved) return;
      debugPrint(
        '[MbtilesDownload] 🧟 Stale running watchdog ($reason) — '
        'no progress for ${grace.inSeconds}s, hard restart',
      );
      unawaited(_recoverFromStallOrFail(force: true, hardRestart: true));
    });
  }

  void _cancelStaleRunningWatchdog() {
    _staleRunningWatchdog?.cancel();
    _staleRunningWatchdog = null;
  }
  DateTime? _lastProgressAt;
  double _lastWatchedProgress = -1;
  /// Stall watchdog keys off on-disk bytes — plugin "progress" can tick
  /// without the temp file growing (ghost / hung Range), which used to
  /// keep resetting [_lastProgressAt] forever.
  int _lastWatchedBytes = -1;
  /// Latest temp size from a real filesystem scan (not the prefs checkpoint).
  /// Stall must use this — [_maxBytesSeen] can stay high after a truncate and
  /// hide a healthy smaller temp that is actively growing.
  int _lastLiveTempBytes = 0;
  /// Back off repeated cancel+resume so we don't loop Resuming↔Reconnecting.
  int _stallForceAttempts = 0;
  DateTime? _lastStallForceAt;
  static const Duration _minStallForceGap = Duration(seconds: 40);
  static const String _stablePartialName = 'tiles.mbtiles.partial';

  /// Backoff counter for silent auto-retries (no user-facing attempt count).
  int _autoResumeAttempts = 0;
  bool _silentRetryScheduled = false;
  DateTime? _lastResumeAttemptAt;
  static const Duration _resumeCooldown = Duration(seconds: 12);
  bool _dedupingTasks = false;
  /// Prevents connectivity + silent-retry + startup from enqueueing two FGS
  /// workers at once (client screenshot: two "Downloading Map Tiles" bars).
  Future<void> _enqueueGate = Future<void>.value();
  bool _notificationsConfigured = false;
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
  // Native retries help after transient Range failures; we still own
  // long-gap recovery ourselves so the UI does not thrash.
  static const int _downloadRetries = 3;

  /// Expected mbtiles package size shown in the UI (4.5 GB).
  /// Finalize still accepts ≥~3.5 GB SQLite files (live R2 object ≈ 3.98 GB).
  static const int _approxExpectedBytes = 4831838208; // 4.5 * 1024^3

  Future<String> _resolveLocalMbtilesPath() async {
    if (_localMbtilesPath != null && _localMbtilesPath!.isNotEmpty) {
      return _localMbtilesPath!;
    }
    final appDir = await getApplicationSupportDirectory();
    return '${appDir.path}/offline_tiles/$LOCAL_MBTILES_FILENAME';
  }

  void _startProgressPolling({bool fast = false, bool resetWatchdog = true}) {
    // Only reset the stall clock on a genuine new attempt — switching to
    // "fast" polling on quiet UI used to zero [_lastProgressAt] every 8s
    // and permanently hide zombies (file frozen, % never recovers).
    if (resetWatchdog || _lastProgressAt == null) {
      _lastProgressAt = DateTime.now();
      _lastWatchedProgress = downloadProgress.value;
      _lastWatchedBytes =
          math.max(downloadedBytes.value, _maxBytesSeen);
    }
    _fastProgressPolling = fast;
    _androidProgressPollTimer?.cancel();
    _androidProgressPollTimer = Timer.periodic(
      Duration(seconds: fast ? 1 : 2),
      (_) => unawaited(_syncProgressFromDatabaseAndFile()),
    );
    unawaited(_syncProgressFromDatabaseAndFile());
  }

  /// Poll every 1s while reconnecting so % can catch up from on-disk bytes.
  void _ensureFastProgressPolling() {
    if (_fastProgressPolling && _androidProgressPollTimer != null) return;
    _startProgressPolling(fast: true, resetWatchdog: false);
  }

  void _ensureNormalProgressPolling() {
    if (!_fastProgressPolling && _androidProgressPollTimer != null) return;
    if (!isDownloading.value || isCompleted.value) return;
    _startProgressPolling(fast: false, resetWatchdog: false);
  }

  /// Back-compat alias used throughout this file.
  void _startAndroidProgressPolling() => _startProgressPolling();

  void _stopAndroidProgressPolling() {
    _androidProgressPollTimer?.cancel();
    _androidProgressPollTimer = null;
    _fastProgressPolling = false;
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
        // Android only: on iOS the URLSession temp is not in our sandbox dir,
        // so "empty disk" is always true and this wiped healthy downloads.
        if (Platform.isAndroid &&
            onDisk < 64 * 1024 &&
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

      // iOS: keep the GB label in step with the % on every poll tick.
      if (!Platform.isAndroid &&
          downloadProgress.value > 0 &&
          _statusL10nKey != 'mbtiles_status_reconnecting' &&
          _statusL10nKey != 'mbtiles_status_resuming') {
        _updateGbStatusFromBytes(downloadedBytes.value);
      }

      if (record.expectedFileSize > 0) {
        _maybeAcceptExpectedFileSize(record.expectedFileSize);
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
        // _scheduleSilentRetry no-ops if already scheduled — avoid log spam.
        if (!_silentRetryScheduled) {
          debugPrint(
            '[MbtilesDownload] 📦 Preferred task failed — silent auto-retry',
          );
          unawaited(_scheduleSilentRetry(reason: 'db_poll_failed'));
        }
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

  /// Cancel every tiles.mbtiles worker. Used before a forced re-enqueue so
  /// Android never shows two FGS "Downloading Map Tiles" notifications.
  Future<void> _cancelAllMbtilesTasks({String? exceptId}) async {
    try {
      final records = await FileDownloader().database.allRecords();
      final ids = <String>[];
      for (final r in records) {
        if (r.task.filename != LOCAL_MBTILES_FILENAME) continue;
        if (exceptId != null && r.task.taskId == exceptId) continue;
        ids.add(r.task.taskId);
      }
      if (ids.isEmpty) return;
      debugPrint(
        '[MbtilesDownload] 🧹 Canceling ${ids.length} mbtiles task(s)'
        '${exceptId != null ? ' (keeping $exceptId)' : ''}',
      );
      await FileDownloader().cancelTasksWithIds(ids);
      for (final id in ids) {
        try {
          await FileDownloader().database.deleteRecordWithId(id);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[MbtilesDownload] ⚠️ cancelAll mbtiles failed: $e');
    }
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
    if (preferred == null) {
      // No preferred — still kill any live orphans so FGS notifications die.
      final orphanIds = mbtiles
          .where((r) =>
              r.status == TaskStatus.running ||
              r.status == TaskStatus.enqueued ||
              r.status == TaskStatus.waitingToRetry ||
              r.status == TaskStatus.paused)
          .map((r) => r.task.taskId)
          .toList();
      if (orphanIds.isNotEmpty) {
        await FileDownloader().cancelTasksWithIds(orphanIds);
      }
      return null;
    }

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

  /// Called on every poll tick. Stall = live temp file not growing.
  /// Uses [_lastLiveTempBytes] (filesystem), not [_maxBytesSeen] — a stale
  /// high checkpoint previously hid a healthy smaller temp and force-resumed
  /// mid-download (truncating tens of MB).
  void _checkForStall() {
    if (!isDownloading.value || hasError.value || isCompleted.value) return;

    // iOS has no visible temp file — watch plugin progress events instead.
    if (!Platform.isAndroid) {
      _checkForStallIos();
      return;
    }

    final bytesNow = _lastLiveTempBytes;
    if (bytesNow > _lastWatchedBytes) {
      _lastWatchedBytes = bytesNow;
      _lastWatchedProgress = downloadProgress.value;
      _lastProgressAt = DateTime.now();
      _stallForceAttempts = 0;
      // Bytes moving — leave Resuming/Reconnecting immediately.
      if (_statusL10nKey == 'mbtiles_status_reconnecting' ||
          _statusL10nKey == 'mbtiles_status_resuming') {
        _updateGbStatusFromBytes(bytesNow);
      }
      _ensureNormalProgressPolling();
      return;
    }

    final lastProgressAt = _lastProgressAt;
    if (lastProgressAt == null) {
      _lastProgressAt = DateTime.now();
      _lastWatchedBytes = bytesNow;
      return;
    }

    final quietFor = DateTime.now().difference(lastProgressAt);
    // Poll faster while quiet, but keep the GB status — flipping to
    // "Reconnecting"/"Resuming" every few seconds is what users see as stuck.
    if (quietFor >= _quietProgressHint) {
      _ensureFastProgressPolling();
      if (_lastLiveTempBytes > 0) {
        _updateGbStatusFromBytes(_lastLiveTempBytes);
      }
    }

    // Back off: 25s, then 45s, 90s… so we never thrash Resuming↔Reconnecting.
    final zombieTimeout = Duration(
      seconds: _zombieRunningTimeout.inSeconds *
          (1 << math.min(_stallForceAttempts, 3)),
    );
    final lastForce = _lastStallForceAt;
    final sinceForce = lastForce == null
        ? const Duration(days: 1)
        : DateTime.now().difference(lastForce);
    if (quietFor >= zombieTimeout && sinceForce >= _minStallForceGap) {
      debugPrint(
        '[MbtilesDownload] 🧟 No live-temp growth for ${quietFor.inSeconds}s '
        '(live=$bytesNow, maxSeen=$_maxBytesSeen, attempt=$_stallForceAttempts) '
        '— forcing resume',
      );
      unawaited(_recoverFromStallOrFail(force: true));
      return;
    }

    // 99.x% freeze: last bytes often stall on Range — kick sooner.
    if (downloadProgress.value >= 0.99 &&
        quietFor >= const Duration(seconds: 90) &&
        sinceForce >= const Duration(seconds: 45)) {
      debugPrint(
        '[MbtilesDownload] ⏱️ Near-complete stall at '
        '${(downloadProgress.value * 100).toStringAsFixed(1)}% — force resume',
      );
      unawaited(_recoverFromStallOrFail(force: true));
      return;
    }

    if (quietFor < _stallTimeout) return;

    if (sinceForce < _minStallForceGap) return;

    debugPrint(
      '[MbtilesDownload] ⏱️ Stall detected — no live-temp growth for '
      '${_stallTimeout.inMinutes}min (live=$bytesNow)',
    );
    unawaited(_recoverFromStallOrFail(force: true));
  }

  /// iOS stall watchdog. URLSession keeps its partial in a system temp, so we
  /// cannot see bytes on disk; the only reliable liveness signal is the
  /// plugin's progress events (see the progress handler, which bumps
  /// [_lastProgressAt] on iOS). Recovery uses pause+resume (URLSession
  /// resumeData) and only runs while the device is online + foregrounded.
  void _checkForStallIos() {
    // Progress events often pause while inactive (Control Center, app switcher).
    // Do not flip to Reconnecting or hard-restart until we're foregrounded
    // and quiet for [_reopenHardRestartGrace].
    if (!_appInForeground) return;

    final lastProgressAt = _lastProgressAt;
    if (lastProgressAt == null) {
      _lastProgressAt = DateTime.now();
      return;
    }

    if (downloadProgress.value > _lastWatchedProgress) {
      _lastWatchedProgress = downloadProgress.value;
      _lastProgressAt = DateTime.now();
      _stallForceAttempts = 0;
      _cancelStaleRunningWatchdog();
      _ensureNormalProgressPolling();
      return;
    }

    final quietFor = DateTime.now().difference(lastProgressAt);
    // Keep GB status — never flash Reconnecting on brief quiet (device log:
    // 15s → Reconnecting while DNS was fine, then 30s hard restart from 0%).
    if (quietFor >= const Duration(seconds: 20)) {
      _ensureFastProgressPolling();
      if (_lastLiveTempBytes > 0 || downloadedBytes.value > 0) {
        _updateGbStatusFromBytes(
          math.max(_lastLiveTempBytes, downloadedBytes.value),
        );
      }
    }

    // Nothing to recover while offline — connectivity listener resumes when
    // airplane mode / network returns.
    if (_wasOffline) return;

    // First hard kick only after reopen grace (~70s), then back off.
    final zombieTimeout = Duration(
      seconds: _reopenHardRestartGrace.inSeconds *
          (1 << math.min(_stallForceAttempts, 2)),
    );
    final lastForce = _lastStallForceAt;
    final sinceForce = lastForce == null
        ? const Duration(days: 1)
        : DateTime.now().difference(lastForce);
    if (downloadProgress.value >= 0.99 &&
        quietFor >= const Duration(seconds: 90) &&
        sinceForce >= const Duration(seconds: 45)) {
      debugPrint(
        '[MbtilesDownload] 🍎 iOS near-complete stall at '
        '${(downloadProgress.value * 100).toStringAsFixed(1)}% — force resume',
      );
      unawaited(_recoverFromStallOrFail(force: true));
      return;
    }

    if (quietFor >= zombieTimeout &&
        sinceForce >= _reopenHardRestartGrace) {
      debugPrint(
        '[MbtilesDownload] 🍎 iOS: no progress for ${quietFor.inSeconds}s '
        '(attempt=$_stallForceAttempts) — hard restart',
      );
      unawaited(_recoverFromStallOrFail(force: true, hardRestart: true));
    }
  }

  Future<void> _recoverFromStallOrFail({
    bool force = false,
    bool hardRestart = false,
  }) async {
    if (!isDownloading.value || hasError.value || isCompleted.value) return;
    if (!_appInForeground) return;

    if (!Platform.isAndroid) {
      _lastStallForceAt = DateTime.now();
      _stallForceAttempts++;
      _lastProgressAt = DateTime.now();
      if (hardRestart) {
        debugPrint(
          '[MbtilesDownload] 🍎 Hard restart after '
          '${_reopenHardRestartGrace.inSeconds}s quiet — wipe + re-enqueue',
        );
        await _wipePreviousMbtilesDownloadArtifacts(preservePartials: false);
        await _resetStaleProgress('ios hard restart after stall');
        await _markDownloadInProgress();
        isDownloading.value = false;
        _allowReenqueueWhileDownloading = true;
        try {
          await downloadMbtiles(zoomLevel: await getSelectedZoomLevel());
        } finally {
          _allowReenqueueWhileDownloading = false;
        }
        return;
      }
      if (await _tryAutoResume(reason: 'stall', force: force)) return;
      unawaited(_scheduleSilentRetry(reason: 'stall'));
      return;
    }

    // Re-scan once — if bytes grew during the quiet window, abort force.
    await _seedProgressFromPartialFileIfNeeded();
    if (_lastLiveTempBytes > _lastWatchedBytes) {
      debugPrint(
        '[MbtilesDownload] ✅ Live temp grew before force '
        '(${_lastWatchedBytes} → $_lastLiveTempBytes) — skip',
      );
      _lastWatchedBytes = _lastLiveTempBytes;
      _lastProgressAt = DateTime.now();
      _stallForceAttempts = 0;
      _updateGbStatusFromBytes(_lastLiveTempBytes);
      return;
    }

    _lastStallForceAt = DateTime.now();
    _stallForceAttempts++;
    // Reset quiet clock so we don't immediately re-enter while resume runs.
    _lastProgressAt = DateTime.now();

    if (await _tryAutoResume(reason: 'stall', force: force)) {
      return;
    }

    debugPrint('[MbtilesDownload] ⏱️ Stall recovery — scheduling silent retry');
    unawaited(_scheduleSilentRetry(reason: 'stall'));
  }

  /// Resume a paused/failed task when the native downloader still has Range data.
  /// Always retries — no user-facing "retry 1 of N" limit or message.
  ///
  /// [force]: after connectivity restore / zombie quiet period, do not trust a
  /// stale `running` status — cancel and Range-resume from the on-disk partial.
  Future<bool> _tryAutoResume({
    required String reason,
    bool force = false,
  }) async {
    if (_wasOffline && !reason.contains('connectivity')) {
      debugPrint(
        '[MbtilesDownload] ⏸️ Offline — defer resume ($reason)',
      );
      return false;
    }
    final last = _lastResumeAttemptAt;
    if (last != null && DateTime.now().difference(last) < _resumeCooldown) {
      debugPrint(
        '[MbtilesDownload] ⏸️ Resume cooldown active — skip ($reason)',
      );
      // false → callers schedule a delayed silent retry. Returning true here
      // previously left % frozen after reconnect (force-resume failed, then
      // task_failed / silent retry thought "already handled").
      return false;
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
        final quietFor = _lastProgressAt == null
            ? Duration.zero
            : DateTime.now().difference(_lastProgressAt!);
        final looksAlive = existing.priority != 0 &&
            (preferred.status == TaskStatus.running ||
                preferred.status == TaskStatus.enqueued ||
                preferred.status == TaskStatus.waitingToRetry);
        // Post-offline zombie: DB still says running but bytes stopped.
        // Airplane-mode restore always force-requeues — URLSession/WorkManager
        // often stay "running" while transferring nothing until kicked.
        final forceReenqueue = force ||
            reason.contains('connectivity') ||
            quietFor >=
                (Platform.isAndroid
                    ? _zombieRunningTimeout
                    : const Duration(seconds: 60));
        if (looksAlive && !forceReenqueue) {
          _backgroundTask = existing;
          isDownloading.value = true;
          if (preferred.progress >= 0 && preferred.progress <= 1) {
            _applyProgress(preferred.progress);
          }
          return true;
        }
        if (looksAlive && forceReenqueue && !Platform.isAndroid) {
          // Prefer pause+resume (keeps URLSession resumeData). If that fails
          // (common after force-quit / airplane), cancel the dead task and
          // fall through to a fresh enqueue — never sit on "Reconnecting".
          try {
            debugPrint(
              '[MbtilesDownload] 🍎 iOS pause+resume for stale '
              '${preferred.status} task ${existing.taskId} ($reason)',
            );
            await FileDownloader().pause(existing);
            await Future<void>.delayed(const Duration(seconds: 1));
            final resumed = await FileDownloader().resume(existing);
            if (resumed) {
              _backgroundTask = existing;
              _lastResumeAttemptAt = DateTime.now();
              _lastProgressAt = DateTime.now();
              _startProgressPolling(fast: true, resetWatchdog: true);
              _armStaleRunningWatchdog(reason: 'ios_pause_resume_$reason');
              debugPrint('[MbtilesDownload] 🍎 iOS resume ok');
              return true;
            }
          } catch (e) {
            debugPrint('[MbtilesDownload] 🍎 iOS pause+resume failed: $e');
          }
          debugPrint(
            '[MbtilesDownload] 🍎 iOS resume unavailable — cancel + '
            'wipe + fresh enqueue ($reason)',
          );
          try {
            await FileDownloader().cancelTaskWithId(existing.taskId);
          } catch (_) {}
          try {
            await FileDownloader().database.deleteRecordWithId(existing.taskId);
          } catch (_) {}
          _backgroundTask = null;
          task = null;
          // Reconnection/resume failed → new connection must not reuse
          // orphan temps or incomplete destination from the dead task.
          await _wipePreviousMbtilesDownloadArtifacts(preservePartials: false);
          await _resetStaleProgress('ios resume unavailable');
        } else if (looksAlive && forceReenqueue) {
          // Android: snapshot BEFORE cancel — plugin often deletes temp on cancel.
          await _snapshotLargestPartial();
          debugPrint(
            '[MbtilesDownload] 🧟 Cancelling stale ${preferred.status} '
            'task ${existing.taskId} (quiet=${quietFor.inSeconds}s, $reason)',
          );
          try {
            await FileDownloader().cancelTaskWithId(existing.taskId);
          } catch (_) {}
          try {
            await FileDownloader().database.deleteRecordWithId(existing.taskId);
          } catch (_) {}
          task = existing;
        } else {
          task = existing;
        }
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
    // New task id after forced cancel — reusing a just-canceled id often
    // fails immediately (seen in logcat as running → failed within 1s).
    final workTask = _asWorkManagerTask(
      template,
      newTaskId: force ||
          reason.contains('connectivity') ||
          template.priority == 0,
    );

    try {
      await _seedProgressFromPartialFileIfNeeded();
      _lastResumeAttemptAt = DateTime.now();
      _autoResumeAttempts++;
      isDownloading.value = true;
      hasError.value = false;
      // Keep GB label — do not flash "Resuming" (looks like a stuck loop).
      if (_lastLiveTempBytes > 0) {
        _updateGbStatusFromBytes(_lastLiveTempBytes);
      }

      final doForceRestart = force ||
          reason.contains('connectivity') ||
          reason.contains('stall') ||
          reason.contains('startup');
      final ok = await _enqueueOrResumeMbtilesTask(
        workTask,
        // After force-quit / airplane, mint a new task id so a dead
        // URLSession/WorkManager row cannot block the fresh enqueue.
        forceRestart: doForceRestart,
      );
      if (ok) {
        // Soft resume paths may keep the same task; still align when we
        // know this was a connectivity / force re-queue (iOS raw→0).
        if (doForceRestart) {
          await _alignUiToRealDownloadProgress('auto_resume_$reason');
        }
        await _markDownloadInProgress();
        _startProgressPolling(fast: true, resetWatchdog: true);
        _armStaleRunningWatchdog(reason: 'auto_resume_$reason');
        debugPrint(
          '[MbtilesDownload] ✅ Auto-resume (WorkManager) after $reason '
          '(task=${workTask.taskId})',
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
    await _seedProgressFromPartialFileIfNeeded();
    if (_lastLiveTempBytes > 0) {
      _updateGbStatusFromBytes(_lastLiveTempBytes);
    }

    final backoffSeconds =
        math.min(60, 5 * (1 << math.min(_autoResumeAttempts, 3)));
    // Wait out any remaining resume cooldown so the next attempt actually
    // enqueues (cooldown used to return "success" and abort the chain).
    final last = _lastResumeAttemptAt;
    final cooldownLeft = last == null
        ? 0
        : math.max(
            0,
            _resumeCooldown.inSeconds -
                DateTime.now().difference(last).inSeconds,
          );
    final delaySeconds = math.max(backoffSeconds, cooldownLeft + 1);
    final forceRetry = reason.contains('failed') ||
        reason.contains('connectivity') ||
        reason.contains('stall');
    debugPrint(
      '[MbtilesDownload] ⏳ Silent retry in ${delaySeconds}s after $reason '
      '(force=$forceRetry)',
    );
    try {
      await Future<void>.delayed(Duration(seconds: delaySeconds));
      if (isCompleted.value) return;

      // Another path (e.g. app_resumed) may have resumed during our wait —
      // finish the remaining cooldown before trying again.
      final lastAfterWait = _lastResumeAttemptAt;
      if (lastAfterWait != null) {
        final left = _resumeCooldown - DateTime.now().difference(lastAfterWait);
        if (left > Duration.zero) {
          debugPrint(
            '[MbtilesDownload] ⏳ Extra ${left.inSeconds + 1}s for resume cooldown',
          );
          await Future<void>.delayed(left + const Duration(seconds: 1));
        }
      }
      if (isCompleted.value) return;

      if (await _tryAutoResume(
            reason: '${reason}_silent',
            force: forceRetry,
          )) {
        return;
      }

      // Last resort: reconnection/resume failed — wipe prior data and start
      // a brand-new download connection from 0%.
      debugPrint(
        '[MbtilesDownload] ♻️ Resume unavailable — wipe + fresh enqueue '
        'after $reason',
      );
      await _reenqueueFreshAfterFailedReconnect(reason);
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
  ///
  /// Same-process pause→foreground only. Cold start after kill is handled by
  /// [_checkForResumedDownloads] (wipe + restart from 0%).
  Future<void> resumeDownloadUpdatesFromBackground() async {
    _appInForeground = true;
    _lastProgressAt = DateTime.now();

    // Let cold-start wipe+restart finish first so we don't "Keep" a dead
    // TaskStatus.running row left after force-quit (device: stuck at 0.08 GB).
    try {
      await _startupReady;
    } catch (_) {}

    await FileDownloader().resumeFromBackground();
    await _syncProgressFromDatabaseAndFile();
    final intended = await _isDownloadInProgressFlag();
    if (isCompleted.value) return;
    if (!(isDownloading.value ||
        intended ||
        _maxBytesSeen > 1024 * 1024 ||
        downloadProgress.value > 0)) {
      return;
    }

    // Already downloading after startup wipe+restart — just keep polling.
    if (isDownloading.value && _backgroundTask != null) {
      _startAndroidProgressPolling();
      _armStaleRunningWatchdog(reason: 'app_resumed');
      return;
    }

    // Same-process: resume existing if not failed; else remove + enqueue.
    await _resumeExistingOrReenqueue(reason: 'app_resumed');
  }

  /// Reopen / recovery rule:
  /// 1. Existing task not failed → resume (or keep if already running)
  /// 2. Else → wipe previous files + remove from queue and enqueue fresh
  Future<void> _resumeExistingOrReenqueue({required String reason}) async {
    try {
      await _loadMaxBytesCheckpoint();
      await _seedProgressFromPartialFileIfNeeded();

      final records = await FileDownloader().database.allRecords();
      final mbtiles = records
          .where((r) => r.task.filename == LOCAL_MBTILES_FILENAME)
          .toList();
      final preferred = await _ensureSingleActiveMbtilesTask(mbtiles);

      if (preferred != null) {
        final task = preferred.task as DownloadTask;
        final status = preferred.status;
        final notFailed = status == TaskStatus.running ||
            status == TaskStatus.enqueued ||
            status == TaskStatus.paused ||
            status == TaskStatus.waitingToRetry;

        // UIDT (priority 0) cannot survive background — treat like failed.
        if (notFailed && task.priority != 0) {
          _backgroundTask = task;
          isDownloading.value = true;
          await _markDownloadInProgress();
          if (preferred.progress >= 0 && preferred.progress <= 1) {
            _applyProgress(preferred.progress);
          }
          await _seedProgressFromPartialFileIfNeeded();
          _updateGbStatusFromBytes(
            math.max(_lastLiveTempBytes, downloadedBytes.value),
          );

          if (status == TaskStatus.running ||
              status == TaskStatus.enqueued) {
            debugPrint(
              '[MbtilesDownload] ▶️ Keep existing $status '
              '${task.taskId} ($reason)',
            );
            _setStatusText('mbtiles_status_downloading');
            _startAndroidProgressPolling();
            _armStaleRunningWatchdog(reason: reason);
            return;
          }

          // paused / waitingToRetry → resume in place
          final canResume = await FileDownloader().taskCanResume(task);
          if (canResume) {
            await _protectResumeDataFromTruncation();
            final ok = await FileDownloader().resume(task);
            debugPrint(
              '[MbtilesDownload] ▶️ Resume existing $status '
              '${task.taskId} ($reason) => $ok',
            );
            if (ok) {
              _setStatusText('mbtiles_status_resuming');
              _startAndroidProgressPolling();
              _armStaleRunningWatchdog(reason: reason);
              return;
            }
          }
          debugPrint(
            '[MbtilesDownload] ⚠️ Resume failed for $status '
            '${task.taskId} — wipe + enqueue ($reason)',
          );
        } else {
          debugPrint(
            '[MbtilesDownload] ❌ Existing ${status.name} '
            '(priority=${task.priority}) — wipe + enqueue ($reason)',
          );
        }

        // Failed / UIDT / resume unavailable → clear files + new connection.
        await _reenqueueFreshAfterFailedReconnect(reason);
        _armStaleRunningWatchdog(reason: '${reason}_enqueued');
        return;
      } else {
        debugPrint(
          '[MbtilesDownload] 📋 No existing task — enqueue ($reason)',
        );
      }

      // No prior task — soft enqueue is fine (nothing to wipe).
      isDownloading.value = false;
      _allowReenqueueWhileDownloading = true;
      try {
        await downloadMbtiles(zoomLevel: await getSelectedZoomLevel());
      } finally {
        _allowReenqueueWhileDownloading = false;
      }
      _armStaleRunningWatchdog(reason: '${reason}_enqueued');
    } catch (e) {
      debugPrint(
        '[MbtilesDownload] ⚠️ resumeExistingOrReenqueue failed ($reason): $e',
      );
    }
  }

  /// Reconnection / resume already failed — delete previous temps, incomplete
  /// destination, and resume metadata, then start a brand-new download from 0%.
  Future<void> _reenqueueFreshAfterFailedReconnect(String reason) async {
    debugPrint(
      '[MbtilesDownload] 🧹 Fresh download after failed reconnect ($reason) '
      '— clearing previous data',
    );
    try {
      await _cancelAllMbtilesTasks();
    } catch (_) {}
    _backgroundTask = null;
    await _wipePreviousMbtilesDownloadArtifacts(preservePartials: false);
    await _resetStaleProgress('failed reconnect: $reason');
    final expected = _expectedTotalBytes();
    if (totalBytes.value < expected) totalBytes.value = expected;
    final totalGB = (expected / (1024 * 1024 * 1024)).toStringAsFixed(1);
    _setStatusText('mbtiles_status_downloading_gb_pair', ['0.00', totalGB]);

    isDownloading.value = false;
    _allowReenqueueWhileDownloading = true;
    try {
      await downloadMbtiles(
        zoomLevel: await getSelectedZoomLevel(),
        clearPreviousData: true,
      );
    } finally {
      _allowReenqueueWhileDownloading = false;
    }
    if (!isDownloading.value && !isCompleted.value && !hasError.value) {
      isDownloading.value = true;
    }
  }

  /// True when Get Started should auto-wire UI after launch / pause-reopen.
  Future<bool> hasResumablePartialOrActiveTask() async {
    try {
      await _startupReady;
    } catch (_) {}
    if (isDownloading.value && !isCompleted.value) return true;
    if (await isMbtilesDownloaded()) return false;
    if (await _isDownloadInProgressFlag()) return true;
    await _loadMaxBytesCheckpoint();
    await _reconcileStaleCheckpoint();
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
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _cancelStaleRunningWatchdog();
    _stopAndroidProgressPolling();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appInForeground = true;
        // Background quiet must not trigger hard restart the moment we return.
        _lastProgressAt = DateTime.now();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _appInForeground = false;
        break;
      case AppLifecycleState.detached:
        // Best-effort cancel when the engine is tearing down (iOS force-quit
        // often skips this; cold-start [_checkForResumedDownloads] is the
        // reliable path). Android also has MainActivity.onTaskRemoved.
        _appInForeground = false;
        if (isDownloading.value && !isCompleted.value) {
          unawaited(cancelDownload());
        }
        break;
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _setStatusText('mbtiles_status_ready_to_download');
    unawaited(_loadMaxBytesCheckpoint());
    _listenForConnectivityChanges();
    // start() must complete before we inspect the task DB / resume.
    _startupReady = () async {
      await _initializeBackgroundDownloader();
      await _checkForResumedDownloads();
    }();
    unawaited(_startupReady);
  }

  /// Completes once the launch-time cleanup/recovery pass has finished, so
  /// screens never act on partial data that pass is about to discard.
  Future<void> _startupReady = Future<void>.value();

  /// After disconnect → reconnect (airplane mode off), auto-resume on both
  /// platforms so the UI never sits on "Reconnecting" forever.
  void _listenForConnectivityChanges() {
    _connectivitySub?.cancel();
    // Seed offline flag so the first online event after a cold start in
    // airplane mode still triggers resume when the radio returns.
    unawaited(() async {
      try {
        final now = await Connectivity().checkConnectivity();
        _wasOffline =
            now.isEmpty || now.contains(ConnectivityResult.none);
      } catch (_) {}
    }());
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final offline =
          results.isEmpty || results.contains(ConnectivityResult.none);
      if (offline) {
        _wasOffline = true;
        if ((isDownloading.value || downloadProgress.value > 0) &&
            !isCompleted.value) {
          _ensureFastProgressPolling();
          _setStatusText('mbtiles_status_reconnecting');
          if (_lastLiveTempBytes > 0) {
            _updateGbStatusFromBytes(_lastLiveTempBytes);
          }
          // While offline: collapse to a single paused worker so we do not
          // keep spawning FGS notifications that sit at 0% + mid-% together.
          unawaited(() async {
            try {
              final records = await FileDownloader().database.allRecords();
              final mbtiles = records
                  .where((r) => r.task.filename == LOCAL_MBTILES_FILENAME)
                  .toList();
              final preferred = await _ensureSingleActiveMbtilesTask(mbtiles);
              if (preferred != null) {
                try {
                  await FileDownloader()
                      .pause(preferred.task as DownloadTask);
                } catch (_) {}
              }
            } catch (_) {}
          }());
        }
        return;
      }
      if (!_wasOffline) return;
      _wasOffline = false;
      unawaited(() async {
        if (isCompleted.value) return;
        final intended = await _isDownloadInProgressFlag();
        if (!isDownloading.value &&
            !intended &&
            _maxBytesSeen < 1024 * 1024 &&
            downloadProgress.value <= 0) {
          return;
        }
        isDownloading.value = true;
        debugPrint(
          '[MbtilesDownload] 🌐 Connectivity restored — forcing resume '
          '(live=$_lastLiveTempBytes, intended=$intended)',
        );
        _ensureFastProgressPolling();
        if (_lastLiveTempBytes > 0) {
          _updateGbStatusFromBytes(_lastLiveTempBytes);
        } else {
          _setStatusText('mbtiles_status_resuming');
        }
        // Let the radio / DNS settle; immediate enqueue often fails instantly.
        await Future<void>.delayed(const Duration(seconds: 2));
        if (isCompleted.value || _wasOffline) return;
        await FileDownloader().resumeFromBackground();
        await _seedProgressFromPartialFileIfNeeded();
        await _syncProgressFromDatabaseAndFile();
        // Dedupe before resume so only one notification returns.
        await _cancelAllMbtilesTasks(
          exceptId: _backgroundTask?.taskId,
        );
        final ok = await _tryAutoResume(
          reason: 'connectivity_restored',
          force: true,
        );
        if (!ok && !_wasOffline) {
          // Reconnect resume failed — wipe orphans and open a new connection.
          await _reenqueueFreshAfterFailedReconnect('connectivity_restored');
        }
        _armStaleRunningWatchdog(reason: 'connectivity_restored');
      }());
    });
  }

  /// Configure running/paused/complete notifications for the mbtiles group.
  /// Required for Android foreground service while the app is backgrounded.
  /// Group-only (not global + per-task) — stacking those + duplicate workers
  /// produced two "Downloading Map Tiles" notifications (client screenshot).
  void _configureMbtilesNotifications() {
    if (_notificationsConfigured) return;
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

    FileDownloader().configureNotificationForGroup(
      _downloadGroup,
      running: running,
      complete: complete,
      error: error,
      paused: paused,
      progressBar: true,
    );
    _notificationsConfigured = true;
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

  /// Cold start after process death (Android swipe-away / iOS force-quit).
  ///
  /// Matches Android [MainActivity.onTaskRemoved]: cancel native workers
  /// (WorkManager FGS / iOS URLSession), clear notifications via task cancel,
  /// wipe orphan/failed partials, clear the in-progress flag, and **do not**
  /// auto-restart. User taps Start again.
  ///
  /// Same-process pause→foreground still soft-resumes via
  /// [resumeDownloadUpdatesFromBackground].
  Future<void> _checkForResumedDownloads() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));

      if (await isMbtilesDownloaded()) {
        debugPrint(
          '[MbtilesDownload] ✅ Complete download already on disk — skip relaunch',
        );
        return;
      }

      final tasks = await FileDownloader().database.allRecords();
      debugPrint(
        '[MbtilesDownload] 🔍 Checking for resumed downloads: ${tasks.length} tasks found',
      );

      final mbtiles = tasks
          .where((r) => r.task.filename == LOCAL_MBTILES_FILENAME)
          .toList();

      final intended = await _isDownloadInProgressFlag();
      await _loadMaxBytesCheckpoint();
      final onDisk =
          await _activePartialBytesOnDisk(minLiveTempBytes: 64 * 1024);
      final hadLeftovers = intended ||
          mbtiles.isNotEmpty ||
          onDisk >= 1024 * 1024 ||
          _maxBytesSeen >= 1024 * 1024;

      if (!hadLeftovers) {
        debugPrint(
          '[MbtilesDownload] 🧹 Relaunch with no incomplete download — clean',
        );
        await _wipePreviousMbtilesDownloadArtifacts(preservePartials: false);
        await _resetStaleProgress('relaunch cleanup');
        isDownloading.value = false;
        return;
      }

      // Android swipe + iOS force-quit: cancel everything, wipe orphans, idle.
      debugPrint(
        '[MbtilesDownload] 🛑 Process-death reopen — cancel workers, wipe '
        'orphans, clear notification (no auto-restart) '
        '(intended=$intended, tasks=${mbtiles.length}, '
        'onDisk=$onDisk, maxSeen=$_maxBytesSeen, '
        'platform=${Platform.isIOS ? 'ios' : 'android'})',
      );
      try {
        await FileDownloader().cancelAll(group: _downloadGroup);
      } catch (_) {}
      await _cancelAllMbtilesTasks();
      await _wipePreviousMbtilesDownloadArtifacts(preservePartials: false);
      await _clearDownloadInProgress();
      await _resetStaleProgress('process death cancel');
      if (totalBytes.value <= 0 ||
          totalBytes.value < (_approxExpectedBytes * 0.85).round() ||
          totalBytes.value > (_approxExpectedBytes * 1.15).round()) {
        totalBytes.value = _approxExpectedBytes;
      }
      isDownloading.value = false;
      _setStatusText('mbtiles_status_ready_to_download');
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
            if (_lastLiveTempBytes > 0) {
              _updateGbStatusFromBytes(_lastLiveTempBytes);
            }
            _ensureFastProgressPolling();
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
          // Android: do NOT bump the stall clock here — plugin progress can
          // advance while the temp file is frozen ([_checkForStall] owns it).
          // iOS: progress events are the only liveness signal we have.
          if (!Platform.isAndroid) {
            _lastProgressAt = DateTime.now();
            if (_statusL10nKey == 'mbtiles_status_reconnecting' ||
                _statusL10nKey == 'mbtiles_status_resuming') {
              _setStatusText('mbtiles_status_downloading');
            }
          }

          debugPrint(
            '[MbtilesDownload] 📊 Progress update: ${(downloadProgress.value * 100).toStringAsFixed(1)}% (raw=${update.progress})',
          );

          if (update.expectedFileSize > 0) {
            _maybeAcceptExpectedFileSize(update.expectedFileSize);
          }
          _updateGbStatusFromProgress();
        } else if (update is TaskStatusUpdate) {
          debugPrint('[MbtilesDownload] 📡 Status update: ${update.status}');

          if (update.status == TaskStatus.running ||
              update.status == TaskStatus.enqueued ||
              update.status == TaskStatus.waitingToRetry) {
            isDownloading.value = true;
            hasError.value = false;
            // Do NOT reset _lastProgressAt here — status flips to running after
            // a network blip without byte growth, which was hiding zombies.
            // Always keep GB label — never flip to Reconnecting/Resuming here.
            if (_lastLiveTempBytes > 0 || downloadedBytes.value > 0) {
              _updateGbStatusFromBytes(
                math.max(_lastLiveTempBytes, downloadedBytes.value),
              );
            } else {
              _setStatusText('mbtiles_status_downloading');
            }
            if (update.status == TaskStatus.waitingToRetry) {
              _ensureFastProgressPolling();
            }
          } else if (update.status == TaskStatus.complete) {
            // isDownloading intentionally stays true until finalize actually
            // confirms success below. Do NOT set progress to 100% here —
            // a rejected finalize (wrong size constant) used to lock the UI
            // at 100% forever via monotonic _lastGoodProgress while a new
            // download restarted from ~1% (device log: complete →
            // "3.98 GB too small" → Progress 100% (raw=0.01)).
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
            final exc = update.exception;
            debugPrint(
              '[MbtilesDownload] ❌ Task failed — silent auto-retry '
              '(exception=$exc)',
            );
            // Preserve bytes before the plugin deletes its temp on failure.
            await _snapshotLargestPartial();
            await _protectResumeDataFromTruncation();
            await _seedProgressFromPartialFileIfNeeded();
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

      // MBTiles is a SQLite DB. Real R2 zoom-11 file is ~3.98GB — our old
      // 4.5GB constant + 98% softMin (=4.41GB) rejected a finished download
      // and left the UI stuck at 100% while a new transfer restarted.
      final isSqlite = header.startsWith('SQLite format 3');
      const absoluteMinBytes = 3500 * 1024 * 1024; // 3.5 GB
      final reportedLen = totalBytes.value;
      final softMin = (reportedLen >= absoluteMinBytes)
          ? (reportedLen * 0.95).round()
          : absoluteMinBytes;

      if (!isSqlite || fileSize < softMin) {
        debugPrint(
          '[MbtilesDownload] ❌ Finalize reject: size=$fileSizeGB GB '
          'sqlite=$isSqlite (need ≥${(softMin / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB)',
        );
        // Unlock monotonic UI from a false 100% before resume/retry.
        final expected = _expectedTotalBytes();
        final unlocked =
            (fileSize / expected).clamp(0.0, 0.99);
        _lastGoodProgress = unlocked;
        downloadProgress.value = unlocked;
        downloadedBytes.value = fileSize;

        if (isSqlite && fileSize >= (absoluteMinBytes * 0.9).round()) {
          // Very close — Range-resume last bytes instead of failing hard.
          isDownloading.value = true;
          hasError.value = false;
          _setStatusText('mbtiles_status_resuming');
          unawaited(
            _tryAutoResume(reason: 'finalize_near_complete', force: true),
          );
          return;
        }
        hasError.value = true;
        errorMessage.value = trKey('mbtiles_error_file_too_small', [fileSizeGB]);
        _setStatusText('mbtiles_status_download_failed_file_small');
        isCompleted.value = false;
        isDownloading.value = false;
        return;
      }

      // Trust measured size for future % / GB labels.
      if (fileSize > totalBytes.value) {
        totalBytes.value = fileSize;
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
      await _clearDownloadInProgress();
      hasError.value = false;
      _applyProgress(1.0);
      _setStatusText('mbtiles_status_download_completed_gb', [fileSizeGB]);
      _cancelStaleRunningWatchdog();
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
          final hasPartial = _maxBytesSeen > 0 ||
              downloadedBytes.value > 0 ||
              _lastGoodProgress > 0;
          if (!isDownloading.value && !hasPartial) {
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

        final hasPartial = _maxBytesSeen > 0 ||
            downloadedBytes.value > 0 ||
            _lastGoodProgress > 0;
        if (!isDownloading.value && !hasPartial) {
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
  /// [clearPreviousData] - When true (failed reconnect → new connection), wipe
  /// all previous temps/incomplete files before enqueueing from 0%.
  Future<String?> downloadMbtiles({
    int? zoomLevel,
    bool enableBackgroundDownload = true,
    bool clearPreviousData = false,
  }) async {
    if (isDownloading.value && !_allowReenqueueWhileDownloading) {
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

    if (clearPreviousData) {
      debugPrint(
        '[MbtilesDownload] 🧹 clearPreviousData — wiping prior download files '
        'before new connection',
      );
      try {
        await _cancelAllMbtilesTasks();
      } catch (_) {}
      _backgroundTask = null;
      await _wipePreviousMbtilesDownloadArtifacts(preservePartials: false);
      await _clearMaxBytesCheckpoint();
      _lastGoodProgress = 0.0;
      _lastLiveTempBytes = 0;
      _lastWatchedProgress = 0.0;
      _lastWatchedBytes = 0;
      downloadProgress.value = 0.0;
      downloadedBytes.value = 0;
    }

    // Prefer resuming an existing incomplete / failed-but-resumable task over
    // wiping offline_tiles and starting from 0% again (common after retry /
    // screen revisit / Xiaomi killing the worker mid-download).
    // Skip when clearPreviousData — caller already decided resume failed.
    var mustHardWipe = clearPreviousData;
    if (!clearPreviousData) {
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
              await _markDownloadInProgress();
              hasError.value = false;
              isCompleted.value = false;
              _applyProgress(record.progress);
              await _seedProgressFromPartialFileIfNeeded();
              debugPrint(
                '[MbtilesDownload] ▶️ Reusing existing WorkManager task '
                '${task.taskId} (${record.status}) at '
                '${(downloadProgress.value * 100).toStringAsFixed(1)}%',
              );

              if (record.status == TaskStatus.paused ||
                  failedButMaybeResumable) {
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
                // Resume metadata missing — plant from on-disk partial.
                if (await _resumeFromOnDiskPartial(task)) {
                  _setStatusText('mbtiles_status_resuming');
                  _startAndroidProgressPolling();
                  return null;
                }
                if (failedButMaybeResumable) {
                  debugPrint(
                    '[MbtilesDownload] ⚠️ Failed task not resumable via '
                    'plugin — wipe + fresh enqueue',
                  );
                  mustHardWipe = true;
                  // Fall through to hard wipe + enqueue below.
                } else {
                  _setStatusText('mbtiles_status_resuming');
                  _startAndroidProgressPolling();
                  return null;
                }
              } else {
                // Already "running" — but may be a hung Range / dead URLSession.
                await _markDownloadInProgress();
                if (_looksLikeZombieRunning(
                  status: record.status,
                  pluginProgress: record.progress,
                )) {
                  debugPrint(
                    '[MbtilesDownload] 🧟 Reused task looks frozen — force resume',
                  );
                  _startAndroidProgressPolling();
                  final ok = await _tryAutoResume(
                    reason: 'reuse_zombie',
                    force: true,
                  );
                  if (ok) {
                    _armStaleRunningWatchdog(reason: 'reuse_zombie');
                    return null;
                  }
                  // Resume failed — wipe before fresh enqueue.
                  mustHardWipe = true;
                } else {
                  _setStatusText('mbtiles_status_downloading');
                  _updateGbStatusFromBytes(
                    math.max(_lastLiveTempBytes, downloadedBytes.value),
                  );
                  _startAndroidProgressPolling();
                  _armStaleRunningWatchdog(reason: 'reuse_running');
                  return null;
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[MbtilesDownload] ⚠️ Could not check existing tasks: $e');
      }
    }

    // Soft prepare keeps temps for Range resume. Hard wipe when reconnection
    // / resume already failed and we are opening a new download connection.
    if (mustHardWipe) {
      await _wipePreviousMbtilesDownloadArtifacts(preservePartials: false);
      await _resetStaleProgress('new connection after failed resume');
    } else {
      await _wipePreviousMbtilesDownloadArtifacts(preservePartials: true);
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
      await _markDownloadInProgress();
      hasError.value = false;
      isCompleted.value = false;
      // Keep last good % when retrying with a partial file already on disk.
      // Never force UI back to 0% — that caused the bouncing progress bar.
      await _seedProgressFromPartialFileIfNeeded();
      // Seed total to the known 4.5 GB package size for the status label.
      if (totalBytes.value <= 0 ||
          totalBytes.value < (_approxExpectedBytes * 0.85).round() ||
          totalBytes.value > (_approxExpectedBytes * 1.15).round()) {
        totalBytes.value = _approxExpectedBytes;
      }
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

      // Create tiles directory if needed. Never wipe the whole folder (that
      // deleted style.json). Only clear tiny/orphan incomplete tile files.
      if (!await tilesDir.exists()) {
        await tilesDir.create(recursive: true);
        debugPrint('[MbtilesDownload] 📁 Created tiles directory: ${tilesDir.path}');
      } else {
        final partialFile = File('${tilesDir.path}/$LOCAL_MBTILES_FILENAME');
        final partialBytes =
            await partialFile.exists() ? await partialFile.length() : 0;
        final keepPartial =
            !mustHardWipe && partialBytes > 1024 * 1024; // >1MB

        if (keepPartial) {
          debugPrint(
            '[MbtilesDownload] ♻️ Keeping partial $LOCAL_MBTILES_FILENAME '
            '($partialBytes bytes) — will resume instead of wiping',
          );
          await _seedProgressFromPartialFileIfNeeded();
        } else {
          // Clear orphan temps / incomplete destination — never wipe the
          // whole offline_tiles folder (that deleted style.json).
          await _clearOrphanFailedDownloadFiles(keepActivePartial: false);
          if (!await tilesDir.exists()) {
            await tilesDir.create(recursive: true);
          }
          try {
            if (await partialFile.exists()) {
              final len = await partialFile.length();
              if (len > 0) {
                await partialFile.delete();
                debugPrint(
                  '[MbtilesDownload] 🗑️ Deleted incomplete '
                  '$LOCAL_MBTILES_FILENAME ($len bytes)',
                );
              }
            }
          } catch (e) {
            debugPrint(
              '[MbtilesDownload] ⚠️ Error deleting incomplete mbtiles: $e',
            );
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
    _cancelStaleRunningWatchdog();
    if (_backgroundTask != null) {
      await FileDownloader().cancelTaskWithId(_backgroundTask!.taskId);
      debugPrint('[MbtilesDownload] ❌ Download cancelled');
      _setStatusText('mbtiles_status_download_cancelled');
      isDownloading.value = false;
      _backgroundTask = null;
      _stopAndroidProgressPolling();
    }
    // A cancel discards the download: drop temps, resume data and the
    // persisted checkpoint so a relaunch starts clean at 0%, not at a ghost %.
    await _clearDownloadInProgress();
    await _wipePreviousMbtilesDownloadArtifacts(preservePartials: false);
    await _resetStaleProgress('user cancel');
    _setStatusText('mbtiles_status_download_cancelled');
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

