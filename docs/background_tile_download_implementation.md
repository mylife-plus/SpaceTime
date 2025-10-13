# Background Tile Download & Auto-Offline Implementation

## Overview
Implement background tile downloading with automatic offline mode enforcement when maximum tiles are downloaded, while preserving all existing MapController functionality.

## Current State Analysis

### Existing MapController Features
- ✅ TileStore and OfflineManager already configured
- ✅ Offline region management with `_offlineRegions`
- ✅ Memory clustering and display functionality
- ✅ Location services and map interactions
- ✅ Filter and search capabilities

### Current Offline Infrastructure
```dart
// Already exists in MapController
mapbox.TileStore? _tileStore;
mapbox.OfflineManager? _offlineManager;
final RxList<mapbox.OfflineRegion> _offlineRegions = <mapbox.OfflineRegion>[].obs;
```

## Implementation Strategy

### 1. Background Tile Download Service
Create a new service that works alongside existing MapController without modifying core logic.

### 2. Tile Quota Management
Implement intelligent tile quota tracking and automatic offline enforcement.

### 3. Progressive Download Strategy
Download tiles based on user behavior and location patterns.

## Required Changes

### Phase 1: Background Download Service

#### A. Create BackgroundTileDownloadService
**File**: `lib/services/background_tile_download_service.dart`

```dart
class BackgroundTileDownloadService extends GetxService {
  static BackgroundTileDownloadService get instance => Get.find();
  
  // Configuration
  static const int MAX_TILES_THRESHOLD = 50000; // Force offline after this
  static const int BACKGROUND_DOWNLOAD_BATCH_SIZE = 1000;
  static const Duration DOWNLOAD_INTERVAL = Duration(minutes: 5);
  
  // State management
  final RxBool isDownloading = false.obs;
  final RxInt totalTilesDownloaded = 0.obs;
  final RxDouble downloadProgress = 0.0.obs;
  final RxBool forceOfflineMode = false.obs;
  
  Timer? _downloadTimer;
  mapbox.TileStore? _tileStore;
  mapbox.OfflineManager? _offlineManager;
}
```

#### B. Integration Points
- Hook into existing MapController initialization
- Use existing TileStore and OfflineManager instances
- Monitor user location patterns from MapController

### Phase 2: Tile Quota Management

#### A. Tile Counting System
```dart
// Add to BackgroundTileDownloadService
Future<int> getCurrentTileCount() async {
  // Use existing TileStore to count tiles
  final regions = await _offlineManager?.listOfflineRegions() ?? [];
  int totalTiles = 0;
  
  for (final region in regions) {
    final status = await region.getOfflineRegionStatus();
    totalTiles += status.completedTileCount;
  }
  
  return totalTiles;
}

Future<bool> shouldForceOfflineMode() async {
  final currentTiles = await getCurrentTileCount();
  return currentTiles >= MAX_TILES_THRESHOLD;
}
```

#### B. Auto-Offline Enforcement
```dart
// Add to BackgroundTileDownloadService
Future<void> checkAndEnforceOfflineMode() async {
  if (await shouldForceOfflineMode()) {
    forceOfflineMode.value = true;
    
    // Update OfflineSettingsService
    await OfflineSettingsService.instance.setForceOfflineMode(true);
    
    // Notify user
    _showOfflineModeEnforcedNotification();
  }
}
```

### Phase 3: Progressive Download Strategy

#### A. Smart Region Selection
```dart
// Add to BackgroundTileDownloadService
Future<List<mapbox.CoordinateBounds>> getHighPriorityRegions() async {
  final mapController = Get.find<MapController>();
  
  // Get user's frequent locations from memory data
  final frequentLocations = await _analyzeUserLocationPatterns();
  
  // Get current location
  final currentLocation = mapController.currentLocation.value;
  
  // Combine and prioritize
  return _prioritizeDownloadRegions(frequentLocations, currentLocation);
}
```

