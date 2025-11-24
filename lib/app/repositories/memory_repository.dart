import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../services/memory_db.dart';

/// Repository class for handling all memory-related database operations
class MemoryRepository extends GetxService {
  static MemoryRepository get instance => Get.find<MemoryRepository>();

  DatabaseHelper? _databaseHelper;

  // Reactive state for memory data
  final RxList<Map<String, dynamic>> allMemories = <Map<String, dynamic>>[].obs;
  final RxBool isLoadingMemories = false.obs;
  final RxInt totalMemoriesCount = 0.obs;

  @override
  void onInit() {
    super.onInit();
    _initializeRepository();
  }

  /// Initialize the repository
  void _initializeRepository() {
    try {
      _databaseHelper = DatabaseHelper.instance;
      debugPrint(
        '[MemoryRepository] Repository initialized with DatabaseHelper',
      );
    } catch (e) {
      debugPrint('[MemoryRepository] Error initializing DatabaseHelper: $e');
      _databaseHelper = null;
    }
  }

  /// Load all memories from database
  Future<List<Map<String, dynamic>>?> loadAllMemories() async {
    try {
      debugPrint(
        '[MemoryRepository] Starting to load memories from database...',
      );
      isLoadingMemories.value = true;

      if (_databaseHelper == null) {
        debugPrint(
          '[MemoryRepository] DatabaseHelper not initialized, attempting to reinitialize...',
        );
        _initializeRepository();

        if (_databaseHelper == null) {
          debugPrint('[MemoryRepository] Failed to initialize DatabaseHelper');
          return null;
        }
      }

      // Get all memories with their details (images, audio, etc.)
      final memories = await _databaseHelper!.getAllMemoriesWithDetails();
      debugPrint(
        '[MemoryRepository] Loaded ${memories.length} memories from database',
      );

      // Update reactive variables
      allMemories.assignAll(memories);
      totalMemoriesCount.value = memories.length;

      // Log sample memory data for debugging
      if (memories.isNotEmpty) {
        final sampleMemory = memories.first;
        debugPrint(
          '[MemoryRepository] Sample memory: ID=${sampleMemory['id']}, '
          'Date=${sampleMemory['date']}, Location=${sampleMemory['location']}, '
          'Images=${sampleMemory['images']?.length ?? 0}',
        );
      }

      debugPrint(
        '[MemoryRepository] Successfully loaded ${memories.length} memories',
      );

      // Print detailed statistics
      printMemoryStatistics();

      return memories;
    } catch (e) {
      debugPrint('[MemoryRepository] Error loading memories from database: $e');
      // Show error message to user
      Get.snackbar(
        'Unable to Load Memories',
        'Unable to load your memories. Please try again.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    } finally {
      isLoadingMemories.value = false;
    }

    return null;
  }

  /// Get memories by location (within a certain radius)
  List<Map<String, dynamic>> getMemoriesNearLocation(
    double latitude,
    double longitude, {
    double radiusKm = 1.0,
  }) {
    return allMemories.where((memory) {
      final memoryLat = memory['location_latitude'] as double?;
      final memoryLng = memory['location_longitude'] as double?;

      if (memoryLat == null || memoryLng == null) return false;

      // Calculate distance using Haversine formula
      final distance = _calculateDistance(
        latitude,
        longitude,
        memoryLat,
        memoryLng,
      );
      return distance <= radiusKm;
    }).toList();
  }

  /// Get memories by date range
  List<Map<String, dynamic>> getMemoriesByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    return allMemories.where((memory) {
      final memoryDateStr = memory['date'] as String?;
      if (memoryDateStr == null) return false;

      try {
        final memoryDate = DateTime.parse(memoryDateStr);
        return memoryDate.isAfter(
              startDate.subtract(const Duration(days: 1)),
            ) &&
            memoryDate.isBefore(endDate.add(const Duration(days: 1)));
      } catch (e) {
        debugPrint(
          '[MemoryRepository] Error parsing memory date: $memoryDateStr',
        );
        return false;
      }
    }).toList();
  }

  /// Get memories by category
  List<Map<String, dynamic>> getMemoriesByCategory(String category) {
    return allMemories.where((memory) {
      final memoryCategory = memory['category'] as String?;
      return memoryCategory?.toLowerCase() == category.toLowerCase();
    }).toList();
  }

  /// Get memories with tags
  List<Map<String, dynamic>> getMemoriesWithTags(List<String> tags) {
    return allMemories.where((memory) {
      final memoryTags = memory['tags'] as String?;
      if (memoryTags == null || memoryTags.isEmpty) return false;

      final memoryTagList =
          memoryTags.split(',').map((tag) => tag.trim().toLowerCase()).toList();
      return tags.any((tag) => memoryTagList.contains(tag.toLowerCase()));
    }).toList();
  }

  /// Get memories with mentions
  List<Map<String, dynamic>> getMemoriesWithMentions(List<String> mentions) {
    return allMemories.where((memory) {
      final memoryMentions = memory['mentions'] as String?;
      if (memoryMentions == null || memoryMentions.isEmpty) return false;

      final memoryMentionList =
          memoryMentions
              .split(',')
              .map((mention) => mention.trim().toLowerCase())
              .toList();
      return mentions.any(
        (mention) => memoryMentionList.contains(mention.toLowerCase()),
      );
    }).toList();
  }

