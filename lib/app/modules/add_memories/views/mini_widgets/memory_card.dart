import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/audio_duration_list.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/image_viewer_screen.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/map_view_widget_new.dart';
import 'package:spacetime/app/modules/memories/views/memory_view.dart';


import '../../../../config/app_images.dart';
import '../../../memories/controllers/memory_controller.dart';
import '../../../ui/controllers/ui_controller.dart';
import '../../controllers/add_memories_controller.dart';
import '../../../filter/controllers/filter_controller.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/l10n/place_category_l10n.dart';

class MemoryCard extends StatefulWidget {
  final Map<String, dynamic> memoryData;

  const MemoryCard({super.key, required this.memoryData});

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
        final stringList =
            value.whereType<String>().where((s) => s.isNotEmpty).toList();
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
        final stringList =
            value.whereType<String>().where((s) => s.isNotEmpty).toList();
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
        final stringList =
            value.whereType<String>().where((s) => s.isNotEmpty).toList();
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
        final stringList =
            value.whereType<String>().where((s) => s.isNotEmpty).toList();
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
        final stringList =
            value.whereType<String>().where((s) => s.isNotEmpty).toList();
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
        if (created == null || created.isAfter(to.add(const Duration(days: 1))))
          return false;
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

  @override
  State<MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<MemoryCard> {
  final PageController _pageController = PageController();
  final controller = Get.find<UiController>();
  int _currentIndex = 0;
  final Map<int, Widget> _imageCache = {};
  final Map<int, VideoPlayerController> _inlineVideoControllers = {};

  @override
  void dispose() {
    _pageController.dispose();
    _imageCache.clear();
    for (final vc in _inlineVideoControllers.values) {
      vc.dispose();
    }
    _inlineVideoControllers.clear();
    super.dispose();
  }

  List<Map<String, dynamic>> _buildOrderedMediaList() {
    // Prefer single list in upload order when provided (same as Memory View)
    final orderedMedia = widget.memoryData['orderedMedia'] as List<dynamic>?;
    if (orderedMedia != null && orderedMedia.isNotEmpty) {
      return orderedMedia
          .map((e) {
            final m = e as Map<String, dynamic>;
            return <String, dynamic>{'type': m['type'], 'path': m['path']};
          })
          .toList();
    }

    final images =
        widget.assetsImg is List
            ? widget.assetsImg as List<String>
            : widget.assetsImg != null
            ? [widget.assetsImg as String]
            : <String>[];
    final videos = widget.videoPaths ?? <String>[];
    final imageOrders = widget.memoryData['imageOrders'] as List<dynamic>?;
    final videoOrders = widget.memoryData['videoOrders'] as List<dynamic>?;

    final List<Map<String, dynamic>> mediaList = [];
    for (int i = 0; i < images.length; i++) {
      mediaList.add({
        'type': 'image',
        'path': images[i],
        'order': (imageOrders != null && i < imageOrders.length) ? imageOrders[i] as int : i,
      });
    }
    for (int i = 0; i < videos.length; i++) {
      mediaList.add({
        'type': 'video',
        'path': videos[i],
        'order': (videoOrders != null && i < videoOrders.length) ? videoOrders[i] as int : images.length + i,
      });
    }
    mediaList.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
    return mediaList;
  }

  Widget _buildImageGallery() {
    final orderedMedia = _buildOrderedMediaList();
    final images =
        widget.assetsImg is List
            ? widget.assetsImg as List<String>
            : widget.assetsImg != null
            ? [widget.assetsImg as String]
            : <String>[];
    final videos = widget.videoPaths ?? <String>[];
    final totalMediaCount = orderedMedia.length;

    if (totalMediaCount == 0) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: Stack(
        children: [
          SizedBox(
            height: 260,
            width: double.infinity,
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) => true,
              child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemCount: totalMediaCount,
              itemBuilder: (context, index) {
                final item = orderedMedia[index];
                final isImage = item['type'] == 'image';
                final path = item['path'] as String;

                if (isImage) {
                  final cached = _imageCache[index];
                  if (cached != null) return cached;
                  final built = GestureDetector(
                    onTap: () {
                      _openMediaViewer(images, videos, index, orderedMedia: orderedMedia);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: ClipRRect(child: _buildImageWidget(path)),
                  );
                  _imageCache[index] = built;
                  return built;
                } else {
                  return _buildInlineVideoPlayer(path, index, images, videos, orderedMedia: orderedMedia);
                }
              },
            ),
          ),
          ),
          if (totalMediaCount > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
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
                                  : Colors.grey.withValues(alpha: 0.8),
                        ),
                      ),
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
      child:
          file.existsSync()
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
      bool isEmojiComponent =
          (rune >= 0x1F300 &&
              rune <= 0x1F9FF) || // Misc symbols, emoticons, etc.
          (rune >= 0x2600 && rune <= 0x26FF) || // Misc symbols
          (rune >= 0x2700 && rune <= 0x27BF); // Dingbats

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
    if (imageData.contains('.png') ||
        imageData.contains('.jpg') ||
        imageData.contains('.jpeg'))
      return false;

    // More robust base64 validation
    try {
      // Try to decode a small portion to validate
      final testData =
          imageData.length > 100 ? imageData.substring(0, 100) : imageData;
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
    if (location.contains('🇦') ||
        location.contains('🇧') ||
        location.contains('🇨') ||
        location.contains('🇩') ||
        location.contains('🇪') ||
        location.contains('🇫') ||
        location.contains('🇬') ||
        location.contains('🇭') ||
        location.contains('🇮') ||
        location.contains('🇯') ||
        location.contains('🇰') ||
        location.contains('🇱') ||
        location.contains('🇲') ||
        location.contains('🇳') ||
        location.contains('🇴') ||
        location.contains('🇵') ||
        location.contains('🇶') ||
        location.contains('🇷') ||
        location.contains('🇸') ||
        location.contains('🇹') ||
        location.contains('🇺') ||
        location.contains('🇻') ||
        location.contains('🇼') ||
        location.contains('🇽') ||
        location.contains('🇾') ||
        location.contains('🇿')) {
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

  String _formatInlineDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _buildInlineVideoPlayer(String videoPath, int index, List<String> images, List<String> videos, {List<Map<String, dynamic>>? orderedMedia}) {
    if (!_inlineVideoControllers.containsKey(index)) {
      final vc = VideoPlayerController.file(File(videoPath));
      _inlineVideoControllers[index] = vc;
      vc.initialize().then((_) {
        if (mounted) {
          vc.addListener(() { if (mounted) setState(() {}); });
          setState(() {});
        }
      });
    }
    final vc = _inlineVideoControllers[index];
    if (vc == null) {
      return Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.white)));
    }
    final initialized = vc.value.isInitialized;

    return Stack(
      alignment: Alignment.center,
      children: [
        initialized
            ? SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: vc.value.size.width,
                    height: vc.value.size.height,
                    child: VideoPlayer(vc),
                  ),
                ),
              )
            : Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.white))),
        if (initialized)
          GestureDetector(
            onTap: () => setState(() { vc.value.isPlaying ? vc.pause() : vc.play(); }),
            child: AnimatedOpacity(
              opacity: vc.value.isPlaying ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
              ),
            ),
          ),
        if (initialized)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VideoProgressIndicator(
                    vc,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: controller.currentMainColor,
                      bufferedColor: Colors.white.withValues(alpha: 0.3),
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() { vc.value.isPlaying ? vc.pause() : vc.play(); }),
                        child: Icon(
                          vc.value.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatInlineDuration(vc.value.position),
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                      Text('text'.tr, style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text(
                        _formatInlineDuration(vc.value.duration),
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () {
                          vc.pause();
                          _openMediaViewer(images, videos, index, orderedMedia: orderedMedia);
                        },
                        child: const Icon(Icons.fullscreen, color: Colors.white, size: 22),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (!initialized)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () {
                _openMediaViewer(images, videos, index, orderedMedia: orderedMedia);
              },
              child: Container(
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                padding: const EdgeInsets.all(6),
                child: const Icon(Icons.fullscreen, color: Colors.white, size: 22),
              ),
            ),
          ),
      ],
    );
  }

  void _openMediaViewer(List<String> images, List<String> videos, int initialIndex, {List<Map<String, dynamic>>? orderedMedia}) {
    try {
      Navigator.of(context)
          .push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) {
                return ImageViewerScreen(
                  images: images,
                  videoPaths: videos,
                  initialIndex: initialIndex,
                  orderedMedia: orderedMedia,
                );
              },
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return child;
              },
            ),
          );
    } catch (e) {
      debugPrint('Exception during navigation: $e');
    }
  }

  // Helper method to check if string is base64
  bool _isBase64String(String str) {
    if (str.length < 100) return false;
    if (str.contains('/') || str.contains('\\')) return false;
    if (str.contains('.png') || str.contains('.jpg') || str.contains('.jpeg'))
      return false;

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
            backgroundColor:
                uiController.darkMode.value
                    ? const Color(0xFF1E1E1E) // Dark mode dialog background
                    : Colors.white, // Light mode dialog background
            surfaceTintColor: Colors.transparent, // Remove surface tint
            shadowColor: Colors.transparent, // Remove shadow tint
          ),
          cardTheme: CardThemeData(
            color:
                uiController.darkMode.value
                    ? const Color(0xFF1E1E1E) // Dark mode card background
                    : Colors.white, // Light mode card background
            surfaceTintColor: Colors.transparent, // Remove surface tint
          ),
          scaffoldBackgroundColor:
              uiController.darkMode.value
                  ? const Color(0xFF1E1E1E) // Dark mode scaffold background
                  : Colors.white, // Light mode scaffold background
        ),
        child: AlertDialog(
          backgroundColor:
              uiController.darkMode.value
                  ? const Color(0xFF1E1E1E) // Dark mode dialog background
                  : Colors.white, // Light mode dialog background
          surfaceTintColor: Colors.transparent, // Remove surface tint
          title: Text(
            'title_text_delete_memory'.tr,
            style: TextStyle(
              color:
                  uiController.darkMode.value
                      ? Colors
                          .white // White text for dark mode
                      : Colors.black, // Black text for light mode
            ),
          ),
          content: Text(
            'dialog_content_are_you_sure_you_want_to_delete_this_memo'.tr,
            style: TextStyle(
              color:
                  uiController.darkMode.value
                      ? Colors
                          .white70 // Light gray text for dark mode
                      : Colors.black87, // Dark gray text for light mode
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: Text(
                'text_cancel'.tr,
                style: TextStyle(
                  color:
                      uiController.darkMode.value
                          ? Colors.grey[400] // Light gray for dark mode
                          : Colors.grey, // Gray for light mode
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                Get.back(); // Close dialog

                try {
                  debugPrint('[MemoryCard] 🗑️ Deleting memory ID: ${widget.id}');

                  final memoryController = Get.find<MemoryController>();
                  await memoryController.deleteMemory(widget.id!);

                  debugPrint('[MemoryCard] ✅ Memory deleted from database');

                  // Reload data from FilterController (single source of truth)
                  if (Get.isRegistered<FilterController>()) {
                    final filterController = Get.find<FilterController>();
                    filterController.resetFilters();
                    filterController.resetFiltersExceptSearch();
                    // await filterController.loadAndApplyFilters();
                    debugPrint('[MemoryCard] 📊 FilterController reloaded: ${filterController.filteredMemories.length} memories');
                  }

                  // Refresh AddMemories view
                  if (Get.isRegistered<AddMemoriesController>()) {
                    final addMemoriesController = Get.find<AddMemoriesController>();
                    await addMemoriesController.loadMemoriesFromDatabase();
                    debugPrint('[MemoryCard] ✅ AddMemories view reloaded');
                  }

                  // Refresh Map view
                  if (Get.isRegistered<MapControllerNew>()) {
                    final mapController = Get.find<MapControllerNew>();
                    final filterController = Get.find<FilterController>();
                    await mapController.loadMemoriesFromDB(filterController.filteredMemories.toList());
                    mapController.showLoadedDataOnMap();
                    debugPrint('[MemoryCard] ✅ Map view reloaded');
                  }

                  showTrSnackbar('snackbar_success_2', 
                    backgroundColor: Colors.red.withValues(alpha: 0.8),
                    colorText: Colors.white,
                    duration: const Duration(seconds: 2),);
                } catch (e) {
                  debugPrint('[MemoryCard] ❌ Error deleting memory: $e');
                  showTrSnackbar('snackbar_error_4', args: [e], 
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                    duration: const Duration(seconds: 2),);
                }
              },
              child: Text(
                'text_delete'.tr,
                style: TextStyle(
                  color:
                      uiController.darkMode.value
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
    return Container(
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
                    Row(
                      children: [
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
                                  getDayOrDate(widget.date, widget.year) !=
                                      'Yesterday')
                              ? widget.year
                              : '',

                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color:
                                controller.darkMode.value
                                    ? Colors.white.withOpacity(0.6)
                                    : controller.currentMainColor.withOpacity(
                                      0.6,
                                    ),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),

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
                          padding: const EdgeInsets.only(right: 8.0),
                          child: GestureDetector(
                            onTap: _handleLongPress,
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Icon(
                                Icons.edit_outlined,
                                color:
                                    controller.darkMode.value
                                        ? Colors.white.withOpacity(0.6)
                                        : controller.currentEditIconColor,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            GestureDetector(
              onTap: () => _handleMemoryTapped(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8.0, 2, 8, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            widget.locationFlag,
                            style: TextStyle(
                              color:
                                  controller.darkMode.value
                                      ? Colors.white
                                      : Colors.black,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              widget.locationString,
                              style: TextStyle(
                                color:
                                    controller.darkMode.value
                                        ? Colors.white
                                        : Colors.black,
                                fontSize: 16,
                              ),
                              maxLines: null,
                              softWrap: true,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (widget.category != null && widget.category!.isNotEmpty)
                      Flexible(
                        child: Text(
                          localizedPlaceCategoryStoredLabel(widget.category!),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color:
                                controller.darkMode.value
                                    ? Colors.white.withValues(alpha: 0.8)
                                    : Colors.grey[700],
                            fontSize: 16,
                          ),
                        ),
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
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            if (widget.assetsImg != null || widget.videoPaths != null)
              _buildImageGallery(),

            // Audio durations - only show if valid audio durations exist
            if (widget.audioDurations != null &&
                widget.audioDurations!.isNotEmpty)
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

  String formatDateString(String dateString, d) {
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
      "Jan": 1,
      "Feb": 2,
      "Mar": 3,
      "Apr": 4,
      "May": 5,
      "Jun": 6,
      "Jul": 7,
      "Aug": 8,
      "Sep": 9,
      "Oct": 10,
      "Nov": 11,
      "Dec": 12,
    };
    return months[month]!;
  }

  Future<void> _handleMemoryTapped() async {
    final memoryIdInt = int.tryParse(widget.memoryData['id'].toString());
    print('Gesture Detected $memoryIdInt');
    if (memoryIdInt != null) {
      final controller = Get.find<AddMemoriesController>();

      controller.applyFilters(memoryIds: [memoryIdInt]);

      final mc = Get.find<MapControllerNew>();
      await mc.loadFilteredMemoriesFromDB();
      mc.handleFilterApplyFromMap(memoryIds: [memoryIdInt]);
      Get.back(result: true);
      debugPrint(
        '[MapControllerNew] 🎯 Applied memory ID filter: $memoryIdInt',
      );
    }
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
          child:
              _hasImage
                  ? LayoutBuilder(
                    builder: (context, constraints) {
                      final dpr = MediaQuery.of(context).devicePixelRatio;
                      final w =
                          (constraints.maxWidth.isFinite
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
            'text_image_failed_to_load'.tr,
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }
}
