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
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_gallery_permission.dart';
import 'package:spacetime/app/modules/media_gps_upload/services/media_gps_gallery_service.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/media_gps_gallery_picker_view.dart';
import 'package:spacetime/app/modules/media_gps_upload/views/media_gps_preview_view.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/services/app_lock_controller.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'package:spacetime/services/memory_import_blocking_controller.dart';
import 'package:spacetime/app/widgets/app_date_time_pickers.dart';

class MediaGpsUploadController extends GetxController {
  final RxBool isBusy = false.obs;
  final RxBool isPreparingPreviewLocations = false.obs;
  final RxBool galleryLoading = false.obs;
  /// True when OS grants only partial / “limited” library access (iOS + newer Android).
  final RxBool photoLibraryLimitedAccess = false.obs;
  final RxList<MediaGpsPickedAsset> galleryAssets = <MediaGpsPickedAsset>[].obs;
  final RxSet<String> selectedAssetIds = <String>{}.obs;
  final Rxn<int> galleryFocusCellIndex = Rxn<int>();

  final RxString selectedMaxTimeApartKey =
      TrackClusterFieldConfig.maxTimeApartOptionKeys[
              TrackClusterFieldConfig.defaultClusterOptionIndex]
          .obs;
  final RxString selectedMaxMeterApartKey =
      TrackClusterFieldConfig.maxMeterApartOptionKeys[
              TrackClusterFieldConfig.defaultClusterOptionIndex]
          .obs;

  final RxList<String> availableDateKeys = <String>[].obs;
  final RxString selectedStartDateKey = ''.obs;
  final RxString selectedEndDateKey = ''.obs;

  final RxInt rawFileCount = 0.obs;
  final RxInt duplicateHintCount = 0.obs;
  final RxInt noGpsCount = 0.obs;
  final RxInt newMemoriesCount = 0.obs;
  final RxInt pastUploadLogCount = 0.obs;

  List<MediaGpsClusterCandidate> _lastCandidates = [];
  Set<String> _existingTrackFingerprints = <String>{};
  List<Map<String, dynamic>> _existingCoordinateRows = const [];

  /// Long-press + drag bulk selection (gallery picker).
  bool _bulkDragActive = false;
  bool _bulkDragSelecting = true;
  int? _bulkDragLastIndex;
  Timer? _bulkRecomputeDebounce;

  /// After bulk drag ends, skip one tap so fullscreen doesn’t open on finger up.
  bool suppressGalleryCellTap = false;

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

  Future<void> _refreshDedupeDataAndRecompute() async {
    try {
      final rows = await DatabaseHelper.instance.queryMemoriesTrackImportDedupeRows();
      final fp = <String>{};
      for (final r in rows) {
        final v = r[DatabaseHelper.columnTrackImportFingerprint] as String?;
        if (v != null && v.isNotEmpty) fp.add(v);
      }
      _existingTrackFingerprints = fp;
      _existingCoordinateRows = rows;
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
      Get.find<AppLockController>().skipLockOnNextResumeFromSettings();
    }
    await PhotoManager.openSetting();
  }

