# Arrows and Lines Logic Documentation

## Overview
This document describes the comprehensive logic for drawing arrows and lines between single location markers and clusters in the SpaceTime memory mapping application.

## Core Components

### 1. ChronologicalArrow Class
```dart
class ChronologicalArrow {
  final double fromLatitude;
  final double fromLongitude;
  final double toLatitude;
  final double toLongitude;
  final DateTime fromDate;
  final DateTime toDate;
  final String fromClusterId;
  final String toClusterId;
}
```

**Purpose**: Represents a temporal connection between two memory locations or clusters.

### 2. Arrow Generation Logic

#### A. Primary Arrow Generation (`generateChronologicalArrows`)
**Location**: `lib/services/memory_clustering_service.dart`

**Algorithm**:
1. **Memory Collection**: Gather all individual memories from all clusters
2. **Chronological Sorting**: Sort memories by `memoryDate` in ascending order
3. **Sequential Connection**: Connect each memory to the next chronological memory
4. **Cluster-Level Aggregation**: Only create arrows between different clusters
5. **Multiple Connections**: Allow multiple arrows between same cluster pairs for different time periods

**Code Flow**:
```dart
// 1. Create memory-cluster pairs
for (final cluster in clusters) {
  for (final memory in cluster.memories) {
    memoriesWithClusters.add(MemoryWithCluster(memory, cluster));
  }
}

// 2. Sort chronologically
memoriesWithClusters.sort((a, b) => a.memory.memoryDate.compareTo(b.memory.memoryDate));

// 3. Generate arrows between different clusters only
for (int i = 0; i < memoriesWithClusters.length - 1; i++) {
  final currentMemory = memoriesWithClusters[i];
  final nextMemory = memoriesWithClusters[i + 1];

  // Only connect different clusters
  if (currentMemory.cluster.id != nextMemory.cluster.id) {
    // Create arrow for each chronological connection
    arrows.add(ChronologicalArrow(
      fromLatitude: currentMemory.cluster.centerLatitude,
      fromLongitude: currentMemory.cluster.centerLongitude,
      toLatitude: nextMemory.cluster.centerLatitude,
      toLongitude: nextMemory.cluster.centerLongitude,
      fromDate: currentMemory.memory.memoryDate,
      toDate: nextMemory.memory.memoryDate,
      fromClusterId: currentMemory.cluster.id,
      toClusterId: nextMemory.cluster.id,
    ));
  }
}
```

#### B. Drill-Down Arrow Generation (`_generateDrillDownArrows`)
**Location**: `lib/app/modules/map/controllers/map_controller.dart`

**Purpose**: Generate arrows within a specific cluster when user drills down.

**Logic**:
- Generate internal arrows within subclusters
- Preserve external connections to other main clusters
- Focus on detailed temporal relationships within the selected area

### 3. Arrow Display Logic

#### A. Main Display Method (`_displayChronologicalArrows`)
**Location**: `lib/app/modules/map/controllers/map_controller.dart`

**Process**:
1. **Performance Optimization**: Limit arrows using `maxArrowsToDisplay`
2. **Manager Creation**: Get or create polyline annotation manager
3. **Clean Slate**: Clear existing arrows before drawing new ones
4. **Curved Line Generation**: Create curved paths between points
5. **Shadow and Main Line**: Draw shadow first, then main line
6. **Arrow Head Placement**: Add directional arrow heads

**Code Structure**:
```dart
Future<void> _displayChronologicalArrows() async {
  // 1. Performance check
  final arrowsToDisplay = currentArrows.length > maxArrowsToDisplay
      ? currentArrows.take(maxArrowsToDisplay).toList()
      : currentArrows;

  // 2. Get line manager
  final lineManager = await _getPolylineManager();
  await lineManager.deleteAll();

  // 3. Draw each arrow
  for (final arrow in arrowsToDisplay) {
    // Create curved line
    final points = _createCurvedArrowLine(...);
    
    // Draw shadow
    await lineManager.create(shadowLine);
    
    // Draw main line with color
    await lineManager.create(mainLine);
    
    // Add arrow head
    await _addArrowHeadOnCurve(points, color);
  }
}
```

### 4. Line Styling and Colors

