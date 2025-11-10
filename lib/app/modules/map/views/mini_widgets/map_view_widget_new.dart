import 'dart:io' as io;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/map/views/mini_widgets/map_fab.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/top_buttons.dart';
import '../../controllers/map_controller_new.dart';
// Note: Permission-related imports removed as location check is disabled
// Note: Internet required screen removed - offline tiles are downloaded during Get Started flow
import '../../../../widgets/offline_download_overlay.dart';
import '../../../ui/controllers/ui_controller.dart';
import '../../../add_memories/controllers/add_memories_controller.dart';
import '../../../add_memories/views/mini_widgets/filter_indicator.dart';
import 'map_filter_overlay.dart';

class MapViewWidgetNew extends StatefulWidget {
  const MapViewWidgetNew({Key? key}) : super(key: key);

  @override
  State<MapViewWidgetNew> createState() => _MapViewWidgetNewState();
}

class _MapViewWidgetNewState extends State<MapViewWidgetNew>
    with WidgetsBindingObserver {
  MapControllerNew? controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // MapControllerNew is initialized in main.dart as permanent singleton
    // Always use Get.find() - never create new instance
    controller = Get.find<MapControllerNew>();
    debugPrint('[MapViewWidgetNew] Using MapControllerNew instance: ${controller.hashCode}');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed && controller != null) {
      // App resumed from background (possibly from settings)
      debugPrint(
        '[MapViewWidgetNew] App resumed, checking location permissions',
      );
      controller!.checkPermissionsAfterResume();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MapControllerNew>(
      // Remove init parameter to prevent creating new instance
      builder: (controller) {
        return Obx(() {
          return Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Stack(
                children: [
                  // MapBox Map
                  _buildMapWidget(controller),
//  Obx(() {
                  //   if (controller.showOfflineDownloadOverlay.value) {
                  //     return Positioned(
                  //       top: 100.0,
                  //       left: 0,
                  //       right: 0,
                  //       child: OfflineDownloadOverlay(
                  //         onClose: controller.hideOfflineDownloadOverlay,
                  //         onStartDownload: controller.startOfflineDownload,
                  //       ),
                  //     );
                  //   }
                  //   return Container();
                  // }),

                  // Filter overlay backdrop
                  if (controller.isFilterOpen.value)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.8),
                      ),
                    ),

                  // Top buttons and FAB (hidden when filter is open)
                  if (!controller.isFilterOpen.value)
                    const MapTopButtons(),
                  if (!controller.isFilterOpen.value)
                    const MapFab(),

                  // Filter indicator (shown when filters are active and filter is not open)
                  if (!controller.isFilterOpen.value)
                    Positioned(
                      top: 60,
                      left: 0,
                      right: 0,
                      child: Obx(() {
                        // Only show if AddMemoriesController is registered and has active filters
                        if (!Get.isRegistered<AddMemoriesController>()) {
                          return const SizedBox.shrink();
                        }

                        final addMemoriesController = Get.find<AddMemoriesController>();
                        if (!addMemoriesController.hasActiveFilters.value) {
                          return const SizedBox.shrink();
                        }

                        return const FilterIndicator();
                      }),
                    ),

                  // Filter overlay
                  if (controller.isFilterOpen.value) const MapFilterOverlay(),


                  // Permission and Internet screens overlay
                  // _buildPermissionAndInternetScreens(context, controller),
                ],
              ),
            ),
            floatingActionButton: _buildFloatingActionButton(controller),
          );
        });
      },
    );
  }

  /// Build the MapBox map widget
  Widget _buildMapWidget(MapControllerNew controller) {
    // return 
    
   return mapbox.MapWidget(
      key: ValueKey("mapbox_map_new"),
      cameraOptions: mapbox.CameraOptions(
        // center: mapbox.Point(
        //   coordinates: mapbox.Position(0.0, 0.0), // Default center
        // ),
        zoom: 8.0,
      ),
      styleUri: mapbox.MapboxStyles.STANDARD,
      // iOS FIX: Use surface view instead of texture view for better iOS compatibility
      textureView: io.Platform.isAndroid, // Only use texture view on Android
      onMapCreated: (mapboxMap) {
        controller.mapboxMap = mapboxMap;
        debugPrint('[MapViewWidgetNew] 🗺️ onMapCreated callback triggered');
        controller.onMapCreated(mapboxMap);
      },
      onStyleLoadedListener: (styleLoadedEventData) {
        debugPrint('[MapViewWidgetNew] 🎨 onStyleLoaded callback triggered');
        controller.onStyleLoaded(styleLoadedEventData);
      },
      onMapLoadErrorListener: (mapLoadErrorEventData) {
        debugPrint('[MapViewWidgetNew] ❌ onMapLoadError callback triggered: ${mapLoadErrorEventData.message}');
        controller.onMapError(mapLoadErrorEventData);
      },
    );
  }

  /// Build floating action button for location actions
  Widget _buildFloatingActionButton(MapControllerNew controller) {
    return Obx(() {
      if (!controller.hasLocationPermission.value) {
        return Container(); // Hide when no permission
      }

      return FloatingActionButton(
        onPressed: controller.refreshLocation,
        backgroundColor: Colors.blue,
        tooltip: 'Go to Current Location',
        child:
            controller.isLoadingLocation.value
                ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : Icon(Icons.my_location, color: Colors.white),
      );
    });
  }

  /// Build permission and internet screens overlay based on controller state
  Widget _buildPermissionAndInternetScreens(
    BuildContext context,
    MapControllerNew controller,
  ) {
    return Obx(() {
      debugPrint('[MapViewWidgetNew] 🔍 Checking overlay conditions:');
      debugPrint(
        '[MapViewWidgetNew] - hasLocationPermission: ${controller.hasLocationPermission.value}',
      );
      debugPrint(
        '[MapViewWidgetNew] - isLoadingLocation: ${controller.isLoadingLocation.value}',
      );

      Widget? overlayContent;

      // PRIORITY 1: Location permission check removed - no longer required
      // Note: Current location check has been disabled as requested

      // PRIORITY 2: Internet-related screens removed - offline tiles are downloaded during Get Started flow
      // No need to check internet connectivity - tiles should already be available

      // PRIORITY 3: Show loading during location loading (after permission granted and internet available)
      if (overlayContent == null &&
          controller.isLoadingLocation.value &&
          controller.hasLocationPermission.value) {
        debugPrint(
          '[MapViewWidgetNew] Showing loading screen - getting location',
        );
        overlayContent = _buildLoadingScreen(
          'Getting your location...',
          controller,
        );
      }

      if (overlayContent == null) {
        debugPrint('[MapViewWidgetNew] No overlay needed - normal state');
        debugPrint(
          '[MapViewWidgetNew] hasLocationPermission: ${controller.hasLocationPermission.value}',
        );
        return const SizedBox.shrink();
      }

      return Positioned.fill(
        child: Stack(
          children: [
            const ModalBarrier(color: Colors.transparent, dismissible: false),
            overlayContent,
          ],
        ),
      );
    });
  }

  /// Build loading screen widget
  Widget _buildLoadingScreen(String message, MapControllerNew controller) {
    final uiController = Get.find<UiController>();

    return Container(
      alignment: Alignment.center,
      width: double.infinity,
      height: double.infinity,

      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color:
                uiController.darkMode.value
                    ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: uiController.currentMainColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated loading indicator with gradient background
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        uiController.currentMainColor.withValues(alpha: 0.8),
                        uiController.currentMainColor.withValues(alpha: 0.4),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: uiController.currentMainColor.withValues(
                        alpha: 0.5,
                      ),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: uiController.currentMainColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 18,
                    color:
                        uiController.darkMode.value
                            ? Colors.white.withValues(alpha: 0.87)
                            : Colors.black.withValues(alpha: 0.87),
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait...',
                  style: TextStyle(
                    fontSize: 14,
                    color:
                        uiController.darkMode.value
                            ? Colors.white.withValues(alpha: 0.54)
                            : Colors.black.withValues(alpha: 0.54),
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
