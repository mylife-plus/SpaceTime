import 'dart:math';
import 'package:flutter/foundation.dart';

enum ClusterLevel {
  initial, // 5km clustering
  subgroup, // 100m clustering
}

class MemoryWithCluster {
  final MemoryLocation memory;
  final MemoryCluster cluster;

  MemoryWithCluster(this.memory, this.cluster);
}

class MemoryClusteringService {
  // Configurable clustering radius constants
  static const double initialClusterRadiusKm = 5.0;
  static const double subgroupClusterRadiusM = 100.0;

  // Additional radius options for different zoom levels
  static const double cityClusterRadiusKm = 50.0;
  static const double countryClusterRadiusKm = 500.0;
  static const double continentClusterRadiusKm = 2000.0;

  // Performance thresholds
  static const int maxMarkersBeforeClustering = 100;
  static const int maxArrowsToDisplay = 50;

  // Unique ID generation
  static int _clusterIdCounter = 0;
  static final Set<String> _usedClusterIds = <String>{};

  /// Generate a unique cluster ID that never repeats
  static String generateUniqueClusterId() {
    String clusterId;
    do {
      _clusterIdCounter++;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      clusterId = 'cluster_${timestamp}_${_clusterIdCounter}';
    } while (_usedClusterIds.contains(clusterId));

    _usedClusterIds.add(clusterId);
    debugPrint(
      '[MemoryClusteringService][generateUniqueClusterId] Generated unique ID: $clusterId',
    );
    return clusterId;
  }

  /// Reset cluster ID tracking (useful for testing or fresh starts)
  static void resetClusterIdTracking() {
    _clusterIdCounter = 0;
    _usedClusterIds.clear();
    debugPrint(
      '[MemoryClusteringService][resetClusterIdTracking] Cluster ID tracking reset',
    );
  }

