import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'dart:math' as math;
import 'dart:convert';
import '../models/memory_cluster.dart';
import '../../services/memory_clustering_service.dart' as clustering;
import '../repositories/memory_repository.dart';
import '../modules/map/views/mini_widgets/click_listener.dart';
import 'map_marker_creation_service.dart';

/// Service for managing map markers and annotations
class MapMarkerService extends GetxService {
  static MapMarkerService get instance => Get.find<MapMarkerService>();

  mapbox.MapboxMap? _mapboxMap;
  mapbox.PointAnnotationManager? _annotationManager;

  // Arrow layer constants for GeoJSON approach
  static const String ARROW_LINES_SOURCE_ID = 'arrow-lines-source';
  static const String ARROW_LINES_LAYER_ID = 'arrow-lines-layer';

  // Marker creation service
  MapMarkerCreationService? _markerCreationService;

  // Marker management
  final RxList<String> clusterMarkerIds = <String>[].obs;
  final RxList<String> individualMarkerIds = <String>[].obs;
  final RxBool isUpdatingMarkers = false.obs;

  // Arrow management
  final RxList<clustering.ChronologicalArrow> currentArrows =
      <clustering.ChronologicalArrow>[].obs;

  // Annotation tracking for tap callbacks
  final Map<String, MemoryCluster> _clusterAnnotationsById = {};
  final Map<String, Map<String, dynamic>> _memoryAnnotationsById = {};
  bool _annotationClickListenerRegistered = false;

  // Callbacks
  Function(MemoryCluster)? onClusterTapped;
  Function(Map<String, dynamic>)? onMemoryTapped;

  @override
  void onInit() {
    super.onInit();
    debugPrint('[MapMarkerService] Service initialized');
  }

  /// Get marker creation service with lazy initialization
  MapMarkerCreationService get markerCreationService {
    _markerCreationService ??= Get.find<MapMarkerCreationService>();
    return _markerCreationService!;
  }

  /// Initialize with MapBox map instance
  void initialize(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    debugPrint('[MapMarkerService] Initialized with MapBox map');
  }

  /// Set marker tap callbacks
  void setCallbacks({
    Function(MemoryCluster)? onClusterTap,
    Function(Map<String, dynamic>)? onMemoryTap,
  }) {
    onClusterTapped = onClusterTap;
    onMemoryTapped = onMemoryTap;
  }

  /// Update markers on the map
  Future<void> updateMarkers({
    required List<MemoryCluster> clusters,
    required List<Map<String, dynamic>> individualMemories,
  }) async {
    if (_mapboxMap == null) {
      debugPrint('[MapMarkerService] MapBox map not initialized');
      return;
    }

    try {
      isUpdatingMarkers.value = true;
      debugPrint(
        '[MapMarkerService] Updating markers: ${clusters.length} clusters, ${individualMemories.length} individual',
      );

      // Clear existing markers
      await _clearAllMarkers();

      // Add cluster markers
      await _addClusterMarkers(clusters);

      // Add individual memory markers
      await _addIndividualMarkers(individualMemories);

      debugPrint('[MapMarkerService] Markers updated successfully');
    } catch (e) {
      debugPrint('[MapMarkerService] Error updating markers: $e');
    } finally {
      isUpdatingMarkers.value = false;
    }
  }

