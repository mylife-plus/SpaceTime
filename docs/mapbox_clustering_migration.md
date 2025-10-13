# Mapbox Native Clustering Migration Guide

## Overview
This document outlines the complete migration from custom memory clustering to Mapbox's native clustering system while **preserving chronological arrows and lines** between memory locations.

## Benefits of Migration
- **Performance**: GPU-accelerated clustering
- **Simplicity**: Remove ~2000 lines of custom clustering code
- **Scalability**: Handles thousands of points efficiently
- **Zoom-Adaptive**: Automatic clustering based on zoom level
- **Smooth UX**: Native animations and interactions
- **Preserved Features**: Keep chronological arrows, lines, and all click behaviors

## Current System Analysis

### Key Features to Preserve
1. **Chronological Arrows**: Lines connecting memories in chronological order
2. **Curved Arrow Lines**: Bezier curves between locations with arrow heads
3. **Year-Based Colors**: Different colors for different years
4. **Click Behaviors**: Cluster expansion, memory details, bottom panels
5. **Performance Optimization**: Limit arrows for large datasets (max 50 arrows)

### Files to Modify/Remove
1. `lib/services/memory_clustering_service.dart` - **PARTIAL REFACTOR**
   - Keep `ChronologicalArrow` class and arrow generation logic
   - Remove custom clustering algorithms
2. `lib/app/modules/map/controllers/map_controller.dart` - **MAJOR REFACTOR**
   - Remove custom clustering methods (~1500 lines)
   - Keep arrow/line display logic (~500 lines)
   - Keep click handling and memory access
3. Custom marker generation methods - **REPLACE**

### Current System Flow
```
Database → MemoryLocation Objects → Custom Clustering → Custom Markers + Arrows → Map Display
```

### New Hybrid Flow
```
Database → GeoJSON → Mapbox Native Clustering → Styled Layers
         ↓
    Arrow Generation → Custom Lines/Arrows → Overlay on Map
```

## Implementation Strategy

### Hybrid Approach: Native Clustering + Custom Arrows + Offline Support
Instead of a complete replacement, we'll use a **hybrid approach** that preserves all existing functionality:

1. **Mapbox Native Clustering**: For memory point clustering and display
2. **Custom Arrow System**: Preserve existing chronological arrow logic
3. **Offline Map Support**: Maintain all offline tile downloading and caching
4. **Layered Rendering**: Arrows rendered on top of clustered points

### Architecture Overview
```
┌─────────────────────────────────────────────────────────────┐
│                    Map Display Layers                       │
├─────────────────────────────────────────────────────────────┤
│ Layer 4: Arrow Heads (Point Annotations)                   │
│ Layer 3: Chronological Lines (Polyline Annotations)        │
│ Layer 2: Memory Clusters (Mapbox Native Clustering)        │
│ Layer 1: Offline Tiles (Downloaded Map Data)               │
│ Layer 0: Base Map Style                                     │
└─────────────────────────────────────────────────────────────┘
```

### Offline Functionality Preservation
The migration will **preserve 100%** of the existing offline functionality:

- ✅ **Tile Downloading**: All existing tile download methods remain unchanged
- ✅ **Offline Detection**: `isMapInOfflineMode()` and related methods preserved
- ✅ **Background Downloads**: `BackgroundTileDownloadService` integration maintained
- ✅ **Regional Downloads**: Country/region-specific tile downloading preserved
- ✅ **Storage Management**: Tile quota and storage management unchanged
- ✅ **Progress Tracking**: Download progress streams and UI indicators preserved

## Implementation Steps

### Step 1: Refactor Memory Clustering Service

Modify `lib/services/memory_clustering_service.dart`:

