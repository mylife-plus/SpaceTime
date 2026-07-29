import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;

import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/filter/controllers/filter_controller.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/models/kmz_ignore_rule.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_import_pipeline.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/track_cluster_field_config.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_kml_inspector.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_kml_parser.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/views/kmz_ignore_rule_editor_view.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/views/kmz_past_uploads_view.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/spacetime_backup_zip.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/track_preview_geocode.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/views/kmz_preview_view.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/utils/memory_sort.dart';
import 'package:spacetime/app/widgets/app_date_time_pickers.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'package:spacetime/services/memory_import_blocking_controller.dart';

/// KMZ import: parse → filter → cluster → preview stats; upload runs geocode + DB.
class GpxKmzUploadController extends GetxController {
  final TextEditingController filePathController = TextEditingController();
  final TextEditingController ignoreMarkerController = TextEditingController();
  final TextEditingController ignoreContainsController =
      TextEditingController();

  final RxString selectedMinTimeApartKey =
      TrackClusterFieldConfig
          .minTimeApartOptionKeys[TrackClusterFieldConfig
              .defaultClusterOptionIndex]
          .obs;
  final RxString selectedMinMeterApartKey =
      TrackClusterFieldConfig
          .minMeterApartOptionKeys[TrackClusterFieldConfig
              .defaultClusterOptionIndex]
          .obs;
  final RxList<String> availableMemoryDateKeys = <String>[].obs;
  final RxString selectedStartDateKey = ''.obs;
  final RxString selectedEndDateKey = ''.obs;

  final RxInt pastUploadCount = 0.obs;

  final RxInt rawEntryCount = 0.obs;
  final RxInt ignoredEntryCount = 0.obs;
  final RxInt duplicateEntryCount = 0.obs;
  final RxInt totalEntryCount = 0.obs;
  final RxInt newMemoriesCount = 0.obs;

  final RxBool isBusy = false.obs;

  /// Full reverse-geocode pass before opening preview (upload screen shows overlay).
  final RxBool isPreparingPreviewLocations = false.obs;

  final RxList<KmzIgnoreRule> ignoreRules = <KmzIgnoreRule>[].obs;
  final Rxn<KmzFileInspect> kmzInspect = Rxn();

  KmzImportStats? _lastStats;
  String? _kmzPath;
  int _previewGeneration = 0;

  /// Parsed track points kept after the last full preview (ignore rules applied).
  List<KmzTrackPoint> _cachedFilteredPoints = const [];
  int _cachedRawPointCount = 0;
  int _cachedIgnoredByRules = 0;
  List<Map<String, dynamic>> _cachedDedupeRows = const [];
  Set<String> _cachedFingerprints = const {};

  /// Candidate fingerprints the user removed from the preview. They are skipped
  /// on commit and subtracted from the displayed new/remaining counts.
  /// `commitUploadToDatabase` re-derives candidates from the file, so this set
  /// must persist across [runPreview] to keep deletions effective.
  final Set<String> _excludedFingerprints = <String>{};

  /// True while [candidate] has been removed from the upload by the user.
  bool isCandidateExcluded(KmzMemoryCandidate candidate) =>
      _excludedFingerprints.contains(candidate.fingerprint);

  /// Remove a previewed memory from the upload: it won't be committed, and the
  /// new/remaining counts shown on the upload screen drop by one.
  void excludeCandidateFromUpload(KmzMemoryCandidate candidate) {
    if (_excludedFingerprints.add(candidate.fingerprint)) {
      _applyExclusionsToCounts();
    }
  }

  /// Subtract user-excluded candidates from the displayed new-memory count only.
  void _applyExclusionsToCounts() {
    if (_lastStats == null || _excludedFingerprints.isEmpty) return;
    final excluded =
        _lastStats!.candidates
            .where((c) => _excludedFingerprints.contains(c.fingerprint))
            .length;
    if (excluded == 0) return;
    newMemoriesCount.value = (_lastStats!.newMemories - excluded).clamp(
      0,
      1 << 30,
    );
  }

  Future<T> _retry<T>(Future<T> Function() fn, {String label = 'op'}) async {
    Object? last;
    for (var i = 0; i < 3; i++) {
      try {
        return await fn();
      } catch (e, st) {
        last = e;
        debugPrint('[GpxKmzUpload] $label retry ${i + 1}/3: $e\n$st');
        if (i < 2) {
          await Future<void>.delayed(Duration(milliseconds: 300 * (i + 1)));
        }
      }
    }
    throw last ?? Exception('$label failed');
  }

