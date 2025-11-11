# Mapbox Tiles Downloader

An intelligent, automated Node.js application for downloading Mapbox map tiles with cron scheduling, quota management, and automatic fallback to smaller tile sizes.

## Features

✅ **Automated Cron Scheduling** - Runs periodically to download tiles in the background  
✅ **Quota Management** - Automatically switches to smaller tiles if quota (750 tiles) is exceeded  
✅ **Resume Support** - Tracks progress and resumes incomplete downloads  
✅ **Smart State Management** - Remembers which zoom levels are completed  
✅ **Concurrent Downloads** - Downloads multiple tiles in parallel for speed  
✅ **Retry Logic** - Automatically retries failed downloads  
✅ **Rate Limit Handling** - Respects Mapbox API rate limits  
✅ **Detailed Statistics** - Track download progress and history  
✅ **Fallback Mode** - Switches to 256px tiles when 512px exceeds quota  

## Project Structure

```
mapbox_tiles_downloader/
├── config.json              # Configuration file
├── package.json             # Node.js dependencies
├── index.js                 # Main entry point
├── src/
│   ├── utils.js            # Utility functions
│   ├── state.js            # State management
│   ├── downloader.js       # Core download logic
│   ├── cron.js             # Cron scheduler
│   ├── status.js           # Status reporter
│   └── reset.js            # Reset utility
├── tiles/                  # Downloaded tiles (created automatically)
└── state.json              # Download state (created automatically)
```

## Installation

### 1. Navigate to the project directory

```bash
cd mapbox_tiles_downloader
```

### 2. Install dependencies

```bash
npm install
```

This will install:
- `node-cron` - For cron scheduling
- `dotenv` - For environment variables (optional)

## Configuration

Edit `config.json` to customize your download settings:

### Mapbox Settings

```json
"mapbox": {
  "accessToken": "your_mapbox_token_here",
  "style": "mapbox/streets-v12",
  "tileSize": 512,
  "retina": "@2x"
}
```

**Available Styles:**
- `mapbox/streets-v12` - Streets (default)
- `mapbox/outdoors-v12` - Outdoors
- `mapbox/light-v11` - Light
- `mapbox/dark-v11` - Dark
- `mapbox/satellite-v9` - Satellite
- `mapbox/satellite-streets-v12` - Satellite + Streets

### Download Settings

```json
"download": {
  "bounds": {
    "north": 37.8324,
    "south": 37.7049,
    "east": -122.3482,
    "west": -122.5270
  },
  "zoomLevels": [8, 9, 10, 11, 12, 13, 14],
  "maxConcurrentDownloads": 5,
  "retryAttempts": 3,
  "retryDelay": 1000
}
```

**Example Bounds:**
- San Francisco: `{ north: 37.8324, south: 37.7049, east: -122.3482, west: -122.5270 }`
- New York: `{ north: 40.9176, south: 40.4774, east: -73.7004, west: -74.2591 }`
- London: `{ north: 51.6723, south: 51.2868, east: 0.3340, west: -0.5103 }`

### Quota Settings

```json
"quota": {
  "maxTilesPerDownload": 750,
  "fallbackTileSize": 256,
  "fallbackRetina": ""
}
```

When a zoom level has more than 750 tiles, the downloader automatically switches to 256px tiles instead of 512px.

### Cron Settings

```json
"cron": {
  "enabled": true,
  "schedule": "0 */6 * * *",
  "scheduleDescription": "Every 6 hours"
}
```

**Common Cron Schedules:**
- `"0 */6 * * *"` - Every 6 hours
- `"0 */12 * * *"` - Every 12 hours
- `"0 0 * * *"` - Daily at midnight
- `"0 2 * * *"` - Daily at 2 AM
- `"*/30 * * * *"` - Every 30 minutes
- `"0 0 * * 0"` - Weekly on Sunday

## Usage

### One-Time Download

Download tiles once and exit:

```bash
npm start
# or
node index.js
```

### Start Cron Scheduler

Run as a background service that downloads tiles periodically:

```bash
npm run cron
```

This will:
1. Run an initial download immediately
2. Schedule future downloads according to the cron schedule
3. Keep running until you stop it (Ctrl+C)

### Check Status

View download progress and statistics:

```bash
npm run status
```

Output example:
```
Overall Progress:
  Total Zoom Levels:      7
  Completed Zoom Levels:  3
  Total Tiles:            15,234
  Downloaded Tiles:       8,456
  Progress:               55.48%
  Last Run:               2024-01-15T10:30:00.000Z

Zoom Level Details:
  Zoom | Total Tiles | Downloaded | Failed | Skipped | Status
  ------------------------------------------------------------------
  8    | 156         | 156        | 0      | 0       | ✓ Done
  9    | 624         | 624        | 0      | 0       | ✓ Done
  10   | 2,496       | 2,496      | 0      | 0       | ✓ Done
  11   | 9,984       | 5,180      | 0      | 0       | ⏳ Pending
  12   | 39,936      | 0          | 0      | 0       | ⏳ Pending
```

### Reset State

Reset download state or delete tiles:

```bash
npm run reset
```

Options:
1. Reset state only (keep downloaded tiles)
2. Reset state and delete all downloaded tiles
3. Reset specific zoom level
4. Cancel

