#!/usr/bin/env node

/**
 * Display download status and statistics
 */

const path = require('path');
const { loadJSON, formatBytes, formatDuration, getDirectorySize, countDownloadedTiles } = require('./utils');
const StateManager = require('./state');

// Load configuration
const configPath = path.join(__dirname, '..', 'config.json');
const config = loadJSON(configPath);

if (!config.mapbox || !config.download) {
  console.error('Error: Invalid configuration file');
  process.exit(1);
}

// Initialize state manager
const stateManager = new StateManager(
  path.join(__dirname, '..', config.output.stateFile)
);

/**
 * Display status
 */
function displayStatus() {
  console.log('╔════════════════════════════════════════════════════════════════╗');
  console.log('║         Mapbox Tile Downloader - Status Report                ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  console.log('');
  
  // Get statistics
  const stats = stateManager.getStats();
  
  // Configuration info
  console.log('Configuration:');
  console.log(`  Mapbox Style:   ${config.mapbox.style}`);
  console.log(`  Tile Size:      ${config.mapbox.tileSize}x${config.mapbox.tileSize}${config.mapbox.retina}`);
  console.log(`  Zoom Levels:    ${config.download.zoomLevels.join(', ')}`);
  console.log(`  Max Quota:      ${config.quota.maxTilesPerDownload} tiles per zoom level`);
  console.log(`  Cron Schedule:  ${config.cron.schedule} (${config.cron.scheduleDescription})`);
  console.log(`  Cron Enabled:   ${config.cron.enabled ? 'Yes' : 'No'}`);
  console.log('');
  
  // Overall progress
  console.log('Overall Progress:');
  console.log(`  Total Zoom Levels:      ${stats.totalZoomLevels}`);
  console.log(`  Completed Zoom Levels:  ${stats.completedZoomLevels}`);
  console.log(`  Total Tiles:            ${stats.totalTiles}`);
  console.log(`  Downloaded Tiles:       ${stats.downloadedTiles}`);
  console.log(`  Failed Tiles:           ${stats.totalFailed}`);
  console.log(`  Progress:               ${stats.progress}%`);
  console.log(`  Last Run:               ${stats.lastRun || 'Never'}`);
  console.log(`  Quota Exceeded:         ${stats.quotaExceeded ? 'Yes' : 'No'}`);
  console.log(`  Used Fallback:          ${stats.usedFallback ? 'Yes' : 'No'}`);
  console.log('');
  
  // Zoom level details
  console.log('Zoom Level Details:');
  console.log('  ' + '-'.repeat(66));
  console.log('  Zoom | Total Tiles | Downloaded | Failed | Skipped | Status');
  console.log('  ' + '-'.repeat(66));
  
  for (const zoom of config.download.zoomLevels) {
    const zoomState = stateManager.state.zoomLevels[zoom];
    
    if (zoomState) {
      const status = zoomState.completed ? '✓ Done' : '⏳ Pending';
      const total = zoomState.totalTiles.toString().padEnd(11);
      const downloaded = zoomState.downloaded.toString().padEnd(10);
      const failed = zoomState.failed.toString().padEnd(6);
      const skipped = zoomState.skipped.toString().padEnd(7);
      
      console.log(`  ${zoom.toString().padEnd(4)} | ${total} | ${downloaded} | ${failed} | ${skipped} | ${status}`);
    } else {
      console.log(`  ${zoom.toString().padEnd(4)} | Not started yet`);
    }
  }
  
  console.log('  ' + '-'.repeat(66));
  console.log('');
  
  // Storage info
  const outputDir = path.join(__dirname, '..', config.output.directory);
  const dirSize = getDirectorySize(outputDir);
  const actualTileCount = countDownloadedTiles(outputDir);
  
  console.log('Storage:');
  console.log(`  Output Directory:  ${config.output.directory}`);
  console.log(`  Total Size:        ${formatBytes(dirSize)}`);
  console.log(`  Actual Tile Count: ${actualTileCount}`);
  console.log('');
  
  // Recent download history
  if (stateManager.state.downloadHistory.length > 0) {
    console.log('Recent Download History (Last 5 sessions):');
    console.log('  ' + '-'.repeat(66));
    console.log('  Timestamp            | Downloaded | Failed | Duration');
    console.log('  ' + '-'.repeat(66));
    
    const recentHistory = stateManager.state.downloadHistory.slice(-5).reverse();
    for (const session of recentHistory) {
      const timestamp = new Date(session.timestamp).toLocaleString().padEnd(20);
      const downloaded = (session.downloaded || 0).toString().padEnd(10);
      const failed = (session.failed || 0).toString().padEnd(6);
      const duration = formatDuration(session.duration || 0);
      
      console.log(`  ${timestamp} | ${downloaded} | ${failed} | ${duration}`);
    }
    
    console.log('  ' + '-'.repeat(66));
    console.log('');
  }
  
  // Next steps
  const incompleteZoomLevels = stateManager.getIncompleteZoomLevels(config.download.zoomLevels);
  
  if (incompleteZoomLevels.length > 0) {
    console.log('Next Steps:');
    console.log(`  ${incompleteZoomLevels.length} zoom level(s) remaining: ${incompleteZoomLevels.join(', ')}`);
    console.log('  Run "npm run download" to continue downloading');
    console.log('  Run "npm run cron" to start automated downloads');
  } else {
    console.log('✓ All zoom levels completed!');
  }
  
  console.log('');
}

// Run if executed directly
if (require.main === module) {
  displayStatus();
}

module.exports = { displayStatus };