#### B. Intelligent Download Scheduling
```dart
// Add to BackgroundTileDownloadService
void startBackgroundDownloads() {
  _downloadTimer = Timer.periodic(DOWNLOAD_INTERVAL, (timer) async {
    if (!isDownloading.value && !forceOfflineMode.value) {
      await _performBackgroundDownload();
    }
  });
}

Future<void> _performBackgroundDownload() async {
  if (await shouldForceOfflineMode()) {
    await checkAndEnforceOfflineMode();
    return;
  }
  
  final priorityRegions = await getHighPriorityRegions();
  await _downloadRegionBatch(priorityRegions.first);
}
```

## Integration with Existing Code

### 1. MapController Integration
**File**: `lib/app/modules/map/controllers/map_controller.dart`

```dart
// Add to MapController initialization
@override
void onInit() {
  super.onInit();
  
  // Existing initialization code remains unchanged
  _initializeMap();
  _loadMemoriesFromDatabase();
  
  // NEW: Initialize background download service
  _initializeBackgroundDownloads();
}

Future<void> _initializeBackgroundDownloads() async {
  // Wait for map initialization
  await Future.delayed(Duration(seconds: 2));
  
  final downloadService = Get.find<BackgroundTileDownloadService>();
  
  // Share TileStore and OfflineManager instances
  await downloadService.initialize(
    tileStore: _tileStore,
    offlineManager: _offlineManager,
  );
  
  // Start background downloads
  downloadService.startBackgroundDownloads();
}
```

### 2. Location Picker Integration
**File**: `lib/app/modules/memories/views/mini_widgets/location_picker_widget.dart`

```dart
// Enhance existing offline mode detection
Future<void> _determineOfflineMode() async {
  // Existing logic remains unchanged
  await OfflineSettingsService.instance.initialize();
  await GlobalTileManager.instance.initialize();
  
  // NEW: Check if forced offline due to tile quota
  final downloadService = Get.find<BackgroundTileDownloadService>();
  if (downloadService.forceOfflineMode.value) {
    isOfflineMode = true;
    offlineModeReason = 'Tile quota reached - Auto offline';
    offlineModePriority = OfflineModePriority.forceOffline; // New priority
    return;
  }
  
  // Continue with existing offline detection logic...
}
```

## New Components Required

### 1. Enhanced OfflineModePriority
**File**: `lib/services/offline_settings_service.dart`

```dart
enum OfflineModePriority {
  userForced,      // User explicitly enabled offline
  forceOffline,    // NEW: System forced due to tile quota
  tilesAvailable,  // Tiles available locally
  networkCheck,    // No internet connection
}
```

### 2. Tile Analytics Service
**File**: `lib/services/tile_analytics_service.dart`

```dart
class TileAnalyticsService {
  // Analyze user location patterns
  Future<List<LocationPattern>> analyzeUserLocationPatterns();
  
  // Predict future tile needs
  Future<List<mapbox.CoordinateBounds>> predictTileNeeds();
  
  // Optimize download priorities
  List<mapbox.CoordinateBounds> optimizeDownloadQueue();
}
```

### 3. Background Task Manager
**File**: `lib/services/background_task_manager.dart`

```dart
class BackgroundTaskManager {
  // Handle app lifecycle for downloads
  void pauseDownloads();
  void resumeDownloads();
  
  // Battery and network optimization
  bool shouldDownloadNow();
  void optimizeForBattery();
}
```

## User Experience Enhancements

### 1. Download Progress UI
```dart
// Add to map view or settings
Widget _buildDownloadProgressIndicator() {
  return Obx(() {
    final service = Get.find<BackgroundTileDownloadService>();
    
    if (!service.isDownloading.value) return SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.all(8),
      child: Column(
        children: [
          Text('Downloading offline maps...'),
          LinearProgressIndicator(value: service.downloadProgress.value),
          Text('${service.totalTilesDownloaded.value} tiles downloaded'),
        ],
      ),
    );
  });
}
```

