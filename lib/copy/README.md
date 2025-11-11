# Download Service Copy

This directory contains a complete duplicate of the existing downloading service with all classes renamed with the `Copy` suffix.

## Purpose

The copy version allows you to:
- Test new features without affecting the production download service
- Run parallel download experiments
- Compare performance between different implementations
- Safely modify download logic without breaking existing functionality

## Files

### Core Service
- **`background_tile_download_service_copy.dart`** - Main download service (copy version)
  - `BackgroundTileDownloadServiceCopy` - Main service class
  - `DownloadRegionCopy` - Download region model
  - `DownloadStatusCopy` - Download status enum
  - `TileQuotaStatusCopy` - Quota status model

### Helper
- **`download_service_copy_helper.dart`** - Convenience methods to use the copy service
  - `DownloadServiceCopyHelper` - Static helper class with easy-to-use methods

### Documentation
- **`README.md`** - This file

## Key Differences from Original

All class names and references have been updated with the `Copy` suffix:

| Original | Copy Version |
|----------|--------------|
| `BackgroundTileDownloadService` | `BackgroundTileDownloadServiceCopy` |
| `DownloadRegion` | `DownloadRegionCopy` |
| `DownloadStatus` | `DownloadStatusCopy` |
| `TileQuotaStatus` | `TileQuotaStatusCopy` |

SharedPreferences keys are also suffixed with `_copy` to avoid conflicts:
- `auto_download_enabled` → `auto_download_enabled_copy`
- `wifi_only_downloads` → `wifi_only_downloads_copy`
- `max_tiles_limit` → `max_tiles_limit_copy`
- `total_tiles_downloaded` → `total_tiles_downloaded_copy`
- `download_queue` → `download_queue_copy`

## Usage

### 1. Basic Initialization

```dart
import 'package:spacetime/copy/download_service_copy_helper.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

// Initialize the copy service
await DownloadServiceCopyHelper.initialize(
  tileStore: myTileStore,
  offlineManager: myOfflineManager,
);
```

### 2. Download a Specific Region

```dart
// Define the region bounds
final bounds = mapbox.CoordinateBounds(
  southwest: mapbox.Point(
    coordinates: mapbox.Position(-74.0060, 40.7128), // NYC
  ),
  northeast: mapbox.Point(
    coordinates: mapbox.Position(-73.9352, 40.7829),
  ),
  infiniteBounds: false,
);

// Start downloading
await DownloadServiceCopyHelper.downloadRegion(
  bounds: bounds,
  zoomLevels: [10, 11, 12],
);
```

### 3. Monitor Download Progress

```dart
// Check if downloading
if (DownloadServiceCopyHelper.isDownloading()) {
  final progress = DownloadServiceCopyHelper.getDownloadProgress();
  print('Download progress: ${(progress * 100).toStringAsFixed(1)}%');
  
  final currentRegion = DownloadServiceCopyHelper.getCurrentDownloadRegion();
  print('Downloading region: $currentRegion');
}
```

### 4. Check Quota Status

```dart
final status = DownloadServiceCopyHelper.getQuotaStatus();

print('Current tiles: ${status.currentTiles}');
print('Max tiles: ${status.maxTiles}');
print('Usage: ${status.usagePercentage.toStringAsFixed(1)}%');

if (status.shouldWarn) {
  print('Warning: Approaching tile limit!');
}

if (status.shouldForceOffline) {
  print('Quota reached - forced offline mode');
}
```

### 5. Manage Auto Downloads

```dart
// Enable automatic downloads
await DownloadServiceCopyHelper.enableAutoDownloads();

// Disable automatic downloads
await DownloadServiceCopyHelper.disableAutoDownloads();
```

### 6. Manage Download Queue

```dart
// Get queue length
final queueLength = DownloadServiceCopyHelper.getQueueLength();
print('Regions in queue: $queueLength');

// Clear all pending downloads
await DownloadServiceCopyHelper.clearAllDownloads();
```

### 7. Advanced: Direct Service Access

```dart
// Get direct access to the service for advanced operations
final service = DownloadServiceCopyHelper.getService();

// Access reactive properties
service.isDownloading.listen((isDownloading) {
  print('Download status changed: $isDownloading');
});

service.totalTilesDownloaded.listen((count) {
  print('Total tiles: $count');
});

service.downloadProgress.listen((progress) {
  print('Progress: ${(progress * 100).toStringAsFixed(1)}%');
});
```

