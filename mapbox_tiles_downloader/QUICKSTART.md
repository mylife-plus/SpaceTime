# Quick Start Guide

Get started with Mapbox Tiles Downloader in 5 minutes!

## Step 1: Install Dependencies

```bash
cd mapbox_tiles_downloader
npm install
```

## Step 2: Configure Your Download

Edit `config.json` and set your area:

```json
{
  "download": {
    "bounds": {
      "north": 37.8324,   // Your area's north latitude
      "south": 37.7049,   // Your area's south latitude
      "east": -122.3482,  // Your area's east longitude
      "west": -122.5270   // Your area's west longitude
    },
    "zoomLevels": [10, 11, 12, 13]  // Start with these zoom levels
  }
}
```

**Tip:** Use https://boundingbox.klokantech.com/ to find coordinates for your area.

## Step 3: Run Your First Download

```bash
npm start
```

You'll see output like:
```
╔════════════════════════════════════════════════════════════════╗
║         Mapbox Tile Downloader - Quota Managed                ║
╚════════════════════════════════════════════════════════════════╝

Incomplete zoom levels: 10, 11, 12, 13

======================================================================
Downloading zoom level 10...
======================================================================
Total tiles at zoom 10: 156
✓ Downloaded tile 10/40/95
✓ Downloaded tile 10/40/96
...
```

## Step 4: Check Status

```bash
npm run status
```

Output:
```
Overall Progress:
  Total Zoom Levels:      4
  Completed Zoom Levels:  1
  Downloaded Tiles:       156
  Progress:               25.00%
```

## Step 5: Set Up Automated Downloads (Optional)

To run downloads automatically every 6 hours:

```bash
npm run cron
```

This will:
- Run an initial download now
- Schedule downloads every 6 hours
- Keep running until you press Ctrl+C

## Common Commands

| Command | Description |
|---------|-------------|
| `npm start` | Download tiles once |
| `npm run cron` | Start cron scheduler |
| `npm run status` | Check download progress |
| `npm run reset` | Reset state or delete tiles |

## What Happens Next?

### If Quota is Exceeded

When a zoom level has more than 750 tiles, you'll see:

```
⚠ Zoom level 14 has 2,496 tiles (exceeds quota of 750)
  Switching to fallback: 256px tiles
```

The downloader automatically switches to smaller 256px tiles instead of 512px.

### Resume Downloads

If you stop the download (Ctrl+C), just run it again:

```bash
npm start
```

It will:
- Skip completed zoom levels
- Skip already downloaded tiles
- Continue where it left off

## Customization

### Change Download Area

Edit `config.json`:

```json
"bounds": {
  "north": 40.9176,   // New York
  "south": 40.4774,
  "east": -73.7004,
  "west": -74.2591
}
```

### Change Zoom Levels

```json
"zoomLevels": [8, 9, 10, 11, 12]  // Add or remove levels
```

**Zoom Level Guide:**
- 8-10: City overview
- 11-13: Neighborhood detail
- 14-16: Street detail (many tiles!)

### Change Cron Schedule

```json
"cron": {
  "schedule": "0 2 * * *",  // Daily at 2 AM
  "scheduleDescription": "Daily at 2 AM"
}
```

**Common Schedules:**
- `"0 */6 * * *"` - Every 6 hours
- `"0 0 * * *"` - Daily at midnight
- `"0 2 * * *"` - Daily at 2 AM
- `"0 0 * * 0"` - Weekly on Sunday

## Troubleshooting

### Downloads are slow

Increase concurrent downloads in `config.json`:

```json
"maxConcurrentDownloads": 10  // Default is 5
```

### Rate limit errors

Decrease concurrent downloads:

```json
"maxConcurrentDownloads": 2
```

### Want to start over

```bash
npm run reset
# Choose option 2 to delete all tiles and reset state
```

## Next Steps

1. **Monitor Progress:** Run `npm run status` periodically
2. **Set Up Cron:** Use `npm run cron` for automated downloads
3. **Use PM2:** For production, use PM2 to run as a service (see README.md)
4. **Integrate with App:** Copy downloaded tiles to your Flutter app

## Example: Download San Francisco

```json
{
  "download": {
    "bounds": {
      "north": 37.8324,
      "south": 37.7049,
      "east": -122.3482,
      "west": -122.5270
    },
    "zoomLevels": [10, 11, 12, 13, 14]
  }
}
```

Run:
```bash
npm start
```

Expected:
- ~5,000 tiles
- 10-20 minutes
- 100-300 MB

## Example: Download New York City

```json
{
  "download": {
    "bounds": {
      "north": 40.9176,
      "south": 40.4774,
      "east": -73.7004,
      "west": -74.2591
    },
    "zoomLevels": [9, 10, 11, 12, 13]
  }
}
```

Run:
```bash
npm start
```

Expected:
- ~15,000 tiles
- 30-60 minutes
- 300-800 MB

## Tips

1. **Start small** - Test with zoom levels 10-12 first
2. **Check disk space** - High zoom levels use lots of storage
3. **Use cron for large areas** - Let it download over time
4. **Monitor with status** - Check progress regularly
5. **Backup state.json** - Preserves your progress

## Need Help?

- Check the full README.md for detailed documentation
- Use `npm run status` to see what's happening
- Use `npm run reset` if you need to start over

Happy downloading! 🗺️

