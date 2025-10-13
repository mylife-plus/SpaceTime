# Map Initialization Flow - Detailed Logic Documentation

## Overview

This document provides a comprehensive explanation of the map initialization flow, including location permissions, internet connectivity, tile downloading, map loading, and error handling with detailed state management and logging.

## State Machine Architecture

### MapInitializationState Enum

The map initialization follows a sequential state machine with the following states:

```dart
enum MapInitializationState {
  initial,           // Starting state
  checkingPermission, // Checking/requesting location permission
  permissionDenied,   // Permission denied, show permission screen
  checkingInternet,   // Checking internet connectivity
  internetRequired,   // No internet and no offline tiles, show internet screen
  downloadingTiles,   // Downloading map tiles
  loadingMap,        // Loading map with tiles
  ready,             // Map is ready and functional
  error              // Error state
}
```

### Enhanced State Logging

Each state transition is logged with:
- **Timestamp**: ISO8601 formatted timestamp
- **State Transition**: Old state → New state
- **Reason**: Why the transition occurred
- **Context**: Additional metadata (permissions, connectivity, errors)
- **State-specific Information**: What each state represents

Example log output:
```
🔄 [STATE TRANSITION] [2024-01-15T10:30:45.123Z] initial → checkingPermission
   📝 Reason: Starting map initialization sequence
   📊 Context: {timestamp: 2024-01-15T10:30:45.123Z, method: startMapInitializationSequence}
   📤 Leaving: Initial startup state
   📥 Entering: Permission checking phase
   ✅ State transition completed
```

## 1. Location Permission Flow

### Permission Screen Display Logic

The permission screen is shown when:
- State is `MapInitializationState.checkingPermission`
- State is `MapInitializationState.permissionDenied`

**Key Requirement**: The permission screen **MUST NOT HIDE** until permission is actually granted.

### Permission State Management

#### Initial Permission Check
```dart
Future<void> _checkLocationPermissionInState() async {
  debugPrint('🔐 [PERMISSION CHECK] Starting location permission check in state');
  final permissionService = Get.find<PermissionService>();
  final hasPermission = await permissionService.checkLocationPermission(requestIfDenied: true);
  
  if (hasPermission) {
    debugPrint('🔐 [PERMISSION CHECK] ✅ Permission granted, advancing to next state');
    _advanceToNextState();
  } else {
    debugPrint('🔐 [PERMISSION CHECK] ❌ Permission denied, transitioning to denied state');
    _setState(MapInitializationState.permissionDenied, 
      reason: 'Location permission denied during state check');
  }
}
```

#### Permission Change Listener
```dart
void _handlePermissionStateChange(bool hasPermission) {
  debugPrint('🔐 [PERMISSION CHANGE] Permission state changed: $hasPermission');
  
  if (currentInitializationState.value == MapInitializationState.checkingPermission ||
      currentInitializationState.value == MapInitializationState.permissionDenied) {
    
    if (hasPermission) {
      debugPrint('🔐 [PERMISSION CHANGE] ✅ Permission granted, advancing to internet check');
      _setState(MapInitializationState.checkingInternet,
        reason: 'Permission granted, advancing to internet check');
    } else {
      debugPrint('🔐 [PERMISSION CHANGE] ❌ Permission denied');
      if (currentInitializationState.value != MapInitializationState.permissionDenied) {
        _setState(MapInitializationState.permissionDenied,
          reason: 'Permission denied by user');
      }
    }
  }
}
```

### Permission Screen Behavior

1. **Screen Persistence**: The permission screen remains visible until `hasLocationPermission.value` becomes `true`
2. **Real-time Updates**: The screen shows a loading indicator when permission is granted but state hasn't transitioned yet
3. **User Actions**: 
   - "Grant Permission" button requests permission
   - "Open Settings" button provides alternative path
4. **State Transition**: Only when permission is granted does the state move from `permissionDenied` to `checkingInternet`

## 2. Internet Connectivity Flow

### Internet Screen Display Logic

