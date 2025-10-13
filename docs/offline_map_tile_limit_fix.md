# Offline Map Tile Limit Fix Guide

## 🚨 Problem Description

**Error**: `The tile region 'spacetime-tile-region' can't be loaded because it would increase the number of Maps tiles to 1409, which is beyond the maximum allowed 750 tiles.`

**Root Cause**: Mapbox has a hard limit of **750 tiles per tile region** for offline downloads. The current configuration exceeds this limit.

## 📊 Current Configuration Issues

```dart
// Current settings in offline_map_service.dart (PROBLEMATIC)
static const int _minZoom = 2;   // Too low - includes global tiles
static const int _maxZoom = 16;  // Too high - includes very detailed tiles  
static const int _requiredTileThreshold = 700; // Close to 750 limit
```

**Why this fails:**
- **Zoom 2-16**: Covers 15 zoom levels (2,3,4,5,6,7,8,9,10,11,12,13,14,15,16)
- **Wide zoom range**: Exponentially increases tile count
- **Large region**: Current region covers ~300km area (Islamabad to Lahore)

## 🔧 Solution Options

### Option 1: Optimize Zoom Levels (Recommended)
```dart
// Recommended settings for 700+ tiles within 750 limit
static const int _minZoom = 8;   // Start at city level
static const int _maxZoom = 14;  // End at street level
static const int _requiredTileThreshold = 700; // Keep current threshold
```

**Benefits:**
- ✅ Stays within 750 tile limit
- ✅ Covers useful zoom levels (city to street detail)
- ✅ Good balance of coverage vs detail

### Option 2: Reduce Region Size
```dart
// Keep zoom levels but reduce geographic area
static const int _minZoom = 2;
static const int _maxZoom = 16;
static const int _requiredTileThreshold = 400; // Reduce threshold

// In _getDownloadRegionGeometry(), use smaller region:
final offset = 0.3; // ~30km radius instead of 100km
```

### Option 3: Multiple Smaller Regions
```dart
// Download multiple smaller regions sequentially
// Each region stays under 750 tiles
// Total coverage can exceed 750 tiles across regions
```

## 🎯 Recommended Fix (Option 1)

### Step 1: Update Zoom Configuration
```dart
// In lib/app/services/offline_map_service.dart
static const int _minZoom = 8;   // City level detail
static const int _maxZoom = 14;  // Street level detail  
static const int _requiredTileThreshold = 700; // Keep current
```

### Step 2: Test Tile Count
The zoom range 8-14 with current region should download ~600-700 tiles.

### Step 3: Adjust Region if Needed
If still over 750 tiles, reduce region size:
```dart
// In _getDownloadRegionGeometry()
final offset = 0.7; // Reduce from 0.9 to 0.7 (~70km radius)
```

## 📈 Tile Count Estimation

| Zoom Range | Region Size | Estimated Tiles | Status |
|------------|-------------|-----------------|---------|
| 2-16 (15 levels) | 100km | 1409+ | ❌ Exceeds limit |
| 8-14 (7 levels) | 100km | ~650 | ✅ Within limit |
| 8-16 (9 levels) | 70km | ~750 | ⚠️ At limit |
| 6-14 (9 levels) | 50km | ~500 | ✅ Safe margin |

## 🔍 Understanding Zoom Levels

| Zoom | Description | Use Case |
|------|-------------|----------|
| 2-5 | Country/State | Navigation overview |
| 6-8 | City/Region | City navigation |
| 9-12 | Neighborhood | Local navigation |
| 13-16 | Street/Building | Walking directions |

**Recommendation**: Focus on zoom levels 8-14 for optimal offline experience.

## 🛠️ Implementation Steps

### 1. Apply the Fix
```bash
# Edit the file
vim lib/app/services/offline_map_service.dart

# Change these lines:
static const int _minZoom = 8;   # Was: 2
static const int _maxZoom = 14;  # Was: 16
```

### 2. Clear Existing Data
```dart
// In main.dart, temporarily uncomment:
await _clearAppData(); // This clears previous download attempts
```

### 3. Test Download
```bash
flutter run --debug
# Monitor logs for tile count
```

### 4. Verify Success
Look for logs like:
```
[OfflineMapService] 📦 Starting tile region download...
[OfflineMapService] 🗺️ Tile region progress: 100% (650/650 tiles)
[OfflineMapService] ✅ Tile region download completed
```

## 🚀 Advanced Solutions

### Multiple Region Strategy
If you need wider coverage:

1. **Download multiple smaller regions**
2. **Each region < 750 tiles**
3. **Sequential downloads**
4. **Combined coverage > 750 tiles total**

```dart
// Example: Download 3 regions of 500 tiles each = 1500 total tiles
final regions = [
  _getIslamabadRegion(),  // 500 tiles
  _getLahoreRegion(),     // 500 tiles  
  _getRawalpindiRegion(), // 500 tiles
];

for (final region in regions) {
  await _downloadSingleRegion(region);
}
```

### Dynamic Zoom Selection
```dart
// Adjust zoom based on region size
int getOptimalMaxZoom(double regionSizeKm) {
  if (regionSizeKm > 100) return 12;  // Large region, lower detail
  if (regionSizeKm > 50) return 14;   // Medium region, medium detail
  return 16;                          // Small region, high detail
}
```

## ✅ Quick Fix Summary

**Immediate solution:**
1. Change `_minZoom = 8` and `_maxZoom = 14`
2. Keep `_requiredTileThreshold = 700`
3. Clear app data and retry download
4. Should download ~650 tiles successfully

This provides excellent offline coverage for city-to-street level navigation while staying within Mapbox limits.
