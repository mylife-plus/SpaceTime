import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/add_memories/views/mini_widgets/filter_overlay.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/filter_overlay.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/internet_required_screen.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/map_fab.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/map_refresh_fab.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/map_view_widget.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/permission_required_screen.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/tile_download_banner.dart';
import 'package:spacetime/app/modules/map/views/mini_widgets/top_buttons.dart';
import 'package:spacetime/app/modules/map/views/widgets/geocoding_indicator_widget.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/services/background_tile_download_service.dart';
import 'package:spacetime/services/permission_service.dart';

import '../controllers/map_controller.dart';

class MapView extends GetView<MapController> {
  const MapView({super.key});

  @override
  Widget build(BuildContext context) {
    BackgroundTileDownloadService service;
    // Initialize the background tile download service if not already initialized
    try {
      service = Get.find<BackgroundTileDownloadService>();
      debugPrint(
        '🎯 MapView - BackgroundTileDownloadService found: ${service.runtimeType}',
      );
    } catch (e) {
      debugPrint('🎯 MapView - Creating new BackgroundTileDownloadService');
      service = Get.put(BackgroundTileDownloadService());
    }

    return SafeArea(
      child: Scaffold(
        body: Obx(() {
          //  controller.currentInitializationState.value = MapInitializationState.error ;

          return Stack(
            children: [
              const MapViewWidget(),

              if (controller.isFilterOpen.value)
                Positioned.fill(
                  child: Container(color: Colors.black.withValues(alpha: 0.8)),
                ),

              // Always show tile download progress bar until 25,000 tiles
              if (service.totalTilesDownloaded.value < 25000)
                const Positioned(
                  top: 60,
                  left: 16,
                  right: 16,
                  child: TileDownloadBanner(),
                ),

              if (!controller.isFilterOpen.value) const MapTopButtons(),

              if (!controller.isFilterOpen.value) const MapFab(),

              if (!controller.isFilterOpen.value) const MapRefreshFab(),

              if (!controller.isFilterOpen.value)
                const GeocodingStatusOverlay(),

              if (controller.isFilterOpen.value)
                Positioned.fill(
                  child: Container(color: Colors.black.withValues(alpha: 0.8)),
                ),
              if (controller.isFilterOpen.value)
                MemoriesFilterOverlay(isOpenedFromMap: true),

              if (service.totalTilesDownloaded.value < 30000) ...[
                buildInternetAndPermissionsScreen(
                  context,
                  controller.currentInitializationState.value,
                ),
              ],
            ],
          );
        }),
      ),
    );
  }

