# Get Started in 3 Minutes! 🚀

The fastest way to start downloading Mapbox tiles.

## Quick Commands

```bash
# 1. Install
cd mapbox_tiles_downloader
npm install

# 2. Test
npm test

# 3. Download
npm start

# 4. Check Status
npm run status

# 5. Automate (Optional)
npm run cron
```

## That's It! 🎉

Your tiles will be downloaded to the `tiles/` directory.

## What Just Happened?

1. **npm install** - Installed dependencies (node-cron, dotenv)
2. **npm test** - Verified your configuration
3. **npm start** - Started downloading tiles
4. **npm run status** - Showed download progress
5. **npm run cron** - Started automated downloads

## Default Configuration

The project comes pre-configured with:
- **Area:** San Francisco Bay Area
- **Zoom Levels:** 8, 9, 10, 11, 12, 13, 14
- **Style:** Mapbox Streets
- **Tile Size:** 512x512 @2x (retina)
- **Cron Schedule:** Every 6 hours
- **Quota:** 750 tiles per zoom level

## Customize Your Download

Edit `config.json`:

```json
{
  "download": {
    "bounds": {
      "north": 37.8324,   // Change these
      "south": 37.7049,   // to your
      "east": -122.3482,  // desired
      "west": -122.5270   // area
    },
    "zoomLevels": [10, 11, 12, 13]  // Adjust zoom levels
  }
}
```

**Find Your Coordinates:**
1. Go to https://boundingbox.klokantech.com/
2. Draw a box around your area
3. Select "CSV" format
4. Copy the coordinates

## Understanding the Output

```
tiles/
├── 8/              # Zoom level 8
│   ├── 40/         # X coordinate
│   │   ├── 95.png  # Tile at 8/40/95
│   │   └── 96.png  # Tile at 8/40/96
│   └── 41/
└── 9/              # Zoom level 9
    └── ...
```

## Common Use Cases

### 1. Download a City

```json
"bounds": {
  "north": 37.8324,
  "south": 37.7049,
  "east": -122.3482,
  "west": -122.5270
},
"zoomLevels": [10, 11, 12, 13]
```

**Result:** ~5,000 tiles, 10-20 minutes, 100-300 MB

### 2. Download a Neighborhood

```json
"bounds": {
  "north": 37.8024,
  "south": 37.7749,
  "east": -122.3882,
  "west": -122.4294
},
"zoomLevels": [12, 13, 14]
```

**Result:** ~2,000 tiles, 5-10 minutes, 50-100 MB

### 3. Download a Country (Overview)

```json
"bounds": {
  "north": 49.0,
  "south": 25.0,
  "east": -66.0,
  "west": -125.0
},
"zoomLevels": [3, 4, 5, 6, 7]
```

**Result:** ~3,000 tiles, 10-15 minutes, 50-150 MB

## Quota Management (Automatic!)

When a zoom level has more than 750 tiles:
```
⚠ Zoom level 14 has 2,496 tiles (exceeds quota of 750)
  Switching to fallback: 256px tiles
```

The system automatically uses smaller tiles. No action needed!

## Running as Background Service

### Using PM2 (Recommended)

```bash
# Install PM2
npm install -g pm2

# Start service
pm2 start src/cron.js --name mapbox-downloader

# Save configuration
pm2 save

# Enable auto-start
pm2 startup
```

### Monitor Service

```bash
pm2 status              # Check status
pm2 logs mapbox-downloader  # View logs
pm2 restart mapbox-downloader  # Restart
pm2 stop mapbox-downloader     # Stop
```

## Checking Progress

```bash
npm run status
```

Output:
```
Overall Progress:
  Total Zoom Levels:      7
  Completed Zoom Levels:  3
  Downloaded Tiles:       8,456
  Progress:               55.48%

Zoom Level Details:
  Zoom | Total Tiles | Downloaded | Status
  8    | 156         | 156        | ✓ Done
  9    | 624         | 624        | ✓ Done
  10   | 2,496       | 2,496      | ✓ Done
  11   | 9,984       | 5,180      | ⏳ Pending
```

## Resuming Downloads

If you stop the download (Ctrl+C), just run it again:

```bash
npm start
```

It will:
- Skip completed zoom levels ✓
- Skip already downloaded tiles ✓
- Continue where it left off ✓

## Resetting

```bash
npm run reset
```

Options:
1. Reset state only (keep tiles)
2. Reset state and delete all tiles
3. Reset specific zoom level
4. Cancel

## Troubleshooting

### Downloads are slow
```json
"maxConcurrentDownloads": 10  // Increase from 5
```

### Rate limit errors
```json
"maxConcurrentDownloads": 2   // Decrease from 5
```

### Want to start over
```bash
npm run reset
# Choose option 2
```

## Next Steps

1. ✅ **Installed** - Dependencies installed
2. ✅ **Configured** - Area and zoom levels set
3. ✅ **Downloaded** - Tiles downloading
4. ⏳ **Automate** - Set up cron for continuous downloads
5. ⏳ **Integrate** - Use tiles in your Flutter app

## Integration with Flutter

After downloading:

```bash
# Copy tiles to Flutter assets
cp -r tiles ../assets/map_tiles

# Update pubspec.yaml
# assets:
#   - assets/map_tiles/
```

## Documentation

- **Full Guide:** `README.md`
- **Quick Start:** `QUICKSTART.md`
- **Installation:** `INSTALL.md`
- **Project Info:** `PROJECT_SUMMARY.md`

## Commands Cheat Sheet

| Command | What It Does |
|---------|--------------|
| `npm install` | Install dependencies |
| `npm test` | Test configuration |
| `npm start` | Download tiles once |
| `npm run cron` | Start automated downloads |
| `npm run status` | Check progress |
| `npm run reset` | Reset state/tiles |

## Tips

1. **Start small** - Test with a small area first
2. **Use cron** - For large downloads, use automated scheduling
3. **Monitor progress** - Check status regularly
4. **Backup state.json** - Preserves your progress
5. **Use PM2** - For production deployments

## Need Help?

- Run `npm test` to verify configuration
- Run `npm run status` to check progress
- Check `README.md` for detailed documentation
- Review `QUICKSTART.md` for examples

## Success! 🎉

You're now downloading Mapbox tiles automatically!

The tiles will be saved in the `tiles/` directory in a format compatible with most offline map libraries.

Happy mapping! 🗺️

