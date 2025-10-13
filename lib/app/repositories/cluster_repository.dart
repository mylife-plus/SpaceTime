import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../models/memory_cluster.dart';

/// Repository for handling memory clustering operations
class ClusterRepository extends GetxService {
  static ClusterRepository get instance => Get.find<ClusterRepository>();

  // Reactive state
  final RxList<MemoryCluster> clusters = <MemoryCluster>[].obs;
  final RxList<Map<String, dynamic>> individualMemories =
      <Map<String, dynamic>>[].obs;
  final RxBool isProcessingClusters = false.obs;
  final Rx<ClusteringResult?> lastClusteringResult = Rx<ClusteringResult?>(
    null,
  );

  // Configuration
  final Rx<ClusteringConfig> config = const ClusteringConfig().obs;

  // Callbacks
  Function(ClusteringResult)? onClusteringComplete;
  Function(String)? onClusteringError;

  @override
  void onInit() {
    super.onInit();
    debugPrint('[ClusterRepository] Repository initialized');
  }

  /// Set clustering configuration
  void setConfig(ClusteringConfig newConfig) {
    config.value = newConfig;
    debugPrint(
      '[ClusterRepository] Configuration updated: ${newConfig.maxDistanceKm}km, min: ${newConfig.minClusterSize}',
    );
  }

  /// Set clustering callbacks
  void setCallbacks({
    Function(ClusteringResult)? onComplete,
    Function(String)? onError,
  }) {
    onClusteringComplete = onComplete;
    onClusteringError = onError;
  }

  /// Create clusters from memories
  Future<ClusteringResult> createClusters(
    List<Map<String, dynamic>> memories, {
    double? zoomLevel,
    ClusteringConfig? customConfig,
  }) async {
    try {
      debugPrint(
        '[ClusterRepository] Starting clustering for ${memories.length} memories',
      );
      isProcessingClusters.value = true;

      final activeConfig = customConfig ?? config.value;
      final clusteringDistance =
          zoomLevel != null
              ? activeConfig.getClusteringDistance(zoomLevel)
              : activeConfig.maxDistanceKm;

      debugPrint(
        '[ClusterRepository] Using clustering distance: ${clusteringDistance}km',
      );

      // Filter memories with valid locations
      final validMemories =
          memories.where((memory) {
            final lat = memory['location_latitude'] as double?;
            final lng = memory['location_longitude'] as double?;
            return lat != null && lng != null;
          }).toList();

      debugPrint(
        '[ClusterRepository] ${validMemories.length} memories have valid locations',
      );

      // Perform clustering
      final result = await _performClustering(
        validMemories,
        clusteringDistance,
        activeConfig,
      );

      // Update reactive state
      clusters.assignAll(result.clusters);
      individualMemories.assignAll(result.individualMemories);
      lastClusteringResult.value = result;

      debugPrint(
        '[ClusterRepository] Clustering complete: ${result.clusters.length} clusters, ${result.individualMemories.length} individual',
      );

      // Trigger callback
      onClusteringComplete?.call(result);

      return result;
    } catch (e) {
      debugPrint('[ClusterRepository] Error during clustering: $e');
      onClusteringError?.call(e.toString());
      rethrow;
    } finally {
      isProcessingClusters.value = false;
    }
  }

