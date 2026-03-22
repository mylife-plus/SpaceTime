import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_location_picker_controller.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/shared/widgets/tick_cross_action_button.dart';
import 'package:spacetime/app/modules/memories/utils/memory_location_line_format.dart';

class MemoryLocationPickerWidget extends StatefulWidget {
  const MemoryLocationPickerWidget({super.key, this.fromMemoryView = true});

  /// Memory form: auto current/fallback when no pin. Edit-location route: pass false.
  final bool fromMemoryView;

  @override
  State<MemoryLocationPickerWidget> createState() => _MemoryLocationPickerWidgetState();
}

class _MemoryLocationPickerWidgetState extends State<MemoryLocationPickerWidget> {
 
  final MemoryLocationPickerController controller =
    Get.find<MemoryLocationPickerController>();

  @override
  void initState() {
    super.initState();
    controller.configureLaunchFromMemoryView(widget.fromMemoryView);
    unawaited(controller.initializeLocationPicker());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  /// Build main body
  Widget _buildBody() {
    return Obx(() {
      switch (controller.state.value) {
        case MemoryLocationPickerState.loading:
          return _buildLoadingView();
        case MemoryLocationPickerState.error:
          return _buildErrorView();
        default:
          return _buildMapView();
      }
    });
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
        _buildMap(),
        // Full width to screen edges; GPS button is stacked on top (does not shrink this column).
        Positioned(
          top: 5,
          left: 4,
          right: 4,
          child: Obx(
            () => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildSearchContainer(controller.uiController.darkMode.value),
                const SizedBox(height: 6),
                _buildLocationDetailLabel(),
                _buildSearchResultsPanel(),
              ],
            ),
          ),
        ),
        
        // Current location button
        // _buildCurrentLocationButton(),
   
        
        // Bottom action buttons
        _buildBottomActionButtons(),
      ],
    );
  }

  /// Same line format as memory form / admin edit ([MemoryLocationLineFormat]).
  Widget _buildLocationDetailLabel() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0;

    return AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isKeyboardVisible ? 0.0 : 1.0,
        child: Obx(() {
          final m = controller.memoryController;
          final lat = m.locationLatitude.value;
          final lng = m.locationLongitude.value;

          if (lat == null || lng == null) {
            return const SizedBox.shrink();
          }

          final isDark = controller.uiController.darkMode.value;
          final valueColor = isDark ? Colors.white : Colors.black87;

          final line = MemoryLocationLineFormat.displayLine(
            flag: m.locationFlag.value,
            locationCity: m.locationCity.value,
            locationName: m.locationName.value,
            lat: lat,
            lng: lng,
          );

          final editColor = isDark
              ? Colors.white.withValues(alpha: 0.75)
              : controller.uiController.currentEditIconColor;

          return Material(
            // color: Colors.transparent,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.only(left: 12, top: 10, bottom: 10, right: 6),
              decoration: BoxDecoration(
                color: isDark
                ?  controller.uiController.primaryColorDark
                    // ? Colors.black.withValues(alpha: 0.78)
                    : controller.uiController.primaryColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    // color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.medium(15, color: valueColor),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => controller.onEditLocationTextPressed(),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Image.asset(
                        'assets/images/ic_edit.png',
                        width: 22,
                        height: 22,
                        color: editColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
    );
  }

  /// Search results directly under the location label (same column as search).
  Widget _buildSearchResultsPanel() {
    return Obx(() {
      if (!controller.showSearchResults.value ||
          (controller.searchController.text.isEmpty &&
              controller.searchResults.isEmpty)) {
        return const SizedBox.shrink();
      }

      return Container(
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
      );
    });
  }

  /// Build map widget
  Widget _buildMap() {
    return Obx(() {
     
      final tileUrl = '${controller.serverUrl.value}/{z}/{x}/{y}.pbf';

            print('loadded URL tileUrl');

      final serverUrl = controller.serverUrl.value!; // Base server URL without tile pattern

      return FutureBuilder<String>(
      future: controller.loadStyleJsonFromAssets(tileUrl, serverUrl),
      builder: (context, snapshot) {
        // Show loading indicator while style.json is being loaded
        if (snapshot.connectionState == ConnectionState.waiting) {
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
        final styleJson = snapshot.data ?? controller.getBlankStyleJson();

        return mapbox.MapWidget(
          key: const ValueKey('memory_location_picker_map'),
          cameraOptions: controller.getCameraOptions(),
          textureView: true,
          onMapCreated: (mapboxMap) async {
            controller.mapController = mapboxMap;
                 mapboxMap.compass.updateSettings(mapbox.CompassSettings(enabled: false));
               mapboxMap.scaleBar.updateSettings(mapbox.ScaleBarSettings(enabled: false));
               mapboxMap.attribution.updateSettings(mapbox.AttributionSettings(enabled: false));

                         mapboxMap.logo.updateSettings(mapbox.LogoSettings(enabled: false));

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
        );
      },
      );
    });
  }

  /// Build top search bar - matching new location picker design
  Widget _buildTopSearchBar() {

      return Positioned(
        top: 50,
        left: 4,
        right: 4,
        child: buildSearchContainer(controller.uiController.darkMode.value),
      );

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
        hintText: 'search locations',
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
      if (!controller.hasLocationPermission.value) {
        return const SizedBox.shrink();
      }

      return Container(
                    padding: const EdgeInsets.only(left: 6),

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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      bottom: isKeyboardVisible ? -100 : 30, // Hide when keyboard is visible
      left: 20,
      right: 20,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isKeyboardVisible ? 0.0 : 1.0, // Fade out with keyboard
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildBottomButton(
              iconPath: 'assets/images/ic_cross.png',
              onTap: () => Get.back(),
            ),
            _buildBottomButton(
              iconPath: 'assets/images/ic_tick.png',
              onTap: controller.onDonePressed,
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
    return TickCrossActionButton(
      iconPath: iconPath,
      onTap: onTap,
    );
  }
  
  Widget buildSearchContainer(bool isDark) {
    
    return Row(
      children: [
        Expanded(child: Container(
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
            ),),
                        _buildCurrentLocationButton(),

      ],
    );}

}
