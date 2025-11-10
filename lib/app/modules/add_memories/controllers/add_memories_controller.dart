import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
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
import 'dart:math';

class AddMemoriesController extends GetxController {
  var isFilterOpen = false.obs;
  var isSearchActive = false.obs;
  var searchQuery = ''.obs;
  var filteredMemories = <Map<String, dynamic>>[].obs;
  var isSearching = false.obs;
  var searchSuggestions = <String>[].obs;
  var showSuggestions = false.obs;
  final RxBool isUIVisible = true.obs;

  // Track search type and memory data for description-based searches
  var searchType = 'general'.obs; // 'general', 'hashtag', 'mention', 'description'
  var searchSuggestionsWithMetadata = <Map<String, dynamic>>[].obs;

  late ScrollController scrollController;

  double _lastScrollOffset = 0.0;
  bool _isScrollingDown = false;

  final RxMap<String, String> filterValues = <String, String>{}.obs;
  final selectedLocation = ''.obs;
  final selectedRadius = ''.obs;
  final RxList<String> selectedHashtags = <String>[].obs;
  final RxList<String> selectedContacts = <String>[].obs;
  final RxList<String> selectedCategories = <String>[].obs;
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

  // Real memories from database
  var allMemories = <Map<String, dynamic>>[].obs;
  var isLoading = false.obs;

  bool isOpenedFromMap = false;

  @override
  void onInit() {
    debugPrint('AddMemoriesController onInit called');
    scrollController = ScrollController();
    scrollController.addListener(_scrollListener);

    // Add a small delay to ensure UI is ready
    Future.delayed(const Duration(milliseconds: 100), () {
      loadMemoriesFromDatabase();
      loadFilterData(); // Load filter data
      _loadHierarchicalData(); // Load hierarchical data for display logic
    });

    super.onInit();
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

    // Reset all states
    isLoading.value = false;
    isSearching.value = false;
    isSearchActive.value = false;
    isFilterOpen.value = false;
    isUIVisible.value = true;

    // Clear search and filter states
    searchQuery.value = '';
    filteredMemories.clear();
    searchSuggestions.clear();
    searchSuggestionsWithMetadata.clear();
    showSuggestions.value = false;
    searchType.value = 'general';
    filterValues.clear();
    selectedLocation.value = '';

    // Reload memories from database
    loadMemoriesFromDatabase();

    // Reload filter data
    loadFilterData();

    debugPrint('AddMemoriesController: onAgainInit completed');
  }

