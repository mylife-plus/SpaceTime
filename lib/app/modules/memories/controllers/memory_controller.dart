import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spacetime/app/shared/widgets/permission_open_settings_dialog.dart';
import 'package:spacetime/app/utils/place_categories_utils.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'package:spacetime/app/services/hashtag_group_service.dart';
import 'package:spacetime/app/services/contact_group_service.dart';
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../services/memory_db.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';

class MemoryController extends GetxController {
  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;
  final AudioRecorder _audioRecorder = AudioRecorder();

  // Audio player state
  RxBool isPlaying = false.obs;
  void togglePlayPause() => isPlaying.value = !isPlaying.value;

  // Audio recording state
  Map<String, dynamic>? locationInfo;
  RxBool isRecording = false.obs;
  RxString recordingDuration = '0:00'.obs;
  RxList<String> recordedAudios =
      <String>[].obs; // Stores durations for display
  RxList<String> recordedAudioPaths =
      <String>[].obs; // Stores actual file paths
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  // Memory info fields
  Rx<DateTime?> selectedDate = Rx<DateTime?>(null);
  Rx<TimeOfDay?> selectedTime = Rx<TimeOfDay?>(null);
  RxString selectedLocation = ''.obs;
  RxString selectedCategory = ''.obs;

  // Enhanced location information
  RxString locationCountry = ''.obs;
  RxString locationCity = ''.obs;
  RxString locationName = ''.obs;
  RxString locationAddress = ''.obs;
  RxString locationFlag = ''.obs;
  Rx<double?> locationLatitude = Rx<double?>(null);
  Rx<double?> locationLongitude = Rx<double?>(null);

  bool ifCalledFromMemoryView = false;
  RxBool isFetchingLocation = false.obs;
  int _locationFetchToken = 0;

  /// Last permission result from [fetchCurrentLocation] (for Memory View placeholder text).
  final Rxn<LocationPermission> lastResolvedLocationPermission =
      Rxn<LocationPermission>();

  /// Placeholder for the location row when no address/coords are shown yet.
  String get locationFieldPlaceholderText {
    final p = lastResolvedLocationPermission.value;
    if (p == null) return 'text_memory_searching_location'.tr;
    if (p == LocationPermission.whileInUse || p == LocationPermission.always) {
      return 'text_memory_pick_location'.tr;
    }
    if (p == LocationPermission.denied ||
        p == LocationPermission.deniedForever) {
      return 'text_memory_location_placeholder'.tr;
    }
    return 'text_memory_searching_location'.tr;
  }

  // Popup controls
  RxBool isPopupOpen = false.obs;
  RxString triggerChar = ''.obs;
  RxString keyword = ''.obs;

  // Tag/Mention/Category lists
  final RxList<String> existingTags = <String>[].obs;
  final RxList<String> existingMentions = <String>[].obs;
  final RxList<String> existingCategories = <String>[].obs;

  @override
  void onInit() {
    super.onInit();
    _initializeDefaults();
    _loadSavedTagsAndMentions();
    _loadSavedCategories();
  }

  // Method to refresh and reinitialize everything (user preference)
  void onAgainInit() {
    debugPrint('MemoryController: onAgainInit called - refreshing data');

    // Reset popup controls
    isPopupOpen.value = false;
    triggerChar.value = '';
    keyword.value = '';

    // DON'T clear enhanced location data when reinitializing
    // Location should only be cleared explicitly via clearAllData() or when user removes it
    // This prevents location from being lost when refreshing categories or other data

    // Reload saved data
    _loadSavedTagsAndMentions();
    _loadSavedCategories();

    // Refresh current location only if no location is set
    if (selectedLocation.value.isEmpty) {
      fetchCurrentLocation();
    }

    debugPrint('MemoryController: onAgainInit completed');
  }

  void _initializeDefaults() async {
    final now = DateTime.now();
    selectedDate.value = now;
    selectedTime.value = TimeOfDay.fromDateTime(now);
    // MemoryView explicitly triggers location once UI is ready.
    // Avoid eager fetch here to prevent duplicate GPS calls on screen open.
  }

  Future<void> _loadSavedTagsAndMentions() async {
    existingTags.value = await _databaseHelper.getPopularTags();
    existingMentions.value = await _databaseHelper.getPopularMentions();
  }

