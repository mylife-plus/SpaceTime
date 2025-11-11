#!/usr/bin/env node

/**
 * Test script to verify configuration and setup
 */

const path = require('path');
const { loadJSON, calculateTotalTiles, formatBytes } = require('./src/utils');

console.log('╔════════════════════════════════════════════════════════════════╗');
console.log('║         Mapbox Tile Downloader - Configuration Test           ║');
console.log('╚════════════════════════════════════════════════════════════════╝');
console.log('');

// Load configuration
const configPath = path.join(__dirname, 'config.json');
const config = loadJSON(configPath);

if (!config.mapbox || !config.download) {
  console.error('❌ Error: Invalid configuration file');
  console.error('   Please check config.json');
  process.exit(1);
}

console.log('✓ Configuration file loaded successfully');
console.log('');

// Validate Mapbox token
if (!config.mapbox.accessToken || config.mapbox.accessToken === 'your_mapbox_token_here') {
  console.error('❌ Error: Mapbox access token not configured');
  console.error('   Please set your token in config.json');
  process.exit(1);
}

console.log('✓ Mapbox access token configured');
console.log('');

// Display configuration
console.log('Configuration Summary:');
console.log('─'.repeat(70));
console.log('');

console.log('Mapbox Settings:');
console.log(`  Style:       ${config.mapbox.style}`);
console.log(`  Tile Size:   ${config.mapbox.tileSize}x${config.mapbox.tileSize}${config.mapbox.retina}`);
console.log(`  Token:       ${config.mapbox.accessToken.substring(0, 20)}...`);
console.log('');

console.log('Download Area:');
console.log(`  North:       ${config.download.bounds.north}°`);
console.log(`  South:       ${config.download.bounds.south}°`);
console.log(`  East:        ${config.download.bounds.east}°`);
console.log(`  West:        ${config.download.bounds.west}°`);
console.log('');

console.log('Zoom Levels:');
console.log(`  Levels:      ${config.download.zoomLevels.join(', ')}`);
console.log(`  Count:       ${config.download.zoomLevels.length} levels`);
console.log('');

console.log('Download Settings:');
console.log(`  Concurrent:  ${config.download.maxConcurrentDownloads} parallel downloads`);
console.log(`  Retry:       ${config.download.retryAttempts} attempts`);
console.log(`  Delay:       ${config.download.retryDelay}ms between retries`);
console.log('');

console.log('Quota Settings:');
console.log(`  Max Tiles:   ${config.quota.maxTilesPerDownload} tiles per zoom level`);
console.log(`  Fallback:    ${config.quota.fallbackTileSize}x${config.quota.fallbackTileSize}${config.quota.fallbackRetina}`);
console.log('');

console.log('Cron Settings:');
console.log(`  Enabled:     ${config.cron.enabled ? 'Yes' : 'No'}`);
console.log(`  Schedule:    ${config.cron.schedule}`);
console.log(`  Description: ${config.cron.scheduleDescription}`);
console.log('');

console.log('Output Settings:');
console.log(`  Directory:   ${config.output.directory}`);
console.log(`  State File:  ${config.output.stateFile}`);
console.log('');

// Calculate tile estimates
console.log('─'.repeat(70));
console.log('Tile Estimates:');
console.log('─'.repeat(70));
console.log('');

let totalTiles = 0;
let quotaExceededLevels = [];

for (const zoom of config.download.zoomLevels) {
  const tiles = calculateTotalTiles(config.download.bounds, [zoom]);
  totalTiles += tiles;
  
  const exceeds = tiles > config.quota.maxTilesPerDownload;
  const status = exceeds ? '⚠ Exceeds quota (will use fallback)' : '✓ Within quota';
  
  if (exceeds) {
    quotaExceededLevels.push(zoom);
  }
  
  console.log(`  Zoom ${zoom.toString().padEnd(2)}: ${tiles.toString().padStart(6)} tiles  ${status}`);
}

console.log('');
console.log(`Total Tiles: ${totalTiles.toLocaleString()}`);
console.log('');

// Estimate download size and time
const avgTileSize512 = 50 * 1024; // 50 KB average for 512px tiles
const avgTileSize256 = 15 * 1024; // 15 KB average for 256px tiles

let estimatedSize = 0;
for (const zoom of config.download.zoomLevels) {
  const tiles = calculateTotalTiles(config.download.bounds, [zoom]);
  const tileSize = tiles > config.quota.maxTilesPerDownload ? avgTileSize256 : avgTileSize512;
  estimatedSize += tiles * tileSize;
}

const estimatedTime = totalTiles / config.download.maxConcurrentDownloads * 0.5; // ~0.5s per tile

console.log('Estimates:');
console.log(`  Download Size:  ${formatBytes(estimatedSize)}`);
console.log(`  Download Time:  ${Math.ceil(estimatedTime / 60)} minutes (approximate)`);
console.log('');

// Warnings
if (quotaExceededLevels.length > 0) {
  console.log('⚠ Warnings:');
  console.log(`  ${quotaExceededLevels.length} zoom level(s) exceed quota: ${quotaExceededLevels.join(', ')}`);
  console.log(`  These will automatically use ${config.quota.fallbackTileSize}px tiles instead of ${config.mapbox.tileSize}px`);
  console.log('');
}

if (totalTiles > 50000) {
  console.log('⚠ Warning: Large download detected!');
  console.log(`  ${totalTiles.toLocaleString()} tiles will take significant time and storage`);
  console.log('  Consider reducing zoom levels or area size for testing');
  console.log('');
}

// Next steps
console.log('─'.repeat(70));
console.log('Next Steps:');
console.log('─'.repeat(70));
console.log('');
console.log('1. Review the configuration above');
console.log('2. Run "npm start" to begin downloading');
console.log('3. Run "npm run status" to check progress');
console.log('4. Run "npm run cron" for automated downloads');
console.log('');
console.log('✓ Configuration test complete!');
console.log('');

