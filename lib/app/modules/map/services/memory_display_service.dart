import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../../../services/memory_clustering_service.dart';
import '../../../services/memory_db.dart';

/// Service responsible for managing memory display and clustering on the map
class MemoryDisplayService extends GetxService {
  // Memory clustering variables
  final RxList<Map<String, dynamic>> allMemories = <Map<String, dynamic>>[].obs;
  final RxList<MemoryCluster> currentClusters = <MemoryCluster>[].obs;
  final RxList<ChronologicalArrow> currentArrows = <ChronologicalArrow>[].obs;
  final Rx<ClusterLevel> currentClusterLevel = ClusterLevel.initial.obs;
  final Rxn<MemoryCluster> selectedCluster = Rxn<MemoryCluster>();
  final RxBool isLoadingMemories = false.obs;

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  /// Load memories from database
  Future<void> loadMemoriesFromDatabase() async {
    debugPrint('[MemoryDisplayService] Starting memory loading from database');

    try {
      debugPrint(
        '[MemoryDisplayService] isLoadingMemories before: ${isLoadingMemories.value}',
      );
      debugPrint(
        '[MemoryDisplayService] allMemories count before: ${allMemories.length}',
      );

      isLoadingMemories.value = true;
      debugPrint('[MemoryDisplayService] Set isLoadingMemories to true');

      debugPrint(
        '[MemoryDisplayService] Calling _databaseHelper.getAllMemoriesWithDetails()',
      );
      final memories = await _databaseHelper.getAllMemoriesWithDetails();
      debugPrint(
        '[MemoryDisplayService] Database query completed, got ${memories.length} memories',
      );

      allMemories.assignAll(memories);
      debugPrint(
        '[MemoryDisplayService] Assigned memories to allMemories, count: ${allMemories.length}',
      );

      if (memories.isEmpty) {
        debugPrint(
          '[MemoryDisplayService] No memories found in database, returning early',
        );

        // Move to user's current location
        try {
          final currentPosition = await getCurrentLocation();
          debugPrint(
            '[MemoryDisplayService] Got current position: ${currentPosition != null}',
          );

          // Callback to move map to current location
          onMoveToCurrentLocation?.call(currentPosition);
        } catch (e) {
          debugPrint(
            '[MemoryDisplayService] Error getting current location: $e',
          );
        }

        return;
      } else {
        debugPrint(
          '[MemoryDisplayService] Memories not empty, continuing with ${memories.length} memories',
        );
      }

      // Debug memory location data
      debugPrint('[MemoryDisplayService] Debugging memory locations...');
      MemoryClusteringService.debugMemoryLocations(memories);

      // Initialize clustering with loaded memories
      debugPrint(
        '[MemoryDisplayService] Starting clustering initialization...',
      );
      await initializeMemoryClustering();
      debugPrint('[MemoryDisplayService] Clustering initialization completed');
    } catch (e) {
      debugPrint(
        '[MemoryDisplayService] Error loading memories from database: $e',
      );
      debugPrint('[MemoryDisplayService] Error type: ${e.runtimeType}');
    } finally {
      debugPrint('[MemoryDisplayService] Setting isLoadingMemories to false');
      isLoadingMemories.value = false;
      debugPrint('[MemoryDisplayService] loadMemoriesFromDatabase completed');
    }
  }

