import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/services/geocoding_isolate_service.dart';
import 'package:spacetime/app/modules/location_picker/services/location_picker_service.dart';
import 'package:spacetime/app/utils/place_categories_utils.dart';

enum MemoryLocationPickerState {
  loading,
  ready,
  error,
  searchingLocation,
  movingToLocation,
}

class MemoryLocationPickerWidget extends StatefulWidget {
  const MemoryLocationPickerWidget({super.key});

  @override
  State<MemoryLocationPickerWidget> createState() => _MemoryLocationPickerWidgetState();
}

class _MemoryLocationPickerWidgetState extends State<MemoryLocationPickerWidget> {
  final MemoryController memoryController = Get.find<MemoryController>();
  final UiController uiController = Get.find<UiController>();
  final LocationPickerService _locationPickerService = LocationPickerService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final RxBool _showSearchResults = false.obs;
  
  // State management
  final Rx<MemoryLocationPickerState> state = MemoryLocationPickerState.loading.obs;
  final RxString errorMessage = ''.obs;
  final RxBool hasLocationPermission = false.obs;
  final RxBool isOfflineMode = false.obs;
  final Rxn<Position> currentPosition = Rxn<Position>();
  final RxBool isSearching = false.obs;
  final RxList<Map<String, dynamic>> searchResults = <Map<String, dynamic>>[].obs;
  
  // Map components
  mapbox.MapboxMap? mapController;
  mapbox.PointAnnotationManager? annotationManager;
  mapbox.PointAnnotation? selectedLocationMarker;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _searchController.addListener(_onSearchChanged);
    _initializeLocationPicker();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Initialize location picker
  Future<void> _initializeLocationPicker() async {
    try {
      state.value = MemoryLocationPickerState.loading;
      
      // Check location permission
      await _checkLocationPermission();
      
      // Get current location if permission is available
      if (hasLocationPermission.value) {
        await _getCurrentLocation();
      }
      
      state.value = MemoryLocationPickerState.ready;
    } catch (e) {
      debugPrint('Error initializing location picker: $e');
      errorMessage.value = 'Failed to initialize location picker: $e';
      state.value = MemoryLocationPickerState.error;
    }
  }