  Future<void> fetchCurrentLocation() async {
    final token = ++_locationFetchToken;
    isFetchingLocation.value = true;
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        selectedLocation.value = '';
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) {
          p = await Geolocator.requestPermission();
        }
        lastResolvedLocationPermission.value = p;
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      lastResolvedLocationPermission.value = permission;

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        selectedLocation.value = '';
        return;
      }

      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await _tryGeolocateCurrentPosition(token);

      if (position == null) {
        selectedLocation.value = '';
        return;
      }

      if (!ifCalledFromMemoryView) {
        return;
      }

      if (token != _locationFetchToken) return;

      // Show coordinates immediately, then enrich with reverse geocoding.
      selectedLocation.value =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
      locationLatitude.value = position.latitude;
      locationLongitude.value = position.longitude;

      final reverseGeocodedData = await _getLocationDetailsFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (reverseGeocodedData != null) {
        // Draft reopen might invalidate this fetch; don't override restored values.
        if (token != _locationFetchToken) return;
        setEnhancedLocationData({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'country': reverseGeocodedData['country'],
          'city': reverseGeocodedData['city'],
          'name': reverseGeocodedData['name'],
          'address': reverseGeocodedData['address'],
          'flag': reverseGeocodedData['flag'],
          'locationString':
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        });
        debugPrint('✅ Reverse geocoding successful for current location');
      } else {
        if (token != _locationFetchToken) return;
        selectedLocation.value = '${position.latitude},${position.longitude}';
        debugPrint('⚠️ Reverse geocoding failed for current location');
      }
    } catch (e) {
      if (token == _locationFetchToken) {
        selectedLocation.value = '';
      }
      debugPrint('fetchCurrentLocation error: $e');
    } finally {
      if (token == _locationFetchToken) {
        isFetchingLocation.value = false;
      }
    }
  }

  Future<Position?> _tryGeolocateCurrentPosition(int token) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: attempt == 0 ? 8 : 12),
          ),
        );
      } catch (e) {
        debugPrint('getCurrentPosition attempt ${attempt + 1}: $e');
        if (attempt == 1) return null;
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (token != _locationFetchToken) return null;
      }
    }
    return null;
  }

  /// Invalidate any in-flight location fetch so it cannot override restored values.
  void invalidateLocationFetch() {
    _locationFetchToken++;
    isFetchingLocation.value = false;
  }

  /// When reopening a draft, we only restore `selectedLocation` (lat,lng).
  /// This rebuilds the enhanced location fields (country/city/name/flag/address)
  /// from those saved coordinates instead of using GPS current location.
  Future<void> fetchEnhancedLocationFromSelectedLocation() async {
    final loc = selectedLocation.value.trim();
    if (loc.isEmpty) return;

    final parts = loc.split(',');
    if (parts.length != 2) return;

    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return;

    isFetchingLocation.value = true;
    try {
      final reverseGeocodedData = await _getLocationDetailsFromCoordinates(
        lat,
        lng,
      );

      if (reverseGeocodedData != null) {
        setEnhancedLocationData({
          'latitude': lat,
          'longitude': lng,
          'country': reverseGeocodedData['country'],
          'city': reverseGeocodedData['city'],
          'name': reverseGeocodedData['name'],
          'address': reverseGeocodedData['address'],
          'flag': reverseGeocodedData['flag'],
        });
      }
    } finally {
      isFetchingLocation.value = false;
    }
  }

  void setDate(DateTime date) => selectedDate.value = date;
  void setTime(TimeOfDay time) => selectedTime.value = time;

  void setLocation(String location) {
    if (_isCoordinateFormat(location)) {
      selectedLocation.value = location;
    }
  }

  /// Set enhanced location information from location picker
  void setEnhancedLocationData(Map<String, dynamic>? locationData) {
    if (locationData != null) {
      print('locationData $locationData');

      // Set enhanced location fields first
      locationCountry.value = locationData['country'] ?? '';
      locationCity.value = locationData['city'] ?? '';
      locationName.value = locationData['name'] ?? '';
      locationAddress.value = locationData['address'] ?? '';
      locationFlag.value = locationData['flag'] ?? '';
      locationLatitude.value = locationData['latitude']?.toDouble();
      locationLongitude.value = locationData['longitude']?.toDouble();

      // Always set selectedLocation as lat,lng coordinates
      if (locationLatitude.value != null && locationLongitude.value != null) {
        selectedLocation.value =
            '${locationLatitude.value},${locationLongitude.value}';
      } else {
        selectedLocation.value = '';
      }

      debugPrint('📍 Enhanced location data set: ${selectedLocation.value}');
      debugPrint(
        '📍 Country: ${locationCountry.value}, City: ${locationCity.value}',
      );
      debugPrint(
        '📍 Coordinates: ${locationLatitude.value}, ${locationLongitude.value}',
      );
    } else {
      // Clear all location data
      selectedLocation.value = '';
      locationCountry.value = '';
      locationCity.value = '';
      locationName.value = '';
      locationAddress.value = '';
      locationFlag.value = '';
      locationLatitude.value = null;
      locationLongitude.value = null;
    }
  }

  Future<Map<String, dynamic>?> _getLocationDetailsFromCoordinates(
    double latitude,
    double longitude,
  ) async {
    try {
      debugPrint(
        '🔍 Reverse geocoding coordinates using OfflineGeocoder: $latitude, $longitude',
      );

      // Initialize offline geocoder if not already done
      final geocodingService = GeocodingIsolateService.instance;

      print('🔍 === ISOLATE REVERSE GEOCODING DEBUG ===');
      print('📍 Input coordinates: $latitude, $longitude');

      final result = await geocodingService.reverseGeocode(latitude, longitude);

      if (result != null) {
        final country = result['country'] ?? '';
        final city = result['city'] ?? '';
        final address = result['address'] ?? '';
        final flag = countryFlags[country.toLowerCase()] ?? '';
        // final flag = _getCountryFlag(country);

        print('📍 Extracted country: "$country"');
        print('📍 Extracted city: "$city"');
        print('📍 Extracted address: "$address"');
        print('📍 Generated flag: "$flag"');

        final locationDetails = {
          'country': country,
          'city': city,
          'name': city.isNotEmpty ? '$city, $country' : country,
          'address': address,
          'flag': flag,
        };

        print('📍 Final locationDetails: $locationDetails');
        print('🔍 === END REVERSE GEOCODING DEBUG ===');

        debugPrint('✅ Reverse geocoding successful: $locationDetails');
        return locationDetails;
      } else {
        print('⚠️ OfflineGeocoder returned null result');
        print('🔍 === END REVERSE GEOCODING DEBUG ===');
        debugPrint('⚠️ No placemarks found for coordinates');
        return null;
      }
    } catch (e) {
      debugPrint('❌ OfflineGeocoder reverse geocoding failed: $e');
      return null;
    }
  }

  bool _isCoordinateFormat(String location) {
    final parts = location.split(',');
    if (parts.length != 2) return false;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    return lat != null && lng != null;
  }

  void setCategory(String category) => selectedCategory.value = category;

  void showPopup(String trigger, String value) {
    triggerChar.value = trigger;
    keyword.value = value;
    isPopupOpen.value = true;
  }

  void hidePopup() {
    triggerChar.value = '';
    keyword.value = '';
    isPopupOpen.value = false;
  }

  // Save images to app directory and return RELATIVE file paths (NEW APPROACH)
  Future<List<String>> saveImagesToAppDirectory(List<String> imagePaths) async {
    List<String> savedImagePaths = [];

    try {
      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/memory_images');

      // Create images directory if it doesn't exist
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      for (String imagePath in imagePaths) {
        try {
          final sourceFile = File(imagePath);
          if (await sourceFile.exists()) {
            // Generate unique filename
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final extension = imagePath.split('.').last.toLowerCase();
            final fileName =
                'memory_${timestamp}_${savedImagePaths.length}.$extension';
            final targetPath = '${imagesDir.path}/$fileName';

            // Copy original image to app directory (preserves quality)
            await sourceFile.copy(targetPath);

            // Store RELATIVE path instead of absolute path
            savedImagePaths.add('memory_images/$fileName');

            debugPrint('Image saved to app directory: $fileName (relative path)');
          }
        } catch (e) {
          debugPrint('Error saving image: $e');
        }
      }
    } catch (e) {
      debugPrint('Error creating images directory: $e');
    }

    return savedImagePaths;
  }

  // Legacy method for backward compatibility - now uses file storage
  Future<List<String>> convertImagesToBase64(List<String> imagePaths) async {
    // For new memories, use file-based storage instead of base64
    return await saveImagesToAppDirectory(imagePaths);
  }

  // Convert relative path to absolute path
  Future<String> getAbsolutePath(String relativePath) async {
    // If already absolute path, return as is
    if (relativePath.startsWith('/')) {
      return relativePath;
    }

    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$relativePath';
  }

  // Convert list of relative paths to absolute paths
  Future<List<String>> getAbsolutePaths(List<String> relativePaths) async {
    final List<String> absolutePaths = [];
    for (String path in relativePaths) {
      absolutePaths.add(await getAbsolutePath(path));
    }
    return absolutePaths;
  }

  // Save videos to app directory and return RELATIVE file paths
  Future<List<String>> saveVideosToAppDirectory(List<String> videoPaths) async {
    List<String> savedVideoPaths = [];

    try {
      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${appDir.path}/memory_videos');

      // Create videos directory if it doesn't exist
      if (!await videosDir.exists()) {
        await videosDir.create(recursive: true);
      }

      for (String videoPath in videoPaths) {
        try {
          final sourceFile = File(videoPath);
          if (await sourceFile.exists()) {
            // Generate unique filename
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final extension = videoPath.split('.').last.toLowerCase();
            final fileName =
                'memory_${timestamp}_${savedVideoPaths.length}.$extension';
            final targetPath = '${videosDir.path}/$fileName';

            // Copy original video to app directory
            await sourceFile.copy(targetPath);

            // Store RELATIVE path instead of absolute path
            savedVideoPaths.add('memory_videos/$fileName');

            debugPrint('Video saved to app directory: $fileName (relative path)');
          }
        } catch (e) {
          debugPrint('Error saving video: $e');
        }
      }
    } catch (e) {
      debugPrint('Error creating videos directory: $e');
    }

    return savedVideoPaths;
  }

  // Compress image to reduce memory usage
  Future<Uint8List> _compressImage(Uint8List bytes) async {
    try {
      // Decode the image
      final codec = await ui.instantiateImageCodec(
        bytes,
        // targetWidth: 800, // Limit width to 800px
        // targetHeight: 600, // Limit height to 600px
      );
      final frame = await codec.getNextFrame();

      // Convert back to bytes with compression
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return byteData!.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error compressing image: $e');
      // Return original bytes if compression fails but limit size
      // if (bytes.length > 1000000) { // If larger than 1MB
      //   // Simple size reduction by taking every nth byte (crude but effective)
      //   final step = (bytes.length / 500000).ceil(); // Target ~500KB
      //   final reducedBytes = <int>[];
      //   for (int i = 0; i < bytes.length; i += step) {
      //     reducedBytes.add(bytes[i]);
      //   }
      //   return Uint8List.fromList(reducedBytes);
      // }
      return bytes;
    }
  }

  Future<int> saveMemory({
    required String description,
    List<String>? imagePaths,
    List<String>? videoPaths,
    List<int>? imageOrders,
    List<int>? videoOrders,
    List<String>? tags,
    List<String>? mentions,
  }) async {
    debugPrint(
      '💾 Saving memory with ${imagePaths?.length ?? 0} images, ${videoPaths?.length ?? 0} videos, and ${recordedAudioPaths.length} audio files',
    );

    if (selectedDate.value == null || selectedTime.value == null) {
      throw Exception('Date and time are required');
    }

    // Validate that date/time is not in the future
    final selectedDateTime = DateTime(
      selectedDate.value!.year,
      selectedDate.value!.month,
      selectedDate.value!.day,
      selectedTime.value!.hour,
      selectedTime.value!.minute,
    );

    final now = DateTime.now();
    if (selectedDateTime.isAfter(now)) {
      throw Exception('Memory date and time cannot be in the future');
    }

    // Snapshot location before any await — validateAudioFiles / GPS / other work
    // can interleave and mutate reactive fields, which caused empty saves.
    final location = selectedLocation.value;
    var locationCountrySnap = locationCountry.value;
    var locationCitySnap = locationCity.value;
    var locationNameSnap = locationName.value;
    final locationAddressSnap = locationAddress.value;
    var locationFlagSnap = locationFlag.value;
    final locationLatitudeSnap = locationLatitude.value;
    final locationLongitudeSnap = locationLongitude.value;
    final category = selectedCategory.value;

    // Place category is optional - no validation needed
    // if (selectedCategory.value.isEmpty) {
    //   throw Exception('Place is required');
    // }

    // Validate audio files before saving
    await validateAudioFiles();
    debugPrint(
      '💾 After validation: ${recordedAudioPaths.length} valid audio files',
    );

    // Format date and time from MemoryInfoWidget
    final dateStr = DateFormat('yyyy-MM-dd').format(selectedDate.value!);
    final timeStr = selectedTime.value!.format(Get.context!);

    if (locationFlagSnap.trim() == '🌊') {
      final c = locationCountrySnap.trim().toLowerCase();
      final resolvedFlag = c.isNotEmpty ? countryFlags[c] : null;
      if (resolvedFlag != null && resolvedFlag.isNotEmpty) {
        locationFlagSnap = resolvedFlag;
      }

      if (locationNameSnap.trim().isEmpty) {
        final countryName = locationCountrySnap.trim();
        if (countryName.isNotEmpty) {
          locationNameSnap = countryName;
        }
      }
    }
    // Prepare memory data without images (images will be stored separately)
    final memory = {
      DatabaseHelper.columnDate: dateStr,
      DatabaseHelper.columnTime: timeStr,
      DatabaseHelper.columnLocation: location,
      DatabaseHelper.columnLocationCountry:
          locationCountrySnap.isNotEmpty ? locationCountrySnap : null,
      DatabaseHelper.columnLocationCity:
          locationCitySnap.isNotEmpty ? locationCitySnap : null,
      DatabaseHelper.columnLocationName:
          locationNameSnap.isNotEmpty ? locationNameSnap : null,
      DatabaseHelper.columnLocationAddress:
          locationAddressSnap.isNotEmpty ? locationAddressSnap : null,
      DatabaseHelper.columnLocationFlag:
          locationFlagSnap.isNotEmpty ? locationFlagSnap : null,
      DatabaseHelper.columnLocationLatitude: locationLatitudeSnap,
      DatabaseHelper.columnLocationLongitude: locationLongitudeSnap,
      DatabaseHelper.columnCategory: category,
      DatabaseHelper.columnDescription:
          description, // From MemoryDescriptionField
      DatabaseHelper.columnImagePath: null, // No longer storing images here
      DatabaseHelper.columnAudioPath:
          recordedAudioPaths.isNotEmpty
              ? recordedAudioPaths.join('|')
              : null, // Multiple audio files
      DatabaseHelper.columnTags: tags?.join(','), // From MemoryDescriptionField
      DatabaseHelper.columnMentions: mentions?.join(
        ',',
      ), // From MemoryDescriptionField
      DatabaseHelper.columnCreatedAt: DateTime.now().toIso8601String(),
    };

    // Check database health before proceeding
    if (!await _databaseHelper.isDatabaseHealthy()) {
      debugPrint('💾 Database unhealthy, attempting to reset connection...');
      await _databaseHelper.resetDatabaseConnection();
    }

    // Prepare image data if any
    List<String>? imageDataList;
    if (imagePaths != null && imagePaths.isNotEmpty) {
      imageDataList = await convertImagesToBase64(imagePaths);
      debugPrint('Prepared ${imageDataList.length} images for insertion');
    }

    // Prepare audio data if any
    List<Map<String, dynamic>>? audioDataList;
    if (recordedAudioPaths.isNotEmpty) {
      audioDataList = [];
      debugPrint(
        '💾 Preparing ${recordedAudioPaths.length} audio files for insertion...',
      );

      for (int i = 0; i < recordedAudioPaths.length; i++) {
        final audioPath = recordedAudioPaths[i];
        final duration = i < recordedAudios.length ? recordedAudios[i] : '0:00';

        // Convert relative path to absolute path for verification
        final absolutePath = await getAbsolutePath(audioPath);
        final file = File(absolutePath);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint(
            '💾 Prepared audio $i: $audioPath (relative) -> $absolutePath ($duration, $fileSize bytes)',
          );

          audioDataList.add({
            'path': audioPath, // Store RELATIVE path in database
            'duration': duration,
          });
        } else {
          debugPrint('❌ Audio file not found, skipping: $audioPath -> $absolutePath');
        }
      }

      debugPrint('✅ Prepared ${audioDataList.length} audio files for insertion');
    }

    // Prepare video data if any
    List<Map<String, dynamic>>? videoDataList;
    if (videoPaths != null && videoPaths.isNotEmpty) {
      // Save videos to app directory first
      final savedVideoPaths = await saveVideosToAppDirectory(videoPaths);
      debugPrint('💾 Saved ${savedVideoPaths.length} videos to app directory');

      videoDataList = [];
      debugPrint(
        '💾 Preparing ${savedVideoPaths.length} video files for insertion...',
      );

      for (int i = 0; i < savedVideoPaths.length; i++) {
        final videoPath = savedVideoPaths[i];

        // Convert relative path to absolute path for verification
        final absolutePath = await getAbsolutePath(videoPath);
        final file = File(absolutePath);
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint(
            '💾 Prepared video $i: $videoPath (relative) -> $absolutePath ($fileSize bytes)',
          );

          videoDataList.add({
            'path': videoPath, // Store RELATIVE path in database
            'duration': '', // Duration can be extracted later if needed
            'thumbnail': '', // Thumbnail path can be generated later if needed
          });
        } else {
          debugPrint('❌ Video file not found, skipping: $videoPath -> $absolutePath');
        }
      }

      debugPrint('✅ Prepared ${videoDataList.length} video files for insertion');
    }

    // Insert everything in a single transaction with error handling
    int memoryId;
    try {
      memoryId = await _databaseHelper.insertCompleteMemory(
        memoryData: memory,
        imageDataList: imageDataList,
        audioDataList: audioDataList,
        videoDataList: videoDataList,
        imageOrders: imageOrders,
        videoOrders: videoOrders,
      );

      debugPrint('💾 Complete memory saved successfully with ID: $memoryId');
    } catch (e) {
      debugPrint('💾 Error saving memory: $e');

      // Try to reset database connection and retry once
      try {
        debugPrint('💾 Attempting database recovery and retry...');
        await _databaseHelper.resetDatabaseConnection();

        memoryId = await _databaseHelper.insertCompleteMemory(
          memoryData: memory,
          imageDataList: imageDataList,
          audioDataList: audioDataList,
          videoDataList: videoDataList,
          imageOrders: imageOrders,
          videoOrders: videoOrders,
        );

        debugPrint('💾 Memory saved successfully after recovery with ID: $memoryId');
      } catch (retryError) {
        debugPrint('💾 Failed to save memory even after recovery: $retryError');
        throw Exception('Unable to save memory. Please try again.');
      }
    }

    final result = memoryId;

    // Clear audio recordings after successful save
    clearAudioRecordings();

    return result;
  }

  // Method to clear audio recordings
  void clearAudioRecordings() {
    recordedAudios.clear();
    recordedAudioPaths.clear();
    recordingDuration.value = '0:00';
    _recordingSeconds = 0;
    isRecording.value = false;
    isPlaying.value = false;

    // Cancel any active recording timer
    _recordingTimer?.cancel();
    _recordingTimer = null;

    // Force UI refresh
    recordedAudios.refresh();
    recordedAudioPaths.refresh();

    debugPrint('Audio recordings cleared completely');
  }

  double? get latitude {
    if (selectedLocation.value.isEmpty) return null;
    final parts = selectedLocation.value.split(',');
    if (parts.length != 2) return null;
    return double.tryParse(parts[0].trim());
  }

  double? get longitude {
    if (selectedLocation.value.isEmpty) return null;
    final parts = selectedLocation.value.split(',');
    if (parts.length != 2) return null;
    return double.tryParse(parts[1].trim());
  }

  Future<List<Map<String, dynamic>>> getAllMemories() async {
    return await _databaseHelper.queryAllMemories();
  }

  Future<List<Map<String, dynamic>>> getMemoriesByDate(DateTime date) async {
    return await _databaseHelper.getMemoriesByDate(date);
  }

  Future<Map<String, dynamic>?> getMemory(int id) async {
    return await _databaseHelper.queryMemory(id);
  }

  /// Load enhanced location data from a memory into the controller
  void loadEnhancedLocationFromMemory(Map<String, dynamic> memory) {
    // Load enhanced location data
    locationCountry.value = memory['location_country'] ?? '';
    locationCity.value = memory['location_city'] ?? '';
    locationName.value = memory['location_name'] ?? '';
    locationAddress.value = memory['location_address'] ?? '';
    locationFlag.value = memory['location_flag'] ?? '';
    locationLatitude.value = memory['location_latitude']?.toDouble();
    locationLongitude.value = memory['location_longitude']?.toDouble();

    // Always set selectedLocation as lat,lng coordinates
    if (locationLatitude.value != null && locationLongitude.value != null) {
      selectedLocation.value =
          '${locationLatitude.value},${locationLongitude.value}';
    } else {
      // Fallback to original location field if coordinates not available
      selectedLocation.value = memory['location'] ?? '';
    }

    debugPrint('📍 Loaded enhanced location data from memory:');
    debugPrint(
      '📍 Country: ${locationCountry.value}, City: ${locationCity.value}',
    );
    debugPrint('📍 Coordinates: ${selectedLocation.value}');
  }

  Future<int> updateMemory(int id, Map<String, dynamic> updatedData) async {
    updatedData['id'] = id;

    // Include enhanced location data only when caller did not already supply keys
    // (avoids overwriting snapshots taken before async validation).
    if (!updatedData.containsKey(DatabaseHelper.columnLocationCountry) &&
        locationCountry.value.isNotEmpty) {
      updatedData[DatabaseHelper.columnLocationCountry] = locationCountry.value;
    }
    if (!updatedData.containsKey(DatabaseHelper.columnLocationCity) &&
        locationCity.value.isNotEmpty) {
      updatedData[DatabaseHelper.columnLocationCity] = locationCity.value;
    }
    if (!updatedData.containsKey(DatabaseHelper.columnLocationName) &&
        locationName.value.isNotEmpty) {
      updatedData[DatabaseHelper.columnLocationName] = locationName.value;
    }
    if (!updatedData.containsKey(DatabaseHelper.columnLocationAddress) &&
        locationAddress.value.isNotEmpty) {
      updatedData[DatabaseHelper.columnLocationAddress] = locationAddress.value;
    }
    if (!updatedData.containsKey(DatabaseHelper.columnLocationFlag) &&
        locationFlag.value.isNotEmpty) {
      updatedData[DatabaseHelper.columnLocationFlag] = locationFlag.value;
    }
    if (!updatedData.containsKey(DatabaseHelper.columnLocationLatitude) &&
        locationLatitude.value != null) {
      updatedData[DatabaseHelper.columnLocationLatitude] =
          locationLatitude.value;
    }
    if (!updatedData.containsKey(DatabaseHelper.columnLocationLongitude) &&
        locationLongitude.value != null) {
      updatedData[DatabaseHelper.columnLocationLongitude] =
          locationLongitude.value;
    }

    return await _databaseHelper.updateMemory(updatedData);
  }

  Future<int> deleteMemory(int id) async {
    return await _databaseHelper.deleteMemory(id);
  }

  Future<void> addNewTag(String tag) async {
    final newTag = tag.trim().toLowerCase();
    if (newTag.isEmpty) return;
    await _databaseHelper.insertTag(newTag);
    existingTags.value = await _databaseHelper.getPopularTags();
  }

  Future<void> addNewMention(String mention) async {
    final newMention = mention.trim().toLowerCase();
    if (newMention.isEmpty) return;
    await _databaseHelper.insertMention(newMention);
    existingMentions.value = await _databaseHelper.getPopularMentions();
  }

  Future<void> _loadSavedCategories() async {
    existingCategories.value = await _databaseHelper.getPopularCategories();
  }

  Future<void> addNewCategory(String category) async {
    final newCategory = category.trim().toLowerCase();
    if (newCategory.isEmpty) return;
    await _databaseHelper.insertCategory(newCategory);
    existingCategories.value = await _databaseHelper.getPopularCategories();
  }

  Future<List<String>> searchCategories(String query) async {
    if (query.trim().isEmpty) {
      return existingCategories.take(20).toList();
    }
    return await _databaseHelper.searchCategories(query);
  }

  Future<List<Map<String, dynamic>>> searchMemories(String query) async {
    return await _databaseHelper.searchMemories(query);
  }

  // Audio recording methods
  Future<void> startRecording() async {
    try {
      debugPrint('🎤 Attempting to start audio recording...');

      final micStatus = await Permission.microphone.request();
      debugPrint('🎤 Microphone permission status: $micStatus');

      if (!micStatus.isGranted) {
        debugPrint('❌ Microphone permission not granted');
        final ctx = Get.context;
        if (ctx != null && ctx.mounted) {
          await showPermissionOpenSettingsDialog(
            ctx,
            title: 'title_literal_microphone_access_needed'.tr,
            message: 'dialog_content_permission_microphone_record'.tr,
          );
        }
        return;
      }

      // Create audio directory in app private storage
      final directory = await getApplicationDocumentsDirectory();
      final audioDir = Directory('${directory.path}/audio_files');

      debugPrint('🎤 Audio directory path: ${audioDir.path}');

      if (!await audioDir.exists()) {
        await audioDir.create(recursive: true);
        debugPrint('🎤 Created audio directory');
      }

      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final filePath = '${audioDir.path}/$fileName';
      final relativePath = 'audio_files/$fileName'; // Store relative path

      debugPrint('🎤 Recording to file: $filePath (relative: $relativePath)');

      // Start recording with enhanced config
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1, // Mono recording for smaller file size
        ),
        path: filePath,
      );

      isRecording.value = true;
      _recordingSeconds = 0;
      recordingDuration.value = '0:00';

      // Start recording timer
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingSeconds++;
        final minutes = _recordingSeconds ~/ 60;
        final seconds = _recordingSeconds % 60;
        recordingDuration.value =
            '$minutes:${seconds.toString().padLeft(2, '0')}';
      });

      debugPrint('✅ Recording started successfully: $filePath');

      // Show recording started feedback
      // Get.snackbar(
      //   'Recording Started',
      //   'Audio recording in progress...',
      //   backgroundColor: Colors.green.shade400,
      //   colorText: Colors.white,
      //   margin: const EdgeInsets.all(12),
      //   snackPosition: SnackPosition.BOTTOM,
      //   duration: const Duration(seconds: 2),
      // );
    } catch (e) {
      debugPrint('❌ Error starting recording: $e');
      debugPrint('❌ Error type: ${e.runtimeType}');

      showTrSnackbar('snackbar_recording_error', args: [e.toString()], 
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),);
    }
  }

  Future<void> stopRecording() async {
    try {
      debugPrint('🎤 Stopping audio recording...');

      final path = await _audioRecorder.stop();
      _recordingTimer?.cancel();
      isRecording.value = false;

      debugPrint('🎤 Recording stopped, path: $path');

      if (path != null) {
        final file = File(path);
        final exists = await file.exists();

        debugPrint('🎤 File exists: $exists');

        if (exists) {
          final fileSize = await file.length();
          debugPrint('🎤 File size: $fileSize bytes');

          if (fileSize > 0) {
            // Check if recording duration is at least 1 second
            final durationParts = recordingDuration.value.split(':');
            final minutes = int.tryParse(durationParts[0]) ?? 0;
            final seconds = int.tryParse(durationParts[1]) ?? 0;
            final totalSeconds = (minutes * 60) + seconds;

            if (totalSeconds < 1) {
              debugPrint(
                '❌ Recording too short (${recordingDuration.value}), not saving',
              );

              // Delete the short recording file
              try {
                await file.delete();
                debugPrint('🗑️ Deleted short audio file');
              } catch (deleteError) {
                debugPrint('❌ Error deleting short file: $deleteError');
              }

              // Reset recording duration and seconds
              recordingDuration.value = '0:00';
              _recordingSeconds = 0;
              debugPrint('🔄 Recording duration reset to 0:00 (too short)');

              showTrSnackbar('snackbar_recording_too_short', 
                backgroundColor: Colors.orange.shade400,
                colorText: Colors.white,
                margin: const EdgeInsets.all(12),
                snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),);
            } else {
              // Convert absolute path to relative path for storage
              final appDir = await getApplicationDocumentsDirectory();
              String pathToStore = path;
              if (path.startsWith(appDir.path)) {
                // Extract relative path
                pathToStore = path.substring(appDir.path.length + 1); // +1 to remove leading slash
                debugPrint('🎤 Converted to relative path: $pathToStore');
              }

              // Store both the duration for display and the RELATIVE file path for database
              recordedAudios.add(recordingDuration.value);
              recordedAudioPaths.add(pathToStore);

              debugPrint('✅ Recording saved successfully:');
              debugPrint('  Absolute Path: $path');
              debugPrint('  Relative Path: $pathToStore');
              debugPrint('  Duration: ${recordingDuration.value}');
              debugPrint('  Size: $fileSize bytes');
              debugPrint('  Total recordings: ${recordedAudios.length}');

              // Reset recording duration and seconds after successful save
              recordingDuration.value = '0:00';
              _recordingSeconds = 0;
              debugPrint('🔄 Recording duration reset to 0:00');

              // // Show success feedback
              // Get.snackbar(
              //   'Recording Saved',
              //   'Audio recorded successfully (${recordingDuration.value})',
              //   backgroundColor: Colors.green.shade400,
              //   colorText: Colors.white,
              //   margin: const EdgeInsets.all(12),
              //   snackPosition: SnackPosition.BOTTOM,
              //   duration: const Duration(seconds: 2),
              // );
            }
          } else {
            debugPrint('❌ Audio file is empty (0 bytes)');
            // Delete the empty file
            try {
              await file.delete();
              debugPrint('🗑️ Deleted empty audio file');
            } catch (deleteError) {
              debugPrint('❌ Error deleting empty file: $deleteError');
            }

            // Reset recording duration and seconds
            recordingDuration.value = '0:00';
            _recordingSeconds = 0;
            debugPrint('🔄 Recording duration reset to 0:00 (empty file)');

            showTrSnackbar('snackbar_recording_failed', 
              backgroundColor: Colors.orange.shade400,
              colorText: Colors.white,
              margin: const EdgeInsets.all(12),
              snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),);
          }
        } else {
          debugPrint('❌ Audio file does not exist after recording');

          // Reset recording duration and seconds
          recordingDuration.value = '0:00';
          _recordingSeconds = 0;
          debugPrint('🔄 Recording duration reset to 0:00 (file not found)');

          showTrSnackbar('snackbar_recording_failed_2', 
            backgroundColor: Colors.red.shade400,
            colorText: Colors.white,
            margin: const EdgeInsets.all(12),
            snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),);
        }
      } else {
        debugPrint('❌ Recording path is null');

        // Reset recording duration and seconds
        recordingDuration.value = '0:00';
        _recordingSeconds = 0;
        debugPrint('🔄 Recording duration reset to 0:00 (path is null)');

        showTrSnackbar('snackbar_recording_failed_3', 
          backgroundColor: Colors.red.shade400,
          colorText: Colors.white,
          margin: const EdgeInsets.all(12),
          snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),);
      }
    } catch (e) {
      debugPrint('❌ Error stopping recording: $e');
      debugPrint('❌ Error type: ${e.runtimeType}');

      isRecording.value = false;
      _recordingTimer?.cancel();

      showTrSnackbar('snackbar_recording_error_2', args: [e.toString()], 
        backgroundColor: Colors.red.shade400,
        colorText: Colors.white,
        margin: const EdgeInsets.all(12),
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),);
    }
  }

  void reorderAudio(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final duration = recordedAudios.removeAt(oldIndex);
    recordedAudios.insert(newIndex, duration);
    if (oldIndex < recordedAudioPaths.length) {
      final path = recordedAudioPaths.removeAt(oldIndex);
      recordedAudioPaths.insert(newIndex, path);
    }
    recordedAudios.refresh();
    recordedAudioPaths.refresh();
  }

  void removeAudio(int index) async {
    if (index >= 0 && index < recordedAudios.length) {
      // Remove the audio file from storage
      if (index < recordedAudioPaths.length) {
        final filePath = recordedAudioPaths[index];
        try {
          // Convert relative path to absolute path if needed
          final absolutePath = await getAbsolutePath(filePath);
          final file = File(absolutePath);
          if (file.existsSync()) {
            file.deleteSync();
            debugPrint('🗑️ Audio file deleted: $absolutePath');
          }
        } catch (e) {
          debugPrint('❌ Error deleting audio file: $e');
        }
        recordedAudioPaths.removeAt(index);
      }
      recordedAudios.removeAt(index);

      // Force UI update
      recordedAudios.refresh();
      recordedAudioPaths.refresh();

      debugPrint('🗑️ Audio removed. Remaining: ${recordedAudios.length}');
    }
  }

  // Method to validate all recorded audio files
  Future<void> validateAudioFiles() async {
    debugPrint('🔍 Validating ${recordedAudioPaths.length} audio files...');

    final validPaths = <String>[];
    final validDurations = <String>[];

    for (int i = 0; i < recordedAudioPaths.length; i++) {
      final path = recordedAudioPaths[i];
      final duration = i < recordedAudios.length ? recordedAudios[i] : '0:00';

      try {
        // Convert relative path to absolute path if needed
        final absolutePath = await getAbsolutePath(path);
        final file = File(absolutePath);
        if (await file.exists()) {
          final size = await file.length();
          if (size > 0) {
            validPaths.add(path); // Store relative path
            validDurations.add(duration);
            debugPrint('✅ Valid audio file: $path -> $absolutePath ($size bytes)');
          } else {
            debugPrint('❌ Empty audio file: $absolutePath');
            // Delete empty file
            try {
              await file.delete();
            } catch (e) {
              debugPrint('❌ Error deleting empty file: $e');
            }
          }
        } else {
          debugPrint('❌ Audio file not found: $path -> $absolutePath');
        }
      } catch (e) {
        debugPrint('❌ Error validating audio file $path: $e');
      }
    }

    // Update lists with only valid files
    recordedAudioPaths.clear();
    recordedAudios.clear();
    recordedAudioPaths.addAll(validPaths);
    recordedAudios.addAll(validDurations);

    debugPrint(
      '🔍 Validation complete: ${validPaths.length}/${recordedAudioPaths.length} files valid',
    );
  }

  // Method to clear all controller data after saving memory
  void clearAllData() {
    // Clear audio recordings
    clearAudioRecordings();

    // Reset memory info fields
    selectedDate.value = DateTime.now();
    selectedTime.value = TimeOfDay.fromDateTime(DateTime.now());
    selectedLocation.value = '';
    selectedCategory.value = '';

    // Clear enhanced location data
    locationCountry.value = '';
    locationCity.value = '';
    locationName.value = '';
    locationAddress.value = '';
    locationFlag.value = '';
    locationLatitude.value = null;
    locationLongitude.value = null;
    lastResolvedLocationPermission.value = null;

    // Reset popup controls
    isPopupOpen.value = false;
    triggerChar.value = '';
    keyword.value = '';

    debugPrint('Controller data cleared after saving memory');
  }

  /// Offline reverse geocode (same pipeline as memory / location picker).
  Future<Map<String, dynamic>?> reverseGeocodeCoordinates(
    double latitude,
    double longitude,
  ) {
    return _getLocationDetailsFromCoordinates(latitude, longitude);
  }

  /// One memory from KMZ/GPX track import: [date]/[time] and [created_at] use [when];
  /// location fields match [saveMemory] after geocoding.
  Future<int> saveImportedTrackMemory({
    required DateTime when,
    required double latitude,
    required double longitude,
    String description = '',
    String? trackImportFingerprint,
  }) async {
    // Keep KMZ/GPX point timestamp per memory exactly as parsed.
    final w = when.toLocal();

    final ctx = Get.context;
    if (ctx == null) {
      throw Exception('Missing context for time formatting');
    }

    final dateStr = DateFormat('yyyy-MM-dd').format(w);
    final timeStr = TimeOfDay.fromDateTime(w).format(ctx);

    final loc =
        '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

    final geo = await reverseGeocodeCoordinates(latitude, longitude);
    var locationCountrySnap = geo?['country'] as String? ?? '';
    var locationCitySnap = geo?['city'] as String? ?? '';
    var locationNameSnap = geo?['name'] as String? ?? '';
    final locationAddressSnap = geo?['address'] as String? ?? '';
    var locationFlagSnap = geo?['flag'] as String? ?? '';

    if (locationFlagSnap.trim() == '🌊') {
      final c = locationCountrySnap.trim().toLowerCase();
      final resolvedFlag = c.isNotEmpty ? countryFlags[c] : null;
      if (resolvedFlag != null && resolvedFlag.isNotEmpty) {
        locationFlagSnap = resolvedFlag;
      }

      if (locationNameSnap.trim().isEmpty) {
        final countryName = locationCountrySnap.trim();
        if (countryName.isNotEmpty) {
          locationNameSnap = countryName;
        }
      }
    }

    final memory = <String, dynamic>{
      DatabaseHelper.columnDate: dateStr,
      DatabaseHelper.columnTime: timeStr,
      DatabaseHelper.columnLocation: loc,
      DatabaseHelper.columnLocationCountry:
          locationCountrySnap.isNotEmpty ? locationCountrySnap : null,
      DatabaseHelper.columnLocationCity:
          locationCitySnap.isNotEmpty ? locationCitySnap : null,
      DatabaseHelper.columnLocationName:
          locationNameSnap.isNotEmpty ? locationNameSnap : null,
      DatabaseHelper.columnLocationAddress:
          locationAddressSnap.isNotEmpty ? locationAddressSnap : null,
      DatabaseHelper.columnLocationFlag:
          locationFlagSnap.isNotEmpty ? locationFlagSnap : null,
      DatabaseHelper.columnLocationLatitude: latitude,
      DatabaseHelper.columnLocationLongitude: longitude,
      DatabaseHelper.columnCategory: selectedCategory.value,
      DatabaseHelper.columnDescription: description,
      DatabaseHelper.columnImagePath: null,
      DatabaseHelper.columnAudioPath: null,
      DatabaseHelper.columnTags: null,
      DatabaseHelper.columnMentions: null,
      DatabaseHelper.columnCreatedAt: w.toIso8601String(),
      DatabaseHelper.columnUpdatedAt: DateTime.now().toIso8601String(),
      DatabaseHelper.columnTrackImportFingerprint: trackImportFingerprint,
    };

    if (!await _databaseHelper.isDatabaseHealthy()) {
      await _databaseHelper.resetDatabaseConnection();
    }

    return _databaseHelper.insertCompleteMemory(memoryData: memory);
  }

  @override
  void onClose() {
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    super.onClose();
  }
}

