import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/audio_duration_list.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/image_viewer_screen.dart';
import 'package:spacetime/app/modules/memories/views/memory_view.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/video_thumbnail_widget.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/video_player_screen.dart';

import '../../../../config/app_images.dart';
import '../../../memories/controllers/memory_controller.dart';
import '../../../ui/controllers/ui_controller.dart';
import '../../controllers/add_memories_controller.dart';

class MemoryCard extends StatefulWidget {
  final Map<String, dynamic> memoryData;

  const MemoryCard({
    super.key,
    required this.memoryData,
  });

  // Getter methods for accessing memory data with safe type casting
  String get date {
    try {
      final value = memoryData['date'];
      final year = memoryData['date'];

     List<String> parts = value.split(" ");
  String day = parts[0].replaceAll('.', ''); // "12"
  String month = parts[1].substring(0, 3); // "Sep"
  String formatted = "$day $month";

      return formatted;
      // return dateData;
    } catch (e) {
      return '';
    }
  }

   // Getter methods for accessing memory data with safe type casting
  String get year {
    try {
      // final value = memoryData['date'];
      final year = memoryData['year'];

      return year;
      // return dateData;
    } catch (e) {
      return '';
    }
  }

  String get location {
    try {
      final value = memoryData['location'].toString();
      print('LOCATION: $value');
      return value;
    } catch (e) {
      return '';
    }
  }

