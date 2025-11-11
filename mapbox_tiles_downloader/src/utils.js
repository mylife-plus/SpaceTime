/**
 * Utility functions for tile calculations and file operations
 */

const fs = require('fs');
const path = require('path');

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
 * @param {object} bounds - Geographic bounds {north, south, east, west}
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
 * Load JSON file
 * @param {string} filePath - Path to JSON file
 * @param {object} defaultValue - Default value if file doesn't exist
 * @returns {object} Parsed JSON object
 */
function loadJSON(filePath, defaultValue = {}) {
  try {
    if (fs.existsSync(filePath)) {
      const data = fs.readFileSync(filePath, 'utf8');
      return JSON.parse(data);
    }
  } catch (err) {
    console.error(`Error loading JSON from ${filePath}:`, err.message);
  }
  return defaultValue;
}

/**
 * Save JSON file
 * @param {string} filePath - Path to JSON file
 * @param {object} data - Data to save
 */
function saveJSON(filePath, data) {
  try {
    ensureDirectoryExists(path.dirname(filePath));
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
  } catch (err) {
    console.error(`Error saving JSON to ${filePath}:`, err.message);
  }
}

/**
 * Check if a tile file exists
 * @param {string} outputDir - Output directory
 * @param {object} tile - Tile coordinates {x, y, z}
 * @returns {boolean} True if tile exists
 */
function tileExists(outputDir, tile) {
  const filePath = path.join(outputDir, tile.z.toString(), tile.x.toString(), `${tile.y}.png`);
  return fs.existsSync(filePath);
}

/**
 * Get tile file path
 * @param {string} outputDir - Output directory
 * @param {object} tile - Tile coordinates {x, y, z}
 * @returns {string} File path
 */
function getTilePath(outputDir, tile) {
  return path.join(outputDir, tile.z.toString(), tile.x.toString(), `${tile.y}.png`);
}

/**
 * Calculate total tiles for bounds and zoom levels
 * @param {object} bounds - Geographic bounds
 * @param {array} zoomLevels - Array of zoom levels
 * @returns {number} Total tile count
 */
function calculateTotalTiles(bounds, zoomLevels) {
  let total = 0;
  for (const zoom of zoomLevels) {
    const tiles = getTilesForBounds(bounds, zoom);
    total += tiles.length;
  }
  return total;
}

/**
 * Format bytes to human readable string
 * @param {number} bytes - Bytes
 * @returns {string} Formatted string
 */
function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

/**
 * Format duration to human readable string
 * @param {number} ms - Milliseconds
 * @returns {string} Formatted string
 */
function formatDuration(ms) {
  const seconds = Math.floor(ms / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  
  if (hours > 0) {
    return `${hours}h ${minutes % 60}m ${seconds % 60}s`;
  } else if (minutes > 0) {
    return `${minutes}m ${seconds % 60}s`;
  } else {
    return `${seconds}s`;
  }
}

/**
 * Get directory size
 * @param {string} dirPath - Directory path
 * @returns {number} Size in bytes
 */
function getDirectorySize(dirPath) {
  let size = 0;
  
  if (!fs.existsSync(dirPath)) {
    return 0;
  }
  
  const files = fs.readdirSync(dirPath);
  
  for (const file of files) {
    const filePath = path.join(dirPath, file);
    const stats = fs.statSync(filePath);
    
    if (stats.isDirectory()) {
      size += getDirectorySize(filePath);
    } else {
      size += stats.size;
    }
  }
  
  return size;
}

/**
 * Count downloaded tiles
 * @param {string} outputDir - Output directory
 * @param {number} zoom - Zoom level (optional, count all if not specified)
 * @returns {number} Number of tiles
 */
function countDownloadedTiles(outputDir, zoom = null) {
  let count = 0;
  
  if (!fs.existsSync(outputDir)) {
    return 0;
  }
  
  const zoomDirs = zoom !== null 
    ? [zoom.toString()] 
    : fs.readdirSync(outputDir).filter(f => !isNaN(f));
  
  for (const zoomDir of zoomDirs) {
    const zoomPath = path.join(outputDir, zoomDir);
    if (!fs.existsSync(zoomPath)) continue;
    
    const xDirs = fs.readdirSync(zoomPath);
    for (const xDir of xDirs) {
      const xPath = path.join(zoomPath, xDir);
      if (!fs.statSync(xPath).isDirectory()) continue;
      
      const tiles = fs.readdirSync(xPath).filter(f => f.endsWith('.png'));
      count += tiles.length;
    }
  }
  
  return count;
}

module.exports = {
  latLonToTile,
  getTilesForBounds,
  ensureDirectoryExists,
  loadJSON,
  saveJSON,
  tileExists,
  getTilePath,
  calculateTotalTiles,
  formatBytes,
  formatDuration,
  getDirectorySize,
  countDownloadedTiles
};

