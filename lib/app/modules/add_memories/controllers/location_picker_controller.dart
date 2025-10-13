import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/services/connectivity_service.dart';

class LocationPickerController extends GetxController {
  // Services
  late final ConnectivityService connectivityService;
  final addMemoryController = Get.find<AddMemoriesController>();

  // Map related
  mapbox.MapboxMap? mapController;
  mapbox.PointAnnotation? currentLocationMarker;
  mapbox.PointAnnotationManager? annotationManager;

  // Reactive state variables
  final Rx<Position?> currentPosition = Rx<Position?>(null);
  final RxBool isLoading = true.obs;
  final RxBool showInternetRequiredScreen = false.obs;
  final RxBool isCheckingInternet = false.obs;

  @override
  void onInit() {
    super.onInit();
    _initializeServices();
    _checkInternetAndProceed();
  }

  @override
  void onClose() {
    // Clean up resources
    super.onClose();
  }

  void _initializeServices() {
    try {
      connectivityService = Get.find<ConnectivityService>();
      debugPrint('[LocationPickerController] ConnectivityService initialized');

      // Listen for connectivity changes
      ever(connectivityService.isConnected, (bool isConnected) {
        if (isConnected && showInternetRequiredScreen.value) {
          debugPrint('[LocationPickerController] Connectivity restored, retrying...');
          _retryInternetConnection();
        }
      });
    } catch (e) {
      debugPrint('[LocationPickerController] Error initializing ConnectivityService: $e');
    }
  }

  Future<void> _checkInternetAndProceed() async {
    // isCheckingInternet.value = true;

    // try {
    //   debugPrint('[LocationPickerController] Checking internet connectivity...');
      
    //   // Check basic connectivity first
    //   if (!connectivityService.isConnected.value) {
    //     debugPrint('[LocationPickerController] No basic connectivity detected');
    //     showInternetRequiredScreen.value = true;
    //     isCheckingInternet.value = false;
    //     return;
    //   }

    //   // Perform internet ping test
    //   // bool hasInternet = await connectivityService.hasInternetQuickCheck();
      
    //   // debugPrint('[LocationPickerController] Internet ping test result: $hasInternet');
      
    //   // if (hasInternet) {
    //   //   debugPrint('[LocationPickerController] Internet connectivity verified');
    //   //   showInternetRequiredScreen.value = false;
    //   //   isCheckingInternet.value = false;
    //   //   await _getCurrentLocation();
    //   // } else {
    //   //   debugPrint('[LocationPickerController] Internet ping test failed');
    //   //   showInternetRequiredScreen.value = true;
    //   //   isCheckingInternet.value = false;
    //   // }
    // } catch (e) {
    //   debugPrint('[LocationPickerController] Error checking internet: $e');
    //   showInternetRequiredScreen.value = true;
    //   isCheckingInternet.value = false;
    // }
  }

  Future<void> _retryInternetConnection() async {
    debugPrint('[LocationPickerController] Retrying internet connection...');
    await _checkInternetAndProceed();
  }

  void forceShowInternetScreen() {
    debugPrint('[LocationPickerController] Force showing internet required screen');
    showInternetRequiredScreen.value = true;
    isLoading.value = false;
    isCheckingInternet.value = false;
  }

