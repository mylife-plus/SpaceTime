# Memory Controller Logic Documentation

## Overview
The Memory Controller (`MapController`) is responsible for loading memories from the database, clustering them geographically, and displaying them on the map with chronological relationships. This document details the complete data flow and logic.

## Database Integration

### Data Source
- **Database Helper**: Uses `DatabaseHelper.instance` (from `lib/app/services/memory_db.dart`)
- **Primary Method**: `getAllMemoriesWithDetails()` - Retrieves all memories with their associated metadata
- **Data Format**: Returns `List<Map<String, dynamic>>` where each map represents a memory record

### Memory Data Structure
Each memory from the database contains:
```dart
{
  'id': int,                    // Unique memory identifier
  'title': String?,             // Memory title
  'description': String?,       // Memory description
  'location': String?,          // Coordinates as "latitude,longitude"
  'created_at': String?,        // ISO timestamp
  'memory_date': String?,       // When the memory occurred
  'place_category': String?,    // Category of the place
  'hashtags': String?,          // Comma-separated hashtags
  'images': String?,            // Base64 encoded images
  'voice_notes': String?,       // Voice note data
  // ... other fields
}
```

## Memory Loading Process

### 1. Initial Load (`loadMemoriesFromDatabase()`)
```dart
Future<void> loadMemoriesFromDatabase() async {
  isLoadingMemories.value = true;
  
  // Load from database
  final memories = await _databaseHelper.getAllMemoriesWithDetails();
  allMemories.assignAll(memories);
  
  // Initialize clustering
  await _initializeMemoryClustering();
  
  isLoadingMemories.value = false;
}
```

### 2. Data Validation (`_hasValidCoordinates()`)
Before clustering, each memory's location is validated:
- **Format Check**: Location must be "latitude,longitude" format
- **Parsing**: Coordinates must be valid numbers
- **Range Check**: Latitude [-90, 90], Longitude [-180, 180]
- **Zero Check**: Excludes 0,0 coordinates (likely invalid)

### 3. Memory Location Conversion
Valid memories are converted to `MemoryLocation` objects:
```dart
class MemoryLocation {
  final double latitude;
  final double longitude;
  final DateTime memoryDate;
  final String title;
  final Map<String, dynamic> metadata; // Original database record
}
```

## Clustering Algorithm

### 1. Adaptive Radius Selection
The clustering radius adapts based on memory count:
```dart
double _getAdaptiveClusterRadius(int memoryCount) {
  if (memoryCount > 1000) return 2000.0; // Continental scale
  if (memoryCount > 500) return 500.0;   // Country scale
  if (memoryCount > 200) return 50.0;    // City scale
  if (memoryCount > 100) return 10.0;    // Large area
  return 5.0;                            // Default 5km
}
```

### 2. Distance-Based Clustering
Uses the Haversine formula to calculate distances:
```dart
static double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
  // Haversine formula implementation
  // Returns distance in kilometers
}
```

### 3. Cluster Creation Process
1. **Initialize**: Create empty clusters list and processed flags
2. **Iterate**: For each unprocessed memory:
   - Start new cluster with current memory
   - Find all memories within radius
   - Add nearby memories to cluster
   - Mark all cluster memories as processed
3. **Center Calculation**: Calculate geographic center of cluster
4. **Result**: Return list of `MemoryCluster` objects

## Memory Cluster Structure

### MemoryCluster Class
```dart
class MemoryCluster {
  final String id;                    // Unique cluster identifier
  final List<MemoryLocation> memories; // Memories in this cluster
  final double centerLatitude;        // Geographic center
  final double centerLongitude;
  final double radiusKm;              // Clustering radius used
  
  // Computed properties
  int get memoryCount => memories.length;
  bool get isSingleMemory => memories.length == 1;
  DateTime get earliestDate => /* earliest memory date */;
  DateTime get latestDate => /* latest memory date */;
  MemoryLocation? get singleMemory => /* if single memory */;
}
```

## Chronological Arrow Generation

### 1. Arrow Logic
Arrows show temporal relationships between clusters:
```dart
List<ChronologicalArrow> generateChronologicalArrows(List<MemoryCluster> clusters) {
  // Create memory-cluster pairs
  // Sort by chronological order
  // Generate arrows between consecutive memories in different clusters
  // Avoid duplicate arrows between same cluster pairs
}
```

### 2. Arrow Properties
```dart
class ChronologicalArrow {
  final double fromLatitude, fromLongitude;
  final double toLatitude, toLongitude;
  final DateTime fromDate, toDate;
  final String fromClusterId, toClusterId;
  final double bearing; // Direction angle
}
```

## Drill-Down Behavior

### 1. Two-Level Clustering
- **Level 1**: Initial clustering (5km radius by default)
- **Level 2**: Sub-clustering (100m radius) when cluster is tapped

### 2. Drill-Down Process (`_drillDownToSubgroup()`)
```dart
Future<void> _drillDownToSubgroup(MemoryCluster selectedCluster) async {
  // Set subgroup level
  currentClusterLevel.value = ClusterLevel.subgroup;
  selectedCluster.value = selectedCluster;
  
  // Re-cluster memories with smaller radius
  final subclusters = MemoryClusteringService.clusterMemories(
    selectedCluster.memories,
    MemoryClusteringService.subgroupClusterRadiusM / 1000,
  );
  
  // Update display
  currentClusters.assignAll(subclusters);
  await _displayMemoryClusters(clearExisting: false); // Preserve other markers
}
```

### 3. Navigation Back
```dart
Future<void> resetToInitialClustering() async {
  currentClusterLevel.value = ClusterLevel.initial;
  selectedCluster.value = null;
  await _initializeMemoryClustering(); // Reload from database
}
```

