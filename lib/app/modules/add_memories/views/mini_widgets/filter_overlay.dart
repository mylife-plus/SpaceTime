import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/filter_fileds.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/filter_dropdown.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/category_picker_widget.dart';
import 'package:spacetime/app/models/place_category_model.dart';
import 'package:spacetime/app/services/place_category_service.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import '../../../../config/app_images.dart';
import 'package:spacetime/app/widgets/filter_section.dart';

import '../../controllers/add_memories_controller.dart';

class MemoriesFilterOverlay extends StatelessWidget {
  bool isOpenedFromMap;
  MemoriesFilterOverlay({super.key, required this.isOpenedFromMap});

  // Helper method to check if a string contains emoji
  bool _isEmoji(String text) {
    if (text.isEmpty) return false;

    // Check if the string contains emoji characters
    // Emojis are typically in Unicode ranges like:
    // U+1F600–U+1F64F (emoticons)
    // U+1F300–U+1F5FF (misc symbols)
    // U+1F680–U+1F6FF (transport)
    // U+1F1E0–U+1F1FF (flags)
    // U+2600–U+26FF (misc symbols)
    // U+2700–U+27BF (dingbats)
    final emojiRegex = RegExp(
      r'[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]',
      unicode: true,
    );
    return emojiRegex.hasMatch(text);
  }