## How It Works

### 1. Initial Run

When you first run the downloader:
- It reads `config.json` for settings
- Creates `state.json` to track progress
- Downloads tiles for each zoom level sequentially
- Saves progress after each zoom level

### 2. Quota Management

For each zoom level:
- Calculates total tiles needed
- If tiles > 750: switches to 256px tiles (fallback mode)
- If tiles ≤ 750: uses 512px tiles (normal mode)
- Downloads tiles with concurrency control

### 3. Resume Support

If interrupted:
- State is saved after each zoom level
- Next run skips completed zoom levels
- Only downloads incomplete zoom levels
- Skips already downloaded tiles

### 4. Cron Scheduling

When running as cron:
- Checks for incomplete zoom levels
- Downloads missing tiles
- Runs on schedule (e.g., every 6 hours)
- Continues until all zoom levels are complete

## Examples

### Example 1: Small City (Quick Download)

```json
{
  "download": {
    "bounds": {
      "north": 37.8024,
      "south": 37.7749,
      "east": -122.3882,
      "west": -122.4294
    },
    "zoomLevels": [10, 11, 12, 13]
  }
}
```

**Estimated:** ~2,000 tiles, 5-10 minutes, 50-100 MB

### Example 2: Large Metro Area

```json
{
  "download": {
    "bounds": {
      "north": 37.9,
      "south": 37.6,
      "east": -122.2,
      "west": -122.6
    },
    "zoomLevels": [8, 9, 10, 11, 12]
  }
}
```

**Estimated:** ~10,000 tiles, 30-60 minutes, 200-500 MB

### Example 3: Country Overview

```json
{
  "download": {
    "bounds": {
      "north": 49.0,
      "south": 25.0,
      "east": -66.0,
      "west": -125.0
    },
    "zoomLevels": [3, 4, 5, 6, 7, 8]
  }
}
```

**Estimated:** ~5,000 tiles, 15-30 minutes, 100-300 MB

## Running as a Service

### Using PM2 (Recommended)

Install PM2:
```bash
npm install -g pm2
```

Start as service:
```bash
pm2 start src/cron.js --name mapbox-downloader
pm2 save
pm2 startup
```

Monitor:
```bash
pm2 status
pm2 logs mapbox-downloader
```

Stop:
```bash
pm2 stop mapbox-downloader
pm2 delete mapbox-downloader
```

### Using systemd (Linux)

Create service file `/etc/systemd/system/mapbox-downloader.service`:

```ini
[Unit]
Description=Mapbox Tile Downloader
After=network.target

[Service]
Type=simple
User=youruser
WorkingDirectory=/path/to/mapbox_tiles_downloader
ExecStart=/usr/bin/node /path/to/mapbox_tiles_downloader/src/cron.js
Restart=always

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl enable mapbox-downloader
sudo systemctl start mapbox-downloader
sudo systemctl status mapbox-downloader
```

## Output Structure

Downloaded tiles are saved in TMS (Tile Map Service) format:

```
tiles/
├── 8/              # Zoom level
│   ├── 40/         # X coordinate
│   │   ├── 95.png  # Y coordinate
│   │   ├── 96.png
│   │   └── ...
│   └── 41/
│       └── ...
├── 9/
│   └── ...
└── ...
```

This structure is compatible with most offline map libraries.

## Troubleshooting

### Problem: "Rate limit exceeded"

**Solution:** Reduce `maxConcurrentDownloads` in config.json to 2-3

### Problem: "Too many tiles for quota"

**Solution:** The downloader automatically switches to 256px tiles. Check logs for "Switching to fallback" message.

### Problem: "Download keeps failing"

**Solution:** 
- Check internet connection
- Verify Mapbox access token is valid
- Increase `retryAttempts` in config.json

### Problem: "Cron not running"

**Solution:**
- Check `cron.enabled` is `true` in config.json
- Verify cron schedule syntax is valid
- Check logs for errors

### Problem: "Out of disk space"

**Solution:**
- Reduce zoom levels
- Delete old tiles: `npm run reset`
- Check disk space before downloading high zoom levels

## Best Practices

1. **Start Small** - Test with a small area and few zoom levels first
2. **Monitor Progress** - Use `npm run status` to track progress
3. **Use Cron for Large Downloads** - Let it run in background over time
4. **Respect Quotas** - The 750 tile limit helps avoid overwhelming the API
5. **Check Disk Space** - High zoom levels can use significant storage
6. **Use PM2 for Production** - More reliable than running directly

## API Reference

### State File Format

```json
{
  "version": "1.0.0",
  "lastRun": "2024-01-15T10:30:00.000Z",
  "totalDownloaded": 8456,
  "totalFailed": 12,
  "zoomLevels": {
    "8": {
      "totalTiles": 156,
      "downloaded": 156,
      "failed": 0,
      "skipped": 0,
      "completed": true,
      "lastAttempt": "2024-01-15T10:25:00.000Z"
    }
  },
  "downloadHistory": [],
  "quotaExceeded": false,
  "usedFallback": false
}
```

## License

MIT

## Support

For issues or questions:
- Mapbox API Docs: https://docs.mapbox.com/api/maps/raster-tiles/
- Cron Syntax: https://crontab.guru/