 String get locationString {
    try {
      // final location_country = memoryData['location_country'].toString();
     final location_city = memoryData['location_city'].toString();
       final location_flag = memoryData['location_flag'].toString();
      // print('LOCATION: $value');
      final value = '$location_city';
      return value;
    } catch (e) {
      return location;
    }
  }

String get locationFlag {
    try {
      // final location_country = memoryData['location_country'].toString();
    //  final location_city = memoryData['location_city'].toString();
       final location_flag = memoryData['location_flag'].toString();
      // print('LOCATION: $value');
      final value = '$location_flag ';
      return value;
    } catch (e) {
      return location;
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

  dynamic get assetsImg {
    try {
      final value = memoryData['assetsImg'];
      if (value == null) return null;
      if (value is String && value.isNotEmpty) return value;
      if (value is List && value.isNotEmpty) return value;
      return null;
    } catch (e) {
      return null;
    }
  }

  List<String>? get audioDurations {
    try {
      final value = memoryData['audioDurations'];
      if (value == null) return null;
      if (value is List) {
        final stringList = value.whereType<String>().where((s) => s.isNotEmpty).toList();
        return stringList.isNotEmpty ? stringList : null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

    List<String>? get audioPaths {
    try {
      final value = memoryData['audioPaths'];
      if (value == null) return null;
      if (value is List) {
        final stringList = value.whereType<String>().where((s) => s.isNotEmpty).toList();
        return stringList.isNotEmpty ? stringList : null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  List<String>? get videoPaths {
    try {
      final value = memoryData['videoPaths'];
      if (value == null) return null;
      if (value is List) {
        final stringList = value.whereType<String>().where((s) => s.isNotEmpty).toList();
        return stringList.isNotEmpty ? stringList : null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  List<String>? get videoThumbnails {
    try {
      final value = memoryData['videoThumbnails'];
      if (value == null) return null;
      if (value is List) {
        final stringList = value.whereType<String>().where((s) => s.isNotEmpty).toList();
        return stringList.isNotEmpty ? stringList : null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  List<String>? get videoDurations {
    try {
      final value = memoryData['videoDurations'];
      if (value == null) return null;
      if (value is List) {
        final stringList = value.whereType<String>().where((s) => s.isNotEmpty).toList();
        return stringList.isNotEmpty ? stringList : null;
      }
      return null;
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

   String? get categoryIcon {
    try {
      final value = memoryData['category'];
      if (value is String && value.isNotEmpty) {
        // Extract first emoji properly (emojis can be multiple code units)
        final runes = value.runes.toList();
        if (runes.isEmpty) return null;

        // Get first character/emoji (handles multi-code-unit emojis)
        int endIndex = 1;
        // Check if it's a multi-code-unit emoji (like skin tone modifiers)
        if (runes.length > 1 && runes[1] >= 0x1F3FB && runes[1] <= 0x1F3FF) {
          endIndex = 2; // Include skin tone modifier
        }

        return String.fromCharCodes(runes.take(endIndex));
      }
      return null;
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

  int? get id {
    try {
      final value = memoryData['id'];
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      return null;
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

  // Filter methods
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
    // Filter by date range
    final fromDate = filters['from date'];
    final toDate = filters['to date'];
    if (fromDate != null && fromDate.isNotEmpty) {
      try {
        final from = DateTime.parse(fromDate);
        final created = DateTime.tryParse(createdAt ?? '');
        if (created == null || created.isBefore(from)) return false;
      } catch (e) {
        // Invalid date format, skip filter
      }
    }

    if (toDate != null && toDate.isNotEmpty) {
      try {
        final to = DateTime.parse(toDate);
        final created = DateTime.tryParse(createdAt ?? '');
        if (created == null || created.isAfter(to.add(const Duration(days: 1)))) return false;
      } catch (e) {
        // Invalid date format, skip filter
      }
    }

    // Filter by location
    final locationFilter = filters['location'];
    if (locationFilter != null && locationFilter.isNotEmpty) {
      if (!location.toLowerCase().contains(locationFilter.toLowerCase())) {
        return false;
      }
    }

    // Filter by category
    final categoryFilter = filters['category'];
    if (categoryFilter != null && categoryFilter.isNotEmpty) {
      if (category == null || !category!.toLowerCase().contains(categoryFilter.toLowerCase())) {
        return false;
      }
    }

    // Filter by tags
    final tagsFilter = filters['tags'];
    if (tagsFilter != null && tagsFilter.isNotEmpty) {
      if (tags == null || !tags!.toLowerCase().contains(tagsFilter.toLowerCase())) {
        return false;
      }
    }

    // Filter by mentions
    final mentionsFilter = filters['mentions'];
    if (mentionsFilter != null && mentionsFilter.isNotEmpty) {
      if (mentions == null || !mentions!.toLowerCase().contains(mentionsFilter.toLowerCase())) {
        return false;
      }
    }

    return true;
  }

  @override
  State<MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<MemoryCard> {
  final PageController _pageController = PageController();
  final controller = Get.find<UiController>();
  int _currentIndex = 0;
  final Map<int, Widget> _imageCache = {}; // Cache for built image widgets


  @override
  void dispose() {
    _pageController.dispose();
    _imageCache.clear(); // Clear image cache to free memory
    super.dispose();
  }

  Widget _buildImageGallery() {
    // Combine images and videos into a single media list
    final images = widget.assetsImg is List
        ? widget.assetsImg as List<String>
        : widget.assetsImg != null ? [widget.assetsImg as String] : <String>[];

    final videos = widget.videoPaths ?? <String>[];
    final totalMediaCount = images.length + videos.length;

    debugPrint('🎬 Gallery: ${images.length} images, ${videos.length} videos, total: $totalMediaCount');
    if (videos.isNotEmpty) {
      debugPrint('🎬 Video paths: $videos');
    }

    if (totalMediaCount == 0) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      // height: 300,
      width: double.infinity,
      child: Stack(
        children: [
          SizedBox(
            height: 260,
            width: double.infinity,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemCount: totalMediaCount,
              itemBuilder: (context, index) {
                // Determine if this is an image or video
                final isImage = index < images.length;

                if (isImage) {
                  // Display image
                  // Use cached widget if available, otherwise build and cache
                  if (!_imageCache.containsKey(index)) {
                    _imageCache[index] = GestureDetector(
                      onTap: () {
                        debugPrint('🔥 IMAGE TAP DETECTED! Index: $index');
                        _openImageViewer(images, index);
                      },
                      behavior: HitTestBehavior.opaque,
                      child: ClipRRect(
                        child: _buildImageWidget(images[index]),
                      ),
                    );
                  }
                  return _imageCache[index]!;
                } else {
                  // Display video with play button
                  final videoIndex = index - images.length;
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return VideoThumbnailWidget(
                        videoPath: videos[videoIndex],
                        width: constraints.maxWidth,
                        height: 260,
                        onTap: () {
                          debugPrint('🔥 VIDEO TAP DETECTED! Index: $videoIndex');
                          Get.to(() => VideoPlayerScreen(
                            videoPath: videos[videoIndex],
                          ));
                        },
                      );
                    },
                  );
                }
              },
            ),
          ),
          if (totalMediaCount > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  totalMediaCount,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          _currentIndex == index
                              ? controller.darkMode.value
                                  ? controller.mainColor.value == 'blue'
                                      ? controller.currentMainColor
                                      : controller.primaryColorDark
                                  : controller.mainColor.value == 'blue'
                                  ? Colors.blue
                                  : controller.primaryColor
                              : Colors.grey.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Build image widget that handles both file paths and base64 images
  Widget _buildImageWidget(String imageData) {
    // Check if it's a file path
    if (_isFilePath(imageData)) {
      return _buildFileImage(imageData);
    } else {
      return _buildBase64Image(imageData);
    }
  }

  // Build image from file path (NEW - preserves quality)
  Widget _buildFileImage(String filePath) {
    final file = File(filePath);

    return SizedBox(
      width: double.infinity,
      height: 260,
      child: file.existsSync()
          ? Image.file(
              file,
              fit: BoxFit.cover,
              width: double.infinity,
              height: 260,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Error loading file image: $error');
                return _buildErrorWidget('File not found');
              },
            )
          : _buildErrorWidget('File does not exist'),
    );
  }

  // Build image from base64 (LEGACY - for backward compatibility)
  Widget _buildBase64Image(String base64Data) {
    try {
      final bytes = base64Decode(base64Data);
      return SizedBox(
        width: double.infinity,
        height: 260,
        child: Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 260,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Error loading base64 image: $error');
            return _buildErrorWidget('Image failed to load');
          },
        ),
      );
    } catch (e) {
      debugPrint('Error decoding base64 image: $e');
      return _buildErrorWidget('Invalid image data');
    }
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

  // Build error widget for failed images
  Widget _buildErrorWidget(String message) {
    return Container(
      width: double.infinity,
      height: 260,
      color: Colors.grey[300],
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image, size: 50, color: Colors.grey[600]),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Extract first emoji character properly (handles multi-code-unit emojis)
  String _getFirstEmoji(String text) {
    if (text.isEmpty) return '';
    print('Emojis $text');

    final runes = text.runes.toList();
    if (runes.isEmpty) return '';

    int endIndex = 1;

    // Iterate through runes to find the complete emoji sequence
    for (int i = 1; i < runes.length; i++) {
      final rune = runes[i];

      // Check for skin tone modifiers (🏻-🏿)
      if (rune >= 0x1F3FB && rune <= 0x1F3FF) {
        endIndex = i + 1;
        continue;
      }

      // Check for Variation Selector (VS16) - makes emoji colorful
      if (rune == 0xFE0F) {
        endIndex = i + 1;
        continue;
      }

      // Check for Zero Width Joiner (ZWJ) - used in combined emojis
      if (rune == 0x200D) {
        endIndex = i + 1;
        // After ZWJ, we need to include the next emoji component
        // Continue to next iteration to include it
        continue;
      }

      // Check for Regional Indicator Symbols (flags) - they come in pairs
      if (runes[0] >= 0x1F1E6 && runes[0] <= 0x1F1FF) {
        if (rune >= 0x1F1E6 && rune <= 0x1F1FF) {
          endIndex = i + 1;
          continue;
        }
      }

      // Check if current rune is an emoji component (common emoji ranges)
      bool isEmojiComponent = (rune >= 0x1F300 && rune <= 0x1F9FF) || // Misc symbols, emoticons, etc.
                              (rune >= 0x2600 && rune <= 0x26FF) ||   // Misc symbols
                              (rune >= 0x2700 && rune <= 0x27BF);     // Dingbats

      // If previous was ZWJ and this is emoji component, include it
      if (i > 0 && runes[i - 1] == 0x200D && isEmojiComponent) {
        endIndex = i + 1;
        continue;
      }

      // If we hit a space, stop
      if (rune == 0x20) break; // Space character

      // If it's not an emoji-related character, stop
      if (!isEmojiComponent && rune != 0xFE0F && rune != 0x200D) {
        break;
      }
    }

    final result = String.fromCharCodes(runes.take(endIndex));
    print('Extracted emoji: $result');
    return result;
  }

  // Check if the image data is base64 encoded
  bool _isBase64Image(String imageData) {
    // Base64 strings are typically much longer than asset paths
    // and don't contain file extensions or path separators
    if (imageData.length < 100) return false;
    if (imageData.contains('/') || imageData.contains('\\')) return false;
    if (imageData.contains('.png') || imageData.contains('.jpg') || imageData.contains('.jpeg')) return false;

    // More robust base64 validation
    try {
      // Try to decode a small portion to validate
      final testData = imageData.length > 100 ? imageData.substring(0, 100) : imageData;
      base64Decode(testData);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Format location for display
  String _formatLocationDisplay(String location) {
    if (location.isEmpty) return 'Unknown Location';

    // Check if location already contains enhanced format (flag + city, country)
    // Enhanced format typically starts with flag emoji or contains country names
    if (location.contains('🇦') || location.contains('🇧') || location.contains('🇨') ||
        location.contains('🇩') || location.contains('🇪') || location.contains('🇫') ||
        location.contains('🇬') || location.contains('🇭') || location.contains('🇮') ||
        location.contains('🇯') || location.contains('🇰') || location.contains('🇱') ||
        location.contains('🇲') || location.contains('🇳') || location.contains('🇴') ||
        location.contains('🇵') || location.contains('🇶') || location.contains('🇷') ||
        location.contains('🇸') || location.contains('🇹') || location.contains('🇺') ||
        location.contains('🇻') || location.contains('🇼') || location.contains('🇽') ||
        location.contains('🇾') || location.contains('🇿')) {
      // Already enhanced format, return as is
      return location;
    }

    // Check if location contains coordinates (lat,lng format)
    final coordPattern = RegExp(r'^(-?\d+\.?\d*),(-?\d+\.?\d*)$');
    final match = coordPattern.firstMatch(location.trim());

    if (match != null) {
      try {
        final lat = double.parse(match.group(1)!);
        final lng = double.parse(match.group(2)!);

        // Format coordinates nicely with 4 decimal places
        return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
      } catch (e) {
        return location; // Return original if parsing fails
      }
    }

    return location; // Return original if not coordinates
  }

  void _openImageViewer(List<String> images, int initialIndex) {
    debugPrint('=== IMAGE VIEWER DEBUG ===');
    debugPrint('Opening image viewer with ${images.length} images');
    debugPrint('Initial index: $initialIndex');

    for (int i = 0; i < images.length; i++) {
      final image = images[i];
      debugPrint('Image $i: ${image.length} characters');
      debugPrint('Image $i starts with: ${image.substring(0, math.min(50, image.length))}');
      debugPrint('Image $i is base64: ${_isBase64String(image)}');
    }
    debugPrint('========================');

    try {
      debugPrint('🚀 Attempting to navigate to ImageViewerScreen...');

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) {
            debugPrint('🏗️ Building ImageViewerScreen...');
            return ImageViewerScreen(images: images, initialIndex: initialIndex);
          },
        ),
      ).then((result) {
        debugPrint('✅ Navigation completed, result: $result');
      }).catchError((error) {
        debugPrint('❌ Navigation error: $error');
      });

      debugPrint('📱 Navigation call completed');
    } catch (e) {
      debugPrint('💥 Exception during navigation: $e');

      // Fallback: Show a simple dialog to test if the issue is with ImageViewerScreen
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Image Viewer'),
          content: Text('Would open image viewer with ${images.length} images at index $initialIndex'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // Helper method to check if string is base64
  bool _isBase64String(String str) {
    if (str.length < 100) return false;
    if (str.contains('/') || str.contains('\\')) return false;
    if (str.contains('.png') || str.contains('.jpg') || str.contains('.jpeg')) return false;

    try {
      final testData = str.length > 100 ? str.substring(0, 100) : str;
      base64Decode(testData);
      return true;
    } catch (e) {
      return false;
    }
  }

  // Handle long press to edit memory
  void _handleLongPress() {
    debugPrint('Long press detected on memory card');

                  _editMemory();
return;
    // Show edit options
   
  }

  // Edit memory functionality
  void _editMemory() {
    debugPrint('Editing memory with ID: ${widget.id}');
    debugPrint('Memory data being passed: ${widget.memoryData}');

    // Log image data specifically
    final images = widget.memoryData['base64Images'] as List<String>?;
    debugPrint('Images found for editing: ${images?.length ?? 0}');

    // Navigate to memory creation page in edit mode
    Get.put(MemoryController());
    Get.to(() => MemoryView(editMode: true, memoryData: widget.memoryData));
  }

  // Delete memory functionality
  void _deleteMemory() {
    debugPrint('Deleting memory with ID: ${widget.id}');

    // Show confirmation dialog
    final uiController = Get.find<UiController>();
    Get.dialog(
      Theme(
        data: ThemeData(
          useMaterial3: true,
          dialogTheme: DialogThemeData(
            backgroundColor: uiController.darkMode.value
                ? const Color(0xFF1E1E1E) // Dark mode dialog background
                : Colors.white, // Light mode dialog background
            surfaceTintColor: Colors.transparent, // Remove surface tint
            shadowColor: Colors.transparent, // Remove shadow tint
          ),
          cardTheme: CardThemeData(
            color: uiController.darkMode.value
                ? const Color(0xFF1E1E1E) // Dark mode card background
                : Colors.white, // Light mode card background
            surfaceTintColor: Colors.transparent, // Remove surface tint
          ),
          scaffoldBackgroundColor: uiController.darkMode.value
              ? const Color(0xFF1E1E1E) // Dark mode scaffold background
              : Colors.white, // Light mode scaffold background
        ),
        child: AlertDialog(
          backgroundColor: uiController.darkMode.value
              ? const Color(0xFF1E1E1E) // Dark mode dialog background
              : Colors.white, // Light mode dialog background
          surfaceTintColor: Colors.transparent, // Remove surface tint
          title: Text(
            'Delete Memory',
            style: TextStyle(
              color: uiController.darkMode.value
                  ? Colors.white // White text for dark mode
                  : Colors.black, // Black text for light mode
            ),
          ),
          content: Text(
            'Are you sure you want to delete this memory? This action cannot be undone.',
            style: TextStyle(
              color: uiController.darkMode.value
                  ? Colors.white70 // Light gray text for dark mode
                  : Colors.black87, // Dark gray text for light mode
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: uiController.darkMode.value
                      ? Colors.grey[400] // Light gray for dark mode
                      : Colors.grey, // Gray for light mode
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
              Get.back(); // Close dialog

              try {
                final memoryController = Get.find<MemoryController>();
                await memoryController.deleteMemory(widget.id!);

                // Refresh the memories list
                final addMemoriesController = Get.find<AddMemoriesController>();
                addMemoriesController.onAgainInit();

                Get.snackbar(
                  'Success',
                  'Memory deleted successfully',
                  backgroundColor: Colors.red.withValues(alpha: 0.8),
                  colorText: Colors.white,
                          duration: const Duration(seconds: 2),

                );
              } catch (e) {
                Get.snackbar(
                  'Error',
                  'Failed to delete memory: $e',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                          duration: const Duration(seconds: 2),

                );
              }
            },
            child: Text(
              'Delete',
              style: TextStyle(
                color: uiController.darkMode.value
                    ? Colors.red[300] // Lighter red for dark mode
                    : Colors.red, // Standard red for light mode
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    debugPrint('Memory Data: ${widget.memoryData}');
    return  Container(
                                  color: (!controller.darkMode.value ? Colors.white : Colors.transparent),

      child: GestureDetector(
          onLongPress: () => _handleLongPress(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image gallery - only show if valid images exist
            
              // Date container - only show if date is not empty
              if (widget.date.isNotEmpty)
                Container(
                  width: double.infinity,
                  height: 36,
                  decoration: BoxDecoration(
                    color:
                        controller.darkMode.value
                            ? controller.mainColor.value == 'blue'
                                ? Color(0xFF002E68)
                                : controller.primaryColor
                            : controller.secondaryColor ??
                                const Color(0xFFDEEDFF),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       if (widget.time.isNotEmpty)
                                Row(
                                  children: [
                                   
                                    Text(
                                      ' ${widget.time}',
                                      style: TextStyle(
                                        fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        color:
                                            controller.darkMode.value
                                                ? Colors.white
                                                : controller.currentMainColor,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(children: [
                                           
                     Text(
                    '${getDayOrDate(widget.date, widget.year)} ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                                        fontSize: 16,
                      color:
                          controller.darkMode.value
                              ? Colors.white
                              : controller.currentMainColor,
                    ),
                  ),
      
      
                   Text(
      (getDayOrDate(widget.date, widget.year) != 'Today' &&
       getDayOrDate(widget.date, widget.year) != 'Yesterday') ?
                    widget.year :'', 
                    
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color:
                          controller.darkMode.value
                              ? Colors.white.withOpacity(0.6)
                              : controller.currentMainColor.withOpacity(0.6),
                                                  fontSize: 16,
      
                    ),
                  ),
      
                                ],),
                            
                  // 3-dots menu icon with proper theming
                  Row(
                    children: [
                        // const SizedBox(width: 3),
                                    Text(
                                      ' ${widget.time.substring(3)}',
                                      style: TextStyle(
                                        fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        color:
                                            controller.darkMode.value
                                                ? Colors.white.withAlpha(0)
                                                : controller.currentMainColor.withAlpha(0),
                                      ),
                                    ),
                                  // ],
                                  Padding(
                                    padding: const EdgeInsets.only(right: 16.0),
                                    child: GestureDetector(
                                      onTap: _handleLongPress, child: Icon(
                                                              Icons.edit_outlined ,
                                                              color: controller.darkMode.value
                                                                  ? Colors.white.withOpacity(0.6)
                                                                  : controller.currentEditIconColor,
                                                              size: 20,
                                                            ),
                                    ),
                                  ),
                                  
                      
                    ],
                  ),
                  ],)
                ),
          
          
      
      
             Container(
               child: Padding(
                 padding: const EdgeInsets.fromLTRB(8.0,2,8,4),
                 child: Row(
                  // crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                                  Row(
                                    children: [
                                     Text(
                                       widget.locationFlag,
                                        style: TextStyle(
                                          color: controller.darkMode.value
                                              ? Colors.white
                                              : Colors.black,
                                              fontSize: 22
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                       widget.locationString,
                                        style: TextStyle(
                                          color: controller.darkMode.value
                                              ? Colors.white
                                              : Colors.black,
                                              fontSize: 16
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                    
                        // Category - only show if category exists
                         
                         
                             Row(
                     children: [
               
                       Text(
                         widget.category.toString().split(' ').first,
                         style: TextStyle(
                           color: controller.darkMode.value
                               ? Colors.white.withValues(alpha: 0.8)
                               : Colors.grey[700],
                           fontSize:22,
                         ),
                       ),
                       const SizedBox(width: 3), 
                       Text( 

                        
                         widget.category!.replaceAll(widget.category.toString().split(' ').first, ''),
                         style: TextStyle(
                           color: controller.darkMode.value
                               ? Colors.white.withValues(alpha: 0.8)
                               : Colors.grey[700],
                           fontSize: 16,
                         ),
                       ),
                     ],
                   ),
                  ],
                 ),
               ),
             ),
      
              // if (widget.category != null && widget.category!.isNotEmpty)
              //  Padding(
              //    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              //    child: 
              //  ),
      
                       // ],
                        // ),
              //         ),
              //         // Text content - only show if text exists and is not empty
                      if (widget.text != null && widget.text!.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: RichText(
                            text: TextSpan(
                              children: _buildStyledText(widget.text!),
                              style: TextStyle(
                                color:
                                    controller.darkMode.value
                                        ? Colors.white
                                        : Colors.black,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
              //       ],
              //     ),
              //   ),
              // ),
           if (widget.assetsImg != null || widget.videoPaths != null) _buildImageGallery(),
      
              // Audio durations - only show if valid audio durations exist
              if (widget.audioDurations != null && widget.audioDurations!.isNotEmpty)
                AudioDurationList(
                  durations: widget.audioDurations!,
                  audioPaths: widget.audioPaths,
                  onLongPress: _handleLongPress,
                ),
          
            ],
          ),
        ),
    );
  }

  /// Helper method to style text with color
  List<TextSpan> _buildStyledText(String text) {
    final words = text.split(' ');
    return words.map((word) {
      if (word.startsWith('@')) {
        return TextSpan(
          text: '$word ',
          style: const TextStyle(color: Colors.blue),
        );
      } else if (word.startsWith('#')) {
        return TextSpan(
          text: '$word ',
          style: const TextStyle(color: Colors.green),
        );
      } else {
        return TextSpan(text: '$word ');
      }
    }).toList();
  }
  
  getDayOrDate(String date, year) {
    String d = '$date $year';
    print('Date Time $d');

    return formatDateString(d, date);
    // return date;
  }

String formatDateString(String dateString, d,) {
  final date = _parseDate(dateString);
  final now = DateTime.now();

  final today = DateTime(now.year, now.month, now.day);
  final input = DateTime(date.year, date.month, date.day);

  if (input == today) {
    return "Today";
  }
  if (input == today.subtract(const Duration(days: 1))) {
    return "Yesterday";
  }

  return d; // Return original format
}

DateTime _parseDate(String dateString) {
  final parts = dateString.split(" ");
  final day = int.parse(parts[0]);
  final month = _monthNumber(parts[1]);
  final year = int.parse(parts[2]);

  return DateTime(year, month, day);
}

int _monthNumber(String month) {
  const months = {
    "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
    "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
  };
  return months[month]!;
}
  
}



class SafeMemoryImage extends StatelessWidget {
  const SafeMemoryImage({
    super.key,
    required this.bytes,
    this.height = 260,
    this.borderRadius = 0,
    this.semanticLabel,
  });

  final Uint8List bytes;
  final double height;
  final double borderRadius;
  final String? semanticLabel;

  bool get _hasImage => bytes.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    // Fixed height like your original, width expands to parent.
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: ColoredBox(
          color: Colors.grey[200]!, // background while decoding
          child: _hasImage
              ? LayoutBuilder(
                  builder: (context, constraints) {
                    final dpr = MediaQuery.of(context).devicePixelRatio;
                    final w = (constraints.maxWidth.isFinite
                            ? constraints.maxWidth
                            : MediaQuery.of(context).size.width) *
                        dpr;
                    final h = height * dpr;

                    // Cap cache size to keep memory in check.
                    final cacheWidth = w.clamp(200, 800).round();
                    final cacheHeight = h.clamp(150, 600).round();

                    return Image.memory(
                      bytes,
                      fit: BoxFit.fitWidth,
                      semanticLabel: semanticLabel,
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint('Error loading memory image: $error');
                        return _fallback();
                      },
                    );
                  },
                )
              : _fallback(),
        ),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image, size: 44, color: Colors.grey[600]),
          const SizedBox(height: 8),
          Text(
            'Image failed to load',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }
}
