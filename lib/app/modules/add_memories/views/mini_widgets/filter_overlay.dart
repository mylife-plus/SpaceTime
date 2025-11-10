import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/filter_fileds.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/filter_dropdown.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/shared/widgets/searchable_category_widget.dart';
import 'package:spacetime/app/shared/widgets/searchable_hashtag_widget.dart';
import 'package:spacetime/app/shared/widgets/searchable_contact_widget.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import '../../../../config/app_images.dart';
import 'package:spacetime/app/widgets/filter_section.dart';

import '../../controllers/add_memories_controller.dart';

class MemoriesFilterOverlay extends StatefulWidget {
  final bool isOpenedFromMap;
  const MemoriesFilterOverlay({super.key, required this.isOpenedFromMap});

  @override
  State<MemoriesFilterOverlay> createState() => _MemoriesFilterOverlayState();
}

class _MemoriesFilterOverlayState extends State<MemoriesFilterOverlay> {
  // Focus nodes for each search field
  final FocusNode _categoryFocusNode = FocusNode();
  final FocusNode _hashtagFocusNode = FocusNode();
  final FocusNode _contactFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Always sync filters bidirectionally when opening filter overlay
    _syncFiltersBidirectionally();
  }

  void _syncFiltersBidirectionally() {
    final addMemoriesController = Get.find<AddMemoriesController>();

    // Check if MapController exists
    if (!Get.isRegistered<MapControllerNew>()) {
      debugPrint('[FilterOverlay] MapController not registered, using AddMemoriesController filters only');
      return;
    }

    final mapController = Get.find<MapControllerNew>();

    // Determine which controller has filters (or more recent filters)
    final addMemoriesHasFilters = addMemoriesController.filterValues.isNotEmpty ||
        addMemoriesController.selectedLocation.value.isNotEmpty ||
        addMemoriesController.selectedRadius.value.isNotEmpty ||
        addMemoriesController.selectedHashtags.isNotEmpty ||
        addMemoriesController.selectedContacts.isNotEmpty ||
        addMemoriesController.selectedCategories.isNotEmpty;

    final mapHasFilters = mapController.filterValues.isNotEmpty ||
        mapController.selectedLocation.value.isNotEmpty ||
        mapController.selectedRadius.value.isNotEmpty ||
        mapController.selectedHashtags.isNotEmpty ||
        mapController.selectedContacts.isNotEmpty ||
        mapController.selectedCategories.isNotEmpty;

    debugPrint('[FilterOverlay] Syncing filters - AddMemories has filters: $addMemoriesHasFilters, Map has filters: $mapHasFilters, Opened from map: ${widget.isOpenedFromMap}');

    if (widget.isOpenedFromMap) {
      // Opened from map view - sync MapController → AddMemoriesController
      debugPrint('[FilterOverlay] Syncing MapController → AddMemoriesController');
      addMemoriesController.filterValues
        ..clear()
        ..addAll(mapController.filterValues);
      addMemoriesController.selectedLocation.value = mapController.selectedLocation.value;
      addMemoriesController.selectedRadius.value = mapController.selectedRadius.value;
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
    } else {
      // Opened from add memories view - sync AddMemoriesController → MapController
      debugPrint('[FilterOverlay] Syncing AddMemoriesController → MapController');
      mapController.filterValues
        ..clear()
        ..addAll(addMemoriesController.filterValues);
      mapController.selectedLocation.value = addMemoriesController.selectedLocation.value;
      mapController.selectedRadius.value = addMemoriesController.selectedRadius.value;
      mapController.selectedHashtags
        ..clear()
        ..addAll(addMemoriesController.selectedHashtags);
      mapController.selectedContacts
        ..clear()
        ..addAll(addMemoriesController.selectedContacts);
      mapController.selectedCategories
        ..clear()
        ..addAll(addMemoriesController.selectedCategories);
      mapController.hasActiveFilters.value = addMemoriesController.hasActiveFilters.value;
    }

    debugPrint('[FilterOverlay] Sync complete - Categories: ${addMemoriesController.selectedCategories.length}, Hashtags: ${addMemoriesController.selectedHashtags.length}, Contacts: ${addMemoriesController.selectedContacts.length}');
  }

  @override
  void dispose() {
    _categoryFocusNode.dispose();
    _hashtagFocusNode.dispose();
    _contactFocusNode.dispose();
    super.dispose();
  }

  /// Handle focus shifting when a field loses focus
  void _handleFocusShift(String fieldName) {
    // Small delay to ensure focus change is processed
    Future.delayed(const Duration(milliseconds: 50), () {
      // Check if any field still has focus
      if (!_categoryFocusNode.hasFocus &&
          !_hashtagFocusNode.hasFocus &&
          !_contactFocusNode.hasFocus) {

        // Shift focus to the next available field
        switch (fieldName) {
          case 'category':
            _hashtagFocusNode.requestFocus();
            debugPrint('[FilterOverlay] Focus shifted from category to hashtag');
            break;
          case 'hashtag':
            _contactFocusNode.requestFocus();
            debugPrint('[FilterOverlay] Focus shifted from hashtag to contact');
            break;
          case 'contact':
            _categoryFocusNode.requestFocus();
            debugPrint('[FilterOverlay] Focus shifted from contact to category');
            break;
        }
      }
    });
  }

  // Helper method to check if a string contains emoji
  bool _isEmoji(String text) {
    if (text.isEmpty) return false;

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
        widget.isOpenedFromMap
            ? (Get.isRegistered<MapControllerNew>()
                ? Get.find<MapControllerNew>()
                : Get.put(MapControllerNew()))
            : null;
    final uiController = Get.find<UiController>();
    controller.isOpenedFromMap = widget.isOpenedFromMap;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              // Just close the filter overlay without resetting filters
              // Filters should persist until manually removed or reset
              controller.closeFilter();
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
              if (widget.isOpenedFromMap) {
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
    
              // Location filter (includes radius)
              const MemoriesFilterTextFieldRow(
                imagePath: AppImages.location,
                hint: 'Location',
              ),
    
                  const SizedBox(height: 2),

              // Search Places Categories - Using Generic SearchableCategoryWidget
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Obx(() => SearchableCategoryWidget(
                    title: 'Search Places Categories',
                    onCategorySelected: (category) {
                      // Use addCategoryGroup to handle both main categories and subcategories properly
                      controller.addCategoryGroup(category);
                      final categoryWithEmoji = category.emoji.isNotEmpty
                          ? '${category.emoji} ${category.name}'
                          : category.name;
                      debugPrint('[FilterOverlay] Added category: $categoryWithEmoji');
                    },
                    onFocusChanged: (isFocused) {
                      if (!isFocused) {
                        _handleFocusShift('category');
                      }
                    },
                    saveToRecent: true, // Show recent categories in filter context
                    showActionButtons: true, // Show "See List" and "Add new" buttons in filter context
                    backgroundColor: uiController.darkMode.value
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.white,
                  )),
    
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
                        children: controller.displayCategories.map((categoryName) {
                          // Extract emoji and name from categoryName using helper method
                          String emoji = '';
                          String displayName = _extractNamePart(categoryName);
    
                          // Get emoji if present
                          if (categoryName.contains(' ') && categoryName.length > 2) {
                            final parts = categoryName.split(' ');
                            if (parts.isNotEmpty && _isEmoji(parts[0])) {
                              emoji = parts[0];
                            }
                          }
    
                          // If no name part extracted, use full category name
                          if (displayName.isEmpty) {
                            displayName = categoryName;
                          }
    
                          return Chip(
                            avatar: emoji.isNotEmpty
                                ? CircleAvatar(
                                    backgroundColor: Colors.transparent,
                                    radius: 10,
                                    child: Text(
                                      emoji,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  )
                                : Icon(
                                    Icons.place,
                                    size: 14,
                                    color: uiController.darkMode.value
                                        ? Colors.white.withValues(alpha: 0.7)
                                        : Colors.grey[600],
                                  ),
                            label: Text(
                              displayName.isNotEmpty ? displayName : categoryName,
                              style: const TextStyle(fontSize: 12),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              debugPrint('Removing category: $categoryName');
                              controller.removeCategory(categoryName);
                            },
                            backgroundColor: uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.blue.withValues(alpha: 0.1),
                          );
                        }).toList(),
                      ),
                    );
                  }),
                ],
              ),
    
              // Spacing between Search Place Categories and Search Hashtags
              const SizedBox(height: 4),
    
              // Search Hashtags - Using SearchableHashtagWidget
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Obx(() => SearchableHashtagWidget(
                    title: 'Search Hashtags',
                    onHashtagSelected: (hashtag) {
                      controller.addHashtag(hashtag);
                      debugPrint('[FilterOverlay] Added hashtag: $hashtag');
                    },
                    onGroupSelected: (group) {
                      controller.addHashtagGroup(group);
                      debugPrint('[FilterOverlay] Added hashtag group: ${group.name}');
                    },
                    onFocusChanged: (isFocused) {
                      if (!isFocused) {
                        _handleFocusShift('hashtag');
                      }
                    },
                    backgroundColor: uiController.darkMode.value
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.white,
                  )),
    
                  // Selected hashtags chips
                  Obx(() {
                    if (controller.selectedHashtags.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Container(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: controller.displayHashtags.map((hashtag) {
                          return Chip(
                            label: Text(
                              '#$hashtag',
                              style: GoogleFonts.kumbhSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              debugPrint('Removing hashtag: $hashtag');
                              controller.removeHashtag(hashtag);
                            },
                            backgroundColor: uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.blue.withValues(alpha: 0.1),
                          );
                        }).toList(),
                      ),
                    );
                  }),
                ],
              ),
    
              // Spacing between Search Hashtags and Search Contacts
              const SizedBox(height: 4),
    
              // Search Contacts - Using SearchableContactWidget
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Obx(() => SearchableContactWidget(
                    title: 'Search Contacts',
                    onContactSelected: (contact) {
                      controller.addContact(contact);
                      debugPrint('[FilterOverlay] Added contact: $contact');
                    },
                    onGroupSelected: (group) {
                      controller.addContactGroup(group);
                      debugPrint('[FilterOverlay] Added contact group: ${group.name}');
                    },
                    onFocusChanged: (isFocused) {
                      if (!isFocused) {
                        _handleFocusShift('contact');
                      }
                    },
                    backgroundColor: uiController.darkMode.value
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.white,
                  )),
    
                  // Selected contacts chips
                  Obx(() {
                    if (controller.selectedContacts.isEmpty) {
                      return const SizedBox.shrink();
                    }

                    return Container(
                      padding: const EdgeInsets.all(8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: controller.displayContacts.map((contact) {
                          return Chip(
                            label: Text(
                              '@$contact',
                              style: const TextStyle(fontSize: 12),
                            ),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              debugPrint('Removing contact: $contact');
                              controller.removeContact(contact);
                            },
                            backgroundColor: uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.blue.withValues(alpha: 0.1),
                          );
                        }).toList(),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