  // Load memories from database
  Future<void> loadMemoriesFromDatabase() async {
    try {
      isLoading.value = true;
      debugPrint('Starting to load memories from database...');

      final memories = await _databaseHelper.getAllMemoriesWithDetails();
      debugPrint('Raw memories from database: ${memories.first}');

      // Transform database memories to UI format
      final transformedMemories = <Map<String, dynamic>>[];
      for (final memory in memories) {
        try {
          final transformed = transformDatabaseMemoryToUI(memory);
          transformedMemories.add(transformed);
          debugPrint(
            'Transformed memory: ${transformed['date']} - ${transformed['location']}',
          );
        } catch (e) {
          debugPrint('Error transforming memory ${memory['id']}: $e');
        }
      }

      // Sort memories by date and time (newest first)
      transformedMemories.sort((a, b) {
        try {
          // Get date, year, and time components
          final aDate = a['date'] as String? ?? '';
          final bDate = b['date'] as String? ?? '';
          final aYear = a['year'] as String? ?? '';
          final bYear = b['year'] as String? ?? '';
          final aTime = a['time'] as String? ?? '';
          final bTime = b['time'] as String? ?? '';

          print(
            '[DateParsing] aDate: $aDate, bDate: $bDate, aYear: $aYear, bYear: $bYear, aTime: $aTime, bTime: $bTime',
          );

          DateTime? aDateTime;
          DateTime? bDateTime;

          String format =
              Platform.isIOS ? "d. MMMM yyyy hh:mm a" : "d. MMMM yyyy HH:mm";
          // Try to parse memory A
          if (aTime.toLowerCase().contains('am') ||
              aTime.toLowerCase().contains('pm')) {
            format = "d. MMMM yyyy hh:mm a";
          } else {
            format = "d. MMMM yyyy HH:mm";
          }

          try {
            if (aDate.isNotEmpty) {
              // Check if date already contains full format: "9. September 2025 06:33"
              if (aDate.contains(' ') && aDate.split(' ').length >= 4) {
                aDateTime = DateFormat(format).parse(aDate);
              } else if (aYear.isNotEmpty) {
                // Format: "15. January" + year + time
                String dateTimeStr = '$aDate $aYear';
                if (aTime.isNotEmpty) {
                  dateTimeStr += ' $aTime';
                  print('Parsing date A with time: $dateTimeStr');

                  aDateTime = DateFormat(format).parse(dateTimeStr);
                } else {
                  aDateTime = DateFormat("d. MMMM yyyy").parse(dateTimeStr);
                }
              }
            }
          } catch (e) {
            debugPrint('Error parsing date A: $aDate $aYear $aTime - $e');
          }
          if (bTime.toLowerCase().contains('am') ||
              bTime.toLowerCase().contains('pm')) {
            format = "d. MMMM yyyy hh:mm a";
          } else {
            format = "d. MMMM yyyy HH:mm";
          }

          // Try to parse memory B
          try {
            if (bDate.isNotEmpty) {
              // Check if date already contains full format: "9. September 2025 06:33"
              if (bDate.contains(' ') && bDate.split(' ').length >= 4) {
                bDateTime = DateFormat(format).parse(bDate);
              } else if (bYear.isNotEmpty) {
                // Format: "15. January" + year + time
                String dateTimeStr = '$bDate $bYear';
                if (bTime.isNotEmpty) {
                  dateTimeStr += ' $bTime';
                  print('Parsing date B with time: $dateTimeStr');
                  bDateTime = DateFormat(format).parse(dateTimeStr);
                } else {
                  bDateTime = DateFormat("d. MMMM yyyy").parse(dateTimeStr);
                }
              }
            }
          } catch (e) {
            debugPrint('Error parsing date B: $bDate $bYear $bTime - $e');
          }

          // Compare parsed dates
          if (aDateTime != null && bDateTime != null) {
            return bDateTime.compareTo(aDateTime); // Newest first
          } else if (aDateTime != null) {
            return -1; // A has valid date, B doesn't
          } else if (bDateTime != null) {
            return 1; // B has valid date, A doesn't
          }

          // Fallback to string comparison
          return 0;
        } catch (e) {
          debugPrint('Error sorting memories: $e');
          return 0; // Keep original order if sorting fails
        }
      });

      debugPrint(
        'Sorted ${transformedMemories.length} memories by date and time (newest first)',
      );
      allMemories.value = transformedMemories;
      debugPrint(
        'Successfully loaded ${allMemories.length} memories from database',
      );
    } catch (e) {
      debugPrint('Error loading memories: $e');
      // Add some mock data for testing if database fails

      debugPrint('Added mock data due to database error');
    } finally {
      isLoading.value = false;
    }
  }

  // Transform database memory to UI format
  Map<String, dynamic> transformDatabaseMemoryToUI(
    Map<String, dynamic> dbMemory,
  ) {
    final createdAt = DateTime.tryParse(dbMemory['created_at'] ?? '');
    final date = _formatDate(dbMemory['date'], dbMemory['created_at']);
    final year = _formatYear(dbMemory['date'], dbMemory['created_at']);

    // Get images from the new 'images' field (loaded from separate table)
    final imagesList = dbMemory['images'] as List<String>?;
    List<String>? displayImages;
    if (imagesList != null && imagesList.isNotEmpty) {
      // Check if images are file paths or base64
      displayImages =
          imagesList.map((image) {
            if (_isFilePath(image)) {
              return image; // Keep file path as is
            } else {
              // Legacy base64 - convert to file if needed
              return image; // For now, keep base64 for backward compatibility
            }
          }).toList();
    }

    // Get audio data from the new 'audios' field (loaded from separate table)
    final audiosList = dbMemory['audios'] as List<Map<String, dynamic>>?;
    List<String>? audioDurations;
    List<String>? audioPaths;
    if (audiosList != null && audiosList.isNotEmpty) {
      audioDurations =
          audiosList.map((audio) => audio['audio_duration'] as String).toList();
      audioPaths =
          audiosList
              .map((audio) => audio['audio_file_path'] as String)
              .toList();
    } else {
      // Fallback to old method for backward compatibility
      audioPaths = _databaseHelper.getAudioPathsFromMemory(dbMemory);
      if (audioPaths.isNotEmpty) {
        audioDurations =
            audioPaths.map((path) => _extractDurationFromPath(path)).toList();
      }
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
      'base64Images': imagesList, // Use the images from separate table
      'audioPaths': audioPaths,
      'created_at': dbMemory['created_at'],
    };
  }

