import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/filter/controllers/filter_controller.dart';
import 'package:spacetime/app/modules/gpx_kmz_upload/controllers/gpx_kmz_upload_controller.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/media_gps_upload/controllers/media_gps_upload_controller.dart';

Future<void> refreshTrackUploadScreensPastCounts() async {
  if (Get.isRegistered<GpxKmzUploadController>()) {
    await Get.find<GpxKmzUploadController>().refreshPastUploadCount();
  }
  if (Get.isRegistered<MediaGpsUploadController>()) {
    await Get.find<MediaGpsUploadController>().refreshPastUploadCount();
  }
}

/// Reload in-memory duplicate caches on upload screens after memories are deleted.
Future<void> refreshUploadDedupeCachesAfterMemoryDeletion() async {
  if (Get.isRegistered<MediaGpsUploadController>()) {
    await Get.find<MediaGpsUploadController>().reloadDedupeFromDatabase();
  }
  if (Get.isRegistered<GpxKmzUploadController>()) {
    await Get.find<GpxKmzUploadController>().reloadDedupeFromDatabase();
  }
}

/// Reload filter, memories list, map, and upload dedupe caches after a full backup restore.
Future<void> refreshConsumersAfterDatabaseRestore({
  String logTag = 'BackupImport',
}) async {
  if (Get.isRegistered<FilterController>()) {
    Get.find<FilterController>().resetFilters();
  }
  if (Get.isRegistered<AddMemoriesController>()) {
    await Get.find<AddMemoriesController>().loadMemoriesFromDatabase();
  }
  if (Get.isRegistered<MapControllerNew>()) {
    final map = Get.find<MapControllerNew>();
    try {
      await map.reloadDisplayedMemoriesWithRetry();
    } catch (e, st) {
      debugPrint('[$logTag] map reload after restore: $e\n$st');
    }
  }
  await refreshUploadDedupeCachesAfterMemoryDeletion();
  await refreshTrackUploadScreensPastCounts();
}

Future<void> refreshConsumersAfterTrackImportDeletion({
  String logTag = 'TrackImportDeletion',
}) async {
  if (Get.isRegistered<FilterController>()) {
    final filter = Get.find<FilterController>();
    // Reset filters WITHOUT re-applying to the stale cache, then reload the full
    // memory list from the DB — otherwise deleted memories linger in
    // FilterController.allMemories and keep showing after a past-upload delete.
    filter.resetFiltersExceptSearch(applyFilters: false);
    await filter.loadAndApplyFilters();
  }
  if (Get.isRegistered<AddMemoriesController>()) {
    await Get.find<AddMemoriesController>().loadMemoriesFromDatabase();
  }
  if (Get.isRegistered<MapControllerNew>() &&
      Get.isRegistered<FilterController>()) {
    final map = Get.find<MapControllerNew>();
    try {
      await map.reloadDisplayedMemoriesWithRetry();
    } catch (e, st) {
      debugPrint('[$logTag] map reload after deletion: $e\n$st');
    }
  }
  await refreshTrackUploadScreensPastCounts();
  await refreshUploadDedupeCachesAfterMemoryDeletion();
}

/// Fast path after deleting a single memory — patch in-memory lists.
///
/// When [waitForMap] is true (Memory View loader), list + map refresh are
/// awaited so the UI can stay busy until everything is ready.
Future<void> refreshConsumersAfterMemoryDeletion({
  required int memoryId,
  bool focusMapOnLatest = false,
  bool waitForMap = false,
  String logTag = 'MemoryDeletion',
}) async {
  if (Get.isRegistered<FilterController>()) {
    Get.find<FilterController>().removeMemoryById(memoryId);
  }

  if (Get.isRegistered<MapControllerNew>() &&
      Get.isRegistered<FilterController>()) {
    final mapFuture = _deferredSingleMemoryMapRefresh(
      focusMapOnLatest: focusMapOnLatest,
      waitForMap: waitForMap,
      logTag: logTag,
    );
    if (waitForMap) {
      await mapFuture;
    } else {
      unawaited(mapFuture);
    }
  }

  if (waitForMap) {
    await Future.wait([
      refreshUploadDedupeCachesAfterMemoryDeletion(),
      refreshTrackUploadScreensPastCounts(),
    ]);
  } else {
    unawaited(refreshUploadDedupeCachesAfterMemoryDeletion());
    unawaited(refreshTrackUploadScreensPastCounts());
  }
}

Future<void> _deferredSingleMemoryMapRefresh({
  required bool focusMapOnLatest,
  bool waitForMap = false,
  required String logTag,
}) async {
  if (!waitForMap) {
    await Future<void>.delayed(Duration.zero);
  }
  if (!Get.isRegistered<MapControllerNew>() ||
      !Get.isRegistered<FilterController>()) {
    return;
  }
  final map = Get.find<MapControllerNew>();
  final fc = Get.find<FilterController>();
  try {
    await map.loadMemoriesFromDB(fc.filteredMemories.toList());
    if (waitForMap) {
      await map.showLoadedDataOnMap();
      if (focusMapOnLatest) {
        await map.focusOnLatestMemory();
      }
    } else {
      unawaited(map.showLoadedDataOnMap());
      if (focusMapOnLatest) {
        unawaited(map.focusOnLatestMemory());
      }
    }
  } catch (e, st) {
    debugPrint('[$logTag] deferred map refresh: $e\n$st');
  }
}