  /// Calculate distance between two points in kilometers using Haversine formula
  static double calculateDistance(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLng = _degreesToRadians(lng2 - lng1);

    final double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  /// Cluster memories by distance threshold
  static List<MemoryCluster> clusterMemories(
    List<MemoryLocation> memories,
    double radiusKm,
  ) {
    if (memories.isEmpty) return [];

    debugPrint(
      '🔄 CLUSTERING - Starting clustering with ${memories.length} memories, radius: ${radiusKm}km',
    );

    final List<MemoryCluster> clusters = [];
    final List<bool> processed = List.filled(memories.length, false);

    for (int i = 0; i < memories.length; i++) {
      if (processed[i]) continue;

      final List<MemoryLocation> clusterMemories = [memories[i]];
      processed[i] = true;

      debugPrint(
        '🔄 CLUSTERING - Starting new cluster with memory ${i + 1} at ${memories[i].latitude}, ${memories[i].longitude}',
      );

      // Find all memories within radius of this memory
      for (int j = i + 1; j < memories.length; j++) {
        if (processed[j]) continue;

        final double distance = calculateDistance(
          memories[i].latitude,
          memories[i].longitude,
          memories[j].latitude,
          memories[j].longitude,
        );

        debugPrint(
          '🔄 CLUSTERING - Distance from memory ${i + 1} to memory ${j + 1}: ${distance.toStringAsFixed(2)}km',
        );

        if (distance <= radiusKm) {
          clusterMemories.add(memories[j]);
          processed[j] = true;
          debugPrint(
            '🔄 CLUSTERING - Added memory ${j + 1} to cluster (distance: ${distance.toStringAsFixed(2)}km <= ${radiusKm}km)',
          );
        }
      }

      final cluster = MemoryCluster(
        id: generateUniqueClusterId(),
        memories: clusterMemories,
        centerLatitude: _calculateCenterLatitude(clusterMemories),
        centerLongitude: _calculateCenterLongitude(clusterMemories),
        radiusKm: radiusKm,
      );

      clusters.add(cluster);

      debugPrint(
        '🔄 CLUSTERING - Created cluster ${clusters.length} with ${cluster.memoryCount} memories at ${cluster.centerLatitude.toStringAsFixed(6)}, ${cluster.centerLongitude.toStringAsFixed(6)}',
      );
    }

    debugPrint(
      '🔄 CLUSTERING - Completed clustering: ${clusters.length} clusters created',
    );
    return clusters;
  }

  /// Calculate center latitude of a cluster
  static double _calculateCenterLatitude(List<MemoryLocation> memories) {
    if (memories.isEmpty) return 0.0;
    return memories.map((m) => m.latitude).reduce((a, b) => a + b) /
        memories.length;
  }

  /// Calculate center longitude of a cluster
  static double _calculateCenterLongitude(List<MemoryLocation> memories) {
    if (memories.isEmpty) return 0.0;
    return memories.map((m) => m.longitude).reduce((a, b) => a + b) /
        memories.length;
  }

  /// Generate chronological arrows between clusters/memories with advanced logic
  static List<ChronologicalArrow> generateChronologicalArrows(
    List<MemoryCluster> clusters,
  ) {
    if (clusters.length < 2) return [];

    final List<ChronologicalArrow> arrows = [];

    // Create a list of all individual memories with their cluster info
    final List<MemoryWithCluster> memoriesWithClusters = [];
    for (final cluster in clusters) {
      for (final memory in cluster.memories) {
        memoriesWithClusters.add(MemoryWithCluster(memory, cluster));
      }
    }

    // Sort all memories by date
    memoriesWithClusters.sort(
      (a, b) => a.memory.memoryDate.compareTo(b.memory.memoryDate),
    );

    // Generate arrows based on chronological sequence
    for (int i = 0; i < memoriesWithClusters.length - 1; i++) {
      final currentMemory = memoriesWithClusters[i];
      final nextMemory = memoriesWithClusters[i + 1];

      // Only create arrow if memories are in different clusters
      if (currentMemory.cluster.id != nextMemory.cluster.id) {
        arrows.add(
          ChronologicalArrow(
            fromLatitude: currentMemory.cluster.centerLatitude,
            fromLongitude: currentMemory.cluster.centerLongitude,
            toLatitude: nextMemory.cluster.centerLatitude,
            toLongitude: nextMemory.cluster.centerLongitude,
            fromDate: currentMemory.memory.memoryDate,
            toDate: nextMemory.memory.memoryDate,
            fromClusterId: currentMemory.cluster.id,
            toClusterId: nextMemory.cluster.id,
          ),
        );

        debugPrint(
          '🏹 Created arrow: ${currentMemory.cluster.id} → ${nextMemory.cluster.id} (${currentMemory.memory.memoryDate} → ${nextMemory.memory.memoryDate})',
        );
      }
    }

    // Debug: Analyze cluster connectivity
    _analyzeClusterConnectivity(clusters, arrows);

    debugPrint(
      '🏹 Generated ${arrows.length} total arrows between ${clusters.length} clusters',
    );
    return arrows;
  }

  /// Analyze which clusters have arrows and which don't
  static void _analyzeClusterConnectivity(
    List<MemoryCluster> clusters,
    List<ChronologicalArrow> arrows,
  ) {
    debugPrint('🔍 CONNECTIVITY ANALYSIS:');

    // Track which clusters have outgoing and incoming arrows
    final Set<String> clustersWithOutgoingArrows = {};
    final Set<String> clustersWithIncomingArrows = {};
    final Map<String, int> outgoingCount = {};
    final Map<String, int> incomingCount = {};

    for (final arrow in arrows) {
      clustersWithOutgoingArrows.add(arrow.fromClusterId);
      clustersWithIncomingArrows.add(arrow.toClusterId);
      outgoingCount[arrow.fromClusterId] =
          (outgoingCount[arrow.fromClusterId] ?? 0) + 1;
      incomingCount[arrow.toClusterId] =
          (incomingCount[arrow.toClusterId] ?? 0) + 1;
    }

    // Find clusters without any arrows
    final clustersWithoutArrows = <String>[];
    final clustersWithOnlyOutgoing = <String>[];
    final clustersWithOnlyIncoming = <String>[];

    for (final cluster in clusters) {
      final hasOutgoing = clustersWithOutgoingArrows.contains(cluster.id);
      final hasIncoming = clustersWithIncomingArrows.contains(cluster.id);

      if (!hasOutgoing && !hasIncoming) {
        clustersWithoutArrows.add(cluster.id);
        debugPrint(
          '❌ Cluster ${cluster.id} has NO arrows (${cluster.memories.length} memories)',
        );
        // Debug the memories in this cluster
        for (final memory in cluster.memories) {
          debugPrint(
            '   Memory: ${memory.memoryDate} at (${memory.latitude}, ${memory.longitude})',
          );
        }
      } else if (hasOutgoing && !hasIncoming) {
        clustersWithOnlyOutgoing.add(cluster.id);
        debugPrint(
          '➡️ Cluster ${cluster.id} has ONLY outgoing arrows (${outgoingCount[cluster.id]})',
        );
      } else if (!hasOutgoing && hasIncoming) {
        clustersWithOnlyIncoming.add(cluster.id);
        debugPrint(
          '⬅️ Cluster ${cluster.id} has ONLY incoming arrows (${incomingCount[cluster.id]})',
        );
      } else {
        debugPrint(
          '↔️ Cluster ${cluster.id} has both arrows (out: ${outgoingCount[cluster.id]}, in: ${incomingCount[cluster.id]})',
        );
      }
    }

    debugPrint('📊 SUMMARY:');
    debugPrint('   Total clusters: ${clusters.length}');
    debugPrint('   Clusters without arrows: ${clustersWithoutArrows.length}');
    debugPrint(
      '   Clusters with only outgoing: ${clustersWithOnlyOutgoing.length}',
    );
    debugPrint(
      '   Clusters with only incoming: ${clustersWithOnlyIncoming.length}',
    );
    debugPrint('   Total arrows generated: ${arrows.length}');
  }

  /// Generate arrows for a specific time window (useful for performance optimization)
  static List<ChronologicalArrow> generateArrowsForTimeWindow(
    List<MemoryCluster> clusters,
    DateTime startDate,
    DateTime endDate,
  ) {
    // Filter memories within the time window
    final filteredClusters =
        clusters
            .map((cluster) {
              final filteredMemories =
                  cluster.memories
                      .where(
                        (memory) =>
                            memory.memoryDate.isAfter(startDate) &&
                            memory.memoryDate.isBefore(endDate),
                      )
                      .toList();

              if (filteredMemories.isEmpty) return null;

              return MemoryCluster(
                id: cluster.id, // Keep the same ID for filtered clusters
                memories: filteredMemories,
                centerLatitude: cluster.centerLatitude,
                centerLongitude: cluster.centerLongitude,
                radiusKm: cluster.radiusKm,
              );
            })
            .where((cluster) => cluster != null)
            .cast<MemoryCluster>()
            .toList();

    return generateChronologicalArrows(filteredClusters);
  }

  /// Debug method to analyze memory location data
  static void debugMemoryLocations(List<Map<String, dynamic>> memories) {
    debugPrint('🔍 DEBUGGING ${memories.length} memories for location data:');

    int validCount = 0;
    int invalidCount = 0;

    for (int i = 0; i < memories.length; i++) {
      final memory = memories[i];
      final locationStr = memory['location'] as String? ?? '';

      debugPrint('🔍 Memory ${i + 1} (ID: ${memory['id']}):');
      debugPrint('   Location string: "$locationStr"');

      if (locationStr.isEmpty) {
        debugPrint('   ❌ Empty location string');
        invalidCount++;
        continue;
      }

      if (!locationStr.contains(',')) {
        debugPrint('   ❌ No comma in location string');
        invalidCount++;
        continue;
      }

      final parts = locationStr.split(',');
      if (parts.length < 2) {
        debugPrint('   ❌ Less than 2 parts after split');
        invalidCount++;
        continue;
      }

      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());

      if (lat == null || lng == null) {
        debugPrint('   ❌ Could not parse coordinates: lat=$lat, lng=$lng');
        invalidCount++;
        continue;
      }

      if (lat == 0.0 && lng == 0.0) {
        debugPrint('   ❌ Coordinates are 0,0');
        invalidCount++;
        continue;
      }

      if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) {
        debugPrint('   ❌ Coordinates out of range: lat=$lat, lng=$lng');
        invalidCount++;
        continue;
      }

      debugPrint('   ✅ Valid coordinates: lat=$lat, lng=$lng');
      validCount++;

      // Only show first 5 memories to avoid spam
      if (i >= 4) {
        debugPrint('🔍 ... (showing first 5 memories only)');
        break;
      }
    }

