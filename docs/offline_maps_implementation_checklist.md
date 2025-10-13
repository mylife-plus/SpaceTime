# Offline Maps Implementation Checklist

## 🎯 **Immediate Changes Required**

### 1. **Create Offline Settings Service**
- [ ] Create `lib/services/offline_settings_service.dart`
- [ ] Implement SharedPreferences-based settings storage
- [ ] Add methods for force offline mode toggle
- [ ] Add tile download status tracking
- [ ] Add smart offline mode detection logic

### 2. **Update Location Picker Widget**
- [ ] Replace simple connectivity check with comprehensive offline detection
- [ ] Add offline mode priority logic (user preference > tiles available > network)
- [ ] Implement offline-first map configuration
- [ ] Add offline mode visual indicators
- [ ] Handle offline-only map interactions

### 3. **Create Global Tile Manager**
- [ ] Create `lib/services/global_tile_manager.dart`
- [ ] Implement world base tiles download (zoom 0-6)
- [ ] Add regional tiles download functionality
- [ ] Create tile availability checking methods
- [ ] Add download progress tracking

### 4. **Enhanced Offline Location Service**
- [ ] Extend existing `OfflineLocationSearchService`
- [ ] Add comprehensive city database loading
- [ ] Implement better search ranking algorithm
- [ ] Add coordinate-based search functionality
- [ ] Integrate user-saved locations into search

## 🔧 **Code Changes Required**

### Location Picker Widget Updates

#### Replace Current Offline Detection
```dart
// CURRENT (line 81-94)
Future<void> _checkOfflineMode() async {
  try {
    final result = await InternetAddress.lookup('mapbox.com');
    isOfflineMode = result.isEmpty;
  } catch (e) {
    isOfflineMode = true;
    debugPrint('Offline mode detected: $e');
  }
  
  if (isOfflineMode) {
    debugPrint('Running in offline mode - using cached tiles and locations');
  }
}

// REPLACE WITH
Future<void> _determineOfflineMode() async {
  final offlineSettings = OfflineSettingsService.instance;
  
  // Priority 1: User forced offline mode
  if (await offlineSettings.isForceOfflineEnabled()) {
    isOfflineMode = true;
    offlineModeReason = 'User preference';
    return;
  }
  
  // Priority 2: Check if tiles are downloaded
  if (await offlineSettings.areBasicTilesDownloaded()) {
    isOfflineMode = true;
    offlineModeReason = 'Tiles available';
    return;
  }
  
  // Priority 3: Network connectivity
  isOfflineMode = !(await _hasInternetConnectivity());
  offlineModeReason = isOfflineMode ? 'No internet' : 'Online';
}
```

#### Update Map Configuration
```dart
// CURRENT (line 1101-1103)
styleUri: isOfflineMode
    ? mapbox.MapboxStyles.MAPBOX_STREETS // Will use cached tiles
    : mapbox.MapboxStyles.MAPBOX_STREETS,

// REPLACE WITH
styleUri: _getOptimalStyleUri(),
resourceOptions: mapbox.ResourceOptions(
  accessToken: mapboxAccessToken,
  cachePath: await _getOfflineCachePath(),
  tileStoreUsageMode: isOfflineMode 
    ? mapbox.TileStoreUsageMode.READ_ONLY 
    : mapbox.TileStoreUsageMode.READ_AND_UPDATE,
),
```

#### Add Offline Mode Indicator
```dart
// ADD TO UI (after line 1030)
if (isOfflineMode) _buildOfflineModeIndicator(),

Widget _buildOfflineModeIndicator() {
  return Container(
    margin: EdgeInsets.all(16),
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.orange.withOpacity(0.9),
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.wifi_off, size: 16, color: Colors.white),
        SizedBox(width: 6),
        Text(
          'Offline Mode ($offlineModeReason)',
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    ),
  );
}
```

### Map Controller Integration

#### Add Tile Management Methods
```dart
// ADD TO MapController
Future<void> ensureOfflineTilesAvailable() async {
  final tileManager = GlobalTileManager.instance;
  
  if (!await tileManager.areWorldBaseTilesDownloaded()) {
    debugPrint('🗺 OFFLINE - Downloading world base tiles...');
    await tileManager.downloadWorldBaseTiles();
  }
  
  // Download regional tiles based on current location
  if (currentPosition != null) {
    await tileManager.downloadRegionalTiles(
      currentPosition!.latitude,
      currentPosition!.longitude,
    );
  }
}

Future<bool> areTilesAvailableForLocation(double lat, double lng) async {
  final tileManager = GlobalTileManager.instance;
  return await tileManager.areTilesAvailable(lat, lng, 14); // Max zoom level
}
```