### 2. Offline Mode Notifications
```dart
void _showOfflineModeEnforcedNotification() {
  Get.snackbar(
    'Offline Mode Activated',
    'Maximum tiles downloaded. App now running in offline mode for optimal performance.',
    backgroundColor: Colors.blue,
    colorText: Colors.white,
    duration: Duration(seconds: 5),
    mainButton: TextButton(
      onPressed: () => _showTileManagementDialog(),
      child: Text('Manage', style: TextStyle(color: Colors.white)),
    ),
  );
}
```

## Configuration Options

### 1. Settings Integration
```dart
// Add to app settings
class OfflineMapSettings {
  static const String MAX_TILES_KEY = 'max_tiles_threshold';
  static const String AUTO_DOWNLOAD_KEY = 'auto_download_enabled';
  static const String DOWNLOAD_ON_WIFI_ONLY = 'wifi_only_downloads';
  
  // User configurable limits
  int maxTilesThreshold = 50000;
  bool autoDownloadEnabled = true;
  bool wifiOnlyDownloads = true;
}
```

### 2. Advanced Configuration
```dart
// For power users
class AdvancedTileSettings {
  int downloadBatchSize = 1000;
  Duration downloadInterval = Duration(minutes: 5);
  List<int> preferredZoomLevels = [10, 11, 12, 13, 14];
  double regionPaddingKm = 5.0;
}
```

## Implementation Timeline

### Week 1: Core Infrastructure
- [ ] Create BackgroundTileDownloadService
- [ ] Implement tile counting system
- [ ] Add quota management logic

### Week 2: Download Strategy
- [ ] Implement progressive download algorithm
- [ ] Add location pattern analysis
- [ ] Create intelligent scheduling

### Week 3: Integration
- [ ] Integrate with existing MapController
- [ ] Update LocationPickerWidget
- [ ] Add UI components

### Week 4: Polish & Testing
- [ ] Add configuration options
- [ ] Implement user notifications
- [ ] Performance optimization
- [ ] Comprehensive testing

## Benefits

### 1. Seamless User Experience
- Maps work offline without user intervention
- Intelligent tile downloading based on usage patterns
- Automatic optimization for performance

### 2. Resource Management
- Prevents unlimited tile storage growth
- Optimizes battery and network usage
- Maintains app performance

### 3. Reliability
- Guaranteed offline functionality
- Predictable storage usage
- Graceful degradation

This implementation maintains all existing MapController functionality while adding sophisticated background tile management and automatic offline mode enforcement.

## Detailed Implementation Steps

### Step 1: Background Download Service Implementation

#### A. Service Structure
```dart
// lib/services/background_tile_download_service.dart
class BackgroundTileDownloadService extends GetxService {
  // Core dependencies
  mapbox.TileStore? _tileStore;
  mapbox.OfflineManager? _offlineManager;
  Timer? _downloadTimer;

  // State tracking
  final RxMap<String, DownloadRegion> _downloadQueue = <String, DownloadRegion>{}.obs;
  final RxList<String> _completedRegions = <String>[].obs;
  final RxBool _isInitialized = false.obs;

  // Configuration
  final _config = BackgroundDownloadConfig();

  @override
  Future<void> onInit() async {
    super.onInit();
    await _loadConfiguration();
    await _loadDownloadHistory();
  }

  Future<void> initialize({
    required mapbox.TileStore? tileStore,
    required mapbox.OfflineManager? offlineManager,
  }) async {
    _tileStore = tileStore;
    _offlineManager = offlineManager;
    _isInitialized.value = true;

    // Start monitoring
    _startTileQuotaMonitoring();
    _startBackgroundDownloads();
  }
}
```

