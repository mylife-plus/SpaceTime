#!/usr/bin/env node

/**
 * Mapbox Tile Downloader
 * 
 * This script downloads Mapbox map tiles for a specific geographic area
 * across different zoom levels and saves them to a local directory.
 * 
 * Usage:
 *   node scripts/download_mapbox_tiles.js
 * 
 * Configuration:
 *   - Edit the BOUNDS and ZOOM_LEVELS constants below
 *   - Tiles are saved to: ./map_tiles/
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

// ============================================================================
// CONFIGURATION
// ============================================================================

// Mapbox Access Token (from .env file)
const MAPBOX_ACCESS_TOKEN = 'pk.eyJ1IjoibW9vc2lhc2QiLCJhIjoiY21jZTV6MzFzMG9wMjJqcXdmY3VjZWV1biJ9.3FMDFTkqzcRTEVBIxyuXeA';

// Mapbox Style - Using Streets style
const MAPBOX_STYLE = 'mapbox/streets-v12';

// Geographic bounds to download (example: San Francisco area)
// Format: { north, south, east, west }
const BOUNDS = {
  north: 37.8324,   // Northern latitude
  south: 37.7049,   // Southern latitude
  east: -122.3482,  // Eastern longitude
  west: -122.5270   // Western longitude
};

// Zoom levels to download (1-22, where higher = more detail)
// Note: Higher zoom levels = exponentially more tiles!
const ZOOM_LEVELS = [8, 9, 10, 11, 12, 13, 14];

// Output directory for downloaded tiles
const OUTPUT_DIR = path.join(__dirname, '..', 'map_tiles');

// Tile size (standard is 512x512 for retina, 256x256 for standard)
const TILE_SIZE = 512;
const RETINA = '@2x'; // Use '@2x' for retina, '' for standard

// Download settings
const MAX_CONCURRENT_DOWNLOADS = 5; // Number of parallel downloads
const RETRY_ATTEMPTS = 3;
const RETRY_DELAY = 1000; // milliseconds

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Convert latitude/longitude to tile coordinates at a given zoom level
 * @param {number} lat - Latitude
 * @param {number} lon - Longitude
 * @param {number} zoom - Zoom level
 * @returns {object} Tile coordinates {x, y}
 */
function latLonToTile(lat, lon, zoom) {
  const n = Math.pow(2, zoom);
  const x = Math.floor((lon + 180) / 360 * n);
  const latRad = lat * Math.PI / 180;
  const y = Math.floor((1 - Math.log(Math.tan(latRad) + 1 / Math.cos(latRad)) / Math.PI) / 2 * n);
  return { x, y };
}

/**
 * Get all tile coordinates for a bounding box at a specific zoom level
 * @param {object} bounds - Geographic bounds
 * @param {number} zoom - Zoom level
 * @returns {array} Array of tile coordinates
 */
function getTilesForBounds(bounds, zoom) {
  const topLeft = latLonToTile(bounds.north, bounds.west, zoom);
  const bottomRight = latLonToTile(bounds.south, bounds.east, zoom);
  
  const tiles = [];
  for (let x = topLeft.x; x <= bottomRight.x; x++) {
    for (let y = topLeft.y; y <= bottomRight.y; y++) {
      tiles.push({ x, y, z: zoom });
    }
  }
  
  return tiles;
}

/**
 * Create directory if it doesn't exist
 * @param {string} dirPath - Directory path
 */