## 📱 **UI Components to Create**

### 1. **Offline Maps Settings Screen**
```dart
// lib/app/modules/settings/views/offline_maps_settings.dart
class OfflineMapsSettings extends StatefulWidget {
  // Features needed:
  // - Force offline mode toggle
  // - Download world tiles button with progress
  // - Download regional tiles for current location
  // - List of downloaded regions with delete options
  // - Cache size display and clear cache button
  // - Offline mode explanation
}
```

### 2. **Tile Download Progress Dialog**
```dart
// lib/app/widgets/tile_download_dialog.dart
class TileDownloadDialog extends StatefulWidget {
  // Features needed:
  // - Download progress bar
  // - Current operation description
  // - Cancel download option
  // - Estimated time remaining
  // - Download speed indicator
}
```

### 3. **Offline Capability Warning Dialog**
```dart
// lib/app/widgets/offline_capability_dialog.dart
class OfflineCapabilityDialog extends StatelessWidget {
  // Features needed:
  // - List of available offline features
  // - List of unavailable features
  // - Option to download more tiles
  // - Settings shortcut
}
```

## 🗂️ **New Files to Create**

### 1. **Offline Settings Service**
```
lib/services/offline_settings_service.dart
- SharedPreferences management
- Offline mode preferences
- Tile download status tracking
- Smart offline detection
```

### 2. **Global Tile Manager**
```
lib/services/global_tile_manager.dart
- World base tiles download
- Regional tiles management
- Tile availability checking
- Download progress tracking
- Cache size management
```

### 3. **Enhanced Offline Location Service**
```
lib/services/enhanced_offline_location_service.dart
- Comprehensive city database
- Advanced search algorithms
- Coordinate-based search
- User location integration
```

### 4. **Offline Memory Manager**
```
lib/services/offline_memory_manager.dart
- Memory-efficient operations
- Cache management
- Resource cleanup
- Performance monitoring
```

## 🔄 **Integration Points**

### 1. **App Initialization**
```dart
// In main.dart or app initialization
await OfflineSettingsService.instance.initialize();
await GlobalTileManager.instance.initialize();
await EnhancedOfflineLocationService.instance.initialize();
```

### 2. **Settings Screen Integration**
```dart
// Add to existing settings screen
ListTile(
  leading: Icon(Icons.map_outlined),
  title: Text('Offline Maps'),
  subtitle: Text('Manage offline map data'),
  onTap: () => Get.to(() => OfflineMapsSettings()),
),
```

### 3. **Memory View Integration**
```dart
// Update memory info widget to show offline status
if (isOfflineMode) 
  _buildOfflineModeWarning(),
```

## ⚙️ **Configuration Updates**

### 1. **pubspec.yaml**
```yaml
dependencies:
  sqflite: ^2.3.0              # Local tile database
  path_provider: ^2.1.1        # Cache directory access
  dio: ^5.3.2                  # Efficient downloads
  crypto: ^3.0.3               # Integrity checking
```

### 2. **Android Manifest**
```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

### 3. **iOS Info.plist**
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

## 🧪 **Testing Requirements**

### Unit Tests
- [ ] Offline settings service methods
- [ ] Tile availability checking
- [ ] Location search in offline mode
- [ ] Cache management operations

### Integration Tests
- [ ] Complete offline workflow
- [ ] Tile download and usage
- [ ] Mode transitions
- [ ] Memory usage monitoring

### Manual Testing
- [ ] Enable airplane mode and test all features
- [ ] Test with various tile cache sizes
- [ ] Test location selection accuracy
- [ ] Test performance with large datasets

## 📊 **Success Criteria**

1. **✅ Functionality**: Location picker works 100% offline after tiles downloaded
2. **✅ Performance**: <2s response time for offline location search
3. **✅ Storage**: Configurable cache (50MB-2GB) with cleanup
4. **✅ UX**: Clear offline indicators and capability communication
5. **✅ Reliability**: No crashes or data loss in offline mode

## 🚀 **Implementation Timeline**

### Week 1: Core Infrastructure
- [ ] Create offline settings service
- [ ] Update location picker offline detection
- [ ] Add basic offline indicators

### Week 2: Tile Management
- [ ] Implement global tile manager
- [ ] Add tile download functionality
- [ ] Create settings screen

### Week 3: Enhanced Features
- [ ] Improve offline search
- [ ] Add coordinate-based search
- [ ] Implement warning dialogs

### Week 4: Polish & Testing
- [ ] Performance optimization
- [ ] Comprehensive testing
- [ ] Documentation updates

This checklist provides a clear roadmap for implementing fully offline maps functionality in the SpaceTime app.
