/**
 * Core tile downloader with quota management
 */

const https = require('https');
const fs = require('fs');
const path = require('path');
const {
  getTilesForBounds,
  ensureDirectoryExists,
  tileExists,
  getTilePath,
  calculateTotalTiles
} = require('./utils');

class TileDownloader {
  constructor(config, stateManager) {
    this.config = config;
    this.stateManager = stateManager;
    this.stats = {
      downloaded: 0,
      skipped: 0,
      failed: 0,
      quotaExceeded: false,
      usedFallback: false
    };
  }

  /**
   * Download a single tile
   * @param {object} tile - Tile coordinates {x, y, z}
   * @param {object} options - Download options
   * @param {number} attempt - Current retry attempt
   * @returns {Promise} Promise that resolves when download is complete
   */
  downloadTile(tile, options = {}, attempt = 1) {
    return new Promise((resolve, reject) => {
      const { x, y, z } = tile;
      const { tileSize, retina, accessToken, style } = options;
      
      // Construct Mapbox tile URL
      const url = `https://api.mapbox.com/styles/v1/${style}/tiles/${tileSize}/${z}/${x}/${y}${retina}?access_token=${accessToken}`;
      
      // Create directory structure
      const tileDir = path.join(this.config.output.directory, z.toString(), x.toString());
      ensureDirectoryExists(tileDir);
      
      // File path
      const filePath = getTilePath(this.config.output.directory, tile);
      
      // Skip if file already exists
      if (fs.existsSync(filePath)) {
        this.stats.skipped++;
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
            this.stats.downloaded++;
            resolve({ tile, status: 'downloaded' });
          });
          
          fileStream.on('error', (err) => {
            fs.unlink(filePath, () => {});
            
            if (attempt < this.config.download.retryAttempts) {
              setTimeout(() => {
                this.downloadTile(tile, options, attempt + 1).then(resolve).catch(reject);
              }, this.config.download.retryDelay);
            } else {
              this.stats.failed++;
              reject(err);
            }
          });
        } else if (response.statusCode === 429) {
          // Rate limit exceeded
          setTimeout(() => {
            this.downloadTile(tile, options, attempt).then(resolve).catch(reject);
          }, 5000);
        } else {
          const err = new Error(`HTTP ${response.statusCode}`);
          
          if (attempt < this.config.download.retryAttempts) {
            setTimeout(() => {
              this.downloadTile(tile, options, attempt + 1).then(resolve).catch(reject);
            }, this.config.download.retryDelay);
          } else {
            this.stats.failed++;
            reject(err);
          }
        }
      }).on('error', (err) => {
        if (attempt < this.config.download.retryAttempts) {
          setTimeout(() => {
            this.downloadTile(tile, options, attempt + 1).then(resolve).catch(reject);
          }, this.config.download.retryDelay);
        } else {
          this.stats.failed++;
          reject(err);
        }
      });
    });
  }

  /**
   * Download tiles with concurrency control
   * @param {array} tiles - Array of tile coordinates
   * @param {object} options - Download options
   * @returns {Promise} Promise that resolves when all downloads are complete
   */
  async downloadTilesWithConcurrency(tiles, options) {
    const queue = [...tiles];
    const inProgress = new Set();
    
    return new Promise((resolve) => {
      const processNext = () => {
        if (queue.length === 0 && inProgress.size === 0) {
          resolve();
          return;
        }
        
        while (queue.length > 0 && inProgress.size < this.config.download.maxConcurrentDownloads) {
          const tile = queue.shift();
          const promise = this.downloadTile(tile, options)
            .catch(() => {}) // Errors already tracked in stats
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
   * Download tiles for a specific zoom level
   * @param {number} zoom - Zoom level
   * @param {object} downloadOptions - Download options
   * @returns {Promise} Promise that resolves with download results
   */
  async downloadZoomLevel(zoom, downloadOptions) {
    console.log(`\n${'='.repeat(70)}`);
    console.log(`Downloading zoom level ${zoom}...`);
    console.log('='.repeat(70));
    
    const tiles = getTilesForBounds(this.config.download.bounds, zoom);
    console.log(`Total tiles at zoom ${zoom}: ${tiles.length}`);
    
    // Initialize state for this zoom level
    this.stateManager.initZoomLevel(zoom, tiles.length);
    
    // Reset stats for this zoom level
    const startStats = { ...this.stats };
    
    // Download tiles
    await this.downloadTilesWithConcurrency(tiles, downloadOptions);
    
    // Calculate progress for this zoom level
    const zoomStats = {
      downloaded: this.stats.downloaded - startStats.downloaded,
      skipped: this.stats.skipped - startStats.skipped,
      failed: this.stats.failed - startStats.failed
    };
    
    // Update state
    this.stateManager.updateZoomLevel(zoom, {
      downloaded: zoomStats.downloaded + zoomStats.skipped,
      failed: zoomStats.failed,
      skipped: zoomStats.skipped,
      lastAttempt: new Date().toISOString()
    });
    
    // Mark as completed if all tiles are downloaded
    if (zoomStats.downloaded + zoomStats.skipped === tiles.length) {
      this.stateManager.completeZoomLevel(zoom);
    }
    
    console.log(`\nZoom ${zoom} complete:`);
    console.log(`  Downloaded: ${zoomStats.downloaded}`);
    console.log(`  Skipped:    ${zoomStats.skipped}`);
    console.log(`  Failed:     ${zoomStats.failed}`);
    
    return zoomStats;
  }

  /**
   * Download tiles with quota management
   * @returns {Promise} Promise that resolves with download results
   */
  async download() {
    console.log('╔════════════════════════════════════════════════════════════════╗');
    console.log('║         Mapbox Tile Downloader - Quota Managed                ║');
    console.log('╚════════════════════════════════════════════════════════════════╝');
    console.log('');
    
    const startTime = Date.now();
    
    // Get incomplete zoom levels
    const incompleteZoomLevels = this.stateManager.getIncompleteZoomLevels(
      this.config.download.zoomLevels
    );
    
    if (incompleteZoomLevels.length === 0) {
      console.log('✓ All zoom levels already downloaded!');
      return this.stats;
    }
    
    console.log(`Incomplete zoom levels: ${incompleteZoomLevels.join(', ')}`);
    console.log('');
    
    // Prepare download options
    let downloadOptions = {
      accessToken: this.config.mapbox.accessToken,
      style: this.config.mapbox.style,
      tileSize: this.config.mapbox.tileSize,
      retina: this.config.mapbox.retina
    };
    
    // Download each incomplete zoom level
    for (const zoom of incompleteZoomLevels) {
      const tiles = getTilesForBounds(this.config.download.bounds, zoom);
      
      // Check if this zoom level exceeds quota
      if (tiles.length > this.config.quota.maxTilesPerDownload) {
        console.log(`⚠ Zoom level ${zoom} has ${tiles.length} tiles (exceeds quota of ${this.config.quota.maxTilesPerDownload})`);
        console.log(`  Switching to fallback: ${this.config.quota.fallbackTileSize}px tiles`);
        
        downloadOptions = {
          ...downloadOptions,
          tileSize: this.config.quota.fallbackTileSize,
          retina: this.config.quota.fallbackRetina
        };
        
        this.stats.quotaExceeded = true;
        this.stats.usedFallback = true;
      }
      
      await this.downloadZoomLevel(zoom, downloadOptions);
    }
    
    const endTime = Date.now();
    const duration = endTime - startTime;
    
    console.log('\n' + '='.repeat(70));
    console.log('Download Session Complete!');
    console.log('='.repeat(70));
    console.log(`Total Downloaded: ${this.stats.downloaded}`);
    console.log(`Total Skipped:    ${this.stats.skipped}`);
    console.log(`Total Failed:     ${this.stats.failed}`);
    console.log(`Duration:         ${(duration / 1000).toFixed(2)}s`);
    console.log(`Quota Exceeded:   ${this.stats.quotaExceeded ? 'Yes' : 'No'}`);
    console.log(`Used Fallback:    ${this.stats.usedFallback ? 'Yes' : 'No'}`);
    console.log('');
    
    // Record session in state
    this.stateManager.recordSession({
      downloaded: this.stats.downloaded,
      skipped: this.stats.skipped,
      failed: this.stats.failed,
      duration,
      quotaExceeded: this.stats.quotaExceeded,
      usedFallback: this.stats.usedFallback
    });
    
    return this.stats;
  }
}

module.exports = TileDownloader;

