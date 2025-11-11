#!/usr/bin/env node

/**
 * Cron job scheduler for automated tile downloads
 */

const cron = require('node-cron');
const path = require('path');
const { loadJSON } = require('./utils');
const StateManager = require('./state');
const TileDownloader = require('./downloader');

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
 * Run download job
 */
async function runDownloadJob() {
  console.log('\n' + '='.repeat(70));
  console.log(`[${new Date().toISOString()}] Starting scheduled download job...`);
  console.log('='.repeat(70));
  
  try {
    const downloader = new TileDownloader(config, stateManager);
    await downloader.download();
    
    console.log(`[${new Date().toISOString()}] Download job completed successfully`);
  } catch (err) {
    console.error(`[${new Date().toISOString()}] Download job failed:`, err.message);
  }
}

/**
 * Main function
 */
function main() {
  console.log('╔════════════════════════════════════════════════════════════════╗');
  console.log('║         Mapbox Tile Downloader - Cron Scheduler               ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log('Configuration:');
  console.log(`  Cron Schedule:  ${config.cron.schedule} (${config.cron.scheduleDescription})`);
  console.log(`  Enabled:        ${config.cron.enabled}`);
  console.log(`  Output Dir:     ${config.output.directory}`);
  console.log(`  State File:     ${config.output.stateFile}`);
  console.log('');
  
  if (!config.cron.enabled) {
    console.log('⚠ Cron is disabled in configuration. Exiting...');
    process.exit(0);
  }
  
  // Validate cron schedule
  if (!cron.validate(config.cron.schedule)) {
    console.error('Error: Invalid cron schedule:', config.cron.schedule);
    process.exit(1);
  }
  
  console.log('✓ Cron scheduler started');
  console.log(`  Next run will be according to schedule: ${config.cron.schedule}`);
  console.log('  Press Ctrl+C to stop');
  console.log('');
  
  // Run immediately on start (optional)
  console.log('Running initial download job...');
  runDownloadJob();
  
  // Schedule cron job
  const task = cron.schedule(config.cron.schedule, () => {
    runDownloadJob();
  });
  
  // Handle graceful shutdown
  process.on('SIGINT', () => {
    console.log('\n\nReceived SIGINT, stopping cron scheduler...');
    task.stop();
    console.log('Cron scheduler stopped. Goodbye!');
    process.exit(0);
  });
  
  process.on('SIGTERM', () => {
    console.log('\n\nReceived SIGTERM, stopping cron scheduler...');
    task.stop();
    console.log('Cron scheduler stopped. Goodbye!');
    process.exit(0);
  });
}

// Run if executed directly
if (require.main === module) {
  main();
}

module.exports = { runDownloadJob };