  @override
  void onInit() {
    super.onInit();
    if (!Get.isRegistered<GeocodingIsolateService>()) {
      Get.put(GeocodingIsolateService(), permanent: true);
    }
    ignoreMarkerController.text = '';
    ignoreContainsController.text = '';
  }

  Future<void> _refreshInspect() async {
    final path = _kmzPath ?? '';
    if (path.isEmpty || !await File(path).exists()) {
      kmzInspect.value = null;
      return;
    }
    kmzInspect.value = await KmzKmlInspector.inspectFromPath(path);
  }

  @override
  void onReady() {
    super.onReady();
    _reloadPastUploadCount();
  }

  Future<void> _reloadPastUploadCount() async {
    try {
      pastUploadCount.value = await DatabaseHelper.instance
          .countTrackImportLogs(
            importSource: DatabaseHelper.trackImportSourceGpxKmz,
          );
    } catch (e) {
      debugPrint('[GpxKmzUpload] past upload count: $e');
    }
  }

  Future<void> refreshPastUploadCount() => _reloadPastUploadCount();

  /// Reload duplicate detection after memories are deleted or erased.
  Future<void> reloadDedupeFromDatabase() async {
    if (_kmzPath != null && filePathController.text.trim().isNotEmpty) {
      await _refreshDedupeAndRecomputeFromCache();
    } else {
      duplicateEntryCount.value = 0;
    }
  }

  /// Opens picker once when entering from Settings (no file yet).
  Future<void> pickKmzFileFromSettingsEntry() async {
    if (_kmzPath != null && _kmzPath!.isNotEmpty) return;
    await pickKmzFile();
  }

