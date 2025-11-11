#!/usr/bin/env node

/**
 * Main entry point for Mapbox Tile Downloader
 */

const path = require('path');
const fs = require('fs');
const { loadJSON } = require('./src/utils');
const StateManager = require('./src/state');
const TileDownloader = require('./src/downloader');

/**
 * Display Get Started screen
 */
function showGetStartedScreen() {
  console.clear();
  console.log('\n');
  console.log('╔════════════════════════════════════════════════════════════════╗');
  console.log('║                                                                ║');
  console.log('║          🚀 MAPBOX TILES DOWNLOADER - GET STARTED 🚀          ║');
  console.log('║                                                                ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  console.log('\n');
  console.log('📍 Welcome to Mapbox Tiles Downloader!');
  console.log('   Download offline map tiles automatically\n');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('📋 CURRENT CONFIGURATION:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  // Load and display config
  const configPath = path.join(__dirname, 'config.json');
  const config = loadJSON(configPath);

  console.log(`   🗺️  Map Style:        ${config.mapbox.style}`);
  console.log(`   📐 Tile Size:        ${config.mapbox.tileSize}x${config.mapbox.tileSize} ${config.mapbox.retina}`);
  console.log(`   🌍 Area:             N:${config.download.bounds.north}, S:${config.download.bounds.south}`);
  console.log(`                        E:${config.download.bounds.east}, W:${config.download.bounds.west}`);
  console.log(`   🔍 Zoom Levels:      ${config.download.zoomLevels.join(', ')}`);
  console.log(`   ⚡ Concurrent DLs:    ${config.download.maxConcurrentDownloads}`);
  console.log(`   📊 Quota Limit:      ${config.quota.maxTilesPerDownload} tiles per zoom level`);
  console.log(`   ⏰ Cron Schedule:    ${config.cron.scheduleDescription} (${config.cron.enabled ? 'Enabled' : 'Disabled'})`);

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('🎯 WHAT WILL HAPPEN:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  console.log('   ✅ Download map tiles for configured area');
  console.log('   ✅ Save tiles to ./tiles directory');
  console.log('   ✅ Track progress in state.json');
  console.log('   ✅ Resume from last position if interrupted');
  console.log('   ✅ Auto-switch to smaller tiles if quota exceeded');

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('💡 QUICK COMMANDS:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  console.log('   npm start          - Download tiles (you\'re here!)');
  console.log('   npm run status     - Check download progress');
  console.log('   npm run cron       - Start automated downloads');
  console.log('   npm run reset      - Reset state or delete tiles');

  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('📚 DOCUMENTATION:');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');
  console.log('   README.md          - Full documentation');
  console.log('   QUICKSTART.md      - Quick start guide');
  console.log('   GET_STARTED.md     - This guide in detail');

  console.log('\n╔════════════════════════════════════════════════════════════════╗');
  console.log('║                  🎬 STARTING DOWNLOAD NOW...                   ║');
  console.log('╚════════════════════════════════════════════════════════════════╝\n');

  // Small delay for user to read
  return new Promise(resolve => setTimeout(resolve, 2000));
}

// Load configuration
const configPath = path.join(__dirname, 'config.json');
const config = loadJSON(configPath);

if (!config.mapbox || !config.download) {
  console.error('Error: Invalid configuration file');
  console.error('Please check config.json');
  process.exit(1);
}

// Initialize state manager
const stateManager = new StateManager(
  path.join(__dirname, config.output.stateFile)
);

/**
 * Main function
 */
async function main() {
  try {
    // Always show Get Started screen
    await showGetStartedScreen();

    // Always start downloading
    const downloader = new TileDownloader(config, stateManager);
    await downloader.download();

    console.log('\n╔════════════════════════════════════════════════════════════════╗');
    console.log('║                  ✅ DOWNLOAD COMPLETED! ✅                     ║');
    console.log('╚════════════════════════════════════════════════════════════════╝\n');
    console.log('📊 Run "npm run status" to view detailed statistics.');
    console.log('📁 Tiles saved to: ./tiles/');
    console.log('💾 State saved to: ./state.json\n');

    process.exit(0);
  } catch (err) {
    console.error('\n❌ Fatal error:', err.message);
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}

module.exports = { main };