  Future<void> _getCurrentLocation() async {
    try {
      debugPrint('[LocationPickerController] Getting current location...');
      
      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('[LocationPickerController] Location permissions denied');
          isLoading.value = false;
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('[LocationPickerController] Location permissions permanently denied');
        isLoading.value = false;
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      currentPosition.value = position;
      isLoading.value = false;

      debugPrint('[LocationPickerController] Current location: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('[LocationPickerController] Error getting location: $e');
      isLoading.value = false;
    }
  }

  Future<void> addCurrentLocationMarker() async {
    if (mapController == null || currentPosition.value == null) return;

    try {
      // Create annotation manager if not exists
      annotationManager ??= await mapController!.annotations.createPointAnnotationManager();

      // Create custom red marker image
      final imageData = await _createRedMarkerImage();

      // Create point annotation
      final pointAnnotationOptions = mapbox.PointAnnotationOptions(
        geometry: mapbox.Point(
          coordinates: mapbox.Position(
            currentPosition.value!.longitude,
            currentPosition.value!.latitude,
          ),
        ),
        image: imageData,
      );

      // Add marker to map
      currentLocationMarker = await annotationManager!.create(pointAnnotationOptions);

      debugPrint('[LocationPickerController] Current location marker added');
    } catch (e) {
      debugPrint('[LocationPickerController] Error adding current location marker: $e');
    }
  }

  Future<Uint8List> _createRedMarkerImage() async {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    const size = 48.0;
    const radius = size / 2;

    // Draw red circle
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    canvas.drawCircle(const Offset(radius, radius), radius * 0.8, paint);

    // Draw white border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(const Offset(radius, radius), radius * 0.8, borderPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  void onMapTap(mapbox.MapContentGestureContext context) {
    final point = context.point;
    debugPrint('[LocationPickerController] Map tapped at: ${point.coordinates.lng}, ${point.coordinates.lat}');
    
    // Update current position with tapped location
    currentPosition.value = Position(
      latitude: point.coordinates.lat.toDouble(),
      longitude: point.coordinates.lng.toDouble(),
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
      headingAccuracy: 0,
    );

    // Update marker position
    _updateMarkerPosition();
  }

  Future<void> _updateMarkerPosition() async {
    if (mapController == null || currentPosition.value == null || annotationManager == null) return;

    try {
      // Remove existing marker
      if (currentLocationMarker != null) {
        await annotationManager!.delete(currentLocationMarker!);
      }

      // Add new marker at updated position
      await addCurrentLocationMarker();
    } catch (e) {
      debugPrint('[LocationPickerController] Error updating marker position: $e');
    }
  }

  void onDonePressed() {
    if (currentPosition.value != null) {
      // Set the location in the add memories controller
      final locationString =
          '${currentPosition.value!.latitude.toStringAsFixed(6)}, ${currentPosition.value!.longitude.toStringAsFixed(6)}';
      addMemoryController.setLocation(locationString);

      // Return the location string and close the picker
      Get.back(result: locationString);
    }
  }

  void onMapLoadError(mapbox.MapLoadingErrorEventData mapLoadingErrorEventData) async {
    debugPrint('[LocationPickerController] Map load error: ${mapLoadingErrorEventData.message}');
    
    // Check if error is related to internet connectivity
    final errorMessage = mapLoadingErrorEventData.message.toLowerCase();
    final isNetworkError = errorMessage.contains('internet_disconnected') || 
                         errorMessage.contains('network') || 
                         errorMessage.contains('connection') ||
                         errorMessage.contains('server') ||
                         errorMessage.contains('timeout');
    
     final hasSufficientTiles = await _checkOfflineTileCount();

      if (!hasSufficientTiles) {
        debugPrint('[MapControllerNew] ❌ Insufficient offline tiles available, showing Internet Required Screen');
       forceShowInternetScreen();
        return;
      }
   
  }


  /// Check if we have sufficient offline tiles (500+) by fetching from SharedPreferences
  Future<bool> _checkOfflineTileCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tileCount = prefs.getInt('offline_downloaded_tile_count') ?? 0;

      debugPrint('[MapControllerNew] 📊 Fetched offline tile count from SharedPreferences: $tileCount tiles');

      if (tileCount >= 500) {
        debugPrint('[MapControllerNew] ✅ Sufficient tiles available: $tileCount >= 500');
        return true;
      } else {
        debugPrint('[MapControllerNew] ❌ Insufficient tiles: $tileCount < 500');
        return false;
      }
    } catch (e) {
      debugPrint('[MapControllerNew] ❌ Error fetching tile count from SharedPreferences: $e');
      return false;
    }
  }


  void onMapCreated(mapbox.MapboxMap controller) async {
    mapController = controller;
    await addCurrentLocationMarker();
  }
}