The internet screen is shown when:
- State is `MapInitializationState.internetRequired`
- No internet connectivity AND fewer than 50,000 offline tiles available

### Connectivity State Management

#### Internet Check Process
```dart
Future<void> _checkInternetAndAdvance() async {
  final connectivityService = Get.find<ConnectivityService>();
  final isConnected = connectivityService.isConnected.value;
  
  if (isConnected) {
    debugPrint('🌐 [INTERNET CHECK] ✅ Internet available, proceeding to tile download');
    _setState(MapInitializationState.downloadingTiles,
      reason: 'Internet connectivity confirmed');
  } else {
    final tileCount = await _getOfflineTileCount();
    if (tileCount < 50000) {
      debugPrint('🌐 [INTERNET CHECK] ❌ No internet, insufficient tiles ($tileCount < 50000)');
      _setState(MapInitializationState.internetRequired,
        reason: 'No internet connectivity and insufficient offline tiles');
    } else {
      debugPrint('🌐 [INTERNET CHECK] ✅ Sufficient offline tiles ($tileCount), proceeding');
      _setState(MapInitializationState.loadingMap,
        reason: 'Sufficient offline tiles available');
    }
  }
}
```

#### Connectivity Change Listener
```dart
void _handleConnectivityStateChange(bool isConnected) {
  debugPrint('🌐 [CONNECTIVITY CHANGE] Connectivity state changed: $isConnected');
  
  if (currentInitializationState.value == MapInitializationState.internetRequired) {
    if (isConnected) {
      debugPrint('🌐 [CONNECTIVITY CHANGE] ✅ Internet restored, advancing to tile download');
      _setState(MapInitializationState.downloadingTiles,
        reason: 'Internet connectivity restored');
    }
  }
}
```

### Internet Screen Behavior

1. **Immediate Display**: Shows immediately when no internet and insufficient tiles
2. **Auto-dismiss**: Automatically hides when internet connectivity is restored
3. **No Delay**: Responsive transitions without artificial delays
4. **Background Monitoring**: Continuously monitors connectivity status

## 3. Backend Tile Downloading

### Tile Download Process

#### Download Initiation
```dart
Future<void> _startTileDownload() async {
  debugPrint('⬇️ [TILE DOWNLOAD] Starting map tile download');
  
  try {
    final service = Get.find<BackgroundTileDownloadService>();
    await service.startDownload();
    
    // Wait briefly to show download progress
    await Future.delayed(const Duration(seconds: 2));
    
    debugPrint('⬇️ [TILE DOWNLOAD] Download initiated, advancing to map loading');
    _advanceToNextState();
  } catch (e) {
    debugPrint('❌ [TILE DOWNLOAD] Error downloading tiles: $e');
    _setState(MapInitializationState.error,
      reason: 'Error during tile download');
  }
}
```

#### Tile Count Monitoring
- Continuously monitors offline tile count
- Threshold: 50,000 tiles for offline functionality
- Updates UI based on tile availability

### Download States

1. **downloadingTiles**: Active tile downloading in progress
2. **Progress Tracking**: Shows download progress to user
3. **Error Handling**: Transitions to error state on download failure
4. **Completion**: Advances to map loading when sufficient tiles downloaded

## 4. Map Loading Process

### Map Loading Sequence

#### Loading Initiation
```dart
Future<void> _startMapLoading() async {
  debugPrint('🗺️ [MAP LOADING] Starting map view loading');

  try {
    // Use direct initialization method for actual map setup
    await _performDirectMapInitialization();

    debugPrint('🗺️ [MAP LOADING] Map loading completed, advancing to ready state');
    _advanceToNextState();
  } catch (e) {
    debugPrint('❌ [MAP LOADING] Error loading map: $e');
    _setState(MapInitializationState.error,
      reason: 'Error during map loading');
  }
}
```

#### Map Initialization Steps

1. **Mapbox Controller Setup**: Initialize Mapbox map controller
2. **Style Loading**: Load map style and configuration
3. **Event Listeners**: Set up map event listeners
4. **Initial Position**: Set initial camera position
5. **Feature Loading**: Load map features and annotations

