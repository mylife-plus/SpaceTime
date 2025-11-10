import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:spacetime/app/data/models/location_data.dart';
import 'package:spacetime/app/modules/location_picker/repositories/location_picker_repository.dart';

import 'package:spacetime/services/background_tile_download_service.dart';
import 'package:spacetime/app/services/offline_map_service.dart';
import 'package:spacetime/services/world_locations_service.dart';
import 'package:spacetime/services/offline_location_search_service.dart' as offline;
import 'package:get/get.dart';

class LocationPickerService {
  final LocationPickerRepository _repository = LocationPickerRepository();
  
  // Offline map services
  BackgroundTileDownloadService? _backgroundTileService;
  OfflineMapService? _offlineMapService;
  
  // Location search services
  final WorldLocationsService _worldLocationsService = WorldLocationsService.instance;
  final offline.OfflineLocationSearchService _offlineSearchService = 
      offline.OfflineLocationSearchService.instance;

  // Map components
  mapbox.MapboxMap? _mapController;
  mapbox.PointAnnotationManager? _annotationManager;

  /// Initialize the service
  Future<void> initialize() async {
    try {
      debugPrint('[LocationPickerService] Initializing service...');
      
      // Initialize offline services
      await _initializeOfflineServices();
      
      // Initialize search services
      await _initializeSearchServices();
      
      debugPrint('[LocationPickerService] Service initialized successfully');
    } catch (e) {
      debugPrint('[LocationPickerService] Failed to initialize: $e');
      throw Exception('Service initialization failed: $e');
    }
  }

  /// Initialize offline map services
  Future<void> _initializeOfflineServices() async {
    try {
      // Try to get background tile service
      if (Get.isRegistered<BackgroundTileDownloadService>()) {
        _backgroundTileService = Get.find<BackgroundTileDownloadService>();
        debugPrint('[LocationPickerService] Background tile service found');
      }

      // Try to get offline map service
      if (Get.isRegistered<OfflineMapService>()) {
        _offlineMapService = Get.find<OfflineMapService>();
      } else {
        _offlineMapService = Get.put(OfflineMapService(), permanent: true);
      }
      
      debugPrint('[LocationPickerService] Offline services initialized');
    } catch (e) {
      debugPrint('[LocationPickerService] Error initializing offline services: $e');
    }
  }

  /// Initialize search services
  Future<void> _initializeSearchServices() async {
    try {
      await Future.wait([
        _worldLocationsService.initialize(),
        _offlineSearchService.initialize(),
      ]);
      debugPrint('[LocationPickerService] Search services initialized');
    } catch (e) {
      debugPrint('[LocationPickerService] Error initializing search services: $e');
    }
  }

  /// Set map controller
  void setMapController(mapbox.MapboxMap controller) {
    _mapController = controller;
    debugPrint('[LocationPickerService] Map controller set');
  }

  /// Set annotation manager
  void setAnnotationManager(mapbox.PointAnnotationManager manager) {
    _annotationManager = manager;
    debugPrint('[LocationPickerService] Annotation manager set');
  }

  /// Update zoom level (no longer needed for GeoJSON circles)
  Future<void> updateZoom(double zoom) async {
    // GeoJSON circles automatically scale with zoom, no action needed
    debugPrint('[LocationPickerService] Zoom updated to: $zoom (GeoJSON circles auto-scale)');
  }



  /// Check if offline tiles are available
  Future<bool> areOfflineTilesAvailable() async {
    try {
      if (_backgroundTileService != null) {
        final tileCount = _backgroundTileService!.totalTilesDownloaded.value;
        return tileCount >= 30000; // Same threshold as map controller
      }
      
      if (_offlineMapService != null) {
        return _offlineMapService!.isOfflineReady.value;
      }
      
      return false;
    } catch (e) {
      debugPrint('[LocationPickerService] Error checking offline tiles: $e');
      return false;
    }
  }

  /// Get optimal style URI for offline mode
  String getOptimalStyleUri() {
    // Use same logic as map controller for consistency
    return mapbox.MapboxStyles.STANDARD;
  }

