import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/map/controllers/memory_location_picker_with_radius_controller.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_location_picker_controller.dart';
import 'package:spacetime/app/config/app_images.dart';

class MemoryLocationPickerWidgetWithRadius extends StatefulWidget {
  const MemoryLocationPickerWidgetWithRadius({super.key});

  @override
  State<MemoryLocationPickerWidgetWithRadius> createState() => _MemoryLocationPickerWidgetState();
}

class _MemoryLocationPickerWidgetState extends State<MemoryLocationPickerWidgetWithRadius> {
 
  final MemoryLocationPickerControllerWithRadius controller =
          Get.put(MemoryLocationPickerControllerWithRadius());


  @override
  void initState() {
        controller.onInit();
    super.initState();
        controller.onInit();
    
  }
  /// Initialize location picker

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: 
      Scaffold(
      backgroundColor: Colors.black,
      body:
        _buildMapView(),
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
            onPressed: controller.initializeLocationPicker,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Build map view
  Widget _buildMapView() {
    // return Obx(() {
    return Stack(
      children: [
        // Map
        Obx(() {
      // Check if server URL is available
      if (controller.serverUrl.value == null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                controller.serverErrorMessage.value ?? 'Initializing map server...',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }

      final tileUrl = '${controller.serverUrl.value}/{z}/{x}/{y}.pbf';

      debugPrint('Loaded URL tileUrl: $tileUrl');

      final serverUrl = controller.serverUrl.value!; // Base server URL without tile pattern

      return FutureBuilder<String>(
      future: controller.loadStyleJsonFromAssets(tileUrl, serverUrl),
      builder: (context, snapshot) {
        // Show loading indicator while style.json is being loaded
      

        // Style loaded successfully - build the map
        final styleJson = snapshot.data ?? controller.getBlankStyleJson();

        return SizedBox.expand(
          child: mapbox.MapWidget(
            key: const ValueKey('memory_location_picker_map'),
            cameraOptions: controller.getCameraOptions(),
            textureView: true,
            
            onMapCreated: (mapboxMap) async {
               
               mapboxMap.compass.updateSettings(mapbox.CompassSettings(enabled: false));
               mapboxMap.scaleBar.updateSettings(mapbox.ScaleBarSettings(enabled: false));
               mapboxMap.attribution.updateSettings(mapbox.AttributionSettings(enabled: false));
               mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));

              controller.mapController = mapboxMap;
              debugPrint('[MemoryLocationPicker] 🗺️ onMapCreated callback triggered');

              // CRITICAL: Enable online mode to allow localhost tile server access
              await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
              debugPrint('[MemoryLocationPicker] 🌐 Online mode ENABLED - localhost tile server can now be accessed');

              // Load the custom style JSON with local tile server URLs
              debugPrint('[MemoryLocationPicker] 📥 Loading custom style JSON into Mapbox...');
              debugPrint('[MemoryLocationPicker] 📊 Style JSON length: ${styleJson.length} characters');

              // Verify the JSON contains our localhost URLs before loading
              // if (styleJson.contains('localhost:8080')) {
              //   debugPrint('[MemoryLocationPicker] ✅ Verified: Style JSON contains localhost URLs');
              // } else {
              //   debugPrint('[MemoryLocationPicker] ⚠️ WARNING: Style JSON does NOT contain localhost URLs!');
              // }

              // await mapboxMap.loadStyleJson(styleJson);
              // debugPrint('[MemoryLocationPicker] ✅ Custom style JSON loaded into Mapbox successfully');

              controller.onMapCreated(mapboxMap);
              controller.getCurrentLocation();
            },
            onStyleLoadedListener: (styleLoadedEventData) async {
              debugPrint('[MemoryLocationPicker] 🎨 onStyleLoaded callback triggered');
              debugPrint('[MemoryLocationPicker] ✅ Style.json from assets loaded successfully with local tiles');
            },
            onTapListener: controller.onMapTap,
          ),
        );
      },
      );
    }),
        // Top search bar
        Positioned(
        top: 50,
        left: 4,
        right: controller.hasLocationPermission.value ? 60 : 4,
        child: buildSearchContainer(controller.uiController.darkMode.value),),

        // Radius seekbar below search
        _buildRadiusSeekbar(),

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
    debugPrint('[MemoryLocationPicker] 🏗️ _buildMap() called');
    return Obx(() {
      debugPrint('[MemoryLocationPicker] 🔄 Obx rebuilding - serverUrl: ${controller.serverUrl.value}');

      // Check if server URL is available
      if (controller.serverUrl.value == null) {
        debugPrint('[MemoryLocationPicker] ⏳ Server URL is null, showing loading indicator');
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                controller.serverErrorMessage.value ?? 'Initializing map server...',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }

      final tileUrl = '${controller.serverUrl.value}/{z}/{x}/{y}.pbf';

      debugPrint('[MemoryLocationPicker] 🗺️ Server URL available: $tileUrl');

      final serverUrl = controller.serverUrl.value!; // Base server URL without tile pattern

      debugPrint('[MemoryLocationPicker] 🔄 Creating FutureBuilder for style.json...');

      return FutureBuilder<String>(
      future: controller.loadStyleJsonFromAssets(tileUrl, serverUrl),
      builder: (context, snapshot) {
        debugPrint('[MemoryLocationPicker] 📊 FutureBuilder state: ${snapshot.connectionState}, hasData: ${snapshot.hasData}, hasError: ${snapshot.hasError}');

        // Show loading indicator while style.json is being loaded
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint('[MemoryLocationPicker] ⏳ Waiting for style.json to load...');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  'Loading map style...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        }

        // Handle error
        if (snapshot.hasError) {
          debugPrint('[MemoryLocationPicker] ❌ Error in FutureBuilder: ${snapshot.error}');
          return Center(
            child: Text(
              'Error loading map style',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        // Style loaded successfully - build the map
        debugPrint('[MemoryLocationPicker] ✅ Style.json loaded, creating MapWidget...');
        final styleJson = snapshot.data ?? controller.getBlankStyleJson();
        debugPrint('[MemoryLocationPicker] 📏 Style JSON length: ${styleJson.length} characters');

        return SizedBox.expand(
          child: mapbox.MapWidget(
            key: const ValueKey('memory_location_picker_map'),
            cameraOptions: controller.getCameraOptions(),
            textureView: true,
            onMapCreated: (mapboxMap) async {
              controller.mapController = mapboxMap;
              debugPrint('[MemoryLocationPicker] 🗺️ onMapCreated callback triggered');

              // CRITICAL: Enable online mode to allow localhost tile server access
              await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
              debugPrint('[MemoryLocationPicker] 🌐 Online mode ENABLED - localhost tile server can now be accessed');

              // Load the custom style JSON with local tile server URLs
              debugPrint('[MemoryLocationPicker] 📥 Loading custom style JSON into Mapbox...');
              debugPrint('[MemoryLocationPicker] 📊 Style JSON length: ${styleJson.length} characters');

              // Verify the JSON contains our localhost URLs before loading
              if (styleJson.contains('localhost:8080')) {
                debugPrint('[MemoryLocationPicker] ✅ Verified: Style JSON contains localhost URLs');
              } else {
                debugPrint('[MemoryLocationPicker] ⚠️ WARNING: Style JSON does NOT contain localhost URLs!');
              }

              await mapboxMap.loadStyleJson(styleJson);
              debugPrint('[MemoryLocationPicker] ✅ Custom style JSON loaded into Mapbox successfully');

              controller.onMapCreated(mapboxMap);
            },
            onStyleLoadedListener: (styleLoadedEventData) async {
              debugPrint('[MemoryLocationPicker] 🎨 onStyleLoaded callback triggered');
              debugPrint('[MemoryLocationPicker] ✅ Style.json from assets loaded successfully with local tiles');
            },
            onTapListener: controller.onMapTap,
          ),
        );
      },
      );
    });
  }


  /// Build search text field
  Widget _buildSearchField(bool isDark) {
    return TextField(
      controller: controller.searchController,
      focusNode: controller.searchFocusNode,
      autofocus: false,
      textInputAction: TextInputAction.search,
      style: AppFonts.medium(
        16,
        color: isDark ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        hintText: 'Search locations...',
        hintStyle: AppFonts.regular(
          16,
          color: isDark ? Colors.white54 : Colors.grey[600]!,
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 2),
      ),
      onTap: () {
        if (!controller.showSearchResults.value) {
          controller.showSearchResults.value = true;
        }
      },
    );
  }

  /// Build search results overlay - matching new location picker design
  Widget _buildSearchResultsOverlay() {
    return Obx(() {
      if (!controller.showSearchResults.value ||
          (controller.searchController.text.isEmpty && controller.searchResults.isEmpty && !controller.isSearching.value)) {
        return const SizedBox.shrink();
      }

      return Positioned(
        top: 100, // Below search bar (50) + search height (44) + seekbar height (~78) + spacing (8)
        left: 4,
        right: controller.hasLocationPermission.value && controller.currentPosition.value != null ? 60 : 4,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: controller.uiController.darkMode.value
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
    return Obx(() {
      

      final isDark = controller.uiController.darkMode.value;

      return ListView.separated(
        shrinkWrap: true,
        itemCount: controller.searchResults.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
        itemBuilder: (context, index) {
          final result = controller.searchResults[index];
          return _buildSearchResultItem(result);
        },
      );
    });
  }

  /// Build individual search result item - matching new location picker design
  Widget _buildSearchResultItem(Map<String, dynamic> result) {
    return Obx(() {
      final isDark = controller.uiController.darkMode.value;

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            controller.selectSearchResult(result);
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
                    color: isDark ? Colors.white : Colors.black87,
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
                      color: isDark ? Colors.white70 : Colors.grey[600]!,
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
    });
  }

  /// Build current location button - matching new location picker design
  Widget _buildCurrentLocationButton() {
    return Obx(() {
      if (!controller.hasLocationPermission.value || controller.currentPosition.value == null) {
        return const SizedBox.shrink();
      }

      return Positioned(
        top: 50,
        right: 4,
        child: GestureDetector(
          onTap: controller.moveToCurrentLocation,
          child: Container(
            padding: const EdgeInsets.all(6),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              image: DecorationImage(
                image: AssetImage(AppImages.rectangle),
                fit: BoxFit.cover,
                colorFilter: controller.uiController.rectangleColorFilter,
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
    });
  }

  /// Build bottom action buttons - matching new location picker design
  Widget _buildBottomActionButtons() {
    // return Obx(() {
      final hasFocus = controller.searchFocusNode.hasFocus;

      return AnimatedPositioned(
        duration: const Duration(milliseconds: 300),
        bottom: hasFocus ? -100 : 30, // Hide when search is focused
        left: 20,
        right: 20,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: hasFocus ? 0.0 : 1.0, // Fade out when search is focused
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
                onTap: controller.onDonePressed1,
              ),
            ],
          ),
        ),
      );
    // });
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
  
  /// Build radius seekbar widget
  Widget _buildRadiusSeekbar() {
    return Obx(() {
      final isDark = controller.uiController.darkMode.value;
      final hasLocation = controller.hasLocationPermission.value && controller.currentPosition.value != null;

      return Positioned(
        top: 102, // Below search bar (50 + 44 + 8)
        left: 4,
        right: 4,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  
                  Text(
                    controller.radiusInKm.value < 1
                        ? '${(controller.radiusInKm.value * 1000).toStringAsFixed(0)} m '
                        : '${controller.radiusInKm.value.toStringAsFixed(1)} km ',
                    style: AppFonts.bold(
                      14,
                      color: controller.uiController.currentMainColor,
                    ),
                  ),Text(
                    'radius',
                    style: AppFonts.bold(
                      14,
                      color: isDark ? Colors.white70 : Colors.grey[700]!,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: controller.uiController.currentMainColor,
                  inactiveTrackColor: isDark ? Colors.grey[700] : Colors.white,
                  thumbColor: controller.uiController.currentMainColor,
                  overlayColor: controller.uiController.currentMainColor.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: controller.radiusSliderValue.value,
                  min: 0,
                  max: 100,
                  divisions: 100,
                 onChangeEnd: (value) {
                     debugPrint('🎚️ Slider UI changed to: $value');
                    controller.radiusSliderValue.value = value;
                    controller.updateRadius(controller.radiusSliderValue.value);
                 }, onChanged: (double value) {  },
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget buildSearchContainer(bool isDark) {

    return Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark
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
          child: Row(
            children: [
              Image.asset(
                AppImages.searchNormal,
                width: 20,
                height: 20,
                color: isDark ? Colors.white70 : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSearchField(isDark),
              ),

              
              // Clear button - uses ValueListenableBuilder to listen to TextEditingController
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller.searchController,
                builder: (context, value, child) {
                  if (value.text.isEmpty) return const SizedBox.shrink();

                  return GestureDetector(
                    onTap: () {
                      controller.searchController.clear();
                      controller.searchResults.clear();
                      controller.showSearchResults.value = false;
                      controller.searchFocusNode.unfocus();
                    },
                    child: Icon(
                      Icons.clear,
                      size: 20,
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  );
                },
              ),
            ],
          ),
        );}

}