#### A. Color System
**Enhanced Color Palette**:
```dart
// Line colors for different connection types
final List<Color> lineColors = [
  Color(0xFF1976D2), // Deep Blue
  Color(0xFF388E3C), // Deep Green
  Color(0xFFF57C00), // Deep Orange
  // ... 15 total colors
];

// Connection type specific colors
final Map<String, Color> connectionTypeColors = {
  'same_day': Color(0xFF4CAF50),      // Green
  'same_week': Color(0xFF2196F3),     // Blue
  'same_month': Color(0xFFFF9800),    // Orange
  'same_year': Color(0xFF9C27B0),     // Purple
  'different_year': Color(0xFFF44336), // Red
  'cluster_internal': Color(0xFF00BCD4), // Cyan
  'cluster_external': Color(0xFFE91E63), // Pink
};
```

#### B. Color Selection Logic
**Current Implementation**:
```dart
// Simple random color based on seed
final lineColor = getRandomMarkerColor(4);
```

**Enhanced Logic** (Available but not currently active):
- Time-based coloring (same day, week, month, year)
- Cluster relationship coloring (internal vs external)
- Distance-based coloring
- Custom type-based coloring

### 5. Curved Line Generation

#### A. Curve Algorithm (`_createCurvedArrowLine`)
**Purpose**: Create smooth curved paths instead of straight lines for better visual appeal.

**Parameters**:
- `segments`: Number of curve segments (default: 32)
- `curvature`: How much the line curves (0.15 = 15% of distance)

**Algorithm**:
1. **Direction Calculation**: Determine bearing between points
2. **Perpendicular Offset**: Calculate curve control point perpendicular to line
3. **Bezier Interpolation**: Generate smooth curve using quadratic Bezier
4. **Segment Generation**: Create multiple points along the curve

**Mathematical Implementation**:
```dart
// 1. Calculate direction and distance
final dx = lng2 - lng1;
final dy = lat2 - lat1;
final len = sqrt(dx * dx + dy * dy);

// 2. Create perpendicular control point
final perpX = -dy / len;  // Perpendicular direction
final perpY = dx / len;
final curvature = 0.15;   // 15% curve
final controlX = midX + perpX * len * curvature;
final controlY = midY + perpY * len * curvature;

// 3. Generate curve points using Bezier interpolation
for (int i = 0; i <= segments; i++) {
  final t = i / segments;
  final x = (1-t)*(1-t)*lng1 + 2*(1-t)*t*controlX + t*t*lng2;
  final y = (1-t)*(1-t)*lat1 + 2*(1-t)*t*controlY + t*t*lat2;
  points.add(Position(x, y));
}
```

### 6. Arrow Head Logic

#### A. Arrow Head Placement (`_addArrowHeadOnCurve`)
**Purpose**: Add directional indicators at the end of curved lines.

**Process**:
1. **Position Calculation**: Place arrow head at 80% along the curve
2. **Rotation Calculation**: Align arrow head with curve tangent
3. **Image Creation**: Generate arrow head image with proper color
4. **Annotation Placement**: Add as point annotation on the map

#### B. Arrow Head Styling
**Visual Properties**:
- Size: 30x30 pixels
- Shape: Triangular pointer
- Color: Matches or complements line color
- Rotation: Aligned with line direction

### 7. Connectivity Analysis and Debugging

#### A. Cluster Connectivity Analysis
**Purpose**: Identify clusters without arrows and analyze connection patterns.

**Features**:
- Track clusters with outgoing arrows only
- Track clusters with incoming arrows only
- Identify isolated clusters (no arrows)
- Count arrow frequency per cluster
- Debug memory details for isolated clusters

**Implementation**:
```dart
static void _analyzeClusterConnectivity(List<MemoryCluster> clusters, List<ChronologicalArrow> arrows) {
  // Track arrow directions
  final Set<String> clustersWithOutgoingArrows = {};
  final Set<String> clustersWithIncomingArrows = {};
  final Map<String, int> outgoingCount = {};
  final Map<String, int> incomingCount = {};

  // Analyze each arrow
  for (final arrow in arrows) {
    clustersWithOutgoingArrows.add(arrow.fromClusterId);
    clustersWithIncomingArrows.add(arrow.toClusterId);
    outgoingCount[arrow.fromClusterId] = (outgoingCount[arrow.fromClusterId] ?? 0) + 1;
    incomingCount[arrow.toClusterId] = (incomingCount[arrow.toClusterId] ?? 0) + 1;
  }

  // Identify connection patterns
  for (final cluster in clusters) {
    final hasOutgoing = clustersWithOutgoingArrows.contains(cluster.id);
    final hasIncoming = clustersWithIncomingArrows.contains(cluster.id);

    if (!hasOutgoing && !hasIncoming) {
      // Isolated cluster - debug why
      debugPrint('❌ Cluster ${cluster.id} has NO arrows');
    }
  }
}
```

