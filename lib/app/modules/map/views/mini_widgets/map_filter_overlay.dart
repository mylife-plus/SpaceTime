import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/filter_overlay.dart';

import '../../controllers/map_controller_new.dart';

class MapFilterOverlay extends StatefulWidget {
  const MapFilterOverlay({super.key});

  @override
  State<MapFilterOverlay> createState() => _MapFilterOverlayState();
}

class _MapFilterOverlayState extends State<MapFilterOverlay> {
  bool _isInitialized = false;

  void _ensureControllersSynced() {
    // Only sync once when first opened, not on every rebuild
    if (_isInitialized) return;

    final mapController = Get.find<MapControllerNew>();
    final addMemoriesController =
        Get.isRegistered<AddMemoriesController>()
            ? Get.find<AddMemoriesController>()
            : Get.put(AddMemoriesController(), permanent: true);

    addMemoriesController.isOpenedFromMap = true;

    // Sync filters from map to add memories controller
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

    _isInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllersSynced();
    return MemoriesFilterOverlay(isOpenedFromMap: true);
  }
}
