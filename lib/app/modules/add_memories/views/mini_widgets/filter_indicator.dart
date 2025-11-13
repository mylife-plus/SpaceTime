import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/add_memories_controller.dart';
import '../../../ui/controllers/ui_controller.dart';

class FilterIndicator extends StatelessWidget {
  const FilterIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AddMemoriesController>();
    final uiController = Get.find<UiController>();

    return Obx(() {
      // Don't show indicator when filters are not active OR when there are 0 results
      if (!controller.hasActiveFilters.value || controller.filteredMemories.isEmpty) {
        return const SizedBox.shrink();
      }

      // Count active filters
      int activeFilterCount = 0;
      List<String> activeFilters = [];

      if (controller.filterValues.isNotEmpty) {
        for (final entry in controller.filterValues.entries) {
          if (entry.value.isNotEmpty) {
            activeFilterCount++;
            if (entry.key.contains('date')) {
              activeFilters.add('Date');
            } else {
              activeFilters.add(entry.key);
            }
          }
        }
      }

      // Location and radius are treated as a single filter
      if (controller.selectedLocation.value.isNotEmpty) {
        activeFilterCount++;
        // Show both location and radius info if radius is set
        if (controller.selectedRadius.value.isNotEmpty) {
          activeFilters.add('Location (${controller.selectedRadius.value})');
        } else {
          activeFilters.add('Location');
        }
      }

      if (controller.selectedHashtags.isNotEmpty) {
        activeFilterCount++;
        activeFilters.add('Hashtags (${controller.selectedHashtags.length})');
      }

      if (controller.selectedContacts.isNotEmpty) {
        activeFilterCount++;
        activeFilters.add('Contacts (${controller.selectedContacts.length})');
      }

      if (controller.selectedCategories.isNotEmpty) {
        activeFilterCount++;
        activeFilters.add(
          'Categories (${controller.selectedCategories.length})',
        );
      }

      // Check if this is a map-based filter (no explicit filters but hasActiveFilters is true)
      bool isMapFilter =
          activeFilterCount == 0 &&
          controller.hasActiveFilters.value &&
          controller.isSearching.value;

      if (isMapFilter) {
        activeFilterCount = 1;
        activeFilters.add('Map View');
      }

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              uiController.darkMode.value
                  ? Colors.orange[900]?.withValues(alpha: 0.3)
                  : Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                uiController.darkMode.value
                    ? Colors.orange[600]!
                    : Colors.orange.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt,
              size: 16,
              color:
                  uiController.darkMode.value
                      ? Colors.orange[300]
                      : Colors.orange[700],
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '$activeFilterCount filter${activeFilterCount > 1 ? 's' : ''} applied',
                style: TextStyle(
                  fontSize: 12,
                  color:
                      uiController.darkMode.value
                          ? Colors.orange[300]
                          : Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
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
                        : Colors.orange[600],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                controller.resetFilters();
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color:
                      uiController.darkMode.value
                          ? Colors.orange.withValues(alpha: 0.3)
                          : Colors.orange.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color:
                      uiController.darkMode.value
                          ? Colors.orange[300]
                          : Colors.orange[700],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