  /// Add cluster markers to the map
  Future<void> _addClusterMarkers(List<MemoryCluster> clusters) async {
    // Create annotation manager if needed
    if (_annotationManager == null) {
      _annotationManager =
          await _mapboxMap!.annotations.createPointAnnotationManager();
    }

    final List<mapbox.PointAnnotationOptions> markerOptions = [];
    final List<MemoryCluster> clustersForMarkers = [];

    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      try {
        final markerId = 'cluster_${cluster.id}';

        // Get the earliest memory date for color consistency
        final memoryDate = cluster.earliestDate ?? DateTime.now();

        // Create cluster marker image using the new service
        final imageBytes = await markerCreationService.createClusterMarkerImage(
          memoryCount: cluster.count,
          isSingleMemory: cluster.count == 1,
          memoryDate: memoryDate,
          clusterId: cluster.id,
        );

        // Add style image to map
        final imageName = 'cluster_marker_${cluster.id}';
        await _mapboxMap!.style.addStyleImage(
          imageName,
          1.0,
          mapbox.MbxImage(data: imageBytes, width: 60, height: 60),
          false,
          [],
          [],
          null,
        );

        // Create cluster annotation
        final annotation = mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(cluster.longitude, cluster.latitude),
          ),
          iconImage: imageName,
          iconSize: 1.0,
        );