```dart
// KEEP: Arrow-related classes and methods
class ChronologicalArrow { /* existing implementation */ }
class MemoryLocation { /* existing implementation */ }

class MemoryArrowService {  // Renamed from MemoryClusteringService
  // KEEP: Arrow generation methods
  static List<ChronologicalArrow> generateChronologicalArrows(List<MemoryLocation> memories) {
    // Generate arrows directly from memory locations, not clusters
    if (memories.length < 2) return [];

    // Sort memories chronologically
    final sortedMemories = List<MemoryLocation>.from(memories);
    sortedMemories.sort((a, b) => a.memoryDate.compareTo(b.memoryDate));

    final arrows = <ChronologicalArrow>[];

    for (int i = 0; i < sortedMemories.length - 1; i++) {
      final current = sortedMemories[i];
      final next = sortedMemories[i + 1];

      // Only create arrow if memories are far enough apart
      final distance = calculateDistance(
        current.latitude, current.longitude,
        next.latitude, next.longitude,
      );

      if (distance > 0.1) { // 100m minimum distance
        arrows.add(ChronologicalArrow(
          fromLatitude: current.latitude,
          fromLongitude: current.longitude,
          toLatitude: next.latitude,
          toLongitude: next.longitude,
          fromDate: current.memoryDate,
          toDate: next.memoryDate,
          fromClusterId: current.id.toString(),
          toClusterId: next.id.toString(),
        ));
      }
    }

    // Performance limit: max 50 arrows
    return arrows.length > 50 ? arrows.take(50).toList() : arrows;
  }

  // KEEP: Distance calculation and other utility methods
  static double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    // existing implementation
  }
}
```

### Step 2: Create GeoJSON Data Service

Create `lib/services/memory_geojson_service.dart` (already created):

```dart
class MemoryGeoJsonService {
  static Map<String, dynamic> createGeoJsonFromMemories(List<Map<String, dynamic>> memories) {
    // Convert memories to GeoJSON for Mapbox clustering
    // Include year, category, and metadata for styling and interaction
  }
}
```

### Step 3: Configure Mapbox Native Clustering with Offline Support

Add to `MapController`:

```dart
class MapController extends GetxController {
  // REMOVE: Custom clustering variables
  // final RxList<MemoryCluster> currentClusters = <MemoryCluster>[].obs;
  // final Rx<ClusterLevel> currentClusterLevel = ClusterLevel.initial.obs;
  // final Rxn<MemoryCluster> selectedCluster = Rxn<MemoryCluster>();

  // KEEP: Essential variables
  final RxList<Map<String, dynamic>> allMemories = <Map<String, dynamic>>[].obs;
  final RxList<ChronologicalArrow> currentArrows = <ChronologicalArrow>[].obs;
  final RxBool isLoadingMemories = false.obs;

  // KEEP: All offline-related variables (UNCHANGED)
  var isOfflineMode = false.obs;
  TileStore? tileStore;
  OfflineManager? offlineManager;
  final tileRegionId = "my-tile-region";
  final StreamController<double> stylePackProgress = StreamController.broadcast();
  final StreamController<double> tileRegionLoadProgress = StreamController.broadcast();

  // ADD: Mapbox clustering constants
  static const String MEMORY_SOURCE_ID = 'memory-source';
  static const String CLUSTER_LAYER_ID = 'clusters';
  static const String CLUSTER_COUNT_LAYER_ID = 'cluster-count';
  static const String UNCLUSTERED_LAYER_ID = 'unclustered-point';

  Future<void> setupMapboxClustering() async {
    if (mapController == null) return;

    try {
      debugPrint('[MapController][setupMapboxClustering] Setting up native clustering for ${allMemories.length} memories');

      // IMPORTANT: Ensure offline functionality is initialized first
      await _ensureOfflineInitialized();

      // Convert memories to GeoJSON
      final geoJson = MemoryGeoJsonService.createGeoJsonFromMemories(allMemories);

      // Add source with clustering enabled
      await mapController!.style.addSource(mapbox.GeoJsonSource(
        id: MEMORY_SOURCE_ID,
        data: geoJson,
        cluster: true,
        clusterMaxZoom: 14,    // Max zoom to cluster points on
        clusterRadius: 50,     // Radius of each cluster when clustering points (pixels)
        clusterMinPoints: 2,   // Minimum points to form a cluster
      ));

      // Layer 1: Cluster circles (background)
      await mapController!.style.addLayer(mapbox.CircleLayer(
        id: CLUSTER_LAYER_ID,
        sourceId: MEMORY_SOURCE_ID,
        filter: ['has', 'point_count'],
        paint: mapbox.CircleLayerPaint(
          circleColor: [
            'step',
            ['get', 'point_count'],
            '#4CAF50',  // Green for small clusters (2-10)
            10,
            '#FF9800',  // Orange for medium clusters (10-50)
            50,
            '#F44336',  // Red for large clusters (50+)
          ],
          circleRadius: [
            'step',
            ['get', 'point_count'],
            15,   // Small clusters
            10,
            25,   // Medium clusters
            50,
            35,   // Large clusters
          ],
          circleStrokeWidth: 3,
          circleStrokeColor: '#ffffff',
        ),
      ));

      // Layer 2: Cluster count text
      await mapController!.style.addLayer(mapbox.SymbolLayer(
        id: CLUSTER_COUNT_LAYER_ID,
        sourceId: MEMORY_SOURCE_ID,
        filter: ['has', 'point_count'],
        layout: mapbox.SymbolLayerLayout(
          textField: ['get', 'point_count_abbreviated'],
          textFont: ['DIN Offc Pro Medium', 'Arial Unicode MS Bold'],
          textSize: 12,
          textAllowOverlap: true,
        ),
        paint: mapbox.SymbolLayerPaint(
          textColor: '#ffffff',
          textHaloColor: '#000000',
          textHaloWidth: 1,
        ),
      ));

      // Layer 3: Individual memory points (unclustered)
      await mapController!.style.addLayer(mapbox.CircleLayer(
        id: UNCLUSTERED_LAYER_ID,
        sourceId: MEMORY_SOURCE_ID,
        filter: ['!', ['has', 'point_count']],
        paint: mapbox.CircleLayerPaint(
          circleColor: _getYearColorExpression(),
          circleRadius: 8,
          circleStrokeWidth: 2,
          circleStrokeColor: '#ffffff',
        ),
      ));

      // Set up click handlers
      await _setupNativeClusterClickHandlers();

      // Generate and display chronological arrows
      await _generateAndDisplayArrows();

      debugPrint('[MapController][setupMapboxClustering] Native clustering setup complete');

    } catch (e) {
      debugPrint('Error setting up Mapbox clustering: $e');
    }
  }

  List<dynamic> _getYearColorExpression() {
    final expression = ['case'];

    // Add year-based color cases using existing color system
    for (int i = 0; i < 20; i++) {
      final year = DateTime.now().year - i;
      final color = getColorForMemoryYear(year.toString()); // Use existing method
      final hexColor = '#${color.value.toRadixString(16).substring(2)}';

      expression.addAll([
        ['==', ['get', 'year'], year],
        hexColor,
      ]);
    }

    expression.add('#11b4da'); // Default color
    return expression;
  }

  // KEEP: All existing offline methods (UNCHANGED)
  Future<void> initOfflineMap() async {
    // Existing implementation - no changes needed
  }

  Future<void> setupOfflineMap() async {
    // Existing implementation - no changes needed
  }

  Future<void> downloadTilesForRegion(String regionName) async {
    // Existing implementation - no changes needed
  }

  Future<bool> isOfflineDataAvailable() async {
    // Existing implementation - no changes needed
  }

  Future<bool> isMapInOfflineMode() async {
    // Existing implementation - no changes needed
  }

  // ADD: Ensure offline is initialized before clustering
  Future<void> _ensureOfflineInitialized() async {
    if (tileStore == null || offlineManager == null) {
      debugPrint('[MapController][_ensureOfflineInitialized] Initializing offline components for clustering');
      await initOfflineMap();
    }

    // Check if we're in offline mode and update status
    await updateOfflineStatus();

    debugPrint('[MapController][_ensureOfflineInitialized] Offline status: ${isOfflineMode.value}');
  }

  // MODIFIED: Update main initialization to include clustering
  Future<void> startMapInitializationSequence() async {
    debugPrint('[MapController][startMapInitializationSequence] Starting map initialization sequence');

    try {
      // Step 1: Check location permissions
      debugPrint('[MapController][startMapInitializationSequence] Step 1: Checking location permissions');
      await _checkLocationPermission();

      // Step 2: Initialize offline functionality
      debugPrint('[MapController][startMapInitializationSequence] Step 2: Initializing offline functionality');
      await _ensureOfflineInitialized();

      // Step 3: Set user location
      debugPrint('[MapController][startMapInitializationSequence] Step 3: Setting user location');
      await _setUserLocation();

      // Step 4: Load data from database
      debugPrint('[MapController][startMapInitializationSequence] Step 4: Loading data from database');
      await loadMemoriesFromDatabase();

      // Step 5: Setup Mapbox native clustering (REPLACES custom clustering)
      debugPrint('[MapController][startMapInitializationSequence] Step 5: Setting up native clustering');
      await setupMapboxClustering();

      // Step 6: Add click to zoom functionality
      debugPrint('[MapController][startMapInitializationSequence] Step 6: Setting up click to zoom');
      _setupClickToZoom();

      debugPrint('[MapController][startMapInitializationSequence] Map initialization sequence completed successfully');

    } catch (e) {
      debugPrint('[MapController][startMapInitializationSequence] Error in initialization sequence: $e');
    }
  }
}
```