class TagMentionController extends GetxController {
  final RxList<String> existingTags = <String>[].obs;
  final RxList<String> existingMentions = <String>[].obs;
  final RxList<Map<String, dynamic>> filteredItems = <Map<String, dynamic>>[].obs;
  final RxList<Map<String, dynamic>> allItems = <Map<String, dynamic>>[].obs;

  final RxBool isEditing = false.obs;
  final RxString editingItem = ''.obs;
  final RxString originalItem = ''.obs;
  final RxString searchQuery = ''.obs;

  final bool isTagMode;
  final List<String>? excludedItems; // Items already added to the description
  final String? initialKeyword; // Initial keyword when opening the bottom sheet
  final bool isEditingExisting; // True when editing an existing hashtag/mention

  TagMentionController({
    required this.isTagMode,
    this.excludedItems,
    this.initialKeyword,
    this.isEditingExisting = false,
  });

  @override
  void onInit() {
    super.onInit();
    loadSavedItems();
  }

  Future<void> loadSavedItems() async {
    if (isTagMode) {
      await _loadHashtagGroups();
    } else {
      await _loadContactGroups();
    }
    // If there's an initial keyword, filter by it immediately to show search results
    // Otherwise show all items (recents)
    filterItems(initialKeyword ?? '');
  }