function ensureDirectoryExists(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

/**
 * Download a single tile
 * @param {object} tile - Tile coordinates {x, y, z}
 * @param {number} attempt - Current retry attempt
 * @returns {Promise} Promise that resolves when download is complete
 */
function downloadTile(tile, attempt = 1) {
  return new Promise((resolve, reject) => {
    const { x, y, z } = tile;
    
    // Construct Mapbox tile URL
    // Format: https://api.mapbox.com/styles/v1/{style}/tiles/{tileSize}/{z}/{x}/{y}{retina}?access_token={token}
    const url = `https://api.mapbox.com/styles/v1/${MAPBOX_STYLE}/tiles/${TILE_SIZE}/${z}/${x}/${y}${RETINA}?access_token=${MAPBOX_ACCESS_TOKEN}`;
    
    // Create directory structure: map_tiles/z/x/
    const tileDir = path.join(OUTPUT_DIR, z.toString(), x.toString());
    ensureDirectoryExists(tileDir);
    
    // File path: map_tiles/z/x/y.png
    const filePath = path.join(tileDir, `${y}.png`);
    
    // Skip if file already exists
    if (fs.existsSync(filePath)) {
      console.log(`✓ Tile ${z}/${x}/${y} already exists, skipping`);
      resolve({ tile, status: 'skipped' });
      return;
    }
    
    // Download the tile
    https.get(url, (response) => {
      if (response.statusCode === 200) {
        const fileStream = fs.createWriteStream(filePath);
        response.pipe(fileStream);
        
        fileStream.on('finish', () => {
          fileStream.close();
          console.log(`✓ Downloaded tile ${z}/${x}/${y}`);
          resolve({ tile, status: 'downloaded' });
        });
        
        fileStream.on('error', (err) => {
          fs.unlink(filePath, () => {}); // Delete partial file
          
          if (attempt < RETRY_ATTEMPTS) {
            console.log(`⚠ Error downloading tile ${z}/${x}/${y}, retrying (${attempt}/${RETRY_ATTEMPTS})...`);
            setTimeout(() => {
              downloadTile(tile, attempt + 1).then(resolve).catch(reject);
            }, RETRY_DELAY);
          } else {
            console.error(`✗ Failed to download tile ${z}/${x}/${y}: ${err.message}`);
            reject(err);
          }
        });
      } else if (response.statusCode === 429) {
        // Rate limit exceeded
        console.log(`⚠ Rate limit exceeded for tile ${z}/${x}/${y}, waiting...`);
        setTimeout(() => {
          downloadTile(tile, attempt).then(resolve).catch(reject);
        }, 5000);
      } else {
        const err = new Error(`HTTP ${response.statusCode}`);
        
        if (attempt < RETRY_ATTEMPTS) {
          console.log(`⚠ Error downloading tile ${z}/${x}/${y} (${response.statusCode}), retrying (${attempt}/${RETRY_ATTEMPTS})...`);
          setTimeout(() => {
            downloadTile(tile, attempt + 1).then(resolve).catch(reject);
          }, RETRY_DELAY);
        } else {
          console.error(`✗ Failed to download tile ${z}/${x}/${y}: HTTP ${response.statusCode}`);
          reject(err);
        }
      }
    }).on('error', (err) => {
      if (attempt < RETRY_ATTEMPTS) {
        console.log(`⚠ Network error for tile ${z}/${x}/${y}, retrying (${attempt}/${RETRY_ATTEMPTS})...`);
        setTimeout(() => {
          downloadTile(tile, attempt + 1).then(resolve).catch(reject);
        }, RETRY_DELAY);
      } else {
        console.error(`✗ Failed to download tile ${z}/${x}/${y}: ${err.message}`);
        reject(err);
      }
    });
  });
}

/**
 * Download tiles with concurrency control
 * @param {array} tiles - Array of tile coordinates
 * @returns {Promise} Promise that resolves when all downloads are complete
 */
async function downloadTilesWithConcurrency(tiles) {
  const results = {
    downloaded: 0,
    skipped: 0,
    failed: 0,
    total: tiles.length
  };
  
  const queue = [...tiles];
  const inProgress = new Set();
  
  return new Promise((resolve) => {
    const processNext = () => {
      // Check if we're done
      if (queue.length === 0 && inProgress.size === 0) {
        resolve(results);
        return;
      }
      
      // Start new downloads up to the concurrency limit
      while (queue.length > 0 && inProgress.size < MAX_CONCURRENT_DOWNLOADS) {
        const tile = queue.shift();
        const promise = downloadTile(tile)
          .then((result) => {
            if (result.status === 'downloaded') results.downloaded++;
            if (result.status === 'skipped') results.skipped++;
          })
          .catch(() => {
            results.failed++;
          })
          .finally(() => {
            inProgress.delete(promise);
            processNext();
          });
        
        inProgress.add(promise);
      }
    };
    
    processNext();
  });
}

/**
 * Calculate total number of tiles for all zoom levels
 * @returns {number} Total tile count
 */
function calculateTotalTiles() {
  let total = 0;
  for (const zoom of ZOOM_LEVELS) {
    const tiles = getTilesForBounds(BOUNDS, zoom);
    total += tiles.length;
  }
  return total;
}

// ============================================================================
// MAIN EXECUTION
// ============================================================================

async function main() {
  console.log('╔════════════════════════════════════════════════════════════════╗');
  console.log('║           Mapbox Tile Downloader (Streets Style)              ║');
  console.log('╚════════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log('Configuration:');
  console.log(`  Style:        ${MAPBOX_STYLE}`);
  console.log(`  Tile Size:    ${TILE_SIZE}x${TILE_SIZE}${RETINA}`);
  console.log(`  Bounds:       N:${BOUNDS.north}, S:${BOUNDS.south}, E:${BOUNDS.east}, W:${BOUNDS.west}`);
  console.log(`  Zoom Levels:  ${ZOOM_LEVELS.join(', ')}`);
  console.log(`  Output Dir:   ${OUTPUT_DIR}`);
  console.log(`  Concurrency:  ${MAX_CONCURRENT_DOWNLOADS} parallel downloads`);
  console.log('');
  
  // Calculate total tiles
  const totalTiles = calculateTotalTiles();
  console.log(`Total tiles to download: ${totalTiles}`);
  console.log('');
  
  // Ensure output directory exists
  ensureDirectoryExists(OUTPUT_DIR);
  
  // Download tiles for each zoom level
  const startTime = Date.now();
  let grandTotal = { downloaded: 0, skipped: 0, failed: 0 };
  
  for (const zoom of ZOOM_LEVELS) {
    console.log(`\n${'='.repeat(70)}`);
    console.log(`Downloading zoom level ${zoom}...`);
    console.log('='.repeat(70));
    
    const tiles = getTilesForBounds(BOUNDS, zoom);
    console.log(`Tiles at zoom ${zoom}: ${tiles.length}`);
    
    const results = await downloadTilesWithConcurrency(tiles);
    
    grandTotal.downloaded += results.downloaded;
    grandTotal.skipped += results.skipped;
    grandTotal.failed += results.failed;
    
    console.log(`\nZoom ${zoom} complete:`);
    console.log(`  Downloaded: ${results.downloaded}`);
    console.log(`  Skipped:    ${results.skipped}`);
    console.log(`  Failed:     ${results.failed}`);
  }
  
  const endTime = Date.now();
  const duration = ((endTime - startTime) / 1000).toFixed(2);
  
  console.log('\n' + '='.repeat(70));
  console.log('Download Complete!');
  console.log('='.repeat(70));
  console.log(`Total Downloaded: ${grandTotal.downloaded}`);
  console.log(`Total Skipped:    ${grandTotal.skipped}`);
  console.log(`Total Failed:     ${grandTotal.failed}`);
  console.log(`Total Time:       ${duration}s`);
  console.log(`Output Directory: ${OUTPUT_DIR}`);
  console.log('');
}

// Run the script
main().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});

