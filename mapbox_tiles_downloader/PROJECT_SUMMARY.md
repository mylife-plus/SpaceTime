# Mapbox Tiles Downloader - Project Summary

## Overview

A complete, production-ready Node.js application for downloading Mapbox map tiles with intelligent quota management, cron scheduling, and automatic fallback mechanisms.

## Key Features

### 1. Intelligent Quota Management
- Automatically detects when a zoom level exceeds 750 tiles
- Switches to 256px tiles (fallback mode) instead of 512px
- Prevents API quota violations
- Transparent to the user

### 2. Cron Job Scheduling
- Runs automatically on a configurable schedule
- Default: Every 6 hours
- Customizable via cron syntax
- Can run as a background service

### 3. Resume Support
- Tracks download progress in `state.json`
- Skips completed zoom levels
- Skips already downloaded tiles
- Can be interrupted and resumed anytime

### 4. State Management
- Persistent state across runs
- Tracks completion status per zoom level
- Records download history
- Provides detailed statistics

### 5. Concurrent Downloads
- Downloads multiple tiles in parallel
- Configurable concurrency (default: 5)
- Respects rate limits
- Automatic retry on failure

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Mapbox Tiles Downloader                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   index.js   │  │   cron.js    │  │  status.js   │     │
│  │ (One-time)   │  │ (Scheduled)  │  │  (Monitor)   │     │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘     │
│         │                 │                  │             │
│         └─────────────────┼──────────────────┘             │
│                           │                                │
│                  ┌────────▼────────┐                       │
│                  │  downloader.js  │                       │
│                  │  (Core Logic)   │                       │
│                  └────────┬────────┘                       │
│                           │                                │
│         ┌─────────────────┼─────────────────┐             │
│         │                 │                 │             │
│    ┌────▼────┐      ┌────▼────┐      ┌────▼────┐         │
│    │ state.js│      │utils.js │      │reset.js │         │
│    │(Progress)      │(Helpers)│      │(Cleanup)│         │
│    └─────────┘      └─────────┘      └─────────┘         │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                     Data Persistence                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  config.json │  │  state.json  │  │   tiles/     │     │
│  │(Settings)    │  │  (Progress)  │  │  (Output)    │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## File Structure

```
mapbox_tiles_downloader/
├── config.json              # Main configuration
├── package.json             # Node.js project file
├── index.js                 # Main entry point
├── test.js                  # Configuration test
├── .gitignore              # Git ignore rules
├── .env.example            # Environment variables template
│
├── src/
│   ├── utils.js            # Utility functions
│   ├── state.js            # State management
│   ├── downloader.js       # Core download logic
│   ├── cron.js             # Cron scheduler
│   ├── status.js           # Status reporter
│   └── reset.js            # Reset utility
│
├── docs/
│   ├── README.md           # Full documentation
│   ├── QUICKSTART.md       # Quick start guide
│   ├── CHANGELOG.md        # Version history
│   └── PROJECT_SUMMARY.md  # This file
│
├── tiles/                  # Downloaded tiles (auto-created)
│   ├── 8/
│   │   └── x/
│   │       └── y.png
│   └── ...
│
└── state.json              # Download state (auto-created)
```

## Workflow

### 1. Initial Setup
```bash
cd mapbox_tiles_downloader
npm install
npm test  # Verify configuration
```

### 2. Configure
Edit `config.json`:
- Set geographic bounds
- Choose zoom levels
- Configure cron schedule
- Set quota limits

### 3. Run
```bash
# One-time download
npm start

# Automated cron
npm run cron

# Check status
npm run status
```

### 4. Monitor
```bash
npm run status
```

### 5. Reset (if needed)
```bash
npm run reset
```

## How Quota Management Works

### Normal Mode (≤ 750 tiles)
```
Zoom Level 10: 156 tiles
→ Uses 512x512@2x tiles
→ Downloads normally
```

### Fallback Mode (> 750 tiles)
```
Zoom Level 14: 2,496 tiles
→ Exceeds quota (750)
→ Switches to 256x256 tiles
→ Downloads with smaller tiles
```

### Benefits
- Prevents API quota violations
- Automatic, no user intervention
- Transparent fallback
- Still provides coverage

## State Management

### State File Structure
```json
{
  "version": "1.0.0",
  "lastRun": "2024-01-15T10:30:00.000Z",
  "totalDownloaded": 8456,
  "totalFailed": 12,
  "zoomLevels": {
    "10": {
      "totalTiles": 156,
      "downloaded": 156,
      "completed": true
    }
  },
  "downloadHistory": [...],
  "quotaExceeded": false,
  "usedFallback": false
}
```