#### B. Common Reasons for Missing Arrows

1. **Temporal Isolation**: Cluster memories are not chronologically adjacent to other clusters
2. **Single Memory Clusters**: Clusters with only one memory at the beginning or end of timeline
3. **Time Gaps**: Large time gaps between cluster memories and others
4. **Data Issues**: Invalid dates or coordinates in memory data

### 8. Performance Optimizations

#### A. Arrow Limiting
```dart
static const int maxArrowsToDisplay = 50; // Configurable limit
```

#### B. Cluster-Level Connections
- Only create arrows between different clusters
- Allow multiple arrows between same clusters for different time periods
- Use cluster center points as connection endpoints

#### C. Time Window Filtering
```dart
static List<ChronologicalArrow> generateArrowsForTimeWindow(
  List<MemoryCluster> clusters,
  DateTime startDate,
  DateTime endDate,
) {
  // Filter memories within time window
  // Generate arrows only for filtered data
}
```

### 8. Connection Types and Logic

#### A. Cluster-to-Cluster Connections
**When**: Different cluster IDs
**Visual**: Curved lines between cluster centers
**Color**: Based on time difference or cluster relationship

#### B. Single Location Connections
**When**: Individual memories not in clusters
**Visual**: Direct curved lines between memory locations
**Color**: Time-based or distance-based

#### C. Mixed Connections
**When**: Single location to cluster or vice versa
**Visual**: Line from memory point to cluster center
**Color**: Hybrid logic based on both time and cluster type

### 9. State Management

#### A. Current State Variables
```dart
final RxList<ChronologicalArrow> currentArrows = <ChronologicalArrow>[].obs;
final RxList<MemoryCluster> currentClusters = <MemoryCluster>[].obs;
```

#### B. Lifecycle Management
1. **Generation**: When clusters are created or updated
2. **Display**: When map view is refreshed
3. **Cleanup**: When transitioning between views
4. **Update**: When filters or zoom levels change

### 10. Integration Points

#### A. Memory Clustering Service
- Generates arrows based on cluster data
- Provides temporal relationship analysis
- Handles performance optimization

#### B. Map Controller
- Manages arrow display and styling
- Handles user interactions
- Coordinates with clustering service

#### C. UI Components
- Responds to arrow tap events
- Shows connection information
- Provides filtering controls

## Future Enhancements

### 1. Enhanced Color Logic
- Implement time-based color coding
- Add cluster relationship colors
- Support custom color themes

### 2. Interactive Features
- Arrow tap to show connection details
- Filter arrows by time period
- Toggle arrow visibility

### 3. Performance Improvements
- Implement arrow clustering for dense areas
- Add level-of-detail rendering
- Optimize curve generation algorithms

### 4. Visual Enhancements
- Animated arrow drawing
- Variable line thickness based on connection strength
- Gradient colors for long-distance connections

## Technical Implementation Details

### 1. Mapbox Integration

#### A. Polyline Annotation Manager
```dart
mapbox.PolylineAnnotationManager? _polylineAnnotationManager;
final _polylineManagers = <mapbox.PolylineAnnotationManager>[];

Future<mapbox.PolylineAnnotationManager> _getPolylineManager() async {
  if (_polylineAnnotationManager == null && mapController != null) {
    _polylineAnnotationManager = await mapController!.annotations.createPolylineAnnotationManager();
    _polylineManagers.add(_polylineAnnotationManager!);
  }
  return _polylineAnnotationManager!;
}
```

#### B. Line Creation Process
```dart
// Shadow line (drawn first, underneath)
await lineManager.create(
  mapbox.PolylineAnnotationOptions(
    geometry: mapbox.LineString(coordinates: points),
    lineColor: 0xFF000000,        // Black shadow
    lineWidth: width + 2,         // Slightly wider
    lineOpacity: 0.20,           // Semi-transparent
  ),
);

// Main line (drawn on top)
await lineManager.create(
  mapbox.PolylineAnnotationOptions(
    geometry: mapbox.LineString(coordinates: points),
    lineColor: decimalValue,      // Actual line color
    lineWidth: 5,                 // Standard width
    lineOpacity: 1,              // Fully opaque
  ),
);
```

### 2. Memory Data Structure Integration