  /// Check location permission
  Future<void> _checkLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      hasLocationPermission.value = permission == LocationPermission.whileInUse || 
                                   permission == LocationPermission.always;
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      hasLocationPermission.value = false;
    }
  }

  /// Get current location
  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      currentPosition.value = position;
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Obx(() => _buildBody()),
      ),
    );
  }

  /// Build main body
  Widget _buildBody() {
    switch (state.value) {
      case MemoryLocationPickerState.loading:
        return _buildLoadingView();
      case MemoryLocationPickerState.error:
        return _buildErrorView();
      default:
        return _buildMapView();
    }
  }

  /// Build loading view
  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading map...'),
        ],
      ),
    );
  }

  /// Build error view
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            'Error',
            style: AppFonts.medium(18, color: Colors.red),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage.value,
            textAlign: TextAlign.center,
            style: AppFonts.regular(14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _initializeLocationPicker,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Build map view
  Widget _buildMapView() {
    return Stack(
      children: [
        // Map
        _buildMap(),
        // Top search bar
        _buildTopSearchBar(),
        // Search results dropdown
        _buildSearchResultsOverlay(),
        // Current location button
        _buildCurrentLocationButton(),
        // Bottom action buttons
        _buildBottomActionButtons(),
      ],
    );
  }

  /// Build map widget
  Widget _buildMap() {
    return mapbox.MapWidget(
      key: const ValueKey('memory_location_picker_map'),
      cameraOptions: _getCameraOptions(),
      styleUri: mapbox.MapboxStyles.STANDARD,
      textureView: true,
      onMapCreated: _onMapCreated,
      onTapListener: _onMapTap,
    );
  }

  /// Get camera options
  mapbox.CameraOptions? _getCameraOptions() {
    if (currentPosition.value != null) {
      return mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            currentPosition.value!.longitude,
            currentPosition.value!.latitude,
          ),
        ),
        zoom: 14.0,
      );
    }
    return null;
  }

  /// Build top search bar - matching new location picker design
  Widget _buildTopSearchBar() {
    return Positioned(
      top: 50,
      left: 4,
      right: hasLocationPermission.value && currentPosition.value != null ? 60 : 4,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: uiController.darkMode.value
              ? Colors.black.withValues(alpha: 0.8)
              : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Obx(() => Row(
          children: [
            Image.asset(
              AppImages.searchNormal,
              width: 20,
              height: 20,
              color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSearchField(),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  searchResults.clear();
                  _showSearchResults.value = false;
                  _searchFocusNode.unfocus();
                },
                child: Icon(
                  Icons.clear,
                  size: 20,
                  color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600],
                ),
              ),
          ],
        )),
      ),
    );
  }

  /// Build search text field
  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: false,
      textInputAction: TextInputAction.search,
      style: AppFonts.medium(
        16,
        color: uiController.darkMode.value ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        hintText: 'Search locations...',
        hintStyle: AppFonts.regular(
          16,
          color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 2),
      ),
      onTap: () {
        if (!_showSearchResults.value) {
          _showSearchResults.value = true;
        }
      },
    );
  }

  /// Build search results overlay - matching new location picker design
  Widget _buildSearchResultsOverlay() {
    return Obx(() {
      if (!_showSearchResults.value ||
          (_searchController.text.isEmpty && searchResults.isEmpty && !isSearching.value)) {
        return const SizedBox.shrink();
      }

      return Positioned(
        top: 98, // Below search bar
        left: 4,
        right: hasLocationPermission.value && currentPosition.value != null ? 60 : 4,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: uiController.darkMode.value
                ? Colors.black.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: _buildSearchResultsContent(),
        ),
      );
    });
  }

  /// Build search results content - matching new location picker design
  Widget _buildSearchResultsContent() {
    if (isSearching.value) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: CircularProgressIndicator(
            color: uiController.primaryColor,
          ),
        ),
      );
    }

    if (searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'No locations found',
          style: AppFonts.medium(
            14,
            color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: searchResults.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: uiController.darkMode.value
            ? Colors.grey[700]!
            : Colors.grey[300]!,
      ),
      itemBuilder: (context, index) {
        final result = searchResults[index];
        return _buildSearchResultItem(result);
      },
    );
  }

  /// Build individual search result item - matching new location picker design
  Widget _buildSearchResultItem(Map<String, dynamic> result) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _selectSearchResult(result);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result['name'] ?? 'Unknown Location',
                style: AppFonts.medium(
                  16,
                  color: uiController.darkMode.value ? Colors.white : Colors.black87,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (result['address'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  result['address'],
                  style: AppFonts.regular(
                    14,
                    color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600]!,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Build current location button - matching new location picker design
  Widget _buildCurrentLocationButton() {
    if (!hasLocationPermission.value || currentPosition.value == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 50,
      right: 4,
      child: GestureDetector(
        onTap: _moveToCurrentLocation,
        child: Container(
          padding: const EdgeInsets.all(6),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(AppImages.rectangle),
              fit: BoxFit.cover,
              colorFilter: uiController.rectangleColorFilter,
            ),
          ),
          child: Image.asset(
            AppImages.location,
            fit: BoxFit.contain,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// Build bottom action buttons - matching new location picker design
  Widget _buildBottomActionButtons() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      bottom: _searchFocusNode.hasFocus ? -100 : 30, // Hide when search is focused
      left: 20,
      right: 20,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _searchFocusNode.hasFocus ? 0.0 : 1.0, // Fade out when search is focused
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Close button
            _buildBottomButton(
              iconPath: 'assets/images/ic_cross.png',
              onTap: () => Get.back(),
            ),
            // Done button
            _buildBottomButton(
              iconPath: 'assets/images/ic_tick.png',
              onTap: _onDonePressed,
            ),
          ],
        ),
      ),
    );
  }

  /// Build individual bottom button - matching new location picker design
  Widget _buildBottomButton({
    required String iconPath,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Image.asset(
            iconPath,
            width: 24,
            height: 24,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }



  /// Handle search focus changes
  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus) {
      _showSearchResults.value = true;
    } else {
      // Only hide if search is empty
      if (_searchController.text.isEmpty) {
        _showSearchResults.value = false;
      }
    }
    // Trigger rebuild for button animation
    setState(() {});
  }

  /// Handle search text changes
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      _performLocationSearch(query);
    } else {
      _showSearchResults.value = false;
      searchResults.clear();
    }
  }

  /// Handle map creation
  Future<void> _onMapCreated(mapbox.MapboxMap controller) async {
    try {
      mapController = controller;

      // Configure offline map support
      await _configureOfflineMap(controller);

      // Create annotation manager
      annotationManager = await controller.annotations.createPointAnnotationManager();

      // Move to current location if available
      if (currentPosition.value != null) {
        await _moveToLocation(
          currentPosition.value!.latitude,
          currentPosition.value!.longitude,
        );
      }
    } catch (e) {
      debugPrint('Error in onMapCreated: $e');
    }
  }

  /// Configure map for offline use
  Future<void> _configureOfflineMap(mapbox.MapboxMap controller) async {
    try {
      // Check if offline tiles are available
      final hasOfflineTiles = await _areOfflineTilesAvailable();

      if (hasOfflineTiles) {
        debugPrint('[MemoryLocationPicker] 🗺️ Configuring map for offline mode');
        isOfflineMode.value = true;

        // Map already uses MAPBOX_STREETS style which matches downloaded tiles
        // No need to change style URI - tiles will be used automatically

        debugPrint('[MemoryLocationPicker] ✅ Offline mode configured - using downloaded tiles');
      } else {
        debugPrint('[MemoryLocationPicker] 🌐 Using online mode - insufficient tiles');
        isOfflineMode.value = false;
      }
    } catch (e) {
      debugPrint('[MemoryLocationPicker] ❌ Error configuring offline map: $e');
      isOfflineMode.value = false;
    }
  }

  /// Check if offline tiles are available
  Future<bool> _areOfflineTilesAvailable() async {
    try {
      // Check if offline mode is enabled
      // This is managed by the offline map service
      return isOfflineMode.value;
    } catch (e) {
      debugPrint('[MemoryLocationPicker] ❌ Error checking offline tiles: $e');
      return false;
    }
  }

  /// Handle map tap - show red marker without radius
  Future<void> _onMapTap(mapbox.MapContentGestureContext context) async {
    final point = context.point;
    await _selectLocation(
      point.coordinates.lat.toDouble(),
      point.coordinates.lng.toDouble(),
    );
  }

  /// Move to current location
  Future<void> _moveToCurrentLocation() async {
    if (currentPosition.value == null) {
      await _getCurrentLocation();
    }

    if (currentPosition.value != null) {
      await _moveToLocation(
        currentPosition.value!.latitude,
        currentPosition.value!.longitude,
      );
      await _selectLocation(
        currentPosition.value!.latitude,
        currentPosition.value!.longitude,
      );
    }
  }

  /// Move camera to location
  Future<void> _moveToLocation(double lat, double lng) async {
    if (mapController == null) return;

    await mapController!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(lng, lat),
        ),
        zoom: 14.0,
      ),
      mapbox.MapAnimationOptions(duration: 1000),
    );
  }

  /// Select location and add red marker without radius
  Future<void> _selectLocation(double lat, double lng) async {
    if (annotationManager == null) return;

    try {
      // Clear existing markers first
      await _clearExistingMarkers();

      // Create red marker image
      await _createRedMarkerImage();

      // Create new red marker
      final pointAnnotationOptions = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
        iconImage: 'red-marker-icon',
        iconSize: 0.1, // Reduced size to make it smaller
      );

      selectedLocationMarker = await annotationManager!.create(pointAnnotationOptions);

      // Update memory controller with selected location
      memoryController.setLocation('$lat,$lng');

      // Get location details using geocoding service
      await _getLocationDetails(lat, lng);

    } catch (e) {
      debugPrint('Error selecting location: $e');
    }
  }

  Future<void> _clearExistingMarkers() async {
    if (annotationManager == null) return;

    try {
      // Clear all existing annotations
      await annotationManager!.deleteAll();

      // Reset the selected marker reference
      selectedLocationMarker = null;

      debugPrint('🧹 Cleared all existing location markers');
    } catch (e) {
      debugPrint('Error clearing existing markers: $e');
    }
  }

  /// Create red marker image for selected location
  Future<void> _createRedMarkerImage() async {
    if (mapController == null) return;

    try {
      // Remove existing image if it exists
      try {
        await mapController!.style.removeStyleImage('red-marker-icon');
      } catch (e) {
        // Image doesn't exist yet, which is fine
      }

      // Create proper circular red marker using Canvas
      final imageBytes = await _createRedMarkerImageBytes();

      await mapController!.style.addStyleImage(
        'red-marker-icon',
        1.0,
        mapbox.MbxImage(
          data: imageBytes,
          width: 500,
          height: 500,
        ),
        false,
        [],
        [],
        null,
      );

      debugPrint('✅ Red marker image created and added to map style');
    } catch (e) {
      debugPrint('Error creating red marker image: $e');
    }
  }

  /// Create red marker image bytes using Canvas
  Future<Uint8List> _createRedMarkerImageBytes() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Create a high-quality circular marker with higher resolution
    const size = 500.0; // Doubled size for better quality
    const center = Offset(size / 2, size / 2);
    const innerRadius = size / 3.5; // Larger inner radius

    // Draw inner red circle with solid color
    final innerPaint = Paint()
      ..color = const Color(0xFFE53E3E) // Better red color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, innerRadius, innerPaint);

    // Draw white border around inner circle with better thickness
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0 // Thicker border for better visibility
      ..isAntiAlias = true;
    canvas.drawCircle(center, innerRadius, borderPaint);

    // Add a subtle shadow effect
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2.0);
    canvas.drawCircle(center.translate(2, 2), innerRadius, shadowPaint);

    // Convert to high-quality image
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  /// Get location details using geocoding service
  Future<void> _getLocationDetails(double lat, double lng) async {
    try {
      // Use the geocoding isolate service for reverse geocoding
      final geocodingService = GeocodingIsolateService.instance;
      final result = await geocodingService.reverseGeocode(lat, lng);

      if (result != null) {
        final country = result['country'] ?? '';
        final city = result['city'] ?? '';
        final address = result['address'] ?? '';
        final flag = result['flag'] ?? countryFlags[country.toLowerCase()] ?? '📍';

        memoryController.setEnhancedLocationData({
          'latitude': lat,
          'longitude': lng,
          'city': city,
          'country': country,
          'address': address,
          'flag': flag,
          'name': city.isNotEmpty ? '$city, $country' : country,
        });

        debugPrint('📍 Location details: $city, $country $flag');
      } else {
        // Fallback to basic location data
        memoryController.setEnhancedLocationData({
          'latitude': lat,
          'longitude': lng,
          'city': 'Selected Location',
          'country': 'Unknown',
          'flag': '📍',
        });
      }
    } catch (e) {
      debugPrint('Error getting location details: $e');
      // Fallback to basic location data
      memoryController.setEnhancedLocationData({
        'latitude': lat,
        'longitude': lng,
        'city': 'Selected Location',
        'country': 'Unknown',
        'flag': '📍',
      });
    }
  }



  /// Perform location search using LocationPickerService (same as new_location_picker_widget)
  Future<void> _performLocationSearch(String query) async {
    if (query.trim().isEmpty) return;

    isSearching.value = true;
    searchResults.clear();

    try {
      // Use LocationPickerService for searching (same database as new_location_picker_widget)
      final results = await _locationPickerService.searchLocations(
        query,
        isOfflineMode: isOfflineMode.value,
      );

      // Results are already in the correct format from LocationPickerService
      searchResults.addAll(results);

    } catch (e) {
      debugPrint('Error performing location search: $e');
    } finally {
      isSearching.value = false;
    }
  }

  /// Select search result
  Future<void> _selectSearchResult(Map<String, dynamic> result) async {
    final lat = double.tryParse(result['latitude']?.toString() ?? '0') ?? 0.0;
    final lng = double.tryParse(result['longitude']?.toString() ?? '0') ?? 0.0;

    _showSearchResults.value = false;
    _searchController.clear();
    FocusScope.of(context).unfocus();

    // Clear existing markers before selecting new location
    await _clearExistingMarkers();

    await _moveToLocation(lat, lng);
    await _selectLocation(lat, lng);
  }

  /// Handle done button press - return complete location data with flag
  void _onDonePressed() {
    if (selectedLocationMarker == null) {
      Get.back();
      return;
    }

    // Return the complete location data including flag
    final locationData = {
      'latitude': selectedLocationMarker!.geometry.coordinates.lat,
      'longitude': selectedLocationMarker!.geometry.coordinates.lng,
      'city': memoryController.locationCity.value,
      'country': memoryController.locationCountry.value,
      'address': memoryController.locationAddress.value,
      'flag': memoryController.locationFlag.value,
      'name': memoryController.locationName.value,
    };

    debugPrint('🎯 Returning location data: $locationData');
    Get.back(result: locationData);
  }
}