### Step 4: Preserve Chronological Arrows

Add arrow generation and display methods:

```dart
// Generate arrows from memory data (not clusters)
Future<void> _generateAndDisplayArrows() async {
  try {
    debugPrint('[MapController][_generateAndDisplayArrows] Generating arrows from ${allMemories.length} memories');

    // Convert memories to MemoryLocation objects
    final memoryLocations = allMemories
        .where((memory) => _hasValidCoordinates(memory))
        .map((memory) => MemoryLocation.fromMap(memory))
        .toList();

    // Generate chronological arrows using existing logic
    final arrows = MemoryArrowService.generateChronologicalArrows(memoryLocations);
    currentArrows.assignAll(arrows);

    debugPrint('[MapController][_generateAndDisplayArrows] Generated ${arrows.length} arrows');

    // Display arrows on map (existing method)
    await _displayChronologicalArrows();

  } catch (e) {
    debugPrint('Error generating arrows: $e');
  }
}

// KEEP: Existing arrow display methods
Future<void> _displayChronologicalArrows() async {
  if (mapController == null || currentArrows.isEmpty) return;

  try {
    final arrowsToDisplay = currentArrows.length > 50
        ? currentArrows.take(50).toList()
        : currentArrows;

    final lineManager = await _getPolylineManager();
    await lineManager.deleteAll();

    for (final arrow in arrowsToDisplay) {
      // Create curved line points (existing method)
      final points = _createCurvedArrowLine(
        arrow.fromLatitude, arrow.fromLongitude,
        arrow.toLatitude, arrow.toLongitude,
      );

      final timeDiffMs = arrow.toDate.difference(arrow.fromDate).inMilliseconds;
      final width = _getArrowWidth(timeDiffMs);
      final currentColor = getColorForYear(arrow.toDate.year);

      // Shadow line
      await lineManager.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(coordinates: points),
          lineColor: 0xFF000000,
          lineWidth: width + 2,
          lineOpacity: 0.20,
        ),
      );

      // Main line
      await lineManager.create(
        mapbox.PolylineAnnotationOptions(
          geometry: mapbox.LineString(coordinates: points),
          lineColor: currentColor.value,
          lineWidth: 5,
          lineOpacity: 1,
        ),
      );

      // Arrow head (existing method)
      await _addArrowHeadOnCurve(points, currentColor);
    }
  } catch (e) {
    debugPrint('Error displaying chronological arrows: $e');
  }
}
```

### Step 5: Native Cluster Click Handling

Replace custom click handling with native cluster support:

```dart
Future<void> _setupNativeClusterClickHandlers() async {
  // Handle cluster clicks (zoom to expand cluster)
  mapController!.addOnMapClickListener((point) async {
    // Check for cluster clicks first
    final clusterFeatures = await mapController!.queryRenderedFeatures(
      point,
      mapbox.RenderedQueryOptions(layerIds: [CLUSTER_LAYER_ID]),
    );

    if (clusterFeatures.isNotEmpty) {
      final clusterId = clusterFeatures.first.properties?['cluster_id'];
      if (clusterId != null) {
        // Get cluster expansion zoom level
        final expansionZoom = await mapController!.queryFeatureExtensions(
          MEMORY_SOURCE_ID,
          {'cluster_id': clusterId},
          'supercluster',
          'expansion-zoom',
        );

        // Zoom to expand cluster
        await mapController!.easeTo(
          mapbox.CameraOptions(
            center: point,
            zoom: expansionZoom?.toDouble() ?? (currentZoom.value + 2),
          ),
          mapbox.MapAnimationOptions(duration: 500),
        );

        debugPrint('[MapController] Expanded cluster at zoom ${expansionZoom}');
        return; // Don't check for individual points
      }
    }

    // Check for individual memory clicks
    final memoryFeatures = await mapController!.queryRenderedFeatures(
      point,
      mapbox.RenderedQueryOptions(layerIds: [UNCLUSTERED_LAYER_ID]),
    );

    if (memoryFeatures.isNotEmpty) {
      final properties = memoryFeatures.first.properties;
      final memoryData = properties?['metadata'];

      if (memoryData != null) {
        // Show memory details using existing bottom panel
        final memoryMap = Map<String, dynamic>.from(memoryData);
        _showMemoryBottomPanel(memoryMap);

        debugPrint('[MapController] Clicked individual memory: ${properties?['title']}');
      }
    }
  });
}

void _showMemoryBottomPanel(Map<String, dynamic> memory) {
  // Use existing bottom panel logic
  final context = Get.context;
  if (context != null) {
    // Create a temporary cluster with single memory for existing UI
    final memoryLocation = MemoryLocation.fromMap(memory);
    final singleMemoryCluster = MemoryCluster(
      id: 'temp_${memory['id']}',
      memories: [memoryLocation],
      centerLatitude: memoryLocation.latitude,
      centerLongitude: memoryLocation.longitude,
      radiusKm: 0.0,
    );

    showLocationBottomPanel(context, singleMemoryCluster);
  }
}
```