  /// Get current location
  Future<Position?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint("Location services are disabled.");
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint("Location permission denied.");
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint("Location permission permanently denied.");
        return null;
      }

      // Try current position
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (e) {
        debugPrint("Error getting current position: $e");
        // Fallback to last known location
        return await Geolocator.getLastKnownPosition();
      }
    } catch (e) {
      debugPrint("Error in getCurrentLocation(): $e");
      return null;
    }
  }

  /// Initialize memory clustering
  Future<void> initializeMemoryClustering() async {
    try {
      debugPrint(
        '[MemoryDisplayService] ========== STARTING CLUSTERING INITIALIZATION ==========',
      );
      debugPrint(
        '[MemoryDisplayService] Total memories in allMemories: ${allMemories.length}',
      );
      debugPrint(
        '[MemoryDisplayService] Current clusters count: ${currentClusters.length}',
      );
      debugPrint(
        '[MemoryDisplayService] Current arrows count: ${currentArrows.length}',
      );

      // Reset cluster ID tracking to ensure fresh unique IDs
      debugPrint(
        '[MemoryDisplayService] Resetting cluster ID tracking for fresh start',
      );
      MemoryClusteringService.resetClusterIdTracking();

      // Log all memories before filtering
      debugPrint('[MemoryDisplayService] === ALL MEMORIES DATA ===');
      for (int i = 0; i < allMemories.length; i++) {
        final memory = allMemories[i];
        debugPrint('[MemoryDisplayService] Memory $i:');
        debugPrint('[MemoryDisplayService]   - ID: ${memory['id']}');
        debugPrint(
          '[MemoryDisplayService]   - Title: ${memory['title'] ?? 'No title'}',
        );
        debugPrint(
          '[MemoryDisplayService]   - Location: ${memory['location']}',
        );
        debugPrint(
          '[MemoryDisplayService]   - Latitude: ${memory['latitude']}',
        );
        debugPrint(
          '[MemoryDisplayService]   - Longitude: ${memory['longitude']}',
        );
        debugPrint(
          '[MemoryDisplayService]   - Memory Date: ${memory['memory_date']}',
        );
        debugPrint(
          '[MemoryDisplayService]   - Has valid coords: ${_hasValidCoordinates(memory)}',
        );
      }

      // Convert memories to MemoryLocation objects, filtering out those without valid locations
      debugPrint(
        '[MemoryDisplayService] === FILTERING MEMORIES WITH VALID COORDINATES ===',
      );
      final memoriesWithCoordinates =
          allMemories.where((memory) => _hasValidCoordinates(memory)).toList();

      debugPrint(
        '[MemoryDisplayService] Filtered memories: ${memoriesWithCoordinates.length} out of ${allMemories.length} have valid coordinates',
      );

      // Log filtered memories
      debugPrint('[MemoryDisplayService] === FILTERED MEMORIES DATA ===');
      for (int i = 0; i < memoriesWithCoordinates.length; i++) {
        final memory = memoriesWithCoordinates[i];
        debugPrint('[MemoryDisplayService] Filtered Memory $i:');
        debugPrint('[MemoryDisplayService]   - ID: ${memory['id']}');
        debugPrint(
          '[MemoryDisplayService]   - Location: ${memory['location']}',
        );
        debugPrint(
          '[MemoryDisplayService]   - Lat/Lng: ${memory['latitude']}, ${memory['longitude']}',
        );
      }

      debugPrint(
        '[MemoryDisplayService] === CONVERTING TO MEMORY LOCATION OBJECTS ===',
      );
      final memoryLocations =
          memoriesWithCoordinates
              .map((memory) => MemoryLocation.fromMap(memory))
              .where(
                (memoryLocation) =>
                    memoryLocation.latitude != 0.0 &&
                    memoryLocation.longitude != 0.0,
              )
              .toList();

      debugPrint(
        '[MemoryDisplayService] MemoryLocation objects created: ${memoryLocations.length}',
      );

      // Log MemoryLocation objects
      debugPrint('[MemoryDisplayService] === MEMORY LOCATION OBJECTS ===');
      for (int i = 0; i < memoryLocations.length; i++) {
        final memLoc = memoryLocations[i];
        debugPrint('[MemoryDisplayService] MemoryLocation $i:');
        debugPrint('[MemoryDisplayService]   - ID: ${memLoc.id}');
        debugPrint('[MemoryDisplayService]   - Title: ${memLoc.title}');
        debugPrint(
          '[MemoryDisplayService]   - Coordinates: ${memLoc.latitude}, ${memLoc.longitude}',
        );
        debugPrint('[MemoryDisplayService]   - Date: ${memLoc.memoryDate}');
        debugPrint('[MemoryDisplayService]   - Metadata: ${memLoc.metadata}');
      }

      debugPrint(
        '[MemoryDisplayService] === FINAL MEMORY LOCATIONS FOR CLUSTERING ===',
      );
      debugPrint(
        '[MemoryDisplayService] Final memory locations count: ${memoryLocations.length}',
      );

      if (memoryLocations.isEmpty) {
        debugPrint('[MemoryDisplayService] ❌ NO VALID MEMORIES FOR CLUSTERING');
        debugPrint(
          '[MemoryDisplayService] No memories with valid coordinates found for clustering',
        );
        debugPrint('[MemoryDisplayService] Clustering process aborted');
        return;
      }

      // Use fixed 50km clustering radius as requested
      double clusterRadius =
          MemoryClusteringService.cityClusterRadiusKm; // 50km
      debugPrint('[MemoryDisplayService] === CLUSTERING CONFIGURATION ===');
      debugPrint('[MemoryDisplayService] Cluster radius: ${clusterRadius}km');
      debugPrint(
        '[MemoryDisplayService] Memory locations to cluster: ${memoryLocations.length}',
      );
      debugPrint(
        '[MemoryDisplayService] Clustering algorithm: MemoryClusteringService.clusterMemories',
      );

      // Initial clustering with adaptive radius
      debugPrint('[MemoryDisplayService] === STARTING CLUSTERING PROCESS ===');
      final stopwatch = Stopwatch()..start();

      final clusters = MemoryClusteringService.clusterMemories(
        memoryLocations,
        clusterRadius,
      );

      stopwatch.stop();
      debugPrint('[MemoryDisplayService] === CLUSTERING COMPLETED ===');
      debugPrint(
        '[MemoryDisplayService] Clustering duration: ${stopwatch.elapsedMilliseconds}ms',
      );
      debugPrint(
        '[MemoryDisplayService] Generated clusters: ${clusters.length}',
      );

      // Log detailed cluster information and verify ID uniqueness
      debugPrint(
        '[MemoryDisplayService] === CLUSTER DETAILS & ID VERIFICATION ===',
      );
      final Set<String> clusterIds = <String>{};
      final List<String> duplicateIds = <String>[];

      for (int i = 0; i < clusters.length; i++) {
        final cluster = clusters[i];
        debugPrint('[MemoryDisplayService] Cluster ${i + 1}:');
        debugPrint('[MemoryDisplayService]   - ID: ${cluster.id}');

        // Check for duplicate IDs
        if (clusterIds.contains(cluster.id)) {
          duplicateIds.add(cluster.id);
          debugPrint(
            '[MemoryDisplayService]   - ❌ DUPLICATE ID DETECTED: ${cluster.id}',
          );
        } else {
          clusterIds.add(cluster.id);
          debugPrint('[MemoryDisplayService]   - ✅ UNIQUE ID: ${cluster.id}');
        }

        debugPrint(
          '[MemoryDisplayService]   - Memory count: ${cluster.memoryCount}',
        );
        debugPrint(
          '[MemoryDisplayService]   - Center: ${cluster.centerLatitude.toStringAsFixed(6)}, ${cluster.centerLongitude.toStringAsFixed(6)}',
        );
        debugPrint('[MemoryDisplayService]   - Radius: ${cluster.radiusKm}km');
        debugPrint(
          '[MemoryDisplayService]   - Earliest date: ${cluster.earliestDate}',
        );
        debugPrint(
          '[MemoryDisplayService]   - Latest date: ${cluster.latestDate}',
        );
        debugPrint(
          '[MemoryDisplayService]   - Is single memory: ${cluster.memoryCount == 1}',
        );

        // Log memories in this cluster
        debugPrint('[MemoryDisplayService]   - Memories in cluster:');
        for (int j = 0; j < cluster.memories.length; j++) {
          final memory = cluster.memories[j];
          debugPrint(
            '[MemoryDisplayService]     Memory ${j + 1}: ${memory.id} - "${memory.title}" at ${memory.latitude}, ${memory.longitude}',
          );
        }
      }

      // Report ID uniqueness results
      debugPrint('[MemoryDisplayService] === CLUSTER ID UNIQUENESS REPORT ===');
      debugPrint('[MemoryDisplayService] Total clusters: ${clusters.length}');
      debugPrint(
        '[MemoryDisplayService] Unique cluster IDs: ${clusterIds.length}',
      );
      debugPrint(
        '[MemoryDisplayService] Duplicate IDs found: ${duplicateIds.length}',
      );

      if (duplicateIds.isNotEmpty) {
        debugPrint(
          '[MemoryDisplayService] ❌ CRITICAL: Duplicate cluster IDs detected: $duplicateIds',
        );
      } else {
        debugPrint(
          '[MemoryDisplayService] ✅ SUCCESS: All cluster IDs are unique',
        );
      }

      debugPrint(
        '[MemoryDisplayService] === ASSIGNING CLUSTERS TO CONTROLLER ===',
      );
      debugPrint(
        '[MemoryDisplayService] Previous currentClusters count: ${currentClusters.length}',
      );
      currentClusters.assignAll(clusters);
      debugPrint(
        '[MemoryDisplayService] New currentClusters count: ${currentClusters.length}',
      );

      // Generate chronological arrows with performance limits
      debugPrint(
        '[MemoryDisplayService] === GENERATING CHRONOLOGICAL ARROWS ===',
      );
      debugPrint(
        '[MemoryDisplayService] Starting arrow generation for ${clusters.length} clusters',
      );
      debugPrint(
        '[MemoryDisplayService] Previous currentArrows count: ${currentArrows.length}',
      );

      final arrowStopwatch = Stopwatch()..start();
      final arrows = _generateOptimizedArrows(clusters);
      arrowStopwatch.stop();

      debugPrint(
        '[MemoryDisplayService] Arrow generation completed in ${arrowStopwatch.elapsedMilliseconds}ms',
      );
      debugPrint(
        '[MemoryDisplayService] Generated arrows count: ${arrows.length}',
      );

      currentArrows.assignAll(arrows);
      debugPrint(
        '[MemoryDisplayService] New currentArrows count: ${currentArrows.length}',
      );

      // Log arrow details
      debugPrint('[MemoryDisplayService] === ARROW DETAILS ===');
      for (int i = 0; i < arrows.length; i++) {
        final arrow = arrows[i];
        debugPrint('[MemoryDisplayService] Arrow ${i + 1}:');
        debugPrint(
          '[MemoryDisplayService]   - From: ${arrow.fromLatitude.toStringAsFixed(6)}, ${arrow.fromLongitude.toStringAsFixed(6)}',
        );
        debugPrint(
          '[MemoryDisplayService]   - To: ${arrow.toLatitude.toStringAsFixed(6)}, ${arrow.toLongitude.toStringAsFixed(6)}',
        );
        debugPrint('[MemoryDisplayService]   - From Date: ${arrow.fromDate}');
        debugPrint('[MemoryDisplayService]   - To Date: ${arrow.toDate}');
        debugPrint(
          '[MemoryDisplayService]   - From Cluster ID: ${arrow.fromClusterId}',
        );
        debugPrint(
          '[MemoryDisplayService]   - To Cluster ID: ${arrow.toClusterId}',
        );
        debugPrint(
          '[MemoryDisplayService]   - Distance: ${arrow.distance.toStringAsFixed(2)}km',
        );
        debugPrint(
          '[MemoryDisplayService]   - Bearing: ${arrow.bearing.toStringAsFixed(2)}°',
        );
      }

      debugPrint('[MemoryDisplayService] === SETTING CLUSTER LEVEL ===');
      debugPrint(
        '[MemoryDisplayService] Previous cluster level: ${currentClusterLevel.value}',
      );
      currentClusterLevel.value = ClusterLevel.initial;
      debugPrint(
        '[MemoryDisplayService] New cluster level: ${currentClusterLevel.value}',
      );

      debugPrint('[MemoryDisplayService] === CLUSTERING SUMMARY ===');
      debugPrint(
        '[MemoryDisplayService] Total memories processed: ${memoryLocations.length}',
      );
      debugPrint('[MemoryDisplayService] Clusters created: ${clusters.length}');
      debugPrint('[MemoryDisplayService] Arrows generated: ${arrows.length}');
      debugPrint(
        '[MemoryDisplayService] Cluster level: ${currentClusterLevel.value}',
      );

      // Display clusters on map
      debugPrint('[MemoryDisplayService] === STARTING MAP DISPLAY ===');
      debugPrint(
        '[MemoryDisplayService] Calling displayMemoryClusters callback',
      );
      await onDisplayMemoryClusters?.call();
      debugPrint('[MemoryDisplayService] Map display completed successfully');

      debugPrint(
        '[MemoryDisplayService] ========== CLUSTERING INITIALIZATION COMPLETED ==========',
      );
    } catch (e) {
      debugPrint('Error initializing memory clustering: $e');
    }
  }

  /// Generate optimized arrows for performance
  List<ChronologicalArrow> _generateOptimizedArrows(
    List<MemoryCluster> clusters,
  ) {
    debugPrint('[MemoryDisplayService] === STARTING ARROW GENERATION ===');
    debugPrint(
      '[MemoryDisplayService] Input clusters count: ${clusters.length}',
    );

    // Log cluster information for arrow generation
    debugPrint('[MemoryDisplayService] === CLUSTERS FOR ARROW GENERATION ===');
    for (int i = 0; i < clusters.length; i++) {
      final cluster = clusters[i];
      debugPrint('[MemoryDisplayService] Cluster ${i + 1} for arrows:');
      debugPrint('[MemoryDisplayService]   - ID: ${cluster.id}');
      debugPrint(
        '[MemoryDisplayService]   - Memory count: ${cluster.memoryCount}',
      );
      debugPrint(
        '[MemoryDisplayService]   - Center: ${cluster.centerLatitude}, ${cluster.centerLongitude}',
      );
      debugPrint(
        '[MemoryDisplayService]   - Earliest date: ${cluster.earliestDate}',
      );
      debugPrint(
        '[MemoryDisplayService]   - Latest date: ${cluster.latestDate}',
      );
    }

    // For performance, limit arrow generation for large datasets
    if (clusters.length > 50) {
      debugPrint('[MemoryDisplayService] === PERFORMANCE OPTIMIZATION ===');
      debugPrint(
        '[MemoryDisplayService] Large dataset detected (${clusters.length} clusters)',
      );
      debugPrint(
        '[MemoryDisplayService] Applying performance optimization - using top 30 clusters',
      );

      // Only generate arrows for the most significant clusters (by memory count)
      final sortedClusters = List<MemoryCluster>.from(clusters);
      sortedClusters.sort((a, b) => b.memoryCount.compareTo(a.memoryCount));
      final topClusters = sortedClusters.take(30).toList();

      debugPrint(
        '[MemoryDisplayService] Top clusters selected for arrow generation:',
      );
      for (int i = 0; i < topClusters.length; i++) {
        final cluster = topClusters[i];
        debugPrint(
          '[MemoryDisplayService] Top cluster ${i + 1}: ${cluster.memoryCount} memories',
        );
      }

      debugPrint(
        '[MemoryDisplayService] Calling MemoryClusteringService.generateChronologicalArrows with ${topClusters.length} clusters',
      );
      final arrows = MemoryClusteringService.generateChronologicalArrows(
        topClusters,
      );
      debugPrint(
        '[MemoryDisplayService] Generated ${arrows.length} arrows from optimized clusters',
      );
      return arrows;
    } else {
      debugPrint('[MemoryDisplayService] === STANDARD ARROW GENERATION ===');
      debugPrint(
        '[MemoryDisplayService] Normal dataset size (${clusters.length} clusters)',
      );
      debugPrint(
        '[MemoryDisplayService] Calling MemoryClusteringService.generateChronologicalArrows with all clusters',
      );

      final arrows = MemoryClusteringService.generateChronologicalArrows(
        clusters,
      );
      debugPrint(
        '[MemoryDisplayService] Generated ${arrows.length} arrows from all clusters',
      );
      return arrows;
    }
  }

  /// Check if memory has valid coordinates
  bool _hasValidCoordinates(Map<String, dynamic> memory) {
    debugPrint('[MemoryDisplayService] === VALIDATING COORDINATES ===');
    debugPrint('[MemoryDisplayService] Memory ID: ${memory['id']}');

    final locationStr = memory['location'] as String? ?? '';
    debugPrint('[MemoryDisplayService] Location string: "$locationStr"');

    // Skip if location is empty or null
    if (locationStr.isEmpty) {
      debugPrint('[MemoryDisplayService] ❌ INVALID: Location string is empty');
      return false;
    }

    // Skip if location doesn't contain coordinates (comma-separated values)
    if (!locationStr.contains(',')) {
      debugPrint(
        '[MemoryDisplayService] ❌ INVALID: Location string does not contain comma separator',
      );
      return false;
    }

    final parts = locationStr.split(',');
    debugPrint(
      '[MemoryDisplayService] Location parts: ${parts.length} parts - $parts',
    );

    if (parts.length < 2) {
      debugPrint(
        '[MemoryDisplayService] ❌ INVALID: Less than 2 coordinate parts',
      );
      return false;
    }

    final latStr = parts[0].trim();
    final lngStr = parts[1].trim();
    debugPrint('[MemoryDisplayService] Latitude string: "$latStr"');
    debugPrint('[MemoryDisplayService] Longitude string: "$lngStr"');

    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);
    debugPrint('[MemoryDisplayService] Parsed latitude: $lat');
    debugPrint('[MemoryDisplayService] Parsed longitude: $lng');

    // Skip if coordinates are invalid or zero
    if (lat == null || lng == null) {
      debugPrint(
        '[MemoryDisplayService] ❌ INVALID: Failed to parse coordinates as numbers',
      );
      return false;
    }

    // Skip if coordinates are exactly 0,0 (likely default/invalid)
    if (lat == 0.0 && lng == 0.0) {
      debugPrint(
        '[MemoryDisplayService] ❌ INVALID: Coordinates are 0,0 (likely default/invalid)',
      );
      return false;
    }

    // Skip if coordinates are outside valid ranges
    if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) {
      debugPrint(
        '[MemoryDisplayService] ❌ INVALID: Coordinates outside valid ranges',
      );
      debugPrint('[MemoryDisplayService] Latitude range: -90 to 90, got: $lat');
      debugPrint(
        '[MemoryDisplayService] Longitude range: -180 to 180, got: $lng',
      );
      return false;
    }

    debugPrint(
      '[MemoryDisplayService] ✅ VALID: Coordinates are valid ($lat, $lng)',
    );
    return true;
  }

  /// Clear all memory data
  void clearMemoryData() {
    allMemories.clear();
    currentClusters.clear();
    currentArrows.clear();
    selectedCluster.value = null;
    currentClusterLevel.value = ClusterLevel.initial;
    isLoadingMemories.value = false;

    debugPrint('[MemoryDisplayService] All memory data cleared');
  }

  /// Get memory statistics
  Map<String, dynamic> getMemoryStatistics() {
    return {
      'total_memories': allMemories.length,
      'total_clusters': currentClusters.length,
      'total_arrows': currentArrows.length,
      'cluster_level': currentClusterLevel.value.toString(),
      'is_loading': isLoadingMemories.value,
      'has_selected_cluster': selectedCluster.value != null,
      'memories_with_valid_coords':
          allMemories.where((memory) => _hasValidCoordinates(memory)).length,
    };
  }

  // Callback functions that can be set by the MapController
  Function(Position?)? onMoveToCurrentLocation;
  Future<void> Function()? onDisplayMemoryClusters;
}
