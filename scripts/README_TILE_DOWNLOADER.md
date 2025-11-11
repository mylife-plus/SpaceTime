# Mapbox Tile Downloader

This Node.js script downloads Mapbox map tiles for offline use. It downloads tiles for a specific geographic area across multiple zoom levels and saves them in a structured directory format.

## Features

- ✅ Downloads Mapbox Streets style tiles
- ✅ Supports multiple zoom levels (1-22)
- ✅ Configurable geographic bounds
- ✅ Parallel downloads with concurrency control
- ✅ Automatic retry on failure
- ✅ Rate limit handling
- ✅ Skip already downloaded tiles
- ✅ Progress tracking and statistics
- ✅ Organized directory structure (z/x/y.png)

## Prerequisites

- Node.js (v12 or higher)
- Valid Mapbox access token (already configured in the script)

## Installation

No additional packages required! The script uses only Node.js built-in modules:
- `https` - for downloading tiles
- `fs` - for file system operations
- `path` - for path manipulation

## Usage

### Basic Usage

```bash
# Run the script from the project root
node scripts/download_mapbox_tiles.js
```

### Configuration

Edit the configuration section in `scripts/download_mapbox_tiles.js`:

#### 1. Geographic Bounds

Define the area you want to download:

```javascript
const BOUNDS = {
  north: 37.8324,   // Northern latitude
  south: 37.7049,   // Southern latitude
  east: -122.3482,  // Eastern longitude
  west: -122.5270   // Western longitude
};
```

**Example Bounds:**

- **San Francisco Bay Area:**
  ```javascript
  { north: 37.8324, south: 37.7049, east: -122.3482, west: -122.5270 }
  ```

- **New York City:**
  ```javascript
  { north: 40.9176, south: 40.4774, east: -73.7004, west: -74.2591 }
  ```

- **London:**
  ```javascript
  { north: 51.6723, south: 51.2868, east: 0.3340, west: -0.5103 }
  ```

- **World (small zoom only!):**
  ```javascript
  { north: 85, south: -85, east: 180, west: -180 }
  ```

#### 2. Zoom Levels

Choose which zoom levels to download (higher = more detail, more tiles):

```javascript
const ZOOM_LEVELS = [8, 9, 10, 11, 12, 13, 14];
```

**Zoom Level Guide:**
- **0-2**: World view (very few tiles)
- **3-5**: Country/continent view
- **6-8**: State/region view
- **9-11**: City view
- **12-14**: Neighborhood view (recommended for most use cases)
- **15-17**: Street view (many tiles!)
- **18-22**: Building view (HUGE number of tiles!)

**⚠️ Warning:** Higher zoom levels generate exponentially more tiles!
- Zoom 10: ~100 tiles for a city
- Zoom 14: ~10,000 tiles for a city
- Zoom 18: ~1,000,000+ tiles for a city

#### 3. Tile Size and Quality

```javascript
const TILE_SIZE = 512;      // 256 or 512
const RETINA = '@2x';       // '@2x' for retina, '' for standard
```

- **Standard (256px):** Smaller files, lower quality
- **Retina (512px @2x):** Larger files, higher quality (recommended)

#### 4. Download Settings

```javascript
const MAX_CONCURRENT_DOWNLOADS = 5;  // Parallel downloads (1-10)
const RETRY_ATTEMPTS = 3;            // Retry failed downloads
const RETRY_DELAY = 1000;            // Wait 1s between retries
```

#### 5. Output Directory

```javascript
const OUTPUT_DIR = path.join(__dirname, '..', 'map_tiles');
```

Default: `./map_tiles/` in the project root

## Output Structure

Downloaded tiles are organized in the standard TMS (Tile Map Service) format:

```
map_tiles/
├── 8/              # Zoom level 8
│   ├── 40/         # X coordinate
│   │   ├── 95.png  # Y coordinate
│   │   ├── 96.png
│   │   └── ...
│   └── 41/
│       └── ...
├── 9/              # Zoom level 9
│   └── ...
└── ...
```

This structure is compatible with most offline map libraries.

## Examples

### Example 1: Download Small City Area

```javascript
// Configuration for a small city (e.g., downtown area)
const BOUNDS = {
  north: 37.8024,
  south: 37.7749,
  east: -122.3882,
  west: -122.4294
};
const ZOOM_LEVELS = [10, 11, 12, 13, 14];
```