  /// Configure offline map
  Future<void> configureOfflineMap(mapbox.MapboxMap controller) async {
    try {

      final hasOfflineTiles = await areOfflineTilesAvailable();

      if (hasOfflineTiles) {
        debugPrint('[LocationPickerService] Configuring for offline mode');

        // Enable offline mode similar to map controller
        await _enableOfflineMode(controller);

        // Set offline-optimized style
        await controller.style.setStyleURI(getOptimalStyleUri());

        debugPrint('[LocationPickerService] Offline mode configured successfully');
      } else {
        debugPrint('[LocationPickerService] Using online mode - insufficient tiles');
        
        await controller.style.setStyleURI(getOptimalStyleUri()); 
     }
    } catch (e) {
      debugPrint('[LocationPickerService] Error configuring offline map: $e');
      // Fallback to online mode
      try {
        await controller.style.setStyleURI(getOptimalStyleUri());
      } catch (fallbackError) {
        debugPrint('[LocationPickerService] Fallback configuration failed: $fallbackError');
      }
    }
  }

  /// Enable offline mode for the map
  Future<void> _enableOfflineMode(mapbox.MapboxMap controller) async {
    try {
      // Configure offline settings similar to main map controller
      if (_backgroundTileService != null && _backgroundTileService!.forceOfflineMode.value) {
        debugPrint('[LocationPickerService] Force offline mode enabled');
        // Additional offline configuration can be added here
      }

      // Set up offline tile source if available
      await _configureOfflineTileSource(controller);

    } catch (e) {
      debugPrint('[LocationPickerService] Error enabling offline mode: $e');
    }
  }

  /// Configure offline tile source
  Future<void> _configureOfflineTileSource(mapbox.MapboxMap controller) async {
    try {
      // This would configure the tile source to use downloaded tiles
      // Implementation depends on how tiles are stored and accessed
      debugPrint('[LocationPickerService] Configuring offline tile source');

      // For now, we rely on the MapboxMap's built-in offline capabilities
      // The actual tile management is handled by the background services

    } catch (e) {
      debugPrint('[LocationPickerService] Error configuring offline tile source: $e');
    }
  }