    debugPrint(
      '🔍 SUMMARY: $validCount valid, $invalidCount invalid locations',
    );
  }

  /// Calculate bearing between two points for arrow direction
  static double calculateBearing(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final double dLng = _degreesToRadians(lng2 - lng1);
    final double lat1Rad = _degreesToRadians(lat1);
    final double lat2Rad = _degreesToRadians(lat2);

    final double y = sin(dLng) * cos(lat2Rad);
    final double x =
        cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLng);

    final double bearing = atan2(y, x);
    return (bearing * 180 / pi + 360) % 360; // Convert to degrees and normalize
  }
}

class MemoryLocation {
  final String id;
  final double latitude;
  final double longitude;
  final DateTime memoryDate;
  final String title;
  final String description;
  final Map<String, dynamic> metadata;

  MemoryLocation({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.memoryDate,
    required this.title,
    required this.description,
    this.metadata = const {},
    required Map<String, dynamic> memoryData,
  });

  factory MemoryLocation.fromMap(Map<String, dynamic> map) {
    // Parse location string if it contains coordinates
    double lat = 0.0;
    double lng = 0.0;

    final locationStr = map['location'] as String? ?? '';
    if (locationStr.isNotEmpty && locationStr.contains(',')) {
      final parts = locationStr.split(',');
      if (parts.length >= 2) {
        final parsedLat = double.tryParse(parts[0].trim());
        final parsedLng = double.tryParse(parts[1].trim());

        // Only use coordinates if they are valid and not 0,0
        if (parsedLat != null &&
            parsedLng != null &&
            !(parsedLat == 0.0 && parsedLng == 0.0) &&
            parsedLat >= -90.0 &&
            parsedLat <= 90.0 &&
            parsedLng >= -180.0 &&
            parsedLng <= 180.0) {
          lat = parsedLat;
          lng = parsedLng;
        }
      }
    }

    // Parse date
    DateTime date = DateTime.now();
    try {
      if (map['date'] != null && map['time'] != null) {
        // Combine date and time strings
        var dateStr = map['date'] as String;
        var timeStr = map['time'] as String;
        dateStr = dateStr.trim();
        timeStr = timeStr.trim();

        if (timeStr.toUpperCase().contains("AM") ||
            timeStr.toUpperCase().contains("PM")) {
          final parts = timeStr.split(RegExp(r'[:\s]'));
          int hour = int.parse(parts[0]);
          int minute = parts.length > 1 ? int.parse(parts[1]) : 0;
          String period = parts.last.toUpperCase();

          if (period == "PM" && hour != 12) hour += 12;
          if (period == "AM" && hour == 12) hour = 0;

          date = DateTime.parse(dateStr); // safe because YYYY-MM-DD
          // return DateTime(date.year, date.month, date.day, hour, minute);
        } else {
          // Fallback: already 24-hour
          // final date = DateTime.parse(dateStr);
          final parts = timeStr.split(":");
          int hour = int.parse(parts[0]);
          int minute = parts.length > 1 ? int.parse(parts[1]) : 0;
          date = DateTime(date.year, date.month, date.day, hour, minute);
        }
        // String isoString = "${dateStr}";

        // print('isoString: $isoString');
        //  date = DateTime.parse(isoString);
      }
    } catch (e) {
      debugPrint('Error parsing date for memory ${map['id']}: $e');
    }

    return MemoryLocation(
      id: map['id']?.toString() ?? '',
      latitude: lat,
      longitude: lng,
      memoryDate: date,
      title: map['text'] ?? map['description'] ?? '',
      description: map['text'] ?? map['description'] ?? '',
      metadata: Map<String, dynamic>.from(map),
      memoryData: Map<String, dynamic>.from(map),
    );
  }