**Estimated tiles:** ~2,000-5,000 tiles
**Estimated time:** 5-15 minutes
**Estimated size:** 50-200 MB

### Example 2: Download Large Metropolitan Area

```javascript
// Configuration for a large metro area
const BOUNDS = {
  north: 37.9,
  south: 37.6,
  east: -122.2,
  west: -122.6
};
const ZOOM_LEVELS = [8, 9, 10, 11, 12, 13];
```

**Estimated tiles:** ~10,000-30,000 tiles
**Estimated time:** 30-90 minutes
**Estimated size:** 200-800 MB

### Example 3: Download Country Overview

```javascript
// Configuration for country-level overview
const BOUNDS = {
  north: 49.0,    // Northern US border
  south: 25.0,    // Southern US border
  east: -66.0,    // Eastern US border
  west: -125.0    // Western US border
};
const ZOOM_LEVELS = [3, 4, 5, 6, 7, 8];
```

**Estimated tiles:** ~5,000-15,000 tiles
**Estimated time:** 15-45 minutes
**Estimated size:** 100-400 MB

## Tile Count Estimation

Use this formula to estimate tile count:

```
tiles_at_zoom = (width_degrees / 360) * (height_degrees / 180) * (2^zoom)^2
```

Or use the script's built-in calculator (it shows total tiles before downloading).

## Tips and Best Practices

### 1. Start Small
Always test with a small area and few zoom levels first:
```javascript
const ZOOM_LEVELS = [10, 11, 12];  // Just 3 levels
```

### 2. Monitor Progress
The script shows real-time progress:
```
✓ Downloaded tile 12/345/678
✓ Tile 12/345/679 already exists, skipping
⚠ Error downloading tile 12/345/680, retrying (1/3)...
```

### 3. Resume Downloads
If the script is interrupted, just run it again. It will skip already downloaded tiles.

### 4. Respect Rate Limits
Mapbox has rate limits. The script handles this automatically, but if you see many rate limit warnings, reduce `MAX_CONCURRENT_DOWNLOADS`.

### 5. Check Disk Space
High zoom levels can use significant disk space:
- Zoom 14: ~500 MB for a city
- Zoom 16: ~5 GB for a city
- Zoom 18: ~50+ GB for a city

### 6. Use Appropriate Zoom Levels
For most mobile apps:
- **Minimum zoom:** 8-10 (city overview)
- **Maximum zoom:** 14-16 (street detail)

## Troubleshooting

### Problem: "Rate limit exceeded"
**Solution:** Reduce `MAX_CONCURRENT_DOWNLOADS` to 2-3

### Problem: "Too many tiles"
**Solution:** Reduce zoom levels or geographic bounds

### Problem: "Network errors"
**Solution:** Check internet connection, increase `RETRY_ATTEMPTS`

### Problem: "Tiles not downloading"
**Solution:** Verify Mapbox access token is valid

### Problem: "Out of disk space"
**Solution:** Reduce zoom levels or clear old tiles

## Advanced Usage

### Change Map Style

Edit the `MAPBOX_STYLE` constant:

```javascript
// Available styles:
const MAPBOX_STYLE = 'mapbox/streets-v12';      // Streets (default)
const MAPBOX_STYLE = 'mapbox/outdoors-v12';     // Outdoors
const MAPBOX_STYLE = 'mapbox/light-v11';        // Light
const MAPBOX_STYLE = 'mapbox/dark-v11';         // Dark
const MAPBOX_STYLE = 'mapbox/satellite-v9';     // Satellite
const MAPBOX_STYLE = 'mapbox/satellite-streets-v12';  // Satellite + Streets
```

### Custom Output Directory

```javascript
const OUTPUT_DIR = '/path/to/custom/directory';
```

### Download Specific Tiles

Modify the `getTilesForBounds` function to return specific tile coordinates.

## Integration with Flutter App

After downloading tiles, you can use them in your Flutter app:

1. Copy `map_tiles/` to your Flutter assets
2. Update `pubspec.yaml`:
   ```yaml
   assets:
     - map_tiles/
   ```
3. Configure Mapbox to use local tiles (see offline map documentation)

## License

This script is for use with valid Mapbox accounts. Respect Mapbox's Terms of Service.

## Support

For issues or questions, refer to:
- Mapbox API Documentation: https://docs.mapbox.com/api/maps/raster-tiles/
- Mapbox Tile Specifications: https://docs.mapbox.com/help/glossary/zoom-level/

