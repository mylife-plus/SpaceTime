import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/filter/controllers/filter_controller.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/track_cluster_field_config.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_import_pipeline.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/track_preview_geocode.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/services/kmz_kml_parser.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_cluster_candidate.dart';
import 'package:spacetime/app/modules/media_gps_upload/models/media_gps_picked_asset.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/capture_time_dedupe_log.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_file_import_service.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_gallery_permission.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_gallery_service.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_import_storage_service.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/media_gps_gallery_picker_view.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/media_gps_preview_view.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/utils/concurrency.dart';
import 'package:spacetime/services/app_lock_controller.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'package:spacetime/services/memory_import_blocking_controller.dart';
import 'package:spacetime/app/utils/memory_sort.dart';
import 'package:spacetime/app/widgets/app_date_time_pickers.dart';

class MediaGpsUploadController extends GetxController {
  /// Max parallel gallery exports / geocodes in flight during a bulk upload.
  static const int _uploadConcurrency = 6;

  final RxBool isBusy = false.obs;
  final RxBool isPreparingPreviewLocations = false.obs;
  final RxBool galleryLoading = false.obs;
  final RxBool filesImporting = false.obs;
  /// True when OS grants only partial / “limited” library access (iOS + newer Android).
  final RxBool photoLibraryLimitedAccess = false.obs;
  final RxList<MediaGpsPickedAsset> galleryAssets = <MediaGpsPickedAsset>[].obs;
  final RxSet<String> selectedAssetIds = <String>{}.obs;
  final Rxn<int> galleryFocusCellIndex = Rxn<int>();

  final RxString selectedMinTimeApartKey =
      TrackClusterFieldConfig.minTimeApartOptionKeys[
              TrackClusterFieldConfig.defaultClusterOptionIndex]
          .obs;
  final RxString selectedMinMeterApartKey =
      TrackClusterFieldConfig.minMeterApartOptionKeys[
              TrackClusterFieldConfig.defaultClusterOptionIndex]
          .obs;

  final RxList<String> availableDateKeys = <String>[].obs;
  final RxString selectedStartDateKey = ''.obs;
  final RxString selectedEndDateKey = ''.obs;

  final RxInt rawFileCount = 0.obs;
  final RxInt ignoredEntryCount = 0.obs;
  final RxInt duplicateHintCount = 0.obs;
  final RxInt noGpsCount = 0.obs;
  final RxInt totalEntryCount = 0.obs;
  final RxInt newMemoriesCount = 0.obs;
  final RxInt pastUploadLogCount = 0.obs;

  List<MediaGpsClusterCandidate> _lastCandidates = [];
  Set<String> _existingTrackFingerprints = <String>{};
  Set<String> _importedGalleryAssetIds = <String>{};
  Set<String> _importedGalleryMediaCreatedAtKeys = <String>{};
  List<Map<String, dynamic>> _existingCoordinateRows = const [];

  /// Long-press + drag bulk selection (gallery picker).
  bool _bulkDragActive = false;
  bool _bulkDragSelecting = true;
  int? _bulkDragLastIndex;
  Timer? _bulkRecomputeDebounce;

  /// After bulk drag ends, skip one tap so fullscreen doesn’t open on finger up.
  bool suppressGalleryCellTap = false;

  bool _autoDateRangeOnNextSync = false;

  int _galleryLoadGen = 0;

  @override
  void onClose() {
    _bulkRecomputeDebounce?.cancel();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    if (!Get.isRegistered<GeocodingIsolateService>()) {
      Get.put(GeocodingIsolateService(), permanent: true);
    }
    _reloadPastPlaceholder();
  }

  @override
  void onReady() {
    super.onReady();
    _reloadPastPlaceholder();
    ensureGalleryLoaded();
    _refreshDedupeDataAndRecompute();
  }

  /// Reload imported gallery ids from DB (e.g. after saving a memory elsewhere).
  Future<void> reloadDedupeFromDatabase() => _refreshDedupeDataAndRecompute();

  bool isGalleryAssetAlreadyImported(String assetId) =>
      _importedGalleryAssetIds.contains(assetId);

  bool _isPickedAssetAlreadyImported(MediaGpsPickedAsset asset) {
    if (asset.id.isNotEmpty &&
        _importedGalleryAssetIds.contains(asset.id)) {
      return true;
    }
    if (!asset.isImage && !asset.isVideo) return false;
    // Always match on media capture time + kind (not memory save time).
    // Asset ids often differ between Add Memories (file/EXIF) and GPS gallery
    // (PhotoManager), so time is the cross-flow signal.
    final kind = asset.isVideo ? 'video' : 'image';
    return _importedGalleryMediaCreatedAtKeys.contains(
      DatabaseHelper.mediaTimeKindDedupeKey(asset.createTime, kind),
    );
  }

  List<ImportedGalleryAssetRecord> _galleryRecordsForItems(
    Iterable<MediaGpsPickedAsset> items,
  ) {
    final seenIds = <String>{};
    final seenTimeKinds = <String>{};
    final out = <ImportedGalleryAssetRecord>[];
    for (final it in items) {
      if (!it.isImage && !it.isVideo) continue;
      final hasId = it.id.isNotEmpty;
      final kind = it.isVideo ? 'video' : 'image';
      final timeKindKey =
          DatabaseHelper.mediaTimeKindDedupeKey(it.createTime, kind);
      if (hasId) {
        if (!seenIds.add(it.id)) continue;
      } else {
        // Asset-less: keep one row per capture time + file type.
        if (!seenTimeKinds.add(timeKindKey)) continue;
      }
      out.add(
        ImportedGalleryAssetRecord(
          assetId: hasId ? it.id : null,
          mediaCreatedAt: it.createTime.toUtc(),
          mediaKind: kind,
        ),
      );
    }
    return out;
  }

