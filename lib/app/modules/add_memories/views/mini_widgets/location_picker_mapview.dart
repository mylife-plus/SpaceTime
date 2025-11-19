import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/modules/add_memories/controllers/location_picker_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../../../../config/app_colors.dart';

class LocationPickerWidget extends GetView<LocationPickerController> {
  const LocationPickerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize controller
    Get.put(LocationPickerController());

    final uiController = Get.find<UiController>();

    // Internet connectivity checks removed - offline tiles are downloaded during Get Started flow
    return Obx(() {
      debugPrint('[LocationPickerWidget][build] State: isOfflineMode=${controller.isOfflineMode.value}, isLoading=${controller.isLoading.value}');

      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
            if (controller.isLoading.value)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Getting your location...'),
                  ],
                ),
              )
            else if (controller.currentPosition.value == null)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_off, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'Unable to get location',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Please check location permissions',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              mapbox.MapWidget(
                key: const ValueKey("mapbox_map_new"),
                cameraOptions: mapbox.CameraOptions(
                  center: mapbox.Point(
                    coordinates: mapbox.Position(
                      controller.currentPosition.value!.longitude,
                      controller.currentPosition.value!.latitude,
                    ),
                  ),
                  zoom: 1.0,
                ),
      styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
                textureView: true,
                onMapCreated: controller.onMapCreated,
                onTapListener: controller.onMapTap,
                onMapLoadErrorListener: controller.onMapLoadError,
              ),

            // Top right Done button
            if (!controller.isLoading.value && controller.currentPosition.value != null)
              Positioned(
                top: 50,
                right: 20,
                child: TextButton(
                  onPressed: controller.onDonePressed,
                  style: TextButton.styleFrom(
                    backgroundColor: uiController.primaryColor ??
                        (uiController.darkMode.value
                            ? Colors.black.withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.9)),
                    foregroundColor: uiController.darkMode.value
                        ? Colors.white
                        : AppColors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}