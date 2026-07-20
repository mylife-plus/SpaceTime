import 'dart:math' as math;
import 'dart:io';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../services/memory_db.dart';
import '../../../models/hashtag_group_model.dart';
import '../../../models/contact_group_model.dart';
import '../../../models/place_category_model.dart';
import '../../../services/hashtag_group_service.dart';
import '../../../services/contact_group_service.dart';
import '../../../services/place_category_service.dart';
import '../../memories/controllers/memory_controller.dart';
import '../../map/controllers/map_controller_new.dart';
import '../../add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/l10n/place_category_l10n.dart';

/// Dedicated controller for managing all filter-related logic
/// Used by both MemoriesFilterOverlay and SearchMemoriesView
class FilterController extends GetxController {
  static const String tag = '[FilterController]';

  // ============================================================================
  // FILTER STATE
  // ============================================================================

  /// Text-based filter values (e.g., title, description)
  final RxMap<String, String> filterValues = <String, String>{}.obs;

  /// Location filter - stores coordinates "lat,lng"
  final RxString selectedLocation = ''.obs;

  /// Location display name for UI
  final RxString selectedLocationDisplayName = ''.obs;

  /// Location flag (country flag emoji)
  final RxString selectedLocationFlag = ''.obs;

  /// Radius filter in meters
  final RxString selectedRadius = ''.obs;

  /// Selected hashtag filters
  final RxList<String> selectedHashtags = <String>[].obs;

  /// Selected contact filters
  final RxList<String> selectedContacts = <String>[].obs;

  /// Selected category filters
  final RxList<String> selectedCategories = <String>[].obs;

  /// Filter by specific memory IDs (from map/filter)
  final RxList<String> selectedMemoryIds = <String>[].obs;

  /// Filter by specific memory IDs (from search)
  final RxList<String> searchedMemoryIds = <String>[].obs;

  /// Whether any filters are currently active
  final RxBool hasActiveFilters = false.obs;

  /// Whether search filter is active (takes precedence over other filters)
  final RxBool isSearchedMemoryList = false.obs;

  // ============================================================================
  // CACHED DATA
  // ============================================================================

  /// All memories loaded from database (global Rx variable)
  final RxList<Map<String, dynamic>> allMemories = <Map<String, dynamic>>[].obs;

  /// Filtered memories after applying all filters
  final RxList<Map<String, dynamic>> filteredMemories =
      <Map<String, dynamic>>[].obs;

  /// Total results count after applying filters
  final RxInt totalResults = 0.obs;

  /// Indicator type (search vs filter)
  final RxString indicatorType = ''.obs; // 'search' or 'filter'

  /// Search keywords (preserved when in search mode)
  final RxString searchKeywords = ''.obs;

  /// Searched text keyword for text-based search filtering
  final RxString searchedTextKeyword = ''.obs;

  /// Loading state for memories
  final RxBool isLoadingMemories = false.obs;

  /// Cached hierarchical data for display logic
  List<HashtagGroup> _cachedHashtagGroups = [];
  List<ContactGroup> _cachedContactGroups = [];
  List<PlaceCategory> _cachedCategories = [];

  /// Available filter items
  final RxList<String> availableHashtags = <String>[].obs;
  final RxList<String> availableContacts = <String>[].obs;
  final RxList<String> availableCategories = <String>[].obs;

  // ============================================================================
  // SERVICES
  // ============================================================================

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  // ============================================================================
  // COMPUTED GETTERS
  // ============================================================================

  /// Display hashtags - show only main groups when all subs are selected
  List<String> get displayHashtags => _getDisplayHashtags();

  /// Display contacts - show only main groups when all subs are selected
  List<String> get displayContacts => _getDisplayContacts();

  /// Display categories - show only main categories when all subs are selected
  List<String> get displayCategories => _getDisplayCategories();

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  @override
  void onInit() {
    super.onInit();
    debugPrint('$tag onInit called');
    _loadFilterData();
  }

  // ============================================================================
  // FILTER DATA LOADING
  // ============================================================================

  /// Load filter data for dropdowns
  /// This loads all memories from database, extracts unique tags/mentions/categories,
  /// and applies any selected filters
  Future<void> _loadFilterData() async {
    // Use the new loadAndApplyFilters method which handles UI transformation
    await loadAndApplyFilters();
  }

  // ============================================================================
  // FILTER APPLICATION METHODS
  // ============================================================================

  /// Apply all filters to allMemories and update filteredMemories
  void applyAllFilters() {
    debugPrint('$tag 🔧 Applying all filters...');

    // Start with all memories
    List<Map<String, dynamic>> result = List.from(allMemories);
    filteredMemories.clear();
    // Apply each filter type in sequence
    result = _applyDateFilter(result);
    result = _applySearchedTextFilter(result);

    // result = _applyTextFilters(result);
    result = _applyHashtagFilters(result);
    result = _applyContactFilters(result);
    result = _applyCategoryFilters(result);
    result = _applyLocationFilters(result);
    result = _applyMemoryIdFilters(result);
    result = _applySearchFilters(result);

    // Update filtered memories and total results
    filteredMemories.value = result;
    totalResults.value = result.length;

    // Update indicator type if not search
    if (!isSearchedMemoryList.value) {
      indicatorType.value = hasActiveFilters.value ? 'filter' : '';
    }

    debugPrint(
      '$tag ✅ Filters applied: ${totalResults.value} results from ${allMemories.length} total memories',
    );
  }