#### A. Memory Location Class
```dart
class MemoryLocation {
  final int id;
  final double latitude;
  final double longitude;
  final DateTime memoryDate;
  final String description;
  final String? category;

  // Used for arrow generation
  bool get hasValidCoordinates => latitude != 0 && longitude != 0;
}
```

#### B. Memory Cluster Class
```dart
class MemoryCluster {
  final String id;
  final List<MemoryLocation> memories;
  final double centerLatitude;
  final double centerLongitude;
  final double radiusKm;

  // Arrow endpoints use cluster centers
  bool get isSingleMemory => memories.length == 1;
  MemoryLocation? get singleMemory => isSingleMemory ? memories.first : null;
}
```

### 3. Arrow Width Calculation

#### A. Time-Based Width Logic
```dart
double _getArrowWidth(int timeDiffMs) {
  // Convert milliseconds to days
  final days = timeDiffMs / (1000 * 60 * 60 * 24);

  if (days <= 1) {
    return 6.0;  // Thick for same-day connections
  } else if (days <= 7) {
    return 4.5;  // Medium for same-week connections
  } else if (days <= 30) {
    return 3.5;  // Thinner for same-month connections
  } else {
    return 2.5;  // Thinnest for older connections
  }
}
```

### 4. Cleanup and Memory Management

#### A. Line Cleanup Process
```dart
Future<void> _clearPolylineAnnotations() async {
  // Clear current single manager
  if (_polylineAnnotationManager != null) {
    try {
      await _polylineAnnotationManager!.deleteAll();
    } catch (_) {}
    _polylineAnnotationManager = null;
  }

  // Clear all managers in the list
  for (final m in _polylineManagers) {
    try {
      await m.deleteAll();
    } catch (_) {}
  }
  _polylineManagers.clear();
}
```

#### B. Complete Cleanup
```dart
Future<void> _clearAllMarkersAndClusters() async {
  // Point annotations (markers + arrow heads)
  if (currentAnnotationManager != null) {
    await currentAnnotationManager!.deleteAll();
    currentAnnotationManager = null;
  }
  annotations.clear();

  // Polyline annotations (chronological arrows)
  await _clearPolylineAnnotations();

  // In-memory state
  currentClusters.clear();
  currentArrows.clear();

  // Style images & style-based layers
  await _clearAllMarkerImages();
  await _clearAllLines();
}
```

### 5. Error Handling and Debugging

#### A. Debug Output
```dart
debugPrint('🔄 DISPLAY CLUSTERS - Displaying chronological arrows...');
debugPrint('🎨 Line color for arrow: ${lineColor.toString()} (decimal: $decimalValue)');
debugPrint('🔍 DRILL DOWN - Arrow ${i + 1}: ${arrow.fromLatitude}, ${arrow.fromLongitude} → ${arrow.toLatitude}, ${arrow.toLongitude}');
```

#### B. Error Recovery
```dart
try {
  await _displayChronologicalArrows();
} catch (e) {
  debugPrint('❌ Error displaying chronological arrows: $e');
  // Continue with other operations
}
```

### 6. Configuration Constants

```dart
class MemoryClusteringService {
  static const int maxArrowsToDisplay = 50;
  static const double minClusterDistance = 0.1; // km
  static const int maxClusterSize = 20;
  static const double curvatureAmount = 0.15; // 15% curve
  static const int curveSegments = 32;
}
```

### 7. Performance Monitoring

#### A. Arrow Count Tracking
```dart
debugPrint('Generated ${arrows.length} chronological arrows');
debugPrint('Displaying ${arrowsToDisplay.length} arrows (limited from ${currentArrows.length})');
```

#### B. Timing Analysis
```dart
final stopwatch = Stopwatch()..start();
await _displayChronologicalArrows();
stopwatch.stop();
debugPrint('Arrow display took ${stopwatch.elapsedMilliseconds}ms');
```

## Summary

The arrows and lines system in SpaceTime provides a sophisticated way to visualize temporal relationships between memory locations. The system:

1. **Generates** chronological connections based on memory timestamps
2. **Optimizes** performance through clustering and limiting
3. **Renders** smooth curved lines with directional indicators
4. **Styles** connections based on temporal and spatial relationships
5. **Manages** resources efficiently with proper cleanup
6. **Handles** errors gracefully with comprehensive debugging

The implementation balances visual appeal, performance, and functionality to create an intuitive representation of how memories connect across time and space.
