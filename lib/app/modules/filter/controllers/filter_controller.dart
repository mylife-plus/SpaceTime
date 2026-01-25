import 'dart:math' as math;
import 'package:get/get.dart';
import 'package:flutter/material.dart';
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
  final RxList<Map<String, dynamic>> filteredMemories = <Map<String, dynamic>>[].obs;

  /// Total results count after applying filters
  final RxInt totalResults = 0.obs;

  /// Indicator type (search vs filter)
  final RxString indicatorType = ''.obs; // 'search' or 'filter'

  /// Search keywords (preserved when in search mode)
  final RxString searchKeywords = ''.obs;

  /// Searched text keyword for text-based search filtering
  final RxString searchedTextKeyword = ''.obs;

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

    try {

      allMemories.clear();
      filteredMemories.clear();
      debugPrint('$tag 📊 Loading filter data from database...');

      // Ensure database is initialized
      final db = await _databaseHelper.database;
      if (!db.isOpen) {
        debugPrint('$tag ⚠️ Database is not open, reinitializing...');
        await _databaseHelper.resetDatabaseConnection();
      }

      // Load all memories from database and store in global variable
      debugPrint('$tag 📂 Loading all memories from database...');
      final memories = await _databaseHelper.getAllMemoriesWithDetails();
      allMemories.value = memories;
      debugPrint('$tag ✅ Loaded ${allMemories.length} memories from database');

      // Extract unique hashtags, contacts, and categories from memories
      final Set<String> uniqueHashtags = {};
      final Set<String> uniqueContacts = {};
      final Set<String> uniqueCategories = {};

      for (final memory in allMemories) {
        // Extract hashtags from tags field (comma-separated)
        final tags = memory[DatabaseHelper.columnTags] as String?;
        if (tags != null && tags.isNotEmpty) {
          final tagList = tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty);
          uniqueHashtags.addAll(tagList);
        }

        // Extract contacts from mentions field (comma-separated)
        final mentions = memory[DatabaseHelper.columnMentions] as String?;
        if (mentions != null && mentions.isNotEmpty) {
          final mentionList = mentions.split(',').map((m) => m.trim()).where((m) => m.isNotEmpty);
          uniqueContacts.addAll(mentionList);
        }

        // Extract category
        final category = memory[DatabaseHelper.columnCategory] as String?;
        if (category != null && category.isNotEmpty) {
          uniqueCategories.add(category.trim());
        }
      }

      // Update available filter options
      availableHashtags.value = uniqueHashtags.toList()..sort();
      availableContacts.value = uniqueContacts.toList()..sort();
      availableCategories.value = uniqueCategories.toList()..sort();

      debugPrint('$tag ✅ Extracted filter data from memories');
      debugPrint('$tag   - Unique Hashtags: ${availableHashtags.length}');
      debugPrint('$tag   - Unique Contacts: ${availableContacts.length}');
      debugPrint('$tag   - Unique Categories: ${availableCategories.length}');

      // Apply all filters to update filteredMemories and totalResults
      applyAllFilters();
    } catch (e) {
      debugPrint('$tag ❌ Error loading filter data: $e');
    }
  }

  // ============================================================================
  // FILTER APPLICATION METHODS
  // ============================================================================

  /// Apply all filters to allMemories and update filteredMemories
  void applyAllFilters() {
    debugPrint('$tag 🔧 Applying all filters...');

    // Start with all memories
    List<Map<String, dynamic>> result = List.from(allMemories);

    // Apply each filter type in sequence
    result = _applySearchedTextFilter(result);
    result = _applyTextFilters(result);
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

    debugPrint('$tag ✅ Filters applied: ${totalResults.value} results from ${allMemories.length} total memories');
  }

  /// Apply searched text keyword filter (text-based search)
  List<Map<String, dynamic>> _applySearchedTextFilter(List<Map<String, dynamic>> memories) {
    if (searchedTextKeyword.value.isEmpty) {
      debugPrint('$tag   ⏭️  No searched text keyword to apply');
      return memories;
    }

    final keyword = searchedTextKeyword.value.toLowerCase().trim();
    debugPrint('$tag   🔍 Applying searched text filter: "$keyword"');

    return memories.where((memory) {
      final description = (memory[DatabaseHelper.columnDescription] as String?)?.toLowerCase() ?? '';
      final tags = (memory[DatabaseHelper.columnTags] as String?)?.toLowerCase() ?? '';
      final mentions = (memory[DatabaseHelper.columnMentions] as String?)?.toLowerCase() ?? '';
      final category = (memory[DatabaseHelper.columnCategory] as String?)?.toLowerCase() ?? '';
      final locationName = (memory[DatabaseHelper.columnLocationName] as String?)?.toLowerCase() ?? '';
      final locationAddress = (memory[DatabaseHelper.columnLocationAddress] as String?)?.toLowerCase() ?? '';
      final locationCity = (memory[DatabaseHelper.columnLocationCity] as String?)?.toLowerCase() ?? '';
      final locationCountry = (memory[DatabaseHelper.columnLocationCountry] as String?)?.toLowerCase() ?? '';

      // Search in all text fields
      final searchableText = '$description $tags $mentions $category $locationName $locationAddress $locationCity $locationCountry';

      return searchableText.contains(keyword);
    }).toList();
  }

  /// Apply text-based filters (title, description, etc.)
  List<Map<String, dynamic>> _applyTextFilters(List<Map<String, dynamic>> memories) {
    if (filterValues.isEmpty) {
      debugPrint('$tag   ⏭️  No text filters to apply');
      return memories;
    }

    debugPrint('$tag   📝 Applying text filters: ${filterValues.length} filters');

    return memories.where((memory) {
      final description = (memory[DatabaseHelper.columnDescription] as String?)?.toLowerCase() ?? '';
      final tags = (memory[DatabaseHelper.columnTags] as String?)?.toLowerCase() ?? '';
      final mentions = (memory[DatabaseHelper.columnMentions] as String?)?.toLowerCase() ?? '';
      final category = (memory[DatabaseHelper.columnCategory] as String?)?.toLowerCase() ?? '';

      final searchableText = '$description $tags $mentions $category';

      // Check if all filter values are present in searchable text
      for (final value in filterValues.values) {
        if (value.isEmpty) continue;
        if (!searchableText.contains(value.toLowerCase())) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// Apply hashtag filters
  List<Map<String, dynamic>> _applyHashtagFilters(List<Map<String, dynamic>> memories) {
    if (selectedHashtags.isEmpty) {
      debugPrint('$tag   ⏭️  No hashtag filters to apply');
      return memories;
    }

    debugPrint('$tag   #️⃣ Applying hashtag filters: ${selectedHashtags.length} hashtags');

    return memories.where((memory) {
      final tags = (memory[DatabaseHelper.columnTags] as String?)?.toLowerCase() ?? '';
      final description = (memory[DatabaseHelper.columnDescription] as String?)?.toLowerCase() ?? '';

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
  List<Map<String, dynamic>> _applyContactFilters(List<Map<String, dynamic>> memories) {
    if (selectedContacts.isEmpty) {
      debugPrint('$tag   ⏭️  No contact filters to apply');
      return memories;
    }

    debugPrint('$tag   👤 Applying contact filters: ${selectedContacts.length} contacts');

    return memories.where((memory) {
      final mentions = (memory[DatabaseHelper.columnMentions] as String?)?.toLowerCase() ?? '';
      final description = (memory[DatabaseHelper.columnDescription] as String?)?.toLowerCase() ?? '';

      // Check if any of the selected contacts match
      for (final contact in selectedContacts) {
        final contactLower = contact.toLowerCase();
        if (mentions.contains(contactLower) || description.contains('@$contactLower')) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  /// Apply category filters
  List<Map<String, dynamic>> _applyCategoryFilters(List<Map<String, dynamic>> memories) {
    if (selectedCategories.isEmpty) {
      debugPrint('$tag   ⏭️  No category filters to apply');
      return memories;
    }

    debugPrint('$tag   🏷️  Applying category filters: ${selectedCategories.length} categories');

    return memories.where((memory) {
      final category = (memory[DatabaseHelper.columnCategory] as String?)?.toLowerCase() ?? '';

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
  List<Map<String, dynamic>> _applyLocationFilters(List<Map<String, dynamic>> memories) {
    if (selectedLocation.value.isEmpty) {
      debugPrint('$tag   ⏭️  No location filters to apply');
      return memories;
    }

    debugPrint('$tag   📍 Applying location filters');

    // If no radius is specified, just return all memories (location filter without radius is not useful)
    if (selectedRadius.value.isEmpty) {
      debugPrint('$tag   ⚠️  Location specified but no radius - skipping location filter');
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
      debugPrint('$tag   ⚠️  Invalid location format: ${selectedLocation.value}');
      return memories;
    }

    final filterLat = double.tryParse(locationParts[0].trim());
    final filterLng = double.tryParse(locationParts[1].trim());

    if (filterLat == null || filterLng == null) {
      debugPrint('$tag   ⚠️  Could not parse location coordinates: ${selectedLocation.value}');
      return memories;
    }

    debugPrint('$tag   📍 Filtering by location: ($filterLat, $filterLng) with radius: $radius miles');

    return memories.where((memory) {
      final memoryLat = memory[DatabaseHelper.columnLocationLatitude] as double?;
      final memoryLng = memory[DatabaseHelper.columnLocationLongitude] as double?;

      if (memoryLat == null || memoryLng == null) {
        return false;
      }

      final distance = _calculateDistanceInMiles(filterLat, filterLng, memoryLat, memoryLng);
      return distance <= radius;
    }).toList();
  }

  /// Apply memory ID filters (from map/filter)
  List<Map<String, dynamic>> _applyMemoryIdFilters(List<Map<String, dynamic>> memories) {
    if (selectedMemoryIds.isEmpty) {
      debugPrint('$tag   ⏭️  No memory ID filters to apply');
      return memories;
    }

    debugPrint('$tag   🎯 Applying memory ID filters: ${selectedMemoryIds.length} IDs');

    final idSet = selectedMemoryIds.map((id) => int.tryParse(id)).whereType<int>().toSet();

    return memories.where((memory) {
      final memoryId = memory[DatabaseHelper.columnId] as int?;
      return memoryId != null && idSet.contains(memoryId);
    }).toList();
  }

  /// Apply search filters (from search - takes precedence)
  List<Map<String, dynamic>> _applySearchFilters(List<Map<String, dynamic>> memories) {
    if (!isSearchedMemoryList.value || searchedMemoryIds.isEmpty) {
      debugPrint('$tag   ⏭️  No search filters to apply');
      return memories;
    }

    debugPrint('$tag   🔍 Applying search filters: ${searchedMemoryIds.length} IDs');
    indicatorType.value = 'search';

    final idSet = searchedMemoryIds.map((id) => int.tryParse(id)).whereType<int>().toSet();

    return memories.where((memory) {
      final memoryId = memory[DatabaseHelper.columnId] as int?;
      return memoryId != null && idSet.contains(memoryId);
    }).toList();
  }

  /// Calculate distance between two coordinates in miles using Haversine formula
  double _calculateDistanceInMiles(double lat1, double lng1, double lat2, double lng2) {
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
        final allSubsSelected = parentCategory.subcategories?.every(
          (sub) => selectedCategories.contains(sub.name),
        ) ?? false;

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
    hasActiveFilters.value = filterValues.isNotEmpty ||
        selectedLocation.value.isNotEmpty ||
        selectedRadius.value.isNotEmpty ||
        selectedHashtags.isNotEmpty ||
        selectedContacts.isNotEmpty ||
        selectedCategories.isNotEmpty ||
        selectedMemoryIds.isNotEmpty ||
        searchedMemoryIds.isNotEmpty;

    debugPrint('$tag Filter status updated: hasActiveFilters=${hasActiveFilters.value}');
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
    debugPrint('$tag 🔍 Searched text keyword set to: "${searchedTextKeyword.value}"');

    // Update indicator type to search if keyword is not empty
    if (searchedTextKeyword.value.isNotEmpty) {
      indicatorType.value = 'search';
      searchKeywords.value = searchedTextKeyword.value;
    }

    applyAllFilters();
  }

  /// Clear searched text keyword
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