## Configuration

### Set Maximum Tile Limit

```dart
// Set custom tile limit (default: 50,000)
await DownloadServiceCopyHelper.setMaxTileLimit(100000);
```

### Reset Quota

```dart
// Reset tile count and quota (use with caution)
await DownloadServiceCopyHelper.resetQuota();
```

## Complete Example

```dart
import 'package:flutter/material.dart';
import 'package:spacetime/copy/download_service_copy_helper.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

class DownloadCopyExample extends StatefulWidget {
  @override
  _DownloadCopyExampleState createState() => _DownloadCopyExampleState();
}

class _DownloadCopyExampleState extends State<DownloadCopyExample> {
  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    // Initialize the copy service
    await DownloadServiceCopyHelper.initialize(
      tileStore: myTileStore,
      offlineManager: myOfflineManager,
    );

    // Enable auto downloads
    await DownloadServiceCopyHelper.enableAutoDownloads();
  }

  Future<void> _downloadNewYork() async {
    final bounds = mapbox.CoordinateBounds(
      southwest: mapbox.Point(
        coordinates: mapbox.Position(-74.0060, 40.7128),
      ),
      northeast: mapbox.Point(
        coordinates: mapbox.Position(-73.9352, 40.7829),
      ),
      infiniteBounds: false,
    );

    await DownloadServiceCopyHelper.downloadRegion(
      bounds: bounds,
      zoomLevels: [10, 11, 12],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Download Service Copy Example')),
      body: Column(
        children: [
          // Download button
          ElevatedButton(
            onPressed: _downloadNewYork,
            child: Text('Download New York'),
          ),

          // Status display
          StreamBuilder<bool>(
            stream: DownloadServiceCopyHelper.getService().isDownloading.stream,
            builder: (context, snapshot) {
              final isDownloading = snapshot.data ?? false;
              
              if (isDownloading) {
                return Column(
                  children: [
                    Text('Downloading...'),
                    StreamBuilder<double>(
                      stream: DownloadServiceCopyHelper.getService().downloadProgress.stream,
                      builder: (context, progressSnapshot) {
                        final progress = progressSnapshot.data ?? 0.0;
                        return LinearProgressIndicator(value: progress);
                      },
                    ),
                  ],
                );
              }
              
              return Text('Ready');
            },
          ),

          // Quota status
          Text('Total tiles: ${DownloadServiceCopyHelper.getTotalTilesDownloaded()}'),
        ],
      ),
    );
  }
}
```

## Important Notes

1. **Independence**: The copy service is completely independent from the original service
2. **Separate Storage**: Uses separate SharedPreferences keys to avoid conflicts
3. **Parallel Operation**: Can run alongside the original service without interference
4. **Testing**: Perfect for testing new features or configurations
5. **Production Ready**: Fully functional and can be used in production if needed

## Troubleshooting

### Service Not Initialized Error

```dart
// Make sure to initialize before use
if (!DownloadServiceCopyHelper.isInitialized()) {
  await DownloadServiceCopyHelper.initialize(
    tileStore: myTileStore,
    offlineManager: myOfflineManager,
  );
}
```

### Quota Reached

```dart
// Check quota status
final status = DownloadServiceCopyHelper.getQuotaStatus();
if (status.shouldForceOffline) {
  // Either reset quota or increase limit
  await DownloadServiceCopyHelper.setMaxTileLimit(100000);
  // OR
  await DownloadServiceCopyHelper.resetQuota();
}
```

## Migration from Original Service

If you want to migrate from the original service to the copy:

1. Replace all imports:
   ```dart
   // Old
   import 'package:spacetime/services/background_tile_download_service.dart';
   
   // New
   import 'package:spacetime/copy/download_service_copy_helper.dart';
   ```

2. Update service access:
   ```dart
   // Old
   final service = BackgroundTileDownloadService.instance;
   
   // New
   final service = DownloadServiceCopyHelper.getService();
   ```

3. Update initialization:
   ```dart
   // Old
   await BackgroundTileDownloadService.instance.initialize(...);
   
   // New
   await DownloadServiceCopyHelper.initialize(...);
   ```

## License

Same as the main SpaceTime application.