  // Helper method to extract the name part from a category (removing emoji if present)
  String _extractNamePart(String categoryName) {
    if (categoryName.contains(' ') && categoryName.length > 2) {
      final parts = categoryName.split(' ');
      if (parts.length > 1 && _isEmoji(parts[0])) {
        // Return name without emoji
        return parts.skip(1).join(' ');
      }
    }
    // Return original name if no emoji found
    return categoryName;
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<AddMemoriesController>();
    final MapControllerNew? mapController =
        isOpenedFromMap
            ? (Get.isRegistered<MapControllerNew>()
                ? Get.find<MapControllerNew>()
                : Get.put(MapControllerNew()))
            : null;
    final uiController = Get.find<UiController>();
    controller.isOpenedFromMap = isOpenedFromMap;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              controller.resetFilters();
              controller.closeFilter();
              mapController?.resetFilters();
              mapController?.isFilterOpen.value = false;
            },
            child: Container(color: Colors.black.withValues(alpha: 0.5)),
          ),
        ),
        // The actual filter panel
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: FilterPanel(
            onReset: () {
              controller.resetFilters();
              mapController?.resetFilters();
              mapController?.isFilterOpen.value = false;
            },
            onApply: () {
              controller.applyFilters();
              controller.closeFilter();
              if (isOpenedFromMap) {
                mapController?.handleFilterApplyFromMap();
              }
            },
            children: [
              // Date range filters
              const Row(
                children: [
                  Expanded(
                    child: MemoriesFilterTextFieldRow(
                      imagePath: AppImages.calendar,
                      hint: 'From Date',
                    ),
                  ),
                  SizedBox(width: 5),
                  Expanded(
                    child: MemoriesFilterTextFieldRow(
                      imagePath: AppImages.calendar,
                      hint: 'To Date',
                    ),
                  ),
                ],
              ),

              // Location and radius filters
              const Row(
                children: [
                  Expanded(
                    child: MemoriesFilterTextFieldRow(
                      imagePath: AppImages.location,
                      hint: 'Location',
                    ),
                  ),
                  SizedBox(width: 5),
                  Expanded(
                    child: MemoriesFilterTextFieldRow(
                      imagePath: AppImages.location,
                      hint: 'Radius',
                    ),
                  ),
                ],
              ),

              // Search Places (Categories dropdown with chips)
              Obx(() {
                debugPrint(
                  'Filter Overlay: Building Category Filter with ${controller.selectedCategories.length} selected categories',
                );
                return GestureDetector(
                  onTap: () async {
                    // Get all categories from the service
                    final categoryService = PlaceCategoryService();
                    final allCategories =
                        await categoryService.getAllCategoriesFlat();

                    // Convert selected category names to PlaceCategory objects
                    final selectedCategoryObjects = <PlaceCategory>[];
                    for (final categoryName in controller.selectedCategories) {
                      PlaceCategory? categoryObj;

                      // Try matching with combined "emoji name" format
                      categoryObj = allCategories.firstWhereOrNull((cat) {
                        final combinedName =
                            cat.emoji.isNotEmpty
                                ? '${cat.emoji} ${cat.name}'
                                : cat.name;
                        return combinedName.toLowerCase() ==
                            categoryName.toLowerCase();
                      });

                      // If no match, try matching just the name part
                      if (categoryObj == null) {
                        categoryObj = allCategories.firstWhereOrNull((cat) {
                          return cat.name.toLowerCase() ==
                              categoryName.toLowerCase();
                        });
                      }

                      // If still no match, try flexible matching (extract name parts)
                      if (categoryObj == null) {
                        categoryObj = allCategories.firstWhereOrNull((cat) {
                          String catNamePart = _extractNamePart(cat.name);
                          String searchNamePart = _extractNamePart(
                            categoryName,
                          );
                          return catNamePart.toLowerCase() ==
                              searchNamePart.toLowerCase();
                        });
                      }

                      if (categoryObj != null) {
                        selectedCategoryObjects.add(categoryObj);
                      }
                    }

                    final result = await Get.to(
                      () => CategoryPickerWidget(
                        allowMultipleSelection: true,
                        selectedCategories: selectedCategoryObjects,
                      ),
                    );

                    if (result != null && result is List<PlaceCategory>) {
                      // Clear existing selections and add new ones
                      controller.selectedCategories.clear();
                      for (final category in result) {
                        // Store category in format "emoji name" if emoji exists, otherwise just name
                        final categoryDisplay =
                            category.emoji.isNotEmpty
                                ? '${category.emoji} ${category.name}'
                                : category.name;
                        controller.addCategory(categoryDisplay);
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2.0, bottom: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Main category selector
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color:
                                uiController.darkMode.value
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.white,
                          ),
                          child: Row(
                            children: [
                              Image.asset(
                                AppImages.category2,
                                width: 18,
                                height: 18,
                                // color:  uiController.darkMode.value
                                color:
                                    uiController.darkMode.value
                                        ? Colors.white
                                        : Colors.grey[600],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Search Places Categories',
                                  style: TextStyle(
                                    color:
                                        uiController.darkMode.value
                                            ? Colors.white.withValues(
                                              alpha: 0.5,
                                            )
                                            : Colors.grey[600],
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color:
                                    uiController.darkMode.value
                                        ? Colors.white
                                        : Colors.white,
                              ),
                            ],
                          ),
                        ),

                        // Selected categories chips
                        Obx(() {
                          if (controller.selectedCategories.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          return Container(
                            padding: const EdgeInsets.all(8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children:
                                  controller.selectedCategories.map((
                                    categoryName,
                                  ) {
                                    // Extract emoji and name from categoryName using helper method
                                    String emoji = '';
                                    String displayName = _extractNamePart(
                                      categoryName,
                                    );

                                    // Get emoji if present
                                    if (categoryName.contains(' ') &&
                                        categoryName.length > 2) {
                                      final parts = categoryName.split(' ');
                                      if (parts.isNotEmpty &&
                                          _isEmoji(parts[0])) {
                                        emoji = parts[0];
                                      }
                                    }

                                    // If no name part extracted, use full category name
                                    if (displayName.isEmpty) {
                                      displayName = categoryName;
                                    }

                                    return Chip(
                                      avatar:
                                          emoji.isNotEmpty
                                              ? CircleAvatar(
                                                backgroundColor:
                                                    Colors.transparent,
                                                radius: 10,
                                                child: Text(
                                                  emoji,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              )
                                              : Icon(
                                                Icons.place,
                                                size: 14,
                                                color:
                                                    Get.find<UiController>()
                                                            .darkMode
                                                            .value
                                                        ? Colors.white
                                                            .withValues(
                                                              alpha: 0.7,
                                                            )
                                                        : Colors.grey[600],
                                              ),
                                      label: Text(
                                        displayName.isNotEmpty
                                            ? displayName
                                            : categoryName,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      deleteIcon: const Icon(
                                        Icons.close,
                                        size: 16,
                                      ),
                                      onDeleted: () {
                                        debugPrint(
                                          'Removing category: $categoryName',
                                        );
                                        controller.removeCategory(categoryName);
                                      },
                                      backgroundColor:
                                          Get.find<UiController>()
                                                  .darkMode
                                                  .value
                                              ? Colors.white.withValues(
                                                alpha: 0.2,
                                              )
                                              : Colors.blue.withValues(
                                                alpha: 0.1,
                                              ),
                                    );
                                  }).toList(),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }),

              // Hashtags dropdown
              Obx(() {
                debugPrint(
                  'Filter Overlay: Building FilterDropdown for hashtags with ${controller.selectedHashtags.length} selected items',
                );
                return FilterDropdown(
                  key: ValueKey(
                    'hashtags_${controller.selectedHashtags.length}_${controller.selectedHashtags.join(',')}',
                  ),
                  imagePath: AppImages.tag,
                  hint: 'Search Hashtags',
                  items: controller.getAvailableHashtags,
                  selectedItems:
                      controller.selectedHashtags
                          .toList(), // Convert to regular list
                  onItemSelected: controller.addHashtag,
                  onItemRemoved: controller.removeHashtag,
                );
              }),

              // Contacts dropdown
              Obx(() {
                debugPrint(
                  'Filter Overlay: Building FilterDropdown for contacts with ${controller.selectedContacts.length} selected items',
                );
                return FilterDropdown(
                  key: ValueKey(
                    'contacts_${controller.selectedContacts.length}_${controller.selectedContacts.join(',')}',
                  ),
                  imagePath: AppImages.mention,
                  hint: 'Search Contacts',
                  items: controller.getAvailableContacts,
                  selectedItems:
                      controller.selectedContacts
                          .toList(), // Convert to regular list
                  onItemSelected: controller.addContact,
                  onItemRemoved: controller.removeContact,
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}
