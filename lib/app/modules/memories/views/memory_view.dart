import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/memory_audio_widget.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/memory_description_field_widget.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/memory_info_widget.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/video_thumbnail_widget.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/video_player_screen.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/media_picker_popup.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/shared/widgets/tick_cross_action_button.dart';

import '../controllers/memory_controller.dart';
import '../../add_memories/controllers/add_memories_controller.dart';
import '../../filter/controllers/filter_controller.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/l10n/place_category_l10n.dart';

class MemoryView extends StatefulWidget {
  final bool editMode;
  final Map<String, dynamic>? memoryData;

  const MemoryView({super.key, this.editMode = false, this.memoryData});

  @override
  State<MemoryView> createState() => _MemoryViewState();
}

class _MemoryViewState extends State<MemoryView> {
  final TextEditingController _descriptionController = TextEditingController();
  final GlobalKey<MemoryDescriptionFieldState> _descriptionFieldKey =
      GlobalKey<MemoryDescriptionFieldState>();
  final ScrollController _scrollController = ScrollController();
  bool _isPopupOpen = false;
  final RxList<Map<String, dynamic>> _orderedMedia = <Map<String, dynamic>>[].obs;
  int? _editingMemoryId;

  final RxBool _isKeyboardVisible = false.obs;

  List<Map<String, dynamic>> _originalImages = [];
  List<Map<String, dynamic>> _originalVideos = [];
  List<Map<String, dynamic>> _originalAudios = [];

  Set<int> _deletedImageIndices = <int>{};
  Set<int> _deletedVideoIndices = <int>{};
  Set<int> _deletedAudioIndices = <int>{};

  List<String> get _selectedImagePaths =>
      _orderedMedia.where((m) => m['type'] == 'image').map((m) => m['path'] as String).toList();

  List<String> get _selectedVideoPaths =>
      _orderedMedia.where((m) => m['type'] == 'video').map((m) => m['path'] as String).toList();

  final List<String> _existingTags = [
    'travel',
    'food',
    'nature',
    'photography',
    'adventure',
    'memories',
  ];

  final List<String> _existingMentions = [
    'john_doe',
    'jane_smith',
    'new_york',
    'paris',
    'london',
    'tokyo',
  ];

  @override
  void initState() {
    super.initState();
    // print('Init State Called:');
    final memoryController = Get.find<MemoryController>();
    memoryController.setTime(TimeOfDay.now());

    memoryController.setDate(DateTime.now());
    memoryController.ifCalledFromMemoryView = true;
    // Clear any existing audio and image data first
    try {
      memoryController.clearAudioRecordings();
    } catch (e) {
      debugPrint('Error clearing audio on init: $e');
    }

    // Load draft for new memories (not in edit mode)
    if (!widget.editMode && widget.memoryData == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _loadDraft();

        // Draft reopen might race with an in-flight GPS fetch from MemoryController.
        // Invalidate it so it cannot override the restored location.
        memoryController.invalidateLocationFetch();

        // If draft already has enhanced location fields, do NOT geocode again.
        final hasEnhancedLocation =
            memoryController.locationFlag.value.isNotEmpty ||
            memoryController.locationCountry.value.isNotEmpty ||
            memoryController.locationCity.value.isNotEmpty ||
            memoryController.locationName.value.isNotEmpty;

        if (hasEnhancedLocation) {
          return;
        }

        // Backward-compat: if only coordinates exist, rebuild enhanced fields once.
        if (memoryController.selectedLocation.value.isNotEmpty) {
          await memoryController.fetchEnhancedLocationFromSelectedLocation();
        } else {
          await memoryController.fetchCurrentLocation();
        }
      });

