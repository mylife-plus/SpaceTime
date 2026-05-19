import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../../../services/memory_clustering_service.dart';
import '../../../services/memory_db.dart';
import '../../memories/controllers/memory_controller.dart';
import '../../map/controllers/map_controller_new.dart';
import '../../../models/hashtag_group_model.dart';
import '../../../models/contact_group_model.dart';
import '../../../models/place_category_model.dart';
import '../../../services/hashtag_group_service.dart';
import '../../../services/contact_group_service.dart';
import '../../../services/place_category_service.dart';
import 'package:spacetime/app/l10n/place_category_l10n.dart';
import 'dart:math';
import 'package:spacetime/app/utils/search_utils.dart';
import '../../filter/controllers/filter_controller.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';

class AddMemoriesController extends GetxController with WidgetsBindingObserver {
  // ============================================================================
  // FILTER CONTROLLER REFERENCE
  // ============================================================================

  /// Get FilterController instance - this is the single source of truth for filters
  FilterController get _filterController => Get.find<FilterController>();

  // ============================================================================
  // COMPUTED PROPERTIES (for backward compatibility)
  // ============================================================================

  /// All memories - delegates to FilterController
  RxList<Map<String, dynamic>> get allMemories => _filterController.allMemories;

  /// Filtered memories - delegates to FilterController
  RxList<Map<String, dynamic>> get filteredMemories => _filterController.filteredMemories;

  /// Loading state - delegates to FilterController
  RxBool get isLoading => _filterController.isLoadingMemories;

  // ============================================================================
  // UI STATE
  // ============================================================================

  var isFilterOpen = false.obs;
  var isSearchActive = false.obs;

  var searchQuery = ''.obs;
  var isSearching = false.obs;
  var searchSuggestions = <String>[].obs;
  var showSuggestions = false.obs;
  final RxBool isUIVisible = true.obs;

  // Track search type and memory data for description-based searches
  var searchType =
      'general'.obs; // 'general', 'hashtag', 'mention', 'description'
  var searchSuggestionsWithMetadata = <Map<String, dynamic>>[].obs;

  late ScrollController scrollController;

  double _lastScrollOffset = 0.0;
  bool _isScrollingDown = false;

  /// Page size for add-memories list (lazy load on scroll).
  static const int memoryListPageSize = 50;

  /// Sorted memories shown in the list (rebuilt when source data/filters change).
  final RxList<Map<String, dynamic>> displayMemories =
      <Map<String, dynamic>>[].obs;

  /// How many rows from [displayMemories] are currently built in the ListView.
  final RxInt loadedDisplayCount = 0.obs;

  bool get _listUsesFilteredSource =>
      isSearching.value || hasActiveFilters.value;

  // ============================================================================
  // FILTER STATE (delegates to FilterController)
  // ============================================================================

  final RxMap<String, String> filterValues = <String, String>{}.obs;
  final selectedLocation = ''.obs; // Stores coordinates "lat,lng" for filtering
  final selectedLocationDisplayName = ''.obs; // Stores display name for UI
  final selectedRadius = ''.obs;
  final RxList<String> selectedHashtags = <String>[].obs;
  final RxList<String> selectedContacts = <String>[].obs;
  final RxList<String> selectedCategories = <String>[].obs;
  final RxList<String> selectedMemoryIds =
      <String>[].obs; // Filter by specific memory IDs
  final RxBool hasActiveFilters = false.obs;

  // Cached hierarchical data for display logic
  List<HashtagGroup> _cachedHashtagGroups = [];
  List<ContactGroup> _cachedContactGroups = [];
  List<PlaceCategory> _cachedCategories = [];

  // Computed getters for display - show only main groups/categories when all subs are selected
  List<String> get displayHashtags => _getDisplayHashtags();
  List<String> get displayContacts => _getDisplayContacts();
  List<String> get displayCategories => _getDisplayCategories();

  // Focus request for radius field
  final RxBool shouldFocusRadiusField = false.obs;

  // Cache for available items
  final RxList<String> availableHashtags = <String>[].obs;
  final RxList<String> availableContacts = <String>[].obs;
  final RxList<String> availableCategories = <String>[].obs;
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  bool isOpenedFromMap = false;

  @override
  void onInit() {
    debugPrint('AddMemoriesController onInit called');
    scrollController = ScrollController();
    scrollController.addListener(_scrollListener);

    // Register this controller as a lifecycle observer so we can detect
    // when the app comes back to the foreground without relying on the View.
    WidgetsBinding.instance.addObserver(this);

    // Add a small delay to ensure UI is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      loadMemoriesFromDatabase();
      loadFilterData();
      _loadHierarchicalData();
    });

    super.onInit();
  }

  /// Called by Flutter whenever the app lifecycle state changes.
  /// On resume we intentionally keep the current view state (no reload).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint(
        'AddMemoriesController: app resumed — preserving current state',
      );
    }
  }

  // Load filter data for dropdowns (same as memory view popups)
  Future<void> loadFilterData() async {
    try {
      // Try to use MemoryController's data if available (same as memory view popups)
      try {
        final memoryController = Get.find<MemoryController>();

        // Use the same data as memory view popups
        availableHashtags.value = List.from(memoryController.existingTags);
        availableContacts.value = List.from(memoryController.existingMentions);
        availableCategories.value = List.from(
          memoryController.existingCategories,
        );

        debugPrint(
          'Using MemoryController data - ${availableHashtags.length} hashtags, ${availableContacts.length} contacts, ${availableCategories.length} categories',
        );

        // If the lists are empty, load from database
        if (availableHashtags.isEmpty ||
            availableContacts.isEmpty ||
            availableCategories.isEmpty) {
          throw Exception(
            'MemoryController data is empty, loading from database',
          );
        }
      } catch (e) {
        debugPrint(
          'MemoryController not available or empty, loading from database: $e',
        );

        // Fallback to direct database access (same methods as MemoryController uses)
        final hashtags = await _databaseHelper.getPopularTags(limit: 100);
        availableHashtags.value = hashtags;

        final contacts = await _databaseHelper.getPopularMentions(limit: 100);
        availableContacts.value = contacts;

        final categories = await _databaseHelper.getPopularCategories(
          limit: 100,
        );
        availableCategories.value = categories;

        debugPrint(
          'Loaded from database - ${hashtags.length} hashtags, ${contacts.length} contacts, ${categories.length} categories',
        );
      }

      debugPrint(
        'Filter data loaded successfully - same source as memory view popups',
      );
    } catch (e) {
      debugPrint('Error loading filter data: $e');
    }
  }

  @override
  void onReady() {
    super.onReady();
    debugPrint('AddMemoriesController onReady called');
    // Additional initialization if needed
  }

  // Method to refresh and reinitialize everything (user preference)
  void onAgainInit() {
    debugPrint('AddMemoriesController: onAgainInit called - refreshing data');

    // Reset UI states
    isLoading.value = false;
    isFilterOpen.value = false;
    isUIVisible.value = true;

    // Clear search states (but keep filters - they should persist)
    searchQuery.value = '';
    searchSuggestions.clear();
    searchSuggestionsWithMetadata.clear();
    showSuggestions.value = false;
    searchType.value = 'general';

    // Don't clear filters - they should persist until manually removed or reset
    // filterValues.clear();  // REMOVED - filters should persist
    // selectedLocation.value = '';  // REMOVED - location filter should persist

    // If filters are active, keep isSearching true to show filtered results
    if (hasActiveFilters.value) {
      isSearching.value = true;
      isSearchActive.value = false;
    } else {
      isSearching.value = false;
      isSearchActive.value = false;
      filteredMemories.clear();
    }

    // Reload memories from database
    loadMemoriesFromDatabase();

    // Reload filter data
    loadFilterData();

    // Reapply filters if they were active
    if (hasActiveFilters.value) {
      applyFilters();
    } else {
      rebuildDisplayList();
    }

  }