  Future<void> _loadHashtagGroups() async {
    try {
      final hashtagGroupService = HashtagGroupService();
      final hierarchicalGroups = await hashtagGroupService.getAllGroupsHierarchical();

      final List<Map<String, dynamic>> items = [];

      for (final mainGroup in hierarchicalGroups) {
        // Add main group as an item
        items.add({
          'type': 'main_group',
          'name': mainGroup.name,
          'parentName': '',
          'id': mainGroup.id,
          'parentId': null,
        });

        // Add all subcategories
        if (mainGroup.subgroups != null && mainGroup.subgroups!.isNotEmpty) {
          for (final subgroup in mainGroup.subgroups!) {
            items.add({
              'type': 'subgroup',
              'name': subgroup.name,
              'parentName': mainGroup.name,
              'id': subgroup.id,
              'parentId': mainGroup.id,
            });
          }
        }
      }

      allItems.value = items;
      filteredItems.value = items;
    } catch (e) {
      debugPrint('[TagMentionController] Error loading hashtag groups: $e');
      // Fallback to existing tags
      final memoryController = Get.find<MemoryController>();
      existingTags.value = memoryController.existingTags;
      final legacyItems = existingTags.map((tag) => {
        'type': 'legacy',
        'name': tag,
        'parentName': '',
        'id': null,
        'parentId': null,
      }).toList();
      allItems.value = legacyItems;
      filteredItems.value = legacyItems;
    }
  }