  void applyAllFilters1() {
    debugPrint('$tag 🔧 Applying all filters...');

    // Start with all memories
    List<Map<String, dynamic>> result = List.from(allMemories);
    filteredMemories.clear();

    // Apply search filters FIRST if active (search takes precedence)
    // This ensures search results are filtered first, then other filters narrow them down
    result = _applySearchFilters(result);

    // Apply each filter type in sequence to narrow down results
    result = _applySearchedTextFilter(result);

    result = _applyTextFilters(result);
    result = _applyHashtagFilters(result);
    result = _applyContactFilters(result);
    result = _applyCategoryFilters(result);
    result = _applyLocationFilters(result);
    result = _applyMemoryIdFilters(result);

    // Update filtered memories and total results
    filteredMemories.value = result;
    totalResults.value = result.length;

    // Update indicator type if not search
    if (!isSearchedMemoryList.value) {
      indicatorType.value = hasActiveFilters.value ? 'filter' : '';
    }

    debugPrint(
      '$tag ✅ Filters applied: ${totalResults.value} results from ${allMemories.length} total memories',
    );
  }

  /// Apply searched text keyword filter (text-based search)
  List<Map<String, dynamic>> _applySearchedTextFilter(
    List<Map<String, dynamic>> memories,
  ) {
    if (searchedTextKeyword.value.isEmpty) {
      debugPrint('$tag   ⏭️  No searched text keyword to apply');
      return memories;
    }

    final keyword = searchedTextKeyword.value.toLowerCase().trim();
    debugPrint('$tag   🔍 Applying searched text filter: "$keyword"');

    return memories.where((memory) {
      final description =
          (memory[DatabaseHelper.columnDescription] as String?)
              ?.toLowerCase() ??
          '';
      final tags =
          (memory[DatabaseHelper.columnTags] as String?)?.toLowerCase() ?? '';
      final mentions =
          (memory[DatabaseHelper.columnMentions] as String?)?.toLowerCase() ??
          '';
      final categoryRaw =
          memory[DatabaseHelper.columnCategory] as String? ?? '';
      final category = categoryRaw.toLowerCase();
      final categoryHaystack = placeCategorySearchHaystack(categoryRaw);
      // final locationName =
      //     (memory[DatabaseHelper.columnLocationName] as String?)
      //         ?.toLowerCase() ??
      //     '';
      final locationAddress =
          (memory[DatabaseHelper.columnLocationAddress] as String?)
              ?.toLowerCase() ??
          '';
      final locationCity =
          (memory[DatabaseHelper.columnLocationCity] as String?)
              ?.toLowerCase() ??
          '';
      final locationCountry =
          (memory[DatabaseHelper.columnLocationCountry] as String?)
              ?.toLowerCase() ??
          '';
      // Search in all text fields

      final searchableText =
          '$description $tags @$tags #$mentions $mentions $category $categoryHaystack $locationAddress $locationCity $locationCountry'
              .toLowerCase();

      if (keyword[0] == '@' || keyword[0] == '#') {
        var contains = searchableText.contains(keyword.substring(1));
        return contains;
      }

      var contains = searchableText.contains(keyword);

      debugPrint(
        '$tag   🔍 Description  contains $searchableText $contains: "$keyword"',
      );

      return contains;
    }).toList();
  }

  /// Apply date range filter (FROM date inclusive, TO date inclusive)
  List<Map<String, dynamic>> _applyDateFilter(
    List<Map<String, dynamic>> memories,
  ) {
    final fromDateStr = filterValues['from date'];
    final toDateStr = filterValues['to date'];

    // No date filters → return all
    if ((fromDateStr == null || fromDateStr.isEmpty) &&
        (toDateStr == null || toDateStr.isEmpty)) {
      debugPrint('$tag ⏭️ No date filters to apply');
      return memories;
    }

    debugPrint(
      '$tag 📅 Applying date filter | from="$fromDateStr" | to="$toDateStr"',
    );

    return memories.where((memory) {
      try {
        final memoryDateText = memory['date'] as String? ?? '';
        final memoryYearText = memory['year'] as String? ?? '';

        if (memoryDateText.isEmpty || memoryYearText.isEmpty) {
          debugPrint('$tag ⚠️ Memory has no date, skipping');
          return false;
        }

        // ---- Parse memory date: "15. January" + "2026"
        final parts = memoryDateText.split('.');
        if (parts.length < 2) {
          debugPrint('$tag ⚠️ Invalid memory date format: $memoryDateText');
          return false;
        }

        const months = {
          'january': 1,
          'february': 2,
          'march': 3,
          'april': 4,
          'may': 5,
          'june': 6,
          'july': 7,
          'august': 8,
          'september': 9,
          'october': 10,
          'november': 11,
          'december': 12,
        };

        final day = int.tryParse(parts[0].trim());
        final monthName = parts[1].trim().toLowerCase();
        final month = months[monthName];
        final year = int.tryParse(memoryYearText);

        if (day == null || month == null || year == null) {
          debugPrint(
            '$tag ⚠️ Failed to parse memory date: $memoryDateText $memoryYearText',
          );
          return false;
        }

        final memoryDate = DateTime(year, month, day);

        // ---- FROM date (start of day)
        if (fromDateStr != null && fromDateStr.isNotEmpty) {
          final from = DateTime.parse(fromDateStr);
          final fromDateStart = DateTime(from.year, from.month, from.day);

          if (memoryDate.isBefore(fromDateStart)) {
            debugPrint(
              '$tag ❌ Memory $memoryDate is before FROM $fromDateStart',
            );
            return false;
          }
        }

        // ---- TO date (end of day)
        if (toDateStr != null && toDateStr != "null" && toDateStr.isNotEmpty) {
          final to = DateTime.parse(toDateStr);
          final toDateEnd = DateTime(
            to.year,
            to.month,
            to.day,
            23,
            59,
            59,
            999,
          );

          if (memoryDate.isAfter(toDateEnd)) {
            debugPrint('$tag ❌ Memory $memoryDate is after TO $toDateEnd');
            return false;
          }
        }

        // ---- Passed all filters
        debugPrint('$tag ✅ Memory $memoryDate passed date filter');
        return true;
      } catch (e) {
        debugPrint('$tag ⚠️ Error in date filter: $e');
        return false;
      }
    }).toList();
  }