/// Now delegates to FilterController which handles loading and UI transformation
  Future<void> loadMemoriesFromDatabase1() async {
    debugPrint('[AddMemoriesController] Loading memories via FilterController...');
    await _filterController.loadAndApplyFilters();

    // Sync filter values from FilterController (single source of truth)
    _syncFilterValuesFromFilterController();

    debugPrint('[AddMemoriesController] Loaded ${allMemories.length} memories from FilterController');
  }
  // Load memories from database
  /// Now delegates to FilterController which handles loading and UI transformation
  Future<void> loadMemoriesFromDatabase() async {
    debugPrint('[AddMemoriesController] Loading memories via FilterController...');
    await _filterController.loadAndApplyFilters();

    // Sync filter values from FilterController (single source of truth)
    _syncFilterValuesFromFilterController();

    debugPrint('[AddMemoriesController] Loaded ${allMemories.length} memories from FilterController');
    rebuildDisplayList();
  }

  /// Rebuilds sorted [displayMemories] and resets pagination window.
  void rebuildDisplayList() {
    final source = _listUsesFilteredSource
        ? filteredMemories.toList()
        : allMemories.toList();
    displayMemories.value = _sortMemoriesNewestFirst(source);
    final total = displayMemories.length;
    loadedDisplayCount.value = total == 0
        ? 0
        : memoryListPageSize.clamp(0, total);
  }

  void loadMoreDisplayItems() {
    final total = displayMemories.length;
    if (loadedDisplayCount.value >= total) return;
    final next = loadedDisplayCount.value + memoryListPageSize;
    loadedDisplayCount.value = next > total ? total : next;
  }

  void onDisplayListIndexVisible(int index) {
    if (index >= loadedDisplayCount.value - 12) {
      loadMoreDisplayItems();
    }
  }

  List<Map<String, dynamic>> _sortMemoriesNewestFirst(
    List<Map<String, dynamic>> memories,
  ) {
    final list = List<Map<String, dynamic>>.from(memories);
    list.sort(
      (a, b) => _memorySortKey(b).compareTo(_memorySortKey(a)),
    );
    return list;
  }

  String _memorySortKey(Map<String, dynamic> memory) {
    final created = memory['created_at'];
    if (created is String && created.isNotEmpty) return created;
    final updated = memory['updated_at'];
    if (updated is String && updated.isNotEmpty) return updated;
    final year = memory['year']?.toString() ?? '';
    final date = memory['date']?.toString() ?? '';
    final time = memory['time']?.toString() ?? '';
    return '$year|$date|$time';
  }

  /// Sync filter values from FilterController to local state
  void _syncFilterValuesFromFilterController() {
    filterValues.value = Map<String, String>.from(_filterController.filterValues);
    selectedLocation.value = _filterController.selectedLocation.value;
    selectedLocationDisplayName.value = _filterController.selectedLocationDisplayName.value;
    selectedRadius.value = _filterController.selectedRadius.value;
    selectedHashtags.value = List<String>.from(_filterController.selectedHashtags);
    selectedContacts.value = List<String>.from(_filterController.selectedContacts);
    selectedCategories.value = List<String>.from(_filterController.selectedCategories);
    selectedMemoryIds.value = List<String>.from(_filterController.selectedMemoryIds);
    hasActiveFilters.value = _filterController.hasActiveFilters.value;

    debugPrint('[AddMemoriesController] 🔄 Synced filter values from FilterController');
  }

  // Transform database memory to UI format
  Future<Map<String, dynamic>> transformDatabaseMemoryToUI(
    Map<String, dynamic> dbMemory,
  ) async {
    final date = _formatDate(dbMemory['date'], dbMemory['created_at']);

    final year = _formatYear(dbMemory['date'], dbMemory['created_at']);

    // Get images from the new 'images' field (loaded from separate table)
    final imagesList = dbMemory['images'] as List<String>?;
    List<String>? displayImages;
    if (imagesList != null && imagesList.isNotEmpty) {
      // Check if images are file paths or base64
      displayImages = await Future.wait(
        imagesList.map((image) async {
          if (_isFilePath(image)) {
            // Convert relative path to absolute path
            return await _getAbsolutePath(image);
          } else {
            // Legacy base64 - keep as is
            return image;
          }
        }),
      );
    }

    // Get audio data from the new 'audios' field (loaded from separate table)
    final audiosList = dbMemory['audios'] as List<Map<String, dynamic>>?;
    List<String>? audioDurations;
    List<String>? audioPaths;
    if (audiosList != null && audiosList.isNotEmpty) {
      audioDurations =
          audiosList.map((audio) => audio['audio_duration'] as String).toList();
      // Convert relative paths to absolute paths
      audioPaths = await Future.wait(
        audiosList.map((audio) async {
          final relativePath = audio['audio_file_path'] as String;
          return await _getAbsolutePath(relativePath);
        }),
      );
    } else {
      // Fallback to old method for backward compatibility
      audioPaths = _databaseHelper.getAudioPathsFromMemory(dbMemory);
      if (audioPaths.isNotEmpty) {
        audioDurations =
            audioPaths.map((path) => _extractDurationFromPath(path)).toList();
      }
    }

    // Get video data from the new 'videos' field (loaded from separate table)
    final videosRaw = dbMemory['videos'];
    debugPrint(
      '🎥 Videos raw from DB (type: ${videosRaw.runtimeType}): $videosRaw',
    );

    List<Map<String, dynamic>>? videosList;
    if (videosRaw is List) {
      videosList = videosRaw.cast<Map<String, dynamic>>();
    }

    debugPrint('🎥 Videos list from DB: $videosList');
    List<String>? videoPaths;
    List<String>? videoThumbnails;
    List<String>? videoDurations;
    if (videosList != null && videosList.isNotEmpty) {
      debugPrint('🎥 Processing ${videosList.length} videos');
      debugPrint('🎥 First video data: ${videosList.first}');

      // Convert relative paths to absolute paths
      videoPaths = await Future.wait(
        videosList.map((video) async {
          debugPrint('🎥 Video map keys: ${video.keys}');
          final relativePath = video['video_file_path'] as String;
          final absolutePath = await _getAbsolutePath(relativePath);
          debugPrint(
            '🎥 Converting video path: $relativePath -> $absolutePath',
          );
          return absolutePath;
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
      debugPrint('🎥 Final video paths (absolute): $videoPaths');
      debugPrint('🎥 Video thumbnails: $videoThumbnails');
      debugPrint('🎥 Video durations: $videoDurations');
    } else {
      debugPrint(
        '🎥 No videos found in database for this memory (videosList is ${videosList == null ? "null" : "empty"})',
      );
    }

    // Format location coordinates
    final formattedLocation = _formatLocation(dbMemory['location'] ?? '');

    // Get enhanced location data from offline reverse geocoding
    final locationCountry = dbMemory['location_country'] ?? '';
    final locationCity = dbMemory['location_city'] ?? '';
    final locationFlag = dbMemory['location_flag'] ?? '';
    final locationName = dbMemory['location_name'] ?? '';
    final locationAddress = dbMemory['location_address'] ?? '';

    // Use enhanced location display if available, otherwise fall back to formatted location
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
      final o = i < vidOrders.length ? (vidOrders[i] as num).toInt() : imgList.length + i;
      orderEntries.add({'order': o, 'type': 'video', 'path': vidPaths[i]});
    }
    orderEntries.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    final orderedMedia = orderEntries.map((e) => {'type': e['type'], 'path': e['path']}).toList();

    final result = {
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
      'base64Images': imagesList, // Use the images from separate table
      'audioPaths': audioPaths,
      'videoPaths': videoPaths,
      'videoThumbnails': videoThumbnails,
      'videoDurations': videoDurations,
      'imageOrders': dbMemory['imageOrders'],
      'videoOrders': dbMemory['videoOrders'],
      'orderedMedia': orderedMedia,
      'created_at': dbMemory['created_at'],
    };

    debugPrint(
      '🎯 Transformed memory ${result['id']}: videoPaths=${result['videoPaths']}, images=${result['assetsImg']?.length}',
    );

    return result;
  }

  // Helper method to check if string is a file path
  bool _isFilePath(String str) {
    // Check for relative paths (memory_images/, memory_videos/, memory_audios/)
    if (str.startsWith('memory_images/') ||
        str.startsWith('memory_videos/') ||
        str.startsWith('memory_audios/') ||
        str.startsWith('audio_files/')) {
      return true;
    }

    // Check for absolute paths or file extensions
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

  // Format date for display
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
        debugPrint('Error parsing dbDate: $e');
        // Fall back to created_at
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
        debugPrint('Error parsing createdAt: $e');
        return 'Unknown Date';
      }
    }

    return 'Unknown Date';
  }

  // Convert relative path to absolute path
  Future<String> _getAbsolutePath(String path) async {
    // If already absolute path, return as is
    if (path.startsWith('/')) {
      return path;
    }

    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$path';
  }

  String _formatYear(String? dbDate, String? createdAt) {
    if (dbDate != null && dbDate.isNotEmpty) {
      try {
        final date = DateTime.parse(dbDate);
        return '${date.year}';
      } catch (e) {
        debugPrint('Error parsing dbDate: $e');
        // Fall back to created_at
      }
    }

    // if (createdAt != null) {
    //   try {
    //     final date = DateTime.parse(createdAt);
    //     final months = ['', 'January', 'February', 'March', 'April', 'May', 'June',
    //                    'July', 'August', 'September', 'October', 'November', 'December'];
    //     return '${date.year}';
    //   } catch (e) {
    //     debugPrint('Error parsing createdAt: $e');
    //     return 'Unknown Date';
    //   }
    // }

    return 'Unknown Date';
  }

  // Format location coordinates to truncate lat/lng to 4 decimal places
  String _formatLocation(String location) {
    if (location.isEmpty) return location;

    // Check if location contains coordinates (lat,lng format)
    final coordPattern = RegExp(r'^(-?\d+\.?\d*),(-?\d+\.?\d*)$');
    final match = coordPattern.firstMatch(location.trim());

    if (match != null) {
      try {
        final lat = double.parse(match.group(1)!);
        final lng = double.parse(match.group(2)!);

        // Truncate to 4 decimal places
        final truncatedLat = (lat * 10000).truncate() / 10000;
        final truncatedLng = (lng * 10000).truncate() / 10000;

        return '$truncatedLat,$truncatedLng';
      } catch (e) {
        debugPrint('Error parsing coordinates: $e');
        return location; // Return original if parsing fails
      }
    }

    return location; // Return original if not coordinates
  }

  // Extract duration from audio file path (placeholder - you might want to implement actual duration extraction)
  String _extractDurationFromPath(String path) {
    // For now, return a placeholder duration
    // In a real implementation, you might want to read the actual audio file duration
    return '1:30'; // Placeholder duration
  }

  void _scrollListener() {
    if (scrollController.hasClients) {
      final currentOffset = scrollController.offset;
      final maxScrollExtent = scrollController.position.maxScrollExtent;
      handleScrollUpdate(currentOffset, maxScrollExtent);
    }
  }

  @override
  void onClose() {
    // Unregister the lifecycle observer to prevent memory leaks.
    WidgetsBinding.instance.removeObserver(this);
    scrollController.removeListener(_scrollListener);
    scrollController.dispose();
    super.onClose();
  }

  void generateSearchSuggestions(String query) {
    if (query.isEmpty) {
      searchSuggestions.clear();
      searchSuggestionsWithMetadata.clear();
      showSuggestions.value = false;
      searchType.value = 'general';
      return;
    }

    // Detect search type based on query prefix
    if (query.startsWith('#')) {
      searchType.value = 'hashtag';
    } else if (query.startsWith('@')) {
      searchType.value = 'mention';
    } else {
      searchType.value =
          'mixed'; // Changed from 'description' to 'mixed' for all types
    }

    final suggestionsWithMetadata = <Map<String, dynamic>>[];
    final normalizedQuery = SearchUtils.normalizeText(query);
    final queryWithoutPrefix =
        query.startsWith('#') || query.startsWith('@')
            ? SearchUtils.normalizeText(query.substring(1))
            : normalizedQuery;

    // Track unique suggestions to avoid duplicates
    final seenMemoryIds =
        <int>{}; // Track memory IDs for description/location/category matches
    final seenHashtags = <String>{};
    final seenMentions = <String>{};

    for (final memory in allMemories) {
      final memoryId = memory['id'] as int?;
      final text = memory['text'] ?? '';
      final location = memory['location'] ?? '';
      final date = memory['date'] ?? '';
      final year = memory['year'] ?? '';
      final category = memory['category'] ?? '';
      final tags = memory['tags'] ?? '';
      final mentions = memory['mentions'] ?? '';
      final time = memory['time'] ?? '';
      final locationCity = memory['location_city'] ?? '';
      final locationCountry = memory['location_country'] ?? '';
      final locationFlag = memory['location_flag'] ?? '';

      // For hashtag search (starts with #)
      if (searchType.value == 'hashtag') {
        if (tags.isNotEmpty) {
          final tagList = tags.split(',');
          for (final tag in tagList) {
            final trimmedTag = tag.trim();
            final normalizedTag = SearchUtils.normalizeText(trimmedTag);
            if (normalizedTag.contains(queryWithoutPrefix) &&
                !seenHashtags.contains(trimmedTag)) {
              seenHashtags.add(trimmedTag);
              suggestionsWithMetadata.add({
                'text': '#$trimmedTag',
                'type': 'hashtag',
              });
            }
          }
        }
      }
      // For mention search (starts with @)
      else if (searchType.value == 'mention') {
        if (mentions.isNotEmpty) {
          final mentionList = mentions.split(',');
          for (final mention in mentionList) {
            final trimmedMention = mention.trim();
            final normalizedMention = SearchUtils.normalizeText(trimmedMention);
            if (normalizedMention.contains(queryWithoutPrefix) &&
                !seenMentions.contains(trimmedMention)) {
              seenMentions.add(trimmedMention);
              suggestionsWithMetadata.add({
                'text': '@$trimmedMention',
                'type': 'mention',
              });
            }
          }
        }
      }
      // For mixed search (plain text - show all types)
      else {
        // Check if this memory matches any criteria using accent-insensitive search
        bool matchesDescription = SearchUtils.matchesSearch(text, query);
        bool matchesLocation = SearchUtils.matchesSearchInAny(query, [
          locationCity,
          locationCountry,
          location,
        ]);

        // Check category match (stored English + all l10n variants)
        bool matchesCategory = false;
        final categoryStr = category.toString().trim();
        if (categoryStr.isNotEmpty) {
          String categoryName = categoryStr;
          if (categoryStr.contains(' ')) {
            final parts = categoryStr.split(' ');
            if (parts.length > 1) {
              categoryName = parts.sublist(1).join(' ');
            }
          }
          matchesCategory = SearchUtils.matchesSearchInAny(query, [
            categoryName,
            categoryStr,
            placeCategorySearchHaystack(categoryStr),
          ]);
        }

        // If memory matches description, location, or category, add it once
        if ((matchesDescription || matchesLocation || matchesCategory) &&
            memoryId != null &&
            !seenMemoryIds.contains(memoryId)) {
          seenMemoryIds.add(memoryId);

          // Determine the primary match type for display
          String matchType = 'description';
          String displayText = text;

          if (matchesDescription) {
            matchType = 'description';
            displayText = text;
          } else if (matchesLocation) {
            matchType = 'location';
            // Build location display
            if (locationCity.isNotEmpty && locationCountry.isNotEmpty) {
              displayText = '$locationCity, $locationCountry';
              if (locationFlag.isNotEmpty) {
                displayText += ' $locationFlag';
              }
            } else if (locationCity.isNotEmpty) {
              displayText = locationCity;
              if (locationFlag.isNotEmpty) {
                displayText += ' $locationFlag';
              }
            } else if (locationCountry.isNotEmpty) {
              displayText = locationCountry;
              if (locationFlag.isNotEmpty) {
                displayText += ' $locationFlag';
              }
            } else if (location.isNotEmpty) {
              displayText = location;
            }
          } else if (matchesCategory) {
            matchType = 'category';
            displayText = localizedPlaceCategoryStoredLabel(category);
          }

          suggestionsWithMetadata.add({
            'text': displayText,
            'date': date,
            'year': year,
            'time': time,
            'category': category,
            'location': location,
            'location_city': locationCity,
            'location_country': locationCountry,
            'location_flag': locationFlag,
            'type': matchType,
            'memoryId':
                memoryId, // Add memory ID for filtering to specific memory
          });
        }

        // 2. Add hashtag matches (these are unique by tag name, not memory)
        if (tags.isNotEmpty) {
          final tagList = tags.split(',');
          for (final tag in tagList) {
            final trimmedTag = tag.trim();
            if (SearchUtils.matchesSearch(trimmedTag, query) &&
                !seenHashtags.contains(trimmedTag)) {
              seenHashtags.add(trimmedTag);
              suggestionsWithMetadata.add({
                'text': '#$trimmedTag',
                'type': 'hashtag',
              });
            }
          }
        }

        // 3. Add mention matches (these are unique by mention name, not memory)
        if (mentions.isNotEmpty) {
          final mentionList = mentions.split(',');
          for (final mention in mentionList) {
            final trimmedMention = mention.trim();
            if (SearchUtils.matchesSearch(trimmedMention, query) &&
                !seenMentions.contains(trimmedMention)) {
              seenMentions.add(trimmedMention);
              suggestionsWithMetadata.add({
                'text': '@$trimmedMention',
                'type': 'mention',
              });
            }
          }
        }
      }
    }

    searchSuggestionsWithMetadata.value =
        suggestionsWithMetadata.take(10).toList();
    showSuggestions.value = suggestionsWithMetadata.isNotEmpty;
  }

  Future<void> selectSuggestion(
    String suggestion, {
    Map<String, dynamic>? suggestionData,
  }) async {

     if (isOpenedFromMap) {
      Navigator.of(Get.context!).pop();
    }
    const String tag = '[SearchController][selectSuggestion]';

    debugPrint('$tag ▶ Called with suggestion="$suggestion"');
    debugPrint('$tag ▶ suggestionData: $suggestionData');

    // Check if this is a hashtag or mention FIRST (before setting searchQuery)
    final type = suggestionData?['type'] ?? '';
    final isHashtagOrMention = type == 'hashtag' || type == 'mention';

    // Only set searchQuery for non-hashtag/mention suggestions
    if (!isHashtagOrMention) {
      searchQuery.value = suggestion;
      debugPrint('$tag ▶ Updated searchQuery to: "$suggestion"');
    } else {
      debugPrint('$tag ▶ Skipping searchQuery update for hashtag/mention');
    }

    showSuggestions.value = false;
    debugPrint('$tag ▶ Hid suggestions');

    // If this is a memory-specific suggestion (description, location, or category),
    // show only that specific memory
    if (suggestionData != null) {
      final memoryId = suggestionData['memoryId'];

      debugPrint('$tag ▶ Suggestion type: $type, memoryId: $memoryId');

      if ((type == 'description' || type == 'location' || type == 'category') &&
          memoryId != null) {
          await selectASignleMamory(memoryId, tag);
        return;
      }
    }

    debugPrint('$tag 🔄 No specific memory detected — checking if hashtag/mention');

    // For hashtags and mentions, use ID-based filter instead of keyword search
    if (suggestionData != null) {
      if (type == 'hashtag') {
        debugPrint('$tag 🏷️ Hashtag selected - using ID-based filter (orange indicator)');

        // Extract hashtag without # prefix
        final hashtag = suggestion.startsWith('#') ? suggestion.substring(1) : suggestion;

        // Clear any existing search keyword to prevent blue search indicator
        _filterController.searchedTextKeyword.value = '';
        _filterController.searchKeywords.value = '';
        _filterController.isSearchedMemoryList.value = false;
        _filterController.searchedMemoryIds.clear();

        // Add to FilterController's selectedHashtags
        _filterController.selectedHashtags.clear();
        _filterController.selectedHashtags.add(hashtag);

        // Apply filters using FilterController
        await _filterController.loadAndApplyFilters();

        // Update local state
        isSearching.value = false; // Set to false to prevent search indicator
        filteredMemories.value = _filterController.filteredMemories.toList();

        // Sync to map
        final mapController = Get.find<MapControllerNew>();
        await mapController.loadMemoriesFromDB(_filterController.filteredMemories.toList());
        mapController.showLoadedDataOnMap();

        debugPrint('$tag ✅ Hashtag filter applied: $hashtag | Results: ${filteredMemories.length}');
        onAgainInit();

        isSearchActive.value = false;
        return;
      } else if (type == 'mention') {
        debugPrint('$tag 👤 Mention selected - using ID-based filter (orange indicator)');

        // Extract mention without @ prefix
        final mention = suggestion.startsWith('@') ? suggestion.substring(1) : suggestion;

        // Clear any existing search keyword to prevent blue search indicator
        _filterController.searchedTextKeyword.value = '';
        _filterController.searchKeywords.value = '';
        _filterController.isSearchedMemoryList.value = false;
        _filterController.searchedMemoryIds.clear();

        // Add to FilterController's selectedContacts
        _filterController.selectedContacts.clear();
        _filterController.selectedContacts.add(mention);

        // Apply filters using FilterController
        await _filterController.loadAndApplyFilters();

        // Update local state
        isSearching.value = false; // Set to false to prevent search indicator
        filteredMemories.value = _filterController.filteredMemories.toList();

        // Sync to map
        final mapController = Get.find<MapControllerNew>();
        await mapController.loadMemoriesFromDB(_filterController.filteredMemories.toList());
        mapController.showLoadedDataOnMap();

        onAgainInit();

        debugPrint('$tag ✅ Mention filter applied: $mention | Results: ${filteredMemories.length}');

        isSearchActive.value = false;
        return;
      }
    }

    debugPrint('$tag 🔄 Performing keyword search (blue indicator)');

    // For other types, perform normal keyword search
    performSearch();

    isSearchActive.value = false;

    debugPrint('$tag ⛔ Search deactivated after performSearch');
  }

  Future<void> performSearch() async {
    const String tag = '[SearchController][performSearch]';

    debugPrint('$tag ▶ performSearch() called');
    debugPrint('$tag ▶ Current searchQuery: "${searchQuery.value}"');
    debugPrint('$tag ▶ hasActiveFilters: ${hasActiveFilters.value}');

    if (searchQuery.value.isEmpty) {
      debugPrint('$tag ⚠️ Search query is empty');

      // Clear searched text keyword in FilterController
      _filterController.clearSearchedTextKeyword();

      // If there are active filters, reapply them instead of clearing
      if (hasActiveFilters.value) {
        debugPrint('$tag 🔁 Reapplying active filters');
        applyFilters();
      } else {
        debugPrint('$tag 🧹 Clearing search & stopping');
        isSearching.value = false;
        rebuildDisplayList();
      }
      return;
    }

    isSearching.value = true;
    final query = searchQuery.value;

    debugPrint('$tag 🔎 Starting search for: "$query"');

    // Sync current filter state to FilterController
    _filterController.filterValues.value = Map<String, String>.from(filterValues);
    _filterController.selectedLocation.value = selectedLocation.value;
    _filterController.selectedLocationDisplayName.value = selectedLocationDisplayName.value;
    _filterController.selectedRadius.value = selectedRadius.value;
    _filterController.selectedHashtags.value = List<String>.from(selectedHashtags);
    _filterController.selectedContacts.value = List<String>.from(selectedContacts);
    _filterController.selectedCategories.value = List<String>.from(selectedCategories);

    // Set searched text keyword in FilterController
    _filterController.setSearchedTextKeyword(query);

    debugPrint('$tag ✅ Search results count: ${filteredMemories.length}');
    debugPrint('$tag 🔍 isSearching.value: ${isSearching.value}');
    debugPrint('$tag 🔍 FilterController.filteredMemories.length: ${_filterController.filteredMemories.length}');
    debugPrint('$tag 🔍 FilterController.searchedTextKeyword: "${_filterController.searchedTextKeyword.value}"');
    debugPrint('$tag 🔍 FilterController.hasActiveSearch: ${_filterController.hasActiveSearch}');

    // Sync search results to MapController with filtered memories
    // This keeps the search as a text-based search, not an ID filter
    final c1 = Get.find<MapControllerNew>();
    await c1.loadMemoriesFromDB(_filterController.filteredMemories.toList());
    c1.showLoadedDataOnMap();

    debugPrint(
      '$tag 🏁 Search completed | Query="$query" | Results=${filteredMemories.length} | isSearching=${isSearching.value} | Filters=${hasActiveFilters.value ? "ON" : "OFF"}',
    );
    rebuildDisplayList();
  }

  // Helper method to create a temporary MemoryCard for filtering
  _MemoryFilterHelper _createTempMemoryCard(Map<String, dynamic> memory) {
    return _MemoryFilterHelper(memory);
  }

  void closeSearch() {
    debugPrint('[AddMemoriesController] closeSearch() called');

    // Close the search overlay UI
    isSearchActive.value = false;

    // Clear search query and suggestions
    searchQuery.value = '';
    searchSuggestions.clear();
    searchSuggestionsWithMetadata.clear();
    showSuggestions.value = false;
    searchType.value = 'general';

    // Clear the search in FilterController
    _filterController.clearSearchedTextKeyword();

    // Only set isSearching to false if there are no active filters
    // If there are filters, keep isSearching true to show filtered results
    if (!hasActiveFilters.value) {
      isSearching.value = false;
      rebuildDisplayList();
    }

    debugPrint('[AddMemoriesController] closeSearch() completed - isSearching: ${isSearching.value}, hasActiveFilters: ${hasActiveFilters.value}');
  }

  void seeAllMemories() {
    isSearching.value = false;
    searchQuery.value = '';
    filteredMemories.clear();
    rebuildDisplayList();
  }

  String _normalizeFilterKey(String hint) => hint.trim().toLowerCase();

  void _setFilterValue(String hint, String? value) {
    final key = _normalizeFilterKey(hint);

    if (value == null || value.isEmpty) {
      filterValues.remove(key);
    } else {
      filterValues[key] = value;
    }

    _updateFilterStatus();
  }

  void onTextChanged(String hint, String value) {
    if (value.contains('@')) {
      debugPrint("Mention trigger from [$hint]: $value");
    } else if (value.contains('#')) {
      debugPrint("Tag trigger from [$hint]: $value");
    }
    _setFilterValue(hint, value);
  }

  void setFilterDate(String hint, String date) {
    _setFilterValue(hint, date);
    debugPrint("Filter date set: $hint = $date");
  }

  void setLocation(String location) {
    selectedLocation.value = location;
    debugPrint("Location set to: $location");

    // Show hint if location is set but radius is empty
    if (location.isNotEmpty && selectedRadius.value.isEmpty) {
      showTrSnackbar('snackbar_hint', 
        backgroundColor: Colors.orange.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),);
    }
  }

  void setRadius(String radius) {
    selectedRadius.value = radius;
    debugPrint("Radius set to: $radius");

    // Show hint if radius is set but location is empty
    if (radius.isNotEmpty && selectedLocation.value.isEmpty) {
      showTrSnackbar('snackbar_hint_2', 
        backgroundColor: Colors.orange.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),);
    }
  }

  // Request focus on radius field
  void requestRadiusFieldFocus() {
    shouldFocusRadiusField.value = true;
    // Reset after a short delay to allow the field to respond
    Future.delayed(const Duration(milliseconds: 100), () {
      shouldFocusRadiusField.value = false;
    });
  }

  void addHashtag(String hashtag) {
    final cleanTag = hashtag.startsWith('#') ? hashtag.substring(1) : hashtag;
    if (!selectedHashtags.contains(cleanTag)) {
      selectedHashtags.add(cleanTag);
      _updateFilterStatus();
      debugPrint("Added hashtag: $cleanTag");
    }
  }

  void removeHashtag(String hashtag) async {
    debugPrint("Attempting to remove hashtag: $hashtag");
    final removed = selectedHashtags.remove(hashtag);
    debugPrint("Hashtag removed successfully: $removed");

    if (removed) {
      // Check if this was a subcategory and if all subcategories of its main group are now removed
      await _checkAndRemoveHashtagMainGroupIfNeeded(hashtag);
    }

    _updateFilterStatus();
    selectedHashtags.refresh(); // Force UI refresh

    debugPrint(
      "Removed hashtag: $hashtag, remaining: ${selectedHashtags.length}",
    );
  }

  void addContact(String contact) {
    final cleanContact =
        contact.startsWith('@') ? contact.substring(1) : contact;
    if (!selectedContacts.contains(cleanContact)) {
      selectedContacts.add(cleanContact);
      _updateFilterStatus();
      debugPrint("Added contact: $cleanContact");
    }
  }

  void removeContact(String contact) async {
    debugPrint("Attempting to remove contact: $contact");
    final removed = selectedContacts.remove(contact);
    debugPrint("Contact removed successfully: $removed");

    if (removed) {
      // Check if this was a subcategory and if all subcategories of its main group are now removed
      await _checkAndRemoveContactMainGroupIfNeeded(contact);
    }

    _updateFilterStatus();
    selectedContacts.refresh(); // Force UI refresh

    debugPrint(
      "Removed contact: $contact, remaining: ${selectedContacts.length}",
    );
  }

  void addHashtagGroup(HashtagGroup group) async {
    final groupName = group.name;
    debugPrint(
      "[AddMemoriesController] Adding hashtag group: $groupName (id: ${group.id}, parentId: ${group.parentId})",
    );

    // If this is a main group, fetch and add all subgroups
    if (group.isMainGroup && group.id != null) {
      try {
        final hashtagGroupService = Get.find<HashtagGroupService>();
        final subgroups = await hashtagGroupService.getSubgroups(group.id!);
        debugPrint(
          "[AddMemoriesController] Fetched ${subgroups.length} subgroups for main group: $groupName",
        );

        // Remove all existing subgroups first (remove before add logic)
        for (final subgroup in subgroups) {
          if (selectedHashtags.contains(subgroup.name)) {
            selectedHashtags.remove(subgroup.name);
            debugPrint(
              "[AddMemoriesController]   - Removed existing subgroup: ${subgroup.name}",
            );
          }
        }

        // Now add all subgroups fresh
        for (final subgroup in subgroups) {
          selectedHashtags.add(subgroup.name);
          debugPrint(
            "[AddMemoriesController]   - Added subgroup: ${subgroup.name}",
          );
        }

        _updateFilterStatus();
        debugPrint(
          "[AddMemoriesController] Added ${subgroups.length} subgroups from hashtag group: $groupName (total selected: ${selectedHashtags.length})",
        );
      } catch (e) {
        debugPrint(
          "[AddMemoriesController] Error fetching subgroups for $groupName: $e",
        );
      }
    } else {
      // For subgroups, just add the hashtag itself
      if (!selectedHashtags.contains(groupName)) {
        selectedHashtags.add(groupName);
        _updateFilterStatus();
        debugPrint(
          "[AddMemoriesController] Added hashtag: $groupName (total selected: ${selectedHashtags.length})",
        );
      }
    }
  }

  void addContactGroup(ContactGroup group) async {
    final groupName = group.name;
    debugPrint(
      "[AddMemoriesController] Adding contact group: $groupName (id: ${group.id}, parentId: ${group.parentId})",
    );

    // If this is a main group, fetch and add all subgroups
    if (group.isMainGroup && group.id != null) {
      try {
        final contactGroupService = Get.find<ContactGroupService>();
        final subgroups = await contactGroupService.getSubgroups(group.id!);
        debugPrint(
          "[AddMemoriesController] Fetched ${subgroups.length} subgroups for main group: $groupName",
        );

        // Remove all existing subgroups first (remove before add logic)
        for (final subgroup in subgroups) {
          if (selectedContacts.contains(subgroup.name)) {
            selectedContacts.remove(subgroup.name);
            debugPrint(
              "[AddMemoriesController]   - Removed existing subgroup: ${subgroup.name}",
            );
          }
        }

        // Now add all subgroups fresh
        for (final subgroup in subgroups) {
          selectedContacts.add(subgroup.name);
          debugPrint(
            "[AddMemoriesController]   - Added subgroup: ${subgroup.name}",
          );
        }

        _updateFilterStatus();
        debugPrint(
          "[AddMemoriesController] Added ${subgroups.length} subgroups from contact group: $groupName (total selected: ${selectedContacts.length})",
        );
      } catch (e) {
        debugPrint(
          "[AddMemoriesController] Error fetching subgroups for $groupName: $e",
        );
      }
    } else {
      // For subgroups, just add the contact itself
      if (!selectedContacts.contains(groupName)) {
        selectedContacts.add(groupName);
        _updateFilterStatus();
        debugPrint(
          "[AddMemoriesController] Added contact: $groupName (total selected: ${selectedContacts.length})",
        );
      }
    }
  }

  void addCategory(String category) {
    if (!selectedCategories.contains(category)) {
      selectedCategories.add(category);
      _updateFilterStatus();
      debugPrint("Added category: $category");
    }
  }

  void addCategoryGroup(PlaceCategory category) async {
    final categoryWithEmoji =
        category.emoji.isNotEmpty
            ? '${category.emoji} ${category.name}'
            : category.name;

    if (!selectedCategories.contains(categoryWithEmoji)) {
      selectedCategories.add(categoryWithEmoji);

      // If this is a main category with subcategories, also add all subcategories
      if (category.isMainCategory && category.hasSubcategories) {
        debugPrint(
          "Adding main category with ${category.subcategories!.length} subcategories: $categoryWithEmoji",
        );
        for (final subcategory in category.subcategories!) {
          final subCategoryWithEmoji =
              subcategory.emoji.isNotEmpty
                  ? '${subcategory.emoji} ${subcategory.name}'
                  : subcategory.name;
          if (!selectedCategories.contains(subCategoryWithEmoji)) {
            selectedCategories.add(subCategoryWithEmoji);
            debugPrint("  - Added subcategory: $subCategoryWithEmoji");
          }
        }
      } else if (category.isMainCategory && category.id != null) {
        // If main category doesn't have subcategories loaded, fetch them from service
        try {
          final placeCategoryService = Get.find<PlaceCategoryService>();
          final subcategories = await placeCategoryService.getSubcategories(
            category.id!,
          );
          debugPrint(
            "Fetched ${subcategories.length} subcategories for main category: $categoryWithEmoji",
          );
          for (final subcategory in subcategories) {
            final subCategoryWithEmoji =
                subcategory.emoji.isNotEmpty
                    ? '${subcategory.emoji} ${subcategory.name}'
                    : subcategory.name;
            if (!selectedCategories.contains(subCategoryWithEmoji)) {
              selectedCategories.add(subCategoryWithEmoji);
              debugPrint("  - Added subcategory: $subCategoryWithEmoji");
            }
          }
        } catch (e) {
          debugPrint("Error fetching subcategories for $categoryWithEmoji: $e");
        }
      }

      _updateFilterStatus();
      debugPrint(
        "Added category group: $categoryWithEmoji (total selected: ${selectedCategories.length})",
      );
    }
  }

  void removeCategory(String category) async {
    debugPrint("Attempting to remove category: $category");
    debugPrint("Categories before removal: ${selectedCategories.toList()}");

    final removed = selectedCategories.remove(category);
    debugPrint("Category removed successfully: $removed");

    if (removed) {
      // Check if this was a subcategory and if all subcategories of its main category are now removed
      await _checkAndRemoveCategoryMainGroupIfNeeded(category);
    }

    _updateFilterStatus();

    // Force UI refresh
    selectedCategories.refresh();

    debugPrint(
      "Removed category: $category, remaining: ${selectedCategories.length}",
    );
  }

  /// Replace all selected categories with new selection from picker
  void replaceSelectedCategories(List<PlaceCategory> categories) {
    debugPrint(
      '[AddMemoriesController] Replacing selected categories with ${categories.length} new categories',
    );
    debugPrint(
      '[AddMemoriesController] Before clear: ${selectedCategories.length} categories',
    );
    selectedCategories.clear();
    debugPrint(
      '[AddMemoriesController] After clear: ${selectedCategories.length} categories',
    );

    for (final category in categories) {
      final categoryWithEmoji =
          category.emoji.isNotEmpty
              ? '${category.emoji} ${category.name}'
              : category.name;
      selectedCategories.add(categoryWithEmoji);
      debugPrint('[AddMemoriesController] Added category: $categoryWithEmoji');
    }

    // Force refresh of the observable list
    selectedCategories.refresh();

    _updateFilterStatus();
    debugPrint(
      '[AddMemoriesController] Categories replaced. Total: ${selectedCategories.length}',
    );
    debugPrint(
      '[AddMemoriesController] Final categories: ${selectedCategories.join(", ")}',
    );
  }

  /// Replace all selected hashtags with new selection from picker
  void replaceSelectedHashtags(List<HashtagGroup> groups) {
    debugPrint(
      '[AddMemoriesController] Replacing selected hashtags with ${groups.length} new groups',
    );
    debugPrint(
      '[AddMemoriesController] Before clear: ${selectedHashtags.length} hashtags',
    );
    selectedHashtags.clear();
    debugPrint(
      '[AddMemoriesController] After clear: ${selectedHashtags.length} hashtags',
    );

    for (final group in groups) {
      selectedHashtags.add(group.name);
      debugPrint('[AddMemoriesController] Added hashtag: ${group.name}');
    }

    // Force refresh of the observable list
    selectedHashtags.refresh();

    _updateFilterStatus();
    debugPrint(
      '[AddMemoriesController] Hashtags replaced. Total: ${selectedHashtags.length}',
    );
    debugPrint(
      '[AddMemoriesController] Final hashtags: ${selectedHashtags.join(", ")}',
    );
  }

  /// Replace all selected contacts with new selection from picker
  void replaceSelectedContacts(List<ContactGroup> groups) {
    debugPrint(
      '[AddMemoriesController] Replacing selected contacts with ${groups.length} new groups',
    );
    debugPrint(
      '[AddMemoriesController] Before clear: ${selectedContacts.length} contacts',
    );
    selectedContacts.clear();
    debugPrint(
      '[AddMemoriesController] After clear: ${selectedContacts.length} contacts',
    );

    for (final group in groups) {
      selectedContacts.add(group.name);
      debugPrint('[AddMemoriesController] Added contact: ${group.name}');
    }

    // Force refresh of the observable list
    selectedContacts.refresh();

    _updateFilterStatus();
    debugPrint(
      '[AddMemoriesController] Contacts replaced. Total: ${selectedContacts.length}',
    );
    debugPrint(
      '[AddMemoriesController] Final contacts: ${selectedContacts.join(", ")}',
    );
  }

  void _updateFilterStatus() {
    updateFilterStatus();
  }

  /// Check if a removed hashtag was a subcategory and remove main group if all subcategories are gone
  Future<void> _checkAndRemoveHashtagMainGroupIfNeeded(
    String removedHashtag,
  ) async {
    try {
      final hashtagGroupService = Get.find<HashtagGroupService>();
      final allGroups = await hashtagGroupService.getAllGroupsHierarchical();

      // Find which main group this subcategory belongs to
      HashtagGroup? parentMainGroup;
      for (final mainGroup in allGroups) {
        if (mainGroup.subgroups != null) {
          for (final subgroup in mainGroup.subgroups!) {
            if (subgroup.name == removedHashtag) {
              parentMainGroup = mainGroup;
              break;
            }
          }
        }
        if (parentMainGroup != null) break;
      }

      if (parentMainGroup != null) {
        debugPrint(
          "Found parent main group for removed hashtag '$removedHashtag': ${parentMainGroup.name}",
        );

        // Check if any subcategories of this main group are still selected
        bool hasRemainingSubcategories = false;
        if (parentMainGroup.subgroups != null) {
          for (final subgroup in parentMainGroup.subgroups!) {
            if (selectedHashtags.contains(subgroup.name)) {
              hasRemainingSubcategories = true;
              break;
            }
          }
        }

        // If no subcategories remain and main group is selected, remove it
        if (!hasRemainingSubcategories &&
            selectedHashtags.contains(parentMainGroup.name)) {
          selectedHashtags.remove(parentMainGroup.name);
          debugPrint(
            "Removed main hashtag group '${parentMainGroup.name}' as all its subcategories were removed",
          );
        }
      }
    } catch (e) {
      debugPrint("Error checking hashtag main group removal: $e");
    }
  }

  /// Check if a removed contact was a subcategory and remove main group if all subcategories are gone
  Future<void> _checkAndRemoveContactMainGroupIfNeeded(
    String removedContact,
  ) async {
    try {
      final contactGroupService = Get.find<ContactGroupService>();
      final allGroups = await contactGroupService.getAllGroupsHierarchical();

      // Find which main group this subcategory belongs to
      ContactGroup? parentMainGroup;
      for (final mainGroup in allGroups) {
        if (mainGroup.subgroups != null) {
          for (final subgroup in mainGroup.subgroups!) {
            if (subgroup.name == removedContact) {
              parentMainGroup = mainGroup;
              break;
            }
          }
        }
        if (parentMainGroup != null) break;
      }

      if (parentMainGroup != null) {
        debugPrint(
          "Found parent main group for removed contact '$removedContact': ${parentMainGroup.name}",
        );

        // Check if any subcategories of this main group are still selected
        bool hasRemainingSubcategories = false;
        if (parentMainGroup.subgroups != null) {
          for (final subgroup in parentMainGroup.subgroups!) {
            if (selectedContacts.contains(subgroup.name)) {
              hasRemainingSubcategories = true;
              break;
            }
          }
        }

        // If no subcategories remain and main group is selected, remove it
        if (!hasRemainingSubcategories &&
            selectedContacts.contains(parentMainGroup.name)) {
          selectedContacts.remove(parentMainGroup.name);
          debugPrint(
            "Removed main contact group '${parentMainGroup.name}' as all its subcategories were removed",
          );
        }
      }
    } catch (e) {
      debugPrint("Error checking contact main group removal: $e");
    }
  }

  /// Check if a removed category was a subcategory and remove main category if all subcategories are gone
  Future<void> _checkAndRemoveCategoryMainGroupIfNeeded(
    String removedCategory,
  ) async {
    try {
      final placeCategoryService = Get.find<PlaceCategoryService>();
      final allCategories =
          await placeCategoryService.getAllCategoriesHierarchical();

      // Find which main category this subcategory belongs to
      PlaceCategory? parentMainCategory;
      for (final mainCategory in allCategories) {
        if (mainCategory.subcategories != null) {
          for (final subcategory in mainCategory.subcategories!) {
            final subCategoryWithEmoji =
                subcategory.emoji.isNotEmpty
                    ? '${subcategory.emoji} ${subcategory.name}'
                    : subcategory.name;
            if (subCategoryWithEmoji == removedCategory) {
              parentMainCategory = mainCategory;
              break;
            }
          }
        }
        if (parentMainCategory != null) break;
      }

      if (parentMainCategory != null) {
        final mainCategoryWithEmoji =
            parentMainCategory.emoji.isNotEmpty
                ? '${parentMainCategory.emoji} ${parentMainCategory.name}'
                : parentMainCategory.name;
        debugPrint(
          "Found parent main category for removed category '$removedCategory': $mainCategoryWithEmoji",
        );

        // Check if any subcategories of this main category are still selected
        bool hasRemainingSubcategories = false;
        if (parentMainCategory.subcategories != null) {
          for (final subcategory in parentMainCategory.subcategories!) {
            final subCategoryWithEmoji =
                subcategory.emoji.isNotEmpty
                    ? '${subcategory.emoji} ${subcategory.name}'
                    : subcategory.name;
            if (selectedCategories.contains(subCategoryWithEmoji)) {
              hasRemainingSubcategories = true;
              break;
            }
          }
        }

        // If no subcategories remain and main category is selected, remove it
        if (!hasRemainingSubcategories &&
            selectedCategories.contains(mainCategoryWithEmoji)) {
          selectedCategories.remove(mainCategoryWithEmoji);
          debugPrint(
            "Removed main category '$mainCategoryWithEmoji' as all its subcategories were removed",
          );
        }
      }
    } catch (e) {
      debugPrint("Error checking category main group removal: $e");
    }
  }

  /// Public method to update filter status (can be called from external controllers)
  void updateFilterStatus() {
    // Update FilterController's filter status first
    _filterController.updateFilterStatus();

    // Sync local hasActiveFilters with FilterController
    hasActiveFilters.value = _filterController.hasActiveFilters.value;

    debugPrint(
      'Filter status updated: hasActiveFilters=${hasActiveFilters.value}',
    );
    debugPrint('  - filterValues: ${filterValues.toString()}');
    debugPrint('  - selectedLocation: "${selectedLocation.value}"');
    debugPrint('  - selectedRadius: "${selectedRadius.value}"');
    debugPrint('  - selectedHashtags: ${selectedHashtags.toString()}');
    debugPrint('  - selectedContacts: ${selectedContacts.toString()}');
    debugPrint('  - selectedCategories: ${selectedCategories.toString()}');
  }

  // Get available hashtags (cached)
  List<String> get getAvailableHashtags => availableHashtags.toList();

  // Get available contacts (cached)
  List<String> get getAvailableContacts => availableContacts.toList();

  // Get available categories (cached)
  List<String> get getAvailableCategories => availableCategories.toList();

  // Get active filter count for badge display - delegates to FilterController
  int get activeFilterCount {
    return _filterController.activeFilterCount;
  }

  // Backup filter state for cancel functionality
  Map<String, String> _backupFilterValues = {};
  String _backupSelectedLocation = '';
  String _backupSelectedRadius = '';
  List<String> _backupSelectedHashtags = [];
  List<String> _backupSelectedContacts = [];
  List<String> _backupSelectedCategories = [];

  void toggleFilter() => isFilterOpen.toggle();

  void openFilter() {
    // Backup current filter state before opening
    _backupFilterValues = Map<String, String>.from(filterValues);
    _backupSelectedLocation = selectedLocation.value;
    _backupSelectedRadius = selectedRadius.value;
    _backupSelectedHashtags = List<String>.from(selectedHashtags);
    _backupSelectedContacts = List<String>.from(selectedContacts);
    _backupSelectedCategories = List<String>.from(selectedCategories);

    isFilterOpen.value = true;
    debugPrint('[AddMemoriesController] Filter opened, state backed up');
  }

  void closeFilter() {
    // Restore backup state when closing without applying (back button)
    filterValues.clear();
    filterValues.addAll(_backupFilterValues);
    selectedLocation.value = _backupSelectedLocation;
    selectedRadius.value = _backupSelectedRadius;
    selectedHashtags.clear();
    selectedHashtags.addAll(_backupSelectedHashtags);
    selectedContacts.clear();
    selectedContacts.addAll(_backupSelectedContacts);
    selectedCategories.clear();
    selectedCategories.addAll(_backupSelectedCategories);

    isFilterOpen.value = false;
    debugPrint(
      '[AddMemoriesController] Filter closed, state restored from backup',
    );
  }

  void _closeFilterPanelOnly() {
    // Just close the panel without restoring state (used after applying filters)
    isFilterOpen.value = false;
    debugPrint('[AddMemoriesController] Filter panel closed (state kept)');
  }

  void filterByYear(String year) {
    // Clear search when year filter is applied
    _clearSearchWithoutClosing();

    isSearching.value = true;

    filteredMemories.value =
        allMemories.where((memory) {
          final memoryYear = memory['year'] ?? '';
          return memoryYear == year;
        }).toList();

    debugPrint('Filtered ${filteredMemories.length} memories for year $year');
  }

  void filterByYearMonth(String yearMonth) {
    // Clear search when year-month filter is applied
    _clearSearchWithoutClosing();

    isSearching.value = true;

    // Parse year-month format (e.g., "2025-06")
    final parts = yearMonth.split('-');
    if (parts.length != 2) {
      debugPrint('Invalid year-month format: $yearMonth');
      return;
    }

    final year = parts[0];
    final month = int.tryParse(parts[1]);

    if (month == null || month < 1 || month > 12) {
      debugPrint('Invalid month in year-month: $yearMonth');
      return;
    }

    filteredMemories.value =
        allMemories.where((memory) {
          final memoryYear = memory['year'] ?? '';
          final memoryDate = memory['date'] ?? '';

          // Check year match
          if (memoryYear != year) return false;

          // Parse memory date to get month
          try {
            // Memory date is in format like "15. January 2025"
            final parsedDate = DateFormat(
              "d. MMMM yyyy",
            ).parse('$memoryDate $memoryYear');
            return parsedDate.month == month;
          } catch (e) {
            debugPrint(
              'Error parsing memory date: $memoryDate $memoryYear - $e',
            );
            return false;
          }
        }).toList();

    debugPrint('Filtered ${filteredMemories.length} memories for $yearMonth');
  }

  void showSpecificMemories(List<MemoryLocation> memoriesInMonthData) {
    // Clear search when showing specific memories
    _clearSearchWithoutClosing();

    var ids =
        memoriesInMonthData
            .map((memoryLocation) => memoryLocation.id.toString())
            .toList();

    isSearching.value = true;
    hasActiveFilters.value =
        true; // Show filter indicator when viewing map-filtered memories

    var filteredData =
        allMemories
            .where((memory) => ids.contains(memory['id'].toString()))
            .toList();

    filteredMemories.value = filteredData;
    debugPrint(
      'Showing  filteredData ${ids} specific memories passed as parameter',
    );
  }

  // Apply filters based on filter values
  /// Now delegates to FilterController which handles all filter logic
  void applyFilters({List<int>? memoryIds}) {
    debugPrint('[AddMemoriesController] applyFilters called with memoryIds: $memoryIds');

    if (selectedMemoryIds.isNotEmpty && memoryIds == null) {
      selectedMemoryIds.clear();
    }
    if (memoryIds != null) {
      _clearFiltersWithoutClosing();
    }

    debugPrint(
      '=== APPLYING FILTERS (isOpenedFromMap: $isOpenedFromMap, memoryIds: $memoryIds) ===',
    );

    // If memory IDs are provided, set them as a filter
    if (memoryIds != null && memoryIds.isNotEmpty) {
      selectedMemoryIds.value = memoryIds.map((id) => id.toString()).toList();
      debugPrint(
        '[AddMemoriesController] 🎯 Memory IDs filter set: $memoryIds',
      );
    }

    // Validate location and radius dependency
    final hasLocation = selectedLocation.value.isNotEmpty;
    final hasRadius = selectedRadius.value.isNotEmpty;

    if (hasLocation && !hasRadius) {
      showTrSnackbar('snackbar_radius_required', 
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),);
      return;
    }

    if (hasRadius && !hasLocation) {
      showTrSnackbar('snackbar_location_required', 
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),);
      return;
    }

    // Validate date range: "to date" cannot be earlier than "from date"
    final fromDateStr = filterValues['from date'];
    final toDateStr = filterValues['to date'];
    if ((fromDateStr?.isNotEmpty ?? false) && (toDateStr?.isNotEmpty ?? false)) {
      try {
        final from = DateTime.parse(fromDateStr!);
        final to = DateTime.parse(toDateStr!);
        final fromDateOnly = DateTime(from.year, from.month, from.day);
        final toDateOnly = DateTime(to.year, to.month, to.day);

        if (toDateOnly.isBefore(fromDateOnly)) {
          showTrSnackbar('snackbar_invalid_date_range', 
            backgroundColor: Colors.red.shade400,
            colorText: Colors.white,
            margin: const EdgeInsets.all(12),
            snackPosition: SnackPosition.TOP,
            duration: const Duration(seconds: 2),);
          return;
        }
      } catch (e) {
        debugPrint('[AddMemoriesController] Date validation parse error: $e');
      }
    }

    // Clear search when filters are applied
    _clearSearchWithoutClosing();

    // Check if any filters are active
    final hasFilters =
        filterValues.isNotEmpty ||
        selectedLocation.value.isNotEmpty ||
        selectedRadius.value.isNotEmpty ||
        selectedHashtags.isNotEmpty ||
        selectedContacts.isNotEmpty ||
        selectedCategories.isNotEmpty ||
        selectedMemoryIds.isNotEmpty;

    debugPrint('ApplyFilterFromOverlay === APPLYING FILTERS ===');
    debugPrint('ApplyFilterFromOverlay Filter values: ${filterValues.toString()}');
    debugPrint('ApplyFilterFromOverlay Selected location: "${selectedLocation.value}"');
    debugPrint('ApplyFilterFromOverlay Selected radius: "${selectedRadius.value}"');
    debugPrint('ApplyFilterFromOverlay Selected hashtags: ${selectedHashtags.toString()}');
    debugPrint('ApplyFilterFromOverlay Selected contacts: ${selectedContacts.toString()}');
    debugPrint('ApplyFilterFromOverlay Selected categories: ${selectedCategories.toString()}');
    debugPrint('ApplyFilterFromOverlay Has filters: $hasFilters');

    if (!hasFilters) {
      isSearching.value = false;
      hasActiveFilters.value = false;
      _filterController.clearFilters();

      _filterController.clearSearchedTextKeyword();
      _filterController.resetFilters();
      closeFilter();
      rebuildDisplayList();
      return;
    }

    isSearching.value = true;
    hasActiveFilters.value = true;

    // Sync filter state to FilterController
    _filterController.filterValues.value = Map<String, String>.from(filterValues);
    _filterController.selectedLocation.value = selectedLocation.value;
    _filterController.selectedLocationDisplayName.value = selectedLocationDisplayName.value;
    _filterController.selectedRadius.value = selectedRadius.value;
    _filterController.selectedHashtags.value = List<String>.from(selectedHashtags);
    _filterController.selectedContacts.value = List<String>.from(selectedContacts);
    _filterController.selectedCategories.value = List<String>.from(selectedCategories);
    _filterController.selectedMemoryIds.value = List<String>.from(selectedMemoryIds);

    // Apply filters in FilterController
    _filterController.applyAllFilters();

    debugPrint(
      '[AddMemoriesController] Applied filters via FilterController, found ${filteredMemories.length} memories out of ${allMemories.length}',
    );

    // Update backup to match current state since filters were applied
    _backupFilterValues = Map<String, String>.from(filterValues);
    _backupSelectedLocation = selectedLocation.value;
    _backupSelectedRadius = selectedRadius.value;
    _backupSelectedHashtags = List<String>.from(selectedHashtags);
    _backupSelectedContacts = List<String>.from(selectedContacts);
    _backupSelectedCategories = List<String>.from(selectedCategories);

    rebuildDisplayList();
    _closeFilterPanelOnly();
  }

  // Reset all filters
  void resetFilters() {
    debugPrint('[AddMemoriesController] Resetting all filters via FilterController');

    // Reset FilterController filters first
    _filterController.resetFilters();

    // Clear local filter state
    filterValues.clear();
    selectedLocation.value = '';
    selectedRadius.value = '';
    selectedLocationDisplayName.value = '';
    selectedHashtags.clear();
    selectedContacts.clear();
    selectedCategories.clear();
    selectedMemoryIds.clear();
    isSearching.value = false;
    hasActiveFilters.value = false;

    // Update backup to match cleared state
    _backupFilterValues.clear();
    _backupSelectedLocation = '';
    _backupSelectedRadius = '';
    _backupSelectedHashtags.clear();
    _backupSelectedContacts.clear();
    _backupSelectedCategories.clear();

    _closeFilterPanelOnly();

    // Sync back to MapController if opened from map
    if (isOpenedFromMap) {
      _syncFiltersToMapController();
    }

    rebuildDisplayList();
    debugPrint('All filters reset (isOpenedFromMap: $isOpenedFromMap)');
  }

  void resetSearchFilters() {
    filterValues.clear();
    selectedLocation.value = '';
    selectedLocationDisplayName.value = '';
    selectedRadius.value = '';
    selectedHashtags.clear();
    selectedContacts.clear();
    selectedCategories.clear();
    selectedMemoryIds.clear();
    filteredMemories.clear();
    isSearching.value = false;
    hasActiveFilters.value = false;

    // Update backup to match cleared state
    _backupFilterValues.clear();
    _backupSelectedLocation = '';
    _backupSelectedRadius = '';
    _backupSelectedHashtags.clear();
    _backupSelectedContacts.clear();
    _backupSelectedCategories.clear();

    _closeFilterPanelOnly();

    // Sync back to MapController if opened from map
    if (isOpenedFromMap) {
      _syncFiltersToMapController();
    }

    rebuildDisplayList();
    debugPrint('All filters reset (isOpenedFromMap: $isOpenedFromMap)');
  }

  // Helper method to sync filters to MapController
  void _syncFiltersToMapController() {
    if (!Get.isRegistered<MapControllerNew>()) {
      debugPrint(
        '[AddMemoriesController] MapController not registered, skipping sync',
      );
      return;
    }

    try {
      final mapController = Get.find<MapControllerNew>();

      debugPrint('[AddMemoriesController] 🔄 Syncing filters to map via FilterController');

      // FilterController is already the single source of truth
      // Just reload the map with the current filtered memories
      mapController.loadMemoriesFromDB(_filterController.filteredMemories.toList());

      Future.delayed(Duration(milliseconds: 200), () {
        mapController.showLoadedDataOnMap();
        mapController.initializeMapAfterCreation();
      });

      debugPrint(
        '[AddMemoriesController] ✅ Map synced with ${_filterController.filteredMemories.length} filtered memories',
      );
    } catch (e) {
      debugPrint(
        '[AddMemoriesController] ❌ Failed to sync filters to MapController: $e',
      );
    }
  }

  /// Sync filters to MapController and load filtered memories from database
  /// Returns the filtered list of memories based on current filter settings
  Future<List<Map<String, dynamic>>> syncFiltersAndLoadMemories() async {
    try {
      debugPrint(
        '[AddMemoriesController] 🔄 Syncing filters and loading memories via FilterController...',
      );

      if (!Get.isRegistered<MapControllerNew>()) {
        debugPrint('[AddMemoriesController] ⚠️ MapController not registered');
        return [];
      }

      final mapController = Get.find<MapControllerNew>();

      // FilterController is the single source of truth for all filters
      // No need to manually sync individual filter properties
      debugPrint('[AddMemoriesController] ✅ Using FilterController as single source of truth');
      debugPrint('[AddMemoriesController] 📋 Active filters:');

      if (_filterController.filterValues.isNotEmpty) {
        debugPrint('  - Text filters: ${_filterController.filterValues.values.join(", ")}');
      }
      if (_filterController.selectedHashtags.isNotEmpty) {
        debugPrint('  - Hashtags: ${_filterController.selectedHashtags.join(", ")}');
      }
      if (_filterController.selectedContacts.isNotEmpty) {
        debugPrint('  - Contacts: ${_filterController.selectedContacts.join(", ")}');
      }
      if (_filterController.selectedCategories.isNotEmpty) {
        debugPrint('  - Categories: ${_filterController.selectedCategories.join(", ")}');
      }
      if (_filterController.selectedMemoryIds.isNotEmpty) {
        debugPrint('  - Memory IDs: ${_filterController.selectedMemoryIds.join(", ")}');
      }
      if (_filterController.selectedLocation.value.isNotEmpty &&
          _filterController.selectedRadius.value.isNotEmpty) {
        debugPrint(
          '  - Location: ${_filterController.selectedLocation.value} (radius: ${_filterController.selectedRadius.value}km)',
        );
      }
      if (_filterController.searchedTextKeyword.value.isNotEmpty) {
        debugPrint('  - Search keyword: "${_filterController.searchedTextKeyword.value}"');
      }

      debugPrint(
        '[AddMemoriesController] 📊 Loaded ${_filterController.filteredMemories.length} filtered memories',
      );

      // Reload map with filtered memories
      await mapController.loadMemoriesFromDB(_filterController.filteredMemories.toList());
      mapController.showLoadedDataOnMap();

      debugPrint('[AddMemoriesController] ✅ Map synced with filtered memories');

      return filteredMemories;
    } catch (e) {
      debugPrint(
        '[AddMemoriesController] ❌ Error syncing filters and loading memories: $e',
      );
      return [];
    }
  }

  // // Helper method to clear filters without closing the filter panel
  void _clearFiltersWithoutClosing() {
    filterValues.clear();
    selectedLocation.value = '';
    selectedLocationDisplayName.value = '';
    selectedRadius.value = '';
    selectedHashtags.clear();
    selectedContacts.clear();
    selectedCategories.clear();
    hasActiveFilters.value = false;
  }

  // Helper method to clear search without closing search panel
  void _clearSearchWithoutClosing() {
    searchQuery.value = '';
    searchSuggestions.clear();
    searchSuggestionsWithMetadata.clear();
    showSuggestions.value = false;
    searchType.value = 'general';
  }

  void handleScrollUpdate(double currentOffset, double maxScrollExtent) {
    final isAtTop = currentOffset <= 10; // Small threshold for top
    final isAtBottom =
        currentOffset >= (maxScrollExtent - 10); // Small threshold for bottom
    final scrollDelta = currentOffset - _lastScrollOffset;

    // Only update if scroll delta is significant enough to avoid jitter
    if (scrollDelta.abs() > 5) {
      _isScrollingDown = scrollDelta > 0;

      // Show UI if at top, bottom, or scrolling up
      // Hide UI if scrolling down and not at top/bottom
      if (isAtTop || isAtBottom || !_isScrollingDown) {
        showUI();
      } else if (_isScrollingDown && !isAtTop && !isAtBottom) {
        hideUI();
      }
    }

    _lastScrollOffset = currentOffset;
  }

  void hideUI() {
    isUIVisible.value = false;
  }

  void showUI() {
    isUIVisible.value = true;
  }


  // Debug method to check current state
  void debugCurrentState() {
    debugPrint('=== AddMemoriesController Debug State ===');
    debugPrint('isLoading: ${isLoading.value}');
    debugPrint('isSearching: ${isSearching.value}');
    debugPrint('allMemories count: ${allMemories.length}');
    debugPrint('filteredMemories count: ${filteredMemories.length}');
    debugPrint('isUIVisible: ${isUIVisible.value}');
    debugPrint('========================================');
  }

  void setEnhancedLocationData(locationData) {
    if (locationData != null) {
      debugPrint('🎯 setEnhancedLocationData received: $locationData');

      // Extract location data
      var locationLatitude = locationData['latitude']?.toDouble();
      var locationLongitude = locationData['longitude']?.toDouble();

      // Get display name from various possible fields
      var displayName =
          locationData['name'] ??
          locationData['address'] ??
          locationData['city'] ??
          'Selected Location';

      // Set selectedLocation as coordinates for filtering
      // Set selectedLocationDisplayName for UI display
      if (locationLatitude != null && locationLongitude != null) {
        // Format to 4 decimal places for filtering
        final formattedLat = locationLatitude.toStringAsFixed(4);
        final formattedLng = locationLongitude.toStringAsFixed(4);
        selectedLocation.value = '$formattedLat,$formattedLng';
        selectedLocationDisplayName.value = displayName;

        debugPrint(
          '🎯 Set selectedLocation (coords): ${selectedLocation.value}',
        );
        debugPrint('🎯 Set selectedLocationDisplayName: $displayName');
      } else {
        selectedLocation.value = '';
        selectedLocationDisplayName.value = '';
      }
    }
  }

  /// Load hierarchical data for display logic
  Future<void> _loadHierarchicalData() async {
    try {
      final hashtagGroupService = Get.find<HashtagGroupService>();
      final contactGroupService = Get.find<ContactGroupService>();
      final placeCategoryService = Get.find<PlaceCategoryService>();

      _cachedHashtagGroups =
          await hashtagGroupService.getAllGroupsHierarchical();
      _cachedContactGroups =
          await contactGroupService.getAllGroupsHierarchical();
      _cachedCategories =
          await placeCategoryService.getAllCategoriesHierarchical();

      debugPrint(
        '[AddMemoriesController] Loaded hierarchical data: ${_cachedHashtagGroups.length} hashtag groups, ${_cachedContactGroups.length} contact groups, ${_cachedCategories.length} categories',
      );
    } catch (e) {
      debugPrint('[AddMemoriesController][_loadHierarchicalData] Error: $e');
    }
  }

  /// Get display list for hashtags - show only main groups when all subgroups are selected
  List<String> _getDisplayHashtags() {
    final displayList = <String>[];
    final processedSubgroups = <String>{};

    for (final mainGroup in _cachedHashtagGroups) {
      if (mainGroup.hasSubgroups) {
        // Check if all subgroups are selected
        final allSubgroupsSelected = mainGroup.subgroups!.every(
          (subgroup) => selectedHashtags.contains(subgroup.name),
        );

        if (allSubgroupsSelected && selectedHashtags.contains(mainGroup.name)) {
          // Show only main group
          displayList.add(mainGroup.name);
          // Mark all subgroups as processed
          for (final subgroup in mainGroup.subgroups!) {
            processedSubgroups.add(subgroup.name);
          }
        } else {
          // Show individual subgroups that are selected
          for (final subgroup in mainGroup.subgroups!) {
            if (selectedHashtags.contains(subgroup.name)) {
              displayList.add(subgroup.name);
              processedSubgroups.add(subgroup.name);
            }
          }
        }
      }
    }

    // Add any selected hashtags that weren't processed (individual hashtags, not groups)
    for (final hashtag in selectedHashtags) {
      if (!processedSubgroups.contains(hashtag) &&
          !displayList.contains(hashtag)) {
        displayList.add(hashtag);
      }
    }

    return displayList;
  }

  /// Get display list for contacts - show only main groups when all subgroups are selected
  List<String> _getDisplayContacts() {
    final displayList = <String>[];
    final processedSubgroups = <String>{};

    for (final mainGroup in _cachedContactGroups) {
      if (mainGroup.hasSubgroups) {
        // Check if all subgroups are selected
        final allSubgroupsSelected = mainGroup.subgroups!.every(
          (subgroup) => selectedContacts.contains(subgroup.name),
        );

        if (allSubgroupsSelected && selectedContacts.contains(mainGroup.name)) {
          // Show only main group
          displayList.add(mainGroup.name);
          // Mark all subgroups as processed
          for (final subgroup in mainGroup.subgroups!) {
            processedSubgroups.add(subgroup.name);
          }
        } else {
          // Show individual subgroups that are selected
          for (final subgroup in mainGroup.subgroups!) {
            if (selectedContacts.contains(subgroup.name)) {
              displayList.add(subgroup.name);
              processedSubgroups.add(subgroup.name);
            }
          }
        }
      }
    }

    // Add any selected contacts that weren't processed (individual contacts, not groups)
    for (final contact in selectedContacts) {
      if (!processedSubgroups.contains(contact) &&
          !displayList.contains(contact)) {
        displayList.add(contact);
      }
    }

    return displayList;
  }

  /// Get display list for categories - show only main categories when all subcategories are selected
  List<String> _getDisplayCategories() {
    final displayList = <String>[];
    final processedSubcategories = <String>{};

    for (final mainCategory in _cachedCategories) {
      final mainCategoryWithEmoji =
          mainCategory.emoji.isNotEmpty
              ? '${mainCategory.emoji} ${mainCategory.name}'
              : mainCategory.name;

      if (mainCategory.hasSubcategories) {
        // Check if all subcategories are selected
        final allSubcategoriesSelected = mainCategory.subcategories!.every((
          subcategory,
        ) {
          final subCategoryWithEmoji =
              subcategory.emoji.isNotEmpty
                  ? '${subcategory.emoji} ${subcategory.name}'
                  : subcategory.name;
          return selectedCategories.contains(subCategoryWithEmoji);
        });

        if (allSubcategoriesSelected &&
            selectedCategories.contains(mainCategoryWithEmoji)) {
          // Show only main category
          displayList.add(mainCategoryWithEmoji);
          // Mark all subcategories as processed
          for (final subcategory in mainCategory.subcategories!) {
            final subCategoryWithEmoji =
                subcategory.emoji.isNotEmpty
                    ? '${subcategory.emoji} ${subcategory.name}'
                    : subcategory.name;
            processedSubcategories.add(subCategoryWithEmoji);
          }
        } else {
          // Show individual subcategories that are selected
          for (final subcategory in mainCategory.subcategories!) {
            final subCategoryWithEmoji =
                subcategory.emoji.isNotEmpty
                    ? '${subcategory.emoji} ${subcategory.name}'
                    : subcategory.name;
            if (selectedCategories.contains(subCategoryWithEmoji)) {
              displayList.add(subCategoryWithEmoji);
              processedSubcategories.add(subCategoryWithEmoji);
            }
          }
        }
      }
    }

    // Add any selected categories that weren't processed (individual categories, not groups)
    for (final category in selectedCategories) {
      if (!processedSubcategories.contains(category) &&
          !displayList.contains(category)) {
        displayList.add(category);
      }
    }

    return displayList;
  }
  
  Future<void> selectASignleMamory(memoryId, tag) async {
      debugPrint('$tag 🎯 Memory-specific suggestion detected');

        isSearching.value = true;

        filteredMemories.value =
            allMemories.where((memory) {
              final match = memory['id'] == memoryId;
              debugPrint(
                '$tag 🔍 Checking memory ID ${memory['id']} == $memoryId → $match',
              );
              return match;
            }).toList();

        debugPrint(
          '$tag ✅ Selected specific memory with ID: $memoryId | Result count: ${filteredMemories.length}',
        );

        final c1 = Get.find<MapControllerNew>();
        List<int> memoryIdInt = [];

        for (var memory in filteredMemories) {
          final idStr = memory['id'];
          final idInt = int.tryParse(idStr.toString());

          if (idInt != null) {
            memoryIdInt.add(idInt);
            debugPrint('$tag ➕ Parsed memory ID: $idInt');
          } else {
            debugPrint('$tag ❌ Failed to parse memory ID: $idStr');
          }
        }

        if (memoryIdInt.isNotEmpty) {
          debugPrint('$tag 🎯 Applying memory ID filters to map: $memoryIdInt');

          applyFilters(memoryIds: memoryIdInt);
          await c1.loadFilteredMemoriesFromDB();
          c1.handleFilterApplyFromMap(memoryIds: memoryIdInt);

          debugPrint(
            '$tag 🗺️ MapControllerNew updated with filtered memory IDs',
          );
        } else {
          debugPrint('$tag ⚠️ No valid memory IDs found to apply to map');
        }

        isSearchActive.value = false;
        debugPrint('$tag ⛔ Search deactivated and early return');
  }


    
  Future<void> selectHashtagOrMentionSuggestion(suggestion, {required Map<String, dynamic> suggestionData}) async {
     if (isOpenedFromMap) {
      Navigator.of(Get.context!).pop();
    }
    const String tag = '[SearchController][selectHashtagOrMentionSuggestion]';

    debugPrint('$tag ▶ Called with suggestion="$suggestion"');
    debugPrint('$tag ▶ suggestionData: $suggestionData');

    // Check if this is a hashtag or mention FIRST (before setting searchQuery)
    final type = suggestionData?['type'] ?? '';
    final isHashtagOrMention = type == 'hashtag' || type == 'mention';

    // Only set searchQuery for non-hashtag/mention suggestions
    if (!isHashtagOrMention) {
      searchQuery.value = suggestion;
      debugPrint('$tag ▶ Updated searchQuery to: "$suggestion"');
    } else {
      debugPrint('$tag ▶ Skipping searchQuery update for hashtag/mention');
    }

    // var tag = ' [SearchController][selectSuggestion] ';
      if (suggestion != null) {
      if (type == 'hashtag') {
        debugPrint('$tag 🏷️ Hashtag selected - using ID-based filter (orange indicator)');

        // Extract hashtag without # prefix
        final hashtag = suggestion.startsWith('#') ? suggestion.substring(1) : suggestion;

        // Clear any existing search keyword to prevent blue search indicator
        _filterController.searchedTextKeyword.value = '';
        _filterController.searchKeywords.value = '';
        _filterController.isSearchedMemoryList.value = false;
        _filterController.searchedMemoryIds.clear();

        // Add to FilterController's selectedHashtags
        _filterController.selectedHashtags.clear();
        _filterController.selectedHashtags.add(hashtag);

        // Apply filters using FilterController
        await _filterController.loadAndApplyFilters();

        // Update local state from FilterController (single source of truth)
        isSearching.value = false; // Set to false to prevent search indicator
        hasActiveFilters.value = true; // ✅ Sync from FilterController
        filteredMemories.value = _filterController.filteredMemories.toList();
        allMemories.value = _filterController.allMemories.toList();

        debugPrint('$tag 🔍 hasActiveFilters synced: ${hasActiveFilters.value}');
        debugPrint('$tag 🔍 activeFilterCount: ${activeFilterCount}');
        debugPrint('$tag 🔍 filteredMemories count: ${filteredMemories.length}');

        // Sync to map
        final mapController = Get.find<MapControllerNew>();
        await mapController.loadMemoriesFromDB(_filterController.filteredMemories.toList());
        mapController.showLoadedDataOnMap();

        debugPrint('$tag ✅ Hashtag filter applied: $hashtag | Results: ${filteredMemories.length}');

        isSearchActive.value = false;
        return;
      } else if (type == 'mention') {
        debugPrint('$tag 👤 Mention selected - using ID-based filter (orange indicator)');

        // Extract mention without @ prefix
        final mention = suggestion.startsWith('@') ? suggestion.substring(1) : suggestion;

        // Clear any existing search keyword to prevent blue search indicator
        _filterController.searchedTextKeyword.value = '';
        _filterController.searchKeywords.value = '';
        _filterController.isSearchedMemoryList.value = false;
        _filterController.searchedMemoryIds.clear();

        // Add to FilterController's selectedContacts
        _filterController.selectedContacts.clear();
        _filterController.selectedContacts.add(mention);

        // Apply filters using FilterController
        await _filterController.loadAndApplyFilters();

        // Update local state from FilterController (single source of truth)
        isSearching.value = false; // Set to false to prevent search indicator
        hasActiveFilters.value = true; // ✅ Sync from FilterController
        filteredMemories.value = _filterController.filteredMemories.toList();
        allMemories.value = _filterController.allMemories.toList();

        debugPrint('$tag 🔍 hasActiveFilters synced: ${hasActiveFilters.value}');
        debugPrint('$tag 🔍 activeFilterCount: ${activeFilterCount}');
        debugPrint('$tag 🔍 filteredMemories count: ${filteredMemories.length}');

        // Sync to map
        final mapController = Get.find<MapControllerNew>();
        await mapController.loadMemoriesFromDB(_filterController.filteredMemories.toList());
        mapController.showLoadedDataOnMap();

        debugPrint('$tag ✅ Mention filter applied: $mention | Results: ${filteredMemories.length}');

        isSearchActive.value = false;
        return;
      }
    }
  }
}

