import 'dart:math' as math;

/// Represents a cluster of memories at a specific location
class MemoryCluster {
  final String id;
  final double latitude;
  final double longitude;
  final List<Map<String, dynamic>> memories;
  final int count;
  final DateTime? earliestDate;
  final DateTime? latestDate;
  final double radiusKm;

  MemoryCluster({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.memories,
    required this.radiusKm,
  }) : count = memories.length,
       earliestDate = _calculateEarliestDate(memories),
       latestDate = _calculateLatestDate(memories);

  /// Calculate the earliest date from memories
  static DateTime? _calculateEarliestDate(List<Map<String, dynamic>> memories) {
    DateTime? earliest;
    for (final memory in memories) {
      final dateStr = memory['date'] as String?;
      if (dateStr != null) {
        try {
          final date = DateTime.parse(dateStr);
          if (earliest == null || date.isBefore(earliest)) {
            earliest = date;
          }
        } catch (e) {
          // Skip invalid dates
        }
      }
    }
    return earliest;
  }

  /// Calculate the latest date from memories
  static DateTime? _calculateLatestDate(List<Map<String, dynamic>> memories) {
    DateTime? latest;
    for (final memory in memories) {
      final dateStr = memory['date'] as String?;
      if (dateStr != null) {
        try {
          final date = DateTime.parse(dateStr);
          if (latest == null || date.isAfter(latest)) {
            latest = date;
          }
        } catch (e) {
          // Skip invalid dates
        }
      }
    }
    return latest;
  }

  /// Get the center point of all memories in the cluster
  static Map<String, double> calculateCenter(
    List<Map<String, dynamic>> memories,
  ) {
    if (memories.isEmpty) {
      return {'latitude': 0.0, 'longitude': 0.0};
    }

    double totalLat = 0.0;
    double totalLng = 0.0;
    int validCount = 0;

    for (final memory in memories) {
      final lat = memory['location_latitude'] as double?;
      final lng = memory['location_longitude'] as double?;

      if (lat != null && lng != null) {
        totalLat += lat;
        totalLng += lng;
        validCount++;
      }
    }

    if (validCount == 0) {
      return {'latitude': 0.0, 'longitude': 0.0};
    }

    return {
      'latitude': totalLat / validCount,
      'longitude': totalLng / validCount,
    };
  }

  /// Get memories with images
  List<Map<String, dynamic>> get memoriesWithImages {
    return memories.where((memory) {
      final images = memory['images'] as List<dynamic>?;
      return images != null && images.isNotEmpty;
    }).toList();
  }

  /// Get memories with audio
  List<Map<String, dynamic>> get memoriesWithAudio {
    return memories.where((memory) {
      final audios = memory['audios'] as List<dynamic>?;
      return audios != null && audios.isNotEmpty;
    }).toList();
  }

  /// Get all categories in this cluster
  Set<String> get categories {
    final categorySet = <String>{};
    for (final memory in memories) {
      final category = memory['category'] as String?;
      if (category != null && category.isNotEmpty) {
        categorySet.add(category);
      }
    }
    return categorySet;
  }

  /// Get all tags in this cluster
  Set<String> get tags {
    final tagSet = <String>{};
    for (final memory in memories) {
      final tagsStr = memory['tags'] as String?;
      if (tagsStr != null && tagsStr.isNotEmpty) {
        final tagList = tagsStr
            .split(',')
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty);
        tagSet.addAll(tagList);
      }
    }
    return tagSet;
  }

  /// Get cluster summary for display
  String get summary {
    final buffer = StringBuffer();
    buffer.write('$count memories');

    if (categories.isNotEmpty) {
      buffer.write(' • ${categories.join(', ')}');
    }

    if (earliestDate != null && latestDate != null) {
      if (earliestDate!.year == latestDate!.year) {
        buffer.write(' • ${earliestDate!.year}');
      } else {
        buffer.write(' • ${earliestDate!.year}-${latestDate!.year}');
      }
    }

    return buffer.toString();
  }

  /// Convert to JSON for debugging
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'count': count,
      'radiusKm': radiusKm,
      'earliestDate': earliestDate?.toIso8601String(),
      'latestDate': latestDate?.toIso8601String(),
      'categories': categories.toList(),
      'tags': tags.toList(),
      'summary': summary,
    };
  }

  @override
  String toString() {
    return 'MemoryCluster(id: $id, count: $count, lat: ${latitude.toStringAsFixed(4)}, lng: ${longitude.toStringAsFixed(4)})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MemoryCluster && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Configuration for clustering algorithm
class ClusteringConfig {
  final double maxDistanceKm;
  final int minClusterSize;
  final int maxZoomLevel;
  final bool enableDynamicClustering;

  const ClusteringConfig({
    this.maxDistanceKm = 1.0,
    this.minClusterSize = 2,
    this.maxZoomLevel = 15,
    this.enableDynamicClustering = true,
  });

  /// Get clustering distance based on zoom level
  double getClusteringDistance(double zoomLevel) {
    if (!enableDynamicClustering) return maxDistanceKm;

    // Adjust clustering distance based on zoom level
    // Higher zoom = smaller clustering distance
    final factor = math.max(0.1, (maxZoomLevel - zoomLevel) / maxZoomLevel);
    return maxDistanceKm * factor;
  }

  ClusteringConfig copyWith({
    double? maxDistanceKm,
    int? minClusterSize,
    int? maxZoomLevel,
    bool? enableDynamicClustering,
  }) {
    return ClusteringConfig(
      maxDistanceKm: maxDistanceKm ?? this.maxDistanceKm,
      minClusterSize: minClusterSize ?? this.minClusterSize,
      maxZoomLevel: maxZoomLevel ?? this.maxZoomLevel,
      enableDynamicClustering:
          enableDynamicClustering ?? this.enableDynamicClustering,
    );
  }
}

/// Result of clustering operation
class ClusteringResult {
  final List<MemoryCluster> clusters;
  final List<Map<String, dynamic>> individualMemories;
  final ClusteringConfig config;
  final DateTime timestamp;
  final int totalMemories;

  ClusteringResult({
    required this.clusters,
    required this.individualMemories,
    required this.config,
    required this.totalMemories,
  }) : timestamp = DateTime.now();

  /// Get total number of clustered memories
  int get clusteredMemoriesCount {
    return clusters.fold(0, (sum, cluster) => sum + cluster.count);
  }

  /// Get clustering efficiency (percentage of memories that were clustered)
  double get clusteringEfficiency {
    if (totalMemories == 0) return 0.0;
    return (clusteredMemoriesCount / totalMemories) * 100;
  }

  /// Get summary statistics
  Map<String, dynamic> get statistics {
    return {
      'totalMemories': totalMemories,
      'clustersCount': clusters.length,
      'individualMemoriesCount': individualMemories.length,
      'clusteredMemoriesCount': clusteredMemoriesCount,
      'clusteringEfficiency': clusteringEfficiency,
      'timestamp': timestamp.toIso8601String(),
      'config': {
        'maxDistanceKm': config.maxDistanceKm,
        'minClusterSize': config.minClusterSize,
      },
    };
  }

  @override
  String toString() {
    return 'ClusteringResult(clusters: ${clusters.length}, individual: ${individualMemories.length}, efficiency: ${clusteringEfficiency.toStringAsFixed(1)}%)';
  }
}
