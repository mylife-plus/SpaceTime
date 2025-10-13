import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'dart:math' as math;
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
  mapbox.PolylineAnnotationManager? _polylineManager;

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
        duration: const Duration(seconds: 4),
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
        tapRadius = 0.001; // ~100m for high zoom (precise)
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
      duration: const Duration(seconds: 4),
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

  /// Display chronological arrows between clusters and markers
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

    if (arrows.isEmpty) {
      debugPrint('[MapMarkerService] No arrows to display');
      return;
    }

    try {
      debugPrint(
        '[MapMarkerService] Starting to display ${arrows.length} chronological arrows',
      );

      // Log first few arrows for debugging
      for (int i = 0; i < math.min(3, arrows.length); i++) {
        final arrow = arrows[i];
        debugPrint(
          '[MapMarkerService] Arrow ${i + 1}: ${arrow.fromClusterId} → ${arrow.toClusterId} (${arrow.fromLatitude},${arrow.fromLongitude} → ${arrow.toLatitude},${arrow.toLongitude})',
        );
      }

      // Store arrows for management
      currentArrows.assignAll(arrows);

      // Limit arrows for performance
      final arrowsToDisplay =
          arrows.length > 50 ? arrows.take(50).toList() : arrows;

      debugPrint(
        '[MapMarkerService] Will display ${arrowsToDisplay.length} arrows (limited from ${arrows.length})',
      );

      // Get or create polyline manager
      _polylineManager ??=
          await _mapboxMap!.annotations.createPolylineAnnotationManager();
      debugPrint('[MapMarkerService] Polyline manager ready');

      // Clear existing arrows
      await _polylineManager!.deleteAll();
      debugPrint('[MapMarkerService] Cleared existing arrows');

      // Display each arrow
      for (int i = 0; i < arrowsToDisplay.length; i++) {
        final arrow = arrowsToDisplay[i];
        debugPrint(
          '[MapMarkerService] Displaying arrow ${i + 1}/${arrowsToDisplay.length}',
        );
        await _displaySingleArrow(arrow);
      }

      debugPrint(
        '[MapMarkerService] Successfully displayed ${arrowsToDisplay.length} arrows',
      );
    } catch (e) {
      debugPrint(
        '[MapMarkerService] Error displaying chronological arrows: $e',
      );
    }
  }

  /// Display a single chronological arrow
  Future<void> _displaySingleArrow(clustering.ChronologicalArrow arrow) async {
    if (_polylineManager == null) return;

    try {
      // Create curved arrow line
      final points = _createCurvedArrowLine(
        arrow.fromLatitude,
        arrow.fromLongitude,
        arrow.toLatitude,
        arrow.toLongitude,
      );

      // Get arrow styling based on time difference
      final timeDiffMs = arrow.toDate.difference(arrow.fromDate).inMilliseconds;
      final width = _getArrowWidth(timeDiffMs);
      final color = markerCreationService.getColorForYear(arrow.toDate.year);

      // Create shadow line (background)
      await _polylineManager!.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(coordinates: points),
          lineColor: 0xFF000000, // Black shadow
          lineWidth: width + 2,
          lineOpacity: 0.20,
        ),
      );

      // Create main arrow line
      await _polylineManager!.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(coordinates: points),
          lineColor: _colorToInt(color),
          lineWidth: width,
          lineOpacity: 1.0,
        ),
      );

      // Add arrow head at the end of the curve (optional - don't fail if this doesn't work)
      try {
        await _addArrowHeadOnCurve(points, color);
      } catch (e) {
        debugPrint(
          '[MapMarkerService] ⚠️  Failed to add arrow head, but arrow line was created: $e',
        );
      }
    } catch (e) {
      debugPrint('[MapMarkerService] Error displaying single arrow: $e');
    }
  }

  /// Create curved arrow line between two points
  List<mapbox.Position> _createCurvedArrowLine(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const int segments = 32;

    // Direction in degrees
    final dx = lng2 - lng1;
    final dy = lat2 - lat1;
    final len = math.sqrt(dx * dx + dy * dy);

    // Handle zero-length gracefully (repeat a point)
    if (len == 0) {
      return [mapbox.Position(lng1, lat1), mapbox.Position(lng2, lat2)];
    }

    // Perpendicular unit (lng, lat)
    final ux = -dy / len;
    final uy = dx / len;

    // Estimate segment length in km for sensible offset scaling
    final avgLatRad = ((lat1 + lat2) * 0.5) * (math.pi / 180.0);
    const kmPerDegLat = 110.574; // approx constant
    final kmPerDegLng = 111.320 * math.cos(avgLatRad);

    final segKm =
        (dy.abs() * kmPerDegLat + dx.abs() * kmPerDegLng) * 0.5; // rough avg

    // Max lateral offset ≈ 8% of segment length, capped (subtle arc)
    final maxOffsetKm = (segKm * 0.08).clamp(0.0, 20.0);
    final offDegLat = maxOffsetKm / kmPerDegLat;
    final offDegLng = kmPerDegLng == 0 ? 0.0 : (maxOffsetKm / kmPerDegLng);

    // Control point (midpoint + perpendicular offset)
    final cLng = (lng1 + lng2) * 0.5 + ux * offDegLng;
    final cLat = (lat1 + lat2) * 0.5 + uy * offDegLat;

    // Quadratic Bézier sampling
    final points = <mapbox.Position>[];
    for (int i = 0; i <= segments; i++) {
      final t = i / segments;
      final omt = 1 - t;

      final lng = omt * omt * lng1 + 2 * omt * t * cLng + t * t * lng2;
      final lat = omt * omt * lat1 + 2 * omt * t * cLat + t * t * lat2;

      points.add(mapbox.Position(lng, lat)); // (lng, lat)
    }

    return points;
  }

  /// Add arrow head at the end of a curved line
  Future<void> _addArrowHeadOnCurve(
    List<mapbox.Position> curvePoints,
    Color arrowColor,
  ) async {
    if (curvePoints.length < 3) return;

    // Ensure annotation manager is available for arrow heads
    if (_annotationManager == null) {
      debugPrint(
        '[MapMarkerService] Creating annotation manager for arrow heads',
      );
      _annotationManager =
          await _mapboxMap!.annotations.createPointAnnotationManager();
    }

    try {
      // Build arrow head image for this color
      final colorInt = _colorToInt(arrowColor);
      final imgKey = 'arrow_head_color_$colorInt';

      // Remove existing image if it exists
      try {
        await _mapboxMap!.style.removeStyleImage(imgKey);
      } catch (_) {}

      // Create arrow head image
      debugPrint(
        '[MapMarkerService] Creating arrow head image with color: $colorInt',
      );
      const int arrowSize = 32; // Use consistent size
      final imageBytes = await markerCreationService.createArrowHeadImage(
        colorValue: colorInt,
        size: arrowSize,
      );
      if (imageBytes.isEmpty) {
        debugPrint(
          '[MapMarkerService] ❌ Skipping arrow head due to empty image data',
        );
        return;
      }
      debugPrint(
        '[MapMarkerService] ✅ Created arrow head image: ${imageBytes.length} bytes',
      );

      final image = mapbox.MbxImage(
        data: imageBytes,
        height: arrowSize,
        width: arrowSize,
      ); // Match the actual image size

      // Validate image data before adding to style
      debugPrint(
        '[MapMarkerService] Adding style image: $imgKey, size: ${arrowSize}x$arrowSize, data: ${imageBytes.length} bytes',
      );

      await _mapboxMap!.style.addStyleImage(
        imgKey,
        1.0,
        image,
        false,
        [],
        [],
        null,
      );
      debugPrint('[MapMarkerService] ✅ Added arrow head style image: $imgKey');

      // Position ~70% along the curve for better visibility
      final idx =
          ((curvePoints.length - 1) * 0.7)
              .clamp(1, curvePoints.length - 1)
              .toInt();
      final pPrev = curvePoints[idx - 1];
      final pNow = curvePoints[idx];

      // Calculate bearing from previous point to current point
      final bearing = _bearingDegrees(
        pPrev.lat.toDouble(),
        pPrev.lng.toDouble(),
        pNow.lat.toDouble(),
        pNow.lng.toDouble(),
      );

      // Adjust bearing for arrow head image orientation
      // The arrow image points right (east) by default, so we need to adjust
      // Mapbox rotation: 0° = North, 90° = East, 180° = South, 270° = West
      // Our bearing: 0° = North, 90° = East, etc.
      // Since our arrow points east by default, we need to subtract 90° to align with north
      final adjustedBearing = (bearing - 90.0) % 360.0;

      // Create arrow head annotation
      debugPrint(
        '[MapMarkerService] Creating arrow head at (${pNow.lng}, ${pNow.lat}) with bearing $bearing (adjusted: $adjustedBearing)',
      );
      await _annotationManager!.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(pNow.lng, pNow.lat),
          ),
          iconImage: imgKey,
          iconSize: 1.2, // Increased size for better visibility
          iconRotate: adjustedBearing,
        ),
      );
      debugPrint(
        '[MapMarkerService] ✅ Successfully created arrow head with image key: $imgKey',
      );
    } catch (e) {
      debugPrint('[MapMarkerService] Error adding arrow head on curve: $e');
    }
  }

  /// Calculate bearing between two points in degrees
  double _bearingDegrees(double lat1, double lng1, double lat2, double lng2) {
    final radLat1 = lat1 * math.pi / 180.0;
    final radLat2 = lat2 * math.pi / 180.0;
    final deltaLon = (lng2 - lng1) * math.pi / 180.0;

    final y = math.sin(deltaLon) * math.cos(radLat2);
    final x =
        math.cos(radLat1) * math.sin(radLat2) -
        math.sin(radLat1) * math.cos(radLat2) * math.cos(deltaLon);

    final theta = math.atan2(y, x); // radians
    final deg = (theta * 180.0 / math.pi + 360.0) % 360.0;
    return deg;
  }

  /// Get arrow width based on time difference
  double _getArrowWidth(int timeDiffMs) {
    // Convert milliseconds to days for easier logic
    final timeDiffDays = timeDiffMs / (1000 * 60 * 60 * 24);

    if (timeDiffDays <= 1) {
      return 4.0; // Thicker for same day/next day connections
    } else if (timeDiffDays <= 7) {
      return 3.5; // Medium for within a week
    } else if (timeDiffDays <= 30) {
      return 3.0; // Standard for within a month
    } else {
      return 2.5; // Thinner for older connections
    }
  }

  /// Clear all arrows from the map
  Future<void> _clearAllArrows() async {
    try {
      if (_polylineManager != null) {
        await _polylineManager!.deleteAll();
        debugPrint('[MapMarkerService] Cleared all arrows');
      }
      currentArrows.clear();
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
