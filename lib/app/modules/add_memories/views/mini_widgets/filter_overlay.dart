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
  // Track which search field is focused
  final RxString _focusedSearchField = ''.obs; // Values: '', 'categories', 'hashtags', 'contacts'

  @override
  void initState() {
    super.initState();
    // Always sync filters bidirectionally when opening filter overlay
    _syncFiltersBidirectionally();
  }

  /// Handle focus changes from category search field
  void _onCategorySearchFocusChanged(bool isFocused) {
    _focusedSearchField.value = isFocused ? 'categories' : '';
    debugPrint('[FilterOverlay] Category search field focus changed: $isFocused');
  }

  /// Handle focus changes from hashtag search field
  void _onHashtagSearchFocusChanged(bool isFocused) {
    _focusedSearchField.value = isFocused ? 'hashtags' : '';
    debugPrint('[FilterOverlay] Hashtag search field focus changed: $isFocused');
  }

  /// Handle focus changes from contact search field
  void _onContactSearchFocusChanged(bool isFocused) {
    _focusedSearchField.value = isFocused ? 'contacts' : '';
    debugPrint('[FilterOverlay] Contact search field focus changed: $isFocused');
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
    super.dispose();
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
    return Scaffold(
      body: Container(
          decoration: BoxDecoration(
        color: uiController.darkMode.value
                  ? uiController.mainColor.value == 'blue'
                      ? Color(0xFF001937)
                      : uiController.iconColor2
                  : uiController.mainColor.value == 'blue'
                  ? Color(0xFF92C3FF)
                  : uiController.primaryColor,
       // boxShadow: [
      //   BoxShadow(
      //     color: Colors.black.withOpacity(0.11),
      //     blurRadius: 10,
      //     offset: const Offset(0, 2),
      //   ),
      // ],
        ),
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Stack(
            children: [
               
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Obx(() => FilterPanel(
                        onBack: () {
                          controller.closeFilter();
                          mapController?.isFilterOpen.value = false;
                        },
                        onReset: () {
                          controller.resetFilters();
                          mapController?.resetFilters();
                          mapController?.isFilterOpen.value = false;
                        },
                        onApply: () {
                          controller.applyFilters();
                          // applyFilters() already closes the panel, no need to call closeFilter()
                          if (widget.isOpenedFromMap) {
                            mapController?.handleFilterApplyFromMap();
                          }
                        },
                        hideButtons: _focusedSearchField.value.isNotEmpty, // Hide buttons when any search field is focused
                        children: [
                          // Date range filters - Hidden when any search field is focused
                          Obx(() => _focusedSearchField.value.isNotEmpty
                              ? const SizedBox.shrink()
                              : const Row(
                                  children: [
                                    Expanded(
                                      child: MemoriesFilterTextFieldRow(
                                        imagePath: AppImages.calendar,
                                        hint: 'From Date',
                                        borderRadius: 5,
                                      ),
                                    ),
                                    SizedBox(width: 5),
                                    Expanded(
                                      child: MemoriesFilterTextFieldRow(
                                        imagePath: AppImages.calendar,
                                        hint: 'To Date',
                                        borderRadius: 5,
                                      ),
                                    ),
                                  ],
                                )),

                          // Location filter (includes radius) - Hidden when any search field is focused
                          Obx(() => _focusedSearchField.value.isNotEmpty
                              ? const SizedBox.shrink()
                              : const MemoriesFilterTextFieldRow(
                                  imagePath: AppImages.location,
                                  hint: 'Location',
                                  borderRadius: 5,
                                )),

                          Obx(() => _focusedSearchField.value.isNotEmpty
                              ? const SizedBox.shrink()
                              : const SizedBox(height: 2)),
                
                          // Search Places Categories - Hidden when hashtags or contacts are focused
                          Obx(() => (_focusedSearchField.value == 'hashtags' || _focusedSearchField.value == 'contacts')
                              ? const SizedBox.shrink()
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SearchableCategoryWidget(
                                      title: 'Search Places Categories',
                                      onCategorySelected: (category) {
                                        // Use addCategoryGroup to handle both main categories and subcategories properly
                                        controller.addCategoryGroup(category);
                                        final categoryWithEmoji = category.emoji.isNotEmpty
                                            ? '${category.emoji} ${category.name}'
                                            : category.name;
                                        debugPrint('[FilterOverlay] Added category: $categoryWithEmoji');
                                      },
                                      onMultipleCategoriesSelectedFromPicker: (categories) {
                                        // Replace entire selection when coming back from picker
                                        controller.replaceSelectedCategories(categories);
                                        debugPrint('[FilterOverlay] Replaced categories with ${categories.length} new categories');
                                      },
                                      onFocusChanged: _onCategorySearchFocusChanged, // Hide top views when focused
                                      saveToRecent: true, // Show recent categories in filter context
                                      showActionButtons: true, // Show "See List" button in filter context
                                      showAddNewButton: false, // Hide "Add new" button in filter context
                                      previouslySelectedCategories: controller.selectedCategories.toList(), // Pass previously selected categories
                                      isInFilterMode: true, // Remove bottom padding in filter mode
                                      backgroundColor: uiController.darkMode.value
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : Colors.white,
                                      borderRadius: 5,
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
                                              label: Text(
                                                displayName.isNotEmpty ? '$emoji $displayName' : '$categoryName',
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
                                )),
                
                          // Spacing between Search Place Categories and Search Hashtags - Hidden when contacts are focused
                          Obx(() => _focusedSearchField.value == 'contacts'
                              ? const SizedBox.shrink()
                              : const SizedBox(height: 4)),

                          // Search Hashtags - Hidden when contacts are focused
                          Obx(() => _focusedSearchField.value == 'contacts'
                              ? const SizedBox.shrink()
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SearchableHashtagWidget(
                                      title: 'Search Hashtags',
                                      onHashtagSelected: (hashtag) {
                                        controller.addHashtag(hashtag);
                                        debugPrint('[FilterOverlay] Added hashtag: $hashtag');
                                      },
                                      onGroupSelected: (group) {
                                        controller.addHashtagGroup(group);
                                        debugPrint('[FilterOverlay] Added hashtag group: ${group.name}');
                                      },
                                      onMultipleGroupsSelectedFromPicker: (groups) {
                                        // Replace entire selection when coming back from picker
                                        controller.replaceSelectedHashtags(groups);
                                        debugPrint('[FilterOverlay] Replaced hashtags with ${groups.length} new groups');
                                      },
                                      onFocusChanged: _onHashtagSearchFocusChanged, // Hide top views when focused
                                      previouslySelectedHashtags: controller.selectedHashtags.toList(), // Pass previously selected hashtags
                                      isInFilterMode: true, // Remove bottom padding in filter mode
                                      backgroundColor: uiController.darkMode.value
                                          ? Colors.white.withValues(alpha: 0.2)
                                          : Colors.white,
                                      borderRadius: 5,
                                    ),

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
                                )),
                
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
                                onMultipleGroupsSelectedFromPicker: (groups) {
                                  // Replace entire selection when coming back from picker
                                  controller.replaceSelectedContacts(groups);
                                  debugPrint('[FilterOverlay] Replaced contacts with ${groups.length} new groups');
                                },
                                onFocusChanged: _onContactSearchFocusChanged, // Hide top views when focused
                                previouslySelectedContacts: controller.selectedContacts.toList(), // Pass previously selected contacts
                                isInFilterMode: true, // Remove bottom padding in filter mode
                                backgroundColor: uiController.darkMode.value
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.white,
                                borderRadius: 5,
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
                      )),
                    ),
                  ),
                ],
              ),
        ),
      ),
    );
  }
}