#### B. Download Queue Management
```dart
class DownloadRegion {
  final String id;
  final mapbox.CoordinateBounds bounds;
  final List<int> zoomLevels;
  final int priority;
  final DateTime scheduledTime;
  final DownloadStatus status;

  DownloadRegion({
    required this.id,
    required this.bounds,
    required this.zoomLevels,
    required this.priority,
    required this.scheduledTime,
    this.status = DownloadStatus.pending,
  });
}

enum DownloadStatus {
  pending,
  downloading,
  completed,
  failed,
  cancelled,
}
```

### Step 2: Smart Region Prioritization

#### A. Location Pattern Analysis
```dart
// lib/services/tile_analytics_service.dart
class TileAnalyticsService {
  Future<List<LocationHotspot>> analyzeUserPatterns() async {
    final memoryController = Get.find<MemoryController>();
    final memories = memoryController.allMemories;

    // Group memories by location clusters
    final locationClusters = <LocationCluster>[];

    for (final memory in memories) {
      final lat = memory['location_latitude'];
      final lng = memory['location_longitude'];

      if (lat != null && lng != null) {
        _addToLocationCluster(locationClusters, lat, lng, memory);
      }
    }

    // Convert clusters to hotspots with priority scores
    return locationClusters.map((cluster) => LocationHotspot(
      center: cluster.center,
      radius: cluster.radius,
      memoryCount: cluster.memories.length,
      lastVisited: cluster.lastVisited,
      priority: _calculatePriority(cluster),
    )).toList();
  }

  int _calculatePriority(LocationCluster cluster) {
    final recency = DateTime.now().difference(cluster.lastVisited).inDays;
    final frequency = cluster.memories.length;

    // Higher frequency and recent visits = higher priority
    return (frequency * 10) - (recency ~/ 7);
  }
}
```

#### B. Predictive Download Strategy
```dart
// Add to BackgroundTileDownloadService
Future<void> _scheduleIntelligentDownloads() async {
  final analytics = Get.find<TileAnalyticsService>();
  final hotspots = await analytics.analyzeUserPatterns();

  // Sort by priority
  hotspots.sort((a, b) => b.priority.compareTo(a.priority));

  // Schedule downloads for top hotspots
  for (int i = 0; i < math.min(5, hotspots.length); i++) {
    final hotspot = hotspots[i];
    await _scheduleRegionDownload(
      bounds: _createBoundsFromHotspot(hotspot),
      priority: hotspot.priority,
      zoomLevels: _getOptimalZoomLevels(hotspot),
    );
  }
}
```

### Step 3: Quota Management System

#### A. Tile Counting and Monitoring
```dart
// Add to BackgroundTileDownloadService
class TileQuotaManager {
  static const int DEFAULT_MAX_TILES = 50000;
  static const int WARNING_THRESHOLD = 40000;

  Future<TileQuotaStatus> getCurrentQuotaStatus() async {
    final totalTiles = await _countAllTiles();
    final maxTiles = await _getMaxTilesLimit();

    return TileQuotaStatus(
      currentTiles: totalTiles,
      maxTiles: maxTiles,
      usagePercentage: (totalTiles / maxTiles) * 100,
      shouldWarn: totalTiles >= WARNING_THRESHOLD,
      shouldForceOffline: totalTiles >= maxTiles,
    );
  }

  Future<int> _countAllTiles() async {
    if (_offlineManager == null) return 0;

    final regions = await _offlineManager!.listOfflineRegions();
    int totalTiles = 0;

    for (final region in regions) {
      try {
        final status = await region.getOfflineRegionStatus();
        totalTiles += status.completedTileCount;
      } catch (e) {
        debugPrint('Error getting region status: $e');
      }
    }

    return totalTiles;
  }
}
```

