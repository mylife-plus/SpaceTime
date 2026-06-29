import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/filter_fileds.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/shared/widgets/searchable_category_widget.dart';
import 'package:spacetime/app/shared/widgets/searchable_hashtag_widget.dart';
import 'package:spacetime/app/shared/widgets/searchable_contact_widget.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import '../../../../config/app_images.dart';
import 'package:spacetime/app/widgets/filter_section.dart';

import '../../controllers/add_memories_controller.dart';
import '../../../filter/controllers/filter_controller.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/l10n/place_category_l10n.dart';

class MemoriesFilterOverlay extends StatefulWidget {
  final bool isOpenedFromMap;
  const MemoriesFilterOverlay({super.key, required this.isOpenedFromMap});

  @override
  State<MemoriesFilterOverlay> createState() => _MemoriesFilterOverlayState();
}

class _MemoriesFilterOverlayState extends State<MemoriesFilterOverlay> {
  // Track which search field is focused
  final RxString _focusedSearchField =
      ''.obs; // Values: '', 'categories', 'hashtags', 'contacts'

  @override
  void initState() {
    super.initState();
    // Defer: sync updates Rx / Obx parents and must not run during mount/build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncFiltersBidirectionally();
    });
  }

  /// Handle focus changes from category search field
  void _onCategorySearchFocusChanged(bool isFocused) {
    _focusedSearchField.value = isFocused ? 'categories' : '';
    debugPrint(
      '[FilterOverlay] Category search field focus changed: $isFocused',
    );
  }

  /// Handle focus changes from hashtag search field
  void _onHashtagSearchFocusChanged(bool isFocused) {
    _focusedSearchField.value = isFocused ? 'hashtags' : '';
    debugPrint(
      '[FilterOverlay] Hashtag search field focus changed: $isFocused',
    );
  }

  /// Handle focus changes from contact search field
  void _onContactSearchFocusChanged(bool isFocused) {
    _focusedSearchField.value = isFocused ? 'contacts' : '';
    debugPrint(
      '[FilterOverlay] Contact search field focus changed: $isFocused',
    );
  }

  void _syncFiltersBidirectionally() {
    final addMemoriesController = Get.find<AddMemoriesController>();

    // Check if MapController exists
    if (!Get.isRegistered<MapControllerNew>()) {
      debugPrint(
        '[FilterOverlay] MapController not registered, using AddMemoriesController filters only',
      );
      return;
    }

    final mapController = Get.find<MapControllerNew>();

    // Determine which controller has filters (or more recent filters)
    final addMemoriesHasFilters =
        addMemoriesController.filterValues.isNotEmpty ||
        addMemoriesController.selectedLocation.value.isNotEmpty ||
        addMemoriesController.selectedRadius.value.isNotEmpty ||
        addMemoriesController.selectedHashtags.isNotEmpty ||
        addMemoriesController.selectedContacts.isNotEmpty ||
        addMemoriesController.selectedCategories.isNotEmpty;

    final mapHasFilters =
        mapController.filterValues.isNotEmpty ||
        mapController.selectedLocation.value.isNotEmpty ||
        mapController.selectedRadius.value.isNotEmpty ||
        mapController.selectedHashtags.isNotEmpty ||
        mapController.selectedContacts.isNotEmpty ||
        mapController.selectedCategories.isNotEmpty;

    debugPrint(
      '[FilterOverlay] Syncing filters - AddMemories has filters: $addMemoriesHasFilters, Map has filters: $mapHasFilters, Opened from map: ${widget.isOpenedFromMap}',
    );

    if (widget.isOpenedFromMap) {
      // Opened from map view - sync MapController → AddMemoriesController
      debugPrint(
        '[FilterOverlay] Syncing MapController → AddMemoriesController',
      );
      addMemoriesController.filterValues
        ..clear()
        ..addAll(mapController.filterValues);
      addMemoriesController.selectedLocation.value =
          mapController.selectedLocation.value;
      // addMemoriesController.selectedLocationDisplayName.value = mapController.selectedLocationDisplayName.value;
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
    } else {
      // Opened from add memories view - sync AddMemoriesController → MapController
      debugPrint(
        '[FilterOverlay] Syncing AddMemoriesController → MapController',
      );
      mapController.filterValues
        ..clear()
        ..addAll(addMemoriesController.filterValues);
      mapController.selectedLocation.value =
          addMemoriesController.selectedLocation.value;
      // mapController.selectedLocationDisplayName.value = addMemoriesController.selectedLocationDisplayName.value;
      mapController.selectedRadius.value =
          addMemoriesController.selectedRadius.value;
      mapController.selectedHashtags
        ..clear()
        ..addAll(addMemoriesController.selectedHashtags);
      mapController.selectedContacts
        ..clear()
        ..addAll(addMemoriesController.selectedContacts);
      mapController.selectedCategories
        ..clear()
        ..addAll(addMemoriesController.selectedCategories);
      mapController.hasActiveFilters.value =
          addMemoriesController.hasActiveFilters.value;
    }

    debugPrint(
      '[FilterOverlay] Sync complete - Categories: ${addMemoriesController.selectedCategories.length}, Hashtags: ${addMemoriesController.selectedHashtags.length}, Contacts: ${addMemoriesController.selectedContacts.length}',
    );
  }

  bool _validateDateRangeOrShowError(AddMemoriesController controller) {
    final fromDateStr = controller.filterValues['from date'];
    final toDateStr = controller.filterValues['to date'];
    if ((fromDateStr?.isNotEmpty ?? false) &&
        (toDateStr?.isNotEmpty ?? false)) {
      try {
        final from = DateTime.parse(fromDateStr!);
        final to = DateTime.parse(toDateStr!);
        final fromDateOnly = DateTime(from.year, from.month, from.day);
        final toDateOnly = DateTime(to.year, to.month, to.day);
        if (toDateOnly.isBefore(fromDateOnly)) {
          showTrSnackbar(
            'snackbar_invalid_date_range_2',
            backgroundColor: Colors.red.shade400,
            colorText: Colors.white,
            margin: const EdgeInsets.all(12),
            snackPosition: SnackPosition.TOP,
            duration: const Duration(seconds: 2),
          );
          return false;
        }
      } catch (e) {
        debugPrint('[FilterOverlay] Date validation parse error: $e');
      }
    }
    return true;
  }

  @override
  void dispose() {
    super.dispose();
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
      body: Obx(
        () => Container(
          decoration: BoxDecoration(
            color: uiController.filterOverlayBackgroundColor,
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
                  child: FilterPanel(
                    onBack: () {
                      controller.closeFilter();
                      mapController?.isFilterOpen.value = false;
                    },
                    onReset: () async {
                      debugPrint(
                        '[FilterOverlay] 🔄 Resetting all filters EXCEPT search...',
                      );

                      final mapController = Get.find<MapControllerNew>();
                      final filterController = Get.find<FilterController>();

                      // Clear all filters EXCEPT search from FilterController
                      filterController.resetFiltersExceptSearch();

                      debugPrint(
                        '[FilterOverlay] ✅ Filters reset (search preserved: "${filterController.searchedTextKeyword.value}")',
                      );

                      // Close filter overlay and reload with delay
                      Future.delayed(Duration(milliseconds: 500), () {
                        closefilterAndReset(mapController, filterController);
                      });
                    },
                    onApply: () async {
                      final mapController = Get.find<MapControllerNew>();
                      if (!_validateDateRangeOrShowError(controller)) {
                        return;
                      }

                      // Apply filters (this will clear memory ID filters automatically)
                      debugPrint(
                        '[FilterOverlay] 🎯 Applying filters from overlay',
                      );
                      controller.applyFilters();

                      mapController.closeFilter();
                      await mapController.loadFilteredMemoriesFromDB();
                      mapController.handleFilterApplyFromMap();
                    },
                    hideButtons:
                        _focusedSearchField
                            .value
                            .isNotEmpty, // Hide buttons when any search field is focused
                    children: [
                      // Date range filters - Hidden when any search field is focused
                      Obx(
                        () =>
                            _focusedSearchField.value.isNotEmpty
                                ? const SizedBox.shrink()
                                : Row(
                                  children: [
                                    Expanded(
                                      child: MemoriesFilterTextFieldRow(
                                        imagePath: AppImages.calendar,
                                        hint:
                                            'memories_filter_label_from_date'
                                                .tr,
                                        filterStorageKey: 'from date',
                                        borderRadius: 5,
                                      ),
                                    ),
                                    SizedBox(width: 5),
                                    Expanded(
                                      child: MemoriesFilterTextFieldRow(
                                        imagePath: AppImages.calendar,
                                        hint:
                                            'memories_filter_label_to_date'.tr,
                                        filterStorageKey: 'to date',
                                        borderRadius: 5,
                                      ),
                                    ),
                                  ],
                                ),
                      ),

                      // Location filter (includes radius) - Hidden when any search field is focused
                      Obx(
                        () =>
                            _focusedSearchField.value.isNotEmpty
                                ? const SizedBox.shrink()
                                : MemoriesFilterTextFieldRow(
                                  imagePath: AppImages.location,
                                  hint: 'memories_filter_label_location'.tr,
                                  filterStorageKey: 'location',
                                  borderRadius: 5,
                                ),
                      ),

                      Obx(
                        () =>
                            _focusedSearchField.value.isNotEmpty
                                ? const SizedBox.shrink()
                                : const SizedBox(height: 2),
                      ),

                      // Search Places Categories - Hidden when hashtags or contacts are focused
                      Obx(
                        () =>
                            (_focusedSearchField.value == 'hashtags' ||
                                    _focusedSearchField.value == 'contacts')
                                ? const SizedBox.shrink()
                                : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SearchableCategoryWidget(
                                      title:
                                          'title_literal_search_places_categories'
                                              .tr,
                                      onCategorySelected: (category) {
                                        // Use addCategoryGroup to handle both main categories and subcategories properly
                                        controller.addCategoryGroup(category);
                                        final categoryWithEmoji =
                                            category.emoji.isNotEmpty
                                                ? '${category.emoji} ${category.name}'
                                                : category.name;
                                        debugPrint(
                                          '[FilterOverlay] Added category: $categoryWithEmoji',
                                        );
                                      },
                                      onMultipleCategoriesSelectedFromPicker: (
                                        categories,
                                      ) {
                                        // Replace entire selection when coming back from picker
                                        controller.replaceSelectedCategories(
                                          categories,
                                        );
                                        debugPrint(
                                          '[FilterOverlay] Replaced categories with ${categories.length} new categories',
                                        );
                                      },
                                      onFocusChanged:
                                          _onCategorySearchFocusChanged, // Hide top views when focused
                                      saveToRecent:
                                          true, // Show recent categories in filter context
                                      showActionButtons:
                                          true, // Show "See List" button in filter context
                                      showAddNewButton:
                                          false, // Hide "Add new" button in filter context
                                      previouslySelectedCategories:
                                          controller.selectedCategories
                                              .toList(), // Pass previously selected categories
                                      isInFilterMode:
                                          true, // Remove bottom padding in filter mode
                                      backgroundColor:
                                          uiController.darkMode.value
                                              ? Colors.white.withValues(
                                                alpha: 0.2,
                                              )
                                              : Colors.white,
                                      borderRadius: 5,
                                    ),

                                    // Selected categories chips
                                    Obx(() {
                                      final _ =
                                          uiController.selectedLanguage.value;
                                      if (controller
                                          .selectedCategories
                                          .isEmpty) {
                                        return const SizedBox.shrink();
                                      }

                                      return Container(
                                        padding: const EdgeInsets.all(8),
                                        child: Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children:
                                              controller.displayCategories.map((
                                                categoryName,
                                              ) {
                                                return Chip(
                                                  label: Text(
                                                    localizedPlaceCategoryStoredLabel(
                                                      categoryName,
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  deleteIcon: const Icon(
                                                    Icons.close,
                                                    size: 16,
                                                  ),
                                                  onDeleted: () {
                                                    debugPrint(
                                                      'Removing category: $categoryName',
                                                    );
                                                    controller.removeCategory(
                                                      categoryName,
                                                    );
                                                  },
                                                  backgroundColor:
                                                      uiController
                                                              .darkMode
                                                              .value
                                                          ? Colors.white
                                                              .withValues(
                                                                alpha: 0.2,
                                                              )
                                                          : Colors.blue
                                                              .withValues(
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

                      // Spacing between Search Place Categories and Search Hashtags - Hidden when contacts are focused
                      Obx(
                        () =>
                            _focusedSearchField.value == 'contacts'
                                ? const SizedBox.shrink()
                                : const SizedBox(height: 4),
                      ),

                      // Search Hashtags - Hidden when contacts are focused
                      Obx(
                        () =>
                            _focusedSearchField.value == 'contacts'
                                ? const SizedBox.shrink()
                                : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SearchableHashtagWidget(
                                      title: 'title_literal_search_hashtags'.tr,
                                      onHashtagSelected: (hashtag) {
                                        controller.addHashtag(hashtag);
                                        debugPrint(
                                          '[FilterOverlay] Added hashtag: $hashtag',
                                        );
                                      },
                                      onGroupSelected: (group) {
                                        controller.addHashtagGroup(group);
                                        debugPrint(
                                          '[FilterOverlay] Added hashtag group: ${group.name}',
                                        );
                                      },
                                      onMultipleGroupsSelectedFromPicker: (
                                        groups,
                                      ) {
                                        // Replace entire selection when coming back from picker
                                        controller.replaceSelectedHashtags(
                                          groups,
                                        );
                                        debugPrint(
                                          '[FilterOverlay] Replaced hashtags with ${groups.length} new groups',
                                        );
                                      },
                                      onFocusChanged:
                                          _onHashtagSearchFocusChanged, // Hide top views when focused
                                      previouslySelectedHashtags:
                                          controller.selectedHashtags
                                              .toList(), // Pass previously selected hashtags
                                      isInFilterMode:
                                          true, // Remove bottom padding in filter mode
                                      backgroundColor:
                                          uiController.darkMode.value
                                              ? Colors.white.withValues(
                                                alpha: 0.2,
                                              )
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
                                          children:
                                              controller.displayHashtags.map((
                                                hashtag,
                                              ) {
                                                return Chip(
                                                  label: Text(
                                                    trKey('label_hashtag', [
                                                      hashtag,
                                                    ]),
                                                    style:
                                                        GoogleFonts.kumbhSans(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w400,
                                                        ),
                                                  ),
                                                  deleteIcon: const Icon(
                                                    Icons.close,
                                                    size: 16,
                                                  ),
                                                  onDeleted: () {
                                                    debugPrint(
                                                      'Removing hashtag: $hashtag',
                                                    );
                                                    controller.removeHashtag(
                                                      hashtag,
                                                    );
                                                  },
                                                  backgroundColor:
                                                      uiController
                                                              .darkMode
                                                              .value
                                                          ? Colors.white
                                                              .withValues(
                                                                alpha: 0.2,
                                                              )
                                                          : Colors.blue
                                                              .withValues(
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

                      // Spacing between Search Hashtags and Search Contacts
                      const SizedBox(height: 4),

                      // Search Contacts - Using SearchableContactWidget
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Obx(
                            () => SearchableContactWidget(
                              title: 'title_literal_search_contacts'.tr,
                              onContactSelected: (contact) {
                                controller.addContact(contact);
                                debugPrint(
                                  '[FilterOverlay] Added contact: $contact',
                                );
                              },
                              onGroupSelected: (group) {
                                controller.addContactGroup(group);
                                debugPrint(
                                  '[FilterOverlay] Added contact group: ${group.name}',
                                );
                              },
                              onMultipleGroupsSelectedFromPicker: (groups) {
                                // Replace entire selection when coming back from picker
                                controller.replaceSelectedContacts(groups);
                                debugPrint(
                                  '[FilterOverlay] Replaced contacts with ${groups.length} new groups',
                                );
                              },
                              onFocusChanged:
                                  _onContactSearchFocusChanged, // Hide top views when focused
                              previouslySelectedContacts:
                                  controller.selectedContacts
                                      .toList(), // Pass previously selected contacts
                              isInFilterMode:
                                  true, // Remove bottom padding in filter mode
                              backgroundColor:
                                  uiController.darkMode.value
                                      ? Colors.white.withValues(alpha: 0.2)
                                      : Colors.white,
                              borderRadius: 5,
                            ),
                          ),

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
                                children:
                                    controller.displayContacts.map((contact) {
                                      return Chip(
                                        label: Text(
                                          trKey('label_contact', [contact]),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        deleteIcon: const Icon(
                                          Icons.close,
                                          size: 16,
                                        ),
                                        onDeleted: () {
                                          debugPrint(
                                            'Removing contact: $contact',
                                          );
                                          controller.removeContact(contact);
                                        },
                                        backgroundColor:
                                            uiController.darkMode.value
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
                    ],
                  ),
                  // ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> closefilterAndReset(
    MapControllerNew? mapController,
    FilterController filterController,
  ) async {
    debugPrint(
      '[FilterOverlay] 📊 Loaded ${filterController.filteredMemories.length} memories',
    );

    // Reload AddMemories view
    if (Get.isRegistered<AddMemoriesController>()) {
      final addMemoriesController = Get.find<AddMemoriesController>();
      await addMemoriesController.loadMemoriesFromDatabase();
      addMemoriesController.isFilterOpen.value = false;
    }

    // Close filter overlay and reload map
    mapController?.isFilterOpen.value = false;
    await mapController?.loadMemoriesFromDB(
      filterController.filteredMemories.toList(),
    );
    mapController?.showLoadedDataOnMap();

    debugPrint('[FilterOverlay] ✅ Map reloaded');
  }
}
