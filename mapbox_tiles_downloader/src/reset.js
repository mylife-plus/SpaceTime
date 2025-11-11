#!/usr/bin/env node

/**
 * Reset download state and optionally delete downloaded tiles
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { loadJSON } = require('./utils');
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
 * Create readline interface
 */
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

/**
 * Ask a question
 * @param {string} question - Question to ask
 * @returns {Promise<string>} User's answer
 */
function ask(question) {
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      resolve(answer);
    });
  });
}

/**
 * Delete directory recursively
 * @param {string} dirPath - Directory path
 */
function deleteDirectory(dirPath) {
  if (fs.existsSync(dirPath)) {
    fs.readdirSync(dirPath).forEach((file) => {
      const curPath = path.join(dirPath, file);
      if (fs.lstatSync(curPath).isDirectory()) {
        deleteDirectory(curPath);
      } else {
        fs.unlinkSync(curPath);
      }
    });
    fs.rmdirSync(dirPath);
  }
}

/**
 * Reset state
 */
async function resetState() {
  console.log('╔════════════════════════════════════════════════════════════════╗');
  console.log('║         Mapbox Tile Downloader - Reset Utility                ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log('This utility will help you reset the download state.');
  console.log('');
  
  // Show current state
  const stats = stateManager.getStats();
  console.log('Current State:');
  console.log(`  Total Zoom Levels:     ${stats.totalZoomLevels}`);
  console.log(`  Completed Zoom Levels: ${stats.completedZoomLevels}`);
  console.log(`  Downloaded Tiles:      ${stats.downloadedTiles}`);
  console.log(`  Last Run:              ${stats.lastRun || 'Never'}`);
  console.log('');
  
  // Ask what to reset
  console.log('What would you like to reset?');
  console.log('  1. Reset state only (keep downloaded tiles)');
  console.log('  2. Reset state and delete all downloaded tiles');
  console.log('  3. Reset specific zoom level');
  console.log('  4. Cancel');
  console.log('');
  
  const choice = await ask('Enter your choice (1-4): ');
  console.log('');
  
  switch (choice.trim()) {
    case '1':
      // Reset state only
      const confirm1 = await ask('Are you sure you want to reset the state? (yes/no): ');
      if (confirm1.toLowerCase() === 'yes') {
        stateManager.reset();
        console.log('✓ State reset successfully!');
        console.log('  Downloaded tiles are preserved.');
      } else {
        console.log('Reset cancelled.');
      }
      break;
      
    case '2':
      // Reset state and delete tiles
      const confirm2 = await ask('⚠ WARNING: This will delete ALL downloaded tiles! Are you sure? (yes/no): ');
      if (confirm2.toLowerCase() === 'yes') {
        const doubleConfirm = await ask('Type "DELETE" to confirm: ');
        if (doubleConfirm === 'DELETE') {
          stateManager.reset();
          const outputDir = path.join(__dirname, '..', config.output.directory);
          deleteDirectory(outputDir);
          console.log('✓ State reset and tiles deleted successfully!');
        } else {
          console.log('Reset cancelled.');
        }
      } else {
        console.log('Reset cancelled.');
      }
      break;
      
    case '3':
      // Reset specific zoom level
      console.log('Available zoom levels:', config.download.zoomLevels.join(', '));
      const zoomInput = await ask('Enter zoom level to reset: ');
      const zoom = parseInt(zoomInput);
      
      if (config.download.zoomLevels.includes(zoom)) {
        const confirm3 = await ask(`Reset zoom level ${zoom}? (yes/no): `);
        if (confirm3.toLowerCase() === 'yes') {
          stateManager.resetZoomLevel(zoom);
          
          const deleteTiles = await ask('Delete downloaded tiles for this zoom level? (yes/no): ');
          if (deleteTiles.toLowerCase() === 'yes') {
            const zoomDir = path.join(__dirname, '..', config.output.directory, zoom.toString());
            deleteDirectory(zoomDir);
            console.log(`✓ Zoom level ${zoom} reset and tiles deleted!`);
          } else {
            console.log(`✓ Zoom level ${zoom} reset (tiles preserved)!`);
          }
        } else {
          console.log('Reset cancelled.');
        }
      } else {
        console.log('Invalid zoom level.');
      }
      break;
      
    case '4':
      console.log('Reset cancelled.');
      break;
      
    default:
      console.log('Invalid choice.');
      break;
  }
  
  console.log('');
  rl.close();
}

// Run if executed directly
if (require.main === module) {
  resetState().catch((err) => {
    console.error('Error:', err.message);
    rl.close();
    process.exit(1);
  });
}

module.exports = { resetState };

