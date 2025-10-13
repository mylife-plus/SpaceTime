import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../../../../config/app_colors.dart';
import '../../controllers/map_controller_new.dart';

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

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
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
    return Obx(
      () => Scaffold(
        backgroundColor:
            uiController.darkMode.value ? Colors.black : Colors.white,
        body: Stack(
          children: [
            if (isLoading)
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
            else if (currentPosition == null)
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
                key: const ValueKey("locationPickerMap"),
                mapOptions: mapbox.MapOptions(
                  contextMode: mapbox.ContextMode.UNIQUE,
                  constrainMode: mapbox.ConstrainMode.HEIGHT_ONLY,
                  viewportMode: mapbox.ViewportMode.DEFAULT,
                  orientation: mapbox.NorthOrientation.UPWARDS,
                  crossSourceCollisions: true,
                  size: mapbox.Size(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                  ),
                  pixelRatio: MediaQuery.of(context).devicePixelRatio,
                ),
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
                    'Done',
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
    );
  }
}