  // Helper method to check if string is a file path
  bool _isFilePath(String str) {
    return str.startsWith('/') ||
        str.contains('\\') ||
        str.contains('.jpg') ||
        str.contains('.jpeg') ||
        str.contains('.png') ||
        str.contains('.gif') ||
        str.contains('.webp');
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

  String _formatYear(String? dbDate, String? createdAt) {
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
      searchType.value = 'mixed'; // Changed from 'description' to 'mixed' for all types
    }

    final suggestionsWithMetadata = <Map<String, dynamic>>[];
    final lowerQuery = query.toLowerCase();
    final queryWithoutPrefix = query.startsWith('#') || query.startsWith('@')
        ? query.substring(1).toLowerCase()
        : lowerQuery;

    // Track unique suggestions to avoid duplicates
    final seenDescriptions = <String>{};
    final seenHashtags = <String>{};
    final seenMentions = <String>{};
    final seenLocations = <String>{};

    for (final memory in allMemories) {
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
            if (trimmedTag.toLowerCase().contains(queryWithoutPrefix) &&
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
            if (trimmedMention.toLowerCase().contains(queryWithoutPrefix) &&
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
        // 1. Add description matches
        if (text.toLowerCase().contains(lowerQuery) && !seenDescriptions.contains(text)) {
          seenDescriptions.add(text);
          suggestionsWithMetadata.add({
            'text': text,
            'date': date,
            'year': year,
            'time': time,
            'category': category,
            'location': location,
            'location_city': locationCity,
            'location_country': locationCountry,
            'location_flag': locationFlag,
            'type': 'description',
          });
        }

        // 2. Add hashtag matches
        if (tags.isNotEmpty) {
          final tagList = tags.split(',');
          for (final tag in tagList) {
            final trimmedTag = tag.trim();
            if (trimmedTag.toLowerCase().contains(lowerQuery) &&
                !seenHashtags.contains(trimmedTag)) {
              seenHashtags.add(trimmedTag);
              suggestionsWithMetadata.add({
                'text': '#$trimmedTag',
                'type': 'hashtag',
              });
            }
          }
        }

        // 3. Add mention matches
        if (mentions.isNotEmpty) {
          final mentionList = mentions.split(',');
          for (final mention in mentionList) {
            final trimmedMention = mention.trim();
            if (trimmedMention.toLowerCase().contains(lowerQuery) &&
                !seenMentions.contains(trimmedMention)) {
              seenMentions.add(trimmedMention);
              suggestionsWithMetadata.add({
                'text': '@$trimmedMention',
                'type': 'mention',
              });
            }
          }
        }

        // 4. Add location matches (city/country)
        String locationDisplay = '';
        if (locationCity.isNotEmpty && locationCountry.isNotEmpty) {
          locationDisplay = '$locationCity, $locationCountry';
          if (locationFlag.isNotEmpty) {
            locationDisplay += ' $locationFlag';
          }
        } else if (location.isNotEmpty) {
          locationDisplay = location;
        }

        if (locationDisplay.isNotEmpty &&
            (locationCity.toLowerCase().contains(lowerQuery) ||
             locationCountry.toLowerCase().contains(lowerQuery) ||
             location.toLowerCase().contains(lowerQuery)) &&
            !seenLocations.contains(locationDisplay)) {
          seenLocations.add(locationDisplay);
          suggestionsWithMetadata.add({
            'text': locationDisplay,
            'date': date,
            'year': year,
            'time': time,
            'category': category,
            'location': location,
            'location_city': locationCity,
            'location_country': locationCountry,
            'location_flag': locationFlag,
            'type': 'location',
          });
        }
      }
    }

    searchSuggestionsWithMetadata.value = suggestionsWithMetadata.take(10).toList();
    showSuggestions.value = suggestionsWithMetadata.isNotEmpty;
  }

  void selectSuggestion(String suggestion) {
    searchQuery.value = suggestion;
    showSuggestions.value = false;
    performSearch();
    isSearchActive.value = false;
  }

  void performSearch() {
    if (searchQuery.value.isEmpty) {
      // If there are active filters, reapply them instead of clearing
      if (hasActiveFilters.value) {
        applyFilters();
      } else {
        filteredMemories.clear();
        isSearching.value = false;
      }
      return;
    }

    // Don't clear filters when search is applied - allow both to work together
    // Filters should persist until manually removed or reset

    isSearching.value = true;
    final query = searchQuery.value;

    // Start with all memories or filtered memories if filters are active
    List<Map<String, dynamic>> memoriesToSearch = allMemories;

    // If filters are active, apply them first
    if (hasActiveFilters.value) {
      memoriesToSearch = allMemories.where((memory) {
        final helper = _MemoryFilterHelper(memory);
        return helper.matchesAdvancedFilters(
          filterValues,
          selectedLocation.value,
          selectedRadius.value,
          selectedHashtags,
          selectedContacts,
          selectedCategories,
        );
      }).toList();
    }

    // Then apply search on top of filtered results
    filteredMemories.value =
        memoriesToSearch.where((memory) {
          // Create a temporary MemoryCard to use its filtering methods
          final tempCard = _createTempMemoryCard(memory);
          return tempCard.matchesSearchQuery(query);
        }).toList();

    debugPrint(
      'Filtered ${filteredMemories.length} memories for query: $query (with ${hasActiveFilters.value ? "active filters" : "no filters"})',
    );
  }

  // Helper method to create a temporary MemoryCard for filtering
  _MemoryFilterHelper _createTempMemoryCard(Map<String, dynamic> memory) {
    return _MemoryFilterHelper(memory);
  }

  void closeSearch() {
    isSearchActive.value = false;
    searchQuery.value = '';
    isSearching.value = false;

    searchSuggestions.clear();
    searchSuggestionsWithMetadata.clear();
    showSuggestions.value = false;
    searchType.value = 'general';
  }

  void seeAllMemories() {
    isSearching.value = false;
    searchQuery.value = '';
    filteredMemories.clear();
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
      Get.snackbar(
        'Hint',
        'Don\'t forget to set the radius for location-based filtering',
        backgroundColor: Colors.orange.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
    }
  }

  void setRadius(String radius) {
    selectedRadius.value = radius;
    debugPrint("Radius set to: $radius");

    // Show hint if radius is set but location is empty
    if (radius.isNotEmpty && selectedLocation.value.isEmpty) {
      Get.snackbar(
        'Hint',
        'Please select a location to use with the radius filter',
        backgroundColor: Colors.orange.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 2),
      );
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
    if (!selectedHashtags.contains(groupName)) {
      selectedHashtags.add(groupName);

      // If this is a main group with subgroups, also add all subcategories
      if (group.isMainGroup && group.hasSubgroups) {
        debugPrint("Adding main hashtag group with ${group.subgroups!.length} subcategories: $groupName");
        for (final subgroup in group.subgroups!) {
          if (!selectedHashtags.contains(subgroup.name)) {
            selectedHashtags.add(subgroup.name);
            debugPrint("  - Added subcategory: ${subgroup.name}");
          }
        }
      } else if (group.isMainGroup && group.id != null) {
        // If main group doesn't have subgroups loaded, fetch them from service
        try {
          final hashtagGroupService = Get.find<HashtagGroupService>();
          final subgroups = await hashtagGroupService.getSubgroups(group.id!);
          debugPrint("Fetched ${subgroups.length} subcategories for main group: $groupName");
          for (final subgroup in subgroups) {
            if (!selectedHashtags.contains(subgroup.name)) {
              selectedHashtags.add(subgroup.name);
              debugPrint("  - Added subcategory: ${subgroup.name}");
            }
          }
        } catch (e) {
          debugPrint("Error fetching subgroups for $groupName: $e");
        }
      }

      _updateFilterStatus();
      debugPrint("Added hashtag group: $groupName (total selected: ${selectedHashtags.length})");
    }
  }

  void addContactGroup(ContactGroup group) async {
    final groupName = group.name;
    if (!selectedContacts.contains(groupName)) {
      selectedContacts.add(groupName);

      // If this is a main group with subgroups, also add all subcategories
      if (group.isMainGroup && group.hasSubgroups) {
        debugPrint("Adding main contact group with ${group.subgroups!.length} subcategories: $groupName");
        for (final subgroup in group.subgroups!) {
          if (!selectedContacts.contains(subgroup.name)) {
            selectedContacts.add(subgroup.name);
            debugPrint("  - Added subcategory: ${subgroup.name}");
          }
        }
      } else if (group.isMainGroup && group.id != null) {
        // If main group doesn't have subgroups loaded, fetch them from service
        try {
          final contactGroupService = Get.find<ContactGroupService>();
          final subgroups = await contactGroupService.getSubgroups(group.id!);
          debugPrint("Fetched ${subgroups.length} subcategories for main contact group: $groupName");
          for (final subgroup in subgroups) {
            if (!selectedContacts.contains(subgroup.name)) {
              selectedContacts.add(subgroup.name);
              debugPrint("  - Added subcategory: ${subgroup.name}");
            }
          }
        } catch (e) {
          debugPrint("Error fetching subgroups for contact group $groupName: $e");
        }
      }

      _updateFilterStatus();
      debugPrint("Added contact group: $groupName (total selected: ${selectedContacts.length})");
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
    final categoryWithEmoji = category.emoji.isNotEmpty
        ? '${category.emoji} ${category.name}'
        : category.name;

    if (!selectedCategories.contains(categoryWithEmoji)) {
      selectedCategories.add(categoryWithEmoji);

      // If this is a main category with subcategories, also add all subcategories
      if (category.isMainCategory && category.hasSubcategories) {
        debugPrint("Adding main category with ${category.subcategories!.length} subcategories: $categoryWithEmoji");
        for (final subcategory in category.subcategories!) {
          final subCategoryWithEmoji = subcategory.emoji.isNotEmpty
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
          final subcategories = await placeCategoryService.getSubcategories(category.id!);
          debugPrint("Fetched ${subcategories.length} subcategories for main category: $categoryWithEmoji");
          for (final subcategory in subcategories) {
            final subCategoryWithEmoji = subcategory.emoji.isNotEmpty
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
      debugPrint("Added category group: $categoryWithEmoji (total selected: ${selectedCategories.length})");
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

  void _updateFilterStatus() {
    updateFilterStatus();
  }

  /// Check if a removed hashtag was a subcategory and remove main group if all subcategories are gone
  Future<void> _checkAndRemoveHashtagMainGroupIfNeeded(String removedHashtag) async {
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
        debugPrint("Found parent main group for removed hashtag '$removedHashtag': ${parentMainGroup.name}");

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
        if (!hasRemainingSubcategories && selectedHashtags.contains(parentMainGroup.name)) {
          selectedHashtags.remove(parentMainGroup.name);
          debugPrint("Removed main hashtag group '${parentMainGroup.name}' as all its subcategories were removed");
        }
      }
    } catch (e) {
      debugPrint("Error checking hashtag main group removal: $e");
    }
  }

  /// Check if a removed contact was a subcategory and remove main group if all subcategories are gone
  Future<void> _checkAndRemoveContactMainGroupIfNeeded(String removedContact) async {
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
        debugPrint("Found parent main group for removed contact '$removedContact': ${parentMainGroup.name}");

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
        if (!hasRemainingSubcategories && selectedContacts.contains(parentMainGroup.name)) {
          selectedContacts.remove(parentMainGroup.name);
          debugPrint("Removed main contact group '${parentMainGroup.name}' as all its subcategories were removed");
        }
      }
    } catch (e) {
      debugPrint("Error checking contact main group removal: $e");
    }
  }

  /// Check if a removed category was a subcategory and remove main category if all subcategories are gone
  Future<void> _checkAndRemoveCategoryMainGroupIfNeeded(String removedCategory) async {
    try {
      final placeCategoryService = Get.find<PlaceCategoryService>();
      final allCategories = await placeCategoryService.getAllCategoriesHierarchical();

      // Find which main category this subcategory belongs to
      PlaceCategory? parentMainCategory;
      for (final mainCategory in allCategories) {
        if (mainCategory.subcategories != null) {
          for (final subcategory in mainCategory.subcategories!) {
            final subCategoryWithEmoji = subcategory.emoji.isNotEmpty
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
        final mainCategoryWithEmoji = parentMainCategory.emoji.isNotEmpty
            ? '${parentMainCategory.emoji} ${parentMainCategory.name}'
            : parentMainCategory.name;
        debugPrint("Found parent main category for removed category '$removedCategory': $mainCategoryWithEmoji");

        // Check if any subcategories of this main category are still selected
        bool hasRemainingSubcategories = false;
        if (parentMainCategory.subcategories != null) {
          for (final subcategory in parentMainCategory.subcategories!) {
            final subCategoryWithEmoji = subcategory.emoji.isNotEmpty
                ? '${subcategory.emoji} ${subcategory.name}'
                : subcategory.name;
            if (selectedCategories.contains(subCategoryWithEmoji)) {
              hasRemainingSubcategories = true;
              break;
            }
          }
        }

        // If no subcategories remain and main category is selected, remove it
        if (!hasRemainingSubcategories && selectedCategories.contains(mainCategoryWithEmoji)) {
          selectedCategories.remove(mainCategoryWithEmoji);
          debugPrint("Removed main category '$mainCategoryWithEmoji' as all its subcategories were removed");
        }
      }
    } catch (e) {
      debugPrint("Error checking category main group removal: $e");
    }
  }

  /// Public method to update filter status (can be called from external controllers)
  void updateFilterStatus() {
    hasActiveFilters.value =
        filterValues.isNotEmpty ||
        selectedLocation.value.isNotEmpty ||
        selectedRadius.value.isNotEmpty ||
        selectedHashtags.isNotEmpty ||
        selectedContacts.isNotEmpty ||
        selectedCategories.isNotEmpty;

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

  void toggleFilter() => isFilterOpen.toggle();
  void openFilter() => isFilterOpen.value = true;
  void closeFilter() => isFilterOpen.value = false;

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
  void applyFilters() {
    // Note: When opened from map, we apply filters directly without navigation
    // The navigation is handled by the MapController
    debugPrint('=== APPLYING FILTERS (isOpenedFromMap: $isOpenedFromMap) ===');

    // Validate location and radius dependency
    final hasLocation = selectedLocation.value.isNotEmpty;
    final hasRadius = selectedRadius.value.isNotEmpty;

    if (hasLocation && !hasRadius) {
      Get.snackbar(
        'Validation Error',
        'Radius is required when location is selected',
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
      return;
    }

    if (hasRadius && !hasLocation) {
      Get.snackbar(
        'Validation Error',
        'Location is required when radius is specified',
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 3),
      );
      return;
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
        selectedCategories.isNotEmpty;

    debugPrint('=== APPLYING FILTERS ===');
    debugPrint('Filter values: ${filterValues.toString()}');
    debugPrint('Selected location: "${selectedLocation.value}"');
    debugPrint('Selected radius: "${selectedRadius.value}"');
    debugPrint('Selected hashtags: ${selectedHashtags.toString()}');
    debugPrint('Selected contacts: ${selectedContacts.toString()}');
    debugPrint('Selected categories: ${selectedCategories.toString()}');
    debugPrint('Has filters: $hasFilters');

    if (!hasFilters) {
      filteredMemories.clear();
      isSearching.value = false;
      hasActiveFilters.value = false;
      closeFilter();
      return;
    }

    isSearching.value = true;
    hasActiveFilters.value = true;

    // Use MemoryFilterHelper for filtering
    filteredMemories.value =
        allMemories.where((memory) {
          final helper = _MemoryFilterHelper(memory);
          final matches = helper.matchesAdvancedFilters(
            filterValues,
            selectedLocation.value,
            selectedRadius.value,
            selectedHashtags,
            selectedContacts,
            selectedCategories,
          );

          if (!matches) {
            debugPrint('Memory ${memory['id']} filtered out');
          }

          return matches;
        }).toList();

    debugPrint(
      'Applied filters, found ${filteredMemories.length} memories out of ${allMemories.length}',
    );

    closeFilter();
  }

  // Reset all filters
  void resetFilters() {
    filterValues.clear();
    selectedLocation.value = '';
    selectedRadius.value = '';
    selectedHashtags.clear();
    selectedContacts.clear();
    selectedCategories.clear();
    filteredMemories.clear();
    isSearching.value = false;
    hasActiveFilters.value = false;
    closeFilter();

    // Sync back to MapController if opened from map
    if (isOpenedFromMap) {
      _syncFiltersToMapController();
    }

    debugPrint('All filters reset (isOpenedFromMap: $isOpenedFromMap)');
  }

  // Helper method to sync filters to MapController
  void _syncFiltersToMapController() {
    if (!Get.isRegistered<MapControllerNew>()) {
      return;
    }

    try {
      final mapController = Get.find<MapControllerNew>();
      mapController.filterValues.clear();
      mapController.selectedLocation.value = '';
      mapController.selectedRadius.value = '';
      mapController.selectedHashtags.clear();
      mapController.selectedContacts.clear();
      mapController.selectedCategories.clear();
      mapController.hasActiveFilters.value = false;

      debugPrint('[AddMemoriesController] Synced reset filters to MapController');
    } catch (e) {
      debugPrint('[AddMemoriesController] Failed to sync filters to MapController: $e');
    }
  }

  // Helper method to clear filters without closing the filter panel
  void _clearFiltersWithoutClosing() {
    filterValues.clear();
    selectedLocation.value = '';
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

  // Manual refresh method
  Future<void> refreshMemories() async {
    await loadMemoriesFromDatabase();
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
      print('locationData $locationData');

      // Set enhanced location fields first

      var locationLatitude = locationData['latitude']?.toDouble();
      var locationLongitude = locationData['longitude']?.toDouble();

      // Always set selectedLocation as lat,lng coordinates with 4 decimal places
      if (locationLatitude != null && locationLongitude != null) {
        // Format to 4 decimal places
        final formattedLat = locationLatitude.toStringAsFixed(4);
        final formattedLng = locationLongitude.toStringAsFixed(4);
        selectedLocation.value = '$formattedLat,$formattedLng';
      } else {
        selectedLocation.value = '';
      }
    }
  }

  /// Load hierarchical data for display logic
  Future<void> _loadHierarchicalData() async {
    try {
      final hashtagGroupService = Get.find<HashtagGroupService>();
      final contactGroupService = Get.find<ContactGroupService>();
      final placeCategoryService = Get.find<PlaceCategoryService>();

      _cachedHashtagGroups = await hashtagGroupService.getAllGroupsHierarchical();
      _cachedContactGroups = await contactGroupService.getAllGroupsHierarchical();
      _cachedCategories = await placeCategoryService.getAllCategoriesHierarchical();

      debugPrint('[AddMemoriesController] Loaded hierarchical data: ${_cachedHashtagGroups.length} hashtag groups, ${_cachedContactGroups.length} contact groups, ${_cachedCategories.length} categories');
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
      if (!processedSubgroups.contains(hashtag) && !displayList.contains(hashtag)) {
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
      if (!processedSubgroups.contains(contact) && !displayList.contains(contact)) {
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
      final mainCategoryWithEmoji = mainCategory.emoji.isNotEmpty
          ? '${mainCategory.emoji} ${mainCategory.name}'
          : mainCategory.name;

      if (mainCategory.hasSubcategories) {
        // Check if all subcategories are selected
        final allSubcategoriesSelected = mainCategory.subcategories!.every(
          (subcategory) {
            final subCategoryWithEmoji = subcategory.emoji.isNotEmpty
                ? '${subcategory.emoji} ${subcategory.name}'
                : subcategory.name;
            return selectedCategories.contains(subCategoryWithEmoji);
          },
        );

        if (allSubcategoriesSelected && selectedCategories.contains(mainCategoryWithEmoji)) {
          // Show only main category
          displayList.add(mainCategoryWithEmoji);
          // Mark all subcategories as processed
          for (final subcategory in mainCategory.subcategories!) {
            final subCategoryWithEmoji = subcategory.emoji.isNotEmpty
                ? '${subcategory.emoji} ${subcategory.name}'
                : subcategory.name;
            processedSubcategories.add(subCategoryWithEmoji);
          }
        } else {
          // Show individual subcategories that are selected
          for (final subcategory in mainCategory.subcategories!) {
            final subCategoryWithEmoji = subcategory.emoji.isNotEmpty
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
      if (!processedSubcategories.contains(category) && !displayList.contains(category)) {
        displayList.add(category);
      }
    }

    return displayList;
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

    final lowerQuery = query.toLowerCase();
    return (text?.toLowerCase().contains(lowerQuery) ?? false) ||
        location.toLowerCase().contains(lowerQuery) ||
        date.toLowerCase().contains(lowerQuery) ||
        (category?.toLowerCase().contains(lowerQuery) ?? false) ||
        (tags?.toLowerCase().contains(lowerQuery) ?? false) ||
        (mentions?.toLowerCase().contains(lowerQuery) ?? false);
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
      if (category == null ||
          !category!.toLowerCase().contains(categoryFilter.toLowerCase())) {
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
        if (category!.toLowerCase().contains(filterCategory.toLowerCase())) {
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
