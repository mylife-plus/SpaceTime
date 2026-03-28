import 'package:get/get.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/filter/controllers/filter_controller.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/repositories/cluster_repository.dart';
import 'package:spacetime/app/repositories/memory_repository.dart';
import 'package:spacetime/app/services/map_marker_creation_service.dart';
import 'package:spacetime/app/services/map_marker_service.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';

/// Map / memories / filter stack — register only when opening map/memories flows
/// (not during Get Started) so startup stays fast and avoids location API contention.
void ensureHeavyAppControllersRegistered() {
  if (Get.isRegistered<FilterController>()) return;

  if (!Get.isRegistered<MemoryRepository>()) {
    Get.put(MemoryRepository(), permanent: true);
    Get.put(ClusterRepository(), permanent: true);
    Get.put(MapMarkerCreationService(), permanent: true);
    Get.put(MapMarkerService(), permanent: true);
  }
  if (!Get.isRegistered<GeocodingIsolateService>()) {
    Get.put(GeocodingIsolateService(), permanent: true);
  }

  Get.put(FilterController(), permanent: true);
  Get.put(MemoryController(), permanent: true);
  Get.put(AddMemoriesController(), permanent: true);
  Get.put(MapControllerNew(), permanent: true);
}