  Future<void> ensureGalleryLoaded({bool force = false}) async {
    if (!force && galleryAssets.isNotEmpty) return;

    final gen = ++_galleryLoadGen;
    galleryLoading.value = true;
    try {
      final list = await MediaGpsGalleryService.loadRecentAssets();
      if (gen != _galleryLoadGen) return;
      galleryAssets.assignAll(list);
      _syncDateKeysFromGallery();
      _refreshDedupeDataAndRecompute();
      recomputeStats();
      await refreshPhotoLibraryAccessFlag();
    } catch (e, st) {
      debugPrint('[MediaGpsUpload] gallery load: $e\n$st');
      if (gen == _galleryLoadGen) {
        showTrSnackbar(
          'gpx_snackbar_preview_error',
          args: [e.toString()],
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

  void _syncDateKeysFromGallery() {
    final set = <String>{};
    for (final a in galleryAssets) {
      final d = a.createTime.toUtc();
      set.add(
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}',
      );
    }
    final keys = set.toList()..sort();
    availableDateKeys.value = keys;
    if (keys.isEmpty) {
      selectedStartDateKey.value = '';
      selectedEndDateKey.value = '';
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

  void _syncDateKeysFromSelection() {
    final set = <String>{};
    for (final id in selectedAssetIds) {
      final a = _assetById(id);
      if (a == null || !a.hasGps) continue;
      final d = a.createTime.toUtc();
      set.add(
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}',
      );
    }
    final keys = set.toList()..sort();
    availableDateKeys.value = keys;
    if (keys.isEmpty) {
      selectedStartDateKey.value = '';
      selectedEndDateKey.value = '';
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
    final pickedKey =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
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
    final keys = availableDateKeys;
    if (keys.isEmpty) return;
    final first = _dateFromKey(keys.first);
    final last = _dateFromKey(keys.last);
    final initial = _dateFromKey(selectedStartDateKey.value) ?? first;
    if (first == null || last == null || initial == null) return;
    final picked = await showAppDatePicker(
      context: context,
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
    final keys = availableDateKeys;
    if (keys.isEmpty) return;
    final first = _dateFromKey(keys.first);
    final last = _dateFromKey(keys.last);
    final initial = _dateFromKey(selectedEndDateKey.value) ?? last;
    if (first == null || last == null || initial == null) return;
    final picked = await showAppDatePicker(
      context: context,
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
    recomputeStats();
  }

  void selectAllInGallery() {
    selectedAssetIds.clear();
    selectedAssetIds.addAll(galleryAssets.map((e) => e.id));
    recomputeStats();
  }

  void unselectAllInGallery() {
    selectedAssetIds.clear();
    recomputeStats();
  }

  void toggleAssetSelection(String id) {
    if (selectedAssetIds.contains(id)) {
      selectedAssetIds.remove(id);
    } else {
      selectedAssetIds.add(id);
    }
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
      selectedAssetIds.add(id);
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
    recomputeStats();
    suppressGalleryCellTap = true;
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      suppressGalleryCellTap = false;
    });
  }

  bool isSelected(String id) => selectedAssetIds.contains(id);

  void setGalleryFocusCell(int? index) => galleryFocusCellIndex.value = index;

  void recomputeStats() {
    _syncDateKeysFromSelection();
    rawFileCount.value = selectedAssetIds.length;

    var noGps = 0;
    for (final id in selectedAssetIds) {
      final a = _assetById(id);
      if (a == null) continue;
      if (!a.hasGps) {
        noGps++;
        continue;
      }
    }
    noGpsCount.value = noGps;

    final candidates = _buildClusterCandidates();
    final filtered = <MediaGpsClusterCandidate>[];
    final seen = <String>{};
    var dup = 0;
    for (final c in candidates) {
      final fp = c.fingerprint;
      if (seen.contains(fp)) {
        dup++;
        continue;
      }
      if (_existingTrackFingerprints.contains(fp) ||
          _matchesExistingCoordinateRow(
            _existingCoordinateRows,
            c.when,
            c.latitude,
            c.longitude,
            fp,
          )) {
        dup++;
        continue;
      }
      seen.add(fp);
      filtered.add(c);
    }

    duplicateHintCount.value = dup;
    _lastCandidates = filtered;
    newMemoriesCount.value = filtered.length;
  }

  bool _matchesExistingCoordinateRow(
    List<Map<String, dynamic>> rows,
    DateTime when,
    double lat,
    double lng,
    String fingerprint,
  ) {
    final d =
        '${when.year.toString().padLeft(4, '0')}-'
        '${when.month.toString().padLeft(2, '0')}-'
        '${when.day.toString().padLeft(2, '0')}';
    for (final r in rows) {
      final fp = r[DatabaseHelper.columnTrackImportFingerprint] as String?;
      if (fp != null && fp.isNotEmpty && fp == fingerprint) return true;
      final latE = (r['location_latitude'] as num?)?.toDouble();
      final lngE = (r['location_longitude'] as num?)?.toDouble();
      if (latE == null || lngE == null) continue;
      if ((r['date'] as String?) != d) continue;
      if (fp == null || fp.isEmpty) {
        if ((lat - latE).abs() < 1e-5 && (lng - lngE).abs() < 1e-5) return true;
      }
    }
    return false;
  }

  MediaGpsPickedAsset? _assetById(String id) {
    for (final a in galleryAssets) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<MediaGpsClusterCandidate> _buildClusterCandidates() {
    final startKey = selectedStartDateKey.value;
    final endKey = selectedEndDateKey.value;

    final tagged = <({KmzTrackPoint p, MediaGpsPickedAsset a})>[];

    for (final id in selectedAssetIds) {
      final asset = _assetById(id);
      if (asset == null || !asset.hasGps) continue;

      final d = asset.createTime.toUtc();
      final key =
          '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
      if (startKey.isNotEmpty &&
          endKey.isNotEmpty &&
          (key.compareTo(startKey) < 0 || key.compareTo(endKey) > 0)) {
        continue;
      }

      final lat = asset.latitude!;
      final lng = asset.longitude!;
      final when = asset.createTime.toUtc();
      tagged.add((
        p: KmzTrackPoint(latitude: lat, longitude: lng, when: when),
        a: asset,
      ));
    }

    if (tagged.isEmpty) return [];

    final maxT = KmzImportPipeline.durationForTimeKey(selectedMaxTimeApartKey.value);
    final maxM = KmzImportPipeline.metersForDistanceKey(selectedMaxMeterApartKey.value);
    final points = tagged.map((e) => e.p).toList();
    final clusters = KmzImportPipeline.clusterTrackPoints(points, maxT, maxM);

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
      final w = rep.when!.toUtc();
      out.add(
        MediaGpsClusterCandidate(
          when: w,
          latitude: rep.latitude,
          longitude: rep.longitude,
          items: items,
          fingerprint: MediaGpsClusterCandidate.buildFingerprint(
            w,
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
    if (_lastCandidates.isEmpty) {
      showTrSnackbar(
        'gpx_snackbar_nothing_to_import',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }
    final sorted = [..._lastCandidates]
      ..sort((a, b) => a.when.compareTo(b.when));
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
        args: [e.toString()],
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
    } finally {
      isPreparingPreviewLocations.value = false;
    }
  }

  Future<void> commitUpload() async {
    await _refreshDedupeDataAndRecompute();
    recomputeStats();
    if (_lastCandidates.isEmpty) {
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
    final rows = await DatabaseHelper.instance.queryMemoriesTrackImportDedupeRows();
    final fpLive = <String>{};
    for (final r in rows) {
      final fp = r[DatabaseHelper.columnTrackImportFingerprint] as String?;
      if (fp != null && fp.isNotEmpty) fpLive.add(fp);
    }

    var galleryMergeRows =
        await DatabaseHelper.instance.queryMemoriesGalleryMergeCandidates();
    final maxT = KmzImportPipeline.durationForTimeKey(
      selectedMaxTimeApartKey.value,
    );
    final maxM = KmzImportPipeline.metersForDistanceKey(
      selectedMaxMeterApartKey.value,
    );

    var inserted = 0;
    var dupRuntime = 0;
    final insertedItems = <Map<String, dynamic>>[];

    try {
      for (final c in _lastCandidates) {
        if (fpLive.contains(c.fingerprint)) {
          dupRuntime++;
          continue;
        }

        final imagePaths = <String>[];
        final videoPaths = <String>[];
        final audioPaths = <String>[];
        for (final it in c.items) {
          final path = await MediaGpsGalleryService.exportToTempFile(it.entity);
          if (path == null || path.isEmpty) continue;
          if (it.isVideo) {
            videoPaths.add(path);
          } else if (it.isAudio) {
            audioPaths.add(path);
          } else {
            imagePaths.add(path);
          }
        }
        if (imagePaths.isEmpty &&
            videoPaths.isEmpty &&
            audioPaths.isEmpty) {
          continue;
        }

        try {
          final mergeId = _findMergeTargetGalleryMemoryId(
            c: c,
            galleryRows: galleryMergeRows,
            maxT: maxT,
            maxM: maxM,
          );

          late final int memoryId;
          if (mergeId != null) {
            await mem.appendImportedGalleryMediaToMemory(
              memoryId: mergeId,
              imageAbsolutePaths: imagePaths,
              videoAbsolutePaths: videoPaths,
              audioAbsolutePaths: audioPaths,
            );
            memoryId = mergeId;
          } else {
            memoryId = await mem.saveImportedGalleryClusterMemory(
              when: c.when,
              latitude: c.latitude,
              longitude: c.longitude,
              imageAbsolutePaths: imagePaths,
              videoAbsolutePaths: videoPaths,
              audioAbsolutePaths: audioPaths,
              trackImportFingerprint: c.fingerprint,
            );
            galleryMergeRows = [
              ...galleryMergeRows,
              {
                DatabaseHelper.columnId: memoryId,
                DatabaseHelper.columnCreatedAt:
                    c.when.toLocal().toIso8601String(),
                DatabaseHelper.columnLocationLatitude: c.latitude,
                DatabaseHelper.columnLocationLongitude: c.longitude,
                DatabaseHelper.columnTrackImportFingerprint: c.fingerprint,
              },
            ];
          }
          fpLive.add(c.fingerprint);
          inserted++;
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
      }

      if (inserted > 0) {
        try {
          final stamp = DateTime.now().toIso8601String();
          final logId = await DatabaseHelper.instance.insertTrackImportLog(
            fileName: 'Media GPS $stamp',
            rawCount: rawFileCount.value,
            ignoredCount: noGpsCount.value + duplicateHintCount.value,
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
            'gpx_snackbar_preview_error',
            args: ['Past upload log: $e'],
            backgroundColor: Colors.red.shade700,
            colorText: Colors.white,
          );
        }
      }

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
      if (Get.isRegistered<MapControllerNew>() && Get.isRegistered<FilterController>()) {
        final map = Get.find<MapControllerNew>();
        try {
          await map.reloadDisplayedMemoriesWithRetry();
        } catch (e, st) {
          debugPrint('[MediaGpsUpload] map reload: $e\n$st');
        }
      }

      showTrSnackbar(
        'gpx_snackbar_import_done',
        args: [inserted],
        backgroundColor: Colors.green.shade700,
        colorText: Colors.white,
      );
      if (inserted > 0) {
        selectedAssetIds.clear();
        await _reloadPastPlaceholder();
        await _refreshDedupeDataAndRecompute();
        recomputeStats();
        await Future<void>.delayed(const Duration(milliseconds: 450));
        Get.back<void>();
      } else {
        await _reloadPastPlaceholder();
        recomputeStats();
      }
    } catch (e, st) {
      debugPrint('[MediaGpsUpload] upload error: $e\n$st');
      showTrSnackbar(
        'gpx_snackbar_preview_error',
        args: [e.toString()],
        backgroundColor: Colors.red.shade700,
        colorText: Colors.white,
      );
    } finally {
      importBlock.importing.value = false;
      isBusy.value = false;
    }
  }

  /// Same place (~5 m) or within import max time + max distance as existing gallery memory.
  int? _findMergeTargetGalleryMemoryId({
    required MediaGpsClusterCandidate c,
    required List<Map<String, dynamic>> galleryRows,
    required Duration maxT,
    required double maxM,
  }) {
    const sameSpotMeters = 5.0;
    int? bestId;
    var bestScore = double.infinity;
    for (final r in galleryRows) {
      final id = r[DatabaseHelper.columnId] as int?;
      if (id == null) continue;
      final mlat =
          (r[DatabaseHelper.columnLocationLatitude] as num?)?.toDouble();
      final mlng =
          (r[DatabaseHelper.columnLocationLongitude] as num?)?.toDouble();
      if (mlat == null || mlng == null) continue;
      final m = KmzImportPipeline.metersBetween(
        c.latitude,
        c.longitude,
        mlat,
        mlng,
      );
      final raw = r[DatabaseHelper.columnCreatedAt]?.toString();
      final memWhen = raw == null ? null : DateTime.tryParse(raw);
      if (memWhen == null) continue;
      final dt = c.when.toUtc().difference(memWhen.toUtc()).abs();
      final sameSpot = m <= sameSpotMeters;
      final inWindow = m <= maxM && dt <= maxT;
      if (!sameSpot && !inWindow) continue;
      final score = m + dt.inMilliseconds / 1e6;
      if (score < bestScore) {
        bestScore = score;
        bestId = id;
      }
    }
    return bestId;
  }

  int get totalUsableSelected {
    var n = 0;
    for (final id in selectedAssetIds) {
      final a = _assetById(id);
      if (a != null && a.hasGps) n++;
    }
    return n;
  }
}