// Helper class for memory filtering without creating widget instances
class _MemoryFilterHelper {
  final Map<String, dynamic> memoryData;

  _MemoryFilterHelper(this.memoryData);

  // Getter methods for accessing memory data with safe type casting
  String get date {
    try {
      final value = memoryData['date'];
      return (value is String) ? value : '';
    } catch (e) {
      return '';
    }
  }

  String get year {
    try {
      final value = memoryData['year'];
      return (value is String) ? value : '';
    } catch (e) {
      return '';
    }
  }

  String get location {
    try {
      final value = memoryData['location'];
      return (value is String) ? value : '';
    } catch (e) {
      return '';
    }
  }

  String get time {
    try {
      final value = memoryData['time'];
      return (value is String) ? value : '';
    } catch (e) {
      return '';
    }
  }

  String? get text {
    try {
      final value = memoryData['text'];
      return (value is String && value.isNotEmpty) ? value : null;
    } catch (e) {
      return null;
    }
  }

  String? get category {
    try {
      final value = memoryData['category'];
      return (value is String && value.isNotEmpty) ? value : null;
    } catch (e) {
      return null;
    }
  }

  String? get tags {
    try {
      final value = memoryData['tags'];
      return (value is String && value.isNotEmpty) ? value : null;
    } catch (e) {
      return null;
    }
  }

