# Internet Required Screen Display Conditions

This document outlines all conditions and scenarios where the **InternetRequiredScreen** is displayed in the SpaceTime app.

## 📋 Overview

The InternetRequiredScreen is shown when the app determines that:
1. **No internet connectivity** is available
2. **No offline tiles** are downloaded
3. **Internet is required** for the current operation

## 🔄 State-Based Display Logic

### Primary State Trigger
The InternetRequiredScreen is displayed when the MapController's state is set to:
```dart
MapInitializationState.internetRequired
```

### UI Display Logic (MapView)
Located in: `lib/app/modules/map/views/map_view.dart`

The screen is shown when **ANY** of these conditions are met:
```dart
// Condition 1: Downloaded tiles < 50,000 AND connectivity issues
if (service.totalTilesDownloaded.value < 50000 || _shouldShowConnectivityScreens(controller))

// Condition 2: State is specifically internetRequired
if (state == MapInitializationState.internetRequired)
```

## 🌐 Detailed Conditions

### 1. **App Launch - No Internet & No Tiles**
**Location**: `_checkInitialConnectivityAndSetState()` in MapController
**Trigger**: App first launch or initialization

```dart
if (!hasInternet || connectionType == 'none') {
  final hasOfflineTiles = await isOfflineDataAvailable();
  if (!hasOfflineTiles) {
    _setState(MapInitializationState.internetRequired);
  }
}
```

**Conditions**:
- ✅ No internet connection (`isConnected.value = false`)
- ✅ Connection type is 'none'
- ✅ No offline tiles available (`isOfflineDataAvailable() = false`)

### 2. **Permission Granted - No Internet Check**
**Location**: State machine flow after permission check
**Trigger**: Location permission granted but no internet

**Flow**:
1. `checkingPermission` → `checkingInternet`
2. `_checkInternetAndAdvance()` called
3. If no internet → `_checkOfflineTilesAndSetState()`
4. If no tiles → `MapInitializationState.internetRequired`

**Conditions**:
- ✅ Location permission granted
- ✅ No internet for Mapbox (`hasInternetForMapbox() = false`)
- ✅ No offline tiles available

### 3. **Connectivity Loss During App Usage**
**Location**: `_handleConnectivityStateChange()` in MapController
**Trigger**: Internet connection lost while app is running

```dart
if (!isConnected) {
  if (currentState == MapInitializationState.ready ||
      currentState == MapInitializationState.loadingMap ||
      currentState == MapInitializationState.checkingInternet) {
    _checkIfInternetScreenNeeded();
  }
}
```

**Conditions**:
- ✅ Internet connection lost (`isConnected.value = false`)
- ✅ App was in ready/loading state
- ✅ No offline tiles available after connectivity check

### 4. **Mapbox Connectivity Errors**
**Location**: `_checkInternetAndAdvance()` error handling
**Trigger**: Mapbox SDK connectivity errors detected

```dart
if (connectivityService.isMapboxConnectivityError(e.toString())) {
  _setState(MapInitializationState.internetRequired);
}
```

**Conditions**:
- ✅ Mapbox connectivity error detected
- ✅ Error indicates network connectivity issues

### 5. **First Time Load Check**
**Location**: `_checkInitialConnectivityState()` (legacy method)
**Trigger**: First time app load

```dart
if (isFirstTimeLoad.value && !hasInternet && !hasOfflineTiles.value) {
  shouldShowInternetScreen.value = true;
  needsInternetConnection.value = true;
}
```

**Conditions**:
- ✅ First time loading the app
- ✅ No internet connection
- ✅ No offline tiles available

### 6. **Error State Recovery**
**Location**: `_shouldShowConnectivityScreens()` in MapView
**Trigger**: App in error state that might be connectivity-related

```dart
if (currentState == MapInitializationState.error) {
  return true; // Show connectivity screens for potential recovery
}
```

**Conditions**:
- ✅ App is in error state
- ✅ Error might be connectivity-related

## 🔍 Supporting Conditions

### Offline Tile Availability Check
**Method**: `isOfflineDataAvailable()`
**Logic**:
```dart
// Check if offline components are initialized
if (tileStore == null || offlineManager == null) return false;

// Check if we actually have downloaded tiles
final hasDownloadedTiles = await _hasDownloadedTiles();
return hasDownloadedTiles;
```

### Downloaded Tiles Check
**Method**: `_hasDownloadedTiles()`
**Logic**:
```dart
final backgroundService = Get.find<BackgroundTileDownloadService>();
final tileCount = backgroundService.totalTilesDownloaded.value;
return tileCount > 0;
```

### Internet Connectivity Check
**Method**: `hasInternetForMapbox()` in ConnectivityService
**Logic**:
```dart
// Quick connectivity check first
final results = await _connectivity.checkConnectivity();
if (results.isEmpty || results.contains(ConnectivityResult.none)) return false;

// Test actual internet connectivity
final result = await InternetAddress.lookup('google.com').timeout(Duration(seconds: 2));
return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
```

## 🎯 Summary of All Conditions

The InternetRequiredScreen is shown when **ALL** of these are true:

### Core Requirements:
1. **No Internet Connection**
   - `ConnectivityService.isConnected.value = false`
   - OR `connectionType.value = 'none'`
   - OR `hasInternetForMapbox() = false`

2. **No Offline Tiles Available**
   - `isOfflineDataAvailable() = false`
   - Which means `_hasDownloadedTiles() = false`
   - Which means `totalTilesDownloaded.value = 0`

### Trigger Scenarios:
- ✅ **App Launch**: First time opening app without internet
- ✅ **Permission Flow**: After granting location permission but no internet
- ✅ **Connectivity Loss**: Internet disconnected during app usage
- ✅ **Mapbox Errors**: SDK detects connectivity issues
- ✅ **Error Recovery**: App in error state potentially due to connectivity
- ✅ **Tile Limit**: Less than 50,000 tiles downloaded AND connectivity issues

## 🔄 User Actions to Dismiss

The InternetRequiredScreen can be dismissed when:

1. **Internet Restored**: User connects to internet and taps "Check Connection"
2. **Offline Tiles Available**: Background service downloads sufficient tiles
3. **State Retry**: User triggers retry and conditions are resolved

## 🛠️ Technical Implementation

### State Management:
- **Primary State**: `MapInitializationState.internetRequired`
- **UI Flag**: `shouldShowInternetScreen.value = true`
- **Reactive**: Uses `Obx()` for real-time updates

### Service Integration:
- **ConnectivityService**: Monitors network state
- **BackgroundTileDownloadService**: Tracks tile availability
- **MapController**: Manages state transitions

### Error Handling:
- **Graceful Degradation**: Shows screen on connectivity errors
- **Recovery Options**: Provides retry mechanisms
- **User Feedback**: Clear status messages and actions
