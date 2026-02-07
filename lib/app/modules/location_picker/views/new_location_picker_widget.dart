import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/location_picker/controllers/location_picker_controller.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/config/app_colors.dart';

class NewLocationPickerWidget extends StatefulWidget {
  const NewLocationPickerWidget({super.key});

  @override
  State<NewLocationPickerWidget> createState() => _NewLocationPickerWidgetState();
}

class _NewLocationPickerWidgetState extends State<NewLocationPickerWidget> {
  final LocationPickerController controller = Get.put(LocationPickerController());
  final UiController uiController = Get.find<UiController>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final RxBool _showSearchResults = false.obs;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    Get.delete<LocationPickerController>();
    super.dispose();
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
    switch (controller.state.value) {
      case LocationPickerState.loading:
        return _buildLoadingView();
      case LocationPickerState.error:
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
            controller.errorMessage.value,
            textAlign: TextAlign.center,
            style: AppFonts.regular(14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => controller.initializeController(),
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

        // Floating action buttons
        _buildFloatingButtons(),

        // Radius control
      //  Positioned(
      //     top: 100,
      //     left: 16,
      //     right: 16,
      //     child: _buildRadiusControl(),
      //   ), 

      ],
    );
  }

  /// Build map widget
  Widget _buildMap() {
    return mapbox.MapWidget(
      key: const ValueKey("mapbox_map_new"),
      cameraOptions: _getCameraOptions(),
      styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
      onMapCreated: _onMapCreated,
      onTapListener: _onMapTap,
      onCameraChangeListener: _onCameraChange,
    );
  }

  /// Build floating action buttons
  Widget _buildFloatingButtons() {
    return Stack(
      children: [
 Positioned(
          top: 100,
          left: 4,
          right: 4,
          child: _buildRadiusControl(),
        ), 

        // Current location button (top right - moved from done button position)
        if (controller.hasLocationPermission.value && controller.currentPosition.value != null)
          Positioned(
            top: 50,
            right: 4,
            child: _buildCurrentLocationButton(),
          ),

        // Search bar (top center area)
        Positioned(
          top: 50,
          left: 4,
          right: controller.hasLocationPermission.value && controller.currentPosition.value != null ? 60 : 4,
          child: Column(
            children: [
              _buildLocationSearchBar(),
              // Search results dropdown
              Obx(() {
                if (_showSearchResults.value && (_searchController.text.isNotEmpty || controller.searchResults.isNotEmpty || controller.isSearching.value)) {
                  return _buildSearchResultsDropdown();
                }
                return const SizedBox.shrink();
              }),
            ],
          ),
        ),

        // Bottom buttons (done and close)
        Positioned(
          bottom: 30,
          left: 20,
          right: 20,
          child: _buildBottomButtons(),
        ),
      ],
    );
  }

  /// Build back button
  Widget _buildBackButton() {
    return GestureDetector(
      onTap: () => Get.back(),
      child: Container(
        padding: EdgeInsets.all(6),
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
          AppImages.arrowBack,
          fit: BoxFit.contain,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Build bottom buttons (done and close)
  Widget _buildBottomButtons() {
    return Row(
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
    );
  }

  /// Build individual bottom button
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

  /// Build current location button
  Widget _buildCurrentLocationButton() {
    return GestureDetector(
      onTap: controller.getCurrentLocation,
      child: Container(
        padding: EdgeInsets.all(6),
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
    );
  }

  /// Build location search bar
  Widget _buildLocationSearchBar() {
    return Container(
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
                controller.searchResults.clear();
                controller.searchQuery.value = '';
                _searchFocusNode.unfocus();
                _showSearchResults.value = false;
              },
              child: Icon(
                Icons.clear,
                size: 20,
                color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600],
              ),
            ),
        ],
      )),
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
  }

  /// Handle search input changes
  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      controller.searchLocations(query);
    } else {
      controller.searchResults.clear();
      controller.searchQuery.value = '';
    }
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

  /// Get camera options
  mapbox.CameraOptions? _getCameraOptions() {
    if (controller.currentPosition.value != null) {
      return mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            controller.currentPosition.value!.longitude,
            controller.currentPosition.value!.latitude,
          ),
        ),
        zoom: 14.0,
      );
    }
    return null;
  }           

  /// Handle map creation
  Future<void> _onMapCreated(mapbox.MapboxMap mapController) async {
    try {
      controller.setMapController(mapController);



      // Configure offline map
      await controller.configureOfflineMap(mapController);

      // Create annotation manager
      final annotationManager = await mapController.annotations.createPointAnnotationManager();
      controller.setAnnotationManager(annotationManager);

      // Get current location if permission is available
      if (controller.hasLocationPermission.value) {
        await controller.getCurrentLocation();
      }
    } catch (e) {
      debugPrint('Error in onMapCreated: $e');
    }
  }



  /// Handle map tap
  void _onMapTap(mapbox.MapContentGestureContext context) {
    final point = context.point;
    controller.onMapTap(
      point.coordinates.lat.toDouble(),
      point.coordinates.lng.toDouble(),
    );
  }

  /// Handle camera change (zoom level changes)
  void _onCameraChange(mapbox.CameraChangedEventData eventData) {
    // Update zoom level in service for marker scaling
    controller.updateZoom(eventData.cameraState.zoom);
  }

  /// Create a GeoJSON polygon circle in meters for accurate radius display
  Map<String, dynamic> _buildCircleGeoJson(double lat, double lon, double radiusMeters, {int points = 64}) {
    final List<List<double>> coords = [];
    const earthRadius = 6371000.0; // meters

    final double latRad = lat * pi / 180;
    final double lonRad = lon * pi / 180;

    for (int i = 0; i < points; i++) {
      final double bearing = 2 * pi * (i / points);
      final double angularDistance = radiusMeters / earthRadius;

      final double lat2 = asin(
        sin(latRad) * cos(angularDistance) + cos(latRad) * sin(angularDistance) * cos(bearing),
      );
      final double lon2 = lonRad +
          atan2(
            sin(bearing) * sin(angularDistance) * cos(latRad),
            cos(angularDistance) - sin(latRad) * sin(lat2),
          );

      coords.add([lon2 * 180 / pi, lat2 * 180 / pi]);
    }

    // Close the polygon by adding the first coordinate at the end
    coords.add(coords.first);

    return {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "properties": {"radius_m": radiusMeters},
          "geometry": {
            "type": "Polygon",
            "coordinates": [coords],
          }
        }
      ]
    };
  }



  /// Build radius control
  Widget _buildRadiusControl() {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 5, top: 10),
      decoration: BoxDecoration(
        color: uiController.darkMode.value
            ? Colors.black.withOpacity(0.8)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              text: 'Radius: ',
              style: AppFonts.medium(
                16,
                color: uiController.darkMode.value ? Colors.white : Colors.black,
              ),
              children: [
                TextSpan(
                  text: '${_formatRadius(controller.selectedRadius.value)} km',
                  style: AppFonts.medium(
                    16,
                    color: uiController.currentMainColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Obx(() {
            // Convert radius to slider value (0-100 scale)
            final sliderValue = _radiusToSliderValue(controller.selectedRadius.value);

            return Slider(
              value: sliderValue,
              min: 0.0,
              max: 100.0,
              padding: EdgeInsets.only(bottom: 5),
              divisions: 1000,
              activeColor: uiController.currentMainColor,
              inactiveColor: Colors.grey.withOpacity(0.3),
              onChanged: (value) {
                // Convert slider value to radius and update immediately for smooth movement
                final radius = _sliderValueToRadius(value);
                controller.selectedRadius.value = radius;
              },
              onChangeEnd: (value) {
                // Save when user releases the slider
                final radius = _sliderValueToRadius(value);
                controller.updateRadius(radius);
              },
            );
          }),
        ],
      ),
    );
  }

  /// Convert radius (km) to slider value (0-100 scale)
  /// 0-50: 1km to 25km (linear)
  /// 50-100: 25km to 200km (linear)
  double _radiusToSliderValue(double radius) {
    if (radius <= 25.0) {
      // 0-50% of slider: 1km to 25km
      return ((radius - 1.0) / 24.0) * 50.0;
    } else {
      // 50-100% of slider: 25km to 200km
      return 50.0 + ((radius - 25.0) / 175.0) * 50.0;
    }
  }

  /// Convert slider value (0-100 scale) to radius (km)
  /// 0-50: 1km to 25km (linear)
  /// 50-100: 25km to 200km (linear)
  double _sliderValueToRadius(double sliderValue) {
    if (sliderValue <= 50.0) {
      // 0-50% of slider: 1km to 25km
      final radius = 1.0 + (sliderValue / 50.0) * 24.0;
      return (radius * 10).round() / 10.0; // Round to 0.1km
    } else {
      // 50-100% of slider: 25km to 200km
      final radius = 25.0 + ((sliderValue - 50.0) / 50.0) * 175.0;
      return (radius * 10).round() / 10.0; // Round to 0.1km
    }
  }

  /// Build location info
  Widget _buildLocationInfo() {
    final location = controller.selectedLocation.value!;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: uiController.darkMode.value 
            ? Colors.black.withOpacity(0.8)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Selected Location',
            style: AppFonts.medium(
              14,
              color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600]!,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            location.address,
            style: AppFonts.medium(
              16,
              color: uiController.darkMode.value ? Colors.white : Colors.black,
            ),
          ),
          if (location.city.isNotEmpty || location.state.isNotEmpty)
            Text(
              '${location.city}${location.city.isNotEmpty && location.state.isNotEmpty ? ', ' : ''}${location.state}',
              style: AppFonts.regular(
                14,
                color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600]!,
              ),
            ),
        ],
      ),
    );
  }

  /// Build search results dropdown
  Widget _buildSearchResultsDropdown() {
    return Container(
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
      child: Obx(() {
 
        return ListView.separated(
          shrinkWrap: true,
          itemCount: controller.searchResults.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: 1,
            color: uiController.darkMode.value
                ? Colors.grey[700]!
                : Colors.grey[300]!,
          ),
          itemBuilder: (context, index) {
            final result = controller.searchResults[index];
            return _buildSearchResultItem(result);
          },
        );
      }),
    );
  }

  /// Build individual search result item
  Widget _buildSearchResultItem(Map<String, dynamic> result) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          controller.selectSearchResult(result);
          _searchController.clear();
          _showSearchResults.value = false;
          _searchFocusNode.unfocus();
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

  /// Handle done button press
  void _onDonePressed() {
    controller.saveSelection();
    final result = controller.getResultData();
    Get.back(result: result);
  }

  /// Format radius value for display
  String _formatRadius(double radius) {
    // Show integer values for whole numbers, decimal for fractional values
    if (radius == radius.toInt()) {
      return radius.toInt().toString();
    } else {
      // Show up to 1 decimal place for precision
      return radius.toStringAsFixed(1);
    }
  }
}
