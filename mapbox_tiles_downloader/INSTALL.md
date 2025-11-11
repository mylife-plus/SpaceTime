# Installation Guide

Complete installation and setup guide for Mapbox Tiles Downloader.

## Prerequisites

### Required
- **Node.js** v12 or higher
- **npm** (comes with Node.js)
- **Mapbox Access Token** (free tier available)

### Optional
- **PM2** (for running as a service)
- **Git** (for version control)

## Step-by-Step Installation

### 1. Verify Node.js Installation

```bash
node --version
# Should show v12.0.0 or higher

npm --version
# Should show 6.0.0 or higher
```

If not installed, download from: https://nodejs.org/

### 2. Navigate to Project Directory

```bash
cd /path/to/SpaceTime/mapbox_tiles_downloader
```

### 3. Install Dependencies

```bash
npm install
```

This installs:
- `node-cron` - Cron job scheduler
- `dotenv` - Environment variable loader

### 4. Verify Installation

```bash
npm test
```

You should see:
```
╔════════════════════════════════════════════════════════════════╗
║         Mapbox Tile Downloader - Configuration Test           ║
╚════════════════════════════════════════════════════════════════╝

✓ Configuration file loaded successfully
✓ Mapbox access token configured
...
```

## Configuration

### 1. Get Mapbox Access Token

1. Go to https://account.mapbox.com/
2. Sign up or log in
3. Go to "Access tokens"
4. Copy your default public token (starts with `pk.`)

### 2. Update config.json

The token is already configured in `config.json`, but you can update it:

```json
{
  "mapbox": {
    "accessToken": "pk.your_token_here"
  }
}
```

### 3. Configure Download Area

Edit `config.json` to set your area:

```json
{
  "download": {
    "bounds": {
      "north": 37.8324,
      "south": 37.7049,
      "east": -122.3482,
      "west": -122.5270
    },
    "zoomLevels": [10, 11, 12, 13]
  }
}
```

**Finding Coordinates:**
- Use https://boundingbox.klokantech.com/
- Select "CSV" format
- Copy coordinates to config.json

### 4. Test Configuration

```bash
npm test
```

Review the output to ensure everything is configured correctly.

## First Run

### 1. Start Download

```bash
npm start
```

### 2. Monitor Progress

In another terminal:
```bash
npm run status
```

### 3. Stop Download (if needed)

Press `Ctrl+C` in the download terminal.

The download can be resumed later by running `npm start` again.

## Setting Up Cron (Automated Downloads)

### Option 1: Run Directly

```bash
npm run cron
```

This runs in the foreground. Press `Ctrl+C` to stop.

### Option 2: Run with PM2 (Recommended)

#### Install PM2

```bash
npm install -g pm2
```

#### Start Service

```bash
pm2 start src/cron.js --name mapbox-downloader
```

#### Save Configuration

```bash
pm2 save
```

#### Enable Auto-Start on Boot

```bash
pm2 startup
# Follow the instructions shown
```

#### Monitor Service

```bash
pm2 status
pm2 logs mapbox-downloader
pm2 monit
```

#### Stop Service

```bash
pm2 stop mapbox-downloader
```

#### Restart Service

```bash
pm2 restart mapbox-downloader
```

#### Remove Service

```bash
pm2 delete mapbox-downloader
```

### Option 3: Run with systemd (Linux)

#### Create Service File

```bash
sudo nano /etc/systemd/system/mapbox-downloader.service
```

#### Add Configuration

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
RestartSec=10

[Install]
WantedBy=multi-user.target
```

#### Enable and Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable mapbox-downloader
sudo systemctl start mapbox-downloader
```

#### Check Status

```bash
sudo systemctl status mapbox-downloader
```

#### View Logs

```bash
sudo journalctl -u mapbox-downloader -f
```

#### Stop Service

```bash
sudo systemctl stop mapbox-downloader
```

## Verification

### 1. Check Downloaded Tiles

```bash
ls -la tiles/
```

You should see directories for each zoom level:
```
tiles/
├── 10/
├── 11/
├── 12/
└── 13/
```

### 2. Check State File

```bash
cat state.json
```

You should see download progress:
```json
{
  "version": "1.0.0",
  "lastRun": "2024-01-15T10:30:00.000Z",
  "totalDownloaded": 156,
  ...
}
```

### 3. Check Status

```bash
npm run status
```

## Troubleshooting Installation

### Problem: "npm: command not found"

**Solution:** Install Node.js from https://nodejs.org/

### Problem: "Cannot find module 'node-cron'"

**Solution:** Run `npm install` in the project directory

### Problem: "Permission denied"

**Solution:** 
```bash
# On Linux/Mac
sudo chown -R $USER:$USER .
chmod -R 755 .

# Or run with sudo (not recommended)
sudo npm install
```

### Problem: "EACCES: permission denied, mkdir"

**Solution:**
```bash
# Fix npm permissions
mkdir ~/.npm-global
npm config set prefix '~/.npm-global'
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
source ~/.bashrc
```

### Problem: "Invalid configuration file"

**Solution:** Verify config.json syntax:
```bash
node -e "console.log(JSON.parse(require('fs').readFileSync('config.json')))"
```

## Updating

### Update Dependencies

```bash
npm update
```

### Update Configuration

Edit `config.json` as needed, then restart:
```bash
# If using PM2
pm2 restart mapbox-downloader

# If using systemd
sudo systemctl restart mapbox-downloader

# If running directly
# Stop with Ctrl+C, then run again
npm run cron
```

## Uninstallation

### 1. Stop Service

```bash
# If using PM2
pm2 delete mapbox-downloader

# If using systemd
sudo systemctl stop mapbox-downloader
sudo systemctl disable mapbox-downloader
sudo rm /etc/systemd/system/mapbox-downloader.service
```

### 2. Remove Files

```bash
cd ..
rm -rf mapbox_tiles_downloader
```

## Next Steps

After installation:

1. **Configure your area** - Edit `config.json`
2. **Test configuration** - Run `npm test`
3. **Start downloading** - Run `npm start`
4. **Set up cron** - Run `npm run cron` or use PM2
5. **Monitor progress** - Run `npm run status`

## Getting Help

- Read the full documentation: `README.md`
- Quick start guide: `QUICKSTART.md`
- Project summary: `PROJECT_SUMMARY.md`
- Test configuration: `npm test`
- Check status: `npm run status`

## Common Commands Reference

| Command | Description |
|---------|-------------|
| `npm install` | Install dependencies |
| `npm test` | Test configuration |
| `npm start` | Download tiles once |
| `npm run cron` | Start cron scheduler |
| `npm run status` | Check progress |
| `npm run reset` | Reset state/tiles |
| `pm2 start src/cron.js --name mapbox-downloader` | Start with PM2 |
| `pm2 status` | Check PM2 status |
| `pm2 logs mapbox-downloader` | View PM2 logs |

## Support

For issues or questions:
- Check the troubleshooting section above
- Review the documentation files
- Verify configuration with `npm test`
- Check logs with `pm2 logs` or `journalctl`