  DateTime combineDateTime(String dateStr, String timeStr) {
    final date = DateTime.parse(dateStr); // parses YYYY-MM-DD safely
    final parts = timeStr.split(":");

    int hour = int.parse(parts[0]);
    int minute = parts.length > 1 ? int.parse(parts[1]) : 0;

    return DateTime(date.year, date.month, date.day, hour, minute);
  }
}

class MemoryCluster {
  final String id;
  final List<MemoryLocation> memories;
  final double centerLatitude;
  final double centerLongitude;
  final double radiusKm;

  MemoryCluster({
    required this.id,
    required this.memories,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.radiusKm,
  });

  int get memoryCount => memories.length;

  DateTime get earliestDate {
    if (memories.isEmpty) return DateTime.now();
    return memories
        .map((m) => m.memoryDate)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  DateTime get latestDate {
    if (memories.isEmpty) return DateTime.now();
    return memories
        .map((m) => m.memoryDate)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  bool get isSingleMemory => memories.length == 1;

  MemoryLocation? get singleMemory => isSingleMemory ? memories.first : null;
}

class ChronologicalArrow {
  final double fromLatitude;
  final double fromLongitude;
  final double toLatitude;
  final double toLongitude;
  final DateTime fromDate;
  final DateTime toDate;
  final String fromClusterId;
  final String toClusterId;

  ChronologicalArrow({
    required this.fromLatitude,
    required this.fromLongitude,
    required this.toLatitude,
    required this.toLongitude,
    required this.fromDate,
    required this.toDate,
    required this.fromClusterId,
    required this.toClusterId,
  });

  double get bearing => MemoryClusteringService.calculateBearing(
    fromLatitude,
    fromLongitude,
    toLatitude,
    toLongitude,
  );

  double get distance => MemoryClusteringService.calculateDistance(
    fromLatitude,
    fromLongitude,
    toLatitude,
    toLongitude,
  );

  // Calculate midpoint for arrow placement
  double get midLatitude => (fromLatitude + toLatitude) / 2;
  double get midLongitude => (fromLongitude + toLongitude) / 2;
}