  Future<void> _refreshDedupeDataAndRecompute() async {
    _existingTrackFingerprints = {};
    _existingCoordinateRows = [];
    _importedGalleryAssetIds = {};
    _importedGalleryMediaCreatedAtKeys = {};
    try {
      final rows = await DatabaseHelper.instance.queryMemoriesTrackImportDedupeRows();
      final fp = <String>{};
      for (final r in rows) {
        final v = r[DatabaseHelper.columnTrackImportFingerprint] as String?;
        if (v != null && v.isNotEmpty) fp.add(v);
      }
      _existingTrackFingerprints = fp;
      _existingCoordinateRows = rows;
      _importedGalleryAssetIds =
          await DatabaseHelper.instance.queryImportedGalleryAssetIds();
      _importedGalleryMediaCreatedAtKeys = await DatabaseHelper.instance
          .queryImportedGalleryMediaCreatedAtKeysForAssetlessRows();
    } catch (e, st) {
      debugPrint('[MediaGpsUpload] dedupe preload: $e\n$st');
    }
    recomputeStats();
  }

  Future<void> _reloadPastPlaceholder() async {
    try {
      pastUploadLogCount.value =
          await DatabaseHelper.instance.countTrackImportLogs(
        importSource: DatabaseHelper.trackImportSourceMediaGps,
      );
    } catch (_) {}
  }

  /// Call when opening the upload screen so past-upload count matches DB.
  Future<void> refreshPastUploadCount() => _reloadPastPlaceholder();

  Future<void> refreshPhotoLibraryAccessFlag() async {
    try {
      final ps = await PhotoManager.getPermissionState(
        requestOption: kMediaGpsGalleryPermissionRequest,
      );
      photoLibraryLimitedAccess.value = ps.isLimited;
    } catch (e, st) {
      debugPrint('[MediaGpsUpload] photo permission state: $e\n$st');
      photoLibraryLimitedAccess.value = false;
    }
  }

  /// Call after returning from system Settings so lists match new library access.
  Future<void> onAppResumedRefreshGallery() async {
    await refreshPhotoLibraryAccessFlag();
    await ensureGalleryLoaded(force: true);
  }

  Future<void> openSystemPhotoLibrarySettings() async {
    if (Get.isRegistered<AppLockController>()) {
      await Get.find<AppLockController>().openExternalSettings(
        PhotoManager.openSetting,
      );
    } else {
      await PhotoManager.openSetting();
    }
  }

  void _assignGalleryListPreservingFilePicks(List<MediaGpsPickedAsset> galleryList) {
    final filePicked =
        galleryAssets.where((a) => a.isFromFile).toList(growable: false);
    final byId = {for (final a in galleryList) a.id: a};
    for (final a in filePicked) {
      byId[a.id] = a;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.createTime.compareTo(a.createTime));
    galleryAssets.assignAll(merged);
  }

