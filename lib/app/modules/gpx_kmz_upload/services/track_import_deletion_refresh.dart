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