  String? get mentions {
    try {
      final value = memoryData['mentions'];
      return (value is String && value.isNotEmpty) ? value : null;
    } catch (e) {
      return null;
    }
  }

  String? get createdAt {
    try {
      final value = memoryData['created_at'];
      return (value is String && value.isNotEmpty) ? value : null;
    } catch (e) {
      return null;
    }
  }

  bool matchesSearchQuery(String query) {
    if (query.isEmpty) return true;

    // Use accent-insensitive, multi-word search
    return SearchUtils.matchesSearchInAny(query, [
      text,
      location,
      date,
      category,
      tags,
      mentions,
    ]);
  }

  bool matchesFilters(Map<String, String> filters) {
    debugPrint('=== DATE FILTER DEBUG ===');
    debugPrint('All filters: ${filters.toString()}');
    debugPrint('Memory ID: ${memoryData['id']}');
    debugPrint('Memory raw date: "${memoryData['date']}"');
    debugPrint('Memory formatted date: "$date"');

    // Filter by date range using the memory's selected date (not created_at)
    final fromDate = filters['from date'];
    final toDate = filters['to date'];

    debugPrint('From date filter: "$fromDate"');
    debugPrint('To date filter: "$toDate"');

    if (fromDate != null && fromDate.isNotEmpty) {
      try {
        final from = DateTime.parse(fromDate);
        // The date field from database is in 'yyyy-MM-dd' format
        final memoryDateStr = '$date $year';
        debugPrint(
          'Date filter FROM: comparing memory date "$memoryDateStr" with filter date "$fromDate"',
        );

        if (memoryDateStr.isEmpty) {
          debugPrint('Memory date is empty, filtering out');
          return false;
        }

        DateTime parsedDate = DateFormat("d. MMMM yyyy").parse(memoryDateStr);

        // final memoryDate = DateTime.tryParse(memoryDateStr);
        if (parsedDate == null) {
          debugPrint('Could not parse memory date: $memoryDateStr');
          return false;
        }

        debugPrint('Parsed memory date: $parsedDate');
        debugPrint('Parsed filter from date: $from');

        // Compare dates (ignore time)
        final memoryDateOnly = DateTime(
          parsedDate.year,
          parsedDate.month,
          parsedDate.day,
        );
        final fromDateOnly = DateTime(from.year, from.month, from.day);

        if (memoryDateOnly.isBefore(fromDateOnly)) {
          debugPrint(
            'Memory date $memoryDateOnly is before filter date $fromDateOnly - FILTERED OUT',
          );
          return false;
        }

        debugPrint('Memory passed FROM date filter');
      } catch (e) {
        debugPrint('Error parsing from date filter: $e');
        return false;
      }
    }

    if (toDate != null && toDate.isNotEmpty) {
      try {
        final to = DateTime.parse(toDate);
        // The date field from database is in 'yyyy-MM-dd' format
        final memoryDateStr = '$date $year';
        debugPrint(
          'Date filter TO: comparing memory date "$memoryDateStr" with filter date "$toDate"',
        );

        if (memoryDateStr.isEmpty) {
          debugPrint('Memory date is empty, filtering out');
          return false;
        }

        DateTime memoryDate = DateFormat("d. MMMM yyyy").parse(memoryDateStr);
        if (memoryDate == null) {
          debugPrint('Could not parse memory date: $memoryDateStr');
          return false;
        }

        debugPrint('Parsed memory date: $memoryDate');
        debugPrint('Parsed filter to date: $to');

        // Compare dates (ignore time)
        final memoryDateOnly = DateTime(
          memoryDate.year,
          memoryDate.month,
          memoryDate.day,
        );
        final toDateOnly = DateTime(to.year, to.month, to.day);

        if (memoryDateOnly.isAfter(toDateOnly)) {
          debugPrint(
            'Memory date $memoryDateOnly is after filter date $toDateOnly - FILTERED OUT',
          );
          return false;
        }

        debugPrint('Memory passed TO date filter');
      } catch (e) {
        debugPrint('Error parsing to date filter: $e');
        return false;
      }
    }

    debugPrint('=== END DATE FILTER DEBUG ===');

    // Filter by location
    final locationFilter = filters['location'];
    if (locationFilter != null && locationFilter.isNotEmpty) {
      // Get the raw location from database (might be coordinates or location name)
      final rawLocation = memoryData['location'] as String? ?? '';
      debugPrint(
        'Filtering location: "$locationFilter" against raw location: "$rawLocation"',
      );

      // Check if the location filter matches the raw location
      if (!rawLocation.toLowerCase().contains(locationFilter.toLowerCase())) {
        return false;
      }
    }

    // Filter by category
    final categoryFilter = filters['category'];
    if (categoryFilter != null && categoryFilter.isNotEmpty) {
      if (category == null || category!.isEmpty) return false;
      if (!category!.toLowerCase().contains(categoryFilter.toLowerCase()) &&
          !SearchUtils.matchesSearchInAny(categoryFilter, [
            category!,
            placeCategorySearchHaystack(category!),
          ])) {
        return false;
      }
    }

    // Filter by tags
    final tagsFilter = filters['tags'];
    if (tagsFilter != null && tagsFilter.isNotEmpty) {
      if (tags == null ||
          !tags!.toLowerCase().contains(tagsFilter.toLowerCase())) {
        return false;
      }
    }

    // Filter by mentions
    final mentionsFilter = filters['mentions'];
    if (mentionsFilter != null && mentionsFilter.isNotEmpty) {
      if (mentions == null ||
          !mentions!.toLowerCase().contains(mentionsFilter.toLowerCase())) {
        return false;
      }
    }

    return true;
  }