## Migration Checklist

### Phase 1: Preparation & Service Creation
- [ ] Create `MemoryGeoJsonService` ✅ (Already created)
- [ ] Create `MemoryArrowService` ✅ (Already created)
- [ ] Test GeoJSON generation with existing data
- [ ] Backup current clustering implementation
- [ ] Verify offline functionality is working before migration
- [ ] Test offline tile downloads and storage
- [ ] Refactor `MemoryClusteringService` → `MemoryArrowService`
  - [ ] Keep `ChronologicalArrow` class ✅
  - [ ] Keep arrow generation methods ✅
  - [ ] Remove custom clustering algorithms
  - [ ] Update arrow generation to work with individual memories ✅

### Phase 2: Mapbox Native Clustering Implementation
- [ ] Add Mapbox clustering constants to `MapController`
- [ ] Implement `setupMapboxClustering()` method with offline integration
- [ ] Add `_ensureOfflineInitialized()` method
- [ ] Add GeoJSON source with clustering enabled
- [ ] Create cluster layers (circles, text, unclustered points)
- [ ] Implement year-based color expressions
- [ ] Test basic clustering functionality
- [ ] Verify clustering works in offline mode
- [ ] Test clustering with downloaded tiles

### Phase 3: Preserve Arrow System
- [ ] Implement `_generateAndDisplayArrows()` method
- [ ] Keep existing `_displayChronologicalArrows()` method
- [ ] Keep existing `_createCurvedArrowLine()` method
- [ ] Keep existing `_addArrowHeadOnCurve()` method
- [ ] Keep existing `_getPolylineManager()` method
- [ ] Test arrow generation and display

### Phase 4: Click Handling & Interaction
- [ ] Implement `_setupNativeClusterClickHandlers()` method
- [ ] Handle cluster expansion on click
- [ ] Handle individual memory clicks
- [ ] Preserve existing bottom panel functionality
- [ ] Test memory detail viewing
- [ ] Test memory editing/deletion flows

### Phase 5: Integration & Testing
- [ ] Update `loadMemoriesFromDatabase()` to call new clustering
- [ ] Replace `_initializeMemoryClustering()` calls with `setupMapboxClustering()`
- [ ] Update `startMapInitializationSequence()` method
- [ ] Test with small datasets (< 100 memories)
- [ ] Test with large datasets (> 1000 memories)
- [ ] Test zoom-based clustering behavior
- [ ] Test chronological arrows display
- [ ] **Offline Mode Testing**:
  - [ ] Test clustering in offline mode
  - [ ] Test arrow display with offline tiles
  - [ ] Test memory interactions when offline
  - [ ] Verify tile downloads still work
  - [ ] Test background tile service integration
- [ ] Performance testing and optimization

### Phase 6: Cleanup & Optimization
- [ ] Remove custom clustering methods from `MapController`:
  - [ ] Remove `_initializeMemoryClustering()`
  - [ ] Remove `_generateOptimizedArrows()` (replaced by direct arrow generation)
  - [ ] Remove `_displayMemoryClusters()`
  - [ ] Remove `_createClusterMarkerImage()`
  - [ ] Remove cluster-related variables
- [ ] Clean up imports and dependencies
- [ ] Update method calls throughout the app
- [ ] Performance optimization and testing

## Expected Outcomes

### Performance Improvements
- **Clustering Speed**: From ~500ms to <50ms for 1000+ memories
- **Memory Usage**: Reduced by ~40% (fewer custom marker images, but keep arrows)
- **Smooth Interactions**: Native zoom/pan performance with GPU acceleration
- **Scalability**: Handle 10,000+ memories without performance degradation

