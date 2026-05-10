import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../../../../config/app_colors.dart';
import '../../controllers/map_controller_new.dart';
import 'package:spacetime/app/widgets/location_picker_system_ui_shell.dart';

class LocationPickerWidget extends StatefulWidget {
  const LocationPickerWidget({super.key});

  @override
  State<LocationPickerWidget> createState() => _LocationPickerWidgetState();
}

class _LocationPickerWidgetState extends State<LocationPickerWidget> {
  mapbox.MapboxMap? mapController;
  final mapController2 = Get.find<MapControllerNew>();
  final uiController = Get.find<UiController>();

  Position? currentPosition;
  mapbox.PointAnnotation? currentLocationMarker;
  mapbox.PointAnnotationManager? annotationManager;
  bool isLoading = true;
  bool isOfflineMode = false;

  @override
  void initState() {
    super.initState();
    _checkOfflineMode();
    _getCurrentLocation();
  }

  /// Check if offline tiles are available
  Future<void> _checkOfflineMode() async {
    try {
      // Check if offline tiles are available using SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final tileCount = prefs.getInt('offline_downloaded_tile_count') ?? 0;
      final hasOfflineTiles = tileCount >= 500;

      setState(() {
        isOfflineMode = hasOfflineTiles;
      });
      debugPrint('[LocationPicker] Offline mode: $isOfflineMode (tiles: $tileCount)');
    } catch (e) {
      debugPrint('[LocationPicker] Error checking offline mode: $e');
      setState(() {
        isOfflineMode = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => isLoading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => isLoading = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => isLoading = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        currentPosition = position;
        isLoading = false;
      });

      // If map is already created, add marker
      if (mapController != null) {
        await _addCurrentLocationMarker();
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  /// Configure map for offline use
  Future<void> _configureOfflineMap(mapbox.MapboxMap controller) async {
    try {
      // ALWAYS use online mode to allow localhost tile server access
      // Mapbox's offline mode blocks ALL network requests, including localhost
      // The local tile server serves tiles via HTTP, so we need network access
      debugPrint('[LocationPicker] 🌐 Enabling online mode for localhost tile server');
      await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
      debugPrint('[LocationPicker] ✅ Online mode enabled - localhost tile server can be accessed');
    } catch (e) {
      debugPrint('[LocationPicker] ❌ Error configuring map: $e');
      // On error, still try to enable online mode
      try {
        await mapbox.OfflineSwitch.shared.setMapboxStackConnected(true);
      } catch (e2) {
        debugPrint('[LocationPicker] ❌ Error setting online mode: $e2');
      }
    }
  }

  Future<void> _addCurrentLocationMarker() async {
    if (mapController == null || currentPosition == null) return;

    try {
      // Create red marker image
      final imageBytes = await _createRedMarkerImage();
      const imageName = 'current_location_marker';

      await mapController!.style.addStyleImage(
        imageName,
        1.0,
        mapbox.MbxImage(
          data: imageBytes,
          width: 100,
          height: 100,
        ), // Updated dimensions
        false,
        [],
        [],
        null,
      );

      // Create point annotation manager
      annotationManager =
          await mapController!.annotations.createPointAnnotationManager();

      // Create marker at current location
      final markerOptions = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(
            currentPosition!.longitude,
            currentPosition!.latitude,
          ),
        ),
        iconImage: imageName,
        iconSize: 0.5, // Reduced from 1.0 to compensate for larger image
      );

      final markers = await annotationManager!.createMulti([markerOptions]);
      if (markers.isNotEmpty && markers.first != null) {
        currentLocationMarker = markers.first!;
      }

      // Map tap listener is handled by the MapWidget's onTapListener property

      // Move camera to current location with better zoom level
      await mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              currentPosition!.longitude,
              currentPosition!.latitude,
            ),
          ),
          zoom: 1.0,
        ),
        mapbox.MapAnimationOptions(duration: 1000),
      );
    } catch (e) {
      debugPrint('Error adding marker: $e');
    }
  }

  void _onMapTap(mapbox.MapContentGestureContext context) async {
    if (mapController == null || annotationManager == null) return;

    try {
      // Get the point from the gesture context
      final point = context.point;

      // Delete existing marker
      if (currentLocationMarker != null) {
        await annotationManager!.delete(currentLocationMarker!);
      }

      // Create new marker at tapped location
      final markerOptions = mapbox.PointAnnotationOptions(
        geometry: point,
        iconImage: 'current_location_marker',
        iconSize: 0.5, // Changed from 1.0 to match initial marker size
      );

      final markers = await annotationManager!.createMulti([markerOptions]);
      if (markers.isNotEmpty && markers.first != null) {
        currentLocationMarker = markers.first!;
      }

      // Update current position for the Done button
      currentPosition = Position(
        latitude: point.coordinates.lat.toDouble(),
        longitude: point.coordinates.lng.toDouble(),
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      // Get current zoom level and maintain it
      final currentCamera = await mapController!.getCameraState();
      await mapController!.flyTo(
        mapbox.CameraOptions(center: point, zoom: currentCamera.zoom),
        mapbox.MapAnimationOptions(duration: 500),
      );
    } catch (e) {
      debugPrint('Error handling map tap: $e');
    }
  }

  Future<Uint8List> _createRedMarkerImage() async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    // Increase size for better resolution
    const size = 100.0; // Doubled from 50.0
    const center = Offset(size / 2, size / 2);
    const outerRadius = size / 3;
    const innerRadius = size / 4;

    // Draw outer red circle with better alpha
    final outerPaint =
        Paint()
          ..color = Colors.red.withOpacity(0.4) // Better opacity
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerRadius, outerPaint);

    // Draw inner red circle with solid color
    final innerPaint =
        Paint()
          ..color =
              Colors
                  .red // Use Colors.red instead of hex
          ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius, innerPaint);

    // Draw white border with better stroke width
    final borderPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;
    canvas.drawCircle(center, innerRadius, borderPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  void _onDonePressed() {
    if (currentPosition != null) {
      // Set the location in the map controller
      final locationString =
          '${currentPosition!.latitude.toStringAsFixed(6)}, ${currentPosition!.longitude.toStringAsFixed(6)}';
      mapController2.setLocation(locationString);

      // Return the location string and close the picker
      Get.back(result: locationString);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return LocationPickerSystemUiShell(
      child: Obx(
        () => Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            bottom: false,
            child: Stack(
              children: [
            if (isLoading)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text('text_getting_your_location_2'.tr),
                  ],
                ),
              )
            else if (currentPosition == null)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      'text_unable_to_get_location_2'.tr,
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'text_please_check_location_permissions_2'.tr,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else
              mapbox.MapWidget(
                key: const ValueKey("mapbox_map_new"),
                // mapOptions: mapbox.MapOptions(
                //   contextMode: mapbox.ContextMode.UNIQUE,
                //   constrainMode: mapbox.ConstrainMode.HEIGHT_ONLY,
                //   viewportMode: mapbox.ViewportMode.DEFAULT,
                //   orientation: mapbox.NorthOrientation.UPWARDS,
                //   crossSourceCollisions: true,
                //   size: mapbox.Size(
                //     width: MediaQuery.of(context).size.width,
                //     height: MediaQuery.of(context).size.height,
                //   ),
                //   pixelRatio: MediaQuery.of(context).devicePixelRatio,
                // ),
                cameraOptions: mapbox.CameraOptions(
                  center: mapbox.Point(
                    coordinates: mapbox.Position(
                      currentPosition!.longitude,
                      currentPosition!.latitude,
                    ),
                  ),
                  zoom: 1.0,
                ),
                styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
                textureView: true,
                onMapCreated: (mapbox.MapboxMap controller) async {
                  mapController = controller;
                  await _configureOfflineMap(controller);
                  await _addCurrentLocationMarker();
                },
                onTapListener: _onMapTap,
              ),

            // Top right Done button
            if (currentPosition != null)
              Positioned(
                top: 50,
                right: 20,
                child: TextButton(
                  onPressed: _onDonePressed,

                  style: TextButton.styleFrom(
                    backgroundColor:
                        controller.primaryColor ??
                        (controller.darkMode.value
                            ? Colors.black.withOpacity(0.6)
                            : AppColors.blue),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: Text(
                    'text_done_2'.tr,
                    style: TextStyle(
                      color:
                          controller.darkMode.value
                              ? Colors.white
                              : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

            Positioned(
              top: 50,
              left: 20,
              child: Container(
                padding: EdgeInsets.all(6),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(AppImages.rectangle),
                    fit: BoxFit.cover,
                    colorFilter: controller.rectangleColorFilter,
                  ),
                ),
                child: Image.asset(
                  AppImages.location,
                  fit: BoxFit.contain,
                  color: Colors.white,
                ),
              ),
            ),
            Positioned(
              top: 50,
              left: 75,
              child: Container(
                padding: EdgeInsets.all(6),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(AppImages.rectangle),
                    fit: BoxFit.cover,
                    colorFilter: controller.rectangleColorFilter,
                  ),
                ),
                child: Image.asset(
                  AppImages.searchNormal,
                  fit: BoxFit.contain,
                  color: Colors.white,
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
}