      // Add auto-save listener to description controller
      _descriptionController.addListener(() {
        debugPrint(
          '📝 Description changed: "${_descriptionController.text}" - calling _saveDraft()',
        );
        // _saveDraft();
      });
    }

    _orderedMedia.clear();
    debugPrint('Media data cleared on init');

    // Initialize edit mode if editing existing memory
    if (widget.editMode && widget.memoryData != null) {
      // Add a small delay to ensure UI is ready
      Future.delayed(const Duration(milliseconds: 100), () {
        _initializeEditMode();
      });
    }
  }

  void _initializeEditMode() async {
    final memoryData = widget.memoryData!;
    _editingMemoryId = memoryData['id'];
    // text
    debugPrint('Initializing edit mode for memory ID: $_editingMemoryId');
    debugPrint('Memory data: ${memoryData.toString()}');

    _orderedMedia.clear();
    _originalImages.clear();
    _originalVideos.clear();
    _originalAudios.clear();
    _deletedImageIndices.clear();
    _deletedVideoIndices.clear();
    _deletedAudioIndices.clear();

    // Load original images, videos, and audio data from database for tracking
    if (_editingMemoryId != null) {
      final databaseHelper = DatabaseHelper.instance;
      _originalImages = await databaseHelper.getMemoryImagesWithOrder(
        _editingMemoryId!,
      );
      _originalVideos = await databaseHelper.getMemoryVideosWithOrder(
        _editingMemoryId!,
      );
      _originalAudios = await databaseHelper.getMemoryAudiosWithOrder(
        _editingMemoryId!,
      );
      debugPrint(
        'Loaded ${_originalImages.length} original images, ${_originalVideos.length} original videos, and ${_originalAudios.length} original audios from database',
      );
    }

    // Debug: Print all memory data to see what we're getting
    debugPrint('=== MEMORY DATA DEBUG ===');
    debugPrint('All memory data keys: ${memoryData.keys.toList()}');
    memoryData.forEach((key, value) {
      debugPrint('$key: $value (${value.runtimeType})');
    });
    debugPrint('========================');

    // Set description with tags and mentions
    final description = memoryData['text'] ?? '';
    final tagsString = memoryData['tags'] as String?;
    final mentionsString = memoryData['mentions'] as String?;

    debugPrint('Raw description: "$description"');
    debugPrint('Raw tags: "$tagsString"');
    debugPrint('Raw mentions: "$mentionsString"');

    // Reconstruct the full description text with tags and mentions
    String fullDescription = description;

    // Add tags if they exist
    if (tagsString != null && tagsString.isNotEmpty) {
      final tags =
          tagsString.split(',').where((tag) => tag.trim().isNotEmpty).toList();
      debugPrint('Parsed tags: $tags');
      for (final tag in tags) {
        if (!fullDescription.contains('#${tag.trim()}')) {
          fullDescription += ' #${tag.trim()}';
        }
      }
    }

    // Add mentions if they exist
    if (mentionsString != null && mentionsString.isNotEmpty) {
      final mentions =
          mentionsString
              .split(',')
              .where((mention) => mention.trim().isNotEmpty)
              .toList();
      debugPrint('Parsed mentions: $mentions');
      for (final mention in mentions) {
        if (!fullDescription.contains('@${mention.trim()}')) {
          fullDescription += ' @${mention.trim()}';
        }
      }
    }

    debugPrint('Final description before setting: "$fullDescription"');

    // Set the controller text
    _descriptionController.text = fullDescription.trim();

    // ✅ IMPORTANT: Initialize the tags and mentions in the description field widget
    // This ensures they are recognized as valid and displayed with correct colors
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_descriptionFieldKey.currentState != null) {
        // Parse and add existing tags to the widget state
        if (tagsString != null && tagsString.isNotEmpty) {
          final tags = tagsString
              .split(',')
              .where((tag) => tag.trim().isNotEmpty)
              .map((tag) => tag.trim())
              .toList();
          _descriptionFieldKey.currentState!.initializeTags(tags);
          debugPrint('Initialized ${tags.length} tags in description field');
        }

        // Parse and add existing mentions to the widget state
        if (mentionsString != null && mentionsString.isNotEmpty) {
          final mentions = mentionsString
              .split(',')
              .where((mention) => mention.trim().isNotEmpty)
              .map((mention) => mention.trim())
              .toList();
          _descriptionFieldKey.currentState!.initializeMentions(mentions);
          debugPrint(
            'Initialized ${mentions.length} mentions in description field',
          );
        }
      }
    });

    debugPrint(
      'Controller text after setting: "${_descriptionController.text}"',
    );
    debugPrint('Controller text length: ${_descriptionController.text.length}');
    debugPrint(
      'Controller text isEmpty: ${_descriptionController.text.isEmpty}',
    );

    debugPrint(
      'Description loaded for editing: "${_descriptionController.text}"',
    );

    // Set images if available - convert base64 to temporary files for editing
    final images = memoryData['base64Images'] as List<String>?;
    debugPrint('Found ${images?.length ?? 0} images for editing');
    if (images != null && images.isNotEmpty) {
      _loadExistingImagesForEdit(images);
    }

    // Load existing audio files for editing
    final audioPaths = memoryData['audioPaths'] as List<String>?;
    final audioDurations = memoryData['audioDurations'] as List<String>?;
    debugPrint('Found ${audioPaths?.length ?? 0} audio files for editing');
    if (audioPaths != null && audioPaths.isNotEmpty) {
      _loadExistingAudiosForEdit(audioPaths, audioDurations);
    }

    // Load existing video files for editing
    final videoPaths = memoryData['videoPaths'] as List<String>?;
    debugPrint('Found ${videoPaths?.length ?? 0} video files for editing');
    if (videoPaths != null && videoPaths.isNotEmpty) {
      _loadExistingVideosForEdit(videoPaths);
    }

    // Initialize memory controller with existing data
    final memoryController = Get.find<MemoryController>();

    // Set date and time
    if (memoryData['created_at'] != null) {
      try {
        final createdAt = DateTime.parse(memoryData['created_at']);
        memoryController.selectedDate.value = createdAt;
        memoryController.selectedTime.value = TimeOfDay.fromDateTime(createdAt);
        debugPrint(
          'Loaded date/time for editing: ${createdAt.toIso8601String()}',
        );
        debugPrint(
          'Set controller date: ${memoryController.selectedDate.value}',
        );
        debugPrint(
          'Set controller time: ${memoryController.selectedTime.value}',
        );
      } catch (e) {
        debugPrint('Error parsing created_at: $e');
      }
    } else {
      debugPrint('No created_at found in memory data, using current date/time');
    }

    // Load enhanced location data from memory
    memoryController.loadEnhancedLocationFromMemory(memoryData);

    // Set category
    memoryController.selectedCategory.value = memoryData['category'] ?? '';

    debugPrint('Edit mode initialized for memory ID: $_editingMemoryId');
  }

  Future<void> _deleteMediaAtIndex(int index) async {
    try {
      final item = _orderedMedia[index];
      final type = item['type'] as String;

      if (widget.editMode && _editingMemoryId != null && item['originalIndex'] != null) {
        final origIdx = item['originalIndex'] as int;
        if (type == 'image') {
          _deletedImageIndices.add(origIdx);
        } else {
          _deletedVideoIndices.add(origIdx);
        }
        debugPrint('Marked $type at original index $origIdx for deletion');
      }

      _orderedMedia.removeAt(index);
      _orderedMedia.refresh();
      debugPrint('Media deleted. Remaining: ${_orderedMedia.length}');
    } catch (e) {
      debugPrint('Error deleting media: $e');
    }
  }

  // Delete audio at specific index, handling both edit mode and new memory mode
  Future<void> _deleteAudioAtIndex(int index) async {
    try {
      final memoryController = Get.find<MemoryController>();

      // If in edit mode, mark the audio for deletion (file will be deleted on save)
      if (widget.editMode && _editingMemoryId != null) {
        // Mark this index as deleted (using the original index before any UI changes)
        _deletedAudioIndices.add(index);
        debugPrint('Marked audio at index $index for deletion in edit mode');
        // Note: File deletion and database update will happen when save button is pressed

        // Only remove from UI lists, don't delete the file yet
        if (index < memoryController.recordedAudioPaths.length) {
          memoryController.recordedAudioPaths.removeAt(index);
        }
        if (index < memoryController.recordedAudios.length) {
          memoryController.recordedAudios.removeAt(index);
        }

        // Force UI update
        memoryController.recordedAudios.refresh();
        memoryController.recordedAudioPaths.refresh();
      } else {
        // For new memories (not in edit mode), delete immediately
        memoryController.removeAudio(index);
      }

      debugPrint(
        'Audio removed from UI. Remaining: ${memoryController.recordedAudios.length}',
      );
    } catch (e) {
      debugPrint('Error deleting audio: $e');
      showTrSnackbar('snackbar_unable_to_delete_9', 
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),        duration: const Duration(seconds: 2),);
    }
  }

  // Load existing images for editing by converting base64 to temporary files or using file paths
  Future<void> _loadExistingImagesForEdit(List<String> base64Images) async {
    try {
      debugPrint('Starting to load ${base64Images.length} images for editing');

      final memoryController = Get.find<MemoryController>();
      final tempDir = await getTemporaryDirectory();

      final editSessionDir = Directory(
        '${tempDir.path}/edit_session_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!await editSessionDir.exists()) {
        await editSessionDir.create(recursive: true);
      }

      for (int i = 0; i < base64Images.length; i++) {
        final imageData = base64Images[i];

        try {
          String path;
          if (imageData.startsWith('memory_images/') || imageData.startsWith('/')) {
            path = await memoryController.getAbsolutePath(imageData);
          } else {
            final bytes = base64Decode(imageData);
            final tempFile = File(
              '${editSessionDir.path}/edit_image_${_editingMemoryId}_$i.png',
            );
            await tempFile.writeAsBytes(bytes);
            path = tempFile.path;
          }
          final imgOrder = _originalImages.isNotEmpty && i < _originalImages.length
              ? (_originalImages[i]['image_order'] as int? ?? i)
              : i;
          _orderedMedia.add({'type': 'image', 'path': path, 'originalIndex': i, 'order': imgOrder});
        } catch (e) {
          debugPrint('Error processing image $i: $e');
        }
      }

      debugPrint('Loaded ${base64Images.length} existing images for editing');
    } catch (e) {
      debugPrint('Error loading existing images for edit: $e');
    }
  }

  // Load existing audio files for editing
  Future<void> _loadExistingAudiosForEdit(
    List<String> audioPaths,
    List<String>? audioDurations,
  ) async {
    try {
      final memoryController = Get.find<MemoryController>();

      // Load existing audio paths and durations into the controller
      memoryController.recordedAudioPaths.clear();
      memoryController.recordedAudios.clear();

      for (int i = 0; i < audioPaths.length; i++) {
        // Convert relative path to absolute path
        final absolutePath = await memoryController.getAbsolutePath(audioPaths[i]);
        memoryController.recordedAudioPaths.add(absolutePath);
        debugPrint('🎵 Loaded audio: ${audioPaths[i]} -> $absolutePath');

        // Use provided duration or default
        final duration =
            (audioDurations != null && i < audioDurations.length)
                ? audioDurations[i]
                : '0:30';
        memoryController.recordedAudios.add(duration);
      }

      debugPrint(
        'Loaded ${audioPaths.length} existing audio files for editing',
      );
    } catch (e) {
      debugPrint('Error loading existing audio files for edit: $e');
    }
  }

  Future<void> _loadExistingVideosForEdit(List<String> videoPaths) async {
    try {
      final memoryController = Get.find<MemoryController>();

      for (int i = 0; i < videoPaths.length; i++) {
        final absolutePath = await memoryController.getAbsolutePath(videoPaths[i]);
        final vidOrder = _originalVideos.isNotEmpty && i < _originalVideos.length
            ? (_originalVideos[i]['video_order'] as int? ?? i)
            : i;
        _orderedMedia.add({'type': 'video', 'path': absolutePath, 'originalIndex': i, 'order': vidOrder});
      }

      _orderedMedia.sort((a, b) => (a['order'] as int? ?? 0).compareTo(b['order'] as int? ?? 0));
      _orderedMedia.refresh();

      debugPrint('Loaded ${videoPaths.length} existing videos for editing');
    } catch (e) {
      debugPrint('Error loading existing video files for edit: $e');
    }
  }

  Future<void> _updateMemoryImages(int memoryId) async {
    try {
      final memoryController = Get.find<MemoryController>();
      final databaseHelper = DatabaseHelper.instance;

      await databaseHelper.deleteMemoryImages(memoryId);

      final originalBase64Images =
          widget.memoryData?['base64Images'] as List<String>? ?? [];

      final List<String> finalBase64Images = [];
      final List<int> finalOrders = [];

      final imageItems = _orderedMedia.where((m) => m['type'] == 'image').toList();

      for (int i = 0; i < imageItems.length; i++) {
        final item = imageItems[i];
        final globalOrder = _orderedMedia.indexOf(item);
        final origIdx = item['originalIndex'] as int?;

        if (origIdx != null && origIdx < originalBase64Images.length) {
          finalBase64Images.add(originalBase64Images[origIdx]);
          finalOrders.add(globalOrder);
        } else {
          final path = item['path'] as String;
          final base64List = await memoryController.convertImagesToBase64([path]);
          if (base64List.isNotEmpty) {
            finalBase64Images.add(base64List.first);
            finalOrders.add(globalOrder);
          }
        }
      }

      for (int i = 0; i < finalBase64Images.length; i++) {
        await databaseHelper.insertMemoryImage(
          memoryId,
          finalBase64Images[i],
          finalOrders[i],
        );
      }

      debugPrint('Updated ${finalBase64Images.length} images for memory $memoryId');
    } catch (e) {
      debugPrint('Error updating memory images: $e');
      throw e;
    }
  }

  // Update memory audio files when editing
  Future<void> _updateMemoryAudios(int memoryId) async {
    try {
      final memoryController = Get.find<MemoryController>();
      final databaseHelper = DatabaseHelper.instance;

      // Delete existing audio files for this memory
      await databaseHelper.deleteMemoryAudios(memoryId);

      // Get the original audio data from memory data
      final originalAudioPaths =
          widget.memoryData?['audioPaths'] as List<String>? ?? [];
      final originalAudioDurations =
          widget.memoryData?['audioDurations'] as List<String>? ?? [];

      // Delete the actual audio files that were marked for deletion
      for (int i in _deletedAudioIndices) {
        if (i < originalAudioPaths.length) {
          final filePath = originalAudioPaths[i];
          try {
            final absolutePath = await memoryController.getAbsolutePath(filePath);
            final file = File(absolutePath);
            if (file.existsSync()) {
              file.deleteSync();
              debugPrint('🗑️ Deleted audio file: $absolutePath');
            }
          } catch (e) {
            debugPrint('❌ Error deleting audio file: $e');
          }
        }
      }

      // Create a list of audio files to save (original audios minus deleted ones + new audios)
      final List<String> finalAudioPaths = [];
      final List<String> finalAudioDurations = [];

      // Add original audios that weren't deleted
      for (int i = 0; i < originalAudioPaths.length; i++) {
        if (!_deletedAudioIndices.contains(i)) {
          finalAudioPaths.add(originalAudioPaths[i]);
          finalAudioDurations.add(
            i < originalAudioDurations.length
                ? originalAudioDurations[i]
                : '0:00',
          );
        }
      }

      // Add any new audio files that were added during editing
      // New audios are those in recordedAudioPaths that are beyond the original count
      final originalAudioCount = originalAudioPaths.length;
      final currentRecordedCount = memoryController.recordedAudioPaths.length;
      final originalMinusDeleted =
          originalAudioCount - _deletedAudioIndices.length;

      if (currentRecordedCount > originalMinusDeleted) {
        // There are new audio files
        final newAudiosStartIndex = originalMinusDeleted;
        for (int i = newAudiosStartIndex; i < currentRecordedCount; i++) {
          finalAudioPaths.add(memoryController.recordedAudioPaths[i]);
          finalAudioDurations.add(
            i < memoryController.recordedAudios.length
                ? memoryController.recordedAudios[i]
                : '0:00',
          );
        }
      }

      // Insert all final audio files
      for (int i = 0; i < finalAudioPaths.length; i++) {
        await databaseHelper.insertMemoryAudio(
          memoryId,
          finalAudioPaths[i],
          finalAudioDurations[i],
          i,
        );
      }

      debugPrint(
        'Updated ${finalAudioPaths.length} audio files for memory $memoryId (${_deletedAudioIndices.length} deleted, ${finalAudioPaths.length - originalMinusDeleted} new)',
      );
    } catch (e) {
      debugPrint('Error updating memory audio files: $e');
      throw e;
    }
  }

  Future<void> _updateMemoryVideos(int memoryId) async {
    try {
      final memoryController = Get.find<MemoryController>();
      final databaseHelper = DatabaseHelper.instance;

      await databaseHelper.deleteMemoryVideos(memoryId);

      final originalVideoPaths =
          widget.memoryData?['videoPaths'] as List<String>? ?? [];

      final List<String> finalVideoPaths = [];
      final List<int> finalOrders = [];

      final videoItems = _orderedMedia.where((m) => m['type'] == 'video').toList();

      for (int i = 0; i < videoItems.length; i++) {
        final item = videoItems[i];
        final globalOrder = _orderedMedia.indexOf(item);
        final origIdx = item['originalIndex'] as int?;

        if (origIdx != null && origIdx < originalVideoPaths.length) {
          finalVideoPaths.add(originalVideoPaths[origIdx]);
          finalOrders.add(globalOrder);
        } else {
          final path = item['path'] as String;
          final savedPaths = await memoryController.saveVideosToAppDirectory([path]);
          if (savedPaths.isNotEmpty) {
            finalVideoPaths.add(savedPaths.first);
            finalOrders.add(globalOrder);
          }
        }
      }

      for (int i = 0; i < finalVideoPaths.length; i++) {
        await databaseHelper.insertMemoryVideo(
          memoryId,
          finalVideoPaths[i],
          '',
          '',
          finalOrders[i],
        );
      }

      debugPrint('Updated ${finalVideoPaths.length} videos for memory $memoryId');
    } catch (e) {
      debugPrint('Error updating memory video files: $e');
      throw e;
    }
  }

  Future<void> _sortMediaByCreationDate(List<Map<String, dynamic>> newItems) async {
    final List<MapEntry<Map<String, dynamic>, DateTime>> withDates = [];
    for (final item in newItems) {
      try {
        final file = File(item['path'] as String);
        final stat = await file.stat();
        withDates.add(MapEntry(item, stat.modified));
      } catch (e) {
        withDates.add(MapEntry(item, DateTime.now()));
      }
    }
    withDates.sort((a, b) => a.value.compareTo(b.value));
    for (final entry in withDates) {
      _orderedMedia.add(entry.key);
    }
    _orderedMedia.refresh();
  }

  void _handleImageUpload() async {
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (context) => MediaPickerPopup(
        onMediaSelected: (imagePaths, videoPaths) async {
          final newItems = <Map<String, dynamic>>[];
          for (final p in imagePaths) {
            newItems.add({'type': 'image', 'path': p});
          }
          for (final p in videoPaths) {
            newItems.add({'type': 'video', 'path': p});
          }
          await _sortMediaByCreationDate(newItems);
        },
      ),
    );
  }

  void _handleAudioPlay() {
    // Handle audio playback fu
    // nctionality
    final controller = Get.find<MemoryController>();
    controller.togglePlayPause();
    debugPrint('Audio play/pause toggled');
  }

  void _onTagAdded(String tag) {
    debugPrint('Tag added: $tag');
  }

  void _onMentionAdded(String mention) {
    debugPrint('Mention added: $mention');
  }

  void _onPopupStateChanged(bool isOpen) {
    setState(() {
      _isPopupOpen = isOpen;
    });
  }

  void _handleCancel(
    List<String> recordedAudioPaths,
    List<String> imagePaths,
    List<String> durations,
  ) {
    final memoryController = Get.find<MemoryController>();
    final description = _descriptionController.text;

    // Check if all fields are empty - if so, just go back
    final hasImages = imagePaths.isNotEmpty;
    final hasAudio = recordedAudioPaths.isNotEmpty;
    final hasDurations = durations.isNotEmpty;
    final hasDescription = description.trim().isNotEmpty;
    final hasCategory = memoryController.selectedCategory.value.isNotEmpty;

    if (!hasImages &&
        !hasAudio &&
        !hasDurations &&
        !hasDescription &&
        !hasCategory) {
      debugPrint('All fields are empty, going back without showing dialog');
      if (!widget.editMode) {
        memoryController.clearAllData();
      }
      Get.back();
      return;
    }

    if (widget.memoryData != null && widget.editMode) {
      Get.back();
      return;
    }

    print('_handleCancel imagePaths $imagePaths ');
    print('_handleCancel recordedAudioPaths $recordedAudioPaths ');
    showDialog(
      context: context,
      useRootNavigator: true,
      builder: (BuildContext context) {
        final controller = Get.find<UiController>();
        return Dialog(
          backgroundColor:
              controller.darkMode.value ? Colors.grey[900] : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'text_save_new_memory'.tr,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color:
                        controller.darkMode.value ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (!widget.editMode) {
                          memoryController.clearAllData();
                        }

                        _clearDraft();
                        Navigator.pop(context);
                        Get.back();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color:
                                controller.darkMode.value
                                    ? controller.mainColor.value == 'blue'
                                        ? Colors.red
                                        : Colors.red
                                    : controller.mainColor.value == 'blue'
                                    ? Colors.red
                                    : Colors.red,
                            width: 2, // thickness of the border
                          ),
                        ),
                        child: Text(
                          'text_no'.tr,
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        await _saveDraft(
                          imagePaths,
                          recordedAudioPaths,
                          durations,
                        );

                        Navigator.pop(context);
                        showOverlaySnackText(
                          'dialog_content_draft_saved_successfully'.tr,
                          duration: const Duration(seconds: 2),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color:
                                controller.darkMode.value
                                    ? controller.mainColor.value == 'blue'
                                        ? Colors.grey
                                        : controller.primaryColor!
                                    : controller.mainColor.value == 'blue'
                                    ? Colors.blue
                                    : controller.primaryColor!,
                            width: 2, // thickness of the border
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'text_yes'.tr,
                          style: TextStyle(
                            color:
                                controller.darkMode.value
                                    ? controller.mainColor.value == 'blue'
                                        ? Colors.blue
                                        : controller.primaryColor!
                                    : controller.mainColor.value == 'blue'
                                    ? Colors.blue
                                    : controller.primaryColor!,

                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Unfocus the description field when interacting with other widgets
  void _unfocusDescriptionField() {
    
    print('Unfocuing');
    if (_descriptionFieldKey.currentState != null) {
      _descriptionFieldKey.currentState!.closePopup();
      _descriptionFieldKey.currentState!.preventAutoFocusTemporarily();
    }

    //  _focusNode.unfocus();
      FocusScope.of(context).unfocus();

      // For iOS, sometimes we need to be more aggressive
      if (Theme.of(context).platform == TargetPlatform.iOS) {
        FocusManager.instance.primaryFocus?.unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      }
    
    
    // FocusScope.of(context).unfocus();
  }

  void _handleSave() async {
    try {
      debugPrint('MemoryView: handleSave - Method called');
      final memoryController = Get.find<MemoryController>();
      debugPrint('MemoryView: handleSave - Got MemoryController');

      final description = _descriptionController.text;
      debugPrint('MemoryView: handleSave - Description: ${description.substring(0, description.length > 50 ? 50 : description.length)}...');

      // Get tags and mentions from MemoryDescriptionField
      final tags = _descriptionFieldKey.currentState?.getTags() ?? [];
      final mentions = _descriptionFieldKey.currentState?.getMentions() ?? [];
      debugPrint('MemoryView: handleSave - Tags: $tags, Mentions: $mentions');

      if (widget.editMode && _editingMemoryId != null) {
        debugPrint('MemoryView: handleSave - EDIT MODE - Memory ID: $_editingMemoryId');
        // Update existing memory
        // Get selected date and time from controller
        final selectedDate =
            memoryController.selectedDate.value ?? DateTime.now();
        final selectedTime =
            memoryController.selectedTime.value ?? TimeOfDay.now();
        debugPrint('MemoryView: handleSave - Selected date: $selectedDate, time: $selectedTime');

        // Format date and time the same way as when creating new memories
        debugPrint('MemoryView: handleSave - EDIT MODE - Formatting date and time');
        final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate);
        final timeStr = selectedTime.format(context);
        debugPrint('MemoryView: handleSave - EDIT MODE - Formatted date: $dateStr, time: $timeStr');

        // Combine selected date and time into a single DateTime for created_at
        final selectedDateTime = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          selectedTime.hour,
          selectedTime.minute,
        );
        debugPrint('MemoryView: handleSave - EDIT MODE - Combined DateTime: ${selectedDateTime.toIso8601String()}');

        debugPrint('MemoryView: handleSave - EDIT MODE - Updating memory with date: $dateStr, time: $timeStr');
        debugPrint(
          'MemoryView: handleSave - EDIT MODE - Updating memory with created_at: ${selectedDateTime.toIso8601String()}',
        );
        debugPrint(
          'MemoryView: handleSave - EDIT MODE - Original date from controller: ${memoryController.selectedDate.value}',
        );
        debugPrint(
          'MemoryView: handleSave - EDIT MODE - Original time from controller: ${memoryController.selectedTime.value}',
        );

        // Calculate the final audio paths for the legacy audio_path field
        // Check if audio files were modified (added, deleted, or changed)
        debugPrint('MemoryView: handleSave - EDIT MODE - Checking audio modifications');
        final shouldUpdateAudios =
            memoryController.recordedAudioPaths.isNotEmpty ||
            _deletedAudioIndices.isNotEmpty ||
            _originalAudios.isNotEmpty;
        debugPrint('MemoryView: handleSave - EDIT MODE - Should update audios: $shouldUpdateAudios');
        String? finalAudioPathString;

        if (shouldUpdateAudios) {
          // Get the original audio data from memory data
          final originalAudioPaths =
              widget.memoryData?['audioPaths'] as List<String>? ?? [];

          // Create a list of final audio paths (original minus deleted + new)
          final List<String> finalAudioPaths = [];

          // Add original audios that weren't deleted
          for (int i = 0; i < originalAudioPaths.length; i++) {
            if (!_deletedAudioIndices.contains(i)) {
              finalAudioPaths.add(originalAudioPaths[i]);
            }
          }

          // Add any new audio files that were added during editing
          final originalAudioCount = originalAudioPaths.length;
          final currentRecordedCount =
              memoryController.recordedAudioPaths.length;
          final originalMinusDeleted =
              originalAudioCount - _deletedAudioIndices.length;

          if (currentRecordedCount > originalMinusDeleted) {
            // There are new audio files
            final newAudiosStartIndex = originalMinusDeleted;
            for (int i = newAudiosStartIndex; i < currentRecordedCount; i++) {
              finalAudioPaths.add(memoryController.recordedAudioPaths[i]);
            }
          }

          // Create pipe-separated string for legacy audio_path field
          finalAudioPathString =
              finalAudioPaths.isNotEmpty ? finalAudioPaths.join('|') : null;
          debugPrint('Final audio path string: $finalAudioPathString');
        }

        // Snapshot location before async validation — same race as saveMemory / GPS.
        final saveLocationSnapshot = memoryController.selectedLocation.value;
        final saveLocCountry = memoryController.locationCountry.value;
        final saveLocCity = memoryController.locationCity.value;
        final saveLocName = memoryController.locationName.value;
        final saveLocAddress = memoryController.locationAddress.value;
        final saveLocFlag = memoryController.locationFlag.value;
        final saveLocLat = memoryController.locationLatitude.value;
        final saveLocLng = memoryController.locationLongitude.value;

        // Validation before updating memory
        debugPrint('MemoryView: handleSave - EDIT MODE - Starting validation');
        final validationResult = await _validateMemoryData(
          description,
          tags,
          mentions,
        );
        debugPrint('MemoryView: handleSave - EDIT MODE - Validation result: ${validationResult['isValid']}');
        if (!validationResult['isValid']) {
          debugPrint(
            'MemoryView: handleSave - EDIT MODE - Validation failed: ${validationResult['messageKey']}',
          );
          _showValidationError(validationResult['messageKey'] as String);
          return;
        }

        debugPrint('MemoryView: handleSave - EDIT MODE - Updating memory in database');
        final editUpdate = <String, dynamic>{
          'date': dateStr,
          'time': timeStr,
          'description': description,
          'tags': tags.join(','),
          'mentions': mentions.join(','),
          'category': memoryController.selectedCategory.value,
          'location': saveLocationSnapshot,
        };
        if (saveLocCountry.isNotEmpty) {
          editUpdate[DatabaseHelper.columnLocationCountry] = saveLocCountry;
        }
        if (saveLocCity.isNotEmpty) {
          editUpdate[DatabaseHelper.columnLocationCity] = saveLocCity;
        }
        if (saveLocName.isNotEmpty) {
          editUpdate[DatabaseHelper.columnLocationName] = saveLocName;
        }
        if (saveLocAddress.isNotEmpty) {
          editUpdate[DatabaseHelper.columnLocationAddress] = saveLocAddress;
        }
        if (saveLocFlag.isNotEmpty) {
          editUpdate[DatabaseHelper.columnLocationFlag] = saveLocFlag;
        }
        if (saveLocLat != null) {
          editUpdate[DatabaseHelper.columnLocationLatitude] = saveLocLat;
        }
        if (saveLocLng != null) {
          editUpdate[DatabaseHelper.columnLocationLongitude] = saveLocLng;
        }
        editUpdate['audio_path'] = finalAudioPathString;
        editUpdate['created_at'] = selectedDateTime.toIso8601String();
        editUpdate['updated_at'] = DateTime.now().toIso8601String();
        await memoryController.updateMemory(_editingMemoryId!, editUpdate);
        debugPrint('MemoryView: handleSave - EDIT MODE - Memory updated successfully');

        // Update images if they were modified (added, deleted, or changed)
        final shouldUpdateImages =
            _selectedImagePaths.isNotEmpty ||
            _deletedImageIndices.isNotEmpty ||
            _originalImages.isNotEmpty;
        debugPrint(
          'MemoryView: handleSave - EDIT MODE - Image update check: selectedPaths=${_selectedImagePaths.length}, deletedIndices=${_deletedImageIndices.length}, originalImages=${_originalImages.length}, shouldUpdate=$shouldUpdateImages',
        );
        if (shouldUpdateImages) {
          debugPrint('MemoryView: handleSave - EDIT MODE - Updating images');
          await _updateMemoryImages(_editingMemoryId!);
          debugPrint('MemoryView: handleSave - EDIT MODE - Images updated');
        }

        // Update audio files if they were modified (added, deleted, or changed)
        debugPrint(
          'MemoryView: handleSave - EDIT MODE - Audio update check: recordedPaths=${memoryController.recordedAudioPaths.length}, deletedIndices=${_deletedAudioIndices.length}, originalAudios=${_originalAudios.length}, shouldUpdate=$shouldUpdateAudios',
        );
        if (shouldUpdateAudios) {
          debugPrint('MemoryView: handleSave - EDIT MODE - Updating audios');
          await _updateMemoryAudios(_editingMemoryId!);
          debugPrint('MemoryView: handleSave - EDIT MODE - Audios updated');
        }

        // Update videos if they were modified (added, deleted, or changed)
        final shouldUpdateVideos =
            _selectedVideoPaths.isNotEmpty ||
            _deletedVideoIndices.isNotEmpty ||
            _originalVideos.isNotEmpty;
        debugPrint(
          'MemoryView: handleSave - EDIT MODE - Video update check: selectedPaths=${_selectedVideoPaths.length}, deletedIndices=${_deletedVideoIndices.length}, originalVideos=${_originalVideos.length}, shouldUpdate=$shouldUpdateVideos',
        );
        if (shouldUpdateVideos) {
          debugPrint('MemoryView: handleSave - EDIT MODE - Updating videos');
          await _updateMemoryVideos(_editingMemoryId!);
          debugPrint('MemoryView: handleSave - EDIT MODE - Videos updated');
        }

        // Clear all controller data after successful update
        debugPrint('MemoryView: handleSave - EDIT MODE - Clearing controller data');
        memoryController.clearAllData();
        debugPrint('MemoryView: handleSave - EDIT MODE - Controller data cleared');

        // Clear the description field and selected images
        debugPrint('MemoryView: handleSave - EDIT MODE - Clearing UI fields');
        _descriptionController.clear();
        _orderedMedia.clear();
        _deletedImageIndices.clear();
        _deletedAudioIndices.clear();
        _deletedVideoIndices.clear();
        debugPrint('MemoryView: handleSave - EDIT MODE - UI fields cleared');

        // Reload data from FilterController (single source of truth)
        debugPrint('MemoryView: handleSave - EDIT MODE - Reloading from FilterController');
        if (Get.isRegistered<FilterController>()) {
          final filterController = Get.find<FilterController>();
          filterController.clearFilters();
          filterController.resetFilters();
          filterController.resetFiltersExceptSearch();
          debugPrint('MemoryView: handleSave - EDIT MODE - FilterController reloaded: ${filterController.filteredMemories.length} memories');
        }

        // Refresh AddMemories view
        if (Get.isRegistered<AddMemoriesController>()) {
          final addMemoriesController = Get.find<AddMemoriesController>();
          await addMemoriesController.loadMemoriesFromDatabase();
          debugPrint('MemoryView: handleSave - EDIT MODE - AddMemories view reloaded');
        }

        // Refresh Map view
        if (Get.isRegistered<MapControllerNew>()) {
          final mapController = Get.find<MapControllerNew>();
          final filterController = Get.find<FilterController>();
          await mapController.loadMemoriesFromDB(filterController.filteredMemories.toList());
          mapController.showLoadedDataOnMap();
          debugPrint('MemoryView: handleSave - EDIT MODE - Map view reloaded');
        }

        debugPrint('MemoryView: handleSave - EDIT MODE - Showing success snackbar');
        showOverlaySnackText(
          'dialog_content_memory_updated_successfully'.tr,
          backgroundColor: Colors.blue.shade400,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
        debugPrint('MemoryView: handleSave - EDIT MODE - Snackbar shown');
        // Pop the view after showing snackbar
        debugPrint('MemoryView: handleSave - EDIT MODE - Popping view with result: true');
        Get.back(result: true);
        debugPrint('MemoryView: handleSave - EDIT MODE - View popped successfully');
      } else {
        debugPrint('MemoryView: handleSave - CREATE MODE - Creating new memory');
        // Create new memory
        // Validation before saving memory
        debugPrint('MemoryView: handleSave - CREATE MODE - Starting validation');
        final validationResult = await _validateMemoryData(
          description,
          tags,
          mentions,
        );
        debugPrint('MemoryView: handleSave - CREATE MODE - Validation result: ${validationResult['isValid']}');
        if (!validationResult['isValid']) {
          debugPrint(
            'MemoryView: handleSave - CREATE MODE - Validation failed: ${validationResult['messageKey']}',
          );
          _showValidationError(validationResult['messageKey'] as String);
          return;
        }

        debugPrint('MemoryView: handleSave - CREATE MODE - Saving memory to database');
        debugPrint('MemoryView: handleSave - CREATE MODE - Images: ${_selectedImagePaths.length}, Videos: ${_selectedVideoPaths.length}');
        final imgOrders = <int>[];
        final vidOrders = <int>[];
        for (int i = 0; i < _orderedMedia.length; i++) {
          final item = _orderedMedia[i];
          if (item['type'] == 'image') imgOrders.add(i);
          if (item['type'] == 'video') vidOrders.add(i);
        }
        final newMemoryId = await memoryController.saveMemory(
          description: description,
          imagePaths: _selectedImagePaths,
          videoPaths: _selectedVideoPaths,
          imageOrders: imgOrders,
          videoOrders: vidOrders,
          tags: tags,
          mentions: mentions,
        );
        debugPrint('MemoryView: handleSave - CREATE MODE - Memory saved successfully (id: $newMemoryId)');

        // Clear the draft since memory was saved successfully
        debugPrint('MemoryView: handleSave - CREATE MODE - Clearing draft');
        await _clearDraft();
        debugPrint('MemoryView: handleSave - CREATE MODE - Draft cleared');

        // Clear the description field
        debugPrint('MemoryView: handleSave - CREATE MODE - Clearing UI fields');
        _descriptionController.clear();
        _orderedMedia.clear();
        debugPrint('MemoryView: handleSave - CREATE MODE - UI fields cleared');

        // Clear all controller data including audio recordings
        debugPrint('MemoryView: handleSave - CREATE MODE - Clearing controller data');
        memoryController.clearAllData();
        debugPrint('MemoryView: handleSave - CREATE MODE - Controller data cleared');

        // Incrementally update lists/map — avoid reloading 1000s of KMZ memories.
        debugPrint('MemoryView: handleSave - CREATE MODE - Incremental FilterController update');
        if (Get.isRegistered<FilterController>()) {
          final filterController = Get.find<FilterController>();
          filterController.resetFiltersExceptSearch();
          await filterController.prependMemoryById(newMemoryId);
          debugPrint(
            'MemoryView: handleSave - CREATE MODE - FilterController: ${filterController.filteredMemories.length} memories',
          );

          if (Get.isRegistered<MapControllerNew>()) {
            final mapController = Get.find<MapControllerNew>();
            await mapController.loadMemoriesFromDB(
              filterController.filteredMemories.toList(),
            );
            mapController.showLoadedDataOnMap();
            debugPrint('MemoryView: handleSave - CREATE MODE - Map view updated (incremental)');
          }
        }

        // Show success snackbar before popping
        debugPrint('MemoryView: handleSave - CREATE MODE - Showing success snackbar');
        Get.back(result: true);

        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(
        //     content: const Text('Memory created successfully!'),
        //     backgroundColor: Colors.green.shade400,
        //     margin: const EdgeInsets.all(12),
        //     behavior: SnackBarBehavior.floating,
        //   ),
        // );
        debugPrint('MemoryView: handleSave - CREATE MODE - Snackbar shown');

        // Pop the view after showing snackbar
        debugPrint('MemoryView: handleSave - CREATE MODE - Popping view with result: true');
        debugPrint('MemoryView: handleSave - CREATE MODE - View popped successfully');
      }

      debugPrint('MemoryView: handleSave - Method completed successfully');
    } catch (e) {
      debugPrint('MemoryView: handleSave - ERROR CAUGHT: $e');
      debugPrint('MemoryView: handleSave - ERROR - Stack trace: ${StackTrace.current}');

      Get.back(result: true);
      debugPrint('MemoryView: handleSave - ERROR - View popped after error');
      print('Error Log: $e');
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text('Unable to save memory. Please try again.')),
      // );
    }
    debugPrint('MemoryView: handleSave - Method exiting (after try-catch)');
  }

  void _handleDelete() {
    //  if (_editingMemoryId == null) {
    //     Get.snackbar(
    //       'Error',
    //       'No memory selected for deletion',
    //       backgroundColor: Colors.red,
    //       colorText: Colors.white,
    //     );
    //     return;
    //   }

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
            'title_text_delete_memory_2'.tr,
            style: TextStyle(
              color:
                  uiController.darkMode.value
                      ? Colors
                          .white // White text for dark mode
                      : Colors.black, // Black text for light mode
            ),
          ),
          content: Text(
            'dialog_content_are_you_sure_you_want_to_delete_this_memo_2'.tr,
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
                'text_cancel_6'.tr,
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
                Get.back();

                try {
                  debugPrint('[MemoryView] 🗑️ Deleting memory ID: $_editingMemoryId');

                  final memoryController = Get.find<MemoryController>();
                  await memoryController.deleteMemory(_editingMemoryId!);

                  debugPrint('[MemoryView] ✅ Memory deleted from database');

                  // Reload data from FilterController (single source of truth)
                  if (Get.isRegistered<FilterController>()) {
                    final filterController = Get.find<FilterController>();
                    await filterController.loadAndApplyFilters();
                    debugPrint('[MemoryView] 📊 FilterController reloaded: ${filterController.filteredMemories.length} memories');
                  }

                  // Refresh AddMemories view
                  if (Get.isRegistered<AddMemoriesController>()) {
                    final addMemoriesController = Get.find<AddMemoriesController>();
                    await addMemoriesController.loadMemoriesFromDatabase();
                    debugPrint('[MemoryView] ✅ AddMemories view reloaded');
                  }

                  // Refresh Map view
                  if (Get.isRegistered<MapControllerNew>()) {
                    final mapController = Get.find<MapControllerNew>();
                    final filterController = Get.find<FilterController>();
                    await mapController.loadMemoriesFromDB(filterController.filteredMemories.toList());
                    mapController.showLoadedDataOnMap();
                    debugPrint('[MemoryView] ✅ Map view reloaded');
                  }

                  // Show success message
                  showTrSnackbar('snackbar_success_21', 
                    backgroundColor: Colors.red.withValues(alpha: 0.8),
                    colorText: Colors.white,
                    duration: const Duration(seconds: 2),);
                  Get.back(result: true);
                } catch (e) {
                  debugPrint('[MemoryView] ❌ Error deleting memory: $e');
                  showTrSnackbar('snackbar_unable_to_delete_10', 
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                    duration: const Duration(seconds: 2),);
                }
              },
              child: Text(
                'text_delete_4'.tr,
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

  void _showDebugDatabaseViewer() async {
    try {
      final memoryController = Get.find<MemoryController>();
      final allMemories = await memoryController.getAllMemories();
      final databaseHelper = DatabaseHelper.instance;

      Get.defaultDialog(
        title: 'title_literal_database_contents'.tr,
        content: SizedBox(
          width: double.maxFinite,
          height: Get.height * 0.7,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'text_database_statistics'.tr,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        trKey('text_debug_total_memories', [allMemories.length]),
                      ),
                      Text('text_database_version_4'.tr),
                      Text('text_database_name_memories_db'.tr),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ...allMemories.map((memory) {
                  final base64Images = databaseHelper.getBase64ImagesFromMemory(
                    memory,
                  );
                  final audioPaths = databaseHelper.getAudioPathsFromMemory(
                    memory,
                  );

                  return Card(
                    margin: const EdgeInsets.all(8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trKey('text_id_memory', [memory['id']]),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const Divider(),
                          Text(trKey('text_date_memory', [
                            memory['date'] ?? 'N/A',
                          ])),
                          Text(trKey('text_time_memory', [
                            memory['time'] ?? 'N/A',
                          ])),
                          if (memory['location'] != null &&
                              memory['location'].toString().isNotEmpty)
                            Text(trKey('text_location_memory', [
                              memory['location'],
                            ])),
                          if (memory['category'] != null &&
                              memory['category'].toString().isNotEmpty)
                            Text(trKey('text_category_memory', [
                              localizedPlaceCategoryStoredLabel(
                                memory['category'].toString(),
                              ),
                            ])),
                          if (memory['description'] != null &&
                              memory['description'].toString().isNotEmpty)
                            Text(
                              trKey('text_description_memory', [
                                memory['description'],
                              ]),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),

                          // Base64 Images Display
                          if (base64Images.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              trKey('text_debug_images_base64_header', [
                                base64Images.length,
                              ]),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            ...base64Images.asMap().entries.map((entry) {
                              final index = entry.key;
                              final base64 = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  top: 4,
                                ),
                                child: Text(
                                  trKey('text_debug_image_base64_entry', [
                                    index + 1,
                                    base64.length,
                                    (base64.length * 0.75 / 1024)
                                        .toStringAsFixed(1),
                                  ]),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              );
                            }).toList(),
                          ],

                          // Audio Files Display
                          if (audioPaths.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              trKey('text_debug_audio_files_header', [
                                audioPaths.length,
                              ]),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            ...audioPaths.asMap().entries.map((entry) {
                              final index = entry.key;
                              final audioPath = entry.value;
                              final fileName = audioPath.split('/').last;
                              return Padding(
                                padding: const EdgeInsets.only(
                                  left: 16,
                                  top: 4,
                                ),
                                child: Text(
                                  trKey('text_debug_audio_file_entry', [
                                    index + 1,
                                    fileName,
                                  ]),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              );
                            }).toList(),
                          ],

                          if (memory['tags'] != null &&
                              memory['tags'].toString().isNotEmpty)
                            Text(trKey('text_tags_memory', [memory['tags']])),
                          if (memory['mentions'] != null &&
                              memory['mentions'].toString().isNotEmpty)
                            Text(trKey('text_mentions_memory', [
                              memory['mentions'],
                            ])),

                          const SizedBox(height: 8),
                          Text(
                            trKey('text_created_memory', [
                              memory['created_at'] ?? 'N/A',
                            ]),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (memory['updated_at'] != null)
                            Text(
                              trKey('text_updated_memory', [
                                memory['updated_at'],
                              ]),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: Text('text_close_4'.tr)),
        ],
      );
    } catch (e) {
      showTrSnackbar('snackbar_unable_to_load_3',       duration: const Duration(seconds: 2),);
    }
  }

  @override
  Widget build(BuildContext context) {
    final memoryController = Get.find<MemoryController>();

    final controller = Get.find<UiController>();

    return PopScope(
      canPop: !_isPopupOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isPopupOpen) {
          _descriptionFieldKey.currentState?.closePopup();
        } else if (didPop) {
          // Clear audio and image data when navigating back
          try {
            memoryController.clearAudioRecordings();
            debugPrint('Audio data cleared on back navigation');
          } catch (e) {
            debugPrint('Error clearing audio data on back navigation: $e');
          }

          _orderedMedia.clear();
          debugPrint('Image data cleared on back navigation');

          // In create mode, also clear location/category/date so next new memory
          // starts fresh with current location instead of previous picked one.
          if (!widget.editMode) {
            memoryController.clearAllData();
          }
        }
      },
      child: Obx(
        () {
          // Detect keyboard visibility
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          _isKeyboardVisible.value = keyboardHeight > 0;

          // Set status bar color to match current main color
          // Icons will be white in dark mode, black in light mode

          return Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor:
                controller.darkMode.value
                    ? Colors.white.withOpacity(0.03)
                    : Colors.white,
            body: GestureDetector(
              // Dismiss keyboard when tapping outside text fields
              onTap: () {
                FocusScope.of(context).unfocus();
              },
              child: SafeArea(bottom: false,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MemoryInfoWidget(
                            onCategorySelected: _unfocusDescriptionField,
                            onAnyWidgetTapped: _unfocusDescriptionField,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            color:
                                controller.darkMode.value
                                    ? Colors.white.withOpacity(0.06)
                                    : controller.getLightModeBackgroundColor(
                                          controller.mainColor.value,
                                        ),
                            child: Obx(
                              () {
                                final totalMediaCount = _orderedMedia.length;

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 170,
                                        child: ReorderableListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          buildDefaultDragHandles: false,
                                          itemCount: totalMediaCount,
                                          onReorder: (oldIndex, newIndex) {
                                            if (newIndex > oldIndex) newIndex--;
                                            final item = _orderedMedia.removeAt(oldIndex);
                                            _orderedMedia.insert(newIndex, item);
                                            _orderedMedia.refresh();
                                          },
                                          itemBuilder: (context, index) {
                                            final mediaItem = _orderedMedia[index];
                                            final isImage = mediaItem['type'] == 'image';
                                            final path = mediaItem['path'] as String;

                                            if (isImage) {
                                              return Padding(
                                                key: ValueKey('media_$index\_${path.hashCode}'),
                                                padding: const EdgeInsets.only(right: 8),
                                                child: SizedBox(
                                                  width: 120,
                                                  height: 170,
                                                  child: Stack(
                                                    children: [
                                                      ClipRRect(
                                                        borderRadius: BorderRadius.circular(8),
                                                        child: Image.file(
                                                          File(path),
                                                          fit: BoxFit.cover,
                                                          width: 120,
                                                          height: 170,
                                                        ),
                                                      ),
                                                      Positioned(
                                                        top: 4,
                                                        right: 4,
                                                        child: GestureDetector(
                                                          onTap: () async {
                                                            await _deleteMediaAtIndex(index);
                                                          },
                                                          child: Container(
                                                            width: 24,
                                                            height: 24,
                                                            decoration: BoxDecoration(
                                                              color: Colors.black.withOpacity(0.6),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: const Icon(
                                                              Icons.close,
                                                              color: Colors.white,
                                                              size: 16,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      Positioned(
                                                        bottom: 4,
                                                        right: 4,
                                                        child: ReorderableDragStartListener(
                                                          index: index,
                                                          child: Container(
                                                            width: 28,
                                                            height: 28,
                                                            decoration: BoxDecoration(
                                                              color: Colors.black.withOpacity(0.6),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: const Icon(
                                                              Icons.drag_handle,
                                                              color: Colors.white,
                                                              size: 18,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            } else {
                                              return Padding(
                                                key: ValueKey('media_$index\_${path.hashCode}'),
                                                padding: const EdgeInsets.only(right: 8),
                                                child: SizedBox(
                                                  width: 120,
                                                  height: 170,
                                                  child: Stack(
                                                    children: [
                                                      VideoThumbnailWidget(
                                                        videoPath: path,
                                                        width: 120,
                                                        height: 170,
                                                        onTap: () {
                                                          Get.to(() => VideoPlayerScreen(
                                                            videoPath: path,
                                                            allowHorizontal: false,
                                                          ));
                                                        },
                                                        onDelete: () async {
                                                          await _deleteMediaAtIndex(index);
                                                        },
                                                      ),
                                                      Positioned(
                                                        bottom: 4,
                                                        right: 4,
                                                        child: ReorderableDragStartListener(
                                                          index: index,
                                                          child: Container(
                                                            width: 28,
                                                            height: 28,
                                                            decoration: BoxDecoration(
                                                              color: Colors.black.withOpacity(0.6),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            child: const Icon(
                                                              Icons.drag_handle,
                                                              color: Colors.white,
                                                              size: 18,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  GestureDetector(
                                    onTap: _handleImageUpload,
                                    child: Padding(
                                      padding: const EdgeInsets.all(5.0),
                                      child: Container(
                                        width: 70,
                                        height: 70,
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color:
                                              controller.darkMode.value
                                                  ? Colors.black
                                                  : Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color:
                                                controller.darkMode.value
                                                    ? Colors.white.withOpacity(
                                                      0.3,
                                                    )
                                                    : Colors.grey.shade300,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  controller.darkMode.value
                                                      ? Colors.white
                                                          .withOpacity(0.15)
                                                      : Colors.black
                                                          .withOpacity(0.2),
                                              blurRadius: 6,
                                              spreadRadius: 0.0,
                                              offset: const Offset(0, 0),
                                            ),
                                          ],
                                        ),
                                        child: Image.asset(
                                          AppImages.addImg,
                                          fit: BoxFit.contain,
                                          color:
                                              controller.darkMode.value
                                                  ? Colors.white
                                                  : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                              },
                            ),
                          ),
                          Divider(
                            color:
                                controller.darkMode.value
                                    ? Colors.black.withOpacity(0.2)
                                    : Colors.transparent,
                            height: 0.1,
                          ),
                          MemoryDescriptionField(
                            key: _descriptionFieldKey,
                            controller: _descriptionController,
                            existingTags: _existingTags,
                            existingMentions: _existingMentions,
                            onTagAdded: _onTagAdded,
                            onMentionAdded: _onMentionAdded,
                            onPopupStateChanged: _onPopupStateChanged,
                            scrollController: _scrollController,
                          ),
                          MemoryAudioWidget(
                            onPlayPause: _handleAudioPlay,
                            onAudioDelete: _deleteAudioAtIndex,
                          ),
                          if (_isKeyboardVisible.value)
                            SizedBox(height: MediaQuery.of(context).size.height * 0.5),
                        ],
                      ),
                    ),
                  ),
                  // Bottom action buttons - hide when keyboard is visible
                  Obx(
                    () => _isKeyboardVisible.value
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 20.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TickCrossActionButton(
                                  iconPath: 'assets/images/ic_cross.png',
                                  onTap: () {
                                    _handleCancel(
                                      memoryController.recordedAudioPaths,
                                      _selectedImagePaths,
                                      memoryController.recordedAudios,
                                    );
                                  },
                                ),
                        // Delete button (only show in edit mode)
                        // Debug: Check delete button visibility
                        Builder(
                          builder: (context) {
                            debugPrint(
                              'Delete button check: editMode=${widget.editMode}, memoryId=$_editingMemoryId',
                            );
                            return const SizedBox.shrink();
                          },
                        ),
                        if (widget.editMode) ...[
                          const SizedBox(width: 20),
                          InkWell(
                            onTap: _handleDelete,
                            child: Container(
                              width: 60,
                              height: 60,
                              // padding: const EdgeInsets.all(15),
                              // decoration: BoxDecoration(
                              //   borderRadius: BorderRadius.circular(20),
                              //   border: Border.all(
                              //     color:
                              //         controller.darkMode.value
                              //             ? Colors.red.withValues(alpha: 0.3)
                              //             : Colors.transparent,
                              //   ),
                              //   image: DecorationImage(
                              //     image: AssetImage(AppImages.whiteRectangle),
                              //     fit: BoxFit.cover,
                              //     colorFilter: ColorFilter.mode(
                              //       controller.darkMode.value
                              //           ? Colors.red.withValues(alpha: 0.8)
                              //           : Colors.red.withValues(alpha: 0.7),
                              //       BlendMode.srcATop,
                              //     ),
                              // //   ),
                              //   boxShadow: [
                              //     BoxShadow(
                              //       color:
                              //           controller.darkMode.value
                              //               ? Colors.red.withValues(alpha: 0.15)
                              //               : Colors.red.withValues(alpha: 0.1),
                              //       blurRadius: 20,
                              //       spreadRadius: 0.0,
                              //       offset: const Offset(0, 0),
                              //     ),
                              //     if (controller.darkMode.value)
                              //       BoxShadow(
                              //         color: Colors.red.withValues(alpha: 0.1),
                              //         blurRadius: 20,
                              //         spreadRadius: 0,
                              //         offset: const Offset(0, 0),
                              //       ),
                              //   ],
                              // ),
                                  //  width: 60,
        // height: 60,

        
        decoration: BoxDecoration(
          color: controller.darkMode.value
              ? Colors.red.withValues(alpha: 0.7)
              : Colors.red,
          borderRadius: BorderRadius.circular(20),
          border:   controller.darkMode.value
              ? Border.all(
                  color: Colors.white.withOpacity(0.22),
                  width: 2,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 20),
                        ] else
                          const SizedBox(width: 70),

                        TickCrossActionButton(
                          iconPath: 'assets/images/ic_tick.png',
                          onTap: _handleSave,
                        ),
                      ],
                    ),
                  ),
                  ), // Close Obx for bottom buttons
                ],
              ),
            ),
          ), // Close GestureDetector
          /// TODO: UnComment whenever you want to see your database tables. <UKDev>
          // floatingActionButton: FloatingActionButton(
          //   heroTag: 'debug_button',
          //   onPressed: _showDebugDatabaseViewer,
          //   mini: true,
          //   child: const Icon(Icons.bug_report, size: 20),
          // ),
          );
        },
      ),
    );
  }

  // Validate memory data before saving
  Future<Map<String, dynamic>> _validateMemoryData(
    String description,
    List<String> tags,
    List<String> mentions,
  ) async {
    final memoryController = Get.find<MemoryController>();

    // Check if date/time is in the future
    final selectedDate = memoryController.selectedDate.value ?? DateTime.now();
    final selectedTime = memoryController.selectedTime.value ?? TimeOfDay.now();

    final selectedDateTime = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    final now = DateTime.now();
    if (selectedDateTime.isAfter(now)) {
      return {
        'isValid': false,
        'messageKey': 'dialog_content_memory_date_cannot_be_future',
      };
    }

    // Check if place category is provided (MANDATORY)
    // if (memoryController.selectedCategory.value.isEmpty) {
    //   return {
    //     'isValid': false,
    //     'message':
    //         'Place category is required. Please select a category for your memory location.',
    //   };
    // }

    // Location permission is not required, but a location must be selected
    // Check if location is selected (mandatory field)
    if (memoryController.selectedLocation.value.isEmpty) {
      return {
        'isValid': false,
        'messageKey': 'dialog_content_memory_location_required_select',
      };
    }

    // Content is no longer mandatory - images, audio, and description are all optional
    // Note: Removed content requirement as per user request

    return {'isValid': true, 'messageKey': ''};
  }

  // Show validation error dialog
  void _showValidationError(String messageKey) {
    final controller = Get.find<UiController>();

    IconData icon = Icons.warning_amber_rounded;
    var titleKey = 'title_text_dialog_validation_error';
    Color iconColor = Colors.orange.shade600;

    switch (messageKey) {
      case 'dialog_content_memory_date_cannot_be_future':
        icon = Icons.access_time;
        titleKey = 'title_text_dialog_invalid_date_time';
        iconColor = Colors.red.shade600;
        break;
      case 'dialog_content_memory_location_required_select':
        icon = Icons.location_on;
        titleKey = 'title_text_dialog_location_required';
        iconColor = Colors.green.shade600;
        break;
      default:
        titleKey = 'title_text_dialog_missing_information';
    }

    showDialog(
      context: context,
      useRootNavigator: true,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(icon, color: iconColor, size: 28),
                const SizedBox(width: 12),
                Text(
                  titleKey.tr,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: Text(
              messageKey.tr,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            backgroundColor:
                controller.darkMode.value ? Colors.grey.shade800 : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor:
                      controller.darkMode.value
                          ? controller.currentMainColor
                          : controller.primaryColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  'text_ok_6'.tr,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
    );
  }

  // Save draft to SharedPreferences (only for new memories)
  Future<void> _saveDraft(
    List<String> _selectedImagePaths,
    List<String> recordedAudioPaths,
    List<String> durations,
  ) async {
    debugPrint('[ _saveDraft ] 🔄 _saveDraft() called');

    // Only save draft for new memories (not in edit mode)
    if (widget.editMode || widget.memoryData != null) {
      debugPrint(
        '[ _saveDraft ] ❌ Skipping draft save - editMode: ${widget.editMode}, memoryData: ${widget.memoryData != null}',
      );
      return;
    }

    debugPrint('[ _saveDraft ] ✅ Proceeding with draft save');

    try {
      final prefs = await SharedPreferences.getInstance();
      final memoryController = Get.find<MemoryController>();

      // Get tags and mentions from the description field
      final tags = _descriptionFieldKey.currentState?.getTags() ?? [];
      final mentions = _descriptionFieldKey.currentState?.getMentions() ?? [];

      debugPrint('[ _saveDraft ] Draft content check:');
      debugPrint(
        '[ _saveDraft ]   Description: "${_descriptionController.text}"',
      );
      debugPrint('[ _saveDraft ]   Images: ${_selectedImagePaths.length}');
      debugPrint('[ _saveDraft ]   Audio: ${recordedAudioPaths.length}');
      debugPrint(
        '[ _saveDraft ]   Location: "${memoryController.selectedLocation.value}"',
      );

      // Debug the actual image paths
      if (_selectedImagePaths.isNotEmpty) {
        debugPrint('[ _saveDraft ]   Image paths:');
        for (int i = 0; i < _selectedImagePaths.length; i++) {
          debugPrint('[ _saveDraft ]     [$i]: ${_selectedImagePaths[i]}');
        }
      } else {
        debugPrint('[ _saveDraft ]   ❌ No images in _selectedImagePaths list!');
      }

      // Convert images to base64 for safe storage
      List<String> imageBase64List = [];
      debugPrint(
        '[ _saveDraft ] Starting to convert ${_selectedImagePaths.length} images to base64',
      );

      for (int i = 0; i < _selectedImagePaths.length; i++) {
        String imagePath = _selectedImagePaths[i];
        try {
          final file = File(imagePath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final base64String = base64Encode(bytes);
            imageBase64List.add(base64String);
            debugPrint(
              '[ _saveDraft ] Image $i converted to base64 for draft: ${imagePath.split('/').last} (${bytes.length} bytes -> ${base64String.length} chars)',
            );
          } else {
            debugPrint('[ _saveDraft ] Image file does not exist: $imagePath');
          }
        } catch (e) {
          debugPrint(
            '[ _saveDraft ] Error converting image $i to base64 for draft: $e',
          );
        }
      }

      debugPrint(
        '[ _saveDraft ] Successfully converted ${imageBase64List.length} images to base64',
      );

      // Store audio file contents as base64 for safe storage
      List<Map<String, String>> audioDataList = [];
      debugPrint(
        '[ _saveDraft ] Starting to convert ${memoryController.recordedAudioPaths.length} audio files to base64',
      );

      for (int i = 0; i < memoryController.recordedAudioPaths.length; i++) {
        String audioPath = memoryController.recordedAudioPaths[i];
        try {
          final file = File(audioPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final base64String = base64Encode(bytes);
            final fileName = audioPath.split('/').last;

            // Get audio duration if available
            String? duration;
            if (i < durations.length) {
              duration = durations[i];
            }

            audioDataList.add({
              'fileName': fileName,
              'base64Data': base64String,
              'originalPath': audioPath,
              'duration':
                  duration ?? '00:00', // Default duration if not available
            });
            debugPrint(
              '[ _saveDraft ] Audio $i converted to base64 for draft: $fileName (${bytes.length} bytes -> ${base64String.length} chars) duration: ${duration ?? "unknown"}',
            );
          } else {
            debugPrint('[ _saveDraft ] Audio file does not exist: $audioPath');
          }
        } catch (e) {
          debugPrint(
            '[ _saveDraft ] Error converting audio $i to base64 for draft: $e',
          );
        }
      }

      debugPrint(
        '[ _saveDraft ] Successfully converted ${audioDataList.length} audio files to base64',
      );

      final draftData = {
        'description': _descriptionController.text,
        'selectedDate': memoryController.selectedDate.value?.toIso8601String(),
        'selectedTime':
            memoryController.selectedTime.value != null
                ? '${memoryController.selectedTime.value!.hour}:${memoryController.selectedTime.value!.minute}'
                : null,
        'selectedLocation': memoryController.selectedLocation.value,
        // Persist enhanced location fields so we don't refetch on reopen.
        'locationCountry': memoryController.locationCountry.value,
        'locationCity': memoryController.locationCity.value,
        'locationName': memoryController.locationName.value,
        'locationAddress': memoryController.locationAddress.value,
        'locationFlag': memoryController.locationFlag.value,
        'locationLatitude': memoryController.locationLatitude.value,
        'locationLongitude': memoryController.locationLongitude.value,
        'selectedCategory': memoryController.selectedCategory.value,
        'tags': tags,
        'mentions': mentions,
        'imageBase64List': imageBase64List,
        'audioDataList': audioDataList,
        'originalImagePaths':
            _selectedImagePaths.toList(), // Keep for reference
        'timestamp': DateTime.now().toIso8601String(),
      };

      debugPrint(
        '[ _saveDraft ] About to save draft with ${imageBase64List.length} images and ${audioDataList.length} audio files',
      );
      debugPrint('[ _saveDraft ] Draft data keys: ${draftData.keys.toList()}');
      debugPrint(
        '[ _saveDraft ] ImageBase64List length: ${(draftData['imageBase64List'] as List?)?.length ?? 0}',
      );
      debugPrint(
        '[ _saveDraft ] AudioDataList length: ${(draftData['audioDataList'] as List?)?.length ?? 0}',
      );

      try {
        final jsonString = jsonEncode(draftData);
        await prefs.setString('memory_draft', jsonString);
        debugPrint(
          '[ _saveDraft ] Draft JSON saved successfully. JSON length: ${jsonString.length} characters',
        );
        debugPrint(
          '[ _saveDraft ] Draft saved successfully with ${imageBase64List.length} images and ${audioDataList.length} audio files',
        );
      } catch (jsonError) {
        debugPrint('[ _saveDraft ] Error encoding draft to JSON: $jsonError');
        // Try saving without base64 data as fallback
        final fallbackData = Map<String, dynamic>.from(draftData);
        fallbackData.remove('imageBase64List');
        fallbackData.remove('audioDataList');
        fallbackData['hasImages'] = imageBase64List.isNotEmpty;
        fallbackData['hasAudio'] = audioDataList.isNotEmpty;

        try {
          await prefs.setString('memory_draft', jsonEncode(fallbackData));
          debugPrint('[ _saveDraft ] Fallback draft saved without media data');
        } catch (fallbackError) {
          debugPrint(
            '[ _saveDraft ] Error saving fallback draft: $fallbackError',
          );
        }
      }
    } catch (e) {
      debugPrint('[ _saveDraft ] Error saving draft: $e');
    }
  }

  // Load draft from SharedPreferences
  Future<void> _loadDraft() async {
    // Only load draft for new memories (not in edit mode)
    if (widget.editMode || widget.memoryData != null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final draftJson = prefs.getString('memory_draft');

      if (draftJson != null) {
        debugPrint('Found draft data length: ${draftJson.length} characters');
        final draftData = jsonDecode(draftJson) as Map<String, dynamic>;
        final memoryController = Get.find<MemoryController>();

        // Restore description
        if (draftData['description'] != null &&
            draftData['description'].toString().isNotEmpty) {
          _descriptionController.text = draftData['description'];
        }

        // Restore date
        if (draftData['selectedDate'] != null) {
          final date = DateTime.tryParse(draftData['selectedDate']);
          if (date != null) {
            memoryController.setDate(date);
          }
        }

        // Restore time
        if (draftData['selectedTime'] != null) {
          final timeParts = draftData['selectedTime'].toString().split(':');
          if (timeParts.length == 2) {
            final hour = int.tryParse(timeParts[0]);
            final minute = int.tryParse(timeParts[1]);
            if (hour != null && minute != null) {
              memoryController.setTime(TimeOfDay(hour: hour, minute: minute));
            }
          }
        }

        // Restore location
        if (draftData['selectedLocation'] != null &&
            draftData['selectedLocation'].toString().isNotEmpty) {
          memoryController.setLocation(draftData['selectedLocation']);
        }

        // Restore enhanced location (avoid reverse geocoding on reopen).
        memoryController.locationCountry.value =
            draftData['locationCountry'] ?? '';
        memoryController.locationCity.value =
            draftData['locationCity'] ?? '';
        memoryController.locationName.value =
            draftData['locationName'] ?? '';
        memoryController.locationAddress.value =
            draftData['locationAddress'] ?? '';
        memoryController.locationFlag.value =
            draftData['locationFlag'] ?? '';

        final savedLat = draftData['locationLatitude'];
        final savedLng = draftData['locationLongitude'];
        if (savedLat != null) {
          memoryController.locationLatitude.value = (savedLat as num).toDouble();
        }
        if (savedLng != null) {
          memoryController.locationLongitude.value = (savedLng as num).toDouble();
        }

        // Restore category
        if (draftData['selectedCategory'] != null &&
            draftData['selectedCategory'].toString().isNotEmpty) {
          memoryController.setCategory(draftData['selectedCategory']);
        }

        // Restore tags and mentions (will be handled by description field widget)
        // Tags and mentions are embedded in the description text and will be
        // automatically parsed when the description field is initialized

        // Restore images from base64 data
        if (draftData['imageBase64List'] != null) {
          debugPrint(
            'Found ${(draftData['imageBase64List'] as List).length} images in draft',
          );
          final imageBase64List = List<String>.from(
            draftData['imageBase64List'],
          );
          _orderedMedia.clear();

          // Create temporary files from base64 data
          final appDir = await getApplicationDocumentsDirectory();
          final tempImagesDir = Directory('${appDir.path}/temp_draft_images');

          if (!await tempImagesDir.exists()) {
            await tempImagesDir.create(recursive: true);
          }

          for (int i = 0; i < imageBase64List.length; i++) {
            try {
              final base64Data = imageBase64List[i];
              final bytes = base64Decode(base64Data);
              final tempFileName =
                  'draft_image_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
              final tempFile = File('${tempImagesDir.path}/$tempFileName');

              await tempFile.writeAsBytes(bytes);
              _orderedMedia.add({'type': 'image', 'path': tempFile.path});
              debugPrint('Restored image from draft: $tempFileName');
              debugPrint('Image file exists: ${await tempFile.exists()}');
              debugPrint('Image file size: ${await tempFile.length()} bytes');
            } catch (e) {
              debugPrint('Error restoring image from draft: $e');
            }
          }
        }

        // Restore audio from base64 data
        if (draftData['audioDataList'] != null) {
          final audioDataList = List<Map<String, dynamic>>.from(
            draftData['audioDataList'],
          );

          memoryController.recordedAudioPaths.clear();
          memoryController.recordedAudios.clear(); // Also clear the durations

          // Create temporary files from base64 data
          final appDir = await getApplicationDocumentsDirectory();
          final tempAudioDir = Directory('${appDir.path}/temp_draft_audio');

          if (!await tempAudioDir.exists()) {
            await tempAudioDir.create(recursive: true);
          }

          for (int i = 0; i < audioDataList.length; i++) {
            try {
              final audioData = audioDataList[i];
              final base64Data = audioData['base64Data'] as String;
              final originalFileName =
                  audioData['fileName'] as String? ?? 'draft_audio_$i.m4a';
              final duration = audioData['duration'] as String? ?? '00:00';
              final bytes = base64Decode(base64Data);

              final tempFileName =
                  'draft_${DateTime.now().millisecondsSinceEpoch}_$originalFileName';
              final tempFile = File('${tempAudioDir.path}/$tempFileName');

              await tempFile.writeAsBytes(bytes);

              // Add the restored audio file path and duration to the controller
              memoryController.recordedAudioPaths.add(tempFile.path);
              memoryController.recordedAudios.add(duration);

              debugPrint('Restored audio from draft: $tempFileName');
              debugPrint('Audio file exists: ${await tempFile.exists()}');
              debugPrint('Audio file size: ${await tempFile.length()} bytes');
              debugPrint('Audio duration restored: $duration');
            } catch (e) {
              debugPrint('Error restoring audio from draft: $e');
            }
          }

          // _loadExistingAudiosForEdit(memoryController.recordedAudioPaths, memoryController.recordedAudios);

          debugPrint(
            'Total audio files restored: ${memoryController.recordedAudioPaths.length}',
          );
          debugPrint(
            'Total audio durations restored: ${memoryController.recordedAudios.length}',
          );
        }

        debugPrint('Draft loaded successfully');

        // Force UI refresh to show restored images and audio
        // Add a small delay to ensure all file operations are complete
        await Future.delayed(const Duration(milliseconds: 100));

        _orderedMedia.refresh();
        debugPrint(
          '🔄 Media refreshed. Count: ${_orderedMedia.length}',
        );

        // Force memory controller refresh for audio
        memoryController.recordedAudioPaths.refresh();
        debugPrint(
          '🔄 Audio refreshed. Count: ${memoryController.recordedAudioPaths.length}',
        );
        for (int i = 0; i < memoryController.recordedAudioPaths.length; i++) {
          debugPrint('  Audio $i: ${memoryController.recordedAudioPaths[i]}');
        }

        setState(() {
          // This will trigger a rebuild of the entire widget tree
          // ensuring that MemoryImageWidget and MemoryAudioWidget
          // pick up the restored image paths and audio paths
        });
        debugPrint('🔄 setState called for UI refresh');

        // Show a snackbar to inform user that draft was restored
      }
    } catch (e) {
      debugPrint('Error loading draft: $e');
    }
  }

  // Clear draft from SharedPreferences and clean up temporary files
  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('memory_draft');

      // Clean up temporary draft files
      await _cleanupDraftTempFiles();

      debugPrint('Draft cleared successfully');
    } catch (e) {
      debugPrint('Error clearing draft: $e');
    }
  }

  // Clean up temporary draft files
  Future<void> _cleanupDraftTempFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();

      // Clean up temporary images
      final tempImagesDir = Directory('${appDir.path}/temp_draft_images');
      if (await tempImagesDir.exists()) {
        await tempImagesDir.delete(recursive: true);
        debugPrint('Cleaned up temporary draft images');
      }

      // Clean up temporary audio files
      final tempAudioDir = Directory('${appDir.path}/temp_draft_audio');
      if (await tempAudioDir.exists()) {
        await tempAudioDir.delete(recursive: true);
        debugPrint('Cleaned up temporary draft audio files');
      }
    } catch (e) {
      debugPrint('Error cleaning up draft temp files: $e');
    }
  }

  @override
  void dispose() {
    // Clear audio and image data when screen is closed
    try {
      final memoryController = Get.find<MemoryController>();
      memoryController.clearAudioRecordings();
      debugPrint('Audio data cleared on screen dispose');
    } catch (e) {
      debugPrint('Error clearing audio data on dispose: $e');
    }

    _orderedMedia.clear();
    debugPrint('Image data cleared on screen dispose');

    // Clean up temporary draft files if not in edit mode
    if (!widget.editMode && widget.memoryData == null) {
      _cleanupDraftTempFiles();
    }

    // Dispose text controller
    _descriptionController.dispose();
    // Dispose scroll controller
    _scrollController.dispose();
    super.dispose();
  }
}