  /// Perform the actual clustering algorithm
  Future<ClusteringResult> _performClustering(
    List<Map<String, dynamic>> memories,
    double maxDistanceKm,
    ClusteringConfig config,
  ) async {
    final clusteredMemories = <Map<String, dynamic>>[];
    final resultClusters = <MemoryCluster>[];
    final processedIndices = <int>{};

    for (int i = 0; i < memories.length; i++) {
      if (processedIndices.contains(i)) continue;

      final currentMemory = memories[i];
      final currentLat = currentMemory['location_latitude'] as double;
      final currentLng = currentMemory['location_longitude'] as double;

      // Find nearby memories
      final nearbyMemories = <Map<String, dynamic>>[currentMemory];
      final nearbyIndices = <int>[i];

      for (int j = i + 1; j < memories.length; j++) {
        if (processedIndices.contains(j)) continue;

        final otherMemory = memories[j];
        final otherLat = otherMemory['location_latitude'] as double;
        final otherLng = otherMemory['location_longitude'] as double;

        final distance = _calculateDistance(
          currentLat,
          currentLng,
          otherLat,
          otherLng,
        );

        if (distance <= maxDistanceKm) {
          nearbyMemories.add(otherMemory);
          nearbyIndices.add(j);
        }
      }

      // Create cluster if we have enough memories
      if (nearbyMemories.length >= config.minClusterSize) {
        final center = MemoryCluster.calculateCenter(nearbyMemories);
        final clusterId = _generateClusterId(
          center['latitude']!,
          center['longitude']!,
        );

        final cluster = MemoryCluster(
          id: clusterId,
          latitude: center['latitude']!,
          longitude: center['longitude']!,
          memories: nearbyMemories,
          radiusKm: maxDistanceKm,
        );

        resultClusters.add(cluster);
        clusteredMemories.addAll(nearbyMemories);
        processedIndices.addAll(nearbyIndices);

        debugPrint(
          '[ClusterRepository] Created cluster $clusterId with ${nearbyMemories.length} memories',
        );
      }
    }

    // Individual memories are those not in any cluster
    final individualMems =
        memories
            .where((memory) => !clusteredMemories.contains(memory))
            .toList();

    return ClusteringResult(
      clusters: resultClusters,
      individualMemories: individualMems,
      config: config,
      totalMemories: memories.length,
    );
  }

  /// Calculate distance between two points using Haversine formula
  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  /// Generate unique cluster ID
  String _generateClusterId(double lat, double lng) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final latStr = lat.toStringAsFixed(6).replaceAll('.', '');
    final lngStr = lng.toStringAsFixed(6).replaceAll('.', '');
    return 'cluster_${latStr}_${lngStr}_$timestamp';
  }

  /// Get cluster by ID
  MemoryCluster? getClusterById(String id) {
    try {
      return clusters.firstWhere((cluster) => cluster.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get clusters within a bounding box
  List<MemoryCluster> getClustersInBounds({
    required double northLat,
    required double southLat,
    required double eastLng,
    required double westLng,
  }) {
    return clusters.where((cluster) {
      return cluster.latitude >= southLat &&
          cluster.latitude <= northLat &&
          cluster.longitude >= westLng &&
          cluster.longitude <= eastLng;
    }).toList();
  }

  /// Get individual memories within a bounding box
  List<Map<String, dynamic>> getIndividualMemoriesInBounds({
    required double northLat,
    required double southLat,
    required double eastLng,
    required double westLng,
  }) {
    return individualMemories.where((memory) {
      final lat = memory['location_latitude'] as double?;
      final lng = memory['location_longitude'] as double?;

      if (lat == null || lng == null) return false;

      return lat >= southLat &&
          lat <= northLat &&
          lng >= westLng &&
          lng <= eastLng;
    }).toList();
  }

  /// Clear all clusters and individual memories
  void clearClusters() {
    debugPrint('[ClusterRepository] Clearing all clusters');
    clusters.clear();
    individualMemories.clear();
    lastClusteringResult.value = null;
  }

  /// Get clustering statistics
  Map<String, dynamic> getStatistics() {
    final result = lastClusteringResult.value;
    if (result == null) {
      return {
        'totalClusters': 0,
        'totalIndividualMemories': 0,
        'totalMemories': 0,
        'clusteringEfficiency': 0.0,
      };
    }

    return result.statistics;
  }

  /// Print clustering statistics
  void printStatistics() {
    final stats = getStatistics();
    debugPrint('[ClusterRepository] Clustering Statistics:');
    debugPrint('  Total clusters: ${stats['clustersCount']}');
    debugPrint('  Individual memories: ${stats['individualMemoriesCount']}');
    debugPrint('  Total memories: ${stats['totalMemories']}');
    debugPrint(
      '  Clustering efficiency: ${stats['clusteringEfficiency'].toStringAsFixed(1)}%',
    );
  }
}