        markerOptions.add(annotation);
        clusterMarkerIds.add(markerId);
        clustersForMarkers.add(cluster);
      } catch (e) {
        debugPrint(
          '[MapMarkerService] Error creating cluster marker for ${cluster.id}: $e',
        );
      }
    }

    // Create all markers at once
    if (markerOptions.isNotEmpty) {
      try {
        final created = await _annotationManager!.createMulti(markerOptions);
        debugPrint(
          '[MapMarkerService] Created ${created.length} cluster markers',
        );
        for (
          var i = 0;
          i < created.length && i < clustersForMarkers.length;
          i++
        ) {
          final annotation = created[i];
          if (annotation == null) continue;
          _clusterAnnotationsById[annotation.id] = clustersForMarkers[i];
        }

        _ensureAnnotationClickListener();
      } catch (e) {
        debugPrint('[MapMarkerService] Error creating cluster markers: $e');
      }
    }
  }

  /// Add individual memory markers to the map
  Future<void> _addIndividualMarkers(
    List<Map<String, dynamic>> memories,
  ) async {
    debugPrint(
      '[MapMarkerService] Adding ${memories.length} individual markers',
    );

    if (memories.isEmpty) {
      debugPrint('[MapMarkerService] No individual memories to display');
      return;
    }

    // Create annotation manager if needed (reuse the same one as clusters)
    if (_annotationManager == null) {
      _annotationManager =
          await _mapboxMap!.annotations.createPointAnnotationManager();
    }

    final List<mapbox.PointAnnotationOptions> markerOptions = [];
    final List<Map<String, dynamic>> memoriesForMarkers = [];

    for (final memory in memories) {
      try {
        final lat = memory['location_latitude'] as double?;
        final lng = memory['location_longitude'] as double?;
        final memoryId = memory['id']?.toString();

        if (lat == null || lng == null || memoryId == null) {
          debugPrint(
            '[MapMarkerService] Skipping memory ${memory['id']} - missing location data',
          );
          continue;
        }

        final markerId = 'memory_$memoryId';

        // Get memory date for color consistency
        final memoryDate =
            DateTime.tryParse(memory['memory_date'] ?? '') ?? DateTime.now();

        // Create individual memory marker image using the marker creation service
        final imageBytes = await markerCreationService.createClusterMarkerImage(
          memoryCount: 1,
          isSingleMemory: true,
          memoryDate: memoryDate,
          clusterId: markerId,
        );

        // Add style image to map
        final imageName = 'individual_marker_$memoryId';
        await _mapboxMap!.style.addStyleImage(
          imageName,
          1.0,
          mapbox.MbxImage(data: imageBytes, width: 60, height: 60),
          false,
          [],
          [],
          null,
        );

        // Create memory annotation
        final annotation = mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
          iconImage: imageName,
          iconSize: 0.6, // Slightly smaller than clusters
        );

        markerOptions.add(annotation);
        individualMarkerIds.add(markerId);
        memoriesForMarkers.add(memory);

        debugPrint(
          '[MapMarkerService] Prepared individual marker for memory $memoryId at $lat, $lng',
        );
      } catch (e) {
        debugPrint(
          '[MapMarkerService] Error preparing individual marker for memory ${memory['id']}: $e',
        );
      }
    }

    // Create all individual markers at once
    if (markerOptions.isNotEmpty) {
      try {
        final created = await _annotationManager!.createMulti(markerOptions);
        debugPrint(
          '[MapMarkerService] Created ${created.length} individual memory markers',
        );
        for (
          var i = 0;
          i < created.length && i < memoriesForMarkers.length;
          i++
        ) {
          final annotation = created[i];
          if (annotation == null) continue;
          _memoryAnnotationsById[annotation.id] = memoriesForMarkers[i];
        }

        _ensureAnnotationClickListener();
      } catch (e) {
        debugPrint('[MapMarkerService] Error creating individual markers: $e');
      }
    } else {
      debugPrint('[MapMarkerService] No valid individual markers to create');
    }
  }

  /// Clear all markers from the map
  Future<void> _clearAllMarkers() async {
    try {
      debugPrint('[MapMarkerService] Clearing all markers');

      // Clear all annotations using the annotation manager
      if (_annotationManager != null) {
        await _annotationManager!.deleteAll();
        debugPrint(
          '[MapMarkerService] Cleared all annotations from annotation manager',
        );
      }

      // Clear marker ID tracking
      clusterMarkerIds.clear();
      individualMarkerIds.clear();
      _clusterAnnotationsById.clear();
      _memoryAnnotationsById.clear();

      debugPrint('[MapMarkerService] Marker clearing completed');
    } catch (e) {
      debugPrint('[MapMarkerService] Error clearing markers: $e');
    }
  }

  void _ensureAnnotationClickListener() {
    if (_annotationManager == null || _annotationClickListenerRegistered) {
      return;
    }

    _annotationManager!.addOnPointAnnotationClickListener(
      AnnotationClickListener((annotation) {
        final cluster = _clusterAnnotationsById[annotation.id];
        if (cluster != null) {
          _handleClusterTap(cluster);
          return;
        }

        final memory = _memoryAnnotationsById[annotation.id];
        if (memory != null) {
          _handleMemoryTap(memory);
          return;
        }

        debugPrint(
          '[MapMarkerService] ⚠️ No mapped data for tapped annotation ${annotation.id}',
        );
      }),
    );

    _annotationClickListenerRegistered = true;
  }

  /// Handle cluster tap - show cluster details and provide interaction options
  void _handleClusterTap(MemoryCluster cluster) {
    if (onClusterTapped != null) {
      onClusterTapped!(cluster);
      return;
    }

    try {
      debugPrint('[MapMarkerService] 🎯 Cluster tapped: ${cluster.id}');
      debugPrint(
        '[MapMarkerService] 📍 Cluster location: ${cluster.latitude}, ${cluster.longitude}',
      );
      debugPrint(
        '[MapMarkerService] 📊 Cluster contains ${cluster.count} memories',
      );
      debugPrint(
        '[MapMarkerService] 🏷️  Cluster categories: ${cluster.categories.join(', ')}',
      );

      // Show cluster details in a snackbar
      final categoryText =
          cluster.categories.isNotEmpty ? cluster.categories.first : 'Mixed';
      Get.snackbar(
        '📍 Memory Cluster',
        '${cluster.count} memories in $categoryText\nTap to zoom or view details',
        backgroundColor: Colors.blue.withValues(alpha: 0.9),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        borderRadius: 8,
        isDismissible: true,
        mainButton: TextButton(
          onPressed: () {
            Get.back(); // Close snackbar
            _showClusterDetails(cluster);
          },
          child: const Text(
            'Details',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[MapMarkerService] ❌ Error handling cluster tap: $e');
      Get.snackbar(
        'Error',
        'Could not load cluster details',
        backgroundColor: Colors.red.withValues(alpha: 0.8),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// Show detailed cluster information
  void _showClusterDetails(MemoryCluster cluster) {
    debugPrint(
      '[MapMarkerService] 📋 Showing details for cluster: ${cluster.id}',
    );

    // Create a detailed description
    final details = StringBuffer();
    details.writeln(
      '📍 Location: ${cluster.latitude.toStringAsFixed(4)}, ${cluster.longitude.toStringAsFixed(4)}',
    );
    details.writeln('🏷️  Categories: ${cluster.categories.join(', ')}');
    details.writeln('📊 Memories: ${cluster.count}');

    // Format date range
    if (cluster.earliestDate != null && cluster.latestDate != null) {
      final startDate = cluster.earliestDate!;
      final endDate = cluster.latestDate!;
      if (startDate.year == endDate.year &&
          startDate.month == endDate.month &&
          startDate.day == endDate.day) {
        details.writeln(
          '📅 Date: ${startDate.day}/${startDate.month}/${startDate.year}',
        );
      } else {
        details.writeln(
          '📅 Date Range: ${startDate.day}/${startDate.month}/${startDate.year} - ${endDate.day}/${endDate.month}/${endDate.year}',
        );
      }
    }

    if (cluster.summary.isNotEmpty) {
      details.writeln('📝 Summary: ${cluster.summary}');
    }

    // Show tags if any
    if (cluster.tags.isNotEmpty) {
      details.writeln('🏷️  Tags: ${cluster.tags.join(', ')}');
    }

    Get.dialog(
      AlertDialog(
        title: const Text('📍 Memory Cluster Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(details.toString()),
              const SizedBox(height: 16),
              Text(
                'Memories in this cluster:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...cluster.memories.map(
                (memory) => Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 4),
                  child: Text(
                    '• ${memory['description'] ?? memory['category'] ?? 'Memory ${memory['id']}'}',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Close')),
          ElevatedButton(
            onPressed: () {
              Get.back();
              // TODO: Implement zoom to cluster bounds
              debugPrint('[MapMarkerService] 🔍 Would zoom to cluster bounds');
            },
            child: const Text('Zoom to Cluster'),
          ),
        ],
      ),
    );
  }

  /// Find cluster or memory near the tapped location with dynamic radius based on zoom
  void handleLocationTap(
    double lat,
    double lng,
    List<MemoryCluster> clusters,
    List<Map<String, dynamic>> memories, {
    double? zoomLevel,
  }) {
    debugPrint(
      '[MapMarkerService] 🎯 Handling location tap at: ($lat, $lng), zoom: $zoomLevel',
    );

    // Dynamic tap radius based on zoom level
    // Higher zoom = smaller radius (more precise), lower zoom = larger radius (easier to tap)
    double tapRadius;
    if (zoomLevel != null) {
      if (zoomLevel >= 15) {
        tapRadius = 0.05; // ~100m for high zoom (precise)
      } else if (zoomLevel >= 12) {
        tapRadius = 0.005; // ~500m for medium zoom
      } else if (zoomLevel >= 10) {
        tapRadius = 0.01; // ~1km for medium-low zoom
      } else if (zoomLevel >= 8) {
        tapRadius = 0.02; // ~2km for low zoom
      } else if (zoomLevel >= 5) {
        tapRadius = 0.1; // ~10km for low zoom
      } else {
        tapRadius =
            1.0; // ~100km for very low zoom (world view) - very generous for testing
      }
    } else {
      tapRadius = 0.01; // Default fallback
    }

    debugPrint(
      '[MapMarkerService] 📏 Using dynamic tap radius: ${tapRadius.toStringAsFixed(4)} degrees (~${(tapRadius * 111).toStringAsFixed(0)}km) for zoom $zoomLevel',
    );

    // First, check if tap is near any cluster
    for (final cluster in clusters) {
      final distance = _calculateDistance(
        lat,
        lng,
        cluster.latitude,
        cluster.longitude,
      );
      if (distance <= tapRadius) {
        debugPrint(
          '[MapMarkerService] 🎯 Found cluster near tap: ${cluster.id}',
        );
        _handleClusterTap(cluster);
        return;
      }
    }

    // If no cluster found, check individual memories
    debugPrint(
      '[MapMarkerService] 🔍 Checking ${memories.length} individual memories...',
    );
    for (final memory in memories) {
      final memoryLat = memory['location_latitude'] as double?;
      final memoryLng = memory['location_longitude'] as double?;

      if (memoryLat != null && memoryLng != null) {
        final distance = _calculateDistance(lat, lng, memoryLat, memoryLng);
        debugPrint(
          '[MapMarkerService] 📏 Memory ${memory['id']} at ($memoryLat, $memoryLng) - distance: ${distance.toStringAsFixed(6)} (threshold: $tapRadius)',
        );
        if (distance <= tapRadius) {
          debugPrint(
            '[MapMarkerService] 🎯 Found memory near tap: ${memory['id']}',
          );
          _handleMemoryTap(memory);
          return;
        }
      }
    }

    // No cluster or memory found near tap
    debugPrint(
      '[MapMarkerService] 📍 No cluster or memory found near tap location',
    );
  }

  /// Handle individual memory tap
  void _handleMemoryTap(Map<String, dynamic> memory) {
    if (onMemoryTapped != null) {
      onMemoryTapped!(memory);
      return;
    }

    debugPrint('[MapMarkerService] 🎯 Memory tapped: ${memory['id']}');

    final category = memory['category'] ?? 'Unknown';
    final description = memory['description'] ?? '';
    final locationName = memory['location_name'] ?? 'Unknown location';
    final date = memory['date'] ?? '';

    Get.snackbar(
      '📝 Memory',
      '$category${description.isNotEmpty ? ': $description' : ''}\n📍 $locationName\n📅 $date',
      backgroundColor: Colors.green.withValues(alpha: 0.9),
      colorText: Colors.white,
        duration: const Duration(seconds: 2),
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      borderRadius: 8,
      isDismissible: true,
      mainButton: TextButton(
        onPressed: () {
          Get.back(); // Close snackbar
          // TODO: Navigate to memory details
          debugPrint(
            '[MapMarkerService] 📝 Would navigate to memory details: ${memory['id']}',
          );
        },
        child: const Text(
          'View',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// Calculate distance between two points in degrees (approximate)
  double _calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final deltaLat = lat1 - lat2;
    final deltaLng = lng1 - lng2;
    return math.sqrt(deltaLat * deltaLat + deltaLng * deltaLng);
  }

  /// Handle marker tap events
  void handleMarkerTap(String markerId) {
    debugPrint('[MapMarkerService] Marker tapped: $markerId');

    if (markerId.startsWith('cluster_')) {
      // For now, just show a simple message since we don't have the clusters list here
      debugPrint('[MapMarkerService] Cluster marker tapped: $markerId');
      Get.snackbar(
        '📍 Cluster Tapped',
        'Cluster marker tapped: $markerId',
        backgroundColor: Colors.blue.withValues(alpha: 0.8),
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    } else if (markerId.startsWith('memory_')) {
      _handleMemoryTapById(markerId);
    }
  }

  /// Handle memory marker tap by ID
  void _handleMemoryTapById(String markerId) {
    final memoryId = markerId.replaceFirst('memory_', '');

    // Find the memory (you'd need to get this from MemoryRepository)
    try {
      final memoryRepo = Get.find<MemoryRepository>();
      final memory = memoryRepo.getMemoryById(int.parse(memoryId));

      if (memory != null) {
        debugPrint('[MapMarkerService] Memory tapped: ${memory['id']}');
        onMemoryTapped?.call(memory);
      }
    } catch (e) {
      debugPrint('[MapMarkerService] Error handling memory tap: $e');
    }
  }

  /// Get marker statistics
  Map<String, dynamic> getStatistics() {
    return {
      'clusterMarkers': clusterMarkerIds.length,
      'individualMarkers': individualMarkerIds.length,
      'totalMarkers': clusterMarkerIds.length + individualMarkerIds.length,
      'isUpdating': isUpdatingMarkers.value,
    };
  }

  /// Clear all markers and reset service
  Future<void> clearAll() async {
    debugPrint('[MapMarkerService] Clearing all markers and resetting service');
    await _clearAllMarkers();
    await _clearAllArrows();
    _mapboxMap = null;
  }

  // ============================================================================
  // CHRONOLOGICAL ARROWS DISPLAY LOGIC
  // ============================================================================

  /// Display chronological arrows between clusters and markers using GeoJSON LineLayer
  Future<void> displayChronologicalArrows(
    List<clustering.ChronologicalArrow> arrows,
  ) async {
    debugPrint(
      '[MapMarkerService] displayChronologicalArrows called with ${arrows.length} arrows',
    );

    if (_mapboxMap == null) {
      debugPrint(
        '[MapMarkerService] Cannot display arrows: MapBox map not initialized',
      );
      return;
    }

    try {
      // Remove existing arrow layers and source
      try {
        await _mapboxMap!.style.removeStyleLayer(ARROW_LINES_LAYER_ID);
        debugPrint('[MapMarkerService] Removed existing arrow layer');
      } catch (e) {
        debugPrint('[MapMarkerService] No existing arrow layer to remove');
      }

      try {
        await _mapboxMap!.style.removeStyleSource(ARROW_LINES_SOURCE_ID);
        debugPrint('[MapMarkerService] Removed existing arrow source');
      } catch (e) {
        debugPrint('[MapMarkerService] No existing arrow source to remove');
      }

      if (arrows.isEmpty) {
        debugPrint('[MapMarkerService] No arrows to display');
        currentArrows.clear();
        return;
      }

      // Store arrows for management
      currentArrows.assignAll(arrows);

      // Create GeoJSON features for arrows
      final features = <Map<String, dynamic>>[];

      for (final arrow in arrows) {
        // Create curved line points
        final points = _createCurvedArrowLine(
          arrow.fromLatitude,
          arrow.fromLongitude,
          arrow.toLatitude,
          arrow.toLongitude,
        );

        // Convert to GeoJSON coordinates format [lng, lat]
        final coordinates = points
            .map((point) => [point.lng, point.lat])
            .toList();

        // Get color based on year
        final year = arrow.toDate.year;
        final color = markerCreationService.getColorForYear(year);

        features.add({
          'type': 'Feature',
          'geometry': {
            'type': 'LineString',
            'coordinates': coordinates,
          },
          'properties': {
            'fromClusterId': arrow.fromClusterId,
            'toClusterId': arrow.toClusterId,
            'fromDate': arrow.fromDate.toIso8601String(),
            'toDate': arrow.toDate.toIso8601String(),
            'year': year,
            'color': '#${_colorToInt(color).toRadixString(16).substring(2)}',
          },
        });
      }

      // Create GeoJSON source
      final geoJson = {
        'type': 'FeatureCollection',
        'features': features,
      };

      debugPrint(
        '[MapMarkerService] Creating arrow source with ${features.length} features',
      );

      await _mapboxMap!.style.addSource(
        mapbox.GeoJsonSource(
          id: ARROW_LINES_SOURCE_ID,
          data: json.encode(geoJson),
        ),
      );
      debugPrint('[MapMarkerService] ✅ Arrow GeoJSON source added');

      // Add LineLayer for arrows (below individual markers)
      await _mapboxMap!.style.addLayer(
        mapbox.LineLayer(minZoom: 14,
          id: ARROW_LINES_LAYER_ID,
          sourceId: ARROW_LINES_SOURCE_ID,
          lineColor: 0xFFFF0000, // Bright red for visibility
          lineWidth: 5.0, // Thicker for visibility
          lineOpacity: 0.9,
        ),
      );
      debugPrint('[MapMarkerService] ✅ Arrow LineLayer added');

      // Move arrow layer below individual markers (if they exist)
      try {
        // Try to position below point annotations
        await _mapboxMap!.style.moveStyleLayer(
          ARROW_LINES_LAYER_ID,
          mapbox.LayerPosition(at: 0), // Move to bottom of all layers
        );
        debugPrint('[MapMarkerService] ✅ Arrow layer positioned at bottom');
      } catch (e) {
        debugPrint('[MapMarkerService] ⚠️ Could not position arrow layer: $e');
      }

      debugPrint(
        '[MapMarkerService] ✅ Successfully displayed ${arrows.length} arrows using GeoJSON LineLayer',
      );
    } catch (e) {
      debugPrint(
        '[MapMarkerService] ❌ Error displaying chronological arrows: $e',
      );
    }
  }

  /// Create curved arrow line between two points (0.1% curve for nearly straight lines)
  List<mapbox.Position> _createCurvedArrowLine(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng,
  ) {
    const int numPoints = 20;
    final points = <mapbox.Position>[];

    // Calculate control point for curve (perpendicular offset)
    final midLat = (fromLat + toLat) / 2;
    final midLng = (fromLng + toLng) / 2;

    // Calculate perpendicular offset (0.1% of distance for nearly straight lines)
    final dx = toLng - fromLng;
    final dy = toLat - fromLat;
    final distance = math.sqrt(dx * dx + dy * dy);
    final offsetDistance = distance * 0.001; // 0.1% curve for nearly straight arrows

    // Perpendicular direction
    final perpLng = -dy * offsetDistance;
    final perpLat = dx * offsetDistance;

    final controlLat = midLat + perpLat;
    final controlLng = midLng + perpLng;

    // Generate curved points using quadratic Bezier
    for (int i = 0; i <= numPoints; i++) {
      final t = i / numPoints;
      final oneMinusT = 1 - t;

      final lat = oneMinusT * oneMinusT * fromLat +
          2 * oneMinusT * t * controlLat +
          t * t * toLat;

      final lng = oneMinusT * oneMinusT * fromLng +
          2 * oneMinusT * t * controlLng +
          t * t * toLng;

      points.add(mapbox.Position(lng, lat));
    }

    return points;
  }

  /// Clear all arrows from the map
  Future<void> _clearAllArrows() async {
    try {
      if (_mapboxMap != null) {
        // Remove arrow layer
        try {
          await _mapboxMap!.style.removeStyleLayer(ARROW_LINES_LAYER_ID);
          debugPrint('[MapMarkerService] Removed arrow layer');
        } catch (e) {
          debugPrint('[MapMarkerService] No arrow layer to remove');
        }

        // Remove arrow source
        try {
          await _mapboxMap!.style.removeStyleSource(ARROW_LINES_SOURCE_ID);
          debugPrint('[MapMarkerService] Removed arrow source');
        } catch (e) {
          debugPrint('[MapMarkerService] No arrow source to remove');
        }
      }
      currentArrows.clear();
      debugPrint('[MapMarkerService] Cleared all arrows');
    } catch (e) {
      debugPrint('[MapMarkerService] Error clearing arrows: $e');
    }
  }

  /// Update arrows with new data
  Future<void> updateArrows(List<clustering.ChronologicalArrow> arrows) async {
    debugPrint(
      '[MapMarkerService] Updating arrows with ${arrows.length} new arrows',
    );
    await _clearAllArrows();
    await displayChronologicalArrows(arrows);
  }

  /// Convert Color to int for MapBox (avoiding deprecated .value)
  int _colorToInt(Color color) {
    return (color.a * 255).round() << 24 |
        (color.r * 255).round() << 16 |
        (color.g * 255).round() << 8 |
        (color.b * 255).round();
  }
}