#### B. Automatic Offline Enforcement
```dart
// Add to BackgroundTileDownloadService
Future<void> _enforceOfflineModeIfNeeded() async {
  final quotaStatus = await TileQuotaManager().getCurrentQuotaStatus();

  if (quotaStatus.shouldForceOffline) {
    // Update offline settings
    await OfflineSettingsService.instance.setForceOfflineMode(true);
    forceOfflineMode.value = true;

    // Stop all downloads
    _stopAllDownloads();

    // Notify user
    _showQuotaReachedNotification(quotaStatus);

    // Optional: Clean up oldest tiles
    if (await _shouldAutoCleanup()) {
      await _performIntelligentCleanup();
    }
  } else if (quotaStatus.shouldWarn) {
    _showQuotaWarningNotification(quotaStatus);
  }
}
```

### Step 4: Integration Points

#### A. MapController Integration (Minimal Changes)
```dart
// lib/app/modules/map/controllers/map_controller.dart
// Add only these lines to existing onInit method:

@override
void onInit() {
  super.onInit();

  // All existing initialization code remains unchanged
  _initializeMap();
  _loadMemoriesFromDatabase();
  // ... existing code ...

  // NEW: Initialize background downloads after map is ready
  _initializeBackgroundTileService();
}

Future<void> _initializeBackgroundTileService() async {
  // Wait for map initialization to complete
  if (_tileStore != null && _offlineManager != null) {
    final downloadService = Get.put(BackgroundTileDownloadService());
    await downloadService.initialize(
      tileStore: _tileStore,
      offlineManager: _offlineManager,
    );
  }
}
```

#### B. Location Picker Enhancement
```dart
// lib/app/modules/memories/views/mini_widgets/location_picker_widget.dart
// Enhance existing _determineOfflineMode method:

Future<void> _determineOfflineMode() async {
  // Existing initialization
  await OfflineSettingsService.instance.initialize();
  await GlobalTileManager.instance.initialize();

  // NEW: Check forced offline mode first
  try {
    final downloadService = Get.find<BackgroundTileDownloadService>();
    if (downloadService.forceOfflineMode.value) {
      isOfflineMode = true;
      offlineModeReason = 'Tile quota reached';
      offlineModePriority = OfflineModePriority.forceOffline;
      return;
    }
  } catch (e) {
    // Service not initialized yet, continue with existing logic
  }

  // Continue with existing offline detection logic...
  final offlineMode = await OfflineSettingsService.instance.determineOfflineMode();
  // ... rest of existing code unchanged
}
```

### Step 5: User Interface Components

#### A. Download Progress Indicator
```dart
// lib/app/modules/map/views/widgets/download_progress_widget.dart
class DownloadProgressWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetBuilder<BackgroundTileDownloadService>(
      builder: (service) {
        if (!service.isDownloading.value) return SizedBox.shrink();

        return Container(
          margin: EdgeInsets.all(16),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.download, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Downloading offline maps...',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
              SizedBox(height: 8),
              LinearProgressIndicator(
                value: service.downloadProgress.value,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              SizedBox(height: 4),
              Text(
                '${service.totalTilesDownloaded.value} tiles downloaded',
                style: TextStyle(color: Colors.white70, fontSize: 10),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

#### B. Quota Status Widget
```dart
// lib/app/modules/settings/views/widgets/tile_quota_widget.dart
class TileQuotaWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetBuilder<BackgroundTileDownloadService>(
      builder: (service) {
        return FutureBuilder<TileQuotaStatus>(
          future: TileQuotaManager().getCurrentQuotaStatus(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return CircularProgressIndicator();

            final quota = snapshot.data!;
            return Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Offline Map Storage', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: quota.usagePercentage / 100,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        quota.shouldWarn ? Colors.orange : Colors.green,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('${quota.currentTiles} / ${quota.maxTiles} tiles (${quota.usagePercentage.toStringAsFixed(1)}%)'),
                    if (quota.shouldWarn)
                      Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          quota.shouldForceOffline
                            ? 'Quota reached - Offline mode enforced'
                            : 'Approaching quota limit',
                          style: TextStyle(
                            color: quota.shouldForceOffline ? Colors.red : Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
```

This comprehensive implementation provides background tile downloading with intelligent quota management while preserving all existing MapController functionality.