  bool matchesAdvancedFilters(
    Map<String, String> filters,
    String locationFilter,
    String radiusFilter,
    List<String> hashtagFilters,
    List<String> contactFilters,
    List<String> categoryFilters,
  ) {
    // First check basic filters
    if (!matchesFilters(filters)) {
      return false;
    }

    // Filter by location (if not already handled in basic filters and no radius specified)
    if (locationFilter.isNotEmpty &&
        !filters.containsKey('location') &&
        radiusFilter.isEmpty) {
      // Simple location text matching when no radius is specified
      final rawLocation =
          '${memoryData['location_latitude']},${memoryData['location_longitude']}';
      debugPrint(
        'Simple location filter: "$locationFilter" against "$rawLocation"',
      );

      if (!rawLocation.toLowerCase().contains(locationFilter.toLowerCase())) {
        debugPrint('Memory filtered out by simple location filter');
        return false;
      }

      debugPrint('Memory passed simple location filter');
    }

    // Filter by hashtags - check if hashtags exist in description
    if (hashtagFilters.isNotEmpty) {
      final description = text ?? '';
      bool hasMatchingTag = false;

      for (final filterTag in hashtagFilters) {
        // Check if hashtag exists in description (with or without # symbol)
        final tagPattern = '#${filterTag.toLowerCase()}';
        if (description.toLowerCase().contains(tagPattern) ||
            description.toLowerCase().contains(filterTag.toLowerCase())) {
          hasMatchingTag = true;
          break;
        }
      }

      if (!hasMatchingTag) return false;
      debugPrint('Memory passed hashtag filter: $hashtagFilters');
    }

    // Filter by contacts - check if @contacts exist in description
    if (contactFilters.isNotEmpty) {
      final description = text ?? '';
      bool hasMatchingContact = false;

      for (final filterContact in contactFilters) {
        // Check if contact exists in description (with or without @ symbol)
        final contactPattern = '@${filterContact.toLowerCase()}';
        if (description.toLowerCase().contains(contactPattern) ||
            description.toLowerCase().contains(filterContact.toLowerCase())) {
          hasMatchingContact = true;
          break;
        }
      }

      if (!hasMatchingContact) return false;
      debugPrint('Memory passed contact filter: $contactFilters');
    }

    // Filter by categories
    if (categoryFilters.isNotEmpty) {
      if (category == null || category!.isEmpty) return false;

      bool hasMatchingCategory = false;
      for (final filterCategory in categoryFilters) {
        if (category!.toLowerCase().contains(filterCategory.toLowerCase()) ||
            SearchUtils.matchesSearchInAny(filterCategory, [
              category!,
              placeCategorySearchHaystack(category!),
            ])) {
          hasMatchingCategory = true;
          break;
        }
      }

      if (!hasMatchingCategory) return false;
    }

    // Filter by location radius
    if (locationFilter.isNotEmpty && radiusFilter.isNotEmpty) {
      try {
        final radius = double.tryParse(radiusFilter);
        if (radius != null && radius > 0) {
          // Parse filter location coordinates
          final filterLocationParts = locationFilter.split(',');
          if (filterLocationParts.length == 2) {
            final filterLat = double.tryParse(filterLocationParts[0].trim());
            final filterLng = double.tryParse(filterLocationParts[1].trim());

            if (filterLat != null && filterLng != null) {
              // Parse memory location coordinates
              final memoryLocation =
                  '${memoryData['location_latitude']},${memoryData['location_longitude']}';
              final memoryLocationParts = memoryLocation.split(',');

              if (memoryLocationParts.length == 2) {
                final memoryLat = double.tryParse(
                  memoryLocationParts[0].trim(),
                );
                final memoryLng = double.tryParse(
                  memoryLocationParts[1].trim(),
                );

                if (memoryLat != null && memoryLng != null) {
                  // Calculate distance in miles
                  final distance = _calculateDistanceInMiles(
                    filterLat,
                    filterLng,
                    memoryLat,
                    memoryLng,
                  );

                  debugPrint(
                    'Location radius filter: distance=$distance miles, radius=$radius miles',
                  );

                  if (distance > radius) {
                    debugPrint(
                      'Memory filtered out by radius: $distance > $radius miles',
                    );
                    return false;
                  }

                  debugPrint('Memory passed radius filter');
                } else {
                  debugPrint(
                    'Could not parse memory coordinates: $memoryLocation',
                  );
                  return false;
                }
              } else {
                debugPrint('Invalid memory location format: $memoryLocation');
                return false;
              }
            } else {
              debugPrint('Could not parse filter coordinates: $locationFilter');
              return false;
            }
          } else {
            debugPrint('Invalid filter location format: $locationFilter');
            return false;
          }
        } else {
          debugPrint('Invalid radius value: $radiusFilter');
        }
      } catch (e) {
        debugPrint('Error in radius filtering: $e');
      }
    }

    return true;
  }

  // Calculate distance between two coordinates in miles using Haversine formula
  double _calculateDistanceInMiles(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusMiles = 3959.0; // Earth's radius in miles

    final double dLat = (lat2 - lat1) * (pi / 180);
    final double dLng = (lng2 - lng1) * (pi / 180);

    final double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) *
            cos(lat2 * (pi / 180)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusMiles * c;
  }
}
