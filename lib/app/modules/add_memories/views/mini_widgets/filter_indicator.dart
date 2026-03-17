import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/filter/controllers/filter_controller.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new%20copy.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart' show MapControllerNew;
import '../../controllers/add_memories_controller.dart';
import '../../../ui/controllers/ui_controller.dart';

class FilterIndicator extends StatelessWidget {
  const FilterIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AddMemoriesController>();
    final uiController = Get.find<UiController>();

    return Obx(() {
      // Don't show indicator when filters are not active
      if (!controller.hasActiveFilters.value) {
        return const SizedBox.shrink();
      }

      // Use activeFilterCount from controller (delegates to FilterController)
      final activeFilterCount = controller.activeFilterCount;

      // Check if this is a map-based filter (no explicit filters but hasActiveFilters is true)
      bool isMapFilter =
          activeFilterCount == 0 &&
          controller.hasActiveFilters.value &&
          controller.isSearching.value;

      if (isMapFilter || activeFilterCount == 0) {
        return const SizedBox.shrink();
      }

      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              color:
                  uiController.darkMode.value
                      ? Colors.black87
                      : Colors.orange.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color:
                    uiController.darkMode.value
                        ? Colors.orange[600]!
                        : Colors.orange.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Row(
              // mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Icon(
                    Icons.filter_alt,
                    size: 16,
                    color:
                        uiController.darkMode.value
                            ? Colors.orange[300]
                            : Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$activeFilterCount filter${activeFilterCount > 1 ? 's' : ''} applied',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        uiController.darkMode.value
                            ? Colors.orange[300]
                          : Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '(${controller.filteredMemories.length} results)',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        uiController.darkMode.value
                            ? Colors.orange[400]
                          : Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    final mapController = Get.find<MapControllerNew>();
                    debugPrint('[FilterIndicator] 🧹 Resetting all filters');
          
                    // Use same logic as filter overlay reset button
                    // controller.resetFilters();
                    // mapController.resetFilters();
          
                    // Close filter overlay if open and reload with delay
                    // Future.delayed(Duration(milliseconds: 500), () {
                      _closefilterAndReset(mapController);
                    // });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color:
                          uiController.darkMode.value
                              ? Colors.orange.withValues(alpha: 0.3)
                              : Colors.orange.withValues(alpha: 0.8),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color:
                          uiController.darkMode.value
                              ? Colors.orange[300]
                          : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  /// Helper method to close filter and reset map (same logic as filter overlay)
  Future<void> _closefilterAndReset(MapControllerNew? mapController) async {
    debugPrint('[FilterIndicator] 🔄 Clearing all filters EXCEPT search from FilterController...');

    // Clear all filters EXCEPT search from FilterController (single source of truth)
    final filterController = Get.find<FilterController>();
    filterController.resetFiltersExceptSearch();

    debugPrint('[FilterIndicator] ✅ Filters cleared (search preserved: "${filterController.searchedTextKeyword.value}")');

    debugPrint('[FilterIndicator] 📊 Loaded ${filterController.filteredMemories.length} memories');

    // Reload AddMemories view
    if (Get.isRegistered<AddMemoriesController>()) {
      final addMemoriesController = Get.find<AddMemoriesController>();
      await addMemoriesController.loadMemoriesFromDatabase();
      debugPrint('[FilterIndicator] ✅ AddMemories view reloaded');
    }

    // Close filter overlay and reload map
    mapController?.isFilterOpen.value = false;
    await mapController?.loadMemoriesFromDB(filterController.filteredMemories.toList());
    mapController?.showLoadedDataOnMap();

    debugPrint('[FilterIndicator] ✅ Map reloaded');
  }
}