  /// Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      return await _repository.getCurrentPosition();
    } catch (e) {
      debugPrint('[LocationPickerService] Error getting current location: $e');
      return null;
    }
  }

  /// Check location permissions
  Future<bool> hasLocationPermission() async {
    return await _repository.hasLocationPermission();
  }

  /// Request location permissions
  Future<bool> requestLocationPermission() async {
    return await _repository.requestLocationPermission();
  }

  /// Search locations
  Future<List<Map<String, dynamic>>> searchLocations(String query, {bool isOfflineMode = false}) async {
    try {
      if (query.isEmpty) return [];

      List<Map<String, dynamic>> results = [];

      // Use offline search service
      if (_offlineSearchService.isInitialized) {
        final offlineResults = await _offlineSearchService.searchLocations(
          query,
          limit: 15,
          forceOffline: isOfflineMode,
        );

        results = offlineResults.map((result) => {
          'name': result.displayName,
          'address': result.shortDisplayName,
          'latitude': result.latitude,
          'longitude': result.longitude,
          'country': result.country,
          'region': result.state ?? '',
          'city': result.city,
          'postcode': '',
          'timestamp': DateTime.now().toIso8601String(),
          'type': result.type.toString(),
          'source': 'offline_search',
        }).toList();
      }

      return results;
    } catch (e) {
      debugPrint('[LocationPickerService] Error searching locations: $e');
      return [];
    }
  }





  /// Remove existing marker and radius layers
  Future<void> _removeExistingLayers() async {
    try {
      if (_mapController == null) return;

      // Step 1: Remove all layers first (they depend on sources)
      final layersToRemove = ["marker-layer", "radius-fill-layer", "radius-outline-layer"];
      for (final layerId in layersToRemove) {
        try {
          await _mapController!.style.removeStyleLayer(layerId);
          debugPrint('[LocationPickerService] Removed layer: $layerId');
        } catch (e) {
          // Layer doesn't exist, this is expected on first run
          debugPrint('[LocationPickerService] Layer $layerId not found (expected)');
        }
      }

      // Step 2: Wait a bit to ensure layers are fully removed
      await Future.delayed(const Duration(milliseconds: 200));

      // Step 3: Remove sources after all layers are removed
      final sourcesToRemove = ["marker-source", "radius-source"];
      for (final sourceId in sourcesToRemove) {
        // Try multiple times with increasing delays
        bool sourceRemoved = false;
        for (int attempt = 0; attempt < 3 && !sourceRemoved; attempt++) {
          try {
            await _mapController!.style.removeStyleSource(sourceId);
            debugPrint('[LocationPickerService] Removed source: $sourceId (attempt ${attempt + 1})');
            sourceRemoved = true;
          } catch (e) {
            debugPrint('[LocationPickerService] Source $sourceId removal attempt ${attempt + 1} failed: $e');
            if (attempt < 2) {
              await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
            }
          }
        }
      }

      // Step 4: Final delay to ensure everything is cleaned up
      await Future.delayed(const Duration(milliseconds: 200));

      debugPrint('[LocationPickerService] Layer cleanup completed');
    } catch (e) {
      debugPrint('[LocationPickerService] Error in layer cleanup: $e');
    }
  }

  /// Add marker to map with accurate GeoJSON radius circle
  Future<void> addMarker(double latitude, double longitude, {double radius = 10.0}) async {
    try {
      if (_mapController == null || _annotationManager == null) {
        debugPrint('[LocationPickerService] Map controller or annotation manager not set');
        return;
      }

      // Wait for map style to be loaded
      await _waitForStyleLoaded();

      // Remove existing marker and radius layers
      await _removeExistingLayers();

      // Create a simple red circle marker using CircleAnnotation instead
      await _addSimpleMarker(latitude, longitude);

      // Add accurate radius circle using GeoJSON
      await _addRadiusCircle(latitude, longitude, radius);

      // Adjust camera zoom to fit the radius circle
      debugPrint('[LocationPickerService] About to call _adjustCameraForRadius with radius: ${radius}km');
      await _adjustCameraForRadius(latitude, longitude, radius);
      debugPrint('[LocationPickerService] _adjustCameraForRadius completed');

      debugPrint('[LocationPickerService] Marker and radius circle added at $latitude, $longitude with ${radius}km radius');
    } catch (e) {
      debugPrint('[LocationPickerService] Error adding marker: $e');
    }
  }

  /// Wait for map style to be loaded
  Future<void> _waitForStyleLoaded() async {
    if (_mapController == null) return;

    try {
      // Check if style is loaded, if not wait a bit
      int attempts = 0;
      while (attempts < 10) {
        try {
          // Try to access style - this will throw if not loaded
          await _mapController!.style.getStyleURI();
          break;
        } catch (e) {
          attempts++;
          if (attempts >= 10) {
            debugPrint('[LocationPickerService] Style loading timeout after 10 attempts');
            break;
          }
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
    } catch (e) {
      debugPrint('[LocationPickerService] Error waiting for style: $e');
    }
  }

  /// Add simple red circle marker
  Future<void> _addSimpleMarker(double lat, double lon) async {
    try {
      if (_mapController == null) return;

      // Create a simple point GeoJSON for the marker
      final markerGeoJson = {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "properties": {},
            "geometry": {
              "type": "Point",
              "coordinates": [lon, lat],
            }
          }
        ]
      };

      // Add marker source with robust error handling
      bool markerSourceAdded = false;
      for (int attempt = 0; attempt < 3 && !markerSourceAdded; attempt++) {
        try {
          await _mapController!.style.addSource(
            mapbox.GeoJsonSource(
              id: "marker-source",
              data: jsonEncode(markerGeoJson),
            ),
          );
          debugPrint('[LocationPickerService] Marker source added successfully (attempt ${attempt + 1})');
          markerSourceAdded = true;
        } catch (e) {
          debugPrint('[LocationPickerService] Marker source add attempt ${attempt + 1} failed: $e');
          if (attempt < 2) {
            // Try to clean up and wait before retry
            try {
              await _mapController!.style.removeStyleSource("marker-source");
            } catch (_) {}
            await Future.delayed(Duration(milliseconds: 50 * (attempt + 1)));
          }
        }
      }

      if (!markerSourceAdded) {
        debugPrint('[LocationPickerService] Failed to add marker source after 3 attempts');
        return;
      }

      // Add marker layer (red circle)
      final markerLayer = mapbox.CircleLayer(
        id: "marker-layer",
        sourceId: "marker-source",
      );
      markerLayer.circleRadius = 8.0;
      markerLayer.circleColor = 0xFFFF4444; // Red color
      markerLayer.circleStrokeColor = 0xFFFFFFFF; // White stroke
      markerLayer.circleStrokeWidth = 2.0;
      await _mapController!.style.addLayer(markerLayer);

      debugPrint('[LocationPickerService] Simple marker added at $lat, $lon');
    } catch (e) {
      debugPrint('[LocationPickerService] Error adding simple marker: $e');
    }
  }

  /// Add accurate radius circle using GeoJSON
  Future<void> _addRadiusCircle(double lat, double lon, double radiusKm) async {
    try {
      if (_mapController == null) return;

      // Convert km to meters
      final radiusMeters = radiusKm * 1000;

      debugPrint('[LocationPickerService] Adding radius circle: ${radiusKm}km (${radiusMeters}m) at lat=$lat, lon=$lon');

      // Create GeoJSON circle
      final circleGeoJson = _buildCircleGeoJson(lat, lon, radiusMeters);

      // Add radius source with robust error handling
      bool radiusSourceAdded = false;
      for (int attempt = 0; attempt < 3 && !radiusSourceAdded; attempt++) {
        try {
          await _mapController!.style.addSource(
            mapbox.GeoJsonSource(
              id: "radius-source",
              data: jsonEncode(circleGeoJson),
            ),
          );
          debugPrint('[LocationPickerService] Radius source added successfully (attempt ${attempt + 1})');
          radiusSourceAdded = true;
        } catch (e) {
          debugPrint('[LocationPickerService] Radius source add attempt ${attempt + 1} failed: $e');
          if (attempt < 2) {
            // Try to clean up and wait before retry
            try {
              await _mapController!.style.removeStyleSource("radius-source");
            } catch (_) {}
            await Future.delayed(Duration(milliseconds: 50 * (attempt + 1)));
          }
        }
      }

      if (!radiusSourceAdded) {
        debugPrint('[LocationPickerService] Failed to add radius source after 3 attempts');
        return;
      }

      // Add FillLayer (for the filled area) - Blue color
      final fillLayer = mapbox.FillLayer(
        id: "radius-fill-layer",
        sourceId: "radius-source",
      );
      fillLayer.fillColor = 0xFF2196F3; // Blue color (Material Blue 500)
      fillLayer.fillOpacity = 0.25;
      await _mapController!.style.addLayer(fillLayer);

      // Add outline (stroke) around the circle - Blue color
      final lineLayer = mapbox.LineLayer(
        id: "radius-outline-layer",
        sourceId: "radius-source",
      );
      lineLayer.lineColor = 0xFF2196F3; // Blue color (Material Blue 500)
      lineLayer.lineWidth = 2.0;
      await _mapController!.style.addLayer(lineLayer);

      debugPrint('[LocationPickerService] Radius circle added: ${radiusKm}km (${radiusMeters}m)');
    } catch (e) {
      debugPrint('[LocationPickerService] Error adding radius circle: $e');
    }
  }

  /// Create a GeoJSON polygon circle in meters for accurate radius display
  Map<String, dynamic> _buildCircleGeoJson(double lat, double lon, double radiusMeters, {int points = 64}) {
    final List<List<double>> coords = [];
    const earthRadius = 6371000.0; // meters

    final double latRad = lat * math.pi / 180;
    final double lonRad = lon * math.pi / 180;

    for (int i = 0; i < points; i++) {
      final double bearing = 2 * math.pi * (i / points);
      final double angularDistance = radiusMeters / earthRadius;

      final double lat2 = math.asin(
        math.sin(latRad) * math.cos(angularDistance) + math.cos(latRad) * math.sin(angularDistance) * math.cos(bearing),
      );
      final double lon2 = lonRad +
          math.atan2(
            math.sin(bearing) * math.sin(angularDistance) * math.cos(latRad),
            math.cos(angularDistance) - math.sin(latRad) * math.sin(lat2),
          );

      coords.add([lon2 * 180 / math.pi, lat2 * 180 / math.pi]);
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

  /// Move camera to location
  Future<void> moveCameraToLocation(double latitude, double longitude, {double? zoom}) async {
    try {
      if (_mapController == null) return;

      await _mapController!.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(longitude, latitude),
          ),
          zoom: zoom ?? 14.0,
        ),
        mapbox.MapAnimationOptions(duration: 1000),
      );
    } catch (e) {
      debugPrint('[LocationPickerService] Error moving camera: $e');
    }
  }

  /// Adjust camera zoom to fit the radius circle
  Future<void> _adjustCameraForRadius(double latitude, double longitude, double radiusKm) async {
    debugPrint('[LocationPickerService] === _adjustCameraForRadius ENTRY === radius: ${radiusKm}km');
    try {
      if (_mapController == null) {
        debugPrint('[LocationPickerService] _mapController is null, cannot adjust camera');
        return;
      }

      debugPrint('[LocationPickerService] Calculating zoom level for radius: ${radiusKm}km');

      // Calculate appropriate zoom level based on radius
      // This formula approximates the zoom level needed to fit a circle of given radius
      // Zoom levels: 1 = world view, 20 = building level
      double zoom;

      if (radiusKm <= 5) {
        zoom = 10.5; // Neighborhood level
      } else if (radiusKm <= 10) {
        zoom = 9.5; // City area
      } else if (radiusKm <= 25) {
        zoom = 8.5; // Metropolitan area
      } else if (radiusKm <= 50) {
        zoom =7.5; // Large city area
      } else if (radiusKm <= 100) {
        zoom = 6.5; // Regional level
      } else if (radiusKm <= 200) {
        zoom = 5.5; // State/province level
      } else if (radiusKm <= 500) {
        zoom = 5.5; // Large state/small country
      } else if (radiusKm <= 1000) {
        zoom = 4.0; // Country level
      } else if (radiusKm <= 2000) {
        zoom = .0; // Large country/continent
      } else {
        zoom = 2.0; // Continental/global view
      }

      debugPrint('[LocationPickerService] Calculated zoom level: $zoom for radius: ${radiusKm}km');

      // Use easeTo for faster, more responsive camera changes
      // This is less animated but more immediate for rapid radius changes
      await _mapController!.easeTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(longitude, latitude),
          ),
          zoom: zoom,
        ),
        mapbox.MapAnimationOptions(duration: 500), // Even faster for immediate response
      );

      debugPrint('[LocationPickerService] Camera adjusted for ${radiusKm}km radius with zoom level $zoom');
    } catch (e) {
      debugPrint('[LocationPickerService] Error adjusting camera for radius: $e');
    }
  }

  /// Get location information from coordinates
  Future<LocationData?> getLocationInfo(double latitude, double longitude) async {
    try {
      // Use reverse geocoding to get location information
      // This would typically use a geocoding service
      // For now, create basic location data
      return LocationData(
        latitude: latitude,
        longitude: longitude,
        address: 'Selected Location',
        city: 'Unknown City',
        state: 'Unknown State',
        country: 'Unknown Country',
        timestamp: DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('[LocationPickerService] Error getting location info: $e');
      return null;
    }
  }

  /// Save location data
  Future<void> saveLocation(LocationData locationData) async {
    try {
      await _repository.saveSelectedLocation(locationData);
      await _repository.saveRecentLocation(locationData);
    } catch (e) {
      debugPrint('[LocationPickerService] Error saving location: $e');
      throw Exception('Failed to save location: $e');
    }
  }

  /// Save radius
  Future<void> saveRadius(double radius) async {
    try {
      await _repository.saveRadius(radius);
    } catch (e) {
      debugPrint('[LocationPickerService] Error saving radius: $e');
      throw Exception('Failed to save radius: $e');
    }
  }

  /// Get saved location
  Future<LocationData?> getSavedLocation() async {
    try {
      return await _repository.getSavedLocation();
    } catch (e) {
      debugPrint('[LocationPickerService] Error getting saved location: $e');
      return null;
    }
  }

  /// Get saved radius
  Future<double> getSavedRadius() async {
    try {
      return await _repository.getSavedRadius();
    } catch (e) {
      debugPrint('[LocationPickerService] Error getting saved radius: $e');
      return 10.0; // Default
    }
  }

  /// Get recent locations
  Future<List<LocationData>> getRecentLocations() async {
    try {
      return await _repository.getRecentLocations();
    } catch (e) {
      debugPrint('[LocationPickerService] Error getting recent locations: $e');
      return [];
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      // Clean up map sources and layers before disposing
      await _removeExistingLayers();
      debugPrint('[LocationPickerService] Map layers cleaned up');
    } catch (e) {
      debugPrint('[LocationPickerService] Error during cleanup: $e');
    }

    _annotationManager = null;
    _mapController = null;
    debugPrint('[LocationPickerService] Service disposed');
  }
}
