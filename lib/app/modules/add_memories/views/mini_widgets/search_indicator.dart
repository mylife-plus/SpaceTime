import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import '../../controllers/add_memories_controller.dart';
import '../../../ui/controllers/ui_controller.dart';
import '../../../map/controllers/map_controller_new.dart';
import '../../../filter/controllers/filter_controller.dart';

class SearchIndicator extends StatelessWidget {
  const SearchIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AddMemoriesController>();
    final uiController = Get.find<UiController>();

    return Obx(() {
      // Show indicator when search is active or when there are filtered results
      final showIndicator =
          controller.isSearching.value &&
          controller.searchQuery.value.isNotEmpty;

      if (!showIndicator) {
        return const SizedBox.shrink();
      }

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              uiController.darkMode.value
                  ? Colors.grey[800]
                  : Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                uiController.darkMode.value
                    ? Colors.grey[600]!
                    : Colors.blue.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 16,
              color:
                  uiController.darkMode.value
                      ? Colors.white70
                      : Colors.blue[700],
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                trKey('text_search_controller_searchquery_value', [
                  controller.searchQuery.value,
                ]),
                style: TextStyle(
                  fontSize: 12,
                  color:
                      uiController.darkMode.value
                          ? Colors.white70
                          : Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              trKey('text_controller_filteredmemories_length_results', [
                controller.filteredMemories.length,
              ]),
              style: TextStyle(
                fontSize: 11,
                color:
                    uiController.darkMode.value
                        ? Colors.white54
                        : Colors.blue[600],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                debugPrint('[SearchIndicator] 🔄 Clearing search filter...');
                controller.closeSearch();
                if (controller.isOpenedFromMap) {
                  await controller.reloadMapFromSearchFilter();
                } else {
                  await controller.loadMemoriesFromDatabase();
                  if (Get.isRegistered<MapControllerNew>()) {
                    final mapController = Get.find<MapControllerNew>();
                    await mapController.loadMemoriesFromDB(
                      Get.find<FilterController>().filteredMemories.toList(),
                    );
                    await mapController.showLoadedDataOnMap();
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color:
                      uiController.darkMode.value
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.blue.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color:
                      uiController.darkMode.value
                          ? Colors.white
                          : Colors.blue[700],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