### Code Reduction & Simplification
- **Lines Removed**: ~1500 lines of custom clustering code
- **Lines Preserved**: ~500 lines of arrow/line display logic
- **Net Reduction**: ~1000 lines total
- **Complexity**: Simplified clustering, preserved chronological features
- **Maintainability**: Standard Mapbox patterns + custom arrow overlay

### User Experience Improvements
- **Responsive Clustering**: Adapts to zoom level automatically
- **Smooth Animations**: Native Mapbox transitions for clustering
- **Preserved Features**: All existing chronological arrows and lines
- **Better Performance**: No UI blocking during clustering operations
- **Enhanced Interaction**: Native cluster expansion with smooth zoom

### Feature Preservation
- ✅ **Chronological Arrows**: Curved lines between memories in time order
- ✅ **Year-Based Colors**: Different colors for different years
- ✅ **Click Behaviors**: Memory details, bottom panels, editing
- ✅ **Performance Limits**: Max 50 arrows for large datasets
- ✅ **Arrow Styling**: Shadows, gradients, arrow heads

## Risk Mitigation

### Potential Issues & Solutions
1. **Click Detection Conflicts**:
   - **Risk**: Overlapping cluster and arrow click areas
   - **Solution**: Layer-based click priority (clusters first, then arrows)

2. **Arrow Performance**:
   - **Risk**: Many arrows may impact performance
   - **Solution**: Keep existing 50-arrow limit and optimization

3. **Data Synchronization**:
   - **Risk**: GeoJSON source and arrow data may get out of sync
   - **Solution**: Single source of truth with coordinated updates

4. **Styling Complexity**:
   - **Risk**: Year-based color expressions may be complex
   - **Solution**: Pre-generate color mappings, test thoroughly

### Fallback Strategy
- **Branch Protection**: Keep current implementation in `feature/custom-clustering` branch
- **Feature Flags**: Implement toggle between old and new systems
- **Gradual Rollout**: Test with subset of users first
- **Performance Monitoring**: Track clustering performance metrics
- **Rollback Plan**: Quick revert to custom clustering if issues arise

## Implementation Timeline

### Week 1: Foundation (3-4 days)
- **Day 1**: Refactor `MemoryClusteringService` → `MemoryArrowService`
- **Day 2**: Implement `setupMapboxClustering()` and basic layers
- **Day 3**: Test basic clustering with existing data
- **Day 4**: Implement arrow generation and display integration

### Week 2: Integration & Testing (3-4 days)
- **Day 1**: Implement native cluster click handling
- **Day 2**: Preserve bottom panel and memory interaction flows
- **Day 3**: Integration testing and performance optimization
- **Day 4**: Cleanup custom clustering code and final testing

### Total Estimate: 6-8 days for complete migration

## Offline Mode Compatibility

### Key Offline Features Preserved
1. **Tile Downloads**: All existing download methods remain unchanged
   - `setupOfflineMap()` - Complete offline setup
   - `downloadTilesForRegion()` - Regional tile downloads
   - `downloadStylePack()` - Style pack downloads

2. **Offline Detection**: All detection methods preserved
   - `isMapInOfflineMode()` - Check if currently offline
   - `isOfflineDataAvailable()` - Check if offline data exists
   - `updateOfflineStatus()` - Update offline status monitoring

3. **Background Services**: Full integration maintained
   - `BackgroundTileDownloadService` - Automatic tile downloads
   - `GlobalTileManager` - World and regional tile management
   - `OfflineSettingsService` - User preferences and settings

4. **Storage Management**: All storage features preserved
   - Tile quota management and limits
   - Progress tracking for downloads
   - Regional tile organization

### Integration Points
- **Initialization**: `_ensureOfflineInitialized()` called before clustering setup
- **Status Monitoring**: Offline status checked during clustering operations
- **Tile Compatibility**: Native clustering works with downloaded offline tiles
- **Performance**: Offline mode doesn't impact clustering performance

### Testing Requirements
- Verify clustering works with offline tiles
- Test arrow display in offline mode
- Ensure memory interactions work offline
- Validate tile downloads continue working
- Test background service integration

## Success Metrics
- **Performance**: Clustering time < 100ms for 1000+ memories
- **Functionality**: All existing features work identically (including offline)
- **Offline Compatibility**: 100% offline feature preservation
- **Code Quality**: Reduced complexity and improved maintainability
- **User Experience**: Smooth interactions with no regressions
- **Storage Efficiency**: No increase in offline storage requirements
