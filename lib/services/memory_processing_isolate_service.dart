import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/services/memory_clustering_service.dart';

/// Service that handles memory loading and clustering in isolates for better performance
class MemoryProcessingIsolateService extends GetxService {
  static MemoryProcessingIsolateService get instance => Get.find();

  // Isolate management
  Isolate? _processingIsolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  StreamSubscription? _isolateSubscription;

  // State management
  final RxBool isProcessingMemories = false.obs;
  final RxDouble processingProgress = 0.0.obs;
  final RxString processingStatus = 'Idle'.obs;
  final RxList<Map<String, dynamic>> processedMemories =
      <Map<String, dynamic>>[].obs;
  final RxList<MemoryCluster> processedClusters = <MemoryCluster>[].obs;
  final RxList<ChronologicalArrow> processedArrows = <ChronologicalArrow>[].obs;

  // Completion callbacks
  final List<
    Function(
      List<Map<String, dynamic>>,
      List<MemoryCluster>,
      List<ChronologicalArrow>,
    )
  >
  _completionCallbacks = [];

  @override
  Future<void> onInit() async {
    super.onInit();
    await _initializeProcessingIsolate();
    debugPrint('[MemoryProcessingIsolateService] Service initialized');
  }

  @override
  void onClose() {
    _cleanup();
    super.onClose();
  }

  /// Initialize the memory processing isolate
  Future<void> _initializeProcessingIsolate() async {
    try {
      _receivePort = ReceivePort();

      // Spawn isolate with entry point
      _processingIsolate = await Isolate.spawn(
        _memoryProcessingIsolateEntryPoint,
        _receivePort!.sendPort,
        debugName: 'MemoryProcessingIsolate',
      );

      // Listen to messages from isolate
      _isolateSubscription = _receivePort!.listen(_handleIsolateMessage);

      debugPrint(
        '[MemoryProcessingIsolateService] Processing isolate initialized',
      );
    } catch (e) {
      debugPrint(
        '[MemoryProcessingIsolateService] Error initializing isolate: $e',
      );
    }
  }

