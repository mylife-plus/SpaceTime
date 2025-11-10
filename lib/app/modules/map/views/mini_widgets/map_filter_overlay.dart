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
  @override
  void initState() {
    super.initState();
    // Sync filters every time the overlay is opened
    _syncFiltersFromMapToAddMemories();
  }

  void _syncFiltersFromMapToAddMemories() {
    final mapController = Get.find<MapControllerNew>();
    // AddMemoriesController is initialized in main.dart as permanent singleton
    // Always use Get.find() - it should always be available
    final addMemoriesController = Get.find<AddMemoriesController>();

    addMemoriesController.isOpenedFromMap = true;

    debugPrint('[MapFilterOverlay] Syncing filters from MapController to AddMemoriesController');

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

    debugPrint('[MapFilterOverlay] Sync complete - Categories: ${addMemoriesController.selectedCategories.length}, Hashtags: ${addMemoriesController.selectedHashtags.length}, Contacts: ${addMemoriesController.selectedContacts.length}');
  }

  @override
  Widget build(BuildContext context) {
    return MemoriesFilterOverlay(isOpenedFromMap: true);
  }
}