  /// Apply text-based filters (title, description, etc.)
  /// Excludes date filters which are handled separately by _applyDateFilter
  List<Map<String, dynamic>> _applyTextFilters(
    List<Map<String, dynamic>> memories,
  ) {
    // Filter out date-related keys from filterValues
    final textFilters = Map<String, String>.from(filterValues);
    textFilters.remove('from date');
    textFilters.remove('to date');

    if (textFilters.isEmpty) {
      debugPrint('$tag   ⏭️  No text filters to apply');
      return memories;
    }

    debugPrint(
      '$tag   📝 Applying text filters: ${textFilters.length} filters',
    );

    return memories.where((memory) {
      final description =
          (memory[DatabaseHelper.columnDescription] as String?)
              ?.toLowerCase() ??
          '';
      final tags =
          (memory[DatabaseHelper.columnTags] as String?)?.toLowerCase() ?? '';
      final mentions =
          (memory[DatabaseHelper.columnMentions] as String?)?.toLowerCase() ??
          '';
      final categoryRaw =
          memory[DatabaseHelper.columnCategory] as String? ?? '';
      final category = categoryRaw.toLowerCase();
      final categoryHaystack = placeCategorySearchHaystack(categoryRaw);

      final searchableText =
          '$description $tags $mentions $category $categoryHaystack';

      // Check if all filter values are present in searchable text
      for (final entry in textFilters.entries) {
        final value = entry.value;
        if (value.isEmpty) continue;
        if (!searchableText.contains(value.toLowerCase())) {
          debugPrint(
            '$tag   ❌ Memory does not contain text filter: "${entry.key}" = "$value"',
          );
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Apply hashtag filters
  List<Map<String, dynamic>> _applyHashtagFilters(
    List<Map<String, dynamic>> memories,
  ) {
    if (selectedHashtags.isEmpty) {
      debugPrint('$tag   ⏭️  No hashtag filters to apply');
      return memories;
    }

    debugPrint(
      '$tag   #️⃣ Applying hashtag filters: ${selectedHashtags.length} hashtags',
    );

    return memories.where((memory) {
      final tags =
          (memory[DatabaseHelper.columnTags] as String?)?.toLowerCase() ?? '';
      final description =
          (memory[DatabaseHelper.columnDescription] as String?)
              ?.toLowerCase() ??
          '';

      // Check if any of the selected hashtags match
      for (final hashtag in selectedHashtags) {
        final tagLower = hashtag.toLowerCase();
        if (tags.contains(tagLower) || description.contains('#$tagLower')) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  /// Apply contact/mention filters
  List<Map<String, dynamic>> _applyContactFilters(
    List<Map<String, dynamic>> memories,
  ) {
    if (selectedContacts.isEmpty) {
      debugPrint('$tag   ⏭️  No contact filters to apply');
      return memories;
    }

    debugPrint(
      '$tag   👤 Applying contact filters: ${selectedContacts.length} contacts',
    );

    return memories.where((memory) {
      final mentions =
          (memory[DatabaseHelper.columnMentions] as String?)?.toLowerCase() ??
          '';
      final description =
          (memory[DatabaseHelper.columnDescription] as String?)
              ?.toLowerCase() ??
          '';

      // Check if any of the selected contacts match
      for (final contact in selectedContacts) {
        final contactLower = contact.toLowerCase();
        if (mentions.contains(contactLower) ||
            description.contains('@$contactLower')) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  /// Apply category filters
  List<Map<String, dynamic>> _applyCategoryFilters(
    List<Map<String, dynamic>> memories,
  ) {
    if (selectedCategories.isEmpty) {
      debugPrint('$tag   ⏭️  No category filters to apply');
      return memories;
    }

    debugPrint(
      '$tag   🏷️  Applying category filters: ${selectedCategories.length} categories',
    );

    return memories.where((memory) {
      final category =
          (memory[DatabaseHelper.columnCategory] as String?)?.toLowerCase() ??
          '';

      // Check if the memory's category matches any selected category
      for (final selectedCategory in selectedCategories) {
        if (category == selectedCategory.toLowerCase()) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  /// Apply location and radius filters
  List<Map<String, dynamic>> _applyLocationFilters(
    List<Map<String, dynamic>> memories,
  ) {
    if (selectedLocation.value.isEmpty) {
      debugPrint('$tag   ⏭️  No location filters to apply');
      return memories;
    }

    debugPrint('$tag   📍 Applying location filters');

    // If no radius is specified, just return all memories (location filter without radius is not useful)
    if (selectedRadius.value.isEmpty) {
      debugPrint(
        '$tag   ⚠️  Location specified but no radius - skipping location filter',
      );
      return memories;
    }

    final radius = double.tryParse(selectedRadius.value);
    if (radius == null || radius <= 0) {
      debugPrint('$tag   ⚠️  Invalid radius value: ${selectedRadius.value}');
      return memories;
    }

    // Parse filter location coordinates
    final locationParts = selectedLocation.value.split(',');
    if (locationParts.length != 2) {
      debugPrint(
        '$tag   ⚠️  Invalid location format: ${selectedLocation.value}',
      );
      return memories;
    }

    final filterLat = double.tryParse(locationParts[0].trim());
    final filterLng = double.tryParse(locationParts[1].trim());

    if (filterLat == null || filterLng == null) {
      debugPrint(
        '$tag   ⚠️  Could not parse location coordinates: ${selectedLocation.value}',
      );
      return memories;
    }

    debugPrint(
      '$tag   📍 Filtering by location: ($filterLat, $filterLng) with radius: $radius miles',
    );

    return memories.where((memory) {
      final memoryLat =
          memory[DatabaseHelper.columnLocationLatitude] as double?;
      final memoryLng =
          memory[DatabaseHelper.columnLocationLongitude] as double?;

      if (memoryLat == null || memoryLng == null) {
        return false;
      }

      final distance = _calculateDistanceInMiles(
        filterLat,
        filterLng,
        memoryLat,
        memoryLng,
      );
      return distance <= radius;
    }).toList();
  }

  /// Apply memory ID filters (from map/filter)
  List<Map<String, dynamic>> _applyMemoryIdFilters(
    List<Map<String, dynamic>> memories,
  ) {
    if (selectedMemoryIds.isEmpty) {
      debugPrint('$tag   ⏭️  No memory ID filters to apply');
      return memories;
    }

    debugPrint(
      '$tag   🎯 Applying memory ID filters: ${selectedMemoryIds.length} IDs',
    );

    final idSet =
        selectedMemoryIds
            .map((id) => int.tryParse(id))
            .whereType<int>()
            .toSet();

    return memories.where((memory) {
      final memoryId = memory[DatabaseHelper.columnId] as int?;
      return memoryId != null && idSet.contains(memoryId);
    }).toList();
  }

  /// Apply search filters (from search - takes precedence)
  List<Map<String, dynamic>> _applySearchFilters(
    List<Map<String, dynamic>> memories,
  ) {
    if (!isSearchedMemoryList.value || searchedMemoryIds.isEmpty) {
      debugPrint('$tag   ⏭️  No search filters to apply');
      return memories;
    }

    debugPrint(
      '$tag   🔍 Applying search filters: ${searchedMemoryIds.length} IDs',
    );
    indicatorType.value = 'search';

    final idSet =
        searchedMemoryIds
            .map((id) => int.tryParse(id))
            .whereType<int>()
            .toSet();

    return memories.where((memory) {
      final memoryId = memory[DatabaseHelper.columnId] as int?;
      return memoryId != null && idSet.contains(memoryId);
    }).toList();
  }

  /// Calculate distance between two coordinates in miles using Haversine formula
  double _calculateDistanceInMiles(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusMiles = 3959.0; // Earth's radius in miles

    final double dLat = (lat2 - lat1) * (math.pi / 180);
    final double dLng = (lng2 - lng1) * (math.pi / 180);

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180)) *
            math.cos(lat2 * (math.pi / 180)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMiles * c;
  }

  // ============================================================================
  // UI TRANSFORMATION METHODS
  // ============================================================================

  /// Load memories from database and apply filters
  /// This is the main orchestration method that should be called to load and filter memories
  Future<void> loadAndApplyFilters() async {
    try {
      isLoadingMemories.value = true;
      debugPrint('$tag Starting to load memories from database...');

      // Ensure database is initialized
      final db = await _databaseHelper.database;
      if (!db.isOpen) {
        await _databaseHelper.resetDatabaseConnection();
      }

      // Load all memories from database
      final memories = await _databaseHelper.getAllMemoriesWithDetails();
      debugPrint('$tag Loaded ${memories.length} raw memories from database');

      // Transform database memories to UI format
      final transformedMemories = <Map<String, dynamic>>[];
      for (final memory in memories) {
        try {
          final transformed = await transformDatabaseMemoryToUI(memory);
          transformedMemories.add(transformed);
        } catch (e) {
          debugPrint('$tag Error transforming memory ${memory['id']}: $e');
        }
      }

      // Sort memories by date and time (newest first)
      transformedMemories.sort((a, b) {
        try {
          final aDate = a['date'] as String? ?? '';
          final bDate = b['date'] as String? ?? '';
          final aYear = a['year'] as String? ?? '';
          final bYear = b['year'] as String? ?? '';
          final aTime = a['time'] as String? ?? '';
          final bTime = b['time'] as String? ?? '';

          DateTime? aDateTime;
          DateTime? bDateTime;

          String format =
              Platform.isIOS ? "d. MMMM yyyy hh:mm a" : "d. MMMM yyyy HH:mm";

          if (aTime.toLowerCase().contains('am') ||
              aTime.toLowerCase().contains('pm')) {
            format = "d. MMMM yyyy hh:mm a";
          } else {
            format = "d. MMMM yyyy HH:mm";
          }

          // Try to parse memory A
          try {
            if (aDate.isNotEmpty) {
              if (aDate.contains(' ') && aDate.split(' ').length >= 4) {
                aDateTime = DateTime.tryParse(aDate);
              } else if (aYear.isNotEmpty) {
                String dateTimeStr = '$aDate $aYear';
                if (aTime.isNotEmpty) {
                  dateTimeStr += ' $aTime';
                }
                aDateTime = DateTime.tryParse(dateTimeStr);
              }
            }
          } catch (e) {
            debugPrint('$tag Error parsing date A: $e');
          }

          // Try to parse memory B
          try {
            if (bDate.isNotEmpty) {
              if (bDate.contains(' ') && bDate.split(' ').length >= 4) {
                bDateTime = DateTime.tryParse(bDate);
              } else if (bYear.isNotEmpty) {
                String dateTimeStr = '$bDate $bYear';
                if (bTime.isNotEmpty) {
                  dateTimeStr += ' $bTime';
                }
                bDateTime = DateTime.tryParse(dateTimeStr);
              }
            }
          } catch (e) {
            debugPrint('$tag Error parsing date B: $e');
          }

          // Compare dates
          if (aDateTime != null && bDateTime != null) {
            return bDateTime.compareTo(aDateTime); // Newest first
          } else if (aDateTime != null) {
            return -1;
          } else if (bDateTime != null) {
            return 1;
          }
          return 0;
        } catch (e) {
          debugPrint('$tag Error sorting memories: $e');
          return 0;
        }
      });

      // Store in global variable
      allMemories.value = transformedMemories;
      debugPrint(
        '$tag Transformed and sorted ${transformedMemories.length} memories',
      );

      // Extract unique hashtags, contacts, and categories from all memories
      final hashtagsSet = <String>{};
      final contactsSet = <String>{};
      final categoriesSet = <String>{};

      for (final memory in allMemories) {
        final tags = memory[DatabaseHelper.columnTags] as String?;
        if (tags != null && tags.isNotEmpty) {
          hashtagsSet.addAll(
            tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
          );
        }

        final mentions = memory[DatabaseHelper.columnMentions] as String?;
        if (mentions != null && mentions.isNotEmpty) {
          contactsSet.addAll(
            mentions.split(',').map((m) => m.trim()).where((m) => m.isNotEmpty),
          );
        }

        final category = memory[DatabaseHelper.columnCategory] as String?;
        if (category != null && category.isNotEmpty) {
          categoriesSet.add(category);
        }
      }

      availableHashtags.value = hashtagsSet.toList()..sort();
      availableContacts.value = contactsSet.toList()..sort();
      availableCategories.value = categoriesSet.toList()..sort();

      debugPrint(
        '$tag Extracted ${availableHashtags.length} hashtags, ${availableContacts.length} contacts, ${availableCategories.length} categories',
      );

      // Apply all filters
      updateFilterStatus();
      applyAllFilters();

      isLoadingMemories.value = false;
    } catch (e) {
      debugPrint('$tag Error loading memories: $e');
      isLoadingMemories.value = false;
    }
  }

  /// True when [memory] would appear in [filteredMemories] under current filter state.
  bool memoryMatchesActiveFilters(Map<String, dynamic> memory) {
    var result = <Map<String, dynamic>>[memory];
    result = _applyDateFilter(result);
    result = _applySearchedTextFilter(result);
    result = _applyHashtagFilters(result);
    result = _applyContactFilters(result);
    result = _applyCategoryFilters(result);
    result = _applyLocationFilters(result);
    result = _applyMemoryIdFilters(result);
    result = _applySearchFilters(result);
    return result.isNotEmpty;
  }

  /// After creating one memory, prepend it without reloading the full library.
  ///
  /// When [incremental] is true, only evaluates filters for the new row instead of
  /// scanning thousands of existing memories (KMZ bulk import case).
  Future<void> prependMemoryById(
    int memoryId, {
    bool incremental = false,
  }) async {
    try {
      final raw = await _databaseHelper.getMemoryWithDetails(memoryId);
      if (raw == null) {
        debugPrint('$tag prependMemoryById: memory $memoryId not found');
        return;
      }

      final uiMemory = await transformDatabaseMemoryToUI(raw);
      final updated = <Map<String, dynamic>>[uiMemory, ...allMemories];
      allMemories.value = updated;

      _mergeFilterOptionsFromUiMemory(uiMemory);
      updateFilterStatus();

      if (incremental) {
        final noFilters =
            !hasActiveFilters.value &&
            searchedTextKeyword.value.isEmpty &&
            !isSearchedMemoryList.value;
        if (noFilters || memoryMatchesActiveFilters(uiMemory)) {
          filteredMemories.value = [uiMemory, ...filteredMemories];
          totalResults.value = filteredMemories.length;
          if (!isSearchedMemoryList.value) {
            indicatorType.value = hasActiveFilters.value ? 'filter' : '';
          }
        } else {
          applyAllFilters();
        }
      } else {
        applyAllFilters();
      }

      debugPrint(
        '$tag prependMemoryById: inserted memory $memoryId (${allMemories.length} total, incremental=$incremental)',
      );

      if (Get.isRegistered<AddMemoriesController>()) {
        final add = Get.find<AddMemoriesController>();
        if (incremental &&
            filteredMemories.isNotEmpty &&
            filteredMemories.first['id']?.toString() == memoryId.toString()) {
          add.prependToDisplayList(uiMemory);
        } else {
          add.rebuildDisplayList();
        }
      }
    } catch (e) {
      debugPrint('$tag prependMemoryById error: $e');
    }
  }

  /// After editing one memory, replace it in-memory without a full DB reload.
  Future<void> replaceMemoryById(
    int memoryId, {
    bool incremental = true,
  }) async {
    try {
      final raw = await _databaseHelper.getMemoryWithDetails(memoryId);
      if (raw == null) {
        debugPrint('$tag replaceMemoryById: memory $memoryId not found');
        return;
      }

      final uiMemory = await transformDatabaseMemoryToUI(raw);

      bool matchesId(Map<String, dynamic> m) {
        final id = m['id'];
        if (id == memoryId) return true;
        if (id != null && id.toString() == memoryId.toString()) return true;
        return false;
      }

      final allIndex = allMemories.indexWhere(matchesId);
      if (allIndex >= 0) {
        allMemories[allIndex] = uiMemory;
        allMemories.refresh();
      } else {
        allMemories.value = [uiMemory, ...allMemories];
      }

      _mergeFilterOptionsFromUiMemory(uiMemory);
      updateFilterStatus();

      if (incremental) {
        final filteredIndex = filteredMemories.indexWhere(matchesId);
        final matches = memoryMatchesActiveFilters(uiMemory);
        if (filteredIndex >= 0) {
          if (matches) {
            filteredMemories[filteredIndex] = uiMemory;
            filteredMemories.refresh();
          } else {
            filteredMemories.removeAt(filteredIndex);
          }
          totalResults.value = filteredMemories.length;
        } else if (matches) {
          filteredMemories.value = [uiMemory, ...filteredMemories];
          totalResults.value = filteredMemories.length;
        }
      } else {
        applyAllFilters();
      }

      if (Get.isRegistered<AddMemoriesController>()) {
        Get.find<AddMemoriesController>().replaceInDisplayList(uiMemory);
      }

      debugPrint(
        '$tag replaceMemoryById: updated memory $memoryId (${allMemories.length} total)',
      );
    } catch (e) {
      debugPrint('$tag replaceMemoryById error: $e');
    }
  }

  /// Remove one memory from in-memory lists without reloading the full library.
  void removeMemoryById(int memoryId) {
    bool matchesId(Map<String, dynamic> m) {
      final id = m['id'];
      if (id == memoryId) return true;
      if (id != null && id.toString() == memoryId.toString()) return true;
      return false;
    }

    allMemories.removeWhere(matchesId);
    filteredMemories.removeWhere(matchesId);
    selectedMemoryIds.remove(memoryId.toString());

    totalResults.value = filteredMemories.length;
    updateFilterStatus();

    if (Get.isRegistered<AddMemoriesController>()) {
      Get.find<AddMemoriesController>().removeFromDisplayList(memoryId);
    }

    debugPrint(
      '$tag removeMemoryById: removed $memoryId (${allMemories.length} total)',
    );
  }

  void _mergeFilterOptionsFromUiMemory(Map<String, dynamic> memory) {
    final tags = memory['tags'] as String?;
    if (tags != null && tags.isNotEmpty) {
      final merged = <String>{
        ...availableHashtags,
        ...tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty),
      };
      availableHashtags.value = merged.toList()..sort();
    }

    final mentions = memory['mentions'] as String?;
    if (mentions != null && mentions.isNotEmpty) {
      final merged = <String>{
        ...availableContacts,
        ...mentions.split(',').map((m) => m.trim()).where((m) => m.isNotEmpty),
      };
      availableContacts.value = merged.toList()..sort();
    }

    final category = memory['category'] as String?;
    if (category != null && category.isNotEmpty) {
      final merged = <String>{...availableCategories, category};
      availableCategories.value = merged.toList()..sort();
    }
  }

  /// Transform database memory to UI format
  Future<Map<String, dynamic>> transformDatabaseMemoryToUI(
    Map<String, dynamic> dbMemory,
  ) async {
    final date = _formatDate(dbMemory['date'], dbMemory['created_at']);
    final year = _formatYear(dbMemory['date'], dbMemory['created_at']);

    // Get images from the new 'images' field (loaded from separate table)
    final imagesList = dbMemory['images'] as List<String>?;
    List<String>? displayImages;
    if (imagesList != null && imagesList.isNotEmpty) {
      displayImages = await Future.wait(
        imagesList.map((image) async {
          if (_isFilePath(image)) {
            return await _getAbsolutePath(image);
          } else {
            return image; // Legacy base64
          }
        }),
      );
    }

    // Get audio data
    final audiosList = dbMemory['audios'] as List<Map<String, dynamic>>?;
    List<String>? audioDurations;
    List<String>? audioPaths;
    if (audiosList != null && audiosList.isNotEmpty) {
      audioDurations =
          audiosList.map((audio) => audio['audio_duration'] as String).toList();
      audioPaths = await Future.wait(
        audiosList.map((audio) async {
          final relativePath = audio['audio_file_path'] as String;
          return await _getAbsolutePath(relativePath);
        }),
      );
    } else {
      audioPaths = _databaseHelper.getAudioPathsFromMemory(dbMemory);
      if (audioPaths.isNotEmpty) {
        audioDurations =
            audioPaths.map((path) => _extractDurationFromPath(path)).toList();
      }
    }

    // Get video data
    final videosRaw = dbMemory['videos'];
    List<Map<String, dynamic>>? videosList;
    if (videosRaw is List) {
      videosList = videosRaw.cast<Map<String, dynamic>>();
    }

    List<String>? videoPaths;
    List<String>? videoThumbnails;
    List<String>? videoDurations;
    if (videosList != null && videosList.isNotEmpty) {
      videoPaths = await Future.wait(
        videosList.map((video) async {
          final relativePath = video['video_file_path'] as String;
          return await _getAbsolutePath(relativePath);
        }),
      );
      videoThumbnails =
          videosList
              .map((video) => (video['video_thumbnail_path'] as String?) ?? '')
              .toList();
      videoDurations =
          videosList
              .map((video) => (video['video_duration'] as String?) ?? '')
              .toList();
    }

    // Format location
    final formattedLocation = _formatLocation(dbMemory['location'] ?? '');
    final locationCountry = dbMemory['location_country'] ?? '';
    final locationCity = dbMemory['location_city'] ?? '';
    final locationFlag = dbMemory['location_flag'] ?? '';
    final locationName = dbMemory['location_name'] ?? '';
    final locationAddress = dbMemory['location_address'] ?? '';

    // Use enhanced location display if available
    String displayLocation = formattedLocation;
    if (locationFlag.isNotEmpty &&
        locationCity.isNotEmpty &&
        locationCountry.isNotEmpty) {
      displayLocation = '$locationFlag $locationCity, $locationCountry';
    } else if (locationName.isNotEmpty) {
      displayLocation = locationName;
    } else if (locationAddress.isNotEmpty) {
      displayLocation = locationAddress;
    }

    // Build single list in upload order (images + videos interleaved by order)
    final imgList = displayImages ?? <String>[];
    final vidPaths = videoPaths ?? <String>[];
    final imgOrders = dbMemory['imageOrders'] as List<dynamic>? ?? [];
    final vidOrders = dbMemory['videoOrders'] as List<dynamic>? ?? [];
    final List<Map<String, dynamic>> orderEntries = [];
    for (int i = 0; i < imgList.length; i++) {
      final o = i < imgOrders.length ? (imgOrders[i] as num).toInt() : i;
      orderEntries.add({'order': o, 'type': 'image', 'path': imgList[i]});
    }
    for (int i = 0; i < vidPaths.length; i++) {
      final o =
          i < vidOrders.length
              ? (vidOrders[i] as num).toInt()
              : imgList.length + i;
      orderEntries.add({'order': o, 'type': 'video', 'path': vidPaths[i]});
    }
    orderEntries.sort(
      (a, b) => (a['order'] as int).compareTo(b['order'] as int),
    );
    final orderedMedia =
        orderEntries
            .map((e) => {'type': e['type'], 'path': e['path']})
            .toList();

    return {
      'id': dbMemory['id'],
      'year': year,
      'date': date,
      'location': displayLocation,
      'location_country': locationCountry,
      'location_city': locationCity,
      'location_flag': locationFlag,
      'location_name': locationName,
      'location_address': locationAddress,
      'location_latitude': dbMemory['location_latitude'],
      'location_longitude': dbMemory['location_longitude'],
      'time': dbMemory['time'] ?? '',
      'text': dbMemory['description'],
      'category': dbMemory['category'],
      'tags': dbMemory['tags'],
      'mentions': dbMemory['mentions'],
      'assetsImg': displayImages,
      'audioDurations': audioDurations,
      'base64Images': imagesList,
      'audioPaths': audioPaths,
      'videoPaths': videoPaths,
      'videoThumbnails': videoThumbnails,
      'videoDurations': videoDurations,
      'imageOrders': dbMemory['imageOrders'],
      'videoOrders': dbMemory['videoOrders'],
      'orderedMedia': orderedMedia,
      'created_at': dbMemory['created_at'],
    };
  }

  /// Helper method to check if string is a file path
  bool _isFilePath(String str) {
    if (str.startsWith('memory_images/') ||
        str.startsWith('memory_videos/') ||
        str.startsWith('memory_audios/') ||
        str.startsWith('audio_files/')) {
      return true;
    }

    return str.startsWith('/') ||
        str.contains('\\') ||
        str.contains('.jpg') ||
        str.contains('.jpeg') ||
        str.contains('.png') ||
        str.contains('.gif') ||
        str.contains('.webp') ||
        str.contains('.mov') ||
        str.contains('.mp4') ||
        str.contains('.m4a');
  }

  /// Format date for display
  String _formatDate(String? dbDate, String? createdAt) {
    if (dbDate != null && dbDate.isNotEmpty) {
      try {
        final date = DateTime.parse(dbDate);
        final months = [
          '',
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
        return '${date.day}. ${months[date.month]}';
      } catch (e) {
        debugPrint('$tag Error parsing dbDate: $e');
      }
    }

    if (createdAt != null) {
      try {
        final date = DateTime.parse(createdAt);
        final months = [
          '',
          'January',
          'February',
          'March',
          'April',
          'May',
          'June',
          'July',
          'August',
          'September',
          'October',
          'November',
          'December',
        ];
        return '${date.day}. ${months[date.month]}';
      } catch (e) {
        debugPrint('$tag Error parsing createdAt: $e');
        return 'Unknown Date';
      }
    }

    return 'Unknown Date';
  }

  /// Convert relative path to absolute path
  Future<String> _getAbsolutePath(String path) async {
    if (path.startsWith('/')) {
      return path;
    }

    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$path';
  }

  /// Format year for display
  String _formatYear(String? dbDate, String? createdAt) {
    if (dbDate != null && dbDate.isNotEmpty) {
      try {
        final date = DateTime.parse(dbDate);
        return '${date.year}';
      } catch (e) {
        debugPrint('$tag Error parsing dbDate: $e');
      }
    }

    return 'Unknown Date';
  }

  /// Format location coordinates to truncate lat/lng to 4 decimal places
  String _formatLocation(String location) {
    if (location.isEmpty) return location;

    final coordPattern = RegExp(r'^(-?\d+\.?\d*),(-?\d+\.?\d*)$');
    final match = coordPattern.firstMatch(location.trim());

    if (match != null) {
      try {
        final lat = double.parse(match.group(1)!);
        final lng = double.parse(match.group(2)!);

        final truncatedLat = (lat * 10000).truncate() / 10000;
        final truncatedLng = (lng * 10000).truncate() / 10000;

        return '$truncatedLat,$truncatedLng';
      } catch (e) {
        debugPrint('$tag Error parsing coordinates: $e');
        return location;
      }
    }

    return location;
  }

  /// Extract duration from audio file path (placeholder)
  String _extractDurationFromPath(String path) {
    return '1:30'; // Placeholder duration
  }

  /// Load hierarchical data for display logic

  // ============================================================================
  // DISPLAY LOGIC (HIERARCHICAL)
  // ============================================================================

  /// Get display hashtags - show only main groups when all subgroups are selected
  /// Note: For now, just return the selected hashtags as-is
  /// TODO: Implement hierarchical display logic when group-hashtag mapping is available
  List<String> _getDisplayHashtags() {
    return List<String>.from(selectedHashtags);
  }

  /// Get display contacts - show only main groups when all subgroups are selected
  /// Note: For now, just return the selected contacts as-is
  /// TODO: Implement hierarchical display logic when group-contact mapping is available
  List<String> _getDisplayContacts() {
    return List<String>.from(selectedContacts);
  }

  /// Get display categories - show only main categories when all subcategories are selected
  List<String> _getDisplayCategories() {
    final result = <String>[];
    final processedCategories = <String>{};

    for (final category in selectedCategories) {
      // Find if this category has a parent
      PlaceCategory? parentCategory;
      for (final cat in _cachedCategories) {
        if (cat.subcategories?.any((sub) => sub.name == category) ?? false) {
          parentCategory = cat;
          break;
        }
      }

      if (parentCategory != null &&
          !processedCategories.contains(parentCategory.name)) {
        // Check if all subcategories of this parent are selected
        final allSubsSelected =
            parentCategory.subcategories?.every(
              (sub) => selectedCategories.contains(sub.name),
            ) ??
            false;

        if (allSubsSelected) {
          // Show only the main category name
          result.add(parentCategory.name);
          processedCategories.add(parentCategory.name);
        } else {
          // Show individual category
          result.add(category);
        }
      } else if (parentCategory == null) {
        // Standalone category or main category
        result.add(category);
      }
    }

    return result;
  }

  // ============================================================================
  // FILTER MANAGEMENT
  // ============================================================================

  /// Update filter status based on current filter values
  void updateFilterStatus() {
    hasActiveFilters.value =
        filterValues.isNotEmpty ||
        selectedLocation.value.isNotEmpty ||
        selectedRadius.value.isNotEmpty ||
        selectedHashtags.isNotEmpty ||
        selectedContacts.isNotEmpty ||
        selectedCategories.isNotEmpty ||
        selectedMemoryIds.isNotEmpty ||
        searchedMemoryIds.isNotEmpty;

    debugPrint(
      '$tag Filter status updated: hasActiveFilters=${hasActiveFilters.value}',
    );
  }

  /// Get active filter count for badge display
  int get activeFilterCount {
    int count = 0;

    // Count text-based filters (date, title, description, etc.)
    if (filterValues.isNotEmpty) {
      for (final entry in filterValues.entries) {
        if (entry.value.isNotEmpty) {
          count++;
        }
      }
    }

    // Count location filter
    if (selectedLocation.value.isNotEmpty) {
      count++;
    }

    // Count hashtags filter
    if (selectedHashtags.isNotEmpty) {
      count++;
    }

    // Count contacts filter
    if (selectedContacts.isNotEmpty) {
      count++;
    }

    // Count categories filter
    if (selectedCategories.isNotEmpty) {
      count++;
    }

    // Count memory ID filters (when individual memory is tapped)
    if (selectedMemoryIds.isNotEmpty) {
      count++;
    }

    return count;
  }

  /// Check if there's an active text search
  bool get hasActiveSearch {
    return searchedTextKeyword.value.isNotEmpty;
  }

  /// Reset all filters to their default values
  void resetFilters() {
    debugPrint('$tag Resetting all filters');

    filterValues.clear();
    selectedLocation.value = '';
    selectedLocationDisplayName.value = '';
    selectedLocationFlag.value = '';
    selectedRadius.value = '';
    selectedHashtags.clear();
    selectedContacts.clear();
    selectedCategories.clear();
    selectedMemoryIds.clear();
    searchedMemoryIds.clear();
    searchedTextKeyword.value = '';
    isSearchedMemoryList.value = false;

    updateFilterStatus();
    debugPrint('$tag All filters reset');
  }

  /// Set searched text keyword and apply filters
  void setSearchedTextKeyword(String keyword) {
    searchedTextKeyword.value = keyword.trim();
    debugPrint(
      '$tag 🔍 Searched text keyword set to: "${searchedTextKeyword.value}"',
    );

    // Update indicator type to search if keyword is not empty
    if (searchedTextKeyword.value.isNotEmpty) {
      indicatorType.value = 'search';
      searchKeywords.value = searchedTextKeyword.value;
    }

    applyAllFilters1();
  }

  /// Reset all filters EXCEPT search filter.
  ///
  /// Set [applyFilters] false when [prependMemoryById] will update lists next
  /// (avoids scanning the full library twice after a single create).
  void resetFiltersExceptSearch({bool applyFilters = true}) {
    debugPrint('$tag 🧹 Resetting all filters except search');

    filterValues.clear();
    selectedLocation.value = '';
    selectedLocationDisplayName.value = '';
    selectedLocationFlag.value = '';
    selectedRadius.value = '';
    selectedHashtags.clear();
    selectedContacts.clear();
    selectedCategories.clear();
    selectedMemoryIds.clear();
    searchedMemoryIds.clear();
    // Keep searchedTextKeyword.value as is - don't clear it
    isSearchedMemoryList.value = false;

    updateFilterStatus();
    debugPrint(
      '$tag ✅ All filters reset except search (search keyword: "${searchedTextKeyword.value}")',
    );

    if (!applyFilters) return;

    if (!hasActiveFilters.value &&
        searchedTextKeyword.value.isEmpty &&
        !isSearchedMemoryList.value) {
      filteredMemories.value = List<Map<String, dynamic>>.from(allMemories);
      totalResults.value = filteredMemories.length;
      indicatorType.value = '';
      debugPrint(
        '$tag ✅ Filters reset — synced ${filteredMemories.length} memories (no filter scan)',
      );
      return;
    }

    applyAllFilters();
  }

  /// Clear searched text keyword ONLY
  void clearSearchedTextKeyword() {
    searchedTextKeyword.value = '';
    debugPrint('$tag 🔍 Searched text keyword cleared');

    // Reset indicator type if no other search is active
    if (!isSearchedMemoryList.value) {
      indicatorType.value = hasActiveFilters.value ? 'filter' : '';
      searchKeywords.value = '';
    }

    applyAllFilters();
  }

  /// Clear specific filter types
  void clearFilters({
    bool clearText = false,
    bool clearLocation = false,
    bool clearHashtags = false,
    bool clearContacts = false,
    bool clearCategories = false,
    bool clearMemoryIds = false,
    bool clearSearchedIds = false,
    bool clearSearchedText = false,
  }) {
    debugPrint('$tag Clearing specific filters');

    if (clearText) filterValues.clear();
    if (clearLocation) {
      selectedLocation.value = '';
      selectedLocationDisplayName.value = '';
      selectedLocationFlag.value = '';
      selectedRadius.value = '';
    }
    if (clearHashtags) selectedHashtags.clear();
    if (clearContacts) selectedContacts.clear();
    if (clearCategories) selectedCategories.clear();
    if (clearMemoryIds) selectedMemoryIds.clear();
    if (clearSearchedIds) {
      searchedMemoryIds.clear();
      isSearchedMemoryList.value = false;
    }
    if (clearSearchedText) {
      searchedTextKeyword.value = '';
    }

    updateFilterStatus();
  }
}