## Map Display Logic

### 1. Marker Creation
Each cluster gets a visual marker:
- **Color Coding**: Based on memory count (blue=1, green≤5, orange≤15, red≤50, purple>50)
- **Size**: Single memories smaller than clusters
- **Count Display**: Number prominently shown in center
- **Visual Indicators**: Dots around cluster markers

### 2. Performance Optimizations
- **Marker Limit**: Max 50 arrows displayed simultaneously
- **Image Caching**: Marker images cached with specific dimensions
- **Batch Operations**: Multiple markers created in single operation
- **Fallback Images**: Simple markers if complex creation fails

### 3. Error Handling
- **Database Errors**: Graceful fallback to empty state
- **Invalid Coordinates**: Filtered out during validation
- **Image Creation Errors**: Fallback to simple markers
- **Clustering Errors**: Debug logging and error recovery

## State Management

### Observable Properties
```dart
final RxList<Map<String, dynamic>> allMemories;     // Raw database data
final RxList<MemoryCluster> currentClusters;        // Current cluster state
final RxList<ChronologicalArrow> currentArrows;     // Current arrows
final Rx<ClusterLevel> currentClusterLevel;         // Current zoom level
final Rxn<MemoryCluster> selectedCluster;           // Selected cluster for drill-down
final RxBool isLoadingMemories;                      // Loading state
```

### Reactive Updates
- **Memory Changes**: Automatically reload and re-cluster
- **Zoom Changes**: Maintain cluster state across zoom levels
- **Selection Changes**: Update UI to reflect current selection

## Debug and Monitoring

### Debug Methods
- `debugDatabaseContents()`: Analyze database memory data
- `getClusteringStats()`: Get current clustering statistics
- `MemoryClusteringService.debugMemoryLocations()`: Detailed location analysis

### Logging Levels
- **🔄 MEMORY CLUSTERING**: Core clustering operations
- **🔄 DISPLAY CLUSTERS**: Map display operations
- **🔍 DATABASE DEBUG**: Database analysis
- **❌ Errors**: Error conditions and recovery

## Data Flow Sequence

### Complete Memory Loading Flow
1. **App Initialization** → `onMapCreated()` called
2. **Map Ready** → `loadMemoriesFromDatabase()` triggered
3. **Database Query** → `getAllMemoriesWithDetails()` executed
4. **Data Validation** → Filter memories with valid coordinates
5. **Location Conversion** → Convert to `MemoryLocation` objects
6. **Adaptive Clustering** → Determine appropriate radius
7. **Cluster Generation** → Group memories by distance
8. **Arrow Generation** → Create chronological connections
9. **Map Display** → Render clusters and arrows
10. **User Interaction** → Handle taps and drill-downs

### Memory Update Flow
1. **New Memory Added** → Database updated
2. **Refresh Trigger** → `refreshMemoryClustering()` called
3. **Reload Data** → Re-fetch from database
4. **Re-cluster** → Regenerate clusters with new data
5. **Update Display** → Refresh map markers

## Edge Cases and Handling

### Empty Database
- **Condition**: No memories in database
- **Behavior**: Show fallback test markers at user location
- **Debug**: Clear logging about empty state

### Invalid Location Data
- **Missing Coordinates**: Memory filtered out during validation
- **Invalid Format**: Coordinates not parseable as numbers
- **Out of Range**: Coordinates outside valid lat/lng bounds
- **Zero Coordinates**: Treated as invalid, filtered out

### Large Datasets
- **1000+ Memories**: Uses continental clustering (2000km radius)
- **Arrow Limiting**: Max 50 arrows displayed for performance
- **Batch Processing**: Efficient marker creation in batches
- **Memory Management**: Cached images with optimized dimensions

### Network/Database Errors
- **Database Unavailable**: Graceful error handling with user feedback
- **Partial Data**: Process available memories, log missing data
- **Corruption**: Skip invalid records, continue with valid ones

### Map Interaction Edge Cases
- **Rapid Tapping**: Debounced to prevent multiple drill-downs
- **Empty Clusters**: Should not occur due to clustering logic
- **Single Memory Clusters**: Direct navigation to memory details
- **Overlapping Clusters**: Handled by distance-based separation

## Performance Considerations

### Database Optimization
- **Single Query**: Load all memories in one database call
- **Indexed Fields**: Ensure location and date fields are indexed
- **Batch Processing**: Process memories in chunks for large datasets

### Memory Management
- **Image Caching**: Marker images cached with specific dimensions
- **Object Reuse**: Reuse annotation managers when possible
- **Garbage Collection**: Clear unused markers and images

### UI Responsiveness
- **Async Operations**: All database and clustering operations are async
- **Progress Indicators**: Loading states shown during operations
- **Background Processing**: Heavy computations off main thread

## Integration Points

### Database Schema Requirements
```sql
-- Required fields for clustering
location TEXT,           -- "latitude,longitude" format
created_at DATETIME,     -- Memory creation timestamp
memory_date DATETIME,    -- When memory occurred
title TEXT,             -- Memory title
description TEXT        -- Memory description
```

### External Dependencies
- **Mapbox SDK**: For map rendering and annotations
- **Geolocator**: For user location (fallback markers)
- **GetX**: For reactive state management
- **Database Helper**: For memory data access

### Controller Integration
- **AddMemoriesController**: Triggers refresh when memories added
- **MemoryController**: Handles individual memory operations
- **LocationController**: Provides user location for fallbacks

This comprehensive system ensures robust handling of memory data from database to map visualization, with proper error handling and performance optimization throughout the pipeline.
