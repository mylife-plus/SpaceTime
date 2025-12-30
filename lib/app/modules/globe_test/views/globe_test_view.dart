import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import '../controllers/globe_test_controller.dart';

class GlobeTestView extends GetView<GlobeTestController> {
  const GlobeTestView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Tiles Test'),
        backgroundColor: Colors.blue,
      ),
      body: Obx(() {
        // Show error message if any
        if (controller.errorMessage.value != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    controller.errorMessage.value!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Get.back(),
                    child: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          );
        }
        
        // Show loading while server is starting
        if (controller.serverUrl.value == null) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('Starting local tile server...'),
              ],
            ),
          );
        }
        
        // Show map when server is ready
        return Stack(
          children: [
            // Mapbox Globe Map with local tiles
            mapbox.MapWidget(
              key: const ValueKey("globe_test_map"),
              cameraOptions: mapbox.CameraOptions(
                center: mapbox.Point(
                  coordinates: mapbox.Position(0.0, 0.0), // Center of the world
                ),
                zoom: 2.0,
              ),
              // Don't set styleUri - we'll load custom JSON in onMapCreated
              textureView: true,
              onMapCreated: controller.onMapCreated,
              onStyleLoadedListener: controller.onStyleLoaded,
            ),
            
            // Info overlay
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '🗺️ Local Tiles Test',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '📡 Server: ${controller.serverUrl.value}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Obx(() => Text(
                      controller.isMapReady.value
                          ? '✅ Map Ready'
                          : '⏳ Loading map...',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    )),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