### Map Loading States

- **loadingMap**: Map view is being initialized
- **ready**: Map is fully loaded and functional
- **error**: Map loading failed

## 5. Error Handling and Listeners

### Error State Management

#### Error Transition
```dart
void _setState(MapInitializationState newState, {String? reason, Map<String, dynamic>? context}) {
  // Enhanced error logging
  if (newState == MapInitializationState.error) {
    debugPrint('💥 [ERROR STATE] Entering error state');
    debugPrint('   📝 Reason: $reason');
    debugPrint('   📊 Context: $context');
    debugPrint('   ⚠️ Manual intervention may be required');
  }
}
```

#### Error Recovery
```dart
Future<void> retryCurrentState() async {
  debugPrint('🔄 [RETRY] Retrying current state: ${currentInitializationState.value}');

  switch (currentInitializationState.value) {
    case MapInitializationState.permissionDenied:
      _setState(MapInitializationState.checkingPermission,
        reason: 'User-triggered retry from permission denied state');
      break;
    case MapInitializationState.internetRequired:
      await connectivityService.refreshConnectivity();
      _setState(MapInitializationState.checkingInternet,
        reason: 'User-triggered retry from internet required state');
      break;
    case MapInitializationState.error:
      _setState(MapInitializationState.initial,
        reason: 'User-triggered retry from error state');
      break;
  }
}
```

### Mapbox Event Listeners

#### Map Creation Listener
```dart
void onMapCreated(MapboxMap mapboxMap) {
  debugPrint('🗺️ [MAPBOX EVENT] Map created successfully');

  // Set up additional event listeners
  mapboxMap.setOnMapLoadedListener(() {
    debugPrint('🗺️ [MAPBOX EVENT] Map loaded completely');
    if (currentInitializationState.value == MapInitializationState.loadingMap) {
      _setState(MapInitializationState.ready,
        reason: 'Map loaded successfully via Mapbox event');
    }
  });
}
```

#### Error Listeners
```dart
void onMapError(String error) {
  debugPrint('❌ [MAPBOX ERROR] Map error occurred: $error');

  if (currentInitializationState.value != MapInitializationState.error) {
    _setState(MapInitializationState.error,
      reason: 'Mapbox map error',
      context: {'mapboxError': error});
  }
}
```

## 6. State Transition Flow Summary

### Complete Flow Sequence

1. **initial** → **checkingPermission**: App startup
2. **checkingPermission** → **permissionDenied**: Permission denied
3. **checkingPermission** → **checkingInternet**: Permission granted
4. **permissionDenied** → **checkingInternet**: Permission granted (via listener)
5. **checkingInternet** → **internetRequired**: No internet + insufficient tiles
6. **checkingInternet** → **downloadingTiles**: Internet available
7. **checkingInternet** → **loadingMap**: Sufficient offline tiles
8. **internetRequired** → **downloadingTiles**: Internet restored
9. **downloadingTiles** → **loadingMap**: Tiles downloaded
10. **loadingMap** → **ready**: Map loaded successfully
11. **Any State** → **error**: Error occurred

### Key Behavioral Requirements

1. **Permission Screen Persistence**: Remains visible until permission granted
2. **Internet Screen Responsiveness**: Shows/hides immediately based on connectivity
3. **No Artificial Delays**: State transitions happen as soon as conditions are met
4. **Comprehensive Logging**: Every state change is logged with context
5. **Error Recovery**: Users can retry from any error state
6. **Real-time Monitoring**: Continuous monitoring of permissions and connectivity

### Logging Format

All state changes follow this enhanced logging format:
```
🔄 [STATE TRANSITION] [timestamp] oldState → newState
   📝 Reason: Human-readable reason
   📊 Context: {key: value, ...}
   📤 Leaving: Description of old state
   📥 Entering: Description of new state
   ✅ State transition completed
```

This comprehensive logging system ensures full traceability of the map initialization process and helps with debugging any issues that may arise.