  Future<void> _loadContactGroups() async {
    try {
      final contactGroupService = ContactGroupService();
      final hierarchicalGroups = await contactGroupService.getAllGroupsHierarchical();

      final List<Map<String, dynamic>> items = [];

      for (final mainGroup in hierarchicalGroups) {
        // Add main group as an item
        items.add({
          'type': 'main_group',
          'name': mainGroup.name,
          'parentName': '',
          'id': mainGroup.id,
          'parentId': null,
        });

        // Add all subcategories
        if (mainGroup.subgroups != null && mainGroup.subgroups!.isNotEmpty) {
          for (final subgroup in mainGroup.subgroups!) {
            items.add({
              'type': 'subgroup',
              'name': subgroup.name,
              'parentName': mainGroup.name,
              'id': subgroup.id,
              'parentId': mainGroup.id,
            });
          }
        }
      }

      allItems.value = items;
      filteredItems.value = items;
    } catch (e) {
      debugPrint('[TagMentionController] Error loading contact groups: $e');
      // Fallback to existing mentions
      final memoryController = Get.find<MemoryController>();
      existingMentions.value = memoryController.existingMentions;
      final legacyItems = existingMentions.map((mention) => {
        'type': 'legacy',
        'name': mention,
        'parentName': '',
        'id': null,
        'parentId': null,
      }).toList();
      allItems.value = legacyItems;
      filteredItems.value = legacyItems;
    }
  }