  Future<void> pickKmzFile() async {
    // iOS: custom UTIs hide most rows in the picker's Recents vs the Files app.
    // public.item (FileType.any) matches system Recents; we filter by extension.
    final FilePickerResult? result =
        Platform.isIOS
            ? await FilePicker.platform.pickFiles(
              type: FileType.any,
              withData: false,
              withReadStream: false,
            )
            : await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: const ['kmz', 'gpx', 'zip'],
              withData: false,
              withReadStream: false,
            );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (!_isSupportedTrackFileName(f.name)) {
      _showInvalidTrackFileSnackbar();
      return;
    }
    if (SpaceTimeBackupZip.isBackupFileName(f.name)) {
      _showInvalidTrackFileSnackbar();
      return;
    }
    final path = f.path;
    if (path != null && path.isNotEmpty) {
      if (await SpaceTimeBackupZip.isBackupZipFile(path)) {
        _showInvalidTrackFileSnackbar();
        return;
      }
      _kmzPath = path;
      _excludedFingerprints.clear(); // fresh file → no carried-over deletions
      // Force From/To to this file's full range on first parse.
      selectedStartDateKey.value = '';
      selectedEndDateKey.value = '';
      filePathController.text = p.basename(path);
    } else if (f.name.isNotEmpty) {
      filePathController.text = f.name;
    }
    try {
      await runPreview();
    } on InvalidTrackFileException {
      clearImportedFileAndResetView();
      _showInvalidTrackFileSnackbar();
    }
  }

  static bool _isSupportedTrackFileName(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.kmz') || n.endsWith('.gpx') || n.endsWith('.zip');
  }

  void _showInvalidTrackFileSnackbar() {
    showTrSnackbar(
      'gpx_snackbar_invalid_track_file',
      backgroundColor: Colors.orange,
      colorText: Colors.white,
    );
  }

  Future<void> runPreview() async {
    final path = _kmzPath ?? '';
    if (path.isEmpty || !await File(path).exists()) {
      _applyEmptyStats();
      return;
    }

    final gen = ++_previewGeneration;
    isBusy.value = true;
    try {
      await _retry(_refreshInspect, label: 'inspect');
      if (gen != _previewGeneration) return;
      final useRules = ignoreRules.isNotEmpty;
      final rawPts = await _retry(
        () => KmzImportPipeline.loadPointsFiltered(
          path,
          ignoreMarkerSub: '',
          ignoreContainsSub: '',
          structuredRules: const [],
        ),
        label: 'loadPointsRaw',
      );
      if (gen != _previewGeneration) return;
      if (rawPts.isEmpty) {
        throw InvalidTrackFileException('empty');
      }
      final pts = await _retry(
        () => KmzImportPipeline.loadPointsFiltered(
          path,
          ignoreMarkerSub: useRules ? '' : ignoreMarkerController.text,
          ignoreContainsSub: useRules ? '' : ignoreContainsController.text,
          structuredRules: ignoreRules.toList(),
        ),
        label: 'loadPointsFiltered',
      );
      if (gen != _previewGeneration) return;
      final dateKeys = _extractDateKeys(pts);
      _syncDateSelection(dateKeys);
      final ignoredByRules = (rawPts.length - pts.length).clamp(0, 1 << 30);
      final rows =
          await DatabaseHelper.instance.queryMemoriesTrackImportDedupeRows();
      final fpSet = <String>{};
      for (final r in rows) {
        final fp = r[DatabaseHelper.columnTrackImportFingerprint] as String?;
        if (fp != null && fp.isNotEmpty) fpSet.add(fp);
      }

      _cachedFilteredPoints = pts;
      _cachedRawPointCount = rawPts.length;
      _cachedIgnoredByRules = ignoredByRules;
      _cachedDedupeRows = rows;
      _cachedFingerprints = fpSet;

      if (gen != _previewGeneration) return;
      _applyClusterStatsFromCache(gen);
    } on InvalidTrackFileException {
      _applyEmptyStats();
      rethrow;
    } catch (e, st) {
      debugPrint('[GpxKmzUpload] preview error: $e\n$st');
      showTrSnackbar(
        'gpx_snackbar_preview_error',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
      _applyEmptyStats();
    } finally {
      isBusy.value = false;
    }
  }

  void _clearImportedTrackFile() {
    _kmzPath = null;
    filePathController.clear();
    kmzInspect.value = null;
    _applyEmptyStats();
  }

  /// Clears the selected KMZ/GPX file and resets preview stats on screen.
  void clearImportedFileAndResetView() {
    _previewGeneration++;
    _clearImportedTrackFile();
  }

  /// Rebuild clustering / new-memory counts from cached parse results when only
  /// min time, min distance, or date range changes (no file reload).
  void recomputeClusterStats() {
    _applyClusterStatsFromCache(_previewGeneration);
  }

  /// Refresh DB dedupe fingerprints and rebuild cluster stats from the cached
  /// parse. Prefer this over [runPreview] for Preview/Upload so memory-creation
  /// settings (min time, min distance, date range) are not wiped by a reload.
  Future<void> _refreshDedupeAndRecomputeFromCache() async {
    if (_cachedFilteredPoints.isEmpty) {
      await runPreview();
      return;
    }
    final rows =
        await DatabaseHelper.instance.queryMemoriesTrackImportDedupeRows();
    final fpSet = <String>{};
    for (final r in rows) {
      final fp = r[DatabaseHelper.columnTrackImportFingerprint] as String?;
      if (fp != null && fp.isNotEmpty) fpSet.add(fp);
    }
    _cachedDedupeRows = rows;
    _cachedFingerprints = fpSet;
    recomputeClusterStats();
  }

  void _applyClusterStatsFromCache(int gen) {
    if (gen != _previewGeneration) return;
    if (_cachedFilteredPoints.isEmpty) {
      if (_kmzPath == null || _kmzPath!.isEmpty) {
        _applyEmptyStats();
      } else {
        newMemoriesCount.value = 0;
        _lastStats = null;
      }
      return;
    }

    final filteredByDate = _filterPointsBySelectedDateRange(
      _cachedFilteredPoints,
    );
    final minT = KmzImportPipeline.durationForTimeKey(
      selectedMinTimeApartKey.value,
    );
    final minM = KmzImportPipeline.metersForDistanceKey(
      selectedMinMeterApartKey.value,
    );

    _lastStats = KmzImportPipeline.buildStats(
      points: filteredByDate,
      minTimeApart: minT,
      minMetersApart: minM,
      existingFingerprints: _cachedFingerprints,
      existingCoordinateRows: _cachedDedupeRows,
    );

    rawEntryCount.value = _cachedRawPointCount;
    // Ignored = ignore rules only. Date range affects new memories.
    // Duplicate entries = per-point DB matches (stable when clustering changes).
    ignoredEntryCount.value = _cachedIgnoredByRules;
    duplicateEntryCount.value = _lastStats!.duplicateEntries;
    totalEntryCount.value = (rawEntryCount.value -
            ignoredEntryCount.value -
            duplicateEntryCount.value)
        .clamp(0, 1 << 30);
    newMemoriesCount.value = _lastStats!.newMemories;
    _applyExclusionsToCounts();
  }

  void _applyEmptyStats() {
    _lastStats = null;
    _cachedFilteredPoints = const [];
    _cachedRawPointCount = 0;
    _cachedIgnoredByRules = 0;
    _cachedDedupeRows = const [];
    _cachedFingerprints = const {};
    _excludedFingerprints.clear();
    availableMemoryDateKeys.clear();
    selectedStartDateKey.value = '';
    selectedEndDateKey.value = '';
    rawEntryCount.value = 0;
    ignoredEntryCount.value = 0;
    duplicateEntryCount.value = 0;
    totalEntryCount.value = 0;
    newMemoriesCount.value = 0;
  }

  Future<void> commitUploadToDatabase() async {
    final path = _kmzPath ?? '';
    if (path.isEmpty || !await File(path).exists()) {
      showTrSnackbar(
        'snackbar_validation_error_35',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    await _refreshDedupeAndRecomputeFromCache();
    if (_lastStats == null || _lastStats!.candidates.isEmpty) {
      showTrSnackbar(
        'gpx_snackbar_nothing_to_import',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    if (!Get.isRegistered<MemoryController>()) {
      showTrSnackbar(
        'gpx_snackbar_memory_controller_missing',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return;
    }

    final importBlock = Get.find<MemoryImportBlockingController>();
    importBlock.importing.value = true;
    isBusy.value = true;
    final mem = Get.find<MemoryController>();
    final fpLive = <String>{..._cachedFingerprints};

    var inserted = 0;
    var dupRuntime = 0;
    final insertedItems = <Map<String, dynamic>>[];

    try {
      for (final c in _lastStats!.candidates) {
        if (_excludedFingerprints.contains(c.fingerprint)) {
          continue; // user removed this one in the preview
        }
        if (fpLive.contains(c.fingerprint)) {
          dupRuntime++;
          continue;
        }
        try {
          final memoryId = await mem.saveImportedTrackMemory(
            when: c.when,
            latitude: c.latitude,
            longitude: c.longitude,
            description: '',
            trackImportFingerprint: c.fingerprint,
          );
          fpLive.add(c.fingerprint);
          inserted++;
          insertedItems.add({
            DatabaseHelper.columnTrackLogItemWhen:
                c.when.toUtc().toIso8601String(),
            DatabaseHelper.columnTrackLogItemLat: c.latitude,
            DatabaseHelper.columnTrackLogItemLng: c.longitude,
            DatabaseHelper.columnTrackLogItemLocation: 'Region',
            DatabaseHelper.columnTrackLogItemMemoryId: memoryId,
          });
        } catch (e) {
          debugPrint('[GpxKmzUpload] skip row: $e');
        }
      }

      final fileName = p.basename(path);
      final logId = await DatabaseHelper.instance.insertTrackImportLog(
        fileName: fileName,
        rawCount: _lastStats!.rawEntries,
        ignoredCount: ignoredEntryCount.value,
        dupCount: _lastStats!.duplicateEntries + dupRuntime,
        newCount: inserted,
        importSource: DatabaseHelper.trackImportSourceGpxKmz,
      );
      await DatabaseHelper.instance.insertTrackImportLogItems(
        logId: logId,
        items: insertedItems,
      );

      await _reloadPastUploadCount();

      if (Get.isRegistered<FilterController>()) {
        Get.find<FilterController>().resetFiltersExceptSearch();
      }
      if (Get.isRegistered<AddMemoriesController>()) {
        await Get.find<AddMemoriesController>().loadMemoriesFromDatabase();
      }
      if (Get.isRegistered<MapControllerNew>() &&
          Get.isRegistered<FilterController>()) {
        final map = Get.find<MapControllerNew>();
        try {
          await map.reloadDisplayedMemoriesWithRetry();
          // Focus on the globally latest memory (not just within this import)
          unawaited(map.focusOnLatestMemory());
        } catch (e, st) {
          debugPrint('[GpxKmzUpload] map reload after import: $e\n$st');
        }
      }

      showTrSnackbar(
        'gpx_snackbar_import_done',
        args: [inserted],
        backgroundColor: Colors.green.shade700,
        colorText: Colors.white,
      );

      if (inserted > 0) {
        _clearImportedTrackFile();
        await Future<void>.delayed(const Duration(milliseconds: 450));
        Get.back<void>();
      } else {
        await _refreshDedupeAndRecomputeFromCache();
      }
    } catch (e, st) {
      debugPrint('[GpxKmzUpload] upload error: $e\n$st');
      showTrSnackbar(
        'gpx_snackbar_preview_error',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
    } finally {
      importBlock.importing.value = false;
      isBusy.value = false;
    }
  }

  Future<void> onPreviewTap() async {
    final path = _kmzPath ?? '';
    if (path.isEmpty || !await File(path).exists()) {
      showTrSnackbar(
        'gpx_snackbar_nothing_to_import',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    // Use current memory-creation settings from cache — do not re-parse the
    // file (that used to reset From/To dates via [_syncDateSelection]).
    await _refreshDedupeAndRecomputeFromCache();
    final stats = _lastStats;
    final previewCandidates = stats == null
        ? const <KmzMemoryCandidate>[]
        : stats.candidates
            .where((c) => !_excludedFingerprints.contains(c.fingerprint))
            .toList();
    if (previewCandidates.isEmpty) {
      showTrSnackbar(
        'gpx_snackbar_nothing_to_import',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    final sorted = MemorySort.sortedByWhenNewestFirst(
      previewCandidates,
      (c) => c.when,
    );
    final coords =
        sorted.map((e) => (lat: e.latitude, lng: e.longitude)).toList();
    try {
      isPreparingPreviewLocations.value = true;
      final lines = await resolveTrackPreviewLocationLinesOrdered(coords);
      await Get.to<void>(
        () => KmzPreviewView(candidates: sorted, locationLines: lines),
      );
    } catch (e, st) {
      debugPrint('[GpxKmzUpload] preview geocode: $e\n$st');
      showTrSnackbar(
        'gpx_snackbar_preview_error',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
    } finally {
      isPreparingPreviewLocations.value = false;
    }
  }

  List<String> _extractDateKeys(List<KmzTrackPoint> pts) {
    final set = <String>{};
    for (final p in pts) {
      if (!p.hasSourceTimestamp) continue;
      final when = p.when;
      if (when == null) continue;
      set.add(_dateKeyFromDateTime(when.toLocal()));
    }
    // Same-day / no-<time> GPX: fall back to normalized when so From/To are set.
    if (set.isEmpty) {
      for (final p in pts) {
        final when = p.when;
        if (when == null) continue;
        set.add(_dateKeyFromDateTime(when.toLocal()));
      }
    }
    final out = set.toList()..sort();
    return out;
  }

  void _syncDateSelection(List<String> keys) {
    availableMemoryDateKeys.value = keys;
    if (keys.isEmpty) {
      selectedStartDateKey.value = '';
      selectedEndDateKey.value = '';
      return;
    }
    // Default to full file range when unset (first pick / same-day tracks).
    // Preserve a user-narrowed From/To across re-parse so Preview/Upload keep
    // the same memory-creation settings shown on screen.
    if (selectedStartDateKey.value.isEmpty ||
        !keys.contains(selectedStartDateKey.value)) {
      selectedStartDateKey.value = keys.first;
    }
    if (selectedEndDateKey.value.isEmpty ||
        !keys.contains(selectedEndDateKey.value)) {
      selectedEndDateKey.value = keys.last;
    }
    if (selectedStartDateKey.value.compareTo(selectedEndDateKey.value) > 0) {
      selectedEndDateKey.value = keys.last;
    }
  }

  List<KmzTrackPoint> _filterPointsBySelectedDateRange(
    List<KmzTrackPoint> pts,
  ) {
    final startKey = selectedStartDateKey.value;
    final endKey = selectedEndDateKey.value;
    if (startKey.isEmpty || endKey.isEmpty) return pts;
    return pts.where((p) {
      final w = p.when;
      if (w == null) return false;
      final key = _dateKeyFromDateTime(w.toLocal());
      return key.compareTo(startKey) >= 0 && key.compareTo(endKey) <= 0;
    }).toList();
  }

  String _dateKeyFromDateTime(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  String formatDateKeyForUi(String key) {
    if (key.length != 10) return key;
    return '${key.substring(8, 10)}.${key.substring(5, 7)}.${key.substring(0, 4)}';
  }

  DateTime? _dateFromKey(String key) {
    if (key.length != 10) return null;
    final y = int.tryParse(key.substring(0, 4));
    final m = int.tryParse(key.substring(5, 7));
    final d = int.tryParse(key.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  Future<void> pickStartDate(BuildContext context) async {
    final keys = availableMemoryDateKeys;
    if (keys.isEmpty) return;
    final first = _dateFromKey(keys.first);
    final last = _dateFromKey(keys.last);
    final initial = _dateFromKey(selectedStartDateKey.value) ?? first;
    if (first == null || last == null || initial == null) return;
    final picked = await showAppDatePicker(
      context: context,
      initialDate:
          initial.isBefore(first)
              ? first
              : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    onStartDateChanged(_dateKeyFromDateTime(picked));
  }

  Future<void> pickEndDate(BuildContext context) async {
    final keys = availableMemoryDateKeys;
    if (keys.isEmpty) return;
    final first = _dateFromKey(keys.first);
    final last = _dateFromKey(keys.last);
    final initial = _dateFromKey(selectedEndDateKey.value) ?? last;
    if (first == null || last == null || initial == null) return;
    final picked = await showAppDatePicker(
      context: context,
      initialDate:
          initial.isBefore(first)
              ? first
              : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    onEndDateChanged(_dateKeyFromDateTime(picked));
  }

  void onStartDateChanged(String key) {
    selectedStartDateKey.value = key;
    if (selectedEndDateKey.value.isEmpty ||
        selectedEndDateKey.value.compareTo(key) < 0) {
      selectedEndDateKey.value =
          availableMemoryDateKeys.isEmpty ? key : availableMemoryDateKeys.last;
    }
    recomputeClusterStats();
  }

  void onEndDateChanged(String key) {
    selectedEndDateKey.value = key;
    if (selectedStartDateKey.value.isEmpty ||
        selectedStartDateKey.value.compareTo(key) > 0) {
      selectedStartDateKey.value =
          availableMemoryDateKeys.isEmpty ? key : availableMemoryDateKeys.first;
    }
    recomputeClusterStats();
  }

  Future<void> onPastUploadsTap() async {
    await Get.to<void>(
      () => const KmzPastUploadsView(
        importSource: DatabaseHelper.trackImportSourceGpxKmz,
      ),
    );
    await _reloadPastUploadCount();
    await reloadDedupeFromDatabase();
  }

  Future<void> onAddIgnoreRuleTap() async {
    try {
      final path = _kmzPath ?? '';
      await _refreshInspect();
      if (path.isEmpty ||
          !await File(path).exists() ||
          kmzInspect.value == null) {
        showTrSnackbar(
          'gpx_ignore_snackbar_need_file',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
        return;
      }
      final rule = await Get.to<KmzIgnoreRule?>(
        () => KmzIgnoreRuleEditorView(inspect: kmzInspect.value!),
      );
      if (rule != null) {
        ignoreRules.add(rule);
        await runPreview();
      }
    } catch (e, st) {
      debugPrint('[GpxKmzUpload] add ignore rule error: $e\n$st');
      showTrSnackbar(
        'gpx_snackbar_preview_error',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
    }
  }

  void onIgnoreHelpTap() {
    Get.dialog<void>(
      AlertDialog(
        title: Text('gpx_ignore_help_title'.tr),
        content: SingleChildScrollView(child: Text('gpx_ignore_help_body'.tr)),
        actions: [
          TextButton(
            onPressed: () => Get.back<void>(),
            child: Text('text_ok'.tr),
          ),
        ],
      ),
    );
  }

  void removeIgnoreRuleAt(int index) {
    if (index < 0 || index >= ignoreRules.length) return;
    ignoreRules.removeAt(index);
    runPreview();
  }

  @override
  void onClose() {
    filePathController.dispose();
    ignoreMarkerController.dispose();
    ignoreContainsController.dispose();
    super.onClose();
  }
}