  Widget _buildLoadingScreen(String message, MapController controller) {
    final uiController = Get.find<UiController>();

    return Container(
      alignment: Alignment.center,
      width: double.infinity,
      height: double.infinity,

      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: MediaQuery.of(Get.context!).size.width * 0.85,
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
            // // boxShadow: [
            // //   BoxShadow(
            // //     color: uiController.currentMainColor.withValues(alpha: 0.2),
            // //     blurRadius: 30,
            // //     spreadRadius: 0,
            // //     offset: const Offset(0, 10),
            // //   ),
            //   BoxShadow(
            //     color: Colors.black.withValues(alpha: 0.1),
            //     blurRadius: 20,
            //     spreadRadius: 0,
            //     offset: const Offset(0, 5),
            //   ),
            // ],
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
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        uiController.currentMainColor.withValues(alpha: 0.2),
                        uiController.currentMainColor.withValues(alpha: 0.05),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: uiController.currentMainColor.withValues(
                        alpha: 0.3,
                      ),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        color: uiController.currentMainColor,
                        strokeWidth: 3,
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
                            ? Colors.white
                            : Colors.black87,
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
                            ? Colors.white60
                            : Colors.black54,
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

  Widget _buildQuickLoadingScreen(String message, MapController controller) {
    final uiController = Get.find<UiController>();

    return Container(
      alignment: Alignment.center,
      width: double.infinity,
      height: double.infinity,
      // decoration: BoxDecoration(
      //   gradient: LinearGradient(
      //     begin: Alignment.topCenter,
      //     end: Alignment.bottomCenter,
      //     colors: [
      //       Colors.black.withValues(alpha: 0.6),
      //       Colors.black.withValues(alpha: 0.8),
      //     ],
      //   ),
      // ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: MediaQuery.of(Get.context!).size.width * 0.7,
          constraints: const BoxConstraints(maxWidth: 260),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color:
                uiController.darkMode.value
                    ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: uiController.currentMainColor.withValues(alpha: 0.3),
              width: 1.5,
            ),
            // boxShadow: [
            //   BoxShadow(
            //     color: uiController.currentMainColor.withValues(alpha: 0.15),
            //     blurRadius: 20,
            //     spreadRadius: 0,
            //     offset: const Offset(0, 8),
            //   ),
            //   BoxShadow(
            //     color: Colors.black.withValues(alpha: 0.1),
            //     blurRadius: 15,
            //     spreadRadius: 0,
            //     offset: const Offset(0, 4),
            //   ),
            // ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compact loading indicator
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        uiController.currentMainColor.withValues(alpha: 0.15),
                        uiController.currentMainColor.withValues(alpha: 0.05),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: uiController.currentMainColor.withValues(
                        alpha: 0.2,
                      ),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: uiController.currentMainColor,
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 16,
                    color:
                        uiController.darkMode.value
                            ? Colors.white
                            : Colors.black87,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
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

  Widget _buildErrorScreen(MapController controller) {
    final uiController = Get.find<UiController>();

    return Container(
      alignment: Alignment.center,
      width: double.infinity,
      height: double.infinity,
      // decoration: BoxDecoration(
      //   gradient: LinearGradient(
      //     begin: Alignment.topCenter,
      //     end: Alignment.bottomCenter,
      //     colors: [
      //       Colors.black.withValues(alpha: 0.7),
      //       Colors.black.withValues(alpha: 0.9),
      //     ],
      //   ),
      // ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          width: MediaQuery.of(Get.context!).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 360),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color:
                uiController.darkMode.value
                    ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                    : Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.red.withValues(alpha: 0.3),
              width: 1.5,
            ),
            // boxShadow: [
            //   BoxShadow(
            //     color: Colors.red.withValues(alpha: 0.2),
            //     blurRadius: 30,
            //     spreadRadius: 0,
            //     offset: const Offset(0, 10),
            //   ),
            //   BoxShadow(
            //     color: Colors.black.withValues(alpha: 0.1),
            //     blurRadius: 20,
            //     spreadRadius: 0,
            //     offset: const Offset(0, 5),
            //   ),
            // ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Error icon with gradient background
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.red.withValues(alpha: 0.2),
                        Colors.red.withValues(alpha: 0.05),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: Colors.red,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color:
                        uiController.darkMode.value
                            ? Colors.white
                            : Colors.black87,
                    letterSpacing: -0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Please try again or restart the app.',
                  style: TextStyle(
                    fontSize: 16,
                    color:
                        uiController.darkMode.value
                            ? Colors.white70
                            : Colors.black54,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Modern retry button
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        uiController.currentMainColor,
                        uiController.currentMainColor.withValues(alpha: 0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: uiController.currentMainColor.withValues(
                          alpha: 0.3,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await controller.retryCurrentState();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  buildInternetAndPermissionsScreen(
    BuildContext context,
    MapInitializationState state,
  ) {
    final currentState = controller.currentInitializationState.value;

    // PRIORITY 1: Handle permission-related states first
    if (currentState == MapInitializationState.initial ||
        currentState == MapInitializationState.checkingPermission) {
      return _buildLoadingScreen('Checking permissions...', controller);
    } else if (currentState == MapInitializationState.permissionDenied) {
      debugPrint(
        '🔐 Showing permission required screen - blocking internet screen',
      );
      return const PermissionRequiredScreen();
    }
    // PRIORITY 2: Only show internet-related screens after permissions are granted
    else if (currentState == MapInitializationState.checkingInternet) {
      return _buildLoadingScreen('Checking internet connection...', controller);
    } else if (currentState == MapInitializationState.internetRequired) {
      debugPrint(
        '🌐 Showing internet required screen (permissions already granted)',
      );
      return const InternetRequiredScreen();
    }
    // PRIORITY 3: Show loading during map loading (this hides internet screen)
    else if (currentState == MapInitializationState.loadingMap) {
      return _buildLoadingScreen('Loading map...', controller);
    }
    // PRIORITY 4: Handle error states
    else if (currentState == MapInitializationState.error) {
      // return const InternetRequiredScreen();
    }

    // Don't show any overlay for ready, downloadingTiles states
    return const SizedBox.shrink();
  }

  /// Determine if connectivity screens should be shown based on current state and errors
  Future<bool> _shouldShowConnectivityScreens(MapController controller) async {
    // Always show for these specific states regardless of tile count
    final currentState = controller.currentInitializationState.value;

    // PRIORITY 1: Always show permission screen if permissions are denied
    // Don't show internet screen until permissions are granted
    if (currentState == MapInitializationState.permissionDenied ||
        currentState == MapInitializationState.checkingPermission) {
      return true;
    }

    // PRIORITY 2: Only show internet-related screens after permissions are granted
    if (currentState == MapInitializationState.internetRequired ||
        currentState == MapInitializationState.checkingInternet) {
      return true;
    }

    // Show if no actual internet access (but only if permissions are granted)
    final permissionService = Get.find<PermissionService>();
    if (permissionService.hasLocationPermission.value) {}

    // Show if we're in error state and it might be connectivity-related
    if (currentState == MapInitializationState.error) {
      debugPrint(
        '🌐 Error state detected - showing connectivity screens for potential recovery',
      );
      return true;
    }

    return false;
  }
}