### State Tracking
- Per-zoom-level progress
- Download history
- Completion status
- Quota usage
- Fallback usage

## Cron Scheduling

### How It Works
1. Loads configuration
2. Checks for incomplete zoom levels
3. Downloads missing tiles
4. Updates state
5. Waits for next scheduled run
6. Repeats

### Schedule Examples
```javascript
"0 */6 * * *"   // Every 6 hours
"0 0 * * *"     // Daily at midnight
"0 2 * * *"     // Daily at 2 AM
"*/30 * * * *"  // Every 30 minutes
"0 0 * * 0"     // Weekly on Sunday
```

### Running as Service
```bash
# Using PM2
pm2 start src/cron.js --name mapbox-downloader
pm2 save
pm2 startup

# Using systemd
sudo systemctl enable mapbox-downloader
sudo systemctl start mapbox-downloader
```

## API Integration

### Mapbox Tile URL Format
```
https://api.mapbox.com/styles/v1/{style}/tiles/{size}/{z}/{x}/{y}{retina}?access_token={token}
```

### Example
```
https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/10/163/395@2x?access_token=pk.xxx
```

### Parameters
- `style`: mapbox/streets-v12
- `size`: 512 or 256
- `z`: Zoom level (8-14)
- `x`: Tile X coordinate
- `y`: Tile Y coordinate
- `retina`: @2x or empty
- `token`: Your Mapbox access token

## Output Format

### TMS Structure
```
tiles/
├── 8/              # Zoom level
│   ├── 40/         # X coordinate
│   │   ├── 95.png  # Y coordinate
│   │   ├── 96.png
│   │   └── ...
│   └── 41/
│       └── ...
└── ...
```

### Compatibility
- Standard TMS format
- Compatible with most offline map libraries
- Can be used with Mapbox GL JS
- Can be served via HTTP server

## Performance

### Download Speed
- 5 concurrent downloads (default)
- ~2 tiles/second average
- ~7,200 tiles/hour
- Adjustable via `maxConcurrentDownloads`

### Storage
- 512px tiles: ~50 KB average
- 256px tiles: ~15 KB average
- Zoom 14 city: ~500 MB
- Zoom 16 city: ~5 GB

### Time Estimates
- Small city (5,000 tiles): 10-20 minutes
- Large metro (20,000 tiles): 1-2 hours
- Country overview (10,000 tiles): 30-60 minutes

## Error Handling

### Retry Logic
- 3 retry attempts (configurable)
- 1 second delay between retries
- Exponential backoff for rate limits

### Rate Limiting
- Detects HTTP 429 responses
- Waits 5 seconds before retry
- Reduces concurrency if needed

### Network Errors
- Automatic retry
- Partial file cleanup
- State preservation

## Use Cases

### 1. Offline Mobile App
- Download tiles for app's coverage area
- Use cron to keep tiles updated
- Integrate with Flutter/React Native

### 2. Emergency Services
- Pre-download critical areas
- Ensure offline availability
- Regular updates via cron

### 3. Field Operations
- Download operational areas
- Offline map access
- Periodic updates

### 4. Development/Testing
- Local tile cache
- Faster development
- Reduced API calls

## Integration with Flutter App

### 1. Download Tiles
```bash
cd mapbox_tiles_downloader
npm start
```

### 2. Copy to Flutter Assets
```bash
cp -r tiles ../assets/map_tiles
```

### 3. Update pubspec.yaml
```yaml
assets:
  - assets/map_tiles/
```

### 4. Configure Mapbox
Use local tiles in your Flutter app's Mapbox configuration.

## Best Practices

1. **Start Small**: Test with small area first
2. **Monitor Progress**: Use `npm run status` regularly
3. **Use Cron**: For large downloads, use automated scheduling
4. **Backup State**: Keep `state.json` backed up
5. **Check Disk Space**: Monitor storage usage
6. **Respect Quotas**: Let the system handle fallback
7. **Use PM2**: For production deployments
8. **Regular Updates**: Schedule periodic re-downloads

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Rate limits | Reduce `maxConcurrentDownloads` |
| Slow downloads | Increase `maxConcurrentDownloads` |
| Quota exceeded | System handles automatically |
| Out of space | Reduce zoom levels or area |
| Cron not running | Check `cron.enabled` in config |
| Invalid token | Update token in config.json |

## Future Enhancements

- Web dashboard
- Email notifications
- Vector tile support
- Cloud storage integration
- Multi-region support
- Tile validation
- Compression options

## License

MIT License

## Support

- Full documentation: README.md
- Quick start: QUICKSTART.md
- Version history: CHANGELOG.md
- Configuration test: `npm test`
- Status check: `npm run status`