  void filterItems(String query) {
    searchQuery.value = query;

    List<Map<String, dynamic>> items;

    if (query.trim().isEmpty) {
      // Show all items when query is empty
      items = List<Map<String, dynamic>>.from(allItems);
    } else {
      final queryLower = query.trim().toLowerCase();
      items = allItems
          .where((item) =>
              item['name'].toString().toLowerCase().contains(queryLower) ||
              item['parentName'].toString().toLowerCase().contains(queryLower))
          .toList();
    }

    // Note: We no longer filter out excluded items here - they will be shown in the list
    // but without the "add" button (handled in the UI layer)

    filteredItems.value = items;
  }

  Future<void> addNewItem(String value, Function(String) onItemSelected) async {
    final newItem = value.trim();
    if (newItem.isEmpty) return;

    final memoryController = Get.find<MemoryController>();
    if (isTagMode) {
      await memoryController.addNewTag(newItem);
    } else {
      await memoryController.addNewMention(newItem);
    }

    filterItems(searchQuery.value);
    onItemSelected('${isTagMode ? '#' : '@'}$newItem');
  }

  void startEditing(String item) {
    isEditing.value = true;
    final plainItem =
        item.startsWith('#') || item.startsWith('@') ? item.substring(1) : item;
    originalItem.value = plainItem;
    editingItem.value = plainItem;
  }

  Future<void> saveEditedItem(String newItem) async {
    final memoryController = Get.find<MemoryController>();
    final list =
        isTagMode
            ? memoryController.existingTags
            : memoryController.existingMentions;
    final oldItem = originalItem.value;
    final trimmedNewItem = newItem.trim();

    if (trimmedNewItem.isEmpty) {
      cancelEditing();
      return;
    }

    final index = list.indexOf(oldItem);
    if (index != -1) {
      list[index] = trimmedNewItem;
      filterItems(searchQuery.value);
    }
    cancelEditing();
  }

  Future<void> deleteItem(String item) async {
    final unprefixed =
        item.startsWith('#') || item.startsWith('@') ? item.substring(1) : item;
    final memoryController = Get.find<MemoryController>();

    if (isTagMode) {
      memoryController.existingTags.remove(unprefixed);
    } else {
      memoryController.existingMentions.remove(unprefixed);
    }

    filterItems(searchQuery.value);
  }

  void cancelEditing() {
    isEditing.value = false;
    editingItem.value = '';
    originalItem.value = '';
  }
}
