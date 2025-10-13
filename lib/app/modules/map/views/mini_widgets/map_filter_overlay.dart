import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/filter_overlay.dart';

import '../../controllers/map_controller_new.dart';

class MapFilterOverlay extends StatelessWidget {
  const MapFilterOverlay({super.key});

  void _ensureControllersSynced() {
    final mapController = Get.find<MapControllerNew>();
    final addMemoriesController =
        Get.isRegistered<AddMemoriesController>()
            ? Get.find<AddMemoriesController>()
            : Get.put(AddMemoriesController());

    addMemoriesController.isOpenedFromMap = true;

    addMemoriesController.filterValues
      ..clear()
      ..addAll(mapController.filterValues);
    addMemoriesController.selectedLocation.value =
        mapController.selectedLocation.value;
    addMemoriesController.selectedRadius.value =
        mapController.selectedRadius.value;
    addMemoriesController.selectedHashtags
      ..clear()
      ..addAll(mapController.selectedHashtags);
    addMemoriesController.selectedContacts
      ..clear()
      ..addAll(mapController.selectedContacts);
    addMemoriesController.selectedCategories
      ..clear()
      ..addAll(mapController.selectedCategories);

    addMemoriesController.updateFilterStatus();
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllersSynced();
    return MemoriesFilterOverlay(isOpenedFromMap: true);
  }
}
