# 🔧 Cluster Properties Fix - Memory IDs Aggregation

## ❌ The Problem

When implementing `clusterProperties` to aggregate memory IDs, we encountered this error:

```
PlatformException(Throwable, java.lang.Throwable: GeoJSON source clusterProperties 
member must be an array with length of 2, Cause: null, Stacktrace: 
java.lang.Throwable: GeoJSON source clusterProperties member must be an array with length of 2
```

## 🔍 Root Cause

The Mapbox GeoJSON source requires that **each property in `clusterProperties` must be an array with EXACTLY 2 elements**:

```
[mapExpression, reduceExpression]
```

- **mapExpression**: Applied to each individual feature in the cluster
- **reduceExpression**: Combines the accumulated value with the current value

## ❌ Incorrect Implementation

```dart
clusterProperties: {
  'memory_ids': [
    'concat',  // ❌ WRONG: 3 elements in array
    ['get', 'id'],
    ['concat', ['accumulated'], ',', ['get', 'id']],
  ],
}
```

This has **3 elements** in the array, which causes the error.

## ✅ Correct Implementation

```dart
clusterProperties: {
  // Each property MUST have EXACTLY 2 elements
  'memory_ids': [
    ['get', 'id'], // Element 1: mapExpression
    ['concat', ['accumulated'], ',', ['get', 'id']], // Element 2: reduceExpression
  ],
  
  'memory_count': [
    1, // Element 1: mapExpression (simple value)
    ['+', ['accumulated'], 1], // Element 2: reduceExpression
  ],
}
```

## 📋 How It Works

### Memory IDs Aggregation

```dart
'memory_ids': [
  ['get', 'id'],                                    // Step 1: Extract ID from each feature
  ['concat', ['accumulated'], ',', ['get', 'id']],  // Step 2: Concatenate with comma
]
```

**Process:**
1. **First feature**: `accumulated = ""`, result = `"mem1"`
2. **Second feature**: `accumulated = "mem1"`, result = `"mem1,mem2"`
3. **Third feature**: `accumulated = "mem1,mem2"`, result = `"mem1,mem2,mem3"`
4. **Final result**: `"mem1,mem2,mem3,mem4,mem5"`

### Memory Count Aggregation

```dart
'memory_count': [
  1,                          // Step 1: Each feature contributes 1
  ['+', ['accumulated'], 1],  // Step 2: Sum all values
]
```

**Process:**
1. **First feature**: `accumulated = 0`, result = `1`
2. **Second feature**: `accumulated = 1`, result = `2`
3. **Third feature**: `accumulated = 2`, result = `3`
4. **Final result**: `5` (total count)

## 🎯 Accessing Aggregated Data

When a cluster is tapped, you can access the aggregated properties:

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
    // Use these IDs to fetch from database or display
  }
}
```

## 📊 Debug Output

When you tap a cluster, you'll see:

```
[MapControllerNew] 📋 ALL Feature properties:
[MapControllerNew]   - cluster_id: 123 (int)
[MapControllerNew]   - point_count: 5 (int)
[MapControllerNew]   - memory_ids: mem1,mem2,mem3,mem4,mem5 (String)
[MapControllerNew]   - memory_count: 5 (int)
[MapControllerNew] 🎯 Parsed Memory IDs (5): mem1, mem2, mem3, mem4, mem5
```

## ✅ Summary

**Key Takeaway**: Each `clusterProperties` entry must be an array with **EXACTLY 2 elements**:
1. **mapExpression**: What to extract from each feature
2. **reduceExpression**: How to combine values

This is a strict requirement of the Mapbox GeoJSON source specification.

## 🔗 References

- [Mapbox GL JS - clusterProperties](https://docs.mapbox.com/mapbox-gl-js/style-spec/sources/#geojson-clusterProperties)
- Implementation: `lib/app/modules/map/controllers/map_controller_new.dart` (Lines 4180-4197)