  Future<void> ensureGalleryLoaded({bool force = false}) async {
    if (!force && galleryAssets.isNotEmpty) return;

    final gen = ++_galleryLoadGen;
    galleryLoading.value = true;
    try {
      // Android: ensure ACCESS_MEDIA_LOCATION before EXIF GPS reads.
      await MediaGpsGalleryService.ensureMediaLocationAccess();
      if (gen != _galleryLoadGen) return;

      List<MediaGpsPickedAsset> list = const [];
      for (var attempt = 0; attempt < 2; attempt++) {
        list = await MediaGpsGalleryService.loadRecentAssets(
          onProgress: (snapshot) {
            if (gen != _galleryLoadGen) return;
            _assignGalleryListPreservingFilePicks(snapshot);
          },
          onFirstBatchDone: () {
            if (gen != _galleryLoadGen) return;
            galleryLoading.value = false;
          },
        );
        if (gen != _galleryLoadGen) return;
        if (list.isNotEmpty) break;
        debugPrint(
          '[MediaGpsUpload] gallery load empty — retry ${attempt + 1}',
        );
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
      if (gen != _galleryLoadGen) return;
      _assignGalleryListPreservingFilePicks(list);
      await _refreshDedupeDataAndRecompute();
      recomputeStats();
      await refreshPhotoLibraryAccessFlag();
    } catch (e, st) {
      debugPrint('[MediaGpsUpload] gallery load: $e\n$st');
      if (gen == _galleryLoadGen) {
        showTrSnackbar(
          'media_gps_snackbar_gallery_failed',
          backgroundColor: Colors.red.shade700,
          colorText: Colors.white,
        );
      }
      if (gen == _galleryLoadGen) {
        await refreshPhotoLibraryAccessFlag();
      }
    } finally {
      if (gen == _galleryLoadGen) {
        galleryLoading.value = false;
      }
    }
  }

  void _markSelectionChanged() {
    _autoDateRangeOnNextSync = true;
  }

  static String _dateKeyFromDateTime(DateTime d) {
    final l = d.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-'
        '${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  List<String> _sortedDateKeysFromAssets(Iterable<MediaGpsPickedAsset> assets) {
    final set = <String>{};
    for (final a in assets) {
      set.add(_dateKeyFromDateTime(a.createTime));
    }
    return set.toList()..sort();
  }

  /// Start/end bounds and picker keys come from selected media that will actually
  /// upload: has GPS, not already imported, and not dropped as duplicate clusters.
  void _syncDateKeysFromRemainingAssets(Iterable<MediaGpsPickedAsset> remaining) {
    final keys = _sortedDateKeysFromAssets(remaining);
    availableDateKeys.value = keys;
    if (keys.isEmpty) {
      selectedStartDateKey.value = '';
      selectedEndDateKey.value = '';
      return;
    }
    if (_autoDateRangeOnNextSync) {
      _autoDateRangeOnNextSync = false;
      selectedStartDateKey.value = keys.first;
      selectedEndDateKey.value = keys.last;
      return;
    }
    if (!keys.contains(selectedStartDateKey.value)) {
      selectedStartDateKey.value = keys.first;
    }
    if (!keys.contains(selectedEndDateKey.value)) {
      selectedEndDateKey.value = keys.last;
    }
    if (selectedStartDateKey.value.compareTo(selectedEndDateKey.value) > 0) {
      selectedEndDateKey.value = keys.last;
    }
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

  String? _nearestDateKey(DateTime picked, {required bool forStart}) {
    final keys = availableDateKeys;
    if (keys.isEmpty) return null;
    final pickedKey = _dateKeyFromDateTime(picked);
    if (keys.contains(pickedKey)) return pickedKey;
    if (forStart) {
      for (final k in keys) {
        if (k.compareTo(pickedKey) >= 0) return k;
      }
      return keys.last;
    }
    for (var i = keys.length - 1; i >= 0; i--) {
      if (keys[i].compareTo(pickedKey) <= 0) return keys[i];
    }
    return keys.first;
  }

  Future<void> pickStartDate(BuildContext context) async {
    final keys = availableDateKeys.toList();
    if (keys.isEmpty) return;
    final first = _dateFromKey(keys.first);
    final last = _dateFromKey(keys.last);
    final initial = _dateFromKey(selectedStartDateKey.value) ?? first;
    if (first == null || last == null || initial == null) return;
    final navContext = Get.overlayContext ?? Get.context ?? context;
    final picked = await showAppDatePicker(
      context: navContext,
      initialDate:
          initial.isBefore(first) ? first : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    final key = _nearestDateKey(picked, forStart: true);
    if (key != null) onStartDateChanged(key);
  }

  Future<void> pickEndDate(BuildContext context) async {
    final keys = availableDateKeys.toList();
    if (keys.isEmpty) return;
    final first = _dateFromKey(keys.first);
    final last = _dateFromKey(keys.last);
    final initial = _dateFromKey(selectedEndDateKey.value) ?? last;
    if (first == null || last == null || initial == null) return;
    final navContext = Get.overlayContext ?? Get.context ?? context;
    final picked = await showAppDatePicker(
      context: navContext,
      initialDate:
          initial.isBefore(first) ? first : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;
    final key = _nearestDateKey(picked, forStart: false);
    if (key != null) onEndDateChanged(key);
  }

  void onStartDateChanged(String key) {
    selectedStartDateKey.value = key;
    if (selectedEndDateKey.value.isEmpty ||
        selectedEndDateKey.value.compareTo(key) < 0) {
      selectedEndDateKey.value =
          availableDateKeys.isEmpty ? key : availableDateKeys.last;
    }
    recomputeStats();
  }

  void onEndDateChanged(String key) {
    selectedEndDateKey.value = key;
    if (selectedStartDateKey.value.isEmpty ||
        selectedStartDateKey.value.compareTo(key) > 0) {
      selectedStartDateKey.value =
          availableDateKeys.isEmpty ? key : availableDateKeys.first;
    }
    recomputeStats();
  }

  Future<void> openGalleryPicker() async {
    final allowed = await ensureMediaGalleryPermissionForPickerNav();
    if (!allowed) return;
    // Open UI immediately; Limited Library + GPS scans can be slow if awaited here.
    unawaited(ensureGalleryLoaded(force: true));
    await Get.to<void>(() => const MediaGpsGalleryPickerView());
    _markSelectionChanged();
    recomputeStats();
  }

  /// System file browser — images, videos, and audio with GPS in file metadata.
  Future<void> pickFilesFromDevice() async {
    if (filesImporting.value) return;
    filesImporting.value = true;
    final appLock = Get.isRegistered<AppLockController>()
        ? Get.find<AppLockController>()
        : null;
    try {
      // The OS file picker sends the app to background/foreground; suppress the
      // PIN/biometric lock while it's open and re-arm it once it closes. We use
      // a picker session (not scheduleRestartOnNextResume) so the awaited picked
      // files survive — a restart would discard them.
      MediaGpsFileImportResult? result;
      appLock?.beginExternalPickerSession();
      try {
        result = await MediaGpsFileImportService.pickAndParse();
      } finally {
        appLock?.endExternalPickerSession();
      }
      if (result == null) return;

      if (result.withGps.isEmpty) {
        if (result.withoutGps > 0) {
          _showFilesWithoutGpsSnackbar(result.withoutGps);
        }
        return;
      }

      _mergeFilePickedAssets(result.withGps);
      for (final a in result.withGps) {
        CaptureTimeDedupeLog.logGalleryAsset(
          source: 'MediaGps.files',
          asset: a,
          alreadyImported: _isPickedAssetAlreadyImported(a),
        );
        final path = a.localPath;
        if (path != null && path.isNotEmpty) {
          unawaited(
            CaptureTimeDedupeLog.logPickedFile(
              source: 'MediaGps.files',
              path: path,
              mediaKind: a.isVideo ? 'video' : 'image',
              resolvedCaptureTime: a.createTime,
              galleryAssetId: a.id,
            ),
          );
        }
      }
      _markSelectionChanged();
      recomputeStats();

      if (result.withoutGps > 0) {
        _showFilesWithoutGpsSnackbar(result.withoutGps);
      }
      if (result.unsupported > 0) {
        showTrSnackbar(
          'media_gps_snackbar_unsupported_file_type',
          args: [result.unsupported.toString()],
          backgroundColor: Colors.orange.shade800,
          colorText: Colors.white,
          duration: const Duration(seconds: 3),
        );
      }
    } catch (e, st) {
      debugPrint('[MediaGpsUpload] pick files: $e\n$st');
      showTrSnackbar(
        'media_gps_snackbar_pick_failed',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
    } finally {
      filesImporting.value = false;
    }
  }

  /// Removes a file-picked asset (not a gallery asset) from the list.
  void removeFileAsset(String id) {
    galleryAssets.removeWhere((a) => a.id == id && a.isFromFile);
    selectedAssetIds.remove(id);
    _markSelectionChanged();
    recomputeStats();
  }

  void _mergeFilePickedAssets(List<MediaGpsPickedAsset> incoming) {
    if (incoming.isEmpty) return;
    final byId = {for (final a in galleryAssets) a.id: a};
    // Also index existing selection by time+GPS so re-picking the same photo
    // via a new staging path still counts as a duplicate.
    final existingMetaKeys = <String>{
      for (final a in galleryAssets)
        if (a.hasGps) _fileContentMetaKey(a),
    };
    var skippedDup = 0;
    for (final a in incoming) {
      if (byId.containsKey(a.id) ||
          (a.hasGps && existingMetaKeys.contains(_fileContentMetaKey(a)))) {
        skippedDup++;
        continue;
      }
      byId[a.id] = a;
      if (a.hasGps) existingMetaKeys.add(_fileContentMetaKey(a));
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.createTime.compareTo(a.createTime));
    galleryAssets.assignAll(merged);
    var limitHit = false;
    for (final a in incoming) {
      if (!byId.containsKey(a.id)) continue; // skipped as duplicate
      if (selectedAssetIds.contains(a.id)) continue;
      if (selectedAssetIds.length >= maxSelection) {
        limitHit = true;
        break;
      }
      selectedAssetIds.add(a.id);
    }
    selectedAssetIds.refresh();
    if (skippedDup > 0) {
      showTrSnackbar(
        'media_gps_snackbar_duplicate_files_skipped',
        args: [skippedDup.toString()],
        backgroundColor: Colors.orange.shade800,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
    if (limitHit) _showSelectionLimitSnackbar();
  }

  /// Stable key for detecting the same filesystem photo picked twice.
  String _fileContentMetaKey(MediaGpsPickedAsset a) {
    final t = a.createTime.toUtc().millisecondsSinceEpoch;
    final lat = (a.latitude ?? 0).toStringAsFixed(5);
    final lng = (a.longitude ?? 0).toStringAsFixed(5);
    final title = (a.fileTitle ?? '').toLowerCase();
    final kind = a.isVideo ? 'video' : (a.isImage ? 'image' : 'unknown');
    return '$t|$lat|$lng|$title|$kind';
  }

  void _showFilesWithoutGpsSnackbar(int count) {
    showTrSnackbar(
      'media_gps_snackbar_files_without_gps',
      args: [count.toString()],
      backgroundColor: Colors.orange.shade800,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  static const int maxSelection = 100;

  void _showSelectionLimitSnackbar() {
    showTrSnackbar(
      'media_gps_snackbar_selection_limit',
      backgroundColor: Colors.orange.shade800,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  void selectAllInGallery() {
    selectedAssetIds.clear();
    final ids = galleryAssets.map((e) => e.id).toList();
    if (ids.length > maxSelection) {
      selectedAssetIds.addAll(ids.take(maxSelection));
      _showSelectionLimitSnackbar();
    } else {
      selectedAssetIds.addAll(ids);
    }
    _markSelectionChanged();
    recomputeStats();
  }

  void unselectAllInGallery() {
    selectedAssetIds.clear();
    _markSelectionChanged();
    recomputeStats();
  }

  void toggleAssetSelection(String id) {
    if (selectedAssetIds.contains(id)) {
      selectedAssetIds.remove(id);
    } else {
      if (selectedAssetIds.length >= maxSelection) {
        _showSelectionLimitSnackbar();
        return;
      }
      selectedAssetIds.add(id);
      final a = _assetById(id);
      if (a != null) {
        CaptureTimeDedupeLog.logGalleryAsset(
          source: 'MediaGps.gallery',
          asset: a,
          alreadyImported: _isPickedAssetAlreadyImported(a),
        );
        final path = a.localPath;
        if (path != null && path.isNotEmpty) {
          unawaited(
            CaptureTimeDedupeLog.logPickedFile(
              source: 'MediaGps.gallery',
              path: path,
              mediaKind: a.isVideo ? 'video' : 'image',
              resolvedCaptureTime: a.createTime,
              galleryAssetId: a.id,
            ),
          );
        }
      }
    }
    _markSelectionChanged();
    recomputeStats();
  }

  /// Remove a previewed memory (whole cluster) from the current selection so
  /// it is no longer uploaded. Deselects every asset in the cluster and
  /// refreshes the stats / candidate list.
  void removeCandidateFromSelection(MediaGpsClusterCandidate candidate) {
    for (final item in candidate.items) {
      selectedAssetIds.remove(item.id);
    }
    _markSelectionChanged();
    recomputeStats();
  }

  /// Apple-style long-press then drag: first cell sets select vs deselect mode.
  void beginBulkDragSelection(int index) {
    if (index < 0 || index >= galleryAssets.length) return;
    _bulkDragActive = true;
    _bulkDragLastIndex = null;
    final id = galleryAssets[index].id;
    _bulkDragSelecting = !selectedAssetIds.contains(id);
    _applyBulkDragIndex(index);
  }

  void bulkDragSelectionMoveTo(int index) {
    if (!_bulkDragActive) return;
    _applyBulkDragIndex(index);
  }

  void _applyBulkDragIndex(int index) {
    if (index == _bulkDragLastIndex) return;
    if (index < 0 || index >= galleryAssets.length) return;
    _bulkDragLastIndex = index;
    final id = galleryAssets[index].id;
    if (_bulkDragSelecting) {
      if (selectedAssetIds.length < maxSelection) {
        selectedAssetIds.add(id);
      }
    } else {
      selectedAssetIds.remove(id);
    }
    selectedAssetIds.refresh();
    _bulkRecomputeDebounce?.cancel();
    _bulkRecomputeDebounce = Timer(const Duration(milliseconds: 45), () {
      if (!_bulkDragActive) return;
      recomputeStats();
    });
  }

  void endBulkDragSelection() {
    _bulkRecomputeDebounce?.cancel();
    if (!_bulkDragActive) return;
    _bulkDragActive = false;
    _bulkDragLastIndex = null;
    _markSelectionChanged();
    recomputeStats();
    suppressGalleryCellTap = true;
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      suppressGalleryCellTap = false;
    });
  }

  bool isSelected(String id) => selectedAssetIds.contains(id);

  void setGalleryFocusCell(int? index) => galleryFocusCellIndex.value = index;

  void recomputeStats() {
    rawFileCount.value = selectedAssetIds.length;

    var noGps = 0;
    var dupAssets = 0;

    final startKey = selectedStartDateKey.value;
    final endKey = selectedEndDateKey.value;
    final hasDateRange = startKey.isNotEmpty && endKey.isNotEmpty;

    for (final id in selectedAssetIds) {
      final a = _assetById(id);
      if (a == null) continue;
      if (!a.hasGps) {
        noGps++;
        continue;
      }
      if (_isPickedAssetAlreadyImported(a)) {
        dupAssets++;
        continue;
      }
      if (hasDateRange) {
        final key = _dateKeyFromDateTime(a.createTime);
        if (key.compareTo(startKey) < 0 || key.compareTo(endKey) > 0) {
          continue;
        }
      }
    }
    noGpsCount.value = noGps;

    // Date picker keys: eligible files before the date filter (GPS, not imported).
    final remainingBeforeDateFilter = _filterNewClusterCandidates(
      _buildClusterCandidates(applyDateRange: false),
    );
    _syncDateKeysFromRemainingAssets(
      remainingBeforeDateFilter.expand((c) => c.items),
    );

    final candidates = _buildClusterCandidates(applyDateRange: true);

    final filtered = _filterNewClusterCandidates(candidates);
    final dupClusters = _countClusterDuplicates(candidates);

    // Ignored = no GPS only. Date range + clustering affect new memories only.
    ignoredEntryCount.value = noGps;
    duplicateHintCount.value = dupClusters + dupAssets;
    totalEntryCount.value = (rawFileCount.value -
            ignoredEntryCount.value -
            duplicateHintCount.value)
        .clamp(0, 1 << 30);
    _lastCandidates = filtered;
    newMemoriesCount.value = filtered.length;
  }

  int _countClusterDuplicates(List<MediaGpsClusterCandidate> candidates) {
    final seen = <String>{};
    var dup = 0;
    for (final c in candidates) {
      final fp = c.fingerprint;
      if (seen.contains(fp)) {
        dup++;
        continue;
      }
      if (_existingTrackFingerprints.contains(fp) ||
          _isExistingGalleryFingerprint(fp)) {
        dup++;
        continue;
      }
      seen.add(fp);
    }
    return dup;
  }

  List<MediaGpsClusterCandidate> _filterNewClusterCandidates(
    List<MediaGpsClusterCandidate> candidates,
  ) {
    final filtered = <MediaGpsClusterCandidate>[];
    final seen = <String>{};
    for (final c in candidates) {
      final fp = c.fingerprint;
      if (seen.contains(fp)) continue;
      if (_existingTrackFingerprints.contains(fp) ||
          _isExistingGalleryFingerprint(fp)) {
        continue;
      }
      seen.add(fp);
      filtered.add(c);
    }
    return filtered;
  }

  /// Exact prior Media-GPS gallery fingerprint only — Memory View memories
  /// (null / non-gallery fingerprint) never block a new preview cluster.
  bool _isExistingGalleryFingerprint(String fingerprint) {
    if (fingerprint.isEmpty) return false;
    for (final r in _existingCoordinateRows) {
      final fp = r[DatabaseHelper.columnTrackImportFingerprint] as String?;
      if (fp != null && fp.isNotEmpty && fp == fingerprint) return true;
    }
    return false;
  }

  static String _localDateKey(DateTime when) {
    final l = when.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-'
        '${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }

  MediaGpsPickedAsset? _assetById(String id) {
    for (final a in galleryAssets) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<MediaGpsClusterCandidate> _buildClusterCandidates({
    bool applyDateRange = true,
  }) {
    final startKey = selectedStartDateKey.value;
    final endKey = selectedEndDateKey.value;

    final tagged = <({KmzTrackPoint p, MediaGpsPickedAsset a})>[];

    for (final id in selectedAssetIds) {
      final asset = _assetById(id);
      if (asset == null || !asset.hasGps) continue;
      if (_isPickedAssetAlreadyImported(asset)) continue;

      final key = _dateKeyFromDateTime(asset.createTime);
      if (applyDateRange &&
          startKey.isNotEmpty &&
          endKey.isNotEmpty &&
          (key.compareTo(startKey) < 0 || key.compareTo(endKey) > 0)) {
        continue;
      }

      final lat = asset.latitude!;
      final lng = asset.longitude!;
      // For videos, use the recording END time (createTime + duration) as the
      // cluster timestamp. This prevents a video from bridging two photo groups
      // that are far apart in time by acting as a mid-recording "link".
      final when = (asset.isVideo && asset.videoDuration > Duration.zero)
          ? asset.createTime.toUtc().add(asset.videoDuration)
          : asset.createTime.toUtc();
      tagged.add((
        p: KmzTrackPoint(latitude: lat, longitude: lng, when: when),
        a: asset,
      ));
    }

    if (tagged.isEmpty) return [];

    final minT = KmzImportPipeline.durationForTimeKey(selectedMinTimeApartKey.value);
    final minM = KmzImportPipeline.metersForDistanceKey(selectedMinMeterApartKey.value);
    final points = tagged.map((e) => e.p).toList();
    // Media: split when either time or distance threshold is met, and never
    // drop whole clusters via distance thinning — otherwise space-distant
    // photos taken close in time are merged or silently discarded.
    final clusters = KmzImportPipeline.clusterTrackPoints(
      points,
      minT,
      minM,
      splitWhenEitherThresholdMet: true,
      thinByMinDistance: false,
    );

    final out = <MediaGpsClusterCandidate>[];
    for (final c in clusters) {
      final items = <MediaGpsPickedAsset>[];
      for (final p in c) {
        for (final t in tagged) {
          if (identical(t.p, p)) {
            items.add(t.a);
            break;
          }
        }
      }
      if (items.isEmpty) continue;
      final rep = c.first;
      // Use the earliest real createTime across all cluster items so that
      // videos (whose track point `when` was shifted to their end time) don't
      // cause the memory to display an inflated timestamp.
      final earliestCreateTime = items
          .map((a) => a.createTime.toUtc())
          .reduce((a, b) => a.isBefore(b) ? a : b);
      out.add(
        MediaGpsClusterCandidate(
          when: earliestCreateTime,
          latitude: rep.latitude,
          longitude: rep.longitude,
          items: items,
          fingerprint: MediaGpsClusterCandidate.buildFingerprint(
            earliestCreateTime,
            rep.latitude,
            rep.longitude,
          ),
        ),
      );
    }
    return out;
  }

  Future<void> onPreviewTap() async {
    recomputeStats();
    if (selectedAssetIds.isEmpty) {
      _showSelectGalleryFilesSnackbar();
      return;
    }
    if (_lastCandidates.isEmpty) {
      _showNoNewMemoriesToUploadSnackbar();
      return;
    }
    final sorted = MemorySort.sortedByWhenNewestFirst(
      _lastCandidates,
      (c) => c.when,
    );
    final coords = sorted
        .map((e) => (lat: e.latitude, lng: e.longitude))
        .toList();
    try {
      isPreparingPreviewLocations.value = true;
      final lines = await resolveTrackPreviewLocationLinesOrdered(coords);
      await Get.to<void>(
        () => MediaGpsPreviewView(
          candidates: sorted,
          locationLines: lines,
        ),
      );
    } catch (e, st) {
      debugPrint('[MediaGpsUpload] preview geocode: $e\n$st');
      showTrSnackbar(
        'gpx_snackbar_preview_error',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
    } finally {
      isPreparingPreviewLocations.value = false;
    }
  }

  void _showSelectGalleryFilesSnackbar() {
    showTrSnackbar(
      'media_gps_snackbar_select_files',
      backgroundColor: Colors.orange.shade800,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  void _showNoNewMemoriesToUploadSnackbar() {
    showTrSnackbar(
      'media_gps_snackbar_no_new_memories',
      backgroundColor: Colors.orange.shade800,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
    );
  }

  Future<void> _showStorageAlert(String l10nKey) async {
    if (Get.isRegistered<MemoryImportBlockingController>()) {
      Get.find<MemoryImportBlockingController>().importing.value = false;
    }
    isBusy.value = false;
    await Future<void>.delayed(const Duration(milliseconds: 32));

    var raw = l10nKey.tr;
    const split = '@@@';
    final i = raw.indexOf(split);
    final title = i >= 0 ? raw.substring(0, i) : raw;
    final body = i >= 0 ? raw.substring(i + split.length) : '';
    await Get.dialog<void>(
      AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Get.back<void>(),
            child: Text('label_ok'.tr),
          ),
        ],
      ),
      barrierDismissible: true,
    );
    showTrSnackbar(
      l10nKey,
      backgroundColor: Colors.red.shade700,
      colorText: Colors.white,
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _showStorageBlockedAlert(MediaGpsStorageCheckReport report) async {
    final key = report.result == MediaGpsStorageCheckResult.unavailable
        ? 'media_gps_snackbar_storage_check_failed'
        : 'media_gps_snackbar_not_enough_storage';
    await _showStorageAlert(key);
  }

  List<MediaGpsPickedAsset> _pendingImportAssets(Set<String> fingerprints) {
    final seen = <String>{};
    final out = <MediaGpsPickedAsset>[];
    for (final c in _lastCandidates) {
      if (fingerprints.contains(c.fingerprint)) continue;
      for (final it in c.items) {
        if (seen.add(it.id)) out.add(it);
      }
    }
    return out;
  }

  /// Runs before [commitUpload] import work: compares image/video totals to free space.
  Future<bool> ensureEnoughStorageForUpload(
    List<MediaGpsPickedAsset> pendingAssets,
  ) async {
    final report = await MediaGpsImportStorageService.validateStorageBeforeImport(
      pendingAssets,
    );
    if (!report.canImport) {
      await _showStorageBlockedAlert(report);
      return false;
    }
    return true;
  }

  /// Resolves an asset's export path with retries. Gallery `entity.file`
  /// exports can transiently fail / return null under concurrent load (iCloud
  /// fetch, photo-manager throttling), which would otherwise silently drop the
  /// asset — and any cluster whose every asset failed — from the upload.
  Future<String?> _resolveExportPathWithRetry(
    MediaGpsPickedAsset asset, {
    int attempts = 2,
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final path = await MediaGpsGalleryService.resolveExportPath(asset)
            .timeout(const Duration(seconds: 10));
        if (path != null && path.isNotEmpty) return path;
      } catch (e) {
        debugPrint('[MediaGpsUpload] export attempt ${attempt + 1} failed: $e');
      }
      if (attempt < attempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 150 * (attempt + 1)));
      }
    }
    return null;
  }

  Future<void> commitUpload() async {
    if (selectedAssetIds.isEmpty) {
      _showSelectGalleryFilesSnackbar();
      return;
    }

    final importBlock = Get.find<MemoryImportBlockingController>();
    isBusy.value = true;
    // Yield so the upload button loading state paints before preflight work.
    await Future<void>.delayed(const Duration(milliseconds: 16));

    try {
      await _refreshDedupeDataAndRecompute();
      if (_lastCandidates.isEmpty) {
        _showNoNewMemoriesToUploadSnackbar();
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

      final rows =
          await DatabaseHelper.instance.queryMemoriesTrackImportDedupeRows();
      final fpLive = <String>{};
      for (final r in rows) {
        final fp = r[DatabaseHelper.columnTrackImportFingerprint] as String?;
        if (fp != null && fp.isNotEmpty) fpLive.add(fp);
      }

      final pendingAssets = _pendingImportAssets(fpLive);
      if (pendingAssets.isEmpty) {
        _showNoNewMemoriesToUploadSnackbar();
        return;
      }

      // Full-screen loader only after storage passes — keeps the alert above it.
      if (!await ensureEnoughStorageForUpload(pendingAssets)) {
        return;
      }

      importBlock.beginImport(progress: '1 / ${pendingAssets.length}');
      await Future<void>.delayed(const Duration(milliseconds: 16));

      final mem = Get.find<MemoryController>();
      // Warm offline geocoder once (hard timeout — never block upload forever).
      var geocoderReady = false;
      try {
        geocoderReady = await GeocodingIsolateService.instance
            .ensureInitialized(timeout: const Duration(seconds: 8));
      } catch (e) {
        debugPrint('[MediaGpsUpload] geocoder warm-up: $e');
      }

      var inserted = 0;
      var dupRuntime = 0;
      final insertedItems = <Map<String, dynamic>>[];
      final insertedMemoryIds = <int>{};

      // Phase 0: drop only clusters whose exact gallery fingerprint was already
      // imported via Media GPS — never skip because a Memory View memory shares
      // the same date/place (those stay as separate memories).
      final pendingClusters = <MediaGpsClusterCandidate>[];
      for (final c in _lastCandidates) {
        if (fpLive.contains(c.fingerprint)) {
          dupRuntime++;
        } else {
          pendingClusters.add(c);
        }
      }

      // Phase 1: resolve every asset's export path in PARALLEL (bounded). This
      // is the heavy gallery-export I/O that previously ran one item at a time
      // and was the main reason a 100-item upload felt frozen.
      importBlock.setProgress('Exporting…');
      final flatAssets = <MediaGpsPickedAsset>[];
      final flatClusterOf = <int>[];
      for (var ci = 0; ci < pendingClusters.length; ci++) {
        for (final it in pendingClusters[ci].items) {
          flatAssets.add(it);
          flatClusterOf.add(ci);
        }
      }
      // iOS Photos/iCloud hates many parallel entity.file calls — keep low.
      final exportConcurrency =
          (GetPlatform.isIOS ? 2 : _uploadConcurrency);
      final resolvedPaths = await mapWithConcurrency<MediaGpsPickedAsset, String?>(
        flatAssets,
        exportConcurrency,
        (asset, _) => _resolveExportPathWithRetry(asset),
      );
      final droppedAssets =
          resolvedPaths.where((p) => p == null || p.isEmpty).length;
      if (droppedAssets > 0) {
        debugPrint(
          '[MediaGpsUpload] WARNING: $droppedAssets/${flatAssets.length} assets '
          'could not be exported after retries and were skipped.',
        );
      }

      final imagePathsByCluster =
          List.generate(pendingClusters.length, (_) => <String>[]);
      final videoPathsByCluster =
          List.generate(pendingClusters.length, (_) => <String>[]);
      final audioPathsByCluster =
          List.generate(pendingClusters.length, (_) => <String>[]);
      for (var k = 0; k < flatAssets.length; k++) {
        final path = resolvedPaths[k];
        if (path == null || path.isEmpty) continue;
        final asset = flatAssets[k];
        final ci = flatClusterOf[k];
        if (asset.isVideo) {
          videoPathsByCluster[ci].add(path);
        } else if (asset.isAudio) {
          audioPathsByCluster[ci].add(path);
        } else {
          imagePathsByCluster[ci].add(path);
        }
      }

      // Phase 2: reverse-geocode every UNIQUE coordinate up front, in parallel,
      // BEFORE saving. reverseGeocodeCoordinates caches by rounded lat/lng, so
      // the per-cluster save below resolves location as an instant cache hit and
      // inserts it in one write — no deferred backfill / second UPDATE.
      if (geocoderReady) {
        importBlock.setProgress('Locations…');
        final coordKeys = <String>{};
        final coordLats = <double>[];
        final coordLngs = <double>[];
        for (var ci = 0; ci < pendingClusters.length; ci++) {
          if (imagePathsByCluster[ci].isEmpty &&
              videoPathsByCluster[ci].isEmpty &&
              audioPathsByCluster[ci].isEmpty) {
            continue;
          }
          final c = pendingClusters[ci];
          final key =
              '${c.latitude.toStringAsFixed(4)},${c.longitude.toStringAsFixed(4)}';
          if (coordKeys.add(key)) {
            coordLats.add(c.latitude);
            coordLngs.add(c.longitude);
          }
        }
        await mapWithConcurrency<int, Map<String, dynamic>?>(
          List<int>.generate(coordLats.length, (i) => i),
          GetPlatform.isIOS ? 2 : _uploadConcurrency,
          (i, _) => mem.reverseGeocodeCoordinates(coordLats[i], coordLngs[i]),
        );
      } else {
        debugPrint(
          '[MediaGpsUpload] geocoder not ready — saving coords only',
        );
      }

      // Phase 2.5: copy ALL images once. On iOS avoid compute() — Photos temp
      // paths + background isolates have caused indefinite hangs.
      importBlock.setProgress('Copying photos…');
      final flatImages = <String>[];
      final imageIndexRanges = List.generate(
        pendingClusters.length,
        (_) => (start: 0, end: 0),
      );
      for (var ci = 0; ci < pendingClusters.length; ci++) {
        final start = flatImages.length;
        flatImages.addAll(imagePathsByCluster[ci]);
        imageIndexRanges[ci] = (start: start, end: flatImages.length);
      }
      final relativeByFlatIndex = flatImages.isEmpty
          ? <String>[]
          : await mem.saveImagesToAppDirectory(
              flatImages,
              forceBackgroundCopy: !GetPlatform.isIOS,
              preserveSourceIndex: true,
            ).timeout(
              Duration(seconds: 12 + flatImages.length * 4),
              onTimeout: () {
                debugPrint(
                  '[MediaGpsUpload] image copy timed out after '
                  '${flatImages.length} files',
                );
                return List<String>.filled(flatImages.length, '');
              },
            );

      // Phase 3: one new memory per Preview cluster — never append into an
      // existing Memory View (or prior GPS) memory that shares date/time/place.
      final saveTotal = pendingClusters.length;
      for (var ci = 0; ci < pendingClusters.length; ci++) {
        final c = pendingClusters[ci];
        final imagePaths = imagePathsByCluster[ci];
        final videoPaths = videoPathsByCluster[ci];
        final audioPaths = audioPathsByCluster[ci];
        if (imagePaths.isEmpty && videoPaths.isEmpty && audioPaths.isEmpty) {
          continue;
        }
        importBlock.setProgress('${ci + 1} / $saveTotal');

        try {
          final clusterAssetRecords = _galleryRecordsForItems(c.items);
          final range = imageIndexRanges[ci];
          final preSavedImages = relativeByFlatIndex
              .sublist(range.start, range.end)
              .where((p) => p.isNotEmpty)
              .toList();

          final memoryId = await mem
              .saveImportedGalleryClusterMemory(
                when: c.when,
                latitude: c.latitude,
                longitude: c.longitude,
                imageAbsolutePaths: const [],
                videoAbsolutePaths: videoPaths,
                audioAbsolutePaths: audioPaths,
                trackImportFingerprint: c.fingerprint,
                galleryAssetRecords: clusterAssetRecords,
                skipReverseGeocode: true,
                preSavedImageRelativePaths: preSavedImages,
                generateVideoThumbnails: false,
              )
              .timeout(const Duration(seconds: 45));
          fpLive.add(c.fingerprint);
          for (final record in clusterAssetRecords) {
            final id = record.assetId;
            if (id != null && id.isNotEmpty) {
              _importedGalleryAssetIds.add(id);
            }
            final kind = record.mediaKind.trim();
            if (kind.isNotEmpty) {
              _importedGalleryMediaCreatedAtKeys.add(
                DatabaseHelper.mediaTimeKindDedupeKey(
                  record.mediaCreatedAt,
                  kind,
                ),
              );
            }
          }
          inserted++;
          insertedMemoryIds.add(memoryId);
          insertedItems.add({
            DatabaseHelper.columnTrackLogItemWhen:
                c.when.toUtc().toIso8601String(),
            DatabaseHelper.columnTrackLogItemLat: c.latitude,
            DatabaseHelper.columnTrackLogItemLng: c.longitude,
            DatabaseHelper.columnTrackLogItemLocation: 'gallery',
            DatabaseHelper.columnTrackLogItemMemoryId: memoryId,
          });
        } catch (e, st) {
          debugPrint('[MediaGpsUpload] skip cluster: $e\n$st');
        }

        if (ci % 2 == 1) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      if (inserted > 0) {
        try {
          final stamp = DateTime.now().toIso8601String();
          final logId = await DatabaseHelper.instance.insertTrackImportLog(
            fileName: 'Media GPS $stamp',
            rawCount: rawFileCount.value,
            ignoredCount: ignoredEntryCount.value,
            dupCount: dupRuntime,
            newCount: inserted,
            importSource: DatabaseHelper.trackImportSourceMediaGps,
          );
          await DatabaseHelper.instance.insertTrackImportLogItems(
            logId: logId,
            items: insertedItems,
          );
        } catch (e, st) {
          debugPrint('[MediaGpsUpload] track import log failed: $e\n$st');
          showTrSnackbar(
            'media_gps_snackbar_import_failed',
            backgroundColor: Colors.red.shade700,
            colorText: Colors.white,
          );
        }
      }

      if (inserted > 0) {
        showTrSnackbar(
          'gpx_snackbar_import_done',
          args: [inserted],
          backgroundColor: Colors.green.shade700,
          colorText: Colors.white,
        );
        selectedAssetIds.clear();
        await _reloadPastPlaceholder();
        _refreshDedupeDataAndRecompute();
        Get.back<void>();
        unawaited(_refreshViewsAfterGalleryImport(insertedMemoryIds));
      } else {
        _showNoNewMemoriesToUploadSnackbar();
        await _reloadPastPlaceholder();
        recomputeStats();
      }
    } catch (e, st) {
      debugPrint('[MediaGpsUpload] upload error: $e\n$st');
      showTrSnackbar(
        'media_gps_snackbar_import_failed',
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
    } finally {
      importBlock.endImport();
      isBusy.value = false;
    }
  }

  Future<void> _refreshViewsAfterGalleryImport(Set<int> memoryIds) async {
    try {
      if (Get.isRegistered<FilterController>()) {
        Get.find<FilterController>().resetFiltersExceptSearch();
      }
    } catch (e, st) {
      debugPrint('[MediaGpsUpload] filter reset: $e\n$st');
    }
    try {
      if (Get.isRegistered<AddMemoriesController>()) {
        await Get.find<AddMemoriesController>().loadMemoriesFromDatabase();
      }
    } catch (e, st) {
      debugPrint('[MediaGpsUpload] loadMemoriesFromDatabase: $e\n$st');
    }
    if (Get.isRegistered<MapControllerNew>() &&
        Get.isRegistered<FilterController>()) {
      try {
        final map = Get.find<MapControllerNew>();
        await map.reloadDisplayedMemoriesWithRetry();
        // Focus on the globally latest memory (not just within this import)
        unawaited(map.focusOnLatestMemory());
      } catch (e, st) {
        debugPrint('[MediaGpsUpload] map reload: $e\n$st');
      }
    }
    // Reverse-geocoding now happens up front during commitUpload (Phase 2), so
    // memories are inserted with location already filled — no deferred backfill.
  }

  /// Remaining entries = raw − ignored − duplicates (same as GPX/KMZ upload).
  int get totalUsableSelected => totalEntryCount.value;
}
