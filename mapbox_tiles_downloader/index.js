#!/usr/bin/env node

/**
 * Main entry point for Mapbox Tile Downloader
 */

const path = require('path');
const { loadJSON } = require('./src/utils');
const StateManager = require('./src/state');
const TileDownloader = require('./src/downloader');

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
    const downloader = new TileDownloader(config, stateManager);
    await downloader.download();
    
    console.log('Download completed successfully!');
    console.log('Run "npm run status" to view detailed statistics.');
    
    process.exit(0);
  } catch (err) {
    console.error('Fatal error:', err.message);
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}

module.exports = { main };