  /// Entry point for the memory processing isolate
  static void _memoryProcessingIsolateEntryPoint(SendPort mainSendPort) {
    final isolateReceivePort = ReceivePort();

    // Send the isolate's send port back to main isolate
    mainSendPort.send(isolateReceivePort.sendPort);

    // Listen for processing commands from main isolate
    isolateReceivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        await _processMemoryCommand(message, mainSendPort);
      }
    });
  }

  /// Process memory commands in the isolate
  static Future<void> _processMemoryCommand(
    Map<String, dynamic> command,
    SendPort mainSendPort,
  ) async {
    try {
      final type = command['type'] as String;

      switch (type) {
        case 'load_and_process_memories':
          await _loadAndProcessMemoriesInIsolate(command, mainSendPort);
          break;
        case 'cluster_memories':
          await _clusterMemoriesInIsolate(command, mainSendPort);
          break;
        case 'generate_arrows':
          await _generateArrowsInIsolate(command, mainSendPort);
          break;
      }
    } catch (e) {
      mainSendPort.send({
        'type': 'error',
        'message': 'Error in memory processing isolate: $e',
      });
    }
  }

  /// Load and process memories in isolate
  static Future<void> _loadAndProcessMemoriesInIsolate(
    Map<String, dynamic> command,
    SendPort mainSendPort,
  ) async {
    try {
      mainSendPort.send({
        'type': 'progress_update',
        'progress': 0.1,
        'status': 'Loading memories from database...',
      });

      // Create database helper instance in isolate
      final databaseHelper = DatabaseHelper.instance;
      final memories = await databaseHelper.getAllMemoriesWithDetails();

      mainSendPort.send({
        'type': 'progress_update',
        'progress': 0.3,
        'status': 'Processing ${memories.length} memories...',
      });

      // Filter memories with valid coordinates
      final memoriesWithCoordinates =
          memories
              .where((memory) => _hasValidCoordinatesInIsolate(memory))
              .toList();

      mainSendPort.send({
        'type': 'progress_update',
        'progress': 0.5,
        'status':
            'Converting ${memoriesWithCoordinates.length} memories to locations...',
      });

      // Convert to MemoryLocation objects
      final memoryLocations = <Map<String, dynamic>>[];
      for (final memory in memoriesWithCoordinates) {
        try {
          final memoryLocation = _convertToMemoryLocationMap(memory);
          memoryLocations.add(memoryLocation);
        } catch (e) {
          debugPrint(
            '[MemoryProcessingIsolate] Error converting memory ${memory['id']}: $e',
          );
        }
      }

      mainSendPort.send({
        'type': 'progress_update',
        'progress': 0.7,
        'status': 'Starting clustering process...',
      });

      // Perform clustering
      final clusterRadius = command['cluster_radius'] as double? ?? 50.0;
      final clusters = await _performClusteringInIsolate(
        memoryLocations,
        clusterRadius,
        mainSendPort,
      );

      mainSendPort.send({
        'type': 'progress_update',
        'progress': 0.9,
        'status': 'Generating chronological arrows...',
      });

      // Generate arrows
      final arrows = await _generateArrowsFromClustersInIsolate(
        clusters,
        mainSendPort,
      );

      mainSendPort.send({
        'type': 'processing_completed',
        'memories': memories,
        'clusters': clusters,
        'arrows': arrows,
      });
    } catch (e) {
      mainSendPort.send({'type': 'processing_error', 'error': e.toString()});
    }
  }

  /// Cluster memories in isolate
  static Future<void> _clusterMemoriesInIsolate(
    Map<String, dynamic> command,
    SendPort mainSendPort,
  ) async {
    try {
      final memoryLocations =
          command['memory_locations'] as List<Map<String, dynamic>>;
      final clusterRadius = command['cluster_radius'] as double;

      mainSendPort.send({
        'type': 'progress_update',
        'progress': 0.1,
        'status': 'Starting clustering...',
      });

      final clusters = await _performClusteringInIsolate(
        memoryLocations,
        clusterRadius,
        mainSendPort,
      );

      mainSendPort.send({'type': 'clustering_completed', 'clusters': clusters});
    } catch (e) {
      mainSendPort.send({'type': 'clustering_error', 'error': e.toString()});
    }
  }

  /// Generate arrows in isolate
  static Future<void> _generateArrowsInIsolate(
    Map<String, dynamic> command,
    SendPort mainSendPort,
  ) async {
    try {
      final clusters = command['clusters'] as List<Map<String, dynamic>>;

      mainSendPort.send({
        'type': 'progress_update',
        'progress': 0.1,
        'status': 'Generating chronological arrows...',
      });

      final arrows = await _generateArrowsFromClustersInIsolate(
        clusters,
        mainSendPort,
      );

      mainSendPort.send({'type': 'arrows_completed', 'arrows': arrows});
    } catch (e) {
      mainSendPort.send({'type': 'arrows_error', 'error': e.toString()});
    }
  }

  /// Perform clustering logic in isolate
  static Future<List<Map<String, dynamic>>> _performClusteringInIsolate(
    List<Map<String, dynamic>> memoryLocationMaps,
    double radiusKm,
    SendPort mainSendPort,
  ) async {
    if (memoryLocationMaps.isEmpty) return [];

    final clusters = <Map<String, dynamic>>[];
    final processed = List.filled(memoryLocationMaps.length, false);

    for (int i = 0; i < memoryLocationMaps.length; i++) {
      if (processed[i]) continue;

      final clusterMemories = <Map<String, dynamic>>[memoryLocationMaps[i]];
      processed[i] = true;

      // Find all memories within radius
      for (int j = i + 1; j < memoryLocationMaps.length; j++) {
        if (processed[j]) continue;

        final distance = _calculateDistanceInIsolate(
          memoryLocationMaps[i]['latitude'] as double,
          memoryLocationMaps[i]['longitude'] as double,
          memoryLocationMaps[j]['latitude'] as double,
          memoryLocationMaps[j]['longitude'] as double,
        );

        if (distance <= radiusKm) {
          clusterMemories.add(memoryLocationMaps[j]);
          processed[j] = true;
        }
      }

      // Create cluster
      final cluster = _createClusterMapInIsolate(clusterMemories, radiusKm);
      clusters.add(cluster);

      // Send progress update
      final progress = 0.1 + (0.6 * (i + 1) / memoryLocationMaps.length);
      mainSendPort.send({
        'type': 'progress_update',
        'progress': progress,
        'status': 'Clustering... ${i + 1}/${memoryLocationMaps.length}',
      });
    }

    return clusters;
  }

  /// Generate arrows from clusters in isolate
  static Future<List<Map<String, dynamic>>>
  _generateArrowsFromClustersInIsolate(
    List<Map<String, dynamic>> clusterMaps,
    SendPort mainSendPort,
  ) async {
    if (clusterMaps.length < 2) return [];

    final arrows = <Map<String, dynamic>>[];

    // Create a list of all individual memories with their cluster info
    final memoriesWithClusters = <Map<String, dynamic>>[];
    for (final clusterMap in clusterMaps) {
      final memories = clusterMap['memories'] as List<Map<String, dynamic>>;
      for (final memory in memories) {
        memoriesWithClusters.add({
          'memory': memory,
          'cluster_id': clusterMap['id'],
          'cluster_center_lat': clusterMap['center_latitude'],
          'cluster_center_lng': clusterMap['center_longitude'],
        });
      }
    }

    // Sort all memories by date
    memoriesWithClusters.sort((a, b) {
      final dateA = DateTime.parse(a['memory']['memory_date'] as String);
      final dateB = DateTime.parse(b['memory']['memory_date'] as String);
      return dateA.compareTo(dateB);
    });

    // Generate arrows between consecutive memories from different clusters
    for (int i = 0; i < memoriesWithClusters.length - 1; i++) {
      final current = memoriesWithClusters[i];
      final next = memoriesWithClusters[i + 1];

      // Only create arrow if memories are from different clusters
      if (current['cluster_id'] != next['cluster_id']) {
        final arrow = {
          'id': 'arrow_${current['cluster_id']}_to_${next['cluster_id']}_$i',
          'from_cluster_id': current['cluster_id'],
          'to_cluster_id': next['cluster_id'],
          'from_latitude': current['cluster_center_lat'],
          'from_longitude': current['cluster_center_lng'],
          'to_latitude': next['cluster_center_lat'],
          'to_longitude': next['cluster_center_lng'],
          'from_date': current['memory']['memory_date'],
          'to_date': next['memory']['memory_date'],
        };
        arrows.add(arrow);
      }

      // Send progress update
      final progress = 0.1 + (0.8 * (i + 1) / memoriesWithClusters.length);
      mainSendPort.send({
        'type': 'progress_update',
        'progress': progress,
        'status':
            'Generating arrows... ${i + 1}/${memoriesWithClusters.length}',
      });
    }

    return arrows;
  }

  /// Helper methods for isolate processing

  /// Check if memory has valid coordinates in isolate
  static bool _hasValidCoordinatesInIsolate(Map<String, dynamic> memory) {
    final lat = memory['location_latitude'];
    final lng = memory['location_longitude'];
    return lat != null &&
        lng != null &&
        lat is num &&
        lng is num &&
        lat != 0.0 &&
        lng != 0.0;
  }

  /// Convert memory to MemoryLocation map in isolate
  static Map<String, dynamic> _convertToMemoryLocationMap(
    Map<String, dynamic> memory,
  ) {
    return {
      'id': memory['id'],
      'latitude': (memory['location_latitude'] as num).toDouble(),
      'longitude': (memory['location_longitude'] as num).toDouble(),
      'memory_date':
          memory['memory_date'] ??
          memory['created_at'] ??
          DateTime.now().toIso8601String(),
      'description': memory['description'] ?? '',
      'location': memory['location'] ?? '',
      'metadata': memory,
    };
  }

  /// Calculate distance between two points in isolate
  static double _calculateDistanceInIsolate(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371.0; // Earth's radius in kilometers

    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLng = _degreesToRadians(lng2 - lng1);

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }

  /// Convert degrees to radians
  static double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  /// Create cluster map in isolate
  static Map<String, dynamic> _createClusterMapInIsolate(
    List<Map<String, dynamic>> clusterMemories,
    double radiusKm,
  ) {
    // Calculate center coordinates
    double totalLat = 0.0;
    double totalLng = 0.0;

    for (final memory in clusterMemories) {
      totalLat += memory['latitude'] as double;
      totalLng += memory['longitude'] as double;
    }

    final centerLat = totalLat / clusterMemories.length;
    final centerLng = totalLng / clusterMemories.length;

    // Generate unique cluster ID
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final clusterId =
        'cluster_${timestamp}_${clusterMemories.length}_${centerLat.toStringAsFixed(6)}';

    return {
      'id': clusterId,
      'memories': clusterMemories,
      'center_latitude': centerLat,
      'center_longitude': centerLng,
      'radius_km': radiusKm,
      'memory_count': clusterMemories.length,
    };
  }

  /// Handle messages from the processing isolate
  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      // This is the isolate's send port
      _sendPort = message;
      debugPrint('[MemoryProcessingIsolateService] Received isolate send port');
      return;
    }

    if (message is Map<String, dynamic>) {
      final type = message['type'] as String;

      switch (type) {
        case 'progress_update':
          _handleProgressUpdate(message);
          break;
        case 'processing_completed':
          _handleProcessingCompleted(message);
          break;
        case 'clustering_completed':
          _handleClusteringCompleted(message);
          break;
        case 'arrows_completed':
          _handleArrowsCompleted(message);
          break;
        case 'processing_error':
        case 'clustering_error':
        case 'arrows_error':
          _handleProcessingError(message);
          break;
        case 'error':
          debugPrint(
            '[MemoryProcessingIsolateService] Isolate error: ${message['message']}',
          );
          break;
      }
    }
  }

  /// Handle progress update message
  void _handleProgressUpdate(Map<String, dynamic> message) {
    processingProgress.value = message['progress'] as double;
    processingStatus.value = message['status'] as String;
    debugPrint(
      '[MemoryProcessingIsolateService] Progress: ${(processingProgress.value * 100).toStringAsFixed(1)}% - ${processingStatus.value}',
    );
  }

  /// Handle processing completed message
  void _handleProcessingCompleted(Map<String, dynamic> message) {
    try {
      final memories =
          (message['memories'] as List).cast<Map<String, dynamic>>();
      final clusterMaps =
          (message['clusters'] as List).cast<Map<String, dynamic>>();
      final arrowMaps =
          (message['arrows'] as List).cast<Map<String, dynamic>>();

      // Convert cluster maps to MemoryCluster objects
      final clusters =
          clusterMaps
              .map((clusterMap) => _convertMapToMemoryCluster(clusterMap))
              .toList();

      // Convert arrow maps to ChronologicalArrow objects
      final arrows =
          arrowMaps
              .map((arrowMap) => _convertMapToChronologicalArrow(arrowMap))
              .toList();

      // Update reactive variables
      processedMemories.assignAll(memories);
      processedClusters.assignAll(clusters);
      processedArrows.assignAll(arrows);

      isProcessingMemories.value = false;
      processingProgress.value = 1.0;
      processingStatus.value = 'Processing completed';

      debugPrint(
        '[MemoryProcessingIsolateService] Processing completed: ${memories.length} memories, ${clusters.length} clusters, ${arrows.length} arrows',
      );

      // Notify completion callbacks
      for (final callback in _completionCallbacks) {
        callback(memories, clusters, arrows);
      }
      _completionCallbacks.clear();
    } catch (e) {
      debugPrint(
        '[MemoryProcessingIsolateService] Error handling processing completion: $e',
      );
      _handleProcessingError({'error': e.toString()});
    }
  }

  /// Handle clustering completed message
  void _handleClusteringCompleted(Map<String, dynamic> message) {
    try {
      final clusterMaps =
          (message['clusters'] as List).cast<Map<String, dynamic>>();
      final clusters =
          clusterMaps
              .map((clusterMap) => _convertMapToMemoryCluster(clusterMap))
              .toList();

      processedClusters.assignAll(clusters);
      debugPrint(
        '[MemoryProcessingIsolateService] Clustering completed: ${clusters.length} clusters',
      );
    } catch (e) {
      debugPrint(
        '[MemoryProcessingIsolateService] Error handling clustering completion: $e',
      );
    }
  }

  /// Handle arrows completed message
  void _handleArrowsCompleted(Map<String, dynamic> message) {
    try {
      final arrowMaps =
          (message['arrows'] as List).cast<Map<String, dynamic>>();
      final arrows =
          arrowMaps
              .map((arrowMap) => _convertMapToChronologicalArrow(arrowMap))
              .toList();

      processedArrows.assignAll(arrows);
      debugPrint(
        '[MemoryProcessingIsolateService] Arrow generation completed: ${arrows.length} arrows',
      );
    } catch (e) {
      debugPrint(
        '[MemoryProcessingIsolateService] Error handling arrow completion: $e',
      );
    }
  }

  /// Handle processing error message
  void _handleProcessingError(Map<String, dynamic> message) {
    isProcessingMemories.value = false;
    processingStatus.value = 'Error: ${message['error']}';
    debugPrint(
      '[MemoryProcessingIsolateService] Processing error: ${message['error']}',
    );

    Get.snackbar(
      'Memory Processing Error',
      'Failed to process memories: ${message['error']}',
      backgroundColor: Colors.red,
      colorText: Colors.white,
      duration: Duration(seconds: 5),
    );
  }

  /// Convert cluster map to MemoryCluster object
  MemoryCluster _convertMapToMemoryCluster(Map<String, dynamic> clusterMap) {
    final memoryMaps =
        (clusterMap['memories'] as List).cast<Map<String, dynamic>>();
    final memories =
        memoryMaps
            .map(
              (memoryMap) => MemoryLocation(
                id: (memoryMap['id'] as int).toString(),
                latitude: memoryMap['latitude'] as double,
                longitude: memoryMap['longitude'] as double,
                memoryDate: DateTime.parse(memoryMap['memory_date'] as String),
                title: memoryMap['description'] as String,
                description: memoryMap['description'] as String,
                metadata: memoryMap['metadata'] as Map<String, dynamic>,
                memoryData: memoryMap['metadata'] as Map<String, dynamic>,
              ),
            )
            .toList();

    return MemoryCluster(
      id: clusterMap['id'] as String,
      memories: memories,
      centerLatitude: clusterMap['center_latitude'] as double,
      centerLongitude: clusterMap['center_longitude'] as double,
      radiusKm: clusterMap['radius_km'] as double,
    );
  }

  /// Convert arrow map to ChronologicalArrow object
  ChronologicalArrow _convertMapToChronologicalArrow(
    Map<String, dynamic> arrowMap,
  ) {
    return ChronologicalArrow(
      fromLatitude: arrowMap['from_latitude'] as double,
      fromLongitude: arrowMap['from_longitude'] as double,
      toLatitude: arrowMap['to_latitude'] as double,
      toLongitude: arrowMap['to_longitude'] as double,
      fromDate: DateTime.parse(arrowMap['from_date'] as String),
      toDate: DateTime.parse(arrowMap['to_date'] as String),
      fromClusterId: arrowMap['from_cluster_id'] as String,
      toClusterId: arrowMap['to_cluster_id'] as String,
    );
  }

  /// Public methods for external use

  /// Load and process all memories from database
  Future<void> loadAndProcessMemories({
    double clusterRadius = 50.0,
    Function(
      List<Map<String, dynamic>>,
      List<MemoryCluster>,
      List<ChronologicalArrow>,
    )?
    onCompleted,
  }) async {
    if (isProcessingMemories.value) {
      debugPrint(
        '[MemoryProcessingIsolateService] Already processing memories, ignoring request',
      );
      return;
    }

    if (_sendPort == null) {
      debugPrint(
        '[MemoryProcessingIsolateService] Isolate not ready, cannot process memories',
      );
      return;
    }

    if (onCompleted != null) {
      _completionCallbacks.add(onCompleted);
    }

    isProcessingMemories.value = true;
    processingProgress.value = 0.0;
    processingStatus.value = 'Starting memory processing...';

    _sendPort!.send({
      'type': 'load_and_process_memories',
      'cluster_radius': clusterRadius,
    });

    debugPrint(
      '[MemoryProcessingIsolateService] Started memory processing with radius: ${clusterRadius}km',
    );
  }

  /// Cluster existing memory locations
  Future<void> clusterMemoryLocations(
    List<MemoryLocation> memoryLocations,
    double clusterRadius, {
    Function(List<MemoryCluster>)? onCompleted,
  }) async {
    if (isProcessingMemories.value) {
      debugPrint(
        '[MemoryProcessingIsolateService] Already processing, ignoring clustering request',
      );
      return;
    }

    if (_sendPort == null) {
      debugPrint(
        '[MemoryProcessingIsolateService] Isolate not ready, cannot cluster memories',
      );
      return;
    }

    isProcessingMemories.value = true;
    processingProgress.value = 0.0;
    processingStatus.value = 'Starting clustering...';

    // Convert MemoryLocation objects to maps for isolate
    final memoryLocationMaps =
        memoryLocations
            .map(
              (location) => {
                'id': location.id,
                'latitude': location.latitude,
                'longitude': location.longitude,
                'memory_date': location.memoryDate.toIso8601String(),
                'description': location.description,
                'title': location.title,
                'metadata': location.metadata,
              },
            )
            .toList();

    _sendPort!.send({
      'type': 'cluster_memories',
      'memory_locations': memoryLocationMaps,
      'cluster_radius': clusterRadius,
    });

    debugPrint(
      '[MemoryProcessingIsolateService] Started clustering ${memoryLocations.length} memories with radius: ${clusterRadius}km',
    );
  }

  /// Generate chronological arrows for existing clusters
  Future<void> generateArrowsForClusters(
    List<MemoryCluster> clusters, {
    Function(List<ChronologicalArrow>)? onCompleted,
  }) async {
    if (isProcessingMemories.value) {
      debugPrint(
        '[MemoryProcessingIsolateService] Already processing, ignoring arrow generation request',
      );
      return;
    }

    if (_sendPort == null) {
      debugPrint(
        '[MemoryProcessingIsolateService] Isolate not ready, cannot generate arrows',
      );
      return;
    }

    isProcessingMemories.value = true;
    processingProgress.value = 0.0;
    processingStatus.value = 'Generating arrows...';

    // Convert MemoryCluster objects to maps for isolate
    final clusterMaps =
        clusters
            .map(
              (cluster) => {
                'id': cluster.id,
                'memories':
                    cluster.memories
                        .map(
                          (memory) => {
                            'id': memory.id,
                            'latitude': memory.latitude,
                            'longitude': memory.longitude,
                            'memory_date': memory.memoryDate.toIso8601String(),
                            'description': memory.description,
                            'title': memory.title,
                            'metadata': memory.metadata,
                          },
                        )
                        .toList(),
                'center_latitude': cluster.centerLatitude,
                'center_longitude': cluster.centerLongitude,
                'radius_km': cluster.radiusKm,
                'memory_count': cluster.memoryCount,
              },
            )
            .toList();

    _sendPort!.send({'type': 'generate_arrows', 'clusters': clusterMaps});

    debugPrint(
      '[MemoryProcessingIsolateService] Started arrow generation for ${clusters.length} clusters',
    );
  }

  /// Cleanup resources
  void _cleanup() {
    _isolateSubscription?.cancel();
    _receivePort?.close();
    _processingIsolate?.kill(priority: Isolate.immediate);
    _completionCallbacks.clear();

    debugPrint('[MemoryProcessingIsolateService] Cleanup completed');
  }

  /// Get current processing status
  ProcessingStatus getCurrentStatus() {
    return ProcessingStatus(
      isProcessing: isProcessingMemories.value,
      progress: processingProgress.value,
      status: processingStatus.value,
      memoriesCount: processedMemories.length,
      clustersCount: processedClusters.length,
      arrowsCount: processedArrows.length,
    );
  }
}

/// Processing status model
class ProcessingStatus {
  final bool isProcessing;
  final double progress;
  final String status;
  final int memoriesCount;
  final int clustersCount;
  final int arrowsCount;

  ProcessingStatus({
    required this.isProcessing,
    required this.progress,
    required this.status,
    required this.memoriesCount,
    required this.clustersCount,
    required this.arrowsCount,
  });
}
