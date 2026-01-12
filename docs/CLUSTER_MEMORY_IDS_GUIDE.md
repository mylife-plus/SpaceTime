# 📋 Storing Memory IDs in Mapbox Clusters

This guide explains how to store and retrieve memory IDs from Mapbox clusters using two different approaches.

---

## 🎯 Overview

When working with Mapbox clustering, you often need to access the individual memory IDs within a cluster. There are **two approaches** to achieve this:

1. **Pre-aggregated Memory IDs** (using `clusterProperties`)
2. **Dynamic Cluster Leaves** (using `getGeoJsonClusterLeaves`)

---

## 📦 Approach 1: Pre-aggregated Memory IDs (FASTER)

### How It Works
Memory IDs are aggregated and stored directly in the cluster properties during GeoJSON source creation using Mapbox's `clusterProperties` feature.

### Implementation

#### Step 1: Configure `clusterProperties` in GeoJsonSource

```dart
await mapboxMap!.style.addSource(
  mapbox.GeoJsonSource(
    id: MEMORY_SOURCE_ID,
    data: geoJsonString,
    cluster: true,
    clusterRadius: 50,
    clusterMaxZoom: 13.5,
    clusterMinPoints: 2,
    clusterProperties: {
      // Each property MUST be an array with EXACTLY 2 elements:
      // [mapExpression, reduceExpression]

      // Aggregate memory IDs into a comma-separated string
      'memory_ids': [
        ['get', 'id'], // Map: extract 'id' from each feature
        ['concat', ['accumulated'], ',', ['get', 'id']], // Reduce: join with comma
      ],

      // Store the count of memories
      'memory_count': [
        1, // Map: each feature contributes 1
        ['+', ['accumulated'], 1], // Reduce: sum all values
      ],
    },
  ),
);
```

#### Step 2: Extract Memory IDs from Cluster Properties

```dart
Future<void> _handleClusterMarkerTap(
  mapbox.TypedFeaturesetFeature feature,
  String layerName,
  mapbox.MapContentGestureContext context,
) async {
  final properties = feature.properties;
  
  // Extract aggregated memory IDs
  final memoryIdsString = properties['memory_ids']?.toString() ?? '';
  final memoryCount = properties['memory_count'];
  
  // Parse the comma-separated IDs
  if (memoryIdsString.isNotEmpty) {
    final memoryIds = memoryIdsString
      .split(',')
      .where((id) => id.trim().isNotEmpty)
      .toList();
    
    debugPrint('Memory IDs: ${memoryIds.join(', ')}');
    
    // Use these IDs to fetch memories from database
    final memories = await _fetchMemoriesByIds(memoryIds);
  }
}
```

### ✅ Advantages
- **Faster**: No additional API calls to fetch cluster leaves
- **Efficient**: IDs are pre-computed during clustering
- **Direct Database Access**: Can query database directly with IDs
- **Less Memory**: Only stores IDs, not full feature data

### ❌ Disadvantages
- **Limited Data**: Only stores IDs, not full properties
- **String Parsing**: Requires parsing comma-separated string
- **Size Limit**: Very large clusters might hit property size limits

---

## 🔍 Approach 2: Dynamic Cluster Leaves (MORE FLEXIBLE)

### How It Works
Fetch individual GeoJSON features from the cluster dynamically using Mapbox's `getGeoJsonClusterLeaves` API.

### Implementation

```dart
Future<void> _showClusterMemoriesBottomSheet(
  dynamic clusterId,
  int pointCount,
  double lat,
  double lng,
) async {
  // Create cluster feature map
  final clusterFeature = {
    'cluster_id': clusterId,
  };
  
  // Fetch all leaves (individual memories) in this cluster
  final result = await mapboxMap!.getGeoJsonClusterLeaves(
    MEMORY_SOURCE_ID,
    clusterFeature,
    0, // offset
    1000, // limit
  );
  
  final leavesData = result.value;
  final leavesJson = jsonDecode(leavesData.toString());
  
  // Extract features
  final features = leavesJson['features'] as List;
  
  for (final feature in features) {
    final properties = feature['properties'];
    final memoryId = properties['id'];
    final memoryTitle = properties['memory_data']?['title'] ?? 'Untitled';
    final memoryDate = properties['memory_date'];
    // ... access all properties
  }
}
```

### ✅ Advantages
- **Complete Data**: Returns full GeoJSON features with all properties
- **No Parsing**: Data is already structured
- **Flexible**: Can access any property from the original features
- **No Size Limits**: Works with clusters of any size

### ❌ Disadvantages
- **Slower**: Requires additional API call
- **More Memory**: Returns full feature data
- **API Dependency**: Relies on Mapbox API availability

---

## 🎨 Which Approach to Use?

| Use Case | Recommended Approach |
|----------|---------------------|
| Need only memory IDs for database query | **Approach 1** (Pre-aggregated) |
| Need full memory properties (title, date, etc.) | **Approach 2** (Cluster Leaves) |
| Performance-critical application | **Approach 1** (Pre-aggregated) |
| Small to medium clusters (< 100 items) | **Either** |
| Large clusters (> 100 items) | **Approach 2** (Cluster Leaves) |
| Offline-first application | **Approach 1** (Pre-aggregated) |

---

## 🔧 Current Implementation

The current implementation in `map_controller_new.dart` supports **BOTH approaches**:

1. Memory IDs are **pre-aggregated** in `clusterProperties` (Line 4122-4134)
2. The `_showClusterMemoriesBottomSheet` method accepts optional `memoryIdsString` parameter
3. Falls back to `getGeoJsonClusterLeaves` if needed

This hybrid approach gives you the best of both worlds! 🎉