  /// Search memories by text content
  List<Map<String, dynamic>> searchMemories(String query) {
    if (query.isEmpty) return allMemories.toList();

    final lowerQuery = query.toLowerCase();
    return allMemories.where((memory) {
      final description =
          (memory['description'] as String?)?.toLowerCase() ?? '';
      final tags = (memory['tags'] as String?)?.toLowerCase() ?? '';
      final mentions = (memory['mentions'] as String?)?.toLowerCase() ?? '';
      final location = (memory['location'] as String?)?.toLowerCase() ?? '';
      final locationName =
          (memory['location_name'] as String?)?.toLowerCase() ?? '';

      return description.contains(lowerQuery) ||
          tags.contains(lowerQuery) ||
          mentions.contains(lowerQuery) ||
          location.contains(lowerQuery) ||
          locationName.contains(lowerQuery);
    }).toList();
  }

  /// Get memory by ID
  Map<String, dynamic>? getMemoryById(int id) {
    try {
      return allMemories.firstWhere((memory) => memory['id'] == id);
    } catch (e) {
      debugPrint('[MemoryRepository] Memory with ID $id not found');
      return null;
    }
  }

  /// Calculate distance between two points using Haversine formula
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  /// Get memory statistics
  Map<String, dynamic> getMemoryStatistics() {
    final stats = <String, dynamic>{
      'total_memories': allMemories.length,
      'memories_with_location': 0,
      'memories_with_images': 0,
      'memories_with_audio': 0,
      'date_range': null,
      'categories': <String, int>{},
      'popular_tags': <String, int>{},
    };

    if (allMemories.isNotEmpty) {
      DateTime? earliestDate;
      DateTime? latestDate;
      final categoryCount = <String, int>{};
      final tagCount = <String, int>{};

      for (final memory in allMemories) {
        // Count memories with location
        if (memory['location_latitude'] != null &&
            memory['location_longitude'] != null) {
          stats['memories_with_location']++;
        }

        // Count memories with images
        final images = memory['images'] as List<dynamic>?;
        if (images != null && images.isNotEmpty) {
          stats['memories_with_images']++;
        }

        // Count memories with audio
        final audios = memory['audios'] as List<dynamic>?;
        if (audios != null && audios.isNotEmpty) {
          stats['memories_with_audio']++;
        }

        // Count categories
        final category = memory['category'] as String?;
        if (category != null && category.isNotEmpty) {
          categoryCount[category] = (categoryCount[category] ?? 0) + 1;
        }

        // Count tags
        final tags = memory['tags'] as String?;
        if (tags != null && tags.isNotEmpty) {
          final tagList = tags
              .split(',')
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty);
          for (final tag in tagList) {
            tagCount[tag] = (tagCount[tag] ?? 0) + 1;
          }
        }

        // Track date range
        final dateStr = memory['date'] as String?;
        if (dateStr != null) {
          try {
            final date = DateTime.parse(dateStr);
            if (earliestDate == null || date.isBefore(earliestDate)) {
              earliestDate = date;
            }
            if (latestDate == null || date.isAfter(latestDate)) {
              latestDate = date;
            }
          } catch (e) {
            debugPrint('[MemoryRepository] Error parsing date: $dateStr');
          }
        }
      }

      if (earliestDate != null && latestDate != null) {
        stats['date_range'] = {
          'earliest': earliestDate.toIso8601String(),
          'latest': latestDate.toIso8601String(),
        };
      }

      stats['categories'] = categoryCount;
      stats['popular_tags'] = tagCount;
    }

    return stats;
  }

  /// Print memory statistics to console
  void printMemoryStatistics() {
    final stats = getMemoryStatistics();
    debugPrint('[MemoryRepository] Memory Statistics:');
    debugPrint('  Total memories: ${stats['total_memories']}');
    debugPrint('  With location: ${stats['memories_with_location']}');
    debugPrint('  With images: ${stats['memories_with_images']}');
    debugPrint('  With audio: ${stats['memories_with_audio']}');
    if (stats['date_range'] != null) {
      debugPrint(
        '  Date range: ${stats['date_range']['earliest']} to ${stats['date_range']['latest']}',
      );
    }

    final categories = stats['categories'] as Map<String, int>;
    if (categories.isNotEmpty) {
      debugPrint(
        '  Categories: ${categories.entries.map((e) => '${e.key}(${e.value})').join(', ')}',
      );
    }

    final tags = stats['popular_tags'] as Map<String, int>;
    if (tags.isNotEmpty) {
      final topTags =
          tags.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final topTagsStr = topTags
          .take(5)
          .map((e) => '${e.key}(${e.value})')
          .join(', ');
      debugPrint('  Top tags: $topTagsStr');
    }
  }

  /// Refresh memories from database
  Future<void> refreshMemories() async {
    debugPrint('[MemoryRepository] Refreshing memories...');
    await loadAllMemories();
  }

  /// Clear all cached memories
  void clearMemories() {
    debugPrint('[MemoryRepository] Clearing cached memories');
    allMemories.clear();
    totalMemoriesCount.value = 0;
  }
}
